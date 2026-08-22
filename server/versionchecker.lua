-- Drop-in version checker for Nt_ resources.
-- Each GitHub repository must have the same name as its resource folder and use
-- the main branch. The version is read from the `version` entry in fxmanifest.lua.

local githubRoot = 'https://raw.githubusercontent.com/Nubetastic'

local resourceName = GetCurrentResourceName()
local currentVersion = GetResourceMetadata(resourceName, 'version', 0)
local manifestUrl = ('%s/%s/main/fxmanifest.lua'):format(githubRoot, resourceName)
local repositoryUrl = ('https://github.com/Nubetastic/%s'):format(resourceName)

local function versionCheckPrint(kind, message)
    local color = kind == 'success' and '^2' or '^1'
    print(('^5[%s] %s%s^7'):format(resourceName, color, message))
end

local function checkVersion()
    if not currentVersion or currentVersion == '' then
        versionCheckPrint('error', "No 'version' entry was found in fxmanifest.lua.")
        return
    end

    PerformHttpRequest(manifestUrl, function(statusCode, response)
        if statusCode ~= 200 or not response then
            versionCheckPrint('error', ('Version check failed (HTTP %s).'):format(statusCode or 'unknown'))
            return
        end

        -- Prefix a newline so this also works when `version` is the first line.
        -- Anchoring to a line prevents this from matching `fx_version`.
        local latestVersion = ('\n' .. response):match("[\r\n]%s*version%s*['\"]([^'\"]+)['\"]")

        if not latestVersion then
            versionCheckPrint('error', "The remote fxmanifest.lua has no readable 'version' entry.")
            return
        end

        if latestVersion == currentVersion then
            versionCheckPrint('success', ('Version %s is up to date.'):format(currentVersion))
        else
            versionCheckPrint('error', ('Version %s is outdated. Latest: %s - %s'):format(
                currentVersion,
                latestVersion,
                repositoryUrl
            ))
        end
    end, 'GET')
end

checkVersion()
