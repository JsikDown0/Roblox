-- PolicyGate: Roblox 정책(ArePaidRandomItemsRestricted) 조회 → 플레이어 속성으로 저장.
-- 유료 랜덤 아이템(스킨 박스)은 이 정책이 걸린 플레이어에게 팔면 안 됨 (지역/연령 규제, 가챠 금지).
-- 속성 NoPaidRandom = true 인 플레이어에겐: 상점이 박스 숨김 + ProcessReceipt가 지급 거부.
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")

-- 기본값: 안전하게 "제한됨(true)"으로 시작 → 조회 성공해야 풀림 (조회 실패 시 팔지 않음)
local function applyPolicy(player)
	player:SetAttribute("NoPaidRandom", true)   -- 조회 전엔 보수적으로 제한
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if ok and type(info) == "table" then
		-- ArePaidRandomItemsRestricted = true 면 유료 랜덤 금지
		local restricted = info.ArePaidRandomItemsRestricted
		player:SetAttribute("NoPaidRandom", restricted == true)
		print("[PolicyGate]", player.Name, "NoPaidRandom =", restricted == true)
	else
		warn("[PolicyGate] 정책 조회 실패 (보수적으로 제한 유지):", player.Name, info)
	end
end

Players.PlayerAdded:Connect(applyPolicy)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(applyPolicy, p)
end

-- 서버 판정 헬퍼 (ProcessReceipt 등에서 사용)
_G.CanBuyPaidRandom = function(player)
	return player:GetAttribute("NoPaidRandom") ~= true
end

print("✅ PolicyGate ready (유료 랜덤 아이템 정책 게이트)")
