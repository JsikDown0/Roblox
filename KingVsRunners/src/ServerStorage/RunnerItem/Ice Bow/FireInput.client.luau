-- Ice Bow 클라이언트 입력 처리 (마인크래프트 식 차징)
-- Mouse Down → 차징 시작 → Mouse Up = 그 시점 power로 발사

local Tool = script.Parent
local RM = Tool:WaitForChild("RemoteEvent")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- 설정 ────────────────────────────────────────────────
local MAX_CHARGE_TIME = 0.8      -- 만렙 도달까지 시간 (초)
local MIN_POWER       = 0.15     -- 이 미만이면 발사 무효
local MAX_DISTANCE    = 1800      -- 사거리 상한 (서버 ARROW_RANGE와 동일)
local CHARGE_SOUND_ID = "rbxassetid://132634002020590"  -- 차징 사운드

-- ── 상태 ────────────────────────────────────────────────
local equippedMouse = nil
local charging = false
local chargeStartTime = 0
local inputConn, endConn = nil, nil

-- ── 차징 사운드 (로컬 재생, 본인만 들음) ────────────────
local SoundService = game:GetService("SoundService")
local chargeSound = Instance.new("Sound")
chargeSound.Name = "IceBowChargeSound"
chargeSound.SoundId = CHARGE_SOUND_ID
chargeSound.Volume = 1
chargeSound.PlaybackSpeed = 1
chargeSound.Parent = SoundService

-- ── 외부 UI 통신 (ChargeBarUI에서 듣게) ─────────────────
-- BindableEvent를 Tool 내부에 생성 (지연 가능, 필수 X)
local chargeBindable = Tool:FindFirstChild("ChargeBindable")
if not chargeBindable then
	chargeBindable = Instance.new("BindableEvent")
	chargeBindable.Name = "ChargeBindable"
	chargeBindable.Parent = Tool
end

local function getCurrentPower()
	if not charging then return 0 end
	local elapsed = tick() - chargeStartTime
	return math.clamp(elapsed / MAX_CHARGE_TIME, 0, 1)
end

