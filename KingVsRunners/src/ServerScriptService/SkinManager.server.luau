local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local getPlayerSkin = ReplicatedStorage:WaitForChild("GetPlayerSkin")
local setPlayerSkin = ReplicatedStorage:WaitForChild("SetPlayerSkin")

-- 스킨 데이터베이스: 아이템별 사용 가능한 스킨 목록
local SKIN_DATABASE = {
    ItemNoob = {
        -- ── Normal (색놀이, 무지개 순) ──
        {
            skinName    = "OrangeNoob",
            displayName = "Orange Noob",
            icon        = "",
            rarity      = "Normal",
            material = "Plastic", color = {255, 130, 20},
        },
        {
            skinName    = "YellowNoob",
            displayName = "Yellow Noob",
            icon        = "",
            rarity      = "Normal",
            material = "Plastic", color = {255, 225, 30},
        },
        {
            skinName    = "GreenNoob",
            displayName = "Green Noob",
            icon        = "",
            rarity      = "Normal",
            material = "Plastic", color = {70, 200, 70},
        },
        {
            skinName    = "BlueNoob",
            displayName = "Blue Noob",
            icon        = "",
            rarity      = "Normal",
            material = "Plastic", color = {40, 120, 255},
        },
        {
            skinName    = "IndigoNoob",
            displayName = "Indigo Noob",
            icon        = "",
            rarity      = "Normal",
            material = "Plastic", color = {80, 60, 200},
        },
        {
            skinName    = "VioletNoob",
            displayName = "Violet Noob",
            icon        = "",
            rarity      = "Normal",
            material = "Plastic", color = {170, 70, 220},
        },
        -- ── Rare ──
        {
            skinName    = "LavaNoob",
            displayName = "Lava Noob",
            icon        = "",  -- 3D 뷰포트로 표시(다른 뉴비와 동일)
            rarity      = "Rare",
        },
        {
            skinName    = "SuitNoob",
            displayName = "Suit Noob",
            icon        = "",
            rarity      = "Rare",
        },
        {
            skinName    = "ZombieNoob",
            displayName = "Zombie Noob",
            icon        = "",
            rarity      = "Rare",
        },
        {
            skinName    = "SoldierNoob",
            displayName = "Soldier Noob",
            icon        = "",
            rarity      = "Rare",
        },
        {
            skinName    = "RainbowNoob",
            displayName = "Rainbow Noob",
            icon        = "",
            rarity      = "Rare",
        },
        -- ── Epic ──
        {
            skinName    = "IceNoob",
            displayName = "Ice Noob",
            icon        = "",
            rarity      = "Epic",
        },
        {
            skinName    = "GlitchNoob",
            displayName = "Glitch Noob",
            icon        = "",
            rarity      = "Epic",
        },
        {
            skinName    = "KingNoob",
            displayName = "King Noob",
            icon        = "",
            rarity      = "Epic",
        },
        {
            skinName    = "SummerNoob",
            displayName = "Summer Noob",
            icon        = "",
            rarity      = "Epic",
        },
        -- ── Legendary ──
        {
            skinName    = "GoldNeonNoob",
            displayName = "Gold Neon Noob",
            icon        = "",  -- 나중에 아이콘 추가
            rarity      = "Legendary",
        },
        -- 나중에 더 추가 가능
    },
    tsunami = {
        -- Rainbow만 별도 카드(순환). 단색/금색은 ITEM COLOR(NoobColorPalette.ITEMS.tsunami)로 통합.
        { skinName = "RainbowTsunami", displayName = "Rainbow Tsunami", icon = "", rarity = "Rare", material = "Neon", color = {255, 40, 40}, cycle = true },
        { skinName = "LavaTsunami", displayName = "Lava Tsunami", icon = "", rarity = "Rare", meshTexture = "rbxassetid://118462674053285", color = {255, 100, 20} },
    },
    tox_box = {
        -- Rainbow만 별도 카드(순환). 단색/금색은 ITEM COLOR(NoobColorPalette.ITEMS.tox_box)로 통합.
        { skinName = "RainbowToxBox", displayName = "Rainbow ToxBox", icon = "", rarity = "Rare", material = "Neon", color = {255, 40, 40}, cycle = true },
    },
    tnt = {
        -- Rainbow만 별도 카드(순환). 단색은 ITEM COLOR(NoobColorPalette.ITEMS.tnt)로 통합.
        { skinName = "RainbowBomb", displayName = "Rainbow Bomb", icon = "", rarity = "Rare", material = "Neon", color = {255, 40, 40}, cycle = true },
    },
    Demonspear = {
        -- Rainbow만 별도 카드(본체 Neon + Beam 빨강 keypoint 순환, 검정 유지). 단색/금색은 ITEM COLOR.
        { skinName = "RainbowDemonSpear", displayName = "Rainbow Demon Spear", icon = "", rarity = "Rare", material = "Neon", color = {255, 40, 40}, cycle = true },
    },
    ["Wood Log"] = {
        {
            skinName    = "SpikedWood",
            displayName = "Spiked Wood",
            icon        = "",  -- 나중에 아이콘 추가
            rarity      = "Epic",
        },
        {
            skinName    = "GoldenLog",
            displayName = "Golden Log",
            icon        = "",  -- 나중에 아이콘 추가
            rarity      = "Legendary",
        },
    },
    -- ── 아이템 스킨: stone 색놀이 (Part Ball Shape, 색만 다름) ──
    -- 베이스 stone Part + material/color로 칠함(모델교체 → 색칠 통합). MeshPart 아니라 텍스처 처리 불필요.
    -- Rainbow/Lava/DemonFlame/Sun/BeachBall은 이펙트·형태가 달라 색 데이터 없음 → ItemSpawnHandler가 모델교체로 폴백.
    stone = {
        {
            skinName    = "GoldStone",
            displayName = "Gold Stone",
            icon        = "",  -- 나중에 아이콘 추가
            rarity      = "Epic",
            material = "Metal", color = {212, 175, 55},
        },
        {
            skinName    = "SilverStone",
            displayName = "Silver Stone",
            icon        = "",  -- 나중에 아이콘 추가
            rarity      = "Epic",
            material = "Metal", color = {200, 200, 205},
        },
        {
            skinName    = "RainbowStone",
            displayName = "Rainbow Stone",
            icon        = "",  -- 나중에 아이콘 추가
            rarity      = "Rare",
        },
        {
            skinName    = "LavaStone",
            displayName = "Lava Stone",
            icon        = "",  -- 나중에 아이콘 추가
            rarity      = "Rare",
        },
        {
            skinName    = "DemonFlameStone",
            displayName = "Demon Flame Stone",
            icon        = "",  -- 나중에 아이콘 추가
            rarity      = "Epic",
        },
        {
            skinName    = "SunStone",
            displayName = "Sun Stone",
            icon        = "",  -- 나중에 아이콘 추가
            rarity      = "Legendary",
        },
        {
            skinName    = "PinkStone",
            displayName = "Pink Stone",
            icon        = "",
            rarity      = "Normal",
            material = "SmoothPlastic", color = {230, 130, 175},
        },
        {
            skinName    = "BlueStone",
            displayName = "Blue Stone",
            icon        = "",
            rarity      = "Normal",
            material = "SmoothPlastic", color = {75, 130, 215},
        },
        {
            skinName    = "GreenStone",
            displayName = "Green Stone",
            icon        = "",
            rarity      = "Normal",
            material = "SmoothPlastic", color = {95, 185, 110},
        },
        {
            skinName    = "BeachBall",
            displayName = "Beach Ball",
            icon        = "",  -- 나중에 아이콘 추가 (여름 시즌)
            rarity      = "Epic",
        },
    },
    -- ── 무기 스킨: Spear 색놀이 (단일 MeshId 8865000365, 색만 다름) ──
    -- 베이스 메시 1개 + material/color 데이터로 칠함(모델교체 → 색칠 통합 완료).
    -- RainbowSpear는 오비터+트레일 이펙트라 색 데이터 없음 → SpearSystem이 모델교체로 폴백.
    Spear = {
        {
            skinName    = "GoldSpear",
            displayName = "Gold Spear",
            icon        = "",  -- 나중에 아이콘 추가
            rarity      = "Epic",
            material = "Metal", color = {212, 175, 55},
        },
        {
            skinName    = "SilverSpear",
            displayName = "Silver Spear",
            icon        = "",
            rarity      = "Epic",
            material = "Metal", color = {195, 195, 205},
        },
        {
            skinName    = "PinkSpear",
            displayName = "Pink Spear",
            icon        = "",
            rarity      = "Normal",
            material = "Neon", color = {255, 105, 180},
        },
        {
            skinName    = "BlueSpear",
            displayName = "Blue Spear",
            icon        = "",
            rarity      = "Normal",
            material = "Neon", color = {40, 90, 220},
        },
        {
            skinName    = "GreenSpear",
            displayName = "Green Spear",
            icon        = "",
            rarity      = "Normal",
            material = "Neon", color = {40, 190, 80},
        },
        {
            skinName    = "BlackSpear",
            displayName = "Black Spear",
            icon        = "",
            rarity      = "Normal",
            material = "Metal", color = {30, 30, 38},
        },
        {
            skinName    = "RainbowSpear",
            displayName = "Rainbow Spear",
            icon        = "",
            rarity      = "Rare",
            -- 이펙트 스킨(오비터+트레일): 색 데이터 없음 → 적용부에서 모델교체 폴백
        },
    },
    bear_trap = {
        {
            skinName    = "GoldBearTrap",
            displayName = "Gold Bear Trap",
            icon        = "",
            rarity      = "Epic",
            material = "Metal", color = {255, 200, 40},
        },
        {
            skinName    = "CrimsonBearTrap",
            displayName = "Crimson Bear Trap",
            icon        = "",
            rarity      = "Epic",
            material = "Metal", color = {200, 20, 20},
        },
        {
            skinName    = "ToxicBearTrap",
            displayName = "Toxic Bear Trap",
            icon        = "",
            rarity      = "Epic",
            material = "Neon", color = {40, 255, 130},
        },
        {
            skinName    = "ObsidianBearTrap",
            displayName = "Obsidian Bear Trap",
            icon        = "",
            rarity      = "Epic",
            material = "Glass", color = {40, 10, 60},
        },
        {
            skinName    = "CobaltBearTrap",
            displayName = "Cobalt Bear Trap",
            icon        = "",
            rarity      = "Epic",
            material = "Metal", color = {30, 70, 200},
        },
        {
            skinName    = "DeepPurpleBearTrap",
            displayName = "Deep Purple Bear Trap",
            icon        = "",
            rarity      = "Epic",
            material = "Metal", color = {95, 30, 170},
        },
        {
            skinName    = "EmeraldBearTrap",
            displayName = "Emerald Bear Trap",
            icon        = "",
            rarity      = "Epic",
            material = "Metal", color = {15, 145, 85},
        },
        {
            skinName    = "BronzeBearTrap",
            displayName = "Bronze Bear Trap",
            icon        = "",
            rarity      = "Epic",
            material = "Metal", color = {150, 95, 40},
        },
        {
            skinName    = "RedBearTrap",
            displayName = "Red Bear Trap",
            icon        = "",
            rarity      = "Normal",
            material = "SmoothPlastic", color = {230, 30, 30},
        },
        {
            skinName    = "OrangeBearTrap",
            displayName = "Orange Bear Trap",
            icon        = "",
            rarity      = "Normal",
            material = "SmoothPlastic", color = {245, 140, 20},
        },
        {
            skinName    = "YellowBearTrap",
            displayName = "Yellow Bear Trap",
            icon        = "",
            rarity      = "Normal",
            material = "SmoothPlastic", color = {245, 225, 30},
        },
        {
            skinName    = "GreenBearTrap",
            displayName = "Green Bear Trap",
            icon        = "",
            rarity      = "Normal",
            material = "SmoothPlastic", color = {40, 190, 60},
        },
        {
            skinName    = "BlueBearTrap",
            displayName = "Blue Bear Trap",
            icon        = "",
            rarity      = "Normal",
            material = "SmoothPlastic", color = {40, 110, 235},
        },
        {
            skinName    = "VioletBearTrap",
            displayName = "Violet Bear Trap",
            icon        = "",
            rarity      = "Normal",
            material = "SmoothPlastic", color = {150, 50, 200},
        },
        {
            skinName    = "RainbowBearTrap",
            displayName = "Rainbow Bear Trap",
            icon        = "",
            rarity      = "Rare",
        },
    },
    -- ── 무기 스킨: Classic Sword 색놀이 8종 (네온 팔레트 스왑) ──
    -- 모델 없이 색/재질만 데이터로 담음. 스폰 시 Handle에 Material/Color 입힘.
    -- cycle=true 이면 무지개 순환(클라에서 Hue 회전).
    ClassicSword = {
        {
            skinName = "RedSword", displayName = "Red Sword", icon = "", rarity = "Normal",
            material = "Neon", color = {255, 40, 40},
        },
        {
            skinName = "OrangeSword", displayName = "Orange Sword", icon = "", rarity = "Normal",
            material = "Neon", color = {255, 140, 20},
        },
        {
            skinName = "YellowSword", displayName = "Yellow Sword", icon = "", rarity = "Normal",
            material = "Neon", color = {255, 240, 50},
        },
        {
            skinName = "GreenSword", displayName = "Green Sword", icon = "", rarity = "Normal",
            material = "Neon", color = {50, 230, 70},
        },
        {
            skinName = "BlueSword", displayName = "Blue Sword", icon = "", rarity = "Normal",
            material = "Neon", color = {40, 120, 255},
        },
        {
            skinName = "IndigoSword", displayName = "Indigo Sword", icon = "", rarity = "Normal",
            material = "Neon", color = {75, 0, 200},
        },
        {
            skinName = "VioletSword", displayName = "Violet Sword", icon = "", rarity = "Normal",
            material = "Neon", color = {200, 60, 255},
        },
        {
            skinName = "RainbowCycleSword", displayName = "Rainbow Cycle Sword", icon = "", rarity = "Rare",
            material = "Neon", cycle = true,
        },
        { skinName = "PoolNoodle", displayName = "Pool Noodle", icon = "", rarity = "Epic", vfxAttachment = "PoolNoodleVFX" },
        -- 모델 교체 스킨: Handle 투명화 + ServerStorage.WeaponSkins.FrozenSword 메시 용접(정렬값 데이터). 스윙 시 눈송이.
        { skinName = "FrozenSword", displayName = "Frozen Sword", icon = "rbxassetid://133834377655975", rarity = "Epic",
          meshSwap = "FrozenSword", swapScale = 2.8209, swapOffset = {0, -0.1, 0}, swapRot = {0, 90, 270}, swingSnow = true },
    },

    -- Weapon skin: Diamond Blade (runner) -- Ice Crystal Blade mesh-swap (Legendary).
    ["DiamondBladeSword"] = {
        { skinName = "IceCrystalBlade", displayName = "Ice Crystal Blade", icon = "rbxassetid://139198284240501", rarity = "Legendary",
          meshSwap = "IceCrystalBlade", swapScale = 3.0, swapOffset = {0.1, -0.7, -0.05}, swapRot = {0, 0, 180}, iceMarks = true },
    },

    -- Weapon skin: Gauntlet (tagger) -- Mech Gauntlet mesh-swap (Legendary).
    ["Gauntlet"] = {
        { skinName = "MechGauntlet", displayName = "Mech Gauntlet", icon = "rbxassetid://136738014500673", rarity = "Legendary",
          meshSwap = "MechGauntlet", swapScale = 1.0, swapOffset = {0, 0, 0}, swapRot = {-90, 0, 0} },
    },

    -- ── 무기 스킨: PushTool(태거 밀쳐내기) 색놀이 ──
    -- Handle은 텍스처 없는 흰색 펀치 글러브 MeshPart → .Color 틴트 깨끗. 무지개 스펙트럼 7색 + 순환.
    PushTool = {
        { skinName = "RedFist",     displayName = "Red Fist",     icon = "", rarity = "Normal", material = "Neon", color = {255, 40, 40} },
        { skinName = "OrangeFist",  displayName = "Orange Fist",  icon = "", rarity = "Normal", material = "Neon", color = {255, 140, 20} },
        { skinName = "YellowFist",  displayName = "Yellow Fist",  icon = "", rarity = "Normal", material = "Neon", color = {255, 240, 50} },
        { skinName = "GreenFist",   displayName = "Green Fist",   icon = "", rarity = "Normal", material = "Neon", color = {48, 200, 66} },
        { skinName = "BlueFist",    displayName = "Blue Fist",    icon = "", rarity = "Normal", material = "Neon", color = {40, 120, 255} },
        { skinName = "VioletFist",  displayName = "Violet Fist",  icon = "", rarity = "Normal", material = "Neon", color = {160, 70, 235} },
        { skinName = "PinkFist",    displayName = "Pink Fist",    icon = "", rarity = "Normal", material = "Neon", color = {255, 95, 200} },
        { skinName = "RainbowFist", displayName = "Rainbow Cycle Fist", icon = "", rarity = "Rare", material = "Neon", cycle = true },
        { skinName = "BlackHoleFist", displayName = "Black Hole Fist", icon = "", rarity = "Epic", material = "Neon", color = {45, 10, 75}, vfxAttachment = "BlackHoleVFX" },
        { skinName = "WatermelonFist", displayName = "Watermelon Slice", icon = "", rarity = "Epic", vfxAttachment = "WatermelonSliceVFX" },
        -- mesh-swap skins (glitch/cursor hand): replace Handle mesh with WeaponSkins model.
        { skinName = "GlitchFist", displayName = "Glitch Hand", icon = "rbxassetid://79840900527115", rarity = "Epic",
          meshSwap = "GlitchFist", swapScale = 0.8, swapOffset = {0, 0, 0}, swapRot = {0, 0, 0} },
        { skinName = "CursorFist", displayName = "Cursor Hand", icon = "rbxassetid://133083959036643", rarity = "Normal",
          meshSwap = "CursorFist", swapScale = 0.22, swapOffset = {0, 0, 0}, swapRot = {-90, 0, 180} },
        -- Vishnu (Legendary): 등 뒤 황금 광배 + 4팔, 원본 양팔 숨김, 푸시/그랩 시 4팔 중 랜덤 스윙. 전용 시스템(_VishnuAuraSystem)이 처리.
        { skinName = "Vishnu", displayName = "Ascendant", icon = "rbxassetid://81090182820271", rarity = "Legendary", vishnuAura = true },
    },

    -- Item skin: Speed Potion (runner consumable) form-swap (bottle -> coconut)
    ["Speed Potion"] = {
        { skinName = "Coconut", displayName = "Coconut Juice", icon = "", rarity = "Epic", vfxAttachment = "CoconutJuiceVFX", potionFxColor = {150, 225, 110}, potionSoundId = "rbxassetid://133347729618467" },
        { skinName = "Cup", displayName = "Coffee", icon = "", rarity = "Epic", vfxAttachment = "CupVFX", potionFxColor = {110, 65, 30}, beanFxId = "rbxassetid://133273413210893" },
    },

    -- Tagger item skin: Wooden Barrel — 모델 교체형(Crusader). 색놀이(커스텀)와 별개 트랙.
    ["Wooden Barrel"] = {
        { skinName = "CrusaderBarrel", displayName = "Crusader Barrel", icon = "", rarity = "Legendary", meshSwapModel = true },
        { skinName = "OilDrum", displayName = "Oil Drum", icon = "", rarity = "Epic", meshSwapModel = true },
    },

    -- Item skin: Revival Flag (runner consumable) form-swap (flag -> palm tree)
    ["RevivalFlag"] = {
        { skinName = "PalmTree", displayName = "Palm Tree", icon = "", rarity = "Epic", vfxAttachment = "PalmTreeVFX" },
    },

    -- Item skin: Wood Shield (runner barricade) template-swap (wood plank -> fantasy metal shield)
    ["Wood Shield"] = {
        { skinName = "LegendShield", displayName = "Aegis of Legends", icon = "", rarity = "Legendary", templateSwap = "LegendShield", blockFx = "aegis" },
        { skinName = "RiotShield", displayName = "Riot Shield", icon = "", rarity = "Epic", templateSwap = "RiotShield", blockFx = "spark" },
        { skinName = "SFShield", displayName = "Jade Barrier", icon = "", rarity = "Rare", templateSwap = "SFShield", blockFx = "redtint" },
    },

    -- ── 무기 스킨: Katana 색놀이 ──
    -- 카타나는 메시 조각 다수 구성. 검은 계열 파트(Blade 등)만 color로 칠함.
    -- color = 메인 색 {r,g,b}. 카운터 참격(VertexColor)도 이 색으로 런타임에 맞춤.
    KatanaSword2 = {
        -- 모델 교체 스킨(Legendary): Handle 포함 기존 파트 전부 투명화 +
        -- ServerStorage.WeaponSkins.LegendKatana 용접. 색놀이가 아니라 별도 모델.
        {
            skinName = "LegendKatana", displayName = "Crimson Fang Katana", icon = "", rarity = "Legendary",
            meshSwap = "LegendKatana", swapScale = 1.0, swapOffset = {0, 0, 0}, swapRot = {0, 0, 0},
        },
        {
            skinName = "RedKatana", displayName = "Red Katana", icon = "", rarity = "Normal",
            material = "Metal", color = {200, 30, 30},
        },
        {
            skinName = "OrangeKatana", displayName = "Orange Katana", icon = "", rarity = "Normal",
            material = "Metal", color = {255, 140, 20},
        },
        {
            skinName = "YellowKatana", displayName = "Yellow Katana", icon = "", rarity = "Normal",
            material = "Metal", color = {255, 220, 40},
        },
        {
            skinName = "GreenKatana", displayName = "Green Katana", icon = "", rarity = "Normal",
            material = "Metal", color = {50, 200, 70},
        },
        {
            skinName = "CyanKatana", displayName = "Cyan Katana", icon = "", rarity = "Normal",
            material = "Metal", color = {70, 190, 255},
        },
        {
            skinName = "IndigoKatana", displayName = "Indigo Katana", icon = "", rarity = "Normal",
            material = "Metal", color = {60, 60, 200},
        },
        {
            skinName = "VioletKatana", displayName = "Violet Katana", icon = "", rarity = "Normal",
            material = "Metal", color = {180, 60, 230},
        },
        {
            skinName = "WhiteKatana", displayName = "White Katana", icon = "", rarity = "Normal",
            material = "Metal", color = {245, 245, 245},
        },
        {
            skinName = "RainbowKatana", displayName = "Rainbow Katana", icon = "", rarity = "Rare",
            material = "Neon", color = {255, 255, 255}, rainbow = true,
        },
    },

    -- ── 무기 스킨: Hammer 색놀이 7종 ──
    -- 망치 Handle은 텍스처 메시 → Neon 단색으로 칠함(TextureId 비우는 처리는 적용부에서).
    -- color = 망치 색, effectColor = 스핀 이펙트 색 (둘 다 같은 색으로 통일).
    HammerLow = {
        {
            skinName = "RedHammer", displayName = "Red Hammer", icon = "", rarity = "Normal",
            material = "Neon", color = {255, 40, 40}, effectColor = {230, 30, 30},
        },
        {
            skinName = "OrangeHammer", displayName = "Orange Hammer", icon = "", rarity = "Normal",
            material = "Neon", color = {255, 140, 20}, effectColor = {235, 120, 15},
        },
        {
            skinName = "GreenHammer", displayName = "Green Hammer", icon = "", rarity = "Normal",
            material = "Neon", color = {50, 220, 70}, effectColor = {40, 200, 60},
        },
        {
            skinName = "BlueHammer", displayName = "Blue Hammer", icon = "", rarity = "Normal",
            material = "Neon", color = {40, 120, 255}, effectColor = {30, 100, 235},
        },
        {
            skinName = "PurpleHammer", displayName = "Purple Hammer", icon = "", rarity = "Normal",
            material = "Neon", color = {180, 60, 240}, effectColor = {160, 50, 220},
        },
        {
            skinName = "PinkHammer", displayName = "Pink Hammer", icon = "", rarity = "Normal",
            material = "Neon", color = {255, 120, 190}, effectModel = "SpinEffectPinkTemplate",
        },
        {
            skinName = "WhiteHammer", displayName = "White Hammer", icon = "", rarity = "Rare",
            material = "Neon", color = {245, 245, 245}, effectModel = "SpinEffectWhiteTemplate",
        },
        {
            skinName = "BlackHammer", displayName = "Black Hammer", icon = "", rarity = "Rare",
            material = "Neon", color = {30, 30, 35}, effectModel = "SpinEffectBlackTemplate",
        },
        {
            skinName = "RainbowHammer", displayName = "Rainbow Hammer", icon = "", rarity = "Rare",
            material = "Neon", color = {255, 255, 255}, rainbow = true,
        },
        {
            skinName = "LightningHammer", displayName = "Lightning Hammer", icon = "", rarity = "Epic",
            material = "ForceField", color = {150, 255, 251}, effectModel = "SpinEffectThunderTemplate",
            thunderStrike = true, auraParticle = "ThunderAuraParticle", keepTexture = true,
        },
        { skinName = "DruidHammer", displayName = "Druid Hammer", icon = "", rarity = "Legendary", meshSwap = "DruidHammer", swapScale = 1.0, swapOffset = {0, 0, 0}, swapRot = {90, 0, 0}, effectColor = {60, 160, 70} },
    },

    -- ── 무기 스킨: Flame Hammer (로켓 해머) ──
    -- 다른 스킨과 달리 무지개 순환 로직이 HammerHighScript에 내장됨.
    -- 그래서 색 데이터 없이 rainbow 플래그만 둠 → 장착 시 무기에 RainbowSkin 속성 부여하면
    -- HammerHighScript가 알아서 머리+flame tail을 순환시킴.
    HammerHigh = {
        {
            skinName = "RainbowRocketHammer", displayName = "Rainbow Flame Hammer", icon = "", rarity = "Rare",
            rainbow = true,
        },
        -- mesh-swap skin: replace the whole hammer with the WeaponSkins model (Blender hammer).
        { skinName = "FlameHammer", displayName = "Ruby Flame Hammer", icon = "", rarity = "Epic",
          meshSwap = "FlameHammer", swapScale = 1.0, swapOffset = {0, 1.2, 0}, swapRot = {0, 0, 0}, solidHSV = {0.97, 0.85, 0.9}, flameOffset = {-7.92, 2.62, 0} },
        -- Ice Crusher mesh-swap (Legendary): SpecialMesh 무기라 크기는 SpecialMesh.Scale이 결정. 이펙트는 중앙부 사출 + 얼음색.
        { skinName = "IceCrusher", displayName = "Ice Crusher", icon = "", rarity = "Legendary",
          meshSwap = "IceCrusher", swapScale = 1.0, swapOffset = {-0.40, 1.50, -0.10}, swapRot = {-94.9, 74.6, 89.9}, solidHSV = {0.55, 0.55, 1.0}, flameOffset = {-7.41, 2.17, 0}, iceGround = true, snowEffect = true, swingAnim = "rbxassetid://86215353915175", inspectAnim = "rbxassetid://94522961972376" },
        -- 단색 11종: solidHSV = {hue, sat, val} (0~1). 장착 시 무기에 SkinHue/SkinSat/SkinVal 속성 부여.
        -- 머리(Cube.004)+Cylinder.004+Handle+flame tail 불꽃을 이 색으로 칠함.
        { skinName = "RedRocketHammer",    displayName = "Red Flame Hammer",    icon = "", rarity = "Normal", solidHSV = {0.00, 1.00, 1.00} },
        { skinName = "OrangeRocketHammer", displayName = "Orange Flame Hammer", icon = "", rarity = "Normal", solidHSV = {0.07, 1.00, 1.00} },
        { skinName = "GreenRocketHammer",  displayName = "Green Flame Hammer",  icon = "", rarity = "Normal", solidHSV = {0.33, 1.00, 1.00} },
        { skinName = "BlueRocketHammer",   displayName = "Blue Flame Hammer",   icon = "", rarity = "Normal", solidHSV = {0.58, 1.00, 1.00} },
        { skinName = "IndigoRocketHammer", displayName = "Indigo Flame Hammer", icon = "", rarity = "Normal", solidHSV = {0.66, 1.00, 0.95} },
        { skinName = "VioletRocketHammer", displayName = "Violet Flame Hammer", icon = "", rarity = "Normal", solidHSV = {0.78, 0.85, 1.00} },
        { skinName = "PinkRocketHammer",   displayName = "Love Flame Hammer",   icon = "", rarity = "Rare", solidHSV = {0.92, 0.55, 1.00}, loveEffect = true },
        { skinName = "GoldRocketHammer",   displayName = "Gold Flame Hammer",   icon = "", rarity = "Rare",   solidHSV = {0.13, 0.90, 1.00} },
        { skinName = "WhiteRocketHammer",  displayName = "White Flame Hammer",  icon = "", rarity = "Rare",   solidHSV = {0.00, 0.00, 1.00} },
        { skinName = "BlackRocketHammer",  displayName = "Black Flame Hammer",  icon = "", rarity = "Rare",   solidHSV = {0.00, 0.00, 0.08} },
    },

    -- ── 무기 스킨: Sakura Blade (벚꽃 검) ──
    -- 검날은 SpecialMesh+텍스처+VertexColor 구조 → VertexColor에 색조 곱해 색 변경.
    -- 오라(SakuraArm/Foot/KParticle)는 파티clos Color로 색 변경. SwordScript가 처리.
    -- solidHSV = {hue, sat, val} (0~1). 장착 시 무기에 SkinHue/SkinSat/SkinVal 속성 부여.
    SakuraBlade = {
        { skinName = "RainbowSakura", displayName = "Rainbow Sakura", icon = "", rarity = "Rare", rainbow = true },
        { skinName = "RedSakura",    displayName = "Red Sakura",    icon = "", rarity = "Normal", solidHSV = {0.00, 1.00, 1.00} },
        { skinName = "OrangeSakura", displayName = "Orange Sakura", icon = "", rarity = "Normal", solidHSV = {0.05, 1.00, 1.00} },
        { skinName = "GreenSakura",  displayName = "Green Sakura",  icon = "", rarity = "Normal", solidHSV = {0.33, 1.00, 1.00} },
        { skinName = "BlueSakura",   displayName = "Blue Sakura",   icon = "", rarity = "Normal", solidHSV = {0.58, 1.00, 1.00} },
        { skinName = "IndigoSakura", displayName = "Indigo Sakura", icon = "", rarity = "Normal", solidHSV = {0.66, 1.00, 0.95} },
        { skinName = "VioletSakura", displayName = "Violet Sakura", icon = "", rarity = "Normal", solidHSV = {0.78, 0.85, 1.00} },
        { skinName = "GoldSakura",   displayName = "Gold Sakura",   icon = "", rarity = "Rare",   solidHSV = {0.15, 0.75, 1.00} },
        { skinName = "SilverSakura", displayName = "Silver Sakura",  icon = "", rarity = "Rare",   solidHSV = {0.00, 0.00, 1.00} },
        { skinName = "BlackSakura",  displayName = "Black Sakura",  icon = "", rarity = "Rare",   solidHSV = {0.00, 0.00, 0.08} },
    },
}

