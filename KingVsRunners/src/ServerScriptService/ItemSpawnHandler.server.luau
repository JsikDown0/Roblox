-- 아이템 스폰 핸들러 (ItemNoob 회전 추가)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local FROST_DRAGON_PASS = 1713666153

local spawnItemEvent = ReplicatedStorage:WaitForChild("SpawnItemEvent")
local spawnWarningEvent = ReplicatedStorage:WaitForChild("SpawnWarning")
local taggerItems = ServerStorage:WaitForChild("TaggerItem")
local rotatorTemplate = ServerScriptService:WaitForChild("ItemNoobRotator")
local iceGeneratorTemplate = ServerScriptService:WaitForChild("FrostDragonIceGenerator")

-- 배럴 겹침 감지 반경
local BARREL_BLOCK_RADIUS = 15
local MIN_SPAWN_DIST = 20   -- 태거와 소환 지점의 최소 거리 (캠핑 방지)

-- 🚫 [MIN-SPAWN-DIST] 클라 청사진이 '같은 기준'으로 금지 반경을 그릴 수 있게 값을 노출한다.
--   ⚠️ 클라(TaggerUIScript)가 숫자를 하드코딩하면 여기만 고쳤을 때 표시와 판정이 어긋나
--      "빨간데 소환되네 / 안 빨간데 거부되네" 가 된다. 그건 지금의 '안내 없음'보다 나쁘다.
--   ⚠️ 이 값을 바꾸려면 이 줄이 아니라 위의 MIN_SPAWN_DIST 만 바꾸면 된다(자동 전파).
ReplicatedStorage:SetAttribute("MinSpawnDist", MIN_SPAWN_DIST)

-- ── 아이템 사운드 ────────────────────────────────────────────
-- 아이템별 음원 + 재생 규칙. 서버에서 파트에 Sound 를 붙이면 3D 위치 사운드로
-- 모든 클라이언트에 복제된다(태거·러너 공통, 거리에 따라 감쇠).
--   spawnOnce : 스폰 순간 1회 재생
--   loopMin/Max: 굴러가는 동안 이 간격(초) 랜덤으로 반복. nil 이면 반복 없음.
--   speed/vol : PlaybackSpeed / Volume 보정
local ITEM_SOUNDS = {
    ["ItemNoob"] = {
        id = "rbxassetid://105916582425420",  -- nom-nom-nom (그룹 보상 전용 아이템, 밈 사운드)
        spawnOnce = true,                      -- 반복 없음: 충돌 시 ItemDamageSystem 이 별도 재생
        vol = 3.2, maxDist = 140,
    },
    ["Wood Log"] = {
        id = "rbxassetid://101897300177252",
        spawnOnce = true, loopMin = 1.6, loopMax = 3.0,
        vol = 3.0, maxDist = 170,
    },
    ["stone"] = {
        id = "rbxassetid://133303251833176",
        spawnOnce = true, loopMin = 1.6, loopMax = 3.0,
        vol = 3.0, maxDist = 170,
    },
    ["Wooden Barrel"] = {
        id = "rbxassetid://101688098876378",
        spawnOnce = true, loopMin = 1.6, loopMax = 3.0,
        speed = 0.7,   -- 느리게 = 더 무겁고 둔탁하게
        vol = 2.4,     -- 통은 속이 비었으니 다른 아이템보다 살짝 가볍게
        maxDist = 170,
    },
}

-- 사운드를 붙일 실제 파트를 찾는다(Model 이면 PrimaryPart 또는 첫 BasePart).
local function findSoundHost(item)
    if item:IsA("BasePart") then return item end
    if item:IsA("Model") then
        if item.PrimaryPart then return item.PrimaryPart end
        for _, d in ipairs(item:GetDescendants()) do
            if d:IsA("BasePart") then return d end
        end
    end
    return nil
end

local function attachItemSound(item, itemName)
    if not item then return end

    -- ⚠️ 전용 사운드를 가진 스킨은 공용 사운드를 붙이지 않는다.
    --    (SummerNoob = _CheerSound/_SplashSound, DemonFlameStone = _DemonSound)
    --    겹쳐 나면 연출이 지저분해지므로 모델이 자기 소리를 갖고 있으면 양보한다.
    --    판정 기준을 "이름 하드코딩"이 아니라 "언더스코어로 시작하는 Sound 존재"로 두어
    --    앞으로 전용 사운드 스킨을 추가해도 별도 수정 없이 자동 적용되게 한다.
    for _, d in ipairs(item:GetDescendants()) do
        if d:IsA("Sound") and d.Name:sub(1, 1) == "_" then
            return
        end
    end

    local cfg = ITEM_SOUNDS[itemName]
    -- 스킨을 끼면 실제 모델명이 달라진다(ItemNoob → GoldNeonNoob, Wood Log → SpikedWood 등).
    -- 정확 일치로만 찾으면 스킨 사용 시 소리가 사라지므로 키워드 폴백을 둔다.
    if not cfg then
        local lower = tostring(itemName):lower()
        -- ⚠️ barrel 을 wood 보다 먼저 검사한다 — "Wooden Barrel" 계열 스킨이
        --    wood 키워드에 먼저 걸려 통나무 소리가 나는 것을 막기 위함.
        if lower:find("noob") then cfg = ITEM_SOUNDS["ItemNoob"]
        elseif lower:find("barrel") then cfg = ITEM_SOUNDS["Wooden Barrel"]
        elseif lower:find("log") or lower:find("wood") then cfg = ITEM_SOUNDS["Wood Log"]
        elseif lower:find("stone") then cfg = ITEM_SOUNDS["stone"]
        end
    end
    if not cfg then return end
    local host = findSoundHost(item)
    if not host then return end

    local snd = Instance.new("Sound")
    snd.Name = "ItemSFX"
    snd.SoundId = cfg.id
    snd.Volume = cfg.vol or 1.4
    snd.PlaybackSpeed = cfg.speed or 1
    snd.RollOffMinDistance = 25   -- 이 거리까지는 감쇠 없이 원음 (기존 12는 너무 짧아 작게 들렸음)
    snd.RollOffMaxDistance = cfg.maxDist or 110
    snd.Parent = host

    if cfg.spawnOnce then snd:Play() end

    -- 굴러가는 동안 랜덤 간격 반복 (아이템이 사라지면 루프 종료)
    if cfg.loopMin and cfg.loopMax then
        task.spawn(function()
            while item.Parent and host.Parent do
                task.wait(math.random() * (cfg.loopMax - cfg.loopMin) + cfg.loopMin)
                if not (item.Parent and host.Parent) then break end
                -- 굴림 소리는 실제로 움직일 때만 (정지한 아이템이 계속 소리내지 않게)
                local ok, spd = pcall(function() return host.AssemblyLinearVelocity.Magnitude end)
                if ok and spd > 3 then
                    snd.TimePosition = 0
                    snd:Play()
                end
            end
        end)
    end
end




-- ✅ TaggerItems ↔ TaggerCharacter 충돌 해제
PhysicsService:CollisionGroupSetCollidable("TaggerItems", "TaggerCharacter", false)
print("✅ TaggerItems ↔ TaggerCharacter 충돌 해제")


-- ✅ Runners / IceEffect 콜리전 그룹 설정
-- 두 그룹 모두 여기서 등록 보장 (KillEffectSystem보다 먼저 실행될 수 있으므로)
local function ensureGroup(name)
    if not PhysicsService:IsCollisionGroupRegistered(name) then
        PhysicsService:RegisterCollisionGroup(name)
    end
end
ensureGroup("Runners")
ensureGroup("IceEffect")
PhysicsService:CollisionGroupSetCollidable("TaggerItems", "Runners",   false)
-- ⚠️ [주의] 위 "Runners" 설정은 사실상 죽은 설정이다(2026-08-23 실측).
--    러너 캐릭터 파트는 "Runners" 가 아니라 "RunnerCharacter" 그룹을 쓴다
--    (RoundSystem 2135/2245/2343/2438 등에서 대입). 따라서 TaggerItems ↔ RunnerCharacter
--    는 여전히 true 이고, 통나무 등이 러너를 물리적으로 밀어낸다.
--    ⚠️ 이걸 false 로 바꾸면 아이템이 러너를 통과해 버려서 '굴러와 덮치는' 1단계 핵심
--       연출이 사라진다. 그래서 여기서는 고치지 않고 그대로 둔다.
--       무적 중에만 통과시키는 처리는 DurabilitySystem 이 DownedRunner 그룹으로 담당.
PhysicsService:CollisionGroupSetCollidable("IceEffect",   "Runners",   false)
PhysicsService:CollisionGroupSetCollidable("IceEffect",   "TaggerItems", false)
print("✅ Runners / IceEffect 콜리전 그룹 설정 완료")

-- ✅ Mountains 콜리전 그룹 설정 (TaggerItems만 통과, 나머지는 막힘)
if not PhysicsService:IsCollisionGroupRegistered("Mountains") then
    PhysicsService:RegisterCollisionGroup("Mountains")
end
PhysicsService:CollisionGroupSetCollidable("TaggerItems", "Mountains", false)

-- ✅ TaggerBarrier 충돌 설정 (TaggerCharacter만 막고 다른 모든 그룹 통과)
-- 용도: ItemSpawnPlate 옆 invisible 벽이 태거 캐릭터만 막아
--       발사된 태거 아이템(통나무 등)은 통과시키도록 함.
if not PhysicsService:IsCollisionGroupRegistered("TaggerBarrier") then
    PhysicsService:RegisterCollisionGroup("TaggerBarrier")
end
PhysicsService:CollisionGroupSetCollidable("TaggerBarrier", "Default",         false)
PhysicsService:CollisionGroupSetCollidable("TaggerBarrier", "TaggerItems",     false)
PhysicsService:CollisionGroupSetCollidable("TaggerBarrier", "Walls",           false)
PhysicsService:CollisionGroupSetCollidable("TaggerBarrier", "ItemBarrier",     false)
PhysicsService:CollisionGroupSetCollidable("TaggerBarrier", "RunnerCharacter", false)
PhysicsService:CollisionGroupSetCollidable("TaggerBarrier", "Mountains",       false)
-- TaggerCharacter와의 충돌은 명시적으로 true (다른 코드가 false로 바꾼 적 있을 수 있음 대비)
PhysicsService:CollisionGroupSetCollidable("TaggerBarrier", "TaggerCharacter", true)

-- ✅ WoodShield 콜리전 그룹 (TaggerItems만 충돌, 나머지 통과)
if not PhysicsService:IsCollisionGroupRegistered("WoodShield") then
    PhysicsService:RegisterCollisionGroup("WoodShield")
end
for _, g in ipairs({"Default","RunnerCharacter","TaggerCharacter","Runners","Walls","Mountains","ItemBarrier","TaggerBarrier","TaggerItems"}) do
    PhysicsService:CollisionGroupSetCollidable("WoodShield", g, false)
end
print("✅ WoodShield 콜리전 그룹 설정 완료")

-- ✅ Vines 콜리전 그룹 (TaggerItems와만 충돌 안 함, 나머지는 그대로 충돌)
if not PhysicsService:IsCollisionGroupRegistered("Vines") then
    PhysicsService:RegisterCollisionGroup("Vines")
end
PhysicsService:CollisionGroupSetCollidable("Vines", "TaggerItems", false)
print("✅ Vines 콜리전 그룹 설정 완료")

-- 맵의 Vine Variant 모델에 그룹 적용
task.defer(function()
    local function applyVineGroup(model)
        if not model then return end
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CollisionGroup = "Vines"
            end
        end
        return true
    end
    local applied = 0
    if applyVineGroup(workspace:FindFirstChild("Vine Variant 1")) then applied += 1 end
    if applyVineGroup(workspace:FindFirstChild("Vine Variant 2")) then applied += 1 end
    print("✅ Vines 콜리전 그룹 적용 완료 (" .. applied .. "개 모델)")
end)

-- 맵의 Mountains 파트에 그룹 적용
task.defer(function()
    local function applyMountainGroup(model)
        if not model then return end
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CollisionGroup = "Mountains"
            end
        end
    end
    -- map1
    local map1 = workspace:FindFirstChild("map1")
    local castle = map1 and map1:FindFirstChild("map1 castle")
    if castle then
        applyMountainGroup(castle:FindFirstChild("left Mountains"))
        applyMountainGroup(castle:FindFirstChild("right Mountains"))
        print("✅ Mountains 콜리전 그룹 적용 완료")
    end
end)

-- Forest map wall segment → Walls 그룹 (TaggerItems와 충돌 안 함)
task.defer(function()
    local map1 = workspace:FindFirstChild("map1")
    if not map1 then return end
    local applied = 0
    for _, child in ipairs(map1:GetChildren()) do
        if child.Name == "Forest map wall segment" and child:IsA("BasePart") then
            child.CollisionGroup = "Walls"
            applied += 1
        end
    end
    if applied > 0 then
        print("✅ Forest map wall segment Walls 그룹 적용:", applied, "개")
    end
end)

-- map2 태거 거점 벽(map1 TaggerWall에서 복제): 저장 누락/롤백 대비 런타임에 그룹·충돌 보장 + 진단
task.defer(function()
    local map2 = workspace:FindFirstChild("map2")
    local wallFolder = map2 and map2:FindFirstChild("Wall")
    if not wallFolder then return end
    for _, c in ipairs(wallFolder:GetChildren()) do
        if c:IsA("BasePart") and c.Name:find("TaggerWall") then
            print("[TaggerWall map2]", c.Name, "런타임 그룹=", c.CollisionGroup, "CanCollide=", c.CanCollide, "→ TaggerBarrier 보장")
            c.CollisionGroup = "TaggerBarrier"
            c.CanCollide = true
            c.CanQuery = true
        end
    end
end)
local playerCooldowns = {}   -- [userId] = { [itemName] = 마지막 사용 시각 }

-- ── 아이템별 쿨다운(초) ──────────────────────────────────────
-- 기준: 자체 잠금이 있는 아이템은 그 잠금이 실질 제한이므로 짧게(기본값) 두고,
--       잠금이 없는 광역/장거리기만 길게 잡는다.
--   EnergyBall : 사거리 1000을 0.6초에 주파(1667 stud/s) + 경고선 1.5초.
--                2초 쿨이면 경고가 끝나자마자 다음 발이 준비돼 사실상 상시 발사였다.
--   tsunami    : 위력 체감이 약하다는 실플레이 피드백 반영 → 짧게(광역기지만 회피 가능).
-- 여기 없는 아이템은 DEFAULT_COOLDOWN. 값만 바꾸면 되니 밸런싱은 이 표에서만 한다.
-- ⚠️ [SWAP-REWARD] 전역 쿨(1.5)보다 '길게' 둔다. 의도적인 설계다:
--      · 같은 아이템 반복  → 3초 (페널티)
--      · 아이템 전환       → 2초 (보상)
--    하나만 계속 쓰는 단조로운 전략에 비용을 매기고, 상대도 덜 지루해진다.
--    ⚠️ 이 값이 GLOBAL_COOLDOWN 보다 작아지면 전환 보상이 사라진다. 항상 크게 유지할 것.
local DEFAULT_COOLDOWN = 3
-- 아이템 종류와 무관한 최소 간격(초). 아이템별 쿨이 독립이라 스위칭 연사가 가능했던 것을 막는다.
-- 클라이언트에 표시하기 위해 플레이어 속성으로도 알린다(TaggerGlobalCDUntil).
-- ⚠️ [BASE-COOLDOWN] 이 값이 '기본 쿨'이다 — 아이템 종류·전환과 무관하게
--    모든 소환에 적용되는 최소 간격. 난사를 막는 것이 목적이다.
--    1 → 1.5 → 2 (2026-08-22). 난사 방지. 실플레이로 조정한 값.
--    ⚠️ DEFAULT_COOLDOWN(같은 아이템 = 3초)보다 짧게 두는 것이 의도다.
--       전환하면 2초, 같은 걸 반복하면 3초 → 다양한 운용에 보상.
--    ⚠️ 아이템별 쿨(ITEM_COOLDOWN)은 '이보다 긴 제약이 필요한 것'만 예외로 둔다.
--       EnergyBall 12 / tsunami 7 처럼. 나머지는 이 값이 실효 간격이 된다.
--    클라 표시는 TaggerGlobalCDUntil/Length 속성으로 자동 반영된다.
-- 🔺 [밸런스 2026-09-18] 2 → 1. 1단계 처치가 목표에 구조적으로 미달해서 올린다.
--   [왜] 러너 쪽 구제가 두 겹으로 쌓였는데 태거 예산은 그대로였다 —
--     · 내구도(기본 1칸): 첫 히트를 먹는다
--     · 봇 부활(2026-09-18 도입): 다운을 되돌린다 → 다음 히트에 즉사
--     실효로 **1킬당 히트 약 2.7회**가 됐다. 목표 5킬 = 히트 13~14회인데
--     굴리기 3종 실측은 86초에 스폰 30회 · 명중 27% = 히트 8회뿐이었다.
--   [실측 4판] 1단계 처치 9 / 3 / 1 / 0 (평균 3.25, 목표 5.0). `⚠️ 1단계 약함`이 상시.
--   [효과] 3종 회전 시 실효 간격 2.0 → 1.0 초. 실플레이 반응시간을 얹어 약 1.8배.
--   ⚠️ [전환 보상이 1.5배 → 3배로 커진다] 같은 아이템 3초 vs 전환 1초.
--     위 [BASE-COOLDOWN] 주석의 "전환에 보상" 의도는 유지되지만 **강도가 두 배**다.
--     한 아이템만 쓰는 플레이가 지금보다 훨씬 나빠진다 — 의도한 방향이되 폭이 커졌다.
--   ⚠️ [로드아웃 칸 수가 더 중요해진다] 3종이면 전역이 천장(1.0)이지만,
--     2종이면 개별 쿨 3초가 천장이라 실효 1.5초다. 칸이 많을수록 유리해진다.
--   ⚠️ [고급템은 거의 안 바뀐다] EnergyBall 12 / tsunami 7 처럼 개별 쿨이 긴 것은
--     그쪽이 천장이라 이 값과 무관하다. 바닥 로드아웃(굴리기 3종)만 크게 오른다 —
--     신규 태거 리텐션이 이 변경의 목적이므로 의도한 편중이다.
--   ⚠️ [유저전에도 그대로 적용된다] 봇 전용 보정이 아니라 규칙이다.
--     숙련 태거도 같이 빨라진다. 봇전 수치는 그대로 유저전으로 옮겨도 된다.
--   ⚠️ 되돌릴 값: 2. 1단계 처치가 목표 5.0 을 크게 넘기면 1.5 를 먼저 시도할 것.
-- 🔻 [밸런스 2026-09-18 재조정] 1 → 1.5. 위 경고대로 1.0 은 과했다.
--   [실측] GLOBAL 2.0 일 때 1단계 처치 9·1·3·0 (평균 3.25) →
--          GLOBAL 1.0 일 때 7·9 (평균 8.0). 두 판 모두 `⚠️ 1단계 과함`.
--   [1.5 예상] 실효 약 2.1초. 목표 5.0 근처를 겨냥한 중간값이다.
-- 🔙 [되돌림 2026-09-18] 1.5 → 2. **축을 잘못 골랐다.**
--   [무엇이 틀렸나] 이 인하의 목적은 "뉴비 태거가 바닥 로드아웃으로 못 이긴다" 였다.
--     그런데 쿨은 **숙련도에 비례해 효과가 커지는 축**이다 — 빠른 쿨은 조준·판단이 좋은
--     사람이 더 잘 쓴다. 숙련도 격차를 좁히는 게 아니라 벌린다.
--     목적이 "격차 좁히기"인데 "격차를 벌리는 손잡이"를 당긴 셈이다.
--   [실측 근거 — 승률] 1단계 처치 수보다 이쪽이 명확했다.
--     GLOBAL 2.0 : 킹 2 · 러너 2 (50/50)
--     GLOBAL 1.5 : 킹 4 · 러너 0   ← 제작자(숙련자) 기준 4연승
--     그리고 2단계가 껍데기가 됐다 — 진입 2명 / 킹 피해 20 / 13초 종료.
--   ⚠️ [1단계 처치 수로는 판별이 안 됐다] 1.5 에서 9·3·4·8 로 평균 6.0 이었지만
--     편차가 목표값 5.0 만큼 커서 2~4판으로는 유의미한 차이를 못 읽는다.
--     같은 실수를 반복하지 말 것 — **승률이 처치 수보다 빨리 신호를 준다**.
--   [대신 무엇을 했나] 러너 구제를 줄이는 쪽으로 옮겼다(ReviveSystem.REVIVE_DURATION
--     1.5 → 2). 부활 완료가 판당 4건 → 2건으로 줄었고, 그 축은 조준 실력과 무관하게
--     모두에게 균등히 걸린다. ⚠️ "홀드가 실력에 덜 민감하다"는 추론이지 측정은 아니다.
--   ⚠️ [이 축은 봇전으로 닫히지 않는다] 진짜 뉴비 태거의 퍼포먼스는 라이브에서만 나온다.
--     제작자 플레이는 최적에 가깝고 봇전에는 뉴비가 없다.
--     라이브에서 `📋 [RoundSummary] 1단계 처치` 와 `📡 [Telemetry] 승자` 를
--     플레이 횟수 구간별로 갈라 봐야 뉴비/숙련자 격차가 드러난다.
local GLOBAL_COOLDOWN  = 2
local globalCooldown   = {}   -- [userId] = 마지막 소환 시각(아이템 무관)