-- ── 입력 핸들러 ─────────────────────────────────────────
local function onInputBegan(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then return end

	-- Tool이 손에 들려있는지 확인
	local char = LocalPlayer.Character
	if not char then return end
	if Tool.Parent ~= char then return end
	if not Tool.Enabled then return end

	charging = true
	chargeStartTime = tick()
	chargeBindable:Fire("start", 0)
	-- 차징 사운드 시작
	chargeSound:Stop()
	chargeSound:Play()
end

local function onInputEnded(input)
	if not charging then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.Touch then return end

	local power = getCurrentPower()
	charging = false
	chargeBindable:Fire("end", power)
	chargeSound:Stop()  -- 차징 사운드 정지

	-- 너무 짧으면 발사 X
	if power < MIN_POWER then return end
	if not equippedMouse then return end

	-- 마우스 hit 위치 계산
	local hitPos = equippedMouse.Hit and equippedMouse.Hit.Position
	if not hitPos then return end

	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- power 기반 사거리 (서버에서도 다시 검증)
	local distance = (hitPos - root.Position).Magnitude
	if distance > MAX_DISTANCE then
		local dir = (hitPos - root.Position).Unit
		hitPos = root.Position + dir * MAX_DISTANCE
	end

	RM:FireServer(hitPos, power)
end

-- 매 프레임 차징 power 업데이트 (UI용)
RunService.Heartbeat:Connect(function()
	if charging then
		chargeBindable:Fire("update", getCurrentPower())
	end
end)

-- ── Tool 이벤트 ─────────────────────────────────────────
Tool.Equipped:Connect(function(mouse)
	equippedMouse = mouse
	-- 입력 연결
	if inputConn then inputConn:Disconnect() end
	if endConn then endConn:Disconnect() end
	inputConn = UserInputService.InputBegan:Connect(onInputBegan)
	endConn = UserInputService.InputEnded:Connect(onInputEnded)
end)

Tool.Unequipped:Connect(function()
	equippedMouse = nil
	if inputConn then inputConn:Disconnect(); inputConn = nil end
	if endConn then endConn:Disconnect(); endConn = nil end
	if charging then
		charging = false
		chargeBindable:Fire("cancel", 0)
		chargeSound:Stop()
	end
end)

-- ═══════════════════════════════════════════════════════════════
-- 🏹 [SHOT-FEEDBACK] 명중/빗나감 알림
--
-- [문제] 원거리 무기인데 멀리서 쏘면 결과를 알 수가 없었다. 명중음은 화살이 박힌
--        자리에서 나므로 거리가 멀면 안 들리고, 얼음 오라도 태거 주변에만 생긴다.
-- [해법] 서버가 도달 시점에 결과를 사수에게만 보내고, 화면 중앙 위쪽에 짧게 띄운다.
-- ⚠️ 조준선(AimingLine)이 화면 중앙을 쓰므로 살짝 위로 올려 겹치지 않게 한다.
-- ═══════════════════════════════════════════════════════════════
local shotLabel = nil
local shotToken = 0

local function showShotResult(hit)
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then return end

	if not shotLabel or not shotLabel.Parent then
		local gui = Instance.new("ScreenGui")
		gui.Name = "IceBowShotResult"
		gui.ResetOnSpawn = false      -- 리스폰마다 재생성되지 않게
		gui.IgnoreGuiInset = true
		gui.Parent = pg

		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.AnchorPoint = Vector2.new(0.5, 0.5)
		lbl.Position = UDim2.fromScale(0.5, 0.34)   -- 중앙 조준선보다 위
		lbl.Size = UDim2.fromScale(0.3, 0.07)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextStrokeTransparency = 0.3
		lbl.Parent = gui
		shotLabel = lbl
	end

	shotToken = shotToken + 1
	local myToken = shotToken

	-- 🛡️ [2026-09-02] 세 번째 상태: CC 면역으로 막힘.
	--   [왜] 면역 중에도 "HIT!" 가 떠서 러너는 걸린 줄 알았다. 실제로는 동결이
	--     하나도 안 걸린 상태다 — 결과를 정직하게 알려야 다음 판단을 할 수 있다.
	--   ⚠️ hit 은 이제 true/false/"immune" 세 값이다. 서버가 그렇게 보낸다.
	if hit == "immune" then
		shotLabel.Text = "CC IMMUNE"
		shotLabel.TextColor3 = Color3.fromRGB(255, 120, 110)   -- 면역 보호막과 같은 붉은 계열
	elseif hit then
		shotLabel.Text = "HIT!"
		shotLabel.TextColor3 = Color3.fromRGB(120, 220, 255)   -- 얼음 계열
	else
		shotLabel.Text = "MISS"
		shotLabel.TextColor3 = Color3.fromRGB(190, 190, 190)
	end
	shotLabel.TextTransparency = 0
	shotLabel.TextStrokeTransparency = 0.3

	-- ⚠️ 토큰으로 최신 발사만 지운다. 연사하면 이전 타이머가 새 표시를 지워버린다.
	task.delay(1.0, function()
		if shotToken ~= myToken then return end
		if shotLabel and shotLabel.Parent then
			shotLabel.TextTransparency = 1
			shotLabel.TextStrokeTransparency = 1
		end
	end)
end

-- ⚠️ Tool 안의 RM 이 아니라 ReplicatedStorage 채널을 쓴다.
--    서버가 Tool 내부 RemoteEvent 로 FireClient 하면 샌드박스 경계에 막힌다.
local ShotResultRemote = game:GetService("ReplicatedStorage"):WaitForChild("IceBowShotResult")

ShotResultRemote.OnClientEvent:Connect(function(hit)
	showShotResult(hit == true)
end)
