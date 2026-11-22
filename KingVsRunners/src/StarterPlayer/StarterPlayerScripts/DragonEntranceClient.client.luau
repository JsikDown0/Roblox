-- DragonEntranceClient: 곡선 비행 + 절벽 회피 + 날개 펄럭 + 불꽃벽 추적 + 사운드
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local countdownEvent = ReplicatedStorage:WaitForChild("FirePressureCountdown")

local dragon = workspace:FindFirstChild("skeleton dragon") or workspace:WaitForChild("map2"):WaitForChild("skeleton dragon")
local plate = workspace:FindFirstChild("centerpart", true) or workspace:WaitForChild("map2"):WaitForChild("map2 castle folder"):WaitForChild("map2 castle"):WaitForChild("centerpart")
local wing = dragon:FindFirstChild("leak")  -- 통짜 날개 파트

local ENTRANCE_LEAD = 3    -- 불꽃벽 N초 전 등장 시작
local FLY_TIME = 3.0       -- 비행(등장/복귀) 소요(초)
local RISE = 150           -- 출발 직후 솟구침 높이
local DIVE = 250           -- 강하 시작 고도(도착점 위로)
local HORIZ_BIAS = 0.10    -- control 수평 치우침(작을수록 강하 수직)

-- 불꽃벽 추적 설정
local CHASE_BEHIND = 160   -- 불꽃벽(FirePillar_1)보다 뒤 거리(stud)
local CHASE_LERP   = 3     -- 추적 부드러움(클수록 빠르게 따라붙음)
local STILL_DX     = 0.02  -- 프레임당 X변화가 이보다 작으면 "멈춤"으로 간주
local STILL_TIME   = 1.5   -- 멈춤이 이 시간 지속되면 끝 도달 → 복귀

-- 사운드 볼륨
local VOL_FULL = 0.8       -- 등장/퇴장 비행음 볼륨
local VOL_HALF = 0.6      -- 불꽃벽 진행 중 비행음 볼륨(절반)

local wcf, wsize = plate.CFrame, plate.Size
local SAFE_Y = (wcf.Position.Y + wsize.Y / 2) + 80

-- 도착(arriveCF)=원본 드래곤 배치 위치 / 출발·복귀(departCF)=skeleton dragon2 자세 참고값
local arriveCF = dragon:GetPivot()
local departCF = CFrame.new(835.48, 236.01, 895.46) * CFrame.fromOrientation(math.rad(-15), math.rad(90), 0)
local wingRel  = wing and arriveCF:ToObjectSpace(wing.CFrame)

-- 사운드(드래곤에 부착, 3D)
local soundParent = dragon.PrimaryPart or dragon:FindFirstChild("Meshes/Bones_SM_Env_Bone_Rigcage_01") or dragon:FindFirstChildWhichIsA("BasePart")
local VOL_FIRE = 0.7       -- fire breath volume
local soundFly = Instance.new("Sound")    -- A: 등장/퇴장/진행 비행음
soundFly.SoundId = "rbxassetid://78381988783824"
soundFly.Looped = true
soundFly.Volume = VOL_FULL
soundFly.RollOffMode = Enum.RollOffMode.Linear
soundFly.RollOffMinDistance = 100
soundFly.RollOffMaxDistance = 500
soundFly.Parent = soundParent
local soundFire = Instance.new("Sound")   -- B: 불꽃 분사음
soundFire.SoundId = "rbxassetid://132960610285205"
soundFire.Looped = true
soundFire.Volume = VOL_FIRE
soundFire.RollOffMode = Enum.RollOffMode.Linear
soundFire.RollOffMinDistance = 100
soundFire.RollOffMaxDistance = 500
soundFire.Parent = soundParent

-- 날개 펄럭
local FLAP_FREQ  = 2.4
local FLAP_PITCH = 0.10
local FLAP_ROLL  = 0.06
local targetFlap = 0
local flapAmp = 0

