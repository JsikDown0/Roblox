-- EffectSystem: Emote & Kill Effect 소유/장착 데이터 관리
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local getEffectData     = ReplicatedStorage:WaitForChild("GetEffectData")
local setEquippedEffect = ReplicatedStorage:WaitForChild("SetEquippedEffect")

local emoteEquipChanged = ReplicatedStorage:FindFirstChild("EmoteEquipChanged")
if not emoteEquipChanged then
	emoteEquipChanged = Instance.new("RemoteEvent")
	emoteEquipChanged.Name = "EmoteEquipChanged"
	emoteEquipChanged.Parent = ReplicatedStorage
end

local getEquippedEmotes = ReplicatedStorage:FindFirstChild("GetEquippedEmotes")
if not getEquippedEmotes then
	getEquippedEmotes = Instance.new("RemoteFunction")
	getEquippedEmotes.Name = "GetEquippedEmotes"
	getEquippedEmotes.Parent = ReplicatedStorage
end

-- ── 아이템 정의 ──────────────────────────────────────────────
local KILL_EFFECTS = {
	-- imageId = AI 배지 아트(1024, 검정배경). Decal 업로드분을 LoadAsset으로 resolve한 실제 Image ID.
	-- icon(이모지)은 이미지 로드 실패 시 폴백으로 유지.
	{ id = "kill_effect_fire",      name = "Fire Kill",      icon = "🔥", imageId = "rbxassetid://113983132530699", desc = "Flame effect on kill",        shopScale = 1.14, rarity = "Normal"      },
	{ id = "kill_effect_lightning", name = "Lightning Kill", icon = "⚡", imageId = "rbxassetid://77963973451496",  desc = "Lightning strike on kill",    rarity = "Normal"      },
	{ id = "kill_effect_ice",       name = "Ice Kill",       icon = "🧊", imageId = "rbxassetid://101097619441293", desc = "Freeze victim for 3 seconds", imgScale = 2.28, rarity = "Legendary" },
	{ id = "kill_effect_water",     name = "Water Kill",     icon = "💧", imageId = "rbxassetid://107520640685638", desc = "Trap victim in a water prison", rarity = "Epic"    },
	{ id = "kill_effect_coffin",    name = "Death Coffin",   icon = "⚰️", imageId = "rbxassetid://118691345122577", desc = "Trap victim in a coffin cutscene", imgScale = 1.59, rarity = "Legendary" },
	{ id = "kill_effect_rainbow",   name = "Rainbow Kill",   icon = "🌈", imageId = "rbxassetid://107296032420423", desc = "Rainbow burst on kill", imgScale = 0.9,        rarity = "Rare"      },
	{ id = "kill_effect_swordrain", name = "Sword Rain",     icon = "⚔️", imageId = "rbxassetid://132505607242998", desc = "Swords rain down on kill", imgScale = 4.11, imgOffX = -1.46, shopScale = 2.73, shopOffX = -0.72,     rarity = "Rare"      },
	{ id = "kill_effect_hellfire",  name = "Hellfire",       icon = "😈", imageId = "rbxassetid://100125051239194", desc = "Erupt victim in hellfire",     rarity = "Normal"      },
	{ id = "kill_effect_glitch",   name = "Glitch Kill",    icon = "📺", imageId = "rbxassetid://94879216532441",  desc = "Glitch out the victim on kill", imgScale = 1.05, imgOffX = 0.1, imgOffY = 0.06, shopScale = 1.14, shopOffX = 0.06, shopOffY = 0.06, rarity = "Legendary" },
	{ id = "kill_effect_tornado",  name = "Tornado Kill",   icon = "🌪️", imageId = "rbxassetid://126413122071875", desc = "Launch victim skyward in a tornado", rarity = "Epic" },
	{ id = "kill_effect_portal",   name = "Portal Kill",    icon = "🌀", imageId = "rbxassetid://84905982206863",  desc = "Suck victim into a void portal", rarity = "Epic" },
	-- [비활성화] EMP Kill (확산 개선 보류) — 복구 시 이 줄 주석 해제
	-- { id = "kill_effect_emp",      name = "EMP Kill",       icon = "📡", imageId = "",                             desc = "Expanding EMP field on kill", rarity = "Epic"        },
	{ id = "kill_effect_grave",    name = "Grave Kill",     icon = "🪦", imageId = "rbxassetid://86642710391768",  desc = "Tombstone drops, ghost ascends", imgScale = 1.92, rarity = "Rare"      },
	{ id = "kill_effect_punch",    name = "Punch Kill",     icon = "👊", imageId = "rbxassetid://109485282716972", desc = "Killer's double beats you down", imgScale = 1.59, rarity = "Legendary" },
}
-- 전 배지 기본 크기 1.77 (개별 튜닝 시 해당 행 imgScale이 우선)
for _, e in ipairs(KILL_EFFECTS) do
	if e.imgScale == nil then e.imgScale = 1.77 end
