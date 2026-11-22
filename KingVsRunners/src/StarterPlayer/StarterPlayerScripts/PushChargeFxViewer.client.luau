-- ✨ 다른 사람의 차징 이펙트를 보여주는 관찰자
--
-- [왜] PushTool.Client 는 도구를 든 본인에게만 실행된다.
--   러너 입장에서 "킹이 차징 중"이 보여야 피할 수 있는데,
--   본인 화면에만 나오면 예고 역할을 못 한다.
--
-- ⚠️ 서버가 캐릭터에 PushCharging 속성을 세운다(PushTool.Server).
--   그걸 감시해 같은 이펙트를 붙인다.
-- ⚠️ 본인은 PushTool.Client 가 이미 처리하므로 제외한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")   -- 🟥 예고 사각형 추종용

local localPlayer = Players.LocalPlayer
local FX_BANK = ReplicatedStorage:WaitForChild("PushChargeFx", 10)

local active = {}   -- [char] = { swirl, spark, wrist, saved }

local function clearFx(char)
    local a = active[char]
    if not a then return end
    active[char] = nil

    for _, inst in ipairs({ a.swirl, a.spark }) do
        if inst and inst.Parent then
            for _, d in ipairs(inst:GetDescendants()) do
                if d:IsA("ParticleEmitter") then d.Enabled = false end
            end
        end
    end
    if a.light and a.light.Parent then a.light.Enabled = false end

    task.delay(1.2, function()
        if a.swirl and a.swirl.Parent then a.swirl:Destroy() end
        if a.spark and a.spark.Parent then a.spark:Destroy() end
        if a.wrist and a.wrist.Parent then a.wrist:Destroy() end
    end)

    -- 손 원래 모습 복원
    if a.handle and a.handle.Parent and a.saved then
        a.handle.Color = a.saved.color
        a.handle.Material = a.saved.material
        if a.handle:IsA("MeshPart") and a.saved.texture then
            a.handle.TextureID = a.saved.texture
        end
    end
end

local function playFx(char, stage)
    if active[char] then return end
    if not FX_BANK then return end

    local tool = char:FindFirstChildOfClass("Tool")
    local handle = tool and tool:FindFirstChild("Handle")
    if not handle then return end

    local tpl = FX_BANK:FindFirstChild("Stage" .. tostring(stage or 1))
    if not tpl then return end

    local saved = {
        color = handle.Color,
        material = handle.Material,
        texture = handle:IsA("MeshPart") and handle.TextureID or nil,
    }

    local hc = tpl:GetAttribute("HandColor")
    if hc then handle.Color = hc end
    handle.Material = Enum.Material.Neon
    if handle:IsA("MeshPart") then handle.TextureID = "" end

    local wrist = Instance.new("Attachment")
    wrist.Name = "_ChargeWristRemote"
    local ratio = tpl:GetAttribute("WristOffsetRatio") or -0.32
    wrist.Position = Vector3.new(0, handle.Size.Y * ratio, 0)
    wrist.Parent = handle

    local light = Instance.new("PointLight")
    light.Color = tpl:GetAttribute("LightColor") or hc or Color3.new(1,1,1)
    light.Brightness = tpl:GetAttribute("LightBrightness") or 3
    light.Range = tpl:GetAttribute("LightRange") or 15
    light.Parent = wrist

    -- 💥 [2026-08-25] 시작 버스트. PushTool.Client 와 같은 규격으로 맞춘다.
    --   여기만 빠지면 킹 본인 화면만 화려하고 러너는 예고를 못 본다.
    --   (차징 중 손이 빛나는 것은 러너에게 주는 예고가 본래 목적이다.)
    local BURST_BASE = { Sparks = 45, MiniSparks = 40 }
    local burstMult = 1 + (math.clamp(stage or 1, 1, 3) - 1) * 0.5   -- 1 / 1.5 / 2
    local function burst(root)
        if not root then return end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("ParticleEmitter") then
                d.Enabled = true
                d:Emit(math.floor((BURST_BASE[d.Name] or 22) * burstMult))
            end
        end
    end

    local sa = tpl:FindFirstChild("SparkAtt")
    local sparkClone
    if sa then
        sparkClone = sa:Clone()
        sparkClone.Name = "_ChargeSparkRemote"
        sparkClone.Position = Vector3.new(0, handle.Size.Y * (tpl:GetAttribute("SparkOffsetRatio") or 0), 0)
        sparkClone.Parent = handle
        for _, d in ipairs(sparkClone:GetDescendants()) do
            if d:IsA("ParticleEmitter") then d.Enabled = true end
        end
        burst(sparkClone)
    end

    -- 🌀 회오리 — Handle 에 Attachment 직접 부착 (PushTool.Client 와 동일 방식).
    --   중간 Part + WeldConstraint 를 거치면 한 프레임 어긋난다.
    local swirlClone
    local sw = tpl:FindFirstChild("Swirl")
    local crashAtt = sw and sw:FindFirstChildOfClass("Attachment")
    if crashAtt then
        swirlClone = crashAtt:Clone()
        swirlClone.Name = "_ChargeSwirlRemote"
        swirlClone.Position = Vector3.new(0, handle.Size.Y * (tpl:GetAttribute("SwirlOffsetRatio") or 0), 0)
        swirlClone.Parent = handle
        for _, d in ipairs(swirlClone:GetDescendants()) do
            if d:IsA("ParticleEmitter") then d.Enabled = true end
        end
        burst(swirlClone)
    end

    active[char] = { swirl = swirlClone, spark = sparkClone,
                     light = light, wrist = wrist,
                     handle = handle, saved = saved }
