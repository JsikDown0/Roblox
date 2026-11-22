-- BattlePassSystem: session-only battle pass XP + tier (slice 1, no persistence yet).
-- XP is granted by RoundSystem (round complete) and QuestSystem (quest reward).
-- Exposes _G.BattlePass = { addXP, getXP, getTier, ... }.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local PREMIUM_PRODUCT_ID = 3609062110   -- dev product: Summer S1 premium (R$499)
-- dev product: Collector Pack (R$79) = Color Skin Box x5.
-- 패스가 아닌 이유: 박스는 소모품이라 반복 구매가 정상. 패스는 1인 1개라 평생 한 번밖에 못 삼.
local COLLECTOR_PRODUCT_ID = 3610453697

local XP_PER_TIER      = 800    -- XP per tier
local MAX_TIER         = 30
local ROUND_XP         = 100    -- XP per round completed
-- 시즌 설계: 30일 시즌 + 1주 휴식(= 5주 주기, Roblox 공식 권장 형태).
-- 완주 기준은 35일 — 라운드만 도는 라이트 유저도 시즌 안에 만렙에 닿게 한다.
--   29티어 × 800 = 23,200 XP
--   라이트(라운드만, 700/일)      → 약 33일
--   중간(라운드+일일퀘, 1450/일)  → 약 16일
--   헤비(전부, 1600/일)           → 약 15일
-- ⚠️ 이 값을 500에서 700으로 올린 이유: XP_PER_TIER 를 낮추면 라이트는 맞출 수 있으나
--    헤비가 더 빨라져 만렙 후 공백이 커진다. 상한 인상은 이미 상한을 채우는 헤비에게
--    영향이 적어, 라이트만 끌어올리며 격차를 좁힌다(46↔17일 → 33↔15일).
local DAILY_ROUND_CAP  = 700    -- max round XP per day (quests are separate)
local QUEST_XP_DEFAULT = 150    -- XP per quest reward if not specified
-- 친구 동시 접속 보너스: 라운드 상한과 별도로 집계한다.
-- 같은 상한에 넣으면 상한을 채우는 유저에게 보너스가 0이 되어 목적을 잃는다.
-- 120/일 → 라운드만 완주 34일 → 29일 (5일 단축, 시즌 여유 +5500).
local FRIEND_XP_CAP    = 120    -- max friend-bonus XP per day
local FRIEND_XP_EACH   = 10     -- XP per co-present friend, per round
local FRIEND_MAX_COUNT = 3      -- 최대 인정 친구 수

-- session state (resets on server restart / F5)
local xpByUser         = {}  -- [userId] = total XP
local roundXpTodayByUser = {} -- [userId] = round XP earned today
local friendXpTodayByUser = {} -- [userId] = friend-bonus XP earned today
local lastDayByUser    = {}  -- [userId] = day string

-- ===== Persistence (DataStore, season-scoped) =====
local DataStoreService = game:GetService("DataStoreService")
-- 시즌 번호는 ReplicatedStorage.SeasonConfig 가 단독 관리한다 (리더보드와 공유).
-- 시즌 전환 시 SeasonConfig.SEASON_NUMBER 만 올리면 배틀패스 + 리더보드가 함께 넘어간다.
-- keyFor 결과는 기존과 동일한 "season1_<userId>" 형식 → 저장 데이터 호환 유지.
local SeasonConfig     = require(game:GetService("ReplicatedStorage"):WaitForChild("SeasonConfig"))
local bpStore          = DataStoreService:GetDataStore("BattlePassData_v1")
local receiptStore     = DataStoreService:GetDataStore("ProcessedReceipts_v1")   -- 개발자상품 중복 지급 방지
local function keyFor(userId) return SeasonConfig.battlePassKey(userId) end
local loadedByUser     = {}  -- [userId] = true once loaded (guards early saves)

