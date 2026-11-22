-- 킬 이펙트 시스템 v8 (ice_block 케이지 + Water Prison 공중 감금)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local Debris = game:GetService("Debris")

-- ── 킬 이펙트 연출 중 표시 ───────────────────────────────────
-- 라운드 종료(RoundSystem)가 연출을 끊지 않도록, 이펙트 발동 시 예상 완료 시각을 기록.
-- RoundSystem이 endRound 전에 이 시각까지 대기한다 (연출 가치 보존).
local effectBusyUntil = 0
local function markEffectBusy(duration)
	effectBusyUntil = math.max(effectBusyUntil, os.clock() + duration)
end
_G.KillEffectBusyUntil = function() return effectBusyUntil end
-- ⏳ [2026-08-27] 외부(ItemDamageSystem.ExecuteKillEffect)에서도 연출 시간을 등록할 수 있게 노출.
--   처형형 이펙트는 effectHandlers 를 안 타므로 그쪽에서 직접 불러야 한다.
_G.MarkKillEffectBusy = function(duration) markEffectBusy(tonumber(duration) or 8) end


-- ── 콜리전 그룹 설정 ─────────────────────────────────────────
local function ensureGroup(name)
    if not PhysicsService:IsCollisionGroupRegistered(name) then
        PhysicsService:RegisterCollisionGroup(name)
    end
end
ensureGroup("IceEffect")
ensureGroup("Runners")

PhysicsService:CollisionGroupSetCollidable("IceEffect", "TaggerItems", false)
PhysicsService:CollisionGroupSetCollidable("IceEffect", "Default",     false)
PhysicsService:CollisionGroupSetCollidable("IceEffect", "Runners",     false)
PhysicsService:CollisionGroupSetCollidable("TaggerItems", "Runners",   false)

print("🔥 KillEffectSystem v8 시작!")

-- ── 킬이펙트 파티클 텍스처 프리로드 준비 ───────────────────────────
-- 첫 발동 시 텍스처 스트리밍 지연(성기게/안 보임) 방지.
-- 템플릿들의 파티클 텍스처 ID를 ImageLabel로 ReplicatedStorage.PreloadAssets에 넣어두면
-- 클라 AssetPreloadClient가 PreloadAsync로 미리 캐시에 올림. (부트마다 재생성 → Ctrl+S 불필요)
local function buildKillEffectPreload()
    local pa = ReplicatedStorage:FindFirstChild("PreloadAssets")
    if not pa then
        pa = Instance.new("Folder")
        pa.Name = "PreloadAssets"
        pa.Parent = ReplicatedStorage
    end
    local old = pa:FindFirstChild("KillEffectTextures")
    if old then old:Destroy() end
    -- Part 홀더: 파티클 텍스처는 실제 ParticleEmitter로 preload해야 파티클 캐시에 정확히 올라감
    local holder = Instance.new("Part")
    holder.Name = "KillEffectTextures"
    holder.Transparency = 1
    holder.CanCollide = false
    holder.Anchored = true

    local TEMPLATES = { "empfieldfx", "Portalfx", "Tornadofx", "glitch effect", "Death coffin", "chain vfx", "Water Prison" }
    local seen, n = {}, 0
    for _, name in ipairs(TEMPLATES) do
        local t = ServerStorage:FindFirstChild(name) or workspace:FindFirstChild(name)
        if t then
            for _, d in ipairs(t:GetDescendants()) do
                if (d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")) and d.Texture ~= "" then
                    local tex = d.Texture
                    if not seen[tex] then
                        seen[tex] = true
                        n = n + 1
                        -- 파티클 캐시용
                        local pe = Instance.new("ParticleEmitter")
                        pe.Name = "pe_" .. n
                        pe.Texture = tex
                        pe.Rate = 0
                        pe.Enabled = false
                        pe.Parent = holder
                        -- 이미지 캐시용(이중 보장)
                        local img = Instance.new("ImageLabel")
                        img.Name = "img_" .. n
                        img.Image = tex
                        img.Visible = false
                        img.Parent = holder
                    end
                end
            end
        end
    end
    holder.Parent = pa

    -- 워밍업용 원본 클론: 실제 config 그대로 방출해야 정상 렌더/디코드됨 (특히 ForceField3)
    local wf = pa:FindFirstChild("WarmupTemplates")
    if wf then wf:Destroy() end
    wf = Instance.new("Folder")
    wf.Name = "WarmupTemplates"
    for _, name in ipairs({ "empfieldfx" }) do
        local t = ServerStorage:FindFirstChild(name) or workspace:FindFirstChild(name)
        if t then
            local c = t:Clone()
            for _, d in ipairs(c:GetDescendants()) do
                if d:IsA("ParticleEmitter") then d.Enabled = false end
            end
            c.Parent = wf
        end
    end
    wf.Parent = pa
    print("🖼️ 킬이펙트 텍스처 프리로드 준비:", n, "개 (PE+Img)")
end
buildKillEffectPreload()

-- ── Death coffin 템플릿 원본 투명도 저장 (경로 키, 중복 이름 충돌 방지) ──
-- key: 템플릿 루트 기준 상대 경로 (예: "CoffinCover/CoffinTop")
-- value: 원본 Transparency
local coffinOrigTransparency = {}

local function getRelPath(root, inst)
    local parts = {}
    local cur = inst
    while cur and cur ~= root do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, "/")
end

task.defer(function()
    local t = ServerStorage:FindFirstChild("Death coffin")
    if not t then return end
    for _, part in ipairs(t:GetDescendants()) do
        if part:IsA("BasePart") then
            coffinOrigTransparency[getRelPath(t, part)] = part.Transparency
            part.Transparency = 1
            part.CanCollide   = false
            part.CastShadow   = false
        end
        -- 템플릿 이펙트 모두 비활성화
        -- → Clone 시 비활성 상태로 복사됨 (지하 방출 방지)
        if part:IsA("ParticleEmitter") or part:IsA("Beam")
        or part:IsA("Fire") or part:IsA("Smoke")
        or part:IsA("PointLight") or part:IsA("SurfaceLight") or part:IsA("SpotLight") then
            part.Enabled = false
        end
    end
    print("⚰️ Death coffin 템플릿 초기화 완료 (이펙트 비활성화 포함)")
end)

local setKillEffectEvent  = ReplicatedStorage:WaitForChild("SetKillEffect")
local killLogEvent        = ReplicatedStorage:WaitForChild("KillLogEvent")
local killCoinEvent       = ReplicatedStorage:WaitForChild("KillCoinEvent")
local coffinCutsceneEvent = ReplicatedStorage:WaitForChild("CoffinCutsceneEvent")
local equippedEffects     = {}

setKillEffectEvent.OnServerEvent:Connect(function(player, effectId)
    -- ⚠️ [KILLFX-OWNERSHIP] 클라가 보낸 값을 그대로 믿으면 안 된다.
    --    소유 검증이 없어 상점에서 팔지 않은/구매하지 않은 킬이펙트도 장착됐다
    --    (실측 2026-08-22 진단). 상점 상품이므로 수익에 직접 영향.
    --    EffectSystem:92 와 같은 기준(OwnedItem_<id> 속성)을 쓴다.
    -- ⚠️ 타입 검사도 함께. 테이블/숫자가 들어오면 이후 비교에서 오작동한다.
    if effectId == "none" or effectId == nil then
        equippedEffects[player.UserId] = nil
        return
    end
    if type(effectId) ~= "string" then return end
    if not player:GetAttribute("OwnedItem_" .. effectId) then
        print("🚫 [KillEffect] " .. player.Name .. " 미보유 장착 시도: " .. effectId)
        return
    end
    equippedEffects[player.UserId] = effectId
end)
Players.PlayerRemoving:Connect(function(p) equippedEffects[p.UserId] = nil end)

-- ── 킬 공통 처리 ────────────────────────────────────────────
local KILL_COIN_REWARD = 10   -- 킬 시점에 RoundCoins로 "즉시 적립"되는 분

-- 킬로그에 표시할 최종 획득량.
-- 실제 지급은 [즉시 적립 10] + [endRound 결산분]의 합이라, 로그에 10만 띄우면
-- 결과창 금액과 어긋나 보인다. 그래서 표시는 총액으로 맞춘다. (지급 로직은 변경 없음)
--   태거의 러너 처치      = 10 + (RoundSystem 결산 roundKills * 20) = 30
--   러너의 태거 처치      = 10 + (RoundSystem 태거사망 시 +60)      = 70
--   AI 러너(농민봇) 처치  = 10 + 0  → RoundKills를 올리지 않으므로 결산 합산 없음
-- ⚠️ RoundSystem의 위 두 결산값을 바꾸면 여기 상수도 같이 고칠 것.
local KILL_COIN_TOTAL_TAGGER = 30
local KILL_COIN_TOTAL_RUNNER = 70

-- ═══════════════════════════════════════════════════════════
-- 👑 차징 슬랩 강화 단계
--
-- [왜] 1단계에서 잘한 태거가 2단계에서도 그 성과를 느껴야 한다.
--   숫자 버프는 저연령층에게 안 보이므로, 손 색으로 드러낸다.
--   흰색 → 노랑 → 빨강. 러너에게도 보이는 신호다.
--
-- ⚠️ 봇 가중치 0.5 — 유저를 잡는 게 2배 가치다.
--   그래야 태거가 봇만 상대하는 소극적 플레이를 안 한다.
--   솔로(봇만)는 11마리 전멸해도 5.5점이라 노랑이 상한이다.
--   → 빨강은 유저를 여럿 잡아야만 나온다.
-- ⚠️ 이 속성은 PushTool.Client 와 PushChargeFxViewer 가 읽는다.
-- ═══════════════════════════════════════════════════════════
local BOT_KILL_WEIGHT = 0.5
local STAGE_THRESHOLD = { 5, 9 }   -- 5점 이상 노랑, 9점 이상 빨강

-- ⚠️ [현재 미사용 — 부활 도입 대비] ────────────────────────
--   지금 구조에서는 이 코드가 실제로 동작할 일이 없다.
--     · 1단계: 태거는 TaggerWalls 안에 있고 러너는 무기가 없어 죽지 않는다.
--     · 2단계: 태거가 죽으면 그 즉시 라운드가 끝나므로 부활이 없다.
--
--   그럼에도 남겨두는 이유는 '킹 부활'을 나중에 넣기로 미뤄뒀기 때문이다.
--   (2026-08-25 논의: 킬 이펙트 재작업 비용 때문에 보류)
--   부활이 들어오면 태거가 죽고 살아날 때 Character 가 새로 생기는데,
--   PushChargeFxViewer 는 Character 속성을 감시하므로 복사가 없으면
--   부활 직후 단계가 1로 돌아간 것처럼 보인다.
--
--   비용은 CharacterAdded 훅 하나뿐이라 성능 영향이 없다.
--   부활을 끝내 안 넣기로 하면 이 블록을 지워도 된다.
-- ──────────────────────────────────────────────────────────
local function syncStageToCharacter(plr, char)
    if not plr or not char then return end
    char:SetAttribute("PushChargeStage", plr:GetAttribute("PushChargeStage") or 1)
end

do
    local Plrs = game:GetService("Players")
    local function hook(plr)
        plr.CharacterAdded:Connect(function(char)
            task.wait(0.2)
            syncStageToCharacter(plr, char)
        end)
    end
    for _, p in ipairs(Plrs:GetPlayers()) do hook(p) end
    Plrs.PlayerAdded:Connect(hook)
end

-- 👑 [2026-09-15] 1단계 성과 → 태거 몸집 확대 (연속값)
--
-- [왜] 강화 단계가 09-02 에 꺼진 이유가 "실효가 래그돌 0.4→0.8초뿐이라 안 보인다" 였다.
--   몸집은 킹 본인도 러너도 즉시 읽는다 — 그 빈자리를 채운다.
--
-- [왜 연속인가] 문턱(5/9)은 솔로에서 도달 불가였다. 봇 11마리 전멸해도 5.5점이라
--   3단계(9점)는 수학적으로 불가능하고, 2단계(5점)는 전멸해야 닿는데 그 판은 2단계가 없다.
--   연속으로 두면 한 마리 잡을 때마다 보상이 생기고 "문턱 직전 4점은 아무 의미 없음"이 사라진다.
--   ⚠️ 단계(PushChargeStage)는 그대로 둔다 — 이펙트 색·래그돌이 그걸 읽는다.
--
-- [값] 만점 4.0점에서 상한 2.5배. (유저 킬 1.0 + 봇 킬 0.5)
--   실측 2026-09-15 분포: 전력 봇10=5.0점 / 힘조절 봇6=3.0점 / 미사용 0점
--   → 힘조절 판(2단계에 실제로 가는 판)이 2.1배. 상한까지 여지가 남는다.
--   ⚠️ 3.0 만점이면 힘조절 판이 이미 천장이라 "더 잡을 이유"가 사라진다. 그래서 4.0.
--
-- ⚠️ [리그] 아바타 설정이 "플레이어 선택"이라 R6·R15 가 둘 다 들어온다.
--   R15  Humanoid 의 스케일 Value 가 정식 경로
--   R6   그게 아예 없다. 파트 Size + 서로의 상대 위치를 직접 곱해야 한다
--        ⚠️ 앵커/조인트로는 안 된다. 실측 2026-09-15 에 C0/C1 만 곱했다가
--          높이가 2.5배가 아니라 1.46배로 나왔다 — 파트 간격이 안 따라온다.
--
-- ⚠️ [정규화와의 순서] RoundSystem.normalizeAllPlayers 가 라운드 시작에 스케일을 1 로
--   강제한다(히트박스 통일·악용 방지). 그건 Tagger 선정 직후라 **이 함수보다 먼저** 돈다.
--   즉 어떤 아바타로 들어오든 1 에서 출발하므로 배율 기준이 항상 같다. 충돌 아님.
--
-- ⚠️ [툴] PushTool 은 2단계 성문 붕괴에 지급된다 — 몸이 커진 뒤에 들어온다.
--   여기서는 캐릭터에 KingScale 속성만 남기고, 툴 확대는 지급하는 쪽이 이 값을 읽어 처리한다.
-- ⚠️ [판정] 히트박스는 여기서 안 건드린다. PushTool.Server 의 vMult 는 비슈누 스킨용으로
--   "시각만 거대, 판정은 원본"이 이미 내려진 결정이다. 성과 보상과 스킨은 근거가 다르므로
--   섞지 말 것 — 판정 확대가 필요하면 별도 변수를 세운다.
local KING_SCALE_MAX   = 2.5
local KING_SCALE_FULL  = 4.0    -- 이 점수에서 상한

local function scaleFromScore(score)
    local t = math.clamp(score / KING_SCALE_FULL, 0, 1)
    return 1 + (KING_SCALE_MAX - 1) * t
end

