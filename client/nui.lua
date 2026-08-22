BlackjackUI = {}

local uiOpen = false
local cameraLookActive = false
local cameraLookSawAim = false
local firstPersonActive = false
local cursorX, cursorY = 0.5, 0.5
local INPUT_AIM = GetHashKey("INPUT_AIM")
local INPUT_ATTACK = GetHashKey("INPUT_ATTACK")
local INPUT_ATTACK2 = GetHashKey("INPUT_ATTACK2")
local INPUT_LOOK_LR = GetHashKey("INPUT_LOOK_LR")
local INPUT_LOOK_UD = GetHashKey("INPUT_LOOK_UD")

local function setFirstPerson(active)
    active = active == true and uiOpen
    firstPersonActive = active
    return firstPersonActive
end

local function setCameraLook(active, data)
    active = active == true and uiOpen
    if active == cameraLookActive then return end
    cameraLookActive = active

    if active then
        cursorX = math.max(0.0, math.min(1.0, tonumber(data and data.x) or 0.5))
        cursorY = math.max(0.0, math.min(1.0, tonumber(data and data.y) or 0.5))
        cameraLookSawAim = false
        SetNuiFocus(true, false)
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(true) end
    elseif uiOpen then
        cameraLookSawAim = false
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
        SetNuiFocus(true, true)
        if SetCursorLocation then SetCursorLocation(cursorX, cursorY) end
        SendNUIMessage({ type = "cameraLook", active = false })
    else
        cameraLookSawAim = false
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
        SetNuiFocus(false, false)
    end
end

-- Resource restarts can preserve NUI focus/page state on the client. Always
-- begin closed so the fullscreen browser cannot cover gameplay at startup.
CreateThread(function()
    Wait(0)
    uiOpen = false
    cameraLookActive = false
    SendNUIMessage({ type = "close" })
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SetNuiFocus(false, false)
end)

function BlackjackUI:Open(tableId)
    uiOpen = true
    cameraLookActive = false
    SendNUIMessage({
        type = "open",
        tableId = tableId,
    })
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SetNuiFocus(true, true)
end

function BlackjackUI:Update(gameView)
    if not uiOpen then return end
    SendNUIMessage({
        type = "state",
        game = gameView,
    })
end

function BlackjackUI:ChooseCardStyle()
    local styles = {}
    for name in pairs(ConfigProps.Cards.cardEndings or {}) do
        if ConfigProps.Cards.DeckEndings[name] then styles[#styles + 1] = name end
    end
    table.sort(styles)
    SendNUIMessage({ type = "chooseCardStyle", styles = styles })
end

function BlackjackUI:Close()
    setFirstPerson(false)
    uiOpen = false
    if ResetActionWait then ResetActionWait() end
    setCameraLook(false)
    SendNUIMessage({ type = "close" })
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SetNuiFocus(false, false)
end

RegisterNUICallback("cameraLook", function(data, callback)
    setCameraLook(data and data.active == true, data)
    callback({ ok = true })
end)

RegisterNUICallback("toggleFirstPerson", function(_, callback)
    callback({ active = setFirstPerson(not firstPersonActive) })
end)

CreateThread(function()
    while true do
        if firstPersonActive then
            Citizen.InvokeNative(0x90DA5BA5C2635416)
            Wait(0)
        else
            Wait(100)
        end
    end
end)

CreateThread(function()
    while true do
        if cameraLookActive then
            DisableControlAction(0, INPUT_AIM, true)
            DisableControlAction(0, INPUT_ATTACK, true)
            DisableControlAction(0, INPUT_ATTACK2, true)
            EnableControlAction(0, INPUT_LOOK_LR, true)
            EnableControlAction(0, INPUT_LOOK_UD, true)
            local aimPressed = IsDisabledControlPressed(0, INPUT_AIM) or IsControlPressed(0, INPUT_AIM)
            if aimPressed then
                cameraLookSawAim = true
            elseif cameraLookSawAim then
                setCameraLook(false)
            end
            Wait(0)
        else
            Wait(100)
        end
    end
end)

local function beginAnimatedAction(animationKey)
    if PlayBlackjackAnimation then PlayBlackjackAnimation(animationKey) end
    return 0
end

RegisterNUICallback("placeBet", function(data, callback)
    local waitMs = beginAnimatedAction("PlayerBet")
    TriggerServerEvent("nt_blackjack:server:placeBet", data and data.amount, data and data.roundId)
    callback({ ok = true, waitMs = waitMs })
end)

RegisterNUICallback("hit", function(data, callback)
    local waitMs = beginAnimatedAction("PlayerHit")
    TriggerServerEvent("nt_blackjack:server:hit", data and data.roundId)
    callback({ ok = true, waitMs = waitMs })
end)

RegisterNUICallback("stand", function(data, callback)
    local waitMs = beginAnimatedAction("PlayerStand")
    TriggerServerEvent("nt_blackjack:server:stand", data and data.roundId)
    callback({ ok = true, waitMs = waitMs })
end)

RegisterNUICallback("double", function(data, callback)
    local waitMs = beginAnimatedAction("PlayerBet")
    TriggerServerEvent("nt_blackjack:server:double", data and data.roundId)
    callback({ ok = true, waitMs = waitMs })
end)

RegisterNUICallback("split", function(data, callback)
    local waitMs = beginAnimatedAction("PlayerBet")
    TriggerServerEvent("nt_blackjack:server:split", data and data.roundId)
    callback({ ok = true, waitMs = waitMs })
end)
RegisterNUICallback("requestLeave", function(_, callback)
    TriggerServerEvent("nt_blackjack:server:leaveTable")
    callback({ ok = true })
end)

RegisterNUICallback("selectCardStyle", function(data, callback)
    TriggerServerEvent("nt_blackjack:server:selectCardStyle", data and data.style)
    callback({ ok = true })
end)
