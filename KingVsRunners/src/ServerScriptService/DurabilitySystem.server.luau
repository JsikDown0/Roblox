-- ═══════════════════════════════════════════════════════════════
-- DurabilitySystem — 러너 기본 내구도
--
-- [무엇] 다운될 상황에서 다운되는 대신 내구도를 1칸 깎는다. 0이면 그때 다운된다.
--
-- ⚠️ [실측 근거 2026-08-23] 태거 아이템은 HP 를 깎지 않는다. 명중하면 곧바로
--    DownSystem.triggerDown 을 부른다. 즉 아이템 1방 = 즉시 다운이었다.
--    (ItemDamageSystem 의 DAMAGE=50 은 UsedRevive 상태의 '처형' 경로 전용)
--    → 내구도 1칸 = 태거가 러너 1명당 2방을 맞춰야 함 = 태거 부담 +100%.
--
-- ⚠️ [칸 수를 늘릴 때 반드시 볼 것]
--    ❌ [폐기 2026-09-01] 아래 옛 근거는 전제가 뒤집혀 더 이상 성립하지 않는다.
--       옛 근거: "태거의 유일한 승리 조건은 러너 전멸이고 시간 초과(180초)는 러너 승리다.
--                칸이 늘면 전멸 소요가 선형으로 늘어(0칸 36초/1칸 72초/2칸 108초),
--                2칸부터는 180초 안에 전멸이 어려워 태거가 이길 수 없는 구조가 된다."
--       무엇이 바뀌었나: 2026-08-25 에 시간 초과가 '태거 승리'로 뒤집혔다
--                (RoundSystem 의 TIME UP 처리). 이제 태거는 전멸을 못 시켜도 버티면 이긴다.
--       따라서 "2칸이면 태거가 못 이긴다"는 결론은 무효다. 실측으로도 timeout 승리가 나왔다.
--    ⚠️ 그렇다고 칸을 늘려도 된다는 뜻은 아니다. 판단 축이 '태거 승패'에서
--       '1단계 처치 수'로 옮겨갔을 뿐이다. 칸이 늘면 1단계 처치가 그만큼 줄고,
--       RoundSummary 의 목표(총원의 절반)에서 더 멀어진다.
--       실제로 이 세션의 개선은 전부 처치 수를 '올리는' 방향이었다.
--    ⚠️ 이 주석을 밸런스 근거로 인용하지 말 것. 칸 수를 만지려면 그때의
--       1단계 처치 실측치를 새로 확보한 뒤 판단해야 한다.
--    현재 기본값이 1칸인 것은 유지한다 — 바꿀 근거가 아직 없다.
--
-- [확장 지점] 이 시스템은 뼈대다. 위에 얹을 수 있는 것:
--    · 아머(상품): grant(char, n) 로 추가 칸 지급 → 기본 1 + 아머 N
--    · 2단계 보충: Stage2TriggerSystem 에서 grant(char, 1)
--    둘 다 지급 경로만 추가하면 되고, 흡수·게이지 로직은 그대로 재사용된다.
-- ═══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")

-- 🔊 내구도 소모음 브로드캐스트 채널.
-- ⚠️ Tool 내부가 아니라 ReplicatedStorage 에 둔다. Tool 안의 RemoteEvent 로
--    서버→클라 발화를 하면 샌드박스 경계에 막힌다(2026-08-23 Ice Bow 에서 실측).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local durSfxRemote = ReplicatedStorage:FindFirstChild("DurabilityHitSfx")
if not durSfxRemote then
    durSfxRemote = Instance.new("RemoteEvent")
    durSfxRemote.Name = "DurabilityHitSfx"
    durSfxRemote.Parent = ReplicatedStorage
end

local DurabilitySystem = {}

local DUR_ATTR    = "Durability"       -- 현재 칸
local MAX_ATTR    = "DurabilityMax"    -- 최대 칸 (게이지 칸 개수)
local IFRAME_ATTR = "DurabilityIFrame"

local BASE_DURABILITY = 1     -- 러너 기본 지급량

-- ⚠️ 흡수 직후 짧은 무적이 반드시 필요하다. 없으면 굴러오는 통나무 하나가
--    프레임마다 판정에 걸려 내구도가 순식간에 전부 사라진다.
local IFRAME_TIME = 1.5