-- ⚠️ 전방 선언. 실제 표는 아래에서 채운다.
--    setGlobalCooldown 이 ITEM_COOLDOWN 을 참조하는데, 원래 선언이
--    그 함수보다 아래에 있어 함수 안에서는 nil(전역)로 잡혔다.
--    Lua 는 뒤에 선언된 local 을 앞선 클로저가 못 본다.
local ITEM_COOLDOWN
-- ⚠️ [2026-08-26] GLOBAL_CD_EXEMPT 도 같은 이유로 전방 선언한다.
--    setGlobalCooldown(바로 아래)이 이 표를 참조하는데, 실제 정의는
--    ITEM_COOLDOWN 옆(약 380행)에 있어 그대로 두면 함수 안에서 nil 로 잡히고
--    아이템 소환 때마다 "attempt to index nil" 로 통째로 죽는다.
--    (같은 함정을 ITEM_COOLDOWN 에서 이미 한 번 밟았다 — 바로 위 주석)
local GLOBAL_CD_EXEMPT
local LOCK_STATE_ITEMS

-- 전역 쿨 기록 + 클라 표시용 속성 갱신.
-- 속성값은 workspace:GetServerTimeNow() 기준 "끝나는 시각" — 서버/클라 시계가 동기화돼 있어
-- 클라가 그대로 비교하면 남은 시간을 정확히 계산할 수 있다(tick()은 기기별로 달라 못 씀).
-- 🤖 [2026-08-26] 봇 안전 FireClient.
--
-- [문제] 태거 봇은 pseudoPlayer(평범한 Lua 테이블)를 넘긴다. FireClient 는
--   Player 인스턴스를 요구하므로 그대로 부르면 터진다:
--     "Unable to cast value to Object"
--   가드가 '자기 근처 소환 금지' 한 곳에만 있었고 나머지 4곳에는 없어서,
--   봇이 스피어 외 아이템을 쏠 때마다 발사가 실패했다.
--   (실측 15:54 판: Wooden Barrel·Wood Log 전부 "발사 실패", 스피어만 정상.
--    스피어는 _G.throwSpear 라는 다른 경로를 타서 영향이 없었다)
--
-- ⚠️ 봇에게 UI 안내를 보내는 건 의미가 없다 — 볼 화면이 없다. 조용히 건너뛴다.
-- ⚠️ 새로 FireClient 를 추가할 때는 반드시 이 함수를 쓸 것.
--   직접 부르면 봇 경로에서만 터지는데, 호출부가 pcall 안이라 조용히 실패한다.
-- ⚠️ setGlobalCooldown 보다 위에 있어야 한다(그 함수가 이걸 쓴다).
local function safeFireClient(remote, player, ...)
    if not remote then return end
    if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
    remote:FireClient(player, ...)
end

local function setGlobalCooldown(player, currentTime, itemName)
    -- 🎯 [계측 2026-09-20] 1단계 아이템 사용 횟수. 밸런스에 영향 없음.
    --   [왜 여기인가] 이 함수는 호출 10곳 전부가 `playerCooldowns[...] = currentTime` 직후라
    --     "사용이 성공했다"의 **유일한 깔때기**다. 각 스폰 경로에서 따로 세면 반드시 하나를 빠뜨린다.
    --   ⚠️ 1단계만 센다. _G.RoundObs.stage2At 이 0 이면 아직 1단계다(Stage2TriggerSystem 이 세운다).
    --   ⚠️ 면제 아이템(bear_trap·Spear)도 센다 — 면제는 '전역 쿨을 안 먹는다'지 '안 썼다'가 아니다.
    --   ⚠️ 상한·구역 거부로 쿨을 안 먹은 건 여기 도달 전에 return 되므로 자동으로 빠진다.
    --     실제로 나간 것만 분모에 들어가는 게 맞다(bear_trap 거부 경로 주석 참조).
    do
        local obs = _G.RoundObs
        if obs and (obs.startAt or 0) > 0 and (obs.stage2At or 0) == 0 then
            obs.s1Spawns = (obs.s1Spawns or 0) + 1
        end
    end
    -- 🪤 [2026-08-26] 전역 쿨 면제 아이템은 타임스탬프를 남기지 않는다.
    --   남기면 "함정 깔았더니 다른 아이템이 2초 잠김" 이 되어, 면제가
    --   오히려 페널티가 된다. 위쪽 검사 면제와 반드시 한 짝으로 움직인다.
    local exempt = itemName ~= nil and GLOBAL_CD_EXEMPT[itemName] == true
    if not exempt then
        globalCooldown[player.UserId] = currentTime
        player:SetAttribute("TaggerGlobalCDUntil", workspace:GetServerTimeNow() + GLOBAL_COOLDOWN)
        player:SetAttribute("TaggerGlobalCDLength", GLOBAL_COOLDOWN)
    end

    -- ⏱️ [수정 2026-08-25] 아이템 리스트 쿨 표시(ItemCooldownStart)를 여기서 쏜다.
    --
    -- [문제] 원래 이 블록은 소환 분기 안에 직접 들어가 있었는데,
    --   들여쓰기가 4칸이라 최상위처럼 보였을 뿐 실제로는
    --   `if itemName == "tsunami"` 분기 안에 갇혀 있었다(619~625행).
    --   → 쓰나미를 쓸 때만 발사되고 Spear·Demonspear·EnergyBall 등
    --      나머지 전부는 클라에 쿨을 안 알려줘 리스트에 아무것도 안 떴다.
    --   문법은 멀쩡해서 get_script_analysis 로도 안 잡혔다.
    --
    -- [해결] setGlobalCooldown 은 이미 모든 소환 분기가 부른다
    --   (626·643·660·678·691·707·723·740·819·1271).
    --   여기에 두면 분기마다 복붙할 필요가 없고, 앞으로 분기가
    --   늘어도 자동으로 따라온다.
    -- ⚠️ itemName 은 선택 인자다. 안 넘겨도 전역 쿨은 정상 동작한다
    --   (클라가 globalCdUntil 로 오버레이를 띄운다).
    if itemName then
        local cdEv = ReplicatedStorage:FindFirstChild("ItemCooldownStart")
        -- 면제 아이템은 전역 쿨을 0으로 알린다 → 클라가 globalCdUntil 을 갱신하지 않는다.
        safeFireClient(cdEv, player, itemName,
            ITEM_COOLDOWN[itemName] or DEFAULT_COOLDOWN, exempt and 0 or GLOBAL_COOLDOWN)
    end
end

-- 💸 [2026-08-28] 아이템 쿨 환불 — '비행 후 거부' 전용.
--   [왜 필요한가] 위임 아이템의 거부는 두 종류다.
--     · 던지기 전 거부(중복 시도 등) → spawnX 의 반환값 false 로 처리. 쿨을 아예 안 건다.
--     · 비행 후 착탄 거부(성문 등)   → 이미 true 를 받아 쿨이 시작된 뒤라 되돌려야 한다.
--   [증상] map1 에서 블랙홀 성문 거부 3연발이 각각 7초를 먹어 21초를 날렸다
--     (실측 12:53:41 / 49.5 / 56.9 — 전부 🚫 성문 구조물 착탄).
--   ⚠️ 전역 쿨(2초)은 되돌리지 않는다. 그건 '연타 방지'라 던진 사실 자체로 정당하고,
--     되돌리면 거부를 유도해 연타하는 우회가 생긴다. 아이템 쿨만 푼다.
--   ⚠️ 클라 표시도 같이 꺼야 한다. 서버만 풀면 UI 는 잠긴 채로 남는다
--     ("한쪽만 보내면 영구 잠김" — TaggerUIScript 의 SetItemLock 규약과 같은 함정).
_G.RefundItemCooldown = function(player, itemName)
    if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
    if type(itemName) ~= "string" then return false end
    local tbl = playerCooldowns[player.UserId]
    if not tbl or tbl[itemName] == nil then return false end
    tbl[itemName] = nil
    -- 쿨 길이 0 으로 다시 알려 클라 표시를 즉시 해제한다.
    local cdEv = ReplicatedStorage:FindFirstChild("ItemCooldownStart")
    safeFireClient(cdEv, player, itemName, 0, 0)
    print(string.format("💸 쿨 환불: %s (%s)", itemName, player.Name))
    return true
end
--
-- ⚠️ [2026-08-26] 여기 없는 아이템은 DEFAULT_COOLDOWN(3.0)으로 떨어진다.
--   그런데 3.0 은 사실상 "쿨 없음" 이다 — 전역 쿨이 2.0 이고, 실측상 태거는
--   1단계 46초에 최대 23회 쓸 수 있는데 실제로는 10~13회밖에 안 쓴다.
--   조준·판단·전환에 걸리는 사람의 조작 속도가 진짜 상한이기 때문이다.
--   → 쿨이 실제로 제약이 되려면 7초는 넘어야 한다. 그 아래 값은 바꿔도
--     판이 안 바뀌므로, 여기서 밸런스를 잡으려 하면 헛돈다.
--   ⚠️ 즉 약한 아이템을 3↔5 사이에서 조정하는 건 의미가 없다.
--     실질 손잡이는 아이템의 효과 값(커버폭·반경·지속)이다.
--     (실측 근거: 통나무 폭 40→30 은 판을 바꿨지만, 쿨 3→5 는 안 바꾼다)
--
-- ⚠️ 키는 ServerStorage.TaggerItem 의 인스턴스 이름과 정확히 같아야 한다.
--   틀리면 조용히 DEFAULT_COOLDOWN 으로 떨어지고 아무 경고도 안 뜬다.
--   (tnt·tsunami·bear_trap 은 소문자, "Frost Dragon" 은 공백 포함)
-- ═══════════════════════════════════════════════════════════
ITEM_COOLDOWN = {
	-- ⚠️ [밸런스 2026-08-25] Demonspear 3 → 8.
	--    즉사 반경 22 + 잔불에 경고가 없어 EnergyBall(반경 10, 쿨 12)보다
	--    시간당 위협이 45배였다. 경고 0.8초를 넣으면서 쿨도 맞춘다.
	["Demonspear"]   = 8,
	["EnergyBall"]   = 12,   -- 즉발 장거리 관통 — 가장 강한 제약
	-- 🧍 [밸런스 2026-09-19] ItemNoob 3 → 7.
	--   [왜 전용 쿨인가] 뉴비는 "던지고 끝"이 아니라 **자율 추적하는 지속 위협**이다
	--     (ItemSpawnHandler:1642 "뉴비 지그재그 주행 활성화"). 성격상 Demonspear(8)·
	--     Frost Dragon(8) 과 같은 그룹인데 쿨만 굴리기와 같은 3 이었다.
	--   [실측 2026-09-19] 뉴비를 단독으로 쓴 판: **1단계 처치 10/10, 2단계 미도달, 88초.**
	--     다른 판이 0~6 인데 혼자 목표(5.0)의 2배다. 투척 21회 / 간격 3.8초.
	--   [왜 3 이 실제로 병목이었나] 위 주석은 "3↔5 조정은 의미 없다"고 하는데,
	--     그건 **여러 아이템을 전환하며 쓸 때**의 얘기다. 한 아이템만 연타하면
	--     그 아이템 쿨이 직접 상한이 된다 — 실측에서 시도 ~32회 중 **11회(34%)가
	--     쿨에 막혔다**(`⏱️ ItemNoob 쿨타임 0.5초 남음`). 즉 여기선 쿨이 먹힌다.
	--   [값 7 의 근거] 간격 3.8초 → 10킬. 목표 5킬이면 간격 약 7.6초.
	--     그리고 위 주석의 "쿨이 제약이 되려면 7초는 넘어야 한다"와 같은 값으로 모인다.
	--   ⚠️ [청소와 무관하다] 같은 날 FirePressureSystem 의 청소 그물에 뉴비를 포함시켰지만,
	--     그 청소는 불벽 **뒤쪽**(이미 러너가 없는 죽은 영역)만 지운다. 위협으로 작동하는
	--     뉴비는 전부 불벽 앞에 있다. 청소는 순수 성능이고 밸런스 손잡이가 아니다.
	--   ⚠️ 되돌릴 값: 3. 1단계 처치가 3 이하로 떨어지면 5 를 먼저 시도할 것.
	["ItemNoob"]     = 7,
	["tsunami"]      = 6,    -- 광역이지만 지속 3초뿐(다운 10초의 30%) → 7 에서 완화
	["tnt"]          = 7,    -- 즉사 반경 75, 반응 2.0초 — 전 아이템 중 최대 커버
	["Frost Dragon"] = 8,    -- 커버 40.6 + 잔류 지대. 상점 최고가 아이템
	["BlackHole"]    = 7,    -- 흡인 반경 70 + 6초 고정
	-- 🪤 [2026-08-26] bear_trap 만 예외적으로 1.0.
	--    [왜] 설치형은 "던져서 맞히는" 아이템과 성격이 다르다. 총 위협량은
	--    MAX_TRAPS_PER_OWNER(5)가 이미 묶고 있어서, 쿨을 줄여도 동시에 존재하는
	--    함정 수는 그대로다. 빨라지는 건 '배치 속도'뿐 — 태거가 함정밭을
	--    빠르게 구성하고 다른 아이템으로 넘어갈 수 있게 된다.
	--    ⚠️ DEFAULT_COOLDOWN(3)보다 짧은 유일한 값이다. 표에 명시하지 않으면
	--       조용히 3으로 떨어지므로 반드시 키를 유지할 것.
	["bear_trap"]    = 0.5,  -- ⚠️ [2026-09-19] 1.0 → 0.5. 동시 5개 상한(MAX_TRAPS_PER_OWNER)이
	                        --    총 위협량을 묶고 있어, 빨라지는 건 배치 속도뿐이라는 위 논거가 그대로 성립한다.
	-- 🗡️ [2026-09-19] Spear. 표에 없어서 조용히 DEFAULT_COOLDOWN(3) 으로 떨어지던 것을 명시한다.
	--    [왜] 직선 투사체라 봇 회피에 가장 약하다 — 실측 명중률 18~29% (굴리기 34%의 절반).
	--    ⚠️ GLOBAL_CD_EXEMPT 에도 같이 넣었다. 개별 1 만 두면 전역 2 가 위에 있어
	--       "UI 는 쿨이 끝났다는데 못 던지는" 거짓 상태가 된다(아래 BASE-COOLDOWN 주석 참조).
	--    🔴 [알고 넣은 위험] bear_trap 과 달리 Spear 는 즉발 다운이고 동시 개수 상한이 없다
	--       (SpearSystem 부팅 로그가 "무제한"). 면제는 양방향이라 Spear 를 끼워 넣으면
	--       세트 전체의 전역 쿨이 사라진다. 1단계 처치가 급증하면 여기부터 의심할 것.
	--    🔴 [되돌리는 법] 이 키를 지우고 GLOBAL_CD_EXEMPT 에서도 지운다. 반드시 둘 다.
	["Spear"]        = 1.5,
}

