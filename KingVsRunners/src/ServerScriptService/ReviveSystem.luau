-- ReviveSystem
-- 다운된 러너의 부활 처리 모듈
--
-- 작동 흐름:
--   1. 부활자가 다운자 근처에서 E키 누름 → ReviveRequestEvent("start")
--   2. 서버가 검증: 거리, 다운 상태, 부활자 자격
--   3. 통과 시 진행 시작 → ReviveStateChanged("progress_started", ...) 모든 클라에
--   4. 매 0.1초 진행률 업데이트 (서버에서 거리/이동/다운 계속 검증)
--   5. 6초 도달 → 부활 완료 → DownSystem.clearDown 호출 + 1회 사용 플래그 + 무적
--   6. 도중 검증 실패 시 즉시 취소 → ReviveStateChanged("progress_cancelled", ...)
--
-- 라운드별 1회 한정:
--   character:GetAttribute("UsedRevive") = true 인 사람은 다음 다운 시 즉시 사망
--   라운드 시작 시 RoundSystem 등에서 ReviveSystem.resetAllRevives() 호출 필요

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local DownSystem = require(game.ServerScriptService:WaitForChild("DownSystem"))

local ReviveSystem = {}

-- ── 설정 ────────────────────────────────────────────────
local REVIVE_DURATION       = 2        -- 부활 홀드 시간 (초)
-- 🔺 [밸런스 2026-09-18] 1.5 → 2.
--   [왜] 러너 쪽 구제가 곱셈으로 쌓여 있다 — 내구도(첫 히트 무효) × 부활(다운 되돌림)
--     × Q 대시(회피). 킹은 1킬에 히트 약 2.7회가 필요해졌는데, 태거 예산은 그대로였다.
--     태거 쿨(GLOBAL_COOLDOWN 2→1.5)은 '입력을 늘린' 증상 대응이었고,
--     이 값은 곱셈의 한 항을 직접 줄인다.
--   [실측 근거] 2026-09-18 봇전에서 부활은 거의 전부 **다운 직후**(0~3초)에 시작됐다.
--     늦게 출발한 건(8.5s / 9.9s) 이미 다운 10초 타이머에 걸려 실패한다.
--     즉 이 값이 실제로 바꾸는 건 '늦은 부활 차단'이 아니라 **처리율**이다 —
--     동시 2명 기준 2.5초당 1명 → 3.5초당 1명.
--   ⚠️ [유저 체감] E 홀드가 2초다. 그동안 구조자는 제자리에 무방비로 선다.
--     러너 입장에서 답답해질 수 있는 방향이라, 과하면 1.5 로 되돌린다.
--   ⚠️ [같이 봐야 하는 두 곳]
--     ① RunnerItem.RevivalFlag.Server 의 REVIVE_DELAY — "일반 부활의 2배" 라는
--        설계 관계가 주석에 명시돼 있다(1.5 → 3). 이 값이 2 면 4 가 되어야 관계 유지.
--        ⚠️ 아직 3 그대로다. 깃발은 과금/러너 아이템이라 별도 판단이 필요해 미뤘다.
--     ② RunnerBotDriveController 의 REVIVE_FIRE_START — 불벽이 홀드 동안 전진하는
--        거리(속도 10 × 홀드)로 계산한 여유값이다. 15+5 → 20+5 로 함께 올렸다.
--   ⚠️ 클라 진행바는 이 값을 이벤트로 받아 그린다(progress_started). 클라 상수 없음.
local REVIVE_DISTANCE       = 10     -- 부활 가능 거리 (stud). 4 → 7 → 10
--   ⚠️ ReviveClient 의 REVIVE_DISTANCE 와 반드시 같은 값이어야 한다.
--      서버가 판정하고 클라가 안내(프롬프트·범위 서클)를 그리므로, 어긋나면
--      "안내는 뜨는데 거부되거나 / 안 뜨는데 되는" 상태가 된다.
-- 홀드 유지 검사에만 주는 여유(stud). 대상 선택·시작 판정은 REVIVE_DISTANCE 그대로.
-- 3초 홀드 동안 매 틱 거리를 재는데, 서버와 클라 값이 같으면 가장자리에서
-- 사소한 움직임이나 렉으로 서버만 범위를 벗어나 부활이 취소된다.
local REVIVE_HOLD_SLACK     = 1
local INVUL_DURATION        = 2      -- 부활 직후 무적 시간 (초). 1 → 2 (2026-08-23)
--   ⚠️ 이 무적은 '부활자'뿐 아니라 '구조자'에게도 걸린다.
--      구조 행위는 1.5초를 제자리에 묶여 있어야 해서 태거 아이템의 표적이 되기 쉽다.
--      살려낸 순간 둘 다 쓸려나가면 부활을 시도할 이유가 사라진다.
local PROGRESS_TICK         = 0.1    -- 진행률 업데이트 주기 (초)
local REVIVE_COIN_BONUS     = 30     -- 실제 플레이어를 살렸을 때 (생존 보상 30 과 동급)
local REVIVE_COIN_BOT       = 15     -- AI 러너를 살렸을 때

