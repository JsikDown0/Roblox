-- 상점 시스템 (서버) - 탭 + 필터
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("🛒 ShopSystem 시작!")

-- [CONSUM-CAP] 소모품 1종당 보유 상한.
--   근거: 라운드당 로드아웃 1칸 = 1개만 소비 → 50개 ≈ 50판 분량(약 1.5시간).
--   너무 높으면 한 번 쟁여두고 상점을 안 보고, 너무 낮으면 코인 싱크가 죽는다.
--   인벤 수량 배지가 2자리까지는 레이아웃이 안 밀리는 것도 실측 확인됨(ODM Gear 19).
local CONSUMABLE_CAP = 50

local openShopEvent = ReplicatedStorage:WaitForChild("OpenShopEvent")
local purchaseEvent = ReplicatedStorage:WaitForChild("ShopPurchaseEvent")

local getItemsEvent = ReplicatedStorage:FindFirstChild("GetShopItems")
if not getItemsEvent then
    getItemsEvent = Instance.new("RemoteFunction")
    getItemsEvent.Name = "GetShopItems"
    getItemsEvent.Parent = ReplicatedStorage
end

local purchaseResultEvent = ReplicatedStorage:FindFirstChild("ShopPurchaseResult")
if not purchaseResultEvent then
    purchaseResultEvent = Instance.new("RemoteEvent")
    purchaseResultEvent.Name = "ShopPurchaseResult"
    purchaseResultEvent.Parent = ReplicatedStorage
end

local shopNpc = workspace:FindFirstChild("ShopNPC")
if shopNpc and shopNpc.PrimaryPart then
    local prompt = shopNpc.PrimaryPart:FindFirstChild("ShopPrompt")
    if prompt then
        prompt.Triggered:Connect(function(player)
            print("🛒 상점 열기:", player.Name)
            openShopEvent:FireClient(player)
        end)
        print("✅ ShopNPC 연결!")
    end
end