-- 플레이어별 장착 스킨: { [userId] = { [itemName] = skinName } }
local playerSkins = {}

-- 스킨 보유 여부 확인 (Attribute 기반)
local function ownsSkin(player, skinName)
    return player:GetAttribute("Has_" .. skinName) == true
end

-- 특정 아이템에 장착된 스킨 가져오기
local function getEquippedSkin(player, itemName)
    local skins = playerSkins[player.UserId]
    local skinName = skins and skins[itemName] or nil
    
    -- ✅ 보유 재검증: 장착 중인데 미보유이면 자동 해제
    if skinName and not ownsSkin(player, skinName) then
        skins[itemName] = nil
        warn("⚠️ 미보유 스킨 자동 해제:", player.Name, skinName)
        return nil
    end
    
    return skinName
end

-- GetPlayerSkin: 클라이언트가 아이템의 스킨 목록 + 장착 정보 요청
getPlayerSkin.OnServerInvoke = function(player, itemName)
    local available = SKIN_DATABASE[itemName] or {}
    local equipped  = getEquippedSkin(player, itemName)
    
    -- 각 스킨에 보유 여부 추가
    local result = {}
    for _, skinData in ipairs(available) do
        table.insert(result, {
            skinName    = skinData.skinName,
            displayName = skinData.displayName,
            icon        = skinData.icon,
            rarity      = skinData.rarity,
            owned       = ownsSkin(player, skinData.skinName),
            equipped    = (equipped == skinData.skinName),
            material    = skinData.material,
            color       = skinData.color,
            cycle       = skinData.cycle,
            solidHSV    = skinData.solidHSV,
            rainbow     = skinData.rainbow,
        })
    end
    
    return result
