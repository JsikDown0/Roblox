-- DeathHeatmapSystem — 다운 위치 히트맵 수집
-- 목적: "어느 구간에서 죽나" 데이터화 (맵 진행 = X축, 50 stud 버킷)
--   ① 계단 근접스폰 즉사 전략이 실제로 유효한지 검증 (텔레그래프 도입/튜닝 근거)
--   ② 신규 이탈 지점(데스존) 파악 → 맵/밸런스 패치 근거
-- 사용: _G.RecordDown(position, itemName) — ItemDamageSystem 다운/즉사 지점에서 호출
-- 조회: /deathmap (dev 채팅) 또는 라운드 종료 시 자동 요약 로그
-- 영구화: DataStore "DeathHeatmap_v1"에 5분 주기 + 서버 종료 시 증분 플러시

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local BUCKET = 50            -- X축 버킷 크기(stud)
local FLUSH_INTERVAL = 300   -- DataStore 플러시 주기(초)

-- 세션 누적: [버킷X] = { count = n, items = { [itemName] = n } }
local session = {}
-- 플러시 대기 증분: [버킷X] = n (DataStore IncrementAsync용)
local pending = {}

local store
pcall(function() store = DataStoreService:GetDataStore("DeathHeatmap_v1") end)

local function bucketOf(x)
	return math.floor(x / BUCKET) * BUCKET
end

_G.RecordDown = function(position, itemName)
	if typeof(position) ~= "Vector3" then return end
	local b = bucketOf(position.X)
	local e = session[b]
	if not e then e = { count = 0, items = {} } session[b] = e end
	e.count += 1
	if itemName then e.items[itemName] = (e.items[itemName] or 0) + 1 end
	pending[b] = (pending[b] or 0) + 1
end

-- 요약 문자열 (상위 n개 구간)
local function summary(topN)
	local list = {}
	for b, e in pairs(session) do list[#list + 1] = { b = b, e = e } end
	table.sort(list, function(a, c) return a.e.count > c.e.count end)
	local out = {}
	for i = 1, math.min(topN or 6, #list) do
		local it = list[i]
		-- 구간별 최다 아이템
		local topItem, topCnt = "?", 0
		for name, cnt in pairs(it.e.items) do
			if cnt > topCnt then topItem, topCnt = name, cnt end
		end
		out[#out + 1] = string.format("X %d~%d: %d회 (주범: %s)", it.b, it.b + BUCKET, it.e.count, topItem)
	end
	return #out > 0 and table.concat(out, " | ") or "(데이터 없음)"
end

_G.DeathHeatmapSummary = function() return summary(6) end

-- 라운드 종료 시 자동 요약 (RoundSystem이 호출해도 되고, 여기선 5분 주기로도 출력)
task.spawn(function()
	while true do
		task.wait(FLUSH_INTERVAL)
		local hasData = next(session) ~= nil
		if hasData then
			print("💀 [DeathHeatmap] " .. summary(6))
		end
		-- DataStore 플러시 (증분)
		if store and next(pending) then
			local toFlush = pending
			pending = {}
			for b, n in pairs(toFlush) do
				local ok = pcall(function()
					store:IncrementAsync("bucket_" .. b, n)
				end)
				if not ok then
					-- 실패분 복원 (다음 주기 재시도)
					pending[b] = (pending[b] or 0) + n
				end
				task.wait(0.5)  -- 요청 예산 보호
			end
		end
	end
end)

-- 서버 종료 시 최종 플러시
game:BindToClose(function()
	if not store then return end
	for b, n in pairs(pending) do
		-- 🛡️ [2026-09-06] 여기만 보고를 붙인다.
		--   위쪽 주기 플러시는 실패해도 pending 에 복원해 다음 주기에 재시도하므로
		--   손실이 아니다 — 거기까지 보고하면 소음만 는다.
		--   반면 종료 시점에는 재시도 기회가 없어 실패가 곧 유실이다.
		--   ⚠️ 히트맵은 개발용 통계라 유저 데이터보다 급하진 않다. 건수 파악용이다.
		local ok, err = pcall(function() store:IncrementAsync("bucket_" .. b, n) end)
		if not ok and _G.ReportSaveFailure then _G.ReportSaveFailure("DeathHeatmap_v1", err) end
	end
end)

-- dev 조회 명령
local isDev
pcall(function() isDev = require(game:GetService("ServerScriptService"):WaitForChild("DevAuth")).isDev end)
local function onChat(player, msg)
	if isDev and not isDev(player) then return end
	local m = msg:lower()
	if m == "/deathmap" then
		print("💀 [DeathHeatmap 세션] " .. summary(10))
	elseif m == "/deathmap all" then
		-- 영구 누적 조회 (버킷 0~1000 범위 스캔)
		if not store then print("💀 DataStore 비활성") return end
		task.spawn(function()
			local rows = {}
			for b = -200, 1000, BUCKET do
				local ok, v = pcall(function() return store:GetAsync("bucket_" .. b) end)
				if ok and v and v > 0 then rows[#rows + 1] = { b = b, v = v } end
				task.wait(0.1)
			end
			table.sort(rows, function(a, c) return a.v > c.v end)
			local out = {}
			for i = 1, math.min(10, #rows) do
				out[#out + 1] = string.format("X %d~%d: %d회", rows[i].b, rows[i].b + BUCKET, rows[i].v)
			end
			print("💀 [DeathHeatmap 누적] " .. (#out > 0 and table.concat(out, " | ") or "(없음)"))
		end)
	end
end
Players.PlayerAdded:Connect(function(p) p.Chatted:Connect(function(m) onChat(p, m) end) end)
for _, p in ipairs(Players:GetPlayers()) do p.Chatted:Connect(function(m) onChat(p, m) end) end

print("✅ DeathHeatmapSystem 준비 (X " .. BUCKET .. "-stud 버킷, /deathmap, /deathmap all)")
