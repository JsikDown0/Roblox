-- 🥊 LobbyDummySlap — 로비 훈련 더미 중 일부가 슬랩으로 반격한다.
--
-- [왜] 훈련장 더미가 말 그대로 허수아비였다(사용자 제보). 때리는 연습은 되는데
--   "언제 밀려나는가"를 익힐 수단이 없었다.
--
-- [왜 진짜 PushTool 인가 — 흉내내지 않는 이유]
--   슬랩을 여기서 자체 구현하면 쿨(1.0) · 넉백(15) · 래그돌 길이 · 카타나 카운터
--   가로채기가 전부 실제 킹과 미세하게 달라진다. 연습이 **잘못된 타이밍을 가르친다**.
--   선례가 이미 있다 — TaggerBotSystem 의 봇 킹도 진짜 PushTool 을 구동한다.
--   그 진입점(Tool.BotAction:Fire)을 그대로 쓴다.
--   ⚠️ 새 공격 로직을 만들지 말 것. 그 순간 같은 규칙이 두 곳에 생긴다.
--
-- [무피해] 데미지 한 축만 PushTool.Server 에서 끈다(trainOnly, LobbyDummy 속성 판별).
--   [왜] 로비에서 죽을 수 있으면 안 된다. 로비 사망 경로(리스폰·상태 복구)가
--     검증된 적이 없어 부작용을 예측할 수 없다. 넉백·래그돌만으로 연습은 성립한다.
--
-- [제자리] WalkSpeed 0 을 그대로 둔다. 추격하면 LobbyDummyAnchor 의 홈 복귀와 싸운다
--   ("두 자리가 값을 넣고 싸운다" 유형). 사거리에 들어온 사람만 때린다.
--
-- ⚠️ 되돌리려면 ENABLED = false. 더미를 늘리거나 줄이려면 SLAP_DUMMIES 만 고친다.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local ENABLED = true

-- 🎯 반격하는 더미. 나머지는 순수 허수아비로 남긴다.
--   [왜 전부가 아닌가] 4체 모두 _DamageSensor 가 붙어 데미지 측정에 쓰인다.
--     반격으로 밀려나면 그 측정이 깨진다. 절반은 측정용으로 남겨둔다.
local SLAP_DUMMIES = {
    "LobbyTrainingDummy_C",
    "LobbyTrainingDummy_D",
}

-- 📏 이 안에 들어오면 휘두른다.
--   ⚠️ PushTool 의 실제 도달(기본 8, 무기 확대 배율 적용)보다 약간 넓게 잡는다.
--     좁으면 "붙었는데 안 때린다"가 되고, 넓으면 헛스윙이 는다.
local SLAP_RANGE  = 11
local TICK        = 0.25   -- 감시 주기(초)
local SWING_GAP   = 7.0    -- 강타 쿨(CHARGED_COOLDOWN). 아래 주석 참조
-- ⚔️ [2026-09-19] 더미는 **강타(차징 슬랩)** 를 쓴다. 1.0 → 6.0 → 1.0 → 7.0 로 왕복했다.
--   [왜 강타인가] 자세·스윙 모션에 ChargeR15 / AttackR15 를 썼는데 그게 강타 애니다.
--     그런데 발동은 "Push"(평타) 경로였다 — 모션은 강타, 판정은 평타.
--     프로젝트 원칙 "예고·표식·판정은 같은 모양이어야 한다" 에 걸린다.
--     → 발동도 "ChargedPush" 로 맞춘다. 넉백도 평타 15 가 아니라 강타 값이 된다.
--   [실측 쿨] PushTool: 평타 1초 / 강타 7초. 강타로 통일했으므로 7.
--   ⚠️ ChargedPush 는 beginCharge 를 탄다 — **부르는 즉시 맞는 게 아니라**
--     CHARGE_TIME 만큼 차징한 뒤 자동 발동한다. 차징음·손 발광·예고가 따라온다.
--     훈련 관점에서 이게 핵심이다: "예열을 보고 피한다"를 연습하게 된다.
--   ⚠️ 이 값은 로컬 스로틀이다. 실제 발동 가능 여부는 PushTool.Server 가 권위를 갖는다.
--   ⚠️ 머리 위 쿨 표시가 이 값을 그대로 읽는다.

