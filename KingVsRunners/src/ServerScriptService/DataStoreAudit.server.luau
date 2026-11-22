-- DataStoreAudit — 저장이 실제로 실패했는지 라이브에서 알 수 있게 남긴다.
--
-- [왜 필요한가] "DataStore request was added to queue" 경고는 큐에 들어갔다는 뜻이지
--   버려졌다는 뜻이 아니다. 그런데 지금은 둘을 구분할 방법이 없다.
--   · ErrorLogger 는 콘솔 전용이라 라이브에서 아무도 못 본다(서버가 죽으면 같이 사라진다).
--   · 저장은 대부분 pcall 로 감싸여 있어 크리에이터 허브 '오류'에도 안 잡힌다.
--   · 유저 신고를 기다리는 건 늦고 부정확하다 — 손실이 유저에게 이득인 경우엔 신고가 안 온다.
--
-- [무엇을 보내는가] AnalyticsService (OnboardingFunnel 이 이미 쓰는 경로).
--   크리에이터 허브 > 애널리틱스에서 건수로 보인다. 서버가 죽어도 남는다.
--
-- ⚠️ Studio 에서는 AnalyticsService 가 전송되지 않는다(라이브 전용).
--   그래서 Studio 에서는 print 로만 남기고, 검증은 라이브에서 한다.
--
-- ⚠️ 이건 진단 코드가 아니라 상시 안전장치다. 릴리즈 전 삭제 목록에 넣지 말 것.

local AnalyticsService = game:GetService("AnalyticsService")
local DataStoreService  = game:GetService("DataStoreService")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local IS_STUDIO = RunService:IsStudio()

-- 마지막으로 본 플레이어. 종료 시 보고용 (위 send 주석 참조).
local lastSeenPlayer = nil
Players.PlayerAdded:Connect(function(p) lastSeenPlayer = p end)
Players.PlayerRemoving:Connect(function(p) lastSeenPlayer = p end)
for _, p in ipairs(Players:GetPlayers()) do lastSeenPlayer = p end

local function send(eventName, value, fields)
	if IS_STUDIO then
		warn(string.format("🚨 [DSAudit] %s = %s | %s", eventName, tostring(value),
			game:GetService("HttpService"):JSONEncode(fields or {})))
		return
	end
	-- ⚠️ [실측 2026-09-06] 종료 감사가 "인원 0"으로 찍혔다.
	--   BindToClose 시점엔 플레이어가 이미 나간 뒤라 LogCustomEvent 가 요구하는
	--   Player 인스턴스가 없다 — 그대로 두면 정작 가장 중요한 종료 보고가 통째로 안 나간다.
	--   [해결] 마지막으로 본 Player 를 기억해 둔다. Parent 가 nil 이어도 인스턴스는
	--   살아 있어 LogCustomEvent 인자로는 쓸 수 있다.
	--   ⚠️ 그래도 실패할 수 있으므로 pcall 안에 둔다 — 감사기가 종료를 막으면 안 된다.
	local anyPlayer = Players:GetPlayers()[1] or lastSeenPlayer
	if not anyPlayer then
		warn("🚨 [DSAudit] 보고 불가(플레이어 없음): " .. eventName)
		return
	end
	pcall(function()
		AnalyticsService:LogCustomEvent(anyPlayer, eventName, value or 1, fields)
	end)
end

-- ── ① 저장 실패 보고 창구 ──────────────────────────────────
-- 각 시스템의 pcall 실패 지점에서 부르면 된다:
--   local ok, err = pcall(...)
--   if not ok then _G.ReportSaveFailure("PlayerRunnerData_v1", err) end
-- ⚠️ 한 번에 한 시스템씩 연결한다. 7곳을 동시에 고치면 무엇이 깨졌는지 못 가른다.
local failCount = 0
_G.ReportSaveFailure = function(storeName, err)
	failCount = failCount + 1
	warn(string.format("🚨 [DSAudit] 저장 실패 #%d — %s | %s",
		failCount, tostring(storeName), tostring(err)))
	send("DataStoreSaveFailed", 1, { store = tostring(storeName) })
end

-- ── ② 종료 시 예산 소진 감시 ───────────────────────────────
-- [원리] 로블록스는 저장 예산을 분당 (60 + 인원×10) 으로 준다.
--   종료 시 전원이 동시에 저장하면 이 예산이 바닥나고, 바닥나면 큐가 쌓인다.
--   큐가 30초(BindToClose 한도) 안에 안 빠지면 그게 실제 손실이다.
-- ⚠️ 이 핸들러는 다른 BindToClose 와 '동시에' 돈다. 그래서 저장을 막지 않고
--   옆에서 예산만 지켜본다 — 여기서 task.wait 을 오래 걸면 남의 저장 시간을 뺏는다.
game:BindToClose(function()
	local t0 = os.clock()
	local playerCount = #Players:GetPlayers()
	local budgetType = Enum.DataStoreRequestType.SetIncrementAsync

	local function budget()
		local ok, v = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(budgetType)
		end)
		return ok and v or -1
	end

	local before = budget()
	local lowest = before

	-- 최대 20초까지 0.5초 간격으로 예산을 지켜본다.
	--   ⚠️ 30초 한도를 다 쓰지 않는다. 남은 시간은 실제 저장이 끝낼 몫이다.
	for _ = 1, 40 do
		task.wait(0.5)
		local b = budget()
		if b >= 0 and b < lowest then lowest = b end
		if b > before * 0.9 then break end   -- 예산이 회복됐다 = 저장이 끝났다
	end

	local elapsed = os.clock() - t0
	warn(string.format(
		"📉 [DSAudit] 종료 감사 | 인원 %d | 예산 %d → 최저 %d | 경과 %.1fs | 세션 실패 %d건",
		playerCount, before, lowest, elapsed, failCount))

	-- 예산이 0 까지 갔다 = 큐가 쌓였다 = 손실 위험 구간
	if lowest == 0 then
		send("DataStoreBudgetExhausted", 1,
			{ players = tostring(playerCount), elapsed = string.format("%.1f", elapsed) })
	end
	-- 20초를 다 쓰고도 회복 못 함 = 30초 한도에 근접 = 실제 손실 가능
	if elapsed >= 19.5 then
		send("DataStoreShutdownSlow", 1, { players = tostring(playerCount) })
	end
	if failCount > 0 then
		send("DataStoreSessionFailures", failCount, {})
	end
end)

print("🛡️ DataStoreAudit 준비 (_G.ReportSaveFailure / 종료 예산 감시)")