-- claim tracking (session; persisted)
local claimedByUser = {}  -- [userId] = { free={[tier]=true}, prem={[tier]=true} }
local function ensureClaimed(uid)
	if not claimedByUser[uid] then claimedByUser[uid] = { free = {}, prem = {} } end
	return claimedByUser[uid]
end

-- DataStore JSON turns int keys into strings; restore numeric keys for claimed tiers
local function numKeyed(t)
	local out = {}
	if type(t) == "table" then
		for k, v in pairs(t) do out[tonumber(k) or k] = v end
	end
	return out
end

local function dayKey()
	return os.date("!%Y-%m-%d")  -- UTC day
end

local function ensure(player)
	local uid = player.UserId
	if xpByUser[uid] == nil then xpByUser[uid] = 0 end
	local today = dayKey()
	if lastDayByUser[uid] ~= today then
		lastDayByUser[uid] = today
		roundXpTodayByUser[uid] = 0
		friendXpTodayByUser[uid] = 0
	end
	return uid
end

local function getXP(player)
	return xpByUser[player.UserId] or 0
end

local function getTier(player)
	local tier = math.floor(getXP(player) / XP_PER_TIER) + 1
	return math.clamp(tier, 1, MAX_TIER)
end

local function addXP(player, amount, source)
	if not player or not amount or amount <= 0 then return end
	local uid = ensure(player)

	-- daily round cap (only for round XP; quests uncapped)
	if source == "round" then
		local todaySoFar = roundXpTodayByUser[uid] or 0
		local room = DAILY_ROUND_CAP - todaySoFar
		if room <= 0 then
			print(string.format("[BattlePass] round XP capped for %s (daily %d)", player.Name, DAILY_ROUND_CAP))
			return
		end
		amount = math.min(amount, room)
		roundXpTodayByUser[uid] = todaySoFar + amount

	-- ⚠️ 친구 보너스는 라운드 상한과 별도로 집계한다.
	--    같은 상한에 넣으면 상한을 채우는 유저에겐 보너스가 0이 되어
	--    "라이트 유저 완주 완화"라는 목적을 전혀 달성하지 못한다(실측 확인).
	--    별도 상한 FRIEND_XP_CAP 으로 완주 일수를 34일 → 29일로 줄인다.
	elseif source == "friend" then
		local todaySoFar = friendXpTodayByUser[uid] or 0
		local room = FRIEND_XP_CAP - todaySoFar
		if room <= 0 then return end
		amount = math.min(amount, room)
		friendXpTodayByUser[uid] = todaySoFar + amount
	end

	xpByUser[uid] = (xpByUser[uid] or 0) + amount
	player:SetAttribute("BP_XP", xpByUser[uid])
	player:SetAttribute("BP_Tier", getTier(player))
	print(string.format("[BattlePass] +%d XP (%s) -> %s | total=%d tier=%d",
		amount, tostring(source), player.Name, xpByUser[uid], getTier(player)))
end

-- DataStore load / save (per player, season-scoped)
local function loadPlayer(player)
	local uid = player.UserId
	local ok, saved = pcall(function() return bpStore:GetAsync(keyFor(uid)) end)
	if ok and type(saved) == "table" then
		xpByUser[uid]           = tonumber(saved.xp) or 0
		roundXpTodayByUser[uid] = tonumber(saved.roundXpToday) or 0
		friendXpTodayByUser[uid] = tonumber(saved.friendXpToday) or 0
		lastDayByUser[uid]      = saved.lastDay
		claimedByUser[uid]      = { free = numKeyed(saved.claimedFree), prem = numKeyed(saved.claimedPrem) }
		player:SetAttribute("BP_HasPremium", saved.premium == true)
	else
		if not ok then warn("[BattlePass] load failed (fresh):", player.Name, saved) end
		xpByUser[uid] = 0
		claimedByUser[uid] = { free = {}, prem = {} }
		player:SetAttribute("BP_HasPremium", false)
	end
	ensure(player)  -- resets roundXpToday if the day rolled over
	loadedByUser[uid] = true
	player:SetAttribute("BP_XP", getXP(player))
	player:SetAttribute("BP_Tier", getTier(player))
	print("[BattlePass] loaded", player.Name, "| xp="..getXP(player).." tier="..getTier(player))
