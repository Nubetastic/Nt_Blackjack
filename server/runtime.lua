CreateThread(function()
    while ServerRunning do
        for tableId, game in pairs(ServerGames) do
            if ServerGames[tableId] == game then ProcessGameTimers(game) end
            if ServerGames[tableId] == game then ProcessGameCommands(game) end
            if ServerGames[tableId] == game then ProcessGameState(game) end
        end
        Wait(100)
    end
end)