local function applyKingScale(char, s)
    if not (char and char.Parent) then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- 👑 [2026-09-15] 왕관은 스케일 전에 떼어두고, 끝난 뒤 새 머리 크기로 다시 놓는다.
    --   [증상] 몸이 커져도 왕관이 제자리라 머리에 파묻혔다(실측 09-15).
    --   [원인] 왕관(char.TaggerCrown)은 WeldConstraint 로 머리에 붙어 있다.
    --     용접은 **만드는 순간의 상대 위치를 고정할 뿐**이라, 머리가 커져도
    --     왕관을 데려오지 않는다. 크기는 같이 커졌지만 위치가 안 따라온 것이다.
    --     (문서 원칙: "부착은 끌려오게 말고 직접 놓고 묶는다")
    --   [무엇을 하나] 용접을 끊고 → 몸을 스케일하고 → 새 머리 기준으로 다시 배치·용접.
    --   ⚠️ 왕관 자체는 아래 스케일 루프에서 함께 커진다(char 하위라서). 여기서는 위치만 다시 잡는다.
    --   ⚠️ RoundSystem 의 부착 공식과 같은 형태를 쓴다 — 머리 반높이 + 왕관 반두께 + 여유.
    --     그쪽 값을 바꾸면 여기도 같이 봐야 한다.
    local head = char:FindFirstChild("Head")
    local crown = char:FindFirstChild("TaggerCrown")
    local crownWelds = {}
    if crown and head then
        for _, d in ipairs(crown:GetDescendants()) do
            if d:IsA("WeldConstraint") then
                crownWelds[#crownWelds + 1] = d.Part1 or d.Part0
                d:Destroy()
            end
        end
    end

    if hum.RigType == Enum.HumanoidRigType.R15 then
        for _, name in ipairs({"BodyDepthScale","BodyWidthScale","BodyHeightScale","HeadScale"}) do
            local v = hum:FindFirstChild(name)
            if v then v.Value = s end
        end
        -- 👑 [2026-09-15] R15 에서도 왕관은 직접 곱한다.
        --   [증상] 머리는 배율대로 커지는데 왕관반이 1.10 으로 고정이었다(실측:
        --     ×1.19 head.Y=1.39 / ×2.31 head.Y=2.71 — 머리만 1.95배, 왕관 그대로).
        --   [원인] Humanoid 스케일 값은 **리그 파츠만** 건드린다. 왕관(TaggerCrown)은
        --     char 밑의 별도 모델이라 그 경로가 닿지 않는다.
        --   ⚠️ 여기도 증분만 곱한다. 매 처치마다 불리므로 목표값을 그대로 곱하면 기하급수다.
        if crown then
            local applied = char:GetAttribute("_KingCrownScale") or 1
            local step = s / applied
            if math.abs(step - 1) > 0.001 then
                for _, p in ipairs(crown:GetDescendants()) do
                    if p:IsA("BasePart") then p.Size = p.Size * step end
                end
                char:SetAttribute("_KingCrownScale", s)
            end
        end
    else
        -- R6: 이미 적용된 배율 대비 '증분'만 곱한다. 매 처치마다 불리므로
        --   누적으로 곱하면 기하급수가 된다.
        local applied = char:GetAttribute("_KingScaleApplied") or 1
        local step = s / applied
        if math.abs(step - 1) < 0.001 then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local origin = root.Position
        local snap = {}
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then snap[#snap + 1] = { p, p.CFrame } end
        end
        for _, e in ipairs(snap) do
            local p, cf = e[1], e[2]
            p.Size = p.Size * step
            local rel = cf.Position - origin
            p.CFrame = CFrame.new(origin + rel * step) * (cf - cf.Position)
        end
        char:SetAttribute("_KingScaleApplied", s)
    end

    -- 👑 왕관 재배치 + 재용접. 커진 머리 위에 다시 얹는다.
    --   ⚠️ 한 프레임 미룬다. 위에서 Size/CFrame 을 막 바꿨는데 같은 프레임에
    --     head.Size 를 읽으면 R15 는 아직 반영 전 값이 나올 수 있다.
    --   🔬 [진단 2026-09-15] 실측에서 "왕관이 커지는데 안 올라간다"가 나왔다.
    --     여기가 도는지, dy 가 얼마인지, 용접을 몇 개 잡았는지를 찍어 갈린다.
    --     ⚠️ 확인 끝나면 print 두 줄 삭제.
    if crown and head then
        if #crownWelds == 0 then
            print(("👑 [CrownDbg] ⚠️ 용접을 못 찾음 — 재배치 건너뜀 (crown=%s head=%s)"):format(
                tostring(crown ~= nil), tostring(head ~= nil)))
        end
    else
        print(("👑 [CrownDbg] ⚠️ crown=%s head=%s — 대상 없음"):format(
            tostring(crown ~= nil), tostring(head ~= nil)))
    end
    if crown and head and #crownWelds > 0 then
        task.defer(function()
            if not (crown.Parent and head.Parent) then
                print("👑 [CrownDbg] ⚠️ defer 시점에 crown/head 가 사라짐")
                return
            end
            for _, pp in ipairs(crownWelds) do
                if pp and pp.Parent then
                    -- 왕관은 PivotTo 시 Z 반두께가 위로 가도록 눕혀져 있다(CROWN_ROTATION).
                    local half = math.max(pp.Size.X, pp.Size.Y, pp.Size.Z) / 2
                    local dy = head.Size.Y / 2 + half + 0.2 * s
                    local before = pp.Position.Y
                    local rot = pp.CFrame - pp.CFrame.Position   -- 기존 각도 보존
                    pp.CFrame = CFrame.new(head.CFrame * Vector3.new(0, dy, 0)) * rot
                    local w = Instance.new("WeldConstraint")
                    w.Part0 = head
                    w.Part1 = pp
                    w.Parent = pp

                    -- 👑 [2026-09-15] 머리 위 UI 를 왕관보다 위로 밀어올린다.
                    --   [증상] 왕관이 커지면서 HP 바를 뚫고 올라갔다(실측: ×1.94 에서 왕관 dy 3.65
                    --     vs HP바 StudsOffset 3.5 — 왕관이 더 높다).
                    --   [원인] TaggerHpDisplay 는 StudsOffset 3.5 / CcImmuneGui 는 5.0 **고정**이다.
                    --     원래는 왕관 dy 1.86 이라 여유가 있었는데, 확대가 그 여유를 먹었다.
                    --   ⚠️ 원본 값을 속성에 적어두고 그 위에서 계산한다. 매 처치마다 불리므로
                    --     현재값에 더하면 누적된다.
                    --   ⚠️ 이름표(로블록스 기본)는 여전히 제어할 수 없다 — 문서에 기록된 한계 그대로.
                    for _, guiName in ipairs({"TaggerHpDisplay", "CcImmuneGui"}) do
                        local g = head:FindFirstChild(guiName)
                        if g and g:IsA("BillboardGui") then
                            local base = g:GetAttribute("_BaseStudsY")
                            if not base then
                                base = g.StudsOffset.Y
                                g:SetAttribute("_BaseStudsY", base)
                            end
                            -- 왕관 꼭대기 + 여유. 왕관이 낮으면 원래 높이를 유지한다.
                            --   ⚠️ 원래 층 간격(HP바 3.5 / CC 5.0 = 1.5)을 그대로 얹는다.
                            --     둘 다 같은 값으로 올리면 CC 표시가 HP 바와 겹친다.
                            local need = dy + half + 0.4 * s + (base - 3.5)
                            g.StudsOffset = Vector3.new(0, math.max(base, need), 0)
                        end
                    end
                    print(("👑 [CrownDbg] ×%.2f | head.Y=%.2f 왕관반=%.2f dy=%.2f | Y %.2f→%.2f (머리Y %.2f)")
                        :format(s, head.Size.Y, half, dy, before, pp.Position.Y, head.Position.Y))
                end
            end
        end)
    end
    -- 툴 지급 쪽이 읽는다(성문 붕괴 시점). 클라 연출도 이 값을 쓸 수 있다.
    char:SetAttribute("KingScale", s)
end

local function updateChargeStage(tagger, victimPos)
    if tagger:GetAttribute("Role") ~= "Tagger" then return end
    -- ⚠️ [2026-08-25] 1단계 킬만 반영한다.
    --   [왜] 강화는 "1단계에 쌓은 성과가 2단계 무기에 실린다"는 개념이다.
    --   2단계 킬까지 반영되면 싸우는 도중 색이 계속 바뀌어,
    --   ChargeStackClient 의 흡수 연출(= 힘이 무기로 들어감)과도 어긋난다.
    local ph = game:GetService("ReplicatedStorage"):GetAttribute("RoundPhase")
    if ph ~= "stage1" then return end
    local userKills = tagger:GetAttribute("RoundKills") or 0
    local botKills  = tagger:GetAttribute("RoundAIKills") or 0
    local score = userKills + botKills * BOT_KILL_WEIGHT

    local stage = 1
    -- 🚫 [비활성 2026-09-02] 강화 단계를 1(흰색)로 고정한다.
    --   [왜] 강화의 실효가 래그돌 0.4→0.8초뿐인데(데미지·넉백은 고정) 문턱은
    --     유저 5명/봇 10마리라 실전에서 거의 도달하지 않는다. 필요성 자체를
    --     재검토 중이라 효과를 전부 내린다.
    --   [왜 여기 한 곳인가] 소비처가 셋이다 — 손 이펙트(PushChargeFxViewer·
    --     PushTool.Client), 래그돌 차등(PushTool.Server STAGE_RAGDOLL),
    --     스택 HUD(ChargeStackClient). 셋 다 PushChargeStage 속성을 읽으므로
    --     여기서 1 로 고정하면 한 번에 꺼진다. 각자 끄면 되살릴 때 반드시 하나를 빠뜨린다.
    --   ⚠️ 1단계는 '기본 동작'이라 그대로 둔다 — 흰색 손빛과 래그돌 0.4초는 유지된다.
    --     노랑(2)·빨강(3)만 사라진다.
    --   ⚠️ 되살리려면 아래 두 줄만 지우면 된다. 점수 집계(RoundKills/RoundAIKills)는
    --     계속 돌고 있어 결과창 "(+N bots)" 병기도 그대로다.
    local CHARGE_STAGE_ENABLED = false
    if CHARGE_STAGE_ENABLED then
    if score >= STAGE_THRESHOLD[2] then stage = 3
    elseif score >= STAGE_THRESHOLD[1] then stage = 2 end
    end

    local prev = tagger:GetAttribute("PushChargeStage") or 1
    tagger:SetAttribute("PushChargeStage", stage)
    -- ⚠️ 캐릭터에도 넣는다. 러너 쪽 뷰어(PushChargeFxViewer)가
    --    캐릭터 속성을 감시하기 때문이다.
    local ch = tagger.Character
    if ch then ch:SetAttribute("PushChargeStage", stage) end

    if stage ~= prev then
        print(string.format("👑 [ChargeStage] %s → %d단계 (유저 %d + 봇 %d = %.1f점)",
            tagger.Name, stage, userKills, botKills, score))
    end

    -- 👑 몸집 확대 (연속). 단계와 달리 문턱이 없어 한 마리마다 반영된다.
    local ks = scaleFromScore(score)
    local prevKs = ch and ch:GetAttribute("KingScale") or 1
    applyKingScale(ch, ks)
    if ch and math.abs(ks - prevKs) > 0.001 then
        print(string.format("👑 [KingScale] %s → ×%.2f (%.1f/%.1f점)",
            tagger.Name, ks, score, KING_SCALE_FULL))
        -- ✨ 흡수 연출 — 처치한 자리에서 정기가 킹에게 빨려온다.
        --   [왜] 몸집이 조용히 커져 "왜 커졌는지"가 안 읽혔다(실측 09-15).
        --   ⚠️ 배율이 실제로 변한 경우에만 쏜다. 상한 도달 후 계속 처치하면
        --     ks 가 그대로라 연출이 안 나간다 — 그게 맞다. 더 강해지지 않았으니까.
        --   ⚠️ 전원에게 보낸다(FireAllClients). 러너도 경고로 읽어야 한다.
        if victimPos then
            local ev = game:GetService("ReplicatedStorage"):FindFirstChild("KingAbsorbFx")
            if ev then ev:FireAllClients(victimPos, ch, stage, ks) end
        end
    end
end

local function handleKill(tagger, victimName, victimCharacter)
    -- AI 러너(농민봇) 처치는 RoundKills 집계에서 제외.
    -- 승패 판정(RoundSystem.checkRunners)이 AIRunner를 세지 않는 것과 기준을 통일 —
    -- 리더보드(TYRANT: 누적 처치)가 봇 학살로 오염되는 것을 막는다.
    -- 코인·킬로그는 그대로 지급: 체감 보상과 피드백은 유지 (AI 킬인데 로그가 안 뜨면 버그로 보임).
    local isAIVictim = victimCharacter and victimCharacter:GetAttribute("AIRunner") or false
    if not isAIVictim then
        local kills = (tagger:GetAttribute("RoundKills") or 0) + 1
        tagger:SetAttribute("RoundKills", kills)
    else
        -- AI 처치는 RoundKills 와 분리해 별도 집계한다.
        -- 리더보드(TYRANT)는 RoundKills 만 보므로 봇 학살로 오염되지 않고,
        -- 결과창에는 "(+N bots)" 로 병기해 "코인은 주는데 Kills 가 0" 인 혼란을 없앤다.
        local aiKills = (tagger:GetAttribute("RoundAIKills") or 0) + 1
        tagger:SetAttribute("RoundAIKills", aiKills)
    end
    local rc = (tagger:GetAttribute("RoundCoins") or 0) + KILL_COIN_REWARD
    tagger:SetAttribute("RoundCoins", rc)

    local displayCoins
    if isAIVictim then
        displayCoins = KILL_COIN_REWARD                      -- 결산 합산 없음 → 즉시 적립분만
    elseif tagger:GetAttribute("Role") == "Runner" then
        displayCoins = KILL_COIN_TOTAL_RUNNER                -- 러너가 태거를 벤 경우
    else
        displayCoins = KILL_COIN_TOTAL_TAGGER
    end
    killLogEvent:FireClient(tagger, victimName, displayCoins)

    -- 👑 차징 강화 단계 갱신
    --   ⚠️ 피격자 위치를 같이 넘긴다 — 흡수 연출의 출발점이다.
    --     여기서 읽어야 한다. 잠시 뒤에는 캐릭터가 파괴돼 위치를 못 구한다.
    local vpos
    if victimCharacter then
        local r = victimCharacter:FindFirstChild("HumanoidRootPart")
            or victimCharacter:FindFirstChild("Torso")
            or victimCharacter:FindFirstChild("UpperTorso")
        vpos = r and r.Position or victimCharacter:GetPivot().Position
    end
    updateChargeStage(tagger, vpos)
end

-- 처형 연출 쪽에서 킬 등록만 따로 호출할 수 있게 노출.
-- ⚠️ onKill 은 Humanoid.Died 훅에서만 불리는데, 캐릭터를 Destroy 하는 연출(얼음)은
--    Died 가 발생하지 않아 킬 카운트·킬로그·코인이 통째로 누락된다.
--    (2026-08 실측: AI 5체 처치 후에도 결과창 Kills: 0, 킬로그 없음)
--    연출이 사망을 확정하는 시점에 이 함수를 직접 호출해 등록을 보장한다.
--    중복 방지: 이미 등록된 캐릭터는 _KillCounted 속성으로 걸러낸다.
_G.RegisterKill = function(tagger, victimCharacter, victimName)
    if not tagger or not victimCharacter then return false end
    if victimCharacter:GetAttribute("_KillCounted") then return false end
    victimCharacter:SetAttribute("_KillCounted", true)
    handleKill(tagger, victimName or victimCharacter.Name, victimCharacter)
    return true
end

-- ── 킬 이펙트 사운드 ID ──────────────────────────────────────
-- ⚠️ 아래 4종은 원래 박혀 있던 ID가 Audio가 아니라 Place/Image 에셋이었다.
--    (2026-08 전수 검사에서 확인: 4612378795·9117614560·5800702078 = Place, 2697632 = Image)
--    재생될 때마다 "Failed to load sound"가 콘솔을 도배해 다른 진단을 방해했으므로 비워둠.
--    ElevenLabs 제작본이 나오면 여기만 채우면 전 호출부에 반영된다.
--    빈 문자열이면 Roblox가 조용히 무시하므로 연출은 소리 없이 정상 동작한다.
local SFX_THUNDER = "rbxassetid://101098396030541"   -- 천둥 (번개 킬, Heavy_thunder_crack)
local SFX_ZAP     = ""   -- (현재 미사용 — 물감옥 폴백 경로에만 남음)
local SFX_GLASS   = ""   -- 유리/얼음 파열 (얼음 킬) — 비어있으면 SFX_ICE_FORM 1.25배속 폴백
local SFX_PORTAL  = "rbxassetid://119988520026144"   -- 차원문 개방 (포탈 킬, Dimensional_portal)
-- 흡입 지속음: 개방음 위에 겹쳐 1.3초 빨려들어가는 구간을 채운다.
-- (연출 타임라인: 0s 포탈 등장 → 1.3s 흡입 완료 → 1.65s 닫힘)
local SFX_PORTAL_SUCK = "rbxassetid://94468730531450"   -- Deep_cosmic_hum
local SFX_FIRE2   = "rbxassetid://93749901877422"   -- 화염 2차 레이어 (kv_burnvfx — 1차 폭발 위에 얹는 연소음)

-- 얼음 킬 전용: Frost Dragon 의 얼음 생성음을 공유한다.
-- 같은 번들("Frost Dragon 세트")로 판매하는 아이템끼리 사운드를 통일해
-- 세트 정체성을 만든다 — 드래곤 브레스와 얼음 처형이 같은 결로 들린다.
-- ⚠️ SFX_ZAP/SFX_THUNDER 는 번개·물 이펙트와 공유하므로 여기에 얼음음을 넣으면 안 된다.
--    (번개 킬에서 얼음 소리가 나게 됨) → 전용 상수로 분리.
local SFX_ICE_FORM = "rbxassetid://82245763898123"   -- 얼음 생성 (FrostDragonIceGenerator SND_ICE 와 동일)
-- 빙결 시작 전용음. 드래곤 브레스와 킬이펙트가 완전히 같은 소리면 두 연출이 구분되지 않아
-- "세트 통일"이 아니라 "재탕"으로 들린다. 시작음은 갈라두고 파열음만 세트를 공유해
-- 통일감과 구분감을 동시에 챙긴다. (ServerStorage.freezing 에 있던 미사용 음원)
local SFX_ICE_START = "rbxassetid://123722087623254"

-- ── 화염 이펙트 ──────────────────────────────────────────────
local function spawnFireEffect(position)
    local core = Instance.new("Part")
    core.Size = Vector3.new(1, 1, 1); core.Position = position
    core.Anchored = true; core.CanCollide = false; core.Transparency = 1; core.Parent = workspace

    -- 화염 사운드: kv_burnvfx 단독 재생.
    -- 이전에는 explosion(외부 음원) + kv_burnvfx 2겹이었으나, 직접 제작한 음원 하나로 통일.
    -- 단독이므로 볼륨·도달거리를 2겹 시절보다 올려 잡는다.
    local sound = Instance.new("Sound")
    sound.SoundId=SFX_FIRE2; sound.Volume=3.0; sound.RollOffMaxDistance=140
    sound.RollOffMinDistance=25; sound.PlaybackSpeed=math.random(92,108)/100; sound.Parent=core; sound:Play()

    local fire=Instance.new("Fire"); fire.Size=20; fire.Heat=25
    fire.Color=Color3.fromRGB(255,60,0); fire.SecondaryColor=Color3.fromRGB(255,230,0); fire.Parent=core
    local smoke=Instance.new("Smoke"); smoke.Color=Color3.fromRGB(40,40,40)
    smoke.Opacity=0.7; smoke.RiseVelocity=20; smoke.Size=8; smoke.Parent=core

    local sparks=Instance.new("ParticleEmitter")
    sparks.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,255,100)),ColorSequenceKeypoint.new(0.3,Color3.fromRGB(255,120,0)),ColorSequenceKeypoint.new(1,Color3.fromRGB(180,30,0))})
    sparks.LightEmission=1; sparks.LightInfluence=0
    sparks.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,2.5),NumberSequenceKeypoint.new(0.5,1.5),NumberSequenceKeypoint.new(1,0)})
    sparks.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(0.8,0.3),NumberSequenceKeypoint.new(1,1)})
    sparks.Lifetime=NumberRange.new(0.8,2.0); sparks.Rate=200; sparks.Speed=NumberRange.new(20,45)
    sparks.SpreadAngle=Vector2.new(180,180); sparks.RotSpeed=NumberRange.new(-180,180); sparks.Rotation=NumberRange.new(0,360); sparks.Parent=core

    local pillar=Instance.new("ParticleEmitter")
    pillar.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,255,200)),ColorSequenceKeypoint.new(0.2,Color3.fromRGB(255,150,0)),ColorSequenceKeypoint.new(0.7,Color3.fromRGB(200,40,0)),ColorSequenceKeypoint.new(1,Color3.fromRGB(80,10,0))})
    pillar.LightEmission=1; pillar.LightInfluence=0
    pillar.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,4),NumberSequenceKeypoint.new(0.4,6),NumberSequenceKeypoint.new(1,0)})
    pillar.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(0.6,0.2),NumberSequenceKeypoint.new(1,1)})
    pillar.Lifetime=NumberRange.new(1.0,2.5); pillar.Rate=80; pillar.Speed=NumberRange.new(25,50)
    pillar.SpreadAngle=Vector2.new(15,15); pillar.RotSpeed=NumberRange.new(-60,60); pillar.Parent=core

    local blast=Instance.new("ParticleEmitter")
    blast.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,255,150)),ColorSequenceKeypoint.new(0.4,Color3.fromRGB(255,80,0)),ColorSequenceKeypoint.new(1,Color3.fromRGB(100,0,0))})
    blast.LightEmission=1; blast.LightInfluence=0
    blast.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,5),NumberSequenceKeypoint.new(1,0)})
    blast.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.1),NumberSequenceKeypoint.new(1,1)})
    blast.Lifetime=NumberRange.new(0.3,0.8); blast.Rate=300; blast.Speed=NumberRange.new(30,60)
    blast.SpreadAngle=Vector2.new(90,90); blast.RotSpeed=NumberRange.new(-90,90); blast.Parent=core

    local embers=Instance.new("ParticleEmitter")
    embers.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,200,50)),ColorSequenceKeypoint.new(0.5,Color3.fromRGB(255,80,0)),ColorSequenceKeypoint.new(1,Color3.fromRGB(80,20,0))})
    embers.LightEmission=1
    embers.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.8),NumberSequenceKeypoint.new(1,0)})
    embers.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)})
    embers.Lifetime=NumberRange.new(2.0,4.0); embers.Rate=60; embers.Speed=NumberRange.new(5,20)
    embers.SpreadAngle=Vector2.new(180,180); embers.RotSpeed=NumberRange.new(-30,30); embers.Parent=core

    local offsets={Vector3.new(4,0,0),Vector3.new(-2,0,3.5),Vector3.new(-2,0,-3.5)}
    for _,offset in ipairs(offsets) do
        local side=Instance.new("Part"); side.Size=Vector3.new(1,1,1); side.Position=position+offset
        side.Anchored=true; side.CanCollide=false; side.Transparency=1; side.Parent=workspace
        local sf=Instance.new("Fire"); sf.Size=10; sf.Heat=15
        sf.Color=Color3.fromRGB(255,100,0); sf.SecondaryColor=Color3.fromRGB(255,200,50); sf.Parent=side
        local sp=Instance.new("ParticleEmitter")
        sp.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,150,0)),ColorSequenceKeypoint.new(1,Color3.fromRGB(100,20,0))})
        sp.LightEmission=1
        sp.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,2),NumberSequenceKeypoint.new(1,0)})
        sp.Lifetime=NumberRange.new(0.5,1.5); sp.Rate=60; sp.Speed=NumberRange.new(10,25)
        sp.SpreadAngle=Vector2.new(60,60); sp.Parent=side
        task.delay(0.4,function() if sf.Parent then sf.Enabled=false end; if sp.Parent then sp.Enabled=false end end)
        Debris:AddItem(side,3)
    end

    task.delay(0.5,function()
        if sparks.Parent then sparks.Enabled=false end; if pillar.Parent then pillar.Enabled=false end
        if blast.Parent then blast.Enabled=false end; if fire.Parent then fire.Enabled=false end
        if smoke.Parent then smoke.Enabled=false end
    end)
    task.delay(1.5,function() if embers.Parent then embers.Enabled=false end end)
    Debris:AddItem(core,5)