-- ════════════════════════════════════════════════════════════
-- 판매 목록 (개편판)
--  · 러너: 소모형(1회성/1라운드권) + 영구 SKU (ODM/Ice Bow는 소모/영구 2종)
--  · 태거: 전부 영구 해금 (1인 진영 → 무기고를 갖춘 폭군)
--  · 코스메틱(skin 탭): 킬이펙트 + 이모트 (크라운/무기스킨은 추후 편입)
--  · 가격은 placeholder (소모 100 / 러너 영구 1200 / 태거·이펙트 개별) — 밸런스 패스에서 조정
--  · SKU 묶음: baseId 필드로 같은 아이템의 소모/영구 두 SKU를 연결 (클라 UI가 묶어 표시)
--  · short = 카드용 한 줄 요약 / desc = 상세 팝업용 전체 설명
-- ════════════════════════════════════════════════════════════
local shopItems = {
    runner = {
        -- 소모품 가격 티어 (전 종목 150 균일 → 성능별 차등)
        --   균일가면 슬롯 4칸에 "제일 센 것 4개"만 넣게 되어 상점에 선택이 없음.
        --   100 기본 / 150 유틸 / 250~300 강력 / 400 최강(태거 무력화)
        {id = "speed_boost",  name = "Speed Potion", displayName = "Speed Potion",   price = 100, icon = "⚡", short = "Temporary speed boost", desc = "Temporarily increases movement speed.", itemType = "consumable", modelName = "Speed Potion"},
        {id = "decoy",        name = "Decoy Wand",   displayName = "Decoy Wand",    price = 100, icon = "🎭", short = "Summon a decoy · distract", desc = "Vanish for a moment and leave a decoy behind to confuse the King.", itemType = "consumable", modelName = "Decoy Wand"},
        {id = "smoke_bomb",   name = "Gas Grenade",  displayName = "Gas Grenade",    price = 50, icon = "💨", short = "Blocks the whole path with gas", desc = "Throw to block enemy sight with gas. Teammates see through it as a light haze.", itemType = "consumable", modelName = "Gas Grenade"},
        -- 🗑️ [2026-08-29] Grappling Hook 제거.
        --   [왜] ODM Gear 의 명백한 하위호환이라 존재 이유가 없었다.
        --     사거리는 150 으로 ODM(110)보다 길지만 1회뿐이라 총 이동량이
        --     150 vs 330 (ODM 110×3) 으로 2.2배 차이났다.
        --     가격 티어를 나눠(그래플 100 / ODM 300) 살려보려 했으나,
        --     하위호환은 싸다고 선택지가 되지 않는다 — "싸구려"가 될 뿐이다.
        --   [무엇을 살려봤나] 기능 차별화를 검토했지만 "지형에 붙는다"는 축이
        --     ODM 과 겹쳐 분리할 여지가 없었다.
        --   ⚠️ 함께 제거한 곳: StarterKitSystem(무료 지급 9→8종),
        --     PickupConfig(픽업 테이블), LoadoutManager(정의·ONUSE),
        --     TestCommands, AssetPreloadClient, RareSkinRewardCard, GrappleRefund(스크립트).
        --     인스턴스: ServerStorage.RunnerItem.GrappleHook,
        --               ReplicatedStorage.RunnerItemPreviews.GrappleHook
        -- 🎤 [밸런스 2026-08-29] 공연 중 피해 면역 추가. "최강 효과"에서 밈 아이템으로 되돌렸다.
        --   8초 무력화가 2단계(20~40초)의 1/4 을 지워 너무 강했다. 댄스 애니·노래가
        --   8초에 맞춰져 있어 지속은 두고 위력만 뺐다(_G.IsDamageImmune, 러너 무기 15곳 가드).
        --   ⚠️ 설명에 '피해 면역'과 '아군 대상 가능'을 반드시 적을 것 —
        --     안 적으면 아군에게 걸고 나서야 알게 된다.
        -- 🎤 [변경 2026-09-02] 완전 면역 → 피해 50% 감소. 설명도 같이 고쳤다.
        --   [왜] 던진 사람의 근접 딜까지 8초간 통째로 지워져 자기 손해였다(실측: 콘서트 중
        --     유저 타격 0건). 방어는 TaggerCcGuard 의 50% 감소가 담당한다.
        --   ⚠️ 실제 판정은 ItemDamageSystem._G.IsDamageImmune 에 있다. 이 설명만 고치면
        --     둘이 어긋난다 — 값을 다시 만질 땐 두 곳을 같이 볼 것.
        {id = "mic_bomb",     name = "Mic Bomb",     displayName = "Mic Bomb",      price = 150, icon = "🎤", short = "Dance party", desc = "Locks the target on a concert stage for 8s. They can't move and take half damage. Works on teammates too.", itemType = "consumable", modelName = "Mic Bomb"},
        -- 실드 150 : 즉사 게임에서 1회 방어는 Speed Potion보다 명백히 셈
        {id = "wood_shield",  name = "Wood Shield",  displayName = "Wood Shield",    price = 50, icon = "🛡️", short = "Blocks one King hit", desc = "Blocks one incoming King item. Guards you for a short moment.", itemType = "consumable", modelName = "wood Shield"},
        {id = "revival_flag", name = "RevivalFlag",  displayName = "Revival Flag",   price = 150, icon = "🚩", short = "Auto-revives nearby allies", desc = "Plant it to auto-revive every downed teammate within 25 studs over 7s.", itemType = "consumable", modelName = "RevivalFlag"},

        -- 🗑️ [2026-08-29] ODM/Ice Bow 영구 SKU 제거.
        --   [왜] 소모품과 영구제가 같은 아이템으로 공존해 가격 기준이 서지 않았다.
        --     손익분기 12회로 맞춰뒀으나, 하루 7판 유저는 2일이면 회수라
        --     "영구를 사는 게 무조건 이득"이었고 1판권 SKU 가 사실상 죽어 있었다.
        --     분기를 40회로 올리는 안도 검토했지만, 그 값이 맞는지 가늠할 근거가 없었다.
        --   [영향] 소모품 SKU 만 남는다. 소모품은 반복 소비돼 코인 싱크로 기능하는데,
        --     영구제는 그 싱크를 영구히 막아버리는 문제도 있었다.
        --   ⚠️ 함께 정리: LoadoutManager.PERMANENT_SKU(비움),
        --     LoadoutPreviewClient 의 같은 매핑.
        --     _G.OwnsPermanentItem 은 남겨둔다 — 테이블이 비면 항상 false 라 로직이
        --     자연히 꺼지고, 나중에 다른 영구제를 넣을 때 그대로 재사용할 수 있다.
        {id = "odm_gear",      name = "ODM Gear", displayName = "ODM Gear (1 round)",  price = 200,  icon = "⚙️", short = "1 round · 3 dashes", desc = "Use 3 times per round. Aim at a wall, teammate, or the hill to dash there fast.", itemType = "consumable", modelName = "ODM Gear", baseId = "odm_gear"},
        {id = "ice_bow",      name = "Ice Bow", displayName = "Ice Bow (1 round)",  price = 200,  icon = "🏹", short = "1 round · 2 freezes", desc = "Use 2 times per round. Hit the King to freeze them briefly.", itemType = "consumable", modelName = "Ice Bow", baseId = "ice_bow"},
    },
    tagger = {
        {id = "spear",       name = "Spear",      displayName = "Spear",       price = 1000, icon = "🗡️", short = "Unlimited throw · instant kill", desc = "Cheap, cost-effective throwing weapon. Throw a spear toward your cursor to kill runners it hits. Unlimited use.", itemType = "permanent", modelName = "Spear"},
        {id = "demon_spear", name = "Demonspear", displayName = "Demon Spear", price = 3500, icon = "🔥", short = "Flaming path · area instant kill", desc = "Spear upgrade. The thrown path bursts into flames, instantly killing runners across a wide area. Zone-control type.", itemType = "permanent", modelName = "Demonspear"},
        {id = "black_hole",  name = "BlackHole",  displayName = "Black Hole",  price = 2500, icon = "🕳️", short = "Pulls runners in · combo", desc = "Throw in an arc to create a 5s black hole. Pulls runners in without damage to set up combos.", itemType = "permanent", modelName = "BlackHole"},
        {id = "energy_ball", name = "EnergyBall", displayName = "Energy Ball", price = 4000, icon = "⚡", short = "Straight railgun · instant kill", desc = "Railgun aimed from the Hill. A purple energy ball flies straight and instantly kills runners it hits. 1.5s charge.", itemType = "permanent", modelName = "EnergyBall", imageId = "97680259293580"},
        {id = "bear_trap",   name = "bear_trap",  displayName = "Bear Trap",   price = 1500, icon = "🪤", short = "Placed snare trap", desc = "A trap placed on the ground. Snares and kills any runner who steps on it.", itemType = "permanent", modelName = "bear_trap"},
        {id = "tox_box",     name = "tox_box",    displayName = "Tox Box",     price = 2500, icon = "☣️", short = "Toxic zone · damage over time", desc = "Deploys a poison zone that deals continuous damage.", itemType = "permanent", modelName = "tox_box"},
        {id = "tsunami",     name = "tsunami",    displayName = "Tsunami",     price = 3000, icon = "🌊", short = "Wide-area wave sweep", desc = "Unleashes a tidal wave that sweeps runners across a wide area at once.", itemType = "permanent", modelName = "tsunami"},
        {id = "tnt",         name = "tnt",        displayName = "Bomb",        price = 4000, icon = "💣", short = "Area explosion · instant kill", desc = "Throw a bomb that explodes on impact, instantly killing runners in a wide area.", itemType = "permanent", modelName = "tnt"},
    },
    skin = {
        {id = "kill_effect_fire",      name = "Fire Kill",    price = 4000,  icon = "🔥", short = "Flames on kill", desc = "Triggers a fire effect when you eliminate a runner as the King.",       itemType = "permanent"},
        {id = "kill_effect_lightning", name = "Lightning Kill",    price = 10000, icon = "⚡", short = "Lightning on kill", desc = "Triggers a lightning strike when you eliminate a runner as the King.",       itemType = "permanent"},
        {id = "kill_effect_ice",       name = "Ice Kill",    price = 25000, icon = "🧊", short = "Frost bundle exclusive", desc = "Part of the Frost Lord bundle (R$799). Freezes runners on elimination.", itemType = "permanent", bundlePass = 1918658457},
        {id = "kill_effect_water",     name = "Water Kill",    price = 10000, icon = "💧", short = "Water prison on kill", desc = "Triggers a water prison effect when you eliminate a runner as the King.",    itemType = "permanent"},
        {id = "kill_effect_coffin",    name = "Death Coffin",  price = 25000, icon = "⚰️", short = "Coffin cutscene on kill", desc = "Traps the runner in a coffin cutscene when you eliminate them as the King.", itemType = "permanent"},
        {id = "kill_effect_rainbow",   name = "Rainbow Kill",  price = 4000,  icon = "🌈", short = "Rainbow on kill",   desc = "Triggers a rainbow effect when you eliminate a runner as the King.",       itemType = "permanent"},
        {id = "kill_effect_swordrain", name = "Sword Rain",    price = 10000, icon = "⚔️", short = "Sword rain on kill",     desc = "Rains swords down when you eliminate a runner as the King.",     itemType = "permanent"},
        {id = "kill_effect_hellfire",  name = "Hellfire",    price = 10000, icon = "😈", short = "Hellfire on kill",   desc = "Bursts hellfire when you eliminate a runner as the King.",       itemType = "permanent"},
        {id = "kill_effect_glitch",    name = "Glitch Kill",    price = 25000, icon = "📺", short = "Glitch on kill",   desc = "Triggers a glitch effect when you eliminate a runner as the King.",       itemType = "permanent"},
        {id = "kill_effect_tornado",   name = "Tornado Kill",  price = 25000, icon = "🌪️", short = "Tornado on kill",   desc = "Flings the runner away in a tornado when you eliminate them as the King.", itemType = "permanent"},
        {id = "kill_effect_portal",    name = "Portal Kill",      price = 25000, icon = "🌀", short = "Portal on kill",     desc = "Sucks the runner into a void portal when you eliminate them as the King.",     itemType = "permanent"},
        {id = "kill_effect_grave",     name = "Grave Kill",  price = 10000, icon = "🪦", short = "Gravestone on kill",     desc = "Triggers a gravestone and ghost effect when you eliminate a runner as the King.",       itemType = "permanent"},
        {id = "kill_effect_punch",     name = "Punch Kill",      price = 25000, icon = "👊", short = "Punch combo on kill",     desc = "Triggers a rapid punch combo when you eliminate a runner as the King.",         itemType = "permanent"},
    }
}

