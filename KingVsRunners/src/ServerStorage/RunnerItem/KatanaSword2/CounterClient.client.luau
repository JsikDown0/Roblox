-- Katana Counter Client — 카운터 자세 버튼/입력.
-- 별도 버튼(모바일) + F키(PC). 한 번 누르면 자세 발동(강제 지속, 취소 불가).
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local Tool = script.Parent
local CounterRemote = Tool:WaitForChild("CounterRemote")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EMP_EMIT_LINES = 6     -- ForceField1(도는 선): 겹수 = 선 개수
local EMP_EMIT_SHELL = 1     -- ForceField3(구체 껍질): 1이 적정, 올리면 불투명해짐
local EMP_EMIT_COUNT = 1     -- Legendary 카운터 EMP 방출량
local EMP_Y_OFFSET   = 0     -- 방출 높이(HRP 기준). 0=캐릭터 중심, 음수=발밑
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ── 카운터 버튼 UI (장착 시 생성, 해제 시 숨김) ──────────────
local gui = Instance.new("ScreenGui")
gui.Name = "KatanaCounterGui"
gui.ResetOnSpawn = true  -- 사망 리스폰 시 자동 정리 (UI 잔재 방지)
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = playerGui

local btn = Instance.new("TextButton")
btn.Name = "CounterButton"
btn.AnchorPoint = Vector2.new(1, 1)
-- 우하단 Q 스킬 슬롯(SkillBar) 바로 위 — 디바이스별 위치는 아래 syncSkillBtnPos가 처리
btn.BackgroundColor3 = Color3.fromRGB(40, 90, 130)
btn.BackgroundTransparency = 0.15
btn.Text = "카운터"
btn.TextColor3 = Color3.fromRGB(255, 255, 255)
btn.TextScaled = true
btn.Font = Enum.Font.GothamBold
btn.AutoButtonColor = false
btn.BackgroundTransparency = 1   -- 아이콘이 배경 대체
btn.Parent = gui

-- 키 힌트 "F" (SkillBarGui DiveSlot.KeyHint와 동일 스타일 · 모바일에서도 표시)
do
	local hint = Instance.new("TextLabel")
	hint.Name = "KeyHint"
	hint.Text = "F"
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Position = UDim2.new(0.96, 0, 0.04, 0)
	hint.Size = UDim2.new(0.32, 0, 0.32, 0)
	hint.BackgroundColor3 = Color3.fromRGB(15, 20, 31)
	hint.BackgroundTransparency = 0.2
	hint.BorderSizePixel = 0
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.Font = Enum.Font.GothamBlack
	hint.TextScaled = true
	hint.ZIndex = 4
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = hint
	local s = Instance.new("UIStroke")
	s.Thickness = 1.5; s.Color = Color3.fromRGB(255, 190, 60); s.Parent = hint
	hint.Parent = btn
	-- 키보드 입력 가능할 때만 표시 (DiveSlotClient와 동일 규칙)
	local _uis = game:GetService("UserInputService")
	local function updateHintVisibility()
		hint.Visible = not (_uis.TouchEnabled and not _uis.KeyboardEnabled)
	end
	updateHintVisibility()
	_uis:GetPropertyChangedSignal("KeyboardEnabled"):Connect(updateHintVisibility)
	_uis:GetPropertyChangedSignal("TouchEnabled"):Connect(updateHintVisibility)
end