-- 🤖 [2026-08-31] 태거봇이 같은 쿨을 쓰도록 노출한다.
--   [왜] 봇 티어 테이블에 쿨을 복사해 두면 값이 두 곳에 생겨, 여기만 고쳤을 때
--     봇은 옛 값으로 계속 돈다. HP 공식을 봇·유저 공통으로 통일한 것과 같은 이유다 —
--     봇전 측정이 실전으로 옮겨가려면 두 쪽이 같은 수를 봐야 한다.
--   ⚠️ 표에 없는 이름은 DEFAULT_COOLDOWN(3)으로 떨어진다. 이건 의도된 폴백이다.
--   ⚠️ 전역 쿨(GLOBAL_COOLDOWN)은 여기 포함하지 않는다. 봇은 fireInterval 로
--     자체 발사 리듬을 갖고, 실제 소환 시점에 전역 쿨이 별도로 걸린다.
_G.GetItemCooldown = function(itemName)
	return ITEM_COOLDOWN[itemName] or DEFAULT_COOLDOWN
end

-- ⚠️ [BASE-COOLDOWN 예외] 전역 쿨(GLOBAL_COOLDOWN=2)을 적용하지 않는 아이템.
--   [왜] 실효 간격은 max(개별 쿨, 전역 쿨)이다. bear_trap 을 1.0 으로 낮춰도
--   전역 2.0 이 위에 있으면 실제 간격은 2.0 그대로고, 코드만 거짓말을 하게 된다.
--   (TrapSystem 주석에 같은 경고가 이미 있었다 — 그 전제를 여기서 깬다)
--   [안전한 이유] 전역 쿨의 목적은 '아이템을 바꿔가며 하는 난사' 차단이다.
--   bear_trap 은 즉발 피해가 없는 설치형이고 동시 5개 상한이 따로 있어,
--   이 경로로 늘어나는 건 순간 화력이 아니라 배치 속도뿐이다.
--   ⚠️ 양방향 예외다: 전역 쿨에 막히지도 않고, 걸지도 않는다.
--      한쪽만 하면 "함정 깔면 다른 아이템이 2초 잠김" 같은 비대칭이 생긴다.
--   ⚠️ 클라 표시(TaggerUIScript GLOBAL_CD_EXEMPT)와 한 짝이다. 항목을 추가하면 같이 추가할 것.
--   ⚠️ 전방 선언된 것에 대입한다 — 여기에 `local` 을 붙이면 새 지역변수가 되어
--      위쪽 setGlobalCooldown 이 보는 건 여전히 nil 이다 (ITEM_COOLDOWN 과 같은 규칙).
GLOBAL_CD_EXEMPT = {
	["bear_trap"] = true,
	["Spear"]     = true,   -- 🗡️ [2026-09-19] 위 ITEM_COOLDOWN 의 Spear 주석 참조
}


-- 🔒 [2026-08-27] '상태 잠금' 아이템 — 표 쿨과 별개로 효과가 끝나야 다시 쓸 수 있다.
--   Frost Dragon : _G.FrostCooldown (얼음 파쇄까지, 실측 약 26초)
--   tox_box      : 이전 박스가 베이스에 도달할 때까지
--   tnt          : 폭격 조준이 끝날 때까지
--   BlackHole    : 홀이 소멸할 때까지 (비행 ~2초 + 수명 6초 ≈ 8초 > 표 쿨 7초)
--
-- [쓰임] 쿨 안내 문구를 억제한다. 표 쿨(8/3/7/7)이 끝나도 못 쓰는데
--   "N초 뒤 가능" 이라고 숫자를 말하면 그게 곧 거짓말이 된다
--   (실측 스크린샷: "tnt needs 5s" 가 떴는데 5초 뒤에도 못 씀).
--   대신 아이템 버튼에 IN FLIGHT / IN USE / AIMING 텍스트가 뜬다(SetItemLock).
--
-- ⚠️ 전방 선언된 것에 대입한다 — `local` 을 붙이면 새 지역변수가 되어
--   위쪽 검사부가 보는 건 여전히 nil 이다 (ITEM_COOLDOWN / GLOBAL_CD_EXEMPT 와 같은 규칙).
-- ⚠️ SetItemLock 을 새로 거는 아이템이 생기면 여기에도 추가할 것.
-- ⚠️ [판별 기준] "표 쿨보다 잠금이 길어질 수 있는가" 만 본다. 잠금이 있어도 쿨보다
--   항상 짧으면 거짓 표시가 생기지 않으므로 넣지 않는다.
--   예: Demonspear 는 activeUntil 잠금이 있지만 최대 4.1초(비행 0.8 + 잔불 3 + 0.3)로
--   표 쿨 8초 안에 항상 들어간다 → 대상 아님.
LOCK_STATE_ITEMS = {
	["Frost Dragon"] = true,
	["tox_box"]      = true,
	["tnt"]          = true,
	["BlackHole"]    = true,
	-- 🧍 [2026-09-20] ItemNoob 추가. 아래 단일 존재 잠금이 표 쿨(7)보다 길어질 수 있다.
	["ItemNoob"]     = true,
}

-- 🧍 [2026-09-20] 뉴비 단일 존재 잠금 — tox_box 와 같은 형태로 기준을 통일한다.
--   [왜] 둘 다 "던지고 끝"이 아니라 월드에 남아 자율 이동하는 잔존형인데 쿨 기준이 달랐다:
--     · tox_box  : 객체 수명 기준(playerActiveBox) — 베이스 도달·차단까지 재사용 불가, 동시 1개
--     · ItemNoob : 시간 기준(ITEM_COOLDOWN 7) — 동시 개수 제한 없음
--     같은 성격인데 제약의 종류가 달라 한쪽 밸런스 경험이 다른 쪽으로 옮겨지지 않았다.
--   [통일 규칙] 둘 다 "내가 낸 것이 사라질 때까지 재사용 불가 + 동시 1개".
--     뉴비가 사라지는 시점은 불벽이 따라잡을 때(FirePressureSystem.cleanupItemsBehindFire)
--     또는 라운드 종료 정리다. 톡스박스는 베이스 도달·완전 차단이다.
--   ⚠️ 표 쿨 7 은 남겨둔다. 이제 상한이 아니라 **하한**이다(뉴비가 즉시 파괴돼도 7초는 기다린다).
--     tox_box 와 완전히 같게 하려면 ITEM_COOLDOWN 에서 ItemNoob 을 빼면 된다(→ DEFAULT 3).
--   ⚠️ _G.SetItemLock 은 UI 전용이다(FireClient 한 줄). 진짜 판정은 이 테이블이다 —
--     tox_box 의 playerActiveBox 와 같은 역할. 둘 중 하나만 고치면 표시와 판정이 어긋난다.
--   ⚠️ 봇(pseudoPlayer)은 제외한다. UserId 가 -1 로 전부 같아서 한 칸을 모든 봇이
--     공유하게 되고, 봇 하나가 뉴비를 내면 나머지 봇이 전부 막힌다. 봇은 기존 시간 쿨만 받는다.
local playerActiveNoob = {}   -- userId → 뉴비 인스턴스

local function isRealPlayer(p)
	return typeof(p) == "Instance" and p:IsA("Player")
end

-- 살아 있는 내 뉴비가 있으면 그걸 돌려준다. 죽은 참조는 여기서 정리한다
-- (spawnToxBox:742 의 "reference만 남음 → 정리하고 진행"과 같은 형태).
local function activeNoobOf(player)
	if not isRealPlayer(player) then return nil end
	local cur = playerActiveNoob[player.UserId]
	if cur and cur.Parent then return cur end
	playerActiveNoob[player.UserId] = nil
	return nil
end

-- ⚠️ 해제를 개별 소멸 경로에 흩어 놓지 않는다. 뉴비는 tox_box 의 cleanupBox 같은
--   단일 깔때기가 없고 소멸 경로가 여럿이다(불벽 청소 · 라운드 정리 · 수동 삭제).
--   → 인스턴스 자신의 Destroying 에 건다. 어느 경로로 사라지든 반드시 지나간다.
--   (ToxBoxSystem:371 "개별 경로에 흩어 놓으면 하나 빠뜨렸을 때 영구 잠김" 과 같은 교훈)
local function registerNoobInstance(player, obj)
	if not isRealPlayer(player) or not obj then return end
	local uid = player.UserId
	playerActiveNoob[uid] = obj
	if _G.SetItemLock then _G.SetItemLock(player, "ItemNoob", true, "IN USE") end
	obj.Destroying:Connect(function()
		if playerActiveNoob[uid] == obj then
			playerActiveNoob[uid] = nil
			local p = game:GetService("Players"):GetPlayerByUserId(uid)
			if p and _G.SetItemLock then _G.SetItemLock(p, "ItemNoob", false) end
		end
	end)
end

-- 🔄 라운드 경계 안전망. RoundSystem 이 _G.resetToxBox 옆에서 부른다.
--   Destroying 이 어떤 이유로든 안 불린 경우에도 잠금이 다음 라운드로 새지 않게 한다.
_G.resetNoobLock = function()
	for uid in pairs(playerActiveNoob) do
		local p = game:GetService("Players"):GetPlayerByUserId(uid)
		if p and _G.SetItemLock then _G.SetItemLock(p, "ItemNoob", false) end
	end
	playerActiveNoob = {}
