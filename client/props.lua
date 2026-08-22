BlackjackProps = {
    table = {},
    dealerCards = {},
    players = {},
}

local currentTableId = nil
local propsVersion = 0
local maxCardsPerHand = 11

local function newProp()
    return { shouldSpawn = false, isSpawned = false, object = nil, descriptor = nil, signature = nil }
end

local function loadModel(model)
    if not model then return nil end
    local hash = type(model) == "number" and model or GetHashKey(model)
    if not IsModelInCdimage(hash) and not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    return HasModelLoaded(hash) and hash or nil
end

local function deleteProp(object)
    if not object or not DoesEntityExist(object) then return true end
    SetEntityAsMissionEntity(object, true, true)
    DeleteObject(object)
    if DoesEntityExist(object) then DeleteEntity(object) end
    return not DoesEntityExist(object)
end

local function worldFromOrigin(origin, offset)
    local heading = tonumber(origin.w) or 0.0
    local radians = math.rad(heading)
    local forward = tonumber(offset.x) or 0.0
    local right = tonumber(offset.y) or 0.0
    return {
        x = origin.x + right * math.cos(radians) - forward * math.sin(radians),
        y = origin.y + right * math.sin(radians) + forward * math.cos(radians),
        z = origin.z + (tonumber(offset.z) or 0.0),
        heading = heading,
    }
end

local function createProp(descriptor)
    local definition = descriptor.definition
    local origin = descriptor.origin
    if type(definition) ~= "table" or not definition.model or not origin then return nil end
    local offset = definition.offset or {}
    local position = worldFromOrigin(origin, offset)
    local hash = loadModel(definition.model)
    if not hash then return nil end
    local object = CreateObjectNoOffset(hash, position.x, position.y, position.z, false, false, false)
    if not object or object == 0 then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end
    if offset.rx ~= nil or offset.ry ~= nil or offset.rz ~= nil then
        SetEntityRotation(object, tonumber(offset.rx) or 0.0, tonumber(offset.ry) or 0.0,
            position.heading + (tonumber(offset.rz) or tonumber(offset.h) or 0.0), 2, true)
    else
        SetEntityHeading(object, position.heading + (tonumber(offset.h) or 0.0))
    end
    SetEntityCollision(object, false, false)
    SetEntityCompletelyDisableCollision(object, true, true)
    FreezeEntityPosition(object, true)
    SetEntityAsMissionEntity(object, true, true)
    SetModelAsNoLongerNeeded(hash)
    return object
end

local function propSignature(definition, origin)
    local offset = definition.offset or {}
    return table.concat({
        tostring(definition.model),
        tostring(offset.x or 0.0), tostring(offset.y or 0.0), tostring(offset.z or 0.0),
        tostring(offset.rx or 0.0), tostring(offset.ry or 0.0), tostring(offset.rz or offset.h or 0.0),
        tostring(origin.x), tostring(origin.y), tostring(origin.z), tostring(origin.w or 0.0),
    }, ":")
end

local function setProp(prop, shouldSpawn, definition, origin)
    prop.shouldSpawn = shouldSpawn == true and definition ~= nil and definition.model ~= nil and origin ~= nil
    prop.descriptor = prop.shouldSpawn and {
        definition = definition,
        origin = origin,
        signature = propSignature(definition, origin),
    } or nil
end

local function updateProp(prop)
    local descriptor = prop.descriptor
    local missing = prop.isSpawned and (not prop.object or not DoesEntityExist(prop.object))
    local changed = prop.isSpawned and descriptor and prop.signature ~= descriptor.signature
    if prop.isSpawned and (not prop.shouldSpawn or missing or changed) then
        if deleteProp(prop.object) then
            prop.isSpawned = false
            prop.object = nil
            prop.signature = nil
        end
    end
    if prop.shouldSpawn and not prop.isSpawned and descriptor then
        local object = createProp(descriptor)
        if object then
            prop.object = object
            prop.signature = descriptor.signature
            prop.isSpawned = true
        end
    end
end

local function forEachProp(callback)
    for _, prop in pairs(BlackjackProps.table) do callback(prop) end
    for cardIndex = 1, maxCardsPerHand do
        local prop = BlackjackProps.dealerCards[cardIndex]
        if prop then callback(prop) end
    end
    for _, playerProps in pairs(BlackjackProps.players) do
        for _, prop in pairs(playerProps.props) do callback(prop) end
        for _, handCards in ipairs(playerProps.hands) do
            for cardIndex = 1, maxCardsPerHand do
                local prop = handCards[cardIndex]
                if prop then callback(prop) end
            end
        end
    end
