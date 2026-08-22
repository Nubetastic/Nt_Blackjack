BlackjackDealer = {}

local dealerPed = nil
local dealerHandObject = nil
local dealerHandObjects = {}
local currentTableId = nil
local animationVersion = 0
local currentAnimation = nil
local currentCardStyle = nil
local attachCards

local function loadModel(model)
    local hash = type(model) == "number" and model or GetHashKey(model)
    if not IsModelInCdimage(hash) and not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function loadAnimation(dictionary)
    RequestAnimDict(dictionary)
    local timeout = GetGameTimer() + 5000
    while not HasAnimDictLoaded(dictionary) and GetGameTimer() < timeout do Wait(0) end
    return HasAnimDictLoaded(dictionary)
end

local function animationDurationMs(animation)
    if animation.Idle then
        if Config.Debug then
            print(("[Nt_BlackJack][DealerAnim] %s / %s | idle loop | duration=-1"):format(
                tostring(animation.Dict),
                tostring(animation.Name)
            ))
        end
        return -1
    end
    local seconds = tonumber(GetAnimDuration(animation.Dict, animation.Name)) or 0.0
    local fallback = seconds <= 0.0
    local milliseconds = fallback and 2000 or math.max(1, math.floor(seconds * 1000.0 + 0.5))
    if Config.Debug then
        print(("[Nt_BlackJack][DealerAnim] %s / %s | native=%.4fs | duration=%dms%s"):format(
            tostring(animation.Dict),
            tostring(animation.Name),
            seconds,
            milliseconds,
            fallback and " | FALLBACK" or ""
        ))
    end
    return milliseconds
end

local function deleteTrackedHandObjects(keepObject)
    local deleted = true
    for object in pairs(dealerHandObjects) do
        if object ~= keepObject then
            if DoesEntityExist(object) then
                SetEntityAsMissionEntity(object, true, true)
                DeleteObject(object)
                if DoesEntityExist(object) then DeleteEntity(object) end
            end
            if DoesEntityExist(object) then
                deleted = false
            else
                dealerHandObjects[object] = nil
            end
        end
    end
    return deleted
end

local function deleteHandObject()
    if dealerHandObject then dealerHandObjects[dealerHandObject] = true end
    if not deleteTrackedHandObjects(nil) then return false end
    dealerHandObject = nil
    return true
end

local function deleteSafe()
    deleteHandObject()
    if dealerPed and DoesEntityExist(dealerPed) then DeletePed(dealerPed) end
    dealerPed = nil
    currentAnimation = nil
    currentCardStyle = nil
end

local function play(animation)
    if not dealerPed or not DoesEntityExist(dealerPed) or not animation then return end
    if not loadAnimation(animation.Dict) then return end
    if animation.HasCards then attachCards() end
    animationVersion = animationVersion + 1
    local version = animationVersion
    local length = animation.Idle and -1
        or (tonumber(animation.time) or 0)
    local blend = animation.Idle and 1.0 or 8.0
    if currentAnimation then
        StopAnimTask(dealerPed, currentAnimation.Dict, currentAnimation.Name, 2.0)
    end
    currentAnimation = {
        Dict = animation.Dict,
        Name = animation.Name,
    }
    -- Keep the original animation flags that these Blackjack clips expect.
    -- StopAnimTask above handles transitions between consecutive actions.
    TaskPlayAnim(dealerPed, animation.Dict, animation.Name, blend, 1.0, length, 25, 1.0, true, 0, false, 0, false)

    if length > 0 then
        CreateThread(function()
            Wait(length)
            if version == animationVersion and dealerPed and DoesEntityExist(dealerPed) then
                play(Config.Animations.DealerIdle)
            end
        end)
    end
end

attachCards = function()
    if not dealerPed or not DoesEntityExist(dealerPed) then return end
    local dealerHand = ConfigProps and ConfigProps.DealerHand or {}
    local attachment = dealerHand.attachment
    if not attachment or not attachment.bone then return end
    local boneIndex = GetEntityBoneIndexByName(dealerPed, attachment.bone)
    if not boneIndex or boneIndex == -1 then return end

    local object = dealerHandObject
    if object and DoesEntityExist(object) then
        dealerHandObjects[object] = true
        deleteTrackedHandObjects(object)
    else
        dealerHandObject = nil
        if not deleteTrackedHandObjects(nil) then return end
        local deckEnding = currentCardStyle and ConfigProps.Cards.DeckEndings[currentCardStyle]
        local model = deckEnding and (ConfigProps.Cards.DeckHeader .. deckEnding) or dealerHand.model
        if not model then return end
        local hash = loadModel(model)
        if not hash then return end
        object = CreateObjectNoOffset(hash, 0.0, 0.0, 0.0, false, false, false)
        if not object or object == 0 then return end
        SetEntityAsMissionEntity(object, true, true)
        SetEntityCollision(object, false, false)
        SetEntityCompletelyDisableCollision(object, true, true)
        dealerHandObject = object
        dealerHandObjects[object] = true
        SetModelAsNoLongerNeeded(hash)
    end

    AttachEntityToEntity(
        object,
        dealerPed,
        boneIndex,
        attachment.x,
        attachment.y,
        attachment.z,
        attachment.rx,
        attachment.ry,
        attachment.rz,
        true,
        false,
        false,
        true,
        1,
        true
    )
