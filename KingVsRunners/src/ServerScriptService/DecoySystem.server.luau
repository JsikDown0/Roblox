-- DecoySystem
-- 디코이(분신) 러너 아이템 처리
--  · 사용 시: 러너 1초 투명화 + 옆에 분신 소환
--  · 분신: 러너의 "행동(자세/이동)"을 매 프레임 복사 (들고 있는 아이템은 복사하지 않음 — 의도)
--    ⚠️ 현재 1단계 전용 아이템으로 취급한다. 2단계 미지원 사유는 클론 정리 루프 주석 참조.
--  · 소멸 조건: 태거 아이템에 닿거나(ItemDamageSystem 훅 → _G.popDecoy) 20초 경과
-- ─────────────────────────────────────────────────────────────
local Players        = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage  = game:GetService("ServerStorage")
local RunService     = game:GetService("RunService")
local PhysicsService  = game:GetService("PhysicsService")
local PathfindingService = game:GetService("PathfindingService")

local useEvent = ReplicatedStorage:WaitForChild("DecoyUse")

-- ── 튜닝 값 ───────────────────────────────────────────
local INVIS_DURATION = 2      -- 러너 투명화 지속(초)
local LIFETIME       = 20     -- 분신 최대 생존(초)
local SIDE_OFFSET    = 4      -- 러너 기준 오른쪽으로 떨어진 거리(studs)
local USE_COOLDOWN   = 0.5    -- 중복 발화 방지

-- 🏃 [2026-08-30] 분신 자율 대시 (Q대시 흉내)
--   [왜] 다른 러너는 대시 잔상을 남기는데 분신만 한 번도 안 남기면, 그게 "가짜" 표시가 된다.
--   ⚠️ 주인의 대시를 따라 하는 게 아니다. 분신은 소환 시점의 속도·방향으로 자율 주행해서
--     주인과 위치가 완전히 다르다. 주인 대시에 맞춰 잔상을 그리면 엉뚱한 자리에 뜬다.
--     자기 리듬으로 대시해야 한다.
--   ⚠️ 수치는 RunnerDive 의 실제 대시와 맞춘다. 어긋나면 속도감 차이로 오히려 티가 난다.
--     원본: BURST 0.50s @80 → 탈진 1.0s @6 → 쿨 6s
local DASH_BURST_TIME    = 0.50
local DASH_BURST_SPEED   = 80
local DASH_EXHAUST_TIME  = 1.00
local DASH_EXHAUST_SPEED = 6
local DASH_MIN_GAP       = 5.0   -- 대시 간격(초). 실제 쿨 6s 주변으로 흔들어 기계적 반복을 피한다
local DASH_MAX_GAP       = 9.0

-- 🛡️ [2026-08-30] 태거 아이템 회피.
--   [왜] 회피가 전혀 없어서 분신이 너무 쉽게 터졌다. 진짜 러너는 날아오는 걸 피하므로
--     한 번도 안 피하는 개체는 그 자체로 "가짜" 표시가 된다.
--   ⚠️ 판정 로직을 복사하지 않는다. RunnerBotDriveController 가 이미 프레임당 1회
--     위협 레지스트리를 갱신하므로(_G.getItemDodgeVector), 그걸 그대로 호출한다.
--     복사하면 위협 판정이 두 벌이 되어 한쪽만 고쳐지는 사고가 난다.
--   ⚠️ 농민봇(엘리트 반경 75)보다 일부러 둔하게 잡았다. 분신이 사람보다 잘 피하면
--     그게 오히려 정체 단서가 된다 — 위장이 목적이지 생존이 목적이 아니다.
local DODGE_RADIUS    = 45    -- 감지 반경(stud)
local DODGE_MIN_SPEED = 12    -- 이 속도 이상으로 움직이는 아이템만 위협으로 본다
local DODGE_APPROACH  = 0.15  -- 아이템 진행방향이 분신을 향하는 정도(내적 임계)
local DODGE_NEAR      = 20    -- 이 거리 안이면 긴급 — 전진을 버리고 측면 우선
local DODGE_LATERAL   = 1.8   -- 측면 강도(전진 대비)
local DODGE_HOLD      = 0.45  -- 위협이 사라져도 방향 유지(초). 없으면 움직임이 덜덜 끊긴다

-- ── DecoyChar 콜리전 그룹 (TaggerItems와만 충돌, 나머지 전부 통과) ──
-- TaggerItems와 충돌 가능해야 ItemDamageSystem의 Touched 판정이 분신에도 동일하게 걸린다.
-- 나머지 그룹과는 비충돌 → 러너/태거/지형을 막거나 물리적으로 밀리지 않음.
local DECOY_GROUP = "DecoyChar"
local function ensureGroup(name)
    if not PhysicsService:IsCollisionGroupRegistered(name) then
        PhysicsService:RegisterCollisionGroup(name)
    end