end

local function savePlayer(player)
	local uid = player.UserId
	if not loadedByUser[uid] then return end  -- never overwrite un-loaded state
	local claimed = ensureClaimed(uid)
	local data = {
		xp           = xpByUser[uid] or 0,
		roundXpToday = roundXpTodayByUser[uid] or 0,
		friendXpToday = friendXpTodayByUser[uid] or 0,
		lastDay      = lastDayByUser[uid],
		claimedFree  = claimed.free,
		claimedPrem  = claimed.prem,
		premium      = player:GetAttribute("BP_HasPremium") == true,
	}
	local ok, err = pcall(function() bpStore:SetAsync(keyFor(uid), data) end)
	if not ok then
		warn("[BattlePass] save failed:", player.Name, err)
		-- 🛡️ [2026-09-06] 실패를 라이브에서도 볼 수 있게 보고한다(콘솔은 서버가 죽으면 사라진다).
		if _G.ReportSaveFailure then _G.ReportSaveFailure("BattlePassData_v1", err) end
	end
end
_G.BattlePass_save = savePlayer  -- for dev-product purchase / tests to force-save

for _, p in ipairs(Players:GetPlayers()) do task.spawn(loadPlayer, p) end
Players.PlayerAdded:Connect(loadPlayer)
Players.PlayerRemoving:Connect(function(p)
	savePlayer(p)
	xpByUser[p.UserId] = nil
	roundXpTodayByUser[p.UserId] = nil
	friendXpTodayByUser[p.UserId] = nil
	lastDayByUser[p.UserId] = nil
	claimedByUser[p.UserId] = nil
	loadedByUser[p.UserId] = nil
end)

game:BindToClose(function()
	for _, p in ipairs(Players:GetPlayers()) do savePlayer(p) end
	task.wait(1)
end)

task.spawn(function()   -- periodic autosave
	while true do
		task.wait(120)
		for _, p in ipairs(Players:GetPlayers()) do savePlayer(p) end
	end
end)

-- ===== Reward payout (slice 2a: coins + box + new skins; other cosmetics = 2b) =====
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Server reward table (1:1 with client TIERS). Actual grant data per tier/track.
local REWARDS = {
	[1]  = { free={coins=150}, prem={coins=300} },
	[2]  = { free={coins=150}, prem={effect="crown_cyan"} },
	[3]  = { free={effect="trail_watermelon"}, prem={coins=300} },
	[4]  = { free={coins=200}, prem={effect="kill_effect_rainbow"} },
	[5]  = { free={coins=200}, prem={coins=350} },
	[6]  = { free={coins=250}, prem={effect="emote_donut_tube"} },
	[7]  = { free={box="common"}, prem={coins=350} },
	[8]  = { free={coins=250}, prem={coins=400} },
	[9]  = { free={coins=300}, prem={coins=400} },
	[10] = { free={skin="Has_SummerNoob"}, prem={effect="crown_emerald"} },
	[11] = { free={coins=300}, prem={coins=450} },
	[12] = { free={coins=350}, prem={effect="emote_coconut_smile"} },
	[13] = { free={effect="dash_watermelon"}, prem={coins=450} },
	[14] = { free={coins=350}, prem={box="plus"} },
	[15] = { free={coins=400}, prem={coins=500} },
	[16] = { free={effect="kill_effect_water"}, prem={coins=500} },
	[17] = { free={coins=400}, prem={coins=550} },
	[18] = { free={coins=450}, prem={coins=550} },
	[19] = { free={coins=450}, prem={coins=600} },
	[20] = { free={skin="Has_Coconut"}, prem={skin="Has_WatermelonFist"} },
	[21] = { free={coins=500}, prem={coins=600} },
	[22] = { free={coins=500}, prem={effect="emote_beach"} },
	[23] = { free={coins=550}, prem={coins=650} },
	[24] = { free={skin="Has_BeachBall"}, prem={coins=650} },
	[25] = { free={coins=550}, prem={coins=700} },
	[26] = { free={coins=600}, prem={coins=700} },
	[27] = { free={box="common"}, prem={coins=750} },
	[28] = { free={coins=600}, prem={box="plus"} },
	[29] = { free={coins=600}, prem={coins=800} },
	[30] = { free={skin="Has_PalmTree"}, prem={skin="Has_PoolNoodle"} },
}