-- ⏳ 차징 시작 → 발동까지 걸리는 시간(초). 스윙 모션 타이밍에만 쓴다.
--   [근거] 실측 로그 `[Charge] 시작` → `[Charge] 발동` 간격 1.50~1.52초 (여러 판).
--   🔴 [위험] 이 값은 PushTool 의 CHARGE_TIME 을 **복사한 것**이다. 그쪽이 바뀌면
--     여기가 조용히 어긋난다 — "같은 규칙이 두 곳에" 유형이다.
--     모션 타이밍에만 영향을 주므로 판정은 안 깨지지만, 어긋나면 스윙 모션이
--     실제 타격보다 이르거나 늦게 나온다. PushTool 쿨을 만질 때 같이 볼 것.
local CHARGE_TIME = 1.5
local FACE_TARGET = true   -- 휘두르는 순간 대상을 본다(AutoRotate 가 false 라 안 싸운다)

-- 🦾 [2026-09-19] 상시 착용 + 팔 앞으로.
--   [증상] 가까이 가야 푸시툴이 보였다(사용자 제보). ensureTool 이 '플레이어가
--     사거리 안일 때'만 불렸기 때문이다 — 멀리서는 맨손 허수아비로 보인다.
--   [수정] 착용·자세는 사거리와 무관하게 매 틱 유지한다. 스윙만 사거리를 본다.
--   [왜 팔을 직접 돌리나] 더미의 Animate 는 LocalScript 다. NPC 모델에서는
--     실행되지 않아 애니메이션이 아예 안 돈다 — 그래서 팔이 기본 자세로 늘어져
--     "들고 있는지" 가 안 읽힌다. 서버에서 Motor6D 를 직접 돌리면
--     돌려놓을 주체가 없어 그대로 유지된다(싸울 상대가 없다).
--   ⚠️ 원본 C0 를 속성에 저장하고 **항상 그 기준으로** 대입한다. 매 틱 곱하면
--     회전이 누적돼 팔이 계속 돌아간다.
--   ⚠️ 각도가 반대로 보이면 부호를 뒤집을 것. R15 어깨는 X축 회전이 앞뒤다.
local ARM_FORWARD_DEG = -75    -- 앞으로 뻗는 각도. 0 이면 기본 자세
local ARM_SPREAD_DEG  = 8      -- 살짝 벌려 어색함을 줄인다

if not ENABLED then return end

local toolTemplate = ReplicatedStorage:WaitForChild("PushTool")
local lastSwing = {}   -- [더미이름] = 마지막 스윙 시각

-- 더미에 PushTool 을 물린다. 이미 있으면 그대로 쓴다.
--   ⚠️ RequiresHandle=true 라 EquipTool 로 물려야 RightGrip 이 생긴다.
--     Parent 대입만 하면 손에 안 붙어 애니메이션이 헛돈다.
local function ensureTool(dummy)
    local hum = dummy:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    local tool = dummy:FindFirstChildOfClass("Tool")
    if tool and tool:FindFirstChild("BotAction") then return tool end
    tool = toolTemplate:Clone()
    tool.Parent = dummy
    hum:EquipTool(tool)
    return tool
end

-- 사거리 안의 가장 가까운 **플레이어** 를 고른다.
--   ⚠️ 대상 선별을 여기서 한다. PushTool 의 피격 필터에만 맡기면 다른 더미·NPC 에게도
--     헛스윙이 나간다 — 더미끼리는 37 stud 떨어져 있어 실제로 닿지는 않지만,
--     "아무도 없는데 계속 휘두르는" 그림이 된다.
local function nearestPlayerChar(root)
    local best, bestD = nil, SLAP_RANGE
    for _, plr in ipairs(Players:GetPlayers()) do
        local ch = plr.Character
        local r  = ch and ch:FindFirstChild("HumanoidRootPart")
        local h  = ch and ch:FindFirstChildOfClass("Humanoid")
        if r and h and h.Health > 0 and not ch:GetAttribute("Downed") then
            local d = (r.Position - root.Position).Magnitude
            if d <= bestD then best, bestD = ch, d end
        end
    end
    return best, bestD
end

-- 🦴 리그 보장 — 관절이 없으면 RigAttachment 로 만든다.
--   🔴 [경위 2026-09-19] 처음엔 "이 더미는 Motor6D 가 0개라 애니메이션이 구조적으로
--     불가능하다"고 결론 내렸다. **그 측정은 편집 모드에서 한 것이었다**(같은 쿼리에서
--     Tool=없음 이 나왔는데 런타임엔 부팅 때 장착된다). 관절도 용접도 없으면 런타임에
--     파츠가 흩어져야 하는데 안 흩어지므로, 런타임엔 관절이 있을 가능성이 높다.
--     ⚠️ 편집 모드 측정으로 런타임 구조를 단정하지 말 것. 오늘 이걸로 한 번 헛돌았다.
--   [그래서 양쪽 다 되는 형태로] 관절이 있으면 그대로 쓰고, 없으면 만든다.
--     RigAttachment 30개가 전부 있으므로 BuildRigFromAttachments 가 성립한다.
--   ⚠️ pcall 로 감싼다. 이미 리그가 있는데 다시 부르면 예외가 날 수 있다.
local rigDone = {}   -- [더미] = true. 리그는 한 번만 확인한다.