-- 등급별 가격 티어 (아래 루프들이 참조)
local WEAPON_PRICE   = { Normal = 1000, Rare = 2000, Epic = 3500,  Legendary = 5000 }   -- 러너 웨폰(영구 사이드그레이드)
-- 🧪 [2026-08-29] 러너 소모품 등급별 가격.
--   [기준] 라운드당 1~2개를 부담 없이 챙기도록. 판당 수입 약 150 기준
--     1개는 여유, 2개는 고민되는 수준으로 잡았다.
--   [Normal 50 인 이유] 러너 최악의 판(초반 사망) 수입이 55다. 그 판에도
--     소모품 하나는 사고 5가 남게 한다.
--     ⚠️ 1단계 목표가 "절반 처치"라 판마다 절반은 이 구간을 겪는다.
--       설계상 정상인 상황인데 보상까지 0 이면 유저는 "내가 못해서"로 받아들인다.
--       저연령층 비중이 큰 만큼 바닥을 보장한다.
--   [비교 기준] 데일리 완주 900 = 소모품 약 7개. 웨폰 Normal 1000 = 약 8개.
--     소모품 8개 ≈ 영구 무기 1개가 되어 "며칠 쓸 소모품 vs 영구 무기" 선택이 성립한다.
--   ⚠️ 값을 바꿀 때는 라운드 보상(RoundSystem)과 함께 볼 것. 판당 수입이 바뀌면
--     "1~2개" 기준이 그대로 깨진다.
local CONSUMABLE_PRICE = { Normal = 50, Rare = 100, Epic = 150, Legendary = 200 }
local COSMETIC_PRICE = { Normal = 1500, Rare = 4000, Epic = 10000, Legendary = 25000 }  -- 트레일/대시/크라운/킬이펙트(최장기 목표)
local EMOTE_PRICE    = { Normal = 400,  Rare = 900,  Epic = 2000,  Legendary = 4000 }   -- 이모트(가벼운 컬렉션·충동구매)
-- ITEM COLOR: 무기 × 색 개별 해금 (Has_<prefix>_<색>). 색 하나가 무기 하나에만 적용됨.
-- 800: 트레일/대시 Normal(1500)은 아이템 하나가 통째로 바뀌는 것, 색놀이는 팔레트 스왑이라 더 가볍게.
--      박스에서도 나오므로(kind="icolor") 확정 구매 프리미엄만 얹은 수준.
local ITEM_COLOR_PRICE = 800