end

-- SetPlayerSkin: 클라이언트가 스킨 착용/해제 요청
-- 💾 [2026-09-11] 장착 상태를 프로필에 쓴다.
--   [왜] playerSkins 는 스크립트 메모리 테이블이라 서버가 꺼지면 사라졌다.
--     소유(Has_)는 저장되는데 장착은 안 돼서, 유저가 스킨을 사고 껴도 재접속하면
--     기본 외형으로 돌아갔다. 과금 상품이라 치명적.
--   ⚠️ 장착을 바꾸는 경로가 셋이다(리모트 착용 / 해제 / _G.setEquippedSkin).
--     한 곳만 고치면 나머지에서 또 새어나간다 — 반드시 이 헬퍼를 거칠 것.
local function persistEquip(player, itemName, skinName)
    local d = _G.DataService and _G.DataService.get and _G.DataService.get(player)
    if not d then return end
    if type(d.EquippedSkins) ~= "table" then d.EquippedSkins = {} end
    d.EquippedSkins[itemName] = skinName   -- nil 이면 해제
end

setPlayerSkin.OnServerEvent:Connect(function(player, itemName, skinName)	-- ⚠️ [ROUND-LOCK] 라운드 중에는 변경 불가. UI 를 닫는 것만으론 부족하다 —
	--    리모트는 클라에서 직접 호출할 수 있으므로 서버가 최종 방어선이다.
	--    (실측 2026-08-21: 라운드 중 인벤에서 바꾸면 실시간 반영됨)
	do
		local _ph = game:GetService("ReplicatedStorage"):GetAttribute("RoundPhase")
		if _ph == "stage1" or _ph == "stage2" then return end
	end
    if not itemName then return end
    
    if not playerSkins[player.UserId] then
        playerSkins[player.UserId] = {}
    end
    
    local current = playerSkins[player.UserId][itemName]
    
    if skinName == nil or skinName == current then
        -- 해제
        playerSkins[player.UserId][itemName] = nil
        persistEquip(player, itemName, nil)
        print("🎨", player.Name, "스킨 해제:", itemName)
    else
        -- 보유 확인
        if not ownsSkin(player, skinName) then
            warn("❌", player.Name, "스킨 미보유:", skinName)
            return
        end
        -- 착용
        playerSkins[player.UserId][itemName] = skinName
        persistEquip(player, itemName, skinName)
        print("🎨", player.Name, "스킨 착용:", itemName, "→", skinName)
    end
end)

