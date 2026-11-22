-- NoobColorServer: 클라가 (zone, colorName) 보내면 보유 검증 후 NoobColor_<zone> 속성 저장
-- 건틀릿 GauntletColorServer 패턴 복제. zone = Head/Torso/Legs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local palette = require(ReplicatedStorage:WaitForChild("NoobColorPalette"))
local remote = ReplicatedStorage:WaitForChild("NoobColorRemote")

local ZONE_KEYS = {}
for _, z in ipairs(palette.ZONES) do ZONE_KEYS[z] = true end

-- 무료색은 항상 보유, 유료색은 Has_NoobColor_<색> 속성으로 판정
local function ownsColor(player, colorName)
	if palette.isFree(colorName) then return true end
	if player:GetAttribute("Has_NoobColor_" .. colorName) then return true end
	return false
end

remote.OnServerEvent:Connect(function(player, zone, colorName)	-- ⚠️ [ROUND-LOCK] 라운드 중에는 변경 불가. UI 를 닫는 것만으론 부족하다 —
	--    리모트는 클라에서 직접 호출할 수 있으므로 서버가 최종 방어선이다.
	--    (실측 2026-08-21: 라운드 중 인벤에서 바꾸면 실시간 반영됨)
	do
		local _ph = game:GetService("ReplicatedStorage"):GetAttribute("RoundPhase")
		if _ph == "stage1" or _ph == "stage2" then return end
	end
	if type(zone) ~= "string" or type(colorName) ~= "string" then return end
	if not ZONE_KEYS[zone] then return end
	if not palette.isValidColor(colorName) then return end
	if not ownsColor(player, colorName) then
		warn("[NoobColor]", player.Name, "미보유 색 시도:", colorName)
		return
	end
	player:SetAttribute("NoobColor_" .. zone, colorName)
end)

print("✅ NoobColorServer 준비 (부위별 색 저장 + 보유 검증)")
