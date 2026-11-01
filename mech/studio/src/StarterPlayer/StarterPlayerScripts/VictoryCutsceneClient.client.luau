-- VictoryCutsceneClient (LocalScript, StarterPlayerScripts) — AELLO 승리포즈 컷씬 재생기 (2026-10-29)
-- 데이터: ReplicatedStorage.VictoryPoseData(자동 생성 — 손으로 고치지 말 것) + VictoryPoseFix(그 위에 얹는 보정, 재생 직전 사본에 적용).
-- 서버(VictoryPadsServer)가 발판을 밟은 플레이어에게 VictoryCutscene:FireClient(clipName) → 이 화면에서만 재생.
-- 무대: 화면 전용 복제 기체(ReplicatedStorage.VictoryRig)를 workspace.VictoryStage 자리에 놓고
--       Motor6D.Transform 을 프레임별 데이터로 덮어씀 + 카메라 Scriptable 경로 + 사격·눈 번쩍·불꽃 효과 + 승리 UI.
-- 10-29 Studio 반영 때 확인한 것 [실측]:
--   · Flame = ParticleEmitter, 부모 Attachment 이름 BoostNozzleL/R = 다리, 나머지(Backpack.Nozzle* · Wing*.WingNozzle*) = 등
--   · 손 칼(Saber.InHand)·허리 라이플(RifleStowed)은 템플릿 기본이 이미 숨김(아래 숨김은 안전장치)
--   · MechClient 는 자기 캐릭터(IsMech)만 잡음 → 이 복제본과 무관
--   · ⚠️ 탑승 중엔 MechClient 의 "MechCamera"(BindToRenderStep, Camera+1)가 매 프레임 카메라를 씀 →
--     이 컷씬은 Camera+10 으로 묶어 그 뒤에 씀(RenderStepped:Connect 와의 순서는 확실치 않음 [추측])
-- 10-29 18:10 유저 "실제 승리화면이라고 생각하고 ui도 꾸며줘. 왼쪽 하단에 플레이어 이름 넣고 MVP로 표시":
--   · 승리 UI = 왼쪽 아래 카드(VICTORY · MVP 배지 · 이름 · @아이디 · 기체명), 자세가 멈추는 눈 번쩍 순간에 들어옴
--   · 컷씬 동안 다른 ScreenGui · 기본 UI(CoreGui) · 마우스 커서 숨김 → 끝나면 숨겼던 것만 되돌림
--   · HUD 문법은 MechHUD 와 같게: 흰색 (235,240,245) · 선 2px · Gotham Black/Bold/Medium · 크기 = 화면 높이 기준(1080 = 1배)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local DATA = require(RS:WaitForChild("VictoryPoseData"))
local Fix = require(RS:WaitForChild("VictoryPoseFix"))
local EV = RS:WaitForChild("VictoryCutscene")

local BIND = "VictoryCutscene"
local BIND_PRIORITY = Enum.RenderPriority.Camera.Value + 10
local PELVIS_PIVOT = Vector3.new(0, 17.2, 0)        -- 템플릿 좌표: 골반 관절점(무대 원점 = 발밑 가운데) [실측 HRP (0,17.2,0) · Root.C0 = 단위]
local EYE_REST = Vector3.new(0, 25.1, -1.8)         -- 템플릿 좌표: 눈 줄 가운데 바로 앞(쉬는 자세)
local HOLD_AFTER = 1.5                               -- 끝난 뒤 마지막 화면 유지(10-29: 0.8 → 1.5, 승리 UI 읽을 시간)
local UI_FADE = 0.3                                  -- 끝나기 전 UI 가 빠지는 시간
local JOINTS = { "Root", "Waist", "Neck", "ShoulderL", "ShoulderR", "ElbowL", "ElbowR", "PadL", "PadR", "HipL", "HipR",
	"KneeL", "KneeR", "AnkleL", "AnkleR", "SkirtJointFL", "SkirtJointFR", "SkirtJointSL", "SkirtJointSR", "WingJointL", "WingJointR", "Grip" }