end

-- ── 번개 킬 이펙트 ──────────────────────────────────────────
local function spawnLightningEffect(position)
    local boltHeight=80
    local boltPart=Instance.new("Part")
    boltPart.Size=Vector3.new(1.5,boltHeight,1.5); boltPart.Position=position+Vector3.new(0,boltHeight/2,0)
    boltPart.Anchored=true; boltPart.CanCollide=false; boltPart.Material=Enum.Material.Neon
    boltPart.BrickColor=BrickColor.new("Cyan"); boltPart.Transparency=0.0; boltPart.CastShadow=false; boltPart.Parent=workspace
    task.spawn(function()
        for i=1,4 do
            boltPart.Transparency=0.0; boltPart.BrickColor=i%2==0 and BrickColor.new("Cyan") or BrickColor.new("White")
            task.wait(0.04); boltPart.Transparency=0.85; task.wait(0.03)
        end
        boltPart.Transparency=0.0; task.wait(0.05)
        for t=0,10 do boltPart.Transparency=t/10; task.wait(0.02) end
        boltPart:Destroy()
    end)
    local shockwave=Instance.new("Part"); shockwave.Shape=Enum.PartType.Cylinder
    shockwave.Size=Vector3.new(0.4,1,1); shockwave.CFrame=CFrame.new(position)*CFrame.Angles(0,0,math.pi/2)
    shockwave.Anchored=true; shockwave.CanCollide=false; shockwave.Material=Enum.Material.Neon
    shockwave.BrickColor=BrickColor.new("Electric blue"); shockwave.Transparency=0.1; shockwave.CastShadow=false; shockwave.Parent=workspace
    task.spawn(function()
        local TweenService=game:GetService("TweenService")
        TweenService:Create(shockwave,TweenInfo.new(0.35,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.new(0.3,22,22),Transparency=1.0}):Play()
    end)
    Debris:AddItem(shockwave,0.4)
    local sparksCore=Instance.new("Part"); sparksCore.Size=Vector3.new(1,1,1); sparksCore.Position=position
    sparksCore.Anchored=true; sparksCore.CanCollide=false; sparksCore.Transparency=1; sparksCore.Parent=workspace
    local sparks=Instance.new("ParticleEmitter")
    sparks.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,255,255)),ColorSequenceKeypoint.new(0.2,Color3.fromRGB(150,220,255)),ColorSequenceKeypoint.new(0.7,Color3.fromRGB(50,100,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(0,30,120))})
    sparks.LightEmission=1; sparks.LightInfluence=0
    sparks.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.4),NumberSequenceKeypoint.new(0.5,0.2),NumberSequenceKeypoint.new(1,0)})
    sparks.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(0.7,0.2),NumberSequenceKeypoint.new(1,1)})
    sparks.Lifetime=NumberRange.new(0.3,0.9); sparks.Rate=400; sparks.Speed=NumberRange.new(25,60)
    sparks.SpreadAngle=Vector2.new(180,180); sparks.RotSpeed=NumberRange.new(-360,360); sparks.Rotation=NumberRange.new(0,360); sparks.Parent=sparksCore
    local pillar=Instance.new("ParticleEmitter")
    pillar.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,255,255)),ColorSequenceKeypoint.new(0.3,Color3.fromRGB(100,200,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(0,50,200))})
    pillar.LightEmission=1; pillar.LightInfluence=0
    pillar.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,3),NumberSequenceKeypoint.new(0.5,5),NumberSequenceKeypoint.new(1,0)})
    pillar.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(0.5,0.3),NumberSequenceKeypoint.new(1,1)})
    pillar.Lifetime=NumberRange.new(0.6,1.4); pillar.Rate=100; pillar.Speed=NumberRange.new(30,55)
    pillar.SpreadAngle=Vector2.new(10,10); pillar.RotSpeed=NumberRange.new(-60,60); pillar.Parent=sparksCore
    local smoke=Instance.new("Smoke"); smoke.Color=Color3.fromRGB(30,20,60); smoke.Opacity=0.5; smoke.RiseVelocity=15; smoke.Size=5; smoke.Parent=sparksCore
    -- 번개 사운드: Heavy_thunder_crack 단독 재생 (화염과 동일하게 자체 제작 음원 하나로 통일).
    local thunder=Instance.new("Sound"); thunder.SoundId=SFX_THUNDER; thunder.Volume=3.0
    thunder.RollOffMaxDistance=150; thunder.RollOffMinDistance=25; thunder.PlaybackSpeed=math.random(92,108)/100; thunder.Parent=sparksCore; thunder:Play()
    task.delay(0.25,function() if sparks.Parent then sparks.Enabled=false end; if pillar.Parent then pillar.Enabled=false end end)
    task.delay(0.8,function() if smoke.Parent then smoke.Enabled=false end end)
    Debris:AddItem(sparksCore,4)
end


-- ── 빙결 킬 이펙트 (ice_block 케이지) ──────────────────────
local function spawnIceEffect(position, victimCharacter, tagger)
    local TweenService = game:GetService("TweenService")
    local template = ServerStorage:FindFirstChild("ice_block")
    if not template then warn("❄️ ice_block을 ServerStorage에서 찾을 수 없습니다!"); return end

    local SCALE = 0.42

    -- ── 피해자 빙결: 얼음 속에 가둠 (얼음이 깨질 때 사망 연출) ──────────
    local victimPlayer = victimCharacter and Players:GetPlayerFromCharacter(victimCharacter)
    if victimCharacter then
        local hum = victimCharacter:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = 0; hum.JumpPower = 0 end
        -- ⚠️ WalkSpeed/JumpPower 만으로는 "이동"만 막힌다. 공격은 그대로 나간다.
        --    실측: 얼음에 갇힌 농민봇이 태거를 계속 때렸고, 유저도 툴 사용이 가능했다.
        --    → 캐릭터에 IceFrozen 표식을 달고 공격 경로들이 이를 확인하게 한다
        --      (RunnerBotDriveController 의 봇 공격 / 무기 Tool.Activated).
        victimCharacter:SetAttribute("IceFrozen", true)
        -- 들고 있던 툴도 즉시 해제 — 얼음 속에서 무기를 휘두르는 그림 방지
        if hum then pcall(function() hum:UnequipTools() end) end
        -- 다시 장착하려 해도 빙결이 풀릴 때까지 계속 해제한다.
        -- (무기가 10종 넘어 각 스크립트를 고치는 대신 장착 자체를 중앙에서 막는다)
        victimCharacter.ChildAdded:Connect(function(c)
            if c:IsA("Tool") and victimCharacter:GetAttribute("IceFrozen") then
                task.defer(function()
                    if victimCharacter:GetAttribute("IceFrozen") then
                        local h = victimCharacter:FindFirstChildOfClass("Humanoid")
                        if h then pcall(function() h:UnequipTools() end) end
                    end
                end)
            end
        end)
        for _, part in ipairs(victimCharacter:GetDescendants()) do
            if part:IsA("BasePart") then
                part.AssemblyLinearVelocity  = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
                part.Anchored   = true
                part.CanCollide = false
            end
        end
    end

    -- 리스폰된 새 캐릭터는 얼음이 깨질 때까지 숨김 (코핀과 동일 방식)
    local iceActive   = true
    local hiddenChar  = nil
    local charConn    = nil
    if victimPlayer then
        charConn = victimPlayer.CharacterAdded:Connect(function(newChar)
            if not iceActive then return end
            hiddenChar = newChar
            task.spawn(function()
                local h = newChar:WaitForChild("Humanoid", 2)
                if h then h.WalkSpeed = 0; h.JumpPower = 0 end
                for _, p in ipairs(newChar:GetDescendants()) do
                    if p:IsA("BasePart") then p.Transparency = 1; p.CanCollide = false end
                    if p:IsA("Decal") or p:IsA("Texture") then p.Transparency = 1 end
                end
                local hrp = newChar:WaitForChild("HumanoidRootPart", 2)
                if hrp then hrp.CFrame = CFrame.new(0, -10000, 0); hrp.Anchored = true end
            end)
        end)
    end

    -- 멱등 종료: 얼어붙은 몸을 얼음과 함께 소멸시키고 정식 리스폰
    local iceEnded = false
    local function endIceSequence()
        if iceEnded then return end
        iceEnded = true
        iceActive = false
        -- 빙결 표식 해제 (봇 공격·툴 장착 차단 종료)
        if victimCharacter and victimCharacter.Parent then
            victimCharacter:SetAttribute("IceFrozen", nil)
        end
        if charConn then charConn:Disconnect(); charConn = nil end

        -- ⚠️ Destroy 전에 반드시 사망 판정을 확정한다.
        --    이 연출은 3초 시점에 원본을 Destroy 하는데, ItemDamageSystem 의 kill_effect_ice 도
        --    같은 3초에 killCharacter(Health=0)를 예약해 둔다. 두 타이머가 경쟁 상태라
        --    Destroy 가 먼저 이기면 killCharacter 가 character.Parent == nil 로 스킵되어
        --    "아무도 죽지 않은" 상태가 된다. → Died 이벤트 미발생 → 킬 카운트 누락 +
        --    RoundSystem.checkRunners 가 계속 생존자로 세어 라운드가 끝나지 않음.
        --    (2026-08 라이브에서 재현: 러너가 나가야만 태거 승리 판정이 나던 버그)
        --
        --    ⚠️ 여기서 Humanoid.Health = 0 을 직접 쓰면 안 된다.
        --    ItemDamageSystem.attachTaggerExec 의 HealthChanged 훅이 frozenCharacters 에 등록된
        --    캐릭터의 체력을 MaxHealth 로 되돌리기 때문(처형 연출 중 무적 처리).
        --    → frozen 해제까지 함께 처리하는 _G.KillFrozenCharacter 를 통해 죽인다.
        if victimCharacter and victimCharacter.Parent then
            -- 킬 등록(카운트·킬로그·코인)을 사망 처리 직전에 확정한다.
            -- Died 훅의 onKill 은 Destroy 로 인해 발생하지 않으므로 여기서 직접 호출.
            if tagger and _G.RegisterKill then
                pcall(function() _G.RegisterKill(tagger, victimCharacter, victimCharacter.Name) end)
            end
            if _G.KillFrozenCharacter then
                _G.KillFrozenCharacter(victimCharacter)
            else
                -- 폴백: ItemDamageSystem 미로드 시에도 최소한 사망은 보장
                local vHum = victimCharacter:FindFirstChildOfClass("Humanoid")
                if vHum and vHum.Health > 0 then vHum.Health = 0 end
            end
        end

        if victimCharacter and victimCharacter.Parent then victimCharacter:Destroy() end
        if victimPlayer and victimPlayer.Parent then
            if hiddenChar and hiddenChar.Parent then hiddenChar:Destroy() end
            task.spawn(function()
                task.wait(0.1)
                local ok, err = pcall(function() victimPlayer:LoadCharacter() end)
                if not ok then warn("❄️ endIceSequence LoadCharacter 실패:", err) end
            end)
        end
    end
    task.delay(12, endIceSequence)   -- 폴백: 무슨 일이 있어도 정리

    local cage = template:Clone()
    cage.Size=template.Size*SCALE
    cage.CFrame=CFrame.new(position.X,position.Y+1,position.Z)*template.CFrame.Rotation
    cage.Anchored=true; cage.CanCollide=false; cage.CollisionGroup="IceEffect"
    cage.CastShadow=false; cage.Transparency=1; cage.Parent=workspace

    local sndCore=Instance.new("Part"); sndCore.Size=Vector3.new(1,1,1); sndCore.Position=position
    sndCore.Anchored=true; sndCore.CanCollide=false; sndCore.Transparency=1; sndCore.Parent=workspace
    -- 빙결 시작음: 전용 음원(SFX_ICE_START). 드래곤과 다른 소리로 두어 연출이 구분되게 한다.
    -- 0.12s 뒤 낮은 배속 레이어를 겹쳐 처형다운 무게를 더한다.
    local snd1=Instance.new("Sound"); snd1.SoundId=SFX_ICE_START; snd1.Volume=3.0; snd1.PlaybackSpeed=1.0
    snd1.RollOffMode=Enum.RollOffMode.InverseTapered
    snd1.RollOffMinDistance=30; snd1.RollOffMaxDistance=250; snd1.Parent=sndCore; snd1:Play()
    local snd2=Instance.new("Sound"); snd2.SoundId=SFX_ICE_START; snd2.Volume=1.8; snd2.PlaybackSpeed=0.85
    snd2.RollOffMode=Enum.RollOffMode.InverseTapered
    snd2.RollOffMinDistance=30; snd2.RollOffMaxDistance=200; snd2.Parent=sndCore
    task.delay(0.12,function() snd2:Play() end)   -- 낮은 레이어를 겹쳐 처형다운 무게만 더함
    Debris:AddItem(sndCore,5)

    TweenService:Create(cage,TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Transparency=0.3}):Play()

    local snowCore=Instance.new("Part"); snowCore.Size=Vector3.new(1,1,1); snowCore.Position=position+Vector3.new(0,4,0)
    snowCore.Anchored=true; snowCore.CanCollide=false; snowCore.Transparency=1; snowCore.Parent=workspace
    local snow=Instance.new("ParticleEmitter")
    snow.Color=ColorSequence.new(Color3.fromRGB(215,242,255)); snow.LightEmission=0.3; snow.LightInfluence=0.6
    snow.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.22),NumberSequenceKeypoint.new(0.5,0.14),NumberSequenceKeypoint.new(1,0)})
    snow.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.2),NumberSequenceKeypoint.new(0.7,0.5),NumberSequenceKeypoint.new(1,1)})
    snow.Lifetime=NumberRange.new(1.2,2.8); snow.Rate=35; snow.Speed=NumberRange.new(2,7)
    snow.SpreadAngle=Vector2.new(180,180); snow.RotSpeed=NumberRange.new(-60,60); snow.Rotation=NumberRange.new(0,360); snow.Parent=snowCore

    task.delay(3.0,function()
        if snow.Parent then snow.Enabled=false end
        local breakCore=Instance.new("Part"); breakCore.Size=Vector3.new(1,1,1); breakCore.Position=position+Vector3.new(0,2,0)
        breakCore.Anchored=true; breakCore.CanCollide=false; breakCore.Transparency=1; breakCore.Parent=workspace
        -- 파열음: Frost Dragon 의 얼음 소멸과 동일 설정(같은 음원, PlaybackSpeed 1.25).
        -- 전용 유리 파열음(SFX_GLASS)이 준비되면 그쪽이 우선.
        local shatterId = (SFX_GLASS ~= "" and SFX_GLASS) or SFX_ICE_FORM
        local glassSnd=Instance.new("Sound"); glassSnd.SoundId=shatterId; glassSnd.Volume=3.2
        glassSnd.PlaybackSpeed=(SFX_GLASS ~= "") and 1.0 or 1.25
        glassSnd.RollOffMode=Enum.RollOffMode.InverseTapered
        glassSnd.RollOffMinDistance=30; glassSnd.RollOffMaxDistance=250; glassSnd.Parent=breakCore; glassSnd:Play()
        local iceSnd=Instance.new("Sound"); iceSnd.SoundId=SFX_ICE_FORM; iceSnd.Volume=1.6; iceSnd.PlaybackSpeed=1.25
        iceSnd.RollOffMaxDistance=100; iceSnd.Parent=breakCore; iceSnd:Play()
        Debris:AddItem(breakCore,3)
        local burstCore=Instance.new("Part"); burstCore.Size=Vector3.new(1,1,1); burstCore.Position=position+Vector3.new(0,2,0)
        burstCore.Anchored=true; burstCore.CanCollide=false; burstCore.Transparency=1; burstCore.Parent=workspace
        local shardBurst=Instance.new("ParticleEmitter")
        shardBurst.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(240,252,255)),ColorSequenceKeypoint.new(0.4,Color3.fromRGB(4,175,236)),ColorSequenceKeypoint.new(1,Color3.fromRGB(0,140,200))})
        shardBurst.LightEmission=0.6; shardBurst.LightInfluence=0.3
        shardBurst.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.9),NumberSequenceKeypoint.new(0.4,0.5),NumberSequenceKeypoint.new(1,0)})
        shardBurst.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(0.5,0.2),NumberSequenceKeypoint.new(1,1)})
        shardBurst.Lifetime=NumberRange.new(0.4,1.0); shardBurst.Rate=0; shardBurst.Speed=NumberRange.new(25,65)
        shardBurst.SpreadAngle=Vector2.new(180,180); shardBurst.RotSpeed=NumberRange.new(-360,360); shardBurst.Rotation=NumberRange.new(0,360)
        shardBurst.Parent=burstCore; shardBurst:Emit(80); Debris:AddItem(burstCore,3)
        -- 💀 얼음이 깨지는 순간 = 사망 연출: 얼어붙은 몸도 함께 소멸 → 리스폰
        endIceSequence()
        for i=1,8 do
            local shard=Instance.new("WedgePart")
            shard.Size=Vector3.new(math.random(2,6)/10,math.random(4,10)/10,math.random(3,7)/10)
            shard.CFrame=CFrame.new(position.X+math.random(-20,20)/10,position.Y+math.random(5,25)/10,position.Z+math.random(-20,20)/10)
                *CFrame.Angles(math.random(0,628)/100,math.random(0,628)/100,0)
            shard.Anchored=false; shard.CanCollide=false; shard.CollisionGroup="IceEffect"
            shard.Material=Enum.Material.Ice; shard.Color=Color3.fromRGB(4,175,236)
            shard.Transparency=0.25; shard.CastShadow=false; shard.Parent=workspace
            local angle=(i/8)*math.pi*2; local speed=math.random(18,35)
            shard.AssemblyLinearVelocity=Vector3.new(math.cos(angle)*speed,math.random(10,22),math.sin(angle)*speed)
            shard.AssemblyAngularVelocity=Vector3.new(math.random(-15,15),math.random(-15,15),math.random(-15,15))
            task.delay(0.1,function() if shard and shard.Parent then TweenService:Create(shard,TweenInfo.new(0.6,Enum.EasingStyle.Linear),{Transparency=1}):Play() end end)
            Debris:AddItem(shard,1.0)
        end
        if cage and cage.Parent then TweenService:Create(cage,TweenInfo.new(0.25,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=cage.Size*1.6,Transparency=1}):Play() end
        Debris:AddItem(cage,0.3)
    end)
    Debris:AddItem(snowCore,5)