-- ── 상태 ────────────────────────────────────────────────
-- 진행 중인 부활: targetCharacter -> { reviver, startTime, lastTick }
local activeRevives = {}
-- 부활자가 한 번 부활한 사람: character -> true
local usedRevives = {}

-- ── 이벤트 ──────────────────────────────────────────────
local stateEvent   = ReplicatedStorage:WaitForChild("ReviveStateChanged")
local requestEvent = ReplicatedStorage:WaitForChild("ReviveRequestEvent")

-- ─────────────────────────────────────────────────────────────
-- API
-- ─────────────────────────────────────────────────────────────
function ReviveSystem.hasUsedRevive(character)
    return usedRevives[character] == true
end

function ReviveSystem.markUsedRevive(character)
    usedRevives[character] = true
end

function ReviveSystem.resetAllRevives()
    usedRevives = {}
    -- 진행 중인 부활도 모두 취소
    for target, _ in pairs(activeRevives) do
        stateEvent:FireAllClients("progress_cancelled", target)
    end
    activeRevives = {}
    print("[ReviveSystem] 모든 부활 카운트 + 진행 상태 리셋")
end

function ReviveSystem.cancelRevive(target)
    if activeRevives[target] then
        activeRevives[target] = nil
        stateEvent:FireAllClients("progress_cancelled", target)
    end
end

-- ─────────────────────────────────────────────────────────────
-- 검증: 부활 시도가 유효한지
-- ─────────────────────────────────────────────────────────────
local function validateRevive(reviverChar, targetChar, slack)
    if not reviverChar or not reviverChar.Parent then return false, "부활자 캐릭터 없음" end
    if not targetChar or not targetChar.Parent then return false, "다운자 캐릭터 없음" end

    -- 부활자 자신이 다운 상태면 불가
    if reviverChar:GetAttribute("Downed") then
        return false, "부활자 본인이 다운 상태"
    end

    -- 부활자가 살아있어야 함
    local reviverHum = reviverChar:FindFirstChildOfClass("Humanoid")
    if not reviverHum or reviverHum.Health <= 0 then
        return false, "부활자 사망 상태"
    end

    -- 다운자가 실제로 다운 상태여야 함
    if not DownSystem.isDowned(targetChar) then
        return false, "대상이 다운 상태 아님"
    end

    -- 다운자가 살아있어야 함 (다운 타이머 중)
    local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
    if not targetHum or targetHum.Health <= 0 then
        return false, "다운자 이미 사망"
    end

    -- 거리 체크
    local reviverRoot = reviverChar:FindFirstChild("HumanoidRootPart")
    local targetRoot  = targetChar:FindFirstChild("HumanoidRootPart")
    if not reviverRoot or not targetRoot then return false, "HRP 없음" end
    local dist = (reviverRoot.Position - targetRoot.Position).Magnitude
    if dist > REVIVE_DISTANCE + (slack or 0) then
        return false, "거리 초과 (" .. math.floor(dist) .. "m)"
    end

    return true
end