local WHITE = Color3.fromRGB(235, 240, 245)
local GREY = Color3.fromRGB(150, 158, 170)
local ORANGE = Color3.fromRGB(255, 140, 40)          -- AELLO 주황(발판과 같은 색)

local playing = false

-- ---------------------------------------------------------------- 데이터
local clips = {}
local function getClip(name)
	if clips[name] then return clips[name] end
	local clip = DATA[name]
	if clip and name == "A" then   -- 무릎 쏴 높이 보정(VictoryPoseFix 설명)
		local ok, c = pcall(function() return (Fix.kneelA(clip, Fix.rig(RS:WaitForChild("VictoryRig")))) end)
		if ok and c then clip = c else warn("[Victory] A 무릎 보정 실패 — 원본으로 재생:", c) end
	end
	clips[name] = clip
	return clip
end

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

-- ---------------------------------------------------------------- 효과
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
		for _, d in ipairs(inHand:GetDescendants()) do
			if d:IsA("BasePart") then d.Transparency = 1 elseif d:IsA("Light") or d:IsA("Trail") then d.Enabled = false end
		end
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
	-- 불꽃: 이름 Flame, 부모 이름에 Boost 가 있으면 다리
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

-- ---------------------------------------------------------------- 승리 UI
-- 왼쪽 아래 카드(1080p 기준 픽셀 × u):  ┃ VICTORY
--                                         ┃ [MVP]
--                                         ┃ 플레이어 이름(크게)
--                                         ┃ ━━━━━━━━ (주황 → 투명)
--                                         ┃ @아이디  ·  FALCO  LF-01
local function makeVictoryUI(rig)
	local u = workspace.CurrentCamera.ViewportSize.Y / 1080
	local function px(x, y) return UDim2.fromOffset(x * u, y * u) end
	local g = Instance.new("ScreenGui")
	g.Name = "VictoryUI"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 20
	-- 왼쪽 아래 그늘(흰 기체 위 흰 글자가 읽히게)
	local shade = Instance.new("Frame")
	shade.AnchorPoint = Vector2.new(0, 1); shade.Position = UDim2.fromScale(0, 1); shade.Size = UDim2.fromScale(0.75, 0.55)
	shade.BackgroundColor3 = Color3.new(0, 0, 0); shade.BackgroundTransparency = 1; shade.BorderSizePixel = 0
	local sg = Instance.new("UIGradient"); sg.Rotation = -32
	sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.75), NumberSequenceKeypoint.new(1, 1) })
	sg.Parent = shade
	shade.Parent = g
	-- 카드(한 번에 페이드되게 CanvasGroup)
	local card = Instance.new("CanvasGroup")
	card.AnchorPoint = Vector2.new(0, 1); card.BackgroundTransparency = 1; card.BorderSizePixel = 0
	card.Size = px(760, 236); card.GroupTransparency = 1
	card.Position = UDim2.new(0, 24 * u, 1, -64 * u)          -- 왼쪽 40px 밖에서 시작 → 64px 자리로 미끄러짐
	card.Parent = g
	local function box(parent, pos, size, color, tr)
		local f = Instance.new("Frame")
		f.Position = pos; f.Size = size; f.BackgroundColor3 = color; f.BackgroundTransparency = tr or 0; f.BorderSizePixel = 0
		f.Parent = parent
		return f
	end
	local function text(parent, s, pos, size, color, font, maxSize, rich)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1; t.Position = pos; t.Size = size; t.Text = s; t.RichText = rich == true
		t.Font = font; t.TextColor3 = color; t.TextXAlignment = Enum.TextXAlignment.Left; t.TextYAlignment = Enum.TextYAlignment.Center
		t.TextScaled = true; t.TextTruncate = Enum.TextTruncate.AtEnd
		local c = Instance.new("UITextSizeConstraint"); c.MaxTextSize = math.max(8, math.floor(maxSize * u)); c.Parent = t
		t.Parent = parent
		return t
	end
	box(card, px(0, 6), UDim2.new(0, math.max(2, math.floor(2 * u)), 1, -12 * u), WHITE, 0.45)        -- 왼쪽 세로 테(HUD 모니터 테와 같은 2px)
	text(card, "VICTORY", px(26, 2), px(300, 28), ORANGE, Enum.Font.GothamBold, 24)
	-- MVP 배지(금색 그라데이션, 튀어나오듯 커졌다 줄어듦)
	local badge = box(card, UDim2.fromOffset(26 * u, 58 * u), px(118, 44), Color3.new(1, 1, 1))
	badge.AnchorPoint = Vector2.new(0, 0.5)
	local bgd = Instance.new("UIGradient"); bgd.Rotation = 90
	bgd.Color = ColorSequence.new(Color3.fromRGB(255, 226, 130), Color3.fromRGB(226, 150, 36)); bgd.Parent = badge
	local bst = Instance.new("UIStroke"); bst.Color = Color3.fromRGB(255, 240, 190); bst.Thickness = math.max(1, math.floor(1.5 * u)); bst.Transparency = 0.2
	bst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; bst.Parent = badge
	local bt = text(badge, "MVP", UDim2.fromScale(0, 0.06), UDim2.fromScale(1, 0.88), Color3.fromRGB(28, 20, 6), Enum.Font.GothamBlack, 34)
	bt.TextXAlignment = Enum.TextXAlignment.Center
	local bscale = Instance.new("UIScale"); bscale.Scale = 1; bscale.Parent = badge
	-- 이름 · 밑줄 · 아이디/기체
	text(card, player.DisplayName, px(24, 86), px(730, 80), WHITE, Enum.Font.GothamBlack, 72)
	local acc = box(card, px(26, 170), px(0, 3), ORANGE)
	local ag = Instance.new("UIGradient")
	ag.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.35), NumberSequenceKeypoint.new(1, 1) })
	ag.Parent = acc
	local mechName = rig and rig:GetAttribute("DisplayName") or "FALCO"
	local des = rig and rig:GetAttribute("Designation")
	local sub = string.format('@%s   ·   <font color="#FF8C28">%s</font>%s', player.Name, mechName, des and ("   " .. des) or "")
	text(card, sub, px(26, 184), px(730, 34), GREY, Enum.Font.GothamMedium, 26, true)
	g.Parent = player:WaitForChild("PlayerGui")
	return { gui = g, shade = shade, card = card, badge = bscale, acc = acc, u = u }
