-- WalkSpeedManager — 이동 상태(mobility) 단일 창구
-- ════════════════════════════════════════════════════════════════
-- [왜 만들었나]
--   실측 2026-09-12: 히어로봇 2명이 HammerHigh 를 뽑은 판에서 킹이 영구 행동불능.
--   원인은 "여러 시스템이 같은 WalkSpeed 를 각자 백업·복원"이었다.
--     A 슬램: prev=14 저장 → 0 으로
--     B 슬램: prev=0 저장(이미 0이니까) → 0 으로
--     A 만료: 14 복원 / B 만료: 0 복원  ← 나중에 끝나는 쪽이 이긴다
--   같은 사고가 KatanaSword2 에도 있었다(주석 [COUNTER-SPEED-LEAK]:
--   16 → 8 → 4 → 2 로 계속 느려지고 원래 값이 영영 사라짐).
--   ⚠️ 그리고 2026-09-13 에 카타나 '태거 스턴'에서 또 났다 — 0.08초 차 카운터 2발로
--     킹이 13초간 WalkSpeed 0. 어제 옮긴 건 '자기 감속'뿐이고 '남에게 거는 스턴'은
--     스냅샷 그대로였다. 같은 스크립트 안에서도 경로마다 따로 봐야 한다.
--   실측 2026-09-13: `.WalkSpeed = ` 직접 대입이 29개 스크립트 / 97곳.
--
-- [설계] 각 시스템은 '배율'만 등록한다. 실제 대입은 여기 한 곳에서만 한다.
--   최종 속도 = BASE × (모든 등록 배율의 곱)
--   ⚠️ 절대값(0, 16)을 주고받지 않는다. 그래야 "누가 원본을 아는가" 문제가 사라진다.
--   ⚠️ 같은 source 로 다시 set 하면 갱신이다(중첩 아님). 슬램 2회가 0.5×0.5 가 되지 않는다.
--
-- [2026-09-13 확장] WalkSpeed 외에 점프·PlatformStand 도 같은 source 로 묶는다.
--   [왜] 관리자가 WalkSpeed 만 맡으니 나머지 축은 각 시스템이 여전히 스냅샷+만료 토큰으로
--     따로 관리했다. 같은 토큰 코드가 HammerHigh(_HammerStunToken)·
--     KatanaSword2(_KatanaStunToken)·TaggerCcGuard(immuneToken) 에 세 벌 복사돼 있다.
--     source 하나가 모든 축을 쥐면 "같은 source 는 갱신" 규칙이 그대로 적용돼
--     토큰이 필요 없어진다 — 마지막 것만 남는 걸 관리자가 보장한다.
--   ⚠️ 이름은 WalkSpeedManager / _G.WalkSpeed 그대로 둔다. 호출부와 기존 주석·grep 이
--     전부 이 이름을 쓴다. 이름을 바꾸면 얻는 것 없이 선례 추적만 끊긴다.
--
-- [쓰는 법]
--   _G.WalkSpeed.set(char, "HammerSlam", 0)      -- 숫자 = 이동속도 배율만 (기존 호출부 그대로)
--   _G.WalkSpeed.set(char, "HammerSlam", { walk = 0, jump = 0, platformStand = true })
--   _G.WalkSpeed.set(char, "KatanaStun", { walk = 0, jump = 0, flags = { "Stunned" } })
--   _G.WalkSpeed.clear(char, "HammerSlam")       -- 그 source 가 건 축을 한 번에 전부 해제
--   _G.WalkSpeed.clearAll(char)                  -- 라운드 정리·리스폰
--   _G.WalkSpeed.setBase(char, 14)               -- 기준값 변경(2단계 태거 감속 등)
--   _G.WalkSpeed.debug(char)                     -- /ws 출력
--
-- [flags] 캐릭터 속성 표식(Stunned 등)도 같은 source 에 묶는다.
--   [왜] 실측 2026-09-13: "Stunned" 의 소유자가 셋이다 —
--     KatanaSword2 · PushTool.Server · ThroneExhaustSystem. 정리 경로까지 하면 다섯.
--     여럿이 켜고 끄는 공유 불리언이라 PlatformStand 와 정확히 같은 문제다:
--     먼저 끝난 쪽이 끄면 아직 묶여 있는데 표식이 사라진다.
--     그러면 TaggerCcGuard 가 CC 지속을 짧게 역산해 면역도, HP 피해감소(1.43×)도
--     일찍 풀린다 — 킹은 아직 못 움직이는데 보호만 먼저 꺼진다.
--   ⚠️ 해제는 false 가 아니라 nil 로 쓴다. 읽는 쪽이 전부 `== true` 또는 truthy 검사이고,
--     RoundSystem·RoundStateResetServer 의 정리 경로도 nil 을 쓴다 — 그쪽에 맞춘다.
--   ⚠️ HammerStunned 는 Character 가 아니라 Humanoid 에 붙는다(TaggerCcGuard:84).
--     HammerHigh 를 이관할 때 캐릭터 쪽으로 옮길지 먼저 정할 것. 여기선 캐릭터 속성만 맡는다.
--
-- ⚠️ 안 건 축은 건드리지 않는다. jump/platformStand 를 한 번도 등록하지 않은 캐릭터에는
--   그 속성을 아예 쓰지 않는다 — 아직 이관 안 된 시스템(DownSystem·Gauntlet·Speed Potion)의
--   값을 빼앗지 않기 위해서다. 마지막 해제 때 딱 한 번 기본값으로 되돌리고 손을 뗀다.
-- ⚠️ 29곳을 한꺼번에 바꾸지 않는다. 사고가 난 곳부터 하나씩 옮긴다 —
--   한 번에 고치면 어디서 깨졌는지 알 수 없다.
-- ⚠️ 이 관리자를 쓰지 않는 시스템이 직접 대입하면 그 값이 이긴다.
--   그건 의도된 동작이다(점진 이행). 다만 옮긴 시스템끼리는 안전하다.