-- ─────────────────────────────────────────────────────────────
-- 가장 가까운 다운자 찾기 (반경 내)
-- ─────────────────────────────────────────────────────────────
local function findNearestDowned(reviverChar)
    local reviverRoot = reviverChar and reviverChar:FindFirstChild("HumanoidRootPart")
    if not reviverRoot then return nil end

    local closest, closestDist = nil, math.huge
    for _, candidate in ipairs(workspace:GetChildren()) do
        if candidate:IsA("Model") and candidate ~= reviverChar then
            if DownSystem.isDowned(candidate) then
                local hum = candidate:FindFirstChildOfClass("Humanoid")
                local hrp = candidate:FindFirstChild("HumanoidRootPart")
                if hum and hum.Health > 0 and hrp then
                    local dist = (reviverRoot.Position - hrp.Position).Magnitude
                    if dist <= REVIVE_DISTANCE and dist < closestDist then
                        closest = candidate
                        closestDist = dist
                    end
                end
            end
        end
    end
    return closest, closestDist
end

-- ─────────────────────────────────────────────────────────────
-- 부활 시작 시도
-- ─────────────────────────────────────────────────────────────
-- 🤖 [2026-09-18] 부활 시작의 핵심을 **캐릭터 기준**으로 분리한다.
--   [왜] 이 모듈의 내부는 이미 전부 캐릭터 기반이다 — validateRevive · findNearestDowned ·
--     activeRevives[target].reviver · completeRevive 전부. 플레이어를 요구하는 곳은
--     이 함수의 첫 줄(player.Character)뿐이었다. 그 한 겹만 벗기면 봇도 부활자가 된다.
--   [왜 봇에게 필요한가] 지금까지 부활은 유저만 했다. 그래서 솔로모드(봇 10체) 측정값에는
--     부활이 구조적으로 빠져 있었고, 러너 전력을 실제보다 낮게 재고 있었다.
--     밸런스를 그 숫자로 맞추면 유저가 섞인 판에서 어긋난다.
--   ⚠️ 유저 경로는 한 글자도 안 바뀐다. startRevive(player) 는 이 함수를 부르는 래퍼로만 남는다.
--   ⚠️ 판당 1회 제한(UsedRevive)·다운자 사망·거리 이탈 검증은 전부 기존 경로 그대로다.
--     봇이라고 더 쉽게 살리지 않는다.
local function beginRevive(reviverChar, wantTarget)
    if not reviverChar or not reviverChar.Parent then return false end

    -- 🎯 [2026-09-18] 대상을 지정할 수 있다. 안 주면 예전처럼 가장 가까운 다운자를 찾는다.
    --   [왜] 봇은 대상을 **신중하게** 고른다 — 킹 거리, 불벽 뒤인지, 위험 지대인지를 보고
    --     그 사람에게 걸어간다(RunnerBotDriveController.reviveStep). 그런데 도착해서
    --     이 함수를 부르면 그 선택을 버리고 '제일 가까운 사람'을 다시 골랐다.
    --     보통은 같은 사람이지만, 도착 직전에 더 가까운 곳에서 누가 쓰러지면
    --     봇이 검사하지 않은 대상으로 바뀐다 — 필터를 우회하는 경로였다.
    --   ⚠️ 지정해도 검증은 그대로 탄다. 거리·다운 상태·본인 다운 여부를 validateRevive 가
    --     막으므로, 엉뚱한 대상을 넘겨도 더 쉬워지지 않는다.
    --   ⚠️ 유저 경로(startRevive)는 인자를 안 넘긴다 — 동작이 한 글자도 안 바뀐다.
    --     "E 누르면 근처 아무나"가 유저에게는 맞는 규칙이다.
    local target = wantTarget or findNearestDowned(reviverChar)
    if not target then
        return false  -- 근처에 다운자 없음
    end

    -- 이미 이 다운자에 대해 부활 진행 중이면 (다른 사람이 시도 중) 중복 시작 안 함
    if activeRevives[target] then
        return false  -- 본인이든 남이든 이미 진행 중
    end

    local ok, reason = validateRevive(reviverChar, target)
    if not ok then
        print("[ReviveSystem] 부활 시작 거절:", reason)
        return false
    end

    activeRevives[target] = {
        reviver   = reviverChar,
        startTime = tick(),
    }

    stateEvent:FireAllClients("progress_started", target, reviverChar, REVIVE_DURATION)
    print(string.format("[ReviveSystem] 부활 시작: %s → %s",
        reviverChar.Name, target.Name))
    return true, target