-- 디바이스별 스킬 버튼 위치 (Q 슬롯 SKILLBAR_POS 바로 위 · 핫스왑 대응)
local _Scaler = require(game:GetService("ReplicatedStorage"):WaitForChild("ResponsiveScaler"))
-- Q 슬롯(DiveSlotClient)과 동일한 UIScale. 이걸 안 걸면 스킬 버튼만 원본 픽셀로 떠서
-- 크기·위치가 Q 슬롯과 다른 좌표계가 됨(= 부채꼴이 어긋남).
_Scaler.applyEdge(gui, nil, {
	baseW = 1280, baseH = 720,
	Mobile = { minScale = 0.55 },
	PC     = { minScale = 0.55 },
})
local SKILLBTN_POS = {
	-- MOBA식 부채꼴 슬롯2. offset × UIScale(0.55) = 실제px
	--   슬롯1 Q(-36,-218) / 슬롯2 무기스킬(여기) / 슬롯3은 skill2 추가 시 재산출
	Mobile = UDim2.new(1, -187, 1, -128),  -- 실제 right-134 / bottom-60
	PC     = UDim2.new(1, -365, 1, -170),  -- -20 → -100 (2026-08-21): 하단에 너무 붙어 있어 올림
}
local SKILLBTN_SIZE = { Mobile = 120, PC = 150 }   -- PC는 마우스 클릭용으로 크게
local function syncSkillBtnPos()
	local dev = _Scaler.device()
	local sz  = SKILLBTN_SIZE[dev] or SKILLBTN_SIZE.PC
	btn.Size = UDim2.fromOffset(sz, sz)
	btn.Position = SKILLBTN_POS[dev] or SKILLBTN_POS.PC
end
syncSkillBtnPos()
local _UIS = game:GetService("UserInputService")
_UIS:GetPropertyChangedSignal("KeyboardEnabled"):Connect(syncSkillBtnPos)
_UIS:GetPropertyChangedSignal("TouchEnabled"):Connect(syncSkillBtnPos)
btn.TextTransparency = 1         -- "카운터" 텍스트 숨김

local icon = Instance.new("ImageLabel")
icon.Name = "SkillIcon"
icon.BackgroundTransparency = 1
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.fromScale(1, 1)
icon.Image = "rbxassetid://93187716940180"
icon.ZIndex = 2
icon.Parent = btn

local iconCorner = Instance.new("UICorner")
iconCorner.CornerRadius = UDim.new(0.5, 0)
iconCorner.Parent = icon

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = btn

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(120, 200, 255)
stroke.Thickness = 2
stroke.Parent = icon

local cdLabel = Instance.new("TextLabel")
cdLabel.Name = "CooldownLabel"
cdLabel.BackgroundTransparency = 1
cdLabel.Size = UDim2.fromScale(1, 1)
cdLabel.Font = Enum.Font.GothamBold
cdLabel.TextScaled = true
cdLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
cdLabel.TextStrokeTransparency = 0.3
cdLabel.ZIndex = 5
cdLabel.Text = ""
cdLabel.Parent = btn

-- ── 입력 처리 ────────────────────────────────────────────────
-- 강제 지속형: 한 번 누르면 발동(취소 불가). 떼는 동작 없음.
-- 연타 방지를 위해 클라에서도 잠깐 버튼을 잠금(서버 쿨다운이 진짜 게이트).
local locked = false

-- Legendary(Crimson Fang) 전용 EMP 필드 — 카운터 자세 발동 즉시 캐릭터 발밑에 방출.
-- ⚠ ReplicatedStorage.empfieldfx 필요(클라 접근). 첫 방출 텍스처 디코드 지연은
--   AssetPreloadClient 의 WARMUP_EMP 워밍업으로 해소됨.
local function emitCounterEMP()
	if not Tool:GetAttribute("LegendarySkin") then return end
	local src = ReplicatedStorage:FindFirstChild("empfieldfx")
	if not src then
		warn("[Counter] ReplicatedStorage.empfieldfx 없음 — EMP 생략")
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local fx = src:Clone()
	fx.Name = "_CounterEMP"
	fx.Anchored = true
	fx.CanCollide = false
	fx.CanQuery = false
	fx.CanTouch = false
	fx.Transparency = 1
	fx.CFrame = hrp.CFrame * CFrame.new(0, EMP_Y_OFFSET, 0)   -- 캐릭터 중심(돔 형태)
	fx.Parent = workspace
	local maxLife = 0
	for _, e in ipairs(fx:GetDescendants()) do
		if e:IsA("ParticleEmitter") then
			e.Enabled = true
			e:Emit(e.Name == "ForceField1" and EMP_EMIT_LINES or EMP_EMIT_SHELL)
			if e.Lifetime and e.Lifetime.Max > maxLife then maxLife = e.Lifetime.Max end
		end
	end
	task.delay(0.05, function()
		for _, e in ipairs(fx:GetDescendants()) do
			if e:IsA("ParticleEmitter") then e.Enabled = false end
		end
	end)
	-- 캐릭터 추적: Anchored 유지 + 매 프레임 CFrame 갱신.
	-- (용접 대신 이 방식 — 클라 전용 연출이라 물리 어셈블리에 끼어들 필요 없음)
	local life = math.max(maxLife, 1) + 0.5
	local RunService = game:GetService("RunService")
	local conn
	local t0 = os.clock()
	conn = RunService.RenderStepped:Connect(function()
		if not fx.Parent or os.clock() - t0 > life then
			if conn then conn:Disconnect() end
			return
		end
		local ch = player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root then
			fx.CFrame = root.CFrame * CFrame.new(0, EMP_Y_OFFSET, 0)
		end
	end)
	game:GetService("Debris"):AddItem(fx, life)