-- 이미지 이모트(무료 제외)를 skin 카테고리에 편입 (EmoteData 단일 소스 = rarity 기반 가격/아이콘/imageId)
do
	local RS = game:GetService("ReplicatedStorage")
	local ok, EmoteData = pcall(require, RS:WaitForChild("EmoteData"))
	if ok and type(EmoteData) == "table" then
		for _, e in ipairs(EmoteData) do
			if not e.free and not e.passExclusive then   -- 무료 이모트는 상점 미노출
				table.insert(shopItems.skin, {
					id = e.id, name = e.name, price = EMOTE_PRICE[e.rarity] or 400,
					icon = e.icon or "🎭", imageId = e.imageId or "",
					short = "Emote", desc = e.name .. " emote", itemType = "permanent", sub = "emote",
				})
			end
		end
	end
end

-- 러너 근접 무기를 runner 카테고리에 편입 (WeaponData 단일 소스, sub=weapon). 사이드그레이드.
do
	local RS = game:GetService("ReplicatedStorage")
	local ok, WeaponData = pcall(require, RS:WaitForChild("WeaponData"))
	if ok and type(WeaponData) == "table" then
		for _, w in ipairs(WeaponData) do
			table.insert(shopItems.runner, {
				id = w.id, name = w.name, price = WEAPON_PRICE[w.rarity] or 2000,
				icon = "⚔️", imageId = "", modelName = w.modelName,
				short = w.short or "Melee weapon", desc = w.desc or w.name,
				itemType = "permanent", sub = "weapon", faction = "runner",
			})
		end
	end
end

-- 트레일 스킨을 skin 카테고리에 편입 (TrailData 단일 소스, 희귀도 티어 가격)
do
	local RS = game:GetService("ReplicatedStorage")
	local ok, TrailData = pcall(require, RS:WaitForChild("TrailData"))
	if ok and type(TrailData) == "table" then
		for _, t in ipairs(TrailData) do
			if t.passExclusive then continue end   -- 패스 전용 스킨은 상점 제외
			table.insert(shopItems.skin, {
				id = t.id, name = t.name, price = COSMETIC_PRICE[t.rarity] or 4000,
				icon = t.icon or "✨", imageId = t.imageId or "", skinKey = t.skinKey,
				short = "Trail skin", desc = t.desc or (t.name .. " trail"),
				-- faction 미지정 = 역할 공용. 트레일은 "움직인 흔적"이라 태거/러너 모두 어울리고
				-- 밸런스 영향도 없어서 공용으로 연다(대시=러너 스킬, 크라운=태거 상징과 다름).
				-- faction 을 넣으면 상점에 "RUNNER ONLY" 배지가 붙어 구매를 망설이게 된다.
				itemType = "permanent", sub = "trail",
			})
		end
	end
end

-- 크라운 스킨을 skin 카테고리에 편입 (CrownData 단일 소스)
do
	local RS = game:GetService("ReplicatedStorage")
	local ok, CrownData = pcall(require, RS:WaitForChild("CrownData"))
	if ok and type(CrownData) == "table" then
		for _, c in ipairs(CrownData) do
			table.insert(shopItems.skin, {
				id = c.id, name = c.name, price = COSMETIC_PRICE[c.rarity] or 4000,
				icon = c.icon or "👑", imageId = c.imageId or "", skinKey = c.skinKey,
				short = "Crown skin", desc = c.desc or (c.name .. " crown"),
				itemType = "permanent", sub = "crown", faction = "tagger",
			})
		end
	end
end

-- 대시 스킨을 skin 카테고리에 편입 (DashData 단일 소스)
do
	local RS = game:GetService("ReplicatedStorage")
	local ok, DashData = pcall(require, RS:WaitForChild("DashData"))
	if ok and type(DashData) == "table" then
		for _, d in ipairs(DashData) do
			if d.passExclusive then continue end   -- 패스 전용 스킨은 상점 제외
			table.insert(shopItems.skin, {
				id = d.id, name = d.name, price = COSMETIC_PRICE[d.rarity] or 4000,
				icon = d.icon or "💨", imageId = d.imageId or "", skinKey = d.skinKey,
				short = "Dash skin", desc = d.desc or (d.name .. " dash"),
				itemType = "permanent", sub = "dash", faction = "runner",
			})
		end
	end