end

-- 유저 경로 — 캐릭터를 꺼내 위 함수로 넘기는 래퍼.
local function startRevive(player)
    local reviverChar = player.Character
    if not reviverChar then return end
    beginRevive(reviverChar)
end

-- 🤖 봇용 공개 진입점. 성공하면 true + 대상 캐릭터를 돌려준다.
--   target 을 주면 그 대상을 살린다(봇이 고른 사람). 안 주면 가장 가까운 다운자.
--   ⚠️ 호출자는 부활이 끝날 때까지 그 자리에 서 있어야 한다. 움직여서 거리가 벌어지면
--     메인 루프의 재검증(REVIVE_HOLD_SLACK)에 걸려 취소된다 — 유저가 E 를 떼는 것과 같다.
function ReviveSystem.beginReviveByCharacter(reviverChar, target)
    return beginRevive(reviverChar, target)
end

-- 🤖 봇용 중단. 이 캐릭터가 진행 중인 부활을 취소한다.
function ReviveSystem.cancelByReviver(reviverChar)
    for target, info in pairs(activeRevives) do
        if info.reviver == reviverChar then
            ReviveSystem.cancelRevive(target)
            return true
        end
    end
    return false
end

-- 🤖 봇용 조회. 이 캐릭터가 지금 누군가를 살리는 중인가.
function ReviveSystem.isReviving(reviverChar)
    for _, info in pairs(activeRevives) do
        if info.reviver == reviverChar then return true end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────
-- 부활 중단 (E키 떼기 또는 외부 요청)
-- ─────────────────────────────────────────────────────────────
local function stopRevive(player)
    local reviverChar = player.Character
    if not reviverChar then return end

    -- 이 부활자가 진행 중인 부활 찾아서 취소
    for target, info in pairs(activeRevives) do
        if info.reviver == reviverChar then
            ReviveSystem.cancelRevive(target)
            print("[ReviveSystem] 부활 중단:", reviverChar.Name, "→", target.Name)
            return
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- 부활 완료 처리
-- ─────────────────────────────────────────────────────────────
-- ── 부활 무적 부여 (부활자 + 구조자 공용) ─────────────────────
-- ReviveInvul 속성은 ItemDamageSystem.processHit 진입부에서 검사한다.
-- 태거 아이템은 HP 를 안 깎고 곧장 다운을 트리거하므로, 속성 검사 없이는 못 막는다.
--
-- 🛡️ 시각 표시: Material=ForceField 인 구체 파트를 몸에 용접해 감싼다.
-- ⚠️ Instance.new("ForceField") 를 쓰면 안 된다. 그건 Humanoid:TakeDamage() 를 차단해서
--    불기둥 압박까지 무시시킨다. 불기둥은 절대 압박이어야 하므로 뚫리면 안 된다.
--    이 무적이 막는 것은 '태거 아이템'뿐이고, 그 차단은 ReviveInvul 속성이 담당한다.
-- ── 머리 위 방패 배지 ─────────────────────────────────────────
-- 아머(ArmorSystem)의 🛡️ HUD 와 같은 방식. "지금 방패 상태다"를 본인과 태거 모두에게 알린다.
-- ⚠️ 아머 HUD 는 StudsOffset Y=3.4 를 쓴다. 아머를 낀 채 부활 무적이 겹치면 두 배지가
--    같은 자리에 포개지므로, 이건 4.4 로 띄워 위아래로 나란히 보이게 한다.
-- ⚠️ 이름도 다르게(_ReviveShieldHud) 둔다. 같은 이름이면 아머 쪽 정리 코드가 이걸 지운다.
local function showShieldBadge(char)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    local old = head:FindFirstChild("_ReviveShieldHud")
    if old then old:Destroy() end

    local gui = Instance.new("BillboardGui")
    gui.Name = "_ReviveShieldHud"
    gui.Size = UDim2.new(0, 110, 0, 30)
    gui.StudsOffset = Vector3.new(0, 4.4, 0)
    gui.AlwaysOnTop = true
    gui.MaxDistance = 150
    gui.Parent = head

    local lbl = Instance.new("TextLabel")
    lbl.Name = "Label"
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextScaled = true
    lbl.Text = "🛡️"
    lbl.TextColor3 = Color3.fromRGB(120, 220, 255)   -- 구체와 같은 하늘색 = 같은 상태임을 색으로 묶는다
    lbl.TextStrokeTransparency = 0.35
    lbl.Parent = gui
