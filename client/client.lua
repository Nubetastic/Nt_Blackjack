local publicTables = {}
local nearTableId = nil
local visualTableId = nil
local seatedTableId = nil
local spectatorTableId = nil
local requestedSpectatorTableId = nil
local seatedSeat = nil
local currentGame = nil
local joinPrompt = nil
local promptGroupId = math.random(0, 0xFFFFFF)
local joinDebounceUntil = 0
local playerAnimationVersion = 0
local tableBlips = {}
local preTablePosition = nil
local gameViewVersion = 0
local lockedTableChairs = {}
local playerHasActiveCards = false

local function notify(message, kind, duration)
    if lib and lib.notify then
        lib.notify({
            title = "Blackjack",
            description = tostring(message),
            type = kind or "inform",
            duration = duration or 5000,
        })
    end
end

local function clearTableBlips()
    for _, blip in ipairs(tableBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    tableBlips = {}
end

local function createTableBlips()
    clearTableBlips()

    local blipConfig = Config.Blip
    if not blipConfig or not blipConfig.Enabled then return end

    local sprite = GetHashKey(blipConfig.Sprite or blip_mg_blackjack)
    local scale = tonumber(blipConfig.Scale) or 0.8
    local label = blipConfig.Label or Blackjack

    for _, tableConfig in pairs(Config.Tables or {}) do
        if tableConfig.Enabled and tableConfig.Table and tableConfig.Table.Coords then
            local coords = tableConfig.Table.Coords
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z)
            if blip and blip ~= 0 then
                SetBlipSprite(blip, sprite, true)
                SetBlipScale(blip, scale)
                Citizen.InvokeNative(0x9CB1A1623062F402, blip, label)
                tableBlips[#tableBlips + 1] = blip
            end
        end
    end
end

local function createPrompt(label, control)
    local prompt = PromptRegisterBegin()
    PromptSetControlAction(prompt, control)
    PromptSetText(prompt, CreateVarString(10, "LITERAL_STRING", label))
    PromptSetEnabled(prompt, false)
    PromptSetVisible(prompt, false)
    PromptSetHoldMode(prompt, true)
    PromptSetGroup(prompt, promptGroupId, 0)
    PromptRegisterEnd(prompt)
    return prompt
end

local function togglePrompt(prompt, enabled)
    if not prompt then return end
    PromptSetEnabled(prompt, enabled)
    PromptSetVisible(prompt, enabled)
end

local function canInteract(ped)
    if not ped or ped == 0 then return false end
    if IsEntityDead(ped) or IsPedRagdoll(ped) then return false end
    if IsPedOnMount(ped) or IsPedInAnyVehicle(ped, false) then return false end
    if IsPedActiveInScenario(ped) then return false end
    return true
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
            print(("[Nt_BlackJack][PlayerAnim] %s / %s | idle loop | duration=-1"):format(
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
        print(("[Nt_BlackJack][PlayerAnim] %s / %s | native=%.4fs | duration=%dms%s"):format(
            tostring(animation.Dict),
            tostring(animation.Name),
            seconds,
            milliseconds,
            fallback and " | FALLBACK" or ""
        ))
    end
    return milliseconds
end

function PlayBlackjackAnimation(animationId)
    local animation = Config.Animations[animationId]
    if not animation or not seatedTableId or not loadAnimation(animation.Dict) then return end
    playerAnimationVersion = playerAnimationVersion + 1
    local version = playerAnimationVersion
    local length = animationDurationMs(animation)
    local blend = animation.Idle and 1.0 or 8.0
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    TaskPlayAnim(ped, animation.Dict, animation.Name, blend, 1.0, length, 25, 1.0, true, 0, false, 0, false)

    if length > 0 then
        CreateThread(function()
            Wait(length)
            if version == playerAnimationVersion and seatedTableId then
                PlayBlackjackAnimation("PlayerIdle")
            end
        end)
    end
end

local function startChairScenario(tableId, seatIndex)
    local tableConfig = Config.Tables[tableId]
    local seat = tableConfig and tableConfig.Seats and tableConfig.Seats[seatIndex] or nil
    if not seat or not seat.Coords then return end
    local coords = seat.Coords
    local ped = PlayerPedId()

    local zOffset = 0

    if not IsPedMale(ped) then
        zOffset = Config.FemaleOffset
    end

    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, true)
    TaskStartScenarioAtPosition(
        ped,
        GetHashKey("GENERIC_SEAT_CHAIR_TABLE_SCENARIO"),
        coords.x,
        coords.y,
        coords.z + zOffset,
        coords.w or 0.0,
        -1,
        false,
        true
    )
end

local function clearPlayerState()
    local returnPosition = preTablePosition
    preTablePosition = nil
    gameViewVersion = gameViewVersion + 1
    playerAnimationVersion = playerAnimationVersion + 1
    seatedTableId = nil
    spectatorTableId = nil
    requestedSpectatorTableId = nil
    seatedSeat = nil
    currentGame = nil
    visualTableId = nil
    playerHasActiveCards = false
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)
    if returnPosition then
        SetEntityCoords(
            ped,
            returnPosition.x,
            returnPosition.y,
            returnPosition.z,
            false,
            false,
            false,
            false
        )
        SetEntityHeading(ped, returnPosition.h)
    end
    BlackjackUI:Close()
    BlackjackProps:CleanupAll()
    BlackjackDealer:CleanupAll()
    if BlackjackNPCPlayers then BlackjackNPCPlayers:CleanupAll() end
end

local function freezeTableChairs(tableId)
    local tableConfig = Config.Tables and Config.Tables[tableId]
    if not tableConfig then return end

    local objects = GetGamePool("CObject")
    for seatIndex, seat in pairs(tableConfig.Seats or {}) do
        if seat.Coords then
            local lockedChair = lockedTableChairs[seatIndex]
            if lockedChair and DoesEntityExist(lockedChair.object) then
                SetEntityCoordsNoOffset(lockedChair.object, lockedChair.coords.x, lockedChair.coords.y, lockedChair.coords.z, false, false, false)
                SetEntityRotation(lockedChair.object, lockedChair.rotation.x, lockedChair.rotation.y, lockedChair.rotation.z, 2, true)
                FreezeEntityPosition(lockedChair.object, true)
            else
                local closestChair = nil
                local closestDistance = 0.75

                for _, object in ipairs(objects) do
                    if DoesEntityExist(object) then
                        local objectCoords = GetEntityCoords(object)
                        local x = objectCoords.x - seat.Coords.x
                        local y = objectCoords.y - seat.Coords.y
                        local distance = math.sqrt(x * x + y * y)
                        if distance < closestDistance then
                            closestChair = object
                            closestDistance = distance
                        end
                    end
                end

                if closestChair then
                    lockedTableChairs[seatIndex] = {
                        object = closestChair,
                        coords = GetEntityCoords(closestChair),
                        rotation = GetEntityRotation(closestChair, 2),
                    }
                    FreezeEntityPosition(closestChair, true)
                end
            end
        end
    end
end

local function ensureVisuals(tableId)
    if visualTableId == tableId then
        if tableId then freezeTableChairs(tableId) end
        return
    end
    BlackjackProps:CleanupAll()
    BlackjackDealer:CleanupAll()
    if BlackjackNPCPlayers then BlackjackNPCPlayers:CleanupAll() end
    visualTableId = tableId
    lockedTableChairs = {}
    if tableId then
        freezeTableChairs(tableId)
        BlackjackProps:Start(tableId)
        BlackjackDealer:Start(tableId)
        if BlackjackNPCPlayers then BlackjackNPCPlayers:Start(tableId) end
    end
end

CreateThread(function()
    joinPrompt = createPrompt("Join Blackjack", GetHashKey(Config.Keys.Join))
    createTableBlips()
    TriggerServerEvent("nt_blackjack:server:setSpectator", nil)
    TriggerServerEvent("nt_blackjack:server:requestTables")

    while true do
        local sleep = 1000
        if not seatedTableId then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local closestInteractionId = nil
            local closestInteractionDistance = nil

            for tableId, tableConfig in pairs(Config.Tables) do
                if tableConfig.Enabled and tableConfig.Table and tableConfig.Table.Coords then
                    local distance = #(coords - tableConfig.Table.Coords)
                    if distance <= Config.InteractionDistance and (not closestInteractionDistance or distance < closestInteractionDistance) then
                        closestInteractionId = tableId
                        closestInteractionDistance = distance
                    end
                end
            end

            nearTableId = closestInteractionId
            togglePrompt(joinPrompt, false)

            if nearTableId and canInteract(ped) then
                sleep = 0
                local status = publicTables[nearTableId]
                local full = status and status.canJoin == false
                if not full then
                    local label = status and status.state ~= "WAITING" and "Join Blackjack (next hand)" or "Join Blackjack"
                    PromptSetText(joinPrompt, CreateVarString(10, "LITERAL_STRING", label))
                    togglePrompt(joinPrompt, true)
                    PromptSetActiveGroupThisFrame(promptGroupId, CreateVarString(10, "LITERAL_STRING", "Blackjack Table"))

                    if PromptHasHoldModeCompleted(joinPrompt) and GetGameTimer() >= joinDebounceUntil then
                        joinDebounceUntil = GetGameTimer() + 3000
                        TriggerServerEvent("nt_blackjack:server:joinTable", nearTableId)
                    end
                end
            end
        else
            nearTableId = seatedTableId
            ensureVisuals(seatedTableId)
        end

        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = Config.Spectator.FarWait
        if seatedTableId then
            sleep = Config.Spectator.NearWait
        else
            local coords = GetEntityCoords(PlayerPedId())
            local closestTableId = nil
            local closestDistance = nil

            for tableId, tableConfig in pairs(Config.Tables) do
                if tableConfig.Enabled and tableConfig.Table and tableConfig.Table.Coords then
                    local distance = #(coords - tableConfig.Table.Coords)
                    if not closestDistance or distance < closestDistance then
                        closestTableId = tableId
                        closestDistance = distance
                    end
                end
            end

            local desiredTableId = closestDistance and closestDistance <= Config.Spectator.Distance
                and closestTableId or nil
            local desiredRequest = desiredTableId or false
            if requestedSpectatorTableId ~= desiredRequest
                and (spectatorTableId ~= desiredTableId or requestedSpectatorTableId ~= nil) then
                requestedSpectatorTableId = desiredRequest
                ensureVisuals(desiredTableId)
                TriggerServerEvent("nt_blackjack:server:setSpectator", desiredTableId)
            end

            if closestDistance and closestDistance < Config.Spectator.NearDistance then
                sleep = Config.Spectator.NearWait
            elseif closestDistance and closestDistance <= Config.Spectator.MediumDistance then
                sleep = Config.Spectator.MediumWait
            end
        end

        Wait(sleep)
    end
end)

RegisterNetEvent("nt_blackjack:client:notify", function(data)
    if type(data) == "table" then
        notify(data.description or data.message or "", data.type, data.duration)
    else
        notify(data)
    end
end)

RegisterNetEvent("nt_blackjack:client:updateTables", function(tables)
    publicTables = tables or {}
end)

RegisterNetEvent("nt_blackjack:client:joined", function(tableId, seatIndex, choosesCardStyle)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    preTablePosition = {
        x = coords.x,
        y = coords.y,
        z = coords.z - 1.0,
        h = GetEntityHeading(ped),
    }
    seatedTableId = tableId
    spectatorTableId = nil
    requestedSpectatorTableId = nil
    seatedSeat = tonumber(seatIndex)
    ensureVisuals(tableId)
    startChairScenario(tableId, seatedSeat)
    BlackjackUI:Open(tableId)
    if choosesCardStyle then BlackjackUI:ChooseCardStyle() end
end)

local function applyWorldView(gameView)
    BlackjackProps:UpdateGame(gameView)
    BlackjackDealer:SetCardStyle(gameView.cardStyle)
    if gameView.state == "SETTLEMENT" then BlackjackDealer:CleanupDeckDuplicates() end
    if BlackjackNPCPlayers then BlackjackNPCPlayers:UpdateGame(gameView) end
end

local function applyGameView(gameView)
    if not gameView or not seatedTableId or gameView.tableId ~= seatedTableId then return end
    currentGame = gameView
    BlackjackUI:Update(gameView)
    applyWorldView(gameView)

    local hasPlayerCards = gameView.self and gameView.self.hands and #gameView.self.hands > 0
    local activeCards = gameView.state == "DEALING"
        or gameView.state == "PLAYER_TURNS"
        or gameView.state == "DEALER_TURN"

    local shouldHoldCards = hasPlayerCards and activeCards
    if shouldHoldCards and not playerHasActiveCards then
        PlayBlackjackAnimation("PlayerIdle")
    end
    playerHasActiveCards = shouldHoldCards
end

RegisterNetEvent("nt_blackjack:client:updateGame", function(gameView)
    if not gameView or not seatedTableId or gameView.tableId ~= seatedTableId then return end
    gameViewVersion = gameViewVersion + 1
    local version = gameViewVersion
    if version == gameViewVersion then applyGameView(gameView) end
end)

RegisterNetEvent("nt_blackjack:client:spectatorChanged", function(tableId)
    spectatorTableId = tableId
    requestedSpectatorTableId = nil
    if not seatedTableId then
        BlackjackUI:Close()
        ensureVisuals(tableId)
    end
end)

RegisterNetEvent("nt_blackjack:client:updateSpectatorGame", function(gameView)
    if not gameView
        or seatedTableId
        or gameView.tableId ~= spectatorTableId
        or visualTableId ~= spectatorTableId then return end
    applyWorldView(gameView)
end)

RegisterNetEvent("nt_blackjack:client:chooseCardStyle", function()
    if seatedTableId then BlackjackUI:ChooseCardStyle() end
end)

RegisterNetEvent("nt_blackjack:client:dealerAnimation", function(tableId, action, data)
    if visualTableId == tableId then
        BlackjackDealer:Play(action, data)
    end
end)

RegisterNetEvent("nt_blackjack:client:npcAnimation", function(tableId, npcId, action, data)
    if visualTableId == tableId and BlackjackNPCPlayers then
        BlackjackNPCPlayers:Play(npcId, action, data)
    end
end)

RegisterNetEvent("nt_blackjack:client:leftTable", function()
    clearPlayerState()
    notify("You left the Blackjack table.", "inform")
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    TriggerServerEvent("nt_blackjack:server:setSpectator", nil)
    togglePrompt(joinPrompt, false)
    clearTableBlips()
    clearPlayerState()
end)