end
ensureGroup(DECOY_GROUP)
ensureGroup("TaggerItems")
PhysicsService:CollisionGroupSetCollidable(DECOY_GROUP, "TaggerItems", true)
for _, g in ipairs({"Default","RunnerCharacter","TaggerCharacter","Runners",
                    "Walls","Mountains","ItemBarrier","TaggerBarrier","IceEffect"}) do
    pcall(function()
        if PhysicsService:IsCollisionGroupRegistered(g) then
            PhysicsService:CollisionGroupSetCollidable(DECOY_GROUP, g, false)
        end
    end)
end
PhysicsService:CollisionGroupSetCollidable(DECOY_GROUP, DECOY_GROUP, false)

-- ── 상태 ──────────────────────────────────────────────
local cooldowns      = {}   -- [userId] = tick
local activeByUser   = {}   -- [userId] = cleanup fn
local cleanupByModel = {}   -- [decoyModel] = cleanup fn

-- ── 등장/소멸 연기 연출 (사용자 제작 "smoke vfx" 사용) ──
-- 템플릿을 ServerStorage로 보관(월드에 상시 표시 방지)하고, 매 연출마다 클론.
local SMOKE_SHOW       = 0.5    -- Smoke 방출 펄스 지속(초)
local SMOKE_LINGER     = 2.5    -- 잔류 후 완전 제거까지(초)
local SMOKE_EMIT_COUNT = 80     -- ParticleEmitter 1개당 한 번에 방출할 개수 (에미터 2개 → 총 160)

local smokeTemplate = ServerStorage:FindFirstChild("smoke vfx") or workspace:FindFirstChild("smoke vfx")
if smokeTemplate then
    smokeTemplate.Parent = ServerStorage  -- 템플릿 보관
    for _, d in ipairs(smokeTemplate:GetDescendants()) do
        if d:IsA("Smoke") or d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Beam") then
            d.Enabled = false
        elseif d:IsA("RocketPropulsion") or d:IsA("BodyMover")
            or d:IsA("Script") or d:IsA("LocalScript") then
            d:Destroy()
        end
    end
    print("✅ [Decoy] smoke vfx 템플릿 로드 (ServerStorage 보관)")
else
    warn("⚠️ [Decoy] 'smoke vfx' 를 찾지 못함 — 연기 연출 비활성")
end

local function poof(cframe, silent)
    if not smokeTemplate then return end
    local fx = smokeTemplate:Clone()

    if fx:IsA("BasePart") then
        fx.Anchored     = true
        fx.CanCollide   = false
        fx.CanQuery     = false
        fx.CanTouch     = false
        fx.Transparency = 1
        fx.CFrame       = cframe
    end
    fx.Parent = workspace

    -- 효과음 (등장/소멸 공통) — 1.2배속 / 볼륨 1.5. silent=true면 생략(중복 방지)
    if not silent then
        local snd = Instance.new("Sound")
        snd.SoundId          = "rbxassetid://73479075020170"
        snd.PlaybackSpeed    = 1.2
        snd.Volume           = 1.5
        snd.RollOffMaxDistance = 80
        snd.Parent           = fx
        snd:Play()
    end

    for _, d in ipairs(fx:GetDescendants()) do
        if d:IsA("ParticleEmitter") then
            -- 진짜 대량 버스트: 한 번에 SMOKE_EMIT_COUNT개 방출
            d.Enabled = true
            pcall(function() d:Emit(SMOKE_EMIT_COUNT) end)
        elseif d:IsA("Smoke") then
            -- 레거시 Smoke는 Emit이 없으므로, 터질 때 짙고 크게(유사 버스트)
            d.Opacity = 1
            d.Size = math.clamp(d.Size * 2.5, 1, 10)
            d.Enabled = true
        elseif d:IsA("Fire") or d:IsA("Beam") then
            d.Enabled = true
        end
    end

    -- 펄스 종료 → 방출 중단, 잔류 사라지면 제거
    task.delay(SMOKE_SHOW, function()
        if fx and fx.Parent then
            for _, d in ipairs(fx:GetDescendants()) do
                if d:IsA("Smoke") or d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Beam") then
                    d.Enabled = false
                end
            end
        end
    end)
    game:GetService("Debris"):AddItem(fx, SMOKE_LINGER)
end

-- ── 분신 정리 ─────────────────────────────────────────
local function makeCleanup(model, conn, userId)
    local done = false
    return function()
        if done then return end
        done = true
        if conn then conn:Disconnect() end
        cleanupByModel[model] = nil
        if activeByUser[userId] == nil then end
        if model and model.Parent then
            poof(model:GetPivot())
            model:Destroy()
        end
    end
end