-- 외부에서 장착 스킨 조회 가능하도록 _G에 등록
_G.getEquippedSkin = getEquippedSkin

-- server-side equip helper (tests + future battle pass grants). skinName=nil to clear.
_G.setEquippedSkin = function(player, itemName, skinName)
    if not (player and itemName) then return end
    if not playerSkins[player.UserId] then playerSkins[player.UserId] = {} end
    playerSkins[player.UserId][itemName] = skinName
    persistEquip(player, itemName, skinName)   -- 💾 세 번째 경로도 저장한다
end

-- 무기 스킨의 색/재질 데이터 조회 (스폰 시 색 입히기용).
-- itemName(예: "ClassicSword")과 skinName으로 SKIN_DATABASE에서 색/재질/순환 정보 반환.
-- 반환: {material=재질명, color=Color3 or nil, cycle=bool} 또는 nil(스킨 없음/색정보 없음).
_G.getSwordSkinData = function(itemName, skinName)
    if not skinName then return nil end
    local list = SKIN_DATABASE[itemName]
    if not list then return nil end
    for _, entry in ipairs(list) do
        if entry.skinName == skinName then
            local data = { material = entry.material, cycle = entry.cycle, rainbow = entry.rainbow, solidHSV = entry.solidHSV, loveEffect = entry.loveEffect, effectModel = entry.effectModel, particle = entry.particle, thunderStrike = entry.thunderStrike, auraParticle = entry.auraParticle, keepTexture = entry.keepTexture, vfxAttachment = entry.vfxAttachment, potionFxColor = entry.potionFxColor, potionSoundId = entry.potionSoundId, meshSwap = entry.meshSwap, swapScale = entry.swapScale, swapOffset = entry.swapOffset, swapRot = entry.swapRot, swingSnow = entry.swingSnow, templateSwap = entry.templateSwap, blockFx = entry.blockFx, meshTexture = entry.meshTexture, beanFxId = entry.beanFxId, bodyMaterial = entry.bodyMaterial, ringsMaterial = entry.ringsMaterial, iceMarks = entry.iceMarks, flameOffset = entry.flameOffset, iceGround = entry.iceGround, snowEffect = entry.snowEffect, swingAnim = entry.swingAnim, inspectAnim = entry.inspectAnim }
            if entry.color then
                data.color = Color3.fromRGB(entry.color[1], entry.color[2], entry.color[3])
            end
            if entry.bodyColor then
                data.bodyColor = Color3.fromRGB(entry.bodyColor[1], entry.bodyColor[2], entry.bodyColor[3])
            end
            if entry.ringsColor then
                data.ringsColor = Color3.fromRGB(entry.ringsColor[1], entry.ringsColor[2], entry.ringsColor[3])
            end
            if entry.effectColor then
                data.effectColor = Color3.fromRGB(entry.effectColor[1], entry.effectColor[2], entry.effectColor[3])
            end
            return data
        end
    end
    return nil