end

-- 스킨 종류(sub) 태깅: 이모트=emote(위에서 부여), 나머지(킬이펙트)=effect
for _, it in ipairs(shopItems.skin) do it.sub = it.sub or "effect" end

local itemLookup = {}
local permByBase = {}    -- baseId → 영구 SKU item
local consumByBase = {}  -- baseId → 소모(1판) SKU item
for _, category in pairs(shopItems) do
    for _, item in ipairs(category) do
        itemLookup[item.id] = item
        if item.baseId then
            if item.itemType == "permanent" then
                permByBase[item.baseId] = item
            elseif item.itemType == "consumable" then
                consumByBase[item.baseId] = item
            end
        end
    end
end

-- Kill-effect prices auto-derive from EffectSystem's live rarity (single source of truth),
-- using the same COSMETIC_PRICE tier map as trails/crowns/dashes. ShopSystem may load
-- before EffectSystem, so wait for _G.KILL_EFFECTS. itemLookup shares these table refs,
-- so updating it.price here keeps the displayed price and the charged price in sync.
-- (The hardcoded prices in shopItems.skin act as a fallback if _G.KILL_EFFECTS never loads.)
task.spawn(function()
    local ke
    for _ = 1, 300 do
        ke = _G.KILL_EFFECTS
        if ke then break end
        task.wait(0.1)
    end
    if not ke then return end
    local rarityById = {}
    for _, e in ipairs(ke) do rarityById[e.id] = e.rarity end
    local synced = 0
    for _, it in ipairs(shopItems.skin) do
        local r = rarityById[it.id]
        if r and COSMETIC_PRICE[r] then
            it.price = COSMETIC_PRICE[r]
            synced += 1
        end
    end
    print(string.format("[Shop] 킬이펙트 가격 등급 동기화: %d종 (COSMETIC_PRICE 기준)", synced))
end)

-- ITEM COLOR 색놀이를 skin 카테고리에 편입 (무기 × 색 개별 해금)
-- 소유는 Has_<prefix>_<색> (예: Has_PushColor_Violet). prefix는 아이템마다 다름 —
-- ItemColorServer.ownsColor()가 cfg.colorOwnPrefix로 읽고, 박스(grantRandomSkin kind="icolor")도 같은 속성을 부여함.
-- 즉 박스에서 나오던 걸 상점에서 확정 구매할 수 있게 하는 것. 박스 풀은 그대로 유지됨.
-- ⚠ _G 의존(SkinManager) → 로드 순서 보장 없어 대기 필요. itemLookup에도 직접 넣어야 구매가 됨.
task.spawn(function()
    local t = 0
    while not (_G.ITEM_COLOR_WEAPONS and _G.ITEM_COLOR_PAID) do
        if t >= 15 then warn("[Shop] ITEM_COLOR 목록 없음 → 색놀이 미판매") return end
        task.wait(0.1); t += 0.1
    end
    local RS = game:GetService("ReplicatedStorage")
    local okP, palette = pcall(require, RS:WaitForChild("NoobColorPalette"))
    if not okP then warn("[Shop] NoobColorPalette require 실패") return end

    -- 팩션/종류 (LoadoutPreviewClient 323줄 "태거: ITEM(4) / WEAPON(PushTool)" 기준 실측)
    local FACTION = {
        stone = "tagger", tsunami = "tagger", tox_box = "tagger", tnt = "tagger",
        Spear = "tagger", Demonspear = "tagger", PushTool = "tagger",
        ["Wooden Barrel"] = "tagger",
        ClassicSword = "runner", KatanaSword2 = "runner",
        HammerLow = "runner", HammerHigh = "runner", SakuraBlade = "runner",
    }
    -- ⚠️ ITEM_COLOR_WEAPONS 에 아이템을 추가하면 여기에도 반드시 넣을 것.
    --    빠지면 아래 `or "runner"` 폴백을 타서 엉뚱한 탭에 들어간다
    --    (실측 2026-08-21: Wooden Barrel 이 RUNNER WPN 탭에 노출됨).
    --    키에 공백이 있으면 ["..."] 형태로 써야 한다.
    -- 태거는 던지는 아이템 vs 근접 웨폰(PushTool)이 갈림. 러너는 전부 웨폰.
    local KIND = { PushTool = "weapon" }

    local added = 0
    for _, w in ipairs(_G.ITEM_COLOR_WEAPONS) do
        local cfg = palette.getConfig and palette.getConfig(w.item)
        local hide = cfg and cfg.hideColors   -- 인벤에서 숨긴 색은 상점에도 미노출(허상 방지)
        local fac = FACTION[w.item] or "runner"
        local knd = KIND[w.item] or (fac == "tagger" and "item" or "weapon")
        for _, colorName in ipairs(_G.ITEM_COLOR_PAID) do
            if not (hide and hide[colorName]) then
                local c = palette.COLORS[colorName]
                if c then
                    local entry = {
                        id = "icolor_" .. w.prefix .. "_" .. colorName,
                        name = w.display .. " " .. colorName,
                        price = ITEM_COLOR_PRICE,
                        icon = "🎨", imageId = "",
                        swatch = { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) },
                        previewModel = w.item,          -- ReplicatedStorage.SkinPreviews 의 모델명 (클라 3D 썸네일)
                        faction = fac,
                        short = w.display .. " Color",
                        desc = w.display .. " in " .. colorName .. ". Also pick the material under ITEM COLOR.",
                        -- sub을 팩션·종류별로 쪼갬: 클라 필터칩이 sub 1개 기준(1단)이라
                        -- 하나로 두면 108개가 한 덩어리로 쏟아짐. 쪼개면 기존 칩 시스템이 그대로 처리.
                        itemType = "permanent", sub = "ic_" .. fac .. "_" .. knd,
                        skinAttr = "Has_" .. w.prefix .. "_" .. colorName,
                    }
                    table.insert(shopItems.skin, entry)
                    itemLookup[entry.id] = entry
                    added += 1
                end
            end
        end
    end
    print("[Shop] ITEM COLOR " .. added .. "종 편입 (" .. #_G.ITEM_COLOR_WEAPONS .. "무기 × " .. #_G.ITEM_COLOR_PAID .. "색)")
end)

