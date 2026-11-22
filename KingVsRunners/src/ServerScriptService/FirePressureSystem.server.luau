-- 불기둥 압박 시스템: 여러 불기둥이 전진 + 그을림 흔적
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local startEvent = ReplicatedStorage:WaitForChild("StartFirePressure")
local stopEvent = ReplicatedStorage:WaitForChild("StopFirePressure")

-- 설정
local DELAY = 10  -- 라운드 시작 후 불기둥 발생까지 대기 (초)
local SPEED = 10             -- 기본 이속보다 느리게
local START_X = -260
local END_X = 685             -- ItemSpawnPlate(시작 X≈687.76) 직전에서 멈춤
-- ⚡ 성능: 불기둥이 지나간 뒤쪽 영역의 태거 아이템 정리 (라운드 중 누적 부하 방지).
--   불기둥 뒤(X < newX - 마진)는 러너가 이미 통과/사망한 죽은 영역 → 그곳 아이템은 물리 부하만 됨.
--   마진을 둬서 불기둥 바로 뒤(경계)는 안 건드리고 충분히 지나간 곳만 제거.
local CLEANUP_MARGIN = 60     -- 불기둥 뒤 이 거리(stud) 너머의 아이템만 정리 (경계 여유)
local CLEANUP_INTERVAL = 2    -- 정리 주기(초) — 매 프레임 X 과부하 방지
local WALL_Z_LEFT = -535
local WALL_Z_RIGHT = -808
local FIRE_Z_CENTER = (WALL_Z_LEFT + WALL_Z_RIGHT) / 2
local FIRE_WIDTH = math.abs(WALL_Z_LEFT - WALL_Z_RIGHT)
local PILLAR_COUNT = 18       -- 불기둥 개수
local PILLAR_SPACING = FIRE_WIDTH / (PILLAR_COUNT + 1)
-- ═══════════════════════════════════════════════════════════════
-- 🔥 [지대 방식 2026-08-23] 즉사 → 지속 데미지
--
-- [이전] 불기둥에 Touched 로 닿으면 즉사(KILL_DAMAGE 200).
--   문제 1: 한 번의 실수로 라운드가 끝나 저연령층에게 가혹했다.
--   문제 2: 2단계에서 불기둥이 꺼지면 압박이 사라져 러너가 가만히 있어도 됐다.
--           (시간 초과가 러너 승리라 그게 최선이 되어버림)
--   문제 3: 불기둥이 지나간 '뒤쪽'은 안전해서, 벽이 지나가도 뒤에서 노는 러너가 생겼다.
--
-- [현재] 불기둥 X 보다 뒤(작은 X)는 전부 위험지대. 그 안에 있으면 초당 데미지.
--   · 즉사가 없어 밀려 들어가도 빠져나올 여지가 있다
--   · 뒤쪽 전체가 지대라 "지나갔으니 안전"이 사라진다
--   · 태거가 밀어 넣어도 처치가 아니라 견제라, 2단계에 유지해도 원콤이 안 생긴다
--
-- ⚠️ 이 게임은 자동 체력 회복이 꺼져 있다(StarterCharacterScripts.Health 가 빈 스크립트).
--    2026-08-23 도입 당시엔 지속 데미지가 '느린 즉사'가 되는 걸 막으려고
--    "지대를 벗어나면 회복" 을 함께 넣었다. 아래에서 그 회복을 껐다.
--
-- 🩹 [버그수정 2026-09-01] 지대 이탈 회복 비활성화 (ZONE_HEAL 6 → 0).
--   [증상] 2단계 교전 중에 러너 체력이 저절로 차올랐다.
--     실측 18:49 판 — 킹이 슬랩 15회 + 마법책 1회로 87 데미지를 넣었는데
--     유저 러너는 한 번도 안 쓰러졌고, 킹이 480 → 98 까지 깎여 타임아웃으로 겨우 이겼다.
--   [원인] zoneLastSafe[char] 는 '지대를 벗어난 순간' 한 번 찍히고 라운드 내내 안 지워진다.
--     피격으로 재시작하지도 않는다. 그래서 불기둥에 한 번이라도 스친 러너는
--     그 뒤로 피해 출처와 무관하게 초당 6 회복을 영구히 받았다.
--   [영향] 킹 강타 40뎀 / 쿨 7초 = 초당 5.7 < 회복 6.
--     쿨마다 100% 명중시켜도 러너를 못 죽인다 — 2단계 처치 경로가 수학적으로 닫혀 있었다.
--     배럴 웅덩이 틱뎀(10/s)도 실효 4/s 로 반토막나 있었다.
--   ⚠️ 킹은 홀드 라인 X=746, 불기둥 종점 X=716 이라 지대에 들어갈 일이 없다.
--     즉 이 회복은 사실상 러너 전용이었다(비대칭).
--   ⚠️ TAGGER_HEAL_PCT 가 ZONE_HEAL 에서 파생되므로 태거 쪽 회복도 같이 0 이 된다.
--   ⚠️ Roblox 기본 재생을 켜는 것으로 대신하면 안 된다. 태거 HP·부활 등 다른 시스템까지 영향.
--
-- 🔁 [2026-09-01 2차] 회복을 되살렸다 (0 → 6). 단 무제한 재생이 아니라 '부채 상환'이다.
--   [왜 되살렸나] 끄고 8라운드 실측하니, 2단계에서 tsunami 래그돌에 밀려난 러너가
--     정지한 압박선 뒤에 떨어져 그대로 탔다. 유저 사망 8건 중 3건이 이것이다.
--     22:01:01 건은 래그돌 6.6초 뒤 사망이고 15/s × 6.6 = 99 로 러너 최대 체력 100 과
--     일치한다 — HP 전량이 불기둥으로만 소진됐다는 뜻이다.
--     "지속 데미지가 느린 즉사가 된다"던 2026-08-23 의 원래 우려가 그대로 실현된 것.
--   [무엇이 달라졌나] 상한이 '시간'이 아니라 '부채'다. 근거는 zoneDebt 선언부 참조.
-- ═══════════════════════════════════════════════════════════════
local ZONE_DPS         = 15     -- 지대 안 초당 데미지
local ZONE_MARGIN      = 5      -- 불기둥 X 에서 이만큼 뒤부터 지대 (여유)
local ZONE_TICK        = 0.25   -- 판정 주기(초). 데미지는 이 간격에 비례 적용
local ZONE_HEAL        = 6      -- 지대 밖 초당 회복 '속도' (총량 상한은 zoneDebt 가 잡는다)
local ZONE_HEAL_DELAY  = 2.0    -- 지대를 벗어난 뒤 회복 시작까지 대기

-- 👑 [2026-08-28] 태거도 압박 지대에서 피해를 받는다.
--   [왜] 압박선이 계단을 넘어와도 태거는 무피해라, 성 안에서 버티는 캠핑이
--     아무 대가 없이 성립했다.
--   [왜 고정수치가 아니라 %인가] 태거 최대HP 가 러너 수에 따라 150~825 로 5.5배 변한다.
--     고정 15 를 주면 150 짜리 태거는 10초 만에 죽고 825 짜리는 55초를 버틴다.
--     같은 압박이 같게 느껴지려면 비율이어야 한다.
--   [기준선] 러너는 ZONE_DPS 15 / 최대HP 100 = 초당 15%. 즉 6.7초 만에 죽는다.
--     태거는 부활이 없고 죽으면 그대로 라운드가 끝나므로, 러너와 같은 비율을 주면
--     캠핑 억제가 아니라 사형선고가 된다 — 반드시 러너보다 훨씬 낮아야 한다.
--   ⚠️ 회복은 러너와 '같은 비율'로 유도한다(러너 회복 6 / 피해 15 = 40%).
--     피해율만 바꾸면 회복이 자동으로 따라오므로 둘이 어긋나지 않는다.
--
-- 🔻 [밸런스 2026-08-31] 8% → 2% 대폭 하향 (12.5초 → 50초).
--   [실측] map1 한 판에서 킹이 물벽에 타 죽었다(18:53:06~10, 4.2초에 17틱 323딜).
--     2단계 전체 피해의 37%가 물벽이었고, 막타도 물벽이라 creator 태그가 없어
--     "KING 처치됨 (막타 불명)"으로 끝났다 — 킬 크레딧이 아무에게도 안 간다.
--   [왜 8%가 과했나] 이 값의 명분은 '성 안 캠핑 억제'인데, 실제로 타는 자리는
--     성 안이 아니라 계단(687.8~710.0)이다. 물벽 최대 피해 경계가 정확히 710 이다
--     (END_X = 계단끝 + GATE_APPROACH 5, edge = END_X - ZONE_MARGIN 5 → 상쇄).
--     그런데 계단은 캠핑 자리가 아니라 킹이 러너를 밀어 내리는 전방 작업 구역이다.
--     즉 정상 플레이를 벌하고 있었다.
--   [왜 0 이 아닌가] 불타는 연출이 켜져 있는데 무피해면 그림이 어색하다.
--     2% = 50초라 "끝까지 눌러앉으면 결국 죽는다"는 억제력은 남는다.
--     물벽이 계단에 닿는 건 라운드 T+107초 무렵이고 종료까지 73초 남으므로,
--     정말 계속 서 있으면 라운드 안에 죽는다. 잠깐 다녀오는 건 5초에 10% 로 싸다.
--   ⚠️ 이건 대증요법이다. 진짜 원인은 봇에 위치 하한이 없다는 것 —
--     holdLineX 는 +X 상한만 걸고, 의도된 자리(성문 741, 경계보다 31 stud 위)를
--     벗어나 계단까지 내려가는 걸 막지 않는다. 하한을 붙이면 이 값은 거의 안 쓰인다.
--   ⚠️ TTK 측정 오염도 이유다. 목표 TTK 30초인데 8% 면 킹이 10초만 지대에 있어도
--     최대HP 80% 가 날아가, 러너 화력 측정이 통째로 왜곡된다.
--   ⚠️ TAGGER_HEAL_PCT 가 이 값에서 파생되므로 회복도 3.2%/초 → 0.8%/초 로 같이 내려간다.
--     비율(40%)은 그대로라 의도된 동작이다. 회복만 따로 만지지 말 것.
local TAGGER_ZONE_PCT = 0.02                                   -- 최대HP의 2%/초 → 50초
local TAGGER_HEAL_PCT = TAGGER_ZONE_PCT * (ZONE_HEAL / ZONE_DPS)
local POST_STOP_VISUAL_DELAY = 3.5  -- 정지 신호 후 시각 효과 정리까지 지연 (RoundSystem의 결과 메시지 wait(3) + 텔레포트 여유분)