-- ── 목표(언덕 위 계단) 찾기 ───────────────────────────
-- 계단 = ItemSpawnPlate(정상 도달 지점), 없으면 taggerbase(성/언덕 상단)로 폴백.
--
-- ⚠️ workspace 전역 재귀 검색을 쓰면 안 된다.
--   map1/map2 가 동시에 workspace 에 존재하고, map2 의 파트는 이름 끝에 "2" 가 붙는다
--   (ItemSpawnPlate2 / taggerbase2). 그래서 FindFirstChild("ItemSpawnPlate", true) 는
--   map2 라운드에서도 map1 의 것을 반환해, 분신이 반대편 맵으로 달려갔다(실측).
--   → 플레이어가 서 있는 맵을 기준으로 그 맵 안에서만 찾는다.
local function mapFolderOf(position)
    -- ⚠️ map1/map2 는 Model 이 아니라 Folder 라 GetBoundingBox 를 쓸 수 없다(실측: pcall 실패).
    --    각 맵의 대표 파트(계단 플레이트)를 기준점으로 삼아 가까운 쪽을 고른다.
    --    두 맵은 Z 로 크게 떨어져 있어(map1 ≈ -675, map2 ≈ 898) 오판 여지가 없다.
    local best, bestDist
    for _, name in ipairs({"map1", "map2"}) do
        local mf = workspace:FindFirstChild(name)
        if mf then
            local ref = mf:FindFirstChild("ItemSpawnPlate", true)
                or mf:FindFirstChild("ItemSpawnPlate2", true)
                or mf:FindFirstChild("taggerbase", true)
                or mf:FindFirstChild("taggerbase2", true)
            if ref and ref:IsA("BasePart") then
                local d = (ref.Position - position).Magnitude
                if not bestDist or d < bestDist then bestDist = d; best = mf end
            end
        end
    end
    return best
end

local function findGoal(fromPosition)
    local mf = fromPosition and mapFolderOf(fromPosition)
    if mf then
        -- 이름 끝 "2" 변형까지 함께 확인
        for _, n in ipairs({"ItemSpawnPlate", "ItemSpawnPlate2"}) do
            local p = mf:FindFirstChild(n, true)
            if p and p:IsA("BasePart") then return p end
        end
        for _, n in ipairs({"taggerbase", "taggerbase2"}) do
            local b = mf:FindFirstChild(n, true)
            if b and b:IsA("BasePart") then return b end
        end
    end
    -- 폴백: 기존 전역 검색 (맵 판별 실패 시)
    local plate = workspace:FindFirstChild("ItemSpawnPlate", true)
        or workspace:FindFirstChild("ItemSpawnPlate2", true)
    if plate and plate:IsA("BasePart") then return plate end
    local base = workspace:FindFirstChild("taggerbase", true)
        or workspace:FindFirstChild("taggerbase2", true)
    if base and base:IsA("BasePart") then return base end
    return nil
end