-- grant one reward. returns granted(bool), boxGrade(string|nil)
local function grantReward(player, reward, silent)
	if not reward then return false end
	if reward.coins then
		if _G.CoinSystem then _G.CoinSystem.addCoins(player, reward.coins) end
		return true
	elseif reward.skin then
		player:SetAttribute(reward.skin, true)
		return true
	elseif reward.box then
		if _G.grantRandomSkin then
			local ok, res = pcall(_G.grantRandomSkin, player, reward.box)
			if ok and res then
				local ev = ReplicatedStorage:FindFirstChild("RareSkinReward")
				if ev and not silent then res.fromBox = true; ev:FireClient(player, res) end
			elseif not ok then
				warn("[BattlePass] box grant error:", res)
			end
		end
		return true, reward.box
	elseif reward.effect then
		player:SetAttribute("OwnedItem_" .. reward.effect, true)   -- trail/dash/crown/killeffect/emote (EffectSystem)
		return true
	elseif reward.todo then
		print("[BattlePass] TODO cosmetic (2b):", reward.todo, "->", player.Name)
		return true  -- slice 2a: record claim only (actual grant in 2b)
	end
	return false
end

-- claim one tier/track. returns ok(bool), msg(string), boxGrade(string|nil)
local function claimTier(player, tier, track, silent)
	tier = tonumber(tier)
	if not tier or (track ~= "free" and track ~= "prem") then return false, "bad args" end
	if tier > getTier(player) then return false, "not reached" end
	if track == "prem" and player:GetAttribute("BP_HasPremium") ~= true then return false, "no premium" end
	local claimed = ensureClaimed(player.UserId)
	if claimed[track][tier] then return false, "already claimed" end
	local row = REWARDS[tier]
	local reward = row and row[track]
	local granted, box = grantReward(player, reward, silent)
	if not granted then return false, "no reward" end
	claimed[track][tier] = true
	print(string.format("[BattlePass] claim T%d %s -> %s", tier, track, player.Name))
	-- [BP-FEEDBACK] 무엇을 받았는지 클라가 알 수 있게 내역을 함께 돌려준다.
	--   ⚠️ box 보상은 grantReward 가 이미 상자 컷신을 띄운다(242행). 중복 연출을 피하려면
	--      클라는 box 가 아닐 때만 토스트를 띄워야 한다.
	return true, "claimed", box, reward
end