end
_G.KILL_EFFECTS = KILL_EFFECTS   -- 코스메틱 박스 풀 등 외부에서 사용 (SkinManager)

local EMOTES = {}
local FREE_EMOTES = {}   -- [id] = true → 구매 없이 기본 보유
do
	local EmoteData = require(ReplicatedStorage:WaitForChild("EmoteData"))
	for _, e in ipairs(EmoteData) do
		table.insert(EMOTES, {
			id      = e.id,
			name    = e.name,
			icon    = e.icon or "",
			imageId = e.imageId or "",
			desc    = e.desc or e.name,
			rarity  = e.rarity or "Normal",
		})
		if e.free then FREE_EMOTES[e.id] = true end
	end
end

local MAX_EMOTES = 6

-- ── 대시(산데비스탄) 색 스킨 ─────────────────────────────────
-- 장착 시 player.DashSkin 속성을 세팅 → RunnerDive가 읽어 색 적용.
-- skinKey는 RunnerDive의 DASH_SKIN_COLORS 키와 일치해야 함.
local DASH_SKINS = require(game:GetService("ReplicatedStorage"):WaitForChild("DashData"))  -- 단일 소스(ShopSystem 공유)

-- ── 트레일 스킨 ──────────────────────────────────────────────
-- 장착 시 player.TrailSkin 속성을 세팅 → RunnerTrail이 읽어 트레일 적용.
-- skinKey는 RunnerTrail의 TRAIL_SKINS_SPEC 키와 일치해야 함. 단일 장착.
local TRAIL_SKINS = require(game:GetService("ReplicatedStorage"):WaitForChild("TrailData"))  -- 단일 소스(ShopSystem 공유)

-- ── 태거 왕관 스킨 (Tagger Crown) ─────────────────────────────
-- 장착 시 player.CrownSkin 속성을 세팅 → RoundSystem.attachCrownToTagger가 읽어 색/재질 적용.
-- skinKey는 RoundSystem의 CROWN_SKIN_VISUAL 키와 일치해야 함. 단일 장착.
local CROWN_SKINS = require(game:GetService("ReplicatedStorage"):WaitForChild("CrownData"))  -- 단일 소스(ShopSystem 공유)

local equipped = {}

local function getEquipped(player)
	if not equipped[player.UserId] then
		equipped[player.UserId] = { killEffect = nil, emotes = {}, dashSkin = nil, trailSkin = nil, weapon = nil, crownSkin = nil }
	end
	return equipped[player.UserId]
end

local function ownsItem(player, itemId)
	if player:GetAttribute("OwnedItem_" .. itemId) then return true end
	return false
end

local function buildEquippedList(eq)
	local list = {}
	for _, emoteId in ipairs(eq.emotes) do
		for _, e in ipairs(EMOTES) do
			if e.id == emoteId then
				table.insert(list, { id = e.id, icon = e.icon, imageId = e.imageId or "" })
				break
			end
		end
	end
	return list
end

getEffectData.OnServerInvoke = function(player, category)
	local eq = getEquipped(player)
	local list
	if category == "emote" then
		list = EMOTES
	elseif category == "dashSkin" then
		list = DASH_SKINS
	elseif category == "trailSkin" then
		list = TRAIL_SKINS
	elseif category == "crownSkin" then
		list = CROWN_SKINS
	else
		list = KILL_EFFECTS
	end
	local result = {}

	for _, item in ipairs(list) do
		local owned = ownsItem(player, item.id)
		if category == "emote" and FREE_EMOTES[item.id] then owned = true end  -- 무료 이모트는 기본 보유
		local isEquipped = false
		if category == "emote" then
			for _, eid in ipairs(eq.emotes) do
				if eid == item.id then isEquipped = true break end
			end
		elseif category == "dashSkin" then
			isEquipped = (eq.dashSkin == item.id)
		elseif category == "trailSkin" then
			isEquipped = (eq.trailSkin == item.id)
		elseif category == "crownSkin" then
			isEquipped = (eq.crownSkin == item.id)
		else
			isEquipped = (eq.killEffect == item.id)
		end

		table.insert(result, {
			id       = item.id,
			name     = item.name,
			icon     = item.icon,
			imageId  = item.imageId or "",
			imgScale = item.imgScale,   -- 배지별 크기 미세조정 (nil이면 클라 기본 0.72)
			imgOffX  = item.imgOffX,    -- 가로 오프셋 (Scale)
			imgOffY  = item.imgOffY,    -- 세로 오프셋 (Scale)
			desc     = item.desc,
			rarity   = item.rarity,
			owned    = owned,
			equipped = isEquipped,
			skinKey  = item.skinKey,   -- 크라운 프리뷰 조회용 (CrownPreviews[skinKey])
		})
	end

	return result