-- ── 분신 생성 ─────────────────────────────────────────
local function spawnDecoy(player)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not root then return end

    -- 기존 분신 제거 (1인 1분신)
    if activeByUser[player.UserId] then
        activeByUser[player.UserId]()
        activeByUser[player.UserId] = nil
    end

    -- ⏱️ [진단 2026-09-06] 분신 소환 구간별 비용 측정.
    --   [증상] 완드 사용(54.157) → 분신 소환(56.174) 사이 2초 동안
    --     서버 611ms/534ms, 클라 1129ms 지연이 동시에 발생했다.
    --   [왜 구간별인가] "분신이 무겁다"까지는 알지만 Archivable 루프인지, Clone 인지,
    --     정리 루프인지, 길찾기인지 모른다. 처방이 각각 다르므로 갈라 재야 한다.
    --   ⚠️ 원인 확정 후 삭제할 것.
    local _t = os.clock()
    local _phase = {}
    local function mark(name)
        _phase[#_phase+1] = string.format("%s=%.0fms", name, (os.clock() - _t) * 1000)
        _t = os.clock()
    end

    -- 클론 (외형 인스턴스가 빠짐없이 복제되도록 모든 하위 Archivable 보장)
    char.Archivable = true
    local descCount = 0
    for _, d in ipairs(char:GetDescendants()) do
        descCount = descCount + 1
        pcall(function() d.Archivable = true end)
    end
    mark("Archivable(" .. descCount .. ")")

    local clone = char:Clone()
    mark("Clone")

    -- 원본 휴머노이드/애니메이션 참고 + 질주 방향(사용 순간 보던 방향, 수평 투영)
    local srcHum = char:FindFirstChildOfClass("Humanoid")
    local runSpeed = (srcHum and srcHum.WalkSpeed > 0 and srcHum.WalkSpeed) or 16
    local lookFlat = root.CFrame.LookVector
    lookFlat = Vector3.new(lookFlat.X, 0, lookFlat.Z)
    if lookFlat.Magnitude < 0.05 then lookFlat = root.CFrame.LookVector end
    local moveDir = lookFlat.Unit

    -- 클론 정리: Humanoid는 유지(옷/피부색/얼굴 렌더에 필요), 스크립트/툴/사운드/UI만 제거
    -- ⚠️ [2026-08-30] 여기서 Tool 을 전부 지우는 건 의도된 동작이다. 2단계 무기 복제를
    --   시도했다가 되돌렸으니, 같은 시도를 반복하기 전에 아래를 먼저 읽을 것.
    --   [왜 안 되는가]
    --   1) 캐릭터는 툴을 하나만 든다. 완드를 쓰는 순간 무기는 이미 Backpack 에 있다.
    --      따라서 clone 의 자식에서는 무기를 절대 찾을 수 없다(맨손으로 나온다).
    --      Backpack 을 뒤지면 찾을 수 있지만, 거기엔 소모품이 섞여 있어 무기 목록이 따로 필요하다.
    --      ServerStorage.RunnerItem 은 무기·소모품이 섞여 있어 그대로는 목록이 못 된다(측정 완료).
    --   2) 더 근본적으로, 분신의 행동이 1단계 전용이다 — 목표 지점으로 직진만 한다.
    --      2단계 러너는 그렇게 움직이지 않으므로, 무기를 들려도 행동에서 먼저 들통난다.
    --      무기는 위장의 조각 하나일 뿐이라 행동이 어긋나면 채워도 의미가 없다.
    --   [결론] 2단계 지원은 러너봇 AI 작업 뒤로 미룬다. 그때 "2단계 러너답게 움직이는 법"이
    --     생기면 분신이 그걸 재사용해야 한다. 지금 따로 만들면 같은 로직이 두 곳에 생긴다.
    local cloneHumanoid = nil
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("Humanoid") then
            cloneHumanoid = d  -- 유지
        elseif d:IsA("BillboardGui") then
            -- 🪪 [2026-09-06] BillboardGui 를 통째로 지우던 것을 선별로 바꿨다.
            --   [증상] 분신에 내구도 게이지(방패 아이콘)가 없어 실제 러너와 즉시 구분됐다.
            --   [왜 전에는 다 지웠나] 스크립트가 만든 UI 가 클론에 남아 어긋나는 걸 막으려던 것이다.
            --     하지만 '위장'이 목적인 아이템에서 표시가 빠지면 그 표시의 부재가 곧 단서가 된다.
            --   ⚠️ DurabilityGauge 만 남긴다. 나머지(VIPNametag 등)는 그대로 지운다 —
            --     VIP 태그는 Players:GetPlayers() 로 다시 붙는 구조라 클론에 남으면 중복이 되고,
            --     주인이 VIP 가 아니면 애초에 없어야 한다.
            --   ⚠️ 남긴 게이지는 '복제 시점의 칸 수'로 얼어붙는다. 주인이 이후에 피격돼도
            --     분신 쪽은 안 줄어든다 — 분신은 주인을 따라가지 않으므로 오히려 자연스럽다.
            -- ⚠️ [2026-09-06 수정] VIPNametag 도 남긴다.
            --   [증상] VIP 유저가 분신을 쓰면 주인만 금색 이름이 뜨고 분신은 없어서
            --     즉시 구분됐다. "VIP 를 샀더니 오히려 불리해지는" 상태였다.
            --   [원인] VIP 는 기본 이름표(NameDisplayDistance)를 끄고 별도 BillboardGui 로
            --     금색 이름을 그린다. 그래서 Humanoid 쪽 설정을 아무리 만져도 안 먹는다.
            --   ⚠️ 중복 걱정은 없다. VIPNametag 는 hookPlayer 가 Players 를 돌며 붙이는데,
            --     분신은 Player 가 아니라 다시 붙을 일이 없다(전수 확인).
            --   ⚠️ Adornee/Parent 가 같은 모델 안의 Head 를 가리키므로 Clone 이 자동 재매핑한다.
            if d.Name ~= "DurabilityGauge" and d.Name ~= "VIPNametag" then
                d:Destroy()
            end
        elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")
            or d:IsA("Tool") or d:IsA("Sound") or d:IsA("ForceField")
            or d:IsA("ParticleEmitter") then
            d:Destroy()
        end
    end

    mark("Cleanup")

    -- 파트: 언앵커 + RunnerCharacter 그룹 (실제 러너처럼 지형 위를 걷고 태거 아이템에 맞도록)
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = false
            pcall(function() d.CollisionGroup = "RunnerCharacter" end)
        end
    end

    local cloneRoot = clone:FindFirstChild("HumanoidRootPart")

    -- Humanoid: 자율 질주 설정 (외형/이름표 유지, 체력바 숨김)
    if cloneHumanoid then
        -- 🪪 [2026-09-06] 기본값 Viewer 그대로 둔다.
        --   한때 주인과 함께 None 으로 숨겼는데, 원인이 VIPNametag 임을 알고 되돌렸다.
        --   숨기는 것보다 '똑같이 보이게' 하는 편이 낫다 — 이름 없는 둘은 사람 러너가
        --   여럿인 판에서 오히려 튀고, 아군에게 필요한 정보까지 지운다.
        --   ⚠️ NameDisplayDistance 는 복제된 값을 그대로 쓴다. VIP 면 0(기본 이름 꺼짐),
        --     비VIP 면 100 이라 주인과 자동으로 일치한다.
        cloneHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
        cloneHumanoid.HealthDisplayType   = Enum.HumanoidHealthDisplayType.AlwaysOff
        cloneHumanoid.MaxHealth = math.huge
        cloneHumanoid.Health    = math.huge
        cloneHumanoid.WalkSpeed = runSpeed
        cloneHumanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
        -- 🪪 [2026-09-06] 조건 없이 항상 주인 이름으로 덮는다.
        --   [증상] 분신 머리 위 이름이 실제 러너와 달랐다.
        --   [원인] 로블록스 이름표는 Humanoid.DisplayName 이 비어 있을 때만
        --     모델 이름으로 폴백한다. 그런데 아래에서 clone.Name 을
        --     "<이름>_Decoy" 로 바꾸므로, DisplayName 이 비어 있으면 그게 그대로 뜬다.
        --     기존 코드는 '비어 있을 때만' 채웠는데, 복제된 Humanoid 의 DisplayName 이
        --     비지 않았더라도 주인 표시명과 다를 수 있다(표시명 변경·캐시 시점 차이).
        --   ⚠️ 항상 덮는 편이 안전하다. 어차피 목적은 "주인과 똑같이 보이는 것" 하나다.
        cloneHumanoid.DisplayName = player.DisplayName
    end

    -- ⚠️ 모델 이름에 _Decoy 를 붙이는 건 코드가 분신을 식별하기 위해서다.
    --   화면에 뜨는 이름은 위에서 세운 Humanoid.DisplayName 이므로 이 이름은 안 보인다.
    --   ⚠️ 이름을 주인과 똑같이 만들지 말 것 — 로그·디버그에서 둘을 구분할 수 없게 된다.
    clone.Name = player.Name .. "_Decoy"
    clone:SetAttribute("IsDecoy", true)
    -- 🪪 [2026-09-06] 주인의 UserId 를 심는다.
    --   [왜] 태거 화면의 러너 마커는 userId 로 프로필 사진을 띄운다
    --     (PlayerMarkerClient: headshot-thumbnail?userId=...).
    --     없으면 분신만 아바타가 빈 마커로 떠서 그게 곧 "가짜" 표식이 된다.
    --   ⚠️ 위장용 표시 데이터일 뿐이다. 판정·크레딧에는 절대 쓰지 말 것 —
    --     분신을 때린 걸 주인을 때린 것으로 세면 안 된다.
    clone:SetAttribute("DecoyOwnerId", player.UserId)
    -- 🏃 잔상 색 동기화. 클라 수신부는 who:GetAttribute("DashSkin") 로 색을 정하므로,
    --   여기서 주인 값을 복사해 두면 Player 든 분신 모델이든 같은 코드로 색이 나온다.
    --   ⚠️ 이걸 빼면 분신 잔상만 기본색으로 떠서, 스킨 낀 러너 옆에서 바로 구분된다.
    -- ⚠️ [2026-08-30] nil 폴백을 둔다.
    --   [증상] 실측 15:23 — DashSkin=nil 로 복사돼 분신 잔상이 기본색으로 떴다.
    --   [원인] EffectSystem 이 라운드 적용 시 "Default" 를 넣는데(:358), 그게 아직
    --     안 돈 시점에 분신을 뽑으면 속성이 없다. 정상 흐름이면 최소 "Default" 다.
    --   ⚠️ nil 을 그대로 넘기면 SetAttribute 가 속성을 '지우는' 동작이 되어,
    --     분신에 키 자체가 없어진다. 클라는 그걸 미장착으로 읽는다.
    clone:SetAttribute("DashSkin", player:GetAttribute("DashSkin") or "Default")
    -- ✨ [2026-08-30] 트레일도 같은 이유로 복사한다.
    --   [왜] RunnerTrail(클라)은 player:GetAttribute("TrailSkin") 을 읽어 '자기 캐릭터'에만
    --     트레일을 붙인다. 분신은 Player 가 아니므로 그 경로를 안 탄다.
    --   [해결] 분신 모델에 같은 키를 박아두고, 클라가 IsDecoy 모델을 보면 같은 스펙으로 만든다.
    --   ⚠️ DashSkin 과 한 짝이다. 하나만 복사하면 "잔상 색은 같은데 트레일만 없는" 분신이 되어
    --     오히려 더 눈에 띈다 — 분신의 목적은 구분되지 않는 것이다.
    clone:SetAttribute("TrailSkin", player:GetAttribute("TrailSkin"))

    -- 스폰: 러너 살짝 앞(겹침 방지) + 같은 방향, 서버 권한 물리
    if cloneRoot then clone.PrimaryPart = cloneRoot end
    local spawnSide = (math.random() < 0.5) and 18 or -18   -- 50% 확률로 좌/우
    clone:PivotTo(root.CFrame * CFrame.new(spawnSide, 0, -2))
    mark("Setup")
    clone.Parent = workspace
    mark("Parent")
    warn("⏱️ [Decoy] 구간별: " .. table.concat(_phase, " "))
    if cloneRoot then pcall(function() cloneRoot:SetNetworkOwner(nil) end) end

    -- 애니메이션: 달리기(루프) + 점프(점프 상태 진입 시 자동 재생 → 진짜 플레이어처럼)
    if cloneHumanoid then
        local animator = cloneHumanoid:FindFirstChildOfClass("Animator")
        if not animator then
            animator = Instance.new("Animator")
            animator.Parent = cloneHumanoid
        end

        local srcAnimate = char:FindFirstChild("Animate")
        local function animIdFrom(folderName, fallback)
            if srcAnimate then
                local folder = srcAnimate:FindFirstChild(folderName)
                local obj = folder and folder:FindFirstChildOfClass("Animation")
                if obj and obj.AnimationId ~= "" then return obj.AnimationId end
            end
            return fallback
        end

        -- 달리기 (루프)
        local runAnim = Instance.new("Animation")
        runAnim.AnimationId = animIdFrom("run", animIdFrom("walk", "rbxassetid://913376220"))
        local okR, runTrack = pcall(function() return animator:LoadAnimation(runAnim) end)
        if okR and runTrack then
            runTrack.Priority = Enum.AnimationPriority.Movement
            runTrack.Looped = true
            runTrack:Play()
        end

        -- 점프/낙하: 실제 플레이어처럼 jump(상승) → fall(하강, 루프) → 착지 정리
        local jumpAnim = Instance.new("Animation")
        jumpAnim.AnimationId = animIdFrom("jump", "rbxassetid://125750702")
        local _, jumpTrack = pcall(function() return animator:LoadAnimation(jumpAnim) end)

        local fallAnim = Instance.new("Animation")
        fallAnim.AnimationId = animIdFrom("fall", "rbxassetid://180436148")
        local _, fallTrack = pcall(function() return animator:LoadAnimation(fallAnim) end)

        if jumpTrack then
            jumpTrack.Priority = Enum.AnimationPriority.Action
            jumpTrack.Looped = false
        end
        if fallTrack then
            fallTrack.Priority = Enum.AnimationPriority.Action
            fallTrack.Looped = true
        end

        cloneHumanoid.StateChanged:Connect(function(_, newState)
            if newState == Enum.HumanoidStateType.Jumping then
                if fallTrack then fallTrack:Stop(0.1) end
                if jumpTrack then jumpTrack:Play(0.1) end
            elseif newState == Enum.HumanoidStateType.Freefall then
                if jumpTrack then jumpTrack:Stop(0.2) end
                if fallTrack then fallTrack:Play(0.2) end
            elseif newState == Enum.HumanoidStateType.Landed
                or newState == Enum.HumanoidStateType.Running
                or newState == Enum.HumanoidStateType.RunningNoPhysics then
                if jumpTrack then jumpTrack:Stop(0.15) end
                if fallTrack then fallTrack:Stop(0.15) end
            end
        end)
    end

    local cleanup = makeCleanup(clone, nil, player.UserId)
    activeByUser[player.UserId] = cleanup
    cleanupByModel[clone] = cleanup

    -- 등장 연기 (LoL 분신 소환 연출)
    poof(clone:GetPivot())

    -- 20초 후 자동 소멸
    task.delay(LIFETIME, function()
        if activeByUser[player.UserId] == cleanup then
            activeByUser[player.UserId] = nil
        end
        cleanup()
    end)

    -- ── 자율 주행: 언덕 위 계단(목표)으로 길찾기 ───────────
    local function isAlive()
        return clone.Parent ~= nil and cloneHumanoid and cloneHumanoid.Parent ~= nil
    end

    -- 분신이 서 있는 위치를 기준으로 그 맵의 목표를 찾는다(map1/map2 혼동 방지)
    local goalPart = findGoal(cloneRoot and cloneRoot.Position or root.Position)

    -- 대각선 기믹: -1(좌) / 0(직진) / +1(우). 별도 루프가 주기적으로 토글
    local strafeBias = 0

    -- 회피 상태. 위협이 사라져도 DODGE_HOLD 동안 방향을 유지해 움직임이 끊기지 않게 한다.
    local dodgeVec, dodgeUntil = nil, 0

    task.spawn(function()
        task.wait(0.15)  -- 스폰 직후 착지 대기

        local function seekStep()
            -- 목표(계단) 수평 방향으로 직접 이동 → 언덕을 직접 기어오름
            if not (goalPart and cloneRoot) then
                cloneHumanoid:Move(moveDir, false)
                return false
            end
            local to = goalPart.Position - cloneRoot.Position
            to = Vector3.new(to.X, 0, to.Z)
            if to.Magnitude < 6 then
                cloneHumanoid:Move(Vector3.zero)
                return true  -- 도착
            end
            local fwd = to.Unit
            local move = fwd
            if strafeBias ~= 0 then
                -- 진행 방향 기준 수평 측면 벡터를 섞어 대각선으로 이동
                local right = Vector3.new(-fwd.Z, 0, fwd.X)
                local blended = fwd + right * (strafeBias * 0.9)
                if blended.Magnitude > 0.01 then move = blended.Unit end
            end
            -- ── 태거 아이템 회피 ──
            -- ⚠️ 위협 판정은 RunnerBotDriveController 의 공유 레지스트리에서 온다.
            --   봇이 한 마리도 없어도 그 갱신 루프는 모듈 수준이라 계속 돌아간다.
            if _G.getItemDodgeVector then
                local dv, dist = _G.getItemDodgeVector(
                    cloneRoot.Position, DODGE_RADIUS, DODGE_MIN_SPEED, DODGE_APPROACH)
                if dv then
                    dodgeVec, dodgeUntil = dv, os.clock() + DODGE_HOLD
                    if dist and dist <= DODGE_NEAR then
                        -- 긴급: 즉사 아이템이라 전진을 버리고 측면으로만 뺀다
                        move = dv
                    end
                end
            end
            if dodgeVec and os.clock() < dodgeUntil then
                local blended = move + dodgeVec * DODGE_LATERAL
                if blended.Magnitude > 0.01 then move = blended.Unit end
            elseif dodgeVec then
                -- ⚠️ 유지시간이 끝나면 반드시 비운다. 안 비우면 위협이 없는데도 계속 옆으로 샌다.
                dodgeVec = nil
            end

            cloneHumanoid:Move(move, false)
            return false
        end

        -- 길찾기 1회 시도: 성공하면 경로 추종(장애물 우회), 실패하면 시크로 계속
        if goalPart and cloneRoot then
            local path = PathfindingService:CreatePath({
                AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true,
            })
            -- ⏱️ [진단 2026-09-06] ComputeAsync 비용. map1 이 975 stud 폭이라
            --   경로 계산이 무거울 수 있다. NoPath 로 실패해도 계산 비용은 이미 치른다.
            --   ⚠️ 원인 확정 후 삭제할 것.
            local _pt = os.clock()
            local ok = pcall(function()
                path:ComputeAsync(cloneRoot.Position, goalPart.Position)
            end)
            local _pms = (os.clock() - _pt) * 1000
            if _pms > 50 then
                warn(string.format("⏱️ [Decoy] ComputeAsync %.0fms (거리 %.0f stud)",
                    _pms, (goalPart.Position - cloneRoot.Position).Magnitude))
            end
            print("🧭 [Decoy] 길찾기 상태:", ok and tostring(path.Status) or "ComputeAsync 에러")
            if ok and path.Status == Enum.PathStatus.Success then
                for _, wp in ipairs(path:GetWaypoints()) do
                    if not isAlive() then return end
                    if wp.Action == Enum.PathWaypointAction.Jump then
                        cloneHumanoid.Jump = true
                    end
                    cloneHumanoid:MoveTo(wp.Position)
                    cloneHumanoid.MoveToFinished:Wait()
                end
            end
        end

        -- 시크 주행 + 끼임 점프 (길찾기 실패/마무리 공통 경로)
        local lastPos = cloneRoot and cloneRoot.Position or Vector3.zero
        local stuck = 0
        while isAlive() do
            local arrived = seekStep()
            if arrived then
                while isAlive() do
                    cloneHumanoid:Move(Vector3.zero)
                    RunService.Heartbeat:Wait()
                end
                return
            end
            if cloneRoot then
                local moved = (cloneRoot.Position - lastPos).Magnitude
                lastPos = cloneRoot.Position
                if moved < 0.12 then
                    stuck += 1
                    if stuck >= 8 then        -- 약 0.13초 정지 → 점프로 장애물 넘기
                        cloneHumanoid.Jump = true
                        stuck = 0
                    end
                else
                    stuck = 0
                end
            end
            RunService.Heartbeat:Wait()
        end
    end)

    -- ── 사람처럼: 사라질 때까지 랜덤 주기로 점프 (계속 X) ──
    task.spawn(function()
        while isAlive() do
            -- 다음 점프까지 랜덤 대기 (1.8 ~ 5.0초)
            local waitT = math.random(18, 50) / 10
            local elapsed = 0
            while elapsed < waitT do
                if not isAlive() then return end
                RunService.Heartbeat:Wait()
                elapsed += 1/60
            end
            if isAlive() and cloneHumanoid and cloneHumanoid.Health > 0 then
                cloneHumanoid.Jump = true
            end
        end
    end)

    -- ── 산데비스탄 흉내: 가끔 Q대시 (잔상 포함) ──
    task.spawn(function()
        while isAlive() do
            local gap = DASH_MIN_GAP + math.random() * (DASH_MAX_GAP - DASH_MIN_GAP)
            local t = 0
            while t < gap do
                if not isAlive() then return end
                RunService.Heartbeat:Wait()
                t += 1/60
            end
            if not isAlive() or not cloneHumanoid or cloneHumanoid.Health <= 0 then return end

            -- 잔상 브로드캐스트. 페이로드가 Player 가 아니라 분신 모델이다.
            --   ⚠️ 수신부(RunnerDive)가 Model 을 받을 수 있어야 한다. Player 전용이면 조용히 무시된다.
            --   ⚠️ 리모트는 RunnerDiveServer 가 만든다. 부팅 순서가 보장되지 않으므로
            --     상단에서 한 번 잡지 않고 발동 시점에 찾는다(그때는 반드시 존재한다).
            local fx = ReplicatedStorage:FindFirstChild("RunnerDiveFxRemote")
            if fx then
                fx:FireAllClients(clone, DASH_BURST_TIME)
                print(string.format("[DecoyDash] 잔상 브로드캐스트 → %s (DashSkin=%s)",
                    clone.Name, tostring(clone:GetAttribute("DashSkin"))))
            else
                -- ⚠️ 조용히 넘어가면 "분신이 대시는 하는데 잔상만 없다"가 되고,
                --   그게 오히려 분신을 가려내는 표식이 된다. 반드시 드러낸다.
                warn("[DecoyDash] RunnerDiveFxRemote 없음 — 잔상 생략됨")
            end

            -- ⚠️ 속도를 올렸으면 되돌리는 코드가 반드시 짝으로 있어야 한다.
            --   중간에 분신이 터지면 아래 복원이 실행되지 않으므로 단계마다 생존을 다시 본다.
            --   (분신은 곧 사라지니 남아도 무해하지만, 같은 패턴을 캐릭터에 쓰면 속도가 박제된다)
            cloneHumanoid.WalkSpeed = DASH_BURST_SPEED
            task.wait(DASH_BURST_TIME)
            if not isAlive() or not cloneHumanoid.Parent then return end

            cloneHumanoid.WalkSpeed = DASH_EXHAUST_SPEED
            task.wait(DASH_EXHAUST_TIME)
            if not isAlive() or not cloneHumanoid.Parent then return end

            cloneHumanoid.WalkSpeed = runSpeed
        end
    end)

    -- ── 대각선 기믹: 직진하다 가끔 2~3초간 좌/우 대각선으로 (사람처럼 불규칙) ──
    task.spawn(function()
        while isAlive() do
            -- 똑바로 가는 구간 (2.0~4.5초)
            local straightT = math.random(20, 45) / 10
            local t = 0
            while t < straightT do
                if not isAlive() then return end
                RunService.Heartbeat:Wait()
                t += 1/60
            end
            -- 대각선 구간 (좌/우 랜덤, 2~3초)
            strafeBias = (math.random() < 0.5) and 1 or -1
            local diagT = math.random(20, 30) / 10
            t = 0
            while t < diagT do
                if not isAlive() then strafeBias = 0 return end
                RunService.Heartbeat:Wait()
                t += 1/60
            end
            strafeBias = 0
        end
    end)

    print("🎭 분신 소환:", player.Name, goalPart and ("→ 목표: "..goalPart.Name) or "(직진)")