local function ensureRig(dummy, hum)
    -- ⚠️ [비용 2026-09-19] 캐시가 없으면 매 틱 GetDescendants() 로 Motor6D 를 센다.
    --   더미 16파트 × 2체 × 4회/초 = 130회/초. 한 번 만들면 끝나는 일을 계속 확인하는
    --   순수 낭비였다. 리그는 라운드와 무관하게 한 번만 보면 된다.
    if rigDone[dummy] then return true end
    local n = 0
    for _, x in ipairs(dummy:GetDescendants()) do
        if x:IsA("Motor6D") then n += 1 end
    end
    if n == 0 then
        local ok = pcall(function() hum:BuildRigFromAttachments() end)
        local after = 0
        for _, x in ipairs(dummy:GetDescendants()) do
            if x:IsA("Motor6D") then after += 1 end
        end
        print(string.format("🦴 [DummySlap] %s 리그 생성 %s — Motor6D 0 → %d",
            dummy.Name, ok and "시도" or "실패", after))
        n = after
    else
        print(string.format("🦴 [DummySlap] %s 리그 이미 있음 — Motor6D %d", dummy.Name, n))
    end
    rigDone[dummy] = true   -- 실패해도 다시 안 센다(매 틱 재시도가 더 나쁘다)
    return n > 0
end

-- 🎬 애니메이션 — 툴 자체 애니를 쓴다(킹과 같은 모션).
--   [자세] ChargeR15 를 속도 0 으로 멈춰 '팔 앞으로 든' 정지 자세를 만든다.
--   [스윙] AttackR15 를 한 번 재생하고 끝나면 자세로 돌아온다.
--   ⚠️ 더미의 Animate 는 LocalScript 라 NPC 에서 안 돈다 → 우리 트랙과 싸울 상대가 없다.
local animCache = {}   -- [더미] = { hold=track, atk=track }

local function ensureAnims(dummy, hum, tool)
    local c = animCache[dummy]
    if c and c.hold and c.hold.IsPlaying then return c end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end
    local holdSrc = tool:FindFirstChild("ChargeR15")
    local atkSrc  = tool:FindFirstChild("AttackR15")
    c = animCache[dummy] or {}
    local ok = pcall(function()
        if holdSrc and not c.hold then
            c.hold = animator:LoadAnimation(holdSrc)
            c.hold.Looped = true
            c.hold.Priority = Enum.AnimationPriority.Idle
        end
        if atkSrc and not c.atk then
            c.atk = animator:LoadAnimation(atkSrc)
            c.atk.Priority = Enum.AnimationPriority.Action
        end
        if c.hold and not c.hold.IsPlaying then
            c.hold:Play(0.2)
            -- ⚠️ 정지 자세: 재생 직후 멈춰 세운다. TimePosition 은 Length 가 0 이면
            --   의미가 없으니(로드 직후 0), 안전하게 speed 만 0 으로 둔다.
            task.delay(0.15, function()
                if c.hold and c.hold.IsPlaying then c.hold:AdjustSpeed(0) end
            end)
        end
    end)
    if not ok then return nil end
    animCache[dummy] = c
    return c
end

local function poseArms(_) end   -- ensureAnims 가 대신한다(호출부 호환용)