-- 그을림 흔적 설정 (Hill 표면에 맞춰 배치)
local HILL_X_MIN = -199.5
local HILL_X_MAX = 702.5
local HILL_Y_RANGE = 122
local SLOPE_ANGLE_RAD = math.atan(HILL_Y_RANGE / (HILL_X_MAX - HILL_X_MIN))
local SCORCH_Z_CENTER = -674.5     -- Hill 의 z 중심
local SCORCH_WIDTH = 242           -- Hill 의 좌우폭과 정확히 매칭
local SCORCH_THICKNESS = 0.2
local SCORCH_SURFACE_OFFSET = 0.15 -- Z-fighting 방지용 살짝 띄움
local SCORCH_TRANSPARENCY = 0.05   -- 거의 불투명하지만 살짝 풀이 비치게

-- ===== 맵 확장 리팩토링 =====
-- 위 좌표(START_X, END_X, WALL_Z_*, HILL_*, SCORCH_* 등)는 map1 초기값일 뿐이고,
-- computeGeometry가 라운드마다 현재 맵의 언덕에서 좌표를 계산해 upvalue로 덮어쓴다.
local START_MARGIN = 60      -- 불기둥 시작점은 언덕 낮은쪽보다 이만큼 뒤(stud)
-- ⚠️ 계단 끝에서 성문 쪽으로 얼마나 더 밀지. 성문 앞에 남길 여유는
--    이 값이 아니라 '계단 끝 + 이 값' 이 성문 앞면에 얼마나 가까운지로 정해진다.
--    map1: 계단 끝 710 + 5 = 715, 성문 726 → 11stud 여유
--    map2: 계단 끝 711 + 5 = 716, 성문 731 → 15stud 여유
local GATE_APPROACH = 5
local END_MARGIN = 17        -- 불기둥 정지점은 언덕 높은쪽보다 이만큼 앞 (ItemSpawnPlate 직전)
local FIRE_WIDTH_EXTRA = 28  -- 불기둥 분산 폭 = 언덕 폭 + 이 값 (가장자리 회피 차단)
local HILL_BASE_Y = 0        -- 언덕 낮은쪽 바닥의 절대 Y (map1=0, computeGeometry가 갱신)
local currentMapFolder = workspace:FindFirstChild("map1")  -- SetCurrentMap으로 갱신

-- 맵 폴더의 언덕(부피 최대 WedgePart)에서 진행범위/폭/경사를 자동 계산.
-- 새 맵 추가 시: 폴더에 경사 언덕(WedgePart)만 있으면 코드 수정 0으로 동작.
-- 전제(현재 모든 맵 공통): 진행축=월드X, 러너는 X증가 방향 진행, 언덕은 X가 클수록 높아짐.
local function computeGeometry(mapFolder)
    if not mapFolder then warn("[FirePressure] currentMap 폴더 없음"); return false end
    local hill, maxVol = nil, 0
    for _, c in ipairs(mapFolder:GetChildren()) do
        if c:IsA("WedgePart") then
            local v = c.Size.X * c.Size.Y * c.Size.Z
            if v > maxVol then maxVol = v; hill = c end
        end
    end
    if not hill then
        warn("[FirePressure] '" .. mapFolder.Name .. "'에 언덕(WedgePart) 없음 - 불꽃벽 생략")
        return false
    end
    local cf, size = hill.CFrame, hill.Size
    -- 언덕 각 로컬축의 월드 X/Z 정렬도로 진행축(월드X)·폭축(월드Z) 판별 (회전 무관)
    local axes = {
        {x = math.abs(cf.RightVector.X), z = math.abs(cf.RightVector.Z), len = size.X},
        {x = math.abs(cf.UpVector.X),    z = math.abs(cf.UpVector.Z),    len = size.Y},
        {x = math.abs(cf.LookVector.X),  z = math.abs(cf.LookVector.Z),  len = size.Z},
    }
    local ti = 1; if axes[2].x > axes[ti].x then ti = 2 end; if axes[3].x > axes[ti].x then ti = 3 end
    local wi = 1; if axes[2].z > axes[wi].z then wi = 2 end; if axes[3].z > axes[wi].z then wi = 3 end
    local travelLen, widthLen = axes[ti].len, axes[wi].len
    local center = cf.Position
    HILL_X_MIN = center.X - travelLen / 2
    HILL_X_MAX = center.X + travelLen / 2
    HILL_Y_RANGE = size.Y
    HILL_BASE_Y = center.Y - size.Y / 2
    SLOPE_ANGLE_RAD = math.atan(HILL_Y_RANGE / travelLen)
    local zCenter = center.Z
    SCORCH_Z_CENTER = zCenter
    SCORCH_WIDTH = widthLen
    FIRE_Z_CENTER = zCenter
    FIRE_WIDTH = widthLen + FIRE_WIDTH_EXTRA
    WALL_Z_LEFT = zCenter + FIRE_WIDTH / 2
    WALL_Z_RIGHT = zCenter - FIRE_WIDTH / 2
    PILLAR_SPACING = FIRE_WIDTH / (PILLAR_COUNT + 1)
    START_X = HILL_X_MIN - START_MARGIN
    -- 정지점: ItemSpawnPlate(이름에 itemspawnplate 포함) 시작 직전. 없으면 언덕 기준 폴백.
    --   언덕-ISP 간격이 맵마다 달라 고정 마진은 부정확 → 실제 ISP 위치로 정밀화.
    local isp, ispThick, ispCenterX = nil, 0, nil
    for _, c in ipairs(mapFolder:GetChildren()) do
        if c:IsA("BasePart") and c.Name:lower():find("itemspawnplate") then
            local ic = c.CFrame
            local ia = {math.abs(ic.RightVector.X), math.abs(ic.UpVector.X), math.abs(ic.LookVector.X)}
            local il = {c.Size.X, c.Size.Y, c.Size.Z}
            local ii = 1; if ia[2] > ia[ii] then ii = 2 end; if ia[3] > ia[ii] then ii = 3 end
            isp = c; ispThick = il[ii]; ispCenterX = ic.Position.X
            break
        end
    end
    if isp then
        -- ⚠️ [밸런스 2026-08-25] 예전엔 ISP(계단) 앞 3stud 에서 멈췄다(X 685).
        --    그러면 계단 전체가 안전지대가 되어, 러너가 성문을 안 뚫고
        --    버티는 게 최선이 됐다. 시간 초과가 러너 승리라 더 그랬다.
        --    압박선의 목적은 "빨리 뚫지 않으면 탄다"인데 그게 무너진 것.
        --    → 계단을 지나 성문 앞까지 밀고 들어간다.
        -- ⚠️ 성문 앞면(map1 726 / map2 731)까지 약 11stud 를 남긴다.
        --    즉사가 아니라 초당 15 지속 데미지이므로 HP100 기준 약 7초 버틴다.
        --    그 안에 성문을 뚫거나 죽거나 — 그게 의도된 선택이다.
        -- ⚠️ 곡사포 사정권(map1 692~760)과 겹치지만, 곡사포는 한 번에 한 발이고
        --    착탄 예고가 있어 회피 가능하다. 겹침 자체는 문제가 아니다.
        END_X = ispCenterX + ispThick / 2 + GATE_APPROACH
    else
        END_X = HILL_X_MAX - END_MARGIN          -- 폴백 (ISP 없는 맵)
    end
    print(string.format("[FirePressure] '%s' geo: X=%.0f~%.0f H=%.0f base=%.0f W=%.0f Z=%.0f", mapFolder.Name, START_X, END_X, HILL_Y_RANGE, HILL_BASE_Y, SCORCH_WIDTH, zCenter))

    -- 픽업 시스템 등이 같은 좌표를 쓰도록 현재 맵 geometry를 공유 (단일 소스)
    _G.MapGeometry = {
        hillXMin   = HILL_X_MIN,
        hillXMax   = HILL_X_MAX,
        hillYRange = HILL_Y_RANGE,
        hillBaseY  = HILL_BASE_Y,
        zCenter    = zCenter,
        zWidth     = widthLen,
        startX     = START_X,
        endX       = END_X,
    }
    return true
