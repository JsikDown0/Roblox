-- ItemDamageSystem v6 (processHit 파이프라인 + 다운 시스템 연동)
-- 태거 아이템 → 러너/NPC 접촉 시 통합 처리
-- 파이프라인: 검증 → 쿨다운 → 보호 아이템 체크 → 효과별 분기
-- v6: 일반 발사체는 즉사 대신 다운 상태로 전환 (DownSystem 호출)
--     킬 이펙트(빙결/물감옥/코핀)는 기존 컷씬 즉사 유지

local Players        = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local workspace      = game:GetService("Workspace")

-- ── 다운 시스템 연동 ────────────────────────────────────
local DownSystem = require(game.ServerScriptService:WaitForChild("DownSystem"))

local DAMAGE = 50
-- 🎯 "1발사 = 1히트" 기록.  [아이템 파트] → { [캐릭터명] = true }
--
-- ⚠️ __mode="k" (약한 키). 아이템이 파괴되면 GC 가 항목째 회수하므로
--    별도 정리 루프가 필요 없다. tostring(instance) 문자열을 키로 쓰면
--    인스턴스가 사라져도 키가 남아 서버 수명 동안 계속 쌓인다
--    (한 라운드에 아이템 수백 개가 스폰된다).
local damageCooldown   = setmetatable({}, { __mode = "k" })
local frozenCharacters = {}  -- 빙결/물감옥/코핀 처리 중인 캐릭터 (중복 방지)

-- 🚧 [2026-08-28] 처형 중인 캐릭터를 태거 아이템과 충돌하지 않게 한다.
--   [증상] 물감옥에 갇힌 러너에 배럴이 부딪혀 배럴 각도가 튀었다(실측 스크린샷).
--   [왜 CanCollide=false 로 안 하나] 그건 '모든' 충돌을 끈다. freezeCharacter 를
--     부르는 3종(ice/water/coffin)은 Anchored=true 라 안전하지만,
--     tornado/portal/punch 는 물리 사출·슬라이드·피격 반동이 필요해 일부러 동결을
--     안 한다. 거기에 CanCollide=false 를 걸면 앵커가 없어 바닥을 뚫고 떨어진다
--     (펀치는 3.8초라 한참 낙하한다).
--   [해결] DownedRunner 콜리전 그룹으로 옮긴다. 실측 매트릭스:
--     TaggerItems 하고만 X, 지형(Default)·벽·캐릭터는 전부 O.
--     즉 아이템만 통과하고 바닥은 그대로 밟는다.
--   ⚠️ 원래 그룹을 기억했다가 되돌려야 한다. 안 되돌리면 부활한 러너가
--     그 라운드 내내 태거 아이템을 통과한다(무적).
--   ⚠️ 새 그룹을 만들지 않는다. DownedRunner 가 이미 '다운자는 아이템에 안 맞는다'는
--     같은 의미로 쓰이고 있어 매트릭스가 이미 맞다.
local NO_ITEM_HIT_GROUP = "DownedRunner"
local savedGroups = setmetatable({}, { __mode = "k" })   -- char → { [part] = 원래 그룹 }

-- 🔍 [진단 2026-08-28] 아이템 통과 적용/복원 추적 — ⚠️ 검증 후 삭제
--   [왜] 배럴을 실제로 맞춰보는 물리 검증은 혼자 재현하기 어렵다.
--     대신 '콜리전 그룹이 실제로 바뀌었는가'를 찍으면 통과 여부가 확정된다
--     (DownedRunner ↔ TaggerItems = false 는 실측으로 이미 확인됨).
--   [무엇을 보나] ON/OFF 가 짝으로 찍히는지. OFF 가 없으면 그게 무적 버그다.
--   ✅ [2026-09-13 검증 완료] 09-13 판 로그에 ON/OFF 가 짝으로 찍혔다:
--     14:04 [PassThrough] ON  → AIRunner_3 | 18파트 → DownedRunner
--     18:17 [PassThrough] OFF → AIRunner_3 | 18파트 복원
--     부팅 확인줄(DownedRunner ↔ TaggerItems = false)도 함께 나왔다. 무적 버그 없음.
--   ⚠️ 릴리즈 전 이 토글과 관련 print 를 삭제할 것. 지금은 false 로만 둔다.
local DIAG_PASSTHROUGH = false

-- ⚠️ 런타임 매트릭스 확인. Edit 모드 실측과 런타임이 다를 수 있다 —
--   ItemSpawnHandler 가 부팅 때 콜리전 그룹을 새로 설정하므로, 거기서
--   DownedRunner ↔ TaggerItems 가 true 로 덮이면 이 수정이 조용히 무력화된다.
task.defer(function()
    if not DIAG_PASSTHROUGH then return end
    local PS = game:GetService("PhysicsService")
    local ok, collidable = pcall(function()
        return PS:CollisionGroupsAreCollidable(NO_ITEM_HIT_GROUP, "TaggerItems")
    end)
    if not ok then
        warn("[PassThrough] ❌ 그룹 조회 실패 — " .. NO_ITEM_HIT_GROUP .. " 미등록?")
    elseif collidable then
        warn("[PassThrough] ❌ 런타임에 " .. NO_ITEM_HIT_GROUP ..
             " ↔ TaggerItems = true. 통과가 안 된다!")
    else
        print("[PassThrough] ✅ 런타임 확인: " .. NO_ITEM_HIT_GROUP ..
              " ↔ TaggerItems = false (아이템 통과 가능)")
    end
end)

local function setItemPassThrough(character, on)
    if not character then return end
    if on then
        if savedGroups[character] then return end   -- 중복 적용 방지
        local saved = {}
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                saved[part] = part.CollisionGroup
                part.CollisionGroup = NO_ITEM_HIT_GROUP
            end
        end
        savedGroups[character] = saved
        if DIAG_PASSTHROUGH then
            local n, sample = 0, "?"
            for p, g in pairs(saved) do n += 1; sample = g end
            print(string.format("[PassThrough] ON  → %s | %d파트 → %s (원래 %s)",
                character.Name, n, NO_ITEM_HIT_GROUP, sample))
        end
    else
        local saved = savedGroups[character]
        if not saved then return end
        local n = 0
        for part, grp in pairs(saved) do
            if part.Parent then part.CollisionGroup = grp; n += 1 end
        end
        savedGroups[character] = nil
        if DIAG_PASSTHROUGH then
            print(string.format("[PassThrough] OFF → %s | %d파트 복원", character.Name, n))
        end
    end
end

-- ── 캐릭터 즉시 동결 ─────────────────────────────────────────
local function freezeCharacter(character)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide  = false
            part.Velocity    = Vector3.zero
            part.RotVelocity = Vector3.zero
            part.Anchored    = true
        end
    end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = 0; hum.JumpPower = 0 end
end

-- ── 동결 해제 → 즉시 사망 ───────────────────────────────────
-- 🔒 [버그수정 2026-09-11] 이 함수는 '조건부로' 부르면 안 된다.
--   [증상] 좀비 러너 — 다운 표식을 단 채 걸어다니고 죽지 않는다.
--     실측 15:07 판 AIRunner_5: `[Punch] start` 후 `-> death` 가 영영 안 왔고,
--     그 뒤 48초를 살아 있다가 킹 평타에 겨우 죽었다(로그 `Downed=nil HP=0`).
--   [원인] 각 처형 종이 frozenCharacters[character]=true 로 무적을 걸어놓고,
--     해제는 이 함수 안에서만 한다. 그런데 호출이 `if character.Parent` 조건부라
--     그 순간 Parent 가 nil 이면 통째로 건너뛰어 무적이 영구히 남는다.
--     attachTaggerExec 가 HP 를 계속 만피로 되돌려 '죽지 않는 러너'가 된다.
--     (AIRunner_5 는 FrostDragonZone 으로 얼어 있었고, 3.8초 창 안에 얼음이 파쇄됐다)
--   [규칙] 아래 주석이 "6종이 모두 거쳐가는 유일한 종료 지점"이라고 선언한다.
--     그 유일한 지점을 조건부로 부르면 선언이 거짓이 된다. 반드시 부른다.
--     parentless 에서도 GetDescendants·SetAttribute·FindFirstChildOfClass 는
--     전부 안전하므로 가드가 막아주는 것이 애초에 없었다.
--   ⚠️ 데스 코핀(_coffinNet 루프)은 이 함정을 이미 알고 else 로 frozenCharacters 를
--     직접 회수하고 있었다. 나머지 5종(빙결·물감옥·토네이도·포탈·펀치)만 안 고쳐져 있었다.
--     같은 사고가 한 곳에서만 고쳐진 전형이다 — 새 처형 종을 추가할 때도 가드를 붙이지 말 것.
local function killCharacter(character)
    frozenCharacters[character] = nil
    -- 🚧 [2026-08-28] 아이템 통과 해제. ExecuteKillEffect 의 setItemPassThrough(true) 와 한 짝.
    --   ⚠️ 안 되돌리면 부활한 러너가 그 라운드 내내 태거 아이템을 통과한다(무적).
    --     killCharacter 는 6종이 모두 거쳐가는 유일한 종료 지점이라 여기 한 곳이면 된다.
    setItemPassThrough(character, false)
    -- 💀 처형 마커 해제. ExecuteKillEffect 의 SetAttribute(true) 와 한 짝.
    --   ⚠️ 안 지우면 부활한 캐릭터가 영영 '처형 중'으로 남아 봇 AI 가 멈춘 채로 있다.
    character:SetAttribute("InKillSequence", nil)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
        end
    end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.WalkSpeed = 0
        hum.JumpPower = 0
        hum.Health    = 0
    end
