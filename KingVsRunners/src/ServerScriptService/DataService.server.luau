-- DataService: ProfileStore 기반 세션 락 데이터 (돈/아이템 등 핵심 데이터 영속화).
-- 프로필 1개/플레이어. 세션 락·자동저장·BindToClose·재시도 전부 ProfileStore 내장.
-- 다른 시스템은 _G.DataService.get(player) 로 프로필 데이터(.Coins 등)를 읽고 씀.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService:WaitForChild("ProfileStore"))

-- 프로필 스키마 (앞으로 소유아이템 등 여기에 추가)
local PROFILE_TEMPLATE = {
	Coins = 0,
	Skins = {},   -- ["Has_스킨명"] = true  (박스/퀘스트/BP로 딴 스킨 — 기존엔 미저장이던 것)
	EquippedSkins = {},   -- [아이템명] = 스킨명  (무엇을 '장착'했는가)
	--   ⚠️ [2026-09-11] Skins 는 '소유'만 저장했다. 장착은 SkinManager 의 메모리
	--      테이블(playerSkins)에만 있어서 서버가 꺼지면 전부 풀렸다 — 유저가 스킨을
	--      사고 장착해도 재접속하면 기본 외형으로 돌아갔다(과금 상품이라 치명적).
	--   ⚠️ Reconcile() 이 기존 프로필에 빈 테이블을 채운다. 기존 유저는 한 번 다시
	--      장착해야 하지만 소유는 유지되므로 손실은 없다.
	RoundsPlayed = 0,   -- 누적 라운드 참여 수. 신규 유저 보호(킹 난이도 제한)에 사용.
	--   ⚠️ Reconcile() 이 기존 프로필에도 이 키를 0 으로 채운다.
	--      즉 기존 유저도 처음엔 0 으로 시작해 잠시 easy/normal 만 만난다.
	--      의도된 절충 — 별도 마이그레이션 없이 안전하게 도입하기 위함.
	GroupRewardClaimed = false,   -- 그룹 가입 보상(ItemNoob + 300코인) 수령 여부. 계정당 1회.
	--   ⚠️ 예전엔 메모리 테이블(rewardedPlayers)로만 관리해 재접속하면 초기화됐다.
	--      → ItemNoob 이 사라지고, 코인 300 을 접속할 때마다 다시 받을 수 있었다(실측 2026-08-22).
	StarterKitGiven = false,   -- 소모품 맛보기(전 종류 2개씩) 지급 여부. 계정당 1회.
	--   ⚠️ Reconcile() 로 기존 유저도 false 가 되어 지급 대상이 된다.
	--      의도된 동작 — 기존 유저에게도 한 번은 체험 기회를 준다.
}

local PlayerStore = ProfileStore.New("PlayerData_v1", PROFILE_TEMPLATE)

local Profiles = {}   -- player -> profile

local function onPlayerAdded(player)
	local profile = PlayerStore:StartSessionAsync("player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players   -- 로드 중 나가면 세션 시도 중단
		end,
	})

	if profile ~= nil then
		profile:AddUserId(player.UserId)   -- GDPR
		profile:Reconcile()                -- 템플릿의 누락 키 채움

		profile.OnSessionEnd:Connect(function()
			Profiles[player] = nil
			player:Kick("데이터 세션이 종료되었습니다. 재접속 해주세요.")   -- 다른 서버가 락 가져감
		end)

		if player.Parent == Players then
			Profiles[player] = profile
		else
			profile:EndSession()   -- 이미 나감
		end
	else
		-- 로드 실패(락 충돌 지속 등) → 킥 (기본값 0으로 덮어 저장하는 사고 방지)
		player:Kick("데이터 로드 실패. 재접속 해주세요.")
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	local profile = Profiles[player]
	if profile ~= nil then
		profile:EndSession()   -- 릴리즈 + 최종 저장 (ProfileStore가 처리)
	end
end)

-- ── 공용 API ─────────────────────────────────────────────────
local function getData(player)
	local p = Profiles[player]
	return p and p.Data or nil   -- nil = 아직 로드 안 됨
end

_G.DataService = {
	get = getData,
	isReady = function(player) return Profiles[player] ~= nil end,
	-- 프로필 로드까지 대기 (조인 직후 데이터 필요한 시스템용)
	waitForData = function(player, timeout)
		local t = 0
		while Profiles[player] == nil do
			if player.Parent ~= Players then return nil end
			if t >= (timeout or 20) then return nil end
			task.wait(0.1); t = t + 0.1
		end
		return getData(player)
	end,
}

print("✅ DataService ready (ProfileStore, session-locked)")