end

local function hideShieldBadge(char)
    if not char then return end
    local head = char:FindFirstChild("Head")
    local gui = head and head:FindFirstChild("_ReviveShieldHud")
    if gui then gui:Destroy() end
end

local function grantReviveInvul(char, playSfx)
    if not char or not char.Parent then return end

    char:SetAttribute("ReviveInvul", true)

    -- ⚠️ 연속 부활 대비 토큰. 이게 없으면 먼저 걸린 task.delay 가 나중 무적을
    --    조기 해제한다(A 부활 → 1초 뒤 B 부활 → A 의 타이머가 B 의 무적을 끔).
    local token = (char:GetAttribute("_ReviveInvulToken") or 0) + 1
    char:SetAttribute("_ReviveInvulToken", token)

    local old = char:FindFirstChild("_ReviveShield")
    if old then old:Destroy() end
    showShieldBadge(char)

    -- 🛡️ 구체는 '보이기만' 해야 한다.
    -- ⚠️ Instance.new("ForceField") 를 쓰면 안 된다(2026-08-23 되돌림).
    --    그건 Humanoid:TakeDamage() 를 실제로 차단해서 불기둥 압박까지 무시된다.
    --    불기둥은 회피 불가능한 절대 압박이라는 게 존재 이유라, 2초라도 뚫리면 성격이 깨진다.
    --    → Material=ForceField 인 구체 파트를 씌운다. 생김새는 사실상 같고 차단 능력은 없다.
    --      태거 아이템 차단은 위의 ReviveInvul 속성이 전담한다(ItemDamageSystem.processHit 검사).
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local orb = Instance.new("Part")
        orb.Name = "_ReviveShield"
        orb.Shape = Enum.PartType.Ball
        orb.Size = Vector3.new(9, 9, 9)
        orb.Material = Enum.Material.ForceField
        orb.Color = Color3.fromRGB(120, 220, 255)
        orb.Transparency = 0.35
        orb.CanCollide = false
        orb.CanQuery = false   -- 조준/판정 레이가 구체에 맞아 착탄점이 어긋나지 않게
        orb.CanTouch = false   -- 아이템 Touched 판정을 대신 먹지 않게
        orb.CastShadow = false
        orb.Massless = true
        orb.CFrame = hrp.CFrame
        orb.Parent = char

        -- 몸을 따라다니게 용접. Anchored 로 두면 제자리에 남는다.
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = orb
        weld.Part1 = hrp
        weld.Parent = orb

        -- 🔊 보호막 생성음은 여기(서버)서 재생하지 않는다.
        -- ⚠️ [실패 기록 2026-08-23] 서버에서 Sound 를 만들고 Play() 했더니
        --    진단상 len=3.92 / playing=true 인데도 클라에서 안 들렸다.
        --    (SoundService.RespectFilteringEnabled = true 환경)
        --    → ReviveClient 의 "revive_completed" 수신부에서 각 클라가 직접 재생한다.
        --      그 이벤트는 이미 FireAllClients 로 나가므로 모든 플레이어가 듣는다.
    end

    task.delay(INVUL_DURATION, function()
        if char and char.Parent and char:GetAttribute("_ReviveInvulToken") == token then
            char:SetAttribute("ReviveInvul", nil)
            char:SetAttribute("_ReviveInvulToken", nil)
            local s = char:FindFirstChild("_ReviveShield")
            if s then s:Destroy() end
            hideShieldBadge(char)
        end
    end)
end