-- 건틀릿 색을 skin 카테고리에 편입. 소유는 Has_GColor_<색> (GauntletColorServer.ownsColor가 읽음).
-- 박스(buildSkinPool kind="gcolor")와 같은 속성이라 상점 구매 = 박스 획득과 동일 효과.
-- 칩은 RUNNER WPN(ic_runner_weapon)에 합류 — 건틀릿은 러너 무기이고,
-- 9종뿐이라 전용 탭을 파면 다른 칩들과 균형이 안 맞음.
-- ⚠ 판매 제외: SPECIAL(rainbow, 박스 Epic) / FINISH(gold·silver·bronze, 박스 Rare).
--    금·은을 코인으로 풀면 "메탈+옐로=금색" 희소성 정책(ITEM_COLOR_PREMIUM)과 어긋남.
task.spawn(function()
    local SS = game:GetService("ServerStorage")
    local mod = SS:WaitForChild("GauntletColorPalette", 15)
    if not mod then warn("[Shop] GauntletColorPalette 없음 → 건틀릿 색 미판매") return end
    local okG, gp = pcall(require, mod)
    if not okG or not gp then warn("[Shop] GauntletColorPalette require 실패") return end
    if not (gp.PAID_COLORS and gp.PALETTE) then warn("[Shop] GauntletColorPalette 구조 불일치") return end

    local gAdded, gSkip = 0, 0
    for _, colorName in ipairs(gp.PAID_COLORS) do
        local isSpecial = gp.SPECIAL and gp.SPECIAL[colorName]
        local isFinish  = gp.FINISH  and gp.FINISH[colorName]
        local c = gp.PALETTE[colorName]
        if isSpecial or isFinish or not c then
            gSkip += 1                      -- 박스 전용 (또는 정적 색값 없음)
        else
            local disp = colorName:sub(1,1):upper() .. colorName:sub(2)
            local entry = {
                id = "gcolor_" .. colorName,
                name = "Gauntlet " .. disp,
                price = ITEM_COLOR_PRICE,
                icon = "🥊", imageId = "",
                swatch = { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) },
                previewModel = "Gauntlet",
                faction = "runner",
                short = "Gauntlet Color",
                desc = "Gauntlet in " .. disp .. ".",
                itemType = "permanent", sub = "ic_runner_weapon",
                skinAttr = "Has_GColor_" .. colorName,
            }
            table.insert(shopItems.skin, entry)
            itemLookup[entry.id] = entry
            gAdded += 1
        end
    end
    print("[Shop] GAUNTLET COLOR " .. gAdded .. "종 편입 (박스 전용 " .. gSkip .. "종 제외)")
end)

