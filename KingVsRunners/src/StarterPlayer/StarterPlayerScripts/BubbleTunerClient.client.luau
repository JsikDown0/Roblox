-- 🎨 BubbleTunerClient — 말풍선 수동 조정 도구 (dev 전용)
--
-- [쓰는 법] 로비에서 V 키 → 조정 패널이 뜬다.
--   값을 맞춘 뒤 "값 출력" 을 누르면 콘솔에 상수 블록이 찍힌다.
--   그걸 EmotionServer 의 상수 자리에 그대로 붙여넣으면 된다.
--
-- ⚠️ 이 스크립트는 '미리보기' 만 만든다. 실제 이모지는 서버(EmotionServer)가
--   만들므로, 여기서 바꾼 값은 저장되지 않는다 — 반드시 출력해서 옮겨야 한다.
--   (BadgeTunerClient 와 같은 규약. 클라가 서버 상수를 바꿀 수는 없다)
-- ⚠️ dev/스튜디오 전용 게이트. 되돌리기 = 아래 한 줄 삭제.
-- ⚠️ 릴리즈 전 이 스크립트 자체를 지울 것.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer

if not game:GetService("RunService"):IsStudio() and player.UserId ~= 9228200642 then return end

-- ── EmotionServer 와 같은 초기값 ───────────────────────────────
local V = {
	BUBBLE_PX       = 190,
	BUBBLE_OFFSET_X = -3.0,
	BUBBLE_OFFSET_Y = 2.2,
	CONTENT_SCALE   = 0.62,
	CONTENT_CX      = 0.44,
	CONTENT_CY      = 0.42,
}

local BUBBLE_IMAGE  = "rbxassetid://103948077910387"
local PREVIEW_IMAGE = "rbxassetid://110805052551564"   -- 아무 이모트 이미지(미리보기용)

local preview = nil

-- 말풍선 재생성 (EmotionServer.makeBubble 과 같은 구조여야 의미가 있다)
local function rebuild()
	if preview then preview:Destroy() ; preview = nil end
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "_BubblePreview"
	-- ⚠️ [2026-08-28] EmotionServer 와 같은 단위여야 한다. Scale=스터드.
	--    Offset(px) 로 두면 줌에 따라 크기가 달라져 튜너 값이 실제와 어긋난다.
	--    ⚠️ BUBBLE_PX 는 이름만 px 지 실제로는 '스터드 × 38' 기준값이다.
	bb.Size = UDim2.fromScale(V.BUBBLE_PX / 38, V.BUBBLE_PX / 38)
	bb.StudsOffset = Vector3.new(V.BUBBLE_OFFSET_X, V.BUBBLE_OFFSET_Y, 0)
	bb.AlwaysOnTop = true
	bb.ResetOnSpawn = false
	bb.LightInfluence = 0
	bb.Parent = head

	local bg = Instance.new("ImageLabel")
	bg.ZIndex = 20
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundTransparency = 1
	bg.Image = BUBBLE_IMAGE
	bg.ScaleType = Enum.ScaleType.Fit
	bg.Parent = bb

	local img = Instance.new("ImageLabel")
	img.ZIndex = 21
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.new(V.CONTENT_CX, 0, V.CONTENT_CY, 0)
	img.Size = UDim2.new(V.CONTENT_SCALE, 0, V.CONTENT_SCALE, 0)
	img.BackgroundTransparency = 1
	img.Image = PREVIEW_IMAGE
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = bg

	preview = bb
end

-- ── 조정 패널 ──────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "BubbleTuner"
gui.ResetOnSpawn = false
gui.DisplayOrder = 200
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(280, 430)
panel.Position = UDim2.new(0, 16, 0.5, -215)
panel.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "💬 Bubble Tuner  (V 로 닫기)"
title.TextColor3 = Color3.fromRGB(255, 220, 90)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.Parent = panel