end

local function showVictoryUI(ui)
	local u = ui.u
	TweenService:Create(ui.shade, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(ui.card, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ GroupTransparency = 0, Position = UDim2.new(0, 64 * u, 1, -64 * u) }):Play()
	ui.badge.Scale = 1.4
	TweenService:Create(ui.badge, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(ui.acc, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.12), { Size = UDim2.fromOffset(470 * u, 3 * u) }):Play()
end

local function hideVictoryUI(ui)
	TweenService:Create(ui.shade, TweenInfo.new(UI_FADE), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(ui.card, TweenInfo.new(UI_FADE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 }):Play()
end

-- 컷씬 동안 다른 UI 숨김 → 숨겼던 것만 되돌림
local function hideHud(keep)
	local st = { gui = {}, core = {}, mouse = UIS.MouseIconEnabled }
	local pg = player:FindFirstChild("PlayerGui")
	if pg then
		for _, g in ipairs(pg:GetChildren()) do
			if g:IsA("ScreenGui") and g ~= keep and g.Enabled then g.Enabled = false; st.gui[#st.gui + 1] = g end
		end
	end
	for _, t in ipairs(Enum.CoreGuiType:GetEnumItems()) do
		if t ~= Enum.CoreGuiType.All then
			local ok, on = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, t)
			if ok and on then st.core[#st.core + 1] = t; pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, false) end
		end
	end
	UIS.MouseIconEnabled = false
	return st
end

local function restoreHud(st)
	for _, g in ipairs(st.gui) do if g.Parent then g.Enabled = true end end
	for _, t in ipairs(st.core) do pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, true) end
	UIS.MouseIconEnabled = st.mouse
end

-- ---------------------------------------------------------------- 재생
local function play(clipName)
	if playing then return end
	local clip = getClip(clipName)
	local stage = workspace:FindFirstChild("VictoryStage")
	if not clip or not stage then warn("[Victory] clip/stage 없음", clipName) return end
	playing = true
	local camera = workspace.CurrentCamera
	local stageCF = stage.CFrame
	local okPrep, rig, motors, head, eyeOff, flames = pcall(prepRig, stageCF)
	if not okPrep then warn("[Victory] 기체 준비 실패", rig); playing = false; return end
	local rifle = rig:FindFirstChild("Rifle", true)
	local muzzles = { rifle and rifle:FindFirstChild("Muzzle"), rifle and rifle:FindFirstChild("Muzzle2") }
	local okUI, ui = pcall(makeVictoryUI, rig)
	if not okUI then warn("[Victory] 승리 UI 실패 — UI 없이 재생:", ui); ui = nil end
	local hud = hideHud(ui and ui.gui)

	local oldType, oldCF, oldFov = camera.CameraType, camera.CFrame, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable

	local t0 = os.clock()
	local endT = clip.frames / clip.fps
	local shotDone, eyeDone, uiOut, done = {}, false, false, false
	-- 끝내기는 정상 종료·오류 어느 쪽이든 여기 한 곳으로(카메라가 Scriptable 에 묶여 남거나 HUD 가 꺼진 채 남지 않게)
	local function finish()
		if done then return end
		done = true
		RunService:UnbindFromRenderStep(BIND)
		rig:Destroy()
		if ui then ui.gui:Destroy() end
		restoreHud(hud)
		camera.CameraType = oldType; camera.FieldOfView = oldFov
		if oldType == Enum.CameraType.Scriptable then camera.CFrame = oldCF end
		playing = false
	end
	local function step()
		local t = os.clock() - t0
		local f = math.min(t, endT) * clip.fps
		for _, j in ipairs(JOINTS) do
			local m = motors[j]
			if m then m.Transform = sample(clip, j, f) end
		end
		local ccf, fov = camAt(clip, f)
		camera.CameraType = Enum.CameraType.Scriptable
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
		-- 눈 번쩍 + 승리 UI 들어옴(자세가 멈추는 순간)
		if not eyeDone and t >= clip.eye then
			eyeDone = true
			local at = head.CFrame * eyeOff
			flash(at, Color3.fromRGB(255, 220, 110), 1.2, 0.35, 14)
			local streak = Instance.new("Part")
			streak.Anchored = true; streak.CanCollide = false; streak.CanQuery = false; streak.CanTouch = false
			streak.Material = Enum.Material.Neon; streak.Color = Color3.fromRGB(255, 230, 150)
			streak.Size = Vector3.new(9, 0.12, 0.12); streak.CFrame = CFrame.lookAt(at.Position, camera.CFrame.Position)
			streak.Parent = workspace
			Debris:AddItem(streak, 0.3)
			if ui then showVictoryUI(ui) end
		end
		if ui and not uiOut and t > endT + HOLD_AFTER - UI_FADE then
			uiOut = true
			hideVictoryUI(ui)
		end
		if t > endT + HOLD_AFTER then finish() end
	end
	RunService:BindToRenderStep(BIND, BIND_PRIORITY, function()
		local ok, err = pcall(step)
		if not ok then warn("[Victory] 재생 중 오류 — 정리하고 멈춤:", err); finish() end
	end)
end

EV.OnClientEvent:Connect(play)
task.spawn(getClip, "A")   -- A 무릎 보정을 미리(편집 모드 실측 약 50ms — 발판 밟는 순간 끊김 방지)
