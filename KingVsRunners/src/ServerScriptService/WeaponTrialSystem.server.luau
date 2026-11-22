-- WeaponTrialSystem
-- 로비 훈련장(Floating Lobby.TrainingYard) 무기 체험 — Blacksmith NPC 프롬프트로
-- 근접무기 8종을 지급한다. 라운드가 시작되면 회수한다.
--
-- ═══ 설계 결정 ═══
-- · 소유(Has_) 검사를 하지 않는다. 체험판이라 미소유 무기도 준다.
--   라운드에 들고 갈 수 없으므로(아래 회수) 상점 가치를 깎지 않는다.
-- · 지급 경로는 Stage2TriggerSystem:475 와 동일하다 — template:Clone() → Backpack.
--   ⚠️ 스킨 적용은 최소판에서 뺐다. 붙일 자리는 giveWeapon 안에 표시해 뒀다.
-- · 회수 그물은 이름 목록이 아니라 TRIAL_TAG 속성으로 잡는다.
--   ("정리 그물은 이름 목록으로 만들지 않는다" — 태거 아이템에서 같은 교훈)
--
-- ⚠️ 로비 무기가 유저를 못 때리는 근거(실측):
--   무기 6종의 히트 판정이 플레이어면 Role=="Tagger" 를 요구한다.
--   로비엔 태거가 없으므로 유저끼리 때릴 수 없다. NPC 분기는 AIRunner/RunnerBot 만
--   걸러내고 나머지를 태거로 간주하므로, 더미는 그 속성만 없으면 맞는다.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local WeaponData  = require(ReplicatedStorage:WaitForChild("WeaponData"))
local openEvent   = ReplicatedStorage:WaitForChild("WeaponTrialOpen")
local pickEvent   = ReplicatedStorage:WaitForChild("WeaponTrialPick")
local runnerItems = ServerStorage:WaitForChild("RunnerItem")

local TRIAL_TAG    = "WeaponTrial"   -- 체험용 무기 표식 (회수 기준)
local MAX_DISTANCE = 30              -- 서버측 거리 검증. 프롬프트 8 보다 넉넉히
local PROMPT_DIST  = 10

-- ── 화이트리스트 ───────────────────────────────────────────────
-- 클라가 임의 문자열을 보내도 여기 없는 건 지급되지 않는다.
local ALLOWED = {}
for _, w in ipairs(WeaponData) do
    if runnerItems:FindFirstChild(w.id) then
        ALLOWED[w.id] = true
    else
        warn("[WeaponTrial] 템플릿 없음, 목록에서 제외:", w.id)
    end
end

-- ⚠️ [2026-09-08] King 도구 추가. 러너 무기와 템플릿 위치가 다르다.
--   러너 8종: ServerStorage.RunnerItem.<id>
--   PushTool: ReplicatedStorage.PushTool
--   그래서 위 루프에 못 섞고 따로 넣는다.
if ReplicatedStorage:FindFirstChild("PushTool") then
    ALLOWED["PushTool"] = true
else
    warn("[WeaponTrial] ReplicatedStorage.PushTool 없음 — King 체험 비활성")
end

-- ── 로비 상태인가 ──────────────────────────────────────────────
-- RoundPhase 는 "intermission" | "stage1" | "stage2" (RoundSystem:256 / Stage2Trigger:884)
local function isLobby()
    local phase = ReplicatedStorage:GetAttribute("RoundPhase")
    return phase == nil or phase == "intermission"
end