end
-- 핸들러를 이름 있는 함수로 분리: RemoteEvent(유저) + _G.BotSpawnItem(태거 봇) 겸용.
-- 봇은 의사 player 테이블 {Name, UserId=-1, GetAttribute→nil, Character=봇모델}로 호출.
-- GetAttribute가 nil이면 스킨 분기가 전부 기본 경로로 흘러 기본 스킨 스폰.
-- 태거 베이스 위 클릭인지 (회전 고려 XZ 박스 판정)
-- 베이스(성 앞 평지)는 "푸시툴로만 대항"하는 결투 구역 — 즉사/투척 아이템 반입 금지 원칙.
-- ⚡ [2026-08-28] 파트 목록 캐시. 이 함수는 호출마다 맵 전체를 '두 번' 훑었다.
--   [증상] 블랙홀을 쓸 때마다 서버가 버벅였다.
--   [원인] BlackHoleSystem 흡인 루프가 캐릭터마다 매 프레임 이 함수를 부른다.
--     map1 은 약 3,900 파트라 1회 호출이 ~7,800 순회. 11명 × 60fps = 초당 500만 회.
--   ⚠️ 캐시는 workspace 소속으로 무효화한다. 비선택 맵은 라운드마다 ServerStorage 로
--     옮겨지므로, 한 맵에서 만든 캐시를 다음 맵에서 쓰면 엉뚱한 파트를 본다.
--     (_G.IsCharInTaggerBase 와 같은 규약 — 둘이 어긋나지 않게 같이 유지할 것)
local _plateCache, _baseCache = nil, nil
local function _cacheStale(list)
    return list == nil or (#list > 0 and not list[1]:IsDescendantOf(workspace))
end
local function _rebuildBaseCaches()
    _plateCache, _baseCache = {}, {}
    for _, mf in ipairs(workspace:GetChildren()) do
        if mf.Name:lower():find("map") then
            for _, d in ipairs(mf:GetDescendants()) do
                if d:IsA("BasePart") then
                    local n = d.Name:lower()
                    if n:find("itemspawnplate") then
                        _plateCache[#_plateCache + 1] = d
                    elseif n:match("^taggerbase%d*$") then
                        _baseCache[#_baseCache + 1] = d
                    end
                end
            end
        end
    end
end

local function isOnTaggerBase(pos)
    if typeof(pos) ~= "Vector3" then return false end
    -- ⚠️ ItemSpawnPlate 위는 합법적 스폰 구역이므로 베이스 판정에서 제외한다.
    --    taggerbase 와 ItemSpawnPlate 의 X 범위가 실제로 겹쳐 있어서
    --    (map1: base 709.2~859.8 / plate 687.8~710.0 → 709.2~710.0 중첩)
    --    TaggerUIScript.projectOntoPlate 가 플레이트 가장자리로 clamp 한 좌표가
    --    다시 베이스 안으로 판정되어 "베이스 조준 → 플레이트 투영" 기능이 막혔다.
    --    ⚠️ EDGE_EPS: clamp 결과는 정확히 경계값(plate.X + Size.X/2)이 되는데
    --       부동소수점 오차로 그 값이 미세하게 범위를 벗어난다.
    --       (실측: clamp 결과 710.0313 vs plate 최대 710.0 → 0.03 초과로 판정 실패)
    --       여유를 주지 않으면 투영 좌표가 영영 통과하지 못한다.
    local EDGE_EPS = 0.5
    if _cacheStale(_plateCache) or _cacheStale(_baseCache) then _rebuildBaseCaches() end
    for _, d in ipairs(_plateCache) do
        if d.Parent then
            local lp = d.CFrame:PointToObjectSpace(pos)
            if math.abs(lp.X) <= d.Size.X / 2 + EDGE_EPS
               and math.abs(lp.Z) <= d.Size.Z / 2 + EDGE_EPS then
                return false   -- 플레이트 위(경계 포함) = 허용
            end
        end
    end
    for _, d in ipairs(_baseCache) do
        if d.Parent then
            local lp = d.CFrame:PointToObjectSpace(pos)
            if math.abs(lp.X) <= d.Size.X / 2 and math.abs(lp.Z) <= d.Size.Z / 2 then
                return true
            end
        end
    end
    return false
end


-- 🚫 [2026-08-27] 태거 베이스 판정을 외부에서도 쓸 수 있게 노출.
--   [왜] BarrelSpillSystem 이 배럴 파열 웅덩이를 베이스 안에도 만들고 있었다.
--     베이스는 "푸시툴로만 대항하는 결투 구역"인데 미끄러짐 지대가 들어가면
--     그 원칙이 깨진다(태거 아이템 반입 금지와 같은 이유).
--   ⚠️ 판정 로직을 복사하지 말 것. 이 함수는 ItemSpawnPlate 중첩·부동소수점 오차까지
--     이미 처리하고 있어(EDGE_EPS), 흉내 내면 그 예외들이 빠진다.
_G.IsOnTaggerBase = isOnTaggerBase

-- 🛡️ [2026-08-28] "이 캐릭터가 태거 베이스 안에 있나" 공용 판정 (살상 면역용).
--   ⚠️ 위 IsOnTaggerBase(pos) 와 '다른 질문'이다. 합치려다 실패했으니 헷갈리지 말 것.
--     · IsOnTaggerBase(pos)       = "여기 소환해도 되나" — 높이 무시, ItemSpawnPlate 면제
--     · IsCharInTaggerBase(model) = "이 캐릭터가 면역인가" — 높이 밴드 O, 플레이트 면제 X
--     소환 판정은 플레이트를 면제해야 하고(합법 스폰 구역), 면역 판정은 면제하면
--     안 된다(플레이트 위 러너도 결투 구역 안이다). 그래서 함수가 둘이다.
--   [왜 만드나] FrostDragon·Bomb·EnergyBall·DemonSpear·Spear 가 같은 로직을 각자
--     복사해 갖고 있었다(5벌). 그중 Spear 만 높이 밴드가 빠져 실제로 갈라졌다.
--   ⚠️ 높이 밴드 +12 를 빼지 말 것. 베이스 파트는 바닥 슬래브라, 그 위에 선 캐릭터의
--     HRP 는 파트 박스 '밖'이다. 밴드가 없으면 서 있는 러너가 면역을 못 받는다.
--     (실측 2026-08-28: map2 castle.taggerbase2 는 두께 2.98 — 밴드 없이는 아무도 안 걸린다)
--   ⚠️ 캐시는 workspace 소속으로 무효화한다. 비선택 맵은 라운드마다 ServerStorage 로
--     옮겨지므로, 한 맵에서 만든 캐시를 다음 맵에서 쓰면 엉뚱한 베이스를 본다.
local _charBaseCache = nil
_G.IsCharInTaggerBase = function(model)
    if not model then return false end
    if _charBaseCache and (#_charBaseCache == 0
        or not _charBaseCache[1]:IsDescendantOf(workspace)) then
        _charBaseCache = nil
    end
    if not _charBaseCache then
        _charBaseCache = {}
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("BasePart") and d.Name:lower():find("taggerbase") then
                _charBaseCache[#_charBaseCache + 1] = d
            end
        end
    end
    if #_charBaseCache == 0 then return false end
    local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
    if not hrp then return false end
    local p = hrp.Position
    for _, bp in ipairs(_charBaseCache) do
        if bp.Parent then
            local lp = bp.CFrame:PointToObjectSpace(p)
            local h = bp.Size * 0.5
            if math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y + 12 and math.abs(lp.Z) <= h.Z then
                -- 🛡️ 막힌 순간을 보여준다. 표시가 없으면 양쪽 다 '버그'로 읽는다.
                if _G.showBaseImmune then _G.showBaseImmune(model) end
                return true
            end
        end
    end
    return false
end
local function handleSpawnRequest(player, spawnPlate, itemName, clickPosition)
    -- ⚠️ 소환 로그는 '요청 1줄'만 남긴다. 예전엔 요청 4줄 + 스폰 5줄 = 9줄이었고,
    --    라운드당 20~40회 소환하면 200줄 넘게 쌓여 실제 에러가 그 사이에 묻혔다.
    --    실패 원인은 아래 차단 분기들이 각자 이유를 찍으므로 추적에 지장 없다.
    -- ⚠️ 쿨다운은 두 값을 모두 보여준다. 전역만 찍으면 "1.5초로 설정됨"으로
    --    오해한 이력이 있다(실측 2026-08-22).
    print(string.format("[Spawn] %s → %s @ %s | 쿨 재사용 %.1fs / 전환 %.1fs",
        player.Name, itemName or "nil", tostring(clickPosition),
        ITEM_COOLDOWN[itemName] or DEFAULT_COOLDOWN, GLOBAL_COOLDOWN))

    -- 🏁 라운드 종료 후 스폰 차단 (킬 이펙트 연출·인터미션 중 아이템 소환 금지)
    -- 🧪 [TEST 2026-08-30] _G.AllowSpawnOffRound 가 true 면 이 가드를 건너뛴다.
    --   [왜] 방패·쓰나미처럼 '설치 후 맞아본다'를 검증하려면 라운드 밖에서 소환해야 한다.
    --     라운드를 돌리면서 하면 봇·불꽃벽·타이머가 끼어들어 원인 분리가 안 된다.
    --   ⚠️ 릴리즈 전 이 분기와 /spawnfree 커맨드를 함께 삭제할 것.
    --     가드 자체는 실전용이므로 지우지 말 것 — 우회 스위치만 지운다.
    if _G.IsRoundLive and not _G.IsRoundLive() and not _G.AllowSpawnOffRound then
        print("🏁 라운드 비활성 — 스폰 차단")
        return
    end

    -- 🚫 태거 베이스 소환 금지 (스피어/에너지볼 등 위임류 포함 전 아이템 공통 — 서버 강제)
    --   ⚠️ 아래 '자기 근처 소환 금지' 의 설계 확정 주석(2026-09-11)과 한 세트다.
    --     둘 다 2단계를 PvP 로 지키는 장치이므로 함께 본다.
    if isOnTaggerBase(clickPosition) then
        print("🚫 태거 베이스 구역 소환 금지:", itemName or "?")
        local nv = game:GetService("ReplicatedStorage"):FindFirstChild("TaggerNoticeEvent")
        safeFireClient(nv, player, "Can't summon inside the castle")
        return
    end
    -- 🚫 태거 자기 근처 소환 금지 (캠핑 방지).
    --   구역 경계로 막으면 '경계 밖으로 한 발' 우회가 성립한다. 통나무처럼 두꺼운
    --   아이템은 계단에서 살짝 떨어져도 계단을 그대로 덮기 때문.
    --   → 위치가 아니라 '태거와 소환 지점의 거리'로 판정한다. 어디에 서든 자기
    --     주변에는 놓을 수 없으므로 우회 지점이 존재하지 않는다.
    --   실측: 정상 플레이(바리케이드 X=733 뒤 → 플레이트 X≈699)는 거리 약 34.
    --         플레이트 가장자리를 노리는 정상 플레이도 살리려 20 으로 둔다.
    --   러너에게 '태거에게 붙으면 아이템을 막는다'는 반격 경로가 생기는 효과도 있다.
    --
    -- 🔒 [설계 확정 2026-09-11] 이 제약을 완화하지 말 것. 2단계는 아이템 축이 아니다.
    --   [단계별 성격] 1단계 = 아이템 중심(다운·즉사 판정, 킹이 사냥한다).
    --     2단계 = 푸시툴 중심의 HP 소모전 PvP(서로 깎는다). 화폐가 다르다.
    --   [과거 실패 이력] 예전엔 2단계도 아이템이 중심축이었다. 제약이 없어서
    --     '계단 근처 캠핑 → 러너 밀침 → 밀착 소환 → 한 방 다운' 이 성립했다.
    --     ⚠️ 기각 사유는 "강해서"가 아니라 "러너가 개입할 여지가 없어서"다.
    --       대처 불가능하고 불쾌하다는 판단으로 걷어냈다. 세기를 조절해도 안 풀린다.
    --   [그래서 지금 상태가 정상이다] 2단계에 `🚫 자기 근처 소환 차단` 이 뜨는 것은
    --     버그가 아니라 이 설계가 작동한 기록이다. "2단계에 아이템이 안 되네" 로 읽고
    --     20 을 낮추거나 예외를 파지 말 것 — 기각된 설계로 되돌아간다.
    --   [남겨둔 예외] 성문 붕괴 직후 강타(KB=90, 잔여속도 27)로 계단 아래로 크게
    --     날렸을 때만 20 stud 가 벌어져 콤보가 성립한다. 그 한 순간은 의도된 보상이다.
    --     ⚠️ 평타(KB=38, 잔여속도 11~14)로는 성립하지 않는다. 래그돌 0.42초 뒤
    --       러너가 즉시 속도 15~19 로 복귀해서다. 이걸 "고쳐야 할 문제"로 보지 말 것.
    --       봇뿐 아니라 Q대시를 가진 숙련 러너 상대로는 더더욱 성립하지 않는 게 맞다.
    do
    	local tChar = player.Character
    	local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
    	if tRoot then
    		local d = (clickPosition - tRoot.Position).Magnitude
    		if d < MIN_SPAWN_DIST then
    			print(string.format("🚫 자기 근처 소환 차단: %s (거리 %.1f < %d)",
    				tostring(itemName), d, MIN_SPAWN_DIST))
    		-- ⚠️ 봇은 pseudoPlayer(평범한 Lua 테이블)를 넘긴다 → safeFireClient 가 걸러낸다.
    			safeFireClient(spawnWarningEvent, player, "Too close! Move back to use items.")
    			return
    		end
    	end
    end

    -- 쿨타임 체크 (아이템별)
    -- ⚠️ 이전에는 전 아이템이 공용 2초 쿨 하나만 공유했다. 그래서 개별 잠금이 없는
    --    EnergyBall/tsunami 는 2초마다 무제한 발사가 가능했다(다른 아이템들은
    --    "동시 1개" 같은 자체 잠금이 있어 실질 제한이 걸려 있었음 — 이 둘만 무방비).
    --    → 아이템별 쿨다운으로 분리. 미등록 아이템은 기존과 동일하게 DEFAULT_COOLDOWN.
    --    참고: TaggerBotSystem.TIERS 가 이미 봇용 아이템별 cd 를 갖고 있다(스피어 9 / 쓰나미 20 /
    --    블랙홀 18 / 톡스박스 15 / 곰덫 12). 사람 태거만 그 개념이 없었던 셈.
    local currentTime = tick()
    if not playerCooldowns[player.UserId] then playerCooldowns[player.UserId] = {} end

    -- ⚠️ 전역 최소 간격: 아이템별 쿨이 서로 독립이라 아이템을 바꿔가며 연사가 가능했다.
    --    (통나무 → 배럴 → 돌 → 통나무... 실측상 초당 여러 발이 나감 = 난사)
    --    아이템 종류와 무관하게 소환 사이 최소 간격을 강제한다.
    local lastAny = globalCooldown[player.UserId]
    if not GLOBAL_CD_EXEMPT[itemName]
       and lastAny and (currentTime - lastAny) < GLOBAL_COOLDOWN then
        local left = GLOBAL_COOLDOWN - (currentTime - lastAny)
        print(string.format("⏱️ 전역 쿨타임 %.1f초 남음", left))
        -- ⚠️ [추가 2026-09-09] 이 분기는 조용히 거부하고 있었다.
        --   [왜 필요한가] 중앙 쿨 바(TaggerItemCooldownClient)가 전역 쿨을 표시하긴 하지만,
        --     교전 중엔 시선이 조준점에 있어 바를 안 본다. 클릭한 '그 순간'의 피드백이 없으면
        --     입력이 먹힌 것처럼 느껴진다(아이템별 쿨 쪽엔 이미 안내가 있었다).
        --   ⚠️ 아이템별 쿨과 문구를 다르게 둔다. 저쪽은 "전환하면 지금 쏜다"가 참이지만
        --     여기선 전환해도 못 쏜다 — 같은 문구를 쓰면 거짓말이 된다(666행 주석 참조).
        safeFireClient(spawnWarningEvent, player,
            string.format("Slow down — %.1fs", left))
        return
    end

    local lastUse = playerCooldowns[player.UserId][itemName]
    local cd = ITEM_COOLDOWN[itemName] or DEFAULT_COOLDOWN
    if lastUse then
        local since = currentTime - lastUse
        if since < cd then
            print(string.format("⏱️ %s 쿨타임 %.1f초 남음 (쿨 %.1fs)", tostring(itemName), cd - since, cd))
            -- [SWAP-HINT] 같은 아이템에 막힌 '그 순간'이 전환 보상을 알리기 가장 좋은 시점이다.
            --   ⚠️ 전역 쿨(위쪽 검사)에 이미 막혔다면 알리지 않는다 —
            --      그건 전환해도 못 쏘는 상황이라 "전환하라"는 안내가 거짓이 된다.
            --      여기까지 왔다는 건 전역 쿨은 통과했다는 뜻이므로 전환하면 즉시 발사된다.
            -- ⚠️ [2026-08-27] 상태 잠금(단일 존재) 아이템은 이 안내를 하지 않는다.
            --   [증상] "tnt needs 5s" 가 떴는데 5초 뒤에도 못 썼다(실측 스크린샷).
            --   [원인] 이 안내는 ITEM_COOLDOWN 표 값(cd)만 본다. 그런데 Frost Dragon /
            --     tox_box / tnt 는 효과가 끝나야 다시 쓸 수 있어(_G.FrostCooldown 등),
            --     표 쿨이 끝나도 잠긴 상태다. 남은 초를 숫자로 말하면 그게 곧 거짓말이다.
            --   ⚠️ 잠금 여부는 서버가 아는 상태(SetItemLock 을 건 그 조건)를 그대로 쓴다.
            if not LOCK_STATE_ITEMS[itemName] then
                -- ⚠️ [버그 수정 2026-09-09] %.0f → %.1f.
                --   [증상] 사용자 제보 — "스톤 소환이 씹히는 느낌".
                --   [원인] 남은 시간이 0.3 초일 때 %.0f 가 "0" 으로 반올림해
                --     "stone needs 0s" 가 떴다. 0초 남았다면서 거부하니 고장으로 읽힌다.
                --   [구조] 이 경로의 남은 시간은 '항상' 1초 미만이다:
                --     전역 쿨(2.0) 을 통과해야 여기 오는데 아이템 쿨은 3.0 이므로
                --     최대 3.0 − 2.0 = 1.0 초만 남는다.
                --     실측 11건 전부 0.3~0.9 였다 → %.0f 로는 "0s"/"1s" 두 값뿐이라
                --     안내로서 아무 정보가 없었다.
                --   ⚠️ 아이템 쿨을 3.0 보다 크게 올리면 이 상한도 같이 커진다.
                --     그때는 %.1f 가 오히려 자연스럽다(예: "2.4s").
                safeFireClient(spawnWarningEvent, player, string.format(
                    "%s needs %.1fs — switch items to throw now", tostring(itemName), cd - since))
            end
            return
        end
    end
    
    -- 태거인지 확인
    if player:GetAttribute("Role") ~= "Tagger" then
        print("❌ Player is not Tagger!")
        return
    end

    -- Frozen 상태 확인 (Ice Bow 봉인)
    if player:GetAttribute("Frozen") then
        print("❄️ Player is Frozen — spawn 거부:", player.Name)
        return
    end
    
    -- 아이템 이름 확인
    if not itemName then
        print("❌ No item name provided!")
        return
    end
    
    -- Frost Dragon 패스 + 쿨타임 체크
    if itemName == "Frost Dragon" then
        _G.FrostCooldown = _G.FrostCooldown or {}
        if _G.FrostCooldown[player.UserId] then
            print("  ❄️ Frost Dragon 쿨타임 중:", player.Name)
            return
        end
        -- 소유 = 게임패스 OR 번들 구매(OwnedItem_frost_dragon).
        -- 개발자상품(Frost Lord Bundle)은 UserOwnsGamePassAsync를 절대 통과 못 하므로 두 번째 항 필요.
        -- LoadoutManager.hasPassCached와 동일 규칙 — 한쪽만 고치면 장착/스폰이 어긋남.
        local owns = player:GetAttribute("OwnedItem_frost_dragon") == true
        if not owns then
            local ok, passOwns = pcall(function()
                return MarketplaceService:UserOwnsGamePassAsync(player.UserId, FROST_DRAGON_PASS)
            end)
            owns = ok and passOwns
        end
        if not owns then
            print("❌ Frost Dragon 미보유(패스/번들 둘 다 없음):", player.Name)
            return
        end
        _G.FrostCooldown[player.UserId] = true
        -- 🔒 실제 잠금 시작을 UI 에 알린다(표 쿨 8초와 무관하게 얼음 파쇄까지 잠긴다)
        if _G.SetItemLock then _G.SetItemLock(player, "Frost Dragon", true, "IN FLIGHT") end
    end
    
    -- 클릭 위치 확인
    if not clickPosition then
        print("❌ No click position provided!")
        return
    end
    
    -- 🛢️ Wooden Barrel: 태거 플레이어 위치와 겹침 체크 (현재 비활성화)
    --[[
    if itemName == "Wooden Barrel" then
        local character = player.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            local dist = (clickPosition - rootPart.Position).Magnitude
            if dist < BARREL_BLOCK_RADIUS then
                print("❌ 배럴이 태거 위치에 너무 가까움! dist:", dist)
                safeFireClient(spawnWarningEvent, player, "Cannot spawn barrel too close to yourself!")
                return
            end
        end
    end
    --]]
    
    -- 아이템 찾기 (스킨 적용 포함 + 보유 이중 체크)
    local actualItemName = itemName
    local stoneSkinData = nil  -- stone 색 스킨이면 {material, color} 저장 → 스폰 후 Part에 칠함
    if _G.getEquippedSkin then
        -- ItemNoob 스킨 체크 (색 스킨은 베이스+색칠, 형태/이펙트 스킨은 모델교체)
        if itemName == "ItemNoob" then
            local skin = _G.getEquippedSkin(player, "ItemNoob")
            if skin and player:GetAttribute("Has_" .. skin) == true then
                local data = _G.getSwordSkinData and _G.getSwordSkinData("ItemNoob", skin)
                if not (data and data.color) then
                    -- 형태/이펙트 스킨(Lava/Ice/Suit/King/등)만 모델교체. 색 스킨은 부위별 색 모드로 흡수.
                    local skinTemplate = taggerItems:FindFirstChild(skin)
                    if skinTemplate then
                        actualItemName = skin
                        print("🎨 스킨 적용:", itemName, "→", skin)
                    end
                end
            end
        -- Wood Log 스킨 체크
        elseif itemName == "Wood Log" then
            local skin = _G.getEquippedSkin(player, "Wood Log")
            if skin then
                local ownsSkin = player:GetAttribute("Has_" .. skin) == true
                local skinTemplate = taggerItems:FindFirstChild(skin)
                if ownsSkin and skinTemplate then
                    actualItemName = skin
                    print("🎨 스킨 적용:", itemName, "→", skin)
                else
                    print("⚠️ 스킨 폴백:", skin)
                end
            end
        -- stone 스킨 체크 (색 스킨은 베이스+색칠, 이펙트 스킨은 모델교체)
        elseif itemName == "stone" then
            local skin = _G.getEquippedSkin(player, "stone")
            if skin and player:GetAttribute("Has_" .. skin) == true then
                local data = _G.getSwordSkinData and _G.getSwordSkinData("stone", skin)
                if data and data.color then
                    stoneSkinData = data  -- 색 스킨: 베이스 stone 유지 + 색칠(스폰 후)
                    print("🎨 stone 색 스킨:", skin)
                else
                    local skinTemplate = taggerItems:FindFirstChild(skin)
                    if skinTemplate then
                        actualItemName = skin  -- 이펙트 스킨(Rainbow/Lava/등): 모델교체
                        print("🎨 스킨 적용:", itemName, "→", skin)
                    end
                end
            end
            -- _Custom: 색/이펙트 스킨 없으면 StoneColor/StoneMaterial 속성으로 색칠
            if actualItemName == "stone" and not stoneSkinData then
                local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
                local cfg = palette.getConfig("stone")
                local colorName = player:GetAttribute("StoneColor_Rock") or cfg.zoneDefault.Rock
                if colorName and palette.COLORS[colorName] then
                    local finishKey = player:GetAttribute("StoneMaterial_Rock") or cfg.materialDefault
                    local baseColor = palette.COLORS[colorName]
                    local f = palette.FINISHES[finishKey]
                    if f then
                        stoneSkinData = { material = f.material, color = f.tint or baseColor }
                    else
                        stoneSkinData = { material = "Slate", color = baseColor }
                    end
                end
            end
        -- 배럴 커스텀 색: BarrelColor_Body / BarrelColor_Rings 속성으로 Body/Rings 각각 색칠
        elseif itemName == "Wooden Barrel" then
            -- ① 모델 교체형 스킨 우선 (Crusader 등): 장착 + 소유 시 스킨 모델을 스폰
            local bskin = _G.getEquippedSkin(player, "Wooden Barrel")
            local barrelSkinModel = bskin and taggerItems:FindFirstChild(bskin)
            if bskin and barrelSkinModel and player:GetAttribute("Has_" .. bskin) == true then
                actualItemName = bskin  -- CrusaderBarrel 등 → 아래서 이 모델 스폰
                print("🎨 배럴 모델 스킨:", bskin)
            else
                -- ② 커스텀 색: BarrelColor_Body / BarrelColor_Rings 속성으로 Body/Rings 각각 색칠
                local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
                local cfg = palette.getConfig("Wooden Barrel")
                if cfg then
                    barrelSkinData = { zones = {} }
                    for _, zone in ipairs(cfg.zones) do  -- {"Body","Rings"}
                        local colorName = player:GetAttribute("BarrelColor_" .. zone) or (cfg.zoneDefault and cfg.zoneDefault[zone])
                        if colorName and palette.COLORS[colorName] then
                            local finishKey = player:GetAttribute("BarrelMaterial_" .. zone) or cfg.materialDefault
                            local f = palette.FINISHES[finishKey]
                            barrelSkinData.zones[zone] = {
                                color = (f and f.tint) or palette.COLORS[colorName],
                                material = (f and f.material) or "Wood",
                            }
                        end
                    end
                end
            end
        end
    end
    local isItemNoob = (itemName == "ItemNoob")
    local isFrostDragon = (itemName == "Frost Dragon")
    local isSpikedWood  = (actualItemName == "SpikedWood")
    -- _CollisionCore 구조를 쓰는 ItemNoob 계열 스킨(GoldNeonNoob + 뉴비 스킨들)
    local NOOB_SKINS = {
        GoldNeonNoob = true, IceNoob = true, GlitchNoob = true, SuitNoob = true,
        KingNoob = true, SummerNoob = true, ZombieNoob = true, SoldierNoob = true,
        RainbowNoob = true,
    }
    local isGoldNeonNoob = NOOB_SKINS[actualItemName] == true
    local isRainbowNoob = (actualItemName == "RainbowNoob")  -- (구) 단독 플래그, 호환용
    -- 모든 뉴비 계열(원본 ItemNoob/LavaNoob + 모든 스킨) → 지그재그 주행 적용
    local isAnyNoob = isItemNoob or (actualItemName == "ItemNoob") or (actualItemName == "LavaNoob") or isGoldNeonNoob
    local isGoldenLog = (actualItemName == "GoldenLog")
    local isSunStone = (actualItemName == "SunStone")
    local isBarrel = (itemName == "Wooden Barrel") or (actualItemName == "CrusaderBarrel") or (actualItemName == "OilDrum")
    -- 🛢️ 배럴 물리 상수. 여러 곳에서 쓰므로 여기 한 번만 정의한다.
    -- ⚠️ _CollisionCore(Cylinder) 지름 18.5 의 절반. 이 값이 세 곳에 쓰인다:
    --     ① 스폰 높이(파묻힘 방지)  ② 각속도 = 선속도 ÷ 반지름(구름 조건)
    --   따로 적어두면 하나만 고쳤을 때 배럴이 미끄러지거나 파묻힌다.
    local BARREL_RADIUS = 9.25

    -- 🪨 스톤 계열 판정. 굴러갈수록 커지는 성장 로직에 쓴다.
    -- ⚠️ 이름 기반으로 넓게 잡는다. 실측(2026-08-26) 결과 스톤 스킨이
    --   팔레트 스왑이 아니라 '별도 템플릿' 이었다:
    --     stone / GoldStone / SilverStone / RainbowStone / LavaStone /
    --     PinkStone / BlueStone / GreenStone / DemonFlameStone / SunStone
    --   itemName=="stone" 만 보면 스킨 낀 스톤이 안 커진다.
    -- ⚠️ SunStone 만 Model 이고 나머지는 BasePart 다. 두 경로 모두에 성장을 붙여야 한다.
    local function looksLikeStone(n)
        return type(n) == "string" and n:lower():find("stone") ~= nil
    end
    local isStone = looksLikeStone(itemName) or looksLikeStone(actualItemName)

    -- ═══════════════════════════════════════════════════════════
    -- 🪨 스톤 성장 — 굴러갈수록 커진다.
    --
    -- [왜] 스톤이 통나무의 하위호환이었다. 커버 폭 20 vs 40 인데
    --   구체(Ball)라 축이 없어 지면 요철에 방향이 틀어진다(볼링공).
    --   즉 '좁은데 안 맞기까지' 했다.
    --
    -- [설계] 약점을 고치는 대신 역할을 바꾼다. 커지면서:
    --   ① 커버 폭이 늘어 명중률이 회복된다(약점 상쇄)
    --   ② "멀리 보낼수록 위험하다" 는 거리 보상이 생긴다
    --   ③ 눈에 확 보인다 — 러너가 "지금 피해야 한다" 를 읽을 수 있다
    --   세 아이템 축: 통나무=넓게 눕힌다 / 배럴=못 피하게 한다 / 스톤=커진다
    --
    -- ⚠️ 넉백 강화는 채택하지 않았다. 쓰나미가 이미 밀어내기 담당이라 겹친다.
    -- ⚠️ 질량은 Size 에 비례해 자동으로 늘어난다(밀도 고정). 별도 조정 불필요.
    -- ⚠️ 세 축을 같이 키운다. 한 축만 키우면 타원이 되어 굴림이 더 불안정해진다.
    -- ⚠️ '거리' 가 아니라 '시간' 기준이다. 거리 기반은 매 프레임 이동량을
    --   누적해야 하는데, 스톤은 튀거나 멈췄다 굴러서 누적이 튄다.
    -- ⚠️ 함수로 뽑은 이유: BasePart 경로(대부분)와 Model 경로(SunStone)가
    --   따로 있다. 한쪽만 고치면 스킨에 따라 동작이 갈린다.
    -- ═══════════════════════════════════════════════════════════
    -- 🪨 [밸런스 2026-09-05] 성장 시간 4.0 → 2.5 / 최대 배율 1.75 → 2.20.
    --   [증상] "스톤은 라운드 초반에 써야 이득인데, 다 커질 때쯤이면 러너가 이미
    --     언덕을 꽤 올라와 있어 가치가 떨어진다. 피하면 그만이고 정확도도 낮다."
    --   [왜 4.0 이 늦었나] 굴리기 초기속 25 → 4초면 계단에서 100 stud 지점에서야 완성된다.
    --     러너는 속도 15~19 로 마주 올라오므로 둘이 만나는 지점은 그보다 앞이다.
    --     즉 '커지는 과정'이 실제 교전에 기여하지 못하고, 만날 땐 이미 다 커져 있다.
    --   [2.5 인 이유] 완성 지점이 62 stud — 계단을 막 벗어날 때 최대가 된다.
    --     더 줄이면(2.0 이하) 성장 연출 자체가 안 보여 "처음부터 큰 돌"이 된다.
    --   [2.20 인 이유] 지름 35 → 44. 스톤은 구라서 통나무(옆으로 누운 원통, 폭 30)보다
    --     같은 지름에서도 유효 커버가 좁게 느껴진다. 그 차이를 크기로 메운다.
    --   ⚠️ 두 값을 함께 바꿨다. 보통은 한 번에 하나씩이지만 여기서는 축이 다르다 —
    --     시간은 '언제 세지나', 배율은 '얼마나 세지나'라 서로 상쇄되지 않는다.
    --     결과가 과하면 배율(2.20)부터 되돌릴 것. 시간 단축이 더 근본적인 수정이다.
    --   ⚠️ 각속도는 발사 시점 반지름으로 계산된다. 시작 배율(0.75)을 안 바꿨으므로
    --     그 계산은 영향받지 않는다.
    local STONE_START_SCALE = 0.75   -- 시작 크기 배율 (지름 20 → 15)
    local STONE_MAX_SCALE   = 2.20   -- 최대 크기 배율 (지름 20 → 44)
    local STONE_GROW_TIME   = 2.5    -- 최대까지 걸리는 시간(초)

    local function startStoneGrowth(target)
        -- target: BasePart 또는 Model(PrimaryPart 기준으로 스케일)
        local parts = {}
        if target:IsA("BasePart") then
            parts[target] = target.Size
        else
            for _, p in ipairs(target:GetDescendants()) do
                if p:IsA("BasePart") then parts[p] = p.Size end
            end
        end
        if next(parts) == nil then return end

        for p, base in pairs(parts) do p.Size = base * STONE_START_SCALE end

        task.spawn(function()
            local t0 = os.clock()
            while target.Parent do
                local a = math.min((os.clock() - t0) / STONE_GROW_TIME, 1)
                local scale = STONE_START_SCALE + (STONE_MAX_SCALE - STONE_START_SCALE) * a
                for p, base in pairs(parts) do
                    if p.Parent then p.Size = base * scale end
                end
                if a >= 1 then break end
                -- ⚠️ Size 대입은 물리 재계산을 부른다. 매 프레임 하면 굴림이
                --   끊기므로 0.1초 간격으로 나눈다(눈으로는 연속으로 보인다).
                task.wait(0.1)
            end

            -- 🪨💥 [연출 2026-09-05] 최대 크기 도달 후, 곁을 지나는 러너 화면을 흔든다.
            --   [왜] 지름 44 짜리 바위가 굴러오는데 시각 정보뿐이라 위압감이 약했다.
            --     "가까이 지나가면 땅이 울린다"를 넣어 크기를 몸으로 느끼게 한다.
            --   [왜 성장 완료 후인가] 작을 때부터 흔들면 흔한 잡음이 된다.
            --     최대 크기가 곧 위협의 신호라 그 시점부터만 준다.
            --   [규격] HammerShakeClient 의 (intensity, duration).
            --     기준선 — 잽 1.3/0.18, 강타 피격 1.2~2.4, 슬램 2.2/0.5.
            --     여기는 '피격'이 아니라 '스쳐 지나감'이므로 가장 약한 잽보다 아래로 잡는다.
            --   ⚠️ 사람당 쿨을 둔다. 바위가 옆에 머무르면 매 틱 흔들려 멀미가 난다.
            --   ⚠️ 태거는 제외한다 — 자기가 굴린 돌에 자기 화면이 흔들리면 조준만 방해된다.
            --   ⚠️ 되돌리려면 SHAKE_ENABLED = false.
            local SHAKE_ENABLED   = true
            -- ⚠️ [재조정 2026-09-05] 38 → 60. "근처를 지나갔는데 한 번밖에 안 울린다".
            --   [실측이 말한 것] 4개 돌 전부 '발사 거리 = 최근접 거리'로 일치했다
            --     (28.9 / 31.7 / 32.5 / 37.2). 즉 최근접 순간에 딱 한 번 들어왔다 바로 나갔다.
            --     쿨 문제가 아니라 반경 안 체류 시간 자체가 0.5초도 안 됐다.
            --   [기하] 최근접 d 일 때 반경 R 안을 지나는 길이는 2·√(R²−d²) 다.
            --     d 가 R 에 가까울수록 급격히 짧아진다 — R38·d37.2 면 겨우 15.5 stud(0.39초).
            --   [60 인 이유] 같은 d=32 에서 통과 101 stud → 2.5초 → 5회.
            --     러너가 언덕을 마주 오르는 실제 동선에서 "쿵…쿵…쿵"이 성립한다.
            --   ⚠️ 반경을 키워도 위압감이 흐려지지 않는 이유는 아래 거리 감쇠 때문이다.
            --     먼 곳은 0.36, 코앞은 0.90 으로 갈린다. 반경은 '언제부터 느껴지나'이고
            --     세기는 '얼마나 무섭나'다 — 두 축을 분리해서 잡는다.
            --   ⚠️ 과하면 50 → 44 순으로 내릴 것.
            local SHAKE_RADIUS    = 60     -- 중심 기준. 바위 반지름 22 + 여유 38
            local SHAKE_POWER     = 0.9    -- 잽(1.3)보다 약하게 — 피격이 아니라 근접이다
            local SHAKE_TIME      = 0.22
            -- ⚠️ [재조정 2026-09-05] 1.2 → 0.5. "좀 더 여러 번 울리게" 요청.
            --   [왜 1.2 가 사실상 1회였나] 스톤 속도 25, 러너가 마주 달리면 상대속도 약 40.
            --     반경 38 의 지름 76 을 통과하는 데 1.9초뿐이라 쿨 1.2 로는 한 번밖에 못 넣는다.
            --   [0.5 인 이유] 같은 통과에 3회. "쿵… 쿵… 쿵" 으로 바위가 다가오는 리듬이 생긴다.
            --   ⚠️ 지속(SHAKE_TIME 0.22)보다 길게 유지한다. 짧으면 흔들림이 끊기지 않고
            --     이어져 하나의 긴 진동처럼 뭉개진다 — 리듬이 사라진다.
            --   ⚠️ 더 잦게 하려면 0.35 까지. 그 아래는 0.22 지속과 겹쳐 뭉개진다.
            local SHAKE_PER_USER  = 0.5    -- 같은 사람에게 이 간격보다 자주는 안 흔든다
            if SHAKE_ENABLED then
                local shakeEvent = ReplicatedStorage:FindFirstChild("HammerShakeEvent")
                local core = target:IsA("BasePart") and target
                    or (target:IsA("Model") and (target.PrimaryPart
                        or target:FindFirstChildWhichIsA("BasePart", true)))
                if shakeEvent and core then
                    -- ⚠️ 이 파일에는 `local Players` 가 없다. 1213행 주석 참조 —
                    --   예전에 있다고 가정하고 썼다가 스폰이 통째로 죽은 이력이 있다
                    --   ("attempt to index nil with 'GetPlayers'"). 같은 방식으로 받는다.
                    local PlayersSvc = game:GetService("Players")
                    local lastShake = {}
                    while target.Parent and core.Parent do
                        local now = os.clock()
                        for _, plr in ipairs(PlayersSvc:GetPlayers()) do
                            -- 러너만. 태거는 자기 아이템이라 제외한다.
                            if plr:GetAttribute("Role") == "Runner" then
                                local ch = plr.Character
                                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                                if hrp and hum and hum.Health > 0
                                   and (now - (lastShake[plr] or 0)) >= SHAKE_PER_USER then
                                    local d = (hrp.Position - core.Position).Magnitude
                                    if d <= SHAKE_RADIUS then
                                        lastShake[plr] = now
                                        -- 📉 거리 감쇠: 가까울수록 세게.
                                        --   [왜] 반경 60 은 "언제부터 느껴지나"를 넓힌 값이다.
                                        --     경계와 코앞이 같은 세기면 "근처면 늘 울린다"가 되어
                                        --     크기의 위압감이 오히려 흐려진다.
                                        --   [곡선] 선형이면 반경 60 에서 중간 거리(41)가 0.65 로 너무 세다.
                                        --     제곱을 씌워 가까울 때만 급격히 세지게 한다 —
                                        --     d22→0.90 / d32→0.62 / d41→0.44 / d60→0.27.
                                        --   ⚠️ 최소 0.3 배는 남긴다. 0 이면 경계에서 발사가 무의미해진다.
                                        local near = math.clamp((SHAKE_RADIUS - d) / (SHAKE_RADIUS - 22), 0, 1)
                                        local power = SHAKE_POWER * (0.3 + 0.7 * near * near)
                                        shakeEvent:FireClient(plr, power, SHAKE_TIME)
                                    end
                                end
                            end
                        end
                        task.wait(0.15)
                    end
                end
            end
        end)
        print(string.format("🪨 스톤 성장 시작 (%.2f → %.2f 배, %.1f초)",
            STONE_START_SCALE, STONE_MAX_SCALE, STONE_GROW_TIME))
    end
    -- 🛢️ [2026-08-26] 배럴 굴림 축. 자세를 잡는 곳(위치 설정)과 속도를 주는 곳
    --   ("즉각적인 속도 적용")이 떨어져 있어, 축 정보를 여기에 담아 넘긴다.
    local barrelRollDir, barrelSideAxis = nil, nil

    -- 🌊 Tsunami: 별도 시스템에 위임 (즉시 발동, 직선 진행, push & ragdoll)
    if itemName == "tsunami" then
        if _G.fireTsunami then
            _G.fireTsunami(player, clickPosition)
            playerCooldowns[player.UserId][itemName] = currentTime
    setGlobalCooldown(player, currentTime, itemName)
            -- 청사진 제거
            local blueprintName = "Blueprint_" .. player.Name
            local blueprint = workspace:FindFirstChild(blueprintName)
            if blueprint then blueprint:Destroy() end
            print("🌊 Tsunami dispatched")
        else
            warn("❌ TsunamiSystem not loaded yet (_G.fireTsunami nil)")
        end
        return
    end

    -- 🪤 Bear Trap: 별도 시스템에 위임 (1.5초 경고 후 함정 활성)
    if itemName == "bear_trap" then
        if _G.placeTrap then
            -- ⚠️ [2026-08-26] 반환값을 반드시 본다.
            --   예전엔 무조건 성공 처리라, 상한(5/5)·구역 밖·사거리 초과로 거부돼도
            --   쿨타임을 먹고 "🪤 Bear trap dispatched" 가 찍혔다.
            --   → 아무 일도 안 일어났는데 다음 설치까지 기다려야 했다.
            local placed = _G.placeTrap(player, clickPosition)
            if not placed then
                print("🪤 Bear trap 거부됨 — 쿨타임 미소모")
                return
            end
            playerCooldowns[player.UserId][itemName] = currentTime
    setGlobalCooldown(player, currentTime, itemName)
            -- 청사진 제거
            local blueprintName = "Blueprint_" .. player.Name
            local blueprint = workspace:FindFirstChild(blueprintName)
            if blueprint then blueprint:Destroy() end
            print("🪤 Bear trap dispatched")
        else
            warn("❌ TrapSystem not loaded yet (_G.placeTrap nil)")
        end
        return
    end

    -- 📦 Tox Box: 별도 시스템에 위임 (굴림 패턴, 즉사 큐브)
    if itemName == "tox_box" then
        if _G.spawnToxBox then
            -- 🧪 [2026-08-27] 반환값 확인. 거부되면 쿨을 소모하지 않는다.
            --   [증상] 이전 박스가 살아 있어 거부됐는데 쿨 3초가 그대로 나갔다
            --     (로그 실측: "❌ 이전 박스 살아있음" 직후 "📦 Tox Box dispatched").
            --   ⚠️ 바로 위 bear_trap 이 같은 이유로 이미 이 형태다. 같은 모양을 유지할 것.
            local ok = _G.spawnToxBox(player, clickPosition)
            if not ok then
                print("⏸️ Tox Box 거부 — 쿨 미소모 (이전 박스 생존)")
                return
            end
            -- 🔒 박스가 베이스에 도달할 때까지 잠긴다(표 쿨 3초와 무관)
            if _G.SetItemLock then _G.SetItemLock(player, "tox_box", true, "IN USE") end
            playerCooldowns[player.UserId][itemName] = currentTime
    setGlobalCooldown(player, currentTime, itemName)
            -- 청사진 제거
            local blueprintName = "Blueprint_" .. player.Name
            local blueprint = workspace:FindFirstChild(blueprintName)
            if blueprint then blueprint:Destroy() end
            print("📦 Tox Box dispatched")
        else
            warn("❌ ToxBoxSystem not loaded yet (_G.spawnToxBox nil)")
        end
        return
    end

    -- 💣 TNT 폭탄: 계단 클릭 시 즉시 spawn 안 함. 클라이언트 탑뷰로 전환만.
    -- 청사진은 그대로 두고(시각 피드백) 타겟팅 시작. BombSystem이 처리.
    if itemName == "tnt" then
        if _G.startBombTargeting then
            -- 💣 [2026-08-27] 반환값 확인. 거부되면 쿨을 소모하지 않는다.
            --   [증상] 이전 폭격 진행 중이면 거부되는데 쿨 7초가 그대로 나갔다.
            --     로그 실측: "📡 진입 신호" 없이 "💣 targeting mode triggered" 만 찍히고
            --     그 뒤 "⏱️ tnt 쿨타임 3.3초 남음" — 잔불 정리 후에도 쿨이 남아 보였다.
            --   ⚠️ 바로 위 tox_box / bear_trap 과 같은 형태. 세 위임 아이템이 한 모양이어야 한다.
            local ok = _G.startBombTargeting(player)
            if not ok then
                print("⏸️ TNT 거부 — 쿨 미소모 (이전 폭격 진행 중)")
                return
            end
            -- 🔒 조준이 끝날 때까지 잠긴다(표 쿨 7초와 무관)
            if _G.SetItemLock then _G.SetItemLock(player, "tnt", true, "AIMING") end
            playerCooldowns[player.UserId][itemName] = currentTime
    setGlobalCooldown(player, currentTime, itemName)
            print("💣 TNT targeting mode triggered for", player.Name)
        else
            warn("❌ BombSystem not loaded yet (_G.startBombTargeting nil)")
        end
        return
    end

    -- 🕳️ Black Hole: 별도 시스템에 위임 (포물선 투척 + 땅 닿으면 활성화 + 흡인)
    if itemName == "BlackHole" then
        if _G.spawnBlackHole then
            -- 🕳️ [2026-08-28] 반환값 확인. 거부되면 쿨을 소모하지 않는다.
            --   ⚠️ tnt / EnergyBall / bear_trap / tox_box 와 같은 형태다.
            --     위임 아이템 다섯이 한 모양이어야 한다.
            --   [증상] '중복 시도 거부' 직후에도 dispatched 를 찍고 7초 쿨을 먹었다
            --     (실측 11:01:25.58 → 11:01:27.9 "쿨타임 4.7초 남음").
            local ok = _G.spawnBlackHole(player, clickPosition)
            if not ok then
                print("⏸️ 블랙홀 거부 — 쿨 미소모")
                return
            end
            playerCooldowns[player.UserId][itemName] = currentTime
    setGlobalCooldown(player, currentTime, itemName)
            local blueprintName = "Blueprint_" .. player.Name
            local blueprint = workspace:FindFirstChild(blueprintName)
            if blueprint then blueprint:Destroy() end
            print("🕳️ Black Hole dispatched")
        else
            warn("❌ BlackHoleSystem not loaded yet (_G.spawnBlackHole nil)")
        end
        return
    end

    -- ⚡ Energy Ball: 레일건 직선 공격 (별도 시스템)
    if itemName == "EnergyBall" then
        if _G.fireEnergyBall then
            -- ⚡ [2026-08-27] 반환값 확인. 거부되면 쿨을 소모하지 않는다.
            --   ⚠️ 위 bear_trap / tox_box / tnt 와 같은 형태다. 네 위임 아이템이 한 모양이어야 한다.
            --   [증상] 에너지볼이 연속 2발 이상 나갔다(12초 쿨 무시). 실측 23:31.
            --   [원인] fireEnergyBall 이 차징+비행까지 인라인 yield 해서 약 4.3초 뒤에 복귀했다.
            --     쿨 기록이 아래(복귀 후)라 그 사이 쿨 슬롯이 비어 재요청이 검사를 통과했다.
            --     아이템 쿨(12s)만이 아니라 setGlobalCooldown 도 함께 늦어 전역 2초 쿨과
            --     클라 쿨 표시(ItemCooldownStart)까지 무방비였다 — UI 상 '사용 가능'으로 보임.
            --   [해결] EnergyBallSystem 이 동기 검증 후 즉시 반환하도록 바꿨다(차징~비행은 task.spawn).
            --     그래서 이 아래 기록부가 '요청 시점'에 실행된다.
            local ok = _G.fireEnergyBall(player, clickPosition)
            if not ok then
                print("⚡ EnergyBall 거부 — 쿨 미소모")
                return
            end
            playerCooldowns[player.UserId][itemName] = currentTime
    setGlobalCooldown(player, currentTime, itemName)
            local blueprintName = "Blueprint_" .. player.Name
            local blueprint = workspace:FindFirstChild(blueprintName)
            if blueprint then blueprint:Destroy() end
            print("⚡ Energy Ball dispatched")
        else
            warn("❌ EnergyBallSystem not loaded yet (_G.fireEnergyBall nil)")
        end
        return
    end
    
    -- 🗡️ Spear: 클릭 지점 방향으로 투척 (별도 시스템, 저가 가성비, 무제한)
    if itemName == "Spear" then
        if _G.throwSpear then
            _G.throwSpear(player, clickPosition)
            playerCooldowns[player.UserId][itemName] = currentTime
    setGlobalCooldown(player, currentTime, itemName)
            local blueprintName = "Blueprint_" .. player.Name
            local blueprint = workspace:FindFirstChild(blueprintName)
            if blueprint then blueprint:Destroy() end
            print("🗡️ Spear dispatched")
        else
            warn("❌ SpearSystem not loaded yet (_G.throwSpear nil)")
        end
        return
    end

    -- 🔥🗡️ Demonspear: 클릭 지점으로 투척 + 경로에 불 궤적(지역장악/넓은 즉사판정)
    if itemName == "Demonspear" then
        if _G.throwDemonSpear then
            local thrown = _G.throwDemonSpear(player, clickPosition)
            if thrown then
                playerCooldowns[player.UserId][itemName] = currentTime
    setGlobalCooldown(player, currentTime, itemName)
                local blueprintName = "Blueprint_" .. player.Name
                local blueprint = workspace:FindFirstChild(blueprintName)
                if blueprint then blueprint:Destroy() end
                print("🔥🗡️ Demonspear dispatched")
            else
                print("🚫 Demonspear 발사 차단됨 (잠금/조건 미충족) — 쿨다운·로그 미적용")
            end
        else
            warn("❌ DemonSpearSystem not loaded yet (_G.throwDemonSpear nil)")
        end
        return
    end
    
    -- ItemNoob 보상 확인 (Clone 전에 체크)
    if isItemNoob then
        local hasReward = player:GetAttribute("HasItemNoob")
        if not hasReward then
            print("❌ ItemNoob 미보유:", player.Name)
            return
        end
        -- 🧍 [2026-09-20] 단일 존재 검사. tox_box 분기와 같은 규약이다 —
        --   거부되면 **쿨을 소모하지 않고** 돌아간다(bear_trap·tox_box 가 이미 이 형태).
        --   ⚠️ Clone 전이어야 한다. 뒤로 가면 모델을 만들어 놓고 버리게 된다.
        local mine = activeNoobOf(player)
        if mine then
            print("⏸️ ItemNoob 거부 — 쿨 미소모 (이전 뉴비 생존)")
            return
        end
    end
    
    local itemTemplate = taggerItems:FindFirstChild(actualItemName)
    if not itemTemplate then
        print("❌ Item not found in ServerStorage:", actualItemName)
        return
    end
    -- (소환 성공 로그 제거: 요청 1줄로 충분. 실패는 각 차단 분기가 이유를 찍는다)

    -- ── 🔴 스폰 텔레그래프 ─────────────────────────────────
    -- 클릭 지점에 붉은 경고 마커를 잠깐 보여준 뒤 실체화.
    -- 근접 직접 스폰("발밑 소환 즉사")에 최소 반응 창을 보장 — 원거리 굴리기엔 체감 영향 없음.
    -- 위임류(스피어/블랙홀/쓰나미/트랩 등)는 위에서 이미 return — 이 경로(직접 스폰)에만 적용.
    -- 봇(KING)도 같은 경로라 동일 규칙. 트랩 warning과 같은 시각 언어(빨강 = 곧 위험).
    do
        -- 예고 시간. 근접 스폰이면 길게 준다.
        --   원거리 투척은 굴러오는 시간이 따로 있어 0.6 으로 충분하다(실측: 59~75m).
        --   문제는 그랩→푸시 콤보였다. 붙잡힌 채 바로 옆에 소환되면 0.6초 예고가
        --   그랩 스턴(1.0초) 안에 다 지나가 '보는 순간 이미 못 움직이는' 상태가 된다.
        --   → 소환 지점 근처에 러너가 있을 때만 연장해 콤보 대응만 가능하게 한다.
        local TELEGRAPH_NEAR_RANGE = 25   -- 이 거리 안에 러너가 있으면 근접 스폰으로 본다
        local TELEGRAPH_TIME = 0.6        -- 기본(원거리)
        do
        	-- ⚠️ 이 스크립트에는 Players 서비스 선언이 없다. 직접 가져온다.
        	--   (전에 local Players 가 있다고 가정하고 썼다가 스폰이 통째로 죽었다:
        	--    "attempt to index nil with 'GetPlayers'")
        	local PlayersSvc = game:GetService("Players")
        	local near = false
        	-- 유저 러너
        	for _, plr in ipairs(PlayersSvc:GetPlayers()) do
        		if plr:GetAttribute("Role") == "Runner" then
        			local ch = plr.Character
        			local rt = ch and ch:FindFirstChild("HumanoidRootPart")
        			if rt and (rt.Position - clickPosition).Magnitude <= TELEGRAPH_NEAR_RANGE then
        				near = true
        				break
        			end
        		end
        	end
        	-- AI 러너 (콤보는 AI 상대로도 성립한다)
        	if not near then
        		for _, m in ipairs(workspace:GetChildren()) do
        			if m:GetAttribute("AIRunner") == true then
        				local rt = m:FindFirstChild("HumanoidRootPart")
        				if rt and (rt.Position - clickPosition).Magnitude <= TELEGRAPH_NEAR_RANGE then
        					near = true
        					break
        				end
        			end
        		end
        	end
        	if near then
        		TELEGRAPH_TIME = 1.4   -- 그랩 스턴 1.0초 + 여유 0.4초
        	end
        end
        -- 쿨다운 선기록: 텔레그래프 대기(0.6s) 중 연타 이중 스폰 방지
        -- (기존 기록 지점은 스폰 완료 후라 대기 중 재요청이 쿨 체크를 통과함)
        playerCooldowns[player.UserId][itemName] = currentTime
    setGlobalCooldown(player, currentTime, itemName)
        -- 태거가 조준 중 보는 청사진(ForceField + 투명 0.5)과 동일한 고스트를 서버에서 생성
        -- → 러너 전원에게도 "무엇이 어디에" 떨어질지 잠깐 보임. (태거 청사진은 클라 로컬이라 러너 불가시)
        local ghost = itemTemplate:Clone()
        ghost.Name = "SpawnTelegraph"
        local function ghostify(p)
            p.Anchored = true
            p.CanCollide = false
            p.CanQuery = false
            p.CanTouch = false
            p.Material = Enum.Material.ForceField
            p.Transparency = math.max(p.Transparency, 0.5)
            p:SetAttribute("NoContactDown", true)  -- 방어: 어떤 경로로든 접촉 판정 금지
        end
        if ghost:IsA("BasePart") then ghostify(ghost) end
        for _, d in ipairs(ghost:GetDescendants()) do
            if d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("Sound") then
                d:Destroy()  -- 고스트에서 스크립트 실행/사운드 방지
            elseif d:IsA("BasePart") then
                ghostify(d)
            end
        end
        ghost:PivotTo(CFrame.new(clickPosition + Vector3.new(0, 2.5, 0)))
        ghost.Parent = workspace
        game:GetService("Debris"):AddItem(ghost, TELEGRAPH_TIME + 0.05)
        task.wait(TELEGRAPH_TIME)
    end

    -- 아이템 복제
    local newItem = itemTemplate:Clone()

    -- stone 색 스킨: 베이스 Part에 material/color 칠 (기존 색 스킨 Part와 동일 결과)
    if stoneSkinData and newItem:IsA("BasePart") then
        newItem.Material = Enum.Material[stoneSkinData.material] or newItem.Material
        newItem.Color = stoneSkinData.color
    end

    -- 배럴 커스텀 색: zones(Body/Rings) 각각 색/재질 적용
    if barrelSkinData and barrelSkinData.zones and newItem:IsA("Model") then
        for zone, zd in pairs(barrelSkinData.zones) do
            local part = newItem:FindFirstChild(zone)
            if part and part:IsA("BasePart") then
                part.Color = zd.color
                if zd.material then
                    part.Material = Enum.Material[zd.material] or part.Material
                end
            end
        end
    end

    -- Noob 부위별 색: ItemNoob이고 형태스킨이 아니면(actualItemName 그대로) 부위별 색 적용.
    -- NoobColor_<zone> 속성이 있는 부위만 칠하고, 없으면 베이스 누비색 유지.
    if itemName == "ItemNoob" and actualItemName == "ItemNoob" and newItem:IsA("Model") then
        local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
        for _, zone in ipairs(palette.ZONES) do
            local colorName = player:GetAttribute("NoobColor_" .. zone)
            if colorName and palette.COLORS[colorName] then
                local col = palette.COLORS[colorName]
                for _, partName in ipairs(palette.ZONE_PARTS[zone]) do
                    local p = newItem:FindFirstChild(partName)
                    if p and p:IsA("BasePart") then
                        p.Color = col
                    end
                end
            end
        end
    end
    
    -- 스폰 위치 = 클릭 위치 + 위로 3 studs (떨어지면서 스폰)
    local spawnPos = clickPosition + Vector3.new(0, 3, 0)

    -- 🛢️ [버그 수정 2026-08-26] 배럴은 반지름만큼 더 띄운다.
    --   [증상] 배럴이 종종 똑바로 못 서고 옆으로 기울어진 채 굴러갔다(실측 18:19 판).
    --   [원인] _CollisionCore 는 지름 18.5(반지름 9.25) 인데 중심을 지면 +3 에 두면
    --     6.25 stud 가 땅에 파묻힌다. 물리 엔진이 겹침을 밀어내면서 자세가 틀어지고,
    --     그 상태에서 각속도까지 받으니 튕겨나간다.
    --     계단 근처에서 더 심한 것도 같은 이유다 — 파묻힌 채 모서리에 걸린다.
    --
    -- 🪵 [일반화 2026-09-09] 배럴 전용 → 크기 기반 전 아이템.
    --   [왜] 위 주석이 "통나무는 메시라 바운딩이 관대하고 돌은 구체라 자세 개념이 없다"며
    --     둘을 제외했는데, 실측하니 그 전제가 틀렸다:
    --       Wooden Barrel  25 × 18.5 × 18.5  → 6.25 파묻힘  (고쳐진 값)
    --       Wood Log       20 × 20   × 30    → 7.00 파묻힘  ← 배럴보다 더 깊다
    --       stone          20 × 20   × 20    → 7.00 (0.75배 시작이라 실효 4.5)
    --     MeshPart 도 기본 충돌은 Size 그대로다. "메시라 관대하다"는 근거가 없었다.
    --   [증상 재현] 사용자 제보 — 통나무가 축이 빙 돌거나 기울어진 채 소환됨.
    --     배럴이 08-26 에 보이던 것과 같은 그림이다.
    --   [규칙] 파묻히는 깊이 = (가장 짧은 축 / 2) - 3.  이걸 0 이하로 만든다.
    --     가장 '짧은' 축을 쓰는 이유: 어떤 자세로 놓이든 최소 그만큼은 확보돼야 한다.
    --   ⚠️ 새 아이템을 추가해도 자동으로 적용된다. 이름 목록이 아니라 크기로 판정하므로.
    --     ("제외 목록보다 결과 보장" — 09-06 문서 원칙)
    --   ⚠️ 배럴은 기존 BARREL_RADIUS 경로를 그대로 둔다. 검증된 값이고,
    --     _CollisionCore(18.5)와 바운딩박스(19.33)가 달라 자동 계산이 더 낮게 나온다.
    --   ⚠️ 되돌리려면 아래 else 블록을 지운다(배럴 분기는 원래대로 남는다).
    if isBarrel then
        spawnPos = clickPosition + Vector3.new(0, BARREL_RADIUS + 2, 0)
    else
        local minHalf = 0
        if newItem:IsA("BasePart") then
            local s = newItem.Size
            minHalf = math.min(s.X, s.Y, s.Z) * 0.5
        elseif newItem:IsA("Model") then
            local _, bb = newItem:GetBoundingBox()
            minHalf = math.min(bb.X, bb.Y, bb.Z) * 0.5
        end
        -- 스톤은 스폰 직후 STONE_START_SCALE 로 줄었다가 자라므로 그만큼만 필요하다.
        -- ⚠️ [미해결 2026-09-19] 스톤이 태거베이스를 관통해 반대편 위에 정착한 제보 1회
        --   (수십 판 중 처음). 재현 안 됨.
        --   [확인된 사실] 이 줄은 **시작 배율(0.75)** 만 본다 → lift = 9.5.
        --     그런데 스톤은 2.5초에 걸쳐 STONE_MAX_SCALE(2.20)까지 자라 반지름이 22 가 되고,
        --     성장 루프(startStoneGrowth)는 Size 만 바꾸고 CFrame 은 건드리지 않는다.
        --   ⚠️ [이게 원인인지는 모른다 — 단정하지 말 것]
        --     · 돌은 굴러간다. 다 자랄 때쯤엔 스폰 지점에 없고 물리가 내내 접촉을 푼다.
        --     · 0.1초당 반지름 증가가 0.58 stud 뿐이라 한 번에 깊이 파고들 구조가 아니다.
        --     · 태거베이스가 얇은 슬래브인지 확인하지 않았다.
        --     · "베이스 아래에서 스폰"이 어떻게 가능했는지 설명하지 못한다.
        --   [재현되면 찍을 것] 관통 순간의 ① 돌 중심 Y ② 아랫면 Y ③ 바닥 파트 두께.
        --     이 세 줄이면 lift 문제인지 다른 문제인지 갈린다.
        --   [고친다면] ① 여기를 STONE_MAX_SCALE 로 (한 줄, lift 9.5 → 24)
        --     ② 또는 성장 시 CFrame 을 위로 같이 올려 아랫면 고정 (연출 유지, 물리와 충돌 위험)
        --   ⚠️ 지금 안 고치는 이유: 빈도가 극히 낮은데 ①은 **모든 스톤의 낙하 연출과
        --     명중률**을 바꾼다. 밸런스 측정 중에는 기준선이 깨진다.
        if itemName == "stone" then minHalf = minHalf * STONE_START_SCALE end
        local lift = math.max(3, minHalf + 2)
        spawnPos = clickPosition + Vector3.new(0, lift, 0)
    end
    
    if newItem:IsA("Model") then
        -- PrimaryPart 확인/설정
        if not newItem.PrimaryPart then
            local biggestPart = nil
            local biggestVolume = 0
            
            for _, part in ipairs(newItem:GetDescendants()) do
                if part:IsA("BasePart") then
                    local volume = part.Size.X * part.Size.Y * part.Size.Z
                    if volume > biggestVolume then
                        biggestVolume = volume
                        biggestPart = part
                    end
                end
            end
            
            if biggestPart then
                newItem.PrimaryPart = biggestPart
                print("Set PrimaryPart:", biggestPart.Name)
            end
        end
        
        -- 모든 파트 물리 설정 + CollisionGroup
        for _, part in ipairs(newItem:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
                part.Anchored = false
                part.CollisionGroup = "TaggerItems"
                
                if isFrostDragon then
                    part.CanCollide = false
                    part.Anchored = true
                    -- 🔇 [로그 정리 2026-08-26] 파트마다 한 줄씩 찍어 소환 1회당 14줄이었다.
                    --   동작이 검증된 지금은 아래 "고정 완료" 한 줄이면 충분하다.
                    --   (되살리려면 이 주석을 print 로 되돌릴 것)
                elseif isSpikedWood then
                    if part.Name == "_CollisionBox" then
                        part.CanCollide = true
                    else
                        part.CanCollide = false
                    end
                    part.Anchored = false
                    print("  🪵 SpikedWood 파트 처리:", part.Name, "CanCollide:", part.CanCollide)
                elseif isGoldNeonNoob then
                    -- 외형/물리 분리: _CollisionCore만 충돌+물리 담당, 나머지는 장식
                    if part.Name == "_CollisionCore" then
                        part.CanCollide = true
                        part.Massless = false
                        part.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.01, 0.5, 1, 1)  -- 원본 ItemNoob과 동일
                        part.CollisionGroup = "Default"  -- 벽(Walls)/산(Mountains)과 충돌하도록 (TaggerItems는 통과함)
                    else
                        part.CanCollide = false
                        part.Massless = true   -- 질량 0 → 코어 물리에 영향 없음
                    end
                    part.Anchored = false
                    print("  👑 GoldNeonNoob 파트 처리:", part.Name, "CanCollide:", part.CanCollide, "Group:", part.CollisionGroup)
                elseif isGoldenLog then
                    -- 외형/물리 분리: 본체(Golden Log)만 충돌+물리, 체인/매직서클은 장식
                    if part.Name == "Golden Log" then
                        part.CanCollide = true
                        part.Massless = false
                        part.CollisionGroup = "TaggerItems"  -- 원본 Wood Log와 동일
                    else
                        part.CanCollide = false
                        part.Massless = true   -- 질량 0 → 본체 물리에 영향 없음
                    end
                    part.Anchored = false
                    print("  🪵✨ GoldenLog 파트 처리:", part.Name, "CanCollide:", part.CanCollide)
                elseif isSunStone then
                    -- 외형/물리 분리: 메인 메시(MeshPart)만 충돌+물리, 글로우 오라(Ball Part)는 장식
                    if part:IsA("MeshPart") then
                        part.CanCollide = true
                        part.Massless = false
                        part.CollisionGroup = "TaggerItems"  -- 다른 stone과 동일
                    else
                        part.CanCollide = false
                        part.Massless = true   -- 질량 0 → 본체 물리에 영향 없음
                    end
                    part.Anchored = false
                    print("  ☀️ SunStone 파트 처리:", part.Name, "CanCollide:", part.CanCollide)
                elseif isBarrel then
                    -- 배럴: 매끈한 _CollisionCore(원기둥)만 충돌+질량 → 곧게 굴러감. Body/Rings는 외형(장식).
                    if part.Name == "_CollisionCore" then
                        part.CanCollide = true
                        part.Massless = false
                        part.CollisionGroup = "TaggerItems"
                    else
                        part.CanCollide = false
                        part.Massless = true
                    end
                    part.Anchored = false
                elseif isItemNoob then
                    part.CustomPhysicalProperties = PhysicalProperties.new(0.3, 0.01, 0.5, 1, 1)
                    -- ⚠️ [버그수정 2026-09-01] 전 파트 "Default" → 몸통 1개만 "TaggerItems".
                    --   [증상] 실측 normal 1판에서 ItemNoob 12발 스폰, 히트 0. 내구도 소모
                    --     원인 목록에 ItemNoob 이 한 번도 등장하지 않았다.
                    --   [원인] ItemDamageSystem:712 가 CollisionGroup == "TaggerItems" 인 파트에만
                    --     Touched → processHit 을 연결한다. 전 파트를 "Default" 로 두면 피해
                    --     판정이 아예 붙지 않는다. _NoobZigzag:42 주석은 "즉사 판정은 Touch로
                    --     처리"라고 적혀 있는데, 그 Touch 가 연결된 적이 없었다.
                    --   [왜 "Default" 였나] 벽·산과 물리 충돌시키려던 잔재다. 지금은 지그재그
                    --     스크립트가 파트를 Anchored + CanCollide=false 로 두고 레이캐스트로
                    --     벽 반사를 처리한다 — 물리 충돌 자체가 일어나지 않으므로 무의미했다.
                    --   ⚠️ 반드시 한 파트에만 줄 것. damageCooldown 키가 '모델'이 아니라
                    --     '파트 인스턴스'라(ItemDamageSystem:626) 7개를 다 주면 같은 러너를
                    --     최대 7번 때려 내구도 흡수와 다운이 한 번에 나간다.
                    --     배럴이 _CollisionCore 하나만 TaggerItems 로 두는 것과 같은 이유다.
                    --   ⚠️ Torso 는 히트박스로 쓸 수 없다. 뉴비가 24.6 stud 짜리 거인이라
                    --     Torso 가 발밑 기준 9.8~19.7 에 있는데, 러너 키는 5 다 —
                    --     아예 겹치지 않는 높이라 머리 위로 지나간다(실측 2026-09-01).
                    --     Torso 로 뒀던 판에서 12발 중 3발만 맞았고, 그 3발도 경사면에서
                    --     노브가 내려앉은 경우였다. "닿았는데 안 맞는다"의 정체다.
                    --   [해결] 전용 히트박스 `_NoobHitbox`(투명·비충돌)를 템플릿에 넣고
                    --     그것만 TaggerItems 로 준다. 발밑 0~74 라 러너 전신과 겹친다.
                    --   ⚠️ 크기는 몸체 bbox 와 일치시킨다 — 29.5×36.9×10.4
                    --     (몸체 29.5×36.9×7.4, 깊이만 +3 여유).
                    --     [왜 일치인가] 한때 몸체 19.7 에 히트박스 60 을 줬는데, 보이는 노브에서
                    --     20 stud 떨어져도 맞는 상태였다. "안 맞는다"의 반대 불만이 나올 자리다.
                    --     2026-09-01 에 모델 자체를 키워(`_NoobScale` 속성, 현재 1.5) 둘을 맞췄다.
                    --   ⚠️ 모델 크기를 다시 바꾸면 이 히트박스도 같이 바꿀 것. 한쪽만 고치면
                    --     "보이는 것과 판정이 다른" 상태로 되돌아간다.
                    if part.Name == "_NoobHitbox" then
                        part.CollisionGroup = "TaggerItems"
                    else
                        part.CollisionGroup = "Default"
                    end
                end
            end
        end

        -- Noob 스킨(SuitNoob/SoldierNoob/GlitchNoob 등): Humanoid가 있으면 물리 간섭 차단
        -- (옷 렌더링 위해 Humanoid는 유지하되, 상태 머신/자세 보정으로 인한 진동·멈춤 방지)
        if isAnyNoob then
            -- 던진 발사체 표시: ItemDamageSystem이 다운/데미지 대상에서 제외하도록
            newItem:SetAttribute("ThrownTaggerItem", true)
            local noobHum = newItem:FindFirstChildOfClass("Humanoid")
            if noobHum then
                noobHum.EvaluateStateMachine = false
                noobHum.PlatformStand = true
                noobHum.WalkSpeed = 0
                noobHum.JumpPower = 0
                noobHum.AutoRotate = false
                noobHum.BreakJointsOnDeath = false
                pcall(function()
                    noobHum:ChangeState(Enum.HumanoidStateType.Physics)
                end)
            end
        end

        -- 모든 뉴비: 지그재그 주행 (CFrame 직접 제어 + 지형 높이 레이캐스트 + 시작 방향 랜덤 + 벽 반사)
        if isAnyNoob and newItem.PrimaryPart then
            -- 물리 굴림 대신 스크립트가 경로를 100% 제어 → 앵커링은 주행 스크립트가 처리
            local zigzag = newItem:FindFirstChild("_NoobZigzag")
            if zigzag then
                zigzag.Disabled = false
            end
            print("✅ 뉴비 지그재그 주행 활성화: " .. tostring(actualItemName))
        end

        -- GoldenLog 스킨: 본체 색 트레일 (구를 때 뒤로 금색 잔상)
        if isGoldenLog then
            local goldBody = newItem:FindFirstChild("Golden Log")
            if goldBody then
                local halfH = goldBody.Size.Y * 0.5
                local a0 = Instance.new("Attachment")
                a0.Name = "_TrailA0"
                a0.Position = Vector3.new(0, halfH, 0)
                a0.Parent = goldBody
                local a1 = Instance.new("Attachment")
                a1.Name = "_TrailA1"
                a1.Position = Vector3.new(0, -halfH, 0)
                a1.Parent = goldBody

                local trail = Instance.new("Trail")
                trail.Name = "_GoldTrail"
                trail.Attachment0 = a0
                trail.Attachment1 = a1
                trail.Color = ColorSequence.new(goldBody.Color)  -- 본체 색과 동일
                trail.Lifetime = 1.0
                trail.LightEmission = 0.6
                trail.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.1),
                    NumberSequenceKeypoint.new(1, 1),
                })
                trail.WidthScale = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1),
                    NumberSequenceKeypoint.new(1, 0.2),
                })
                trail.FaceCamera = true
                trail.Parent = goldBody
                print("  ✨ GoldenLog 금색 트레일 부착")
            end
        end

        
        -- 위치 설정 (클릭 위치!)
        if newItem.PrimaryPart then
            if itemName == "Wooden Barrel" then
                -- 배럴: 원통축(로컬Y)을 진행방향과 수직으로 눕혀 곧게 굴러가게.
                local rollDir = Vector3.new(1, 0, 0)  -- 기본(map1 진행축=X)
                do
                    -- ⚠️ [수정 2026-08-26] 정확한 이름 매칭 → 접두사 매칭.
                    --   FindFirstChild("taggerspawn", true) 는 map2 의 "taggerspawn2" 를
                    --   못 찾는다. taggerbase 폴백도 "taggerbase2" 라 같이 실패했다.
                    --   → map2 에서는 rollDir 이 기본값 (1,0,0) 으로 고정돼,
                    --      맵의 실제 진행축과 무관하게 굴러갔다.
                    --   TaggerUIScript.getRunnerDirection 이 쓰는 접두사 방식과 통일한다.
                    local function findPrefix(mf, pfx)
                        for _, d in ipairs(mf:GetDescendants()) do
                            if (d:IsA("BasePart") or d:IsA("SpawnLocation"))
                               and d.Name:lower():sub(1, #pfx) == pfx then
                                return d
                            end
                        end
                    end
                    local bestDir = nil
                    for _, mf in ipairs(workspace:GetChildren()) do
                        if mf.Name:lower():find("map") then
                            local ps = findPrefix(mf, "playerspawn") or findPrefix(mf, "playerbase")
                            local ts = findPrefix(mf, "taggerspawn") or findPrefix(mf, "taggerbase")
                            if ps and ts then
                                local pPos = ps:IsA("BasePart") and ps.Position or ps:GetPivot().Position
                                local tPos = ts:IsA("BasePart") and ts.Position or ts:GetPivot().Position
                                local d = Vector3.new(tPos.X - pPos.X, 0, tPos.Z - pPos.Z)
                                if d.Magnitude > 1 then bestDir = d.Unit; break end
                            end
                        end
                    end
                    if bestDir then rollDir = bestDir end
                end
                -- 원통축 = rollDir과 수직인 좌우 수평축. 배럴이 rollDir 방향으로 곧게 굴러감.
                local sideAxis = Vector3.new(0,1,0):Cross(rollDir).Unit
                -- 계단 회피: 진행방향 기준 오른쪽으로 살짝 오프셋
                local BARREL_SIDE_OFFSET = -4  -- 오른쪽 이동량 (F5 튜닝)
                local offsetPos = spawnPos + sideAxis * BARREL_SIDE_OFFSET
                -- PrimaryPart=_CollisionCore는 Cylinder(원통축=로컬X). 원통축을 sideAxis(좌우)로 맞춤.
                -- fromMatrix(pos, rightVector=원통축, upVector) → right=sideAxis, up=월드Up
                local barrelCF = CFrame.fromMatrix(offsetPos, sideAxis, Vector3.new(0,1,0))
                newItem:SetPrimaryPartCFrame(barrelCF)
                -- ⚠️ [2026-08-26] 여기서는 자세만 잡고 속도는 건드리지 않는다.
                --   예전엔 여기서 각속도·직선속도를 0으로 죽였는데, 아래
                --   "즉각적인 속도 적용" 블록이 다시 값을 넣어 두 자리가 싸웠다.
                --   속도는 한 곳(아래 블록)에서만 정한다.
                -- 아래 블록이 쓸 수 있게 굴림 축을 넘긴다.
                barrelRollDir = rollDir
                barrelSideAxis = sideAxis

                -- 🛢️ [2026-08-26] 파열 표식. ItemDamageSystem 이 이 속성을 보고
                --   _G.BarrelBurst 를 호출한다(러너에게 닿으면 액체 지대 생성).
                -- ⚠️ 값에 '실제 스킨 이름' 을 담는다. BarrelSpillSystem 이 이걸로
                --   액체 종류를 고른다(나무통=와인 / OilDrum=기름 / Crusader=성수).
                --   itemName 은 항상 "Wooden Barrel" 이라 스킨 구분이 안 된다.
                newItem:SetAttribute("BarrelSpill", actualItemName or itemName)
            else
                newItem:SetPrimaryPartCFrame(CFrame.new(spawnPos))
            end
        else
            newItem:MoveTo(spawnPos)
        end
        
        newItem.Parent = workspace
        newItem:SetAttribute("TaggerSpawnedItem", true)   -- 조준 제외 표식 (배럴 계열 경로)
        -- 🧍 뉴비는 Model 이라 이 경로를 탄다. 아래 BasePart 경로에도 같은 줄이 있다 —
        --   두 줄은 짝이다(RoundSystem 정리 그물이 의존하는 그 쌍과 같다). 한쪽만 고치지 말 것.
        if isItemNoob then registerNoobInstance(player, newItem) end

        -- 🛢️ [수정 2026-09-18] 배럴 속도를 **자세와 같은 프레임**에 준다.
        --   [무엇이 문제였나] 아래 "즉각적인 속도 적용" 블록은 wait(0.05) 뒤에 돈다.
        --     그 0.05초 동안 배럴은 **각속도 없이** 자유낙하한다. 원통은 각운동량이 없으면
        --     자세가 안 잡혀서(굴러야 안 넘어지는 바퀴와 같다) 경사·직전 스폰물에 닿으면 기운다.
        --   [근거] 1852행 진단 주석이 예고한 그대로다 — "틀어짐이 찍히면 wait(0.05) 를 없애고
        --     자세·속도를 같은 프레임에 주는 쪽으로 고친다".
        --     실측(2026-09-18): 자세 1.00 / 0.97 / 0.94 / 0.92 / 0.89(⚠️ 틀어짐).
        --   ⚠️ [예측과 값이 다르다] 주석은 "0.00 근처 = 90° 누움"을 예상했는데 실측은
        --     0.89~0.94 (20~27°) 였다. 기울긴 해도 못 구를 정도는 아니다 —
        --     즉 이 수정은 '각도 틀어짐'을 고치지, "베이스에 머문다"까지 고친다는 보장은 없다.
        --     그쪽은 BARREL_SIDE_OFFSET(-4, 1695행) 이 유력한 별건이다.
        --   ⚠️ [왜 CFrame 설정부(1694행)가 아니라 여기인가] 거기선 아직 Parent 가 nil 이라
        --     어셈블리가 물리 세계에 없다. 속도를 넣어도 시뮬레이션이 안 받는다.
        --     Parent 직후가 '자세 설정과 같은 프레임'이면서 물리가 도는 가장 이른 지점이다.
        --   ⚠️ 아래 블록의 배럴 분기는 이 값을 덮어쓰지 않도록 비워뒀다. 두 곳에서 속도를
        --     정하면 2026-08-26 에 겪은 "두 자리가 싸우는" 문제가 재발한다.
        --   ⚠️ 되돌리려면 이 블록을 지우고 아래 배럴 분기를 복원한다.
        local barrelVelocityDone = false
        if isBarrel and barrelRollDir and barrelSideAxis and newItem.PrimaryPart then
            local BARREL_SPEED = 25      -- 다른 굴리기류와 동일 기준
            local axisDot = newItem.PrimaryPart.CFrame.RightVector:Dot(barrelSideAxis)
            newItem.PrimaryPart.AssemblyLinearVelocity =
                barrelRollDir * BARREL_SPEED + Vector3.new(0, -30, 0)
            newItem.PrimaryPart.AssemblyAngularVelocity =
                -barrelSideAxis * (BARREL_SPEED / BARREL_RADIUS)
            barrelVelocityDone = true
            print(string.format("🛢️ 배럴 초기속도: 선속 %d / 각속 %.2f rad/s | 자세 %.2f%s (즉시)",
                BARREL_SPEED, BARREL_SPEED / BARREL_RADIUS, axisDot,
                (math.abs(axisDot) < 0.9) and "  ⚠️ 틀어짐" or ""))
        end
        
        -- 🌟 Crusader Barrel: 금색 발광 오비터 2개가 배럴을 공전하며 트레일(성스러운 오라)
        if actualItemName == "CrusaderBarrel" then
            local GOLD = Color3.fromRGB(255, 215, 0)
            local barrelRoot = newItem.PrimaryPart
            if barrelRoot then
                local ORB_SIZE = 2.6
                local ORB_R = 15          -- 궤도 반지름 (배럴 지름 ~19보다 살짝 크게)
                local ORB_SPEED = 2.5     -- 공전 속도(rad/s)
                local orbFolder = Instance.new("Folder")
                orbFolder.Name = "_CrusaderOrbiters"
                orbFolder.Parent = newItem
                local function makeOrbiter(nm)
                    local p = Instance.new("Part")
                    p.Name = nm
                    p.Shape = Enum.PartType.Ball
                    p.Size = Vector3.new(ORB_SIZE, ORB_SIZE, ORB_SIZE)
                    p.Anchored = true
                    p.CanCollide = false
                    p.CastShadow = false
                    p.Material = Enum.Material.Neon
                    p.Color = GOLD
                    p.Position = barrelRoot.Position
                    local a0 = Instance.new("Attachment"); a0.Name="TS"; a0.Position=Vector3.new(0, ORB_SIZE*0.4, 0); a0.Parent=p
                    local a1 = Instance.new("Attachment"); a1.Name="TE"; a1.Position=Vector3.new(0,-ORB_SIZE*0.4, 0); a1.Parent=p
                    local tr = Instance.new("Trail")
                    tr.Attachment0 = a0; tr.Attachment1 = a1
                    tr.Color = ColorSequence.new(GOLD)
                    tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1) })
                    tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(1,0) })
                    tr.Lifetime = 0.25
                    tr.LightEmission = 1
                    tr.LightInfluence = 0
                    tr.MinLength = 0
                    tr.FaceCamera = true
                    tr.Parent = p
                    p.Parent = orbFolder
                    return p
                end
                local orbA = makeOrbiter("OrbA")
                local orbB = makeOrbiter("OrbB")
                -- 배럴 위치 추적하며 공전 (자전과 무관, 위치만 따라감)
                local ang = 0
                local conn
                conn = RunService.Heartbeat:Connect(function(dt)
                    if not newItem.Parent or not barrelRoot.Parent then
                        conn:Disconnect()
                        return
                    end
                    ang = ang + dt * ORB_SPEED
                    local c = barrelRoot.Position
                    orbA.Position = c + Vector3.new(math.cos(ang) * ORB_R, 0, math.sin(ang) * ORB_R)
                    orbB.Position = c + Vector3.new(0, math.cos(ang + math.pi/2) * ORB_R, math.sin(ang + math.pi/2) * ORB_R)
                end)
            end
        end
        
        if isFrostDragon then
            -- 방향 = (태거가 있는 맵의) taggerspawn → playerspawn 고정점. 태거 위치·클릭 무관하게 항상 러너 방향.
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            local taggerPos = hrp and hrp.Position or newItem.PrimaryPart.Position
            local function findPrefix(mf, pfx)
                for _, d in ipairs(mf:GetDescendants()) do
                    if (d:IsA("BasePart") or d:IsA("SpawnLocation")) and d.Name:lower():sub(1, #pfx) == pfx then return d end
                end
            end
            -- 태거와 가장 가까운 taggerspawn을 가진 맵 = 활성 맵 (두 맵이 동시 존재하므로)
            local bestMap, bestDist = nil, math.huge
            for _, mf in ipairs(workspace:GetChildren()) do
                if mf.Name:lower():find("map") then
                    local t = findPrefix(mf, "taggerspawn") or findPrefix(mf, "taggerbase")
                    if t then
                        local dd = (t.Position - taggerPos).Magnitude
                        if dd < bestDist then bestDist = dd; bestMap = mf end
                    end
                end
            end
            local dir = Vector3.new(-1, 0, 0)
            if bestMap then
                local tRef = findPrefix(bestMap, "taggerspawn") or findPrefix(bestMap, "taggerbase")
                local rRef = findPrefix(bestMap, "playerspawn") or findPrefix(bestMap, "playerbase")
                if tRef and rRef then
                    local flat = Vector3.new(rRef.Position.X - tRef.Position.X, 0, rRef.Position.Z - tRef.Position.Z)
                    if flat.Magnitude > 0.1 then dir = flat.Unit end
                end
            end
            -- 시작 = 태거 앞 15stud (태거가 선 레인에서 러너쪽으로 전진)
            local startPos = taggerPos + dir * 15 + Vector3.new(0, 30, 0)
            newItem.PrimaryPart.Anchored = true
            newItem:SetPrimaryPartCFrame(CFrame.lookAt(startPos, startPos + dir))
            newItem:SetAttribute("FireDirection", dir)
            newItem:SetAttribute("FrostOwner", player.UserId)
            print("  🐉 Frost Dragon 브레스 강하 (dir=" .. tostring(dir) .. ")")

            -- 얼음 생성기 부착
            local iceGenerator = iceGeneratorTemplate:Clone()
            iceGenerator.Parent = newItem
            iceGenerator.Disabled = false
            print("  ❄️ Frost Dragon 얼음 생성기 부착!")
        elseif isAnyNoob then
            -- 모든 뉴비: 지그재그 주행을 쓰므로 굴림 회전기(ItemNoobRotator)를 붙이지 않음
        end
        
        -- 즉각적인 속도 적용!
        wait(0.05)
        if newItem.PrimaryPart then
            -- ItemNoob는 더 강한 초기 속도
            if isFrostDragon then
                -- Frost Dragon은 움직이지 않음
                print("✅ Frost Dragon 고정 완료")
            elseif isAnyNoob then
                -- 모든 뉴비: 지그재그 스크립트가 파트를 앵커링하고 CFrame으로 직접 제어
                -- → 물리 초기 속도 적용 안 함 (앵커와 충돌). 여기서 할 일이 없다.
            elseif isBarrel and barrelRollDir and barrelSideAxis then
                -- 🛢️ [2026-09-18] 여기서는 아무것도 하지 않는다.
                --   속도·각속도는 위 `Parent = workspace` 직후에서 이미 줬다.
                --   [왜 옮겼나] 이 블록은 wait(0.05) 뒤라, 그 사이 배럴이 각속도 없이
                --     떨어지며 자세가 틀어졌다(실측 0.89~0.94). 1852행 진단의 처방이다.
                --   ⚠️ 여기에 속도를 다시 넣지 말 것. 2026-08-26 에 "두 자리가 값을 넣고
                --     싸우는" 문제를 이미 겪었다 — 속도는 한 곳에서만 정한다.
                --   ⚠️ 되돌리려면 위 블록을 지우고 원래 본문을 여기로 복원한다.
                --     원래 본문의 상세 주석(각속도 부호·구름 조건)은 위로 함께 옮겨갔다.
                if not barrelVelocityDone then
                    warn("🛢️ [Barrel] 즉시 속도 적용이 건너뛰어졌다 — PrimaryPart 없음?")
                end
            elseif isSpikedWood then
                -- SpikedWood: 태거가 바라보는 방향으로 부스팅
                local character = player.Character
                local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                local forwardDir = rootPart and rootPart.CFrame.LookVector or Vector3.new(0, 0, -1)
                local boostVelocity = forwardDir * 50 + Vector3.new(0, -10, 0)
                -- AssemblyLinearVelocity는 PrimaryPart에 적용 (어셈블리 전체에 영향)
                newItem.PrimaryPart.AssemblyLinearVelocity = boostVelocity
                -- 각속도는 적용하지 않음 → 바닥 마찰로 자연스럽게 굴러가도록
                print("✅ SpikedWood 부스팅:", boostVelocity)
            else
                newItem.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, -30, 25)
                -- (초기 속도 로그 제거 — 요청 1줄로 충분)
            end

            -- 🪨 스톤 성장 (Model 경로 — SunStone 만 Model 이다)
            -- ⚠️ BasePart 경로와 같은 함수를 쓴다. 따로 적으면 스킨에 따라 동작이 갈린다.
            if isStone then startStoneGrowth(newItem) end
        end
    else
        -- BasePart인 경우
        -- 용접된 장식 파트(예: DemonFlameStone의 불꽃)가 따라오도록 어셈블리 전체 이동
        newItem:PivotTo(CFrame.new(spawnPos))
        newItem.CanCollide = true
        newItem.Anchored = false
        newItem.CollisionGroup = "TaggerItems"
        
        -- ItemNoob 특별 처리
        if isItemNoob then
            newItem.CustomPhysicalProperties = PhysicalProperties.new(
                0.3, 0.01, 0.5, 1, 1
            )
            
            -- 회전 스크립트 부착
            local rotator = rotatorTemplate:Clone()
            rotator.Parent = newItem
            rotator.Disabled = false
        end
        
        newItem.Parent = workspace
        -- 조준 레이캐스트 제외용 표식.
        -- ⚠️ CollisionGroup 으로 거르면 놓친다 — ItemNoob/GoldNeonNoob 등은 의도적으로
        --    "Default" 그룹을 쓰기 때문(벽·산과 충돌해야 함). 그룹과 무관한 표식이 필요.
        newItem:SetAttribute("TaggerSpawnedItem", true)
        -- 🧍 BasePart 경로의 뉴비(스킨 변형 등). 위 Model 경로와 짝이다.
        --   ⚠️ 바로 아래 wait(0.05) 보다 앞이어야 한다. 그 사이에 같은 플레이어가 또 던지면
        --     등록 전이라 게이트를 통과해 두 마리가 생긴다.
        if isItemNoob then registerNoobInstance(player, newItem) end
        
        -- 즉각적인 속도 적용!
        wait(0.05)
        if isItemNoob then
            newItem.AssemblyLinearVelocity = Vector3.new(0, -40, 35)
            newItem.AssemblyAngularVelocity = Vector3.new(25, 0, 0)
            print("✅ ItemNoob 강화 속도:", Vector3.new(0, -40, 35))
        else
            newItem.AssemblyLinearVelocity = Vector3.new(0, -30, 25)
            -- 🪨 [버그수정 2026-09-05] 구르는 아이템에 각속도를 함께 준다.
            --   [증상] 스톤이 열에 아홉은 굴러오다 옆으로 빠졌다.
            --   [1차 시도의 오류] X축 회전 (25/r, 0, 0) 을 줬는데, 실제 굴러가는 방향이
            --     -X 였다. 진행 방향과 회전축이 '직각이 아니라 평행'이라 팽이처럼
            --     제자리 회전하며 옆으로 미끄러졌다. ItemNoob(+Z 진행)의 값을
            --     방향 확인 없이 베낀 것이 원인이다.
            --   [정석] 배럴(1666~1670행)이 이미 쓰는 공식을 그대로 따른다.
            --     sideAxis = up × rollDir  →  각속도 = -sideAxis * (속도/반지름)
            --     "rollDir 로 굴러가려면 그 축의 '음' 방향으로 회전"(오른손 법칙).
            --   ⚠️ 반지름은 스톤 성장(0.75~2.20배) 때문에 시점마다 다르다.
            --     발사 순간의 실제 크기로 계산한다 — 상수로 박으면 성장 배율이 바뀔 때 어긋난다.
            if isStone then
                -- ⚠️ 여기서 AssemblyLinearVelocity 를 바로 읽으면 안 된다. 방금 대입한
                --   (0,-40,35) 는 '로컬 기준으로 의도한' 값이고, 아이템이 회전 배치돼
                --   나가므로 월드 진행 방향과 다르다(실측: 선속은 +Z 인데 맵상 진행은 -X).
                --   물리가 한 번 돌아야 월드 속도가 확정된다 — 그 뒤에 축을 잡는다.
                --   (09-01: "부착·복제는 같은 프레임에 안 끝난다. task.delay 뒤에 잰다")
                local stoneRef = newItem
                task.delay(0.1, function()
                    if not stoneRef or not stoneRef.Parent then return end
                    local wv = stoneRef.AssemblyLinearVelocity
                    local rollDir = Vector3.new(wv.X, 0, wv.Z)
                    if rollDir.Magnitude < 0.5 then return end
                    local speed = rollDir.Magnitude
                    rollDir = rollDir.Unit
                    -- sideAxis = up × rollDir. rollDir 로 굴러가려면 그 축의 '음'방향 회전
                    -- (오른손 법칙) — 배럴 1666~1670행과 같은 공식.
                    local sideAxis = Vector3.new(0, 1, 0):Cross(rollDir)
                    local radius = stoneRef.Size.Y * 0.5
                    if radius > 0.1 and sideAxis.Magnitude > 0.01 then
                        stoneRef.AssemblyAngularVelocity = -sideAxis.Unit * (speed / radius)
                    end
                end)
            end
        end

        -- 🪨 스톤 성장 (BasePart 경로 — 대부분의 스톤 계열)
        if isStone then startStoneGrowth(newItem) end
    end
    -- 청사진 제거
    local blueprintName = "Blueprint_" .. player.Name
    local blueprint = workspace:FindFirstChild(blueprintName)
    if blueprint then
        blueprint:Destroy()
        print("✅ Blueprint removed after spawn")
    end
    
    -- 쿨타임 설정
    playerCooldowns[player.UserId][itemName] = currentTime
    setGlobalCooldown(player, currentTime, itemName)

    -- ── 아이템 사운드 ────────────────────────────────────────
    -- 스폰 시 1회 + (굴러가는 아이템은) 랜덤 간격 반복.
    -- 서버에서 아이템 파트에 직접 붙여 모든 클라이언트에 3D 사운드로 복제되게 한다.
    attachItemSound(newItem, itemName)

    -- (스폰 완료 로그 제거 — 요청 1줄로 충분)
    -- 쿨다운은 요청 로그(handleSpawnRequest)에 합쳤다.
    -- ⚠️ 두 쿨을 모두 보여야 한다. 전역만 찍으면 "1.5초로 설정됨"으로 오해된다(실측 2026-08-22).
