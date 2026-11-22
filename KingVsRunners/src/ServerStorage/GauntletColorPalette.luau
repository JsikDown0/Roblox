-- 건틀렛 컬러 커스텀 팔레트 + 부위별 색 적용 로직 (공용 모듈)
-- 부위는 각 파트의 SkinZone 속성(Body/Point/Handle)으로 판별 → 색을 몇 번 바꿔도 안전.

local M = {}

-- 텍스처 마감(예: gold)이 각 파트 면에 입히는 데칼 이름/면 목록. 색 변경 시 이름으로 찾아 제거.
local SKIN_DECAL_NAME = "_GauntletSkinDecal"
local SKIN_FACES = { Enum.NormalId.Top, Enum.NormalId.Bottom, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Front, Enum.NormalId.Back }

-- ── 색 팔레트 (이름 → Color3) ──
-- 기본 6색(무료) + 유료색. UI/해금은 이 이름 키를 인덱스로 사용.
-- 주의: 일부 색은 PALETTE에 없는 특수 처리(아래 SPECIAL / FINISH 참고).
M.PALETTE = {
	-- 기본 6색
	black  = Color3.fromRGB(20, 20, 20),
	white  = Color3.fromRGB(245, 245, 245),
	gray   = Color3.fromRGB(120, 125, 130),
	navy   = Color3.fromRGB(27, 42, 53),    -- 원본 몸체색
	beige  = Color3.fromRGB(254, 243, 187), -- 원본 핸들색 (#fef3bb)
	orange = Color3.fromRGB(170, 85, 0),    -- 원본 포인트색
	-- 유료 4색
	pink   = Color3.fromRGB(255, 80, 180),
	red    = Color3.fromRGB(220, 30, 30),
	cyan   = Color3.fromRGB(0, 200, 220),
	purple = Color3.fromRGB(160, 60, 255),
	-- 추가 유료 단일색
	lime    = Color3.fromRGB(80, 230, 60),
	emerald = Color3.fromRGB(0, 150, 90),
	yellow  = Color3.fromRGB(255, 225, 40),
	royal   = Color3.fromRGB(40, 90, 230),
	crimson = Color3.fromRGB(150, 15, 30),
}

-- ── 특수 색 두 종류 ──
-- SPECIAL: 효과색(정적 Color3 아님). 매 프레임 순환 등 → applyZoneColors는 건너뛰고
--          GauntletScript의 별도 루프가 처리. (예: rainbow)
M.SPECIAL = { rainbow = true }

-- FINISH: 마감재 색(정적이지만 색+재질+반사를 묶어서 적용). 루프 불필요.
--         applyZoneColors가 Color/Material/Reflectance를 한 번에 칠함.
--         (gold = 직접 만든 브러시드 골드 텍스처 데칼 + SmoothPlastic + 약한 반사.
--          texture 필드가 있으면 applyZoneColors가 각 면에 데칼을 래핑. SmoothPlastic이라 광원 변화에 색이 안정적.)
M.FINISH = {
	gold = {
		color = Color3.fromRGB(238, 200, 95),       -- 데칼 안 닿는 모서리용 베이스(면은 데칼이 덮음)
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.08,
		texture = "rbxassetid://138973318266736",   -- 직접 만든 브러시드 골드(6면 래핑)
	},
	silver = {
		color = Color3.fromRGB(220, 222, 228),       -- 데칼 안 닿는 모서리용 베이스(면은 데칼이 덮음)
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.08,
		texture = "rbxassetid://112079548029936",   -- 직접 만든 브러시드 실버(6면 래핑)
	},
	bronze = {
		color = Color3.fromRGB(175, 120, 70),        -- 데칼 안 닿는 모서리용 베이스(면은 데칼이 덮음)
		material = Enum.Material.SmoothPlastic,
		reflectance = 0.08,
		texture = "rbxassetid://113929307685125",   -- 직접 만든 브러시드 브론즈(6면 래핑)
	},
}

-- 기본(무료) 색 목록 — 모든 플레이어가 기본 보유
M.FREE_COLORS = { "black", "white", "gray", "navy", "beige", "orange" }
-- 유료/해금 색 목록 (rainbow = 효과색, gold = 마감재색)
M.PAID_COLORS = { "pink", "red", "cyan", "purple", "lime", "emerald", "yellow", "royal", "crimson", "rainbow", "gold", "silver", "bronze" }

-- 원본(기본) 부위별 색 — 커스텀 안 했을 때의 디폴트
M.DEFAULT_ZONE = {
	Body   = "navy",
	Point  = "orange",
	Handle = "beige",
}

-- 부위별 "원래 재질" — 정적 색 적용 시 이 재질로 복원.
-- (무지개/금색이 부위 재질을 바꿔놨다가 일반색으로 돌아올 때, 효과가 남지 않도록 복원 필수)
M.ZONE_MATERIAL = {
	Body   = Enum.Material.SmoothPlastic,  -- 무광 몸체
	Point  = Enum.Material.Neon,           -- 포인트는 원래 발광
	Handle = Enum.Material.Plastic,        -- 손잡이
}

-- 색 이름이 유효한가(정적 팔레트 색 / 효과색 / 마감재색)
function M.isValidColor(name)
	if type(name) ~= "string" then return false end
	return (M.PALETTE[name] ~= nil) or (M.SPECIAL[name] == true) or (M.FINISH[name] ~= nil)
end

-- 부위별 색 적용 (SkinZone 태그 기반)
-- zoneColors = { Body="white", Point="gold", Handle="navy" } (색 이름)
-- 처리 규칙:
--   · 정적 팔레트색 → Color + 부위 기본재질 + 반사0
--   · FINISH(gold)  → Color + 지정 재질 + 지정 반사 (한 번 칠하면 끝, 루프 불필요)
--   · SPECIAL(rainbow) → 건너뜀 (GauntletScript 루프가 색/재질 처리)
--   · nil/미지정 부위 → 건드리지 않음
function M.applyZoneColors(model, zoneColors)
	if not model then return end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local zone = p:GetAttribute("SkinZone")
			if zone then
				local colorName = zoneColors[zone]
				if colorName then
					-- 이전 스킨 데칼 정리(색 바꿀 때 텍스처 잔존/중복 방지)
					for _, ch in ipairs(p:GetChildren()) do
						if ch:IsA("Decal") and ch.Name == SKIN_DECAL_NAME then ch:Destroy() end
					end
					local finish = M.FINISH[colorName]
					if finish then
						-- 마감재(금색 등): 색 + 재질 + 반사 묶음
						p.Color = finish.color
						p.Material = finish.material
						p.Reflectance = finish.reflectance or 0
						-- 텍스처 마감이면 6면에 데칼 래핑(예: gold 브러시드 골드)
						if finish.texture then
							for _, f in ipairs(SKIN_FACES) do
								local d = Instance.new("Decal")
								d.Name = SKIN_DECAL_NAME
								d.Texture = finish.texture
								d.Face = f
								d.Parent = p
							end
						end
					elseif not M.SPECIAL[colorName] then
						-- 정적 색: 색 + 부위 기본재질, 반사는 0으로 복원
						local col = M.PALETTE[colorName]
						if col then
							p.Color = col
							local mat = M.ZONE_MATERIAL[zone]
							if mat then p.Material = mat end
							p.Reflectance = 0
						end
					end
					-- SPECIAL(rainbow)은 여기서 아무것도 안 함(루프가 처리)
				end
			end
		end
	end
end

-- 플레이어의 저장된 색 선택을 읽어 zoneColors 테이블로 반환(미설정 부위는 기본색)
function M.getPlayerZoneColors(player)
	local function pick(attr, default)
		local v = player:GetAttribute(attr)
		if v and M.isValidColor(v) then return v end
		return default
	end
	return {
		Body   = pick("GauntletColor_Body",   M.DEFAULT_ZONE.Body),
		Point  = pick("GauntletColor_Point",  M.DEFAULT_ZONE.Point),
		Handle = pick("GauntletColor_Handle", M.DEFAULT_ZONE.Handle),
	}
end

return M
