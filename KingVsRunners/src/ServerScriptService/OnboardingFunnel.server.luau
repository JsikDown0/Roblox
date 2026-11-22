-- OnboardingFunnel
-- 신규 유저가 어디서 이탈하는지 측정한다. (크리에이터 허브 > 애널리틱스 > 유입 경로)
--
-- 왜 필요한가:
--   이 게임은 라운드제라 접속 직후 "다음 라운드까지 대기"라는 구간이 있다.
--   신규 유저가 그 대기에서 나가는지, 첫 라운드를 해보고 나가는지는 원인이 완전히 달라
--   (전자는 로비/대기 문제, 후자는 게임 자체 문제) 대응도 정반대다.
--   지금은 이걸 구분할 방법이 없어서 추측만 가능하다.
--
-- 단계 설계 (4단계로 최소화):
--   1 접속            — 서버에 들어옴
--   2 첫 라운드 진입   — 대기를 견디고 라운드 시작을 맞음
--   3 첫 라운드 완주   — 라운드 끝까지 남음
--   4 두 번째 라운드   — 재도전 = 실질적 리텐션 확보 지점
--
-- ⚠️ 제약 (Roblox 문서):
--   · 이벤트는 서버에서만, 그리고 "게시된 게임"에서만 전송된다. Studio/클라 불가.
--     → F5 로 검증이 불가능하므로 로직을 최대한 단순하게 유지한다.
--   · 같은 단계를 여러 번 기록해도 첫 번째만 집계된다. (중복 방어 코드 불필요)
--   · 뒷 단계를 기록하면 앞 단계는 자동 완료 처리된다.
--   · 반복 기록도 전송 한도에는 계산되므로, 세션당 1회만 보내도록 플래그로 막는다.
--
-- 익스플로잇 표면 없음: 클라이언트 RemoteEvent 를 쓰지 않고 서버 상태만 읽는다.

local AnalyticsService = game:GetService("AnalyticsService")
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")

-- Studio 에서는 어차피 전송되지 않는다. 불필요한 호출과 로그를 아예 막는다.
if RunService:IsStudio() then
	print("[Funnel] Studio 에서는 전송되지 않음 (라이브 전용)")
	return
end

local STEP = {
	JOINED       = { 1, "Joined" },
	FIRST_ROUND  = { 2, "First Round Started" },
	ROUND_DONE   = { 3, "First Round Finished" },
	SECOND_ROUND = { 4, "Second Round Started" },
}

-- [userId] = { [stepNumber] = true }  세션 내 중복 전송 방지
local sent = {}
-- [userId] = 시작한 라운드 수
local roundsStarted = {}
-- [userId] = 이번 라운드 시작 시각(os.clock). 조기 사망 측정용.
--   ⚠️ onRoundStart 보다 먼저 선언해야 한다. 아래에 두면 그 함수가 전역 nil 을 잡는다.
local roundStartAt = {}

local function log(player, step)
	if not player or not player.Parent then return end
	local uid = player.UserId
	sent[uid] = sent[uid] or {}
	if sent[uid][step[1]] then return end
	sent[uid][step[1]] = true

	local ok, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step[1], step[2])
	end)
	if not ok then
		warn("[Funnel] 전송 실패 step " .. step[1] .. ": " .. tostring(err))
	end
end

-- ── 1단계: 접속 ──────────────────────────────────────
local function onJoin(player)
	roundsStarted[player.UserId] = 0
	log(player, STEP.JOINED)
end

Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do onJoin(p) end

Players.PlayerRemoving:Connect(function(p)
	sent[p.UserId] = nil
	roundsStarted[p.UserId] = nil
	roundStartAt[p.UserId] = nil
end)

-- ── 2·4단계: 라운드 시작 ─────────────────────────────
-- RoundSystem 이 라운드를 시작할 때 호출한다.
local function onRoundStart()
	for _, player in ipairs(Players:GetPlayers()) do
		local uid = player.UserId
		roundsStarted[uid] = (roundsStarted[uid] or 0) + 1
		-- 💀 조기 사망 측정용 시작 시각. 아래 onRunnerDied 가 이걸로 생존 초를 잰다.
		roundStartAt[uid] = os.clock()
		if roundsStarted[uid] == 1 then
			log(player, STEP.FIRST_ROUND)
		elseif roundsStarted[uid] == 2 then
			log(player, STEP.SECOND_ROUND)
		end
	end
end

-- ── 3단계: 첫 라운드 완주 ────────────────────────────
-- "완주" = 라운드 종료 시점에 아직 서버에 있음. (죽었어도 결과창까지 봤으면 완주로 본다 —
--  중간에 나간 것과 구분하는 게 목적이므로 생존 여부는 기준이 아니다)
local function onRoundEnd()
	for _, player in ipairs(Players:GetPlayers()) do
		if (roundsStarted[player.UserId] or 0) >= 1 then
			log(player, STEP.ROUND_DONE)
		end
	end
end

-- ── 조기 사망 측정 (퍼널과 별개) ─────────────────────
-- 💀 [2026-09-02] "라운드 중 사망"을 퍼널 단계로는 넣을 수 없다.
--   [왜] 퍼널은 선형이고, 위 20행 주석대로 "뒷 단계를 기록하면 앞 단계가 자동 완료"된다.
--     사망은 진행 단계가 아니라 갈림길이라, 중간에 끼우면 2라운드를 시작한 사람이
--     앞 단계를 자동 완료시켜 사망 여부가 지워진다.
--   [대신] 커스텀 이벤트로 "몇 초 만에 죽었나"를 따로 기록한다.
--     퍼널의 '라운드1 → 라운드2 이탈' 수와 이 이벤트를 대조하면
--     이탈자 중 조기 사망자 비중을 추정할 수 있다.
--   [배경] 라운드 150초 / 1단계 실측 37.6~52.1초. 1단계 초반(10~20초)에 죽으면
--     관전 130~140초 + 라운드 간 대기 34초 = 약 170초를 아무것도 못 한다.
--     조작 20초 : 대기 170초 = 1:7. (Piggy 는 8분 생존 : 2분 관전 = 4:1)
--   ⚠️ Studio 에서는 전송되지 않는다(위 30행에서 조기 return). 라이브에서만 쌓인다.
--   ⚠️ 값(value)은 생존 초를 넣는다. 애널리틱스에서 평균·분포를 볼 수 있다.

-- RoundSystem 이 러너 사망 시 호출한다.
local function onRunnerDied(player)
	if not player or not player.Parent then return end
	local uid = player.UserId
	local startedAt = roundStartAt[uid]
	if not startedAt then return end          -- 라운드 중이 아니면 무시
	roundStartAt[uid] = nil                   -- 라운드당 1회

	local survived = math.floor(os.clock() - startedAt)
	local isFirstRound = (roundsStarted[uid] or 0) <= 1

	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, "RunnerDied", survived, {
			-- ⚠️ 커스텀 필드는 문자열만 받는다. 숫자를 넣으면 조용히 누락된다.
			firstRound = isFirstRound and "yes" or "no",
			bucket     = (survived < 20 and "0-20s")
			          or (survived < 40 and "20-40s")
			          or (survived < 80 and "40-80s")
			          or "80s+",
		})
	end)
	if not ok then
		warn("[Funnel] RunnerDied 전송 실패: " .. tostring(err))
	end
end

_G.OnboardingFunnel = {
	roundStarted = onRoundStart,
	roundEnded   = onRoundEnd,
	runnerDied   = onRunnerDied,
}

print("✅ OnboardingFunnel ready (4단계 퍼널 + RunnerDied 커스텀 이벤트)")