end

local setMapEvent = ReplicatedStorage:FindFirstChild("SetCurrentMap")
if setMapEvent then
    setMapEvent.Event:Connect(function(mapFolder)
        if mapFolder then currentMapFolder = mapFolder end
    end)
end
-- 🌊 침수 물 설정
local FLOOD_HEIGHT = 4             -- 침수 물 두께(정강이~무릎 높이감)
local FLOOD_TRANSPARENCY = 0.35    -- 반투명 물

-- 산 색 변환 설정
local MOUNTAIN_BROWN_BURNT = Color3.fromRGB(15, 12, 10)    -- 갈색(흙) → 까맣게 그을림
local MOUNTAIN_GREEN_BURNT = Color3.fromRGB(30, 25, 22)    -- 초록(잎) → 살짝 다른 톤의 검정 (재)

-- 산 파트 캐시 (스크립트 시작 시 1회만 수집)
local mountainParts = {}     -- { {part, originalColor, x, transformed}, ... } X 오름차순 정렬
local mountainCheckIndex = 1 -- 다음에 검사할 인덱스 (포인터 방식으로 매 프레임 비용 0)

-- 상태
local pillars = {}
local killPart = nil
local waveWall = nil   -- 🌊 보이는 물벽 (넘을 수 없는 거대 파도)
local waveCrest = nil  -- 🌊 앞으로 말린 마루 (덮쳐오는 곡선 흉내)
local scorchPart = nil
local fireActive = false
local fireSession = 0  -- 🔒 startFire 세션 ID. 정지/종료 시 +1 하여 진행 중 카운트다운을 무효화(라운드 종료 후 늦은 압박 시작 방지)
local moveConnection = nil
-- ⚡ 독립 정리선: 불기둥이 멈춰도(2단계) 이 라인 뒤의 태거 아이템을 계속 소멸.
--   "불꽃이 지나간 자리는 죽음의 땅" — 정리선은 불기둥 최대 도달 지점에 남아 통로 아이템을 치움.
local cleanupConnection = nil
local cleanupLineX = nil  -- nil이면 정리 비활성. 불기둥 진행 시 그 위치를 따라가고, 멈추면 마지막 값 고정.
local survivingScorch = nil  -- 2단계로 불꽃이 사라진 뒤에도 남겨두는 그을린 땅 자국 (RoundEnded 때 최종 제거)

local function createFirePillars()
    local folder = Instance.new("Folder")
    folder.Name = "FirePressurePillars"
    folder.Parent = workspace
    
    local pillarList = {}
    
    for i = 1, PILLAR_COUNT do
        local zPos = WALL_Z_RIGHT + PILLAR_SPACING * i
        
        -- 투명 앵커 파트 (파티클 부착용)
        local pillar = Instance.new("Part")
        pillar.Name = "FirePillar_" .. i
        pillar.Size = Vector3.new(6, 0.5, 6)
        pillar.Position = Vector3.new(START_X, 0, zPos)
        pillar.Anchored = true
        pillar.CanCollide = false
        pillar.CanQuery = false   -- 파티클 앵커 전용: 레이캐스트 제외
        pillar.CastShadow = false
        pillar.Transparency = 1
        
        -- 물보라 파티클 (거대한 파도가 높이 솟구침 — 넘을 수 없는 높이감)
        local fire = Instance.new("ParticleEmitter")
        fire.Name = "Fire"
        fire.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(245, 252, 255)),
            ColorSequenceKeypoint.new(0.3, Color3.fromRGB(175, 225, 248)),
            ColorSequenceKeypoint.new(0.7, Color3.fromRGB(90, 165, 220)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 115, 185))
        })
        fire.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 10),
            NumberSequenceKeypoint.new(0.3, 16),
            NumberSequenceKeypoint.new(1, 6)
        })
        fire.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.1),
            NumberSequenceKeypoint.new(0.5, 0.3),
            NumberSequenceKeypoint.new(1, 1)
        })
        fire.Lifetime = NumberRange.new(1.2, 2.2)
        fire.Rate = 180                                  -- 흰 물결 밀도 ↑ (선명도)
        fire.Speed = NumberRange.new(45, 70)              -- 높이 솟구침 (불꽃벽 수준 높이감 회복)
        fire.SpreadAngle = Vector2.new(18, 10)            -- 위로 모아 솟게 (벽처럼, 흰 물결 표현 유지)
        fire.Acceleration = Vector3.new(0, -15, 0)        -- 약한 중력 (살짝만 떨어짐, 높이 유지)
        fire.RotSpeed = NumberRange.new(-40, 40)
        fire.Rotation = NumberRange.new(0, 360)
        fire.LightEmission = 0        -- 물은 발광체 아님 (중앙 흰 발광 방지)
        fire.LightInfluence = 1       -- 환경광만 받음
        fire.EmissionDirection = Enum.NormalId.Top
        fire.Parent = pillar
        
        -- 물안개 파티클 (파도 위로 흩날리는 물보라 안개)
        local smoke = Instance.new("ParticleEmitter")
        smoke.Name = "Smoke"
        smoke.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 240, 250)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 205, 220))
        })
        smoke.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 6),
            NumberSequenceKeypoint.new(1, 16)
        })
        smoke.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.7),
            NumberSequenceKeypoint.new(1, 1)
        })
        smoke.Lifetime = NumberRange.new(1.2, 3)
        smoke.Rate = 18
        smoke.Speed = NumberRange.new(4, 10)              -- 낮게 깔리는 해무
        smoke.SpreadAngle = Vector2.new(40, 25)
        smoke.LightEmission = 0       -- 물안개도 발광체 아님 (흰 발광 구름 방지)
        smoke.LightInfluence = 1
        smoke.EmissionDirection = Enum.NormalId.Top
        smoke.Parent = pillar
        
        -- (PointLight 제거: 물 파도는 발광체가 아니라 혼자 튀어 보임 + 모바일 GPU 절약)
        
        
        pillar.Parent = folder
        table.insert(pillarList, {part = pillar, zPos = zPos})
    end
    
    -- 투명 킬 파트 (넓게 깔아서 데미지 판정)
    local kill = Instance.new("Part")
    kill.Name = "FireKillZone"
    kill.Size = Vector3.new(12, 150, FIRE_WIDTH)
    kill.Position = Vector3.new(START_X, 75, FIRE_Z_CENTER)
    kill.Anchored = true
    kill.CanCollide = false
    -- ⚠️ 판정은 Touched 로만 한다. 레이캐스트에는 절대 잡히면 안 된다.
    --    Y 0~150 을 차지하는 투명 벽이라, CanQuery=true 면:
    --      · 프로스트드래곤 얼음 발판이 이 윗면(Y=150)을 지면으로 오인해 하늘로 솟구침
    --      · 태거 조준 청사진이 허공(FireKillZone)에 달라붙음
    kill.CanQuery = false
    kill.CastShadow = false
    kill.Transparency = 1
    
    -- ⚠️ [2026-08-23] Touched 즉사 판정 제거.
    --    이제 데미지는 좌표 기반 지대 판정(applyZoneDamage)이 전담한다.
    --    Touched 를 남겨두면 "닿으면 즉사 + 지대는 데미지" 두 규칙이 공존해
    --    같은 불기둥이 상황에 따라 다르게 동작한다.
    --    이 파트는 시각/충돌 용도로만 남긴다.
    
    kill.Parent = folder
    
    -- 🌊 보이는 물벽 (넘을 수 없는 거대 파도의 실체 — 파티클만으론 흐릿해 착각 유발)
    local waveWall = Instance.new("Part")
    waveWall.Name = "WaveWall"
    waveWall.Size = Vector3.new(8, 34, FIRE_WIDTH)   -- 높이 34 (캐릭터 점프로 못 넘는 명백한 벽)
    waveWall.Position = Vector3.new(START_X, 17, FIRE_Z_CENTER)  -- 바닥(Y0)에서 위로 솟음
    waveWall.Anchored = true
    waveWall.CanCollide = false      -- 통과는 됨(킬존이 데미지 담당), 시각 벽 역할
    waveWall.CanTouch = false
    waveWall.CanQuery = false
    waveWall.CastShadow = false
    waveWall.Material = Enum.Material.Glass
    waveWall.Color = Color3.fromRGB(45, 120, 195)
    waveWall.Transparency = 0.35
    waveWall.Reflectance = 0.1
    waveWall.Parent = folder
    
    -- 🌊 말린 마루: 본체 꼭대기에서 앞(+X, 러너 쪽)으로 기울어 덮쳐오는 곡선 흉내
    local crest = Instance.new("Part")
    crest.Name = "WaveCrest"
    crest.Size = Vector3.new(14, 5, FIRE_WIDTH)       -- 앞으로 뻗는 마루 (얇고 김)
    crest.Anchored = true
    crest.CanCollide = false
    crest.CanTouch = false
    crest.CanQuery = false
    crest.CastShadow = false
    crest.Material = Enum.Material.Glass
    crest.Color = Color3.fromRGB(60, 140, 210)
    crest.Transparency = 0.3
    crest.Reflectance = 0.1
    -- 본체 꼭대기(Y34)에서 +X로 약 35도 기울여 앞으로 말림. 위치는 이동 루프에서 본체 기준 갱신.
    local CREST_TILT = math.rad(40)   -- 앞으로 기운 각도
    crest.CFrame = CFrame.new(START_X + 5, 36, FIRE_Z_CENTER) * CFrame.Angles(0, 0, CREST_TILT)
    crest.Parent = folder
    
    -- 포말 마루: 말린 마루 표면 전체에서 부서지는 흰 거품띠
    
    local foam = Instance.new("ParticleEmitter")
    foam.Name = "Foam"
    foam.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(225, 240, 250)),
        ColorSequenceKeypoint.new(0.6, Color3.fromRGB(200, 225, 245)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(175, 205, 230))
    })
    foam.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 5),
        NumberSequenceKeypoint.new(0.4, 8),
        NumberSequenceKeypoint.new(1, 2)
    })
    foam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(0.6, 0.5),
        NumberSequenceKeypoint.new(1, 1)
    })
    foam.Lifetime = NumberRange.new(0.8, 1.6)
    foam.Rate = 70
    foam.Speed = NumberRange.new(5, 12)
    foam.SpreadAngle = Vector2.new(30, 50)
    foam.Acceleration = Vector3.new(0, -20, 0)
    foam.RotSpeed = NumberRange.new(-50, 50)
    foam.Rotation = NumberRange.new(0, 360)
    foam.LightEmission = 0
    foam.LightInfluence = 1
    foam.EmissionDirection = Enum.NormalId.Top
    foam.Parent = crest          -- Attachment(한 점) 대신 마루 Part 전체 표면에서 고르게 뿜음
    
    return pillarList, kill, folder, waveWall, crest
