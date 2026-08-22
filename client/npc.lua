BlackjackNPCPlayers = {}

local currentTableId = nil
local spawnedPeds = {}
local animationVersions = {}

local function loadModel(model)
    if not model then return nil end
    local hash = type(model) == "number" and model or tonumber(model) or GetHashKey(model)
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
    if animation.Idle then return -1 end
    local seconds = tonumber(GetAnimDuration(animation.Dict, animation.Name)) or 0.0
    return seconds <= 0.0 and 2000 or math.max(1, math.floor(seconds * 1000.0 + 0.5))
end

local function deleteNpc(npcId)
    local ped = spawnedPeds[npcId]
    if ped and DoesEntityExist(ped) then DeletePed(ped) end
    spawnedPeds[npcId] = nil
    animationVersions[npcId] = nil
end

local function pointInPoly2D(point, poly)
    if type(poly) ~= "table" or #poly < 3 then return true end
    local x = point.x
    local y = point.y
    local inside = false
    local j = #poly
    for i = 1, #poly do
        local a = poly[i]
        local b = poly[j]
        if ((a.y > y) ~= (b.y > y))
            and (x < (b.x - a.x) * (y - a.y) / ((b.y - a.y) + 0.000001) + a.x) then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- Population types 1-6 are ambient world peds. Types 7+ are scripted.
local function isAmbientPed(ped, playerPed, scanArea)
    if ped == playerPed or not DoesEntityExist(ped) or IsEntityDead(ped)
        or IsPedAPlayer(ped) or not IsPedHuman(ped) or IsEntityAMissionEntity(ped) then
        return false
    end
    local populationType = GetEntityPopulationType(ped)
    return populationType >= 1 and populationType <= 6
        and pointInPoly2D(GetEntityCoords(ped), scanArea)
end

local function scanAmbientAppearance(tableId, scanArea)
    local peds = GetGamePool and GetGamePool("CPed") or {}
    local playerPed = PlayerPedId()
    local selectedPed = nil
    local candidateCount = 0

    for _, ped in ipairs(peds) do
        if isAmbientPed(ped, playerPed, scanArea) then
            candidateCount = candidateCount + 1
            if math.random(candidateCount) == 1 then selectedPed = ped end
        end
    end

    if not selectedPed then
        if Config.Debug then
            print(("[Nt_BlackJack][NPC] No ambient NPC found in scan area for %s"):format(tostring(tableId)))
        end
        return { failed = true }
    end

    local model = GetEntityModel(selectedPed)
    local outfitCount = GetNumMetaPedOutfits(selectedPed) or 0
    local outfit = outfitCount > 0 and math.random(0, outfitCount - 1) or nil
    local isMale = IsPedMale(selectedPed)
    local names = isMale and Config.NPCPlayers.MaleNames or Config.NPCPlayers.FemaleNames
    local name = names[math.random(1, #names)]
    if Config.Debug then
        print(("[Nt_BlackJack][NPC] Found ambient NPC for %s | candidates=%d | model=%s | outfits=%d | selected=%s"):format(
            tostring(tableId),
            candidateCount,
            tostring(model),
            outfitCount,
            tostring(outfit)
        ))
    end
    return {
        model = model,
        outfit = outfit,
        name = name,
        isMale = isMale,
    }
end

local function playPedAnimation(npcId, animation)
    local ped = spawnedPeds[npcId]
    if not ped or not DoesEntityExist(ped) or not animation or not loadAnimation(animation.Dict) then return end
    animationVersions[npcId] = (animationVersions[npcId] or 0) + 1
    local version = animationVersions[npcId]
    local length = animationDurationMs(animation)
    TaskPlayAnim(ped, animation.Dict, animation.Name, animation.Idle and 1.0 or 8.0, 1.0, length, 25, 1.0, true, 0, false, 0, false)
    if length > 0 then
        CreateThread(function()
            Wait(length)
            if animationVersions[npcId] == version and spawnedPeds[npcId] and DoesEntityExist(spawnedPeds[npcId]) then
                playPedAnimation(npcId, Config.Animations.PlayerIdle)
            end
        end)
    end
end

local function spawnNpc(player)
    local tableConfig = Config.Tables and Config.Tables[currentTableId]
    local seat = tableConfig and tableConfig.Seats and tableConfig.Seats[tonumber(player.seatIndex)]
    local appearance = player.npcAppearance or {}
    if not seat or not seat.Coords then return end
    local hash = loadModel(appearance.model)
    if not hash then return end

    local coords = seat.Coords
    -- The first two booleans keep this ped local-only/non-networked, matching dealer spawning.
    local ped = CreatePed(hash, coords.x, coords.y, coords.z, coords.w or 0.0, false, false, true, true)
    if not ped or ped == 0 then
        SetModelAsNoLongerNeeded(hash)
        return
    end

    -- Mirror the dealer's initialization order before starting the scenario.
    SetEntityHeading(ped, coords.w or 0.0)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityAsMissionEntity(ped, true, true)
    local outfit = tonumber(appearance.outfit)
    if outfit and outfit >= 0 then
        Citizen.InvokeNative(0x77FF8D35EEC6BBC4, ped, outfit, false)
    elseif SetRandomOutfitVariation then
        SetRandomOutfitVariation(ped, true)
    end
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, false)
    ClearPedTasksImmediately(ped)


    local zOffset = 0

    if not IsPedMale(ped) then
        zOffset = Config.FemaleOffset
    end



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

    spawnedPeds[player.npcId] = ped
    SetModelAsNoLongerNeeded(hash)
    CreateThread(function()
        Wait(500)
        if spawnedPeds[player.npcId] == ped and DoesEntityExist(ped) then
            playPedAnimation(player.npcId, Config.Animations.PlayerIdle)
        end
    end)
end

function BlackjackNPCPlayers:Start(tableId)
    if currentTableId == tableId then return end
    self:CleanupAll()
    currentTableId = tableId
end

function BlackjackNPCPlayers:UpdateGame(gameView)
    if not currentTableId or not gameView or gameView.tableId ~= currentTableId then return end
    local desired = {}
    for _, player in ipairs(gameView.players or {}) do
        if player.isNpc and player.npcId then
            desired[player.npcId] = player
        end
    end

    for npcId, ped in pairs(spawnedPeds) do
        if not desired[npcId] then
            deleteNpc(npcId)
        end
    end

    for npcId, player in pairs(desired) do
        if not spawnedPeds[npcId] or not DoesEntityExist(spawnedPeds[npcId]) then
            spawnNpc(player)
        end
    end
end

function BlackjackNPCPlayers:Play(npcId, action, _)
    local animations = {
        hit = Config.Animations.PlayerHit,
        stand = Config.Animations.PlayerStand,
        idle = Config.Animations.PlayerIdle,
        bet = Config.Animations.PlayerBet,
    }
    playPedAnimation(npcId, animations[action] or Config.Animations.PlayerIdle)
end

function BlackjackNPCPlayers:CleanupAll()
    for npcId in pairs(spawnedPeds) do deleteNpc(npcId) end
    currentTableId = nil
end

RegisterNetEvent("nt_blackjack:client:requestNpcAppearance", function(requestId, tableId, scanArea)
    local appearance = scanAmbientAppearance(tableId, scanArea)
    TriggerServerEvent("nt_blackjack:server:npcAppearance", requestId, appearance)
end)