end

-- 🟥 [2026-09-08] 강타 예고 사각형 (바닥 표시)
--   [왜] 차징 예고가 손 발광·차징음뿐이라 "어디까지 닿는지"를 알 방법이 없었다.
--     러너는 눈대중으로 피하고, 킹은 리치를 못 재고 휘둘렀다.
--     양쪽 모두에게 보여 회피를 플레이로 만든다.
--   ⚠️ 판정(PushTool.Server performHitCheck)과 '같은 수식'을 쓴다 —
--     평탄화 → forward * FORWARD → lookAt 순서까지 동일하게 맞췄다.
--     모양만 비슷하게 그리면 가장자리에서 "표시됐는데 안 맞음"이 생긴다.
--   ⚠️ 상수가 두 파일에 흩어져 있다. 서버의 CHARGED_FORWARD / CHARGED_SIZE 를
--     바꾸면 아래 세 값도 반드시 같이 바꿀 것. 한쪽만 고치면 어긋난다.
--   ⚠️ [2026-09-08] 평타가 아니라 '강타' 기준이다. 이 표시는 PushCharging 이
--     참일 때만 뜨고, 차징이 끝나면 반드시 강타가 나가기 때문이다.
--     평타(중심 3 / 깊이 10)를 그리면 실제보다 4 stud 짧게 표시된다.
local TELE_FORWARD = 5      -- = CHARGED_FORWARD
local TELE_W       = 10     -- = CHARGED_SIZE.X
local TELE_D       = 14     -- = CHARGED_SIZE.Z
-- 📏 [2026-09-18] 옛 상수 TELE_FOOT = 2.9 (HRP 중심 → 발밑)을 버린다.
--   [증상] 봇 킹의 강타 예고가 지면에 파묻혀 안 보였다(09-18 실측). 유저 킹은 정상.
--   [원인] 2.9 는 '표준 아바타'를 가정한 값이다. 실측 HRP→발바닥:
--     유저 아바타 3.01 → 예고 중심이 바닥 +0.11 (보임)
--     King npc2   2.33 → 예고 중심이 바닥 -0.57
--       파트 두께 0.2 라 윗면도 바닥 -0.47 — 구조적으로 보일 수 없었다.
--   [규칙] 체격을 가정하지 말고 발바닥을 계산해 그 위에 눕힌다.
--     DoubleJump:287 이 이미 같은 형태를 쓴다(footY = HRP.Y - Size.Y/2 - HipHeight).
--     선례가 있으니 새로 만들지 않고 그 형태를 따른다.
--   ⚠️ R6 는 HipHeight 를 0 으로 보고한다 — 실측 Noob·Famer2 둘 다 0(실제 3.00).
--     R15 만 정확하다(King npc2 오차 0.02 / runnerdummy2 오차 0.00).
--     0 이하면 R6 다리 길이 2 로 폴백한다. 이 분기를 지우면 R6 가 2 stud 뜬다.
--     ⚠️ DoubleJump 쪽은 이 폴백이 없다. 거기 R6 가 들어오면 같은 사고가 난다.
--   ⚠️ LIFT 0.2 는 옛 상수가 유저 아바타에서 만들던 여유(+0.11)보다 높다.
--     0.11 이면 파트 밑면이 바닥 +0.01 이라 경사·계단에서 바로 묻힌다.
--   ⚠️ 연출값이라 판정과 무관하다. 판정은 XZ 로만 잰다(PushTool.Server).
--     PushTool.Server 의 그랩 예고(telegraphY)도 09-18 에 같은 형태로 고쳤다 — 짝으로 볼 것.
local TELE_LIFT    = 0.2    -- 발바닥 위로 띄우는 높이. 순수 연출값(판정 무관)