getItemsEvent.OnServerInvoke = function(player, category)
    -- 🗂️ [2026-08-27] 탭 배정을 faction 기준으로 전환.
    --   [왜] 인벤토리는 역할 우선(King: Item/Weapon/Crown | Runner: Item/Weapon/Dash/Trail)인데
    --     상점은 종류 우선(Runner/Tagger/Skin)이라 같은 물건이 '살 때'와 '낄 때' 다른 곳에 있었다.
    --     게다가 Skin 탭에 칩이 8개 몰려 KING FIST 가 화면 밖으로 잘렸다(실측 2026-08-27).
    --   [방식] 모든 SKU 에 faction 이 이미 붙어 있다:
    --     crown=tagger / dash·weapon=runner / ic_*=각 진영 / effect·emote·trail=없음(공용).
    --     그 값을 그대로 탭 배정에 쓴다 — 하드코딩 목록이 없으므로 새 SKU 는
    --     faction 만 붙이면 자동으로 올바른 탭에 들어간다.
    --   ⚠️ 클라의 카테고리 문자열("runner"/"tagger"/"skin")은 그대로 둔다.
    --     탭 배선·색·딥링크(tabHint)를 건드리지 않기 위해서다. 바뀌는 건 '무엇을 돌려주느냐' 뿐.
    --   ⚠️ 칩 바는 클라가 반환 목록의 sub 값에서 자동 생성한다(ShopClient buildSubChips).
    --     따라서 칩 재배치를 위해 클라를 손댈 필요가 없다.
    --   ⚠️ 아이템 '참조'를 담는다. 복사본을 만들면 아래 킬이펙트 이미지 주입이 원본에 안 남아
    --     호출마다 다시 계산된다.
    local function collectByFaction(base, fac)
        local list = {}
        for _, it in ipairs(base or {}) do list[#list + 1] = it end
        for _, it in ipairs(shopItems.skin or {}) do
            if it.faction == fac then list[#list + 1] = it end
        end
        return list
    end

    local items
    if category == "runner" then
        items = collectByFaction(shopItems.runner, "runner")
    elseif category == "tagger" then
        items = collectByFaction(shopItems.tagger, "tagger")
    elseif category == "skin" then
        items = collectByFaction(nil, nil)   -- faction 없는 것만 = 공용(effect/emote/trail)
    else
        items = shopItems[category] or {}
    end
    -- 킬이펙트 배지 이미지/튜닝값을 단일 소스(_G.KILL_EFFECTS)에서 실어줌 → 인벤과 동일 표현
    local ke = _G.KILL_EFFECTS
    if ke then
        local byId = {}
        for _, e in ipairs(ke) do byId[e.id] = e end
        for _, it in ipairs(items) do
            local src = byId[it.id]
            if src and src.imageId and src.imageId ~= "" then
                it.imageId  = src.imageId
                it.imgScale = src.imgScale
                it.imgOffX  = src.imgOffX
                it.imgOffY  = src.imgOffY
                it.shopScale = src.shopScale   -- 상점 전용 크기 오버라이드 (없으면 클라가 imgScale 폴백)
                it.shopOffX  = src.shopOffX
                it.shopOffY  = src.shopOffY
            end
        end
    end
    return items
end

purchaseEvent.OnServerEvent:Connect(function(player, itemId, category, itemType)
    local itemData = itemLookup[itemId]
    if not itemData then
        purchaseResultEvent:FireClient(player, false, "This item does not exist.")
        return
    end

    -- 번들 전용 아이템은 코인 구매 불가 → 로벅스 번들로만 (클라 자물쇠 UI + 서버 익스플로잇 방지)
    if itemData.bundlePass then
        purchaseResultEvent:FireClient(player, false, "Bundle-exclusive item. Buy it through the Robux bundle.")
        return
    end

    -- 영구 아이템만 중복 구매 차단. 소모품은 반복 구매 허용(수량 누적)
    -- 무기 스킨은 소유가 Has_<skinName> 계열이라 OwnedItem_ 이 아님 → skinAttr로 판정.
    if itemData.itemType == "permanent" then
        local ownedAttr = itemData.skinAttr or ("OwnedItem_" .. itemId)
        if player:GetAttribute(ownedAttr) then
            purchaseResultEvent:FireClient(player, false, "You already own this item.")
            return
        end
    end

    -- 영구 보유 시 같은 baseId 소모(1판) SKU 구매 거부 (죽은 패스 재구매 방지)
    if itemData.itemType == "consumable" and itemData.baseId then
        local perm = permByBase[itemData.baseId]
        if perm and player:GetAttribute("OwnedItem_" .. perm.id) then
            purchaseResultEvent:FireClient(player, false, "You already own the permanent version.")
            print("🚫 영구 보유—소모 구매 거부:", player.Name, itemId)
            return
        end
    end

    -- [CONSUM-CAP] 소모품 보유 상한.
    --   ⚠️ 반드시 코인 차감(아래 removeCoins)보다 앞에서 검사해야 한다.
    --      뒤에 두면 "코인만 빠지고 수량은 안 느는" 최악이 된다.
    --   라운드당 로드아웃 1칸 = 1개만 소비되므로 50개 = 약 50판 분량.
    --   상한을 두는 이유: ①코인 싱크 유지(다시 사러 오는 주기) ②인벤 수량 배지
    --   2자리 유지 ③코인 폭주·환불 버그 시 피해를 50개에서 차단.
    if itemData.itemType == "consumable" then
        -- GetConsumableCount 는 데이터 미로드 시 nil 을 준다.
        -- nil 은 "0개"가 아니라 "모름"이므로, 막지 말고 통과시킨다
        -- (막으면 로드 지연 중인 정상 유저의 구매가 거부된다).
        local have = _G.GetConsumableCount and _G.GetConsumableCount(player, itemData.name)
        if type(have) == "number" and have >= CONSUMABLE_CAP then
            purchaseResultEvent:FireClient(player, false,
                "You can hold up to " .. CONSUMABLE_CAP .. " of this item.")
            print("🚫 소모품 상한 도달 — 구매 거부:", player.Name, itemData.name, have .. "/" .. CONSUMABLE_CAP)
            return
        end
    end

    -- 코인 입출은 CoinSystem 경유(내부 store + UI UpdateCoinEvent 동기화). raw SetAttribute는 UI/정합성 desync 유발.
    local CoinSystem = _G.CoinSystem
    local coins = CoinSystem and CoinSystem.getCoins(player) or (player:GetAttribute("Coins") or 0)
    if coins < itemData.price then
        purchaseResultEvent:FireClient(player, false, "Not enough coins. (" .. coins .. "/" .. itemData.price .. ")")
        return
    end

    if CoinSystem then
        CoinSystem.removeCoins(player, itemData.price)
    else
        player:SetAttribute("Coins", coins - itemData.price)
    end

    if itemData.itemType == "permanent" then
        if itemData.skinAttr then
            -- 무기 스킨: Has_ 계열이라 GrantOwnedPermanent(=OwnedItem_) 경로가 아님.
            -- DataService.Skins에 넣어야 영속됨 (SkinManager.restoreSkins가 조인 시 Has_로 복원).
            player:SetAttribute(itemData.skinAttr, true)
            local d = _G.DataService and _G.DataService.get(player)
            if d and type(d.Skins) == "table" then
                d.Skins[itemData.skinAttr] = true
            else
                warn("[Shop] DataService 프로필 미로드 → 스킨 영속 실패:", player.Name, itemData.skinAttr)
            end
        -- 영구 해금 + DataStore 지속 (LoadoutManager가 ownedPermanents로 저장/복원)
        elseif _G.GrantOwnedPermanent then
            _G.GrantOwnedPermanent(player, itemId)
        else
            player:SetAttribute("OwnedItem_" .. itemId, true)
        end

        -- 같은 baseId 남은 1판권 전액 환불 + 소모 수량 정리(playerConsumables + 표시 어트리뷰트)
        -- 현재가 기준. 향후 기간한정 할인 SKU 도입 시 '지불가 추적'으로 바꿔야 익스플로잇 방지.
        local consumSku = consumByBase[itemData.baseId or ""]
        if consumSku and _G.ClearConsumable then
            local leftover = _G.ClearConsumable(player, consumSku.name)  -- 정리 전 수량
            if leftover and leftover > 0 then
                player:SetAttribute("Consumable_" .. consumSku.id, 0)
                local refund = leftover * consumSku.price
                if _G.CoinSystem then
                    _G.CoinSystem.addCoins(player, refund)
                else
                    player:SetAttribute("Coins", (player:GetAttribute("Coins") or 0) + refund)
                end
                print("💸 1판권 환불:", player.Name, consumSku.name, "×", leftover, "→ +", refund, "코인")
            end
        end
    else
        -- 소모품: 인벤 수량 지급 (반복 구매 = 수량 누적)
        if itemData.modelName then
            local c = player:GetAttribute("Consumable_" .. itemId) or 0
            player:SetAttribute("Consumable_" .. itemId, c + 1)
            if _G.AddConsumable then _G.AddConsumable(player, itemData.name) end
        end
    end

    -- [CONSUM-CAP] 잔여코인은 CoinSystem.getCoins 로 읽는다.
    --   player:GetAttribute("Coins") 는 갱신이 한 박자 늦어 차감 전 값을 찍었다
    --   (실측 2026-08-20: 실제 145846 인데 로그엔 145946 → "코인이 안 빠졌다"고 오진).
    local leftCoins = CoinSystem and CoinSystem.getCoins(player) or player:GetAttribute("Coins")
    print("🛒 구매 완료:", player.Name, "→", itemId, "| 잔여코인:", leftCoins)
    purchaseResultEvent:FireClient(player, true, (itemData.displayName or itemData.name) .. " purchased!")
end)

print("✅ ShopSystem 준비 완료! (개편판: 더미 제거 + 소모/영구 SKU + short)")
-- ════════════════════════════════════════════════════════════════
-- [ITEM-DESC-SHARE] 아이템 설명을 인벤토리에서도 쓸 수 있게 노출한다.
--   ⚠️ 설명이 상점에만 있어 인벤 툴팁에는 안 보였다. 상점을 안 열면
--      사용법을 알 방법이 없다(실측 2026-08-21).
--      특히 스타터킷으로 9종을 무료 지급하므로 상점에 갈 이유가 더 줄었다.
--   ⚠️ 설명을 두 곳에 중복 정의하면 나중에 어긋난다 → 상점 정의를 단일 소스로 삼는다.
-- ════════════════════════════════════════════════════════════════
do
	local descByName = {}
	for _, group in pairs(shopItems) do
		if type(group) == "table" then
			for _, it in ipairs(group) do
				if it.name and it.desc then descByName[it.name] = it.desc end
			end
		end
	end

	-- 상점에서 팔지 않아 shopItems 에 항목이 없는 것들.
	--   기본 지급(굴리기 3종) / 게임패스(Frost Dragon) / 그룹 보상(ItemNoob).
	--   ⚠️ 판매 항목이 아니므로 shopItems 에 넣으면 상점에 노출된다. 설명만 따로 채운다.
	local EXTRA_DESCS = {
		["stone"]         = "Basic rolling item. Small and quick - roll it down the hill to pick off runners.",
		["Wood Log"]      = "Rolls farther than a stone and knocks down anyone in a line.",
		["Wooden Barrel"] = "The widest roller. Covers a broad lane, hard for runners to dodge.",
		["Frost Dragon"]  = "Game Pass exclusive. Breathes a freezing path that slows and shatters runners.",
		["ItemNoob"]      = "Group reward. Roll a noob down the hill - same idea, more style.",
	}
	for k, v in pairs(EXTRA_DESCS) do
		if not descByName[k] then descByName[k] = v end
	end
	_G.GetItemDesc = function(itemName)
		return itemName and descByName[itemName] or nil
	end
	-- 클라(인벤 툴팁)용. _G 는 서버 전역이라 클라가 못 읽으므로 리모트로 넘긴다.
	--   ⚠️ 매번 호출하지 않도록 클라가 1회 받아 캐시한다.
	local descRemote = ReplicatedStorage:FindFirstChild("GetItemDescs")
	if descRemote and descRemote:IsA("RemoteFunction") then
		descRemote.OnServerInvoke = function()
			return descByName
		end
	end
	print("📖 [ShopSystem] 아이템 설명 " .. (function()
		local n = 0 ; for _ in pairs(descByName) do n = n + 1 end ; return n
	end)() .. "종 노출 (_G.GetItemDesc)")
end