end

local function activateCounter()
	if locked then return end
	locked = true
	icon.ImageColor3 = Color3.fromRGB(140, 140, 140)  -- 발동 중 아이콘 어둡게
	btn.AutoButtonColor = false
	CounterRemote:FireServer("Activate")
	emitCounterEMP()
	-- 자세(1.5s) + 쿨다운(8s) 동안 버튼 잠금 표시. 서버가 실제 게이트.
	task.spawn(function()
		local remain = 7.5
		while remain > 0 do
			cdLabel.Text = tostring(math.ceil(remain))
			task.wait(0.2)
			remain = remain - 0.2
		end
		locked = false
		icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		cdLabel.Text = ""
	end)
end

-- 버튼 클릭 (모바일 터치 + 마우스) — 한 번 누름
btn.Activated:Connect(activateCounter)

-- PC: F 키 한 번 누름
UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not gui.Enabled then return end
	if input.KeyCode == Enum.KeyCode.F then
		activateCounter()
	end
end)

-- ── 참격 이펙트 (무협/애니풍 베기 호) ───────────────────────
-- 러너 위치 → 태거 위치 방향으로 휘어진 발광 호를 순간 그렸다 페이드.
local TweenService = game:GetService("TweenService")

local slashTemplate = ReplicatedStorage:WaitForChild("BlueSlashTemplate", 5)

-- 참격 지속 시간 + 페이드 곡선 (모든 참격 함수 공통).
-- 앞부분(60%)은 또렷하게 유지 → 뒷부분에서 빠르게 사라짐 → "확 긋고 스르륵" 베기 리듬.
local SLASH_LIFE = 0.4
local function slashFade(a)  -- a: 0~1 진행도 → 반환: 0(불투명)~1(투명)
	if a < 0.6 then
		return a * 0.15          -- 앞 60%: 거의 안 흐려짐 (0 → 0.09)
	else
		local t = (a - 0.6) / 0.4  -- 뒤 40%: 빠르게 사라짐
		return 0.09 + t * 0.91
	end
end

-- Beam 참격: 호를 따라 colorSeq(ColorSequence)를 입힘.
-- 데칼로 표현 안 되는 색(흰색·무지개 등)에 사용. 공간 그라데이션이라 짧은 베기에도 또렷.
local function drawBeamSlash(fromPos, toPos, colorSeq)
	local dir = (toPos - fromPos)
	if dir.Magnitude < 0.1 then return end
	local mid = fromPos:Lerp(toPos, 0.5) + Vector3.new(0, 2.5, 0)

	local base = Instance.new("Part")
	base.Anchored = true; base.CanCollide = false; base.CanQuery = false
	base.Transparency = 1; base.Size = Vector3.new(0.2,0.2,0.2)
	base.CFrame = CFrame.lookAt(mid, toPos)
	base.Parent = workspace

	local span = math.clamp(dir.Magnitude * 0.6, 8, 18)
	local a0 = Instance.new("Attachment", base); a0.Position = Vector3.new(-span/2, 0, 0)
	local a1 = Instance.new("Attachment", base); a1.Position = Vector3.new(span/2, 0, 0)

	local function makeBeam(width, trans)
		local b = Instance.new("Beam")
		b.Attachment0 = a0; b.Attachment1 = a1
		b.CurveSize0 = span * 0.45; b.CurveSize1 = -span * 0.45
		b.Width0 = width; b.Width1 = width
		b.Color = colorSeq
		b.LightEmission = 1; b.LightInfluence = 0
		b.FaceCamera = true
		b.Transparency = NumberSequence.new(trans)
		b.Parent = base
		return b
	end
	local beam = makeBeam(0.3, 0)
	local core = makeBeam(0.9, 0.5)

	task.spawn(function()
		local t0 = tick()
		while tick() - t0 < SLASH_LIFE do
			local a = (tick() - t0) / SLASH_LIFE
			local f = slashFade(a)
			beam.Transparency = NumberSequence.new(f)
			core.Transparency = NumberSequence.new(0.5 + f * 0.5)
			task.wait()
		end
		base:Destroy()
	end)