end


-- ── 워터 킬 이펙트 (Water Prison 공중 감금 + 캐릭터 동반 부상) ──
local function spawnWaterEffect(position, victimCharacter)
    local TweenService = game:GetService("TweenService")

    local template = ServerStorage:FindFirstChild("Water Prison")
    if not template then
        warn("💧 Water Prison을 ServerStorage에서 찾을 수 없습니다!")
        return
    end

    local cage = template:Clone()

    local sphere    = nil
    local meshParts = {}
    for _, v in ipairs(cage:GetChildren()) do
        if v:IsA("Part") then
            sphere = v
        elseif v:IsA("MeshPart") then
            table.insert(meshParts, v)
        end
    end
    if not sphere then cage:Destroy(); return end

    local FLOAT_HEIGHT   = 14
    local templateSphere = template:FindFirstChildOfClass("Part")
    local templateCenter = templateSphere and templateSphere.Position or Vector3.new(0,0,0)
    local groundCenter   = Vector3.new(position.X, position.Y + 1, position.Z)
    local floatCenter    = Vector3.new(position.X, position.Y + FLOAT_HEIGHT, position.Z)
    local moveOffset     = groundCenter - templateCenter

    sphere.CFrame         = sphere.CFrame + moveOffset
    sphere.Anchored       = true
    sphere.CanCollide     = false
    sphere.CollisionGroup = "IceEffect"
    sphere.CastShadow     = false
    sphere.Transparency   = 1

    for _, mesh in ipairs(meshParts) do
        mesh.CFrame         = mesh.CFrame + moveOffset
        mesh.Anchored       = false
        mesh.Massless       = true
        mesh.CanCollide     = false
        mesh.CollisionGroup = "IceEffect"
        mesh.CastShadow     = false
        mesh.Transparency   = 1
    end

    cage.Parent = workspace

    -- 🔊 water splash 사운드
    local splashTemplate = ServerStorage:FindFirstChild("water splash")
    local sndCore = Instance.new("Part")
    sndCore.Size=Vector3.new(1,1,1); sndCore.Position=groundCenter
    sndCore.Anchored=true; sndCore.CanCollide=false; sndCore.Transparency=1; sndCore.Parent=workspace
    if splashTemplate then
        local snd = splashTemplate:Clone()
        snd.Volume=2.5; snd.RollOffMaxDistance=120; snd.Parent=sndCore; snd:Play()
    else
        local snd=Instance.new("Sound"); snd.SoundId=SFX_ZAP
        snd.Volume=2.0; snd.PlaybackSpeed=0.5; snd.RollOffMaxDistance=100; snd.Parent=sndCore; snd:Play()
    end
    Debris:AddItem(sndCore, 5)

    -- 등장 트윈
    TweenService:Create(sphere, TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {Transparency=0.3}):Play()
    for _, mesh in ipairs(meshParts) do
        TweenService:Create(mesh, TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {Transparency=0.15}):Play()
    end

    -- 초기 상대 CFrame 저장
    local sphereInitCF = CFrame.new(sphere.Position)
    local relMesh = {}
    for _, mesh in ipairs(meshParts) do
        relMesh[mesh] = sphereInitCF:Inverse() * mesh.CFrame
    end

    local charParts = {}
    local relChar   = {}
    if victimCharacter then
        for _, part in ipairs(victimCharacter:GetDescendants()) do
            if part:IsA("BasePart") then
                table.insert(charParts, part)
                relChar[part] = sphereInitCF:Inverse() * part.CFrame
            end
        end
    end

    -- 구 공중 부상
    TweenService:Create(sphere,
        TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { CFrame = CFrame.new(floatCenter) }
    ):Play()

    -- 💧 물방울 파티클
    local waterCore=Instance.new("Part"); waterCore.Size=Vector3.new(1,1,1); waterCore.Position=groundCenter
    waterCore.Anchored=true; waterCore.CanCollide=false; waterCore.Transparency=1; waterCore.Parent=workspace
    local drops=Instance.new("ParticleEmitter")
    drops.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(4,175,236)),ColorSequenceKeypoint.new(1,Color3.fromRGB(100,220,255))})
    drops.LightEmission=0.2; drops.LightInfluence=0.7
    drops.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.25),NumberSequenceKeypoint.new(0.5,0.12),NumberSequenceKeypoint.new(1,0)})
    drops.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.1),NumberSequenceKeypoint.new(1,1)})
    drops.Lifetime=NumberRange.new(1.0,2.2); drops.Rate=25; drops.Speed=NumberRange.new(1,5)
    drops.SpreadAngle=Vector2.new(180,180); drops.RotSpeed=NumberRange.new(-60,60); drops.Rotation=NumberRange.new(0,360)
    drops.Parent=waterCore

    -- 🔄 Heartbeat
    local SPIN_SPEED = 1.5
    local CHAR_SPIN  = 2.5
    local angle      = 0
    local charAngle  = 0
    local active     = true

    local conn = RunService.Heartbeat:Connect(function(dt)
        if not active or not (cage and cage.Parent) then return end
        angle     += SPIN_SPEED * dt
        charAngle += CHAR_SPIN  * dt
        local spherePos  = sphere.Position
        local meshSpinCF = CFrame.new(spherePos) * CFrame.Angles(0, angle, 0)
        for _, mesh in ipairs(meshParts) do
            if mesh and mesh.Parent then mesh.CFrame = meshSpinCF * relMesh[mesh] end
        end
        local charSpinCF = CFrame.new(spherePos) * CFrame.Angles(0, charAngle, 0)
        for _, part in ipairs(charParts) do
            if part and part.Parent then part.CFrame = charSpinCF * relChar[part] end
        end
    end)

    -- ⏰ 4초 후: 버스트 파티클 + 즉시 제거
    task.delay(4.0, function()
        active = false
        conn:Disconnect()
        if drops.Parent then drops.Enabled = false end
        local burstCore=Instance.new("Part"); burstCore.Size=Vector3.new(1,1,1)
        burstCore.Position=sphere.Position
        burstCore.Anchored=true; burstCore.CanCollide=false; burstCore.Transparency=1; burstCore.Parent=workspace
        local burst=Instance.new("ParticleEmitter")
        burst.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(200,245,255)),ColorSequenceKeypoint.new(0.4,Color3.fromRGB(4,175,236)),ColorSequenceKeypoint.new(1,Color3.fromRGB(0,120,200))})
        burst.LightEmission=0.5; burst.LightInfluence=0.4
        burst.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,1.2),NumberSequenceKeypoint.new(0.4,0.6),NumberSequenceKeypoint.new(1,0)})
        burst.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(0.5,0.2),NumberSequenceKeypoint.new(1,1)})
        burst.Lifetime=NumberRange.new(0.5,1.4); burst.Rate=0; burst.Speed=NumberRange.new(20,55)
        burst.SpreadAngle=Vector2.new(180,180); burst.RotSpeed=NumberRange.new(-180,180); burst.Rotation=NumberRange.new(0,360)
        burst.Parent=burstCore; burst:Emit(120); Debris:AddItem(burstCore,3)
        cage:Destroy()
    end)

    Debris:AddItem(waterCore, 5)
    print("💧 Water Prison 공중 감금 발동! 위치:", position)
end



