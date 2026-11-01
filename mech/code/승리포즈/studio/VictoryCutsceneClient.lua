-- VictoryCutsceneClient (LocalScript, StarterPlayerScripts) — AELLO 승리포즈 컷씬 재생기 (2026-10-29 초안)
-- 데이터: ReplicatedStorage.VictoryPoseData(자동 생성 — 손으로 고치지 말 것). 카메라 fov 는 프레임마다 데이터에 있음.
-- 서버(VictoryPadsServer)가 발판을 밟은 플레이어에게 VictoryCutscene:FireClient(clipName) → 이 화면에서만 재생.
-- 무대: 화면 전용 복제 기체(ReplicatedStorage.VictoryRig)를 workspace.VictoryStage 자리에 놓고
--       Motor6D.Transform 을 프레임별 데이터(VictoryPoseData)로 덮어씀 + 카메라 Scriptable 경로 + 사격·눈 번쩍·불꽃 효과.
-- ⚠️ 적용 전 확인할 것(Studio 연결 뒤): AeroTemplate 위치 · Flame 객체 종류 · 손 칼(InHand) 기본 보임 여부 ·
--    MechClient 가 이 복제본을 건드리지 않는지(태그 "Mech"/"MechDisplay" 없음) · 탑승 중 카메라 충돌(MechClient 가 매 프레임 카메라를 씀)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local DATA = require(RS:WaitForChild("VictoryPoseData"))
local EV = RS:WaitForChild("VictoryCutscene")

local PELVIS_PIVOT = Vector3.new(0, 17.2, 0)        -- 템플릿 좌표: 골반 관절점(무대 원점 = 발밑 가운데)
local EYE_REST = Vector3.new(0, 25.1, -1.8)         -- 템플릿 좌표: 눈 줄 가운데 바로 앞(쉬는 자세)
local HOLD_AFTER = 0.8                               -- 끝난 뒤 마지막 화면 유지
local JOINTS = { "Root", "Waist", "Neck", "ShoulderL", "ShoulderR", "ElbowL", "ElbowR", "PadL", "PadR", "HipL", "HipR",
	"KneeL", "KneeR", "AnkleL", "AnkleR", "SkirtJointFL", "SkirtJointFR", "SkirtJointSL", "SkirtJointSR", "WingJointL", "WingJointR", "Grip" }

local playing = false

local function qcf(t, i)                             -- i = 0-기반 프레임
	local b = i * 4
	return CFrame.new(0, 0, 0, t[b + 1], t[b + 2], t[b + 3], t[b + 4])
end

local function sample(clip, j, f)
	local t = clip.q[j]
	local n = clip.frames
	local i0 = math.clamp(math.floor(f), 0, n - 1)
	local i1 = math.min(i0 + 1, n - 1)
	local a = math.clamp(f - i0, 0, 1)
	local cf = qcf(t, i0):Lerp(qcf(t, i1), a)
	if j == "Root" then
		local p = clip.rootp
		local p0 = Vector3.new(p[i0 * 3 + 1], p[i0 * 3 + 2], p[i0 * 3 + 3])
		local p1 = Vector3.new(p[i1 * 3 + 1], p[i1 * 3 + 2], p[i1 * 3 + 3])
		cf = CFrame.new(p0:Lerp(p1, a)) * cf
	end
	return cf
end

local function camAt(clip, f)
	local c = clip.cam
	local n = clip.frames
	local i0 = math.clamp(math.floor(f), 0, n - 1)
	local i1 = math.min(i0 + 1, n - 1)
	local a = math.clamp(f - i0, 0, 1)
	local function v(i, k) return Vector3.new(c[i * 7 + k + 1], c[i * 7 + k + 2], c[i * 7 + k + 3]) end
	local pos = v(i0, 0):Lerp(v(i1, 0), a)
	local look = v(i0, 3):Lerp(v(i1, 3), a).Unit
	local fov = c[i0 * 7 + 7] + (c[i1 * 7 + 7] - c[i0 * 7 + 7]) * a
	return CFrame.lookAt(pos, pos + look), fov
end

local function flash(at, color, size, life, light)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon; p.Color = color; p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(size, size, size); p.CFrame = at
	p.Parent = workspace
	if light then
		local l = Instance.new("PointLight"); l.Color = color; l.Brightness = light; l.Range = size * 6; l.Parent = p
	end
	Debris:AddItem(p, life)
	return p
end

