--[[ DataSoldierLab v2 (2026-11-10) — 데이터 병사 1단계: 서버만 (화면 표시 없음)

  ■ v1 → v2 (v1 실측: 500명 시뮬 7.3ms/틱 · 최대 19.6ms, 송신 308kbps/클라)
    ① 틱을 3프레임에 나눠 돈다(한 프레임에 7ms 덩어리 대신 2~3ms 셋)
    ② 칸 12 → 6, 병사 1명이 살피는 이웃 최대 32 — 몰린 곳에서 O(k²) 를 막는다 [추측: v1 비용의 대부분이 몰림]
       확인용으로 '가장 붐빈 칸 인원 · 1명당 살핀 이웃 수'를 찍는다
    ③ 표적 기억: 살아 있고 시야 안이면 다음 틱에도 같은 표적(매 틱 새로 찾지 않는다)
    ④ 송신: 플레이어별 관심 반경. 150 스터드 안 = 10Hz, 밖 = 2Hz. 높이(y) 빼서 1명 7바이트 — 높이는 클라가 그릴 때 지형에서 구한다
       v1 원본 ServerStorage._Archive_데이터병사_20261110.DataSoldierLab_v1

  ■ 켜고 끄기: workspace 속성 DataSoldierLab (숫자). 0 이나 없음 = 이 스크립트는 아무것도 안 한다.
    켜져 있으면 F5 한 번에 아래 순서가 자동으로 돈다(약 110초). 본 게임 물결은 _G.AttackWaves = false 로 멈춘다.
      기준(0) 15초 → 300 30초 → 500 30초 → 기준(0) 재 15초 → 300 재 20초
    각 단계 앞 5초는 버린다(생성·워밍업).

  ■ 무엇을 재나
    병사는 Humanoid · 파트 · 스크립트 없이 표(배열)로만 있다. 서버가 20Hz 로 이동 · 표적 · 공격 · 사망 · 재생성을 계산하고,
    10Hz 로 위치를 묶어 보낸다(UnreliableRemoteEvent, 패킷당 90명 · 9바이트/명 — 선례 HitFxSoldier).
    더미 장수 8명(편당 4)이 분당 90명씩 베고 20초마다 무쌍(반경 10 · 최대 20명)을 쓴다 = 기획안 2차 규모의 처치 속도.
      시뮬 ms  : os.clock 으로 잰 우리 코드의 순수 비용(정확)
      프레임    : Heartbeat 간격. ⚠️ 9월 하네스 규칙 2 — 숫자가 아니라 문턱(17ms·33ms 넘은 프레임 수)으로 읽는다
      송신      : 보낸 바이트(클라 한 명당)
    ⚠️ 규칙 1: 기준(0) 재측정이 첫 기준과 다르면 그 사이 결과는 무효.

  ■ 원본·선례: ServerStorage.PerfArchive(2026-09-22) README · 프로젝트 문서 claude/군대전투_성능실측_20260922.md
]]

local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Stats = game:GetService("Stats")

local LAB = workspace:GetAttribute("DataSoldierLab")
if not LAB or LAB == 0 then return end
_G.AttackWaves = false

local CFG = {
	TICK = 0.05, SEND = 0.1, PER_PACKET = 120, BYTES = 7, SLICES = 3, MAX_CHECK = 32,
	NEAR = 150, FAR_EVERY = 5,
	CELL = 6, SIGHT = 12, REACH = 3.5, SPEED = 10, SEP = 2,
	HP = 3, ATK_CD = 1.2, ATK_HIT = 0.35,
	RAY_EVERY = 1.0,
	X_ATK = 1900, X_DEF = 1500, LANES = { 700, 752, 804 }, LANE_W = 18,
	SWEEPERS = 4, SWEEP_SPEED = 16, SWEEP_RATE = 1.5, SWEEP_R = 7,
	ULT_EVERY = 20, ULT_R = 10, ULT_MAX = 20,
	RESPAWN_EVERY = 1.0, RESPAWN_DELAY = 1.0,
	ORIGIN = Vector3.new(1700, 0, 752),
}
local PHASES = {
	{ name = "기준(0)", n = 0, t = 15 },
	{ name = "300", n = 300, t = 30 },
	{ name = "500", n = 500, t = 30 },
	{ name = "기준(0) 재", n = 0, t = 15 },
	{ name = "300 재", n = 300, t = 20 },
}
local WARM = 5
local MAXN = 500
local HALF = MAXN // 2