local function footY(root, hum)
    local hip = (hum and hum.HipHeight) or 0
    if hip <= 0 then hip = 2 end                    -- R6 폴백(실측 근거는 위 주석)
    return root.Position.Y - (hip + root.Size.Y * 0.5)
end
local telegraphs   = {}     -- [char] = { part, conn }

local function hideTelegraph(char)
    local t = telegraphs[char]
    if not t then return end
    telegraphs[char] = nil   -- ⚠️ 먼저 지운다. Destroy 가 재진입을 부를 수 있다.
    if t.conn then t.conn:Disconnect() end
    if t.part then t.part:Destroy() end
end

-- 👑 [2026-09-18] 몸집 강화에 따른 판정 확대를 예고에도 반영한다.
--   [증상] 킹이 커져도 예고 사각형은 그대로였다. 판정만 커지고 표시는 안 커진다.
--     9킬(상한 ×2.5) 기준: 예고 도달 12 / 실제 판정 21 — **9 stud 가 표시 밖에서 맞는다.**
--   [근거] PushTool.Server:1008 의 sMult 와 **같은 수식**이어야 한다.
--       sMult = 1 + (KingScale − 1) × 0.5        (몸 배율의 절반)
--       hitCenter = root + forward × (FORWARD × sMult)
--       boxSize   = SIZE × sMult
--   [왜 중요한가] BombSystem 주석이 남긴 교훈 그대로다 —
--     "즉사 반경 75인데 경고가 70이라 원 밖 5스터드가 죽는 구간이 있었다.
--      학습 불가능한 죽음이라 불만으로 직결된다."
--     킹이 강해질수록 러너에게 더 불공정해지는 방향이라 더 나쁘다.
--   ⚠️ vMult(비슈누 스킨)는 곱하지 않는다. 그쪽은 "시각만 거대, 판정은 원본"이라
--     서버에서도 영원히 1 이다. 여기서 곱하면 스킨 쓴 킹만 예고가 커져 거짓말이 된다.
--   ⚠️ 2단계 중에는 KingScale 이 변하지 않는다(1단계 처치로만 오르고, 툴은 성문
--     붕괴에 지급된다). 그래서 생성 시점에 한 번 읽어도 어긋나지 않는다.
local function chargeSMult(char)
    local ks = char and char:GetAttribute("KingScale")
    if ks and ks > 1 then return 1 + (ks - 1) * 0.5 end
    return 1
end

