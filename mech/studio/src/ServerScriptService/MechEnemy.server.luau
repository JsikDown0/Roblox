-- MechEnemy: 시험장 적 메카(탑승 불가) + 간단한 AI. CFG.EnemyAI = false 면 서 있는 표적.
-- 정체 표식 = 속성 EnemyMech (이름·클래스로 판별하지 않는다). "Mech" 태그가 있어서 MechClient 코드 애니메이션을 그대로 탄다
--   (속성 AimPitch·BoostUntil·MeleeAt 과 MechFX "fire" 로 다른 기체와 똑같이 그려진다)
-- 위치·방향 = workspace.MechTestRange.EnemySpawn 파트 / 수치 = MechConfig(Enemy*)
-- AI: 탑승한 메카 중 가장 가까운 상대를 노림 → 거리 유지하며 옆걸음 + 연사 → 가끔 옆 부스트 → 가까우면 내딛어 베기/주먹
-- 근접 판정은 MechServer 의 _G.MechStartMelee 를 같이 쓴다(플레이어와 같은 판정)
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local Proto = RS:WaitForChild("MechProto")
local CFG = require(Proto:WaitForChild("MechConfig"))
local Remotes = Proto:WaitForChild("Remotes")
local SM = require(Proto:WaitForChild("SoundManager"))   -- 소리는 SoundManager 로만
local Dmg = require(game:GetService("ServerScriptService"):WaitForChild("MechDamage"))   -- 피해 대상 판단(플레이어 무기와 같은 함수)
local Template = Proto:WaitForChild("MechTemplate")
local Range = workspace:WaitForChild("MechTestRange")
local Marker = Range:WaitForChild("EnemySpawn")

local function groundY(pos, ignore)
	local p = RaycastParams.new(); p.FilterType = Enum.RaycastFilterType.Exclude; p.FilterDescendantsInstances = ignore
	local r = workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -200, 0), p)
	return r and r.Position.Y or pos.Y
end

-- 머리 위 체력 표시 (크기는 스터드 단위라 멀수록 작아진다)
local function addHpBar(m, hum)
	local head = m:FindFirstChild("Head")
	local bb = Instance.new("BillboardGui")
	bb.Name = "EnemyHP"; bb.Adornee = head
	bb.Size = UDim2.new(10, 0, 1.2, 0); bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.LightInfluence = 0; bb.MaxDistance = 300
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1); back.BackgroundColor3 = Color3.fromRGB(30, 32, 38); back.BorderSizePixel = 0
	back.Parent = bb
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1); fill.BackgroundColor3 = Color3.fromRGB(178, 34, 62); fill.BorderSizePixel = 0
	fill.Parent = back
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1); label.BackgroundTransparency = 1
	label.TextScaled = true; label.Font = Enum.Font.GothamBold; label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = back
	local function refresh()
		local r = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
		fill.Size = UDim2.fromScale(r, 1)
		label.Text = tostring(math.max(0, math.floor(hum.Health + 0.5)))
	end
	hum.HealthChanged:Connect(refresh)
	refresh()
	bb.Parent = m
end

-- ================= AI =================
local function findTarget(m, root)
	local best, bestD = nil, CFG.EnemySight
	for _, o in ipairs(CollectionService:GetTagged("Mech")) do
		if o ~= m and o.Parent and o:GetAttribute("Pilot") then   -- 탑승한 메카만 (빈 보급 기체는 무시)
			local r, h = o:FindFirstChild("HumanoidRootPart"), o:FindFirstChildOfClass("Humanoid")
			if r and h and h.Health > 0 then
				local d = (r.Position - root.Position).Magnitude
				if d < bestD then best, bestD = o, d end
			end
		end
	end
	return best, bestD
end

local function push(root, name, dir, speed, time)
	-- 수평 속도만 잡는다(높이는 휴머노이드에 맡김). 부스트·내딛기 공용
	for _, c in ipairs(root:GetChildren()) do if c:IsA("LinearVelocity") then c:Destroy() end end
	local att = root:FindFirstChild("BoostAtt")
	if not att then att = Instance.new("Attachment"); att.Name = "BoostAtt"; att.Parent = root end
	local v = Instance.new("LinearVelocity")
	v.Name = name; v.Attachment0 = att; v.MaxForce = math.huge
	v.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	v.PrimaryTangentAxis = Vector3.xAxis; v.SecondaryTangentAxis = Vector3.zAxis
	v.RelativeTo = Enum.ActuatorRelativeTo.World
	v.PlaneVelocity = Vector2.new(dir.X, dir.Z) * speed
	v.Parent = root
	Debris:AddItem(v, time)
