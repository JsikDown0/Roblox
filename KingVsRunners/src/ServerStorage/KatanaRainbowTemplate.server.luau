-- 카타나 무지개 순환 (RainbowKatana 스킨용 템플릿).
-- Tool 안에 복제되어 들어감. RainbowPart 속성이 true인 파트들의 색을 Hue 순환.
local tool = script.Parent
local RunService = game:GetService("RunService")
local CYCLE_TIME = 3      -- 한 바퀴 도는 시간(초)
local UPDATE_INTERVAL = 0.05  -- 색 갱신 간격(초). 0.05=초당 20회면 눈엔 충분히 부드럽고 가벼움.

-- 순환 대상 수집 (지급 시 RainbowPart=true로 표시된 파트)
local parts = {}
for _, p in ipairs(tool:GetDescendants()) do
	if p:IsA("BasePart") and p:GetAttribute("RainbowPart") then
		p.Material = Enum.Material.Neon
		table.insert(parts, p)
	end
end

-- 순환 대상이 없으면 루프 자체를 안 돌림 (낭비 방지)
if #parts == 0 then return end

local conn
local accum = 0
conn = RunService.Heartbeat:Connect(function(dt)
	-- 무기가 사라졌으면(부모 없음) 루프 해제 → 누수 방지
	if not tool.Parent then
		conn:Disconnect()
		return
	end
	accum = accum + dt
	if accum < UPDATE_INTERVAL then return end
	accum = 0
	local hue = (tick() % CYCLE_TIME) / CYCLE_TIME
	local col = Color3.fromHSV(hue, 1, 1)
	for _, p in ipairs(parts) do
		if p.Parent then p.Color = col end
	end
end)
