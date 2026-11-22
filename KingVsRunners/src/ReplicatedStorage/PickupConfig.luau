-- PickupConfig — Hill 아이템 픽업 시스템의 공유 상수/아이템 테이블/헬퍼.
-- 서버와 클라가 require 가능 (현재는 서버만 사용)

local Config = {}

-- ════════════ 타이밍 ════════════
Config.SPAWN_START_DELAY    = 3      -- 라운드 시작 후 첫 스폰까지 대기 (초)
Config.INITIAL_BURST_COUNT  = 3      -- 첫 스폰 시 한꺼번에 깔리는 픽업 개수
Config.REPLENISH_INTERVAL   = 8      -- 초기 버스트 이후 보충 픽업 주기 (초, 1개씩)
Config.MAX_ACTIVE_PICKUPS   = 5      -- 맵에 동시 존재 가능한 최대 픽업 수 (캡 도달 시 보충 스킵)
Config.PICKUP_HOLD_DURATION = 0.5    -- E키 차징 시간 (초)

-- ════════════ 스폰 위치 검증 ════════════
Config.MIN_PICKUP_DISTANCE  = 20     -- 픽업들 간 최소 거리 (stud) — ProximityPrompt 활성화 거리(8) + 시각 마진
Config.MAX_SPAWN_RETRIES    = 5      -- 위치 충돌 시 재시도 횟수 (전부 실패하면 이번 틱 스킵)

-- ════════════ 위치 (불벽 기준) ════════════
Config.AHEAD_MIN       = 200         -- 불벽 앞 최소 거리 (위험 띠)
Config.AHEAD_MAX       = 600         -- 불벽 앞 최대 거리 (안전 띠 끝)
Config.PICKUP_Y_OFFSET = 3.5         -- 지면 위로 띄움

-- ════════════ Hill 영역 (FirePressureSystem이 _G.MapGeometry로 공유) ════════════
-- 픽업은 고정 좌표 대신, 불벽이 현재 맵에서 계산한 geometry를 읽는다.
-- _G.MapGeometry 가 아직 없으면(라운드 시작 전 등) map1 값으로 폴백.
local MAP1_FALLBACK = {
	hillXMin = -199.5, hillXMax = 702.5,
	hillYRange = 122,  hillBaseY = 0,
	zCenter  = -675,   zWidth = 230,
	startX   = -259.5, endX = 685,
}
function Config.GetGeometry()
	return _G.MapGeometry or MAP1_FALLBACK
end

-- ════════════ 인터랙션 ════════════
Config.MAX_ACTIVATION_DISTANCE = 8   -- ProximityPrompt 반응 거리 (stud)

-- ════════════ 비주얼 ════════════
Config.LIGHT_BEAM_HEIGHT = 100
Config.LIGHT_BEAM_COLOR  = Color3.fromRGB(255, 255, 255)  -- 흰색
Config.ORB_SIZE          = 3                              -- 오브 지름
Config.ORB_COLOR         = Color3.fromRGB(255, 255, 255)

-- ════════════ 궤도 트레일 구체 (픽업 주변을 직교 궤도로 도는 작은 흰 구 2개) ════════════
Config.ORBITER_SIZE      = 0.6                            -- 궤도 구체 지름
Config.ORBITER_COLOR     = Color3.fromRGB(255, 255, 255)  -- 흰색
Config.ORBIT_RADIUS      = 3                              -- 중심으로부터 거리 (오브 크기 + 약간)
Config.ORBIT_SPEED       = 4                              -- 각속도 (rad/sec, 한 바퀴 ≈ 1.57s)
Config.TRAIL_LIFETIME    = 0.5                            -- 트레일 잔상 지속 (초)
Config.TRAIL_WIDTH       = 0.6                            -- 트레일 굵기 (시작 기준 stud)

-- ════════════ 체스트 애니메이션 ════════════
Config.CHEST_TEMPLATE_NAME      = "Item Chest"            -- ServerStorage 안 모델명
Config.CHEST_OPEN_DURATION      = 1                       -- 뚜껑 열림 트윈 시간 (초)
Config.CHEST_OPEN_ANGLE_DEG     = 110                     -- 뚜껑 회전 각도 (양수/음수로 방향 조절)
Config.CHEST_VISUAL_CENTER_Y    = 1.5                     -- 체스트 root 기준 시각 중심 Y 오프셋 (궤도 구체 중심)

-- ════════════ 체스트 내부 오브 (뚜껑 열렸을 때 보이는 전리품 비주얼) ════════════
Config.INNER_ORB_SIZE  = 1.2                              -- 내부 오브 지름
Config.INNER_ORB_COLOR = Color3.fromRGB(255, 255, 255)    -- 아이템 체스트 (흰색)
Config.COIN_ORB_COLOR  = Color3.fromRGB(255, 215, 0)      -- 코인 체스트 (황금색)
Config.INNER_ORB_Y_RATIO = 0.3                            -- WoodBottom 사이즈 기준 위쪽 오프셋 비율 (0 = 중심, 0.5 = top)