local Players = game:GetService("Players")

local DEFAULT_BASE = 16

-- 점프 기준값. 실측 2026-09-13 StarterPlayer:
--   CharacterUseJumpPower = false / CharacterJumpHeight = 7.2 / CharacterJumpPower = 50
-- ⚠️ JumpPower 와 JumpHeight 는 서로 연동되지 않는다(JumpPower=0 을 넣어도 JumpHeight 는
--   7.2 그대로 — 빈 Humanoid 로 실측). 이 게임은 UseJumpPower=false 라 JumpHeight 가
--   점프를 결정하고, JumpPower 대입은 아무 효과가 없다. KatanaSword2 의
--   `tHum.JumpPower = 0` 이 그래서 몇 달간 죽은 줄이었다(스턴이 점프를 못 막았다).
-- ⚠️ 그래도 UseJumpPower 를 보고 갈라 쓴다. DoubleJump.getJumpVelocity 와 같은 규약이라
--   나중에 StarterPlayer 설정이 바뀌어도 여기서 깨지지 않는다.
local JUMP_BASE_HEIGHT = 7.2
local JUMP_BASE_POWER  = 50

-- [character] = {
--   base  = 16,
--   mult  = { [source] = { walk = 0.5, jump = 0, platform = true, flags = { Stunned = true } } },
--   wrote = { jump = false, platform = false, flags = {} },  -- 관리자가 지금 그 축을 쥐고 있는가
-- }
local state = setmetatable({}, { __mode = "k" })

local function ensure(char)
    local st = state[char]
    if not st then
        st = { base = DEFAULT_BASE, mult = {}, wrote = { jump = false, platform = false, flags = {} } }
        state[char] = st
    end
    return st
end

-- 등록값 정규화. 숫자면 '이동속도 배율만' 건 것으로 본다 — 기존 호출부 호환 경로다.
--   ⚠️ 0 은 Lua 에서 참이므로 `if e.walk then` 로 걸러도 스턴(배율 0)이 살아남는다.
--     nil 과 0 을 구분하는 게 이 테이블의 전부다.
local function normalize(v)
    if type(v) == "number" then
        return { walk = v }
    elseif type(v) == "table" then
        local f = nil
        if v.flags then
            f = {}
            for _, name in ipairs(v.flags) do f[name] = true end
        end
        return { walk = v.walk, jump = v.jump, platform = v.platformStand, flags = f }
    end
    return nil
end