local function completeRevive(target)
    local info = activeRevives[target]
    if not info then return end
    activeRevives[target] = nil

    -- 1회 사용 플래그
    ReviveSystem.markUsedRevive(target)
    target:SetAttribute("UsedRevive", true)

    -- 다운 해제 (DownSystem이 캐릭터 상태 복구)
    DownSystem.clearDown(target)

    -- 짧은 무적 (캐릭터 속성으로 표시 → ItemDamageSystem이 체크 가능)
    -- 부활자와 구조자 둘 다 건다. 구조자는 홀드 1.5초 동안 제자리에 묶여 있어서
    -- 살려낸 직후가 가장 무방비하다 — 둘 다 쓸려나가면 부활을 시도할 이유가 없어진다.
    grantReviveInvul(target, true)          -- 소리는 부활자 쪽에서 1회만
    grantReviveInvul(info.reviver, false)   -- 구조자는 구체(시각)만

    stateEvent:FireAllClients("revive_completed", target, info.reviver)
    print(string.format("[ReviveSystem] 부활 완료: %s가 %s 살림",
        info.reviver.Name, target.Name))
    -- 📡 [2026-09-06] 부활 건수 집계. "죽어도 할 일이 있는가"를 라이브에서 판정하려면
    --   이 값이 필요하다. 0 에 가까우면 판당 1회 제한이 병목이라는 근거가 된다.
    -- 🔧 [2026-09-18] **살린 쪽이 플레이어일 때만** 센다.
    --   [무엇이 깨졌나] 원래 주석은 "AI 를 살린 것도 센다 — 유저 입장에서 '할 일이 있었다'는
    --     사실은 같다" 였다. 그 전제는 **부활하는 쪽이 항상 유저**일 때만 성립한다.
    --     2026-09-18 에 봇 부활이 들어가면서 깨졌다 — 봇↔봇 부활이 이 값에 섞인다.
    --   [실측] 유저가 태거였고 부활을 한 번도 안 한 판에서 "부활 7회" 가 찍혔다. 전부 봇이었다.
    --     그 값으로 "부활이 잘 쓰이니 1회 제한은 병목이 아니다" 라고 읽으면 정반대로 틀린다.
    --   ⚠️ 이 지표가 재려는 건 봇 개체수가 아니라 **유저의 행동**이다. 살린 쪽으로 가른다.
    --     살려진 쪽(target)이 유저인지는 여기서 안 본다 — "유저가 뭔가 할 일이 있었나"는
    --     누구를 살렸든 성립하고, 그건 아래 코인 보상이 targetIsPlayer 로 이미 가른다.
    --   ⚠️ 되돌리려면 이 if 를 지우고 pcall 만 남기면 된다(봇 부활을 끌 때).
    local reviverPlayer = Players:GetPlayerFromCharacter(info.reviver)
    if reviverPlayer and _G.Telemetry_Revive then pcall(_G.Telemetry_Revive) end

    -- 부활자에게 코인 보상 + 카운트 증가 (RoundSystem이 라운드 종료 시 일괄 지급)
    -- killer:SetAttribute("RoundCoins", ...) 와 동일 패턴
    -- 살린 대상이 실제 플레이어인지 AI 러너인지로 보상을 가른다.
    --   AI 는 매 라운드 10체가 스폰되고 통나무 한 방에 여럿이 함께 다운돼 기회가 흔하다.
    --   반면 실제 아군을 살리는 건 드물고 라운드 결과에 직접 영향을 준다.
    --   보상이 같으면 '가장 가까운 아무나' 살리게 되어 선택이 무의미해진다.
    local targetIsPlayer = Players:GetPlayerFromCharacter(target) ~= nil
    local coinGain = targetIsPlayer and REVIVE_COIN_BONUS or REVIVE_COIN_BOT
    -- ⚠️ reviverPlayer 는 위 텔레메트리 가드에서 이미 구했다. 여기서 다시 선언하면
    --   같은 이름의 새 지역변수가 생겨 위 가드와 어긋날 수 있다.
    if reviverPlayer then
        local current = reviverPlayer:GetAttribute("RoundCoins") or 0
        reviverPlayer:SetAttribute("RoundCoins", current + coinGain)

        local revives = reviverPlayer:GetAttribute("RoundRevives") or 0
        reviverPlayer:SetAttribute("RoundRevives", revives + 1)

        print(string.format("🩹 %s 부활 보너스 +%d (총 %d회 부활, 누적 %d코인)",
            reviverPlayer.Name, coinGain, revives + 1, current + coinGain))

        -- 퀘스트: 구원의 손길 (러너로 동료 부활시키기)
        if _G.QuestSystem then
            _G.QuestSystem.addProgress(reviverPlayer, "reviveGiven", 1, "Runner")
        end
    end

    -- 퀘스트: 끈질긴 생명 (러너로 동료에게 부활당하기)
    local targetPlayer = Players:GetPlayerFromCharacter(target)
    if targetPlayer and _G.QuestSystem then
        _G.QuestSystem.addProgress(targetPlayer, "reviveTaken", 1, "Runner")
    end