local BAR_W, BAR_H = 92, 14
local ICON_W = 18   -- 방패 아이콘 폭. 게이지 왼쪽 바깥에 붙는다.

-- 👁️ [2026-09-14] 2단계에서는 게이지를 '변할 때만' 보여준다.
--   [왜] 축 규칙의 마지막 항목이 "상시 여부 = 지금 중요한가" 인데, 2단계에서 내구도는
--     대부분 무의미하다. RoundSystem:844 주석이 실측으로 그렇게 적어뒀다
--     ("내구도는 1단계에서만 유효하다(2단계 소모 로그 0건)").
--     그런데 상시로 떠 있어 "항상 중요하다"고 말하고 있었다 — 표시가 거짓말을 한 상태다.
--   [그런데 왜 아주 끄지 않나] 드물게 결정적이다. 2단계에도 계단 아래로 밀친 뒤
--     아이템으로 다운시키는 경우가 있고, 그때는 몇 칸 남았는지가 판단을 가른다.
--     그래서 '끈다/켠다'가 아니라 **변할 때만 잠깐**으로 축을 옮긴다.
--   ⚠️ 1단계는 손대지 않는다. 그 국면에서는 내구도가 늘 중요하므로 상시가 맞다.
--   ⚠️ 서버가 만드는 GUI 라 러너 본인에게도 같이 숨겨진다. 흡수 시에는 다시 뜨고,
--     DurabilityHitClient 의 흡수 팝업·효과음은 그대로라 "막혔다"는 여전히 전달된다.
local REVEAL_TIME = 2.5     -- 변화 후 노출 지속(초). 흡수 팝업(0.9)보다 길게 — 칸을 셀 시간.
local revealUntil = setmetatable({}, { __mode = "k" })   -- [character] = os.clock() 만료시각
local COL_FILL  = Color3.fromRGB(255, 210, 60)   -- 노랑 (바리케이드 게이지와 같은 계열)
local COL_EMPTY = Color3.fromRGB(60, 55, 40)
local COL_BACK  = Color3.fromRGB(25, 25, 25)

