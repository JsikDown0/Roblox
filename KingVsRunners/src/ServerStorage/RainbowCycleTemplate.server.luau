-- 무지개 순환 발광 (RainbowCycleSword 스킨용 템플릿).
-- Stage2에서 검 Handle에 복제·삽입됨. script.Parent = Handle.
local handle = script.Parent
if not handle or not handle:IsA("BasePart") then return end

handle.Material = Enum.Material.Neon

local RunService = game:GetService("RunService")
local CYCLE_TIME = 3  -- 한 바퀴(빨→보) 도는 시간(초)
RunService.Heartbeat:Connect(function()
	local hue = (tick() % CYCLE_TIME) / CYCLE_TIME
	handle.Color = Color3.fromHSV(hue, 1, 1)
end)
