-- ═══════════════════════════════════════════════════════════════
-- 🎯 곡사포 (수성 무기) — 조준 없는 단순판
--
-- [왜 이 무기가 있나] 공성 구간에 태거가 할 일이 없었다. 성문이 러너와
--   태거를 갈라놓아 Push·Grab 은 벽에 막히고, 아이템은 계단으로만 투영되어
--   닿지 않는다. 러너가 8대 때리는 동안 태거는 구경만 했다.
--
-- [왜 조준을 없앴나] 저연령층·모바일이 주 사용자다. 마우스로 착탄점을 옮기는
--   조작은 모바일에서 특히 어렵다.
--   → 대포마다 '고정 표적'을 두고, 태거는 어느 대포 앞에 설지만 고른다.
--     조작은 E 를 길게 누르는 것 하나뿐이다.
--   → 대신 여러 대를 일렬로 배치해 위치 선택이 곧 조준이 되게 한다.
--
-- [고정 포대인 이유] 대포 앞으로 가야 쓸 수 있다 = 점령존을 비우는 대가.
--   대포(X 780)에서 점령존(X 808)까지 2.0초.
-- ═══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- ── 튜닝 ───────────────────────────────────────────────────────
local USE_RANGE     = 14      -- 대포에 이만큼 다가가야 조작 가능
local CHARGE_TIME   = 2.0     -- E 홀드 시간
local COOLDOWN       = 6.0    -- 발사 후 재장전
-- ⚠️ [2026-08-24] 16 → 34. 대포 4대로 성벽 전 폭(243)을 덮으려면 이 값이 필요하다.
--    (폭 = 2R + 3×간격, 연속 조건 간격 ≤ 2R → 최소 R = 243/8 = 30.4)
--    러너가 좌우 끝으로 붙어 벽을 때리면 막을 수 없던 문제를 해결한다.
local BLAST_RADIUS  = 34      -- 착탄 피해 반경
-- 🛢️ [2026-08-27] 판정은 '구'가 아니라 '원기둥'이다. (MagicBookSystem 과 동일 규약)
--   [증상] 경고원 안인데 안 맞는다.
--   [원인] 경고원은 평평한 원반인데 판정이 3D 거리였다. map1 은 반경 34 안
--     지면 기복이 151 stud(124~276)라 원의 절반이 죽은 영역이었다.
--     (0° 방향 지면 276 = 중심 138 대비 +138 → 3D 142, 반경의 4배라 절대 미적중)
--   [해결] 수평거리로만 반경을 재고 높이는 밴드로 자른다.
--   ⚠️ 밴드 필수. 대포 타깃 4개가 전부 taggerbase(X 709~860 / Y 10~138) 위에 있어,
--     높이를 안 보면 성 내부까지 관통한다.
--   ⚠️ 반경이 마법책(44)과 다른 건 정상이다 — 대포 4대 / 책 3개로 같은 폭(238)을 덮는다.
--     통일하지 말 것. 같아야 하는 건 '판정 방식' 이지 값이 아니다.
local BLAST_HEIGHT  = 35      -- 착탄점 기준 위아래 유효 높이(stud)
-- ⚠️ 반경이 16→34 로 커지며 면적이 4.5배가 됐다. 같은 데미지를 유지하면
--    '피할 수 없는 광역기'가 된다. 중심 데미지를 낮추고 감쇠를 키운다.
local BLAST_DAMAGE  = 38      -- 중심 데미지
local BLAST_FALLOFF = 0.75    -- 가장자리에서 이 비율만큼 감소 (중심 38 → 끝 9.5)
-- ⏱️ [2026-08-30] 1.1 → 2.2. 실질 회피 창을 두 배로.
--   [왜] 경고원(warnEvent)은 발사 순간에 뜨고 착탄까지 유지된다. 즉 FLIGHT_TIME 이
--     러너가 실제로 반응할 수 있는 유일한 시간이다. 그 앞의 연기·차징 단계는
--     대포를 보고 있어야만 인지되므로 회피 창으로 치면 안 된다.
--   [계산] 반경 34 를 걷기(16 stud/s)로 벗어나려면 중심에서 2.1초가 필요하다.
--     1.1 초로는 중심에 있으면 구조적으로 못 빠져나갔다 — 대시가 없으면 확정타였다.
--     2.2 면 걸어서 딱 벗어날 수 있고, 대시가 있으면 여유가 생긴다.
--   ⚠️ 이 값은 포탄 비행 속도이기도 하다. 늘리면 궤적이 그만큼 느려 보인다.
--     연출이 늘어져 보이면 여기가 아니라 BLAST_RADIUS 를 줄이는 쪽을 먼저 볼 것
--     (필요 회피 시간 = 반경 / 이동속도 이므로 반경이 진짜 손잡이다).
local FLIGHT_TIME   = 2.2     -- 포탄 비행 시간 = 경고원 표시 시간
-- ⏳ [2026-08-29] 봇 전용 예고 시간(초). 연기가 피어오르고 이만큼 뒤에 발사한다.
--   [왜] 유저는 프롬프트를 CHARGE_TIME 동안 홀드하며 연기로 예고가 되지만,
--     봇은 그 단계가 없어 실질 경고가 FLIGHT_TIME 뿐이었다.
--     러너가 반응할 수 없어 "피할 수 없는 광역기"가 됐다.
--   [값] CHARGE_TIME 과 맞추면 유저와 같은 리듬이 된다.
--     총 경고 = BOT_TELEGRAPH + FLIGHT_TIME → 1.4 + 2.2 = 3.6초.
local BOT_TELEGRAPH = 1.4
-- ⚠️ [2026-08-30] 0.45 → 0.9. FLIGHT_TIME 이 두 배가 됐으므로 같이 늘린다.
--   점멸은 "이제 진짜 터진다"는 마지막 신호다. 비율이 어긋나면 경고원이 뜨자마자
--   점멸하거나(너무 이름) 터지기 직전에야 깜빡인다(너무 늦음).
--   ⚠️ FLIGHT_TIME 을 바꾸면 이 값도 같이 볼 것 — 둘은 한 짝이다.
local WARN_BLINK_AT = 0.9     -- 착탄 이 시간 전부터 붉게 점멸