-- ── 데스 코핀 킬 이펙트 v12 ─────────────────────────────────────────
-- 시퀀스:
--  Step1  플레이어 앵커 + chain vfx 발밑 등장 + 파티클 활성화 (구속)
--  Step2  플레이어 뒤쪽에서 관이 땅 아래에서 천천히 올라오며 등장
--         (등장 중 약간의 검은 연기)
--  Step3  뚜껑 오픈
--  Step4  플레이어 + chain vfx 입관
--  Step5  뚜껑 닫힘
--  Step6  관을 2초 비춰줌
--  Step7  관이 약간의 검은 연기와 함께 천천히 땅 아래로 내려감
--  Step8  플레이어 사망 처리
-- ☠️ [2026-08-28] 처형 연출의 '스레드 소유권' 분리 — 6종 공용.
--   [증상] 코핀이 중간에 멎고 관이 맵에 영구히 남는다. 진단상 thr=suspended —
--     에러로 죽은 게 아니라 살아 있는데 스케줄러가 더 이상 깨우지 않는다.
--     (task.wait 만 있는 스레드가 안 깨어나는 건 "불가능"이 아니었다)
--   [원인] 연출 스레드의 혈통이 호출자에서 시작한다. 프드 얼음 생성기는
--     clone 되어 붙었다가 드래곤과 함께 Destroy 되는 임시 스크립트인데
--     (파쇄 로그에 스크립트 출처가 안 찍히는 게 증거), 그 유령 스레드가
--     끝나는 순간 같은 혈통의 자손 스레드가 함께 회수된다.
--     실측: 3개 배치 전부 '얼음 파쇄' 시각에 정지. 얼음이 없던 곡사포발
--     코핀 1건만 정상 완료. 데몬스피어·에너지볼이 멀쩡했던 것도 같은 이유
--     (그 시스템 스크립트는 죽지 않는다).
--   [해결] 부팅 때 띄운 워커가 큐에서 꺼내 task.spawn 한다. 그러면 연출
--     스레드의 뿌리는 항상 이 스크립트의 부팅 스레드다.
--   ⚠️ 큐에 넣는 건 '연출'뿐이다. 몸을 확보하는 프롤로그(freezeCharacter·속성)는
--     ItemDamageSystem 의 핸들러가 '동기'로 끝낸 뒤 여기로 넘어온다.
--     그 순서를 뒤집지 말 것 — 큐 대기 중 몸이 무방비가 되어 라운드 종료 정리에
--     시체가 먼저 치워지고 관이 빈 채로 재생됐다(실측 12:57:37, 되돌림).
--   ⚠️ 호출부에서 직접 task.spawn 하지 말 것 — 그 순간 혈통이 되살아난다.
--     처형 이펙트를 추가할 때도 반드시 queueFx 를 거칠 것.
--   ⚠️ 이 워커는 반드시 최상위(부팅 스레드)에서 띄워야 한다. 함수 안으로
--     옮기면 그 함수 호출자의 혈통을 물려받아 원래 문제로 되돌아간다.
local _fxQueue = {}
task.spawn(function()
    while true do
        task.wait()
        while #_fxQueue > 0 do
            task.spawn(table.remove(_fxQueue, 1))
        end
    end
end)
local function queueFx(fn)
    _fxQueue[#_fxQueue + 1] = fn
end

local function spawnCoffinEffect(position, victimCharacter)
    local TweenService = game:GetService("TweenService")

    local template      = ServerStorage:FindFirstChild("Death coffin")  -- ServerStorage 기준
    local chainTemplate = ServerStorage:FindFirstChild("chain vfx")   -- Death coffin과 같은 위치로 통일
    if not template then warn("⚰️ 'Death coffin' 없음"); return end

    local tBottom = template:FindFirstChild("CoffinBottom")
    local tCover  = template:FindFirstChild("CoffinCover")
    local tTop    = tCover and tCover:FindFirstChild("CoffinTop")
    if not (tBottom and tCover and tTop) then warn("⚰️ Death coffin 구조 오류"); return end

    local victimPlayer   = Players:GetPlayerFromCharacter(victimCharacter)
    local victimHumanoid = victimCharacter:FindFirstChildOfClass("Humanoid")
    local root = victimCharacter
        and (victimCharacter:FindFirstChild("HumanoidRootPart")
          or victimCharacter:FindFirstChild("Torso")
          or victimCharacter:FindFirstChild("UpperTorso"))
    if not root then warn("⚰️ root 없음"); return end

    -- ── per-player 자동 리스폰 가로채기 ─────────────────────────────────
    -- Roblox 기본 RespawnTime(5초)보다 이펙트가 길어서 중간에 자동 리스폰 되면
    -- 하강이 끝나기 전 새 캐릭터가 스폰되어 "먼저 죽은 것"처럼 보임
    --
    -- per-player 방식: Players.CharacterAutoLoads는 건드리지 않고
    -- 이 플레이어의 CharacterAdded만 가로채서 새 캐릭터를 숨김/잠금.
    -- → 다른 플레이어가 동시에 죽어도 정상적으로 자동 리스폰됨.
    local coffinActive = true
    local hiddenCharacter = nil  -- 자동 리스폰으로 생긴 숨겨진 캐릭터
    local charAddedConn

    if victimPlayer then
        charAddedConn = victimPlayer.CharacterAdded:Connect(function(newChar)
            if not coffinActive then return end
            hiddenCharacter = newChar
            -- 새 캐릭터를 즉시 숨기고 잠금 (뷰에서 완전히 제거)
            task.spawn(function()
                local hum = newChar:WaitForChild("Humanoid", 2)
                if hum then
                    hum.WalkSpeed = 0
                    hum.JumpPower = 0
                end
                for _, p in ipairs(newChar:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.Transparency = 1
                        p.CanCollide = false
                    end
                    if p:IsA("Decal") or p:IsA("Texture") then
                        p.Transparency = 1
                    end
                end
                local hrp = newChar:WaitForChild("HumanoidRootPart", 2)
                if hrp then
                    hrp.CFrame = CFrame.new(0, -10000, 0)
                    hrp.Anchored = true
                end
            end)
        end)
    end

    -- 멱등성 있는 종료 함수 (여러 번 호출 안전)
    local coffinEnded = false
    local function endCoffinSequence()
        if coffinEnded then return end
        coffinEnded = true
        coffinActive = false
        if charAddedConn then
            charAddedConn:Disconnect()
            charAddedConn = nil
        end
        -- 숨겨진 캐릭터 정리 + 정식 리스폰
        if victimPlayer and victimPlayer.Parent then
            if hiddenCharacter and hiddenCharacter.Parent then
                hiddenCharacter:Destroy()
            end
            task.spawn(function()
                task.wait(0.1)
                local ok, err = pcall(function()
                    victimPlayer:LoadCharacter()
                end)
                if not ok then
                    warn("⚰️ endCoffinSequence LoadCharacter 실패:", err)
                else
                    print("⚰️ endCoffinSequence LoadCharacter 성공:", victimPlayer.Name)
                end
            end)
        end
    end

    -- 폴백: 어떤 에러가 나도 30초 뒤에 반드시 정리
    task.delay(30, endCoffinSequence)

    -- ── [COFFIN-POSE] 무기 해제 + 차렷 자세 ──────────────────────────────
    -- 증상: PushTool 을 앞으로 든 자세 그대로 굳어, 관 뚜껑이 닫혀도 툴이 관 앞으로 튀어나왔다.
    -- 원인: 아래 앵커 블록(또는 ItemDamageSystem.freezeCharacter)이 전 파트를 Anchored 로 만드는데,
    --       앵커된 파트는 Motor6D 로 움직이지 않아 그 순간의 포즈가 그대로 고정된다.
    -- 처리 순서가 중요하다 — 앵커를 잠깐 풀어야 관절이 rest pose 로 돌아간다.
    do
        -- 1) 들고 있던 Tool 제거. 관 밖으로 튀어나오는 직접 원인이다.
        --    코핀은 끝에서 사망/리스폰으로 이어지므로 파괴해도 안전하다.
        for _, t in ipairs(victimCharacter:GetChildren()) do
            if t:IsA("Tool") then t:Destroy() end
        end

        -- 2) Animate 정지. 살려두면 아래 Transform 초기화를 매 프레임 덮어쓴다.
        --    킹 봇(King npc2)은 서버 Script, 유저는 LocalScript 지만
        --    서버에서 Disabled 를 켜면 클라로 복제되어 멈춘다.
        local animateScript = victimCharacter:FindFirstChild("Animate")
        if animateScript and animateScript:IsA("LuaSourceContainer") then
            animateScript.Disabled = true
        end
        if victimHumanoid then
            local animator = victimHumanoid:FindFirstChildOfClass("Animator")
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    pcall(function() track:Stop(0) end)
                end
            end
        end

        -- 3) 앵커 해제 → Motor6D 를 rest pose(팔 내림 = 차렷)로 → 한 프레임 뒤 아래에서 재앵커.
        --    킹은 spawnBot 에서 BreakJointsOnDeath=false 라 사망 후에도 관절이 살아있다.
        --    러너는 코핀이 사망 전에 불리므로 애초에 관절이 온전하다.
        for _, d in ipairs(victimCharacter:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Anchored = false
            elseif d:IsA("Motor6D") then
                d.Transform = CFrame.new()
            end
        end
        -- 관절이 rest pose 로 이완되려면 물리 솔버가 여러 스텝 돌아야 한다.
        --   ⚠️ Heartbeat 한 번만 기다렸더니 팔이 거의 안 움직였다(실측 2026-08-20:
        --      Motor6D=15 로 관절은 멀쩡했는데도 자세가 굳은 채 유지됨).
        --      앵커된 파트의 CFrame 은 복제되므로, 서버에서 충분히 이완시킨 뒤
        --      앵커하면 그 자세가 그대로 클라에 전달된다.
        --   낙하 위험: 관절이 살아있어 몸이 통째로 유지되고, 0.25초면 ~0.3 stud 수준.
        local RELAX_TIME = 0.25
        local t0 = tick()
        while tick() - t0 < RELAX_TIME do
            game:GetService("RunService").Heartbeat:Wait()
            -- Animate 가 되살아나 다시 포즈를 잡는 걸 막는다
            for _, d in ipairs(victimCharacter:GetDescendants()) do
                if d:IsA("Motor6D") then d.Transform = CFrame.new() end
            end
        end
        -- 실측(2026-08-20): 이 구간에서 RightHand 가 2.23 stud 이동 — 이완 확인됨.
    end

    -- ── 플레이어 앵커 + 정지 ─────────────────────────────────────────────
    if victimHumanoid then
        victimHumanoid.WalkSpeed = 0
        victimHumanoid.JumpPower = 0
    end
    for _, part in ipairs(victimCharacter:GetDescendants()) do
        if part:IsA("BasePart") then
            part.AssemblyLinearVelocity  = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
            part.Anchored   = true
            part.CanCollide = false
        end
    end

    -- ── 방향 계산 ────────────────────────────────────────────────────────
    local lv = root.CFrame.LookVector
    local fx, fz = lv.X, lv.Z
    local flatLen = math.sqrt(fx*fx + fz*fz)
    if flatLen < 0.001 then fx, fz = 0, 1 end
    fx, fz = fx / flatLen, fz / flatLen

    local rotAngle    = math.atan2(-fx, -fz)
    local newLookVec  = Vector3.new(math.sin(rotAngle), 0, math.cos(rotAngle))
    local newRightVec = Vector3.new(-math.cos(rotAngle), 0, math.sin(rotAngle))

    -- ── 사운드 시스템 ───────────────────────────────────────────────────
    -- 컷씬 위치에 sndCore(투명 파트)를 두고, 이 파트의 자식으로 Sound를 생성.
    -- 모든 사운드는 3D positional → 근처 다른 플레이어도 들을 수 있음.
    local sndCore = Instance.new("Part")
    sndCore.Size = Vector3.new(1,1,1); sndCore.Position = position
    sndCore.Anchored = true; sndCore.CanCollide = false
    sndCore.Transparency = 1; sndCore.Parent = workspace
    Debris:AddItem(sndCore, 30)  -- 컷씬 ~18s + 여유

    -- 사운드 ID (직접 업로드한 자산)
    local S_TRIGGER_A = "rbxassetid://128622162873827"   -- 발동 즉시 재생 1
    local S_TRIGGER_B = "rbxassetid://80186384271553"    -- 발동 즉시 재생 2
    local S_PRE_RISE  = "rbxassetid://130089498896083"   -- 관 등장 1초 전 재생

    -- 사운드 헬퍼: 즉시 또는 지연 후 재생
    local function playSnd(soundId, volume, pitch, delaySec)
        task.spawn(function()
            if delaySec and delaySec > 0 then task.wait(delaySec) end
            if not sndCore.Parent then return end
            local snd = Instance.new("Sound")
            snd.SoundId = soundId
            snd.Volume = volume or 2.0
            snd.PlaybackSpeed = pitch or 1.0
            snd.RollOffMaxDistance = 120
            snd.RollOffMinDistance = 5
            snd.Parent = sndCore
            snd:Play()
            Debris:AddItem(snd, 12)
        end)
    end

    -- ── 헬퍼: 연기 생성기 ───────────────────────────────────────────────
    local function makeSmoke(pos, rate, duration)
        local core = Instance.new("Part")
        core.Size = Vector3.new(1,1,1); core.Position = pos
        core.Anchored = true; core.CanCollide = false; core.Transparency = 1; core.Parent = workspace
        local pe = Instance.new("ParticleEmitter")
        pe.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(30,0,50)),
            ColorSequenceKeypoint.new(0.6, Color3.fromRGB(10,0,20)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(0,0,0))
        })
        pe.LightEmission = 0; pe.LightInfluence = 0
        pe.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1.5),
            NumberSequenceKeypoint.new(0.5, 3.5),
            NumberSequenceKeypoint.new(1, 0)
        })
        pe.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(0.7, 0.6),
            NumberSequenceKeypoint.new(1, 1)
        })
        pe.Lifetime = NumberRange.new(1.0, 2.5); pe.Rate = rate
        pe.Speed = NumberRange.new(2, 8); pe.SpreadAngle = Vector2.new(60, 60)
        pe.RotSpeed = NumberRange.new(-45, 45); pe.Parent = core
        task.delay(duration, function()
            if pe.Parent then pe.Enabled = false end
            Debris:AddItem(core, 3)
        end)
        return core, pe
    end

    -- ── 헬퍼: 현재 CFrame 스냅샷 ────────────────────────────────────────
    local function snapParts(character)
        local t = {}
        for _, p in ipairs(character:GetDescendants()) do
            if p:IsA("BasePart") then t[p] = p.CFrame end
        end
        return t
    end

    -- ── 헬퍼: 캐릭터 평행이동 ───────────────────────────────────────────
    -- chain vfx는 캐릭터 파트에 WeldConstraint로 묶여있어 자동으로 따라옴
    local function moveCharacterTo(charSnap, fromPos, toPos, duration)
        local elapsed = 0
        local conn
        conn = RunService.Heartbeat:Connect(function(dt)
            elapsed = math.min(elapsed + dt, duration)
            local ease = elapsed / duration
            ease = ease * ease * (3 - 2 * ease)
            local delta = fromPos:Lerp(toPos, ease) - fromPos
            for part, initCF in pairs(charSnap) do
                if part and part.Parent then part.CFrame = initCF + delta end
            end
            if elapsed >= duration then conn:Disconnect() end
        end)
        task.wait(duration + 0.05)
    end

    local function coffinJob()
        local playerPos  = root.Position
        local groundY    = playerPos.Y - (root.Size.Y * 0.5)  -- 발바닥 Y

        -- ──────────────────────────────────────────────────────────────────
        -- Step1: chain vfx 발밑에 등장 + 파티클 활성화
        -- (chain vfx를 복제해 각 파트를 WeldConstraint로 캐릭터 파트에 부착 →
        --  플레이어가 점프/이동 중이어도 체인 위치가 완벽히 동기화됨)
        -- ──────────────────────────────────────────────────────────────────
        -- 🔊 발동 즉시 재생: 트리거 사운드 2개 동시 + 관 등장 사전 사운드 예약
        playSnd(S_TRIGGER_A, 2.5, 1.0)
        playSnd(S_TRIGGER_B, 2.5, 1.0)
        -- Step2(관 등장)는 Step1(체인 1.8s) 이후라 1초 전 = 0.8s 후에 시작
        playSnd(S_PRE_RISE, 2.5, 1.0, 0.8)
        local chainModel = nil

        if chainTemplate then
            chainModel = chainTemplate:Clone()

            -- 내부 리그 해제 (자체 Motor6D/Humanoid 제거 → 외부 용접과의 충돌 방지)
            for _, desc in ipairs(chainModel:GetDescendants()) do
                if desc:IsA("Motor6D") then
                    desc:Destroy()
                end
            end
            local chainHumanoid = chainModel:FindFirstChildOfClass("Humanoid")
            if chainHumanoid then chainHumanoid:Destroy() end

            -- PrimaryPart 지정 + 캐릭터 위치로 이동
            local chainHRP = chainModel:FindFirstChild("HumanoidRootPart")
            if chainHRP and not chainModel.PrimaryPart then
                chainModel.PrimaryPart = chainHRP
            end
            if chainModel.PrimaryPart then
                chainModel:PivotTo(root.CFrame)
            end

            -- 리그 타입 감지 + chain vfx(R6) → 캐릭터 파트 매핑
            local rigType = victimCharacter:FindFirstChild("UpperTorso") and "r15" or "r6"
            local PART_MAP = {
                ["HumanoidRootPart"] = { r6 = "HumanoidRootPart", r15 = "HumanoidRootPart" },
                ["Head"]             = { r6 = "Head",             r15 = "Head" },
                ["Torso"]            = { r6 = "Torso",            r15 = "UpperTorso" },
                ["Left Arm"]         = { r6 = "Left Arm",         r15 = "LeftLowerArm" },
                ["Right Arm"]        = { r6 = "Right Arm",        r15 = "RightLowerArm" },
                ["Left Leg"]         = { r6 = "Left Leg",         r15 = "LeftLowerLeg" },
                ["Right Leg"]        = { r6 = "Right Leg",        r15 = "RightLowerLeg" },
                ["Effects"]          = { r6 = "Torso",            r15 = "UpperTorso" },
            }

            -- 파티클 초기 비활성화
            for _, part in ipairs(chainModel:GetDescendants()) do
                if part:IsA("ParticleEmitter") then
                    part.Enabled = false
                end
            end

            -- 각 파트를 매칭된 캐릭터 파트에 WeldConstraint로 부착
            for _, chainPart in ipairs(chainModel:GetChildren()) do
                if chainPart:IsA("BasePart") then
                    chainPart.Anchored   = false
                    chainPart.CanCollide = false
                    chainPart.CanQuery   = false
                    chainPart.CanTouch   = false
                    chainPart.Massless   = true

                    local mapping = PART_MAP[chainPart.Name]
                    local targetPart = nil
                    if mapping then
                        local t = victimCharacter:FindFirstChild(mapping[rigType])
                        if t and t:IsA("BasePart") then
                            targetPart = t
                        end
                    end

                    -- 매칭된 파트에 용접, 없으면 root(HRP)에 폴백
                    local weldTo = targetPart or root
                    local weld = Instance.new("WeldConstraint")
                    weld.Part0 = weldTo
                    weld.Part1 = chainPart
                    weld.Parent = chainPart
                end
            end

            chainModel.Parent = workspace

            -- 파티클 순차 활성화 (마법진 등장 연출)
            task.wait(0.1)
            for _, part in ipairs(chainModel:GetDescendants()) do
                if part:IsA("ParticleEmitter") then
                    part.Enabled = true
                end
            end
        end

        task.wait(1.8)  -- 구속 연출 유지

        -- ──────────────────────────────────────────────────────────────────
        -- Step2: 관이 플레이어 뒤쪽 땅 아래에서 올라오며 등장
        --        (등장 중 약간의 검은 연기)
        -- ──────────────────────────────────────────────────────────────────
        local coffinBehindPos = playerPos + newLookVec * 5  -- newLookVec은 등 방향 벡터
        local pivotCF  = CFrame.new(tBottom.Position)
        -- 관의 최종 목표 CFrame (지면 위로 살짝 띄움 → 바닥 이펙트 가시성 확보)
        local COFFIN_LIFT = 2.5  -- 지면 위로 띄우는 높이 (스터드)
        local finalCF  = CFrame.new(coffinBehindPos + Vector3.new(0, COFFIN_LIFT, 0)) * CFrame.Angles(0, rotAngle, 0)
        -- 관의 시작 CFrame (땅 아래 숨겨진 위치)
        local SINK_DEPTH = 20  -- 땅 아래로 숨길 깊이 (스터드) - 관 top이 지면 아래로 확실히 내려가도록
        local startCF  = CFrame.new(coffinBehindPos + Vector3.new(0, COFFIN_LIFT - SINK_DEPTH, 0)) * CFrame.Angles(0, rotAngle, 0)

        local coffin = template:Clone()
        local bottom = coffin:FindFirstChild("CoffinBottom")
        local cover  = coffin:FindFirstChild("CoffinCover")
        local top    = cover and cover:FindFirstChild("CoffinTop")
        if not (bottom and cover and top) then
            coffin:Destroy()
            if chainModel then chainModel:Destroy() end
            endCoffinSequence()  -- 조기 반환 시에도 정리
            return
        end


        -- 관 전체를 시작 위치(땅 아래)에 배치 + 상대 CFrame 스냅샷
        local coffinRelCFs = {}
        for _, part in ipairs(coffin:GetDescendants()) do
            if part:IsA("BasePart") then
                local relCF        = pivotCF:Inverse() * part.CFrame
                part.CFrame        = startCF * relCF
                coffinRelCFs[part] = relCF
                -- 경로 키로 원본 투명도 복원 (중복 이름 충돌 없음)
                local relPath      = getRelPath(coffin, part)
                local orig         = coffinOrigTransparency[relPath]
                part.Transparency  = (orig ~= nil) and orig or 0
                part.Anchored      = true
                part.CanCollide    = false
            end
        end
        coffin.Parent = workspace

        -- 카메라 컷씬 + coffin 레퍼런스 전달 (클라이언트 Emit 루프용)
        if victimPlayer then
            local camPos    = coffinBehindPos - newLookVec * 24 + Vector3.new(0, 9, 0)
            local camLookAt = coffinBehindPos + Vector3.new(0, 3, 0)
            coffinCutsceneEvent:FireClient(victimPlayer, camPos, camLookAt, 22.0, coffin)
        end

        -- 관 등장 연기
        makeSmoke(coffinBehindPos + Vector3.new(0, 1, 0), 60, 2.5)

        -- 관 이동 공용 헬퍼: coffinRelCFs 기반으로 pivot 보간
        local function animateCoffin(fromCF, toCF, duration, easeFn)
            local elapsed = 0
            local conn
            conn = RunService.Heartbeat:Connect(function(dt)
                elapsed = math.min(elapsed + dt, duration)
                local ease  = easeFn(elapsed / duration)
                local curCF = fromCF:Lerp(toCF, ease)
                for part, relCF in pairs(coffinRelCFs) do
                    if part and part.Parent then
                        part.CFrame = curCF * relCF
                    end
                end
                if elapsed >= duration then conn:Disconnect() end
            end)
            task.wait(duration + 0.05)
        end

        -- 올라오기: easeOutCubic (빠르게 솟아오르다 부드럽게 안착)
        animateCoffin(startCF, finalCF, 2.0, function(t) return 1 - math.pow(1 - t, 3) end)


        -- 관이 완전히 올라온 후: 이펙트 활성화 + TimeScale 워밍업
        -- TimeScale을 높게 잠깐 돌려서 파티클을 순간적으로 채운 뒤 정상 속도로 복원
        local particleList = {}
        for _, part in ipairs(coffin:GetDescendants()) do
            if part:IsA("ParticleEmitter") or part:IsA("Fire") or part:IsA("Smoke") then
                part.TimeScale = 20  -- 20배속으로 즉시 채움
                part.Enabled = true
                table.insert(particleList, part)
            end
            if part:IsA("Beam")
            or part:IsA("PointLight") or part:IsA("SurfaceLight") or part:IsA("SpotLight") then
                part.Enabled = true
            end
        end
        -- 한 프레임 기다린 후 정상 속도로 복원
        task.wait(0.1)
        for _, part in ipairs(particleList) do
            if part and part.Parent then
                part.TimeScale = 1
            end
        end

        -- 올라온 후 top/bottom 위치 기록
        local newBottomCF = bottom.CFrame
        local newTopCF    = top.CFrame
        -- top은 뚜껑 트윈이 직접 제어하므로 coffinRelCFs에서 제외
        coffinRelCFs[top] = nil
        task.wait(0.3)

        -- ──────────────────────────────────────────────────────────────────
        -- Step3: 뚜껑 오픈
        -- ──────────────────────────────────────────────────────────────────
        TweenService:Create(top,
            TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {CFrame = newTopCF + newRightVec * 7}
        ):Play()
        task.wait(1.1)

        -- ──────────────────────────────────────────────────────────────────
        -- Step4: 플레이어 + chain vfx 입관
        -- ──────────────────────────────────────────────────────────────────
        -- chain vfx는 캐릭터 파트에 weld되어 있으므로 캐릭터만 이동하면 자동으로 따라옴
        moveCharacterTo(snapParts(victimCharacter), playerPos, bottom.Position, 1.0)

        -- ──────────────────────────────────────────────────────────────────
        -- Step5: chain vfx 소멸 + 뚜껑 닫힘
        -- ──────────────────────────────────────────────────────────────────
        if chainModel then
            for _, part in ipairs(chainModel:GetDescendants()) do
                if part:IsA("ParticleEmitter") then part.Enabled = false end
                if part:IsA("BasePart") then
                    TweenService:Create(part, TweenInfo.new(0.4), {Transparency = 1}):Play()
                end
            end
            Debris:AddItem(chainModel, 0.5)
        end

        TweenService:Create(top,
            TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {CFrame = newTopCF}
        ):Play()
        task.wait(1.1)

        -- 뚜껑이 닫혔으므로 top을 coffinRelCFs에 다시 등록
        -- → Step 7에서 관이 내려갈 때 뚜껑도 bottom과 함께 움직임 (분리 현상 해결)
        coffinRelCFs[top] = finalCF:Inverse() * newTopCF

        -- ──────────────────────────────────────────────────────────────────
        -- Step6: 관에 갇힌 채 한참 정지 (긴장감 연출)
        -- ──────────────────────────────────────────────────────────────────
        task.wait(5.0)

        -- ──────────────────────────────────────────────────────────────────
        -- Step7: 검은 연기 + 관이 천천히 땅 아래로 내려감 (캐릭터도 함께)
        -- ──────────────────────────────────────────────────────────────────
        makeSmoke(newBottomCF.Position, 50, 4.0)

        -- 캐릭터 파트를 coffinRelCFs에 등록 → 관과 함께 내려감
        -- (이 처리가 없으면 관만 내려가고 캐릭터는 지상에 남겨져
        --  플레이어가 먼저 죽은 것처럼 보임)
        for _, part in ipairs(victimCharacter:GetDescendants()) do
            if part:IsA("BasePart") then
                coffinRelCFs[part] = finalCF:Inverse() * part.CFrame
            end
        end

        -- 내려가기: easeInCubic (처음엔 천천히, 점점 빠르게 내려감)
        -- animateCoffin은 내부에서 블록하므로, 끝난 후 사망 처리가 이어짐
        animateCoffin(finalCF, startCF, 4.5, function(t) return t * t * t end)

        -- 하강 완료 후 잠시 대기 (관이 바닥에 완전히 안착한 여운)
        task.wait(1.0)

        -- ──────────────────────────────────────────────────────────────────
        -- Step8: 플레이어 사망 처리 (하강 완전 종료 후)
        --   - 캐릭터 Humanoid는 트리거 시점에 이미 Health=0 (no-op)
        --   - 보류되었던 자동 리스폰을 복구 + 수동 LoadCharacter 호출
        -- ──────────────────────────────────────────────────────────────────
        if victimHumanoid and victimHumanoid.Parent then
            victimHumanoid.Health = 0
        end

        -- 정리: 가로채기 해제 + 숨겨진 캐릭터 제거 + 정식 리스폰
        endCoffinSequence()

        Debris:AddItem(coffin, 0.1)
        print("⚰️ Death Coffin v12 완료")
    end
    -- ⚠️ 직접 task.spawn 금지. 큐에 넣어야 워커(부팅 스레드) 소유가 된다.
    queueFx(coffinJob)

    markEffectBusy(18)  -- 코핀 전체 시퀀스(상승·전시·하강·여운 ≈17초) 보호
    print("⚰️ Death Coffin v12 발동!")
