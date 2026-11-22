-- 건틀렛 컬러 저장 서버 핸들러
-- 클라가 APPLY 시 (zone, colorName) 보내면, 보유 검증 후 플레이어 속성에 저장.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local remote = ReplicatedStorage:WaitForChild("GauntletColorRemote")
local paletteMod = ServerStorage:FindFirstChild("GauntletColorPalette")
local palette = paletteMod and require(paletteMod)

-- 플레이어가 해당 색을 보유했는지 검사
-- 기본색(FREE_COLORS)은 항상 보유. 유료색은 Has_GColor_<색> 속성으로 판정.
local function ownsColor(player, colorName)
	if not palette then return false end
	-- 기본 무료색?
	for _, c in ipairs(palette.FREE_COLORS) do
		if c == colorName then return true end
	end
	-- 유료색: 보유 속성 확인
	if player:GetAttribute("Has_GColor_" .. colorName) then
		return true
	end
	return false
end

local ZONE_KEYS = { Body = true, Point = true, Handle = true }

remote.OnServerEvent:Connect(function(player, zone, colorName)	-- ⚠️ [ROUND-LOCK] 라운드 중에는 변경 불가. UI 를 닫는 것만으론 부족하다 —
	--    리모트는 클라에서 직접 호출할 수 있으므로 서버가 최종 방어선이다.
	--    (실측 2026-08-21: 라운드 중 인벤에서 바꾸면 실시간 반영됨)
	do
		local _ph = game:GetService("ReplicatedStorage"):GetAttribute("RoundPhase")
		if _ph == "stage1" or _ph == "stage2" then return end
	end
	-- 입력 검증 (정적 색 또는 특수 효과색 rainbow 허용)
	if type(zone) ~= "string" or type(colorName) ~= "string" then return end
	if not ZONE_KEYS[zone] then return end
	if not palette or not palette.isValidColor(colorName) then return end
	-- 보유 검증
	if not ownsColor(player, colorName) then
		warn("[GauntletColor]", player.Name, "미보유 색 시도:", colorName)
		return
	end
	-- 저장
	player:SetAttribute("GauntletColor_" .. zone, colorName)
end)

print("✅ GauntletColorServer 준비 (컬러 저장 + 보유 검증)")
