-- 아이템 색/재질(마감) 커스텀 팔레트 (클라 UI + 서버 적용/저장 공유)
-- 색(hue)은 모든 아이템 공유. 마감(finish)=재질+선택적 색조(tint). 부위/마감 세부는 M.ITEMS[아이템명] config로 정의.
local M = {}

-- ===== 공유 색 팔레트 (hue) =====
M.COLORS = {
	-- 기본색 (무료): 베이스 누비색 + 무채색
	NoobYellow = Color3.fromRGB(245,205,48),
	NoobBlue   = Color3.fromRGB(13,105,172),
	NoobGreen  = Color3.fromRGB(164,189,71),
	White = Color3.fromRGB(245,245,245),
	Gray  = Color3.fromRGB(120,125,130),
	-- 프리셋 7색
	Red    = Color3.fromRGB(225,40,40),
	Orange = Color3.fromRGB(255,105,15),
	Yellow = Color3.fromRGB(255,225,30),
	Green  = Color3.fromRGB(70,200,70),
	Blue   = Color3.fromRGB(40,120,255),
	Indigo = Color3.fromRGB(80,60,200),
	Violet = Color3.fromRGB(170,70,220),
	-- 기존 색 스킨 재현용
	Pink  = Color3.fromRGB(255,105,180),
	Black = Color3.fromRGB(30,30,38),
}

M.ORDER = {
	{k="NoobYellow", name="NOOB YELLOW", free=true, noobOnly=true},
	{k="NoobBlue",   name="NOOB BLUE",   free=true, noobOnly=true},
	{k="NoobGreen",  name="NOOB GREEN",  free=true, noobOnly=true},
	{k="Red",    name="RED",    free=false},
	{k="Orange", name="ORANGE", free=false},
	{k="Yellow", name="YELLOW", free=false},
	{k="Green",  name="GREEN",  free=false},
	{k="Blue",   name="BLUE",   free=false},
	{k="Indigo", name="INDIGO", free=false},
	{k="Violet", name="VIOLET", free=false},
	{k="Pink",   name="PINK",   free=false},
	{k="White",  name="WHITE",  free=true},
	{k="Black",  name="BLACK",  free=false},
	{k="Gray",   name="GRAY",   free=true},
}

M.FREE_COLORS = {"NoobYellow","NoobBlue","NoobGreen","White","Gray"}

-- ===== 공유 마감(finish): 로블록스 Material + 선택적 tint =====
-- tint가 있으면 선택 hue를 덮어씀(금/은처럼 색이 고정인 금속 마감).
M.FINISHES = {
	MATTE  = { material = "SmoothPlastic" },
	METAL  = { material = "Metal" },
	NEON   = { material = "Neon" },
	GLASS  = { material = "Glass" },
	STONE  = { material = "Slate" },
	WOOD   = { material = "Wood" },
}

-- 마감 적용 (모든 페인트 지점 공유). baseColor=선택 hue. 마감 tint 있으면 우선.
function M.applyFinish(part, finishKey, baseColor)
	local f = M.FINISHES[finishKey]
	if not f then
		if baseColor then part.Color = baseColor end
		return
	end
	part.Material = Enum.Material[f.material] or part.Material
	part.Color = f.tint or baseColor
	if part:IsA("MeshPart") then
		part.TextureID = ""  -- 단색 마감: 텍스처 제거(발광/금속 살림)
	end
	local sa = part:FindFirstChildWhichIsA("SurfaceAppearance")
	if sa then sa:Destroy() end  -- PBR 텍스처(Tsar Bomba 등) 제거 → 단색/발광이 보이게
	local sm = part:FindFirstChildWhichIsA("SpecialMesh")
	if sm then
		sm.TextureId = ""                      -- SpecialMesh(ClassicSword 등) 텍스처 제거
		sm.VertexColor = Vector3.new(1, 1, 1)  -- 색조 곱 리셋(Part.Color 그대로 보이게)
	end
end