end

function BlackjackDealer:Start(tableId)
    if currentTableId == tableId and dealerPed and DoesEntityExist(dealerPed) then return end
    self:CleanupAll()
    local tableConfig = Config.Tables[tableId]
    local dealer = tableConfig and tableConfig.Dealer or nil
    if not dealer or not dealer.Coords or not dealer.Model then return end

    local hash = loadModel(dealer.Model)
    if not hash then return end
    local coords = dealer.Coords
    dealerPed = CreatePed(hash, coords.x, coords.y, coords.z, coords.w or 0.0, false, false, true, true)
    if not dealerPed then return end

    currentTableId = tableId
    SetEntityHeading(dealerPed, coords.w or 0.0)
    SetEntityCollision(dealerPed, false, false)
    FreezeEntityPosition(dealerPed, true)
    SetEntityInvincible(dealerPed, true)
    SetBlockingOfNonTemporaryEvents(dealerPed, true)
    SetEntityAsMissionEntity(dealerPed, true, true)
    Citizen.InvokeNative(0x283978A15512B2FE, dealerPed, true)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, dealerPed, 0, 1, 1, 1, false)
    ClearPedTasksImmediately(dealerPed)
    TaskStartScenarioAtPosition(
        dealerPed,
        GetHashKey("GENERIC_SEAT_CHAIR_TABLE_SCENARIO"),
        coords.x,
        coords.y,
        coords.z,
        coords.w or 0.0,
        -1,
        false,
        true
    )
    SetModelAsNoLongerNeeded(hash)
    attachCards()

    -- Do not layer the Blackjack upper-body idle over the chair scenario in
    -- the same frame. The scenario needs a moment to establish its base pose.
    local startedPed = dealerPed
    local startedTableId = currentTableId
    local startedAnimationVersion = animationVersion
    CreateThread(function()
        Wait(500)
        if dealerPed ~= startedPed
            or currentTableId ~= startedTableId
            or not DoesEntityExist(startedPed) then return end
        if animationVersion == startedAnimationVersion then
            play(Config.Animations.DealerIdle)
        end
        while dealerPed == startedPed
            and currentTableId == startedTableId
            and DoesEntityExist(startedPed) do
            attachCards()
            Wait(1000)
        end
    end)
end

function BlackjackDealer:SetHasCards(_)
    attachCards()
end

function BlackjackDealer:CleanupDeckDuplicates()
    if dealerHandObject and DoesEntityExist(dealerHandObject) then
        dealerHandObjects[dealerHandObject] = true
        deleteTrackedHandObjects(dealerHandObject)
    else
        dealerHandObject = nil
        deleteTrackedHandObjects(nil)
        attachCards()
    end
end

function BlackjackDealer:SetCardStyle(style)
    if currentCardStyle == style then return end
    if not deleteHandObject() then return end
    currentCardStyle = style
    attachCards()
end

function BlackjackDealer:GetPed()
    if dealerPed and DoesEntityExist(dealerPed) then return dealerPed end
    return nil
end

local function buildSeatAnimation(animation, data)
    if not animation then return nil end
    local seats = {}
    local seen = {}
    for _, value in ipairs(data and data.seats or {}) do
        local seatIndex = tonumber(value)
        if seatIndex and seatIndex % 1 == 0 and seatIndex >= 1 and seatIndex <= 4 and not seen[seatIndex] then
            seen[seatIndex] = true
            seats[#seats + 1] = seatIndex
        end
    end
    table.sort(seats)
    if #seats == 0 then return nil end
    return {
        Dict = animation.Dict,
        Name = animation.Name .. table.concat(seats),
        time = data and data.duration or animation.time,
        HasCards = animation.HasCards,
    }
end

function BlackjackDealer:Play(action, data)
    local dealerDeal = Config.Animations.DealerDeal
    local animations = {
        reveal = Config.Animations.DealerReveal,
        dealerHit = {
            Dict = dealerDeal.Self.Dict,
            Name = dealerDeal.Self.Name,
            time = dealerDeal.time,
            HasCards = dealerDeal.HasCards,
        },
        shuffle = Config.Animations.DealerShuffle,
    }

    local seatAnimations = {
        deal = Config.Animations.DealerDeal,
        initialDeal = Config.Animations.DealerInitialDeal,
        collect = Config.Animations.DealerCollect,
        payout = Config.Animations.DealerPayout,
        retrieve = Config.Animations.DealerRetrieveCards,
    }
    if seatAnimations[action] then
        local animation = buildSeatAnimation(seatAnimations[action], data)
        if animation then play(animation) end
        return
    end

    play(animations[action] or Config.Animations.DealerIdle)
end

function BlackjackDealer:CleanupAll()
    animationVersion = animationVersion + 1
    deleteSafe()
    currentTableId = nil
end
