--[[
	SeasonConfig — 시즌 번호의 단일 진실 공급원 (Single Source of Truth)

	배틀패스와 리더보드가 같은 "시즌" 개념을 공유하도록 여기 한 곳에서만 시즌을 관리한다.
	시즌을 넘길 때는 아래 SEASON_NUMBER 만 올리고 퍼블리시하면 된다.
	  → 배틀패스 진행도 리셋 + 리더보드 새 보드 시작이 동시에 일어남.

	ReplicatedStorage에 두는 이유: 클라이언트도 시즌 번호를 읽어야 함
	(보드 제목 "SEASON 2", 배틀패스 UI 표기 등). 쓰기는 서버에서만.

	⚠️ 데이터 호환 주의
	  BattlePassSystem이 기존에 쓰던 키 형식은 "season1_<userId>" 였다.
	  SEASON_NUMBER = 1 일 때 id() 가 정확히 "season1"을 반환하므로 기존 저장 데이터와 호환된다.
	  이 형식을 바꾸면 기존 유저의 배틀패스 진행도가 전부 초기화되니 건드리지 말 것.
]]

local SeasonConfig = {}

-- ▼▼▼ 시즌 전환 시 이 값만 올린다 ▼▼▼
SeasonConfig.SEASON_NUMBER = 1
-- ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

-- ── 시즌 일정 ────────────────────────────────────────────────
-- 30일 시즌 + 1주 휴식(= 5주 주기). Roblox 권장 형태.
-- 시즌을 넘길 때 SEASON_NUMBER 와 함께 START_UNIX 도 갱신해야 한다.
--   START_UNIX = 이 시즌이 시작된 시각(UTC epoch 초).
--   구하는 법: 콘솔에서 os.time() 실행, 또는 https://www.epochconverter.com
-- ⚠️ 클라이언트 UI("ends in Nd")가 이 값으로 남은 기간을 계산한다.
--    하드코딩된 문구를 쓰면 시즌이 끝나도 같은 숫자가 계속 표시되어
--    "예고 없이 끝났다"는 배신감을 준다 — 반드시 여기서 계산할 것.
-- 🔄 [시즌 재시작 2026-09-19] START_UNIX 를 오늘로 옮긴다. SEASON_NUMBER 는 그대로 1.
--   [왜] 배틀패스가 사실상 안 팔렸다. 기간을 다시 주어 판매 기회를 회복한다.
--   [무엇이 보존되나] SEASON_NUMBER 를 안 올렸으므로 저장 키("season1_<userId>")가
--     그대로다 → **배틀패스 진행도 · 구매 기록 · 리더보드 전부 보존된다.**
--     SEASON_NUMBER 를 올렸다면 리더보드까지 같이 초기화됐을 것이다(둘이 같은 번호를 쓴다).
--   ⚠️ [이전 값이 이미 만료돼 있었다] 1787011200 = **2026-08-18**(실측), +35일 = 09-22 종료.
--     🔴 그런데 그 줄의 주석은 "2026-08-13" 이라고 적혀 있었다 — **주석이 5일 틀렸다.**
--     09-19 작업 때 그 틀린 주석을 기준으로 새 값을 역산했다가 5일 어긋난 값을 넣었다.
--     [교훈] 이 상수는 사람이 읽을 수 없는 숫자다. 주석을 믿지 말고 코드로 확인할 것:
--       print(os.date("!%Y-%m-%d", SeasonConfig.START_UNIX))
--     ⚠️ Studio 에서 require 는 모듈을 캐시한다. 값을 바꾼 직후 require 로 검산하면
--       옛 값이 나온다 — 숫자를 직접 os.date 에 넣어 확인할 것.
SeasonConfig.START_UNIX   = 1789776000   -- 2026-09-19 00:00 UTC (= 09:00 KST) 재시작 [검산 완료]
SeasonConfig.DURATION_DAYS = 35          -- 시즌 본편 길이 → 2026-10-24 00:00 UTC 종료 [검산 완료]
--   ⚠️ [부작용] 이미 티어를 올린 유저는 진행도를 유지한 채 재시작된다(유리한 출발).
--     그게 싫으면 SEASON_NUMBER 를 올려야 하는데, 그때는 리더보드도 같이 날아간다.
--     "안 팔린 것"과 "플레이 기록을 지우는 것"은 별개 결정이라 여기서는 보존을 택했다.
--   ⚠️ 다음 시즌으로 진짜 넘길 때는 SEASON_NUMBER 와 START_UNIX 를 **같이** 올린다.
SeasonConfig.START_UNIX   = 1789776000   -- 2026-09-19 00:00 UTC (= 09:00 KST) 재시작 [검산 완료]
--   ⚠️ 이 값은 손으로 계산하지 말고 반드시 검산할 것(위 교훈 참조).
SeasonConfig.DURATION_DAYS = 35          -- 시즌 본편 길이 → 2026-10-24 00:00 UTC 종료 [검산 완료]
SeasonConfig.BREAK_DAYS    = 2           -- 시즌 사이 휴식 기간

-- 시즌 종료 시각(epoch 초)
function SeasonConfig.endsAt()
	return SeasonConfig.START_UNIX + SeasonConfig.DURATION_DAYS * 86400
end

-- 남은 초. 이미 끝났으면 0.
function SeasonConfig.secondsLeft()
	return math.max(0, SeasonConfig.endsAt() - os.time())
end

-- UI 표기용 문자열: "12d 5h" / "5h 23m" / "23m" / "Ended"
-- 하루 미만이면 시/분 단위로 바꿔 마감이 임박했음을 체감시킨다.
function SeasonConfig.timeLeftText()
	local s = SeasonConfig.secondsLeft()
	if s <= 0 then return "Ended" end
	local d = math.floor(s / 86400)
	local h = math.floor((s % 86400) / 3600)
	local m = math.floor((s % 3600) / 60)
	if d > 0 then return string.format("%dd %dh", d, h) end
	if h > 0 then return string.format("%dh %dm", h, m) end
	return string.format("%dm", m)
end

-- 시즌 식별자: 1 -> "season1"
function SeasonConfig.id(n)
	return "season" .. (n or SeasonConfig.SEASON_NUMBER)
end

-- 이전 시즌 식별자. 시즌 1이면 이전이 없으므로 nil.
-- 명예의 전당 lazy 마이그레이션(지난 시즌 1위 소급 박제)에서 사용.
function SeasonConfig.previousId()
	local prev = SeasonConfig.SEASON_NUMBER - 1
	if prev < 1 then return nil end
	return SeasonConfig.id(prev)
end

-- 배틀패스 저장 키: "season1_12345"
function SeasonConfig.battlePassKey(userId)
	return SeasonConfig.id() .. "_" .. userId
end

-- 리더보드 OrderedDataStore 이름: "LB_season1_KingWins"
-- seasonId를 넘기면 과거 시즌 보드도 읽을 수 있다(명예의 전당용).
function SeasonConfig.boardStoreName(boardId, seasonId)
	return "LB_" .. (seasonId or SeasonConfig.id()) .. "_" .. boardId
end

return SeasonConfig
