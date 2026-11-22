-- HammerShakeClient — 고급 망치 슬램 명중 시 화면 흔들림
-- 서버(HammerHighScript)가 ReplicatedStorage.HammerShakeEvent로 (intensity, duration)을 보냄.
-- Humanoid.CameraOffset을 감쇠 랜덤 진동시켜 흔들림 연출 (카메라 모드 안 건드림 → 1인칭/3인칭 모두 동작).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local shakeEvent = ReplicatedStorage:WaitForChild("HammerShakeEvent")

local activeConn = nil   -- 현재 진동 루프 (겹침 방지)

local function shake(intensity, duration)
	intensity = intensity or 1.5
	duration = duration or 0.4

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- 이전 흔들림이 돌고 있으면 정리 (새 흔들림으로 덮어씀)
	if activeConn then activeConn:Disconnect(); activeConn = nil end

	local t0 = os.clock()
	activeConn = RunService.RenderStepped:Connect(function()
		local humNow = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not humNow then
			if activeConn then activeConn:Disconnect(); activeConn = nil end
			return
		end
		local elapsed = os.clock() - t0
		local a = elapsed / duration
		if a >= 1 then
			humNow.CameraOffset = Vector3.new(0, 0, 0)   -- 원위치 복원
			if activeConn then activeConn:Disconnect(); activeConn = nil end
			return
		end
		-- 감쇠: 시작 강하게 → 끝으로 갈수록 약해짐 (1-a)
		local falloff = (1 - a)
		local mag = intensity * falloff
		humNow.CameraOffset = Vector3.new(
			(math.random() - 0.5) * 2 * mag,
			(math.random() - 0.5) * 2 * mag,
			(math.random() - 0.5) * 2 * mag * 0.5   -- 앞뒤는 약하게
		)
	end)
end

shakeEvent.OnClientEvent:Connect(function(intensity, duration)
	shake(intensity, duration)
end)