local function prepRig(stageCF)
	local rig = RS:WaitForChild("VictoryRig"):Clone()
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") then d:Destroy() end
	end
	-- 무장 상태: 라이플 손 · 허리 뒤 라이플 숨김 · 손 칼 숨김(칼집은 보임)
	local stowed = rig:FindFirstChild("RifleStowed", true)
	if stowed and stowed:IsA("BasePart") then stowed.Transparency = 1 end
	local saber = rig:FindFirstChild("Saber")
	local inHand = saber and saber:FindFirstChild("InHand")
	if inHand then
		for _, d in ipairs(inHand:GetDescendants()) do if d:IsA("BasePart") then d.Transparency = 1 end end
	end
	local hrp = rig:WaitForChild("HumanoidRootPart")
	local root = hrp:FindFirstChild("Root", true) or rig:FindFirstChild("Root", true)
	hrp.Anchored = true
	-- 무대 원점(발밑 가운데) = stageCF 가 되게 HRP 를 놓음: 원점 = HRP · Root.C0 · (−골반 관절점)
	hrp.CFrame = stageCF * CFrame.new(PELVIS_PIVOT) * root.C0:Inverse()
	rig.Parent = workspace
	local motors = {}
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("Motor6D") then motors[d.Name] = d end
	end
	-- 눈 자리(머리 기준) — 쉬는 자세에서 잼
	local head = rig:FindFirstChild("Head", true)
	local eyeOff = head.CFrame:ToObjectSpace(stageCF * CFrame.new(EYE_REST))
	-- 불꽃: 이름 Flame(부모 이름으로 등/다리 구분 — 확인 필요)
	local flames = { back = {}, leg = {} }
	for _, d in ipairs(rig:GetDescendants()) do
		if d.Name == "Flame" then
			local par = d.Parent and d.Parent.Name or ""
			table.insert(par:find("Boost") and flames.leg or flames.back, d)
		end
	end
	return rig, motors, head, eyeOff, flames
end

local function setFlames(list, on)
	for _, d in ipairs(list) do
		if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Fire") or d:IsA("Light") then
			d.Enabled = on
		elseif d:IsA("BasePart") then
			d.Transparency = on and 0 or 1
		end
	end
end

local function play(clipName)
	if playing then return end
	local clip = DATA[clipName]
	local stage = workspace:FindFirstChild("VictoryStage")
	if not clip or not stage then warn("[Victory] clip/stage 없음", clipName) return end
	playing = true
	local stageCF = stage.CFrame
	local rig, motors, head, eyeOff, flames = prepRig(stageCF)
	local rifle = rig:FindFirstChild("Rifle", true)
	local muzzles = { rifle and rifle:FindFirstChild("Muzzle"), rifle and rifle:FindFirstChild("Muzzle2") }

	local oldType, oldCF, oldFov = camera.CameraType, camera.CFrame, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable

	local t0 = os.clock()
	local shotDone, eyeDone = {}, false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local f = math.min(t, clip.frames / clip.fps) * clip.fps
		for _, j in ipairs(JOINTS) do
			local m = motors[j]
			if m then m.Transform = sample(clip, j, f) end
		end
		local ccf, fov = camAt(clip, f)
		camera.CFrame = stageCF * ccf
		camera.FieldOfView = fov
		-- 불꽃 세기(0.4 넘으면 켬)
		local fb, fl = 0, 0
		for _, k in ipairs(clip.flames) do
			if t >= k[1] then fb, fl = k[2], k[3] end
		end
		setFlames(flames.back, fb > 0.4); setFlames(flames.leg, fl > 0.4)
		-- 사격
		for i, s in ipairs(clip.shots) do
			if not shotDone[i] and t >= s[1] then
				shotDone[i] = true
				local a = muzzles[s[2] + 1] or muzzles[1]
				if a then flash(a.WorldCFrame, Color3.fromRGB(255, 225, 140), 1.6, 0.06, 10) end
			end
		end
		-- 눈 번쩍
		if not eyeDone and t >= clip.eye then
			eyeDone = true
			local at = head.CFrame * eyeOff
			local g = flash(at, Color3.fromRGB(255, 220, 110), 1.2, 0.35, 14)
			local streak = Instance.new("Part")
			streak.Anchored = true; streak.CanCollide = false; streak.CanQuery = false; streak.CanTouch = false
			streak.Material = Enum.Material.Neon; streak.Color = Color3.fromRGB(255, 230, 150)
			streak.Size = Vector3.new(9, 0.12, 0.12); streak.CFrame = CFrame.lookAt(at.Position, camera.CFrame.Position)
			streak.Parent = workspace
			Debris:AddItem(streak, 0.3)
		end
		if t > clip.frames / clip.fps + HOLD_AFTER then
			conn:Disconnect()
			rig:Destroy()
			camera.CameraType = oldType; camera.FieldOfView = oldFov
			if oldType == Enum.CameraType.Scriptable then camera.CFrame = oldCF end
			playing = false
		end
	end)
end

EV.OnClientEvent:Connect(play)