-- ── 머리 위 칸 분할 게이지 ─────────────────────────────────────
-- ⚠️ 비율 바가 아니라 '칸'으로 그린다. 내구도는 연속값이 아니라 횟수라
--    몇 대 더 버티는지가 한눈에 보여야 한다(바리케이드 게이지와 같은 이유).
-- ⚠️ 기존 이름표(RunnerProfile)나 아머 HUD 와 겹치지 않게 높이를 띄운다.
local function updateGauge(character)
    if not character then return end
    local head = character:FindFirstChild("Head")
    if not head then return end

    local cur = character:GetAttribute(DUR_ATTR) or 0
    local max = character:GetAttribute(MAX_ATTR) or 0

    local gui = head:FindFirstChild("DurabilityGauge")
    if max <= 0 then
        if gui then gui:Destroy() end
        return
    end

    if not gui then
        gui = Instance.new("BillboardGui")
        gui.Name = "DurabilityGauge"
        -- ⚠️ 방패 아이콘 자리만큼 가로를 넓힌다(BAR_W + ICON_W).
        gui.Size = UDim2.new(0, BAR_W + ICON_W, 0, BAR_H)
        -- ⚠️ [2026-08-26] 3.9 → 4.9. HP 바와 겹쳐 읽기 어려웠다.
        --   실측 간격: 봇 HP 바 Y_OFFSET 3.2 (높이 8px) vs 내구도 3.9 (높이 14px).
        --   0.7 stud 차이인데 내구도 쪽이 더 두꺼워, 가까이서 보면 두 바가 물렸다.
        --   (BillboardGui 는 픽셀 크기가 거리에 따라 stud 로 환산되므로
        --    "높이가 큰 쪽"이 실제로 더 넓은 세로 공간을 먹는다)
        -- ⚠️ HP 바가 기준선이고 내구도는 부가 정보다. 내구도를 위로 올린다.
        -- ⚠️ 값을 바꿀 때는 BotHealthBarSystem.Y_OFFSET(3.2)·TaggerHpDisplay(3.5)를
        --    함께 볼 것. 세 게이지가 같은 머리 위 공간을 나눠 쓴다.
        gui.StudsOffset = Vector3.new(0, 4.9, 0)
        gui.AlwaysOnTop = true
        gui.MaxDistance = 160
        gui.ResetOnSpawn = false
        gui.Parent = head

        -- 🛡️ 방패 아이콘.
        -- ⚠️ [실측 2026-08-23] 칸 게이지만 있으니 "이게 HP바인가?" 하는 혼동이 있었다.
        --    이 게임엔 태거 HP바가 이미 머리 위에 뜨므로 형태가 비슷하면 헷갈린다.
        --    → 앞에 방패를 달아 "체력이 아니라 방어 횟수"임을 형태로 구분한다.
        -- ⚠️ 게이지 '바깥' 왼쪽에 둔다. Back 안에 넣으면 UIListLayout 이
        --    칸으로 취급해 배치가 틀어진다.
        local icon = Instance.new("TextLabel")
        icon.Name = "ShieldIcon"
        icon.Size = UDim2.new(0, ICON_W, 1, 0)
        icon.Position = UDim2.new(0, 0, 0, 0)
        icon.BackgroundTransparency = 1
        icon.Font = Enum.Font.GothamBold
        icon.TextScaled = true
        icon.Text = "🛡"
        icon.TextColor3 = COL_FILL
        icon.TextStrokeTransparency = 0.4
        icon.Parent = gui

        local back = Instance.new("Frame")
        back.Name = "Back"
        -- 아이콘 오른쪽부터 나머지 폭을 차지한다
        back.Size = UDim2.new(1, -ICON_W, 1, 0)
        back.Position = UDim2.new(0, ICON_W, 0, 0)
        back.BackgroundColor3 = COL_BACK
        back.BorderSizePixel = 0
        back.Parent = gui
        Instance.new("UICorner", back).CornerRadius = UDim.new(0.35, 0)

        local list = Instance.new("UIListLayout")
    -- ⚠️ SortOrder 기본값은 Name. LayoutOrder 를 쓰려면 명시해야 한다.
    --    (Cell1, Cell10, Cell2... 처럼 두 자리부터 순서가 뒤섞인다)
    list.SortOrder = Enum.SortOrder.LayoutOrder
        list.FillDirection = Enum.FillDirection.Horizontal
        list.Padding = UDim.new(0, 2)
        list.HorizontalAlignment = Enum.HorizontalAlignment.Center
        list.VerticalAlignment = Enum.VerticalAlignment.Center
        list.Parent = back

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 2); pad.PaddingRight = UDim.new(0, 2)
        pad.PaddingTop = UDim.new(0, 2);  pad.PaddingBottom = UDim.new(0, 2)
        pad.Parent = back
    end

    local back = gui:FindFirstChild("Back")
    if not back then return end

    -- 칸 개수가 바뀌었으면(아머 등으로 max 변동) 다시 만든다.
    local existing = 0
    for _, c in ipairs(back:GetChildren()) do
        if c:IsA("Frame") then existing = existing + 1 end
    end
    if existing ~= max then
        for _, c in ipairs(back:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        for i = 1, max do
            local cell = Instance.new("Frame")
            cell.Name = "Cell" .. i
            cell.Size = UDim2.new(1 / max, -2, 1, 0)
            cell.BorderSizePixel = 0
            cell.LayoutOrder = i
            cell.Parent = back
            Instance.new("UICorner", cell).CornerRadius = UDim.new(0.3, 0)
        end
    end

    for i = 1, max do
        local cell = back:FindFirstChild("Cell" .. i)
        if cell then
            cell.BackgroundColor3 = (i <= cur) and COL_FILL or COL_EMPTY
        end
    end

    -- 👁️ 노출 갱신. updateGauge 는 흡수·리셋·재계산이 모두 지나는 단일 진입점이라
    --   "값이 변했다"를 잡기에 여기가 맞다.
    --   ⚠️ 1단계에서는 항상 보인다. 2단계에서만 REVEAL_TIME 동안 보였다 사라진다.
    --   ⚠️ 실제로 숨기는 건 아래 상주 스윕이다. 여기서 task.delay 로 끄면 호출자
    --     (ItemDamageSystem 등) 혈통에 묶여, 그쪽이 죽을 때 켜진 채로 남는다.
    revealUntil[character] = os.clock() + REVEAL_TIME
    gui.Enabled = true
end

-- ── 지급 ───────────────────────────────────────────────────────
-- n 칸을 '추가'한다. 아머·2단계 보충도 이 함수를 쓰면 된다.
function DurabilitySystem.grant(character, n)
    if not character then return end
    n = tonumber(n) or 1
    if n <= 0 then return end
    local cur = character:GetAttribute(DUR_ATTR) or 0
    local max = character:GetAttribute(MAX_ATTR) or 0
    character:SetAttribute(DUR_ATTR, cur + n)
    character:SetAttribute(MAX_ATTR, max + n)
    updateGauge(character)
end

-- 라운드 시작 시 기본값으로 초기화한다(누적 방지).
function DurabilitySystem.reset(character, amount)
    if not character then return end
    local n = tonumber(amount) or BASE_DURABILITY
    character:SetAttribute(DUR_ATTR, n)
    character:SetAttribute(MAX_ATTR, n)
    character:SetAttribute(IFRAME_ATTR, nil)
    updateGauge(character)
end

function DurabilitySystem.clear(character)
    if not character then return end
    character:SetAttribute(DUR_ATTR, nil)
    character:SetAttribute(MAX_ATTR, nil)
    character:SetAttribute(IFRAME_ATTR, nil)
    local head = character:FindFirstChild("Head")
    local gui = head and head:FindFirstChild("DurabilityGauge")
    if gui then gui:Destroy() end
end

function DurabilitySystem.get(character)
    if not character then return 0 end
    return character:GetAttribute(DUR_ATTR) or 0
end

-- ── 무적 중 콜리전 해제 ────────────────────────────────────────
-- ⚠️ [실패 기록 2026-08-23] 내구도는 '데미지'만 막고 '물리'는 못 막는다.
--    그래서 통나무가 러너를 계속 밀고 가다가 무적이 풀리는 순간 다시 판정에 걸렸다.
--      실측: 흡수 30.087 → 다운 31.655 (= 무적 1.5초 직후, 같은 Wood Log)
--    무적 시간을 늘려도 통나무가 더 오래 밀면 같은 일이 반복되므로 근본 해결이 아니다.
--    → 다운 시스템이 쓰는 것과 같은 방식으로, 무적 동안 태거 아이템을 '통과'시킨다.
--      DownedRunner 그룹은 이미 TaggerItems 와 비충돌로 등록되어 있다(DownSystem).
local PhysicsService = game:GetService("PhysicsService")
local IFRAME_GROUP = "DownedRunner"

-- ⚠️ 이 그룹은 DownSystem 이 '첫 다운 때' 만든다(ensureDownedGroup).
--    내구도 흡수가 그보다 먼저 일어나면 그룹이 없어 CollisionGroup 대입이 실패하고,
--    통과가 안 되어 원래 문제(통나무에 끌림)가 그대로 남는다. → 부팅 시 보장한다.
--    이미 있으면 RegisterCollisionGroup 이 실패하지만 pcall 로 무시된다.
do
    pcall(function() PhysicsService:RegisterCollisionGroup(IFRAME_GROUP) end)
    pcall(function()
        PhysicsService:CollisionGroupSetCollidable(IFRAME_GROUP, "TaggerItems", false)
    end)
end

local function suspendCollision(character)
    local snapshot = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            snapshot[part] = part.CollisionGroup
            pcall(function() part.CollisionGroup = IFRAME_GROUP end)
        end
    end

    -- ⚠️ 콜리전만 꺼서는 부족하다. 이미 통나무가 부여한 속도가 캐릭터에 남아 있어
    --    충돌이 사라져도 그 관성으로 계속 미끄러진다. 실측(2026-08-23)에서
    --    흡수 시점 수평 속도가 12.5 로 남아 있었고, 그대로 밀려 불기둥에 닿아 죽었다.
    --    (DownSystem 이 NO_PUSH_ITEMS 로 '다운 시 관성을 죽이는' 것과 같은 이유)
    -- ⚠️ Y 는 살린다. 낙하 중이었다면 공중에 멈춰 버린다.
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp then
        local v = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
    return snapshot
end

local function restoreCollision(snapshot)
    if not snapshot then return end
    for part, originalGroup in pairs(snapshot) do
        -- ⚠️ 다운 등 다른 시스템이 그 사이에 그룹을 바꿨을 수 있다.
        --    내가 바꿔둔 값(IFRAME_GROUP)일 때만 되돌린다. 아니면 그쪽 상태를 존중.
        if part and part.Parent and part.CollisionGroup == IFRAME_GROUP then
            pcall(function() part.CollisionGroup = originalGroup end)
        end
    end
end

-- ── 흡수 판정 (ItemDamageSystem.processHit 이 호출) ────────────
-- 반환 true = 이 히트를 무효화한다.
-- 🗡️ count(선택, 기본 1) = 이 히트가 뚫는 내구도 칸 수. 자세한 규약은 함수 안 주석 참조.
function DurabilitySystem.absorb(character, sourceName, count)
    if not character then return false end

    -- 무적 중이면 계속 흡수한다. 같은 아이템의 연속 판정을 한 번으로 묶는 장치.
    if character:GetAttribute(IFRAME_ATTR) then
        return true
    end

    -- 🗡️ [2026-09-19] 다중 히트 판정. count 칸을 한 번에 소모한다.
    --   [왜 필요한가] Spear 를 "적중 시 2히트"로 만들려는데, processHit 을 두 번
    --     부르는 방식은 **성립하지 않는다** — 바로 위 무적 가드가 두 번째 호출을
    --     또 흡수해 버린다(연속 판정 병합 장치). 그래서 흡수 자체를 n칸 단위로 만든다.
    --   [의미] "내구도를 count 칸만큼 뚫는다". 다 못 뚫으면 흡수(다운 없음),
    --     뚫고도 모자라면 false 를 돌려 히트가 그대로 진행된다(= 다운).
    --       count=2, 내구도 1 → 1칸 소모 후 false → 다운 ✅ (이게 "2히트")
    --       count=2, 내구도 2 → 2칸 소모 후 true  → 흡수
    --       count=1(기본)     → 기존과 완전히 동일
    --   [왜 '무시'가 아니라 '소모'인가] 위 [확장 지점] 주석의 아머 상품(grant n칸)과
    --     맞물린다. 아머 2칸 러너는 Spear 한 방을 견디고 1칸은 못 견딘다 —
    --     "관통 무기 vs 방어 강화"라는 축이 생긴다. 단순 무시면 아머가 무의미해진다.
    --   ⚠️ 판정은 **한 번**이다. 킬이펙트·텔레메트리·어그로가 두 번 발화하지 않고,
    --     다운자에게 써도 "다운 + 즉사"가 되지 않는다.
    count = math.max(1, math.floor(tonumber(count) or 1))

    local n = character:GetAttribute(DUR_ATTR) or 0
    if n <= 0 then
        -- 🚧 [진단 2026-09-02] "내구도 소모 로그 없이 다운" 원인 분리용. 확인 후 제거.
        --   [증상] 09:09:53 판 — melonberrystrong 이 내구도 소모 없이 Wood Log 로 바로 다운.
        --     같은 판 AI 러너는 전부 '소모 → 다음 히트에 다운' 순서였다.
        --   [왜 구분이 안 됐나] 여기서 조용히 false 만 돌려주므로 로그가 없다.
        --     "칸이 있었는데 안 깎임" 과 "애초에 칸이 없음" 이 같은 침묵으로 보였다.
        --   [판별] MAX 가 nil/0 이면 reset(부여) 자체가 안 걸린 것이다.
        --     정상 소진은 위 성공 경로가 이미 "내구도 소모" 로그를 남기므로 여기서
        --     또 찍지 않는다 — 그래야 이 경고가 뜨는 것 자체가 신호가 된다.
        local maxN = character:GetAttribute(MAX_ATTR) or 0
        if maxN <= 0 then
            warn(string.format("🛡️ [Durability] 부여된 적 없음 — %s (원인 %s)",
                character.Name, tostring(sourceName)))
        end
        return false
    end

    -- 🗡️ count 칸을 한 번에 소모한다. 가진 만큼만 깎이고, 모자라면 아래에서 false.
    local consumed = math.min(n, count)
    n = n - consumed
    character:SetAttribute(DUR_ATTR, n)
    character:SetAttribute(IFRAME_ATTR, true)
    updateGauge(character)

    -- 무적 동안 태거 아이템을 통과시킨다(계속 밀려 끌려가는 것 방지).
    local snapshot = suspendCollision(character)

    -- 🔊 내구도 소모음. 각 클라가 자기 쪽에서 재생한다.
    -- ⚠️ 서버에서 Sound 를 만들어 Play() 하면 안 된다(2026-08-23 부활 보호막에서 실측).
    --    SoundService.RespectFilteringEnabled = true 환경이라 서버 진단상 playing=true
    --    인데도 클라에서 들리지 않았다. → 이벤트로 알리고 클라가 직접 재생한다.
    if durSfxRemote then
        durSfxRemote:FireAllClients(character)
    end

    print(string.format("🛡️ 내구도 소모: %s (%d칸 소모, 남은 %d, 원인 %s%s)",
        character.Name, consumed, n, tostring(sourceName or "?"),
        (count > 1) and string.format(" · %d히트", count) or ""))

    -- ⚠️ 연속 흡수 대비 토큰. 없으면 먼저 걸린 타이머가 나중 무적을 조기 해제하고
    --    콜리전도 미리 되돌려 버린다.
    local token = (character:GetAttribute("_DurIfToken") or 0) + 1
    character:SetAttribute("_DurIfToken", token)

    task.delay(IFRAME_TIME, function()
        if not (character and character.Parent) then return end
        if character:GetAttribute("_DurIfToken") ~= token then return end
        character:SetAttribute(IFRAME_ATTR, nil)
        character:SetAttribute("_DurIfToken", nil)
        -- ⚠️ 다운 상태면 되돌리지 않는다. 다운도 같은 그룹을 쓰는데 여기서 복원하면
        --    쓰러진 러너가 다시 통나무에 끌리게 된다.
        if not character:GetAttribute("Downed") then
            restoreCollision(snapshot)
        end
    end)
    -- 🗡️ count 칸을 다 막았을 때만 '흡수 성공'이다.
    --   모자라면 false → 호출부(ItemDamageSystem)가 히트를 그대로 진행시켜 다운이 난다.
    --   ⚠️ 그래도 위에서 가진 칸은 이미 소모했고 무적·콜리전 처리도 끝냈다.
    --     "뚫렸지만 방어는 값을 치렀다" 가 의도한 동작이다.
    return consumed >= count
end

-- 👁️ [2026-09-14] 게이지 노출 스윕 — 이 스크립트(상주)가 소유한다.
--   [왜 상주 루프인가] updateGauge 는 ItemDamageSystem 등 **다른 스크립트에서** 불린다.
--     거기서 task.delay 로 숨김을 예약하면 그 스크립트 혈통에 묶여, 호출자가 죽으면
--     콜백이 회수되고 게이지가 켜진 채 영영 남는다(에러도 안 남는다).
--     2026-09-13 에 같은 형태로 킹이 30초간 WalkSpeed 0 에 갇힌 이력이 있다.
--   ⚠️ 2단계 진입 시 이미 떠 있던 게이지도 이 루프가 내린다. 새로 만들 때만 걸렀다면
--     1단계부터 떠 있던 것이 그대로 남았을 것이다.
--   ⚠️ 1단계로 돌아오면 다시 상시 노출로 복귀한다(아래 isStage2 가 false 가 되는 순간).
local RunService = game:GetService("RunService")

local function isStage2()
    return ReplicatedStorage:GetAttribute("RoundPhase") == "stage2"
end

RunService.Heartbeat:Connect(function()
    local stage2 = isStage2()
    local now = os.clock()
    for _, model in ipairs(workspace:GetChildren()) do
        if model:IsA("Model") then
            local head = model:FindFirstChild("Head")
            local gui = head and head:FindFirstChild("DurabilityGauge")
            if gui then
                if not stage2 then
                    gui.Enabled = true                       -- 1단계: 상시
                else
                    local until_ = revealUntil[model]
                    gui.Enabled = (until_ ~= nil) and (now < until_) or false
                end
            end
        end
    end
end)

_G.DurabilitySystem = DurabilitySystem

-- ⚠️ 하위호환: ItemDamageSystem 이 _G.ArmorSystem.absorb 를 부르고 있다.
--    그쪽을 고치기 전까지 같은 테이블을 가리키게 해 둔다.
_G.ArmorSystem = DurabilitySystem

print("✅ DurabilitySystem 로드됨 (기본 " .. BASE_DURABILITY .. "칸)")
