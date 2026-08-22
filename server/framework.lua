Framework = {}

if Config and (Config.Framework == "RSG" or Config.Framework == "rsg") then
    local Core = exports["rsg-core"] and exports["rsg-core"]:GetCoreObject() or nil

    function Framework.getPlayer(source)
        if not Core or not source then return nil end
        return Core.Functions.GetPlayer(source)
    end

    function Framework.getName(source)
        if Config.DisplayName == "account" then
            return GetPlayerName(source)
        end

        local player = Framework.getPlayer(source)
        local info = player and player.PlayerData and player.PlayerData.charinfo
        if info and info.firstname and info.lastname then
            return ("%s %s"):format(info.firstname, info.lastname)
        end
        return (info and info.firstname) or GetPlayerName(source)
    end

    function Framework.getCash(source)
        local player = Framework.getPlayer(source)
        if not player then return 0 end
        return tonumber(player.Functions.GetMoney("cash")) or 0
    end

    function Framework.hasMoney(source, amount)
        return Framework.getCash(source) >= (tonumber(amount) or 0)
    end

    function Framework.removeMoney(source, amount, reason)
        local player = Framework.getPlayer(source)
        amount = tonumber(amount) or 0
        if not player or amount < 0 or Framework.getCash(source) < amount then return false end
        player.Functions.RemoveMoney("cash", amount, reason or "blackjack")
        return true
    end

    function Framework.addMoney(source, amount, reason)
        local player = Framework.getPlayer(source)
        amount = tonumber(amount) or 0
        if not player or amount < 0 then return false end
        player.Functions.AddMoney("cash", amount, reason or "blackjack")
        return true
    end
elseif Config and (Config.Framework == "VORP" or Config.Framework == "vorp" or Config.Framework == "Vorp") then
    local VORPcore = exports.vorp_core and exports.vorp_core.GetCore and exports.vorp_core:GetCore() or nil

    local function getCharacter(source)
        if not VORPcore or not source then return nil end
        local user = VORPcore.getUser and VORPcore.getUser(source) or nil
        return user and user.getUsedCharacter or nil
    end

    function Framework.getPlayer(source)
        return getCharacter(source)
    end

    function Framework.getName(source)
        if Config.DisplayName == "account" then
            return GetPlayerName(source)
        end

        local character = getCharacter(source)
        local first = character and (character.firstname or character.firstName)
        local last = character and (character.lastname or character.lastName)
        if first and last then return ("%s %s"):format(first, last) end
        return first and tostring(first) or GetPlayerName(source)
    end

    function Framework.getCash(source)
        local character = getCharacter(source)
        return character and (tonumber(character.money) or 0) or 0
    end

    function Framework.hasMoney(source, amount)
        return Framework.getCash(source) >= (tonumber(amount) or 0)
    end

    function Framework.removeMoney(source, amount, reason)
        local character = getCharacter(source)
        amount = tonumber(amount) or 0
        if not character or amount < 0 or Framework.getCash(source) < amount then return false end
        if character.removeCurrency then character.removeCurrency(0, amount) return true end
        if character.subMoney then character.subMoney(amount) return true end
        if character.removeMoney then character.removeMoney(amount) return true end
        return false
    end

    function Framework.addMoney(source, amount, reason)
        local character = getCharacter(source)
        amount = tonumber(amount) or 0
        if not character or amount < 0 then return false end
        if character.addCurrency then character.addCurrency(0, amount) return true end
        if character.addMoney then character.addMoney(amount) return true end
        return false
    end
else
    print(("[Nt_BlackJack] Unsupported Config.Framework: %s"):format(tostring(Config and Config.Framework)))

    function Framework.getPlayer() return nil end
    function Framework.getName(source) return GetPlayerName(source) end
    function Framework.getCash() return 0 end
    function Framework.hasMoney() return false end
    function Framework.removeMoney() return false end
    function Framework.addMoney() return false end
end