end

-- ✅ rare chest 보상용: 안 가진 스킨/건틀릿색 1개를 균등 추첨해 Has_ 부여.
-- 반환: { kind="skin"/"gcolor", attr="Has_...", display="표시명" } 또는 nil(전부 보유 → 호출측 코인 폴백).
local _gauntletPaletteMod = game:GetService("ServerStorage"):FindFirstChild("GauntletColorPalette")
local _gauntletPalette = _gauntletPaletteMod and require(_gauntletPaletteMod)

-- 공통 무기 색 보상용 (NoobColorPalette 공유 팔레트). 무기별 prefix로 개별 해금.
local _ncPaletteMod = game:GetService("ReplicatedStorage"):FindFirstChild("NoobColorPalette")
local _ncPalette = _ncPaletteMod and require(_ncPaletteMod)
local ITEM_COLOR_WEAPONS = {
    { item = "HammerLow",    prefix = "HammerColor",  display = "Hammer" },
    { item = "HammerHigh",   prefix = "FlameColor",   display = "Flame Hammer" },
    { item = "ClassicSword", prefix = "ClassicColor", display = "Sword" },
    { item = "KatanaSword2", prefix = "KatanaColor",  display = "Katana" },
    { item = "PushTool",     prefix = "PushColor",    display = "Fist" },
    { item = "Spear",        prefix = "SpearColor",   display = "Spear" },
    { item = "Demonspear",   prefix = "DemonColor",   display = "Demon Spear" },
    { item = "stone",        prefix = "StoneColor",   display = "Stone" },
    { item = "SakuraBlade",  prefix = "SakuraColor",  display = "Sakura Blade" },
    { item = "tsunami",      prefix = "TsunamiColor", display = "Tsunami" },
    { item = "tox_box",      prefix = "ToxColor",     display = "Tox Box" },
    { item = "tnt",          prefix = "BombColor",    display = "Bomb" },
    { item = "Wooden Barrel", prefix = "BarrelColor", display = "Barrel" },
}
-- 코인샵 판매 색 (일반). ShopSystem이 이 목록으로 판매 항목을 생성.
local ITEM_COLOR_PAID = {"Red","Orange","Green","Blue","Indigo","Violet","Pink","Black"}
-- 프리미엄 색: 코인샵 판매 제외, 박스 추첨 전용.
-- Yellow는 METAL 재질과 조합하면 금색이 되어 별도 Gold 스킨과 사실상 동일해짐
-- → 800코인에 풀면 금색 희소성이 사라지므로 상점에서 빼고 박스로만 배포.
-- (재질 제한은 없음. 받으면 MATTE/NEON에도 사용 가능 — 의도된 동작)
local ITEM_COLOR_PREMIUM = {"Yellow"}
local ITEM_COLOR_PREMIUM_RARITY = "Rare"   -- 색놀이 최상위=Rare (Epic+는 모델교체/이펙트 스킨 전용). Yellow는 코인샵 제외·박스 전용 유지.

-- ShopSystem이 같은 목록으로 코인 판매 항목을 생성한다 (박스 추첨과 단일 소스 공유).
-- ⚠ 여기를 고치면 상점 목록도 자동으로 따라감. 별도 사본 만들지 말 것.
_G.ITEM_COLOR_WEAPONS = ITEM_COLOR_WEAPONS
_G.ITEM_COLOR_PAID    = ITEM_COLOR_PAID

-- ⚠️ 동기화 필수: UnifiedInvenClient의 COLOR_SKINS(팔레트/Custom으로 대체되어 인벤에서 숨기는 단색)와 항상 같게 유지.
-- 여기 등록된 스킨은 고급 상자 추첨에서도 제외됨 → 인벤에 안 뜨는 "허상 스킨" 방지.
local PALETTE_COLOR_SKINS = {
    ItemNoob     = {OrangeNoob=true,YellowNoob=true,GreenNoob=true,BlueNoob=true,IndigoNoob=true,VioletNoob=true},
    Spear        = {GoldSpear=true,SilverSpear=true,PinkSpear=true,BlueSpear=true,GreenSpear=true,BlackSpear=true},
    stone        = {BlueStone=true,GoldStone=true,GreenStone=true,PinkStone=true,SilverStone=true},
    bear_trap    = {BlueBearTrap=true,BronzeBearTrap=true,CobaltBearTrap=true,CrimsonBearTrap=true,DeepPurpleBearTrap=true,EmeraldBearTrap=true,GoldBearTrap=true,GreenBearTrap=true,ObsidianBearTrap=true,OrangeBearTrap=true,RedBearTrap=true,ToxicBearTrap=true,VioletBearTrap=true,YellowBearTrap=true},
    PushTool     = {RedFist=true,OrangeFist=true,YellowFist=true,GreenFist=true,BlueFist=true,VioletFist=true,PinkFist=true,GlitchFist=true,CursorFist=true,Vishnu=true},
    ClassicSword = {RedSword=true,OrangeSword=true,YellowSword=true,GreenSword=true,BlueSword=true,IndigoSword=true,VioletSword=true},
    KatanaSword2 = {RedKatana=true,OrangeKatana=true,YellowKatana=true,GreenKatana=true,CyanKatana=true,IndigoKatana=true,VioletKatana=true,WhiteKatana=true},
    HammerLow    = {RedHammer=true,OrangeHammer=true,GreenHammer=true,BlueHammer=true,PurpleHammer=true,PinkHammer=true,WhiteHammer=true,BlackHammer=true},
    SakuraBlade  = {RedSakura=true,OrangeSakura=true,GreenSakura=true,BlueSakura=true,IndigoSakura=true,VioletSakura=true,GoldSakura=true,SilverSakura=true,BlackSakura=true},
    HammerHigh   = {RedRocketHammer=true,OrangeRocketHammer=true,GreenRocketHammer=true,BlueRocketHammer=true,IndigoRocketHammer=true,VioletRocketHammer=true,GoldRocketHammer=true,WhiteRocketHammer=true,BlackRocketHammer=true},
}

