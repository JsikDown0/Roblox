-- ItemColorServer: 범용 색+재질 저장.
-- 클라가 (itemName, zone, colorName, materialName) 보내면 config 기반 검증 후
-- <colorAttr>_<zone> / <materialAttr>_<zone> 속성에 저장.
-- 전용색(cfg.colors/colorOrder/colorOwnPrefix) 또는 공유 팔레트 자동 지원.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local palette = require(ReplicatedStorage:WaitForChild("NoobColorPalette"))
local remote = ReplicatedStorage:WaitForChild("ItemColorRemote")

local function isFreeColor(cfg, colorName)
	if cfg.colorOrder then
		for _, e in ipairs(cfg.colorOrder) do
			if e.k == colorName then return e.free end
		end
		return false
	end
	return palette.isFree(colorName)
end

local function isValidColor(cfg, colorName)
	local defs = cfg.colors or palette.COLORS
	return defs[colorName] ~= nil
end

local function ownsColor(player, cfg, colorName)
	if isFreeColor(cfg, colorName) then return true end
	local prefix = cfg.colorOwnPrefix or "NoobColor"
	return player:GetAttribute("Has_" .. prefix .. "_" .. colorName) and true or false
end

remote.OnServerEvent:Connect(function(player, itemName, zone, colorName, materialName)	-- ⚠️ [ROUND-LOCK] 라운드 중에는 변경 불가. UI 를 닫는 것만으론 부족하다 —
	--    리모트는 클라에서 직접 호출할 수 있으므로 서버가 최종 방어선이다.
	--    (실측 2026-08-21: 라운드 중 인벤에서 바꾸면 실시간 반영됨)
	do
		local _ph = game:GetService("ReplicatedStorage"):GetAttribute("RoundPhase")
		if _ph == "stage1" or _ph == "stage2" then return end
	end
	if type(itemName) ~= "string" or type(zone) ~= "string" then return end
	local cfg = palette.getConfig(itemName)
	if not cfg then return end
	-- 전체 리셋: 모든 zone 색/재질 속성 제거 → 원본(커스텀 해제) 복귀
	if zone == "__RESET_ALL__" then
		for _, z in ipairs(cfg.zones) do
			player:SetAttribute(cfg.colorAttr .. "_" .. z, nil)
			if cfg.materialAttr then
				player:SetAttribute(cfg.materialAttr .. "_" .. z, nil)
			end
		end
		return
	end
	-- zone 검증
	local validZone = false
	for _, z in ipairs(cfg.zones) do if z == zone then validZone = true; break end end
	if not validZone then return end
	-- 색 검증 + 보유
	if type(colorName) == "string" and isValidColor(cfg, colorName) and ownsColor(player, cfg, colorName) then
		player:SetAttribute(cfg.colorAttr .. "_" .. zone, colorName)
	end
	-- 재질 검증 (재질 지원 아이템만)
	if cfg.materialAttr and type(materialName) == "string" and palette.isValidMaterial(itemName, materialName) then
		player:SetAttribute(cfg.materialAttr .. "_" .. zone, materialName)
	end
end)

print("✅ ItemColorServer 준비 (범용 색+재질, 전용색 지원)")