-- ===== 아이템별 설정 =====
-- zones: 부위 / zoneParts: 부위→파트이름(모델형) / singlePart=true: 단일 파트
-- zoneDefault: 부위별 기본색 / materials: 마감 키 목록(nil이면 마감 커스텀 없음)
M.ITEMS = {
	ItemNoob = {
		zones = {"Head", "Torso", "Arms", "Legs"},
		zoneParts = {
			Head  = {"Head"},
			Torso = {"Torso"},
			Arms  = {"Left Arm", "Right Arm"},
			Legs  = {"Left Leg", "Right Leg"},
		},
		zoneDefault = { Head="NoobYellow", Torso="NoobBlue", Arms="NoobYellow", Legs="NoobGreen" },
		materials = nil,  -- 마감 커스텀 없음
		colorAttr = "NoobColor",
		colorOwnPrefix = "NoobColor",
		materialAttr = nil,
		hideColors = { Black = true },  -- 캐릭터 피부 → 검정 제외(인종 민감)
		isNoob = true,  -- 뉴비 전용 색(noobOnly 플래그)을 노출하는 유일한 아이템
	},
	Spear = {
		zones = {"Blade"},
		singlePart = true,
		previewLookDir = {0, 0.3, 1},  -- 회전 끄고 넓은 면 정면 고정 (F5 튜닝)
		zoneDefault = { Blade = "Gray" },
		materials = {"MATTE", "METAL", "NEON"},
		materialDefault = "METAL",
		colorAttr = "SpearColor",
		colorOwnPrefix = "SpearColor",
		materialAttr = "SpearMaterial",
	},
	stone = {
		zones = {"Rock"},
		singlePart = true,
		zoneDefault = { Rock = "Gray" },
		materials = {"STONE", "MATTE", "METAL", "NEON"},
		materialDefault = "STONE",
		colorAttr = "StoneColor",
		colorOwnPrefix = "StoneColor",
		materialAttr = "StoneMaterial",
		previewDistScale = 1.2,
	},
	PushTool = {
		zones = {"Fist"},
		zoneParts = { Fist = {"Handle"} },  -- Handle(글러브 본체)만 색칠, 자식 디테일은 회색 유지
		zoneDefault = { Fist = "White" },
		materials = {"MATTE", "METAL", "NEON"},
		materialDefault = "NEON",  -- 발광 글러브가 기본
		colorAttr = "PushColor",
		colorOwnPrefix = "PushColor",
		materialAttr = "PushMaterial",
	},
	ClassicSword = {
		zones = {"Blade"},
		singlePart = true,  -- Handle(Part + SpecialMesh) 하나
		previewRotate = true,  -- 프리뷰 회전(singlePart라도)
		zoneDefault = { Blade = "Red" },
		materials = {"MATTE", "METAL", "NEON"},
		materialDefault = "NEON",  -- 색놀이 검은 네온 발광이 기본
		colorAttr = "ClassicColor",
		colorOwnPrefix = "ClassicColor",
		materialAttr = "ClassicMaterial",
	},
	KatanaSword2 = {
		zones = {"Blade"},
		paintTagged = true,  -- SkinPaintPart 태그된 파트만 색칠(어두운 칼날/장식, 금장식·손잡이 유지)
		zoneDefault = { Blade = "Red" },
		materials = {"MATTE", "METAL", "NEON"},
		materialDefault = "METAL",
		colorAttr = "KatanaColor",
		colorOwnPrefix = "KatanaColor",
		materialAttr = "KatanaMaterial",
	},
	HammerLow = {
		zones = {"Head"},
		singlePart = true,  -- Handle(Part + SpecialMesh) 망치 본체 (스핀 이펙트는 HammerScript가 런타임 처리)
		previewRotate = true,  -- 망치라 직선(upright) 대신 회전 프리뷰 (자루+머리 다 보이게)
		previewDistScale = 0.66,  -- 실시간 조정으로 확정
		previewYOffset = 0,
		previewPitch = 3.3,
		zoneDefault = { Head = "Red" },
		materials = {"MATTE", "METAL", "NEON"},
		materialDefault = "NEON",
		colorAttr = "HammerColor",
		colorOwnPrefix = "HammerColor",
		materialAttr = "HammerMaterial",
	},
	SakuraBlade = {
		zones = {"Blade"},
		vertexTint = true,  -- preview: SpecialMesh VertexColor 색조(텍스처 유지) + Metal + Reflectance (SwordScript 재현)
		hsvApply = true,    -- 적용: 색→HSV→SkinHue/Sat/Val 속성 (SwordScript가 칼날+오라 칠)
		zoneDefault = { Blade = "Pink" },
		materials = {"MATTE", "METAL"},
		materialDefault = "METAL",
		colorAttr = "SakuraColor",
		colorOwnPrefix = "SakuraColor",
		materialAttr = "SakuraMaterial",
	},
	HammerHigh = {
		zones = {"Head"},
		paintTagged = true,   -- SkinPaintPart 태그 파트(머리/금장식/손잡이)만
		hsvApply = true,      -- 적용: 색→HSV→SkinHue/Sat/Val (HammerHighScript가 본체+flame 칠)
		previewNeon = true,   -- preview: 태그 파트 Neon 발광 (실제 본체가 Neon)
		previewDistScale = 0.61,  -- 실시간 조정으로 확정
		previewYOffset = -0.6,
		previewPitch = -0.8,
		zoneDefault = { Head = "Orange" },
		materials = {"NEON"},  -- Neon 발광 고정 (flame hammer 정체성) — 탭에 1개만 표시
		materialDefault = "NEON",
		colorAttr = "FlameColor",
		colorOwnPrefix = "FlameColor",
		hideColors = { Pink = true },  -- Love Flame Hammer(전용 핑크 스킨)와 중복 → 커스텀 핑크 제외
		materialAttr = nil,
	},
	bear_trap = {
		zones = {"Trap"},
		zoneParts = { Trap = {"Open"} },  -- Open 파트만 색칠 (Close는 회색 고정)
		zoneDefault = { Trap = "Bronze" },
		materials = {"MATTE", "METAL", "GLASS", "NEON"},
		materialDefault = "METAL",
		colorAttr = "BTColor",
		colorOwnPrefix = "BTColor",
		materialAttr = "BTMaterial",
		colors = {  -- bear_trap 전용 14색
			Blue=Color3.fromRGB(40,110,235), Bronze=Color3.fromRGB(150,95,40), Cobalt=Color3.fromRGB(30,70,200),
			Crimson=Color3.fromRGB(200,20,20), DeepPurple=Color3.fromRGB(95,30,170), Emerald=Color3.fromRGB(15,145,85),
			Gold=Color3.fromRGB(255,200,40), Green=Color3.fromRGB(40,190,60), Obsidian=Color3.fromRGB(40,10,60),
			Orange=Color3.fromRGB(245,140,20), Red=Color3.fromRGB(230,30,30), Toxic=Color3.fromRGB(40,255,130),
			Violet=Color3.fromRGB(150,50,200), Yellow=Color3.fromRGB(245,225,30),
		},
		colorOrder = {
			{k="Bronze",name="BRONZE",free=true},
			{k="Blue",name="BLUE",free=false},
			{k="Cobalt",name="COBALT",free=false},
			{k="Crimson",name="CRIMSON",free=false},
			{k="DeepPurple",name="DEEP PURPLE",free=false},
			{k="Emerald",name="EMERALD",free=false},
			{k="Gold",name="GOLD",free=false},
			{k="Green",name="GREEN",free=false},
			{k="Obsidian",name="OBSIDIAN",free=false},
			{k="Orange",name="ORANGE",free=false},
			{k="Red",name="RED",free=false},
			{k="Toxic",name="TOXIC",free=false},
			{k="Violet",name="VIOLET",free=false},
			{k="Yellow",name="YELLOW",free=false},
		},
	},
	tsunami = {
		zones = {"Wave"},
		singlePart = true,
		zoneDefault = { Wave = "Blue" },        -- 물 테마 기본 파랑
		materials = {"MATTE", "NEON"},          -- 무광(물) / 발광(금색=Yellow+NEON 등)
		materialDefault = "MATTE",
		colorAttr = "TsunamiColor",
		colorOwnPrefix = "TsunamiColor",
		materialAttr = "TsunamiMaterial",
		previewLookDir = {0.3, 0.25, 1},  -- ITEM COLOR 프리뷰를 인벤 썸네일과 같은 비스듬 3/4 각도로
		previewDistScale = 2.2,           -- 인벤(2.8)보다 가까이 = 프리뷰 더 크게 보이게
	},
	tox_box = {
		zones = {"Steel"},                -- 1존: 청회(#1b2a35)+적갈(#7b2e2f)+빨강(#c4281c)을 한 색으로 통합 커스텀
		paintTagged = true,               -- SkinPaintPart 속성이 붙은 파트만 색칠 (흰색 제외)
		zoneDefault = { Steel = "Gray" }, -- UI 기본 하이라이트(미적용 시 원본 색 유지)
		materials = {"MATTE", "NEON"},    -- 무광 / 발광(금색=Yellow+NEON)
		materialDefault = "MATTE",
		colorAttr = "ToxColor",
		colorOwnPrefix = "ToxColor",
		materialAttr = "ToxMaterial",
		previewDistScale = 1.4,           -- 회전 프리뷰 카메라 거리(클수록 작게 보임, 기본 0.9)
	},
	tnt = {
		zones = {"Body"},
		singlePart = true,                -- 단일 MeshPart → 폭탄 전체 한 색
		zoneDefault = { Body = "Gray" },
		materials = {"MATTE", "NEON"},
		materialDefault = "MATTE",
		colorAttr = "BombColor",
		colorOwnPrefix = "BombColor",
		materialAttr = "BombMaterial",
		previewLookDir = {0.3, 0.25, 1},  -- 비스듬 3/4 각도(긴 메시)
		previewDistScale = 2.2,
	},
	["Wooden Barrel"] = {
		zones = {"Body", "Rings"},        -- 2존: 나무 본체 + 금속 링 각각 커스텀
		zoneParts = { Body = {"Body"}, Rings = {"Rings"} },
		zoneDefault = { Body = "Orange", Rings = "Blue" },  -- 기본: 나무색 톤 + 파란 링
		materials = {"WOOD", "MATTE", "METAL", "NEON"},     -- 나무 / 무광 / 금속(금색) / 발광
		materialDefault = "WOOD",
		colorAttr = "BarrelColor",
		colorOwnPrefix = "BarrelColor",
		materialAttr = "BarrelMaterial",
		previewLookDir = {0.3, 0.2, 1},   -- 인벤 썸네일과 같은 3/4 각도
		previewDistScale = 2.2,
	},
	Demonspear = {
		zones = {"Body"},
		singlePart = true,                 -- 본체 단일 MeshPart(Neon). Beam은 발사 시 서버에서 함께 틴트.
		previewRotate = true,              -- 프리뷰 회전(singlePart라도)
		zoneDefault = { Body = "Red" },
		materials = {"MATTE", "NEON"},
		materialDefault = "NEON",          -- 데몬 스피어는 발광이 기본
		colorAttr = "DemonColor",
		colorOwnPrefix = "DemonColor",
		materialAttr = "DemonMaterial",
		beamTint = true,                   -- Beam ColorSequence를 본체색으로 틴트(검정 keypoint 유지)
		previewDistScale = 1.3,            -- 작을수록 크게 보임 (F5 튜닝)
	},
}

-- ===== 하위호환 (기존 뉴비 직접 참조 — 점진 제거 예정) =====
M.ZONE_PARTS   = M.ITEMS.ItemNoob.zoneParts
M.ZONES        = M.ITEMS.ItemNoob.zones
M.ZONE_DEFAULT = M.ITEMS.ItemNoob.zoneDefault

-- ===== 접근자 =====
function M.getConfig(itemName)
	return M.ITEMS[itemName]
end

function M.isValidColor(name)
	return M.COLORS[name] ~= nil
end

function M.isFree(name)
	for _, c in ipairs(M.FREE_COLORS) do
		if c == name then return true end
	end
	return false
end

function M.isValidMaterial(itemName, mat)
	local cfg = M.ITEMS[itemName]
	if not cfg or not cfg.materials then return false end
	for _, m in ipairs(cfg.materials) do
		if m == mat then return true end
	end
	return false
end

return M