local snap = RS:FindFirstChild("DataSoldierSnap")
if not snap then
	snap = Instance.new("UnreliableRemoteEvent"); snap.Name = "DataSoldierSnap"; snap.Parent = RS
end

----------------------------------------------------------------- 데이터
local x, y, z, team, hp, alive, atkAt, lane, rayAt, deadAt, tgt, last = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
for i = 1, MAXN do
	team[i] = (i <= HALF) and 1 or 2
	alive[i] = false; deadAt[i] = -math.huge
	x[i], y[i], z[i] = 0, 0, 0; hp[i] = 0; atkAt[i] = 0; lane[i] = 1; rayAt[i] = 0; tgt[i] = 0; last[i] = 0
end
local perTeam = 0

local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Include
rp.FilterDescendantsInstances = { workspace.Terrain }
local M = { rays = 0, kills = 0, spawns = 0, bytes = 0, packets = 0, checks = 0, updates = 0, maxCell = 0, near = 0, nearN = 0 }

local function ground(px, pz, fallback)
	M.rays += 1
	local r = workspace:Raycast(Vector3.new(px, 400, pz), Vector3.new(0, -800, 0), rp)
	return r and r.Position.Y or fallback
end

local function spawn(i, now)
	local t = team[i]
	lane[i] = math.random(1, #CFG.LANES)
	x[i] = (t == 1) and (CFG.X_ATK + math.random() * 30) or (CFG.X_DEF - math.random() * 30)
	z[i] = CFG.LANES[lane[i]] + (math.random() - 0.5) * CFG.LANE_W
	y[i] = ground(x[i], z[i], 20)
	hp[i] = CFG.HP; alive[i] = true; atkAt[i] = now + math.random() * CFG.ATK_CD
	rayAt[i] = now + math.random() * CFG.RAY_EVERY
	tgt[i] = 0; last[i] = now
	M.spawns += 1
end

local function kill(j, now)
	if not alive[j] then return end
	alive[j] = false; deadAt[j] = now; M.kills += 1
end

----------------------------------------------------------------- 공간 해시
local cells = {}
local floor = math.floor
local function key(cx, cz) return cx * 65536 + cz end

local function rebuild()
	table.clear(cells)
	for i = 1, MAXN do
		if alive[i] then
			local k = key(floor(x[i] / CFG.CELL), floor(z[i] / CFG.CELL))
			local c = cells[k]
			if not c then c = {}; cells[k] = c end
			c[#c + 1] = i
			if #c > M.maxCell then M.maxCell = #c end
		end
	end
end

----------------------------------------------------------------- 더미 장수
local sweepers = {}
for s = 1, CFG.SWEEPERS * 2 do
	local t = (s <= CFG.SWEEPERS) and 1 or 2
	sweepers[s] = { team = t, x = (t == 1) and CFG.X_ATK or CFG.X_DEF, z = CFG.LANES[(s % 3) + 1],
		nextKill = 0, nextUlt = s * (CFG.ULT_EVERY / (CFG.SWEEPERS * 2)) }
end

local function sweeperStep(sw, dt, now)
	local cx, cz = floor(sw.x / CFG.CELL), floor(sw.z / CFG.CELL)
	local best, bd = nil, math.huge
	for dx = -2, 2 do for dz = -2, 2 do
		local c = cells[key(cx + dx, cz + dz)]
		if c then for _, j in ipairs(c) do
			if alive[j] and team[j] ~= sw.team then
				local ddx, ddz = x[j] - sw.x, z[j] - sw.z
				local d2 = ddx * ddx + ddz * ddz
				if d2 < bd then bd = d2; best = j end
			end
		end end
	end end
	if now >= sw.nextUlt and best then
		sw.nextUlt = now + CFG.ULT_EVERY
		local n = 0
		for dx = -2, 2 do for dz = -2, 2 do
			local c = cells[key(cx + dx, cz + dz)]
			if c then for _, j in ipairs(c) do
				if n < CFG.ULT_MAX and alive[j] and team[j] ~= sw.team then
					local ddx, ddz = x[j] - sw.x, z[j] - sw.z
					if ddx * ddx + ddz * ddz <= CFG.ULT_R * CFG.ULT_R then kill(j, now); n += 1 end
				end
			end end
		end end
		return
	end
	local tx, tz
	if best then tx, tz = x[best], z[best] else tx, tz = CFG.ORIGIN.X, CFG.ORIGIN.Z end
	local ddx, ddz = tx - sw.x, tz - sw.z
	local d = math.sqrt(ddx * ddx + ddz * ddz)
	if best and d <= CFG.SWEEP_R then
		if now >= sw.nextKill then sw.nextKill = now + 1 / CFG.SWEEP_RATE; kill(best, now) end
	elseif d > 0.5 then
		local s = math.min(CFG.SWEEP_SPEED * dt, d)
		sw.x += ddx / d * s; sw.z += ddz / d * s
	end
end

----------------------------------------------------------------- 병사 한 틱 (조각)
local function updateOne(i, now)
	local dt = math.min(now - last[i], 0.2); last[i] = now
	local xi, zi, ti = x[i], z[i], team[i]
	local SIGHT2, REACH2, SEP2 = CFG.SIGHT ^ 2, CFG.REACH ^ 2, CFG.SEP ^ 2
	local best, bd, sx, sz = nil, SIGHT2, 0, 0
	-- ③ 표적 기억
	local t = tgt[i]
	if t ~= 0 and alive[t] then
		local ddx, ddz = x[t] - xi, z[t] - zi
		local d2 = ddx * ddx + ddz * ddz
		if d2 < SIGHT2 then best, bd = t, d2 end
	end
	local cx, cz = floor(xi / CFG.CELL), floor(zi / CFG.CELL)
	local checked = 0
	local R = best and 1 or 2              -- 표적이 있으면 가까운 칸만(떼밀기용), 없으면 시야 12 를 덮게 넓게
	for dx = -R, R do for dz = -R, R do
		if checked < CFG.MAX_CHECK then
			local c = cells[key(cx + dx, cz + dz)]
			if c then for _, j in ipairs(c) do
				if checked >= CFG.MAX_CHECK then break end
				if j ~= i and alive[j] then
					checked += 1
					local ddx, ddz = x[j] - xi, z[j] - zi
					local d2 = ddx * ddx + ddz * ddz
					if team[j] ~= ti then
						if d2 < bd then bd = d2; best = j end
					elseif d2 < SEP2 and d2 > 1e-4 then
						sx -= ddx / d2; sz -= ddz / d2
					end
				end
			end end
		end
	end end
	M.checks += checked; M.updates += 1
	tgt[i] = best or 0
	local mx, mz
	if best then
		if bd <= REACH2 then
			mx, mz = 0, 0
			if now >= atkAt[i] then
				atkAt[i] = now + CFG.ATK_CD
				if math.random() < CFG.ATK_HIT then
					hp[best] -= 1
					if hp[best] <= 0 then kill(best, now) end
				end
			end
		else
			local d = math.sqrt(bd)
			mx, mz = (x[best] - xi) / d, (z[best] - zi) / d
		end
	else
		mx = (ti == 1) and -1 or 1
		mz = (CFG.LANES[lane[i]] - zi) * 0.05
	end
	mx += sx * 0.5; mz += sz * 0.5
	local m = math.sqrt(mx * mx + mz * mz)
	if m > 1 then mx /= m; mz /= m end
	x[i] = xi + mx * CFG.SPEED * dt
	z[i] = zi + mz * CFG.SPEED * dt
	if (ti == 1 and x[i] < CFG.X_DEF - 80) or (ti == 2 and x[i] > CFG.X_ATK + 80) then
		alive[i] = false; deadAt[i] = now
	elseif now >= rayAt[i] then
		rayAt[i] = now + CFG.RAY_EVERY
		y[i] = ground(x[i], z[i], y[i])
	end
end

-- ① 한 틱 = SLICES 프레임. 조각 0 에서 해시를 다시 짓고, 조각마다 i % SLICES 가 맞는 병사만 움직인다
local sweepLast = 0
local function stepSlice(slice, now)
	if slice == 0 then rebuild() end
	for i = slice + 1, MAXN, CFG.SLICES do
		if alive[i] then updateOne(i, now) end
	end
	if slice == CFG.SLICES - 1 then
		local dt = math.min(now - sweepLast, 0.2); sweepLast = now
		for _, sw in ipairs(sweepers) do sweeperStep(sw, dt, now) end
	end
end

----------------------------------------------------------------- 재생성 · 단계 인원
local function respawnPass(now)
	for t = 1, 2 do
		local base = (t == 1) and 0 or HALF
		for k = 1, HALF do
			local i = base + k
			if k <= perTeam then
				if not alive[i] and now - deadAt[i] >= CFG.RESPAWN_DELAY then spawn(i, now) end
			elseif alive[i] then
				alive[i] = false
			end
		end
	end
end

----------------------------------------------------------------- 송신 (④ 플레이어별 관심 반경)
local Players = game:GetService("Players")
local sendCount = 0
local function packAndFire(pl, ids)
	local n, o, p = #ids, CFG.ORIGIN, 1
	while p <= n do
		local cnt = math.min(CFG.PER_PACKET, n - p + 1)
		local b = buffer.create(cnt * CFG.BYTES)
		local off = 0
		for q = p, p + cnt - 1 do
			local i = ids[q]
			buffer.writeu16(b, off, i)
			buffer.writei16(b, off + 2, math.clamp(math.round((x[i] - o.X) * 4), -32768, 32767))
			buffer.writei16(b, off + 4, math.clamp(math.round((z[i] - o.Z) * 4), -32768, 32767))
			buffer.writeu8(b, off + 6, team[i])
			off += CFG.BYTES
		end
		snap:FireClient(pl, b)
		M.bytes += cnt * CFG.BYTES; M.packets += 1
		p += cnt
	end
end
local function send()
	sendCount += 1
	local farTurn = (sendCount % CFG.FAR_EVERY == 0)
	local NEAR2 = CFG.NEAR * CFG.NEAR
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		local px, pz = root and root.Position.X or CFG.ORIGIN.X, root and root.Position.Z or CFG.ORIGIN.Z
		local ids, near = {}, 0
		for i = 1, MAXN do
			if alive[i] then
				local ddx, ddz = x[i] - px, z[i] - pz
				if ddx * ddx + ddz * ddz <= NEAR2 then ids[#ids + 1] = i; near += 1
				elseif farTurn then ids[#ids + 1] = i end
			end
		end
		M.near += near; M.nearN += 1
		packAndFire(pl, ids)
	end
end

----------------------------------------------------------------- 측정
local function newStat() return { ticks = 0, simSum = 0, simMax = 0, frames = 0, dtSum = 0, over17 = 0, over33 = 0, hbSum = 0, hbN = 0, aliveSum = 0, aliveN = 0 } end
local cur, results = newStat(), {}
local measuring = false

local function f1(v) return string.format("%.1f", v) end
local function summary(name, s, secs, m0)
	local kills = M.kills - m0.kills
	local line = ("[데이터병사S] %s | 평균 병사 %d | 시뮬 조각 평균 %sms 최대 %sms (조각 %d) | 프레임 평균 %sms · 17ms넘음 %d · 33ms넘음 %d (총 %d) | HB %sms | 처치/분 %d · 재생성/분 %d · 광선/초 %d | 송신 %skbps 패킷/초 %s"):format(
		name, cur.aliveN > 0 and math.floor(cur.aliveSum / cur.aliveN) or 0,
		f1(s.ticks > 0 and s.simSum / s.ticks * 1000 or 0), f1(s.simMax * 1000), s.ticks,
		f1(s.frames > 0 and s.dtSum / s.frames * 1000 or 0), s.over17, s.over33, s.frames,
		f1(s.hbN > 0 and s.hbSum / s.hbN or 0),
		math.floor(kills / secs * 60), math.floor((M.spawns - m0.spawns) / secs * 60), math.floor((M.rays - m0.rays) / secs),
		f1((M.bytes - m0.bytes) * 8 / 1000 / secs), f1((M.packets - m0.packets) / secs))
		.. (" | 가장 붐빈 칸 %d명 · 1명당 살핀 이웃 %s · 가까운(150) 병사 %d"):format(M.maxCell,
			f1((M.updates - m0.updates) > 0 and (M.checks - m0.checks) / (M.updates - m0.updates) or 0),
			(M.nearN - m0.nearN) > 0 and math.floor((M.near - m0.near) / (M.nearN - m0.nearN)) or 0)
	print(line)
	return line
end

----------------------------------------------------------------- 진행
local acc, sendAcc, respAcc, sliceNo = 0, 0, 0, 0
RunService.Heartbeat:Connect(function(dt)
	if measuring then
		cur.frames += 1; cur.dtSum += dt
		if dt > 0.017 then cur.over17 += 1 end
		if dt > 0.033 then cur.over33 += 1 end
		local ok, hb = pcall(function() return Stats.HeartbeatTimeMs end)
		if ok then cur.hbSum += hb; cur.hbN += 1 end
	end
	local now = os.clock()
	acc += dt; sendAcc += dt; respAcc += dt
	if respAcc >= CFG.RESPAWN_EVERY then respAcc = 0; respawnPass(now) end
	if acc >= CFG.TICK / CFG.SLICES then
		local t0 = os.clock()
		stepSlice(sliceNo, now)
		sliceNo = (sliceNo + 1) % CFG.SLICES
		local el = os.clock() - t0
		if measuring then
			cur.ticks += 1; cur.simSum += el; if el > cur.simMax then cur.simMax = el end
			local a = 0 for i = 1, MAXN do if alive[i] then a += 1 end end
			cur.aliveSum += a; cur.aliveN += 1
		end
		acc = 0
	end
	if sendAcc >= CFG.SEND then sendAcc = 0; send() end
end)

task.spawn(function()
	task.wait(8)   -- 접속 · 맵 로딩이 가라앉을 때까지
	print("[데이터병사S] v2 1단계 시작 — 서버만 · 단계 " .. #PHASES .. "개 · 본 게임 물결 멈춤")
	local lines = {}
	for _, ph in ipairs(PHASES) do
		perTeam = ph.n // 2
		workspace:SetAttribute("DataSoldierPhase", ph.name)
		respawnPass(os.clock())
		task.wait(WARM)
		cur = newStat()
		local m0 = { kills = M.kills, spawns = M.spawns, rays = M.rays, bytes = M.bytes, packets = M.packets, checks = M.checks, updates = M.updates, near = M.near, nearN = M.nearN }
		M.maxCell = 0
		measuring = true
		task.wait(ph.t - WARM)
		measuring = false
		table.insert(lines, summary(ph.name, cur, ph.t - WARM, m0))
	end
	perTeam = 0
	respawnPass(os.clock())
	workspace:SetAttribute("DataSoldierPhase", "끝")
	_G.AttackWaves = nil
	print("[데이터병사S] ===== 1단계 끝 — 요약 =====")
	for _, l in ipairs(lines) do print(l) end
end)
