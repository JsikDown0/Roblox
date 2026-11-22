-- 🏰 성문 붕괴 화면 흔들림
--
-- ⚠️ 강도는 서버가 거리로 계산해 보낸다(0.35~1.0). 클라는 그대로 쓴다.
-- ⚠️ 짧고 약하게. 과한 흔들림은 저연령·모바일에서 멀미를 유발하고,
--    "무게감"을 넘어 "조작 불능"으로 느껴진다.
-- ⚠️ CFrame 을 직접 덮어쓰지 않는다. 카메라 제어는 Roblox 기본 스크립트가
--    매 프레임 하고 있어, 덮어쓰면 서로 싸우다 화면이 튄다.
--    → RenderStepped 에서 '현재 카메라에 오프셋을 더하는' 방식으로 얹는다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local shakeEvent = ReplicatedStorage:WaitForChild("BarricadeShake")

local DURATION   = 0.55   -- 총 지속(초). 길면 멀미가 난다.
local MAX_ANGLE  = 1.6    -- 최대 회전 진폭(도)
local MAX_OFFSET = 0.5    -- 최대 위치 진폭(stud)
local FREQ       = 34     -- 진동 주파수

local shakeUntil = 0
local shakePower = 0
local shakeStart = 0

shakeEvent.OnClientEvent:Connect(function(power)
    power = math.clamp(tonumber(power) or 0.5, 0, 1)
    -- 이미 흔들리는 중이면 더 센 쪽을 채택(겹쳐서 두 배가 되지 않게)
    if os.clock() < shakeUntil and power <= shakePower then return end
    shakePower = power
    shakeStart = os.clock()
    shakeUntil = shakeStart + DURATION
end)

RunService.RenderStepped:Connect(function()
    if os.clock() >= shakeUntil then return end
    local cam = workspace.CurrentCamera
    if not cam then return end

    local el = os.clock() - shakeStart
    -- 시간이 갈수록 잦아든다(감쇠)
    local decay = 1 - (el / DURATION)
    decay = decay * decay          -- 초반이 세고 빠르게 잦아듦
    local amp = shakePower * decay

    local t = el * FREQ
    local rx = math.sin(t * 1.0) * MAX_ANGLE * amp
    local ry = math.sin(t * 1.37) * MAX_ANGLE * amp
    local ox = math.sin(t * 1.21) * MAX_OFFSET * amp
    local oy = math.sin(t * 0.93) * MAX_OFFSET * amp

    cam.CFrame = cam.CFrame
        * CFrame.new(ox, oy, 0)
        * CFrame.Angles(math.rad(rx), math.rad(ry), 0)
end)
