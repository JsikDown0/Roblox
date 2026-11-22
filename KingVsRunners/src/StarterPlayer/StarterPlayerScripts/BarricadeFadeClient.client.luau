-- ═══════════════════════════════════════════════════════════════
local RunService = game:GetService("RunService")
-- 🧱 성문 페이드 (태거 시야 확보)
--
-- [왜] 성문이 태거와 러너 사이를 막고 서 있어, 태거 입장에서는
--      1단계 내내 시야를 가리는 벽이 된다. 아이템을 조준해야 하는데
--      앞이 안 보이면 게임이 안 된다.
--
-- [규칙]
--   · 태거: 라운드 시작 1.5초까지 보이다가 서서히 사라진다
--           → "벽이 있다"는 인지는 주되, 그 뒤로는 시야를 연다
--   · 태거: 2단계가 시작되면 다시 불투명으로 복원
--           → 러너가 부수러 오는 대상이므로 보여야 한다
--   · 러너: 항상 불투명. 아무 변화 없음
--
-- ⚠️ [실패 기록 2026-08-24] 예전 버전은 Barricades 폴더의 '판정 파트'를
--    페이드했다. 그런데 통짜 구조물 전환 후 판정 파트는 Transparency=1 인
--    보이지 않는 판정 전용이 되었고, 실제 벽은 Gatehouse 구조물이다.
--    → 페이드 대상을 연결 구조물로 바꾼다.
-- ⚠️ 원본 투명도를 기억해둔다. 성문에는 원래 반투명한 파트(창문 등)가
--    섞여 있을 수 있어, 복원할 때 전부 0 으로 만들면 원래 모습이 깨진다.
-- ═══════════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer

local SHOW_TIME   = 1.5    -- 라운드 시작 후 이만큼은 보여준다
local FADE_TIME   = 1.0    -- 사라지는 데 걸리는 시간
local FADED_ALPHA = 0.95   -- 사실상 투명 (완전히 1 로 하면 실루엣도 사라진다)
local RESTORE_TIME = 0.4   -- 2단계 복원 속도

local ORIG_ATTR = "_FadeOrigTransparency"

local function isTagger()
    return player:GetAttribute("Role") == "Tagger"
end