local function showTelegraph(char)
    hideTelegraph(char)   -- 중복 방지("켜는 코드에 끄는 코드를 같이")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    -- ⚠️ 매 프레임 찾지 않도록 여기서 잡아둔다. footY 가 HipHeight 를 읽는다.
    local hum = char:FindFirstChildOfClass("Humanoid")
    -- 👑 판정 확대 배율. 아래 Size 와 전방 오프셋 **둘 다** 이걸 곱한다 —
    --   한쪽만 곱하면 사각형은 커지는데 위치가 안 따라가 오히려 더 어긋난다.
    local sm = chargeSMult(char)

    local p = Instance.new("Part")
    p.Name         = "_ChargeTelegraph"
    p.Size         = Vector3.new(TELE_W * sm, 0.2, TELE_D * sm)
    p.Anchored     = true
    p.CanCollide   = false
    p.CanQuery     = false   -- ⚠️ 레이캐스트에 걸리면 지면 판정·조준이 오염된다
    p.CanTouch     = false
    p.Massless     = true
    p.Material     = Enum.Material.Neon
    p.Color        = Color3.fromRGB(255, 60, 60)
    p.Transparency = 0.65
    p.Parent       = workspace

    -- 몸이 도는 대로 따라간다. 판정도 스윙 시점의 몸 방향을 쓰므로 같은 기준이다.
    local conn = RunService.RenderStepped:Connect(function()
        if not (char.Parent and root.Parent) then hideTelegraph(char) return end
        -- 🟥 [2026-09-16] 전이가 아니라 '상태'로 판정한다.
        --   [증상] 라운드 종료 직전에 차징하면 예고 사각형이 로비까지 따라와 영구 잔존.
        --   [원인] 해제가 전부 PushCharging 의 false '전이'에 걸려 있었다(196행).
        --     차징 도중 툴이 파괴되면 PushTool.Server 의 task.delay(CHARGE_TIME) 가
        --     호출자 혈통과 함께 회수돼 SetAttribute(false) 가 실행되지 않는다.
        --     에러도 안 나므로 전이가 영영 안 온다. 로비 복귀는 캐릭터를 교체하지 않아
        --     (RoundStateResetServer = 상태 복구) CharacterRemoving·위 가드도 안 걸린다.
        --   [해결] "표시는 속성이 참인 동안에만 존재한다"로 뒤집는다. 앞으로 어떤
        --     경로로 전이를 놓치든 다음 프레임에 스스로 사라진다.
        --     "제외 목록보다 결과 보장"과 같은 형태.
        --   ⚠️ 이건 증상 차단이다. 속성 자체의 고착은 PushTool.Server 쪽에서 막는다 —
        --     RunnerBotDriveController:1290 의 봇 강타 회피가 같은 속성을 읽으므로,
        --     여기만 고치면 사각형만 사라지고 봇 주행은 계속 오염된다.
        if not char:GetAttribute("PushCharging") then hideTelegraph(char) return end
        local fwd = root.CFrame.LookVector
        fwd = Vector3.new(fwd.X, 0, fwd.Z)          -- 평탄화 (서버와 동일)
        if fwd.Magnitude < 0.001 then return end
        fwd = fwd.Unit
        local c = root.Position + fwd * (TELE_FORWARD * sm)
        c = Vector3.new(c.X, footY(root, hum) + TELE_LIFT, c.Z)
        p.CFrame = CFrame.lookAt(c, c + fwd)
    end)

    telegraphs[char] = { part = p, conn = conn }
end

local function watch(char, withFx)
    -- ⚠️ [2026-09-08] 본인도 이제 watch 한다(예전엔 통째로 return 했다).
    --   손 이펙트는 여전히 PushTool.Client 담당이라 withFx=false 로 걸러내고,
    --   예고 사각형만 붙인다. 킹 본인에게도 보여야 리치를 재고 휘두른다.
    char:GetAttributeChangedSignal("PushCharging"):Connect(function()
        if char:GetAttribute("PushCharging") then
            if withFx then playFx(char, char:GetAttribute("PushChargeStage") or 1) end
            showTelegraph(char)
        else
            if withFx then clearFx(char) end
            hideTelegraph(char)
        end
    end)

    -- 🤖 [2026-09-08] 속성 보장 + 현재 상태 반영.
    --   [증상] 봇 킹의 예고 사각형이 안 떴다(실측).
    --   [원인] 봇은 스폰 직후 watch() 가 붙는데(tryWatchBot), PushTool 은
    --     2단계에 가서야 장착된다 — 실측 26초 차이. 그동안 PushCharging 속성이
    --     아예 없어서, 없는 속성에 건 GetAttributeChangedSignal 이
    --     첫 생성 때 발화하지 않았다.
    --   [해결] 여기서 false 로 미리 만들어 속성을 존재하게 한다.
    --     서버도 해제를 nil → false 로 바꿔(PushTool.Server) 두 번 다시 사라지지 않는다.
    --   ⚠️ 이미 차징 중인 캐릭터에 뒤늦게 붙는 경우도 있다(리스폰·늦은 관전 진입).
    --     그때는 시그널을 기다리면 이번 차징을 통째로 놓치므로 지금 상태를 즉시 반영한다.
    if char:GetAttribute("PushCharging") == nil then
        char:SetAttribute("PushCharging", false)
    elseif char:GetAttribute("PushCharging") then
        if withFx then playFx(char, char:GetAttribute("PushChargeStage") or 1) end
        showTelegraph(char)
    end