-- claim RemoteFunction: action = "state" | "claim" | "claimAll"
local claimFn = ReplicatedStorage:FindFirstChild("BattlePassClaim")
if claimFn then claimFn:Destroy() end
claimFn = Instance.new("RemoteFunction")
claimFn.Name = "BattlePassClaim"
claimFn.Parent = ReplicatedStorage
claimFn.OnServerInvoke = function(player, action, tier, track)
	if action == "state" then
		local claimed = ensureClaimed(player.UserId)
		return {
			tier = getTier(player), xp = getXP(player),
			hasPremium = player:GetAttribute("BP_HasPremium") == true,
			claimedFree = claimed.free, claimedPrem = claimed.prem,
		}
	elseif action == "claim" then
		local ok, msg, box, reward = claimTier(player, tier, track)
		return { ok = ok, msg = msg, box = box, reward = reward, tier = tonumber(tier), track = track }
	elseif action == "claimAll" then
		local results = {}
		local cur = getTier(player)
		local prem = player:GetAttribute("BP_HasPremium") == true
		for t = 1, cur do
			if (claimTier(player, t, "free")) then results[#results+1] = { tier = t, track = "free" } end
			if prem and (claimTier(player, t, "prem")) then results[#results+1] = { tier = t, track = "prem" } end
		end
		return { ok = true, claimed = results }
	end
	return { ok = false, msg = "unknown action" }
end

-- [BP-DEBUG] 배틀패스 배지/수령 검증용. 만렙이면 '받을 게 없어' 테스트가 안 된다.
--   ⚠️ isDev 게이트는 호출부(DownedBotSystem)가 담당한다.
--   검증이 끝나면 이 블록과 채팅 커맨드를 함께 제거할 것.
local function debugSetTier(player, tier)
	local uid = player.UserId
	tier = math.clamp(tonumber(tier) or 1, 1, MAX_TIER)
	-- 해당 티어 '시작' XP 로 맞춘다(티어 = floor(xp / XP_PER_TIER) + 1)
	xpByUser[uid] = (tier - 1) * XP_PER_TIER
	player:SetAttribute("BP_XP", xpByUser[uid])
	-- 수령 기록도 비워야 '받을 게 있는' 상태가 된다
	claimedByUser[uid] = { free = {}, prem = {} }
	savePlayer(player)
	return tier, xpByUser[uid]
end

_G.BattlePass = {
	debugSetTier    = debugSetTier,
	addXP           = addXP,
	getXP           = getXP,
	getTier         = getTier,
	XP_PER_TIER     = XP_PER_TIER,
	MAX_TIER        = MAX_TIER,
	ROUND_XP        = ROUND_XP,
	QUEST_XP_DEFAULT = QUEST_XP_DEFAULT,
	FRIEND_XP_EACH   = FRIEND_XP_EACH,
	FRIEND_XP_CAP    = FRIEND_XP_CAP,
	FRIEND_MAX_COUNT = FRIEND_MAX_COUNT,
}

-- Developer product: battle pass premium (season-scoped, consumable).
-- NOTE: only one ProcessReceipt allowed per game. If other dev products are added later,
-- extend this handler with more ProductId cases (do NOT create a second ProcessReceipt).
MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet  -- player gone; Roblox retries later
	end

	-- 중복 지급 방지: PurchaseId 기록 확인 (재시도/재접속 시 이중 지급 차단)
	local rkey = "r_" .. receipt.PlayerId .. "_" .. receipt.PurchaseId
	local seen
	local okCheck = pcall(function() seen = receiptStore:GetAsync(rkey) end)
	if not okCheck then
		return Enum.ProductPurchaseDecision.NotProcessedYet  -- DataStore 실패 → Roblox 재시도
	end
	if seen then
		return Enum.ProductPurchaseDecision.PurchaseGranted  -- 이미 지급됨
	end

	-- 지급
	local granted = false
	if PREMIUM_PRODUCT_ID ~= 0 and receipt.ProductId == PREMIUM_PRODUCT_ID then
		player:SetAttribute("BP_HasPremium", true)
		savePlayer(player)   -- persist immediately so premium survives rejoin
		print("[BattlePass] premium purchased ->", player.Name)
		granted = true
	else
		local COIN_PRODUCTS = { [3609085669] = 1000, [3609085736] = 2500, [3609085817] = 6000, [3609085871] = 15000 }
		local coinAmount = COIN_PRODUCTS[receipt.ProductId]
		if coinAmount and _G.CoinSystem and _G.CoinSystem.addCoins then
			_G.CoinSystem.addCoins(player, coinAmount)
			print("[Shop] coin pack purchased ->", player.Name, coinAmount)
			granted = true
		end
	end

	-- 태거 우선권 토큰 (개발자상품)
	if not granted and receipt.ProductId == 3609286877 and _G.TaggerBoost then
		_G.TaggerBoost.grant(player, 1)
		granted = true
	end

	-- 스킨 박스 (개발자상품): productId -> grade. 정책(유료 랜덤 제한) 백스톱.
	if not granted then
		local BOX_PRODUCTS = {
			[3609370373] = { grade = "common", fallback = 1000 },   -- Basic
			[3609370476] = { grade = "plus",   fallback = 2000 },   -- Rare+
			[3609370535] = { grade = "mega",   fallback = 3500 },   -- Epic+
		}
		local box = BOX_PRODUCTS[receipt.ProductId]
		if box then
			if _G.CanBuyPaidRandom and not _G.CanBuyPaidRandom(player) then
				warn("[Box] policy restricted, not granted ->", player.Name)
				return Enum.ProductPurchaseDecision.NotProcessedYet   -- 제한 플레이어: 지급 안 함
			end
			if _G.grantBoxToPlayer then
				_G.grantBoxToPlayer(player, box.grade, box.fallback)
				print("[Box] purchased ->", player.Name, box.grade)
				granted = true
			end
		end
	end

	-- 코스메틱 박스 (개발자상품): 킬/트레일/대시/크라운 랜덤. 정책 백스톱 동일.
	if not granted and receipt.ProductId == 3609608159 then
		if _G.CanBuyPaidRandom and not _G.CanBuyPaidRandom(player) then
			warn("[CosmeticBox] policy restricted, not granted ->", player.Name)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if _G.grantCosmeticBox then
			_G.grantCosmeticBox(player, 4000)   -- 전부 보유 시 코인 폴백
			print("[CosmeticBox] purchased ->", player.Name)
			granted = true
		end
	end

	-- Frost Lord Bundle은 개발자상품이 아니라 게임패스(1918658457)로 판매됨 → ProcessReceipt 대상 아님.
	-- 지급은 BundleGrant 스크립트가 조인 시 + PromptGamePassPurchaseFinished 두 경로로 처리.
	-- (개발자상품은 중복 구매가 가능해 799를 두 번 결제할 수 있고, 로블록스는 환불 API가 없음.)

	-- Collector Pack (개발자상품 3610453697): Color Skin Box ×5.
	-- 박스는 소모품이라 "반복 구매가 정상" → 패스가 아니라 개발자상품이 맞음 (패스는 1인 1개라 재구매 불가).
	-- ⚠ 유료 랜덤이므로 CanBuyPaidRandom 정책 게이트를 반드시 통과시켜야 함 (BOX_PRODUCTS와 동일 백스톱).
	--   등급/폴백은 Color Skin Box(3609370373)와 일치: grade="common", fallback=1000.
	if not granted and receipt.ProductId == COLLECTOR_PRODUCT_ID then
		if _G.CanBuyPaidRandom and not _G.CanBuyPaidRandom(player) then
			warn("[Collector] policy restricted, not granted ->", player.Name)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if not _G.grantBoxToPlayer then
			warn("[Collector] grantBoxToPlayer 없음 → 재시도 요청")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		for _ = 1, 5 do
			_G.grantBoxToPlayer(player, "common", 1000)
			task.wait(0.15)   -- 컷신 큐가 겹치지 않게 간격
		end
		print("[Collector] Collector Pack 지급 완료 (Color Skin Box x5) ->", player.Name)
		granted = true
	end

	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet  -- 모르는 상품
	end

	-- 처리 기록 후 완료
	do
		-- ⚠️ 영수증은 유실 시 '중복 지급'으로 이어질 수 있어 실패를 반드시 남긴다.
		local rok, rerr = pcall(function() receiptStore:SetAsync(rkey, os.time()) end)
		if not rok and _G.ReportSaveFailure then
			_G.ReportSaveFailure("ProcessedReceipts_v1", rerr)
		end
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

print("[BattlePass] ready (session memory) | tier=" .. XP_PER_TIER .. "xp round=" .. ROUND_XP .. " cap=" .. DAILY_ROUND_CAP)
