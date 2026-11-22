-- PickupPromptFilter
-- 태거에게는 픽업 ProximityPrompt가 보이지 않도록 클라이언트 사이드 필터링.
-- ProximityPromptService.PromptShown 이벤트로 표시 직전에 가로채서 역할 검사 후 차단.
--
-- 동작:
--   - 러너: 평소처럼 prompt 보임 (Default 스타일)
--   - 태거: prompt 자체가 표시 안 됨 (시각 + 인터랙션 둘 다 차단)

local Players               = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local localPlayer = Players.LocalPlayer

-- 픽업 prompt인지 식별: 부모 모델의 이름이 "Pickup_" 로 시작하는지 확인
-- (PickupSystem의 createPickupModel에서 model.Name = "Pickup_" .. itemName 으로 명명)
local function isPickupPrompt(prompt)
	local part = prompt.Parent
	if not part then return false end
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then return false end
	return string.sub(model.Name, 1, 7) == "Pickup_"
end

local function getRole()
	-- Role 어트리뷰트는 RoundSystem에서 캐릭터/플레이어에 설정됨
	-- 안전하게 둘 다 확인
	local role = localPlayer:GetAttribute("Role")
	if role then return role end

	local character = localPlayer.Character
	if character then
		role = character:GetAttribute("Role")
		if role then return role end
	end
	return nil
end

ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if not isPickupPrompt(prompt) then return end  -- 다른 prompt(부활 등)는 손대지 않음

	local role = getRole()
	if role == "Runner" then return end  -- 러너는 그대로 표시

	-- 태거 또는 역할 미정 → 즉시 숨김
	-- ProximityPrompt:InputHoldBegin/End가 클라이언트 트리거이므로,
	-- Style을 Custom으로 바꾸고 아무 UI도 만들지 않으면 시각적으로 안 보임 + 차징도 못 함
	prompt.Style = Enum.ProximityPromptStyle.Custom
end)

print("✅ PickupPromptFilter 활성화 (태거 prompt 숨김)")