end

-- 위/아래 2색 참격: 호를 폭 방향으로 위(topColor)/아래(botColor) 나눔.
-- Beam의 ColorSequence는 길이방향만 되므로, 위·아래로 살짝 띄운 Beam 2줄로 표현.
local function drawSplitSlash(fromPos, toPos, topColor, botColor)
	local dir = (toPos - fromPos)
	if dir.Magnitude < 0.1 then return end
	local mid = fromPos:Lerp(toPos, 0.5) + Vector3.new(0, 2.5, 0)

	local base = Instance.new("Part")
	base.Anchored = true; base.CanCollide = false; base.CanQuery = false
	base.Transparency = 1; base.Size = Vector3.new(0.2,0.2,0.2)
	base.CFrame = CFrame.lookAt(mid, toPos)
	base.Parent = workspace

	local span = math.clamp(dir.Magnitude * 0.6, 8, 18)
	-- 위/아래로 살짝 띄운 4개 어태치먼트 (위 호 / 아래 호)
	local off = 0.55  -- 위아래 분리 간격
	local topA0 = Instance.new("Attachment", base); topA0.Position = Vector3.new(-span/2,  off, 0)
	local topA1 = Instance.new("Attachment", base); topA1.Position = Vector3.new( span/2,  off, 0)
	local botA0 = Instance.new("Attachment", base); botA0.Position = Vector3.new(-span/2, -off, 0)
	local botA1 = Instance.new("Attachment", base); botA1.Position = Vector3.new( span/2, -off, 0)

	local function makeBeam(a0, a1, color, width)
		local b = Instance.new("Beam")
		b.Attachment0 = a0; b.Attachment1 = a1
		b.CurveSize0 = span * 0.45; b.CurveSize1 = -span * 0.45
		b.Width0 = width; b.Width1 = width
		b.Color = ColorSequence.new(color)
		b.LightEmission = 1; b.LightInfluence = 0
		b.FaceCamera = true
		b.Transparency = NumberSequence.new(0)
		b.Parent = base
		return b
	end
	-- 위(검정) / 아래(흰색) — HDR로 발광. 검정은 발광이 약하니 밝기 보정.
	local topBeam = makeBeam(topA0, topA1, topColor, 0.8)
	local botBeam = makeBeam(botA0, botA1, botColor, 0.8)

	task.spawn(function()
		local t0 = tick()
		while tick() - t0 < SLASH_LIFE do
			local a = (tick() - t0) / SLASH_LIFE
			local f = slashFade(a)
			topBeam.Transparency = NumberSequence.new(f)
			botBeam.Transparency = NumberSequence.new(f)
			task.wait()
		end
		base:Destroy()
	end)
end

-- 무지개 그라데이션 시퀀스 (호를 따라 빨→보)
local RAINBOW_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 40, 40)),
	ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 150, 20)),
	ColorSequenceKeypoint.new(0.34, Color3.fromRGB(255, 240, 40)),
	ColorSequenceKeypoint.new(0.50, Color3.fromRGB(50, 220, 70)),
	ColorSequenceKeypoint.new(0.67, Color3.fromRGB(60, 160, 255)),
	ColorSequenceKeypoint.new(0.84, Color3.fromRGB(70, 70, 220)),
	ColorSequenceKeypoint.new(1.00, Color3.fromRGB(180, 60, 230)),
})

