-- 좌/우 Mountains 모델의 모든 BasePart 충돌 비활성화
-- 시각 메쉬보다 충돌 영역이 더 커서 보이지 않는 막힘이 발생하는 문제 해결용

local map1 = workspace:WaitForChild("map1")
local castle = map1:WaitForChild("map1 castle")

local function disableCollisionFor(model, label)
	if not model then
		warn("⚠️ " .. label .. " 모델 없음")
		return
	end
	local disabled = 0
	local skipped = 0
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			if desc.CanCollide then
				desc.CanCollide = false
				disabled += 1
			else
				skipped += 1
			end
		end
	end
	print(string.format("✅ %s: CanCollide 비활성 %d개 (이미 false: %d)", label, disabled, skipped))
end

disableCollisionFor(castle:FindFirstChild("left Mountains"),  "left Mountains")
disableCollisionFor(castle:FindFirstChild("right Mountains"), "right Mountains")
