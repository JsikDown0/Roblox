-- PresetManager: 풀 로드아웃 프리셋 (태거아이템 + 러너아이템 + 장착 코스메틱).
-- 무료 2슬롯 / VIP 4슬롯. DataStore 영속. 편집 시 활성 슬롯 자동 동기화.
-- 캡처/적용은 LoadoutManager/EffectSystem의 _G 노출 함수 조합.
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local DataStoreService   = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")

local presetStore = DataStoreService:GetDataStore("PlayerPresets_v1")

local FREE_SLOTS  = 2
local VIP_SLOTS   = 4
local MAX_SLOTS   = VIP_SLOTS
local VIP_PASS_ID = 1906860989   -- VIP 게임패스. 소유 시 프리셋 슬롯 4개.

-- 리모트
local function ensureRemote(name, className)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local getPresets    = ensureRemote("GetPresets", "RemoteFunction")
local switchPreset  = ensureRemote("SwitchPreset", "RemoteEvent")
local presetChanged = ensureRemote("PresetChanged", "RemoteEvent")

-- 메모리: data[uid] = { presets = { [1..MAX_SLOTS] = blob | nil }, active = n }
-- blob = { tagger = {...}, runner = {...}, eq = { crownSkin, killEffect, dashSkin, trailSkin, weapon } }
local data         = {}
local ready        = {}   -- uid -> true : 조인 로드+적용 완료 전엔 스위치/동기화 무시
local vipCache     = {}
local saveDebounce = {}

-- VIP 슬롯 수
local function hasVIP(player)
	if player:GetAttribute("_VIPTest") then return true end   -- [TEST] /vip 오버라이드
	if VIP_PASS_ID == 0 then return false end
	local uid = player.UserId
	if vipCache[uid] == nil then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(uid, VIP_PASS_ID)
		end)
		vipCache[uid] = (ok and owns) or false
	end
	return vipCache[uid]
end
_G.HasVIP = hasVIP   -- 공통 VIP 판정 (채팅 태그·맵 투표 등 재사용)
local coins2xCache = {}
local function has2xCoins(player)
	if player:GetAttribute("_2xTest") then return true end
	local uid = player.UserId
	if coins2xCache[uid] == nil then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(uid, 1905787000)
		end)
		coins2xCache[uid] = (ok and owns) or false
	end
	return coins2xCache[uid]
end
_G.Has2xCoins = has2xCoins   -- 2x Coins 게임패스 소유 판정 (라운드 보상 2배)

local function maxSlots(player)
	return hasVIP(player) and VIP_SLOTS or FREE_SLOTS
end

-- 캡처 / 적용 (1단계 _G 노출 조합)
local function captureCurrent(player)
	local ld = (_G.LM_getLoadouts and _G.LM_getLoadouts(player)) or { tagger = {}, runner = {} }
	local eq = (_G.ES_getEquipped and _G.ES_getEquipped(player)) or {}
	return {
		tagger = ld.tagger or {},
		runner = ld.runner or {},
		eq = {
			crownSkin  = eq.crownSkin,
			killEffect = eq.killEffect,
			dashSkin   = eq.dashSkin,
			trailSkin  = eq.trailSkin,
			weapon     = eq.weapon,
			emotes     = eq.emotes,   -- 배열(순서 유지). ES_getEquipped가 복사본을 줌
		},
	}
end

local function applyPreset(player, blob)
	if type(blob) ~= "table" then return end
	if _G.LM_applyLoadouts then _G.LM_applyLoadouts(player, blob.tagger or {}, blob.runner or {}) end
	if _G.ES_applyEquipped then _G.ES_applyEquipped(player, blob.eq or {}) end
end

-- DataStore
local function loadData(player)
	local uid = player.UserId
	local ok, saved = pcall(function()
		return presetStore:GetAsync("preset_" .. uid)
	end)
	if ok and type(saved) == "table" and type(saved.presets) == "table" then
		data[uid] = { presets = saved.presets, active = tonumber(saved.active) or 1 }
	else
		data[uid] = { presets = {}, active = 1 }
	end
	local a = data[uid].active
	if a < 1 or a > MAX_SLOTS then data[uid].active = 1 end
end

local function saveData(player)
	local d = data[player.UserId]
	if not d then return end
	local ok, err = pcall(function()
		presetStore:SetAsync("preset_" .. player.UserId, { presets = d.presets, active = d.active })
	end)
	if not ok and _G.ReportSaveFailure then _G.ReportSaveFailure("PlayerPresets_v1", err) end
end

local function saveDebounced(player)
	local uid = player.UserId
	if saveDebounce[uid] then return end
	saveDebounce[uid] = true
	task.delay(3, function()
		saveDebounce[uid] = nil
		local p = Players:GetPlayerByUserId(uid)
		if p then saveData(p) end
	end)
end

-- 편집 동기화 훅: 유저가 로드아웃/코스메틱 편집 -> 활성 슬롯 재캡처 + 디바운스 저장.
-- applyPreset은 _G 함수를 직접 호출(리모트 핸들러 우회)하므로 이 훅을 안 건드림 = 피드백 루프 없음.
_G.PM_onEdit = function(player)
	local uid = player.UserId
	local d = data[uid]
	if not d or not ready[uid] then return end
	d.presets[d.active] = captureCurrent(player)
	saveDebounced(player)
end