local function drawRainbowSlash(fromPos, toPos)
	drawBeamSlash(fromPos, toPos, RAINBOW_SEQ)
end

local function drawSlash(fromPos, toPos, slashColor)
	if not slashTemplate then return end
	local dir = (toPos - fromPos)
	if dir.Magnitude < 0.1 then return end
	local mid = fromPos:Lerp(toPos, 0.35) + Vector3.new(0, 0.5, 0)  -- 살짝 위로 (초승달과 동일 거리)

	-- blue slash 템플릿 복제 → 태거 방향으로 배치
	local fx = slashTemplate:Clone()
	-- 모델/파트 모두 대응
	local primary = fx:IsA("BasePart") and fx or (fx.PrimaryPart or fx:FindFirstChildWhichIsA("BasePart"))
	if not primary then fx:Destroy(); return end

	-- 스킨 색이 전달되면 참격 색을 그 색으로 칠함 (유채색 전용 — 흰색/무지개는 Beam 경로).
	if slashColor then
		local r, g, b = slashColor.R, slashColor.G, slashColor.B
		local boost = 3
		local hdr = Color3.new(math.min(r*boost,4), math.min(g*boost,4), math.min(b*boost,4))
		local vc = Vector3.new(r*5, g*5, b*5)
		for _, d in ipairs(fx:GetDescendants()) do
			if d:IsA("Decal") or d:IsA("Texture") then
				d.Color3 = hdr
			elseif d:IsA("SpecialMesh") then
				d.VertexColor = vc
			end
		end
		if fx:IsA("BasePart") then
			for _, d in ipairs(fx:GetChildren()) do
				if d:IsA("Decal") or d:IsA("Texture") then d.Color3 = hdr end
			end
		end
	end

	-- 초승달(drawTemplateSlash)과 동일한 배치: 눕힌 메시를 진행 방향으로 yaw + 각도 보정
	-- (유채색 데칼은 메시 기준이 반대라 flatDir을 뒤집어 정반대로 향하게)
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	if flatDir.Magnitude < 0.01 then flatDir = Vector3.new(0,0,-1) end
	flatDir = -flatDir.Unit
	local yawCF = CFrame.lookAt(mid, mid + flatDir)
	local cf = yawCF * CFrame.Angles(math.rad(-40), -140, -10)
	if fx:IsA("BasePart") then
		fx.CFrame = cf
		fx.Anchored = true
		fx.CanCollide = false
	else
		fx:PivotTo(cf)
	end
	fx.Parent = workspace

	-- 데칼/텍스처 수집 (페이드 대상)
	local decals = {}
	for _, d in ipairs(fx:GetDescendants()) do
		if d:IsA("Decal") or d:IsA("Texture") then
			table.insert(decals, { obj = d, base = d.Transparency })
		end
	end
	-- fx 본체가 Part면 그 데칼도
	if fx:IsA("BasePart") then
		for _, d in ipairs(fx:GetChildren()) do
			if d:IsA("Decal") or d:IsA("Texture") then
				table.insert(decals, { obj = d, base = d.Transparency })
			end
		end
	end

	-- 빠르게 페이드아웃 (베는 순간 번쩍 → 사라짐)
	task.spawn(function()
		local t0 = tick()
		while tick() - t0 < SLASH_LIFE do
			local a = (tick() - t0) / SLASH_LIFE
			local f = slashFade(a)
			for _, rec in ipairs(decals) do
				rec.obj.Transparency = rec.base + (1 - rec.base) * f
			end
			task.wait()
		end
		fx:Destroy()
	end)
end