end

-- 불(lava) 테마용 불기둥: 물 버전과 뼈대(앵커/킬존) 동일, 비주얼만 불꽃+연기+라이트.
-- 전진벽(WaveWall/Crest)은 없음 -> 반환 4,5번째를 nil로 둬 이동 루프가 벽 갱신을 자동 skip.
local function createFirePillarsLava()
    local folder = Instance.new("Folder")
    folder.Name = "FirePressurePillars"
    folder.Parent = workspace

    local pillarList = {}

    for i = 1, PILLAR_COUNT do
        local zPos = WALL_Z_RIGHT + PILLAR_SPACING * i

        -- 투명 앵커 파트 (파티클 부착용)
        local pillar = Instance.new("Part")
        pillar.Name = "FirePillar_" .. i
        pillar.Size = Vector3.new(6, 0.5, 6)
        pillar.Position = Vector3.new(START_X, 0, zPos)
        pillar.Anchored = true
        pillar.CanCollide = false
        pillar.CanQuery = false   -- 파티클 앵커 전용: 레이캐스트 제외
        pillar.CastShadow = false
        pillar.Transparency = 1

        -- 불꽃 파티클 (위로 솟아오름)
        local fire = Instance.new("ParticleEmitter")
        fire.Name = "Fire"
        fire.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 50)),
            ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 120, 0)),
            ColorSequenceKeypoint.new(0.7, Color3.fromRGB(220, 40, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 10, 0))
        })
        fire.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 6),
            NumberSequenceKeypoint.new(0.3, 10),
            NumberSequenceKeypoint.new(1, 2)
        })
        fire.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.1),
            NumberSequenceKeypoint.new(0.5, 0.3),
            NumberSequenceKeypoint.new(1, 1)
        })
        fire.Lifetime = NumberRange.new(0.8, 1.8)
        fire.Rate = 120
        fire.Speed = NumberRange.new(20, 50)
        fire.SpreadAngle = Vector2.new(25, 12)
        fire.LightEmission = 1
        fire.LightInfluence = 0
        fire.EmissionDirection = Enum.NormalId.Top
        fire.Parent = pillar

        -- 연기 파티클
        local smoke = Instance.new("ParticleEmitter")
        smoke.Name = "Smoke"
        smoke.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 40, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30))
        })
        smoke.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 4),
            NumberSequenceKeypoint.new(1, 12)
        })
        smoke.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.5),
            NumberSequenceKeypoint.new(1, 1)
        })
        smoke.Lifetime = NumberRange.new(1, 3)
        smoke.Rate = 20
        smoke.Speed = NumberRange.new(15, 30)
        smoke.SpreadAngle = Vector2.new(15, 15)
        smoke.LightEmission = 0.3
        smoke.EmissionDirection = Enum.NormalId.Top
        smoke.Parent = pillar

        -- 포인트 라이트 (4개 기둥마다, 모바일 GPU 절약)
        if i % 4 == 0 then
            local light = Instance.new("PointLight")
            light.Color = Color3.fromRGB(255, 100, 0)
            light.Brightness = 2
            light.Range = 25
            light.Parent = pillar
        end

        pillar.Parent = folder
        table.insert(pillarList, {part = pillar, zPos = zPos})
    end

    -- 투명 킬 파트 (물 버전과 동일 규격)
    local kill = Instance.new("Part")
    kill.Name = "FireKillZone"
    kill.Size = Vector3.new(12, 150, FIRE_WIDTH)
    kill.Position = Vector3.new(START_X, 75, FIRE_Z_CENTER)
    kill.Anchored = true
    kill.CanCollide = false
    kill.CanQuery = false   -- 위 물 버전과 동일 사유 (레이캐스트 오인 방지)
    kill.CastShadow = false
    kill.Transparency = 1

    -- ⚠️ [2026-08-23] Touched 즉사 판정 제거 (위 FireKillZone 과 같은 이유).
    --    데미지는 좌표 기반 지대 판정이 전담한다.

    kill.Parent = folder

    -- 불은 전진벽 없음: waveWall, crest 자리에 nil
    return pillarList, kill, folder, nil, nil
end

local function getHillY(x)
    local hillProgress = math.clamp((x - HILL_X_MIN) / (HILL_X_MAX - HILL_X_MIN), 0, 1)
    return HILL_BASE_Y + hillProgress * HILL_Y_RANGE   -- 절대 Y (언덕 바닥 + 경사 상승분)
end