-- ── 이 플레이어가 라운드 참가자인가 ────────────────────────────
-- 🔴 [버그수정 2026-09-20] 체험 무기 게이트를 전부 이 함수로 바꾼다.
--   [증상] 라이브 제보 — 라운드 도중 훈련장에 가면 무기도 안 나오고 블랙스미스
--     상호작용 자체가 막힌다. 라운드가 아니면 정상.
--   [원인] 게이트 다섯 곳이 전부 isLobby() 를 썼다. 그건 "내가 로비에 있나"가 아니라
--     **"지금 라운드가 도는가"** 다. 그런데 라이브에서 로비에 있는 사람은 대부분
--     라운드 중이다 — 죽어서 관전 중이거나, 라운드 도중 접속해 다음 판을 기다린다.
--     그 전원이 훈련장에서 통째로 차단됐다.
--   [같은 병의 이력] BridgeBoostClient(로비 스피드 패드)·FirePressureSystem(로비 화상)이
--     같은 날 같은 이유로 고쳐졌다. 여기만 남아 있었다.
--   ⚠️ isLobby() 는 남겨둔다 — "라운드가 도는가" 자체를 물어야 하는 자리가 아직 있다.
local function inRound(player)
    return player:GetAttribute("Role") ~= nil
end

-- 🔴 [버그수정 2026-09-20 #2] "회수 대상인가" 와 "야드를 써도 되나" 는 다른 질문이다.
--   [증상] 09-20 1차 수정 후에도 **조기탈락자**는 여전히 훈련장이 막혔다.
--     사망 시 Eliminated 만 켜지고 Role 은 그대로다(해제는 endRound 한 곳뿐) → inRound 가 계속 true.
--   [측정 09-20] 활성 SpawnLocation 은 Floating Lobby 하나뿐이다(맵 스폰은 전부 Enabled=false).
--     탈락자는 로비로 리스폰되고, 스폰(84,304,81) → 야드 진입로(175,302,88) 91 stud · 같은 고도다.
--     걸어갈 수 있는데 게이트에서 막히고 있었다.
--   [규모] RoundSystem:2436 주석 — 초반 사망자는 관전 130~140초 + 라운드 간 34초를 기다린다.
--     야드를 열어준 대상이 정확히 이 사람들이다.
--   ⚠️ [왜 inRound 에 Eliminated 를 넣지 않았나] 넣으면 회수가 뚫린다. 라운드 시작 순서가
--     ① Role 설정(RoundSystem:2828/2880) → ② Eliminated 해제(:3572, role 변수를 쓰는 블록)
--     라서 ① 시점엔 지난 판 탈락자의 Eliminated 가 아직 true 다. 그때 inRound 가 false 면
--     Role 변경 훅이 회수를 건너뛰어 체험 무기가 라운드로 딸려 들어간다.
--     그래서 회수 훅은 inRound(Role 만), 출입 게이트는 canUseYard 로 축을 나눈다.
--   ✅ 판별식은 새로 만들지 않았다 — TaggerBotSystem:702 · BarrelSpillSystem:337 ·
--     RoundSystem:1239/1293/1544 가 전부 "Role 있고 Eliminated 아님"을 쓴다. 같은 형태다.
--   ⚠️ 탈락자가 맵에 남아 있어도 안전하다: 야드 루프는 isInYard(위치)로 한 번 더 거르고,
--     pickEvent 는 NPC 거리 검증이 있다. 위치가 최종 보증이다.
local function canUseYard(player)
    if player:GetAttribute("Eliminated") then return true end   -- 탈락 → 로비에 있다
    return not inRound(player)
end

-- ── 회수 ───────────────────────────────────────────────────────
local function stripTrialWeapons(player)
    local n = 0
    for _, where in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
        if where then
            for _, d in ipairs(where:GetChildren()) do
                if d:IsA("Tool") and d:GetAttribute(TRIAL_TAG) then
                    d:Destroy()
                    n = n + 1
                end
            end
        end
    end
    -- ⚠️ [2026-09-07] 툴을 지우면 그 안의 스킬 스크립트도 함께 죽는다.
    --   진행 중이던 스킬(해머 스핀 등)이 WalkSpeed·PlatformStand 를 되돌릴 기회를 잃는다.
    --   실측: 스핀 중(16→8) 야드 이탈 → 회수 → 8 로 굳음. 복구 로그 없음.
    --   RoundStateResetServer 는 RoundPhase 변화만 보는데 여기는 로비 안이라 안 돈다.
    -- ⚠️ 지우기 '직전'이 아니라 '직후'에 부른다 — 파괴 순간 스킬 코드가 마지막
    --   대입을 할 수 있어, 먼저 되돌리면 그 위에 덮어써진다.
    -- ⚠️ 한 프레임 양보한다. Destroy 로 끊긴 연결의 잔여 콜백이 같은 프레임에 돌 수 있다.
    if n > 0 and _G.ResetCharacterState then
        task.defer(function()
            _G.ResetCharacterState(player)
        end)
    end
    -- Q 대시 권한 해제 (RunnerDive:502 가 이 속성을 본다)
    player:SetAttribute("WeaponTrialActive", nil)
    return n
end

local function stripAll(reason)
    local total = 0
    for _, plr in ipairs(Players:GetPlayers()) do
        total = total + stripTrialWeapons(plr)
    end
    if total > 0 then
        print(string.format("🧹 [WeaponTrial] 체험 무기 %d개 회수 (%s)", total, reason))
    end
end

-- ── 지급 ───────────────────────────────────────────────────────
local function giveWeapon(player, weaponId)
    -- ⚠️ King 도구는 템플릿 위치가 다르다.
    --   러너 8종은 ServerStorage.RunnerItem 하위, PushTool 은 ReplicatedStorage 직속.
    --   나머지 흐름(표식·회수·EquipTool 지연)은 완전히 동일해서 여기만 갈라준다.
    local template = (weaponId == "PushTool")
        and ReplicatedStorage:FindFirstChild("PushTool")
        or  runnerItems:FindFirstChild(weaponId)
    if not template then return false, "템플릿 없음" end

    stripTrialWeapons(player)   -- 한 번에 하나만 들게 한다

    -- ✨ [2026-09-08] 이전 무기가 캐릭터에 남긴 이펙트를 걷어낸다.
    --   [왜 여기인가] 사쿠라 오라는 서버가 캐릭터 팔다리에 붙이는데, 정리가
    --     Tool.Unequipped 에만 걸려 있어 Destroy 경로에서 실행되지 않는다.
    --     RoundStateResetServer 에도 같은 처리가 있지만 그건 로비 전환·회수 때만 돈다 —
    --     '무기 교체'(야드 안에서 다른 걸 고름)는 여기서만 잡힌다.
    --   ⚠️ 생성 쪽(SakuraBlade.attachOne)이 _WeaponFx_ 이름을 붙여준다.
    do
        local ch = player.Character
        if ch then
            for _, d in ipairs(ch:GetDescendants()) do
                if d.Name == "_WeaponFx_SakuraAura" then d:Destroy() end
            end
        end
    end

    local tool = template:Clone()
    tool:SetAttribute(TRIAL_TAG, true)

    -- 🎨 [나중에] 여기서 장착 스킨을 입힌다.
    --    _G.getEquippedSkin + _G.getSwordSkinData → Handle 색/재질
    --    (Stage2TriggerSystem:478 이 같은 일을 한다. 최소판 검증 후 옮겨올 것)

    local backpack = player:FindFirstChildOfClass("Backpack")
    if not backpack then return false, "Backpack 없음" end

    -- 🔴 [버그수정 2026-09-20] 부모에 붙이기 '직전'에 로비 상태를 다시 본다.
    --   [증상] 라이브 제보 — 2단계에서 클래식 소드가 손에는 있는데 인벤·스킬이 없고
    --     사용이 안 됐다. 제보자 행동: 훈련장에서 태거봇에게 강타를 맞는 중이었고,
    --     그 뒤 '새로 참여한' 라운드에서 발생(이전 라운드 잔재가 아니다).
    --   [원인] 야드 자동지급 루프(아래 288행)는 0.5초 틱 맨 위에서 isLobby() 를
    --     **한 번만** 본 뒤 플레이어 전원을 순회한다. 그 순회 도중 RoundPhase 가
    --     stage1 로 바뀌면 stripAll("라운드 시작") 이 먼저 돌고, **그 뒤에** 여기서
    --     체험 무기가 백팩에 들어간다. 다음 인터미션까지 아무도 안 걷어간다.
    --   [무엇이 깨지나] 남은 체험 무기 때문에 Stage2TriggerSystem 의 hasAlready 가
    --     참이 되어 2단계 무기 지급이 **조용히 스킵**된다(그 스킵에 09-20 로그를 붙여뒀다).
    --   [왜 여기인가] 태그는 이미 Clone 직후에 붙는다. 문제는 '언제 백팩에 들어가느냐'라서,
    --     가장 늦은 시점 = 가시화 직전에 다시 확인하는 것이 창을 0 으로 만든다.
    --   ⚠️ 호출자(프롬프트·야드 루프) 각각에 넣지 않는다. 지급 경로가 늘 때마다 또 샌다 —
    --     한 곳(여기)에서 막아야 새 호출자가 생겨도 자동으로 커버된다.
    -- 🔴 [버그수정 2026-09-20 · 2차] isLobby() → 플레이어별 Role 검사로 바꾼다.
    --   [증상] 라이브 제보 — 남이 플레이하는 동안 로비에서 기다리는 사람이
    --     훈련장에서 무기를 못 받는다. 받자마자 사라진다.
    --   [원인] isLobby() 는 "내가 로비에 있나"가 아니라 **"지금 라운드가 도는가"** 를 묻는다.
    --     라이브에서 로비에 있는 사람은 대부분 라운드 중이다 — 죽어서 관전 중이거나,
    --     라운드 도중 접속해 다음 판을 기다리는 중이다. 그 전원이 여기서 막혔다.
    --     BridgeBoostClient 가 같은 날 같은 이유로 고쳐졌는데 여기서 되풀이했다.
    --   [무엇을 막아야 했나] 원래 목적은 "이 플레이어가 지금 라운드에 끌려가는 중"이다.
    --     그건 전역 페이즈가 아니라 **이 플레이어의 Role** 이 말해준다 —
    --     RoundSystem 이 라운드 시작에 참가자에게만 세우고(:2879 등) 종료에 지운다.
    --   [무엇이 달라지나]
    --     · 라운드에 끌려가는 중  → Role 세워짐 → 여전히 차단 (원래 목적 유지)
    --     · 남의 라운드 로비 대기 → Role nil  → 지급됨 (되살아난 경로)
    --   ⚠️ isLobby() 는 지우지 않는다. 야드 자동지급 루프(아래)가 여전히 쓴다 —
    --     거기는 "라운드 중엔 야드 운영 자체를 쉰다"는 다른 판단이다.
    if player:GetAttribute("Role") ~= nil then
        tool:Destroy()
        return false, "라운드 참가 중"
    end

    tool.Parent = backpack

    -- 바로 손에 쥐어준다 — 고른 걸 또 꺼내게 만들 이유가 없다
    -- ⚠️ [2026-09-07] 같은 프레임에 EquipTool 하면 스킬 아이콘이 안 뜬다.
    --   무기 스킬 GUI 는 툴 안 LocalScript 가 Tool.Equipped 에서 gui.Enabled = true 로 켠다
    --   (SpinClient:204 / CounterClient / ChargeClient 전부 같은 구조).
    --   Backpack 에 넣은 직후엔 그 LocalScript 가 아직 복제·시작되지 않아
    --   Equipped 리스너가 연결되기 전이고, 이벤트를 통째로 놓친다.
    --   → 결과: 무기는 손에 있는데 스킬 버튼만 안 보인다 (실측).
    -- ⚠️ task.wait 로 한 프레임 이상 양보한다. task.defer 로는 부족했다.
    task.spawn(function()
        task.wait(0.2)
        if tool.Parent ~= backpack then return end   -- 그 사이 회수됐으면 중단
        local char = player.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            pcall(function() hum:EquipTool(tool) end)
        end
    end)
    -- ⚠️ Q 대시(RunnerDive) 권한. 로비에선 Role 이 nil 이라 기본적으로 막혀 있다.
    --   2단계에서 대시가 이동의 핵심이라, 대시 없이 무기만 휘둘러보는 건
    --   실제 전투와 감각이 다르다. 야드 안에서만 열어준다.
    player:SetAttribute("WeaponTrialActive", true)
    return true
end

-- ── 클라 선택 수신 ─────────────────────────────────────────────
pickEvent.OnServerEvent:Connect(function(player, weaponId)
    if typeof(weaponId) ~= "string" then return end
    if not ALLOWED[weaponId] then
        warn("[WeaponTrial] 허용되지 않은 무기 요청:", player.Name, tostring(weaponId))
        return
    end
    -- 🚪 살아서 뛰고 있는 참가자만 막는다(위 canUseYard 주석 참조).
    --    로비 대기자 + 조기탈락자는 통과.
    if not canUseYard(player) then return end

    -- 거리 검증 — 프롬프트를 우회한 직접 호출을 막는다
    local npc  = _G.WeaponTrialNpc
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if npc and hrp then
        local root = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Torso")
        if root and (root.Position - hrp.Position).Magnitude > MAX_DISTANCE then return end
    end

    local ok, err = giveWeapon(player, weaponId)
    if ok then
        print(string.format("🗡️ [WeaponTrial] %s → %s", player.Name, weaponId))
    else
        warn("[WeaponTrial] 지급 실패:", player.Name, weaponId, err)
    end
end)

-- ── 프롬프트 설치 ──────────────────────────────────────────────
local function installPrompt()
    local lobby = workspace:WaitForChild("Floating Lobby", 30)
    if not lobby then warn("[WeaponTrial] Floating Lobby 없음 — 중단"); return end
    local forge = lobby:WaitForChild("Forge", 30)
    if not forge then warn("[WeaponTrial] Forge 없음 — 중단"); return end
    local npc = forge:WaitForChild("Blacksmith", 30)
    if not npc then warn("[WeaponTrial] Blacksmith 없음 — 중단"); return end

    _G.WeaponTrialNpc = npc

    local anchor = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Torso")
    if not anchor then warn("[WeaponTrial] Blacksmith 에 부착할 파트 없음 — 중단"); return end

    local old = anchor:FindFirstChild("WeaponTrialPrompt")
    if old then old:Destroy() end

    local p = Instance.new("ProximityPrompt")
    p.Name                    = "WeaponTrialPrompt"
    p.ActionText              = "Try Weapons"
    p.ObjectText              = "Blacksmith"
    p.KeyboardKeyCode         = Enum.KeyCode.E
    p.HoldDuration            = 0
    p.MaxActivationDistance   = PROMPT_DIST
    p.RequiresLineOfSight     = false
    p.Parent                  = anchor

    p.Triggered:Connect(function(player)
        -- 🚪 살아서 뛰고 있는 참가자만 막는다.
        --    예전엔 라운드 중이면 로비 대기자·탈락자 모두 UI 가 안 열렸다.
        if not canUseYard(player) then return end
        openEvent:FireClient(player)
    end)

    print("✅ [WeaponTrial] Blacksmith 프롬프트 설치 완료 (무기 " ..
        (function() local n = 0 for _ in pairs(ALLOWED) do n = n + 1 end return n end)() .. "종)")
end

-- ── 라운드 시작 시 회수 ────────────────────────────────────────
-- 🔴 [버그수정 2026-09-20] 전원 회수 → **참가자만** 회수.
--   stripAll 은 로비 대기자의 체험 무기까지 걷어갔다. 그 사람은 라운드에 없다.
--   ⚠️ stripAll 은 남겨둔다(다른 호출부가 쓴다). 여기서만 대상을 좁힌다.
ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(function()
    if isLobby() then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if inRound(plr) then stripTrialWeapons(plr) end
    end
end)

-- 사망/리스폰으로 Backpack 이 비워져도 표식이 남은 잔존물은 없다(Backpack 이 통째 교체됨).
-- 다만 라운드 중 합류자가 로비 무기를 들고 들어오는 일이 없도록 스폰 때도 한 번 턴다.
Players.PlayerAdded:Connect(function(plr)
    -- 🔴 [버그수정 2026-09-20] 이 사람이 **참가자가 되는 순간** 회수한다.
    --   [왜 이게 정확한가] RoundPhase 는 전역이라 "누가 참가자인지"를 모른다.
    --     Role 이 세워지는 순간이 곧 "이 사람이 라운드에 들어갔다"이고,
    --     그 시점은 RoundPhase 변화보다 **앞선다**(RoundSystem 이 배치 전에 Role 을 세운다).
    --     위 RoundPhase 훅은 이걸 놓친 경우를 위한 그물이다.
    plr:GetAttributeChangedSignal("Role"):Connect(function()
        if inRound(plr) then stripTrialWeapons(plr) end
    end)
    plr.CharacterAdded:Connect(function()
        task.wait(0.5)
        -- ⚠️ 로비 대기자는 리스폰해도 체험 무기를 유지한다. 참가자만 턴다.
        if inRound(plr) then stripTrialWeapons(plr) end
    end)
end)

-- ── 야드 진입 시 로드아웃 무기 자동 지급 ──────────────────────
-- [왜] 09-06 문서가 짚은 문제가 "인벤에서 골라놓고 한 번도 만져본 적이 없다" 였다.
--      들어서자마자 그게 손에 쥐어지면 그 문제가 즉시 풀린다.
-- ⚠️ NPC 는 '게이트'가 아니라 '교체' 역할이다. 입구에서 뭘 골라야 통과되면
--    구경만 하러 온 사람까지 막힌다.
local yardRegion   -- {min=Vector3, max=Vector3}
local inYard = {}  -- [player] = true

local function computeYardRegion()
    local lobby = workspace:FindFirstChild("Floating Lobby")
    local yard  = lobby and lobby:FindFirstChild("TrainingYard")
    if not yard then return end
    local cf, size = yard:GetBoundingBox()
    -- 🔺 [2026-09-18] 위쪽 여유 20 → 60.
    --   [증상] 점프 중이거나 바위 위에서 해머하이를 쓰면 회수가 터졌다(실측 09-18).
    --     회수 = 툴 파괴라 진행 중인 스킬 정리가 통째로 날아간다(아래 stripTrialWeapons 주석).
    --   [측정] 야드 바닥 ≈ 306 · 발판 상단 ≈ 315 · 그 위 HRP ≈ 318
    --     + 점프 6.4 (JumpPower 50 / 중력 196.2)
    --     + 슬램 아치 30 (HammerHigh LEAP_HEIGHT)   → 정점 ≈ 354
    --     옛 천장 = 316.2 + 20 = 336.2 → **18 stud 초과**. 바닥에서 쏴도 339 라 이미 넘었다.
    --   [값] 60 → 천장 376. 정점 354 위로 22 여유. 야드 벽 상단(실측 363.7)보다도 높으니
    --     "벽 안이면 야드 안"이 성립한다.
    --   ⚠️ 가로(X/Z)는 안 건드린다. 도약은 clampDistByWalls 가 벽 앞에서 잘라주므로
    --     수평으로는 야드를 벗어나지 않는다. 위쪽만 막는 게 없어서 뚫렸다.
    --   ⚠️ 이건 여유값 조정이라 새 스킬이 더 높이 뜨면 또 뚫린다. 근본 해법은
    --     "야드 밖에 N초 이상 머물 때만 회수"다(순간 이탈은 스킬의 일부) — 별건으로 남긴다.
    --   ⚠️ 로비는 공중에 떠 있어 위쪽에 혼동할 지형이 없다. 넉넉히 줘도 오탐이 안 생긴다.
    local YARD_HEADROOM = 60
    yardRegion = {
        min = Vector3.new(cf.X - size.X/2, cf.Y - size.Y/2 - 5, cf.Z - size.Z/2),
        max = Vector3.new(cf.X + size.X/2, cf.Y + size.Y/2 + YARD_HEADROOM, cf.Z + size.Z/2),
    }
    print(string.format("📐 [WeaponTrial] 야드 영역 X %.0f~%.0f / Y %.0f~%.0f / Z %.0f~%.0f",
        yardRegion.min.X, yardRegion.max.X, yardRegion.min.Y,
        yardRegion.max.Y, yardRegion.min.Z, yardRegion.max.Z))
end

local function isInYard(pos)
    if not yardRegion then return false end
    return pos.X >= yardRegion.min.X and pos.X <= yardRegion.max.X
       and pos.Y >= yardRegion.min.Y and pos.Y <= yardRegion.max.Y
       and pos.Z >= yardRegion.min.Z and pos.Z <= yardRegion.max.Z
end

-- 로드아웃에 낀 무기. Stage2TriggerSystem:455 와 같은 규칙을 쓴다.
local function loadoutWeapon(player)
    local w = player:GetAttribute("EquippedWeapon")
    if w and ALLOWED[w] then return w end
    return "ClassicSword"
end

task.spawn(function()
    while true do
        task.wait(0.5)
        -- 🔴 [버그수정 2026-09-20] 루프 전체를 isLobby() 로 잠그던 것을 제거한다.
        --   라운드 중이라고 야드 운영을 통째로 쉬면 로비 대기자가 못 쓴다.
        --   대신 아래에서 **플레이어별로** 참가자만 건너뛴다.
        if yardRegion then
            for _, plr in ipairs(Players:GetPlayers()) do
                if not canUseYard(plr) then
                    -- 살아서 뛰는 참가자만 제외한다(탈락자는 로비이므로 대상).
                    -- 라운드에서 나오면 재진입으로 다시 받게
                    -- 상태를 비워둔다 — 안 그러면 inYard 가 남아 재진입 판정이 안 선다.
                    inYard[plr] = nil
                    continue
                end
                local char = plr.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                local hum  = char and char:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    local inside = isInYard(hrp.Position)
                    if inside and not inYard[plr] then
                        inYard[plr] = true
                        -- 이미 체험 무기를 들고 있으면 덮어쓰지 않는다
                        -- (NPC 로 고른 걸 재진입이 되돌리면 짜증난다)
                        local has = false
                        for _, where in ipairs({ plr:FindFirstChildOfClass("Backpack"), char }) do
                            if where then
                                for _, d in ipairs(where:GetChildren()) do
                                    if d:IsA("Tool") and d:GetAttribute(TRIAL_TAG) then has = true end
                                end
                            end
                        end
                        if not has then
                            local id = loadoutWeapon(plr)
                            local ok = giveWeapon(plr, id)
                            if ok then
                                print(string.format("🚪 [WeaponTrial] %s 야드 진입 → %s (로드아웃)", plr.Name, id))
                            end
                        end
                    elseif not inside and inYard[plr] then
                        inYard[plr] = nil
                        local n = stripTrialWeapons(plr)
                        if n > 0 then
                            print(string.format("🚪 [WeaponTrial] %s 야드 이탈 → %d개 회수", plr.Name, n))
                        end
                    end
                end
            end
        end
    end
end)

Players.PlayerRemoving:Connect(function(plr) inYard[plr] = nil end)


task.spawn(function()
    computeYardRegion()
    installPrompt()
end)