end


_G.SpawnCoffinEffect = function(tagger, victimCharacter, position)
    spawnCoffinEffect(position, victimCharacter)
end

-- ⚠️ [2026-08-28] 처형형(EXECUTION_EFFECTS) 6종은 연출을 queueFx 로 넘긴다.
--   spawnXEffect 내부의 task.spawn 이 호출자 혈통을 물려받는 걸 끊기 위함이다.
--   markEffectBusy 는 큐 밖에서 '동기'로 남긴다 — 라운드 종료 대기가 즉시 걸려야 한다.
_G.SpawnIceFreezeEffect = function(tagger, victimCharacter, position)
	markEffectBusy(8)
	queueFx(function() spawnIceEffect(position, victimCharacter, tagger) end)
end

_G.SpawnWaterPrisonEffect = function(tagger, victimCharacter, position)
	markEffectBusy(8)
	queueFx(function() spawnWaterEffect(position, victimCharacter) end)
end

-- ── 레인보우 킬 이펙트 (rainbow_killparticle 버스트) ──────────
local function spawnRainbowEffect(position, victimCharacter)
    local template = ServerStorage:FindFirstChild("rainbow_killparticle")
    if not template then warn("🌈 rainbow_killparticle을 ServerStorage에서 찾을 수 없습니다!"); return end

    local fx = template:Clone()
    fx.Anchored     = true
    fx.CanCollide   = false
    fx.CastShadow   = false
    fx.Transparency = 1
    fx.CFrame       = CFrame.new(position + Vector3.new(0, 1, 0))   -- 똑바로 세워 중심 배치 (원본 Enabled 상태 그대로 유지)
    fx.Parent = workspace

    -- 사운드 (fx 자식 → 이펙트 사라질 때 fx와 함께 제거되어 같이 끊김)
    local snd = Instance.new("Sound")
    snd.SoundId = "rbxassetid://8482764467"
    snd.Volume = 2.0
    snd.RollOffMaxDistance = 90
    snd.RollOffMinDistance = 5
    snd.Parent = fx
    snd:Play()

    -- 밀도 강화 버스트: Rate를 올려 촘촘하게 + 초기 Emit 펀치 (원본 클론이라 Rate 수정 안전)
    for _, d in ipairs(fx:GetDescendants()) do
        if d:IsA("ParticleEmitter") and d.Enabled then
            local lt = d.Lifetime
            d:Emit(math.clamp(math.floor(d.Rate * ((lt.Min + lt.Max) / 2) * 3), 12, 100))
            d.Rate = d.Rate * 5
        end
    end

    -- 1.3초간 강화 방출 유지(밀도) 후 정지 → 파티클 자연 소멸
    task.delay(1.3, function()
        for _, d in ipairs(fx:GetDescendants()) do
            if d:IsA("ParticleEmitter") or d:IsA("Trail") then d.Enabled = false end
        end
    end)
    task.delay(1.0, function()
        for _, d in ipairs(fx:GetDescendants()) do
            if d:IsA("Sparkles") or d:IsA("PointLight") then d.Enabled = false end
        end
    end)

    Debris:AddItem(fx, 5)
    print("🌈 Rainbow 킬 이펙트 발동! 위치:", position)
end

_G.SpawnRainbowEffect = function(tagger, victimCharacter, position)
	markEffectBusy(8)
    spawnRainbowEffect(position, victimCharacter)
end

-- ── 소드 레인 킬 이펙트 (하늘에서 검이 쏟아져 꽂힘) ──────────
local function spawnSwordRainEffect(position, victimCharacter)
    local template = ServerStorage:FindFirstChild("killeffect_Sword")
    if not template then warn("⚔️ killeffect_Sword을 ServerStorage에서 찾을 수 없습니다!"); return end

    local SWORD_COUNT = 7
    local FALL_HEIGHT = 40
    local RADIUS      = 5
    local groundY     = position.Y - 1.5   -- 대략 발밑 (스샷 보고 조정)

    for i = 1, SWORD_COUNT do
        task.delay((i - 1) * 0.18, function()   -- 스태거드 낙하 (간격 넓혀 타격음 구분)
            local sword = template:Clone()
            sword.PrimaryPart = sword:FindFirstChild("blade")   -- 검날 기준 pivot
            if not sword.PrimaryPart then sword:Destroy(); return end
            for _, p in ipairs(sword:GetDescendants()) do
                if p:IsA("BasePart") then p.Anchored = true; p.CanCollide = false; p.CastShadow = false end
            end

            local ang  = math.random() * math.pi * 2
            local r    = math.random() * RADIUS
            local tx   = position.X + math.cos(ang) * r
            local tz   = position.Z + math.sin(ang) * r
            local yaw  = math.random() * math.pi * 2
            local tilt = math.rad(math.random(-12, 12))
            -- 검끝 아래로 (X축 180° = 추정. 위아래 뒤집혔으면 이 각도만 바꿈)
            local rot     = CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(180), 0, 0) * CFrame.Angles(tilt, 0, 0)
            local startCF = CFrame.new(tx, groundY + FALL_HEIGHT, tz) * rot
            local endCF   = CFrame.new(tx, groundY, tz) * rot
            sword:PivotTo(startCF)
            sword.Parent = workspace

            local dur, elapsed = 0.22, 0
            local conn
            conn = RunService.Heartbeat:Connect(function(dt)
                elapsed = math.min(elapsed + dt, dur)
                local a = (elapsed / dur) ^ 2   -- easeIn 가속 낙하
                sword:PivotTo(startCF:Lerp(endCF, a))
                if elapsed >= dur then
                    conn:Disconnect()
                    -- 꽂히는 순간 검마다 사운드 (3D positional)
                    local hit = Instance.new("Part")
                    hit.Size = Vector3.new(1,1,1); hit.Position = Vector3.new(tx, groundY, tz)
                    hit.Anchored = true; hit.CanCollide = false; hit.Transparency = 1; hit.CastShadow = false
                    hit.Parent = workspace
                    local snd = Instance.new("Sound")
                    snd.SoundId = "rbxassetid://127362823754161"
                    snd.Volume = 2.2
                    snd.RollOffMaxDistance = 100
                    snd.RollOffMinDistance = 5
                    snd.PlaybackSpeed = math.random(72, 82) / 100   -- 피치 낮춰 묵직하게 (+겹칠 때 변주)
                    -- 저음 강조 이퀄라이저 (무게감)
                    local eq = Instance.new("EqualizerSoundEffect")
                    eq.LowGain = 8
                    eq.MidGain = 0
                    eq.HighGain = -6
                    eq.Parent = snd
                    snd.Parent = hit
                    snd:Play()
                    Debris:AddItem(hit, 2.5)
                end
            end)
            Debris:AddItem(sword, 3.5)   -- 꽂힌 채 잠깐 있다 제거
        end)
    end
    print("⚔️ Sword Rain 발동! 위치:", position)
end

_G.SpawnSwordRainEffect = function(tagger, victimCharacter, position)
	markEffectBusy(8)
    spawnSwordRainEffect(position, victimCharacter)
end