-- 🌊 침수 물 자국 생성: 파도가 지나간 자리에 차오르는 물 (정강이~무릎 높이, 순수 비주얼)
-- lava: scorched earth plate (dark soil + smolder + embers)
local function createScorchLava(parentFolder)
    local part = Instance.new("Part")
    part.Name = "ScorchTrail"
    part.Size = Vector3.new(0.1, SCORCH_THICKNESS, SCORCH_WIDTH)
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.Slate
    part.Color = Color3.fromRGB(35, 28, 22)
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Transparency = 1
    local smolder = Instance.new("ParticleEmitter")
    smolder.Name = "SmolderSmoke"
    smolder.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(200, 195, 190)),
        ColorSequenceKeypoint.new(0.4, Color3.fromRGB(140, 135, 130)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(70,  65,  60))
    })
    smolder.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 2),
        NumberSequenceKeypoint.new(1, 9)
    })
    smolder.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.4),
        NumberSequenceKeypoint.new(0.5, 0.7),
        NumberSequenceKeypoint.new(1,   1)
    })
    smolder.Lifetime = NumberRange.new(2, 4)
    smolder.Rate = 40
    smolder.Speed = NumberRange.new(2, 4)
    smolder.SpreadAngle = Vector2.new(20, 20)
    smolder.LightEmission = 0.15
    smolder.EmissionDirection = Enum.NormalId.Top
    smolder.Enabled = false
    smolder.Parent = part
    local embers = Instance.new("ParticleEmitter")
    embers.Name = "Embers"
    embers.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 160, 40)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 30, 0))
    })
    embers.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(1, 0.15)
    })
    embers.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.1),
        NumberSequenceKeypoint.new(1, 1)
    })
    embers.Lifetime = NumberRange.new(0.8, 2)
    embers.Rate = 18
    embers.Speed = NumberRange.new(1, 3)
    embers.SpreadAngle = Vector2.new(30, 30)
    embers.LightEmission = 1
    embers.LightInfluence = 0
    embers.EmissionDirection = Enum.NormalId.Top
    embers.Enabled = false
    embers.Parent = part
    part.Parent = parentFolder
    return part
end

local function createScorchTrail(parentFolder, theme)
    if theme == "lava" then return createScorchLava(parentFolder) end
    -- 파도 비주얼 모드: 그을림 대신 침수 물 판을 생성.
    --    (용암지대 map2용 불꽃/그을림 버전은 ServerStorage.FirePressureSystem_LAVA_BACKUP 에 보존됨)
    local part = Instance.new("Part")
    part.Name = "FloodTrail"
    part.Size = Vector3.new(0.1, FLOOD_HEIGHT, SCORCH_WIDTH)
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.Glass
    part.Color = Color3.fromRGB(45, 120, 195)
    part.Reflectance = 0.1
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Transparency = 1  -- 시작은 안 보임 (파도가 Hill에 도착하면 켜짐)
    
    -- 윗면 물결 텍스처 (ocean과 동일, OffsetStuds 흐름은 별도 루프에서)
    local tex = Instance.new("Texture")
    tex.Name = "FloodFlowTex"
    tex.Texture = "rbxassetid://257528237"
    tex.Face = Enum.NormalId.Top
    tex.StudsPerTileU = 40
    tex.StudsPerTileV = 40
    tex.Color3 = Color3.fromRGB(190, 225, 245)
    tex.Transparency = 0.3
    tex.Parent = part
    
    part.Parent = parentFolder
    return part
end

-- 그을림 흔적 갱신: 시작점부터 현재 불꽃 X 위치까지 늘어남
-- lava: grow scorched plate + ignite particles on first reveal
local function updateScorchLava(currentX)
    if not scorchPart or not scorchPart.Parent then return end
    local xStart = math.max(START_X, HILL_X_MIN + 1)
    local xEnd = math.clamp(currentX, HILL_X_MIN, HILL_X_MAX)
    if xEnd <= xStart then return end
    if scorchPart.Transparency == 1 then
        scorchPart.Transparency = SCORCH_TRANSPARENCY
        for _, child in ipairs(scorchPart:GetChildren()) do
            if child:IsA("ParticleEmitter") then child.Enabled = true end
        end
    end
    local hillStartY = getHillY(xStart)
    local hillEndY = getHillY(xEnd)
    local dx = xEnd - xStart
    local dy = hillEndY - hillStartY
    local lengthAlongSlope = math.sqrt(dx * dx + dy * dy)
    local midX = (xStart + xEnd) / 2
    local midY = (hillStartY + hillEndY) / 2 + SCORCH_SURFACE_OFFSET
    scorchPart.Size = Vector3.new(lengthAlongSlope, SCORCH_THICKNESS, SCORCH_WIDTH)
    scorchPart.CFrame = CFrame.new(midX, midY, SCORCH_Z_CENTER)
        * CFrame.Angles(0, 0, SLOPE_ANGLE_RAD)
end

local function updateScorchTrail(currentX, theme)
    if theme == "lava" then return updateScorchLava(currentX) end
    if not scorchPart or not scorchPart.Parent then return end
    
    local xStart = math.max(START_X, HILL_X_MIN + 1)
    local xEnd = math.clamp(currentX, HILL_X_MIN, HILL_X_MAX)
    
    -- 아직 Hill 위에 진입 안 한 경우
    if xEnd <= xStart then return end
    
    -- 처음 보이게 될 때 한 번만 활성화
    if scorchPart.Transparency == 1 then
        scorchPart.Transparency = FLOOD_TRANSPARENCY
    end
    
    local hillStartY = getHillY(xStart)
    local hillEndY = getHillY(xEnd)
    
    local dx = xEnd - xStart
    local dy = hillEndY - hillStartY
    local lengthAlongSlope = math.sqrt(dx * dx + dy * dy)
    
    local midX = (xStart + xEnd) / 2
    local midY = (hillStartY + hillEndY) / 2 + FLOOD_HEIGHT / 2  -- 지면 위로 물이 차오름
    
    scorchPart.Size = Vector3.new(lengthAlongSlope, FLOOD_HEIGHT, SCORCH_WIDTH)
    scorchPart.CFrame = CFrame.new(midX, midY, SCORCH_Z_CENTER)
                      * CFrame.Angles(0, 0, SLOPE_ANGLE_RAD)
end

local fireFolder = nil