-- 등급별 허용 rarity 범위 (풀 필터 — 인접 확장 폴백용 lo/hi 인덱스)
local RARITY_IDX = { Normal = 1, Rare = 2, Epic = 3, Legendary = 4 }
-- Cosmetic box weighted draw: per-rarity item weight. SINGLE SOURCE for both the draw
-- (grantRandomCosmetic) and the odds disclosure (getCosmeticOdds) -- never split them, or
-- displayed odds != actual odds = Roblox paid-random-item policy violation.
local RARITY_WEIGHT = { Normal = 8, Rare = 4, Epic = 2, Legendary = 1 }
-- Weighted random pick from a pool of entries carrying .rarity (uses RARITY_WEIGHT).
local function weightedPick(pool)
    local totalW = 0
    for _, e in ipairs(pool) do totalW = totalW + (RARITY_WEIGHT[e.rarity] or 1) end
    local roll = math.random() * totalW
    local acc = 0
    for _, e in ipairs(pool) do
        acc = acc + (RARITY_WEIGHT[e.rarity] or 1)
        if roll <= acc then return e end
    end
    return pool[#pool]
end
local GRADE_RANGE = {
    common = { 1, 2 },  -- Normal + Rare
    plus   = { 2, 3 },  -- Rare + Epic
    mega   = { 3, 4 },  -- Epic + Legendary
}

-- 미보유 풀 생성 — 추첨(grantRandomSkin)과 확률공시(getBoxOdds)가 공유하는 단일 소스.
-- 둘이 다른 코드를 쓰면 표시 확률과 실제 확률이 어긋나므로 반드시 이 함수만 사용할 것.
local function buildSkinPool(player)
    local pool = {}

    -- 1) SkinManager 스킨 전체 (SKIN_DATABASE). 팔레트/Custom으로 대체되는 단색은 제외.
    for weaponName, list in pairs(SKIN_DATABASE) do
        local excl = PALETTE_COLOR_SKINS[weaponName]
        for _, entry in ipairs(list) do
            if not (excl and excl[entry.skinName]) then
                local attr = "Has_" .. entry.skinName
                if not player:GetAttribute(attr) then
                    pool[#pool+1] = { kind = "skin", attr = attr, display = entry.displayName or entry.skinName,
                        icon = entry.icon, rarity = entry.rarity or "Normal",
                        weapon = weaponName, skinName = entry.skinName,
                        color = entry.color, material = entry.material, cycle = entry.cycle,
                        solidHSV = entry.solidHSV, rainbow = entry.rainbow }
                end
            end
        end
    end

    -- 2) 건틀릿 유료 색 (GauntletColorPalette.PAID_COLORS) → Has_GColor_<색>
    if _gauntletPalette and _gauntletPalette.PAID_COLORS then
        for _, colorName in ipairs(_gauntletPalette.PAID_COLORS) do
            local attr = "Has_GColor_" .. colorName
            if not player:GetAttribute(attr) then
                local gentry = { kind = "gcolor", attr = attr,
                    display = "Gauntlet " .. colorName:sub(1,1):upper() .. colorName:sub(2),
                    icon = "", rarity = "Normal", gcolorName = colorName }  -- 기본 단색 = Normal
                -- 실제 팔레트 색/효과 첨부 + 등급 (시각 화려함 기준)
                if _gauntletPalette.SPECIAL and _gauntletPalette.SPECIAL[colorName] then
                    gentry.cycle = true  -- rainbow = 무지개 순환
                    gentry.rarity = "Epic"
                elseif _gauntletPalette.FINISH and _gauntletPalette.FINISH[colorName] then
                    local fc = _gauntletPalette.FINISH[colorName].color
                    gentry.color = { math.floor(fc.R*255+0.5), math.floor(fc.G*255+0.5), math.floor(fc.B*255+0.5) }
                    gentry.rarity = "Rare"  -- 금속/특수 마감
                elseif _gauntletPalette.PALETTE and _gauntletPalette.PALETTE[colorName] then
                    local pc = _gauntletPalette.PALETTE[colorName]
                    gentry.color = { math.floor(pc.R*255+0.5), math.floor(pc.G*255+0.5), math.floor(pc.B*255+0.5) }
                end
                pool[#pool+1] = gentry
            end
        end
    end

    -- 3) 공통 무기 유료 색 (NoobColorPalette 공유 팔레트) → Has_<prefix>_<색>. 무기별 개별 해금.
    --    PAID(코인샵 판매) + PREMIUM(박스 전용) 둘 다 추첨 대상.
    --    ⚠ PREMIUM을 여기 안 넣으면 상점에도 박스에도 없는 "획득 불가 색"이 됨.
    if _ncPalette and _ncPalette.COLORS then
        local colorSets = {
            { list = ITEM_COLOR_PAID,    rarity = "Normal" },
            { list = ITEM_COLOR_PREMIUM, rarity = ITEM_COLOR_PREMIUM_RARITY },
        }
        for _, w in ipairs(ITEM_COLOR_WEAPONS) do
            local wcfg = _ncPalette.getConfig(w.item)
            local hide = wcfg and wcfg.hideColors  -- 인벤에서 숨긴 색은 추첨에서도 제외(허상 방지)
            for _, set in ipairs(colorSets) do
                for _, colorName in ipairs(set.list) do
                    if not (hide and hide[colorName]) then
                        local attr = "Has_" .. w.prefix .. "_" .. colorName
                        if not player:GetAttribute(attr) then
                            local ientry = { kind = "icolor", attr = attr,
                                display = w.display .. " " .. colorName,
                                icon = "", rarity = set.rarity,
                                weapon = w.item, itemColorName = colorName }
                            local c3 = _ncPalette.COLORS[colorName]
                            if c3 then
                                ientry.color = { math.floor(c3.R*255+0.5), math.floor(c3.G*255+0.5), math.floor(c3.B*255+0.5) }
                            end
                            pool[#pool+1] = ientry
                        end
                    end
                end
            end
        end
    end

    return pool
end

-- 등급 범위로 서브풀 필터. 비면 범위를 한 칸씩 넓혀 인접확장(원본 pool이 비지 않았으면 반드시 채워짐).
local function filterByGrade(pool, grade)
    if grade and GRADE_RANGE[grade] then
        local lo, hi = GRADE_RANGE[grade][1], GRADE_RANGE[grade][2]
        local sub = {}
        for _ = 1, 4 do
            sub = {}
            for _, e in ipairs(pool) do
                local ri = RARITY_IDX[e.rarity] or 1
                if ri >= lo and ri <= hi then sub[#sub+1] = e end
            end
            if #sub > 0 then break end
            lo = math.max(1, lo - 1); hi = math.min(4, hi + 1)
        end
        if #sub > 0 then return sub end
    end
    return pool
end

_G.grantRandomSkin = function(player, grade)
    if not player then return nil end
    local pool = buildSkinPool(player)
    if #pool == 0 then return nil end  -- 전부 보유 → 코인 폴백
    pool = filterByGrade(pool, grade)
    local pick = pool[math.random(1, #pool)]
    player:SetAttribute(pick.attr, true)
    local d = _G.DataService and _G.DataService.get(player)   -- 프로필에 영속 기록 (재접속 복원용)
    if d and d.Skins then d.Skins[pick.attr] = true end
    return pick
end

-- ── 확률 공시 (로블록스 유료 랜덤 아이템 정책) ─────────────────────
-- 추첨과 동일한 buildSkinPool/filterByGrade를 쓰므로 표시값 = 실제값 (드리프트 불가).
-- 중복 방지(no dupes) 설계라 확률이 플레이어마다 다름 → 화면에 띄울 때마다 호출할 것.
-- 반환: { total, each, byRarity = { [rarity] = {count, chance} }, items = { {display, rarity, chance} } }
_G.getBoxOdds = function(player, grade)
    if not player then return nil end
    local pool = filterByGrade(buildSkinPool(player), grade)
    local total = #pool
    if total == 0 then
        return { total = 0, each = 0, byRarity = {}, byKind = {}, items = {} }   -- 전부 보유 → 코인 폴백
    end
    local each = 100 / total          -- 균등 추첨이라 개별 확률은 전부 동일
    -- byKind: skin(실제 스킨) / gcolor(건틀릿 색) / icolor(무기 색). 등급만으론
    -- 색 변형이 몇 %인지 안 보여서 유저 기대값이 어긋나므로 종류별도 집계.
    local rc, kc, items = {}, {}, {}
    for _, e in ipairs(pool) do
        local r = e.rarity or "Normal"
        local k = e.kind or "skin"
        rc[r] = (rc[r] or 0) + 1
        kc[k] = (kc[k] or 0) + 1
        items[#items+1] = { display = e.display, rarity = r, kind = k, chance = each }
    end
    local byRarity, byKind = {}, {}
    for r, c in pairs(rc) do byRarity[r] = { count = c, chance = c * 100 / total } end
    for k, c in pairs(kc) do byKind[k]   = { count = c, chance = c * 100 / total } end
    return { total = total, each = each, byRarity = byRarity, byKind = byKind, items = items }
end

-- ── Details 팝업용 확률 조회 (RemoteFunction, 런타임 생성) ─────────
-- 유료 랜덤 아이템 정책: 구매 전에 전체 결과와 수치 확률을 보여줘야 함.
-- 중복 방지라 유저마다 값이 달라서 클라 캐시 금지 — 팝업 열 때마다 조회할 것.
do
    local RS = game:GetService("ReplicatedStorage")
    local rf = RS:FindFirstChild("GetBoxOdds")
    if not rf then
        rf = Instance.new("RemoteFunction")
        rf.Name = "GetBoxOdds"
        rf.Parent = RS
    end
    local GRADE_BY_PRODUCT = {
        [3609370373] = "common",   -- Color Skin Box
        [3610453697] = "common",   -- Collector Pack (Color Skin Box x5)
        [3609370476] = "plus",     -- Rare+ Box
        [3609370535] = "mega",     -- Epic+ Box
    }
    local COSMETIC_PRODUCT = 3609608159
    rf.OnServerInvoke = function(player, productId)
        if type(productId) ~= "number" then return nil end
        if productId == COSMETIC_PRODUCT then
            return _G.getCosmeticOdds and _G.getCosmeticOdds(player, nil) or nil
        end
        local grade = GRADE_BY_PRODUCT[productId]
        if not grade then return nil end
        return _G.getBoxOdds and _G.getBoxOdds(player, grade) or nil
    end
end

-- 유료/무료 박스 공용: 추첨(grade) + 상자 컷신 발사 + 전부보유 시 코인 폴백. ProcessReceipt 등에서 한 줄 호출.
_G.grantBoxToPlayer = function(player, grade, fallbackCoins)
    if not player then return end
    local result = _G.grantRandomSkin and _G.grantRandomSkin(player, grade) or nil
    if result then
        local ev = game:GetService("ReplicatedStorage"):FindFirstChild("RareSkinReward")
        if ev then
            result.fromBox = true
            result.boxGrade = grade   -- 클라 컷신이 등급별 외형 선택 (common=뚜껑 / plus·mega=회전+펑)
            ev:FireClient(player, result)
        end
    elseif _G.CoinSystem and _G.CoinSystem.addCoins then
        _G.CoinSystem.addCoins(player, fallbackCoins or 100)
    end
end

-- ── 코스메틱 박스 (킬이펙트/트레일/대시/크라운 랜덤) ─────────────
-- grantRandomSkin과 별개 풀. OwnedItem_ 부여 + 프로필 영속(d.Skins). 전부보유 시 nil(코인 폴백).
-- 코스메틱 미보유 풀 생성 — 추첨(grantRandomCosmetic)과 확률공시(getCosmeticOdds) 공용 단일 소스.
local function buildCosmeticPool(player)
    local RS = game:GetService("ReplicatedStorage")
    local pool = {}
    local function tryRequire(name)
        local m = RS:FindFirstChild(name)
        if m then local ok, data = pcall(require, m); if ok then return data end end
        return nil
    end
    local function addList(list, category)
        if type(list) ~= "table" then return end
        for _, e in ipairs(list) do
            if e.id then
                local attr = "OwnedItem_" .. e.id
                if not player:GetAttribute(attr) then
                    pool[#pool+1] = { kind = "cosmetic", category = category, attr = attr, id = e.id,
                        display = e.name or e.displayName or e.id,
                        icon = e.icon or "", imageId = e.imageId or "",
                        rarity = e.rarity or "Normal", skinKey = e.skinKey }
                end
            end
        end
    end
    addList(_G.KILL_EFFECTS, "killEffect")          -- EffectSystem이 _G로 노출
    addList(tryRequire("TrailData"), "trailSkin")
    addList(tryRequire("DashData"), "dashSkin")
    addList(tryRequire("CrownData"), "crownSkin")
    return pool
end

_G.grantRandomCosmetic = function(player, grade)
    if not player then return nil end
    local pool = buildCosmeticPool(player)
    if #pool == 0 then return nil end  -- all owned -> coin fallback
    pool = filterByGrade(pool, grade)  -- single box: grade=nil -> all tiers
    local pick = weightedPick(pool)    -- rarity-weighted draw (RARITY_WEIGHT)
    player:SetAttribute(pick.attr, true)
    local d = _G.DataService and _G.DataService.get(player)   -- persist to profile
    if d and d.Skins then d.Skins[pick.attr] = true end
    return pick
end

-- Cosmetic box odds disclosure (WEIGHTED).
-- Uses the same RARITY_WEIGHT as the draw (weightedPick) -> displayed == actual (no drift).
-- byCategory: the card says "trail, dash, crown or kill effect", so per-type share is shown too.
-- No "each" field returned: signals non-uniform to the client (skips the "each item X%" line).
_G.getCosmeticOdds = function(player, grade)
    if not player then return nil end
    local pool = filterByGrade(buildCosmeticPool(player), grade)
    local total = #pool
    if total == 0 then
        return { total = 0, byRarity = {}, byCategory = {}, items = {} }
    end
    local totalW = 0
    for _, e in ipairs(pool) do totalW = totalW + (RARITY_WEIGHT[e.rarity] or 1) end
    local rc, cc, cw, items = {}, {}, {}, {}
    for _, e in ipairs(pool) do
        local r = e.rarity or "Normal"
        local c = e.category or "etc"
        local w = RARITY_WEIGHT[r] or 1
        rc[r] = (rc[r] or 0) + 1
        cc[c] = (cc[c] or 0) + 1
        cw[c] = (cw[c] or 0) + w
        items[#items+1] = { display = e.display, rarity = r, category = c, chance = w * 100 / totalW }
    end
    local byRarity, byCategory = {}, {}
    for r, cnt in pairs(rc) do byRarity[r]   = { count = cnt, chance = cnt * (RARITY_WEIGHT[r] or 1) * 100 / totalW } end
    for c, cnt in pairs(cc) do byCategory[c] = { count = cnt, chance = (cw[c] or 0) * 100 / totalW } end
    return { total = total, byRarity = byRarity, byCategory = byCategory, items = items }
end

-- 코스메틱 박스 공용: 추첨 + 상자 컷신 발사 + 전부보유 시 코인 폴백. (단일 박스 = 전 등급)
_G.grantCosmeticBox = function(player, fallbackCoins)
    if not player then return end
    local result = _G.grantRandomCosmetic and _G.grantRandomCosmetic(player, nil) or nil
    if result then
        local ev = game:GetService("ReplicatedStorage"):FindFirstChild("RareSkinReward")
        if ev then
            result.fromBox = true
            result.cosmeticBox = true   -- 클라: Color Skin Box(ItemChest) 재활용 + 색/재질 변주
            ev:FireClient(player, result)
        end
    elseif _G.CoinSystem and _G.CoinSystem.addCoins then
        _G.CoinSystem.addCoins(player, fallbackCoins or 100)
    end
end

-- ✅ 테스트용: 스킨 + 아이템 보상 자동 부여
-- (나중에 실제 구매/보상 시스템으로 교체)
-- ⚠ 라이브 서버에서는 실행 금지 — 이 함수는 유료 스킨 100+개를 무상 지급하므로
--   그대로 두면 박스/상점 상품이 전부 무의미해짐. Studio에서만 동작하도록 게이트.
--   (테스트 더미 _TestRigBoot 와 동일한 방식)
local function grantTestSkins(player)
    if not game:GetService("RunService"):IsStudio() then return end
    -- [테스트 A안] 무기별 유료색 전량 지급 — do return end 앞이라 스킨은 미보유여도 색은 열림.
    -- [검증용] _SKIP_ICOLOR의 무기는 색 미보유로 남겨 rare chest 무기색 카드를 확인. 검증 끝나면 {} 로 비우면 전량 지급.
    -- [신규유저 재현] _GIVE_ICOLOR=false 면 무기색 미지급 → rare chest 무기색 도배 확인용. 평소엔 true.
    local _GIVE_ICOLOR = false
    if _GIVE_ICOLOR then
        for _, prefix in ipairs({"HammerColor","FlameColor","ClassicColor","KatanaColor","PushColor","SpearColor","DemonColor","StoneColor","SakuraColor","TsunamiColor","ToxColor","BombColor"}) do
            for _, c in ipairs({"Red","Orange","Yellow","Green","Blue","Indigo","Violet","Pink","Black"}) do
                player:SetAttribute("Has_" .. prefix .. "_" .. c, true)
            end
        end
    end
    for _, c in ipairs({"Bronze","Blue","Cobalt","Crimson","DeepPurple","Emerald","Gold","Green","Obsidian","Orange","Red","Toxic","Violet","Yellow"}) do
        player:SetAttribute("Has_BTColor_" .. c, true)  -- bear_trap 전용 14색
    end
    for _, c in ipairs({"Red","Orange","Yellow","Green","Blue","Indigo","Violet","Pink","Black"}) do
        player:SetAttribute("Has_NoobColor_" .. c, true)  -- ItemNoob(캐릭터) 색
    end
    player:SetAttribute("Has_LegendKatana", true)  -- Crimson Fang (Legendary 모델교체) — 가드 앞이어야 실제 지급됨
    player:SetAttribute("Has_LegendShield", true)  -- Aegis of Legends (Legendary 템플릿교체) — 가드 앞
    player:SetAttribute("Has_Cup", true)  -- Golden Chalice (Speed Potion Epic form-swap) — 가드 앞
    player:SetAttribute("Has_DruidHammer", true)  -- Druid Hammer (Legendary meshSwap) — 가드 앞
    player:SetAttribute("Has_IceCrystalBlade", true)  -- Ice Crystal Blade (DiamondBladeSword Legendary meshSwap)
    player:SetAttribute("Has_GlitchFist", true)  -- Glitch Hand (PushTool Epic meshSwap)
    player:SetAttribute("Has_CursorFist", true)  -- Cursor Hand (PushTool Normal meshSwap)
    player:SetAttribute("Has_Vishnu", true)  -- Vishnu (PushTool Legendary aura)
    player:SetAttribute("Has_FlameHammer", true)  -- Flame Hammer (HammerHigh Epic meshSwap)
    player:SetAttribute("Has_MechGauntlet", true)  -- Mech Gauntlet (Gauntlet Legendary meshSwap)
    player:SetAttribute("Has_IceCrusher", true)  -- Ice Crusher (HammerHigh Legendary meshSwap)
    player:SetAttribute("Has_CrusaderBarrel", true)  -- Crusader Barrel (Legendary 모델교체) — 가드 앞
    player:SetAttribute("Has_OilDrum", true)  -- Oil Drum (Epic 모델교체+fire) — 가드 앞
    player:SetAttribute("Has_RiotShield", true)  -- Riot Shield (Wood Shield Rare 템플릿교체) — 가드 앞
    player:SetAttribute("Has_SFShield", true)  -- Prism Barrier (Wood Shield Epic 템플릿교체) — 가드 앞
    player:SetAttribute("Has_LavaTsunami", true)  -- Lava Tsunami (tsunami Rare 텍스처스왑) — 가드 앞 (테스트용)
    do return end  -- 🔧 임시: rare 스킨 추첨 테스트용 (이 줄만 지우면 전체 스킨 부여 원복)
    player:SetAttribute("Has_LavaNoob", true)
    -- 테스트용: Rainbow Tsunami 카드만 (단색/금색은 ITEM COLOR 색 보유로 별도 관리)
    player:SetAttribute("Has_RainbowTsunami", true)
    player:SetAttribute("Has_RainbowToxBox", true)
    player:SetAttribute("Has_RainbowBomb", true)
    player:SetAttribute("Has_RainbowDemonSpear", true)
    player:SetAttribute("Has_GoldNeonNoob", true)  -- 테스트용: Gold Neon Noob 스킨 보유
    -- 테스트용: Noob 스킨 7종 보유
    player:SetAttribute("Has_IceNoob", true)
    player:SetAttribute("Has_GlitchNoob", true)
    player:SetAttribute("Has_SuitNoob", true)
    player:SetAttribute("Has_KingNoob", true)
    player:SetAttribute("Has_SummerNoob", true)
    player:SetAttribute("Has_ZombieNoob", true)
    player:SetAttribute("Has_SoldierNoob", true)
    player:SetAttribute("Has_RainbowNoob", true)
    player:SetAttribute("Has_OrangeNoob", true)  -- 무지개 색놀이 뉴비 (빨강 제외)
    player:SetAttribute("Has_YellowNoob", true)
    player:SetAttribute("Has_GreenNoob", true)
    player:SetAttribute("Has_BlueNoob", true)
    player:SetAttribute("Has_IndigoNoob", true)
    player:SetAttribute("Has_VioletNoob", true)
    -- 테스트용: 망치 색놀이 8종 보유
    player:SetAttribute("Has_RedHammer", true)
    player:SetAttribute("Has_OrangeHammer", true)
    player:SetAttribute("Has_GreenHammer", true)
    player:SetAttribute("Has_BlueHammer", true)
    player:SetAttribute("Has_PurpleHammer", true)
    player:SetAttribute("Has_PinkHammer", true)
    player:SetAttribute("Has_RainbowHammer", true)
    player:SetAttribute("Has_LightningHammer", true)
    player:SetAttribute("Has_WhiteHammer", true)
    player:SetAttribute("Has_BlackHammer", true)
    player:SetAttribute("Has_RainbowRocketHammer", true)  -- 테스트용: Flame Hammer 무지개 스킨 보유
    -- 테스트용: Flame Hammer 단색 11종 보유
    player:SetAttribute("Has_RedRocketHammer", true)
    player:SetAttribute("Has_OrangeRocketHammer", true)
    player:SetAttribute("Has_GreenRocketHammer", true)
    player:SetAttribute("Has_BlueRocketHammer", true)
    player:SetAttribute("Has_IndigoRocketHammer", true)
    player:SetAttribute("Has_VioletRocketHammer", true)
    player:SetAttribute("Has_PinkRocketHammer", true)
    player:SetAttribute("Has_GoldRocketHammer", true)
    player:SetAttribute("Has_WhiteRocketHammer", true)
    player:SetAttribute("Has_BlackRocketHammer", true)
    player:SetAttribute("Has_BlueSakura", true)  -- 테스트용: Sakura Blade 파랑 스킨 보유
    -- 테스트용: Sakura Blade 나머지 스킨 보유
    player:SetAttribute("Has_RainbowSakura", true)
    player:SetAttribute("Has_RedSakura", true)
    player:SetAttribute("Has_OrangeSakura", true)
    player:SetAttribute("Has_GreenSakura", true)
    player:SetAttribute("Has_IndigoSakura", true)
    player:SetAttribute("Has_VioletSakura", true)
    player:SetAttribute("Has_GoldSakura", true)
    player:SetAttribute("Has_SilverSakura", true)
    player:SetAttribute("Has_BlackSakura", true)
    player:SetAttribute("Has_SpikedWood", true)
    player:SetAttribute("Has_GoldenLog", true)  -- 테스트용: Golden Log 스킨 보유
    player:SetAttribute("Has_GoldStone", true)  -- 테스트용: Gold Stone 스킨 보유
    player:SetAttribute("Has_SilverStone", true)  -- 테스트용: Silver Stone 스킨 보유
    player:SetAttribute("Has_RainbowStone", true)  -- 테스트용: Rainbow Stone 스킨 보유
    player:SetAttribute("Has_LavaStone", true)  -- 테스트용: Lava Stone 스킨 보유
    player:SetAttribute("Has_DemonFlameStone", true)  -- 테스트용: Demon Flame Stone 스킨 보유
    player:SetAttribute("Has_SunStone", true)  -- 테스트용: Sun Stone 스킨 보유
    -- 테스트용: Bear Trap 스킨 15종 보유
    player:SetAttribute("Has_GoldBearTrap", true)
    player:SetAttribute("Has_CrimsonBearTrap", true)
    player:SetAttribute("Has_ToxicBearTrap", true)
    player:SetAttribute("Has_ObsidianBearTrap", true)
    player:SetAttribute("Has_CobaltBearTrap", true)
    player:SetAttribute("Has_DeepPurpleBearTrap", true)
    player:SetAttribute("Has_EmeraldBearTrap", true)
    player:SetAttribute("Has_BronzeBearTrap", true)
    player:SetAttribute("Has_RedBearTrap", true)
    player:SetAttribute("Has_OrangeBearTrap", true)
    player:SetAttribute("Has_YellowBearTrap", true)
    player:SetAttribute("Has_GreenBearTrap", true)
    player:SetAttribute("Has_BlueBearTrap", true)
    player:SetAttribute("Has_VioletBearTrap", true)
    player:SetAttribute("Has_RainbowBearTrap", true)
    player:SetAttribute("Has_PinkStone", true)
    player:SetAttribute("Has_BlueStone", true)
    player:SetAttribute("Has_GreenStone", true)
    player:SetAttribute("Has_BeachBall", true)  -- 테스트용: Beach Ball 스킨 보유 (여름 시즌)
    player:SetAttribute("Has_GoldSpear", true)  -- 테스트용: Gold Spear 스킨 보유
    player:SetAttribute("Has_SilverSpear", true)
    player:SetAttribute("Has_PinkSpear", true)
    player:SetAttribute("Has_BlueSpear", true)
    player:SetAttribute("Has_GreenSpear", true)
    player:SetAttribute("Has_BlackSpear", true)
    player:SetAttribute("Has_RainbowSpear", true)
    -- 테스트용: Classic Sword 색놀이 8종 보유
    player:SetAttribute("Has_RedSword", true)
    player:SetAttribute("Has_OrangeSword", true)
    player:SetAttribute("Has_YellowSword", true)
    player:SetAttribute("Has_GreenSword", true)
    player:SetAttribute("Has_BlueSword", true)
    player:SetAttribute("Has_IndigoSword", true)
    player:SetAttribute("Has_VioletSword", true)
    player:SetAttribute("Has_RainbowCycleSword", true)
    -- 테스트용: Katana 색놀이
    player:SetAttribute("Has_RedKatana", true)
    player:SetAttribute("Has_OrangeKatana", true)
    player:SetAttribute("Has_YellowKatana", true)
    player:SetAttribute("Has_GreenKatana", true)
    player:SetAttribute("Has_CyanKatana", true)
    player:SetAttribute("Has_IndigoKatana", true)
    player:SetAttribute("Has_VioletKatana", true)
    player:SetAttribute("Has_WhiteKatana", true)
    player:SetAttribute("Has_RainbowKatana", true)
    -- 테스트용: PushTool 색놀이 8종
    player:SetAttribute("Has_RedFist", true)
    player:SetAttribute("Has_OrangeFist", true)
    player:SetAttribute("Has_YellowFist", true)
    player:SetAttribute("Has_GreenFist", true)
    player:SetAttribute("Has_BlueFist", true)
    player:SetAttribute("Has_VioletFist", true)
    player:SetAttribute("Has_PinkFist", true)
    player:SetAttribute("Has_RainbowFist", true)
    player:SetAttribute("Has_BlackHoleFist", true)  -- 블랙홀 핸드(VFX 스킨)
    player:SetAttribute("HasItemNoob", true)  -- ItemNoob 잠금 해제 (그룹 보상 대체)
    print("🎨 테스트: " .. player.Name .. " LavaNoob 스킨 + ItemNoob 잠금해제")
end

-- 이미 접속한 플레이어에게도 부여
for _, player in ipairs(Players:GetPlayers()) do
    grantTestSkins(player)
end
Players.PlayerAdded:Connect(grantTestSkins)

-- 프로필에 저장된 스킨(Has_) 복원 (조인 시 — 박스/퀘스트/BP로 딴 스킨 영속)
local function restoreSkins(player)
    task.spawn(function()
        local d = _G.DataService and _G.DataService.waitForData(player, 20)
        if not d then return end
        -- 소유(Has_) 복원
        if type(d.Skins) == "table" then
            for attr in pairs(d.Skins) do
                player:SetAttribute(attr, true)
            end
        end
        -- 💾 [2026-09-11] 장착 복원. 소유만 돌아오고 장착이 안 돌아오던 문제.
        --   ⚠️ 보유 확인을 다시 한다 — 소유가 회수된 스킨(환불·기간제)이 장착으로
        --     남아 있으면 "없는 스킨을 낀 상태"가 된다.
        --   ⚠️ 소유 복원 뒤에 와야 한다. ownsSkin 이 방금 세운 속성을 읽는다.
        if type(d.EquippedSkins) == "table" then
            if not playerSkins[player.UserId] then playerSkins[player.UserId] = {} end
            local n = 0
            for itemName, skinName in pairs(d.EquippedSkins) do
                if skinName and ownsSkin(player, skinName) then
                    playerSkins[player.UserId][itemName] = skinName
                    n = n + 1
                end
            end
            if n > 0 then print(string.format("🎨 [Skin] %s 장착 복원 %d종", player.Name, n)) end
        end
    end)
end
Players.PlayerAdded:Connect(restoreSkins)
for _, p in ipairs(Players:GetPlayers()) do restoreSkins(p) end

Players.PlayerRemoving:Connect(function(player)
    playerSkins[player.UserId] = nil
end)

print("✅ SkinManager 준비 완료!")
