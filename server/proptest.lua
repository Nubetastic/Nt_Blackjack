local SAVE_FILE = "proptest_props.json"

local function finiteNumber(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function rounded(value)
    local scaled = value * 100000
    if scaled >= 0 then return math.floor(scaled + 0.5) / 100000 end
    return math.ceil(scaled - 0.5) / 100000
end

local function allowedModel(model)
    for _, configuredModel in pairs(ConfigPropsTest and ConfigPropsTest.CardProps or {}) do
        if model == configuredModel then return true end
    end
    return false
end

local function normalizeProps(props)
    local normalized = {}
    for key, prop in pairs(type(props) == "table" and props or {}) do
        if type(prop) == "table" then
            local name = tostring(prop.Name or key)
            if tonumber(key) then name = tostring(prop.Name or ("Prop_%03d"):format(key)) end
            local offset = prop.offset or prop.PlayerOffset or prop.DealerOffset or {}
            local relativeTo = string.lower(tostring(prop.relativeTo or (prop.PlayerOffset and "player") or "dealer"))
            normalized[name] = {
                model = tostring(prop.model or prop.Model or ""),
                relativeTo = relativeTo == "player" and "player" or "dealer",
                showWhen = tostring(prop.showWhen or "always"),
                offset = {
                    x = tonumber(offset.x) or 0.0,
                    y = tonumber(offset.y) or 0.0,
                    z = tonumber(offset.z) or 0.0,
                    h = tonumber(offset.h) or 0.0,
                    rx = tonumber(offset.rx) or 0.0,
                    ry = tonumber(offset.ry) or 0.0,
                    rz = tonumber(offset.rz) or tonumber(offset.h) or 0.0,
                },
            }
        end
    end
    return normalized
end

local function loadSavedProps()
    local contents = LoadResourceFile(GetCurrentResourceName(), SAVE_FILE)
    if not contents or contents == "" then return { version = 2, tables = {} } end
    local ok, decoded = pcall(json.decode, contents)
    if not ok or type(decoded) ~= "table" then return nil end

    local saved = { version = 2, tables = {} }
    for tableId, tableData in pairs(type(decoded.tables) == "table" and decoded.tables or {}) do
        saved.tables[tostring(tableId)] = {
            Props = normalizeProps(type(tableData) == "table" and tableData.Props or {}),
        }
    end
    return saved
end

local function numberText(value)
    return ("%.5f"):format(tonumber(value) or 0.0)
end

local function encodeSavedProps(saved)
    local lines = { "{", '  "version": 2,', '  "tables": {' }
    local tableIds = {}
    for tableId in pairs(saved.tables or {}) do tableIds[#tableIds + 1] = tableId end
    table.sort(tableIds)

    for tablePosition, tableId in ipairs(tableIds) do
        local props = normalizeProps(saved.tables[tableId].Props)
        local names = {}
        for name in pairs(props) do names[#names + 1] = name end
        table.sort(names)

        lines[#lines + 1] = ("    %s: {"):format(json.encode(tableId))
        lines[#lines + 1] = '      "Props": {'
        for propPosition, name in ipairs(names) do
            local prop = props[name]
            local offset = prop.offset
            lines[#lines + 1] = ("        %s: {"):format(json.encode(name))
            lines[#lines + 1] = ('          "model": %s,'):format(json.encode(prop.model))
            lines[#lines + 1] = ('          "relativeTo": %s,'):format(json.encode(prop.relativeTo))
            lines[#lines + 1] = ('          "showWhen": %s,'):format(json.encode(prop.showWhen))
            lines[#lines + 1] = ('          "offset": { "x": %s, "y": %s, "z": %s, "h": %s, "rx": %s, "ry": %s, "rz": %s }'):format(
                numberText(offset.x), numberText(offset.y), numberText(offset.z), numberText(offset.h),
                numberText(offset.rx), numberText(offset.ry), numberText(offset.rz)
            )
            lines[#lines + 1] = propPosition < #names and "        }," or "        }"
        end
        lines[#lines + 1] = "      }"
        lines[#lines + 1] = tablePosition < #tableIds and "    }," or "    }"
    end

    lines[#lines + 1] = "  }"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n") .. "\n"
end

local function nextPropName(props)
    local highest = 0
    for name in pairs(props or {}) do
        local index = tonumber(tostring(name):match("^Prop_(%d+)$"))
        if index and index > highest then highest = index end
    end
    return ("Prop_%03d"):format(highest + 1)
end

RegisterNetEvent("nt_blackjack:proptest:save", function(payload)
    local source = source
    if type(payload) ~= "table" then return end

    local tableId = tostring(payload.tableId or "")
    local tableConfig = Config.Tables and Config.Tables[tableId]
    local model = tostring(payload.model or "")
    local relativeTo = string.lower(tostring(payload.relativeTo or "dealer"))
    local showWhen = string.lower(tostring(payload.showWhen or "always"))
    local seatIndex = tonumber(payload.seatIndex)
    if not tableConfig or not allowedModel(model) or (relativeTo ~= "dealer" and relativeTo ~= "player") then
        TriggerClientEvent("nt_blackjack:proptest:saved", source, false, "Invalid table, prop model, or origin.")
        return
    end
    local validVisibility = relativeTo == "dealer"
        and (showWhen == "always" or showWhen == "dealer_cards")
        or relativeTo == "player"
        and (showWhen == "always" or showWhen == "player_cards" or showWhen == "player_bet")
    if not validVisibility then
        TriggerClientEvent("nt_blackjack:proptest:saved", source, false, "Invalid visibility state for the selected origin.")
        return
    end
    if relativeTo == "player" and not (seatIndex and tableConfig.Seats and tableConfig.Seats[seatIndex]) then
        TriggerClientEvent("nt_blackjack:proptest:saved", source, false, "Invalid player seat origin.")
        return
    end

    local offset = payload.offset or {}
    local values = {
        x = finiteNumber(offset.x), y = finiteNumber(offset.y), z = finiteNumber(offset.z),
        h = finiteNumber(offset.h), rx = finiteNumber(offset.rx), ry = finiteNumber(offset.ry), rz = finiteNumber(offset.rz),
    }
    for _, value in pairs(values) do
        if not value then
            TriggerClientEvent("nt_blackjack:proptest:saved", source, false, "Prop offset contains invalid numbers.")
            return
        end
    end
    if math.abs(values.x) > 10.0 or math.abs(values.y) > 10.0 or math.abs(values.z) > 10.0 then
        TriggerClientEvent("nt_blackjack:proptest:saved", source, false, "Prop must remain within 10 metres of its origin.")
        return
    end

    local saved = loadSavedProps()
    if not saved then
        TriggerClientEvent("nt_blackjack:proptest:saved", source, false, SAVE_FILE .. " contains invalid JSON.")
        return
    end

    local tableData = saved.tables[tableId] or { Props = {} }
    tableData.Props = normalizeProps(tableData.Props)
    local name = nextPropName(tableData.Props)
    tableData.Props[name] = {
        model = model,
        relativeTo = relativeTo,
        showWhen = showWhen,
        offset = {
            x = rounded(values.x), y = rounded(values.y), z = rounded(values.z), h = rounded(values.h),
            rx = rounded(values.rx), ry = rounded(values.ry), rz = rounded(values.rz),
        },
    }
    saved.tables[tableId] = tableData

    local encoded = encodeSavedProps(saved)
    if not encoded or not SaveResourceFile(GetCurrentResourceName(), SAVE_FILE, encoded, #encoded) then
        TriggerClientEvent("nt_blackjack:proptest:saved", source, false, "Could not write " .. SAVE_FILE .. ".")
        return
    end
    TriggerClientEvent("nt_blackjack:proptest:saved", source, true, ("%s saved relative to %s as %s (%s)."):format(model, relativeTo, name, showWhen))
end)