end

getEquippedEmotes.OnServerInvoke = function(player)
	local eq = getEquipped(player)
	return buildEquippedList(eq)
end

setEquippedEffect.OnServerEvent:Connect(function(player, category, itemId)
	-- ⚠️ [ROUND-LOCK] 라운드 중에는 코스메틱도 바꿀 수 없다.
	--    LoadoutManager 는 이미 막고 있었는데(isRoundActive) 여기엔 없어서
	--    트레일/대시/왕관/킬이펙트가 라운드 도중 실시간으로 바뀌었다
	--    (실측 2026-08-21: 인벤에서 트레일 장착 → 즉시 반영됨).
	--    UI 를 닫는 것만으로는 부족하다 — 리모트는 클라에서 직접 호출할 수 있으므로
	--    서버가 최종 방어선이 되어야 한다.
	do
		local phase = game:GetService("ReplicatedStorage"):GetAttribute("RoundPhase")
		if phase == "stage1" or phase == "stage2" then return end
	end
	local eq = getEquipped(player)

	-- ── 보유 검증 (익스플로잇 차단) ────────────────────────────
	-- 이전엔 weapon 분기에만 검증이 있어서, 클라가 SetEquippedEffect를 직접 쏘면
	-- 미보유 킬이펙트/트레일/대시/왕관/이모트를 그대로 장착할 수 있었음.
	-- (전부 Cosmetic Box 판매 품목 → 상점 우회 경로)
	-- 해제 요청(none/nil)은 항상 허용. 이모트는 OwnedItem_이 아니라 FREE_EMOTES로
	-- 무료분을 관리하므로 그 경로도 함께 허용해야 기본 이모트가 막히지 않음.
	if itemId ~= nil and itemId ~= "none" then
		local allowed = ownsItem(player, itemId)
		if not allowed and category == "emote" and FREE_EMOTES[itemId] then
			allowed = true
		end
		if not allowed then
			print("🚫", player.Name, "미소유 장착 거부:", tostring(category), tostring(itemId))
			return
		end
	end

	if category == "emote" then
		local found = false
		for i, eid in ipairs(eq.emotes) do
			if eid == itemId then
				table.remove(eq.emotes, i)
				found = true
				break
			end
		end
		if not found then
			if #eq.emotes >= MAX_EMOTES then return end
			table.insert(eq.emotes, itemId)
		end

		local equippedList = buildEquippedList(eq)
		emoteEquipChanged:FireClient(player, equippedList)
		print("🎭", player.Name, "Emotes:", #eq.emotes)

	elseif category == "killEffect" then
		local newEffect = (itemId == "none" or itemId == nil) and nil or itemId
		if eq.killEffect == newEffect then newEffect = nil end
		eq.killEffect = newEffect
		player:SetAttribute("EquippedKillEffect", eq.killEffect or "")
		print("💀", player.Name, "KillEffect:", eq.killEffect or "none")

	elseif category == "dashSkin" then
		local newSkin = (itemId == "none" or itemId == nil) and nil or itemId
		if eq.dashSkin == newSkin then newSkin = nil end   -- 같은 거 다시 누르면 해제
		eq.dashSkin = newSkin
		-- skinKey 찾아 DashSkin 속성 세팅 (RunnerDive가 읽음). 해제 시 기본(Default).
		local skinKey = "Default"
		if newSkin then
			for _, s in ipairs(DASH_SKINS) do
				if s.id == newSkin then skinKey = s.skinKey break end
			end
		end
		player:SetAttribute("DashSkin", skinKey)
		print("💨", player.Name, "DashSkin:", eq.dashSkin or "none", "→ key:", skinKey)

	elseif category == "trailSkin" then
		local newSkin = (itemId == "none" or itemId == nil) and nil or itemId
		if eq.trailSkin == newSkin then newSkin = nil end   -- 같은 거 다시 누르면 해제
		eq.trailSkin = newSkin
		-- skinKey 찾아 TrailSkin 속성 세팅 (RunnerTrail이 읽음). 해제 시 빈 문자열 → 트레일 없음.
		local skinKey = ""
		if newSkin then
			for _, s in ipairs(TRAIL_SKINS) do
				if s.id == newSkin then skinKey = s.skinKey break end
			end
		end
		player:SetAttribute("TrailSkin", skinKey)
		print("✨", player.Name, "TrailSkin:", eq.trailSkin or "none", "→ key:", skinKey ~= "" and skinKey or "(none)")

	elseif category == "crownSkin" then
		local newSkin = (itemId == "none" or itemId == nil) and nil or itemId
		if eq.crownSkin == newSkin then newSkin = nil end   -- 같은 거 다시 누르면 해제
		eq.crownSkin = newSkin
		-- skinKey 찾아 CrownSkin 속성 세팅 (RoundSystem이 읽음). 해제 시 기본 Gold.
		local skinKey = "Gold"
		if newSkin then
			for _, s in ipairs(CROWN_SKINS) do
				if s.id == newSkin then skinKey = s.skinKey break end
			end
		end
		player:SetAttribute("CrownSkin", skinKey)
		-- 현재 왕관을 쓰고 있으면 즉시 갱신(라이브 프리뷰)
		if _G.attachCrownToTagger and player.Character and player.Character:FindFirstChild("TaggerCrown") then
			_G.attachCrownToTagger(player)
		end
		print("👑", player.Name, "CrownSkin:", eq.crownSkin or "none", "→ key:", skinKey)

	elseif category == "weapon" then
		-- 2단계 무기: 단일 장착. eq.weapon에 저장 + EquippedWeapon 속성에 박아둠.
		-- Stage2TriggerSystem이 이 속성을 읽어 해당 무기를 지급한다.
		local newWeapon = (itemId == "none" or itemId == nil) and nil or itemId
		if newWeapon and not ownsItem(player, newWeapon) then
			print("🚫", player.Name, "미소유 무기 장착 거부:", newWeapon)
			return
		end
		-- ⚔️ [버그수정 2026-09-02] 무기는 '해제'가 없다. 항상 하나는 장착된 슬롯이다.
		--   [증상] 건틀렛 장착 → 해제 → 장착 시 로드아웃 UI 무기칸이 빈칸으로 보였다.
		--   [원인] 아래 "같은 거 다시 누르면 해제" 토글이 무기에도 걸려 EquippedWeapon 이
		--     "" 이 됐다. 그런데 Stage2TriggerSystem:384 는 비어 있으면 ClassicSword 로
		--     폴백한다 — 실제로는 검을 들고 나가는데 UI 만 '없음'으로 보였다. 정보 불일치.
		--   [해결] 해제를 막고 기본값(ClassicSword)으로 되돌린다. 대시·크라운과 같은 규칙이다
		--     (그쪽도 무료 기본값이 항상 장착돼 있다).
		--   ⚠️ ClassicSword 는 grantFreeSkins 에서 전원에게 소유·장착시키는 기본 무기다.
		--     폴백 대상을 바꾸려면 그쪽과 Stage2TriggerSystem 폴백을 같이 고쳐야 한다.
		if eq.weapon == newWeapon then newWeapon = "ClassicSword" end
		eq.weapon = newWeapon
		player:SetAttribute("EquippedWeapon", eq.weapon or "ClassicSword")
		print("⚔️", player.Name, "Weapon:", eq.weapon or "none")
	end
	if _G.PM_onEdit then _G.PM_onEdit(player) end
end)

Players.PlayerRemoving:Connect(function(player)
	equipped[player.UserId] = nil
end)

-- 기본 무료 스킨 부여 (정식 — raw OwnedItem_이라 지속저장 무관, GrantOwnedPermanent 안 거침).
-- 대시 Cyan / 왕관 Gold: 소유+기본장착. 트레일 White: 소유만.
local function grantFreeSkins(player)
	player:SetAttribute("OwnedItem_dash_default", true)  -- 무료 기본 대시 소유
	local eq = getEquipped(player)
	eq.dashSkin = "dash_default"                         -- 기본 장착 = Cyan
	player:SetAttribute("DashSkin", "Default")           -- RunnerDive가 읽는 키

	player:SetAttribute("OwnedItem_trail_white", true)  -- 트레일 소유만 (자동 장착 X)

	player:SetAttribute("OwnedItem_crown_gold", true)   -- 무료 기본 왕관 소유
	player:SetAttribute("OwnedItem_ClassicSword", true) -- 무료 기본 근접 무기 소유 (Stage2 폴백과 일치)
	eq.weapon = "ClassicSword"                          -- 기본 장착 = Classic Sword (dash/crown과 동일)
	player:SetAttribute("EquippedWeapon", "ClassicSword")
	eq.crownSkin = "crown_gold"                          -- 기본 장착 = Gold
	player:SetAttribute("CrownSkin", "Gold")            -- RoundSystem이 읽는 키
	print("🎁 기본 무료 스킨 부여:", player.Name, "(dash_default·crown_gold 장착 / trail_white 소유)")
end
Players.PlayerAdded:Connect(grantFreeSkins)
for _, p in ipairs(Players:GetPlayers()) do grantFreeSkins(p) end

print("✅ EffectSystem ready! (multi-emote + ice kill + water kill + dashSkin + trailSkin)")

-- ── 프리셋 시스템용 노출 (PresetManager가 capture/apply에 사용) ──
local function _es_skinKeyOf(list, id, default)
	if id then
		for _, s in ipairs(list) do
			if s.id == id then return s.skinKey end
		end
	end
	return default
end

_G.ES_getEquipped = function(player)
	local eq = getEquipped(player)
	-- emotes는 배열이라 참조를 넘기면 프리셋 저장 후에도 라이브 변경이 따라 들어감
	-- (에일리어싱) → 복사본으로. 순서 그대로 보존.
	local emotes = {}
	for i, id in ipairs(eq.emotes) do emotes[i] = id end
	return {
		crownSkin  = eq.crownSkin,
		killEffect = eq.killEffect,
		dashSkin   = eq.dashSkin,
		trailSkin  = eq.trailSkin,
		weapon     = eq.weapon,
		emotes     = emotes,
	}
end

-- 토글 없이 blob 값으로 직접 세팅. blob은 서버 캡처라 유효(무기만 방어적 소유 검증).
_G.ES_applyEquipped = function(player, blob)
	if type(blob) ~= "table" then return end
	local eq = getEquipped(player)

	-- 소유 검증: blob이 서버 캡처라도 무조건 신뢰하면 안 됨.
	-- 리모트에 검증이 없던 시기에 캡처된 프리셋이 DataStore에 남아 있으면
	-- 프리셋 전환 때마다 미보유 코스메틱이 계속 재적용됨 → 적용 시점에도 확인.
	local function keepIfOwned(id)
		if id and not ownsItem(player, id) then return nil end
		return id
	end
	local kKill  = keepIfOwned(blob.killEffect)
	local kDash  = keepIfOwned(blob.dashSkin)
	local kTrail = keepIfOwned(blob.trailSkin)
	local kCrown = keepIfOwned(blob.crownSkin)

	eq.killEffect = kKill
	player:SetAttribute("EquippedKillEffect", kKill or "")

	eq.dashSkin = kDash
	player:SetAttribute("DashSkin", _es_skinKeyOf(DASH_SKINS, kDash, "Default"))

	eq.trailSkin = kTrail
	player:SetAttribute("TrailSkin", _es_skinKeyOf(TRAIL_SKINS, kTrail, ""))

	eq.crownSkin = kCrown
	player:SetAttribute("CrownSkin", _es_skinKeyOf(CROWN_SKINS, kCrown, "Gold"))
	if _G.attachCrownToTagger and player.Character and player.Character:FindFirstChild("TaggerCrown") then
		_G.attachCrownToTagger(player)
	end

	local weapon = blob.weapon
	if weapon and not ownsItem(player, weapon) then weapon = nil end
	eq.weapon = weapon
	player:SetAttribute("EquippedWeapon", weapon or "")

	-- 이모트 복원: 순서 유지 + 리모트 핸들러와 동일한 검증(보유 or 무료) + 상한.
	-- 검증을 빼면 프리셋이 미보유 이모트 장착 우회로가 됨.
	if type(blob.emotes) == "table" then
		local restored = {}
		for _, id in ipairs(blob.emotes) do
			if #restored >= MAX_EMOTES then break end
			if type(id) == "string" and (ownsItem(player, id) or FREE_EMOTES[id]) then
				local dup = false
				for _, x in ipairs(restored) do if x == id then dup = true break end end
				if not dup then restored[#restored+1] = id end
			end
		end
		eq.emotes = restored
		if emoteEquipChanged then
			emoteEquipChanged:FireClient(player, buildEquippedList(eq))
		end
	end
end

-- [TEST] 모든 킬이펙트 언락 (/fxunlock에서 호출)
_G.UnlockAllKillEffects = function(player)
	local n = 0
	for _, item in ipairs(KILL_EFFECTS) do
		player:SetAttribute("OwnedItem_" .. item.id, true)
		n = n + 1
	end
	return n
end