-- ── 헬파이어 킬 이펙트 (흑염 지옥불 폭발) ──────────
local function spawnHellfireEffect(position, victimCharacter)
    local template = ServerStorage:FindFirstChild("Hellfire")
    if not template then warn("😈 Hellfire을 ServerStorage에서 찾을 수 없습니다!"); return end

    local fx = template:Clone()
    fx.Anchored     = true
    fx.CanCollide   = false
    fx.CastShadow   = false
    fx.Transparency = 1
    fx.CFrame       = CFrame.new(position + Vector3.new(0, -2.5, 0))   -- 발밑 (Top 방출이라 위로 솟음)
    fx.Parent = workspace

    -- 불 버스트: Emit 펀치 + Rate 강화 (Rainbow 패턴)
    for _, d in ipairs(fx:GetDescendants()) do
        if d:IsA("ParticleEmitter") and d.Enabled then
            local lt = d.Lifetime
            d.EmissionDirection = Enum.NormalId.Top   -- 위로 방출 (불기둥/폭발)
            d:Emit(math.clamp(math.floor(d.Rate * ((lt.Min + lt.Max) / 2) * 2), 20, 120))
            d.Rate = d.Rate * 3
        end
    end

    -- 지옥 발광 (붉은 PointLight → 페이드)
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 70, 20)
    light.Brightness = 8
    light.Range = 18
    light.Shadows = false
    light.Parent = fx
    game:GetService("TweenService"):Create(light, TweenInfo.new(1.5, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()

    -- 사운드 (불 whoosh, 낮은 피치로 묵직한 지옥불)
    local snd = Instance.new("Sound")
    snd.SoundId = "rbxassetid://75422951"   -- 교체된 사운드
    snd.Volume = 2.5
    snd.PlaybackSpeed = 0.75
    snd.RollOffMaxDistance = 100
    snd.RollOffMinDistance = 5
    snd.Parent = fx
    snd:Play()

    -- 1.0초 강화 방출 후 정지 → 자연 소멸
    task.delay(1.0, function()
        for _, d in ipairs(fx:GetDescendants()) do
            if d:IsA("ParticleEmitter") then d.Enabled = false end
        end
    end)

    Debris:AddItem(fx, 4)
    print("😈 Hellfire 킬 이펙트 발동! 위치:", position)
end

_G.SpawnHellfireEffect = function(tagger, victimCharacter, position)
	markEffectBusy(8)
    spawnHellfireEffect(position, victimCharacter)
end

-- ── Glitch Kill (victim 제어형: 사체 지지직 + 페이드, 리스폰 미터치) ──
-- Fire/Lightning 버스트와 달리 victim의 죽은 몸을 ~2초간 글리치 후 사라지게 함.
-- RespawnTime(3s) > 이펙트(~2.1s)라 자동 리스폰이 자연 흐름으로 이어짐 → LoadCharacter 안 부름.
local function spawnGlitchEffect(position, victimCharacter)
	if not victimCharacter then return end

	local template = ServerStorage:FindFirstChild("glitch effect")
	if not template then warn("[GlitchFX] 'glitch effect' 템플릿 없음 (ServerStorage)"); return end

	local victimHumanoid = victimCharacter:FindFirstChildOfClass("Humanoid")
	local root = victimCharacter:FindFirstChild("HumanoidRootPart")
		or victimCharacter:FindFirstChild("Torso")
		or victimCharacter:FindFirstChild("UpperTorso")
	if not root then warn("[GlitchFX] root 없음"); return end

	-- 사체 고정 (코핀 앵커 블록 재활용)
	if victimHumanoid then
		victimHumanoid.WalkSpeed = 0
		victimHumanoid.JumpPower = 0
	end
	for _, part in ipairs(victimCharacter:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity  = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
			part.Anchored   = true
			part.CanCollide = false
		end
	end

	-- 투명도 조작 대상(원본 보이던 파트) 수집 — fx 파트 붙이기 전에 먼저
	-- 🎭 [2026-08-30] Decal/Texture 도 함께 모은다.
	--   [증상] 킹이 죽으면 몸은 사라지는데 얼굴만 공중에 잠시 남았다.
	--   [원인] BasePart.Transparency = 1 은 그 파트에 붙은 Decal 을 숨기지 않는다.
	--     Decal 은 자기 Transparency 를 따로 갖는다. 파트만 훑으면 얼굴이 그대로 남는다.
	--     킹은 티어별 얼굴(easy_normal_face / hard_face)을 Decal 투명도로 전환하므로
	--     특히 눈에 띈다(TaggerBotSystem:156).
	--   ⚠️ 같은 파일 512행·893행은 이미 이 짝을 지키고 있다. 여기만 빠져 있었다.
	--   ⚠️ 앞으로 캐릭터를 숨기는 코드를 쓸 때 BasePart 만 훑지 말 것.
	local bodyParts = {}
	local bodyDecals = {}
	for _, part in ipairs(victimCharacter:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			bodyParts[#bodyParts+1] = part
		elseif (part:IsA("Decal") or part:IsA("Texture")) and part.Transparency < 1 then
			bodyDecals[#bodyDecals+1] = part
		end
	end
	local function setBodyTransparency(t)
		for _, p in ipairs(bodyParts) do
			p.Transparency = t
		end
		for _, d in ipairs(bodyDecals) do
			d.Transparency = t
		end
	end

	-- 글리치 파티클 파트 부착 (torso에 앵커, 사체가 정지 상태라 weld 불필요)
	-- tiled vertically to cover full body incl. legs
	local minY, maxY = math.huge, -math.huge
	for _, p in ipairs(bodyParts) do
		local h = p.Size.Y * 0.5
		if p.Position.Y - h < minY then minY = p.Position.Y - h end
		if p.Position.Y + h > maxY then maxY = p.Position.Y + h end
	end
	if minY == math.huge then minY, maxY = root.Position.Y - 2.5, root.Position.Y + 2.5 end
	local bodyHeight = maxY - minY
	local tileH = template.Size.Y
	local nTiles = math.max(1, math.ceil(bodyHeight / tileH))
	local rootRot = root.CFrame - root.CFrame.Position
	local DENSITY_MULT = 0.5  -- 타일당 파티클 Rate 배율 (낮출수록 옅음)
	local fxParts = {}
	for i = 1, nTiles do
		local frac = (nTiles == 1) and 0.5 or (i - 0.5) / nTiles
		local y = minY + bodyHeight * frac
		local clone = template:Clone()
		clone.Anchored = true
		clone.CanCollide = false
		clone.Transparency = 1
		clone.CFrame = CFrame.new(root.Position.X, y, root.Position.Z) * rootRot
		clone.Parent = victimCharacter
		for _, e in ipairs(clone:GetDescendants()) do
			if e:IsA("ParticleEmitter") then
				e.Rate = e.Rate * DENSITY_MULT
				e.Enabled = true
			end
		end
		fxParts[#fxParts + 1] = clone
	end

	-- 사운드 (3D positional)
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://140043289814504"
	snd.Volume  = 1
	snd.RollOffMaxDistance = 80
	snd.Parent  = root
	snd:Play()

	-- 연출: 지지직 깜빡임 ~1.5s → 페이드아웃 ~0.6s
	task.spawn(function()
		local BLINK_TIME = 1.5
		local BLINK_INT  = 0.06
		local t0 = os.clock()
		while os.clock() - t0 < BLINK_TIME do
			setBodyTransparency(0)
			task.wait(BLINK_INT)
			setBodyTransparency(0.55)
			task.wait(BLINK_INT)
		end
		local FADE_TIME = 0.6
		local f0 = os.clock()
		while true do
			local a = (os.clock() - f0) / FADE_TIME
			if a >= 1 then break end
			setBodyTransparency(0.55 + 0.45 * a)  -- 0.55 → 1
			task.wait()
		end
		setBodyTransparency(1)

		-- 👻 [2026-08-30] 투명해졌으면 충돌도 꺼야 한다.
		--   [증상] 글리치로 죽은 킹 자리에 안 보이는 벽이 남아 러너가 걸렸다.
		--   [원인] 이 연출은 투명도만 조작하고 CanCollide 를 안 건드렸다.
		--     사체는 그대로 물리 객체로 남아 있었다.
		--   ⚠️ "보이지 않으면 만져지지도 않아야 한다" — 투명화와 충돌 해제는 한 짝이다.
		--   ⚠️ CanQuery 도 끈다. 안 그러면 태거 조준 레이캐스트가 유령을 맞춘다
		--     (아이템 청사진이 허공에 달라붙는 증상의 원인이 된다).
		--   ⚠️ 사체를 Destroy 하지는 않는다. 리스폰·관전 등이 캐릭터 참조를 들고 있을 수 있고,
		--     이 연출은 "리스폰 미터치"가 전제다(상단 주석). 통과만 시킨다.
		if victimCharacter and victimCharacter.Parent then
			for _, p in ipairs(victimCharacter:GetDescendants()) do
				if p:IsA("BasePart") then
					p.CanCollide = false
					p.CanQuery   = false
					p.CanTouch   = false
				end
			end
		end
		for _, fxp in ipairs(fxParts) do
			for _, e in ipairs(fxp:GetDescendants()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
		end
	end)

	for _, fxp in ipairs(fxParts) do Debris:AddItem(fxp, 4) end
	Debris:AddItem(snd, 4)
	print("[GlitchFX] Glitch 킬 이펙트 발동! 위치:", position)
end

_G.SpawnGlitchEffect = function(tagger, victimCharacter, position)
	markEffectBusy(8)
	spawnGlitchEffect(position, victimCharacter)
end

-- ── Tornado Kill (victim 제어형: 상승-회전 후 사출 래그돌, 리스폰 미터치) ──
-- 토네이도 VFX가 사망 지점에 뜨고, victim이 빙빙 돌며 위로 빨려 올라간 뒤 바깥으로 사출됨.
-- RespawnTime(3s) 안에 끝나 자동 리스폰이 날아간 사체를 대체 → LoadCharacter 안 부름.
local function spawnTornadoEffect(position, victimCharacter)
	if not victimCharacter then return end

	local RunService = game:GetService("RunService")
	local template = ServerStorage:FindFirstChild("Tornadofx") or workspace:FindFirstChild("Tornadofx")
	if not template then warn("[TornadoFX] 'Tornadofx' 템플릿 없음"); return end

	local humanoid = victimCharacter:FindFirstChildOfClass("Humanoid")
	local hrp = victimCharacter:FindFirstChild("HumanoidRootPart")
		or victimCharacter:FindFirstChild("Torso")
		or victimCharacter:FindFirstChild("UpperTorso")
	if not hrp then warn("[TornadoFX] hrp 없음"); return end

	-- 튜닝 노브
	local LIFT_TIME  = 0.9   -- 상승-회전 시간(s)
	local LIFT_SPEED = 24    -- 상승 속도(studs/s)
	local SPIN_Y     = 20    -- 빙빙 스핀(rad/s, Y축)
	local EJECT_OUT  = 55    -- 사출 수평 세기
	local EJECT_UP   = 45    -- 사출 상승 세기

	-- 래그돌 준비 (PlatformStand + 언앵커 + 서버 소유)
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end
	for _, p in ipairs(victimCharacter:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false end
	end
	pcall(function() hrp:SetNetworkOwner(nil) end)

	-- 토네이도 VFX (사망 지점 지면 근처에 고정)
	local fx = template:Clone()
	fx.Anchored   = true
	fx.CanCollide = false
	fx.CFrame     = CFrame.new(hrp.Position.X, position.Y - 3, hrp.Position.Z)
	fx.Parent     = workspace
	for _, e in ipairs(fx:GetDescendants()) do
		if e:IsA("ParticleEmitter") then e.Enabled = true end
	end

	-- 사운드 (3D positional, 토네이도 위치)
	local snd = Instance.new("Sound")
	snd.SoundId = "rbxassetid://138466406484615"
	snd.Volume  = 1
	snd.RollOffMaxDistance = 120
	snd.Parent  = fx
	snd:Play()
	Debris:AddItem(snd, 4)

	-- 상승-회전 페이즈 → 사출
	local t0 = os.clock()
	local ejected = false
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not hrp or not hrp.Parent then
			if conn then conn:Disconnect(); conn = nil end
			return
		end
		local elapsed = os.clock() - t0
		if elapsed < LIFT_TIME then
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity  = Vector3.new(v.X * 0.55, LIFT_SPEED, v.Z * 0.55)
			hrp.AssemblyAngularVelocity = Vector3.new(math.random(-5, 5), SPIN_Y, math.random(-5, 5))
		else
			if not ejected then
				ejected = true
				local dir = Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))
				if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0.5) end
				dir = dir.Unit
				hrp.AssemblyLinearVelocity  = dir * EJECT_OUT + Vector3.new(0, EJECT_UP, 0)
				hrp.AssemblyAngularVelocity = Vector3.new(math.random(-14, 14), SPIN_Y, math.random(-14, 14))
			end
			if conn then conn:Disconnect(); conn = nil end
		end
	end)

	-- VFX 페이드/정리
	task.delay(1.5, function()
		if fx and fx.Parent then
			for _, e in ipairs(fx:GetDescendants()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
		end
	end)
	Debris:AddItem(fx, 4)
	print("[TornadoFX] Tornado 킬 이펙트 발동! 위치:", position)
end

_G.SpawnTornadoEffect = function(tagger, victimCharacter, position)
	markEffectBusy(8)
	queueFx(function() spawnTornadoEffect(position, victimCharacter) end)
end

-- ── Portal Kill (victim 제어형 / 처형 모델: 아공간 포탈로 빨려들어가며 투명화 후 사망) ──
-- 죽는 순간 앞쪽에 포탈이 열리고, 몸이 포탈로 슬라이드되며 포탈에 가까운 파트부터 투명해짐.
-- 사망은 호출한 executionHandler의 killCharacter가 처리 (여기선 연출만).
local function spawnPortalEffect(position, victimCharacter)
	if not victimCharacter then return end

	local RunService = game:GetService("RunService")
	local template = ServerStorage:FindFirstChild("Portalfx") or workspace:FindFirstChild("Portalfx")
	if not template then warn("[PortalFX] 'Portalfx' 템플릿 없음"); return end

	local humanoid = victimCharacter:FindFirstChildOfClass("Humanoid")
	local hrp = victimCharacter:FindFirstChild("HumanoidRootPart")
		or victimCharacter:FindFirstChild("Torso")
		or victimCharacter:FindFirstChild("UpperTorso")
	if not hrp then warn("[PortalFX] hrp 없음"); return end

	-- 튜닝 노브
	local PORTAL_DIST = 5.0   -- 앞쪽 포탈 거리(stud)
	local SUCK_TIME   = 1.3   -- 빨려들어가는 시간(s)
	local FADE_RADIUS = 6.0   -- 포탈 중심 이 반경 안 파트는 투명해짐
	local PORTAL_SCALE = 3.0  -- 파티클 크기 배율 (포탈 크게)
	local PORTAL_RISE  = 8.0  -- 지면에서 포탈 중심 높이 (떠있게)

	if humanoid then humanoid.WalkSpeed = 0; humanoid.JumpPower = 0 end

	-- 시작 상태 + 포탈 위치 (앞쪽 수평, victim 향함)
	local startCF = hrp.CFrame
	local rot = startCF - startCF.Position
	local lv = startCF.LookVector
	local flat = Vector3.new(lv.X, 0, lv.Z)
	if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, 1) end
	flat = flat.Unit
	-- 지면 raycast → 포탈은 지면 위 PORTAL_RISE 높이에 떠있게
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { victimCharacter }
	local rayResult = workspace:Raycast(startCF.Position, Vector3.new(0, -60, 0), rp)
	local groundY = rayResult and rayResult.Position.Y or (startCF.Position.Y - 3)
	local frontXZ = startCF.Position + flat * PORTAL_DIST
	local portalPos = Vector3.new(frontXZ.X, groundY + PORTAL_RISE, frontXZ.Z)
	local portalCF  = CFrame.lookAt(portalPos, Vector3.new(startCF.Position.X, portalPos.Y, startCF.Position.Z))

	-- Portalfx 배치
	local fx = template:Clone()
	fx.Anchored = true
	fx.CanCollide = false
	fx.CFrame = portalCF
	fx.Parent = workspace

	-- 🔊 차원문 개방음: 포탈 위치에서 3D 재생 (근처 플레이어도 들림)
	do
		local sndCore = Instance.new("Part")
		sndCore.Size = Vector3.new(1,1,1); sndCore.Position = portalPos
		sndCore.Anchored = true; sndCore.CanCollide = false; sndCore.Transparency = 1
		sndCore.Parent = workspace
		local s = Instance.new("Sound")
		s.SoundId = SFX_PORTAL; s.Volume = 3.0
		s.RollOffMinDistance = 25; s.RollOffMaxDistance = 140
		s.PlaybackSpeed = math.random(94,106)/100
		s.Parent = sndCore; s:Play()
		-- 흡입 지속음(우주적 저역 드론): 개방음과 동시에 시작해 빨려드는 1.3초를 채운다.
		local suck = Instance.new("Sound")
		suck.SoundId = SFX_PORTAL_SUCK; suck.Volume = 2.6
		suck.RollOffMinDistance = 25; suck.RollOffMaxDistance = 160
		suck.Parent = sndCore; suck:Play()
		-- 연출 종료(1.65s)에 맞춰 페이드아웃 — 음원이 더 길어도 뚝 끊기지 않게
		task.delay(1.35, function()
			if suck.Parent then
				game:GetService("TweenService"):Create(suck, TweenInfo.new(0.5), {Volume = 0}):Play()
			end
		end)
		Debris:AddItem(sndCore, 6)
	end
	local function scaleSize(seq, f)
		local kps = {}
		for _, kp in ipairs(seq.Keypoints) do
			kps[#kps + 1] = NumberSequenceKeypoint.new(kp.Time, kp.Value * f, kp.Envelope * f)
		end
		return NumberSequence.new(kps)
	end
	for _, e in ipairs(fx:GetDescendants()) do
		if e:IsA("ParticleEmitter") then
			e.Size = scaleSize(e.Size, PORTAL_SCALE)
			e.Enabled = true
			e:Emit(math.max(1, math.ceil(e.Rate * (e.Lifetime.Max or 1))))  -- 즉시 채워 빨리 나타남
		end
	end

	-- 사체 고정 + 원본 투명도 저장
	for _, p in ipairs(victimCharacter:GetDescendants()) do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
			p.Anchored = true
			p.CanCollide = false
		end
	end
	local bodyParts = {}
	for _, p in ipairs(victimCharacter:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			bodyParts[#bodyParts+1] = { part = p, orig = p.Transparency }
		end
	end

	-- 빨려들어가기: 몸을 포탈로 슬라이드 + 파트별 거리 페이드
	task.spawn(function()
		local t0 = os.clock()
		while true do
			local a = (os.clock() - t0) / SUCK_TIME
			if a >= 1 then break end
			local eased = a * a  -- 가속하며 빨려들어감
			local curPos = startCF.Position:Lerp(portalPos, eased)
			victimCharacter:PivotTo(CFrame.new(curPos) * rot)
			for _, rec in ipairs(bodyParts) do
				local d = (rec.part.Position - portalPos).Magnitude
				local ft = math.clamp(1 - d / FADE_RADIUS, 0, 1)
				rec.part.Transparency = rec.orig + (1 - rec.orig) * ft
			end
			task.wait()
		end
		for _, rec in ipairs(bodyParts) do rec.part.Transparency = 1 end
	end)

	-- 포탈 닫기 + 정리
	task.delay(SUCK_TIME + 0.35, function()
		if fx and fx.Parent then
			for _, e in ipairs(fx:GetDescendants()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
		end
	end)
	Debris:AddItem(fx, 4)
	print("[PortalFX] Portal 킬 이펙트 발동! 위치:", position)
end

_G.SpawnPortalEffect = function(tagger, victimCharacter, position)
	markEffectBusy(8)
	queueFx(function() spawnPortalEffect(position, victimCharacter) end)
end

-- ── EMP Kill (버스트형: 사망 지점에서 EMP 필드가 작게 시작해 점점 커지는 원으로 확산) ──
-- victim을 안 건드리는 버스트라 처형 모델 X → 사망 시점(onKill)에 위치만 받아 발동.
local function spawnEmpEffect(position)
	local template = ServerStorage:FindFirstChild("empfieldfx") or workspace:FindFirstChild("empfieldfx")
	if not template then warn("[EmpFX] 'empfieldfx' 템플릿 없음"); return end

	-- 튜닝 노브
	local EXPAND_TIME = 0.7   -- 작은→큰으로 커지는 시간(s)
	local SIZE_START  = 0.3   -- 크기 배율 시작 (작게)
	local SIZE_END    = 1.5   -- 크기 배율 최종 (크게, arc 유지)
	local HOLD_TIME   = 0.35  -- 최대 크기 유지 후 소멸(s)
	local DENSITY     = 6     -- 방출 밀도 배율 (짧은 시간에도 촘촘한 arc-sphere)

	local fx = template:Clone()
	fx.Anchored = true
	fx.CanCollide = false
	fx.CFrame = CFrame.new(position)
	fx.Parent = workspace

	-- 원본 config(연속방출 Rate/Speed/Orientation/Transparency) 그대로 유지 → arc-sphere 렌더.
	-- Size 배율만 시간에 따라 램프해서 확산 (Emit 방식은 이 emitter에서 안 보여서 연속방출로).
	local emitters = {}
	for _, e in ipairs(fx:GetDescendants()) do
		if e:IsA("ParticleEmitter") then
			emitters[#emitters + 1] = { emitter = e, base = e.Size }
			e.Rate = e.Rate * DENSITY
			e.Enabled = true
		end
	end
	local function applyScale(f)
		for _, rec in ipairs(emitters) do
			local kps = {}
			for _, kp in ipairs(rec.base.Keypoints) do
				kps[#kps + 1] = NumberSequenceKeypoint.new(kp.Time, kp.Value * f, kp.Envelope * f)
			end
			rec.emitter.Size = NumberSequence.new(kps)
		end
	end
	applyScale(SIZE_START)

	task.spawn(function()
		local t0 = os.clock()
		while true do
			local a = (os.clock() - t0) / EXPAND_TIME
			if a >= 1 then break end
			local eased = 1 - (1 - a) * (1 - a)  -- ease-out
			applyScale(SIZE_START + (SIZE_END - SIZE_START) * eased)
			task.wait()
		end
		applyScale(SIZE_END)
		task.wait(HOLD_TIME)
		for _, rec in ipairs(emitters) do rec.emitter.Enabled = false end
	end)

	Debris:AddItem(fx, EXPAND_TIME + HOLD_TIME + 2.0)
	print("[EmpFX] EMP 킬 이펙트 발동! 위치:", position)
end

_G.SpawnEmpEffect = function(tagger, victimCharacter, position)
	markEffectBusy(8)
	spawnEmpEffect(position)
end

-- ── Grave Kill (버스트형: 위에서 비석 쿵 낙하 + ghost 아래→위 승천 페이드아웃) ──
local function spawnGraveEffect(position, victimCharacter, killer)
	local template = ServerStorage:FindFirstChild("Grave") or workspace:FindFirstChild("Grave")
	if not template then warn("[GraveFX] 'Grave' 템플릿 없음"); return end

	local graveModel = template:FindFirstChild("Grave")  -- 비석 모델
	local ghostUnion = template:FindFirstChild("ghost")  -- ghost union

	-- 튜닝 노브
	local GRAVE_SCALE = 1.3   -- 비석 크기 배율
	local FALL_HEIGHT = 28    -- 비석 낙하 시작 높이
	local FALL_TIME   = 0.32  -- 낙하 시간
	local RISE        = 9     -- ghost 승천 높이
	local RISE_TIME   = 1.6   -- ghost 승천/페이드 시간

	-- 지면 raycast: 플레이어/NPC/Tool(무기·아이템) 무시하고 지형에만 착지 (만나면 제외 후 재발사)
	local function nonTerrainTarget(inst)
		local tool = inst:FindFirstAncestorWhichIsA("Tool")
		if tool then return tool end
		local a = inst
		while a and a ~= workspace do
			if a:IsA("Model") and a:FindFirstChildOfClass("Humanoid") then return a end
			a = a.Parent
		end
		return nil  -- 지형
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	local origin = position + Vector3.new(0, 3, 0)
	local groundY
	for _ = 1, 10 do
		rp.FilterDescendantsInstances = exclude
		local ray = workspace:Raycast(origin, Vector3.new(0, -120, 0), rp)
		if not ray then break end
		local skip = nonTerrainTarget(ray.Instance)
		if not skip then groundY = ray.Position.Y; break end
		exclude[#exclude + 1] = skip
	end
	groundY = groundY or (position.Y - 2.5)

	-- ghost 승천 (비석 착지 후 호출)
	local function startGhost()
		if not ghostUnion then return end
		local ghost = ghostUnion:Clone()
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.CastShadow = false
		ghost.Transparency = 0
		local sx, sz = position.X, position.Z
		ghost.CFrame = CFrame.new(sx, groundY, sz)
		ghost.Parent = workspace
		task.spawn(function()
			local t0 = os.clock()
			while true do
				local a = (os.clock() - t0) / RISE_TIME
				if a >= 1 then break end
				ghost.CFrame = CFrame.new(sx, groundY + RISE * a, sz)
				ghost.Transparency = a
				for _, d in ipairs(ghost:GetDescendants()) do
					if d:IsA("Decal") then d.Transparency = a end
				end
				RunService.Heartbeat:Wait()
			end
			ghost.Transparency = 1
		end)
		Debris:AddItem(ghost, 2.2)
	end

	-- ── 비석 낙하 → 착지 후 유령 승천 ──
	if graveModel then
		local grave = graveModel:Clone()
		local union = grave:FindFirstChild("Grave")
		if union then grave.PrimaryPart = union end
		grave:ScaleTo(GRAVE_SCALE)  -- 크기 키우기
		for _, p in ipairs(grave:GetDescendants()) do
			if p:IsA("BasePart") then p.Anchored = true; p.CanCollide = false end
		end
		-- pivot → 바닥 오프셋(스케일 후) → 바닥이 지면에 정확히 닿게
		local cf, size = grave:GetBoundingBox()
		local pivotToBottom = grave:GetPivot().Position.Y - (cf.Position.Y - size.Y / 2)
		-- 데칼 큰 면(Right/Left)이 킬러를 향하게 회전 (킬러 없으면 원본 회전)
		local baseCF
		local kchar = killer and killer.Character
		local kroot = kchar and (kchar:FindFirstChild("HumanoidRootPart") or kchar.PrimaryPart)
		if kroot then
			local d = kroot.Position - position
			d = Vector3.new(d.X, 0, d.Z)
			if d.Magnitude > 0.1 then
				baseCF = CFrame.fromMatrix(
					Vector3.new(position.X, groundY + pivotToBottom, position.Z),
					d.Unit, Vector3.new(0, -1, 0))
			end
		end
		baseCF = baseCF or (CFrame.new(position.X, groundY + pivotToBottom, position.Z) * grave:GetPivot().Rotation)
		local startCF = baseCF + Vector3.new(0, FALL_HEIGHT, 0)
		grave:PivotTo(startCF)
		grave.Parent = workspace

		local elapsed = 0
		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			elapsed = math.min(elapsed + dt, FALL_TIME)
			local a = (elapsed / FALL_TIME) ^ 2  -- easeIn 가속 낙하
			grave:PivotTo(startCF:Lerp(baseCF, a))
			if elapsed >= FALL_TIME then
				conn:Disconnect()
				-- 쿵 (묵직한 착지음)
				local hit = Instance.new("Part")
				hit.Size = Vector3.new(1, 1, 1)
				hit.Position = Vector3.new(position.X, groundY, position.Z)
				hit.Anchored = true; hit.CanCollide = false; hit.Transparency = 1; hit.CastShadow = false
				hit.Parent = workspace
				local snd = Instance.new("Sound")
				snd.SoundId = "rbxassetid://127362823754161"
				snd.Volume = 2.5
				snd.RollOffMaxDistance = 110
				snd.PlaybackSpeed = 0.7
				local eq = Instance.new("EqualizerSoundEffect")
				eq.LowGain = 10; eq.MidGain = 0; eq.HighGain = -6
				eq.Parent = snd
				snd.Parent = hit
				snd:Play()
				Debris:AddItem(hit, 2.5)
				startGhost()  -- 착지 후 유령 승천 시작
			end
		end)
		Debris:AddItem(grave, 4.0)
	else
		startGhost()
	end

	print("[GraveFX] Grave 킬 이펙트 발동! 위치:", position)
end

_G.SpawnGraveEffect = function(tagger, victimCharacter, position)
	markEffectBusy(8)
	spawnGraveEffect(position, victimCharacter, tagger)
end

-- ── Punch Kill (victim 제어형 / 처형: 킬러 외형 더미가 나타나 마구 때린 뒤 멀리 날려 사망) ──
local function spawnPunchEffect(position, victimCharacter, killer)
	if not victimCharacter then return end
	local killerChar = killer and killer.Character
	if not killerChar then warn("[PunchFX] 킬러 캐릭터 없음"); return end

	local vHum = victimCharacter:FindFirstChildOfClass("Humanoid")
	local vRoot = victimCharacter:FindFirstChild("HumanoidRootPart")
		or victimCharacter:FindFirstChild("Torso") or victimCharacter:FindFirstChild("UpperTorso")
	if not vHum or not vRoot then return end

	-- 튜닝 노브
	local PUNCH_TIME = 3.0   -- 때리는 시간(s) — 애니 약 2회 반복
	local FRONT_DIST = 3.5   -- 더미가 victim 앞 거리(stud)
	local KNOCK_BACK = 130   -- 뒤로 날리는 힘
	local KNOCK_UP   = 60    -- 위로 날리는 힘

	-- victim 홀드 (살아있는 몸 정지)
	vHum.PlatformStand = true
	vHum.WalkSpeed = 0
	vHum.JumpPower = 0
	for _, p in ipairs(victimCharacter:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true end
	end

	-- 킬러 외형 복제 더미 (도구/스크립트/creator 제거)
	local wasArch = killerChar.Archivable
	killerChar.Archivable = true
	local dummy = killerChar:Clone()
	killerChar.Archivable = wasArch
	if not dummy then warn("[PunchFX] 복제 실패"); return end
	dummy.Name = "_PunchDummy"
	for _, d in ipairs(dummy:GetDescendants()) do
		if d:IsA("Tool") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d.Name == "creator" then
			d:Destroy()
		end
	end
	local dHum = dummy:FindFirstChildOfClass("Humanoid")
	if not dHum then dummy:Destroy(); return end
	pcall(function() dHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end)
	local animator = dHum:FindFirstChildOfClass("Animator") or Instance.new("Animator", dHum)

	-- victim 정면 앞에 배치 + victim 바라봄. HRP만 앵커(림은 애니로 움직이게)
	local vcf = vRoot.CFrame
	local flat = Vector3.new(vcf.LookVector.X, 0, vcf.LookVector.Z)
	if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, 1) end
	flat = flat.Unit
	local dPos = vRoot.Position + flat * FRONT_DIST
	dummy:PivotTo(CFrame.lookAt(Vector3.new(dPos.X, vRoot.Position.Y, dPos.Z), vRoot.Position))
	-- ⚠️ [2026-08-28] 더미는 '순수 연출' 이다. 물리·판정에서 완전히 빼낸다.
	--   [증상] 쓰나미가 _PunchDummy 를 러너로 보고 ragdoll 시켰다(실측 11:39:14.392).
	--     CanCollide=false 만으로는 공간 질의(OverlapParams·GetPartBoundsInRadius)와
	--     Touched 가 그대로 살아 있어 다른 시스템이 계속 대상으로 잡는다.
	--   [3겹 — 셋 다 필요하다. 하나만 끄면 다른 경로로 다시 잡힌다]
	--     · CanQuery=false : 공간 질의·레이캐스트에서 제외 (쓰나미·블랙홀·폭탄 등)
	--     · CanTouch=false : Touched 기반 히트박스에서 제외
	--     · NoTarget 속성  : processHit 파이프라인 전체 + 모델 스캔형(SpearSystem:280) 제외
	dummy:SetAttribute("NoTarget", true)
	for _, p in ipairs(dummy:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery   = false
			p.CanTouch   = false
			p.Massless   = true
			p.Anchored   = false
		end
	end
	local dRoot = dummy:FindFirstChild("HumanoidRootPart")
	if dRoot then dRoot.Anchored = true end
	dummy.Parent = workspace

	-- 펀치 애니 (R6/R15 분기)
	local anim = Instance.new("Animation")
	anim.AnimationId = (dHum.RigType == Enum.HumanoidRigType.R6)
		and "rbxassetid://72437207295411" or "rbxassetid://103901383724467"
	local track
	pcall(function()
		track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()
	end)

	-- ── 타격감: 펀치 명중마다 히트 VFX(건틀릿 재활용) + 카메라 셰이크(피격자) + 몸 리코일 ──
	local RS = game:GetService("ReplicatedStorage")
	local punchVfxEv = RS:FindFirstChild("PunchVfxEmit")
	local shakeEv = RS:FindFirstChild("HammerShakeEvent")
	local victimPlayer = Players:GetPlayerFromCharacter(victimCharacter)
	local HIT_INTERVAL = 0.35
	-- 연발 펀치음 (3초짜리) — 시작 시 한 번만 재생 (명중마다 X)
	local punchSnd = Instance.new("Sound")
	punchSnd.SoundId = "rbxassetid://126199589428068"
	punchSnd.Volume = 1.4
	punchSnd.RollOffMaxDistance = 100
	punchSnd.Parent = vRoot
	punchSnd:Play()
	Debris:AddItem(punchSnd, 4)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < PUNCH_TIME - 0.15 do
			local r = victimCharacter:FindFirstChild("HumanoidRootPart") or vRoot
			if not r or not r.Parent then break end
			if punchVfxEv then punchVfxEv:FireAllClients(r.Position + Vector3.new(0, 0.5, 0), 7) end
			if shakeEv and victimPlayer then shakeEv:FireClient(victimPlayer, 1.3, 0.18) end
			-- 몸 리코일: 뒤로 살짝 밀렸다 복귀
			local holdPivot = victimCharacter:GetPivot()
			victimCharacter:PivotTo(holdPivot + (-flat) * 0.45)
			task.wait(0.06)
			if victimCharacter.Parent then victimCharacter:PivotTo(holdPivot) end
			task.wait(HIT_INTERVAL - 0.06)
		end
	end)
	-- 빅히트 사운드: 날리기(PUNCH_TIME)보다 SND_LEAD 먼저 재생 (넉백을 예고하듯)
	local SND_LEAD = 0.4
	task.delay(math.max(0, PUNCH_TIME - SND_LEAD), function()
		local sr = victimCharacter:FindFirstChild("HumanoidRootPart") or vRoot
		if sr and sr.Parent then
			local hitSnd = Instance.new("Sound")
			hitSnd.SoundId = "rbxassetid://113232724764217"
			hitSnd.Volume = 2.5
			hitSnd.RollOffMaxDistance = 120
			hitSnd.Parent = sr
			hitSnd:Play()
			Debris:AddItem(hitSnd, 2)
		end
	end)
	-- 펀치 종료 → victim 뒤로 날림 (사망은 executionHandler가 처리)
	task.delay(PUNCH_TIME, function()
		if track then pcall(function() track:Stop() end) end
		-- 마지막 빅히트: 큰 카메라 셰이크 + 큰 히트 VFX
		if shakeEv and victimPlayer then shakeEv:FireClient(victimPlayer, 2.8, 0.45) end
		local vr0 = victimCharacter:FindFirstChild("HumanoidRootPart")
		if punchVfxEv and vr0 then punchVfxEv:FireAllClients(vr0.Position + Vector3.new(0, 0.5, 0), 13) end
		local root = victimCharacter:FindFirstChild("HumanoidRootPart")
		if root then
			-- 서버 구동 포물선 날리기: 몸 앵커 유지 + CFrame 직접 이동 (소유권 무관 → 본인 클라에도 확실히 보임)
			for _, p in ipairs(victimCharacter:GetDescendants()) do
				if p:IsA("BasePart") then p.Anchored = true; p.CanCollide = false end
			end
			local startCF = root.CFrame
			local vel0 = (-flat) * KNOCK_BACK + Vector3.new(0, KNOCK_UP, 0)
			local G = 200
			local FLY_TIME = 0.6
			task.spawn(function()
				local t0 = os.clock()
				while true do
					local t = os.clock() - t0
					if t >= FLY_TIME then break end
					local offset = vel0 * t - Vector3.new(0, 0.5 * G * t * t, 0)
				local a = math.min(t / FLY_TIME, 1)
				-- 시작 자세 → 등으로 눕기(하늘 봄)로 부드럽게 회전
				local faceUp = startCF.Rotation * CFrame.Angles(math.rad(100), 0, 0)
				victimCharacter:PivotTo(CFrame.new(startCF.Position + offset) * startCF.Rotation:Lerp(faceUp, a))
					RunService.Heartbeat:Wait()
				end
				for _, p in ipairs(victimCharacter:GetDescendants()) do
					if p:IsA("BasePart") then p.Anchored = false end  -- 물리 복귀(사망은 executionHandler)
				end
			end)
		end
		task.delay(0.15, function() if dummy and dummy.Parent then dummy:Destroy() end end)
	end)

	print("[PunchFX] Punch 킬 이펙트 발동! 킬러:", killer and killer.Name)
end

_G.SpawnPunchEffect = function(killer, victimCharacter, position)
	markEffectBusy(8)
	queueFx(function() spawnPunchEffect(position, victimCharacter, killer) end)
end


local effectHandlers = {
    kill_effect_fire      = spawnFireEffect,
    kill_effect_lightning = spawnLightningEffect,
    kill_effect_ice       = spawnIceEffect,
    kill_effect_water     = spawnWaterEffect,
    kill_effect_coffin    = spawnCoffinEffect,
    kill_effect_rainbow   = spawnRainbowEffect,
    kill_effect_swordrain = spawnSwordRainEffect,
    kill_effect_hellfire  = spawnHellfireEffect,
    kill_effect_glitch    = spawnGlitchEffect,
    kill_effect_emp       = spawnEmpEffect,
    kill_effect_grave     = spawnGraveEffect,
}

_G.GetEquippedKillEffect = function(tagger)
    local effectId = equippedEffects[tagger.UserId]
    if not effectId or effectId == "" then
        local attr = tagger:GetAttribute("EquippedKillEffect")
        if attr and attr ~= "" then effectId = attr end
    end
    if effectId and tagger:GetAttribute("OwnedItem_" .. effectId) then return effectId end
    return nil
end

-- 🎬 [2026-08-27] 킬이펙트 재생 — 집계(handleKill)와 분리해 둔다.
--   [왜] onKill 이 "집계 + 이펙트" 한 덩어리라, 위쪽 _KillCounted 가드가
--     조기 return 할 때 이펙트까지 같이 사라졌다(아래 onKill 주석 참조).
local function playKillEffect(tagger, deathPosition, victimCharacter)
    if not tagger or not deathPosition then return end
    local effectId = equippedEffects[tagger.UserId]
    if not effectId or effectId == "" then
        local attr = tagger:GetAttribute("EquippedKillEffect")
        if attr and attr ~= "" then effectId = attr end
    end
    if effectId and tagger:GetAttribute("OwnedItem_" .. effectId) then
        local handler = effectHandlers[effectId]
        if handler then
            markEffectBusy(8)  -- 이펙트 공통 연출 보호(기본 8초). 긴 이펙트(코핀 18초)는 자체 상향.
            if effectId == "kill_effect_ice" or effectId == "kill_effect_coffin" or effectId == "kill_effect_glitch" then
                handler(deathPosition, victimCharacter)
            else
                handler(deathPosition, victimCharacter, tagger)
            end
        end
    end
end

local function onKill(tagger, victimName, deathPosition, victimCharacter)
    -- 연출 쪽에서 _G.RegisterKill 로 이미 등록했다면 중복 집계 방지.
    -- ⚠️ [2026-08-27] 여기서 return 하면 집계뿐 아니라 '이펙트도' 같이 사라진다.
    --   그러니 이 경로로 들어오는 건 "자기 연출을 이미 재생 중인" 케이스여야 한다
    --   (얼음/코핀 등 — 549행에서 RegisterKill 을 부른다).
    --   ⚠️ 전멸 정산은 RegisterKill 을 쓰지 않는다. RoundSystem.registerDownedAsKills 가
    --     _G.KillDownedRunner 로 '실제로 죽여서' 이 함수를 정상 경로로 태운다.
    --     (예전엔 집계만 하고 몸은 10초 더 살려둬서, 이펙트가 사망 8초 전에
    --      다운된 몸 위로 나오거나 결과창 뒤에 나왔다 — 실측 2026-08-27 00:42)
    if victimCharacter and victimCharacter:GetAttribute("_KillCounted") then
        victimCharacter:SetAttribute("_KillCounted", nil)
        return
    end
    if victimCharacter then
        if victimCharacter:GetAttribute("IceFrozen") then
            handleKill(tagger, victimName, victimCharacter)
            victimCharacter:SetAttribute("IceFrozen", nil)
            return
        end
        if victimCharacter:GetAttribute("WaterFrozen") then
            handleKill(tagger, victimName, victimCharacter)
            victimCharacter:SetAttribute("WaterFrozen", nil)
            return
        end
        if victimCharacter:GetAttribute("CoffinSequence") then
            handleKill(tagger, victimName, victimCharacter)
            victimCharacter:SetAttribute("CoffinSequence", nil)
            return
        end
        if victimCharacter:GetAttribute("TornadoActive") then
            handleKill(tagger, victimName, victimCharacter)
            victimCharacter:SetAttribute("TornadoActive", nil)
            return
        end
        if victimCharacter:GetAttribute("PortalActive") then
            handleKill(tagger, victimName, victimCharacter)
            victimCharacter:SetAttribute("PortalActive", nil)
            return
        end
        if victimCharacter:GetAttribute("PunchActive") then
            handleKill(tagger, victimName, victimCharacter)
            victimCharacter:SetAttribute("PunchActive", nil)
            return
        end
    end
    handleKill(tagger, victimName, victimCharacter)
    playKillEffect(tagger, deathPosition, victimCharacter)
end

local function findTagger()
    for _, p in ipairs(Players:GetPlayers()) do
        if p:GetAttribute("Role") == "Tagger" then return p end
    end
    return nil
end


local function watchPlayerCharacter(character, player)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then return end
    humanoid.Died:Connect(function()
        local killer = _G.GetKiller and _G.GetKiller(character)
        if not killer or killer == player then return end  -- 킬러 없음/자살 → 스킵
        task.wait(0.08)
        local hrp = character:FindFirstChild("HumanoidRootPart")
        local pos = hrp and hrp.Position or Vector3.new(0, 0, 0)
        onKill(killer, player.Name, pos, character)
    end)
end

for _, p in ipairs(Players:GetPlayers()) do
    if p.Character then watchPlayerCharacter(p.Character, p) end
    p.CharacterAdded:Connect(function(c) watchPlayerCharacter(c, p) end)
end
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function(c) watchPlayerCharacter(c, p) end)
end)

local watchedNPCs = {}
local function watchNPC(model)
    if watchedNPCs[model] then return end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    if Players:GetPlayerFromCharacter(model) then return end
    watchedNPCs[model] = true
    humanoid.Died:Connect(function()
        local killer = _G.GetKiller and _G.GetKiller(model)
        if not killer then return end
        task.wait(0.08)
        local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
        local pos = root and root.Position or Vector3.new(0, 0, 0)
        onKill(killer, model.Name, pos, model)
    end)
    model.AncestryChanged:Connect(function()
        if not model.Parent then watchedNPCs[model] = nil end
    end)
end

for _, obj in ipairs(workspace:GetDescendants()) do
    if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then watchNPC(obj) end
end
workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Humanoid") then
        local model = obj.Parent
        if model and model:IsA("Model") then task.defer(function() watchNPC(model) end) end
    end
end)
print("✅ KillEffectSystem v9 준비 완료! (Death Coffin v5 + black hand 체인 + ice_block + Water Prison)")