-- 🔊 사운드. ⚠️ AssetTypeId=3(Sound) 이라 변환 없이 그대로 쓴다.
-- ⚠️ 발사음이 착탄음보다 크면 주객전도가 된다. 실제 위협은 착탄이므로
--    발사는 '쐈다'는 신호 정도로만 두고, 착탄을 더 크게 울린다.
local SFX_FIRE     = "rbxassetid://73341075974025"
-- 🔔 [2026-08-29] 착탄 경고음. 베어트랩(TrapSystem.SND_WARNING)·마법책과 공유한다.
--   [왜] 이미 "위험이 온다"는 의미로 학습된 소리다. 기물마다 다른 경고음을 쓰면
--     유저가 각각 배워야 하는데, 경고는 즉시 알아들어야 하는 정보다.
--   ⚠️ 세 시스템이 한 소리를 공유한다(TrapSystem / MagicBookSystem / 여기).
--     바꿀 거면 셋을 같이 볼 것.
local SFX_WARN     = "rbxassetid://16903690359"
local VOL_WARN     = 1.0
local RANGE_WARN   = 200
local SFX_IMPACT   = "rbxassetid://107141645486762"
local VOL_FIRE     = 0.7
local VOL_IMPACT   = 2.2
-- 들리는 거리. 발사는 가까이에서만, 착탄은 멀리서도 들려야 경고가 된다.
local RANGE_FIRE   = 120
local RANGE_IMPACT = 320

local function ensureRemote(name)
    local e = ReplicatedStorage:FindFirstChild(name)
    if not e then
        e = Instance.new("RemoteEvent")
        e.Name = name
        e.Parent = ReplicatedStorage
    end
    return e
end
local inputEvent = ensureRemote("CannonInput")
local stateEvent = ensureRemote("CannonState")
local warnEvent  = ensureRemote("CannonWarn")

local cannons = {}       -- [model] = { cooldownUntil }
-- 🤖 [2026-08-29] 대포별 발사 함수. 봇 킹이 프롬프트 없이 쏘기 위한 통로.
--   ⚠️ 약한 참조로 둔다. 대포는 성문 붕괴 때 Destroy 되므로 강한 참조면 누수가 된다.
local cannonFireFns = setmetatable({}, { __mode = "k" })