end

-- ─────────────────────────────────────────────────────────────
-- 메인 루프: 진행 중인 부활들 매 틱 검증 + 진행률 발신
-- ─────────────────────────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(PROGRESS_TICK)
        local now = tick()

        for target, info in pairs(activeRevives) do
            local reviverChar = info.reviver

            -- 검증 재실행 (도중에 거리 멀어짐, 다운자 사망, 부활자 다운 등)
            local ok, reason = validateRevive(reviverChar, target, REVIVE_HOLD_SLACK)
            if not ok then
                ReviveSystem.cancelRevive(target)
                print("[ReviveSystem] 진행 중 취소:", reason)
            else
                local elapsed = now - info.startTime
                if elapsed >= REVIVE_DURATION then
                    completeRevive(target)
                else
                    -- 진행률 갱신
                    local progress = elapsed / REVIVE_DURATION
                    stateEvent:FireAllClients("progress_update", target, progress)
                end
            end
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- 클라이언트 요청 처리
-- ─────────────────────────────────────────────────────────────
requestEvent.OnServerEvent:Connect(function(player, action)
    if action == "start" then
        startRevive(player)
    elseif action == "stop" then
        stopRevive(player)
    end
end)

-- ─────────────────────────────────────────────────────────────
-- 캐릭터 사망/이탈 시 진행 중 부활 정리
-- ─────────────────────────────────────────────────────────────
local function watchCharacter(character)
    local hum = character:WaitForChild("Humanoid", 5)
    if not hum then return end
    hum.Died:Connect(function()
        -- 이 캐릭터가 부활 대상이었다면 취소
        if activeRevives[character] then
            ReviveSystem.cancelRevive(character)
        end
        -- 이 캐릭터가 부활자였다면 본인 진행 중 부활 취소
        for target, info in pairs(activeRevives) do
            if info.reviver == character then
                ReviveSystem.cancelRevive(target)
            end
        end
    end)
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(watchCharacter)
end)
for _, player in ipairs(Players:GetPlayers()) do
    if player.Character then watchCharacter(player.Character) end
    player.CharacterAdded:Connect(watchCharacter)
end

print("✅ ReviveSystem 활성화 (홀드:", REVIVE_DURATION, "초, 거리:", REVIVE_DISTANCE, "stud, 무적:", INVUL_DURATION, "초)")


-- 🛡️ [2026-08-27] 부활 무적을 외부에서도 쓸 수 있게 노출.
--   [왜] Revival Flag(광역 자동 부활)가 자체 경로로 clearDown 만 부르고 있어
--     무적이 안 붙었다. 일반 부활은 2초 무적인데 깃발로 살아난 사람은 맨몸이라,
--     일어서자마자 다시 쓰러지는 일이 잦았다.
--   ⚠️ 무적 구현(속성 + 토큰 + 구체 + 배지 + 해제 예약)이 한 덩어리라
--     호출부에서 흉내 내면 반드시 뭔가 빠진다. 반드시 이 함수를 쓸 것.
--   playSfx: 소리를 낼지. 여러 명을 한꺼번에 살릴 땐 첫 사람만 true 를 권한다.
function ReviveSystem.grantInvul(character, playSfx)
    if not character or not character.Parent then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    grantReviveInvul(character, playSfx and true or false)
    return true
end
return ReviveSystem
