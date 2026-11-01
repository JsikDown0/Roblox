-- MechStressServer (Script → ServerScriptService)
-- 4v4 이상 성능 측정용 부하 기체. 시험이 끝나면 지운다.
-- 방식: 템플릿 복제 → 태그 "MechDisplay"(MechClient 가 실제 애니 경로로 그림 · 서버 로직은 "Mech" 태그만 보므로 MaxMechs·미사일·적 AI 에 안 잡힘)
--       → 서버가 Humanoid:Move 로 원을 따라 걷게 함(MechEnemy 와 같은 방식, 속도가 있어 걷기 자세 경로를 탐)
--       → 사격은 실제 MechFX "fire" 를 모든 클라에 보냄(탄도선·총구 불꽃·불꽃 튐·소리·반동 = 실제 남의 기체 사격과 같은 비용)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local CONFIG = {
	Templates = { "HeavyTemplate" },   -- 섞으려면 { "HeavyTemplate", "AeroTemplate", "SkadiTemplate", "HorkosTemplate" } — 기체 i 는 순서대로 돌아가며
	MaxCount = 16,
	RingRadius = 110,                  -- 기체들이 걷는 원 반지름(스터드)
	DistanceFromPlayer = 170,          -- 원 중심 = 처음 누른 플레이어 앞 이 거리
	FireRateScale = 1,                 -- 1 = 그 기체 총의 실제 연사 간격(개틀링 1/18초). 0.5 = 절반 빠르기
	FireOnSeconds = 2, FireOffSeconds = 1,   -- 사격 켬일 때: 2초 쏘고 1초 쉼(계속 쏘게 하려면 Off 0)
	AimHz = 10,                        -- 조준 속성 갱신(실제 MechAim 최대 10/s 와 같음)
}

local Proto = ReplicatedStorage:WaitForChild("MechProto")
local Remotes = Proto:WaitForChild("Remotes")
local MechFX = Remotes:WaitForChild("MechFX")
local okCFG, CFG = pcall(require, Proto:WaitForChild("MechConfig"))
if not okCFG then CFG = nil; warn("[MechStress] MechConfig require 실패 — 기본값 사용") end

local folder = workspace:FindFirstChild("StressMechs") or Instance.new("Folder")
folder.Name = "StressMechs"
folder.Parent = workspace
folder:SetAttribute("Walk", true)
folder:SetAttribute("Fire", false)
folder:SetAttribute("Aim", true)
folder:SetAttribute("Shadow", 0)   -- 0 = 템플릿 그대로 · 1 = 큰 파트만 그림자 · 2 = 그림자 전부 끔

-- 그림자 모드(GPU 측정용): 큰 몸통·다리 파트만 남기면 땅 그림자는 유지된다
local BIG_SHADOW = { Pelvis = true, Torso = true, Backpack = true, UpperLegL = true, UpperLegR = true, LowerLegL = true, LowerLegR = true }
local function applyShadow(m)
	local mode = folder:GetAttribute("Shadow") or 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("StressOrigShadow") == nil then d:SetAttribute("StressOrigShadow", d.CastShadow) end
			local orig = d:GetAttribute("StressOrigShadow")
			if mode == 0 then d.CastShadow = orig
			elseif mode == 1 then d.CastShadow = orig and BIG_SHADOW[d.Name] == true
			else d.CastShadow = false end
		end
	end
end

local cmd = ReplicatedStorage:FindFirstChild("MechStressCmd") or Instance.new("RemoteEvent")
cmd.Name = "MechStressCmd"
cmd.Parent = ReplicatedStorage