local function setFire(on)
	local pf = dragon:FindFirstChild("Pillar of fire")
	if not pf then return end
	for _, d in ipairs(pf:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = on
		end
	end
end

local function bezier3(p0, p1, p2, p3, t)
	local u = 1 - t
	return (u*u*u)*p0 + (3*u*u*t)*p1 + (3*u*t*t)*p2 + (t*t*t)*p3
end

-- 비행/추적 상태
local flying = false
local chasing = false
local returning = false   -- 복귀(퇴장) 비행 중인지
local flyT, flyDur = 0, 1
local fromCF, toCF
local bP0, bP1, bP2, bP3
local lastFireX, stillTime, fireY0 = nil, 0, nil

local function startFly(srcCF, dstCF, dur)
	print(string.format("🐉 [Dragon] startFly: from(%.0f,%.0f,%.0f) → to(%.0f,%.0f,%.0f)",
		srcCF.Position.X, srcCF.Position.Y, srcCF.Position.Z, dstCF.Position.X, dstCF.Position.Y, dstCF.Position.Z))
	chasing = false
	fromCF, toCF = srcCF, dstCF
	local p0, p3 = srcCF.Position, dstCF.Position
	local flat = (p3 - p0) * Vector3.new(1, 0, 1)
	local dist = flat.Magnitude
	local horiz = dist > 0.1 and flat.Unit or Vector3.new(0, 0, 0)
	local UP = Vector3.new(0, 1, 0)
	bP0 = p0
	bP3 = p3
	bP1 = p0 + UP * RISE + horiz * (dist * HORIZ_BIAS)
	bP2 = p3 + UP * DIVE - horiz * (dist * HORIZ_BIAS)
	bP1 = Vector3.new(bP1.X, math.max(bP1.Y, SAFE_Y), bP1.Z)
	bP2 = Vector3.new(bP2.X, math.max(bP2.Y, SAFE_Y), bP2.Z)
	flyDur = dur
	flyT = 0
	flying = true
	targetFlap = 1
end

-- 불기둥 미발견 유예: startChase 직후에는 서버가 만든 FirePressurePillars 가 아직
-- 클라이언트로 복제되지 않았을 수 있다. 첫 프레임에 "못 찾음 = 소멸"로 판정하면
-- 추적 시작 수 ms 만에 대기 위치로 돌아가버린다 (2026-08 실측: startChase 4ms 뒤 복귀).
-- → 연속 miss 가 임계치를 넘을 때만 소멸로 인정한다. 실제 소멸(라운드 종료)은
--    보통 clear 이벤트가 먼저 오므로, 이 안전망은 그 누락분만 받으면 된다.
local MISS_GRACE = 90     -- 연속 미발견 허용 프레임 (60fps 기준 약 1.5초)
local missFrames = 0

local function startChase()
	print("🐉 [Dragon] startChase 진입 (불꽃벽 추적 시작)")
	flying = false
	chasing = true
	lastFireX = nil
	stillTime = 0
	fireY0 = nil
	targetFlap = 1
	missFrames = 0
end

RunService.RenderStepped:Connect(function(dt)
	local bodyCF
	if flying then
		flyT = math.min(flyT + dt / flyDur, 1)
		local a = flyT * flyT * (3 - 2 * flyT)  -- smoothstep
		local pos  = bezier3(bP0, bP1, bP2, bP3, a)
		local aN   = math.min(a + 0.02, 1)
		local posN = bezier3(bP0, bP1, bP2, bP3, aN)
		local dir  = posN - pos
		local faceCF
		if dir.Magnitude > 0.01 then
			faceCF = CFrame.lookAt(pos, pos + dir)
		else
			faceCF = CFrame.new(pos) * toCF.Rotation
		end
		if a < 0.15 then
			bodyCF = (CFrame.new(pos) * fromCF.Rotation):Lerp(faceCF, a / 0.15)
		elseif a > 0.85 then
			bodyCF = faceCF:Lerp(CFrame.new(pos) * toCF.Rotation, (a - 0.85) / 0.15)
		else
			bodyCF = faceCF
		end
		if flyT >= 1 then
			flying = false
			targetFlap = 0
			bodyCF = toCF
			if returning then soundFly:Stop(); returning = false end  -- 퇴장 완료 → 비행음 정지
		end
	elseif chasing then
		local pillars = workspace:FindFirstChild("FirePressurePillars")
		local p1 = pillars and pillars:FindFirstChild("FirePillar_1")
		if p1 then
			missFrames = 0
			local fx = p1.Position.X
			local fy = p1.Position.Y
			if fireY0 == nil then fireY0 = fy end
			if lastFireX and math.abs(fx - lastFireX) < STILL_DX then
				stillTime = stillTime + dt
			else
				stillTime = 0
			end
			lastFireX = fx
			if stillTime >= STILL_TIME then
				-- [원본] 불꽃벽 정지 = 밀어내기 완료 → 대기 위치(departCF)로 복귀.
				setFire(false)
				soundFire:Stop()
				returning = true
				soundFly.Volume = VOL_FULL
				startFly(dragon:GetPivot(), departCF, FLY_TIME)
				bodyCF = dragon:GetPivot()
			else
				local cur = dragon:GetPivot()
				local k = math.min(dt * CHASE_LERP, 1)
				local targetY = arriveCF.Position.Y + (fy - fireY0)
				local nx = cur.Position.X + ((fx - CHASE_BEHIND) - cur.Position.X) * k
				local ny = cur.Position.Y + (targetY - cur.Position.Y) * k
				local nz = cur.Position.Z + (arriveCF.Position.Z - cur.Position.Z) * k
				bodyCF = CFrame.new(nx, ny, nz) * arriveCF.Rotation
			end
		else
			-- 불기둥 미발견 → 즉시 복귀하지 않고 유예 프레임을 센다.
			-- (서버 생성분이 복제되기 전이면 잠깐 못 찾는 게 정상)
			missFrames = missFrames + 1
			if missFrames >= MISS_GRACE then
				-- 불기둥 소멸 = 추적 대상 없음 → 대기 위치(departCF) 복귀 (clear 누락/경합 대비 안전망)
				print("🐉 [Dragon] 불기둥 소멸 감지 → 대기 위치 복귀 (miss " .. missFrames .. "프레임)")
				setFire(false)
				soundFire:Stop()
				returning = true
				soundFly.Volume = VOL_FULL
				startFly(dragon:GetPivot(), departCF, FLY_TIME)
				bodyCF = dragon:GetPivot()
			else
				-- 유예 중: 아직 복귀하지 않는다. bodyCF 를 비워두면 아래 PivotTo 가 nil 을 받으므로
				-- 현재 위치를 그대로 유지시킨다. (이 줄이 없으면 "Argument 1 missing or nil" 발생)
				bodyCF = dragon:GetPivot()
			end
		end
	else
		-- idle(비행·추적 아님): 드래곤을 서버 앵커에 맡기고 손 뗀다.
		-- 매 프레임 GetPivot→PivotTo로 자기 위치를 자기가 다시 쓰면, 승리 선언(라운드 종료) 시
		-- 서버의 map2 스왑(원본 CFrame 재복제)과 프레임 단위로 쟁탈해 '몸이 뒤틀림'이 생긴다.
		-- → idle이면 PivotTo 자체를 건너뛰고 날개도 잠재운다.
		flapAmp = flapAmp + (0 - flapAmp) * math.min(dt * 4, 1)
		return
	end
	dragon:PivotTo(bodyCF)
	-- 날개 펄럭 (몸통 따라가며)
	flapAmp = flapAmp + (targetFlap - flapAmp) * math.min(dt * 4, 1)
	if wing and wingRel then
		local tt = os.clock() * FLAP_FREQ * math.pi * 2
		local pitch = math.sin(tt) * FLAP_PITCH * flapAmp
		local roll  = math.sin(tt * 0.5) * FLAP_ROLL * flapAmp
		wing.CFrame = bodyCF * wingRel * CFrame.Angles(pitch, 0, roll)
	end
end)

-- 초기: 대기 위치 + 불꽃 off
dragon:PivotTo(departCF)
setFire(false)

local entered = false

-- 🗺️ [2026-09-07] 이 연출은 map2 전용이다.
--   [증상] map1 라운드인데 사막 쪽 하늘에 스켈레톤 드래곤이 날아다녔다.
--     실측 로그: map1 선택 판에서 startFly: to(-281, 98, 891) — Z≈891 은 map2 좌표다
--     (map1 은 Z≈-674). 플레이어에겐 그냥 버그로 보인다.
--   [원인] dragon 도 plate 도 workspace.map2 하위에서 가져오는데(위 8~9행),
--     정작 이 스크립트는 어느 맵인지 확인하지 않았다. 확인할 수단이 없었기 때문이다 —
--     SetCurrentMap 은 BindableEvent 라 서버 전용이고 클라는 받지 못한다.
--   [해결] RoundSystem 이 ReplicatedStorage.CurrentMap 속성으로도 남기게 했다.
--   ⚠️ 속성이 없으면(부팅 직후·구버전) 막지 않는다. 모르면 기존 동작을 유지한다 —
--     연출이 안 나오는 것보다 잘못 막아서 map2 에서도 안 나오는 쪽이 더 나쁘다.
local function isDragonMap()
	local m = ReplicatedStorage:GetAttribute("CurrentMap")
	if m == nil then return true end   -- 모르면 종전대로
	return m == "map2"
end

countdownEvent.OnClientEvent:Connect(function(eventType, value)
	if not isDragonMap() then
		-- 다른 맵이면 연출 자체를 건너뛴다. 상태를 건드리기 전에 나간다.
		return
	end
	print(string.format("🐉 [Dragon] 이벤트 수신: %s (value=%s) | flying=%s chasing=%s returning=%s entered=%s",
		tostring(eventType), tostring(value), tostring(flying), tostring(chasing), tostring(returning), tostring(entered)))
	if eventType == "tick" then
		if value and value <= ENTRANCE_LEAD and not entered then
			entered = true
			returning = false
			soundFly.Volume = VOL_FULL
			soundFly:Play()                  -- 등장 비행음 (풀 볼륨)
			-- [원본] 대기 위치(departCF = 성 지붕 위 상공)에서 불꽃벽 위치(arriveCF)로 비행.
			startFly(departCF, arriveCF, FLY_TIME)
		end
	elseif eventType == "started" then
		setFire(true)
		soundFire:Play()                     -- 불꽃 분사음 시작
		soundFly.Volume = 0           -- 진행 중 날갯짓 OFF (불꽃벽 전진)
		startChase()
	elseif eventType == "clear" then
		-- 중복 clear 방어: 이미 복귀 중이거나 대기(비행·추적 아님) 상태면 무시.
		-- (승리 시 clear가 한 번 더 와서 상공→상공 startFly로 발작하던 문제 차단)
		if returning or (not flying and not chasing) then
			print("🐉 [Dragon] clear 무시 (이미 복귀중/대기중)")
			return
		end
		setFire(false)
		soundFire:Stop()                     -- 분사음 정지
		returning = true
		soundFly.Volume = VOL_FULL           -- 복귀 비행음 (풀 볼륨)
		-- [원본] 대기 위치(departCF = 성 지붕 위 상공)로 복귀.
		startFly(dragon:GetPivot(), departCF, FLY_TIME)
		entered = false
	end
end)

-- 개발용 커맨드: /dg → 등장→분사→복귀 (불꽃벽 없으니 추적 제외)
local devBusy = false
local function devShow()
	if devBusy then return end
	devBusy = true
	flying = false
	chasing = false
	returning = false
	dragon:PivotTo(departCF)
	setFire(false)
	soundFire:Stop()
	task.wait(0.4)
	soundFly.Volume = VOL_FULL
	soundFly:Play()
	startFly(departCF, arriveCF, FLY_TIME)
	repeat task.wait(0.05) until not flying
	setFire(true)
	soundFire:Play()
	soundFly.Volume = 0
	task.wait(3)
	setFire(false)
	soundFire:Stop()
	soundFly.Volume = VOL_FULL
	returning = true
	startFly(arriveCF, departCF, FLY_TIME)
	repeat task.wait(0.05) until not flying
	devBusy = false
end
TextChatService.SendingMessage:Connect(function(msg)
	if msg.Text and msg.Text:lower() == "/dg" then
		task.spawn(devShow)
	end
end)

print("[DragonEntrance] ready / sound="..(soundParent and "O" or "X").." / dev: /dg")
-- ─── 라운드 경계 리셋 ────────────────────────────────────────
-- DragonEntranceClient는 countdownEvent(tick/started/clear)만 받아서,
-- 라운드가 clear 없이 끝나면(승리 등) chasing/returning 등 상태가 다음 라운드로 샌다.
-- → intermission phase마다 모든 상태를 초기화하고 드래곤을 지붕(departCF)에 정착시킨다.
local RoundPhaseEvent = ReplicatedStorage:WaitForChild("RoundPhaseEvent")
RoundPhaseEvent.OnClientEvent:Connect(function(phase)
	if phase == "intermission" then
		print("🐉 [Dragon] intermission → 상태 완전 리셋 + 지붕 정착")
		flying = false
		chasing = false
		returning = false
		entered = false
		targetFlap = 0
		flyT = 0
		lastFireX, stillTime, fireY0 = nil, 0, nil
		if soundFly then soundFly:Stop() end
		if soundFire then soundFire:Stop() end
		setFire(false)
		-- 지붕 정착 (departCF = 대기 위치). idle 손떼기가 이후 서버 앵커에 맡김.
		pcall(function() dragon:PivotTo(departCF) end)
	end
end)
