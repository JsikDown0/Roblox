--[[
	LeaderboardService — 시즌 리더보드 기록/조회 (서버 전용)

	보드 4종:
	  KingWins    (태거) 왕좌 방어      — elimination 승리
	  Tyrant      (태거) 누적 처치      — 승패 무관, 처치 수만큼 가산
	  RunnerWins  (러너) 최후 생존      — 라운드 종료 시점 생존
	  Kingslayer  (러너) 왕에게 막타    — tagger_slain 시 killerName 본인

	설계 원칙
	  · 시즌 구분은 SeasonConfig 하나에만 의존 (배틀패스와 공유).
	  · 쓰기는 전부 비동기(task.spawn) + pcall — endRound가 결과창 타이밍에 물려 있어
	    DataStore 지연이 전원 결과창을 늦추면 안 됨.
	  · AI 러너/봇 태거가 낀 판, 무효 라운드, 저인원 판은 recordRound에서 통째로 차단.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SeasonConfig = require(ReplicatedStorage:WaitForChild("SeasonConfig"))

local LeaderboardService = {}

-- ── 보드 정의 ────────────────────────────────────────────────
-- id는 DataStore 이름에 들어가므로 절대 바꾸지 말 것 (바꾸면 기록 유실).
LeaderboardService.BOARDS = {
	KingWins   = { id = "KingWins",   title = "KING WINS",  subtitle = "Defended the throne",  role = "Tagger" },
	Tyrant     = { id = "Tyrant",     title = "TYRANT",     subtitle = "Runners eliminated",   role = "Tagger" },
	RunnerWins = { id = "RunnerWins", title = "RUNNER WINS", subtitle = "Survived to the end", role = "Runner" },
	Kingslayer = { id = "Kingslayer", title = "KINGSLAYER", subtitle = "Final blow on the King", role = "Runner" },
}

-- 리더보드 집계 최소 유저 러너 수.
-- [LEADERBOARD-OPEN] 아래 상수는 현재 게이트에서 사용하지 않는다(2026-08-21 해제).
--   되돌릴 때를 대비해 값만 남겨둔다. recordRound 의 주석 처리된 블록과 짝이다.
--   원래 의도: AI 러너가 자동 보충되므로 실인원이 적으면 사실상 봇전이 되고,
--             태거와 짜고 자살시키는 소인원 어뷰징도 이 선에서 차단하려던 것.
local MIN_USER_RUNNERS = 3

-- ── 진단 로그 ────────────────────────────────────────────────
-- ⚠️ 출시 전 DEBUG = false 로 내릴 것 (릴리즈 정리 목록).
-- 기록이 안 남을 때 "어느 게이트에서 걸렀는지"를 F9 콘솔에서 바로 확인하기 위한 것.
-- 혼자 테스트하면 MIN_USER_RUNNERS 게이트에 항상 걸리므로 이 로그가 없으면 원인 구분이 불가능하다.
local DEBUG = false
local function dbg(fmt, ...)
	if DEBUG then print("[LB] " .. string.format(fmt, ...)) end
end

-- ── 내부: 스토어 캐시 ────────────────────────────────────────
local storeCache = {}
local function getStore(boardId, seasonId)
	local name = SeasonConfig.boardStoreName(boardId, seasonId)
	if not storeCache[name] then
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(name)
		end)
		if not ok or not store then
			warn("[Leaderboard] 스토어 로드 실패:", name, store)
			return nil
		end
		storeCache[name] = store
	end
	return storeCache[name]
end

-- ── 기록 ─────────────────────────────────────────────────────
-- 비동기 + pcall. 실패해도 라운드 흐름에 영향 없음.
function LeaderboardService.increment(boardId, userId, amount)
	amount = amount or 1
	if amount <= 0 then return end
	if not LeaderboardService.BOARDS[boardId] then
		warn("[Leaderboard] 알 수 없는 보드:", boardId)
		return
	end
	task.spawn(function()
		local store = getStore(boardId)
		if not store then return end
		local ok, result = pcall(function()
			return store:IncrementAsync(tostring(userId), amount)
		end)
		if ok then
			dbg("✅ %s +%d → user %d (누적 %s)", boardId, amount, userId, tostring(result))
		else
			warn(string.format("[Leaderboard] %s 기록 실패 (user %d): %s", boardId, userId, tostring(result)))
		end
	end)
end

--[[
	라운드 결산 1건을 받아 해당 유저의 보드들을 갱신한다.
	RoundSystem.endRound 의 stats 루프 안에서 플레이어마다 1회 호출.

	entry = {
		userId       = number,
		playerName   = string,
		role         = "Tagger" | "Runner",
		survived     = boolean,
		won          = boolean,
		roundKills   = number,    -- AI 러너 처치는 이미 제외된 값 (KillEffectSystem)
	}
	ctx = {
		endReason        = "elimination" | "tagger_slain" | "timeout" | "bot_slain" | "voided" | ...
		voided           = boolean,
		killerName       = string?,  -- 태거에게 막타를 넣은 러너 이름
		userRunnerCount  = number,   -- 라운드 시작 시점 유저 러너 실인원 (AI 제외)
	}
]]
function LeaderboardService.recordRound(entry, ctx)
	if not entry or not ctx then
		warn("[Leaderboard] recordRound 인자 누락 — entry/ctx 확인 필요")
		return
	end

	local who = string.format("%s(%s)", entry.playerName or "?", entry.role or "?")

	-- ── 공통 게이트 ──
	-- ⚠️ voided(무효 라운드)만 남긴다. 이건 어뷰징 방지가 아니라
	--    "라운드가 정상 종료되지 않음"이라 기록 자체가 의미 없는 경우다.
	if ctx.voided then
		dbg("⏭ %s 스킵 — 무효 라운드(voided)", who)
		return
	end
	-- [LEADERBOARD-OPEN] 2026-08-21: 인원수/봇 제한 해제.
	--   기존: bot_slain 스킵 + userRunnerCount >= 3 요구 → 솔로는 영원히 기록 없음.
	--   판단 근거:
	--     ① 리더보드 보상이 없어 어뷰징으로 얻을 실익이 없다.
	--     ② 빈 리더보드는 신규에게 "죽은 게임" 신호가 되어 손해가 더 크다.
	--     ③ 어뷰징이라도 결국 플레이 시간이고, 알고리즘 지표에는 오히려 기여한다.
	--   되돌리려면 아래 두 블록의 주석을 풀면 된다.
	-- if ctx.endReason == "bot_slain" then
	-- 	dbg("⏭ %s 스킵 — 봇 태거 상대 승리(bot_slain)는 미인정", who)
	-- 	return
	-- end
	-- if (ctx.userRunnerCount or 0) < MIN_USER_RUNNERS then
	-- 	dbg("⏭ %s 스킵 — 유저 러너 %d명 < 최소 %d명",
	-- 		who, ctx.userRunnerCount or 0, MIN_USER_RUNNERS)
	-- 	return
	-- end

	dbg("▶ %s 판정 시작 (endReason=%s, survived=%s, won=%s, kills=%d, killer=%s)",
		who, tostring(ctx.endReason), tostring(entry.survived), tostring(entry.won),
		entry.roundKills or 0, tostring(ctx.killerName))

	if entry.role == "Tagger" then
		if entry.won and ctx.endReason == "elimination" then
			LeaderboardService.increment("KingWins", entry.userId, 1)
		else
			dbg("   · KingWins 미해당 (won=%s, endReason=%s / 요구: won & elimination)",
				tostring(entry.won), tostring(ctx.endReason))
		end
		-- 승패 무관: 진 라운드에도 벤 만큼 쌓인다 (왕 차례가 드물기 때문)
		if (entry.roundKills or 0) > 0 then
			LeaderboardService.increment("Tyrant", entry.userId, entry.roundKills)
		else
			dbg("   · Tyrant 미해당 (처치 0 — AI 러너 처치는 집계 제외됨)")
		end

	elseif entry.role == "Runner" then
		-- 러너가 살아남았는데 태거가 이기는 경우는 존재하지 않음(전멸이 태거 승리 조건).
		-- 따라서 survived 단독으로 충분하며 won 검사는 잉여.
		if entry.survived then
			LeaderboardService.increment("RunnerWins", entry.userId, 1)
		else
			dbg("   · RunnerWins 미해당 (종료 시점 사망)")
		end
		if ctx.endReason == "tagger_slain" and ctx.killerName and entry.playerName == ctx.killerName then
			LeaderboardService.increment("Kingslayer", entry.userId, 1)
		else
			dbg("   · Kingslayer 미해당 (endReason=%s, killer=%s / 본인=%s)",
				tostring(ctx.endReason), tostring(ctx.killerName), tostring(entry.playerName))
		end
	end
end

-- ── 조회 ─────────────────────────────────────────────────────
-- 보드 표시용 Top N. 반환: { {userId=number, value=number}, ... } (실패 시 nil)
function LeaderboardService.getTop(boardId, count, seasonId)
	count = math.clamp(count or 10, 1, 100)
	local store = getStore(boardId, seasonId)
	if not store then return nil end
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, count):GetCurrentPage()
	end)
	if not ok or not page then
		warn(string.format("[Leaderboard] %s 조회 실패: %s", boardId, tostring(page)))
		return nil
	end
	local result = {}
	for _, item in ipairs(page) do
		table.insert(result, { userId = tonumber(item.key), value = item.value })
	end
	return result