local function findCannons()
    local list = {}
    for _, mapFolder in ipairs(workspace:GetChildren()) do
        if mapFolder:IsA("Folder") or mapFolder:IsA("Model") then
            for _, d in ipairs(mapFolder:GetChildren()) do
                if d:IsA("Model") and d.Name == "Cannon" then list[#list + 1] = d end
            end
        end
    end
    return list
end

local function getBarrel(c) return c.PrimaryPart or c:FindFirstChild("Barrel") end

-- ⚠️ 서버에서 Sound.Play() 는 RespectFilteringEnabled 환경에서 클라에 안 닿는다.
--    파트에 붙여 3D 사운드로 재생하면 복제되어 모두에게 들린다.
local function playAt(pos, id, volume, range)
    local p = Instance.new("Part")
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.CanTouch = false
    p.Transparency = 1
    p.Size = Vector3.new(1, 1, 1)
    p.CFrame = CFrame.new(pos)
    p.Parent = workspace
    local s = Instance.new("Sound")
    s.SoundId = id
    s.Volume = volume
    s.RollOffMaxDistance = range
    s.RollOffMode = Enum.RollOffMode.InverseTapered
    s.Parent = p
    s:Play()
    Debris:AddItem(p, 6)
end

-- 🎯 대포의 고정 표적. 조준이 없으므로 배치 시 정해둔 좌표를 쓴다.
local function getTarget(cannon)
    local tx = cannon:GetAttribute("TargetX")
    local tz = cannon:GetAttribute("TargetZ")
    if not tx or not tz then return nil end
    -- 지면 높이를 찾아 착탄점을 바닥에 붙인다
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { cannon }
    local hit = workspace:Raycast(Vector3.new(tx, 400, tz), Vector3.new(0, -500, 0), params)
    local y = hit and hit.Position.Y or (getBarrel(cannon) and getBarrel(cannon).Position.Y or 0)
    return Vector3.new(tx, y, tz)
end

local function setBarrelReady(cannon, ready)
    local b = getBarrel(cannon)
    if not b then return end
    b.Color = ready and Color3.fromRGB(120, 105, 85) or Color3.fromRGB(58, 52, 46)
end

local function setSmoke(cannon, on)
    local sp = cannon:FindFirstChild("SmokePart", true)
    if not sp then return end
    for _, d in ipairs(sp:GetChildren()) do
        if d:IsA("Smoke") or d:IsA("ParticleEmitter") then d.Enabled = on end
    end
end

-- ── 착탄 ───────────────────────────────────────────────────────
local function damageAt(pos)
    -- 🏰 [2026-08-28] 곡사포는 '공성 방어' 무기다 — 태거 베이스 면역을 두지 않는다.
    --   ⚠️ 여기에 isInTaggerBase / _G.IsCharInTaggerBase 를 추가하지 말 것.
    --     "다른 태거 아이템엔 다 있는데 여기만 없다"고 보이지만 의도된 예외다.
    --   [근거] 착탄점이 애초에 베이스 안이다. 실측 2026-08-28:
    --     · 곡사포 TargetX = 726, map1 taggerbase X 범위 709.2~859.8 → 베이스 위
    --     · 착탄 지면이 Workspace.map1.taggerbase (Y 137.8) 로 찍힌다
    --     · 2단계 러너는 성문(X≈731)을 때리므로 역시 베이스 위에 서 있다
    --     → 면역을 걸면 모든 착탄이 무효가 되어 무기가 통째로 죽는다.
    --   [왜 다른 아이템은 면역이 있나] 프드·폭탄·에너지볼·데몬스피어는 '들판에 던지는'
    --     아이템이라, 베이스까지 반경이 닿는 게 사고다. 곡사포·마법책은 반대로
    --     베이스(성문 앞)를 때리는 게 존재 이유다. 규칙이 아니라 역할이 다르다.
    --   ⚠️ MagicBookSystem 에 같은 주석이 있다. 곡사포는 그 무기의 스킨이므로
    --     한쪽만 바꾸면 반드시 갈라진다.
    local function hurt(char)
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end
        if char:GetAttribute("Downed") then return end
        -- 수평거리로 반경 판정 + 높이는 밴드로 컷 (원기둥). 상수 선언부 주석 참조.
        local off = hrp.Position - pos
        local d = Vector2.new(off.X, off.Z).Magnitude
        if d <= BLAST_RADIUS and math.abs(off.Y) <= BLAST_HEIGHT then
            local dmg = BLAST_DAMAGE * (1 - (d / BLAST_RADIUS) * BLAST_FALLOFF)
            hum:TakeDamage(dmg)
            -- 🚧 [진단 2026-08-26] 데미지 출처 추적 (MagicBook 과 같은 규약).
            warn(string.format("[Cannon] 명중 → %s (dmg %.1f / 거리 %.0f)",
                char.Name, dmg, d))
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr:GetAttribute("Role") == "Runner" and plr.Character then hurt(plr.Character) end
    end
    for _, mdl in ipairs(workspace:GetChildren()) do
        if mdl:IsA("Model") and mdl.Name:match("^AIRunner") then hurt(mdl) end
    end
end

local function detonate(pos)
    local fx = Instance.new("Explosion")
    fx.Position = pos
    fx.BlastRadius = BLAST_RADIUS
    fx.BlastPressure = 0                -- ⚠️ 0. 러너가 맵 밖으로 날아가면 안 된다.
    fx.DestroyJointRadiusPercent = 0    -- ⚠️ 캐릭터를 분해하지 않는다.
    fx.ExplosionType = Enum.ExplosionType.NoCraters
    fx.Parent = workspace
    Debris:AddItem(fx, 3)
    playAt(pos, SFX_IMPACT, VOL_IMPACT, RANGE_IMPACT)
    damageAt(pos)
end

local function fireShell(cannon, targetPos)
    local barrel = getBarrel(cannon)
    if not barrel then return end
    local startPos = barrel.Position + Vector3.new(0, 3, 0)

    warnEvent:FireAllClients(targetPos, FLIGHT_TIME, BLAST_RADIUS, WARN_BLINK_AT)
    playAt(startPos, SFX_FIRE, VOL_FIRE, RANGE_FIRE)
    -- 🔔 경고음은 '착탄 지점'에서 낸다. 포구에서 내면 어디로 떨어지는지 귀로 알 수 없다.
    --    ⚠️ 시각 경고 원(warnEvent)과 같은 좌표를 쓴다. 둘이 어긋나면 더 헷갈린다.
    playAt(targetPos, SFX_WARN, VOL_WARN, RANGE_WARN)

    local shell = Instance.new("Part")
    shell.Name = "_CannonShell"
    shell.Shape = Enum.PartType.Ball
    shell.Size = Vector3.new(3, 3, 3)
    shell.Color = Color3.fromRGB(45, 42, 40)
    shell.Material = Enum.Material.Slate
    shell.Anchored = true
    shell.CanCollide = false
    shell.CanQuery = false
    shell.CFrame = CFrame.new(startPos)
    shell.Parent = workspace
    Debris:AddItem(shell, FLIGHT_TIME + 1)

    local trail = Instance.new("Fire")
    trail.Heat = 8 ; trail.Size = 5 ; trail.Parent = shell

    -- ⚠️ 물리 대신 수동 보간. 착탄 시각이 정확해야 경고원과 어긋나지 않는다.
    task.spawn(function()
        local t0 = os.clock()
        while true do
            local a = math.min((os.clock() - t0) / FLIGHT_TIME, 1)
            if not shell.Parent then return end
            local flat = startPos:Lerp(targetPos, a)
            shell.CFrame = CFrame.new(flat + Vector3.new(0, 45 * 4 * a * (1 - a), 0))
            if a >= 1 then break end
            RunService.Heartbeat:Wait()
        end
        shell:Destroy()
        detonate(targetPos)
    end)
end

-- ── 입력 ───────────────────────────────────────────────────────
-- ⚠️ 서버가 최종 방어선. 클라는 "시작/발사"만 보내고 좌표는 서버가 정한다.
--    조준이 없으니 클라가 보낼 좌표 자체가 없다 — 우회 여지가 원천 차단된다.
-- ⚠️ [2026-08-24] 옛 커스텀 입력 핸들러(inputEvent.OnServerEvent)를 제거했다.
--    ProximityPrompt 의 PromptButtonHoldBegan / Triggered 가 그 역할을 대신한다.
--    로블록스 기본 UI 라 학습이 필요 없고, 모바일 버튼도 엔진이 만들어준다.

-- ⚠️ 이탈 정리는 ProximityPrompt 가 자동으로 처리한다(거리를 벗어나면 홀드가 끊긴다).
--    다만 연기가 남을 수 있어 안전망으로 전 대포를 정리한다.
Players.PlayerRemoving:Connect(function()
    for _, c in ipairs(findCannons()) do
        setSmoke(c, false)
        c:SetAttribute("CannonCharging", nil)
    end
end)

-- ═══════════════════════════════════════════════════════════════
-- ═══════════════════════════════════════════════════════════════
-- 🎯 대포 백업 / 파괴 / 복원
--
-- ⚠️ [왜 성문과 함께 부서지나] 사거리가 성문 앞(54 stud)에 고정이라,
--    성문이 뚫려 러너가 안으로 들어오면 이미 지나간 자리를 쏘게 되어
--    무의미해진다. 서사적으로도 '성문이 무너지며 포대도 무너진다'가 자연스럽다.
--
-- ⚠️ [왜 BarricadeGate 목록에 안 넣나] BarricadeSystem 의 backupGates 는
--    이름당 1개만 백업한다. 대포는 4대 모두 이름이 'Cannon' 이라 1대만
--    백업되어 다음 라운드에 3대가 사라진다. → 자체 관리한다.
-- ═══════════════════════════════════════════════════════════════
local ServerStorage = game:GetService("ServerStorage")
local cannonBackups = {}

-- 🚪 [2026-08-28] '이번 라운드에 성문이 이미 무너졌는가'.
--   [증상] 성문을 부순 뒤 2단계에 진입하면 파괴됐던 대포 4대가 되살아났다.
--     (실측 18:02:38.359 파괴 → 18:02:42.095 복원)
--   [원인] restoreCannons 는 '지난 라운드에 파괴된 것을 되살린다'는 의도인데,
--     '이번 라운드에 방금 무너진 것'과 구분할 방법이 없었다. 평소엔
--     2단계 진입이 성문 붕괴보다 먼저라 문제가 안 드러났을 뿐이다.
--   [해결] 붕괴 여부를 상태로 남기고, 복원은 그 상태를 본다.
--   ⚠️ 라운드 시작(setCurrentMap/백업)에서 반드시 false 로 되돌릴 것.
--     안 되돌리면 다음 라운드에 대포가 영영 안 생긴다 — 켜는 코드와 끄는 코드는 한 짝이다.
local gateCollapsed = false

-- ⚠️ attachPrompt 는 아래(375행 부근)에 정의된다. restoreCannons 가 그보다
--    먼저 선언되므로 전방 선언이 필요하다. 없으면 런타임에 nil 참조로 터진다.
local attachPrompt

local function backupCannons()
    local folder = ServerStorage:FindFirstChild("_CannonBackups")
    if folder then folder:Destroy() end
    folder = Instance.new("Folder")
    folder.Name = "_CannonBackups"
    folder.Parent = ServerStorage

    cannonBackups = {}
    for _, c in ipairs(findCannons()) do
        local clone = c:Clone()
        clone.Parent = folder
        table.insert(cannonBackups, {
            clone = clone, parent = c.Parent, cframe = c:GetPivot(),
            targetX = c:GetAttribute("TargetX"),
            targetZ = c:GetAttribute("TargetZ"),
        })
    end
    print(string.format("🎯 [Cannon] 백업 %d대", #cannonBackups))
    -- 🚪 초기값 세팅일 뿐이다. 이 함수는 부팅 시 1회만 호출된다(호출부 1곳).
    --   ⚠️ [2026-09-01 정정] 옛 주석은 "백업은 맵이 준비될 때마다 도는 지점이라
    --     라운드 경계와 일치한다" 고 적혀 있었으나 사실이 아니었다. 그 탓에 성문이
    --     한 번 무너지면 대포가 영영 복원되지 않았다(8라운드 실측으로 확인).
    --     실제 라운드 경계 해제는 RoundPhase 감시 루프의 else 분기에 있다.
    --     해제 지점을 여기로 되돌리거나 늘리지 말 것 — 한 곳으로 유지한다.
    gateCollapsed = false
end

local function restoreCannons()
    -- ⚠️ 백업이 아직 안 됐으면 아무것도 하지 않는다.
    --    RoundPhase 감시 루프(task.spawn)가 부팅 백업(task.defer)보다
    --    먼저 돌 수 있어, 빈 목록으로 복원을 시도하면 조용히 실패한다.
    if #cannonBackups == 0 then return 0 end
    -- 🚪 이번 라운드에 성문이 이미 무너졌으면 되살리지 않는다.
    --   ⚠️ 이 검사가 없으면 "성문 부수고 2단계 진입" 순서에서 대포가 부활한다.
    if gateCollapsed then return 0 end
    local n = 0
    for _, e in ipairs(cannonBackups) do
        -- ⚠️ 좌표로 중복을 판단한다. 이름이 모두 'Cannon' 이라 이름으로는 구분이 안 된다.
        local found = false
        for _, c in ipairs(findCannons()) do
            if (c:GetPivot().Position - e.cframe.Position).Magnitude < 2 then
                found = true
                break
            end
        end
        if not found then
            local c = e.clone:Clone()
            c.Parent = (e.parent and e.parent.Parent) and e.parent or workspace
            c:PivotTo(e.cframe)
            if e.targetX then c:SetAttribute("TargetX", e.targetX) end
            if e.targetZ then c:SetAttribute("TargetZ", e.targetZ) end
            attachPrompt(c)
            setBarrelReady(c, true)
            setSmoke(c, false)
            n = n + 1
        end
    end
    if n > 0 then print(string.format("🎯 [Cannon] 복원 %d대", n)) end
    return n
end

-- 성문 파괴 시 BarricadeSystem 이 호출한다.
-- ⚠️ 폭발 연출은 착탄과 같은 것을 재사용한다. 새 연출을 만들면 톤이 어긋난다.
-- ⚠️ 데미지는 주지 않는다. 태거가 자기 포대 폭발에 죽으면 이상하다.
local function destroyCannons()
    -- 🚪 성문 붕괴 상태를 남긴다. 대포를 못 찾아 아래에서 return 하더라도
    --    '무너졌다'는 사실은 기록해야 한다 — 그래야 뒤늦은 복원을 막는다.
    gateCollapsed = true
    local list = findCannons()
    if #list == 0 then return end
    for _, c in ipairs(list) do
        local b = getBarrel(c)
        local pos = b and b.Position or c:GetPivot().Position
        local fx = Instance.new("Explosion")
        fx.Position = pos
        fx.BlastRadius = 18
        fx.BlastPressure = 0
        fx.DestroyJointRadiusPercent = 0
        fx.ExplosionType = Enum.ExplosionType.NoCraters
        fx.Parent = workspace
        Debris:AddItem(fx, 3)
        playAt(pos, SFX_IMPACT, VOL_IMPACT * 0.7, RANGE_IMPACT)
        c:Destroy()
    end
    print(string.format("🎯 [Cannon] 성문 붕괴와 함께 %d대 파괴", #list))

    -- ⚠️ [버그 수정 2026-08-26] 조준 원 정리.
    --   [증상] 조준 중에 성문이 무너지면 바닥 조준 원이 화면에 영영 남았다.
    --   [원인] 대포 모델만 Destroy 하고 클라에 "조준 해제" 를 안 알렸다.
    --     CannonClient 는 서버 신호로만 원을 그리고 지운다(자체 판단 없음).
    --   ⚠️ "상태를 켜는 코드와 끄는 코드는 같은 편집에" — 파괴 경로가 늘면
    --     여기도 함께 볼 것.
    stateEvent:FireAllClients("cancel")
end

_G.CannonOnGateDestroyed = destroyCannons

-- 🎯 곡사포 표시 제어 (2단계 전용)
--
-- ⚠️ [2026-08-24] 곡사포는 2단계 전용 무기다. 사거리가 성문 앞(54 stud)에
--    고정되어 있어, 1단계에는 그 범위에 러너가 아무도 없다.
--    그런데 대포가 보이면 태거는 1단계부터 쏘려 하고, 코앞만 폭격되니
--    "왜 여기에 떨어지지?" 하는 혼란이 생긴다.
--    → 점령존과 같은 방식으로 2단계에만 드러낸다.
-- ⚠️ 보이기만 막으면 안 된다. 프롬프트도 함께 꺼야 투명한 대포를
--    더듬어 쏘는 일이 없다.
-- ═══════════════════════════════════════════════════════════════
-- ⚠️ [2026-08-24] 완전 투명(1) → 반투명(0.7).
--    완전히 사라지면 태거가 대포의 존재조차 모르고, 2단계에 갑자기
--    나타나면 '이게 뭐지' 가 된다. 흐릿하게 보이면 "저기 있는데 아직
--    못 쓴다" 가 전달되고, 2단계 진입이 '이제 쓸 수 있다' 로 이어진다.
--    사용 차단은 프롬프트를 끄는 것으로 충분하다.
local DIM_TRANSPARENCY = 0.7

local function setCannonVisible(cannon, on)
    for _, d in ipairs(cannon:GetDescendants()) do
        if d:IsA("BasePart") then
            -- SmokePart 는 원래 투명하므로 건드리지 않는다
            if d.Name ~= "SmokePart" then
                if on then
                    local orig = d:GetAttribute("_CannonOrigTransparency")
                    d.Transparency = orig or 0
                else
                    if d:GetAttribute("_CannonOrigTransparency") == nil then
                        d:SetAttribute("_CannonOrigTransparency", d.Transparency)
                    end
                    d.Transparency = DIM_TRANSPARENCY
                end
            end
            -- ⚠️ 반투명이라 눈에 보인다. 충돌을 끄면 '보이는데 통과되는' 이상한
            --    상태가 되므로 1단계에도 유지한다.
            d.CanCollide = (d.Name ~= "SmokePart")
        end
    end
    local barrel = getBarrel(cannon)
    local p = barrel and barrel:FindFirstChild("CannonPrompt")
    if p then p.Enabled = on end
    -- 게이지도 함께 (BillboardGui 는 파트 투명도와 무관하게 보인다)
    local g = barrel and barrel:FindFirstChild("CannonGauge")
    if g then g.Enabled = on end
end

local function setAllCannonsVisible(on)
    for _, c in ipairs(findCannons()) do
        setCannonVisible(c, on)
    end
end

-- 2단계 진입 시 나타난다.
-- ⚠️ RoundPhase 속성을 쓴다. 이벤트만 믿으면 늦게 접속한 클라나
--    재시작된 스크립트가 상태를 놓친다(기존 규약).
task.spawn(function()
    local last = nil
    while true do
        task.wait(0.4)
        local ph = ReplicatedStorage:GetAttribute("RoundPhase")
        if ph ~= last then
            last = ph
            if ph == "stage2" then
                restoreCannons()   -- ⚠️ 복원을 먼저. 지난 라운드에 파괴됐다면 되살린다.
                setAllCannonsVisible(true)
                print("🎯 [Cannon] 2단계 — 곡사포 사용 가능")
            else
                -- 🚪 [버그수정 2026-09-01] 라운드 경계에서 성문 붕괴 상태를 푼다.
                --   [증상] 성문이 한 번 무너진 뒤로 세션이 끝날 때까지 대포가 0대였다.
                --     실측 21:45~22:07 8라운드 — 3라운드 '4대 파괴' 후, 4라운드부터
                --     봇 로그가 계속 "곡사포 0 / 마법책 1". 복원 로그는 한 번도 안 찍혔다.
                --   [원인] gateCollapsed=false 해제가 backupCannons() 안에만 있었는데
                --     그 함수는 부팅 시 1회만 호출된다(호출부 전수 검색 결과 1곳).
                --     "백업은 맵이 준비될 때마다 돈다"는 옛 주석의 가정이 사실이 아니었다.
                --   [왜 여기인가] restoreCannons 는 stage2 진입에서만 돈다. 따라서
                --     'stage2 가 아닌 단계로 바뀌는 시점'에 풀면 다음 복원보다 항상 앞서고,
                --     같은 라운드 안에서 붕괴 뒤에 다시 풀릴 일도 없다(붕괴 시점엔 이미 stage2).
                --   ⚠️ destroyCannons 의 gateCollapsed=true 와 한 짝이다.
                --     파괴 경로가 늘어도 해제 지점은 여기 하나로 유지할 것.
                gateCollapsed = false
                setAllCannonsVisible(false)
            end
        end
    end
end)

-- ── ProximityPrompt 설치 ───────────────────────────────────────
-- ⚠️ [2026-08-24] 커스텀 E 홀드 방식에서 전환.
--    · 로블록스 기본 UI 라 학습이 필요 없다 (픽업 상자와 같은 조작)
--    · HoldDuration 이 차징을 대신하고, 진행 게이지를 엔진이 그려준다
--    · 모바일에서 터치 버튼이 자동 생성된다 — 별도 버튼 UI 가 불필요
-- ⚠️ Exclusivity=OnePerButton 으로 여러 대포의 프롬프트가 겹치지 않게 한다.
-- ⚠️ 상단에 전방 선언되어 있다. local 을 다시 쓰면 새 변수가 되어
--    restoreCannons 가 보는 것은 여전히 nil 이 된다.
function attachPrompt(cannon)
    local barrel = getBarrel(cannon)
    if not barrel then return end
    local old = barrel:FindFirstChildOfClass("ProximityPrompt")
    if old then old:Destroy() end

    local p = Instance.new("ProximityPrompt")
    p.Name = "CannonPrompt"
    p.ActionText = "발사"
    p.ObjectText = "곡사포"
    p.KeyboardKeyCode = Enum.KeyCode.E
    p.HoldDuration = CHARGE_TIME
    p.MaxActivationDistance = USE_RANGE
    p.RequiresLineOfSight = false
    p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
    p.Parent = barrel

    -- 홀드 시작: 연기 + 표적 미리보기
    p.PromptButtonHoldBegan:Connect(function(player)
        if player:GetAttribute("Role") ~= "Tagger" then return end
        setSmoke(cannon, true)
        cannon:SetAttribute("CannonCharging", true)
        stateEvent:FireClient(player, "charging", CHARGE_TIME, getTarget(cannon))
    end)

    p.PromptButtonHoldEnded:Connect(function(player)
        -- ⚠️ 중도 포기와 발사 완료 모두 이 신호가 온다.
        --    Triggered 가 별도로 오므로 여기서는 연출만 정리한다.
        setSmoke(cannon, false)
        cannon:SetAttribute("CannonCharging", nil)
        stateEvent:FireClient(player, "cancel")
    end)

    -- 발사 본체. 프롬프트(유저)와 봇이 함께 쓴다.
    -- 🤖 [2026-08-29] player 인자를 옵셔널로 뺐다.
    --   봇 킹은 Player 인스턴스가 아니라 Lua 테이블(pseudoPlayer)이라
    --   ProximityPrompt.Triggered 경로를 탈 수 없다. 그래서 본체를 분리한다.
    --   ⚠️ stateEvent:FireClient 는 player 가 진짜 Player 일 때만 부른다.
    --     테이블을 넘기면 "Player expected" 로 터진다(pseudoPlayer 규칙).
    --
    -- ⏳ botTelegraph=true 면 발사 전에 '차징 단계'를 거친다.
    --   [왜] 유저는 프롬프트를 CHARGE_TIME 동안 홀드하고, 그동안 연기가 피어올라
    --     러너에게 "저 대포가 곧 쏜다"는 예고가 된다. 봇은 그 과정을 건너뛰어
    --     실제 경고가 FLIGHT_TIME(1.1초)뿐이었다 — 사실상 회피 불가였다.
    --   [해결] 봇도 같은 연출을 거친다. 연기가 먼저 피어오르고 그 뒤에 쏜다.
    --   ⚠️ 쿨다운은 '차징 시작' 시점에 건다. 안 그러면 차징 중에 또 호출돼
    --     같은 대포가 두 번 예약된다.
    local function doFire(player, botTelegraph)
        local st = cannons[cannon]
        if st and os.clock() < (st.cooldownUntil or 0) then
            if player and typeof(player) == "Instance" and player:IsA("Player") then
                stateEvent:FireClient(player, "cooldown", st.cooldownUntil - os.clock())
            end
            return false
        end

        local target = getTarget(cannon)
        if not target then return false end

        cannons[cannon] = cannons[cannon] or {}
        cannons[cannon].cooldownUntil = os.clock() + COOLDOWN + (botTelegraph and BOT_TELEGRAPH or 0)
        setBarrelReady(cannon, false)
        cannon:SetAttribute("CannonReadyAt", os.time() + COOLDOWN)
        -- ⚠️ 쿨다운 중에는 프롬프트를 숨긴다. 눌러도 안 되는 버튼이 보이면
        --    "고장났나?" 가 된다.
        p.Enabled = false

        setSmoke(cannon, true)

        local function shoot()
            if not cannon.Parent then return end
            task.delay(0.6, function() setSmoke(cannon, false) end)
            -- ⚠️ 표적을 다시 읽는다. 차징 동안 러너가 움직였을 수 있고,
            --    '연기를 보고 피한' 러너가 실제로 살아남아야 예고가 의미를 갖는다.
            fireShell(cannon, getTarget(cannon) or target)
            task.delay(COOLDOWN, function()
                if cannon and cannon.Parent then
                    setBarrelReady(cannon, true)
                    cannon:SetAttribute("CannonReadyAt", nil)
                    p.Enabled = true
                end
            end)
        end

        if botTelegraph then
            task.delay(BOT_TELEGRAPH, shoot)
        else
            task.delay(0.6, function() setSmoke(cannon, false) end)
            shoot()
        end
        return true
    end
    cannon:SetAttribute("_HasFireFn", true)
    cannonFireFns[cannon] = doFire

    -- 홀드 완료 = 발사
    p.Triggered:Connect(function(player)
        if player:GetAttribute("Role") ~= "Tagger" then return end
        local char = player.Character
        if not char or char:GetAttribute("Downed") then return end
        doFire(player)
    end)
end

task.defer(function()
    local list = findCannons()
    for _, c in ipairs(list) do
        setBarrelReady(c, true)
        setSmoke(c, false)
        c:SetAttribute("CannonReadyAt", nil)
        c:SetAttribute("CannonCharging", nil)
        attachPrompt(c)
    end
    -- ⚠️ 기본은 숨김. 2단계 감시 루프가 켜준다.
    backupCannons()   -- 🎯 원본 백업 (성문과 함께 파괴되므로 복원 자료 필요)
    setAllCannonsVisible(false)
    print(string.format("🎯 CannonSystem 준비 (대포 %d대, 고정 표적 방식)", #list))
end)

_G.CannonConfig = { USE_RANGE = USE_RANGE, CHARGE_TIME = CHARGE_TIME, COOLDOWN = COOLDOWN }

-- 🤖 [2026-08-29] 봇 킹용 발사 진입점.
--   [왜] 2단계에서 봇 킹은 슬랩만 쓴다. 실제 태거는 곡사포·마법책까지 쓰므로
--     봇 상대 측정이 실전보다 후하게 나온다. 봇에게 같은 도구를 준다.
--   ⚠️ 봇은 Player 인스턴스가 아니라 pseudoPlayer 테이블이라
--     ProximityPrompt.Triggered 를 못 탄다. 그래서 doFire 를 직접 부른다.
--
-- 🎯 [2026-08-29 수정] '한 번에 한 대만' 쏜다.
--   [증상] 쿨이 풀린 대포를 전부 돌며 쏴서 한 번에 3~4발이 동시 착탄했다.
--     경고를 봐도 피할 곳이 없어 회피 불가능한 공격이 됐다.
--   [원인] 유저는 프롬프트를 하나씩 눌러 순차 발사인데, 봇만 루프로 전탄 발사였다.
--     같은 도구를 준다면서 사용 방식이 달랐던 것.
--   [해결] 준비된 대포 중 무작위로 하나만 고른다. 여러 대를 쓰려면
--     봇 AI 가 FIXTURE_INTERVAL 간격으로 여러 번 부르면 되고, 그게 유저와 같은 리듬이다.
--   ⚠️ 무작위인 이유: 항상 첫 번째 대포만 쓰면 표적이 한 곳으로 고정돼
--     러너가 그 지점만 피하면 된다. 어느 대포가 쏠지 모르게 한다.
--   [반환] 실제로 쏜 대포 수(0 또는 1).
_G.FireCannonForBot = function()
    local ready = {}
    for _, c in ipairs(findCannons()) do
        local fn = cannonFireFns[c]
        -- ⚠️ 숨겨진(1단계) 대포는 쏘지 않는다. setAllCannonsVisible 이 관리한다.
        if fn and c.Parent and c:GetAttribute("CannonReadyAt") == nil then
            ready[#ready + 1] = fn
        end
    end
    if #ready == 0 then return 0 end
    local pick = ready[math.random(1, #ready)]
    return pick(nil, true) and 1 or 0   -- ⏳ botTelegraph=true (예고 후 발사)
end