end

-- ⏳ [버그수정 2026-09-11] 처형 종료 예약을 상주 루프로 옮긴다. task.delay 를 쓰지 말 것.
--   [증상] 좀비 러너 — `[Punch] start` 는 찍히는데 `-> death` 가 영영 안 온다.
--     frozenCharacters 가 안 풀려 무적이 되고, 다운 표식을 단 채 걸어다닌다.
--   [실측] 3판 전부 조건이 같다. 예외 없음:
--     15:07 AIRunner_5 / 16:05 AIRunner_3·9·5·10 / 16:19 AIRunner_2
--     → 전부 FrostDragon 얼음에 갇힌 상태로 처형됐고, 3.8초 창 안에 얼음이 파쇄됐다.
--   [원인] 아래 코핀 주석이 이미 적어둔 그대로다 —
--     "예약형(task.delay)은 호출자 혈통을 물려받아, 임시 스크립트(프드 얼음 생성기 등)가
--      죽으면 함께 회수된다."
--     처형이 얼음 생성기 경로에서 시작되면 task.delay 가 그 혈통에 묶인다.
--     ⚠️ 콜백이 '실행 자체가 안 되므로' 에러도 안 남는다. 그래서 오래 안 잡혔다.
--   ⚠️ 09-11 의 `character.Parent` 가드 제거는 헛수고였다 — 도달조차 못 하는 코드였다.
--     증상이 같다고 원인이 같지 않다. 가드를 의심하기 전에 콜백이 도는지부터 볼 것.
--   [규칙] 코핀은 08-28 에 같은 함정을 밟고 이 방식으로 고쳤는데 나머지 5종이 안 따라왔다.
--     새 처형 종을 추가할 때도 scheduleKill 을 쓴다. task.delay 는 같은 사고를 반복한다.
--   ⚠️ 주기 0.1초. 코핀(1초)보다 촘촘히 돈다 — 3.8초 연출과 사망 시점이 어긋나면 안 된다.
--   ⚠️ 이 루프도 반드시 최상위(부팅 스레드)에서 띄운다. 함수 안으로 옮기면 원점이다.
local _killNet = {}   -- [character] = { at = 마감시각(os.clock), msg = 로그 문구 }
task.spawn(function()
    while true do
        task.wait(0.1)
        local now = os.clock()
        for character, job in pairs(_killNet) do
            if now >= job.at then
                _killNet[character] = nil
                if character then
                    killCharacter(character)
                    print(job.msg, character.Name)
                end
            end
        end
    end
end)

-- 처형 연출이 끝나는 시점에 사망 처리를 예약한다.
--   ⚠️ 같은 캐릭터를 두 번 예약하면 뒤엣것이 이긴다(키가 캐릭터라 덮어쓴다). 의도한 동작이다.
local function scheduleKill(character, delay, msg)
    if not character then return end
    _killNet[character] = { at = os.clock() + delay, msg = msg }
end