end

_G.LeaderboardService = LeaderboardService

print(string.format("✅ LeaderboardService 준비 (%s, 보드 4종, 인원 제한 없음)",
	SeasonConfig.id()))

-- ── 부팅 자가진단 ────────────────────────────────────────────
-- Studio에서 API 접근이 꺼져 있으면 모든 IncrementAsync가 조용히 실패한다.
-- 그 상태를 라운드 끝나고서야 알면 원인 추적에 시간을 버리므로 부팅 시 한 번 확인한다.
-- 기존 보드를 읽기만 하므로(GetSortedAsync) 데이터를 오염시키지 않는다.
task.spawn(function()
	local store = getStore("KingWins")
	if not store then
		warn("[Leaderboard] ⚠️ OrderedDataStore 생성 실패 — 기록 불가")
		return
	end
	local ok, err = pcall(function()
		return store:GetSortedAsync(false, 1):GetCurrentPage()
	end)
	if ok then
		print("✅ [Leaderboard] DataStore 접근 정상 — 기록 활성")
	else
		warn("[Leaderboard] ⚠️ DataStore 접근 불가 — 리더보드가 기록되지 않습니다.")
		warn("   Studio: Game Settings → Security → 'Enable Studio Access to API Services' 확인")
		warn("   원인: " .. tostring(err))
	end
end)

return LeaderboardService