-- ════════════ 코인 보상 (아이템 대신 코인 드롭) ════════════
-- 박스 트리거 시 일정 확률로 아이템 대신 코인을 지급.
-- 평균 라운드당 ~1.2개의 코인 박스 (30% × 4 박스 픽업 가정) → 라운드당 ~12 코인 보조.
-- 기본 라운드 보상 (15~30) 대비 50% 보강 정도, 메인 코인 소스가 되지는 않게 설계.
Config.COIN_DROP_CHANCE  = 0.40   -- 0~1 사이. 0.40 = 40% 확률로 코인 보상
Config.COIN_REWARD_AMOUNT = 10    -- 코인 보상시 지급 코인 (고정값)

-- ════════════ 고급 상자 (Rare Chest) ════════════
-- 일반 박스 스폰 시 RARE_SPAWN_CHANCE 확률로 Item Chest 대신 Rare Chest로 대체.
-- 보상: 랜덤 스킨 1개(영구) + 랜덤 아이템 1개(즉시 인벤). 스킨을 다 모았으면 스킨 칸만 코인 폴백.
Config.RARE_SPAWN_CHANCE        = 0.05         -- 5% (일반 박스 95%). 테스트 시 1.0으로 올렸다 복원
Config.RARE_CHEST_TEMPLATE_NAME = "RareChest" -- ServerStorage 안 모델명
Config.RARE_FALLBACK_COIN       = 50           -- 스킨 다 모았을 때 스킨 칸 대신 줄 코인 (rare라 일반보다 후하게)

-- ════════════ 사운드 (클라가 입장 시 프리로드 → 첫 재생 지연 방지) ════════════
Config.SOUND_OPEN_NORMAL = "rbxassetid://116841971399984"  -- 일반 상자 열림
Config.SOUND_OPEN_RARE   = "rbxassetid://100791117505114"  -- 고급 상자 열림

-- ════════════ 아이템 테이블 ════════════
-- name 은 ServerStorage.RunnerItem 안의 Tool 이름과 정확히 일치해야 함
--
-- 🎁 [밸런스 2026-08-29] weight 를 상점 등급의 '역순'으로 재배분했다.
--   [문제] Speed Potion 30(34%) + Wood Shield 20(23%) = 두 종이 57% 를 차지했다.
--     그런데 Speed Potion 은 Rare(200코인) 로 올릴 예정이라,
--     "가장 비싼 축인데 3판에 한 번 공짜로 나오는" 상태가 된다 → 상점 수요를 직접 깎는다.
--   [원칙] 싼 건 자주, 비싼 건 드물게. 등급이 곧 희소성이 되게 한다.
--   ⚠️ [2026-08-23] 패치로 코인 상자에서도 아이템이 '항상' 나온다.
--     COIN_DROP_CHANCE 는 이제 "코인이 추가로 얹힐 확률"이지 아이템 대체 확률이 아니다.
--     즉 스폰된 상자 수 = 아이템 지급 수다. weight 구성이 곧 공급 구성이다.
--   ⚠️ 총량(REPLENISH_INTERVAL/MAX_ACTIVE_PICKUPS)은 건드리지 않았다.
--     픽업 아이템은 라운드 종료와 함께 사라져 재고가 남지 않으므로
--     경제에 미치는 영향이 제한적이다. 총량은 '라운드 중 밀도' 문제라 플레이로 판단할 것.
Config.ITEM_TABLE = {
	-- Normal (상점 150) — 가장 흔하게
	{ name = "Wood Shield",  weight = 20 },
	{ name = "Gas Grenade",  weight = 20 },
	-- Rare (상점 200)
	{ name = "Speed Potion", weight = 12 },
	{ name = "Decoy Wand",   weight = 12 },
	-- Epic (상점 300)
	{ name = "RevivalFlag",  weight = 8  },
	{ name = "Mic Bomb",     weight = 8  },
	-- Legendary (상점 400) — 가장 드물게
	{ name = "Ice Bow",      weight = 5  },
	{ name = "ODM Gear",     weight = 5  },
}

-- 무게 합 기반 가중치 추첨
function Config.PickRandomItem()
	local total = 0
	for _, e in ipairs(Config.ITEM_TABLE) do total = total + e.weight end
	local r = math.random() * total
	local sum = 0
	for _, e in ipairs(Config.ITEM_TABLE) do
		sum = sum + e.weight
		if r <= sum then return e.name end
	end
	return Config.ITEM_TABLE[1].name
end

-- Hill 슬로프 표면의 절대 Y 위치 (불벽 geometry 기반, X에 선형 비례)
function Config.GetHillSurfaceY(x)
	local g = Config.GetGeometry()
	local t = math.clamp((x - g.hillXMin) / (g.hillXMax - g.hillXMin), 0, 1)
	return g.hillBaseY + t * g.hillYRange
end

return Config