-- 실제 대입. 모든 배율의 곱을 base 에 적용한다.
local function apply(char)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Parent == nil then return end
    local st = ensure(char)

    local walkM, jumpM = 1, 1
    local anyJump, anyPlatform, wantPlatform = false, false, false
    local wantFlags = {}
    for _, e in pairs(st.mult) do
        if e.walk then walkM = walkM * e.walk end
        if e.jump then
            jumpM = jumpM * e.jump
            anyJump = true
        end
        if e.platform ~= nil then
            anyPlatform = true
            if e.platform then wantPlatform = true end
        end
        if e.flags then
            for name in pairs(e.flags) do wantFlags[name] = true end
        end
    end

    hum.WalkSpeed = st.base * walkM

    -- 점프. 등록이 하나라도 있으면 계산값, 마지막 해제에서 딱 한 번 기본값으로 되돌린다.
    if anyJump then
        st.wrote.jump = true
        if hum.UseJumpPower then
            hum.JumpPower = JUMP_BASE_POWER * jumpM
        else
            hum.JumpHeight = JUMP_BASE_HEIGHT * jumpM
        end
    elseif st.wrote.jump then
        st.wrote.jump = false
        if hum.UseJumpPower then
            hum.JumpPower = JUMP_BASE_POWER
        else
            hum.JumpHeight = JUMP_BASE_HEIGHT
        end
    end

    -- PlatformStand 는 불리언이라 곱이 아니라 OR 다 — 하나라도 원하면 눕는다.
    -- ⚠️ 해제 시 false 를 쓰는 건 살아 있을 때만. 사망 래그돌이 PlatformStand 를 쓰는데
    --   여기서 무조건 false 를 쓰면 시체를 일으켜 세운다.
    if anyPlatform then
        st.wrote.platform = true
        hum.PlatformStand = wantPlatform
    elseif st.wrote.platform then
        st.wrote.platform = false
        if hum.Health > 0 then
            hum.PlatformStand = false
        end
    end

    -- 표식 속성. 하나라도 원하면 true, 마지막 source 가 빠질 때만 지운다.
    --   ⚠️ 관리자가 쥔 적 없는 이름은 절대 건드리지 않는다 — 아직 이관 안 된
    --     PushTool·ThroneExhaust 가 직접 세운 Stunned 를 빼앗지 않기 위해서다.
    for name in pairs(wantFlags) do
        st.wrote.flags[name] = true
        char:SetAttribute(name, true)
    end
    for name in pairs(st.wrote.flags) do
        if not wantFlags[name] then
            st.wrote.flags[name] = nil
            char:SetAttribute(name, nil)
        end
    end
end

local WS = {}

-- 기준 속도 변경(2단계 태거 감속, 역할별 기본값 등).
--   ⚠️ 배율이 아니라 '기준'이다. 여기에 CC 를 섞지 말 것.
function WS.setBase(char, value)
    if not char then return end
    ensure(char).base = value or DEFAULT_BASE
    apply(char)
end

function WS.getBase(char)
    return char and ensure(char).base or DEFAULT_BASE
end

-- 배율 등록. 같은 source 는 갱신된다(중첩 없음).
--   source 는 문자열 상수로 — "HammerSlam", "MicBomb", "Downed" 처럼.
--   value = 숫자(이동속도 배율) 또는 { walk=, jump=, platformStand=, flags= }
--   duration = 주면 그 뒤 자동 해제(초). 안 주면 호출자가 clear 해야 한다.
--
-- ⚠️ [source 를 시전자별로 나눌 것] 여럿이 동시에 같은 대상을 묶는 CC 는
--   "KatanaStun:"..시전자 처럼 키를 나눈다. 하나로 합치면 먼저 예약된 만료가
--   아직 유효한 남의 CC 까지 풀어버린다(실측 2026-09-13: 0.08초 차 카운터 2발에서
--   둘째 스턴이 0.42초 손실). 키를 나누면 마지막 하나가 빠질 때 비로소 풀린다 —
--   만료 토큰이 하던 일을 키 분리가 대신한다.
-- ⚠️ [만료는 매니저 상주 루프가 돌린다] duration 을 주면 아래 Heartbeat 스윕이 해제한다.
--   ❌ 처음엔 WS.set 안에서 task.delay 를 걸었다. 함수 본문이 이 파일에 있으니 만료도
--     여기 소유라고 적었는데 **틀렸다.** task.delay 는 '지금 실행 중인 스레드'에 묶인다 —
--     HammerHighScript 가 이 함수를 부르면 그 툴 스크립트 혈통의 예약이 된다.
--   [실측 2026-09-13] 22:19:51 / 22:21:43 / 22:26:05 — 슬램이 들어간 30ms 안에 시전 봇이
--     죽은 판 3건. Tool 이 사라지며 콜백이 회수됐고 **실행이 안 되니 에러도 안 남았다.**
--     킹은 각각 3초 · 18초 · 30초를 WalkSpeed 0 으로 갇혔다(강타 취소의 직접 대입이
--     우연히 풀어준 게 전부). "한 방 맞으면 다시는 못 움직인다"의 정체다.
function WS.set(char, source, value, duration)
    if not (char and source) then return end
    local e = normalize(value)
    if not e then return end
    if duration and duration > 0 then
        e.expireAt = os.clock() + duration
    end
    ensure(char).mult[source] = e
    apply(char)