-- 템플릿 초승달을 색 변경 없이 그대로 띄움 (검정/흰색 등 이미 색이 입혀진 모델용).
local katanaSlashTemplate = ReplicatedStorage:FindFirstChild("KatanaSlashTemplate")
local function drawTemplateSlash(fromPos, toPos, template)
	if not template then return end
	local dir = (toPos - fromPos)
	if dir.Magnitude < 0.1 then return end
	local mid = fromPos:Lerp(toPos, 0.35) + Vector3.new(0, 2.5, 0)

	local fx = template:Clone()
	-- 초승달은 원래 바닥에 평평하게 누운 메시. 눕힌 자세를 유지하며
	-- 오목한 입구가 태거(진행 방향)를 향하도록 yaw만 회전 + 살짝 기울여 세움.
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	if flatDir.Magnitude < 0.01 then flatDir = Vector3.new(0,0,-1) end
	flatDir = flatDir.Unit
	-- 진행 방향을 바라보는 수평 기준 + 앞으로 30도 기울여 비스듬히
	local yawCF = CFrame.lookAt(mid, mid + flatDir)
	local cf = yawCF * CFrame.Angles(-math.pi/2, 0, 0) * CFrame.Angles(0, 0, 0)
	-- 살짝 세움(앞으로 60도 기울임): 수평(눕힘) ↔ 수직(세움) 사이
	cf = yawCF * CFrame.Angles(math.rad(0), -90, -10)
	if fx:IsA("BasePart") then
		fx.CFrame = cf; fx.Anchored = true; fx.CanCollide = false
	else
		fx:PivotTo(cf)
	end
	fx.Parent = workspace

	-- 페이드 대상: 파트 투명도 + 데칼/텍스처 투명도
	local fades = {}
	local function collect(inst)
		if inst:IsA("BasePart") then
			table.insert(fades, { obj = inst, base = inst.Transparency })
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			table.insert(fades, { obj = inst, base = inst.Transparency })
		end
	end
	collect(fx)
	for _, d in ipairs(fx:GetDescendants()) do collect(d) end

	task.spawn(function()
		local t0 = tick()
		while tick() - t0 < SLASH_LIFE do
			local a = (tick() - t0) / SLASH_LIFE
			local f = slashFade(a)
			for _, rec in ipairs(fades) do
				rec.obj.Transparency = rec.base + (1 - rec.base) * f
			end
			task.wait()
		end
		fx:Destroy()
	end)
end
CounterRemote.OnClientEvent:Connect(function(action, fromPos, toPos, slashColor, isRainbow)
	if action == "CounterSuccess" then
		-- 버튼 번쩍 (성공)
		icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		task.wait(0.15)
		-- 성공해도 쿨다운 도는 동안 잠금색 유지 (locked면 그대로)
		if not locked then
			icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		else
			icon.ImageColor3 = Color3.fromRGB(140, 140, 140)
		end
	elseif action == "CounterSlash" then
		-- 참격 이펙트 (모든 클라가 봄).
		if fromPos and toPos then
			if isRainbow then
				drawRainbowSlash(fromPos, toPos)  -- 무지개: Beam 공간 그라데이션
			elseif slashColor then
				-- 흰색/밝은 무채색은 데칼 곱으로 파랑이 안 지워짐 → Beam 단색으로.
				local r, g, b = slashColor.R, slashColor.G, slashColor.B
				local maxc, minc = math.max(r,g,b), math.min(r,g,b)
				local isWhitish = (minc > 0.6) and (maxc - minc < 0.15)
				if isWhitish then
					-- 화이트 카타나: 원본과 동일한 음양(검정/흰색) 초승달 공유
					drawTemplateSlash(fromPos, toPos, katanaSlashTemplate)
				else
					drawSlash(fromPos, toPos, slashColor)  -- 유채색: blue slash 데칼에 색입힘
				end
			else
				-- 원본 카타나(스킨 없음): 검정/흰색 초승달 참격
				drawTemplateSlash(fromPos, toPos, katanaSlashTemplate)
			end
		end
	end
end)

-- ── 장착/해제 시 버튼 표시 토글 ─────────────────────────────
Tool.Equipped:Connect(function()
	gui.Enabled = true
end)
Tool.Unequipped:Connect(function()
	gui.Enabled = false
end)
