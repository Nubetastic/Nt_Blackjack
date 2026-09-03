local gamesByTableId = {}
local playerTableBySource = {}
local spectatorTableBySource = {}

ServerRunning = true
ServerGames = gamesByTableId

local startBetting
local beginDeal
local startDealerTurn
local settleRound
local sendViews
local cueDealer
local cueNpc
local processNpcTurn
local maybeRequestNpcJoin
local syncNpcPlayers
local maybeNpcLeavesBetweenHands
local continueAfterAction

local npcSerial = 0
local pendingNpcRequests = {}

local function validateCardConfiguration()
    if type(Config.FullDeck) ~= 'table' or #Config.FullDeck ~= 52 then
        error('[Nt_BlackJack] Config.FullDeck must contain exactly 52 cached card definitions.')
    end

    local seen = {}
    for index, card in ipairs(Config.FullDeck) do
        if not card.suit or not card.royalty then
            error(('[Nt_BlackJack] Invalid cached card at index %d.'):format(index))
        end
        local key = tostring(card.royalty) .. tostring(card.suit)
        if seen[key] then
            error(('[Nt_BlackJack] Duplicate cached card: %s'):format(key))
        end
        seen[key] = true
    end
end

validateCardConfiguration()

local function notify(source, message, kind, duration)
    TriggerClientEvent("nt_blackjack:client:notify", source, {
        description = tostring(message),
        type = kind or "inform",
        duration = duration or 5000,
    })
end

local function playerIsNpc(player)
    return player and player.isNpc == true
end

local function sourceIsConnected(source)
    return type(source) == "number" and GetPlayerName(source) ~= nil
end

local function countPlayers(game)
    local count = 0
    for _, player in pairs(game.players) do
        if not player.hasLeft then count = count + 1 end
    end
    return count
end

local function countRealPlayers(game)
    local count = 0
    for source, player in pairs(game.players) do
        if not player.hasLeft and not playerIsNpc(player) and sourceIsConnected(source) then
            count = count + 1
        end
    end
    return count
end

local function countNpcPlayers(game)
    local count = 0
    for _, player in pairs(game.players) do
        if not player.hasLeft and playerIsNpc(player) then count = count + 1 end
    end
    return count
end

local function forEachRealPlayer(game, callback)
    for source, player in pairs(game.players) do
        if not player.hasLeft and not playerIsNpc(player) and sourceIsConnected(source) then
            callback(source, player)
        end
    end
end

local function forEachViewer(game, callback)
    local sent = {}
    forEachRealPlayer(game, function(source, player)
        sent[source] = true
        callback(source, player)
    end)
    for source in pairs(game.spectators) do
        if spectatorTableBySource[source] == game.id and sourceIsConnected(source) then
            if not sent[source] then callback(source) end
        else
            game.spectators[source] = nil
        end
    end
end

local function npcConfig()
    return Config.NPCPlayers or {}
end

local function randomChance(percent)
    percent = tonumber(percent) or 0
    if percent <= 0 then return false end
    if percent >= 100 then return true end
    return math.random(1, 100) <= percent
end

local function npcBetAmount()
    local npc = npcConfig()
    local minBet = math.max(Config.Rules.MinBet, tonumber(npc.MinBet) or Config.Rules.MinBet)
    local maxBet = math.min(Config.Rules.MaxBet, tonumber(npc.MaxBet) or Config.Rules.MaxBet)
    local step = math.max(1, tonumber(Config.Rules.BetStep) or 1)
    if maxBet < minBet then maxBet = minBet end
    local steps = math.max(0, math.floor((maxBet - minBet) / step))
    return minBet + (math.random(0, steps) * step)
end

local function assignNpcBet(player)
    local amount = npcBetAmount()
    player.bet = amount
    player.betVisible = true
    player.totalWager = amount
    player.betLocked = true
    player.waiting = false
end

local function clearNpcPlayers(game)
    for source, player in pairs(game.players) do
        if playerIsNpc(player) then
            game.seats[player.seatIndex] = nil
            game.players[source] = nil
        end
    end
end

