Config = {}

Config.Debug = false
Config.Framework = "RSG" -- Supported: "RSG" or "Vorp"
Config.DisplayName = "account" -- "account" or "character"
Config.InteractionDistance = 2.5
Config.SpawnDistance = 40
Config.BettingTimeoutSeconds = 60
Config.ActionTimeoutSeconds = 60
Config.BetweenHandsWaitMs = 10000

Config.Spectator = {
    Distance = 30.0,
    NearDistance = 50.0,
    MediumDistance = 200.0,
    NearWait = 1000,
    MediumWait = 10000,
    FarWait = 30000,
}

Config.NPCPlayers = {
    Enabled = true,
    JoinAtStartChance = 90,
    JoinBetweenHandsChance = 60,
    LeaveBetweenHandsChance = 30,
    MinSeatsOpen = 1,
    MaxPlayersPerTable = 2,
    MaxJoinPerCheck = 1,
    MinHandsToStay = 2,
    MaxHandsToStay = 5,
    KickForPlayerJoin = true,
    MinBet = 2,
    MaxBet = 20,
    StandValue = 17,
    ActionDelayMs = 1200,
    MaleNames = {
        "Arthur", "Benjamin", "Caleb", "Charles", "Daniel", "Elias", "Emmett", "Ezra",
        "Franklin", "George", "Henry", "Isaac", "Jasper", "Jesse", "Levi", "Nathaniel",
        "Samuel", "Silas", "Theodore", "Walter",
    },
    FemaleNames = {
        "Abigail", "Alice", "Beatrice", "Caroline", "Clara", "Edith", "Eleanor", "Elizabeth",
        "Emma", "Esther", "Florence", "Grace", "Josephine", "Louisa", "Margaret", "Martha",
        "Matilda", "Rose", "Sarah", "Violet",
    },
}

Config.FemaleOffset = .05 -- Z offset.


Config.Keys = {
    Join = "INPUT_CONTEXT_X", -- R
}

Config.Rules = {
    MinBet = 2,
    MaxBet = 100,
    BetStep = 2, -- Even bets keep 3:2 blackjack payouts in whole dollars.
    DeckCount = 1,
    ReshuffleAfterHands = 5,
    MinimumCardsBeforeHand = 20,
    BlackjackPayout = 1.5,
    DealerHitsSoft17 = false,
    DealerPeek = true,
    AllowDouble = true,
    AllowSplit = true,
    MaxSplitHands = 2,
}

Config.Blip = {
    Enabled = true,
    Sprite = "blip_mg_blackjack",
    Scale = 0.8,
    Label = "Blackjack",
}

Config.Tables = {
    ["Rhodes Parlour House"] = {
        Enabled = true,
        Label = "Blackjack Table",
        Table = {
            Coords = vector3(1340.45, -1371.79, 83.29),
        },
        Dealer = {
            Coords = vector4(1338.5978, -1371.9944, 83.7909, 259.9999),
            Model = "u_m_m_bht_saintdenissaloon",
        },
        -- The native Blackjack dealer animation set targets seats 01-04.
        MaxPlayers = 4,
        Seats = {
            [1] = { Coords = vector4(1339.9227, -1370.9707, 83.7909, 147.5000) },
            [2] = { Coords = vector4(1340.5065, -1371.8048, 83.7909, 102.5000)},
            [3] = { Coords = vector4(1340.3120, -1372.8354, 83.7909, 57.5000)},
            [4] = { Coords = vector4(1339.4626, -1373.4347, 83.7909, 12.4999) },
        },
        -- World props are configured in ConfigProps.Props.
        NPCScanArea = { -- poly zone
            vector3(1339.2565, -1368.6121, 81.9910),
            vector3(1337.4105, -1379.8352, 82.0610),
            vector3(1354.9501, -1383.1567, 82.1381),
            vector3(1356.9119, -1371.8439, 82.0980),
        },
    },
    ["Blackwater"] = {
        Enabled = true,
        Label = "Blackjack Table",
        Table = {
            Coords = vector3(-813.3864, -1324.1777, 48.7328),
        },
        Dealer = {
            Coords = vector4(-813.2962, -1323.2572, 47.3868, 180.4352),
            Model = "u_m_m_bht_saintdenissaloon",
        },
        -- The native Blackjack dealer animation set targets seats 01-04.
        MaxPlayers = 4,
        Seats = {
            [1] = { Coords = vector4(-812.0296, -1324.4032, 47.3868, 70.0301) },
            [2] = { Coords = vector4(-812.7511, -1325.1329, 47.3868, 25.0302)},
            [3] = { Coords = vector4(-813.8160, -1325.1427, 47.3868, 340.0301)},
            [4] = { Coords = vector4(-814.5717, -1324.4141, 47.3868, 296.4795) },
        },
        -- World props are configured in ConfigProps.Props.
        NPCScanArea = { -- poly zone
            vector3(-811.4205, -1312.4879, 45.0698),
            vector3(-808.8923, -1327.2257, 45.5134),
            vector3(-826.2944, -1312.0153, 47.5608),
            vector3(-826.0157, -1326.4695, 49.2345),
        },
    },
    ["Vanhorn"] = {
        Enabled = true,
        Label = "Blackjack Table",
        Table = {
            Coords = vector3(2937.87, 520.10, 44.35),
        },
        Dealer = {
            Coords = vector4(2937.8179, 520.0856, 44.8403, 307.1100),
            Model = "u_m_m_bht_saintdenissaloon",
        },
        -- The native Blackjack dealer animation set targets seats 01-04.
        MaxPlayers = 4,
        Seats = {
            [1] = { Coords = vector4(2937.9453, 521.7375, 44.8403, 196.7052) },
            [2] = { Coords = vector4(2938.9089, 521.5120, 44.8403, 151.7053)},
            [3] = { Coords = vector4(2939.5730, 520.7540, 44.8403, 106.7052)},
            [4] = { Coords = vector4(2939.4490, 519.7324, 44.8403, 63.1545) },
        },
        -- World props are configured in ConfigProps.Props.
        NPCScanArea = { -- poly zone
            vector3(2936.9790, 518.5540, 47.1008),
            vector3(2936.4080, 527.8134, 46.9460),
            vector3(2947.4731, 527.8519, 47.0849),
            vector3(2950.8499, 517.0051, 46.9144),
        },
    },
}