-- ⏱️ 쿨 표시 UI — 훈련장이므로 "언제 또 오는가"를 눈으로 익히게 한다.
--   [왜 BillboardGui + Scale 인가] 프로젝트 원칙: 크기는 Scale(스터드) 단위로 준다.
--     픽셀 고정은 거리와 무관하게 같은 크기라 멀리서 거대해 보인다
--     (TaggerHpDisplay:30 이 같은 이유로 이미 기각한 방식).
--   ⚠️ 머리 위 UI 는 이름표와 겹친다. StudsOffset 으로 피한다 —
--     VIP 커스텀이 2.5, 러너 HP바가 3.8 이다. 그 사이를 피해 3.2 로 둔다.
--   ⚠️ MaxDistance 를 둔다. 라운드 중 맵에서 로비 더미의 UI 가 보이면 안 된다.
local CD_UI = "SlapCooldownUI"
local function ensureCdUi(dummy)
    local head = dummy:FindFirstChild("Head")
    if not head then return nil end
    local bb = head:FindFirstChild(CD_UI)
    if bb then return bb:FindFirstChild("Label") end

    bb = Instance.new("BillboardGui")
    bb.Name = CD_UI
    bb.Size = UDim2.fromScale(5, 1.1)      -- 스터드 단위
    bb.StudsOffset = Vector3.new(0, 3.2, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 70
    bb.Parent = head

    local lbl = Instance.new("TextLabel")
    lbl.Name = "Label"
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextScaled = true
    lbl.TextStrokeTransparency = 0.4
    lbl.Text = ""
    lbl.Parent = lbl.Parent or bb
    lbl.Parent = bb
    return lbl
end

-- 남은 쿨을 갱신한다. 색은 "지금 위험한가" 한 축만 쓴다(원칙: 한 축에 두 정보 금지).
local function updateCdUi(dummy, name)
    local lbl = ensureCdUi(dummy)
    if not lbl then return end
    local remain = SWING_GAP - (os.clock() - (lastSwing[name] or -math.huge))
    if remain > 0 then
        lbl.Text = string.format("%.1f", remain)
        lbl.TextColor3 = Color3.fromRGB(255, 170, 60)
    else
        lbl.Text = "READY"
        lbl.TextColor3 = Color3.fromRGB(120, 255, 130)
    end
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
    acc += dt
    if acc < TICK then return end
    acc = 0

    for _, name in ipairs(SLAP_DUMMIES) do
        local dummy = workspace:FindFirstChild(name)
        local root  = dummy and dummy:FindFirstChild("HumanoidRootPart")
        if root then
            -- ⚠️ 착용·자세는 **사거리와 무관하게** 유지한다. 멀리서도 무장이 보여야 한다.
            local hum = dummy:FindFirstChildOfClass("Humanoid")
            local tool = ensureTool(dummy)
            if hum and tool then
                ensureRig(dummy, hum)
                ensureAnims(dummy, hum, tool)
            end
            updateCdUi(dummy, name)   -- ⏱️ 쿨 표시는 사거리와 무관하게 항상 갱신

            local targetChar = nearestPlayerChar(root)
            if targetChar then
                local now = os.clock()
                if now - (lastSwing[name] or 0) >= SWING_GAP then
                    local tool = ensureTool(dummy)
                    if tool then
                        local tRoot = targetChar:FindFirstChild("HumanoidRootPart")
                        local flat = Vector3.new(
                            tRoot.Position.X - root.Position.X, 0,
                            tRoot.Position.Z - root.Position.Z)
                        if flat.Magnitude > 0.01 then
                            local dir = flat.Unit
                            if FACE_TARGET then
                                root.CFrame = CFrame.lookAt(root.Position,
                                    root.Position + dir)
                            end
                            -- 🤖 봇 킹과 완전히 같은 진입점. 검증·실행이 유저 경로와 동일하다.
                            --   ⚠️ "ChargedPush" 는 beginCharge 를 타므로 **즉발이 아니다** —
                            --     CHARGE_TIME 뒤에 자동 발동한다. 차징음·손 발광이 따라온다.
                            tool.BotAction:Fire("ChargedPush", dir)
                            -- 🎬 모션 두 단계.
                            --   ① 지금: ChargeR15 를 **정상 속도로 재생** = 예열 텔레그래프.
                            --     (평소엔 같은 애니가 속도 0 으로 얼어 있어 '든 자세'다.
                            --      움직이기 시작하는 것 자체가 "온다"는 신호가 된다)
                            --   ② CHARGE_TIME 뒤: AttackR15 = 발동 스윙.
                            --   ⚠️ 끝나면 되돌리는 코드가 없다. Priority 로 처리된다 —
                            --     atk 는 Action, hold 는 Idle 이라 atk 가 끝나면 hold 가 드러난다.
                            local c = animCache[dummy]
                            if c then
                                pcall(function()
                                    if c.hold then c.hold:AdjustSpeed(1) end
                                end)
                                task.delay(CHARGE_TIME, function()
                                    pcall(function()
                                        if c.atk then c.atk:Play(0.05) end
                                        -- 예열 자세는 다시 얼려 '든 자세'로 복귀
                                        if c.hold then c.hold:AdjustSpeed(0) end
                                    end)
                                end)
                            end
                            lastSwing[name] = now
                        end
                    end
                end
            end
        end
    end
end)

print(string.format("🥊 LobbyDummySlap 준비 — 반격 더미 %d체 (사거리 %d, 무피해·넉백만)",
    #SLAP_DUMMIES, SLAP_RANGE))