-- 페이드 대상: 판정 파트에 연결된 구조물의 '보이는' 파트들
-- ⚠️ 이미 투명한 파트(Middle Wall 등)는 제외한다. 건드려도 의미가 없고,
--    복원할 때 원래 투명이던 걸 불투명하게 만들면 도약 방지벽이 드러난다.
local function gateParts()
    local list = {}
    for _, mn in ipairs({ "map1", "map2" }) do
        local m = workspace:FindFirstChild(mn)
        if m then
            local f = m:FindFirstChild("Barricades", true)
            if f then
                for _, seg in ipairs(f:GetChildren()) do
                    local gname = seg:GetAttribute("BarricadeGate")
                    if gname then
                        local wanted = {}
                        for _, t in ipairs(string.split(gname, ",")) do
                            wanted[t:gsub("^%s+", ""):gsub("%s+$", "")] = true
                        end
                        for _, d in ipairs(m:GetDescendants()) do
                            if wanted[d.Name] then
                                if d:IsA("BasePart") and d.Transparency < 1 then
                                    list[#list + 1] = d
                                end
                                for _, x in ipairs(d:GetDescendants()) do
                                    if x:IsA("BasePart") and x.Transparency < 1 then
                                        list[#list + 1] = x
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return list
end

local function rememberOrig(p)
    if p:GetAttribute(ORIG_ATTR) == nil then
        p:SetAttribute(ORIG_ATTR, p.Transparency)
    end
    return p:GetAttribute(ORIG_ATTR)
end

-- 🔥 성문에 붙은 불꽃(횃불)도 함께 처리한다.
-- ⚠️ [실측 2026-08-24] 파트를 투명하게 해도 Fire/PointLight 는 그대로 남아
--    "공중에 불꽃만 떠 있는" 그림이 된다. 시야 확보라는 목적도 반쯤 무산된다.
--    Fire 는 Transparency 가 없으므로 Enabled 로 끈다.
local function gateEffects()
    local list = {}
    for _, mn in ipairs({ "map1", "map2" }) do
        local m = workspace:FindFirstChild(mn)
        if m then
            local f = m:FindFirstChild("Barricades", true)
            if f then
                for _, seg in ipairs(f:GetChildren()) do
                    local gname = seg:GetAttribute("BarricadeGate")
                    if gname then
                        local wanted = {}
                        for _, t in ipairs(string.split(gname, ",")) do
                            wanted[t:gsub("^%s+", ""):gsub("%s+$", "")] = true
                        end
                        for _, d in ipairs(m:GetDescendants()) do
                            if wanted[d.Name] then
                                for _, x in ipairs(d:GetDescendants()) do
                                    if x:IsA("Fire") or x:IsA("Smoke")
                                       or x:IsA("ParticleEmitter")
                                       or x:IsA("PointLight") or x:IsA("SpotLight") then
                                        list[#list + 1] = x
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return list
end

local function setEffects(on)
    for _, e in ipairs(gateEffects()) do
        e.Enabled = on
    end
end

-- ⚠️ [성능 2026-08-25] 파트마다 Tween 을 만들면 594~787개가 한 프레임에
--    생성돼 태거 화면만 크게 끊긴다(러너는 isTagger 로 걸러져 실행 안 됨).
--    → Tween 하나 없이 RenderStepped 한 개로 전부 보간한다.
local fadeConn = nil
-- ⚠️ 중복 페이드 방지. 2단계에도 반투명을 유지하므로 상태를 기억한다.
local faded = false
local function animateAll(parts, getTarget, duration)
    if fadeConn then fadeConn:Disconnect(); fadeConn = nil end
    local from = {}
    for _, p in ipairs(parts) do from[p] = p.Transparency end
    local t0 = os.clock()
    fadeConn = RunService.RenderStepped:Connect(function()
        local a = math.clamp((os.clock() - t0) / duration, 0, 1)
        -- Quad Out 과 비슷한 곡선
        local e = 1 - (1 - a) * (1 - a)
        for _, p in ipairs(parts) do
            if p.Parent then
                local f = from[p] or 0
                p.Transparency = f + (getTarget(p) - f) * e
            end
        end
        if a >= 1 then
            fadeConn:Disconnect(); fadeConn = nil
        end
    end)
end

-- 🔴 [버그수정 2026-09-20] 페이드를 "한 순간의 스냅샷"에서 "유지되는 상태"로 바꾼다.
--   [증상] map2 성문이 여러 라운드를 거치면 일부만 반투명해진다(라이브 제보).
--   [확인된 것]
--     · fadeOut() 은 gateParts() 를 그 순간 1회 훑고 그 목록만 보간한다.
--       그 뒤에 '나타난' 파트는 영원히 불투명하게 남는다 — 재적용 경로가 아예 없다.
--     · 성문은 라운드마다 실제로 새로 생긴다: BarricadeSystem.rebuild 가 Barricades
--       폴더를 Destroy 후 재생성하고, restoreGates 가 파괴된 성문을 백업에서 Clone 한다.
--     · workspace.StreamingEnabled = true. map2 성문은 783파트
--       (Gatehouse2 3개 × 131 + Gate2 6개 × 65)로 map1(587, 사실상 3덩이)보다
--       크고 Z 827~969 로 넓게 퍼져 있어 늦게 도착할 여지가 더 크다.
--   [왜 이렇게 고치나] 늦는 원인이 clone 이든 streaming 이든 구멍은 하나다 —
--     "그 순간 목록에 없던 파트". 원인을 가려내 거르는 대신 결과를 보장한다:
--     faded 인 동안 게이트 파트는 무조건 FADED_ALPHA 다.
--     (지면 레이캐스트 '제외 목록'을 법선 보장으로 뒤집은 것과 같은 형태)
--   ⚠️ workspace.DescendantAdded 가 아니라 맵 폴더에만 건다. workspace 전체에 걸면
--     아이템·투사체·이펙트까지 전부 타고 들어와 태거 화면에서만 도는 헛일이 커진다.
--     맵 폴더는 비활성 맵도 workspace 에 남아 교체되지 않는다(BarricadeSystem:988).
local lateConns  = {}
local lateCount  = 0
local lateLogAt  = 0

-- 게이트 이름 집합. 진실은 Barricades 세그먼트의 BarricadeGate 속성이다
-- (이름 하드코딩 금지 — TaggerUIScript:977 이 같은 이유로 경고하고 있다).
local function wantedGateNames()
    local w = {}
    for _, mn in ipairs({ "map1", "map2" }) do
        local m = workspace:FindFirstChild(mn)
        local f = m and m:FindFirstChild("Barricades", true)
        if f then
            for _, seg in ipairs(f:GetChildren()) do
                local g = seg:GetAttribute("BarricadeGate")
                if g then
                    for _, t in ipairs(string.split(g, ",")) do
                        w[t:gsub("^%s+", ""):gsub("%s+$", "")] = true
                    end
                end
            end
        end
    end
    return w
end

-- ⚠️ 상위 8단계까지만 거슬러 본다. 성문은 Model 중첩이 깊다
--    (_G.IsGateStructure 가 서버에서 같은 깊이를 쓴다 — BarricadeSystem:100).
local function isGatePart(inst, wanted)
    if not inst:IsA("BasePart") then return false end
    local cur, n = inst, 0
    while cur and n < 8 do
        if wanted[cur.Name] then return true end
        cur = cur.Parent
        n = n + 1
    end
    return false
end

local function startLateWatch()
    if #lateConns > 0 then return end
    local wanted = wantedGateNames()
    lateCount, lateLogAt = 0, os.clock()
    for _, mn in ipairs({ "map1", "map2" }) do
        local m = workspace:FindFirstChild(mn)
        if m then
            lateConns[#lateConns + 1] = m.DescendantAdded:Connect(function(inst)
                if not faded or not isTagger() then return end
                if not isGatePart(inst, wanted) then return end
                -- ⚠️ 원래 투명한 판정 파트(Middle Wall·GateBlocker2·GatePocketFill2)는
                --    건드리지 않는다. gateParts() 의 '< 1' 필터와 같은 규칙이다.
                if inst.Transparency >= 1 then return end
                rememberOrig(inst)
                inst.Transparency = FADED_ALPHA
                lateCount = lateCount + 1
                if os.clock() - lateLogAt > 2 then
                    lateLogAt = os.clock()
                    print(string.format("🧱 [BarricadeFade] 뒤늦게 도착한 게이트 파트 %d개 추가 페이드(누적)", lateCount))
                end
            end)
        end
    end
end

local function stopLateWatch()
    for _, c in ipairs(lateConns) do pcall(function() c:Disconnect() end) end
    table.clear(lateConns)
    if lateCount > 0 then
        print(string.format("🧱 [BarricadeFade] 이번 라운드 늦게 도착한 게이트 파트 총 %d개", lateCount))
        lateCount = 0
    end
end

local function fadeOut()
    if not isTagger() then return end
    faded = true
    startLateWatch()
    local parts = gateParts()
    local n = #parts
    for _, p in ipairs(parts) do rememberOrig(p) end
    animateAll(parts, function() return FADED_ALPHA end, FADE_TIME)
    if n > 0 then
        print(string.format("🧱 [BarricadeFade] 태거 시야 확보 — %d파트 페이드", n))
    end

    -- 🔥 불꽃은 Transparency 가 없어 서서히 사라지게 할 수 없다.
    -- ⚠️ 페이드가 거의 끝난 뒤에 끈다. 먼저 끄면 "벽은 있는데 불만 사라지는"
    --    어색한 순간이 생긴다.
    task.delay(FADE_TIME * 0.7, function()
        if ReplicatedStorage:GetAttribute("RoundPhase") == "stage1" and isTagger() then
            setEffects(false)
        end
    end)
end

local function restore()
    -- ⚠️ 감시 해제는 isTagger 가드보다 먼저다. 라운드 종료 시 Role 이 먼저 지워지면
    --   아래 가드에서 조기 return 되어 감시가 영구히 살아남는다
    --   ("끄는 코드에 도달이 보장되는가" — 조기 return 가드마다 복구자 확인).
    stopLateWatch()
    if not isTagger() then return end
    faded = false

    setEffects(true)
    -- ⚠️ Tween 대신 단일 RenderStepped 보간 (594~787파트)
    local parts = gateParts()
    local n = #parts
    animateAll(parts, function(p)
        return p:GetAttribute(ORIG_ATTR) or 0
    end, RESTORE_TIME)
    if n > 0 then
        print(string.format("🧱 [BarricadeFade] 2단계 — %d파트 복원", n))
    end
end

-- ⚠️ 페이드된 파트는 Transparency 가 0.95 라 gateParts() 의 '< 1' 필터를
--    여전히 통과한다. 복원 대상 수집에 문제가 없다.

-- ── 라운드 상태 추적 ───────────────────────────────────────────
-- ⚠️ 이벤트만 믿으면 안 된다. 캐릭터 리스폰 시 스크립트가 재시작되므로
--    시작 시 현재 phase 를 읽고, 이후 변화를 신호로 따라간다.
local lastPhase = nil

local function onPhase(ph)
    if ph == lastPhase then return end
    lastPhase = ph

    if ph == "stage1" then
        -- 1.5초 보여준 뒤 사라진다
        task.delay(SHOW_TIME, function()
            if ReplicatedStorage:GetAttribute("RoundPhase") == "stage1" then
                fadeOut()
            end
        end)
    elseif ph == "stage2" then
        -- ⚠️ [2026-08-25] 2단계에도 반투명을 유지한다.
        --   [왜] 예전엔 여기서 restore() 를 불러 성벽이 불투명해졌다.
        --   그러면 러너가 2단계 도달 시점을 통제하므로,
         --   "빨리 뚫으면 태거 조준이 막힌다"는 의도치 않은 전략이 생긴다.
        --   태거는 2단계에도 아이템을 조준해야 하고(tnt 등),
        --   성벽의 실체는 러너 시점에서 이미 드러난다.
        --   → 태거에게는 라운드 내내 비쳐 보이게 둔다.
        if not faded then fadeOut() end
    else
        -- ⚠️ 라운드가 끝나면(intermission 등) 원래 모습으로 되돌린다.
        --    안 그러면 로비에서도 성벽이 비쳐 보인다.
        if faded then restore() end
    end
end

onPhase(ReplicatedStorage:GetAttribute("RoundPhase"))
ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(function()
    onPhase(ReplicatedStorage:GetAttribute("RoundPhase"))
end)

-- 역할이 늦게 정해지는 경우 대비
player:GetAttributeChangedSignal("Role"):Connect(function()
    if not isTagger() then return end
    local ph = ReplicatedStorage:GetAttribute("RoundPhase")
    if ph == "stage1" then
        task.delay(SHOW_TIME, function()
            if isTagger() and ReplicatedStorage:GetAttribute("RoundPhase") == "stage1" then
                fadeOut()
            end
        end)
    elseif ph == "stage2" then
        -- ⚠️ 역할이 늦게 확정돼도 반투명을 유지한다(위 주석 참조)
        if not faded then fadeOut() end
    end
end)

-- 리스폰 시 상태 재적용
-- ⚠️ ResetOnSpawn 으로 스크립트가 다시 도는 경우, 이미 페이드된 상태가
--    유지되어야 한다. phase 를 다시 읽어 맞춘다.
player.CharacterAdded:Connect(function()
    task.wait(0.5)
    lastPhase = nil
    onPhase(ReplicatedStorage:GetAttribute("RoundPhase"))
end)