-- Native Blackjack clips are used where they work safely as standalone
-- TaskPlayAnim flair. Poker remains the seated idle/check fallback because
-- Rockstar's other player clips expect its synchronized scene and props.

Config.AnimationTime = 2000 -- added to each animation time for latency.
Config.NextPlayerDelay = 2000 -- added as a delay when switching from one player to the next.

-- Prop timing values ending in "At" are normalized animation positions from 0.0 to 1.0.
Config.Animations = {
    PlayerIdle = {
        Dict = "mini_games@blackjack_mg@player@base",
        Name = "idle_a",
        Idle = true,
        time = 0,
    },
    PlayerBet = {
        Dict = "mini_games@blackjack_mg@player@base",
        Name = "bet_ins",
        time = 2300,
        ShowBetAt = 0.50,
    },
    PlayerHit = {
        Dict = "mini_games@blackjack_mg@player@base",
        Name = "hit_lh_a",
        time = 1000,
        DealDelay = 500,
    },
    PlayerStand = {
        Dict = "mini_games@blackjack_mg@player@base",
        Name = "stand_rh_a",
        time = 2200,
    },
    DealerIdle = {
        Dict = "mini_games@blackjack_mg@dealer@self@idle",
        Name = "idle",
        Idle = true,
        time = 0,
        HasCards = true,
    },
    DealerDeal = {
        Dict = "mini_games@blackjack_mg@dealer@actions@deal",
        Name = "deal_",
        Self = {
            Dict = "mini_games@blackjack_mg@dealer@self@hit",
            Name = "03",
        },
        time = 1000,
        DealCardAt = 0.4,
        HasCards = true,
    },
    DealerInitialDeal = {
        Dict = "mini_games@blackjack_mg@dealer@actions@deal_end_in_self",
        Name = "deal_",
        time = (4800/3), -- Per participant, including the dealer.
        HasCards = true,
    },
    DealerReveal = {
        Dict = "mini_games@blackjack_mg@dealer@self@hit",
        Name = "reveal",
        time = 700,
        RevealCardAt = 0.6,
        HasCards = true,
    },
    DealerCollect = {
        Dict = "mini_games@blackjack_mg@dealer@actions@retrieve_bets",
        Name = "loss_",
        time = 2200,
        HasCards = true,
    },
    DealerPayout = {
        Dict = "mini_games@blackjack_mg@dealer@actions@pay_bets",
        -- Winning seat numbers are appended in order, e.g. win_13 or win_234.
        Name = "win_",
        time = 1700,
        HasCards = true,
    },
    DealerRetrieveCards = {
        Dict = "mini_games@blackjack_mg@dealer@actions@retrieve_cards",
        Name = "retrieve_",
        time = 2433,
        CleanCardsAt = 0.50,
        HasCards = true,
    },
    DealerShuffle = {
        Dict = "mini_games@blackjack_mg@dealer@actions@shuffle",
        Name = "standard_shuffle",
        time = 2333,
        HasCards = true,
    },
}

-- Cached reference deck. Gameplay must copy this table and never remove from it.
Config.FullDeck = {}
local suits = { "c", "d", "h", "s" }
local royalties = { "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A" }
local cardId = 1
for _, suit in ipairs(suits) do
    for _, royalty in ipairs(royalties) do
        Config.FullDeck[#Config.FullDeck + 1] = {
            id = cardId,
            suit = suit,
            royalty = royalty,
        }
        cardId = cardId + 1
    end
end
