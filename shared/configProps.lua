ConfigProps = {}

-- Entity-attached props use a bone attachment instead of a world origin.
ConfigProps.DealerHand = {
    model = "p_cardssplit01x_rrs",
    attachment = {
        bone = "SKEL_L_Hand",
        x = 0.10,
        y = 0.02,
        z = 0.06,
        rx = -50.0,
        ry = -60.0,
        rz = 10.0,
    },
}

-- World props all use the same format:
-- relativeTo: "dealer" or "player"
-- seatIndex: optional seat restriction for player props
-- showWhen: "always", "dealer_cards", "player_cards", "player_bet", or "player_payout"
-- offset: x = forward, y = right, z = up, h = heading offset
-- rx/ry/rz are optional and support props that need full 3-axis rotation.
ConfigProps.Props = {
    TableCaddy = {
        model = "p_pokercaddy02x",
        relativeTo = "dealer",
        showWhen = "always",
        offset = { x = 0.59075, y = 0.45263, z = 0.28342, h = -0.00003, rx = 0.00000, ry = 0.00000, rz = -0.00002 },
    },
    CaddyChipsWhite = {
        model = "prop_chip_white_x10",
        relativeTo = "dealer",
        showWhen = "always",
        offset = { x = 0.52597, y = 0.32494, z = 0.33080, h = 10.07230, rx = -89.76761, ry = 174.47112, rz = 172.31722 }
    },
    CaddyChipsRed = {
        model = "prop_chip_red_x10",
        relativeTo = "dealer",
        showWhen = "always",
        offset = { x = 0.52597, y = 0.38594, z = 0.33080, h = 10.07230, rx = -89.76761, ry = 174.47112, rz = 172.31722 }
    },
    CaddyChipsGreen = {
        model = "prop_chip_green_x8",
        relativeTo = "dealer",
        showWhen = "always",
        offset = { x = 0.52597, y = 0.45594, z = 0.33080, h = 10.07230, rx = -89.76761, ry = 174.47112, rz = 172.31722 }
    },
    DealerCard1 = {
        relativeTo = "dealer",
        showWhen = "dealer_cards",
        offset = { x = 0.75, y = -0.07541, z = 0.30622, h = -0.00003, rx = 0.00000, ry = 0.00000, rz = -0.00002  },
    },
    DealerCard2 = {
        relativeTo = "dealer",
        showWhen = "dealer_cards",
        offset = { x = 0.75, y = -0.15, z = 0.30622, h = -0.00003, rx = 0, ry = 0, rz = -0.00002 },
    },
    PlayerCard1 = {
        relativeTo = "player",
        showWhen = "player_cards",
        offset = { x = 0.8, y = 0.04, z = 0.30622, h = -0.00003, rx = 0.00000, ry = 0, rz = -0.00002 },
    },
    PlayerCard2 = {
        relativeTo = "player",
        showWhen = "player_cards",
        offset = { x = 0.8, y = 0.11, z = 0.30622, h = -0.00003, rx = 0.00000, ry = 0, rz = -0.00002 },
    },
    PlayerBetSet1 = {
        model = "prop_chip_white_x1",
        relativeTo = "player",
        seatIndex = 1,
        showWhen = "player_bet",
        offset = { x = 0.68, y = 0.01, z = 0.30373, h = -0.00003, rx = 0.00000, ry = 0.00000, rz = -0.00002 },
    },
    PlayerBetSet2 = {
        model = "prop_chip_white_x1",
        relativeTo = "player",
        seatIndex = 2,
        showWhen = "player_bet",
        offset = { x = 0.67, y = -0.04, z = 0.30373, h = -0.00003, rx = 0.00000, ry = 0.00000, rz = -0.00002 },
    },
    PlayerBetSet3 = {
        model = "prop_chip_white_x1",
        relativeTo = "player",
        seatIndex = 3,
        showWhen = "player_bet",
        offset = { x = 0.66, y = -0.04, z = 0.30373, h = -0.00003, rx = 0.00000, ry = 0.00000, rz = -0.00002 },
    },
    PlayerBetSet4 = {
        model = "prop_chip_white_x1",
        relativeTo = "player",
        seatIndex = 4,
        showWhen = "player_bet",
        offset = { x = 0.66, y = -0.04, z = 0.30373, h = -0.00003, rx = 0.00000, ry = 0.00000, rz = -0.00002 },
    },
    DealerPayOffset = {
        model = "prop_chip_white_x1",
        relativeTo = "player",
        showWhen = "player_payout",
        offset = { x = 0.75, y = -0.07541, z = 0.31109, h = -0.00003, rx = 0.00000, ry = 0.00000, rz = -0.00002 },
    },
}

ConfigProps.Cards = {
    cardHeader = "p_crd_",
    cardEndings = {
        ["Blackwater"] = "01x_bla",
        ["Valentine"] = "01x_val",
        ["Saint Denis"] = "01x_std_labastille",
        ["Rhodes"] = "01x_rho",
        ["Camp"] = "01x_camp",
        ["Vanhorn"] = "01x_van",
        ["RRS"] = "01x_rrs",
        --["GK"] = "01x_tgk",
        ["New"] = "01x_new",
    },
    DeckHeader = "p_cardssplit01x_",
    DeckEndings = {
        ["Blackwater"] = "bla",
        ["Valentine"] = "val",
        ["Saint Denis"] = "std_labastille",
        ["Rhodes"] = "rho",
        ["Camp"] = "camp",
        ["Vanhorn"] = "van",
        ["RRS"] = "rrs",
        --["GK"] = "tgk",
        ["New"] = "new",
    },
    HitOffset = { x = 0.025, y = 0.05, z = 0.001, h = 0.0 }, -- use card 2 offset and adds this to the hit card.
    DealerHitOffset = { x = 0.15, y = 0.05, z = 0.001, h = 0.0 }, -- use card 2 offset and adds this to the hit card.
    SplitOffset = { x = 0.10, y = 0, z = 0.001, h = 0.0 },
}