-- 산 MeshPart들을 캐싱 (한 번만 수집, X 오름차순 정렬)
local function cacheMountainParts()
    local map1Folder = workspace:FindFirstChild("map1")
    local castle = map1Folder and map1Folder:FindFirstChild("map1 castle")
    if not castle then
        warn("⚠️ map1 castle 못 찾음 — 산 변환 비활성화")
        return
    end
    
    local function collect(root)
        if not root then return end
        for _, c in ipairs(root:GetDescendants()) do
            if c:IsA("MeshPart") then
                table.insert(mountainParts, {
                    part = c,
                    originalColor = c.Color,
                    x = c.Position.X,
                    transformed = false
                })
            end
        end
    end
    
    collect(castle:FindFirstChild("left Mountains"))
    collect(castle:FindFirstChild("right Mountains"))
    
    table.sort(mountainParts, function(a, b) return a.x < b.x end)
    print("🏔️ 산 MeshPart 캐싱 완료:", #mountainParts, "개")
end

cacheMountainParts()

-- 불꽃 X 위치까지 닿은 산 파트들의 색 변환 (한 번 변환된 파트는 재방문 X)
local function transformMountainsBeforeX(currentX)
    while mountainCheckIndex <= #mountainParts do
        local data = mountainParts[mountainCheckIndex]
        if data.x > currentX then break end  -- 아직 불꽃이 안 닿은 영역
        
        if not data.transformed then
            local oc = data.originalColor
            -- G > R 이면 초록(풀), 아니면 갈색(흙)
            if oc.G > oc.R then
                data.part.Color = MOUNTAIN_GREEN_BURNT
            else
                data.part.Color = MOUNTAIN_BROWN_BURNT
            end
            data.transformed = true
        end
        mountainCheckIndex = mountainCheckIndex + 1
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 🔥 지대 데미지 / 회복
--
-- ⚠️ 새 루프를 만들지 않는다. 아이템 청소(cleanupItemsBehindFire)와 같은 곳에서
--    호출한다 — 이미 fireX 를 알고 좌표 비교를 하는 자리라 추가 비용이 거의 없다.
-- ⚠️ Touched 를 쓰지 않는다. 좌표 판정이면 '닿았는가'가 아니라 '뒤에 있는가'라
--    불기둥이 지나간 자리 전체를 한 번에 커버한다.
-- ═══════════════════════════════════════════════════════════════
local zoneLastSafe = {}   -- [character] = 지대를 벗어난 시각

-- 💰 [2026-09-01] 지대 회복을 '부채 상환'으로 바꾼다.
--   [왜] 시간 게이트("마지막 피격 후 N초 조용하면 회복")만으로는 못 막는다.
--     실측 22:06~22:07 라운드 8 — 킹이 유저를 때린 간격이 2.65 / 1.82 / 5.47 / 12.8초.
--     2단계에선 킹이 여러 명을 번갈아 상대해서 공백이 원래 길다.
--     2초 게이트면 12.8초 공백 하나에서만 10.8초 × 6 = 65 HP 가 새어들어간다.
--   [해결] 불기둥이 깎은 양을 기록해두고 딱 그만큼만 돌려준다.
--     · 불기둥에 안 닿았으면 부채 0 → 회복 경로가 아예 존재하지 않는다
--       (2026-09-01 무한 재생 버그의 발동 조건 자체가 사라진다).
--     · 공백이 아무리 길어도 부채를 다 갚으면 멈춘다. 시간은 상한이 아니다.
--     · 킹 슬랩·마법책·배럴로 깎인 HP 는 부채에 안 들어가니 영영 안 돌아온다.
--   ⚠️ 시간 게이트는 그대로 둔다. 상한이 아니라 연출용이다 —
--     맞는 도중에 체력이 차오르면 이상하다. 총량은 부채가 잡는다.
local zoneDebt   = {}   -- [character] = 불기둥이 깎았고 아직 안 갚은 HP
local lastSeenHp = {}   -- [character] = 직전 틱 HP (외부 피격 감지용)

-- 🔥 지대 1틱 처리. 러너와 태거가 반드시 같은 규칙을 쓰도록 한 곳에 모았다.
--   dps / healRate 는 '초당 절대량'. 태거는 비율식이라 호출부에서 MaxHealth 를 곱해 넘긴다.
--   ⚠️ 예전엔 이 로직이 러너·태거 블록에 복사되어 있었고 "한쪽만 고치지 말 것" 이라는
--     주석으로 버티고 있었다. 실제로 한쪽만 고쳐지는 사고가 났으므로 함수로 합친다.
local function zoneTick(char, hum, inZone, dps, healRate, dt)
    if inZone then
        zoneLastSafe[char] = nil
        local before = hum.Health
        hum:TakeDamage(dps * dt)
        -- ⚠️ 요청값이 아니라 '실제로 깎인 양'을 부채로 잡는다. TakeDamage 는 0 아래로
        --   내려가지 않으므로, 요청값을 쓰면 갚을 수 없는 부채가 쌓여 나중에
        --   불기둥과 무관한 회복으로 새어나간다.
        local dealt = before - hum.Health
        if dealt > 0 then zoneDebt[char] = (zoneDebt[char] or 0) + dealt end
        char:SetAttribute("InFireZone", true)   -- 클라 연출용(화면 붉게 등)
    else
        if char:GetAttribute("InFireZone") then
            char:SetAttribute("InFireZone", nil)
            zoneLastSafe[char] = os.clock()
        end
        -- 외부 피격이면 회복 대기를 재시작한다. 이건 연출용이다 — 킹한테 맞는 도중에
        -- 체력이 차오르면 이상하다. 총량 상한은 아래 부채가 잡으므로 이게 새도 안전하다.
        local prev = lastSeenHp[char]
        if prev and hum.Health < prev - 0.01 then
            zoneLastSafe[char] = os.clock()
        end
        local debt   = zoneDebt[char] or 0
        local safeAt = zoneLastSafe[char]
        if debt > 0 and safeAt and (os.clock() - safeAt) >= ZONE_HEAL_DELAY then
            local heal = math.min(healRate * dt, debt, hum.MaxHealth - hum.Health)
            if heal > 0 then
                hum.Health = hum.Health + heal
                zoneDebt[char] = debt - heal
            end
        end
    end
    lastSeenHp[char] = hum.Health
end

-- 러너 캐릭터를 훑는다(유저 + AI 봇).
local function forEachRunner(fn)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr:GetAttribute("Role") == "Runner" then
            local char = plr.Character
            if char then fn(char, plr) end
        end
    end
    -- AI 러너도 같은 규칙을 받는다. 안 그러면 봇만 불 속에서 멀쩡하다.
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m.Name:match("^AIRunner") then fn(m, nil) end
    end
end

-- 👑 태거 캐릭터를 훑는다(유저 태거 + KING 봇).
-- ⚠️ 봇은 진짜 Player 가 아니라 workspace 의 Model 이다. Role 속성으로 찾는다
--    (BlackHoleSystem.collectAllCharacters 가 같은 방법을 쓴다 — 이름 하드코딩보다 안전).
-- ⚠️ GetPlayerFromCharacter 가드 필수. 유저 태거의 캐릭터도 workspace 의 Model 이라
--    이게 없으면 위 루프와 아래 루프에 '두 번' 잡혀 피해가 두 배가 된다.
local function forEachTagger(fn)
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr:GetAttribute("Role") == "Tagger" then
            local char = plr.Character
            if char then fn(char, plr) end
        end
    end
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("Role") == "Tagger"
           and not Players:GetPlayerFromCharacter(m) then
            fn(m, nil)
        end
    end
end

-- 🤖 [2026-09-01] 태거봇이 읽는 '지대 경계 X'. 이 아래(X 작은 쪽)가 피해 지대다.
--   [왜] 봇에 위치 하한을 주려면 경계를 알아야 하는데, 불기둥은 시간에 따라
--     전진하므로 고정값을 쓸 수 없다(START_X 에서 END_X 까지 이동).
--   ⚠️ 반드시 아래 판정과 '같은 식'으로 계산한 값을 넣는다. 봇이 보는 경계와
--     실제 피해 경계가 어긋나면, 안전하다고 믿는 자리에서 타 죽는다.
--   ⚠️ 압박이 시작되기 전이나 정지 후에는 nil 이다. 봇은 nil 이면 하한 없이 동작한다.
-- 🔴 [버그수정 2026-09-20] 지대 판정에 '맵 위인가'를 곱한다.
--   [증상] 라운드 중 죽어 로비로 간 러너가 로비에서 계속 타 죽었다(라이브 제보).
--   [원인] 판정이 X 하나뿐이었다(hrp.Position.X < edge). 그런데 로비는 X=85 라
--     불기둥 진행 구간(START_X -260 → END_X 685) **안쪽**에 있다.
--     불기둥이 X=90 을 넘는 순간부터 로비 전체가 피해 지대가 된다.
--     Role 은 라운드 종료에만 지워지므로, 죽어서 로비에 있어도 루프에 계속 잡힌다.
--   [왜 X 하한으로는 못 고치나] 로비 X(85) 가 러너 스폰(-222)과 성(685) '사이'에 끼어 있다.
--     X 로는 로비와 레인을 가를 수 없다.
--   [해결] Z 로 가른다. 실측 2026-09-20:
--     로비 Z=81 / map1 언덕 Z=-674.5 / map2 언덕 Z=897.5 — 750 stud 이상 떨어져 있다.
--   ⚠️ SCORCH_Z_CENTER·SCORCH_WIDTH 를 재사용한다. computeGeometry 가 라운드마다 현재 맵
--     언덕에서 다시 계산하는 값이라 **새 맵을 추가해도 자동으로 따라온다.**
--     여기에 새 상수를 만들면 맵이 늘 때마다 또 고쳐야 한다.
--   ⚠️ 'Eliminated 인 사람만 제외'가 아니라 '맵 밖이면 관여하지 않는다'로 뒤집었다 —
--     앞으로 어떤 이유로 맵 밖에 있게 되든 안 깨진다(09-01 "제외 목록보다 결과 보장").
--   ⚠️ 피해뿐 아니라 회복도 건너뛴다. 맵 밖은 이 시스템의 관할이 아니다.
local function onMapForZone(hrp)
    local half = (SCORCH_WIDTH or 242) * 2   -- 언덕 폭의 2배 = 넉넉한 여유(로비는 750 밖)
    return math.abs(hrp.Position.Z - (SCORCH_Z_CENTER or 0)) <= half
end

local function applyZoneDamage(fireX, dt)
    local edge = fireX - ZONE_MARGIN
    _G.FireZoneEdgeX = edge

    -- 👑 [2026-08-28] 태거 비율 피해. 러너 블록과 '같은 구조'를 유지한다
    --    (지대 판정 → 피해 or 회복 지연). 한쪽만 고치지 않도록 나란히 둔다.
    --    ⚠️ 러너와 달리 Downed 검사가 없다 — 태거는 다운 상태가 없고 바로 죽는다.
    forEachTagger(function(char)
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp or hum.Health <= 0 then return end
        if not onMapForZone(hrp) then return end   -- 🔴 맵 밖(로비 등)은 관여하지 않는다

        zoneTick(char, hum, hrp.Position.X < edge,
            hum.MaxHealth * TAGGER_ZONE_PCT, hum.MaxHealth * TAGGER_HEAL_PCT, dt)
    end)

    forEachRunner(function(char)
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp or hum.Health <= 0 then return end
        if not onMapForZone(hrp) then return end   -- 🔴 맵 밖(로비 등)은 관여하지 않는다
        -- ⚠️ 다운 상태는 제외한다. 쓰러진 러너까지 태우면 부활이 사실상 불가능해진다.
        if char:GetAttribute("Downed") then return end

        zoneTick(char, hum, hrp.Position.X < edge, ZONE_DPS, ZONE_HEAL, dt)
    end)
end

-- 불기둥 뒤쪽(이미 지나간 죽은 영역)의 태거 아이템 정리.
-- fireX = 현재 불기둥 X. fireX - CLEANUP_MARGIN 보다 뒤(X 작은 쪽)의 TaggerItems 제거.
-- 라운드 중 누적되는 물리 아이템 수에 상한을 줘 서버 부하를 일정하게 유지.
local function cleanupItemsBehindFire(fireX)
    local cutoff = fireX - CLEANUP_MARGIN

    -- 🧹 [버그수정 2026-09-19] 표식(TaggerSpawnedItem) 그물. 이제 이게 주력이다.
    --   [증상] 뉴비(ItemNoob)가 불벽이 지나간 뒤에도 안 치워져 계속 쌓였다(사용자 제보).
    --     라운드 종료 때는 치워지는데 불벽 청소만 안 됐다 — 두 그물이 기준이 달랐다.
    --   🔴 [원인] **RoundSystem 이 2026-09-02 에 고친 것과 글자 그대로 같은 버그다.**
    --     그때 아래 두 그물의 결함을 밝히고 표식 그물로 바꿨는데,
    --     **같은 결함을 가진 이 함수는 같이 안 고쳤다.** 같은 규칙이 두 곳에 필요한데
    --     한쪽만 적용된 사례가 또 나온 것이다.
    --     · 그물①(CollisionGroup=="TaggerItems"): ItemNoob·GoldNeonNoob 등은 벽·산과
    --       충돌해야 해서 **의도적으로 Default 그룹**을 쓴다. 그래서 아예 안 걸린다.
    --     · 그물②의 "Wood Log" 분기는 죽은 코드다 — Wood Log 는 Model 이 아니라
    --       MeshPart 라 IsA("Model") 이 영원히 false 다.
    --   [왜 중요한가] 이건 연출이 아니라 **성능**이다. 이 함수의 존재 이유가
    --     "라운드 중 누적되는 물리 아이템 수에 상한을 주는 것"인데, 가장 많이 쌓이는
    --     뉴비가 통째로 빠져 있었다(실측: 1단계 88초에 21개 투척).
    --   ⚠️ 아래 두 그물을 지우지 않는다. 표식은 스폰된 '최상위 오브젝트'에만 붙으므로
    --     배럴 파열·스톤 분열로 흩어진 파편은 여전히 콜리전 그룹으로만 잡힌다.
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:GetAttribute("TaggerSpawnedItem") then
            -- 위치는 BasePart / Model 양쪽을 본다(뉴비는 Model, 스톤은 BasePart).
            local px
            if obj:IsA("BasePart") then
                px = obj.Position.X
            elseif obj:IsA("Model") then
                local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                px = pp and pp.Position.X
            end
            if px and px < cutoff then obj:Destroy() end
        end
    end

    -- BasePart (TaggerItems 콜리전 그룹) 정리
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("BasePart") then
            local ok, gn = pcall(function() return obj.CollisionGroup end)
            if ok and gn == "TaggerItems" and obj.Position.X < cutoff then
                obj:Destroy()
            end
        elseif obj:IsA("Model") and (obj.Name == "Wooden Barrel" or obj.Name == "Wood Log") then
            -- Model 형태 아이템: PrimaryPart(또는 첫 파트) 위치로 판정
            local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if pp and pp.Position.X < cutoff then
                obj:Destroy()
            end
        end
    end
end

-- 라운드 종료 시 모든 변환된 산 파트를 원래 색으로 복구
local function restoreMountains()
    for _, data in ipairs(mountainParts) do
        if data.transformed then
            data.part.Color = data.originalColor
            data.transformed = false
        end
    end
    mountainCheckIndex = 1
end


local function startFire()
    fireSession = fireSession + 1
    local mySession = fireSession
    -- 맵 기하 자동 계산 (현재 맵의 언덕에서 좌표 갱신). 언덕 없으면 불꽃벽 생략.
    if not computeGeometry(currentMapFolder) then
        warn("[FirePressure] 기하 계산 실패 - 불꽃벽 시작 중단")
        return
    end

    -- 기존 정리
    if fireFolder then fireFolder:Destroy() end
    if moveConnection then moveConnection:Disconnect() end
    if cleanupConnection then cleanupConnection:Disconnect(); cleanupConnection = nil end  -- 이전 정리 루프 해제(중복 방지)
    cleanupLineX = nil
    if survivingScorch then survivingScorch:Destroy(); survivingScorch = nil end  -- 이전 라운드 그을림 자국 잔존 시 제거(안전장치)
    fireActive = false
    pillars = {}
    killPart = nil
    scorchPart = nil
    restoreMountains()  -- 혹시 이전 라운드의 변환이 남아있으면 복구

    -- 테마 선택: 맵 FireTheme Attribute (water/lava). 없으면 water.
    --   카운트다운 UI 문구(쓰나미/불꽃벽)와 불기둥 비주얼이 모두 이 값으로 갈림.
    local themeName = currentMapFolder:GetAttribute("FireTheme") or "water"

    -- 카운트다운: 매초 클라이언트에 남은 시간 + 테마 전달 (UI 문구 분기용)
    local countdownEvent = ReplicatedStorage:FindFirstChild("FirePressureCountdown")
    for remaining = DELAY, 1, -1 do
        if mySession ~= fireSession then return end  -- 🔒 정지/종료로 취소됨 → 압박 시작 중단
        if countdownEvent then
            countdownEvent:FireAllClients("tick", remaining, themeName)
        end
        task.wait(1)
    end
    if mySession ~= fireSession then return end  -- 🔒 카운트다운 직후 최종 확인 (대기 마지막 1초 사이 종료 대비)
    -- 카운트다운 종료 신호
    if countdownEvent then
        countdownEvent:FireAllClients("started", nil, themeName)
    end

    local pillarBuilder = (themeName == "lava") and createFirePillarsLava or createFirePillars
    pillars, killPart, fireFolder, waveWall, waveCrest = pillarBuilder()
    scorchPart = createScorchTrail(fireFolder, themeName)
    fireActive = true
    print("🔥 불기둥 압박 시작! 기둥", PILLAR_COUNT, "개, 속도:", SPEED)
    
    moveConnection = RunService.Heartbeat:Connect(function(dt)
        if not fireActive or not fireFolder or not fireFolder.Parent then
            if moveConnection then moveConnection:Disconnect() end
            return
        end
        
        local currentX = pillars[1].part.Position.X

        -- 🔥 [2026-09-18] 불벽 위치 공개. 봇이 "불벽 뒤로 동료를 구하러 가는" 자살을 막는 데 쓴다.
        --   [왜 X 한 값인가] 불벽은 맵 폭 전체를 가로질러 +X 로 전진하는 선이다.
        --     러너는 START(-222) → GOAL(784) 로 같은 방향으로 달리므로,
        --     X 가 이 값보다 작은 자리 = 이미 지나간 자리 = 죽는 자리다.
        --   ⚠️ [BotDangerZone 을 안 쓴 이유] 그 속성을 붙이면 봇의 일반 회피가 같이 반응한다.
        --     lane 탈출은 좌우로 빠지는 규칙인데, 맵 폭 전체를 덮는 벽에서는 옆으로 가도 소용없고
        --     "불벽이 앞으로 밀어낸다"는 압박 설계가 정반대로 깨진다. 그래서 읽기 전용으로만 낸다.
        --   ⚠️ [끄는 코드를 안 만든다] at 시각을 같이 실어 소비처가 만료로 판단한다.
        --     라운드 종료·스크립트 사망·루프 중단 어느 경로로 끝나도 저절로 무효가 된다 —
        --     "해제 코드에 도달이 보장되는가"를 물을 필요가 없는 형태.
        _G.FireLine = { x = currentX, at = os.clock() }
        local newX = math.min(currentX + SPEED * dt, END_X)
        local hillY = getHillY(newX)
        
        -- 불기둥 위치 업데이트
        for _, pillarData in ipairs(pillars) do
            pillarData.part.Position = Vector3.new(newX, hillY + 1, pillarData.zPos)
        end
        
        -- 킬존 업데이트
        if killPart and killPart.Parent then
            killPart.Position = Vector3.new(newX, hillY + 75, FIRE_Z_CENTER)
        end
        
        -- 🌊 물벽 업데이트 (언덕 표면에서 위로 솟은 채 전진)
        if waveWall and waveWall.Parent then
            waveWall.Position = Vector3.new(newX, hillY + 17, FIRE_Z_CENTER)
        end
        
        -- 🌊 말린 마루 업데이트 (본체 꼭대기 앞쪽에서 기울어진 채 전진)
        if waveCrest and waveCrest.Parent then
            waveCrest.CFrame = CFrame.new(newX + 5, hillY + 36, FIRE_Z_CENTER) * CFrame.Angles(0, 0, math.rad(40))
        end
        
        -- 그을림 흔적 갱신
        updateScorchTrail(newX, themeName)
        
        -- 🌊 침수 물 표면 텍스처 흐름 (물결 움직임)
        if scorchPart and scorchPart.Parent then
            local ftex = scorchPart:FindFirstChild("FloodFlowTex")
            if ftex then
                ftex.OffsetStudsU = (ftex.OffsetStudsU + 3 * dt) % ftex.StudsPerTileU
                ftex.OffsetStudsV = (ftex.OffsetStudsV + 1.2 * dt) % ftex.StudsPerTileV
            end
        end
        
        -- 산 색 변환 (불꽃이 닿은 영역) — 🌊 파도 모드 비활성화 (물은 산을 그을리지 않음)
        --    (용암지대 map2용 불꽃 버전은 ServerStorage.FirePressureSystem_LAVA_BACKUP 에 보존됨)
        -- transformMountainsBeforeX(newX)

        -- ⚡ 정리선을 불기둥 위치로 갱신 (불기둥이 전진하면 정리선도 따라감)
        cleanupLineX = newX
    end)

    -- ⚡ 독립 정리 루프: 불기둥 루프와 분리해, 불기둥이 멈춰도(2단계) 계속 돈다.
    --   정리선(cleanupLineX) 뒤의 태거 아이템을 주기적으로 소멸.
    --   불기둥 진행 중엔 위 루프가 cleanupLineX를 갱신, 멈추면 마지막 값(END_X)에 고정됨.
    cleanupLineX = pillars[1].part.Position.X
    local cleanupAccum = 0
    local zoneAccum = 0
    cleanupConnection = RunService.Heartbeat:Connect(function(dt)
        cleanupAccum = cleanupAccum + dt
        if cleanupAccum >= CLEANUP_INTERVAL then
            cleanupAccum = 0
            if cleanupLineX then
                cleanupItemsBehindFire(cleanupLineX)
            end
        end

        -- 🔥 지대 데미지/회복.
        -- ⚠️ 아이템 청소와 같은 루프를 쓴다. cleanupLineX(현재 불기둥 X)가 이미
        --    갱신되고 있어 별도 추적이 필요 없고, 러너는 최대 10여 명이라 비용도 작다.
        -- ⚠️ 주기는 따로 둔다. 아이템 청소는 드물어도 되지만(CLEANUP_INTERVAL),
        --    데미지는 촘촘해야 "서서히 깎인다"가 체감된다.
        zoneAccum = zoneAccum + dt
        if zoneAccum >= ZONE_TICK then
            local step = zoneAccum
            zoneAccum = 0
            if cleanupLineX then
                applyZoneDamage(cleanupLineX, step)
            end
        end
    end)
end

local function stopFire()
    -- 1단계 (즉시): 데미지/이동 중지
    --   fireActive=false 로 kill.Touched 콜백이 데미지 차단,
    --   moveConnection 해제로 불기둥 이동 중지.
    --   시각 효과(불꽃, 그을림, 산 색)는 그 자리에 그대로 유지됨.
    fireSession = fireSession + 1  -- 🔒 진행 중이던 카운트다운(startFire) 무효화 → 정지 후 늦은 시작 방지
    fireActive = false

    -- 🔥 지대 상태 정리.
    -- ⚠️ InFireZone 속성을 안 지우면 불이 꺼진 뒤에도 클라 연출(화면 붉게)이 남고,
    --    캐릭터가 리스폰되지 않는 경로에서는 다음 라운드까지 따라간다.
    --    "상태를 켜는 코드에는 끄는 코드를 반드시 같이" 원칙.
    for char in pairs(zoneLastSafe) do
        if char and char.Parent then char:SetAttribute("InFireZone", nil) end
    end
    zoneLastSafe = {}
    -- 💰 부채·HP 캐시도 같이 비운다. 남겨두면 다음 라운드 시작 시점에
    --    "지난 라운드에 탄 만큼"이 회복 권리로 살아남는다 — 켜는 코드와 끄는 코드는 한 짝.
    zoneDebt   = {}
    lastSeenHp = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        local c = plr.Character
        if c then c:SetAttribute("InFireZone", nil) end
    end
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m.Name:match("^AIRunner") then
            m:SetAttribute("InFireZone", nil)
        end
    end
    if moveConnection then
        moveConnection:Disconnect()
        moveConnection = nil
    end

    -- 카운트다운 UI도 클리어 (라운드 도중 종료된 경우 대비)
    local countdownEvent = ReplicatedStorage:FindFirstChild("FirePressureCountdown")
    if countdownEvent then
        countdownEvent:FireAllClients("clear")
    end

    -- ⚠️ 봇이 읽는 지대 경계를 지운다. 안 지우면 다음 라운드 시작 시 봇이
    --   이전 판의 경계(보통 END_X 근처)로 묶여, 압박이 시작도 안 했는데 물러난다.
    --   "켜는 코드에는 끄는 코드를 같이".
    _G.FireZoneEdgeX = nil

    print("🔥 불기둥 압박 정지 (불꽃 기둥 제거, 그을린 땅 자국은 유지)")
    
    -- ⚡ 그을린 땅 자국 보존: fireFolder에서 분리해 살린다("불꽃이 지나간 죽음의 땅" 흔적 유지).
    --   파티클(연기·잉걸불)은 꺼서 "다 타고 식은 흔적"으로 만듦. 검은 자국 판만 남음.
    --   살아남은 자국은 RoundEnded(라운드 진짜 종료) 때 최종 제거됨.
    if scorchPart and scorchPart.Parent then
        for _, child in ipairs(scorchPart:GetChildren()) do
            if child:IsA("ParticleEmitter") then
                child.Enabled = false  -- 신규 입자 방출 중지 (이미 떠있는 입자는 수명대로 자연 소멸)
            end
        end
        scorchPart.Parent = workspace  -- fireFolder destroy 영향에서 분리
        survivingScorch = scorchPart
    end

    -- 캡처: 다음 라운드의 새 fireFolder가 영향받지 않도록 로컬에 저장
    local folderToCleanup = fireFolder
    fireFolder = nil
    pillars = {}
    killPart = nil
    scorchPart = nil
    
    -- 2단계 (지연): 플레이어가 로비로 텔레포트된 후 불꽃 기둥/킬존 정리 (그을림 자국은 위에서 이미 분리해 보존)
    task.delay(POST_STOP_VISUAL_DELAY, function()
        if folderToCleanup then
            folderToCleanup:Destroy()
        end
        -- 새 라운드가 이미 시작됐다면 산 복구 스킵 (정상 흐름에선 발생 X, 안전장치)
        if not fireActive and not fireFolder then
            restoreMountains()
            print("🔥 불기둥 기둥 정리 완료 (그을린 땅 자국은 유지, 산 색 복구)")
        end
    end)
end

startEvent.Event:Connect(function()
    task.spawn(startFire)
end)

stopEvent.Event:Connect(function()
    stopFire()
end)

-- ⚡ 라운드 진짜 종료(RoundEnded) 시에만 독립 정리 루프 해제.
--   StopFirePressure는 Stage2에서도 발사되므로 거기선 정리를 멈추면 안 됨(통로 아이템 계속 처리).
--   RoundEnded는 승부 결정/전원 사망 등 라운드가 실제로 끝났을 때만 발사됨.
local roundEndedEvent = ReplicatedStorage:FindFirstChild("RoundEnded")
if roundEndedEvent then
    roundEndedEvent.Event:Connect(function()
        fireSession = fireSession + 1  -- 🔒 라운드 진짜 종료 → 진행 중 카운트다운 무효화 (StopFirePressure 없이 끝나는 경로 대비)
        if cleanupConnection then
            cleanupConnection:Disconnect()
            cleanupConnection = nil
        end
        cleanupLineX = nil
        -- 라운드 진짜 종료 → 보존했던 그을린 땅 자국도 최종 제거 (다음 라운드 깨끗이 시작)
        if survivingScorch then
            survivingScorch:Destroy()
            survivingScorch = nil
        end
    end)
else
    warn("[FirePressure] RoundEnded 이벤트 못 찾음 - 정리 루프가 라운드 종료 시 해제 안 될 수 있음")
end

print("✅ FirePressureSystem v3 준비 완료! (불기둥 " .. PILLAR_COUNT .. "개 + 그을림 흔적)")