local function randomNpcName(game, appearance)
    local names = appearance.isMale and npcConfig().MaleNames or npcConfig().FemaleNames
    local availableNames = {}

    for _, name in ipairs(names) do
        local used = false
        for _, player in pairs(game.players) do
            if playerIsNpc(player) and not player.hasLeft and player.name == name then
                used = true
                break
            end
        end
        if not used then availableNames[#availableNames + 1] = name end
    end

    for _, name in ipairs(availableNames) do
        if name == appearance.name then return name end
    end
    if #availableNames > 0 then return availableNames[math.random(1, #availableNames)] end
    return "NPC Player"
end


local function orderedPlayers(game, requireBet)
    local players = {}
    for _, player in pairs(game.players) do
        if not player.hasLeft and (not requireBet or (player.bet or 0) > 0) then
            players[#players + 1] = player
        end
    end
    table.sort(players, function(a, b) return a.seatIndex < b.seatIndex end)
    return players
end

local function publicTables()
    local result = {}
    for tableId, game in pairs(gamesByTableId) do
        local occupiedSeats = {}
        for _, player in pairs(game.players) do
            if not player.hasLeft then
                occupiedSeats[#occupiedSeats + 1] = player.seatIndex
            end
        end
        result[tableId] = {
            id = tableId,
            label = game.label,
            state = game.state,
            playerCount = countPlayers(game),
            realPlayerCount = countRealPlayers(game),
            npcPlayerCount = countNpcPlayers(game),
            maxPlayers = game.maxPlayers,
            canJoin = #occupiedSeats < game.maxPlayers or countNpcPlayers(game) > 0,
            occupiedSeats = occupiedSeats,
        }
    end
    return result
end

local function broadcastTables(target)
    TriggerClientEvent("nt_blackjack:client:updateTables", target or -1, publicTables())
end

local function newGame(tableId, tableConfig)
    return {
        id = tableId,
        label = tableConfig.Label or tableId,
        maxPlayers = tableConfig.MaxPlayers or 4,
        state = "WAITING",
        players = {},
        spectators = {},
        seats = {},
        dealerHand = { cards = {}, value = 0, isSoft = false, revealed = false },
        shuffleDeck = {},
        nextCardIndex = 1,
        cardsRemaining = 0,
        handsSinceShuffle = Config.Rules.ReshuffleAfterHands,
        roundId = 0,
        roundSettled = true,
        currentTurnPosition = nil,
        currentSource = nil,
        acceptingAction = false,
        deadline = nil,
        cardStyle = nil,
        cardStyleChooser = nil,
        commands = {},
        flow = nil,
        flowData = nil,
        waitSteps = 0,
        bettingSteps = nil,
        actionSteps = nil,
    }
end

local function destroyTableSession(game)
    if not game then return end

    -- Invalidate delayed callbacks which still hold this session. Replacing the
    -- object below prevents them from mutating a newly joined game.
    game.state = "STOPPED"
    game.deadline = nil

    for source, player in pairs(game.players) do
        if not playerIsNpc(player) then
            playerTableBySource[source] = nil
        end
    end

    for requestId, pending in pairs(pendingNpcRequests) do
        if pending.tableId == game.id then
            pendingNpcRequests[requestId] = nil
        end
    end

    local spectators = game.spectators
    local tableConfig = Config.Tables[game.id]
    if tableConfig then
        local replacement = newGame(game.id, tableConfig)
        replacement.spectators = spectators
        gamesByTableId[game.id] = replacement
        if next(replacement.spectators) then sendViews(replacement) end
    else
        for source in pairs(spectators) do
            spectatorTableBySource[source] = nil
            TriggerClientEvent("nt_blackjack:client:spectatorChanged", source, nil)
        end
        gamesByTableId[game.id] = nil
    end
end

for tableId, tableConfig in pairs(Config.Tables) do
    gamesByTableId[tableId] = newGame(tableId, tableConfig)
end

local function createShoe(game)
    game.shuffleDeck = BlackjackCards.buildShuffledDeck(Config.FullDeck, Config.Rules.DeckCount)
    local expectedCards = 52 * math.max(1, tonumber(Config.Rules.DeckCount) or 1)
    if #game.shuffleDeck ~= expectedCards then
        error(('[Nt_BlackJack] Shoe build failed for %s: expected %d cards, received %d.'):format(
            game.id,
            expectedCards,
            #game.shuffleDeck
        ))
    end
    game.nextCardIndex = 1
    game.cardsRemaining = #game.shuffleDeck
    game.handsSinceShuffle = 0
    if Config.Debug then
        print(("[Nt_BlackJack] Shuffled %d cards for %s"):format(game.cardsRemaining, game.id))
    end
end

local function shouldShuffle(game)
    return not game.shuffleDeck
        or game.cardsRemaining < (Config.Rules.MinimumCardsBeforeHand or 20)
        or game.handsSinceShuffle >= (Config.Rules.ReshuffleAfterHands or 5)
end

local function updateHand(hand)
    hand.value, hand.isSoft = BlackjackCards.score(hand.cards)
    if hand.value > 21 then
        hand.status = "BUST"
    elseif hand.value == 21 and hand.status == "ACTIVE" then
        hand.status = "STOOD"
    end
end

local function drawInto(game, cards)
    local card = BlackjackCards.draw(game)
    if not card then return nil end
    cards[#cards + 1] = card
    return card
end

local function serializeCards(cards, reveal)
    local output = {}
    for index, card in ipairs(cards or {}) do
        output[index] = BlackjackCards.publicCard(card, reveal == true)
    end
    return output
end

local function serializeHand(hand, includeCards)
    return {
        cards = includeCards and serializeCards(hand.cards, true) or nil,
        cardCount = #(hand.cards or {}),
        bet = hand.bet,
        value = hand.value,
        isSoft = hand.isSoft,
        status = hand.status,
        isSplitHand = hand.isSplitHand,
        doubled = hand.doubled,
        result = hand.result,
        payout = hand.payout,
    }
end

local function allowedActions(game, player)
    local allowed = {
        placeBet = false,
        hit = false,
        stand = false,
        double = false,
        split = false,
    }

    if playerIsNpc(player) then return allowed end

    if game.state == "BETTING" and not player.waiting and not player.betLocked then
        allowed.placeBet = true
        return allowed
    end

    if game.state ~= "PLAYER_TURNS" or game.currentSource ~= player.source or not game.acceptingAction then
        return allowed
    end

    local hand = player.hands[player.activeHandIndex or 1]
    if not hand or hand.status ~= "ACTIVE" then return allowed end

    allowed.hit = true
    allowed.stand = true
    allowed.double = Config.Rules.AllowDouble
        and #hand.cards == 2
        and Framework.hasMoney(player.source, hand.bet)
    allowed.split = Config.Rules.AllowSplit
        and #player.hands < (Config.Rules.MaxSplitHands or 2)
        and BlackjackCards.canSplit(hand)
        and Framework.hasMoney(player.source, hand.bet)
    return allowed
end

local function buildGameView(game, source)
    local player = source and game.players[source] or nil
    if source and not player then return nil end

    local dealerCards = {}
    for index, card in ipairs(game.dealerHand.cards or {}) do
        local reveal = index == 1 or game.dealerHand.revealed
        dealerCards[index] = BlackjackCards.publicCard(card, reveal)
        dealerCards[index].propRoyalty = card.royalty
        dealerCards[index].propSuit = card.suit
    end

    local playerRows = {}
    for _, other in ipairs(orderedPlayers(game, false)) do
        local hands = {}
        for handIndex, hand in ipairs(other.hands or {}) do
            hands[handIndex] = serializeHand(hand, true)
        end
        playerRows[#playerRows + 1] = {
            source = other.source,
            name = other.name,
            seatIndex = other.seatIndex,
            bet = other.bet or 0,
            betVisible = other.betVisible == true,
            showPayoutChip = other.showPayoutChip or false,
            waiting = other.waiting or false,
            hands = hands,
            activeHandIndex = other.activeHandIndex or 1,
            isCurrent = game.currentSource == other.source,
            isNpc = playerIsNpc(other),
            npcId = other.npcId,
            npcAppearance = other.npcAppearance,
        }
    end

    local current = game.currentSource and game.players[game.currentSource] or nil
    return {
        tableId = game.id,
        tableLabel = game.label,
        state = game.state,
        roundId = game.roundId,
        deadline = game.deadline,
        cardsRemaining = game.cardsRemaining,
        handsSinceShuffle = game.handsSinceShuffle,
        cardStyle = game.cardStyle,
        currentSeat = current and current.seatIndex or nil,
        currentName = current and current.name or nil,
        isMyTurn = player and game.currentSource == source or false,
        dealer = {
            cards = dealerCards,
            value = game.dealerHand.revealed and game.dealerHand.value or BlackjackCards.valueOf(game.dealerHand.cards[1]),
            isSoft = game.dealerHand.revealed and game.dealerHand.isSoft or false,
            revealed = game.dealerHand.revealed,
        },
        players = playerRows,
        self = player and {
            source = player.source,
            name = player.name,
            seatIndex = player.seatIndex,
            bet = player.bet or 0,
            waiting = player.waiting or false,
            betLocked = player.betLocked or false,
            hands = (function()
                local hands = {}
                for index, hand in ipairs(player.hands or {}) do
                    hands[index] = serializeHand(hand, true)
                end
                return hands
            end)(),
            activeHandIndex = player.activeHandIndex or 1,
            cash = Framework.getCash(source),
        } or nil,
        rules = player and {
            minBet = Config.Rules.MinBet,
            maxBet = Config.Rules.MaxBet,
            betStep = Config.Rules.BetStep,
            blackjackPayout = Config.Rules.BlackjackPayout,
            dealerHitsSoft17 = Config.Rules.DealerHitsSoft17,
        } or nil,
        allowedActions = player and allowedActions(game, player) or nil,
    }
end

sendViews = function(game)
    forEachRealPlayer(game, function(source)
        local view = buildGameView(game, source)
        if view then
            TriggerClientEvent("nt_blackjack:client:updateGame", source, view)
        end
    end)
    local spectatorView = buildGameView(game)
    for source in pairs(game.spectators) do
        if spectatorTableBySource[source] == game.id and sourceIsConnected(source) then
            TriggerClientEvent("nt_blackjack:client:updateSpectatorGame", source, spectatorView)
        else
            game.spectators[source] = nil
        end
    end
    broadcastTables()
end

local dealerAnimationKeys = {
    deal = "DealerDeal", initialDeal = "DealerInitialDeal", reveal = "DealerReveal",
    dealerHit = "DealerDeal", collect = "DealerCollect", payout = "DealerPayout",
    retrieve = "DealerRetrieveCards", shuffle = "DealerShuffle",
}

local function clientAnimation(game, eventName, animationKey, ...)
    local eventArguments = { ... }
    forEachViewer(game, function(source)
        TriggerClientEvent(eventName, source, game.id, table.unpack(eventArguments))
    end)
    local animation = Config.Animations and Config.Animations[animationKey]
    local animationMs = animation and tonumber(animation.time) or 0
    return math.max(0, math.floor(animationMs + (tonumber(Config.AnimationTime) or 0)))
end

cueDealer = function(game, action, data)
    local duration = clientAnimation(game, "nt_blackjack:client:dealerAnimation",
        dealerAnimationKeys[action] or "DealerIdle", action, data)
    if action == "initialDeal" and data and data.duration then
        return math.max(0, math.floor(data.duration + (tonumber(Config.AnimationTime) or 0)))
    end
    return duration
end

cueNpc = function(game, player, action, data)
    local animationKey = "PlayerBet"
    if action == "stand" then
        animationKey = "PlayerStand"
    elseif action == "hit" then
        animationKey = "PlayerHit"
    end
    return clientAnimation(game, "nt_blackjack:client:npcAnimation", animationKey, player.npcId, action, data)
end

local function orderedSeatList(seatSet)
    local seats = {}
    for seatIndex = 1, 4 do
        if seatSet[seatIndex] then seats[#seats + 1] = seatIndex end
    end
    return seats
end

local function playerSeatList(players)
    local seats = {}
    for _, player in ipairs(players or {}) do
        local seatIndex = tonumber(player.seatIndex)
        if seatIndex and seatIndex >= 1 and seatIndex <= 4 then
            seats[#seats + 1] = seatIndex
        end
    end
    table.sort(seats)
    return seats
end

local function roundCurrency(amount)
    return math.floor((tonumber(amount) or 0) + 0.5)
end

local function steps(milliseconds)
    milliseconds = tonumber(milliseconds) or 0
    if milliseconds <= 0 then return 0 end
    return math.max(1, math.ceil(milliseconds / 100))
end

local function dividedStepDelay(totalSteps, itemIndex, itemCount)
    local previousStep = math.floor(totalSteps * (itemIndex - 1) / itemCount + 0.5)
    local currentStep = math.floor(totalSteps * itemIndex / itemCount + 0.5)
    return math.max(1, currentStep - previousStep)
end

local function clearDeparted(game)
    for source, player in pairs(game.players) do
        if player.hasLeft or (not playerIsNpc(player) and not sourceIsConnected(source)) then
            game.seats[player.seatIndex] = nil
            game.players[source] = nil
            if not playerIsNpc(player) then playerTableBySource[source] = nil end
        end
    end
end

local function scheduleNextRound(game)
    game.deadline = os.time() + math.ceil(Config.BetweenHandsWaitMs / 1000)
    game.flow = "BETWEEN_ROUNDS"
    game.flowData = nil
    game.waitSteps = steps(Config.BetweenHandsWaitMs)
    sendViews(game)
end

local function refundRound(game, reason)
    if game.roundSettled then return end
    game.roundSettled = true

    for source, player in pairs(game.players) do
        if not player.hasLeft and (player.totalWager or 0) > 0 then
            Framework.addMoney(source, player.totalWager, "blackjack-refund")
            notify(source, ("Blackjack hand refunded: %s"):format(reason), "error", 7000)
            for _, hand in ipairs(player.hands or {}) do
                hand.status = "COMPLETE"
                hand.result = "REFUND"
                hand.payout = hand.bet
            end
        end
    end

    game.state = "SETTLEMENT"
    game.currentSource = nil
    game.dealerHand.revealed = true
    scheduleNextRound(game)
end

processNpcTurn = function(game)
    local player = game.players[game.currentSource]
    local hand = player and player.hands[player.activeHandIndex or 1]
    if not player or not playerIsNpc(player) or not hand or hand.status ~= "ACTIVE" then
        continueAfterAction(game)
        return
    end

    local standValue = tonumber(npcConfig().StandValue) or 17
    if (hand.value or 0) < standValue then
        cueNpc(game, player, "hit", {})
        game.flow = "NPC_HIT_WAIT"
        game.flowData = { player = player }
        game.waitSteps = steps(Config.Animations.PlayerHit.time + Config.Animations.PlayerHit.DealDelay)
        return
    end

    hand.status = "STOOD"
    game.flow = "NPC_STAND_FINISH"
    game.flowData = { player = player }
    game.waitSteps = steps(cueNpc(game, player, "stand", {}))
end

local function activatePlayerTurn(game, position, handIndex)
    local source = game.turnOrder[position]
    local player = source and game.players[source]
    local hand = player and player.hands[handIndex]
    if not player or player.hasLeft or not hand or hand.status ~= "ACTIVE" then return false end
    game.state = "PLAYER_TURNS"
    game.currentTurnPosition = position
    game.currentSource = source
    player.activeHandIndex = handIndex
    game.acceptingAction = not playerIsNpc(player)
    if playerIsNpc(player) then
        game.deadline = nil
        game.actionSteps = steps(tonumber(npcConfig().ActionDelayMs) or 1200)
    else
        game.deadline = os.time() + Config.ActionTimeoutSeconds
        game.actionSteps = steps(Config.ActionTimeoutSeconds * 1000)
    end
    sendViews(game)
    return true
end

local function beginPlayerTurn(game, position, handIndex)
    local source = game.turnOrder[position]
    local player = source and game.players[source] or nil
    local hand = player and player.hands[handIndex] or nil
    if not player or player.hasLeft or not hand or hand.status ~= "ACTIVE" then return false end

    local transitionWaitMs = math.max(0, math.floor(tonumber(Config.NextPlayerDelay) or 0))
    if game.currentSource and game.currentSource ~= source and transitionWaitMs > 0 then
        game.acceptingAction = false
        game.actionSteps = nil
        game.deadline = nil
        game.flow = "NEXT_PLAYER_WAIT"
        game.flowData = { position = position, handIndex = handIndex }
        game.waitSteps = steps(transitionWaitMs)
        return true
    end
    return activatePlayerTurn(game, position, handIndex)
end

local function advanceTurn(game, startPosition, startHand)
    for position = startPosition or 1, #game.turnOrder do
        local source = game.turnOrder[position]
        local player = game.players[source]
        local firstHand = position == (startPosition or 1) and (startHand or 1) or 1
        if player and not player.hasLeft then
            for handIndex = firstHand, #player.hands do
                if player.hands[handIndex].status == "ACTIVE" then
                    beginPlayerTurn(game, position, handIndex)
                    return
                end
            end
        end
    end
    startDealerTurn(game)
end

continueAfterAction = function(game)
    local player = game.players[game.currentSource]
    if not player then
        advanceTurn(game, (game.currentTurnPosition or 1) + 1, 1)
        return
    end

    local hand = player.hands[player.activeHandIndex]
    if hand and hand.status == "ACTIVE" then
        beginPlayerTurn(game, game.currentTurnPosition, player.activeHandIndex)
        return
    end

    advanceTurn(game, game.currentTurnPosition, player.activeHandIndex + 1)
end

local function startPlayerDealFlow(game, player)
    game.acceptingAction = false
    game.actionSteps = nil
    game.deadline = nil
    local duration = cueDealer(game, "deal", { seats = { player.seatIndex } })
    local viewDelay = math.floor(Config.Animations.DealerDeal.time * Config.Animations.DealerDeal.DealCardAt)
    game.flow = "PLAYER_DEAL_VIEW"
    game.flowData = { remaining = duration - viewDelay }
    game.waitSteps = steps(viewDelay)
end

settleRound = function(game)
    if game.roundSettled then return end
    game.roundSettled = true
    game.state = "SETTLEMENT"
    game.currentSource = nil
    game.currentTurnPosition = nil
    game.acceptingAction = false
    game.deadline = nil
    game.dealerHand.revealed = true
    game.dealerHand.value, game.dealerHand.isSoft = BlackjackCards.score(game.dealerHand.cards)

    local dealerValue = game.dealerHand.value
    local dealerBlackjack = #game.dealerHand.cards == 2 and dealerValue == 21
    local dealerBust = dealerValue > 21
    local winningSeats = {}
    local losingSeats = {}
    local participatingSeats = {}

    for source, player in pairs(game.players) do
        local seatIndex = tonumber(player.seatIndex)
        if not player.hasLeft and (player.totalWager or 0) > 0 and seatIndex and seatIndex >= 1 and seatIndex <= 4 then
            participatingSeats[seatIndex] = true
        end
        for _, hand in ipairs(player.hands or {}) do
            local payout = 0
            local result = "LOSS"

            if player.hasLeft or hand.status == "FORFEIT" then
                result = "FORFEIT"
            elseif hand.status == "BUST" or hand.value > 21 then
                result = "BUST"
            elseif BlackjackCards.isNatural(hand) and not dealerBlackjack then
                result = "BLACKJACK"
                payout = hand.bet + (hand.bet * Config.Rules.BlackjackPayout)
            elseif dealerBlackjack and BlackjackCards.isNatural(hand) then
                result = "PUSH"
                payout = hand.bet
            elseif dealerBlackjack then
                result = "LOSS"
            elseif dealerBust or hand.value > dealerValue then
                result = "WIN"
                payout = hand.bet * 2
            elseif hand.value == dealerValue then
                result = "PUSH"
                payout = hand.bet
            end

            payout = roundCurrency(payout)
            hand.result = result
            hand.payout = payout
            hand.status = "COMPLETE"

            if result == "WIN" or result == "BLACKJACK" then
                if seatIndex and seatIndex >= 1 and seatIndex <= 4 then
                    winningSeats[seatIndex] = true
                end
            elseif result == "LOSS" or result == "BUST" then
                if seatIndex and seatIndex >= 1 and seatIndex <= 4 then
                    losingSeats[seatIndex] = true
                end
            end

            if payout > 0 and not player.hasLeft and not playerIsNpc(player) and sourceIsConnected(source) then
                Framework.addMoney(source, payout, result == "PUSH" and "blackjack-push" or "blackjack-win")
            end
        end
    end

    for _, player in pairs(game.players) do
        if playerIsNpc(player) and not player.hasLeft and (player.totalWager or 0) > 0 then
            player.handsPlayed = (player.handsPlayed or 0) + 1
            if player.pendingLeave or player.handsPlayed >= (player.handsToStay or 1) then
                player.hasLeft = true
            end
        end
    end

    game.handsSinceShuffle = game.handsSinceShuffle + 1
    local settlementCues = {}
    local lossSeats = orderedSeatList(losingSeats)
    local payoutSeats = orderedSeatList(winningSeats)
    local cardSeats = orderedSeatList(participatingSeats)
    if #lossSeats > 0 then settlementCues[#settlementCues + 1] = { action = "collect", seats = lossSeats } end
    if #payoutSeats > 0 then settlementCues[#settlementCues + 1] = { action = "payout", seats = payoutSeats } end
    if #cardSeats > 0 then settlementCues[#settlementCues + 1] = { action = "retrieve", seats = cardSeats } end

    game.settlementCues = settlementCues
    game.settlementCueIndex = 1
    game.flowData = { losingSeats = losingSeats, winningSeats = winningSeats }
    game.flow = "SETTLEMENT_NEXT_CUE"
    game.waitSteps = 0
end

local function startDealerReveal(game, finishFlow)
    local duration = cueDealer(game, "reveal")
    local revealDelay = math.floor(Config.Animations.DealerReveal.time
        * Config.Animations.DealerReveal.RevealCardAt)
    game.flow = "DEALER_REVEAL_VIEW"
    game.flowData = { remaining = duration - revealDelay, finishFlow = finishFlow }
    game.waitSteps = steps(revealDelay)
end

startDealerTurn = function(game)
    if game.state == "DEALER_TURN" or game.state == "SETTLEMENT" then return end
    local transitionWaitMs = math.max(0, math.floor(tonumber(Config.AnimationTime) or 0))
    if game.state == "PLAYER_TURNS" and transitionWaitMs > 0 then
        game.acceptingAction = false
        game.actionSteps = nil
        game.deadline = nil
        game.flow = "DEALER_TRANSITION"
        game.flowData = nil
        game.waitSteps = steps(transitionWaitMs)
        return
    end
    game.state = "DEALER_TURN"
    game.currentSource = nil
    game.currentTurnPosition = nil
    game.acceptingAction = false
    game.deadline = nil
    startDealerReveal(game, "DEALER_REVEAL_FINISH")
end

beginDeal = function(game)
    if game.state ~= "BETTING" then return end
    game.bettingSteps = nil
    local activePlayers = orderedPlayers(game, true)
    local realBettors = 0
    for _, player in ipairs(activePlayers) do
        if not playerIsNpc(player) then realBettors = realBettors + 1 end
    end
    if #activePlayers == 0 or realBettors == 0 then
        game.state = "WAITING"
        game.deadline = nil
        game.flow = "WAITING_RETRY"
        game.waitSteps = steps(3000)
        sendViews(game)
        return
    end

    game.state = "DEALING"
    game.deadline = nil
    game.dealerHand = { cards = {}, value = 0, isSoft = false, revealed = false }
    game.turnOrder = {}
    for _, player in ipairs(activePlayers) do
        player.hands = {
            {
                cards = {},
                bet = player.bet,
                value = 0,
                isSoft = false,
                status = "ACTIVE",
                isSplitHand = false,
                doubled = false,
            },
        }
        player.activeHandIndex = 1
        game.turnOrder[#game.turnOrder + 1] = player.source
    end

    local dealQueue = {}
    local function queueCard(source, dealer)
        local cards = {}
        if not drawInto(game, cards) then return false end
        dealQueue[#dealQueue + 1] = { source = source, dealer = dealer == true, card = cards[1] }
        return true
    end

    for _, player in ipairs(activePlayers) do
        if not queueCard(player.source, false) then refundRound(game, "the shoe ran out of cards") return end
    end
    if not queueCard(nil, true) then refundRound(game, "the shoe ran out of cards") return end
    for _, player in ipairs(activePlayers) do
        if not queueCard(player.source, false) then refundRound(game, "the shoe ran out of cards") return end
    end
    if not queueCard(nil, true) then refundRound(game, "the shoe ran out of cards") return end

    local animationDuration = math.floor(Config.Animations.DealerInitialDeal.time * (#activePlayers + 1))
    local totalDuration = cueDealer(game, "initialDeal", {
        seats = playerSeatList(activePlayers),
        duration = animationDuration,
    })
    local cardAnimationSteps = steps(animationDuration)
    game.flow = "INITIAL_DEAL_CARD"
    game.flowData = {
        cards = dealQueue,
        cardIndex = 1,
        totalDuration = totalDuration,
        animationDuration = animationDuration,
        cardAnimationSteps = cardAnimationSteps,
    }
    game.waitSteps = dividedStepDelay(cardAnimationSteps, 1, #dealQueue)
end

local function allBetsResolved(game)
    local eligible = 0
    for _, player in pairs(game.players) do
        if not player.hasLeft and not player.waiting then
            eligible = eligible + 1
            if not player.betLocked then return false end
            if (tonumber(player.bet) or 0) > 0 and not player.betVisible then return false end
        end
    end
    return eligible > 0
end

local function initializeBetting(game)
    game.roundId = game.roundId + 1
    game.roundSettled = false
    game.state = "BETTING"
    game.deadline = os.time() + Config.BettingTimeoutSeconds
    game.currentSource = nil
    game.currentTurnPosition = nil
    game.acceptingAction = false
    game.actionSteps = nil
    game.turnOrder = {}
    game.dealerHand = { cards = {}, value = 0, isSoft = false, revealed = false }

    for _, player in pairs(game.players) do
        player.bet = 0
        player.betVisible = false
        player.betPropSteps = nil
        player.showPayoutChip = false
        player.totalWager = 0
        player.betLocked = false
        player.waiting = false
        player.hands = {}
        player.activeHandIndex = 1
        if playerIsNpc(player) then assignNpcBet(player) end
    end

    game.bettingSteps = steps(Config.BettingTimeoutSeconds * 1000)
    game.flow = nil
    game.flowData = nil
    game.waitSteps = 0
    sendViews(game)
end

startBetting = function(game)
    clearDeparted(game)
    if countRealPlayers(game) == 0 then
        clearNpcPlayers(game)
        game.state = "WAITING"
        game.deadline = nil
        game.bettingSteps = nil
        game.flow = nil
        broadcastTables()
        return
    end

    maybeRequestNpcJoin(game, game.roundId == 0 and "start" or "betweenHands")
    if shouldShuffle(game) then
        createShoe(game)
        game.flow = "SHUFFLE_FINISH"
        game.flowData = nil
        game.waitSteps = steps(cueDealer(game, "shuffle"))
        return
    end
    initializeBetting(game)
end

local function findFreeSeat(game)
    local openSeats = {}
    for seat = 1, game.maxPlayers do
        if not game.seats[seat] then openSeats[#openSeats + 1] = seat end
    end
    if #openSeats == 0 then return nil end
    return openSeats[math.random(1, #openSeats)]
end

local function randomNpcPlayer(game)
    local npcs = {}
    for _, player in pairs(game.players) do
        if playerIsNpc(player) and not player.hasLeft then npcs[#npcs + 1] = player end
    end
    if #npcs == 0 then return nil end
    return npcs[math.random(1, #npcs)]
end

local function removeNpcPlayer(game, player)
    if not player or not playerIsNpc(player) then return end
    player.hasLeft = true
    game.seats[player.seatIndex] = nil
    game.players[player.source] = nil
end

local function tableRealSources(game)
    local sources = {}
    forEachRealPlayer(game, function(realSource)
        sources[#sources + 1] = realSource
    end)
    return sources
end

local function npcCapacity(game)
    local npc = npcConfig()
    local minSeatsOpen = math.max(1, tonumber(npc.MinSeatsOpen) or 1)
    local hardCap = math.max(0, tonumber(npc.MaxPlayersPerTable) or 0)
    local bySeats = math.max(0, game.maxPlayers - countRealPlayers(game) - minSeatsOpen)
    return math.min(hardCap, bySeats)
end

maybeRequestNpcJoin = function(game, reason)
    local npc = npcConfig()
    if not npc.Enabled or countRealPlayers(game) == 0 then return end
    if countNpcPlayers(game) >= npcCapacity(game) then return end

    local chance = reason == "start" and npc.JoinAtStartChance or npc.JoinBetweenHandsChance
    if not randomChance(chance) then return end

    local realSources = tableRealSources(game)
    if #realSources == 0 then return end
    local requestSource = realSources[math.random(1, #realSources)]
    npcSerial = npcSerial + 1
    local requestId = ("%s:%d:%d"):format(game.id, game.roundId or 0, npcSerial)
    pendingNpcRequests[requestId] = {
        tableId = game.id,
        game = game,
        requestedFrom = requestSource,
    }
    local tableConfig = Config.Tables[game.id]
    TriggerClientEvent("nt_blackjack:client:requestNpcAppearance", requestSource, requestId, game.id, tableConfig and tableConfig.NPCScanArea or nil)
end

syncNpcPlayers = function(game)
    sendViews(game)
end

maybeNpcLeavesBetweenHands = function(game)
    local npc = npcConfig()
    for _, player in pairs(game.players) do
        if playerIsNpc(player) and not player.hasLeft and player.handsPlayed >= (player.handsToStay or 1) and randomChance(npc.LeaveBetweenHandsChance) then
            player.hasLeft = true
        end
    end
end

local function markRandomNpcToLeave(game)
    local npc = randomNpcPlayer(game)
    if not npc then return false end
    if game.state == "WAITING" or game.state == "BETTING" or game.state == "SETTLEMENT" then
        removeNpcPlayer(game, npc)
    else
        npc.pendingLeave = true
    end
    return true
end


local function isNearConfiguredTable(source, tableId)
    local config = Config.Tables[tableId]
    if not config or not config.Table or not config.Table.Coords then return false end
    if not GetPlayerPed or not GetEntityCoords then return true end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return true end
    local playerCoords = GetEntityCoords(ped)
    local tableCoords = config.Table.Coords
    local dx = playerCoords.x - tableCoords.x
    local dy = playerCoords.y - tableCoords.y
    local dz = playerCoords.z - tableCoords.z
    return math.sqrt(dx * dx + dy * dy + dz * dz) <= (Config.InteractionDistance + 2.0)
end

local function continueDealerTurn(game)
    local needsDealer = false
    for _, player in pairs(game.players) do
        if not player.hasLeft then
            for _, hand in ipairs(player.hands or {}) do
                if hand.status ~= "BUST" and hand.status ~= "FORFEIT" then
                    needsDealer = true
                    break
                end
            end
        end
        if needsDealer then break end
    end
    if not needsDealer then
        settleRound(game)
        return
    end

    game.dealerHand.value, game.dealerHand.isSoft = BlackjackCards.score(game.dealerHand.cards)
    local shouldHit = game.dealerHand.value < 17
        or game.dealerHand.value == 17 and game.dealerHand.isSoft and Config.Rules.DealerHitsSoft17
    if not shouldHit then
        settleRound(game)
        return
    end
    if not drawInto(game, game.dealerHand.cards) then
        refundRound(game, "the shoe ran out of cards")
        return
    end
    game.dealerHand.value, game.dealerHand.isSoft = BlackjackCards.score(game.dealerHand.cards)
    local duration = cueDealer(game, "dealerHit")
    local viewDelay = math.floor(Config.Animations.DealerDeal.time * Config.Animations.DealerDeal.DealCardAt)
    game.flow = "DEALER_HIT_VIEW"
    game.flowData = { remaining = duration - viewDelay }
    game.waitSteps = steps(viewDelay)
end

local function applySettlementSeatProp(game, action, seatIndex)
    for _, player in pairs(game.players) do
        if tonumber(player.seatIndex) == tonumber(seatIndex) then
            if action == "payout" then
                player.showPayoutChip = true
            elseif action == "collect" then
                player.bet = 0
            end
            break
        end
    end
    sendViews(game)
end

local function cleanRetrievedCards(game)
    game.dealerHand.cards = {}
    for _, player in pairs(game.players) do
        player.bet = 0
        player.showPayoutChip = false
        for _, hand in ipairs(player.hands or {}) do hand.cards = {} end
    end
    sendViews(game)
end

function ProcessGameTimers(game)
    if game.waitSteps and game.waitSteps > 0 then game.waitSteps = game.waitSteps - 1 end
    if game.bettingSteps and game.bettingSteps > 0 then game.bettingSteps = game.bettingSteps - 1 end
    if game.actionSteps and game.actionSteps > 0 then game.actionSteps = game.actionSteps - 1 end
    local updateBets = false
    for _, player in pairs(game.players) do
        if player.betPropSteps and player.betPropSteps > 0 then
            player.betPropSteps = player.betPropSteps - 1
            if player.betPropSteps == 0 then
                player.betPropSteps = nil
                player.betVisible = true
                updateBets = true
            end
        end
    end
    if updateBets then sendViews(game) end
end

function ProcessGameState(game)
    if game.waitSteps and game.waitSteps > 0 then return end

    if game.flow == "SHUFFLE_FINISH" then
        initializeBetting(game)
        return
    end
    if game.flow == "WAITING_RETRY" then
        game.flow = nil
        if countRealPlayers(game) > 0 then startBetting(game) end
        return
    end
    if game.flow == "BETWEEN_ROUNDS" then
        game.flow = nil
        game.deadline = nil
        clearDeparted(game)
        if countRealPlayers(game) == 0 then
            game.state = "WAITING"
            broadcastTables()
        else
            maybeNpcLeavesBetweenHands(game)
            startBetting(game)
        end
        return
    end
    if game.flow == "NEXT_PLAYER_WAIT" then
        local data = game.flowData
        game.flow = nil
        game.flowData = nil
        if not activatePlayerTurn(game, data.position, data.handIndex) then
            advanceTurn(game, data.position, data.handIndex)
        end
        return
    end
    if game.flow == "INITIAL_DEAL_CARD" then
        local data = game.flowData
        local dealCard = data.cards[data.cardIndex]
        if dealCard.dealer then
            game.dealerHand.cards[#game.dealerHand.cards + 1] = dealCard.card
        else
            local player = game.players[dealCard.source]
            if player and player.hands[1] then
                player.hands[1].cards[#player.hands[1].cards + 1] = dealCard.card
            end
        end
        data.cardIndex = data.cardIndex + 1

        if not data.cards[data.cardIndex] then
            for _, player in ipairs(orderedPlayers(game, true)) do
                local hand = player.hands[1]
                updateHand(hand)
                if BlackjackCards.isNatural(hand) then hand.status = "BLACKJACK" end
            end
            game.dealerHand.value, game.dealerHand.isSoft = BlackjackCards.score(game.dealerHand.cards)
            game.flow = "INITIAL_DEAL_FINISH"
            game.waitSteps = steps(data.totalDuration - data.animationDuration)
        else
            game.waitSteps = dividedStepDelay(data.cardAnimationSteps, data.cardIndex, #data.cards)
        end
        sendViews(game)
        return
    end
    if game.flow == "INITIAL_DEAL_FINISH" then
        game.flow = nil
        game.flowData = nil
        local upValue = BlackjackCards.valueOf(game.dealerHand.cards[1])
        if Config.Rules.DealerPeek and (upValue == 10 or upValue == 11) and game.dealerHand.value == 21 then
            startDealerReveal(game, "PEEK_REVEAL_FINISH")
            return
        end
        for _, player in ipairs(orderedPlayers(game, true)) do
            if player.hands[1] and player.hands[1].status == "ACTIVE" then
                advanceTurn(game, 1, 1)
                return
            end
        end
        game.flow = "NO_ACTIVE_HAND_REVEAL"
        game.waitSteps = steps(1000)
        return
    end
    if game.flow == "PEEK_REVEAL_FINISH" then
        game.flow = nil
        sendViews(game)
        settleRound(game)
        return
    end
    if game.flow == "NO_ACTIVE_HAND_REVEAL" then
        startDealerReveal(game, "NO_ACTIVE_REVEAL_FINISH")
        return
    end
    if game.flow == "NO_ACTIVE_REVEAL_FINISH" then
        game.flow = nil
        sendViews(game)
        settleRound(game)
        return
    end
    if game.flow == "PLAYER_HIT_WAIT" then
        startPlayerDealFlow(game, game.flowData.player)
        return
    end
    if game.flow == "PLAYER_DEAL_VIEW" then
        local remaining = game.flowData.remaining
        sendViews(game)
        game.flow = "PLAYER_DEAL_FINISH"
        game.waitSteps = steps(remaining)
        return
    end
    if game.flow == "PLAYER_DEAL_FINISH" then
        game.flow = nil
        game.flowData = nil
        continueAfterAction(game)
        return
    end
    if game.flow == "NPC_HIT_WAIT" then
        local player = game.flowData.player
        local hand = player and player.hands[player.activeHandIndex or 1]
        if not hand or not drawInto(game, hand.cards) then
            refundRound(game, "the shoe ran out of cards")
            return
        end
        updateHand(hand)
        local dealerDuration = cueDealer(game, "deal", { seats = { player.seatIndex } })
        local viewDelay = math.floor(Config.Animations.DealerDeal.time * Config.Animations.DealerDeal.DealCardAt)
        game.flow = "NPC_DEAL_VIEW"
        game.flowData = { player = player, dealerRemaining = dealerDuration - viewDelay }
        game.waitSteps = steps(viewDelay)
        return
    end
    if game.flow == "NPC_DEAL_VIEW" then
        local data = game.flowData
        local hand = data.player.hands[data.player.activeHandIndex or 1]
        if hand and hand.status == "ACTIVE" and (hand.value or 0) >= (tonumber(npcConfig().StandValue) or 17) then
            hand.status = "STOOD"
        end
        sendViews(game)
        game.flow = "NPC_DEAL_FINISH"
        game.waitSteps = steps(data.dealerRemaining)
        return
    end
    if game.flow == "NPC_DEAL_FINISH" or game.flow == "NPC_STAND_FINISH" then
        game.flow = nil
        game.flowData = nil
        continueAfterAction(game)
        return
    end
    if game.flow == "DEALER_TRANSITION" then
        game.flow = nil
        game.state = "DEALER_TURN"
        game.currentSource = nil
        game.currentTurnPosition = nil
        game.acceptingAction = false
        startDealerReveal(game, "DEALER_REVEAL_FINISH")
        return
    end
    if game.flow == "DEALER_REVEAL_VIEW" then
        local data = game.flowData
        game.dealerHand.revealed = true
        sendViews(game)
        game.flow = data.finishFlow
        game.flowData = nil
        game.waitSteps = steps(data.remaining)
        return
    end
    if game.flow == "DEALER_REVEAL_FINISH" then
        game.flow = nil
        sendViews(game)
        continueDealerTurn(game)
        return
    end
    if game.flow == "DEALER_HIT_VIEW" then
        local remaining = game.flowData.remaining
        sendViews(game)
        game.flow = "DEALER_HIT_FINISH"
        game.waitSteps = steps(remaining)
        return
    end
    if game.flow == "DEALER_HIT_FINISH" then
        game.flow = nil
        game.flowData = nil
        continueDealerTurn(game)
        return
    end
    if game.flow == "SETTLEMENT_NEXT_CUE" then
        local cue = game.settlementCues and game.settlementCues[game.settlementCueIndex]
        if not cue then
            game.settlementCues = nil
            game.settlementCueIndex = nil
            game.flow = nil
            game.flowData = nil
            scheduleNextRound(game)
            return
        end
        game.flowData.activeCue = cue
        local duration = cueDealer(game, cue.action, { seats = cue.seats })
        if cue.action == "retrieve" then
            local propDelay = Config.Animations.DealerRetrieveCards.time
                * Config.Animations.DealerRetrieveCards.CleanCardsAt
            game.flowData.cueRemaining = duration - propDelay
            game.flow = "SETTLEMENT_RETRIEVE_PROP"
            game.waitSteps = steps(propDelay)
        else
            local animation = cue.action == "collect"
                and Config.Animations.DealerCollect or Config.Animations.DealerPayout
            game.flowData.cueSeatIndex = 1
            game.flowData.cueAnimationSteps = steps(animation.time)
            game.flowData.cueRemaining = duration - animation.time
            game.flow = "SETTLEMENT_SEAT_PROP"
            game.waitSteps = dividedStepDelay(game.flowData.cueAnimationSteps, 1, #cue.seats)
        end
        return
    end
    if game.flow == "SETTLEMENT_SEAT_PROP" then
        local cue = game.flowData.activeCue
        applySettlementSeatProp(game, cue.action, cue.seats[game.flowData.cueSeatIndex])
        game.flowData.cueSeatIndex = game.flowData.cueSeatIndex + 1
        if cue.seats[game.flowData.cueSeatIndex] then
            game.waitSteps = dividedStepDelay(game.flowData.cueAnimationSteps,
                game.flowData.cueSeatIndex, #cue.seats)
        else
            game.flow = "SETTLEMENT_CUE_FINISH"
            game.waitSteps = steps(game.flowData.cueRemaining)
        end
        return
    end
    if game.flow == "SETTLEMENT_RETRIEVE_PROP" then
        cleanRetrievedCards(game)
        game.flow = "SETTLEMENT_CUE_FINISH"
        game.waitSteps = steps(game.flowData.cueRemaining)
        return
    end
    if game.flow == "SETTLEMENT_CUE_FINISH" then
        game.flowData.activeCue = nil
        game.flowData.cueSeatIndex = nil
        game.flowData.cueAnimationSteps = nil
        game.flowData.cueRemaining = nil
        game.settlementCueIndex = game.settlementCueIndex + 1
        game.flow = "SETTLEMENT_NEXT_CUE"
        return
    end

    if game.state == "BETTING" and allBetsResolved(game) then
        beginDeal(game)
        return
    end

    if game.state == "BETTING" and game.bettingSteps == 0 then
        game.bettingSteps = nil
        for _, player in pairs(game.players) do
            if not player.hasLeft and not player.betLocked then
                player.betLocked = true
                player.bet = 0
                if not playerIsNpc(player) then
                    notify(player.source, "Betting timed out. You are sitting out this hand.", "error")
                end
            end
        end
        if allBetsResolved(game) then beginDeal(game) end
        return
    end

    if game.state == "PLAYER_TURNS" and game.actionSteps == 0 then
        game.actionSteps = nil
        if playerIsNpc(game.players[game.currentSource]) then
            processNpcTurn(game)
        else
            local player = game.players[game.currentSource]
            local hand = player and player.hands[player.activeHandIndex]
            game.acceptingAction = false
            game.deadline = nil
            if hand and hand.status == "ACTIVE" then
                hand.status = "STOOD"
                notify(player.source, "Action timed out. Your hand stood automatically.", "error")
            end
            continueAfterAction(game)
        end
    end
end

local commandHandlers = {}

function QueueGameCommand(game, command)
    if not game or gamesByTableId[game.id] ~= game or type(command) ~= "table" then return false end
    command.game = game
    command.player = command.source and game.players[command.source] or nil
    game.commands[#game.commands + 1] = command
    return true
end

function ProcessGameCommands(game)
    while game.commands[1] and gamesByTableId[game.id] == game do
        local command = table.remove(game.commands, 1)
        local handler = commandHandlers[command.type]
        if command.game == game and handler then handler(game, command) end
    end
end

local function queuePlayerCommand(source, command)
    local game = gamesByTableId[playerTableBySource[source]]
    if not game then return false end
    command.source = source
    return QueueGameCommand(game, command)
end

local function removeSpectator(source)
    local tableId = spectatorTableBySource[source]
    local game = tableId and gamesByTableId[tableId] or nil
    if game then game.spectators[source] = nil end
    spectatorTableBySource[source] = nil
end

RegisterNetEvent("nt_blackjack:server:requestTables", function()
    broadcastTables(source)
end)

RegisterNetEvent("nt_blackjack:server:setSpectator", function(tableId)
    local source = source
    local requestedTableId = tableId and tostring(tableId) or nil
    local game = requestedTableId and gamesByTableId[requestedTableId] or nil
    local tableConfig = requestedTableId and Config.Tables[requestedTableId] or nil
    if playerTableBySource[source]
        or not game
        or not tableConfig
        or not tableConfig.Enabled then
        requestedTableId = nil
        game = nil
    end

    removeSpectator(source)
    if game then
        game.spectators[source] = true
        spectatorTableBySource[source] = requestedTableId
    end

    TriggerClientEvent("nt_blackjack:client:spectatorChanged", source, requestedTableId)
    if game then
        TriggerClientEvent("nt_blackjack:client:updateSpectatorGame", source, buildGameView(game))
    end
end)

commandHandlers.joinTable = function(game, command)
    local source = command.source
    local tableId = game.id
    local config = Config.Tables[tableId]

    if not config or not config.Enabled or gamesByTableId[tableId] ~= game then return end
    if playerTableBySource[source] then
        notify(source, "You are already seated at a Blackjack table.", "error")
        return
    end
    if not isNearConfiguredTable(source, tableId) then
        notify(source, "You are too far from that table.", "error")
        return
    end

    local seat = findFreeSeat(game)
    if not seat and Config.NPCPlayers and Config.NPCPlayers.KickForPlayerJoin and markRandomNpcToLeave(game) then
        seat = findFreeSeat(game)
    end
    if not seat then
        notify(source, "This Blackjack table is full. An NPC will leave after this hand if one is seated.", "error")
        return
    end

    local choosesCardStyle = countRealPlayers(game) == 0 and not game.cardStyle
    local player = {
        source = source,
        name = Framework.getName(source) or GetPlayerName(source) or ("Player %d"):format(source),
        seatIndex = seat,
        hands = {},
        activeHandIndex = 1,
        bet = 0,
        betVisible = false,
        totalWager = 0,
        betLocked = false,
        waiting = game.state ~= "WAITING" and game.state ~= "BETTING",
        hasLeft = false,
    }

    removeSpectator(source)
    game.players[source] = player
    game.seats[seat] = source
    playerTableBySource[source] = tableId
    if choosesCardStyle then game.cardStyleChooser = source end
    TriggerClientEvent("nt_blackjack:client:joined", source, tableId, seat, choosesCardStyle)
    TriggerClientEvent("nt_blackjack:client:spectatorChanged", source, nil)
    notify(source, player.waiting and "You will join the next hand." or "Place your bet.", "success")

    if game.state == "WAITING" then
        maybeNpcLeavesBetweenHands(game)
        startBetting(game)
    else
        sendViews(game)
    end
end

RegisterNetEvent("nt_blackjack:server:joinTable", function(tableId)
    tableId = tostring(tableId or "")
    local game = gamesByTableId[tableId]
    if game then QueueGameCommand(game, { type = "joinTable", source = source }) end
end)

commandHandlers.selectCardStyle = function(game, command)
    local source = command.source
    if not game or game.cardStyle or game.cardStyleChooser ~= source then return end
    local style = command.style
    if not ConfigProps.Cards.cardEndings[style] or not ConfigProps.Cards.DeckEndings[style] then return end
    game.cardStyle = style
    game.cardStyleChooser = nil
    sendViews(game)
end

RegisterNetEvent("nt_blackjack:server:selectCardStyle", function(style)
    queuePlayerCommand(source, { type = "selectCardStyle", style = tostring(style or "") })
end)

commandHandlers.npcAppearance = function(game, command)
    local source = command.source
    local requestId = command.requestId
    local appearance = command.appearance
    local pending = pendingNpcRequests[requestId]
    if not pending or pending.requestedFrom ~= source or pending.game ~= game then return end
    pendingNpcRequests[requestId] = nil

    if not game or not appearance or appearance.failed or not appearance.model or countRealPlayers(game) == 0 then return end
    if countNpcPlayers(game) >= npcCapacity(game) then return end

    local seat = findFreeSeat(game)
    if not seat then return end

    npcSerial = npcSerial + 1
    local npcId = ("npc:%s:%d"):format(game.id, npcSerial)
    local npc = npcConfig()
    local minHands = math.max(1, tonumber(npc.MinHandsToStay) or 1)
    local maxHands = math.max(minHands, tonumber(npc.MaxHandsToStay) or minHands)
    local player = {
        source = npcId,
        name = randomNpcName(game, appearance),
        seatIndex = seat,
        hands = {},
        activeHandIndex = 1,
        bet = 0,
        betVisible = false,
        totalWager = 0,
        betLocked = false,
        waiting = false,
        hasLeft = false,
        isNpc = true,
        npcId = npcId,
        npcAppearance = {
            model = appearance.model,
            outfit = appearance.outfit,
        },
        handsPlayed = 0,
        handsToStay = math.random(minHands, maxHands),
        pendingLeave = false,
    }

    if game.state == "BETTING" then assignNpcBet(player) end
    game.players[npcId] = player
    game.seats[seat] = npcId
    syncNpcPlayers(game)
    if game.state == "BETTING" and allBetsResolved(game) then beginDeal(game) end
end

RegisterNetEvent("nt_blackjack:server:npcAppearance", function(requestId, appearance)
    requestId = tostring(requestId or "")
    local pending = pendingNpcRequests[requestId]
    local game = pending and gamesByTableId[pending.tableId]
    if game then
        QueueGameCommand(game, {
            type = "npcAppearance",
            source = source,
            requestId = requestId,
            appearance = appearance,
        })
    end
end)

commandHandlers.placeBet = function(game, command)
    local source = command.source
    local player = game and game.players[source] or nil
    local amount = command.amount

    if not game or not player or game.state ~= "BETTING" or player.waiting or player.betLocked then return end
    if command.roundId ~= game.roundId then return end
    if not amount or amount ~= math.floor(amount) then
        notify(source, "Bet must be a whole number.", "error")
        return
    end
    if amount < Config.Rules.MinBet or amount > Config.Rules.MaxBet then
        notify(source, ("Bet must be between $%d and $%d."):format(Config.Rules.MinBet, Config.Rules.MaxBet), "error")
        return
    end
    if amount % Config.Rules.BetStep ~= 0 then
        notify(source, ("Bet must be in increments of $%d."):format(Config.Rules.BetStep), "error")
        return
    end
    if not Framework.removeMoney(source, amount, "blackjack-bet") then
        notify(source, "You do not have enough cash.", "error")
        return
    end

    player.bet = amount
    local propDelay = math.floor(Config.Animations.PlayerBet.time * Config.Animations.PlayerBet.ShowBetAt)
    player.betVisible = propDelay == 0
    player.betPropSteps = propDelay > 0 and steps(propDelay) or nil
    player.totalWager = amount
    player.betLocked = true
    notify(source, ("Bet placed: $%d"):format(amount), "success")
    sendViews(game)
    if allBetsResolved(game) then beginDeal(game) end
end

RegisterNetEvent("nt_blackjack:server:placeBet", function(amount, roundId)
    queuePlayerCommand(source, { type = "placeBet", amount = tonumber(amount), roundId = tonumber(roundId) })
end)

local function currentAction(source, roundId)
    local game = gamesByTableId[playerTableBySource[source]]
    if not game or game.state ~= "PLAYER_TURNS" or game.currentSource ~= source or not game.acceptingAction then return nil end
    if tonumber(roundId) ~= game.roundId then return nil end
    local player = game.players[source]
    local hand = player and player.hands[player.activeHandIndex] or nil
    if not hand or hand.status ~= "ACTIVE" then return nil end
    game.acceptingAction = false
    return game, player, hand
end

commandHandlers.hit = function(_, command)
    local game, player, hand = currentAction(command.source, command.roundId)
    if not game then return end
    if not drawInto(game, hand.cards) then refundRound(game, "the shoe ran out of cards") return end
    updateHand(hand)
    game.actionSteps = nil
    game.deadline = nil
    game.flow = "PLAYER_HIT_WAIT"
    game.flowData = { player = player }
    game.waitSteps = steps(Config.Animations.PlayerHit.time + Config.Animations.PlayerHit.DealDelay)
end

RegisterNetEvent("nt_blackjack:server:hit", function(roundId)
    queuePlayerCommand(source, { type = "hit", roundId = tonumber(roundId) })
end)

commandHandlers.stand = function(_, command)
    local game, _, hand = currentAction(command.source, command.roundId)
    if not game then return end
    game.actionSteps = nil
    game.deadline = nil
    hand.status = "STOOD"
    continueAfterAction(game)
end

RegisterNetEvent("nt_blackjack:server:stand", function(roundId)
    queuePlayerCommand(source, { type = "stand", roundId = tonumber(roundId) })
end)

commandHandlers.double = function(_, command)
    local source = command.source
    local game, player, hand = currentAction(source, command.roundId)
    if not game then return end
    if not Config.Rules.AllowDouble or #hand.cards ~= 2 then
        game.acceptingAction = true
        return
    end
    if not Framework.removeMoney(source, hand.bet, "blackjack-double") then
        game.acceptingAction = true
        notify(source, "You do not have enough cash to double.", "error")
        sendViews(game)
        return
    end

    player.totalWager = player.totalWager + hand.bet
    hand.bet = hand.bet * 2
    hand.doubled = true
    if not drawInto(game, hand.cards) then refundRound(game, "the shoe ran out of cards") return end
    updateHand(hand)
    if hand.status == "ACTIVE" then hand.status = "STOOD" end
    startPlayerDealFlow(game, player)
end

RegisterNetEvent("nt_blackjack:server:double", function(roundId)
    queuePlayerCommand(source, { type = "double", roundId = tonumber(roundId) })
end)

commandHandlers.split = function(_, command)
    local source = command.source
    local game, player, hand = currentAction(source, command.roundId)
    if not game
        or not Config.Rules.AllowSplit
        or #player.hands >= (Config.Rules.MaxSplitHands or 2)
        or not BlackjackCards.canSplit(hand)
    then
        if game then game.acceptingAction = true end
        return
    end
    if not Framework.removeMoney(source, hand.bet, "blackjack-split") then
        game.acceptingAction = true
        notify(source, "You do not have enough cash to split.", "error")
        sendViews(game)
        return
    end

    player.totalWager = player.totalWager + hand.bet
    local firstCard = hand.cards[1]
    local secondCard = hand.cards[2]
    local splitAces = firstCard.royalty == "A" and secondCard.royalty == "A"
    local firstHand = {
        cards = { firstCard },
        bet = hand.bet,
        value = 0,
        isSoft = false,
        status = "ACTIVE",
        isSplitHand = true,
        doubled = false,
    }
    local secondHand = {
        cards = { secondCard },
        bet = hand.bet,
        value = 0,
        isSoft = false,
        status = "ACTIVE",
        isSplitHand = true,
        doubled = false,
    }
    player.hands = { firstHand, secondHand }
    player.activeHandIndex = 1

    if not drawInto(game, firstHand.cards) or not drawInto(game, secondHand.cards) then
        refundRound(game, "the shoe ran out of cards")
        return
    end
    updateHand(firstHand)
    updateHand(secondHand)
    if splitAces then
        if firstHand.status == "ACTIVE" then firstHand.status = "STOOD" end
        if secondHand.status == "ACTIVE" then secondHand.status = "STOOD" end
    end
    startPlayerDealFlow(game, player)
end

RegisterNetEvent("nt_blackjack:server:split", function(roundId)
    queuePlayerCommand(source, { type = "split", roundId = tonumber(roundId) })
end)

local function leavePlayer(source, dropped)
    local tableId = playerTableBySource[source]
    local game = tableId and gamesByTableId[tableId] or nil
    local player = game and game.players[source] or nil
    if not game or not player then
        playerTableBySource[source] = nil
        return
    end

    player.hasLeft = true
    player.waiting = false
    game.seats[player.seatIndex] = nil
    playerTableBySource[source] = nil
    for _, hand in ipairs(player.hands or {}) do
        if hand.status == "ACTIVE" or hand.status == "STOOD" or hand.status == "BLACKJACK" then
            hand.status = "FORFEIT"
        end
    end

    if not dropped then
        TriggerClientEvent("nt_blackjack:client:leftTable", source)
    end

    if countRealPlayers(game) == 0 then
        destroyTableSession(game)
        broadcastTables()
        return
    end

    if not game.cardStyle and game.cardStyleChooser == source then
        for nextSource, nextPlayer in pairs(game.players) do
            if not playerIsNpc(nextPlayer) and not nextPlayer.hasLeft then
                game.cardStyleChooser = nextSource
                TriggerClientEvent("nt_blackjack:client:chooseCardStyle", nextSource)
                break
            end
        end
    end

    if game.state == "PLAYER_TURNS" and game.currentSource == source then
        game.actionSteps = nil
        game.acceptingAction = false
        game.deadline = nil
        game.flow = nil
        game.flowData = nil
        advanceTurn(game, game.currentTurnPosition + 1, 1)
    elseif game.state == "BETTING" and allBetsResolved(game) then
        beginDeal(game)
    else
        sendViews(game)
    end
end

commandHandlers.leave = function(_, command)
    leavePlayer(command.source, command.dropped)
end

RegisterNetEvent("nt_blackjack:server:leaveTable", function()
    queuePlayerCommand(source, { type = "leave", dropped = false })
end)

AddEventHandler("playerDropped", function()
    removeSpectator(source)
    if not queuePlayerCommand(source, { type = "leave", dropped = true }) then
        playerTableBySource[source] = nil
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    ServerRunning = false
    for _, game in pairs(gamesByTableId) do
        if not game.roundSettled and game.state ~= "WAITING" then
            for source, player in pairs(game.players) do
                if not player.hasLeft and not playerIsNpc(player) and (player.totalWager or 0) > 0 then
                    Framework.addMoney(source, player.totalWager, "blackjack-resource-stop-refund")
                end
            end
        end
    end
end)
