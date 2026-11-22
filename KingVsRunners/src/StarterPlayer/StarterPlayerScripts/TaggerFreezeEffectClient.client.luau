-- Tagger Freeze Effect Client
-- 서버에서 TaggerFreezeEffect:FireClient(player, duration) 호출 시
-- 화면 테두리에 얼음 효과 + Blur 흐림 효과를 duration 초간 표시.
-- Ice Bow 명중 시 또는 다른 도구에서 공용으로 사용.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local TaggerFreezeEffect = ReplicatedStorage:WaitForChild("TaggerFreezeEffect")

local UI_NAME = "TaggerFreezeUI"
local BLUR_NAME = "TaggerFreezeBlur"
local FADE_TIME = 0.2  -- 페이드 인/아웃 시간

local function clearExisting()
	local oldUI = PlayerGui:FindFirstChild(UI_NAME)
	if oldUI then oldUI:Destroy() end
	local oldBlur = Lighting:FindFirstChild(BLUR_NAME)
	if oldBlur then oldBlur:Destroy() end
end

local function playFreeze(duration)
	duration = math.max(duration or 1, 0.1)
	clearExisting()

	-- 1) 화면 테두리 얼음 효과 (ScreenGui + Frame들로 사면 가장자리 표현)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = UI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.Parent = PlayerGui

	-- 중앙은 비고 가장자리만 푸르게 (radial gradient 비슷한 효과를 4면 Frame으로)
	-- 실제로는 ImageLabel + UIGradient 한 장으로 더 깔끔하지만, 
	-- 외부 텍스처 없이 즉시 렌더 가능한 4면 Frame 방식 사용
	local function makeEdge(name, anchor, position, size, gradientRotation)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = anchor
		frame.Position = position
		frame.Size = size
		frame.BackgroundColor3 = Color3.fromRGB(150, 220, 255)
		frame.BackgroundTransparency = 1  -- 초기 투명, 페이드 인됨
		frame.BorderSizePixel = 0
		frame.Parent = screenGui

		-- 가장자리는 진하고 안쪽으로 갈수록 투명해지는 그라데이션
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(Color3.fromRGB(180, 230, 255))
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),    -- 바깥쪽 불투명
			NumberSequenceKeypoint.new(1, 1),    -- 안쪽 투명
		})
		gradient.Rotation = gradientRotation
		gradient.Parent = frame
		return frame
	end

	-- 4면 가장자리 (각자 약 18% 너비/높이)
	local top = makeEdge("Top",
		Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 0),
		UDim2.new(1, 0, 0.18, 0), 90)
	local bottom = makeEdge("Bottom",
		Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, 0),
		UDim2.new(1, 0, 0.18, 0), 270)
	local left = makeEdge("Left",
		Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0),
		UDim2.new(0.12, 0, 1, 0), 0)
	local right = makeEdge("Right",
		Vector2.new(1, 0.5), UDim2.new(1, 0, 0.5, 0),
		UDim2.new(0.12, 0, 1, 0), 180)
	local edges = {top, bottom, left, right}

	-- 1.5) 경고 라벨 (화면 중앙 위쪽) — "무슨일인지" 명확히 알림
	local warnFrame = Instance.new("Frame")
	warnFrame.Name = "WarnFrame"
	warnFrame.AnchorPoint = Vector2.new(0.5, 0)
	warnFrame.Position = UDim2.new(0.5, 0, 0.18, 0)
	warnFrame.Size = UDim2.fromOffset(360, 64)
	warnFrame.BackgroundColor3 = Color3.fromRGB(20, 35, 55)
	warnFrame.BackgroundTransparency = 1   -- 초기 투명, 페이드 인
	warnFrame.BorderSizePixel = 0
	warnFrame.Parent = screenGui

	local warnCorner = Instance.new("UICorner", warnFrame)
	warnCorner.CornerRadius = UDim.new(0, 10)

	local warnStroke = Instance.new("UIStroke", warnFrame)
	warnStroke.Color = Color3.fromRGB(180, 230, 255)
	warnStroke.Thickness = 2
	warnStroke.Transparency = 1   -- 초기 투명, 페이드 인

	local warnTitle = Instance.new("TextLabel", warnFrame)
	warnTitle.Name = "Title"
	warnTitle.AnchorPoint = Vector2.new(0.5, 0)
	warnTitle.Position = UDim2.new(0.5, 0, 0, 6)
	warnTitle.Size = UDim2.new(1, -16, 0, 28)
	warnTitle.BackgroundTransparency = 1
	warnTitle.Font = Enum.Font.GothamBold
	warnTitle.TextSize = 20
	warnTitle.TextColor3 = Color3.fromRGB(200, 240, 255)
	warnTitle.Text = "❄️  FROZEN BY ICE BOW"
	warnTitle.TextXAlignment = Enum.TextXAlignment.Center
	warnTitle.TextTransparency = 1

	local titleStroke = Instance.new("UIStroke", warnTitle)
	titleStroke.Color = Color3.fromRGB(0, 0, 0)
	titleStroke.Thickness = 2
	titleStroke.Transparency = 1

	local warnSub = Instance.new("TextLabel", warnFrame)
	warnSub.Name = "Sub"
	warnSub.AnchorPoint = Vector2.new(0.5, 1)
	warnSub.Position = UDim2.new(0.5, 0, 1, -6)
	warnSub.Size = UDim2.new(1, -16, 0, 22)
	warnSub.BackgroundTransparency = 1
	warnSub.Font = Enum.Font.Gotham
	warnSub.TextSize = 14
	warnSub.TextColor3 = Color3.fromRGB(220, 240, 250)
	warnSub.Text = "Items disabled  ·  Slowed  ·  " .. string.format("%.1f", duration) .. "초"
	warnSub.TextXAlignment = Enum.TextXAlignment.Center
	warnSub.TextTransparency = 1

	local subStroke = Instance.new("UIStroke", warnSub)
	subStroke.Color = Color3.fromRGB(0, 0, 0)
	subStroke.Thickness = 1.5
	subStroke.Transparency = 1

	-- 2) Blur 효과
	local blur = Instance.new("BlurEffect")
	blur.Name = BLUR_NAME
	blur.Size = 0  -- 초기 0, 페이드 인
	blur.Parent = Lighting

	-- 페이드 인
	local fadeIn = TweenService:Create(blur,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = 14})
	fadeIn:Play()
	for _, edge in ipairs(edges) do
		local tw = TweenService:Create(edge,
			TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 0.15})
		tw:Play()
	end
	-- 경고 라벨 페이드 인
	TweenService:Create(warnFrame,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{BackgroundTransparency = 0.15}):Play()
	TweenService:Create(warnStroke,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Transparency = 0}):Play()
	TweenService:Create(warnTitle,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{TextTransparency = 0}):Play()
	TweenService:Create(titleStroke,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Transparency = 0.2}):Play()
	TweenService:Create(warnSub,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{TextTransparency = 0}):Play()
	TweenService:Create(subStroke,
		TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Transparency = 0.3}):Play()

	-- duration 유지 후 페이드 아웃
	task.delay(duration, function()
		if not blur or not blur.Parent then return end
		local fadeOut = TweenService:Create(blur,
			TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Size = 0})
		fadeOut:Play()
		for _, edge in ipairs(edges) do
			local tw = TweenService:Create(edge,
				TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{BackgroundTransparency = 1})
			tw:Play()
		end
		-- 경고 라벨 페이드 아웃
		if warnFrame and warnFrame.Parent then
			TweenService:Create(warnFrame,
				TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{BackgroundTransparency = 1}):Play()
			TweenService:Create(warnStroke,
				TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{Transparency = 1}):Play()
			TweenService:Create(warnTitle,
				TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{TextTransparency = 1}):Play()
			TweenService:Create(titleStroke,
				TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{Transparency = 1}):Play()
			TweenService:Create(warnSub,
				TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{TextTransparency = 1}):Play()
			TweenService:Create(subStroke,
				TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{Transparency = 1}):Play()
		end
		fadeOut.Completed:Connect(function()
			clearExisting()
		end)
	end)
end

TaggerFreezeEffect.OnClientEvent:Connect(playFreeze)

-- 캐릭터 리스폰/제거 시 잔여 효과 청소 (안전망)
Player.CharacterRemoving:Connect(clearExisting)