end

spawnItemEvent.OnServerEvent:Connect(handleSpawnRequest)

-- 태거 봇(서버) 스폰 진입점: TaggerBotSystem이 의사 player로 호출
_G.BotSpawnItem = handleSpawnRequest

-- 🔒 [2026-08-27] 단일 존재 아이템의 '상태 잠금' 표시.
--   [왜] ITEM_COOLDOWN 과 별개로, 효과가 끝나야 다시 쓸 수 있는 아이템이 셋 있다:
--     · Frost Dragon (_G.FrostCooldown — 얼음 파쇄까지, 실측 약 26초)
--     · tox_box      (이전 박스가 베이스에 도달할 때까지)
--     · tnt          (폭격 조준이 끝날 때까지)
--     표에 적힌 쿨(8/3/7)이 끝나도 못 쓰는데 UI 는 그걸 몰라 "열린 것처럼" 보였다.
--   [왜 숫자가 아니라 텍스트인가] 셋 중 둘은 종료 시점이 예측 불가다.
--     톡스박스는 지형·거리에 따라, TNT 는 태거 본인이 조준을 끝낼 때 풀린다.
--     프드는 파쇄 시간이 기둥 수(33~144)에 비례해 24~28초로 흔들린다.
--     예측 못 하는 걸 숫자로 보여주면 0 에 닿아도 안 열려 UI 가 또 거짓말을 한다.
--   ⚠️ ItemCooldownStart 와 별도 이벤트다. 그쪽은 '시간'을 보내고 클라가 카운트다운을
--     돌리는 경로라, 여기 상태를 섞으면 남은 시간 계산이 꼬인다.
--   ⚠️ 반드시 짝으로 부를 것 — 잠글 때 true, 풀릴 때 false.
--     한쪽만 부르면 그 아이템이 영영 잠긴 것처럼 보인다.
do
    local lockEv = game:GetService("ReplicatedStorage"):FindFirstChild("ItemLockState")
    if not lockEv then
        lockEv = Instance.new("RemoteEvent")
        lockEv.Name = "ItemLockState"
        lockEv.Parent = game:GetService("ReplicatedStorage")
    end
    -- player 는 진짜 Player 여야 한다. 태거봇은 pseudoPlayer(Lua 테이블)라 FireClient 가 터진다.
    _G.SetItemLock = function(player, itemName, locked, label)
        if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
        lockEv:FireClient(player, itemName, locked and true or false, label)
    end
end

print("Item Spawn Handler ready (ItemNoob Continuous Rotation)!")