local list = Instance.new("Frame")
list.Position = UDim2.new(0, 8, 0, 34)
list.Size = UDim2.new(1, -16, 1, -78)
list.BackgroundTransparency = 1
list.Parent = panel
local layout = Instance.new("UIListLayout", list)
layout.Padding = UDim.new(0, 4)

-- 각 값의 조정 폭
local STEP = {
	BUBBLE_PX = 4, BUBBLE_OFFSET_X = 0.2, BUBBLE_OFFSET_Y = 0.2,
	CONTENT_SCALE = 0.02, CONTENT_CX = 0.02, CONTENT_CY = 0.02,
}
local ORDER = { "BUBBLE_OFFSET_X", "BUBBLE_OFFSET_Y", "BUBBLE_PX",
                "CONTENT_SCALE", "CONTENT_CX", "CONTENT_CY" }

local valueLabels = {}
for i, key in ipairs(ORDER) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundTransparency = 1
	row.LayoutOrder = i
	row.Parent = list

	local nm = Instance.new("TextLabel")
	nm.Size = UDim2.new(0, 130, 1, 0)
	nm.BackgroundTransparency = 1
	nm.Text = key
	nm.TextColor3 = Color3.fromRGB(200, 205, 220)
	nm.Font = Enum.Font.Gotham
	nm.TextSize = 11
	nm.TextXAlignment = Enum.TextXAlignment.Left
	nm.Parent = row

	local function mkBtn(txt, x, delta)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(24, 22)
		b.Position = UDim2.new(0, x, 0, 2)
		b.BackgroundColor3 = Color3.fromRGB(55, 60, 78)
		b.Text = txt
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.BorderSizePixel = 0
		b.Parent = row
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
		b.MouseButton1Click:Connect(function()
			V[key] = V[key] + delta
			valueLabels[key].Text = string.format("%.2f", V[key])
			rebuild()
		end)
		return b
	end
	mkBtn("-", 132, -STEP[key])
	mkBtn("+", 218,  STEP[key])

	local vl = Instance.new("TextLabel")
	vl.Size = UDim2.fromOffset(56, 22)
	vl.Position = UDim2.new(0, 158, 0, 2)
	vl.BackgroundTransparency = 1
	vl.Text = string.format("%.2f", V[key])
	vl.TextColor3 = Color3.fromRGB(255, 255, 255)
	vl.Font = Enum.Font.GothamBold
	vl.TextSize = 12
	vl.Parent = row
	valueLabels[key] = vl
end

local dump = Instance.new("TextButton")
dump.Size = UDim2.new(1, -16, 0, 32)
dump.Position = UDim2.new(0, 8, 1, -40)
dump.BackgroundColor3 = Color3.fromRGB(60, 160, 90)
dump.Text = "📋 값 출력 (콘솔)"
dump.TextColor3 = Color3.fromRGB(255, 255, 255)
dump.Font = Enum.Font.GothamBold
dump.TextSize = 13
dump.BorderSizePixel = 0
dump.Parent = panel
Instance.new("UICorner", dump).CornerRadius = UDim.new(0, 6)

dump.MouseButton1Click:Connect(function()
	print("─── EmotionServer 에 붙여넣을 값 ───")
	print(string.format("local BUBBLE_PX       = %d",   V.BUBBLE_PX))
	print(string.format("local BUBBLE_OFFSET_X = %.1f", V.BUBBLE_OFFSET_X))
	print(string.format("local BUBBLE_OFFSET_Y = %.1f", V.BUBBLE_OFFSET_Y))
	print(string.format("local CONTENT_SCALE = %.2f",   V.CONTENT_SCALE))
	print(string.format("local CONTENT_CX    = %.2f",   V.CONTENT_CX))
	print(string.format("local CONTENT_CY    = %.2f",   V.CONTENT_CY))
	print("──────────────────────────────────")
end)

UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.V then
		gui.Enabled = not gui.Enabled
		if gui.Enabled then rebuild()
		elseif preview then preview:Destroy() ; preview = nil end
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	if gui.Enabled then rebuild() end
end)

print("🎨 BubbleTunerClient 활성화 — 로비에서 V 키")
