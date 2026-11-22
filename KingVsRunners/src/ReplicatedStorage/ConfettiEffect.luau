-- ConfettiEffect: 보상 수령 등에서 화면에 색종이 컨페티를 뿌리는 UI 연출
-- 자체 ScreenGui(최상단)를 만들어 팝업 위에 표시하고, 끝나면 자동 정리.
-- 사용: local Confetti = require(game.ReplicatedStorage.ConfettiEffect); Confetti.play()
local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local ConfettiEffect = {}

local COLORS = {
	Color3.fromRGB(255, 80, 80),   -- 빨강
	Color3.fromRGB(255, 170, 40),  -- 주황
	Color3.fromRGB(255, 235, 60),  -- 노랑
	Color3.fromRGB(90, 220, 120),  -- 초록
	Color3.fromRGB(70, 180, 255),  -- 파랑
	Color3.fromRGB(180, 110, 255), -- 보라
	Color3.fromRGB(255, 120, 200), -- 분홍
}

function ConfettiEffect.play(count)
	count = count or 70
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ConfettiBurst"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999   -- 퀘스트/리워드 팝업 위에 표시
	gui.Parent = pg

	-- 팡파레 사운드
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://138915554817346"
	sound.Volume = 1
	sound.Parent = SoundService
	sound:Play()
	task.delay(5, function() if sound then sound:Destroy() end end)

	for i = 1, count do
		local piece = Instance.new("Frame")
		piece.BorderSizePixel = 0
		piece.BackgroundColor3 = COLORS[math.random(#COLORS)]
		piece.Size = UDim2.fromOffset(math.random(8, 15), math.random(12, 22))
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 999
		-- 화면 상단 가로 랜덤 위치에서 시작 (화면 밖 살짝 위)
		local startX = math.random(0, 1000) / 1000
		piece.Position = UDim2.new(startX, 0, -0.1, 0)
		piece.Parent = gui

		-- 떨어지면서 좌우로 약간 흘러내리고 회전
		local endX = math.clamp(startX + (math.random(-160, 160) / 1000), 0, 1)
		local dur  = math.random(140, 240) / 100   -- 1.4~2.4초
		TweenService:Create(piece, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(endX, 0, 1.15, 0),
			Rotation = piece.Rotation + math.random(-540, 540),
		}):Play()
		-- 후반부에 페이드 아웃
		TweenService:Create(piece, TweenInfo.new(dur * 0.35, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, dur * 0.65), {
			BackgroundTransparency = 1,
		}):Play()
	end

	task.delay(3, function()
		if gui and gui.Parent then gui:Destroy() end
	end)
end

return ConfettiEffect