end

local function disableAllProps()
    forEachProp(function(prop)
        prop.shouldSpawn = false
        prop.descriptor = nil
    end)
end

local function setupProps(tableConfig)
    BlackjackProps.table = {}
    BlackjackProps.dealerCards = {}
    BlackjackProps.players = {}
    for name, definition in pairs(ConfigProps.Props or {}) do
        if definition.model and string.lower(tostring(definition.relativeTo or "dealer")) == "dealer" then
            BlackjackProps.table[name] = newProp()
        end
    end
    for cardIndex = 1, maxCardsPerHand do BlackjackProps.dealerCards[cardIndex] = newProp() end
    for seatIndex in pairs(tableConfig.Seats or {}) do
        local playerProps = { props = {}, hands = {} }
        for name, definition in pairs(ConfigProps.Props or {}) do
            if definition.model and string.lower(tostring(definition.relativeTo or "dealer")) == "player" then
                playerProps.props[name] = newProp()
            end
        end
        for handIndex = 1, math.max(1, tonumber(Config.Rules.MaxSplitHands) or 2) do
            playerProps.hands[handIndex] = {}
            for cardIndex = 1, maxCardsPerHand do playerProps.hands[handIndex][cardIndex] = newProp() end
        end
        BlackjackProps.players[tonumber(seatIndex)] = playerProps
    end
end

local function playerRowsBySeat(gameView)
    local rows = {}
    for _, player in ipairs(gameView and gameView.players or {}) do
        local seatIndex = tonumber(player.seatIndex)
        if seatIndex then rows[seatIndex] = player end
    end
    return rows
end

local function playerHasCards(player)
    for _, hand in ipairs(player and player.hands or {}) do
        if type(hand.cards) == "table" and #hand.cards > 0 then return true end
    end
    return false
end

local function cardModel(card, style)
    if not card or not style then return nil end
    local ending = ConfigProps.Cards.cardEndings[style]
    if not ending then return nil end
    local royalty = tostring(card.royalty or card.propRoyalty or ""):lower()
    local suit = tostring(card.suit or card.propSuit or ""):lower()
    if royalty == "" or suit == "" then return nil end
    if royalty == "t" then royalty = "10" end
    return ConfigProps.Cards.cardHeader .. royalty .. "_" .. suit .. ending
end

local function cardDefinition(template, card, style, extraOffset, faceDown)
    local model = cardModel(card, style)
    if not template or not model then return nil end
    local base = template.offset or {}
    local extra = extraOffset or {}
    return {
        model = model,
        offset = {
            x = (tonumber(base.x) or 0.0) + (tonumber(extra.x) or 0.0),
            y = (tonumber(base.y) or 0.0) + (tonumber(extra.y) or 0.0),
            z = (tonumber(base.z) or 0.0) + (tonumber(extra.z) or 0.0),
            rx = tonumber(base.rx) or 0.0,
            ry = (tonumber(base.ry) or 0.0) + (faceDown and 180.0 or 0.0),
            rz = (tonumber(base.rz) or tonumber(base.h) or 0.0) + (tonumber(extra.h) or 0.0),
        },
    }
end