end

local function hook(plr)
    -- ⚠️ localPlayer 도 hook 한다. withFx 로만 갈린다.
    local withFx = (plr ~= localPlayer)
    if plr.Character then watch(plr.Character, withFx) end
    -- ⚠️ CharacterAdded:Connect(watch) 로 직결하면 두 번째 인자가 nil 이 되어
    --   다른 플레이어의 손 이펙트까지 꺼진다. 반드시 클로저로 감싼다.
    plr.CharacterAdded:Connect(function(c) watch(c, withFx) end)
    plr.CharacterRemoving:Connect(function(c) clearFx(c) hideTelegraph(c) end)
end

for _, p in ipairs(Players:GetPlayers()) do hook(p) end
Players.PlayerAdded:Connect(hook)

-- 태거봇(진짜 플레이어가 아님)도 감시
-- ⚠️ [2026-08-29] 조건을 IsTaggerNoob → Role=="Tagger" 로 바꿨다.
--   [증상] KING 봇이 강화 슬랩을 써도 차징 이펙트가 안 보였다.
--   [원인] IsTaggerNoob 은 TaggerNoobSystem(/taggerbot)이 세우는 속성이다.
--     TaggerBotSystem 의 KING 봇은 Role="Tagger" / TaggerDummy 를 세우므로
--     이 조건에 걸리지 않아 watch() 가 아예 붙지 않았다.
--   ⚠️ 유저 캐릭터도 workspace 의 Model 이고 Role 속성을 갖는다.
--     GetPlayerFromCharacter 로 걸러야 위 hook() 경로와 이중으로 붙지 않는다.
local function tryWatchBot(m)
    if not m:IsA("Model") then return end
    if Players:GetPlayerFromCharacter(m) then return end
    -- 🥊 [2026-09-19] 로비 훈련 더미도 감시한다.
    --   [왜] 더미가 강타(ChargedPush)를 쓰는데 차징 이펙트·범위 예고가 안 나왔다.
    --     **08-29 에 KING 봇에서 겪은 것과 정확히 같은 원인이다** — 위 주석 참조.
    --     그때는 IsTaggerNoob 만 보느라 Role="Tagger" 인 봇이 빠졌고,
    --     이번엔 Role 도 IsTaggerNoob 도 없는 더미가 빠졌다. 세 번째로 같은 자리다.
    --   ⚠️ [왜 더미에 Role="Tagger" 를 안 붙이나] Role 을 읽는 시스템이 많다.
    --     로비 설치물에 라운드 역할을 붙이면 어디로 번질지 못 가늠한다.
    --     **읽는 쪽에서 표식 하나를 더 보는 편이 파급이 없다**
    --     (PlayerMarkerClient 도 같은 날 같은 방식으로 처리했다).
    --   ⚠️ 이게 있어야 훈련이 성립한다. 실제 킹전에서 러너가 보는 신호가
    --     '손 발광 + 범위 예고' 인데, 그게 없으면 "예열을 보고 피한다"를 못 익힌다.
    if m:GetAttribute("Role") ~= "Tagger"
       and not m:GetAttribute("IsTaggerNoob")
       and not m:GetAttribute("LobbyDummy") then return end
    task.wait(0.3)   -- 스폰 직후엔 파츠가 아직 없을 수 있다
    if m.Parent then watch(m, true) end
end
workspace.ChildAdded:Connect(function(m) task.spawn(tryWatchBot, m) end)
for _, m in ipairs(workspace:GetChildren()) do task.spawn(tryWatchBot, m) end

print("✨ PushChargeFxViewer 준비")