-- ☠️ [2026-08-28] 코핀 안전망 — 부팅 소유 스윕 루프.
--   [왜 루프인가] 예약형(task.delay)은 호출자 혈통을 물려받아, 임시 스크립트
--     (프드 얼음 생성기 등)가 죽으면 함께 회수된다. 하나의 상주 루프가 전체를
--     훑으면 등록만 남고 스레드가 없어 혈통 문제에 원천적으로 면역이다.
--   ⚠️ 이 루프는 반드시 최상위(부팅 스레드)에서 띄울 것. 함수 안으로 옮기면
--     그 호출자의 혈통을 물려받아 원래 문제로 되돌아간다.
--   ⚠️ 키는 캐릭터 인스턴스다. 처리하든 못 하든 반드시 목록에서 지운다 —
--     안 지우면 frozenCharacters 와 똑같이 서버 수명 내내 쌓인다.
local _coffinNet = {}   -- [character] = 마감시각(os.clock)
task.spawn(function()
    while true do
        task.wait(1)
        local now = os.clock()
        for character, deadline in pairs(_coffinNet) do
            if now >= deadline then
                _coffinNet[character] = nil
                if character and character.Parent then
                    killCharacter(character)
                    print("💀 데스 코핀 → 사망:", character.Name)
                else
                    -- 캐릭터가 이미 사라진 뒤 = 코핀이 정상 완료하고 치운 경우.
                    -- killCharacter 를 못 부르므로 frozenCharacters 키만 직접 회수한다.
                    frozenCharacters[character] = nil
                end
            end
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- 보호 아이템 처리 (헬멧, 회피 부츠, 반사 망토 등)
-- 새 보호 아이템 추가 시 이 함수 내부에서 차단 로직 구현
-- @return true = 차단됨 (이후 단계 스킵), false = 통과
-- ─────────────────────────────────────────────────────────────
local function tryConsumeProtection(character, hitPosition, equippedEffect, tagger)
    -- ── 헬멧 (1회 태거 아이템 무시) - 미구현 예시 ─────────
    -- local charges = character:GetAttribute("HelmetCharges") or 0
    -- if charges > 0 then
    --     character:SetAttribute("HelmetCharges", charges - 1)
    --     -- TODO: 헬멧 깨짐 이펙트, 짧은 무적, UI 알림 등
    --     -- spawnHelmetBlockEffect(character, hitPosition)
    --     print("🛡️ 헬멧으로 차단:", character.Name, "(남은 횟수:", charges - 1, ")")
    --     return true
    -- end

    -- ── 회피 부츠 (대시 중 무적) - 미구현 예시 ────────────
    -- if character:GetAttribute("DashInvincibility") then
    --     return true  -- 자원 소비 없이 차단만
    -- end

    -- ── 반사 망토 (태거에게 데미지) - 미구현 예시 ─────────
    -- if character:GetAttribute("ReflectCharges") and ... then
    --     -- 태거에게 역으로 효과 적용
    --     return true
    -- end

    return false  -- 차단 없음, 일반 처리로 진행
end

-- ─────────────────────────────────────────────────────────────
-- 효과별 핸들러 테이블
-- 시그니처: (character, position, tagger, humanoid, player)
-- 새 효과 추가 시 이 테이블에 항목만 추가
-- ─────────────────────────────────────────────────────────────
local executionHandlers = {
    -- ❄️ 빙결: 3초간 결빙 후 사망
    kill_effect_ice = function(character, position, tagger, humanoid, player)
        frozenCharacters[character] = true
        character:SetAttribute("IceFrozen", true)
        freezeCharacter(character)

        if _G.SpawnIceFreezeEffect then
            _G.SpawnIceFreezeEffect(tagger, character, position)
        end
        print("❄️ 빙결 시작:", character.Name)

        scheduleKill(character, 3.0, "💀 빙결 해제 → 사망:")
    end,

    -- 💧 물감옥: 4초간 공중 감금 후 사망
    kill_effect_water = function(character, position, tagger, humanoid, player)
        frozenCharacters[character] = true
        character:SetAttribute("WaterFrozen", true)
        freezeCharacter(character)

        if _G.SpawnWaterPrisonEffect then
            _G.SpawnWaterPrisonEffect(tagger, character, position)
        end
        print("💧 물감옥 시작:", character.Name)

        scheduleKill(character, 4.0, "💀 물감옥 해제 → 사망:")
    end,

    -- ⚰️ 데스 코핀: 컷씬 후 사망
    -- ※ 타이머는 KillEffectSystem 컷씬 길이(약 17.9초)와 동기화 필수
    --   - 컷씬 자체가 Step8에서 Health=0 처리하므로 이 타이머는 안전망 역할
    --   - 컷씬보다 약간 늦게 발동해서 frozenCharacters 정리 + 미완료 시 강제 사망 보장
    --   - 컷씬 길이 변경 시 이 값도 함께 조정할 것
    kill_effect_coffin = function(character, position, tagger, humanoid, player)
        frozenCharacters[character] = true
        character:SetAttribute("CoffinSequence", true)
        freezeCharacter(character)

        if _G.SpawnCoffinEffect then
            _G.SpawnCoffinEffect(tagger, character, position)
        end
        print("⚰️ 데스 코핀 시작:", character.Name)

        -- ☠️ [2026-08-28] 안전망을 task.delay 로 예약하지 않는다.
        --   [원인] task.delay 는 호출자 혈통을 물려받는다. 이 핸들러는 프드 잔류지대
        --     → processHit → DownSystem → killDowned 체인에서 불리는데, 프드 얼음
        --     생성기는 clone 후 Destroy 되는 임시 스크립트다. 그 유령 스레드가
        --     파쇄에서 끝나는 순간 예약된 안전망도 함께 회수됐다.
        --   [실측] 11:11 판 — 코핀 10건 중 프드 혈통 3건만 안전망이 안 돌았다
        --     (11:12:48.9 파쇄와 동시). 나머지 7건(푸시툴·정산 혈통)은 정상 동작.
        --   [해결] 아래 _coffinNet 목록에 등록만 하고, 판정은 부팅 때 띄운 스윕
        --     루프가 한다. 예약 스레드가 없으므로 혈통에 영향받지 않는다.
        --   ⚠️ 여기서 task.delay/task.spawn 으로 되돌리지 말 것.
        _coffinNet[character] = os.clock() + 19.0
    end,

    -- 🌪️ 토네이도: 살아있는 채로 빨아올려 회전 → 사출 + 사망 (pre-death)
    --   freeze 안 함(물리 사출 필요). SpawnTornadoEffect가 PlatformStand+launch 처리.
    kill_effect_tornado = function(character, position, tagger, humanoid, player)
        frozenCharacters[character] = true
        character:SetAttribute("TornadoActive", true)

        if _G.SpawnTornadoEffect then
            _G.SpawnTornadoEffect(tagger, character, position)
        end
        print("[Tornado] start:", character.Name)

        -- 상승-회전(약 0.9s) + 사출 직후 사망 → 래그돌로 날아감
        scheduleKill(character, 1.1, "[Tornado] -> death:")
    end,

    -- 🌀 포탈: 앞쪽 아공간 포탈로 빨려들어가며 투명화 후 사망 (슬라이드+페이드는 SpawnPortalEffect가 처리)
    kill_effect_portal = function(character, position, tagger, humanoid, player)
        frozenCharacters[character] = true
        character:SetAttribute("PortalActive", true)

        if _G.SpawnPortalEffect then
            _G.SpawnPortalEffect(tagger, character, position)
        end
        print("[Portal] start:", character.Name)

        scheduleKill(character, 1.5, "[Portal] -> death:")
    end,

    -- 👊 펀치: 킬러 외형 더미가 나타나 마구 때린 뒤 멀리 날려 사망 (연출은 SpawnPunchEffect)
    kill_effect_punch = function(character, position, tagger, humanoid, player)
        frozenCharacters[character] = true
        character:SetAttribute("PunchActive", true)

        if _G.SpawnPunchEffect then
            _G.SpawnPunchEffect(tagger, character, position)  -- tagger = 실제 킬러(GetKiller)
        end
        print("[Punch] start:", character.Name)

        scheduleKill(character, 3.8, "[Punch] -> death:")
    end,
}

-- ─────────────────────────────────────────────────────────────
-- 기본 데미지 처리 (효과 미장착 또는 fire/lightning 등 시각형)
-- v6 변경: 즉사 → 다운 시스템 호출
--   - 일반 발사체(통나무, 돌, 통, Noob 등)에 맞으면 다운 상태로 전환
--   - 다운 타이머 만료 시 사망 처리되며, 그때 KillEffect.Died가 트리거됨
--     (화염/번개 시각형 효과는 다운 → 사망 시점에 자연스럽게 발동)
-- ─────────────────────────────────────────────────────────────
-- 히트 아이템 설명 (디버깅용: "뭐에 다운됐는지" 로그 표기)
local function describeHitItem(hitObject)
    if not hitObject then return "?" end
    local p = hitObject.Parent
    if p and p ~= workspace then return p.Name end
    return hitObject.Name
end

local function defaultDamage(character, position, tagger, humanoid, player, hitObject)
    -- 이미 한 번 부활을 사용한 사람은 다운 거치지 않고 즉사
    -- (라운드당 1회 부활 — 이 플래그는 RoundSystem이 새 라운드 시작 시 초기화 필요)
    if character:GetAttribute("UsedRevive") then
        -- 부활 소진자: 다운 없이 처형 (victim-제어 이펙트 있으면 이펙트가 사망 처리)
        if _G.ExecuteKillEffect and _G.ExecuteKillEffect(character) then return end
        humanoid:TakeDamage(DAMAGE)
        local itemDesc = describeHitItem(hitObject)
        if _G.RecordDown and player then _G.RecordDown(position, itemDesc) end  -- 💀 히트맵 수집 (유저만 — AI 제외)
        if player then
            print("💀", player.Name, "부활 사용자 즉사! ← " .. itemDesc)
        else
            print("💀 NPC", character.Name, "부활 사용자 즉사! ← " .. itemDesc)
        end
        return
    end

    -- 어떤 아이템에 맞았는지 넘긴다(통나무는 다운 시 관성을 죽인다).
    local triggered = DownSystem.triggerDown(character, describeHitItem(hitObject))
    if triggered then
        local itemDesc = describeHitItem(hitObject)
        if _G.RecordDown and player then _G.RecordDown(position, itemDesc) end  -- 💀 히트맵 수집 (유저만 — AI 제외)

        -- ItemNoob 명중음: "잡아먹었다"는 그림이 되도록 충돌 순간에 재생.
        -- (스폰 시 1회는 ItemSpawnHandler 가 담당 — 여기는 러너와 부딪힌 순간)
        -- ⚠️ 스킨이 16종(GoldNeonNoob·IceNoob·KingNoob …)이라 이름이 제각각이다.
        --    "Noob" 부분 일치로 잡아야 스킨을 껴도 소리가 난다.
        -- ⚠️ 단, 전용 사운드를 가진 스킨(SummerNoob 등)은 제외 — 자체 루프가 돌고 있어
        --    공용 nom-nom-nom 이 겹치면 연출이 지저분해진다. (ItemSpawnHandler 와 동일 기준)
        if itemDesc and itemDesc:lower():find("noob") then
            local hasOwnSfx = false
            if hitObject then
                local root = (hitObject.Parent ~= workspace and hitObject.Parent) or hitObject
                for _, d in ipairs(root:GetDescendants()) do
                    if d:IsA("Sound") and d.Name:sub(1, 1) == "_" then hasOwnSfx = true break end
                end
            end
            local hrp = (not hasOwnSfx) and character:FindFirstChild("HumanoidRootPart") or nil
            if hrp then
                local s = Instance.new("Sound")
                s.SoundId = "rbxassetid://105916582425420"   -- nom-nom-nom
                s.Volume = 3.5
                s.RollOffMinDistance = 25
                s.RollOffMaxDistance = 140
                s.Parent = hrp
                s:Play()
                game:GetService("Debris"):AddItem(s, 5)
            end
        end

        if player then
            print("🩸", player.Name, "다운! (10초 후 사망) ← " .. itemDesc)
        else
            print("🩸 NPC", character.Name, "다운! ← " .. itemDesc)
        end
    else
        -- 폴백: 다운 트리거 실패 시 기존 즉사 로직 (이미 다운/사망 상태 등)
        humanoid:TakeDamage(DAMAGE)
    end
end

-- ─────────────────────────────────────────────────────────────
-- 처형(execution): 죽는 순간, 태거가 victim-제어 이펙트 장착 중이면
-- 아직 살아있는 몸에 이펙트를 발동시켜 사망을 위임한다.
-- DownSystem.killDowned(블리드아웃) / defaultDamage(부활소진 즉사)에서 호출.
-- @return true = 이펙트가 사망을 맡음(호출부는 Health=0 하지 말 것), false = 미개입
-- ─────────────────────────────────────────────────────────────
local EXECUTION_EFFECTS = {
    kill_effect_ice     = true,
    kill_effect_water   = true,
    kill_effect_coffin  = true,
    kill_effect_tornado = true,
    kill_effect_portal  = true,
    kill_effect_punch   = true,
}

-- ─────────────────────────────────────────────────────────────
-- 실제 킬러 판별 (킬이펙트 공용): creator 태그(러너 무기/AI가 붙임) 우선,
-- 없으면 태거 역할 플레이어(태거 킬 / creator 만료된 처형). AI 킬러는 nil.
-- ─────────────────────────────────────────────────────────────
_G.GetKiller = function(victimCharacter)
    if victimCharacter then
        local hum = victimCharacter:FindFirstChildOfClass("Humanoid")
        local creator = hum and hum:FindFirstChild("creator")
        if creator and creator.Value then
            local kv = creator.Value
            if kv:IsA("Player") then return kv end
            local p = Players:GetPlayerFromCharacter(kv)
            -- 🤖 [2026-09-12] AI 킬러면 여기서 끝낸다. 아래 폴백으로 떨어지면 안 된다.
            --   [왜] creator 가 있다는 건 '누가 죽였는지 안다'는 뜻이다.
            --     그게 봇이면 답은 "이펙트 없음"이지 "모르겠다"가 아니다.
            --   ⚠️ 예전엔 nil 을 반환해 폴백을 탔고, 폴백이 '태거 역할 플레이어'를
            --     찾아 돌려줬다 — 희생자가 그 태거 본인이면 자기가 자기를 죽인 게 된다.
            --     실측 2026-09-12: 봇이 킹을 잡았는데 "킬러: melonberrystrong" 으로
            --     처형 이펙트가 재생됐다(승패는 Unknown 이었다 — 두 시스템이 어긋남).
            return p   -- AI 모델이면 nil = 이펙트 없음 (의도된 결과)
        end
    end
    -- creator 가 아예 없을 때만 오는 폴백.
    --   [원래 의도] 태거가 러너를 죽였는데 creator 태그가 만료된 경우를 구제한다.
    --   ⚠️ 희생자 본인은 제외한다. 태거가 환경·봇에게 죽으면 자기 자신이 킬러가 된다.
    --   ⚠️ 희생자가 태거면 이 폴백 자체가 성립하지 않는다 — 태거를 죽이는 건 러너다.
    local victimPlayer = victimCharacter and Players:GetPlayerFromCharacter(victimCharacter)
    if victimPlayer and victimPlayer:GetAttribute("Role") == "Tagger" then
        return nil
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= victimPlayer and p:GetAttribute("Role") == "Tagger" then return p end
    end
    return nil
end

-- 🔍 [진단 2026-08-28] 처형이 스킵된 이유 색출 — ⚠️ 원인 확인 후 이 블록 삭제
--   [증상] 10:24 판에서 마법책에 다운된 3명이 킬이펙트 없이 소멸(DownSystem:477).
--     killDowned 416행의 ExecuteKillEffect 가 false 를 돌려주면 그리로 빠진다.
--   [왜 진단인가] 게이트가 6개인데 어느 것이 막았는지 로그에 안 남는다.
--     불기둥·곡사포·마법책·프드지대 모두 Downed 가드가 있어 후보가 좁혀지지 않았고,
--     이후 두 판에서 재현되지 않았다. 추측으로 고치지 말 것.
local function _rejectKillEffect(character, why)
    warn(string.format("[KillFxGate] 처형 스킵 → %s | 사유=%s",
        character and character.Name or "?", why))
    return false
end

_G.ExecuteKillEffect = function(character)
    if not character or not character.Parent then return false end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return _rejectKillEffect(character, "Humanoid 없음") end
    if humanoid.Health <= 0 then
        return _rejectKillEffect(character, string.format("HP<=0 (%.2f)", humanoid.Health))
    end
    if frozenCharacters[character] then return true end  -- 이미 처형 진행 중

    local tagger = _G.GetKiller(character)  -- 실제 킬러 (creator 우선, 태거 폴백)
    if not tagger then
        local cr = humanoid:FindFirstChild("creator")
        return _rejectKillEffect(character, "킬러 없음 | creator="
            .. tostring(cr and cr.Value and cr.Value.Name or "없음"))
    end

    local effectId = _G.GetEquippedKillEffect and _G.GetEquippedKillEffect(tagger)
    if not effectId or not EXECUTION_EFFECTS[effectId] then
        return _rejectKillEffect(character, "이펙트 부적격 | id=" .. tostring(effectId)
            .. " | killer=" .. tagger.Name)
    end
    local handler = executionHandlers[effectId]
    if not handler then
        return _rejectKillEffect(character, "핸들러 없음 | id=" .. tostring(effectId))
    end

    local root = character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")
    local position = root and root.Position or character:GetPivot().Position
    local player = Players:GetPlayerFromCharacter(character)

    -- ⏳ [KILLFX-BUSY 2026-08-27] 연출 보호 시간을 등록한다.
    --   [증상] 태거가 죽을 때 킬이펙트가 끝나기 전에 라운드가 끝났다(실측 2026-08-27).
    --   [원인] markEffectBusy 는 KillEffectSystem 의 effectHandlers 경로에만 붙어 있다.
    --     처형형 이펙트(코핀·펀치·포탈 등)는 여기 executionHandlers 를 직접 타므로
    --     그 등록을 통째로 건너뛰었다. RoundSystem.waitForKillEffects 는 등록된 게
    --     없으면 즉시 통과하므로, 태거 사망 경로의 task.wait(2) 만 지켜졌다.
    --   ⚠️ 코핀은 전체 시퀀스가 약 17초다. 기본 8 로 두면 코핀만 또 잘린다.
    --     KillEffectSystem 이 코핀에 18 을 쓰므로 같은 값을 맞춘다.
    --   ⚠️ handler 호출 '전에' 등록한다. 핸들러 안에서 yield 하면 그 사이 라운드가
    --     끝나버릴 수 있다.
    if _G.MarkKillEffectBusy then
        _G.MarkKillEffectBusy(effectId == "kill_effect_coffin" and 18 or 8)
    end
    -- ⚠️ [2026-08-28 되돌림] 핸들러를 큐로 미루지 말 것. 여기서 '동기'로 부른다.
    --   [무슨 일이 있었나] 혈통 분리를 위해 이 호출을 큐로 옮겼더니, 처형이 확정된
    --     뒤 핸들러가 실제로 돌기까지 창이 생겼다. 그 사이 몸이 무방비다.
    --     (실측 12:57:37 — 처형 발동 37.477 → 사망 37.727 → 관 시작 37.744.
    --      라운드 종료 정리가 그 창에 끼어들어 시체가 먼저 치워졌고,
    --      관이 빈 채로 재생됐다)
    --   [왜 frozenCharacters 만으로 부족했나] 그건 processHit 파이프라인만 막는다.
    --     몸을 실제로 확보하는 건 핸들러 첫 줄의 freezeCharacter(앵커)다.
    --   [혈통 분리는 어디서 하나] 핸들러의 짧은 프롤로그(동결·속성)는 동기로 돌리고,
    --     긴 연출만 KillEffectSystem 의 부팅 소유 큐(queueFx)가 맡는다.
    --     6종 _G.SpawnXEffect 가 전부 그 큐를 거친다.
    handler(character, position, tagger, humanoid, player)
    -- 🚧 [2026-08-28] 처형 시작 = 태거 아이템 통과. 6종 공용 지점이라 여기 한 곳이면 된다.
    --   ⚠️ handler '뒤'에 둔다. freezeCharacter 가 GetDescendants 를 먼저 돌아야
    --     그 시점의 파트 목록이 확정되고, 우리도 같은 목록을 본다.
    --   ⚠️ 해제는 killCharacter 가 담당한다(아래). 짝을 반드시 유지할 것.
    setItemPassThrough(character, true)
    -- 💀 [2026-08-29] 처형 중 공용 마커. 6종 효과가 각자 다른 속성을 세우므로
    --   (IceFrozen / WaterFrozen / CoffinSequence / TornadoActive / PortalActive / PunchActive)
    --   외부에서 "지금 처형 중인가"를 물으려면 6개를 다 알아야 했다.
    --   ⚠️ 7번째 효과가 생기면 검사하는 쪽이 또 빠진다. 여기 한 곳에서 세운다.
    --   [용도] TaggerBotSystem 이 이 값을 보고 AI 를 멈춘다.
    --     실측 17:32 판: KING 이 Punch 처형 중(3.8초)에 계속 차징·공격했다.
    --     ⚠️ punch/tornado/portal 은 freezeCharacter 를 안 부르므로(물리 사출 필요)
    --       Frozen 속성으로는 잡히지 않는다.
    character:SetAttribute("InKillSequence", true)
    return true
end

-- ─────────────────────────────────────────────────────────────
-- 🎯 메인 파이프라인: processHit
-- 태거 아이템 접촉 시 호출
-- 1. 검증     → 잘못된 대상 거르기
-- 2. 쿨다운   → 같은 아이템 다중 트리거 방지
-- 3. 보호     → 헬멧/부츠/망토 등 차단 기회
-- 4. 분기     → 효과별 핸들러 또는 기본 데미지
-- ─────────────────────────────────────────────────────────────
local function processHit(character, hitObject)
    -- ⚠️ NoTarget 모델은 어떤 아이템에도 반응하지 않는다.
    --   로비 상점 NPC 처럼 "Humanoid 는 있지만 전투 대상이 아닌" 오브젝트가
    --   태거 아이템에 맞아 다운되거나 죽는 것을 막는다.
    --   (충돌 그룹 LobbyProp 이 물리는 막지만, 데미지 판정은 Humanoid 유무로 하므로 별도 차단 필요)
    if character and character:GetAttribute("NoTarget") == true then return end
    -- 🎤 [밸런스 2026-08-29] 마이크밤 공연 중에는 피해를 받지 않는다.
    --   [왜] 마이크밤은 밈/개그 아이템으로 넣었는데(아군에게도 쓸 수 있다는 점이 그렇다)
    --     8초 완전 무력화는 2단계(20~40초)의 1/4 을 지워버려 너무 강했다.
    --   [왜 지속을 안 줄이나] 댄스 애니메이션과 노래가 8초에 정확히 맞춰져 있다.
    --     지속을 줄이면 연출이 중간에 잘린다 → 위력만 뺀다.
    --   [효과] 무대에 올라간 대상은 못 움직이지만 죽지도 않는다.
    --     · 태거에게 걸면: 8초 무력화 대신 "8초 동안 서로 아무것도 못 함"
    --     · 아군에게 걸면: 트롤링이 아니라 오히려 8초 무적 → 밈 성격에 맞다
    --   ⚠️ MicBombed 속성은 MicBombSystem 이 세우고 지운다. 여기선 읽기만 한다.
    --   ⚠️ 넉백·래그돌은 각 아이템이 자체 처리하므로 여기서 막히지 않는다.
    --     무대 위 캐릭터는 HRP 가 Anchored 라 물리적으로도 안 밀린다.
    if character and character:GetAttribute("MicBombed") then return end
    -- ── 접촉 다운 면제 아이템 ────────────────────────────
    -- NoContactDown 속성(쓰나미 등 "밀어내기 전용"): 접촉해도 다운/데미지 없음.
    -- 래그돌/넉백은 각 아이템 시스템이 자체 처리. (다운은 래그돌 중 다른 아이템 접촉 콤보로만)
    if hitObject and hitObject:GetAttribute("NoContactDown") then return end

    -- ── 0단계: 디코이(분신) 처리 ─────────────────────────
    -- 태거 아이템이 분신에 닿으면 다운/킬 없이 분신만 소멸.
    -- hit.Parent 가 분신 모델이거나(일반 바디파트) 그 부모가 분신(악세서리 등)인 경우 모두 커버.
    do
        local decoy = nil
        if character:GetAttribute("IsDecoy") then
            decoy = character
        elseif character.Parent and character.Parent:GetAttribute("IsDecoy") then
            decoy = character.Parent
        end
        if decoy then
            if _G.popDecoy then _G.popDecoy(decoy) else decoy:Destroy() end
            return
        end
    end

    -- ── 0.5단계: 콘서트 게스트(장식용 더미)는 무시 ──────
    -- 마이크밤 무대의 게스트 더미는 단순 장식이라 다운/데미지 대상이 아님.
    if character:GetAttribute("ConcertGuest")
        or (character.Parent and character.Parent:GetAttribute("ConcertGuest")) then
        return
    end

    -- ── 0.6단계: 던진 태거 아이템(Noob 스킨 등)은 무시 ──────
    -- Noob 계열 스킨은 옷 렌더링을 위해 Humanoid를 갖지만, 이건 던지는 발사체일 뿐
    -- 공격 대상이 아니므로 다운/데미지 판정에서 제외.
    if character:GetAttribute("ThrownTaggerItem") then
        return
    end

    -- ── 0.7단계: 무적(i-frame) 체크 ────────────────────
    -- RunnerDive(산데비스탄) 등에서 player:SetAttribute("Invincible", true) 켜둔 경우 통과.
    do
        local plr = Players:GetPlayerFromCharacter(character)
        if plr and plr:GetAttribute("Invincible") then return end
    end

    -- ── 1단계: 검증 ─────────────────────────────────────
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    if frozenCharacters[character] then return end  -- 이미 처리 중
    if DownSystem.isDowned(character) then return end  -- 다운 상태 (발사체 무적)
    if character:GetAttribute("ReviveInvul") then return end  -- 부활 직후 무적 (1초)
    if character:GetAttribute("DiveInvul") then return end  -- 다이브 발동 무적 (짧음, DiveServer가 서버에서 부여)

    -- ── 0.7단계: 같은 아이템-캐릭터 페어는 평생 1회 ──────
    --
    -- ⚠️ [버그 수정 2026-08-26] ① 0.5초 만료 → 영구 기록  ② 내구도 검사보다 앞으로 이동.
    --
    -- [설계 의도] 잔불처럼 명시적으로 지속 판정인 것을 빼면, 모든 태거 아이템은
    --   "1발사 = 1히트" 다. 통나무 하나가 같은 사람을 두 번 칠 수 없어야 한다.
    --
    -- [문제 ①] 이 쿨이 0.5초 뒤에 지워지는데 내구도 무적은 1.5초다:
    --     0.0s  명중 → 내구도 흡수 + 무적 시작 + 쿨키 등록
    --     0.5s  쿨키 삭제                      ← 여기서 샌다
    --     1.5s  무적 해제 → 통나무가 아직 몸에 걸쳐 있음 → 두 번째 판정 → 다운
    --   (실측 2026-08-23: 흡수 30.087 → 다운 31.655 = 정확히 무적 1.5초 뒤)
    --
    -- [문제 ②] 영구 기록으로 바꿔도 이 블록이 내구도 검사 '뒤' 에 있으면
    --   흡수된 순간 early return 이라 기록이 안 남는다. 결국 같은 일이 반복된다.
    --   → 흡수든 다운이든 "이 아이템이 이 사람을 건드렸다" 는 사실을 먼저 남긴다.
    --   ⚠️ 그래서 이 블록은 반드시 내구도 검사보다 위에 있어야 한다. 순서를 바꾸지 말 것.
    --
    -- [왜 무적 시간을 늘리는 게 답이 아닌가] 통나무는 길이 40 stud 다.
    --   1.5초 안에 몸을 완전히 지나가려면 27 stud/s 이상이어야 하는데
    --   굴러 내려오는 속도가 그보다 느리다. 무적을 얼마로 잡든
    --   "더 느린 아이템" 앞에서 같은 일이 반복된다.
    --
    -- ⚠️ 키는 아이템 파트 인스턴스다(약한 참조 — 선언부 참조). 파트가 사라지면
    --   기록도 함께 회수되므로 누수가 없다.
    -- ⚠️ 지속 판정이 필요한 것(잔불 등)은 이 경로를 타면 안 된다.
    --   그런 시스템은 processHit 대신 자체 TakeDamage 를 쓴다(불기둥이 그렇다).
    local hitRec = damageCooldown[hitObject]
    if hitRec and hitRec[character.Name] then return end
    if not hitRec then
        hitRec = {}
        damageCooldown[hitObject] = hitRec
    end
    hitRec[character.Name] = true

    -- ── 0.75단계: 🛢️ 배럴 파열 ───────────────────────────
    -- 배럴은 러너에게 닿는 순간 사라지고 액체 지대를 남긴다(BarrelSpillSystem).
    -- ⚠️ 위치가 여기인 이유: "1발사 1히트" 기록 직후, 내구도 검사 앞이다.
    --   흡수되든 다운되든 '닿았다' 는 사실만으로 터져야 한다(설계 결정).
    --   내구도 뒤에 두면 흡수된 경우 early return 이라 안 터진다.
    -- ⚠️ 지대 파트 자신도 TaggerItems 그룹이라 이 경로를 탄다. 무한 재귀를
    --   막으려면 지대에는 BarrelSpill 속성이 없어야 한다(spawnSpill 이 안 붙인다).
    if hitObject and _G.BarrelBurst then
        local barrelModel = hitObject:FindFirstAncestorOfClass("Model")
        if barrelModel and barrelModel:GetAttribute("BarrelSpill") then
            local pos = hitObject.Position
            _G.BarrelBurst(barrelModel, barrelModel:GetAttribute("BarrelSpill"), pos, character)
        end
    end

    -- ── 0.75b단계: 🛡️ 태거 베이스 면역 ──────────────────
    -- ⚠️ [2026-09-01] 접촉형(굴리기) 아이템에도 베이스 면역을 적용한다.
    --   [왜] Spear·DemonSpear·Bomb·EnergyBall·FrostDragon 은 각자 _G.IsCharInTaggerBase 를
    --     부르지만, Touched → processHit 로만 들어오는 굴리기류(stone/Wood Log/
    --     Wooden Barrel/ItemNoob)는 아무 검사도 없었다. "태거 아이템은 베이스 안에서
    --     작동하면 안 된다"는 원칙(SpearSystem SPEAR-BASE 주석)에서 이 경로만 빠져 있었다.
    --   [드러난 계기] ItemNoob 히트박스를 키우자 계단(플레이트)에서 스폰되는 순간
    --     문턱에 선 러너 전원이 즉시 맞았다(실측 17:50:46 — 스폰 0.13초 뒤 3명 동시).
    --     굴러와서 맞은 게 아니라 '스폰 겹침'이라 회피 자체가 불가능했다.
    --   ⚠️ 플레이트도 면역 범위다. _G.IsCharInTaggerBase 선언부 주석 참조 —
    --     "소환 판정은 플레이트를 면제해야 하고, 면역 판정은 면제하면 안 된다".
    --   ⚠️ 위치가 여기인 이유: damageCooldown 기록 '뒤' 다. Touched 는 겹쳐 있는 동안
    --     초당 수십 번 발화하는데, 기록 앞에 두면 showBaseImmune(내부 호출) 이 그만큼 터진다.
    --     기록 뒤에 두면 아이템 하나당 러너 하나에 한 번만 표시된다.
    --   ⚠️ 배럴 파열 '뒤' 이기도 하다. 배럴은 베이스로 굴러 들어와 터져도 된다 —
    --     웅덩이 생성은 BarrelSpillSystem 의 BASE-BLOCK 이 따로 막는다(설계 결정).
    --     여기서 막는 것은 '피해' 뿐이다.
    if _G.IsCharInTaggerBase and _G.IsCharInTaggerBase(character) then return end

    -- 🎯 [계측 2026-09-20] 1단계 유효 히트. 밸런스에 영향 없음.
    --   [왜 여기인가] 무적·베이스면역·damageCooldown 가드를 전부 통과한 '확정 히트' 지점이고,
    --     **내구도 흡수 바로 앞**이다. 흡수분을 포함해야 "맞혔는데 안 죽었다"가 잡힌다 —
    --     한 줄이라도 아래로 내리면 흡수된 히트가 빠져 이 계측의 목적 자체가 사라진다.
    --   ⚠️ 1단계만 센다. 2단계 히트는 🔬 [K] 줄이 따로 담당한다.
    --   ⚠️ 불기둥은 processHit 을 안 타므로 여기 안 잡힌다(의도) — 환경 압박은 킹의 조준이 아니다.
    do
        local obs = _G.RoundObs
        if obs and (obs.startAt or 0) > 0 and (obs.stage2At or 0) == 0 then
            obs.s1Hits = (obs.s1Hits or 0) + 1
        end
    end

    -- ── 0.8단계: 🛡️ 내구도 ──────────────────────────────
    -- 내구도가 남아 있으면 1칸을 소모하고 이 히트를 통째로 무효화한다.
    --   [위치 근거] 위의 무적 체크들과 같은 계층이다. 여기서 return 하면 데미지도
    --   다운도 일어나지 않고, defaultDamage 의 폴백 즉사 경로(272행)도 타지 않는다.
    --   ⚠️ 처음엔 DownSystem.triggerDown 안에 넣었다가 실패했다. 그 함수의 false 는
    --      "다운 취소"가 아니라 "이미 다운/사망"을 뜻해서, 호출부가 폴백으로
    --      TakeDamage(DAMAGE) 를 돌렸고 오히려 러너를 죽였다(2026-08-23 실측).
    --   ⚠️ 외부 시스템(Bomb/Spear/DemonSpear/EnergyBall)도 _G.processHit 을 거치므로
    --      이 한 곳으로 전부 커버된다.
    --   ⚠️ 불기둥(FirePressureSystem)은 processHit 을 안 쓰고 TakeDamage 로 직접 깎는다.
    --      환경 압박은 내구도로 막히면 안 되므로 이게 의도한 동작이다.
    if _G.DurabilitySystem and _G.DurabilitySystem.absorb then
        -- 🗡️ [2026-09-19] 다중 히트 아이템. HitCount 칸만큼 내구도를 뚫는다.
        --   [왜] Spear 는 직선 투사체라 봇 회피에 가장 약해 명중률이 18% 뿐이다
        --     (다른 아이템 34%). 명중 '빈도'를 올리면 연사가 되어 "한 방 다운" 경제가
        --     깨지므로, 대신 명중 **1회의 가치**를 올린다.
        --   [효과] 내구도 1칸 러너가 Spear 에 맞으면 1칸을 소모하고 **그대로 다운**된다.
        --     내구도×부활×대시로 쌓인 3중 구제를 태거가 능동적으로 뚫는 수단이 된다.
        --   ⚠️ 이름 비교가 아니라 **속성**이다. 다른 아이템에 같은 성질을 주려면
        --     발사체에 HitCount 만 켜면 여기를 안 고쳐도 된다(GroundRayIgnore 와 같은 형태).
        --   ⚠️ hitObject 자신과 조상 모두에서 찾는다 — 투사체가 Model 이면 속성이
        --     최상위에 붙는데 Touched 는 자식 파트에서 올라오기 때문이다.
        --   ⚠️ [측정 주의] 봇전은 이 상향을 **과소평가한다**. 농민 6체는 내구도가 0이라
        --     아무 변화가 없고 히어로 4체에만 걸린다. 유저 러너는 전원 1칸이라 100% 걸린다.
        local hits = 1
        do
            local o = hitObject
            while o and o ~= workspace do
                local v = tonumber(o:GetAttribute("HitCount"))
                if v then hits = v break end
                o = o.Parent
            end
        end
        local absorbed = false
        local ok = pcall(function()
            absorbed = _G.DurabilitySystem.absorb(character, describeHitItem(hitObject), hits)
        end)
        if ok and absorbed then return end
    end

    local player = Players:GetPlayerFromCharacter(character)
    -- 태거 면역: 태거(유저/봇 KING 모두)는 태거 아이템에 다운/사망하지 않음.
    -- 봇은 Player가 아니라 GetPlayerFromCharacter가 nil → 캐릭터 자체의 Role 속성으로도 판별.
    local roleAttr = (player and player:GetAttribute("Role")) or character:GetAttribute("Role")
    if roleAttr and roleAttr ~= "Runner" then return end

    -- ── 위치 + 태거 + 효과 정보 수집 ────────────────────
    local root = character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")
    local position = root and root.Position or hitObject.Position

    local tagger = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p:GetAttribute("Role") == "Tagger" then
            tagger = p; break
        end
    end

    local equippedEffect = tagger
        and _G.GetEquippedKillEffect
        and _G.GetEquippedKillEffect(tagger)

    -- ── 3단계: 보호 아이템 체크 ─────────────────────────
    if tryConsumeProtection(character, position, equippedEffect, tagger) then
        return
    end

    -- ── 4단계: 효과별 분기 ──────────────────────────────
    -- 첫 명중은 항상 다운 (부활 기회 보존). victim-제어 이펙트는 죽는 순간 ExecuteKillEffect로 발동.
    local handler = defaultDamage
    handler(character, position, tagger, humanoid, player, hitObject)
end

-- ─────────────────────────────────────────────────────────────
-- 태거 아이템 Touched 이벤트 자동 등록
-- ─────────────────────────────────────────────────────────────
workspace.DescendantAdded:Connect(function(obj)
    if not obj:IsA("BasePart") then return end

    task.defer(function()
        local ok, groupName = pcall(function()
            return obj.CollisionGroup
        end)
        if not ok or groupName ~= "TaggerItems" then return end

        obj.Touched:Connect(function(hit)
            if not hit or not hit.Parent then return end
            processHit(hit.Parent, obj)
        end)
    end)
end)

-- BombSystem 등 다른 시스템에서 명시적으로 호출할 수 있도록 노출
_G.processHit = processHit

-- 🎤 [2026-08-29] 피해 면역 공용 판정.
--   [왜 필요한가] TakeDamage 호출 지점이 20곳이 넘는다(러너 무기 8종, 압박선, 곡사포,
--     마법책, 폭탄, 프드, 봇 등). 각각에 MicBombed 검사를 넣으면 반드시 하나를 빠뜨리고,
--     새 무기를 추가할 때 또 빠진다.
--   [사용법] 피해를 주기 직전에 부른다:
--       if _G.IsDamageImmune(victimChar) then return end
--   [현재 조건] 마이크밤 공연 중(MicBombed). 앞으로 다른 면역이 생기면 여기만 고친다.
--   ⚠️ 넉백·래그돌은 막지 않는다. 이건 '피해' 판정 전용이다.
-- 🔢 [2026-09-02] 화면에 띄울 데미지 숫자 환산.
--   [왜] TaggerCcGuard 는 '피해 감소'를 MaxHealth 배율로 구현한다(마이크밤 ×2 / 아이스보우 ×1.43).
--     실제 HP 는 그 스케일 위에서 깎이므로 판정은 맞지만, 무기가 클라로 보내는 숫자는
--     '때리려고 한 원본 값'이라 화면엔 감소가 반영되지 않는다.
--     실측(14:34): CC 중 "-8 → 1896/1950" / 해제 직후 "-8 → 940/975" — 같은 8 인데
--     분모가 두 배였다. 즉 실효는 4 인데 화면엔 8 로 떴다.
--   [사용법] 클라로 숫자를 보내기 직전에 감싼다:
--       Remote:FireClient(plr, "hitFX", _G.DisplayDamage(victimChar, dmg), ...)
--   ⚠️ 판정용 값(TakeDamage 인자)에는 쓰지 말 것. 그쪽은 원본이 맞다 —
--     스케일된 HP 를 원본 값으로 깎는 게 곧 '감소'다. 여기서 또 나누면 이중 적용된다.
--   ⚠️ 숫자를 띄우는 무기는 현재 3종뿐이다(ClassicSword / DiamondBladeSword /
--     DragonFireSword). 나머지 5종은 표시가 없어 대상이 아니다. 새 무기에 숫자를
--     붙일 땐 이 헬퍼를 함께 태울 것.
_G.DisplayDamage = function(character, dmg)
    if not character or not dmg then return dmg end
    local scale = character:GetAttribute("CcHpScale")
    if not scale or scale <= 0 then return dmg end
    return dmg / scale
end

_G.IsDamageImmune = function(character)
    -- 🎤 [변경 2026-09-02] 마이크밤 완전 면역 해제 → TaggerCcGuard 의 50% 감소로 일원화.
    --   [증상] 유저가 마이크밤을 던지면 8초간 자기 검이 한 대도 안 들어갔다.
    --     실측(14:17, 콘서트 2회): 그 구간 유저 타격 0건 / AI 러너 타격 30여 건.
    --   [원인] 여기서 true 를 돌려주면 러너 무기 8종의 가드가 전부 return 한다.
    --     반면 AI 러너(RunnerBotDriveController)는 이 가드를 안 타서 그대로 들어갔다.
    --     즉 '완전 면역'과 '50% 감소'가 서로 다른 대상에 걸려 규칙이 갈라져 있었다.
    --   [결정] 던진 사람이 자기 딜만 지우는 구조라 면역을 뺀다. CC 중 방어는
    --     TaggerCcGuard(MaxHealth ×2 = 피해 50% 감소)가 담당하고 유저·AI 가 같은 규칙을 받는다.
    --   ⚠️ 08-29 에 "8초 무력화가 2단계(20~40초)의 1/4 을 지운다"는 이유로 넣은 면역이다.
    --     지금은 절반만 들어가므로 그때의 우려가 그대로 되살아나진 않는다. 그래도
    --     2단계가 다시 짧아지면 여기부터 의심할 것.
    --   ⚠️ 상점 설명(ShopSystem mic_bomb)도 같이 고쳤다 — 같은 규칙이 두 곳에 있으면
    --     반드시 한쪽만 고쳐진다.
    --   ⚠️ 함수는 남긴다. 러너 무기 15곳의 호출부를 그대로 두면, 앞으로 다른 면역
    --     (예: 부활 직후 무적)이 생길 때 여기에만 조건을 추가하면 된다.
    return false
end

print("✅ ItemDamageSystem v6 활성화! (processHit 파이프라인 + 다운 시스템 연동 + _G.processHit 노출)")

-- 처형 연출 쪽(KillEffectSystem)에서도 정식 사망 처리를 호출할 수 있게 노출.
-- ⚠️ frozenCharacters 해제를 반드시 거쳐야 한다 — attachTaggerExec 의 HealthChanged 훅이
--    frozen 상태에서는 Health 를 MaxHealth 로 되돌리기 때문에, 외부에서 Health=0 만 쓰면 무효화된다.
--    (얼음 연출이 원본을 Destroy 하기 전에 이걸 호출해야 Died 이벤트가 정상 발생)
_G.KillFrozenCharacter = function(character)
    if not character or not character.Parent then return false end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    killCharacter(character)
    return true
end

-- ☠️ [2026-08-28] "처형 연출 진행 중인가" 공용 판정.
--   [왜 만드나] 지속 피해원(프드 잔류지대·톡스박스·잔불 등)이 처형 중인 캐릭터를
--     계속 때리고 있었다. processHit 은 416행에서 frozenCharacters 로 막지만,
--     피해원들이 processHit 을 부르기 '전에' 이미 Humanoid.Health 를 직접 만진다.
--     (FrostDragonIceGenerator:650 — hum.Health = 1 을 가드보다 먼저 실행)
--   [무슨 일이 생기나] 574행 HealthChanged 훅이 frozen 중엔 Health 를 MaxHealth 로
--     되돌린다. 그래서 처형 중 캐릭터의 체력이 매 프레임 흔들리고,
--     실측(09:58 판)에서 코핀 시퀀스·19초 안전망·워치독이 전부 사라졌다.
--     → 관이 맵에 영구히 남았다(진단 7건, 전부 얼음 활성 구간).
--   ⚠️ frozenCharacters 는 이 파일의 지역 테이블이라 밖에서 볼 수 없었다.
--     각 피해원이 CoffinSequence/IceFrozen/... 속성을 따로 검사하면 반드시
--     한쪽만 갱신되어 갈라진다(이번 세션에만 같은 패턴이 세 번 나왔다).
--     새 처형 이펙트를 추가할 때 frozenCharacters 만 채우면 여기로 전파된다.
--   ⚠️ 피해원은 '체력을 만지기 전에' 이걸 확인할 것. 나중에 확인하면 늦다.
_G.IsInKillSequence = function(character)
    if not character then return false end
    return frozenCharacters[character] == true
end

-- ─────────────────────────────────────────────────────────────
-- 태거 처형 훅: 태거는 다운/부활 없이 직접 TakeDamage로 죽으므로,
-- Health가 0 이하로 떨어지는 순간 가로채 살려두고(즉사 방지) →
-- victim-제어 이펙트가 장착돼 있으면 ExecuteKillEffect로 연출 위임.
-- (러너→태거 킬에도 punch/coffin 등 처형 연출이 나오게)
-- ─────────────────────────────────────────────────────────────
local function attachTaggerExec(character)
    if not character or character:GetAttribute("_TaggerExecHook") then return end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    character:SetAttribute("_TaggerExecHook", true)
    local executing = false
    hum.HealthChanged:Connect(function(newHealth)
        -- 처형 이펙트 진행 중이면 무적 (풀피 유지 + 추가 공격 무시). killCharacter가 frozen 해제 후 죽임.
        if frozenCharacters[character] then
            if newHealth < hum.MaxHealth then hum.Health = hum.MaxHealth end
            return
        end
        if executing or newHealth > 0 then return end
        executing = true
        hum.Health = hum.MaxHealth  -- 즉사 방지 (살려둔 채 처형 연출)
        local handled = _G.ExecuteKillEffect and _G.ExecuteKillEffect(character)
        if handled then
            -- 처형 연출 중 HP바 숨김 (기본 Humanoid바 + TaggerHpDisplay 빌보드)
            pcall(function() hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff end)
            local head = character:FindFirstChild("Head")
            local bar = head and head:FindFirstChild("TaggerHpDisplay")
            if bar then bar.Enabled = false end
        else
            hum.Health = 0  -- victim-제어 이펙트 없음 → 그냥 사망 (버스트는 onKill)
        end
    end)
end

-- taggerdummy (respawn 시 재부착)
do
    local d = workspace:FindFirstChild("taggerdummy")
    if d then attachTaggerExec(d) end
    workspace.ChildAdded:Connect(function(c)
        if c.Name == "taggerdummy" then task.wait(0.15); attachTaggerExec(c) end
    end)
end

-- 🤖 [2026-08-29] KING 봇에도 붙인다.
--   [증상] 봇 킹을 죽여도 처형 킬이펙트가 안 나오고 그냥 쓰러졌다
--     (실측 13:47:51 — "킹 피격 -22 → -10/150" 직후 바로 라운드 종료).
--   [원인] 위 두 경로는 taggerdummy(이름)와 Player(Role 속성)만 본다.
--     봇 킹은 Player 인스턴스가 아니라 workspace 의 Model 이라 어느 쪽에도 안 걸렸다.
--   ⚠️ 이름("KING") 대신 Role 속성으로 찾는다. BlackHoleSystem·FirePressureSystem 이
--     같은 방법을 쓴다 — 봇 이름이 바뀌어도 안 깨진다.
--   ⚠️ task.wait 후 붙인다. 스폰 직후엔 Humanoid 가 아직 없을 수 있다(taggerdummy 와 동일).
do
    local function tryAttachBotKing(m)
        if not m:IsA("Model") then return end
        if m:GetAttribute("Role") ~= "Tagger" then return end
        if Players:GetPlayerFromCharacter(m) then return end   -- 유저는 위 경로가 담당
        task.wait(0.15)
        if m.Parent then attachTaggerExec(m) end
    end
    for _, c in ipairs(workspace:GetChildren()) do task.spawn(tryAttachBotKing, c) end
    workspace.ChildAdded:Connect(function(c) task.spawn(tryAttachBotKing, c) end)
end

-- 실제 태거 플레이어 (Role=Tagger 일 때 캐릭터 감시)
local function hookTaggerPlayer(player)
    local function tryAttach()
        if player:GetAttribute("Role") == "Tagger" and player.Character then
            attachTaggerExec(player.Character)
        end
    end
    player.CharacterAdded:Connect(function() task.wait(0.15); tryAttach() end)
    player:GetAttributeChangedSignal("Role"):Connect(tryAttach)
    tryAttach()
end
for _, p in ipairs(Players:GetPlayers()) do hookTaggerPlayer(p) end
Players.PlayerAdded:Connect(hookTaggerPlayer)


-- ═══════════════════════════════════════════════════════════════
-- 🩸 [2026-08-27] 러너: HP 소진 → 즉사 대신 '다운'
--
-- [왜] 처치 경로가 둘인데 결과가 반대였다.
--   · 태거 아이템 명중  → triggerDown  → 부활 기회 있음 (관대)
--   · HP 소진(불꽃벽·쓰나미·킹 슬랩) → 즉사 → 기회 없음 (가혹)
--   조준해서 맞힌 쪽이 더 관대하고, 자동으로 도는 환경 압박이 더 가혹했다.
--   실측(2026-08-27): 1단계 처치 대부분이 쓰나미에 밀려 불꽃벽에 탄 즉사였다.
--   → HP 0 은 언제나 다운. 처치 경로와 무관하게 규칙을 하나로 만든다.
--
-- ⚠️ 이미 다운 상태면 개입하지 않는다. 그래야
--   · 강화 슬랩 처형(_G.KillDownedRunner)
--   · 다운 타이머 만료(자연사)
--   두 경로가 정상적으로 죽일 수 있다. 여기서 또 가로채면 러너가 불사가 된다.
--
-- ⚠️ Health = 1 로 살려두고 triggerDown 을 부른다. triggerDown 은 호출 시점에
--   Health > 0 을 전제한다(DownedBotSystem 이 그렇게 가드하고 있다).
--   1 로 되돌리면 HealthChanged 가 다시 돌지만 newHealth > 0 이라 즉시 빠져나간다.
--
-- ⚠️ triggerDown 이 false 를 돌려주는 경우(이미 다운/사망 등)엔 원래대로 죽인다.
--   여기서 살려두면 HP 0 인데 안 죽은 유령이 남는다.
--
-- ⚠️ 태거에겐 붙이지 않는다. 태거는 attachTaggerExec 가 따로 담당하고,
--   다운/부활 개념 자체가 없다(즉사가 의도된 설계).
-- ═══════════════════════════════════════════════════════════════
local function attachRunnerDownOnZero(character)
    if not character or character:GetAttribute("_RunnerDownHook") then return end
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    character:SetAttribute("_RunnerDownHook", true)
    hum.HealthChanged:Connect(function(newHealth)
        if newHealth > 0 then return end
        -- ⚠️ [2026-08-27] 발동 시점에 역할을 '다시' 본다.
        --   [왜] 훅은 캐릭터에 붙고, 캐릭터는 라운드가 바뀌어도 유지된다.
        --     러너로 붙은 훅이 그대로 남아, 다음 라운드에 그 사람이 태거가 되면
        --     태거가 다운되어 버렸다(실측 15:16:00 — 태거 다운 후 사망 판정).
        --   태거는 다운·부활 개념이 없다(즉사가 의도된 설계, attachTaggerExec 담당).
        do
            local plr = Players:GetPlayerFromCharacter(character)
            if plr and plr:GetAttribute("Role") ~= "Runner" then return end
        end
        if character:GetAttribute("Downed") then return end   -- 처형·자연사 경로를 막지 않는다
        -- ⚠️ [2026-08-27] 부활 소진자는 '다운 없이 즉사'가 규칙이다(defaultDamage 상단).
        --   그 경로가 humanoid:TakeDamage(DAMAGE) 로 죽이는데, 훅이 그걸 가로채
        --   다운으로 바꿔버려 규칙이 무력화됐다(실측 15:20:25 — "즉사!" 로그 직후 다운).
        --   라운드당 부활 1회 제한이 사실상 사라지므로 여기서 비켜준다.
        if character:GetAttribute("UsedRevive") then return end
        -- ⚠️ killDowned 는 Downed 를 '먼저 지우고' Health=0 을 준다. 그래서 위 가드만으로는
        --   사망 순간을 못 걸러 재다운 루프가 생긴다(실측 2026-08-27: 10초마다 무한 부활).
        --   DownSystem.killDowned 가 세우는 표식을 함께 본다.
        if character:GetAttribute("_DyingFromDown") then return end
        if not character.Parent then return end
        hum.Health = 1                                        -- 즉사 방지
        local ok = DownSystem.triggerDown(character, "HpDepleted")
        if not ok then hum.Health = 0 end                     -- 다운 실패 → 원래대로 사망
    end)
end

-- 유저 러너 (Role=Runner 일 때 캐릭터 감시) — hookTaggerPlayer 와 같은 형태
local function hookRunnerPlayer(player)
    local function tryAttach()
        if player:GetAttribute("Role") == "Runner" and player.Character then
            attachRunnerDownOnZero(player.Character)
        end
    end
    player.CharacterAdded:Connect(function() task.wait(0.15); tryAttach() end)
    player:GetAttributeChangedSignal("Role"):Connect(tryAttach)
    tryAttach()
end
for _, p in ipairs(Players:GetPlayers()) do hookRunnerPlayer(p) end
Players.PlayerAdded:Connect(hookRunnerPlayer)

-- AI 러너(농민봇). 라운드마다 workspace 에 스폰되므로 ChildAdded 로 받는다.
-- ⚠️ 속성이 붙기 전에 ChildAdded 가 먼저 도는 경우가 있어 잠깐 기다린다.
do
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("AIRunner") then attachRunnerDownOnZero(m) end
    end
    workspace.ChildAdded:Connect(function(c)
        if not c:IsA("Model") then return end
        task.wait(0.2)
        if c.Parent and c:GetAttribute("AIRunner") then attachRunnerDownOnZero(c) end
    end)
end