end

local function fireAt(m, root, target)
	local tr = target:FindFirstChild("HumanoidRootPart"); if not tr then return end
	-- 서버의 총구 부착점은 휴식 자세(팔을 내린 자세)라 바닥 속에 있다 → 조준 자세의 어깨 앞 지점에서 쏜다
	local origin = (root.CFrame * CFrame.new(3.4, 4.8, -8)).Position
	local s = CFG.EnemySpread
	local aim = tr.Position + Vector3.new(0, 3.8, 0) + Vector3.new((math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s, (math.random() - 0.5) * 2 * s)
	local d = (aim - origin).Unit
	m:SetAttribute("AimPitch", math.clamp(math.deg(math.asin(math.clamp(d.Y, -1, 1))), -55, 65))
	local p = RaycastParams.new(); p.FilterType = Enum.RaycastFilterType.Exclude; p.FilterDescendantsInstances = { m }
	local hit = workspace:Raycast(origin, d * CFG.Range, p)
	local hitPos = hit and hit.Position or (origin + d * CFG.Range)
	local hitHum = false   -- 기체를 맞혔나 → 클라가 적중음을 낸다
	if hit then
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		while model do
			local h = model:FindFirstChildOfClass("Humanoid")
			if h then
				if Dmg.canDamage(m, model) then
					Dmg.hurt(m, model, h, CFG.Damage)   -- 10-30 맞은 플레이어 기체의 궁극기 게이지(받은 피해)도 여기서 셈
					hitHum = true
				end
				break
			end
			model = model:FindFirstAncestorOfClass("Model")
		end
	end
	Remotes.MechFX:FireAllClients("fire", m, origin, hitPos, 0, hit and hit.Normal or Vector3.yAxis, hitHum)
end

local function aiMelee(m, root, target, dist, face)
	local start = _G.MechStartMelee   -- MechServer 가 등록. 아직 없으면 이번엔 건너뜀
	if not start then return false end
	local tr = target:FindFirstChild("HumanoidRootPart"); if not tr then return false end
	local d = tr.Position - root.Position
	local dir = Vector3.new(d.X, 0, d.Z)
	if dir.Magnitude < 0.1 then return false end
	dir = dir.Unit
	local punch = dist < 16
	-- 2026-10-25: 플레이어와 같은 고정 내딛기(적 쪽으로 끌려가는 보정 없음). 몸이 겹치기 전에만 멈춘다
	local ltime = punch and CFG.PunchLungeTime or CFG.LungeTime * (CFG.SaberSlow or 1)   -- 빔사벨은 휘두름이 느려진 만큼 내딛기도
	local travel = math.min(punch and CFG.PunchLunge or CFG.SaberLunge, math.max(0, dist - CFG.LungeBodyGap))
	face.CFrame = CFrame.lookAt(Vector3.zero, dir)
	if travel > 0.5 then push(root, "MeleeLunge", dir, travel / ltime, ltime) end
	start(m, punch and "punch" or "saber", dir)
	return true
end

local function runAI(m, root, hum, face)
	local strafe, nextFlip = (math.random() < 0.5) and 1 or -1, 0
	local shotsLeft, nextShot, nextBurst = 0, 0, os.clock() + 1
	local nextBoost = os.clock() + CFG.EnemyBoostEvery + (math.random() - 0.5) * 3
	local nextMelee, busyUntil = 0, 0
	while m.Parent and hum.Health > 0 do
		local dt = task.wait(0.05)
		local e = m:GetAttribute("Energy") or 0
		if e < CFG.MaxEnergy then m:SetAttribute("Energy", math.min(CFG.MaxEnergy, e + CFG.EnergyRegen * dt)) end
		if CFG.stunned(m) then hum:Move(Vector3.zero); continue end   -- 10-27 작살 그랩에 끌려오는 중·경직 중(끌어오기는 MechServer GRAB.pull)
		local now = os.clock()
		local target, dist = nil, 0
		if CFG.EnemyAI and Range:GetAttribute("EnemyActive") then target, dist = findTarget(m, root) end   -- 대기 중이면 서 있는 표적
		if not target then
			hum:Move(Vector3.zero)
			m:SetAttribute("AimPitch", 0)
		elseif now >= busyUntil then
			local tr = target.HumanoidRootPart
			local to = tr.Position - root.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			local fdir = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
			face.CFrame = CFrame.lookAt(Vector3.zero, fdir)
			if dist < CFG.EnemyMeleeRange and now >= nextMelee and aiMelee(m, root, target, dist, face) then
				hum:Move(Vector3.zero)
				nextMelee = now + CFG.EnemyMeleeCooldown
				busyUntil = now + ((dist < 16) and CFG.PunchTime or CFG.SaberTime * (CFG.SaberSlow or 1))
				shotsLeft = 0
			else
				-- 거리 유지 + 옆걸음
				if now >= nextFlip then strafe = -strafe; nextFlip = now + 1.5 + math.random() * 2 end
				local side = Vector3.new(-fdir.Z, 0, fdir.X) * strafe
				local fw = (dist > CFG.EnemyKeepFar) and 1 or ((dist < CFG.EnemyKeepNear) and -0.8 or 0)
				local mv = side * 0.7 + fdir * fw
				if mv.Magnitude > 1 then mv = mv.Unit end
				hum:Move(mv / CFG.slowMul(m))   -- 10-30 FALCO 마비 덫: 이동 ÷1.5
				-- 옆 부스트 회피
				if now >= nextBoost and e >= CFG.BoostCost then
					m:SetAttribute("Energy", e - CFG.BoostCost)
					m:SetAttribute("BoostUntil", workspace:GetServerTimeNow() + CFG.BoostTime)
					push(root, "Boost", side, CFG.BoostSpeed, CFG.BoostTime)
					nextBoost = now + CFG.EnemyBoostEvery + (math.random() - 0.5) * 3
				end
				-- 연사: 몸이 상대 쪽을 볼 때만
				local lv = root.CFrame.LookVector
				local facing = Vector3.new(lv.X, 0, lv.Z).Unit:Dot(fdir) > math.cos(math.rad(60))
				if shotsLeft <= 0 and now >= nextBurst then shotsLeft = CFG.EnemyBurst end
				if shotsLeft > 0 and now >= nextShot and facing and dist <= CFG.Range then
					fireAt(m, root, target)
					shotsLeft -= 1
					nextShot = now + CFG.FireInterval * 1.5 * CFG.slowMul(m)   -- 10-30 마비 덫: 사격 간격 ×1.5
					if shotsLeft <= 0 then nextBurst = now + CFG.EnemyBurstGap end
				end
			end
		end
	end
	hum:Move(Vector3.zero)
end

-- ================= 생성 =================
local spawnEnemy
function spawnEnemy()
	local m = Template:Clone()
	m.Name = "EnemyMech"
	local root = m.HumanoidRootPart
	local prompt = root:FindFirstChild("BoardPrompt"); if prompt then prompt:Destroy() end
	m:SetAttribute("EnemyMech", true)
	m:SetAttribute("Energy", CFG.MaxEnergy)
	m:SetAttribute("AimYaw", 0); m:SetAttribute("AimPitch", 0)

	local pos = Marker.Position
	local y = groundY(pos, { Marker })
	local look = Marker.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	local at = Vector3.new(pos.X, y + (m:GetAttribute("RootHeight") or 11.6), pos.Z)
	m:PivotTo(CFrame.lookAt(at, at + flat.Unit))

	local hum = m:FindFirstChildOfClass("Humanoid")
	hum.MaxHealth = CFG.MaxHealth; hum.Health = CFG.MaxHealth
	hum.WalkSpeed = CFG.WalkSpeed; hum.UseJumpPower = true; hum.JumpPower = CFG.JumpPower
	hum.AutoRotate = false
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	local tint = CFG.EnemyTint or Color3.new(1, 1, 1)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("SurfaceAppearance") then d.Color = tint end
	end

	-- 몸 방향은 물리 제약으로(플레이어 메카와 같은 방식)
	local fatt = Instance.new("Attachment"); fatt.Name = "FaceAtt"; fatt.Parent = root
	local face = Instance.new("AlignOrientation")
	face.Name = "FaceAlign"; face.Mode = Enum.OrientationAlignmentMode.OneAttachment
	face.Attachment0 = fatt; face.RigidityEnabled = false
	face.MaxTorque = math.huge; face.Responsiveness = CFG.TurnResponsiveness; face.MaxAngularVelocity = CFG.AimTurnRate
	face.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
	face.Parent = root

	root.Anchored = false
	m.Parent = workspace
	root:SetNetworkOwner(nil)          -- 서버가 움직인다
	CollectionService:AddTag(m, "Mech")
	hum:ChangeState(Enum.HumanoidStateType.Running)
	addHpBar(m, hum)

	hum.Died:Connect(function()
		local ex = Instance.new("Explosion"); ex.BlastPressure = 0; ex.BlastRadius = 0; ex.DestroyJointRadiusPercent = 0
		ex.Position = root.Position; ex.Parent = workspace
		SM.play("MechDestroy", root.Position)   -- 기체 파괴음(SoundManager)
		task.delay(2.5, function() if m.Parent then m:Destroy() end end)
		task.delay(CFG.EnemyRespawn or 5, spawnEnemy)
	end)
	task.spawn(runAI, m, root, hum, face)
	return m
end

-- ================= 적기 대기/전투 버튼 (workspace.MechTestRange.EnemyButton) =================
-- 상태 = 시험장 속성 EnemyActive. 대기면 AI 가 상대를 찾지 않아 서 있는 표적이 된다(runAI)
-- 올라서는 순간(비어 있다가 누가 올라옴) 한 번만 전환. 맨몸 플레이어나 탑승한 메카만 누른다(적기·빈 보급 기체는 무시)
local Players = game:GetService("Players")
local OFF_COLOR, ON_COLOR = Color3.fromRGB(80, 85, 95), Color3.fromRGB(255, 120, 24)
Range:SetAttribute("EnemyActive", CFG.EnemyStartActive == true)
local button = Range:FindFirstChild("EnemyButton")
local function showButton()
	if not button then return end
	local on = Range:GetAttribute("EnemyActive") == true
	button.Color = on and ON_COLOR or OFF_COLOR
	button.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
	local label = button:FindFirstChild("Label")
	local state = label and label:FindFirstChild("State")
	if state then state.Text = on and "적기 전투" or "적기 대기" end
end
showButton()
Range:GetAttributeChangedSignal("EnemyActive"):Connect(showButton)
if button then
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { button }
	local wasPressed = false
	task.spawn(function()
		while button.Parent do
			task.wait(0.15)
			local pressed = false
			local box = button.CFrame + Vector3.new(0, button.Size.Y / 2 + 3, 0)
			for _, part in ipairs(workspace:GetPartBoundsInBox(box, Vector3.new(button.Size.X, 6, button.Size.Z), op)) do
				local model = part:FindFirstAncestorOfClass("Model")
				if model and not model:GetAttribute("EnemyMech") then
					if Players:GetPlayerFromCharacter(model) or model:GetAttribute("Pilot") then pressed = true; break end
				end
			end
			if pressed and not wasPressed then
				Range:SetAttribute("EnemyActive", not Range:GetAttribute("EnemyActive"))
			end
			wasPressed = pressed
		end
	end)
end
spawnEnemy()

-- 기체 물리 안전장치(10-25 13:26, 유저 영상 "부스트→빔사벨로 적에 부딪히면 급상승"): 적 AI 의 push(무한 힘 수평 속도 제약)가
-- 플레이어 몸통을 밀지 않게(닿으면 그쪽 성분 0 + 힘 유한) + 위로 RiseCap 넘게 못 오름. 내 기체 쪽은 MechClient 카메라 단계가 같은 함수를 부른다.
-- Stepped = 물리 전에(이번 프레임 물리부터 적용)
local MP = require(Proto:WaitForChild("MechPhysics"))
game:GetService("RunService").Stepped:Connect(function()
	for _, m in ipairs(CollectionService:GetTagged("Mech")) do
		if m:GetAttribute("EnemyMech") and m.Parent then
			local r = m:FindFirstChild("HumanoidRootPart")
			if r and not r.Anchored then
				MP.clipPush(m, r)
				MP.capRise(r, CFG.RiseCap)
			end
		end
	end
end)