end

-- ── 러너 투명화 ───────────────────────────────────────
local function setInvisible(char, duration, onRestore)
    local saved = {}
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            table.insert(saved, {obj = d, val = d.Transparency})
            d.Transparency = 1
        elseif d:IsA("Decal") or d:IsA("Texture") then
            table.insert(saved, {obj = d, val = d.Transparency})
            d.Transparency = 1
        end
    end
    task.delay(duration, function()
        for _, e in ipairs(saved) do
            if e.obj and e.obj.Parent then
                e.obj.Transparency = e.val
            end
        end
        if onRestore then onRestore() end  -- 투명화 해제 직후 콜백 (분신 생성 등)
    end)
end

-- ── Tool 회수 ─────────────────────────────────────────
local function removeTool(player)
    for _, loc in ipairs({ player.Character, player:FindFirstChild("Backpack") }) do
        if loc then
            local t = loc:FindFirstChild("Decoy Wand")
            if t then t:Destroy() end
        end
    end
end

-- ── 외부 노출: 태거 아이템 접촉 시 소멸 ─────────────────
_G.popDecoy = function(model)
    if not model then return end
    local fn = cleanupByModel[model]
    if fn then
        fn()
    elseif model.Parent then
        poof(model:GetPivot())
        model:Destroy()
    end