local bots = {}        -- { model, root, hum, face, nextFire, phase }
local center = nil     -- Vector3 (땅 높이)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshFilter()
	local list = { folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(list, p.Character) end
	end
	rayParams.FilterDescendantsInstances = list
end

local function groundY(pos)
	refreshFilter()
	local hit = workspace:Raycast(pos + Vector3.new(0, 300, 0), Vector3.new(0, -800, 0), rayParams)
	return hit and hit.Position.Y or pos.Y
end

local function pickCenter(player)
	local char = player and player.Character
	local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
	if not root then return Vector3.new(0, 0, 0) end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	local p = root.Position + flat.Unit * CONFIG.DistanceFromPlayer
	return Vector3.new(p.X, groundY(p), p.Z)
end

local function gunOf(m)
	if CFG and CFG.gun then
		local ok, g = pcall(CFG.gun, m)
		if ok and g then return g end
	end
	return { FireInterval = 0.12, Range = 400 }
end

local function spawnBot(index)
	local name = CONFIG.Templates[((index - 1) % #CONFIG.Templates) + 1]
	local template = Proto:FindFirstChild(name)
	if not template then warn("[MechStress] 템플릿 없음: " .. name); return end
	local m = template:Clone()
	m.Name = "StressMech" .. index
	local root = m:FindFirstChild("HumanoidRootPart")
	local hum = m:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then warn("[MechStress] HumanoidRootPart/Humanoid 없음: " .. name); m:Destroy(); return end
	local prompt = root:FindFirstChild("BoardPrompt"); if prompt then prompt:Destroy() end
	for _, tag in ipairs(CollectionService:GetTags(m)) do CollectionService:RemoveTag(m, tag) end
	m:SetAttribute("StressBot", true)
	m:SetAttribute("AimYaw", 0); m:SetAttribute("AimPitch", 0)
	if CFG and CFG.stat then
		local ok, e = pcall(CFG.stat, m, "MaxEnergy"); m:SetAttribute("Energy", ok and e or 100)
	end
	local g = gunOf(m)
	m:SetAttribute("Ammo", g.MagSize or 30)

	local a =(index - 1) / math.max(CONFIG.MaxCount, 1) * math.pi * 2
	local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * CONFIG.RingRadius
	local at = Vector3.new(p.X, groundY(p) + (m:GetAttribute("RootHeight") or 11.6), p.Z)
	local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
	m:PivotTo(CFrame.lookAt(at, at + tangent))

	hum.MaxHealth = 1000; hum.Health = 1000
	local ws = 18
	if CFG and CFG.stat then
		local ok, v = pcall(CFG.stat, m, "WalkSpeed")
		if ok and type(v) == "number" then ws = v end
	end
	hum.WalkSpeed = ws
	hum.AutoRotate = false
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	-- 몸 방향 = 물리 제약(MechEnemy 와 같은 방식)
	local fatt = Instance.new("Attachment"); fatt.Name = "FaceAtt"; fatt.Parent = root
	local face = Instance.new("AlignOrientation")
	face.Name = "FaceAlign"; face.Mode = Enum.OrientationAlignmentMode.OneAttachment
	face.Attachment0 = fatt; face.RigidityEnabled = false
	face.MaxTorque = math.huge
	face.Responsiveness = (CFG and CFG.TurnResponsiveness) or 25
	face.MaxAngularVelocity = (CFG and CFG.AimTurnRate) or 10
	face.CFrame = CFrame.lookAt(Vector3.zero, tangent)
	face.Parent = root

	root.Anchored = false
	applyShadow(m)
	m.Parent = folder
	root:SetNetworkOwner(nil)
	CollectionService:AddTag(m, "MechDisplay")
	hum:ChangeState(Enum.HumanoidStateType.Running)
	table.insert(bots, { model = m, root = root, hum = hum, face = face, nextFire = 0, phase = math.random() * 10, gun = g })
	return true
end

local function setCount(n, player)
	n = math.clamp(math.floor(tonumber(n) or 0), 0, CONFIG.MaxCount)
	if n > 0 and (not center or #bots == 0) then center = pickCenter(player) end
	while #bots > n do
		local b = table.remove(bots)
		if b.model then b.model:Destroy() end
	end
	while #bots < n do
		if not spawnBot(#bots + 1) then break end
	end
	folder:SetAttribute("Count", #bots)
	print(("[MechStress] 기체 %d대"):format(#bots))
end

cmd.OnServerEvent:Connect(function(player, action, value)
	if action == "setCount" then
		setCount(value, player)
	elseif action == "shadow" then
		folder:SetAttribute("Shadow", ((folder:GetAttribute("Shadow") or 0) + 1) % 3)
		for _, b in ipairs(bots) do applyShadow(b.model) end
	elseif action == "flag" and (value == "Walk" or value == "Fire" or value == "Aim") then
		folder:SetAttribute(value, not folder:GetAttribute(value))
	elseif action == "recenter" then
		center = pickCenter(player)
		local n = #bots; setCount(0, player); setCount(n, player)
	end
end)

-- 서버 프레임 측정(클라 화면에 표시)
local acc, frames = 0, 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt; frames += 1
	if acc >= 1 then
		folder:SetAttribute("ServerFPS", math.floor(frames / acc * 10 + 0.5) / 10)
		acc, frames = 0, 0
	end
end)

-- 이동·조준(20Hz) + 사격(Heartbeat)
local moveAcc, aimAcc = 0, 0
RunService.Heartbeat:Connect(function(dt)
	if #bots == 0 or not center then return end
	local t = os.clock()
	moveAcc += dt; aimAcc += dt
	local walk = folder:GetAttribute("Walk")
	local fire = folder:GetAttribute("Fire")
	local aim = folder:GetAttribute("Aim")

	if moveAcc >= 0.05 then
		moveAcc = 0
		for _, b in ipairs(bots) do
			if b.root.Parent then
				local rel = b.root.Position - center
				local ang = math.atan2(rel.Z, rel.X)
				if walk then
					local goal = center + Vector3.new(math.cos(ang + 0.35), 0, math.sin(ang + 0.35)) * CONFIG.RingRadius
					local d = Vector3.new(goal.X - b.root.Position.X, 0, goal.Z - b.root.Position.Z)
					if d.Magnitude > 0.1 then
						b.hum:Move(d.Unit)
						b.face.CFrame = CFrame.lookAt(Vector3.zero, d.Unit)
					end
				else
					b.hum:Move(Vector3.zero)
				end
			end
		end
	end

	if aim and aimAcc >= 1 / CONFIG.AimHz then
		aimAcc = 0
		for _, b in ipairs(bots) do
			local m = b.model
			m:SetAttribute("AimPitch", math.floor(math.sin(t * 0.7 + b.phase) * 20))
			m:SetAttribute("AimYaw", math.floor(math.sin(t * 0.5 + b.phase) * 25))
			m:SetAttribute("AimZoom", (math.floor((t + b.phase) / 3) % 2 == 0) or nil)   -- 3초마다 두 손 조준(IK 경로) 켬/끔
		end
	end

	if fire then
		local cycle = CONFIG.FireOnSeconds + CONFIG.FireOffSeconds
		for _, b in ipairs(bots) do
			local inBurst = CONFIG.FireOffSeconds <= 0 or ((t + b.phase) % cycle) < CONFIG.FireOnSeconds
			if inBurst and t >= b.nextFire and b.root.Parent then
				b.nextFire = t + (b.gun.FireInterval or 0.12) / math.max(CONFIG.FireRateScale, 0.05)
				local rifle = b.model:FindFirstChild("Rifle")
				local mz = rifle and rifle:FindFirstChild("Muzzle")
				local muzzle = (mz and mz:IsA("Attachment") and mz.WorldPosition) or b.root.Position + Vector3.new(0, 4, 0)
				local look = b.root.CFrame.LookVector
				local dir = (look + Vector3.new(0, math.sin(t + b.phase) * 0.05, 0)).Unit * (b.gun.Range or 400)
				local hit = workspace:Raycast(muzzle, dir, rayParams)   -- 실제 사격과 같은 서버 레이캐스트 1회
				local hitPos = hit and hit.Position or (muzzle + dir)
				MechFX:FireAllClients("fire", b.model, muzzle, hitPos, 0, hit and hit.Normal or Vector3.yAxis, nil)
			end
		end
	end
end)

-- 필터는 사람이 들고 날 때만 새로
Players.PlayerAdded:Connect(function(p) p.CharacterAdded:Connect(refreshFilter) end)
for _, p in ipairs(Players:GetPlayers()) do p.CharacterAdded:Connect(refreshFilter) end
refreshFilter()
print("[MechStress] 서버 준비 — 화면 왼쪽 위 버튼으로 조작")