local function applyGameView(tableConfig, gameView)
    disableAllProps()
    local definitions = ConfigProps.Props or {}
    local dealerOrigin = tableConfig.Dealer and tableConfig.Dealer.Coords
    local players = playerRowsBySeat(gameView)
    local dealerCards = gameView and gameView.dealer and gameView.dealer.cards or {}
    local style = gameView and gameView.cardStyle
    for name, prop in pairs(BlackjackProps.table) do
        local definition = definitions[name]
        local showWhen = string.lower(tostring(definition.showWhen or "always"))
        setProp(prop, showWhen == "always" or showWhen == "dealer_cards" and #dealerCards > 0,
            definition, dealerOrigin)
    end
    if style then
        local hitOffset = ConfigProps.Cards.DealerHitOffset or {}
        for cardIndex, card in ipairs(dealerCards) do
            local prop = BlackjackProps.dealerCards[cardIndex]
            if prop then
                local template = definitions[cardIndex == 1 and "DealerCard1" or "DealerCard2"]
                local hitMultiplier = math.max(0, cardIndex - 2)
                local extra = {
                    x = hitMultiplier > 0 and (tonumber(hitOffset.x) or 0.0) or 0.0,
                    y = (tonumber(hitOffset.y) or 0.0) * hitMultiplier,
                    z = (tonumber(hitOffset.z) or 0.0) * hitMultiplier,
                    h = (tonumber(hitOffset.h) or 0.0) * hitMultiplier,
                }
                setProp(prop, true, cardDefinition(template, card, style, extra,
                    cardIndex == 2 and not gameView.dealer.revealed), dealerOrigin)
            end
        end
    end
    local hitOffset = ConfigProps.Cards.HitOffset or {}
    local splitOffset = ConfigProps.Cards.SplitOffset or {}
    for seatIndex, playerProps in pairs(BlackjackProps.players) do
        local player = players[seatIndex]
        local seat = tableConfig.Seats[seatIndex]
        local origin = seat and seat.Coords
        for name, prop in pairs(playerProps.props) do
            local definition = definitions[name]
            local matchesSeat = not definition.seatIndex or tonumber(definition.seatIndex) == seatIndex
            local showWhen = string.lower(tostring(definition.showWhen or "always"))
            local visible = matchesSeat and (showWhen == "always"
                or showWhen == "player_cards" and playerHasCards(player)
                or showWhen == "player_bet" and player and player.betVisible
                    and (tonumber(player.bet) or 0) > 0
                or showWhen == "player_payout" and player and player.showPayoutChip)
            setProp(prop, visible, definition, origin)
        end
        if style and player then
            for handIndex, hand in ipairs(player.hands or {}) do
                local handCards = playerProps.hands[handIndex]
                if handCards then
                    for cardIndex, card in ipairs(hand.cards or {}) do
                        local prop = handCards[cardIndex]
                        if prop then
                            local template = definitions[cardIndex == 1 and "PlayerCard1" or "PlayerCard2"]
                            local hitMultiplier = math.max(0, cardIndex - 2)
                            local splitMultiplier = handIndex - 1
                            local extra = {
                                x = (hitMultiplier > 0 and (tonumber(hitOffset.x) or 0.0) or 0.0)
                                    + (tonumber(splitOffset.x) or 0.0) * splitMultiplier,
                                y = (tonumber(hitOffset.y) or 0.0) * hitMultiplier
                                    + (tonumber(splitOffset.y) or 0.0) * splitMultiplier,
                                z = (tonumber(hitOffset.z) or 0.0) * hitMultiplier
                                    + (tonumber(splitOffset.z) or 0.0) * splitMultiplier,
                                h = (tonumber(hitOffset.h) or 0.0) * hitMultiplier
                                    + (tonumber(splitOffset.h) or 0.0) * splitMultiplier,
                            }
                            setProp(prop, true, cardDefinition(template, card, style, extra, false), origin)
                        end
                    end
                end
            end
        end
    end
end

function BlackjackProps:Stop()
    propsVersion = propsVersion + 1
    disableAllProps()
    for _ = 1, 10 do
        local propsRemaining = false
        forEachProp(function(prop)
            updateProp(prop)
            if prop.isSpawned then propsRemaining = true end
        end)
        if not propsRemaining then break end
    end
    currentTableId = nil
    self.table = {}
    self.dealerCards = {}
    self.players = {}
end

function BlackjackProps:Start(tableId)
    if currentTableId == tableId then return end
    self:Stop()
    local tableConfig = Config.Tables and Config.Tables[tableId]
    if not tableConfig then return end
    currentTableId = tableId
    setupProps(tableConfig)
    applyGameView(tableConfig, nil)
    local version = propsVersion
    CreateThread(function()
        while version == propsVersion and currentTableId == tableId do
            forEachProp(updateProp)
            Wait(100)
        end
    end)
end

function BlackjackProps:UpdateGame(gameView)
    if not currentTableId or not gameView or gameView.tableId ~= currentTableId then return end
    local tableConfig = Config.Tables and Config.Tables[currentTableId]
    if not tableConfig then return end
    applyGameView(tableConfig, gameView)
end

function BlackjackProps:CleanupAll()
    self:Stop()
end