end

function WS.clear(char, source)
    if not (char and source) then return end
    local st = state[char]
    if not st then return end
    st.mult[source] = nil
    apply(char)
end

-- 이 캐릭터에 걸린 모든 배율 제거(라운드 정리·리스폰).
function WS.clearAll(char)
    if not char then return end
    local st = state[char]
    if not st then return end
    st.mult = {}
    apply(char)
end

-- 진단: 지금 누가 뭘 걸고 있나. 계산값과 실제값이 다르면 = 관리자를 안 거친 시스템이 덮어썼다.
function WS.debug(char)
    local st = char and state[char]
    if not st then return "(등록 없음)" end

    local parts = {}
    local walkM, jumpM = 1, 1
    local anyJump, anyPlatform = false, false
    for k, e in pairs(st.mult) do
        local bits = {}
        if e.walk then
            bits[#bits + 1] = string.format("w%.2f", e.walk)
            walkM = walkM * e.walk
        end
        if e.jump then
            bits[#bits + 1] = string.format("j%.2f", e.jump)
            jumpM = jumpM * e.jump
            anyJump = true
        end
        if e.platform ~= nil then
            bits[#bits + 1] = "ps=" .. tostring(e.platform)
            anyPlatform = true
        end
        if e.flags then
            local names = {}
            for name in pairs(e.flags) do names[#names + 1] = name end
            table.sort(names)
            bits[#bits + 1] = "@" .. table.concat(names, "+")
        end
        parts[#parts + 1] = k .. "=" .. table.concat(bits, "/")
    end
    table.sort(parts)

    local hum = char:FindFirstChildOfClass("Humanoid")
    local out = string.format("base %.1f × [%s] = %.1f (실제 %.1f)",
        st.base, table.concat(parts, ", "), st.base * walkM,
        hum and hum.WalkSpeed or -1)

    if anyJump or st.wrote.jump then
        local usePower = hum and hum.UseJumpPower
        local jBase = usePower and JUMP_BASE_POWER or JUMP_BASE_HEIGHT
        local jCur = -1
        if hum then
            if usePower then jCur = hum.JumpPower else jCur = hum.JumpHeight end
        end
        out = out .. string.format(" | jump %.2f (실제 %.2f)", jBase * jumpM, jCur)
    end
    if anyPlatform or st.wrote.platform then
        out = out .. " | PlatformStand " .. tostring(hum and hum.PlatformStand)
    end
    local held = {}
    for name in pairs(st.wrote.flags) do held[#held + 1] = name end
    if #held > 0 then
        table.sort(held)
        out = out .. " | 표식 " .. table.concat(held, ", ")
    end
    return out
end

-- ⏱ 만료 스윕 — 이 스크립트(부팅 스레드)가 소유하는 상주 루프.
--   호출자 무기가 파괴돼도 해제는 계속 돈다. KillEffectSystem 의 scheduleKill 과 같은 형태다.
--   ⚠️ 비용: state 는 라운드당 캐릭터 십여 개뿐이고 약한참조라 자동 정리된다.
--     등록이 하나도 없으면 첫 줄에서 바로 빠진다.
--   ⚠️ 순회 중 지우지 않는다 — 만료 목록을 모은 뒤 지우고 apply 는 캐릭터당 1회만 부른다.
local RunService = game:GetService("RunService")
RunService.Heartbeat:Connect(function()
    if next(state) == nil then return end
    local now = os.clock()
    for char, st in pairs(state) do
        local expired
        for source, e in pairs(st.mult) do
            if e.expireAt and now >= e.expireAt then
                expired = expired or {}
                expired[#expired + 1] = source
            end
        end
        if expired then
            for _, source in ipairs(expired) do
                st.mult[source] = nil
            end
            apply(char)
        end
    end
end)

_G.WalkSpeed = WS

-- 캐릭터가 사라지면 정리 (약한참조라 자동이지만 명시적으로도 지운다)
Players.PlayerRemoving:Connect(function(plr)
    if plr.Character then state[plr.Character] = nil end
end)

print("🏃 WalkSpeedManager 준비 (_G.WalkSpeed.set / clear / setBase — walk + jump + platformStand + flags)")
