BlackjackCards = {}

local function copyCard(card, deckNumber)
    return {
        id = card.id,
        shoeId = ("%d:%d"):format(deckNumber or 1, card.id),
        suit = card.suit,
        royalty = card.royalty,
        isRevealed = true,
    }
end

function BlackjackCards.buildShuffledDeck(fullDeck, deckCount)
    local tempDeck = {}
    local shuffledDeck = {}

    for deckNumber = 1, math.max(1, tonumber(deckCount) or 1) do
        for i = 1, #fullDeck do
            tempDeck[#tempDeck + 1] = copyCard(fullDeck[i], deckNumber)
        end
    end

    while #tempDeck > 0 do
        local randomIndex = math.random(1, #tempDeck)
        shuffledDeck[#shuffledDeck + 1] = tempDeck[randomIndex]
        tempDeck[randomIndex] = tempDeck[#tempDeck]
        tempDeck[#tempDeck] = nil
    end

    return shuffledDeck
end

function BlackjackCards.draw(game)
    local index = game.nextCardIndex or 1
    local card = game.shuffleDeck and game.shuffleDeck[index] or nil
    if not card then return nil end

    game.shuffleDeck[index] = nil
    game.nextCardIndex = index + 1
    game.cardsRemaining = math.max(0, (game.cardsRemaining or 1) - 1)
    return card
end

function BlackjackCards.valueOf(card)
    if not card then return 0 end
    if card.royalty == "A" then return 11 end
    if card.royalty == "T" or card.royalty == "J" or card.royalty == "Q" or card.royalty == "K" then
        return 10
    end
    return tonumber(card.royalty) or 0
end

function BlackjackCards.score(cards)
    local total = 0
    local aces = 0

    for _, card in ipairs(cards or {}) do
        total = total + BlackjackCards.valueOf(card)
        if card.royalty == "A" then aces = aces + 1 end
    end

    while total > 21 and aces > 0 do
        total = total - 10
        aces = aces - 1
    end

    return total, aces > 0
end

function BlackjackCards.isNatural(hand)
    if not hand or hand.isSplitHand then return false end
    return #(hand.cards or {}) == 2 and BlackjackCards.score(hand.cards) == 21
end

function BlackjackCards.canSplit(hand)
    if not hand or #(hand.cards or {}) ~= 2 then return false end
    return BlackjackCards.valueOf(hand.cards[1]) == BlackjackCards.valueOf(hand.cards[2])
end

function BlackjackCards.publicCard(card, revealed)
    if not card or not revealed then
        return { isRevealed = false }
    end
    return {
        royalty = card.royalty,
        suit = card.suit,
        isRevealed = true,
    }
end