end

-- ── 사용 요청 처리 ─────────────────────────────────────
useEvent.OnServerEvent:Connect(function(player)
    local now = tick()
    if cooldowns[player.UserId] and now - cooldowns[player.UserId] < USE_COOLDOWN then return end
    cooldowns[player.UserId] = now

    if player:GetAttribute("Role") ~= "Runner" then return end

    local char = player.Character
    if not char then return end
    if char:GetAttribute("Downed") then return end
    if char:GetAttribute("IceFrozen") or char:GetAttribute("WaterFrozen")
        or char:GetAttribute("CoffinSequence") or char:GetAttribute("TsunamiHit") then return end

    removeTool(player)
    -- [CONSUMABLE-ONUSE] 실제 발동 확정 지점. 위 쿨다운·Role·Downed·상태이상 가드를
    --   모두 통과한 뒤여야 한다(가드에 걸려 return 되면 쓴 게 아니다).
    if _G.MarkConsumableUsed then _G.MarkConsumableUsed(player, "Decoy Wand") end
    -- 러너를 먼저 투명화하고, 투명화가 풀리는 순간 분신 생성
    -- (그 시점엔 러너가 다시 보이므로 클론 외형도 정상)
    setInvisible(char, INVIS_DURATION, function()
        -- 원본 러너에게도 동시에 연기 (어느 쪽이 분신인지 티 안 나도록, 사운드는 생략)
        local r = char:FindFirstChild("HumanoidRootPart")
        if r then poof(r.CFrame, true) end
        spawnDecoy(player)  -- 분신 위치 연기 + 사운드는 여기서
    end)
end)

-- 플레이어 퇴장 시 분신 정리
Players.PlayerRemoving:Connect(function(player)
    if activeByUser[player.UserId] then
        activeByUser[player.UserId]()
        activeByUser[player.UserId] = nil
    end
    cooldowns[player.UserId] = nil
end)

print("✅ DecoySystem 활성화! (_G.popDecoy 노출, DecoyChar 그룹 설정 완료)")