-- 목록 조회 (UI용)
getPresets.OnServerInvoke = function(player)
	local unlocked = maxSlots(player)
	local d = data[player.UserId]
	if not d then return { slots = {}, active = 1, unlocked = unlocked } end
	local slots = {}
	for i = 1, MAX_SLOTS do
		slots[i] = { filled = d.presets[i] ~= nil, unlocked = i <= unlocked }
	end
	return { slots = slots, active = d.active, unlocked = unlocked }
end

-- 프리셋 전환
switchPreset.OnServerEvent:Connect(function(player, n)
	n = tonumber(n)
	local uid = player.UserId
	local d = data[uid]
	if not d or not ready[uid] then return end
	if not n or n < 1 or n > MAX_SLOTS then return end
	if n > maxSlots(player) then return end   -- VIP 잠금 슬롯 거부
	if n == d.active then return end

	d.presets[d.active] = captureCurrent(player)     -- 현재 라이브 -> 옛 active 슬롯
	if d.presets[n] == nil then
		d.presets[n] = captureCurrent(player)        -- 빈 슬롯: 현재 복제로 시드
	end
	applyPreset(player, d.presets[n])
	d.active = n
	presetChanged:FireClient(player)   -- 저장 전에 먼저 알림 (UI 즉시 갱신)
	task.spawn(function() saveData(player) end)   -- 저장은 비동기 (DataStore yield가 UI 안 막게)
end)

-- 조인 / 리브
-- VIP 구매 완료 시 슬롯 잠금 해제 (재접속 불필요)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if purchased and passId == VIP_PASS_ID then
		vipCache[player.UserId] = true
		player:SetAttribute("IsVIP", true)
		if data[player.UserId] then presetChanged:FireClient(player) end
	elseif purchased and passId == 1905787000 then
		coins2xCache[player.UserId] = true
	end
end)

local function setupPlayer(player, joinDelay)
	loadData(player)
	task.delay(joinDelay, function()
		if not player.Parent then return end
		local d = data[player.UserId]
		if not d then return end
		if d.presets[d.active] == nil then
			d.presets[d.active] = captureCurrent(player)   -- 첫 접속: 현재(기본) 상태 시드
		else
			applyPreset(player, d.presets[d.active])        -- 저장된 active 복원
		end
		ready[player.UserId] = true
		player:SetAttribute("IsVIP", hasVIP(player))
		presetChanged:FireClient(player)
	end)
end

Players.PlayerAdded:Connect(function(player)
	setupPlayer(player, 4)   -- grantFreeSkins/소유복원 이후에 적용되도록 딜레이
end)

Players.PlayerRemoving:Connect(function(player)
	local uid = player.UserId
	if data[uid] and ready[uid] then saveData(player) end   -- 활성 슬롯은 PM_onEdit로 이미 최신
	data[uid] = nil
	ready[uid] = nil
	vipCache[uid] = nil
	saveDebounce[uid] = nil
end)

for _, p in ipairs(Players:GetPlayers()) do
	setupPlayer(p, 1)   -- 스크립트 리로드 대비
end

-- [TEST] /resetloadout : 내 로드아웃/코스메틱/프리셋을 기본값으로 초기화 (편집 오염 복구). 릴리즈 전 제거.
local function resetToDefault(player)
	if _G.LM_applyLoadouts then
		_G.LM_applyLoadouts(player, {"stone", "Wood Log", "Wooden Barrel"}, {"Speed Potion"})
	end
	if _G.ES_applyEquipped then
		_G.ES_applyEquipped(player, { dashSkin = "dash_default", crownSkin = "crown_gold", weapon = "ClassicSword", killEffect = nil, trailSkin = nil })
	end
	local d = data[player.UserId]
	if d then
		d.presets = {}
		d.active = 1
		d.presets[1] = captureCurrent(player)
		task.spawn(function() saveData(player) end)
	end
	presetChanged:FireClient(player)
	print("[Preset] RESET to default: " .. player.Name)
end
-- ⚠️ [DEV-GATE] 아래 커맨드들은 유료 혜택(VIP·2x코인·부스트)을 직접 켠다.
--    가드가 없어 누구나 /vip 를 쳐서 게임패스를 우회할 수 있었다(실측 2026-08-21).
--    광고 유입 전 반드시 막아야 하는 항목이라 개발자 전용으로 잠근다.
local _isDev = require(game:GetService("ServerScriptService"):WaitForChild("DevAuth")).isDev

local function hookReset(player)
	player.Chatted:Connect(function(msg)
		if not _isDev(player) then return end   -- 🔒 개발자 전용
		if msg == "/resetloadout" then
			resetToDefault(player)
		elseif msg == "/vip" then
			local now = not player:GetAttribute("_VIPTest")
			player:SetAttribute("_VIPTest", now)
			player:SetAttribute("IsVIP", now)
			vipCache[player.UserId] = nil
			if data[player.UserId] then presetChanged:FireClient(player) end
			print("[VIP] test override " .. player.Name .. " = " .. tostring(now))
		elseif msg == "/2x" then
			local now = not player:GetAttribute("_2xTest")
			player:SetAttribute("_2xTest", now)
			coins2xCache[player.UserId] = nil
			print("[2x] test override " .. player.Name .. " = " .. tostring(now))
		elseif msg == "/boost" then
			if _G.TaggerBoost then _G.TaggerBoost.grant(player, 1) end
		end
	end)
end
Players.PlayerAdded:Connect(hookReset)
for _, p in ipairs(Players:GetPlayers()) do hookReset(p) end

print("PresetManager ready (free " .. FREE_SLOTS .. " / VIP " .. VIP_SLOTS .. " slots)")
