-- BarricadeSystem
-- 태거 베이스 앞 바리케이드의 내구도/파괴 처리.
--
-- 설계 메모:
--  · 러너 무기는 humanoid:TakeDamage() 로 데미지를 준다. 바리케이드엔 Humanoid 가 없으므로
--    무기 쪽을 고치지 않고 "바리케이드가 스스로 타격을 감지"하는 방식을 쓴다.
--    (무기가 10종이 넘어 각각 수정하면 비용이 크고, 새 무기가 추가될 때마다 누락된다)
--  · Humanoid 를 붙이는 방법도 있으나, RoundSystem/Stage2TriggerSystem 등이
--    "Humanoid 있는 Model"을 캐릭터로 순회하므로 오작동 위험이 크다. 그래서 배제.
--  · 판정: 러너가 든 Tool 의 파트가 조각에 닿으면 1히트. 공격자별 쿨다운으로 연타를 막는다.

local Players           = game:GetService("Players")
-- ⚠️ 붕괴 파편 정리에 쓴다. 선언 없이 Debris:AddItem 을 호출하면 런타임에 터진다.
local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ⚠️ 봇 공격 주기(RunnerBotDriveController.ATTACK_COOLDOWN = 1.6)와 일치시킨다.
--   0.45 였을 때: 벽 타격이 "공격 동작"과 무관하게 닿기만 하면 발생해 3.6배 빠르게 깎였다.
--   실측 — 봇 10마리 분산 시 벽 전체가 약 0.7초, 한 조각에 몰리면 0.14초에 개방됐다.
--   1.6 으로 맞추면 때리는 동작·평타음과 리듬이 일치하고, 사람 러너 스윙 속도와도 비슷하다.
-- ⚠️ [BARRICADE-FADE] 페이드는 서버가 하지 않는다.
--    Transparency 를 서버가 정하면 모두에게 같은 값이 복제되는데,
--    러너는 엄폐물의 존재를 알아야 하고 태거는 시야가 필요해 요구가 정반대다
--    (실측 2026-08-22: 태거 기준으로 흐리게 했더니 러너가 존재를 모름).
--    → StarterPlayerScripts.BarricadeFadeClient 가 '태거 클라에서만' 로컬로 흐리게 한다.
--    여기서는 HP 기준 기본값(0.5~0.35)만 유지하면 되고, 그 값이 러너가 보는 화면이다.

local HIT_COOLDOWN = 1.6   -- 공격자별 재타격 간격(초)

-- ⚠️ [2026-08-24] 봇 전용 쿨다운. 유저와 분리한다.
--    봇은 벽 앞에 서 있기만 하면 자동으로 때린다. 여럿이 붙으면
--    각자 HIT_COOLDOWN 마다 깎아 공성이 순식간에 끝난다.
--    실측: HP 8, 봇 3마리 → 4.3초 / 5마리 → 2.6초.
--    곡사포는 차징 2.0 + 비행 1.1 = 3.1초라 첫 발도 못 쏜다.
--    → 봇은 '천천히 두드리는' 역할. 실제 파괴 속도는 유저가 만든다.
local BOT_HIT_COOLDOWN = 5.0
-- ⚠️ [2026-08-25] 5 → 8. 실제 배치된 판정 파트가 HP 8 인데 이 값이 5 라,
--    MaxHP 속성이 빠진 상황에서 게이지가 5칸으로 그려졌다.
--    폴백 값은 실제와 같아야 한다.
-- ⚠️ 실제 배치된 판정 파트의 HP 와 항상 같아야 한다.
--    다르면 MaxHP 속성이 빠진 상황에서 게이지 칸 수가 어긋난다.
local DEFAULT_HP = 10     -- 조각당 내구도 (봇 10마리 기준, 실측 후 조정)

-- ── 사운드 ──────────────────────────────────────────────
-- 타격음은 2종을 랜덤 재생한다. 한 소리만 반복하면 3히트 내내 같은 소리가 나 지겹다.
local HIT_SOUNDS = {
    "rbxassetid://138453047962067",
    "rbxassetid://127860004094478",
}
local BREAK_SOUND = "rbxassetid://84981346209739"
-- 🔊 [타격감 2026-09-04] 0.7 → 1.2 / 1.0 → 1.6. 성문 타격이 약하게 들렸다.
--   ⚠️ 둘을 같이 올린다. HIT 만 올리면 파괴음이 상대적으로 묻혀 "부서졌다"가 안 들린다.
--     비율(파괴가 타격보다 큼)은 유지한 채 전체를 끌어올린다.
local HIT_VOLUME   = 1.2
local BREAK_VOLUME = 1.6
local SOUND_RANGE  = 120    -- 들리는 거리(stud). 계단~성 안 교전 범위를 덮는 값

-- 파괴 시 조각이 즉시 사라지므로, 사운드를 조각에 붙이면 같이 지워져 안 들린다.
-- → 같은 위치에 임시 파트를 만들어 거기서 재생하고 Debris 로 정리한다.
local function playAt(position, soundId, volume)
    local anchor = Instance.new("Part")
    anchor.Name = "_BarricadeSfx"
    anchor.Size = Vector3.new(1, 1, 1)
    anchor.Position = position
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Parent = workspace

    local s = Instance.new("Sound")
    s.SoundId = soundId
    s.Volume = volume
    s.RollOffMaxDistance = SOUND_RANGE
    s.RollOffMode = Enum.RollOffMode.InverseTapered
    s.Parent = anchor
    s:Play()

    game:GetService("Debris"):AddItem(anchor, 5)
end

local blueprints = {}       -- [mapName] = 원본 사양 목록 (라운드마다 복원용)
local lastHit    = {}       -- [attackerChar] = os.clock()

local GATE_ATTR = "BarricadeGate"   -- 판정 파트에 붙이는, 함께 무너질 구조물 이름
-- ⚠️ snapshot() 이 이 값을 읽으므로 그보다 먼저 선언해야 한다.
--    아래쪽에 두면 스냅샷 시점에 nil 이라 연결 정보가 저장되지 않는다.

-- 🏰 [2026-08-28] "이 인스턴스가 성문·바리케이드 구조물인가" 공용 판정.
--   [왜 만드나] BlackHoleSystem.rejectLanding 이 같은 판정을 자기 안에 들고 있었고,
--     FrostDragonIceGenerator.isTaggerBase 는 아예 못 잡아 얼음이 게이트하우스 위에
--     생성돼 태거 시야를 가렸다(실측 2026-08-28 map1 스크린샷).
--   ⚠️ 성문 구조물 자체엔 표식이 '없다'. Gatehouse·GateWing1/2·Middle Wall 1~7 을
--     직접 조회해도 BarricadeGate / BarricadeHP 가 전부 nil 이다(실측 확인).
--     이름 목록은 '판정 파트'(Barricades 폴더 안 세그먼트)의 BarricadeGate 속성에
--     콤마 구분으로 들어 있다. 그걸 대조하는 게 유일한 방법이다.
--   ⚠️ 판정을 복사하지 말 것. 여기에만 조건을 추가한다.
--   ⚠️ 상위 8단계까지 거슬러 본다. 성문은 Model 중첩이 깊다.
_G.IsGateStructure = function(inst)
    if typeof(inst) ~= "Instance" then return false end
    -- ① 판정 파트 자체 / 그 하위
    local node = inst
    for _ = 1, 8 do
        if node == nil or node == workspace then break end
        if node.Name == "Barricades" or node:GetAttribute("BarricadeHP") ~= nil then
            return true
        end
        node = node.Parent
    end
    -- ② 세그먼트가 들고 있는 성문 이름 목록과 대조
    for _, mapName in ipairs({ "map1", "map2" }) do
        local mf = workspace:FindFirstChild(mapName)
        local f = mf and mf:FindFirstChild("Barricades")
        local seg = f and f:GetChildren()[1]
        local gname = seg and seg:GetAttribute(GATE_ATTR)
        if gname then
            for _, target in ipairs(string.split(gname, ",")) do
                target = target:gsub("^%s+", ""):gsub("%s+$", "")
                if target ~= "" then
                    local n2 = inst
                    for _ = 1, 8 do
                        if n2 == nil or n2 == workspace then break end
                        if n2.Name == target then return true end
                        n2 = n2.Parent
                    end
                end
            end
        end
    end
    return false
end

-- 🏰 점진적 붕괴 시 색을 입힐 파트 수 상한.
-- ⚠️ 성문은 620파트다. 전부 물들이면 피격마다 수백 번 대입이 일어난다.
--    앞쪽 표본만 어둡게 해도 "상해간다"는 인상은 충분히 전달된다.
local GATE_TINT_LIMIT = 80

-- 판정 파트에 연결된 구조물을 찾는다.
-- ⚠️ applyVisual 보다 먼저 선언해야 한다(거기서 점진적 붕괴에 쓴다).
-- ⚠️ [성능] 이 함수는 map 전체를 대상 이름 수만큼 순회한다(map1 기준 3918 × 10 = 39,180회).
--    applyVisual 이 피격마다 호출되므로 캐시가 없으면 8대에 31만 회가 돈다.
--    → 결과를 캐시한다. 구조물은 라운드 중 파괴될 때만 바뀌므로,
--       파괴 시점에 무효화하면 된다.
local gateCache = {}   -- [seg] = { instances... }

local function findGateStructure(seg)
    local cached = gateCache[seg]
    if cached then
        -- 파괴된 항목이 섞여 있으면 캐시를 버린다
        local valid = true
        for _, g in ipairs(cached) do
            if not g.Parent then valid = false break end
        end
        if valid then return cached end
        gateCache[seg] = nil
    end

    local name = seg:GetAttribute(GATE_ATTR)
    if not name then return nil end
    local mf = seg:FindFirstAncestorWhichIsA("Folder")
    mf = mf and mf.Parent
    if not mf then return nil end

    -- ⚠️ GetDescendants 를 한 번만 부르고 이름 집합으로 한 번에 훑는다.
    --    예전엔 target 마다 전체를 다시 순회해 비용이 대상 수만큼 곱해졌다.
    local wanted = {}
    for _, target in ipairs(string.split(name, ",")) do
        wanted[target:gsub("^%s+", ""):gsub("%s+$", "")] = true
    end

    local list = {}
    for _, d in ipairs(mf:GetDescendants()) do
        if wanted[d.Name] then list[#list + 1] = d end
    end

    gateCache[seg] = list
    return list
end

-- ═══════════════════════════════════════════════════════════════
-- 🏰 통짜 구조물(성문) 백업 / 복원
--
-- ⚠️ [실패 기록 2026-08-24] 판정 파트는 blueprints 로 재건되지만, 연결 구조물
--    (Gatehouse 620파트 등)은 Destroy 되면 그대로 사라졌다. 2라운드부터
--    벽이 아예 없는 맵이 되어 게임이 성립하지 않았다.
--    → 부팅 시 ServerStorage 에 원본을 복제해두고, 라운드 시작마다 없으면 되살린다.
--
-- ⚠️ Clone 은 620파트라 비용이 있다. 매 프레임이 아니라 라운드당 1회이므로 괜찮지만,
--    "없을 때만" 복원해야 한다. 매번 지우고 다시 만들면 낭비다.
-- ═══════════════════════════════════════════════════════════════
local ServerStorage = game:GetService("ServerStorage")
local GATE_BACKUP_FOLDER = "_GateBackups"

-- 백업본과 '원래 부모'를 함께 기억한다.
-- ⚠️ 경로 문자열로 되찾으려다 실패했다 — GetFullName 은 공백이 포함된 이름
--    ("map1 castle")에서 점 분리가 어긋난다. 인스턴스 참조를 직접 들고 있는 게 안전하다.
local gateBackups = {}   -- [mapName] = { {clone=Instance, parent=Instance, name=string}, ... }

-- 부팅 시 1회: 연결 구조물의 원본을 통째로 백업한다.
local function backupGates()
    local folder = ServerStorage:FindFirstChild(GATE_BACKUP_FOLDER)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = GATE_BACKUP_FOLDER
        folder.Parent = ServerStorage
    end

    for _, mapName in ipairs({ "map1", "map2" }) do
        local mf = workspace:FindFirstChild(mapName)
        local bf = mf and mf:FindFirstChild("Barricades")
        if bf then
            for _, seg in ipairs(bf:GetChildren()) do
                local gname = seg:GetAttribute(GATE_ATTR)
                if gname then
                    gateBackups[mapName] = gateBackups[mapName] or {}
                    -- ⚠️ [성능] target 마다 GetDescendants 를 다시 부르지 않는다.
                    --    한 번만 훑고 이름 집합으로 매칭한다.
                    local wanted = {}
                    for _, target in ipairs(string.split(gname, ",")) do
                        wanted[target:gsub("^%s+", ""):gsub("%s+$", "")] = true
                    end
                    -- ⚠️ [수정 2026-08-25] 예전엔 wanted[obj.Name] = nil 로 이름당
                    --    1개만 백업했다. map2 는 Gatehouse2 3개 / Gate2 6개 처럼
                    --    같은 이름이 여러 개라, 다음 라운드에 1개만 복원되어
                    --    '벽이 절반만 복구' 되는 증상이 나왔다.
                    --    → 이름이 같아도 전부 백업한다. 중복 판단은 좌표로 한다.
                    for _, obj in ipairs(mf:GetDescendants()) do
                        if wanted[obj.Name] then
                            local c = obj:Clone()
                            c.Parent = folder
                            local pivot
                            local okp, pv = pcall(function()
                                return (obj:IsA("Model") and obj:GetPivot() or obj.CFrame)
                            end)
                            if okp then pivot = pv end
                            table.insert(gateBackups[mapName], {
                                clone = c, parent = obj.Parent, name = obj.Name,
                                cframe = pivot,
                            })
                        end
                    end
                    print(string.format("[Barricade] %s 성문 백업: %d개",
                        mapName, #gateBackups[mapName]))
                end
            end
        end
    end
end

-- 라운드 시작 시: 사라진 구조물을 되살린다.
local function restoreGates(mapName)
    local list = gateBackups[mapName]
    if not list then return 0 end
    local mf = workspace:FindFirstChild(mapName)
    if not mf then return 0 end

    -- ⚠️ [수정 2026-08-25] 예전엔 FindFirstChild(이름) 으로 존재를 판단했다.
    --    map2 는 Gatehouse2 3개 / Gate2 6개 처럼 같은 이름이 여럿이라,
    --    하나만 남아 있어도 '있다'고 보고 나머지를 복원하지 않았다.
    --    → 좌표로 판단한다. 백업된 위치에 실물이 없으면 그것만 되살린다.
    local RADIUS = 3   -- 같은 자리로 볼 거리

    -- 현재 살아있는 구조물의 좌표를 모은다
    -- ⚠️ [수정 2026-08-25] 예전엔 entry 루프 안에서 break 해, 첫 entry 이름만
    --    alive 에 담겼다. 나머지는 '없다'고 판단되어 매 라운드 중복 생성됐다
    --    (실측: map1 연결 구조물이 10개 → 28개로 불어남).
    --    → 이름 집합을 먼저 만들고 descendants 를 한 번만 훑는다.
    local wantNames = {}
    for _, entry in ipairs(list) do wantNames[entry.name] = true end

    local alive = {}
    for _, d in ipairs(mf:GetDescendants()) do
        if wantNames[d.Name] and (d:IsA("Model") or d:IsA("BasePart")) then
            local ok, pv = pcall(function()
                return (d:IsA("Model") and d:GetPivot() or d.CFrame)
            end)
            if ok then alive[#alive + 1] = { name = d.Name, pos = pv.Position, inst = d } end
        end
    end

    local restored = 0
    for _, entry in ipairs(list) do
        local found = nil
        if entry.cframe then
            for _, a in ipairs(alive) do
                if a.name == entry.name and (a.pos - entry.cframe.Position).Magnitude < RADIUS then
                    found = a.inst
                    break
                end
            end
        else
            found = mf:FindFirstChild(entry.name, true)
        end

        if not found then
            local c = entry.clone:Clone()
            c.Parent = (entry.parent and entry.parent.Parent) and entry.parent or mf
            -- ⚠️ 원래 자리로. 백업 시 기록한 좌표를 쓴다.
            if entry.cframe then
                pcall(function()
                    if c:IsA("Model") then c:PivotTo(entry.cframe) else c.CFrame = entry.cframe end
                end)
            end
            restored = restored + 1
        else
            -- ⚠️ 살아남은 구조물은 그을린 색이 남아 있다(부서지지 않고 라운드가 끝난 경우).
            local parts = {}
            if found:IsA("BasePart") then parts[1] = found end
            for _, d in ipairs(found:GetDescendants()) do
                if d:IsA("BasePart") then parts[#parts + 1] = d end
            end
            for _, p in ipairs(parts) do
                local orig = p:GetAttribute("_OrigColor")
                if orig then p.Color = orig end
            end
        end
    end
    if restored > 0 then
        print(string.format("[Barricade] %s 성문 복원: %d개", mapName, restored))
    end
    return restored
end

local function snapshot()
    for _, mapName in ipairs({"map1", "map2"}) do
        local mf = workspace:FindFirstChild(mapName)
        local folder = mf and mf:FindFirstChild("Barricades")
        if folder then
            local list = {}
            for _, d in ipairs(folder:GetChildren()) do
                if d:IsA("BasePart") then
                    -- ⚠️ 두께는 내구도에 따라 줄어드므로 현재 Size 를 그대로 저장하면
                    --    라운드마다 벽이 점점 얇아진다. 원본 두께 속성을 우선 사용.
                    local baseThick = d:GetAttribute("BarricadeBaseThick") or d.Size.X
                    list[#list + 1] = {
                        name = d.Name,
                        size = Vector3.new(baseThick, d.Size.Y, d.Size.Z),
                        cframe = d.CFrame,
                        color = d.Color, material = d.Material, transparency = d.Transparency,
                        -- ⚠️ [2026-08-23] 충돌/질의 플래그를 저장하지 않아, 재건된 파트가
                        --    기본값(CanCollide=true)으로 살아나 성문 앞에 보이지 않는 벽이
                        --    하나 더 생겼다. 통짜 구조물 방식에서는 판정 파트가
                        --    투명·비충돌이어야 한다.
                        canCollide = d.CanCollide,
                        canQuery = d.CanQuery,
                        castShadow = d.CastShadow,
                        -- 재건은 항상 만전 상태로. 현재 HP 를 저장하면 깎인 채로 부활한다.
                        hp = d:GetAttribute("BarricadeMaxHP") or d:GetAttribute("BarricadeHP"),
                        -- ⚠️ MaxHP 가 없으면 현재 HP 를 최대치로 본다.
                        --    nil 로 저장되면 재건 때 속성이 안 붙어 DEFAULT_HP 로 떨어진다.
                        maxHp = d:GetAttribute("BarricadeMaxHP") or d:GetAttribute("BarricadeHP"),
                        index = d:GetAttribute("BarricadeIndex"),
                        -- 🏰 함께 무너질 구조물(성문 등). 이걸 저장하지 않으면 재건 후
                        --    연결이 끊겨 판정 파트만 사라지고 성문이 그대로 남는다.
                        gate = d:GetAttribute(GATE_ATTR),
                    }
                end
            end
            blueprints[mapName] = list
            print(string.format("[Barricade] %s 원본 저장: %d개", mapName, #list))
        end
    end
end

-- 러너(유저 또는 AI)인지 판정. 캐릭터 단위로 본다.
--   이전에는 "든 Tool 의 파트가 닿았는가"를 봤지만, 겹침 검사 방식으로 바꾸면서
--   캐릭터 자체를 대상으로 한다(무기를 안 든 순간에도 벽을 두드릴 수 있어야 자연스럽다).
local function isRunnerChar(char)
    local player = Players:GetPlayerFromCharacter(char)
    if player then
        return player:GetAttribute("Role") == "Runner"
    end
    return char:GetAttribute("AIRunner") == true
end

local function applyVisual(seg)
    local hp    = seg:GetAttribute("BarricadeHP") or 0
    local maxHp = seg:GetAttribute("BarricadeMaxHP") or DEFAULT_HP
    local ratio = math.clamp(hp / math.max(maxHp, 1), 0, 1)

    -- 🏰 통짜 구조물(성문)에 연결된 판정 파트는 '보이지 않는 판정용'이다.
    -- ⚠️ [실측 2026-08-23] 아래 두께·색·투명도 처리는 판정 파트 자체가 나무 벽으로
    --    보이던 시절의 로직이다. 성문 방식에서는 이게 매 피격마다 Transparency 를
    --    0.5 로 되돌려, 투명하게 설정해둬도 "반투명 나무 벽"이 다시 나타났다.
    --    → 연결 구조물이 있으면 형상 변경을 건너뛴다. 시각은 성문이, HP 는 게이지가 담당.
    local isGate = seg:GetAttribute(GATE_ATTR) ~= nil
    if not isGate then
        local baseThick = seg:GetAttribute("BarricadeBaseThick")
        if not baseThick then
            baseThick = seg.Size.X
            seg:SetAttribute("BarricadeBaseThick", baseThick)
        end
        local thick = baseThick * (0.5 + 0.5 * ratio)
        seg.Size = Vector3.new(thick, seg.Size.Y, seg.Size.Z)
        seg.Color = Color3.fromRGB(122, 92, 62):Lerp(Color3.fromRGB(90, 40, 30), 1 - ratio)
        seg.Transparency = 0.5 - (1 - ratio) * 0.15
    else
        -- 판정 전용: 항상 보이지 않게 유지한다
        seg.Transparency = 1

        -- 🏰 점진적 붕괴: 맞을수록 성문이 상해 보인다.
        -- ⚠️ 성문은 620파트다. 전부 물들이면 피격마다 수백 번 대입이 일어난다.
        --    표본만 어둡게 해도 "상해간다"는 인상은 충분하다.
        -- ⚠️ [실패 기록 2026-08-24] 예전엔 목록 순서대로 훑었는데, Gatehouse 620파트가
        --    맨 앞이라 상한(80)을 거기서 다 써버렸다. 그 결과 좌우 벽(GateWing)과
        --    Middle Wall 은 색이 전혀 안 변해 "성문만 상하고 벽은 멀쩡한" 그림이 됐다.
        --    → 파트 수가 적은 구조물을 먼저 처리한다. 작은 것들(각 1파트)은 항상
        --       포함되고, 남은 몫으로 Gatehouse 표본을 물들인다.
        -- ⚠️ [성능] HP 만전(ratio == 1)이면 색 변화량이 0 이라 계산할 이유가 없다.
        --    라운드 재건 때마다 hookSegment → applyVisual 이 도는데, 그때 구조물
        --    탐색까지 하면 헛수고다. 실제로 색이 변할 때만 찾는다.
        local gate = (ratio < 1) and findGateStructure(seg) or nil
        if gate then
            -- 구조물별 파트 목록을 모으고, 파트 수가 적은 순으로 정렬
            -- ⚠️ 보이지 않는 파트(Transparency >= 1)는 제외한다. Middle Wall 은
            --    해머 도약을 막는 투명 벽이라 색을 바꿔도 안 보이면서 상한만 먹는다.
            local groups = {}
            for _, g in ipairs(gate) do
                local parts = {}
                if g:IsA("BasePart") and g.Transparency < 1 then parts[1] = g end
                for _, d in ipairs(g:GetDescendants()) do
                    if d:IsA("BasePart") and d.Transparency < 1 then
                        parts[#parts + 1] = d
                    end
                end
                if #parts > 0 then
                    groups[#groups + 1] = parts
                end
            end
            table.sort(groups, function(x, y) return #x < #y end)

            local tinted = 0
            for _, parts in ipairs(groups) do
                for _, p in ipairs(parts) do
                    if tinted >= GATE_TINT_LIMIT then break end
                    local orig = p:GetAttribute("_OrigColor")
                    if not orig then
                        orig = p.Color
                        p:SetAttribute("_OrigColor", orig)
                    end
                    -- ⚠️ UnionOperation 은 UsePartColor=false 면 Color 대입이 통째로
                    --    무시된다(합치기 전 원본 파트 색을 쓴다). 실측 2026-08-24:
                    --    GateWing1·2 가 이 상태라 색을 바꿔도 화면에 아무 변화가 없었다.
                    if p:IsA("UnionOperation") and not p.UsePartColor then
                        p.UsePartColor = true
                    end
                    -- ⚠️ 선형 (1-ratio) 은 초반 변화가 너무 작다. HP 8 이라 한 대에
                    --    1/8 씩만 줄어드는데, 거기에 선형을 곱하면 첫 타격이 RGB -10 이라
                    --    눈치채기 어렵다(특히 Cobblestone 처럼 텍스처가 있는 재질).
                    --    → 제곱근 곡선으로 초반을 키운다. 후반은 비슷하게 수렴한다.
                    --      HP 6/8 기준 0.175 → 0.375 (두 배 이상)
                    p.Color = orig:Lerp(Color3.fromRGB(58, 44, 38), math.sqrt(1 - ratio) * 0.75)
                    tinted = tinted + 1
                end
                if tinted >= GATE_TINT_LIMIT then break end
            end
        end
    end

    -- 게이지 갱신 (태거 전용 — 아래 ensureGauge 에서 생성)
    -- HP 가 3처럼 작은 이산값이라 연속 막대는 33%씩 뚝 끊겨 의미가 약하다.
    -- → 칸을 HP 수만큼 나누고 "남은 칸"을 켜고 끈다. 세면 바로 읽힌다.
    local bb = seg:FindFirstChild("HpGauge")
    if bb then
        local back = bb:FindFirstChild("Back")
        if back then
            for i = 1, maxHp do
                local cell = back:FindFirstChild("Cell" .. i)
                if cell then
                    local alive = (i <= hp)
                    cell.BackgroundColor3 = alive
                        and Color3.fromRGB(90, 200, 90):Lerp(Color3.fromRGB(220, 60, 60), 1 - ratio)
                        or  Color3.fromRGB(45, 45, 52)
                    cell.BackgroundTransparency = alive and 0 or 0.35
                end
            end
        end
    end
end

-- 남은 내구도 게이지. 태거만 보이게 해서 화면 부담을 줄이고,
-- 벽 너머가 안 보이는 태거가 "어느 조각이 뚫리기 직전인지"를 원거리에서 파악하게 한다.
local function ensureGauge(seg)
    local maxHp = seg:GetAttribute("BarricadeMaxHP") or DEFAULT_HP
    local existing = seg:FindFirstChild("HpGauge")
    if existing then
        -- ⚠️ [수정 2026-08-25] 예전엔 게이지가 있으면 그냥 반환했다.
        --    MaxHP 를 8 → 10 으로 바꿔도 셀은 8개 그대로라, applyVisual 이
        --    Cell9/Cell10 을 못 찾아 "중간에 빈 칸"이 생겼다.
        --    → 셀 수가 다르면 지우고 다시 만든다.
        local back = existing:FindFirstChild("Back")
        local cells = 0
        if back then
            for _, c in ipairs(back:GetChildren()) do
                if c:IsA("Frame") and c.Name:match("^Cell%d+$") then cells = cells + 1 end
            end
        end
        -- ⚠️ 셀 수뿐 아니라 '크기 방식'도 확인한다. 셀 수가 같아도 예전
        --    스케일 방식(1/maxHp)으로 만들어진 게이지는 넘침 문제가 남는다.
        local firstCell = back and back:FindFirstChild("Cell1")
        local sizeOk = firstCell and firstCell.Size.X.Scale == 0
        -- ⚠️ SortOrder 가 LayoutOrder 인지도 확인한다. 예전 게이지는 Name 정렬이라
        --    칸 순서가 뒤섞여 있다.
        local lay = back and back:FindFirstChildOfClass("UIListLayout")
        local sortOk = lay and lay.SortOrder == Enum.SortOrder.LayoutOrder
        if cells == maxHp and sizeOk and sortOk then return end
        existing:Destroy()
    end

    local bb = Instance.new("BillboardGui")
    bb.Name = "HpGauge"
    -- 칸 수에 맞춰 폭을 잡아 칸 하나가 항상 같은 크기로 보이게 (HP 를 올려도 대응됨)
    -- ⚠️ [수정 2026-08-25] 셀 크기를 스케일(1/maxHp)로 두면 UIPadding(좌우 3)과
    --    UIListLayout.Padding(3)이 겹쳐 총합이 컨테이너를 넘친다. 넘친 셀은
    --    밀려나 "중간에 빈 칸"처럼 보였다(HP 5 남았는데 4칸으로 읽힘).
    --    → 셀 너비를 오프셋으로 고정하고 컨테이너를 거기 맞춘다.
    local CELL_W  = 20   -- 셀 하나의 너비(px)
    local CELL_GAP = 3   -- 셀 사이 간격(px)
    bb.Size = UDim2.new(0, CELL_W * maxHp + CELL_GAP * (maxHp - 1) + 8, 0, 14)
    bb.StudsOffsetWorldSpace = Vector3.new(0, seg.Size.Y / 2 + 3, 0)
    -- ⚠️ AlwaysOnTop=true 는 "지형에 가려도 보이게" 하는 옵션이라, 멀리 있어도 화면에 그려진다.
    --    실측: 762~912 스터드 거리의 게이지가 로비 캐릭터 머리 위에 겹쳐 보였다
    --    ("정체불명의 희미한 글자"의 정체 — 5개 조각의 게이지 막대였음).
    --    MaxDistance 는 Adornee 기준으로 계산되므로 Adornee 를 명시해야 거리 제한이 먹는다.
    bb.Adornee = seg
    bb.AlwaysOnTop = true
    bb.MaxDistance = 220
    -- [DEFAULT-HIDDEN] 꺼진 상태로 만든다. 켜는 건 BarricadeGaugeClient 의 몫.
    --   기본값(true)으로 두면 "보이는 게 기본, 클라가 뒤늦게 끔" 구조가 되어
    --   ①클라 스크립트가 뜨기 전 ②Barricades 폴더가 아직 복제되기 전
    --   ③라운드 재건으로 새 게이지가 생긴 직후 — 이 틈마다 화면에 그려진다.
    --   실측(2026-08-20): 접속 직후 화면 상단 (354,69)·(1370,91) 에
    --   깊이 589~664 짜리 게이지가 En=false 로 존재하는 걸 확인했다.
    --   ⚠️ 당시 "검은 바코드" 증상의 원인으로 의심해 이 수정을 넣었으나,
    --      진범은 VIPNametag 의 TextScaled 축소(8px 뭉개짐)로 밝혀졌다.
    --      이 수정 자체는 별개의 실제 결함(기본값 방향 역전)을 고친 것이라 유지한다.
    --   기본을 꺼짐으로 두면 이 경합이 통째로 사라진다(클라가 0.5초마다 켜므로 손실 없음).
    bb.Enabled = false
    bb.Parent = seg

    local back = Instance.new("Frame")
    back.Name = "Back"
    back.Size = UDim2.new(1, 0, 1, 0)
    back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    back.BackgroundTransparency = 0.25
    back.BorderSizePixel = 0
    back.Parent = bb

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 2); pad.PaddingBottom = UDim.new(0, 2)
    pad.PaddingLeft = UDim.new(0, 3); pad.PaddingRight = UDim.new(0, 3)
    pad.Parent = back

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, CELL_GAP)
    -- ⚠️ [수정 2026-08-25] SortOrder 기본값은 Name 이라 LayoutOrder 가 무시된다.
    --    그러면 Cell1, Cell10, Cell2, Cell3... 순으로 정렬되어
    --    Cell10 이 두 번째 자리에 오고, HP 가 그보다 낮으면 그 칸만 꺼져
    --    '중간에 빈 칸'처럼 보였다. 여러 세션에 걸쳐 재발한 원인이 이것.
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Parent = back

    -- 칸을 HP 최대치만큼 생성. 남은 칸만 색이 켜진다.
    for i = 1, maxHp do
        local cell = Instance.new("Frame")
        cell.Name = "Cell" .. i
        cell.Size = UDim2.new(0, CELL_W, 1, 0)
        cell.BackgroundColor3 = Color3.fromRGB(90, 200, 90)
        cell.BorderSizePixel = 0
        cell.LayoutOrder = i
        cell.Parent = back
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 🏰 통짜 구조물(성문) 지원
--
-- [왜] map1 은 판때기 한 장이 아니라 '성문 + 좌우벽'이라는 구조물이 벽 역할을 한다.
--   그런데 그 구조물은 파트가 수백 개다. 파트마다 개별 HP 를 주면
--     · 어디를 때리느냐에 따라 진행이 달라지고
--     · 일부만 부서져 '남은 벽'이 러너의 안전지대가 된다(5조각 시절 실패 이력)
--   → 어느 파트를 때리든 '대표 HP' 하나를 공유하고, 0 이 되면 통째로 사라진다.
--
-- ⚠️ 판정 파트(BarricadeHP 를 가진 얇은 판)는 그대로 둔다. 그게 타격 판정과
--    태거 조준의 기준이고, 성문은 거기에 '딸린 시각 구조물'로 묶인다.
--    이러면 기존 damageSegment/applyVisual 로직을 하나도 안 건드려도 된다.
-- ═══════════════════════════════════════════════════════════════
-- (GATE_ATTR 은 snapshot 보다 앞, 파일 상단에 선언되어 있다)

-- 판정 파트에 연결된 구조물을 찾는다.
-- ═══════════════════════════════════════════════════════════════
-- 🏰 붕괴 연출 (파편 + 먼지 + 화면 흔들림)
--
-- ⚠️ 성문은 620파트다. 실제 파트를 물리 조각으로 떨어뜨리면 서버가 감당 못 한다.
--    → 파편은 '새로 만든 소수의 조각'이다. 원본은 그냥 사라지고, 그 자리에
--      돌·나무 조각 몇 개가 튀면서 "무너졌다"를 연출한다.
-- ⚠️ 개수 상한을 둔다. 라운드에 한 번뿐인 사건이지만, 파편이 많으면
--    저사양 모바일에서 그 순간만 프레임이 떨어진다.
-- ═══════════════════════════════════════════════════════════════
local DEBRIS_COUNT   = 14      -- 파편 개수 (모바일 고려한 상한)
local DEBRIS_LIFE    = 3.5     -- 파편 수명(초)
local STONE_COLOR    = Color3.fromRGB(163, 162, 165)   -- 성문 주 색(487파트)
local WOOD_COLOR     = Color3.fromRGB(108, 88, 75)     -- 성문 보조 색(133파트)
local SHAKE_RANGE    = 220     -- 흔들림이 전달되는 거리

local shakeEvent = ReplicatedStorage:FindFirstChild("BarricadeShake")
if not shakeEvent then
    shakeEvent = Instance.new("RemoteEvent")
    shakeEvent.Name = "BarricadeShake"
    shakeEvent.Parent = ReplicatedStorage
end

local function spawnCollapseFx(centerCF, spanZ)
    local folder = Instance.new("Folder")
    folder.Name = "_GateDebris"
    folder.Parent = workspace
    Debris:AddItem(folder, DEBRIS_LIFE + 1)

    for i = 1, DEBRIS_COUNT do
        local p = Instance.new("Part")
        local sz = math.random(18, 42) / 10
        p.Size = Vector3.new(sz, sz * math.random(6, 14) / 10, sz)
        -- 돌:나무 = 대략 4:1 (성문 구성비와 맞춘다)
        local isWood = (i % 5 == 0)
        p.Color = isWood and WOOD_COLOR or STONE_COLOR
        p.Material = isWood and Enum.Material.Wood or Enum.Material.Slate
        -- ⚠️ CanCollide=false. 파편이 러너를 밀거나 통로를 막으면 안 된다.
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.CastShadow = false
        p.Anchored = false

        -- 성문 폭을 따라 흩뿌린다
        local zOff = (math.random() - 0.5) * spanZ * 0.8
        p.CFrame = centerCF * CFrame.new(math.random(-4, 4), math.random(0, 22), zOff)
            * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
        p.Parent = folder

        -- 앞쪽(러너 방향)으로 튀어나오며 흩어진다
        p.AssemblyLinearVelocity = Vector3.new(
            -math.random(12, 34),
            math.random(8, 26),
            math.random(-18, 18)
        )
        p.AssemblyAngularVelocity = Vector3.new(
            math.random(-8, 8), math.random(-8, 8), math.random(-8, 8)
        )
    end

    -- 먼지: 파편과 별개로 바닥에서 피어오른다
    local dustAnchor = Instance.new("Part")
    dustAnchor.Name = "_GateDust"
    dustAnchor.Size = Vector3.new(1, 1, 1)
    dustAnchor.Transparency = 1
    dustAnchor.Anchored = true
    dustAnchor.CanCollide = false
    dustAnchor.CanQuery = false
    dustAnchor.CFrame = centerCF
    dustAnchor.Parent = workspace
    Debris:AddItem(dustAnchor, DEBRIS_LIFE + 1)

    local dust = Instance.new("ParticleEmitter")
    dust.Texture = "rbxassetid://8451174579"
    dust.Color = ColorSequence.new(Color3.fromRGB(190, 185, 175), Color3.fromRGB(120, 112, 102))
    dust.Size = NumberSequence.new(14)
    dust.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.35),
        NumberSequenceKeypoint.new(1, 1),
    })
    dust.Lifetime = NumberRange.new(1.2, 2.2)
    dust.Rate = 0
    dust.Speed = NumberRange.new(6, 16)
    dust.SpreadAngle = Vector2.new(70, 70)
    dust.Acceleration = Vector3.new(0, -4, 0)
    dust.Parent = dustAnchor
    dust:Emit(26)

    -- 화면 흔들림 — 가까운 사람만
    -- ⚠️ 거리 판정을 서버에서 한다. 전원에게 보내면 맵 반대편에서도 흔들려
    --    "무슨 일이 일어났는지 모르는 채 화면만 떨리는" 상태가 된다.
    for _, plr in ipairs(Players:GetPlayers()) do
        local ch = plr.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        if hrp then
            local dist = (hrp.Position - centerCF.Position).Magnitude
            if dist <= SHAKE_RANGE then
                -- 가까울수록 강하게 (0.35 ~ 1.0)
                local power = 0.35 + 0.65 * (1 - dist / SHAKE_RANGE)
                shakeEvent:FireClient(plr, power)
            end
        end
    end
end

-- 💥 [2026-09-02] 바리케이드 피격 표식. 게이지 말고도 "맞았다"가 그 자리에 뜬다.
--   [왜] 게이지는 화면 구석이라 타격감이 안 붙는다. 아이스보우의 HIT 표시처럼
--     때린 지점에 뜨는 피드백이 있어야 "내가 지금 유효타를 넣고 있다"가 읽힌다.
--   ⚠️ 판정 파트(seg)는 27×20×238 짜리 거대 박스다. seg.Position 에 띄우면
--     실제 타격 지점에서 100 stud 넘게 떨어진다 → 공격자 위치를 기준으로 띄운다.
--   ⚠️ 서버에서 만든 BillboardGui 는 모든 클라에 자동 복제된다. 별도 RemoteEvent 불필요.
--   ⚠️ 크기는 스터드(Scale) 단위. 픽셀 고정은 원거리에서 거대해 보인다
--     (TaggerHpDisplay:30 이 같은 이유로 기각한 방식).
local HIT_MARK_LIFE = 0.7      -- 표식 수명(초)
local HIT_MARK_RISE = 3.5      -- 떠오르는 높이(stud)

local function showHitMark(attacker, remainHp, maxHp)
    local hrp = attacker and attacker:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local anchor = Instance.new("Part")
    anchor.Name = "_BarricadeHitMark"
    anchor.Size = Vector3.new(0.2, 0.2, 0.2)
    anchor.Transparency = 1
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Anchored = true
    -- 공격자 앞쪽 살짝 위 — 벽면 근처에 뜬다
    anchor.CFrame = hrp.CFrame * CFrame.new(0, 2.2, -3)
    anchor.Parent = workspace

    local gui = Instance.new("BillboardGui")
    gui.Size = UDim2.new(4, 0, 1.6, 0)
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.MaxDistance = 300
    gui.Adornee = anchor
    gui.Parent = anchor

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "HIT!"
    lbl.TextColor3 = Color3.fromRGB(255, 220, 90)
    lbl.TextScaled = true
    lbl.Font = Enum.Font.GothamBold
    lbl.TextStrokeTransparency = 0
    lbl.TextStrokeColor3 = Color3.fromRGB(40, 20, 0)
    lbl.Parent = gui

    -- 마지막 한 대는 색으로 예고한다("다음이 끝이다").
    if remainHp and remainHp <= 1 then
        lbl.Text = "HIT!"
        lbl.TextColor3 = Color3.fromRGB(255, 120, 90)
    end

    -- 떠오르며 사라짐
    local TweenService = game:GetService("TweenService")
    local info = TweenInfo.new(HIT_MARK_LIFE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(anchor, info, {
        CFrame = anchor.CFrame + Vector3.new(0, HIT_MARK_RISE, 0)
    }):Play()
    TweenService:Create(lbl, info, {
        TextTransparency = 1, TextStrokeTransparency = 1
    }):Play()

    game:GetService("Debris"):AddItem(anchor, HIT_MARK_LIFE + 0.1)
end

local function damageSegment(seg, attacker)
    -- 🏰 [2026-09-11] 공성 인원 스케일을 '첫 타격' 에 확정한다.
    --   ⚠️ hp 를 읽기 '전' 이어야 한다. 뒤에 두면 첫 타격이 옛 HP 기준으로 깎인다.
    --   ⚠️ 매 타격마다 불리지만 BarricadeScaled 표식 때문에 2회차부터는 즉시 빠진다.
    if _G.ScaleBarricadeForStage2 then pcall(_G.ScaleBarricadeForStage2) end
    local hp = seg:GetAttribute("BarricadeHP")
    if not hp or hp <= 0 then return end
    local sfxPos = seg.Position
    hp -= 1
    seg:SetAttribute("BarricadeHP", hp)
    if hp <= 0 then
        playAt(sfxPos, BREAK_SOUND, BREAK_VOLUME)
        print(string.format("[Barricade] %s 파괴됨 (by %s)", seg.Name, attacker.Name))

        -- 🏰 딸린 구조물(성문 등)도 함께 무너뜨린다.
        -- ⚠️ 판정 파트만 지우면 벽은 그대로 서 있어 러너가 못 지나간다.
        local gate = findGateStructure(seg)

        -- 붕괴 연출은 '지우기 전에' 띄운다.
        -- ⚠️ Destroy 후에 하면 위치 기준이 사라져 파편이 원점(0,0,0)에 생긴다.
        if gate and #gate > 0 then
            spawnCollapseFx(seg.CFrame, seg.Size.Z)
        end

        if gate then
            for _, g in ipairs(gate) do
                if g and g.Parent then g:Destroy() end
            end
            print(string.format("[Barricade] 연결 구조물 %d개 함께 파괴", #gate))
        end

        -- 👑 [2026-08-29] 태거 HP 확정 시점 = 성문 붕괴.
        --   [왜 여기인가] 성문이 무너지는 순간이 실제 전투 개시다. 계단 진입 시점에
        --     찍으면 1등 러너 혼자서 전체 인원분 HP 를 상대하게 된다(실측: 진입→붕괴
        --     6.9~11.2초 동안 참여 인원이 1명 → 6명으로 늘어난다).
        --   ⚠️ 곡사포보다 '먼저' 부른다. 곡사포 파괴는 연출이고 이건 밸런스라,
        --     혹시 곡사포 쪽에서 에러가 나도 HP 확정은 반드시 일어나야 한다.
        --   ⚠️ pcall. Stage2TriggerSystem 이 아직 준비 전이거나 없는 상황에서도
        --     성문 파괴 자체는 진행돼야 한다.
        if _G.FinalizeTaggerHp then
            pcall(_G.FinalizeTaggerHp, "성문 붕괴")
        end

        -- 👊 [2026-09-02] 유저 태거 PushTool 지급도 이 시점이다.
        --   [왜] 2단계 진입(계단 도달)에 주면 성문이 버티는 ~10초 동안 태거가 결투
        --     무기로 바리케이드 앞 러너를 때린다. 공성 구간에는 공성 도구(굴리기·
        --     곡사포·마법책)로만 견제하는 게 설계 의도다.
        --   ⚠️ HP 확정 '뒤에' 부른다. 반대로 하면 지급 직후 HP 재산정이 돌아
        --     TaggerBotSystem 의 피격 관찰자가 중간값을 본다.
        --   ⚠️ 봇 킹은 TaggerBotSystem.enterDuelMode 가 TaggerHpReady 로 이미 게이트한다.
        --     같은 규칙이 두 곳에 있으니 한쪽만 고치면 유저·봇이 어긋난다.
        --   ⚠️ pcall. Stage2TriggerSystem 이 없어도 성문 파괴는 진행돼야 한다.
        if _G.GrantTaggerPushTool then
            pcall(_G.GrantTaggerPushTool)
        end

        -- 🎯 곡사포도 함께 무너진다. 사거리가 성문 앞 고정이라 벽이 뚫린 뒤엔
        --    무의미해지고, 서사적으로도 '성문과 함께 포대가 무너진다'가 자연스럽다.
        -- ⚠️ pcall. CannonSystem 이 없는 맵/상황에서도 성문 파괴는 진행돼야 한다.
        if _G.CannonOnGateDestroyed then
            pcall(_G.CannonOnGateDestroyed)
        end
        -- 📖 마법책도 같이. 곡사포와 같은 무기이고 스킨만 다르다.
        -- ⚠️ [버그 2026-08-26] 이 호출이 누락돼 있었다. 곡사포는 사라지는데
        --    마법책만 남아 성문 붕괴 후에도 계속 발사됐다.
        if _G.MagicBookOnGateDestroyed then
            pcall(_G.MagicBookOnGateDestroyed)
        end
        -- ⚠️ 캐시 무효화. 파괴된 인스턴스를 계속 참조하면 다음 라운드에
        --    되살아난 구조물 대신 죽은 참조를 쓴다.
        gateCache[seg] = nil

        seg:Destroy()
    else
        playAt(sfxPos, HIT_SOUNDS[math.random(1, #HIT_SOUNDS)], HIT_VOLUME)
        applyVisual(seg)   -- Transparency 를 HP 기준으로 되돌린다 = 페이드 복구
        -- 💥 때린 지점에 HIT 표식 (게이지만으로는 타격감이 안 붙는다)
        showHitMark(attacker, hp, seg:GetAttribute("BarricadeMaxHP"))
        print(string.format("[Barricade] %s 피격 → 남은 %d (by %s)", seg.Name, hp, attacker.Name))
        -- ⚔️ [2026-09-08 → 같은 날 철회] 사쿠라 바리케이드 스택 훅을 제거했다.
        --   [넣었던 이유] 사쿠라는 명중으로 스택을 쌓는데 바리케이드는 Humanoid 가
        --     없어 무기 타격 경로(Blow)를 안 탄다. 성문 부수는 15초 내내 0칸이라
        --     붕괴 직후 첫 교전을 가장 약한 상태로 맞았다(실측 14:49).
        --   [왜 뺐나] 고치려던 것보다 큰 걸 망가뜨렸다.
        --     ① 실측(19:26) — 성문 19초 동안 5칸을 다 채우고 2단계를 시작했다.
        --        "0스택에서 시작해 5스택을 유지하는 것"이 이 무기의 실력 요소인데
        --        그 구간을 통째로 건너뛰게 만들었다.
        --     ② 다른 근접 6종은 2단계를 아무 버프 없이 시작한다. 사쿠라만
        --        공짜 준비 시간을 받는 셈이라 무기 간 형평이 깨진다.
        --   ⚠️ 상한(2칸까지만 허용)도 검토했으나 폐기했다 — 유저가 그 2칸을
        --     '풀스택'으로 오인할 여지가 있어 스택 UI 의 의미가 흐려진다.
        --   [원래 문제는?] 그 사이 SLASH_DAMAGE 가 5 고정 → 5 + 스택×2 로 바뀌었다.
        --     0칸이어도 예전과 상황이 다르므로, 다시 약하다고 판단되면 그때는
        --     스택이 아니라 0칸 데미지 쪽을 볼 것.
        --   ⚠️ _G.sakuraStackers 등록부는 SakuraBlade.SwordScript 에 그대로 살아 있다.
        --     소비처가 여기 하나뿐이라 지금은 아무도 호출하지 않는다 —
        --     되살릴 일이 없다고 판단되면 그쪽 등록·해제도 같이 지울 것.

        -- 🪓 [연출 2026-09-04] 때린 봇에게 스윙 모션을 재생시킨다.
        --   [증상] 봇은 벽을 '공격'하지 않고 밀착만 하면 아래 겹침 검사가 깎는 구조라,
        --     성문을 부수는 내내 봇이 가만히 서 있는 것처럼 보였다.
        --   [규칙] 연출만 요청한다. 데미지·재타격 쿨(1.6s)은 여기가 그대로 소유하므로
        --     스윙이 타격 판정에 관여하지 않는다.
        --   ⚠️ AI 봇만. 유저는 자기 무기 애니가 이미 돌고 있어 겹치면 어색해진다.
        if attacker:GetAttribute("AIRunner") and _G.playBotSwing then
            pcall(_G.playBotSwing, attacker)
        end
    end
end

-- ⚠️ Touched 를 쓰지 않는다.
--   Touched 는 "접촉이 시작될 때" 한 번만 발생한다. 봇이 벽에 밀착해 정지하면
--   이벤트가 더 이상 오지 않아 몇 대 때리다 멈춘다(실측: HP 5→3 에서 정지).
--   → 주기적으로 조각 주변을 검사해 "붙어 있는 동안 계속" 판정한다.
--
-- ⚠️ 단, 이 근접 판정은 AI 봇 전용이다.
--   근접 판정은 "벽 앞에 서 있기만 하면 깎임"이라 무기를 휘두르는지 보지 않는다.
--   따라서 유저에게 적용하면 무기 공속 차이(0.45초 ~ 6초, 13배)가 전부 사라지고
--   "벽 앞에 서 있기"가 최적 전략이 된다.
--   유저는 아래 hookPlayerAttacks() 가 Tool.Activated 를 감지해 처리한다 —
--   무기마다 자기 쿨다운(Tool.Enabled 게이트)이 있으니 공속이 자동으로 반영된다.
local SCAN_DT    = 0.2    -- 겹침 검사 주기(초)
local REACH      = 4      -- 조각 표면에서 이 거리 안의 캐릭터를 공격자로 인정(무기 길이 감안)

local function scanSegment(seg)
    if seg:GetAttribute("BarricadeHP") == nil then return end
    local op = OverlapParams.new()
    op.FilterType = Enum.RaycastFilterType.Exclude
    op.FilterDescendantsInstances = { seg.Parent }
    -- 조각을 두께 방향으로만 넓힌 박스 — 벽면에 붙은 캐릭터를 잡는다
    local box = seg.Size + Vector3.new(REACH * 2, 0, 0)
    local parts = workspace:GetPartBoundsInBox(seg.CFrame, box, op)

    local seen = {}
    for _, p in ipairs(parts) do
        local char = p:FindFirstAncestorOfClass("Model")
        if char and not seen[char] and char:FindFirstChildOfClass("Humanoid") then
            seen[char] = true
            local hum = char:FindFirstChildOfClass("Humanoid")
            -- 유저는 제외 — 공격 기반(hookPlayerAttacks)으로 처리해 무기 공속을 반영한다
            local isUser = Players:GetPlayerFromCharacter(char) ~= nil
            if hum.Health > 0 and not isUser and isRunnerChar(char) then
                local now = os.clock()
                -- ⚠️ 이 경로는 봇 전용이다(위에서 isUser 를 걸렀다).
                if not lastHit[char] or (now - lastHit[char]) >= BOT_HIT_COOLDOWN then
                    lastHit[char] = now
                    damageSegment(seg, char)
                    if seg:GetAttribute("BarricadeHP") == nil then return end  -- 파괴됨
                end
            end
        end
    end
end

local function hookSegment(seg)
    if not seg:IsA("BasePart") then return end
    if seg:GetAttribute("BarricadeHP") == nil then return end   -- 기둥은 파괴 불가
    ensureGauge(seg)
    applyVisual(seg)
end

local function rebuild(mapName)
    local mf = workspace:FindFirstChild(mapName)
    if not mf then return end

    -- 🏰 연결 구조물(성문)을 먼저 되살린다.
    -- ⚠️ 판정 파트보다 먼저여야 한다. 판정 파트의 applyVisual 이 성문 색을
    --    입히는데, 성문이 없으면 그 처리가 헛돈다.
    restoreGates(mapName)

    local list = blueprints[mapName]
    if not list then return end

    local folder = mf:FindFirstChild("Barricades")
    if folder then folder:Destroy() end
    folder = Instance.new("Folder"); folder.Name = "Barricades"; folder.Parent = mf

    for _, b in ipairs(list) do
        local p = Instance.new("Part")
        p.Name = b.name
        p.Anchored = true
        -- ⚠️ [2026-08-23] 예전엔 두 값을 true 로 하드코딩했다. 통짜 구조물(성문)
        --    방식에서는 판정 파트가 투명·비충돌이어야 하는데, 재건 때마다 되살아나
        --    "성문 앞에 옛 벽이 다시 나타나는" 증상이 됐다.
        --    → 저장된 값을 복원한다(옛 데이터엔 없으니 true 폴백).
        p.CanCollide = (b.canCollide == nil) or b.canCollide
        p.CanQuery   = (b.canQuery == nil) or b.canQuery
        if b.castShadow ~= nil then p.CastShadow = b.castShadow end
        p.Size = b.size
        p.CFrame = b.cframe
        p.Color = b.color
        p.Material = b.material
        p.Transparency = b.transparency
        if b.hp then p:SetAttribute("BarricadeHP", b.hp) end
        -- ⚠️ MaxHP 는 반드시 붙인다. 없으면 게이지가 DEFAULT_HP 칸으로 그려져
        --    "체력이 일부만 복구된 것처럼" 보인다.
        p:SetAttribute("BarricadeMaxHP", b.maxHp or b.hp or DEFAULT_HP)
        if b.index then p:SetAttribute("BarricadeIndex", b.index) end
        -- 🏰 연결 구조물 정보 복원.
        -- ⚠️ 이걸 빠뜨리면 재건 후 연결이 끊겨, 판정 파트만 사라지고 성문은 그대로 남는다
        --    (실측 2026-08-23: "연결 구조물 함께 파괴" 로그가 안 찍혔다).
        if b.gate then p:SetAttribute("BarricadeGate", b.gate) end
        p.Parent = folder
        hookSegment(p)
    end
    print(string.format("[Barricade] %s 재건: %d개", mapName, #list))
end

snapshot()
-- 🏰 성문 원본 백업.
-- ⚠️ 부팅 시 1회. 이 시점의 성문이 '온전한 원본'이므로 파괴되기 전에 떠야 한다.
--    snapshot 뒤에 두는 이유: GATE_ATTR 이 설정된 판정 파트를 훑어야 대상을 안다.
backupGates()

for mapName in pairs(blueprints) do
    local folder = workspace[mapName]:FindFirstChild("Barricades")
    if folder then
        for _, d in ipairs(folder:GetChildren()) do hookSegment(d) end
    end
end

-- 라운드 시작(맵 지정)마다 재건 — 파괴 상태가 다음 라운드로 새지 않게
-- 🗺️ [2026-08-30] 활성 맵 폴더. frontBarricade 가 레이캐스트 대상을 고를 때 쓴다.
--   ⚠️ 비활성 맵도 workspace 에 남아 있으므로 "workspace 에서 이름으로 찾기"는 신뢰할 수 없다.
local activeMapFolder = nil

local setMapEvent = ReplicatedStorage:WaitForChild("SetCurrentMap", 5)
if setMapEvent and setMapEvent:IsA("BindableEvent") then
    setMapEvent.Event:Connect(function(folder)
        activeMapFolder = folder   -- ⚠️ 예전엔 인자를 버렸다. 이걸 안 받아서 map2 판정이 깨졌다.
        lastHit = {}
        for mapName in pairs(blueprints) do rebuild(mapName) end
    end)
end

-- 🏰 [2026-09-11] 공성 시간 인원 스케일. Stage2TriggerSystem 이 2단계 진입 시 1회 부른다.
--   [문제] 성문 HP 가 인원과 무관하게 고정이라 소수 러너 판에서 공성만 늘어진다.
--     실측 — 10칸을 부수는 데 봇 10마리 5.2s / 3마리 20.4s / 1마리 46.5s.
--     마리당 타격률은 0.16~0.22 /s 로 거의 상수라, 시간이 인원에 반비례한다.
--     1마리 판은 그 46.5초 동안 킹이 성문 너머라 손도 못 댄다(순수 대기 36초).
--   [왜 √ 인가] 선형(H ∝ N)으로 깎으면 타격률이 상수라 N 이 약분돼 인원과 무관하게
--     5.2초가 된다 = 공성 구간이 통째로 사라진다. 공성 중에는 공성 도구로만 견제한다는
--     설계(Stage2TriggerSystem 의 PushTool 지연 주석)가 그 5초에 들어갈 수 없다.
--     √ 는 "소수일수록 공성이 길다"는 성질을 남기면서 극단만 눌러준다:
--       10명 10칸 5.2s / 5명 7칸 7.2s / 3명 5칸 10.2s / 1명 3칸 14.0s
--   [왜 '첫 타격' 에 확정하나] 재건은 맵 선택 시점이라 그때는 아직 전원 생존이다.
--     2단계 진입 시점도 틀렸다 — 진입 후에도 킹이 계속 죽인다.
--     실측 16:05 판: 진입 시 9명 → 9칸으로 잠김 → 그 뒤 15초간 킹이 8명 처형 →
--     남은 1명이 9칸을 26초에 걸쳐 혼자 부쉈다. 고치려던 증상이 그대로 재현됐다.
--     성문을 실제로 때리기 시작하는 순간이 '공성 인원' 이 확정되는 유일한 시점이다.
--   ⚠️ 확정 후에는 안 바꾼다. 매 타격마다 재평가하면 게이지가 중간에 튄다.
--     BarricadeScaled 표식이 그 1회성을 보장한다(재건이 파트를 새로 만들어 자동 리셋).
--   ⚠️ MaxHP 는 절대 건드리지 않는다. 게이지 셀 수가 그 값을 쓰는데, ensureGauge 의
--     셀 재생성이 옛 셀을 완전히 지우지 못해 "왼쪽 참 / 가운데 빔 / 오른쪽 참"이 된다
--     (485행 주석의 08-25 수정이 불완전하다. 실측 2026-09-11 스크린샷).
--     HP 만 내리는 경로는 /capfill · /tp 가 이미 쓰는 검증된 길이다 —
--     TaggerBotSystem 의 "BarricadeMaxHP 는 안 건드린다" 주석이 같은 결론이다.
--   ⚠️ 그래서 게이지는 "10칸 중 3칸 남음"으로 그려진다. 의도한 표시다 —
--     칸 수가 곧 남은 타격 수라 정보는 정확하고, 킹에게 "곧 뚫린다"가 즉시 읽힌다.
--     MaxHP 를 내리면 "3칸 중 3칸 = 만전"으로 보여 오히려 방심을 부른다.
--   ⚠️ 중복 호출 방지는 모듈 플래그가 아니라 세그먼트 속성으로 한다. rebuild 가 파트를
--     새로 만들므로 표식이 저절로 사라진다 = 리셋을 따로 기억할 필요가 없다.
--     표식이 없으면 두 번 불릴 때 10 → 3 → 1 로 겹쳐 깎인다.
_G.ScaleBarricadeForStage2 = function()
    -- 인원을 여기서 직접 센다. 호출부(damageSegment)는 '언제' 만 알면 된다.
    -- ⚠️ 세는 방식은 Stage2TriggerSystem 의 headcount 와 같다(다운도 생존으로 센다).
    local total = (_G.RoundObs and _G.RoundObs.runnersTotal) or 0
    if total <= 0 then return end
    local alive = 0
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr:GetAttribute("Role") == "Runner" then
            local ch = plr.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then alive = alive + 1 end
        end
    end
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("AIRunner") then
            local hum = m:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then alive = alive + 1 end
        end
    end
    if alive <= 0 then return end
    local ratio = math.sqrt(alive / total)
    for _, mapName in ipairs({ "map1", "map2" }) do
        local mf = workspace:FindFirstChild(mapName)
        local bf = mf and mf:FindFirstChild("Barricades")
        if bf then
            for _, seg in ipairs(bf:GetDescendants()) do
                local maxHp = seg:GetAttribute("BarricadeMaxHP") or seg:GetAttribute("BarricadeHP")
                if maxHp and not seg:GetAttribute("BarricadeScaled") then
                    seg:SetAttribute("BarricadeScaled", true)
                    local newHp = math.max(1, math.floor(maxHp * ratio + 0.5))
                    if newHp < maxHp then
                        seg:SetAttribute("BarricadeHP", newHp)
                        print(string.format("🏰 [Barricade] 공성 축소: %s 남은 %d/%d칸 (생존 %d/%d)",
                            seg.Name, newHp, maxHp, alive, total))
                    end
                end
            end
        end
    end
end

-- 🧪 [테스트 2026-09-05] 바리케이드 게이지를 1칸으로 낮춘다. /capfill 이 부른다.
--   [왜] 2단계 진입 후 성문을 부수는 데만 30초가 든다. 점령 완료 연출을 반복
--     확인할 때 그 시간이 매번 통째로 낭비됐다.
--   [왜 0 이 아니라 1 인가] 0 으로 만들면 여기서 파괴 처리를 직접 해야 하는데,
--     성문 붕괴는 태거 HP 확정·곡사포 파괴·2단계 전환이 줄줄이 엮인 지점이다.
--     1 로 두면 다음 한 대에 '정상 경로'가 그대로 돌아간다 — 테스트 전용 분기를
--     만들지 않는다는 원칙(/capfill 95%와 같은 이유)을 지킨다.
--   ⚠️ 릴리즈 전 삭제.
_G.DebugWeakenBarricades = function()
    local n, hit = 0, 0
    for _, mapName in ipairs({ "map1", "map2" }) do
        local mf = workspace:FindFirstChild(mapName)
        local bf = mf and mf:FindFirstChild("Barricades")
        if bf then
            for _, seg in ipairs(bf:GetDescendants()) do
                local hp = seg:GetAttribute("BarricadeHP")
                if hp and hp > 1 then
                    seg:SetAttribute("BarricadeHP", 1)
                    hit = hit + 1
                end
                if hp then n = n + 1 end
            end
        end
    end
    return hit, n
end

_G.RebuildBarricades = function()
    for mapName in pairs(blueprints) do rebuild(mapName) end
end

-- 🚪 [2026-08-31] 성문 X(홀드 라인) 조회 — 청사진 기준.
--   [왜 workspace 를 읽으면 안 되나] SetCurrentMap 은 BindableEvent 이고
--     Roblox 기본 SignalBehavior=Deferred 라 Fire() 가 핸들러를 즉시 돌리지 않는다.
--     RoundSystem 은 그대로 TAGGER SELECTION 까지 진행하므로,
--     TaggerBot 이 홀드 라인을 읽는 시점의 Barricades 폴더는 아직 '전 라운드 파괴 상태'다.
--   [실측 2026-08-30 17:32:51] 같은 맵(map2)이 연속 선택되고 전 판에서 성문이 부서진 경우:
--     .860 [TaggerBot] 성문 못 찾음  →  .888 [Barricade] map2 성문 복원: 11개
--     28ms 차이로 봇이 홀드 라인 없이 출발했고, 그 판에서만 킹이 죽었다.
--   [해결] 청사진은 부팅 시 snapshot() 으로 뜨고 파괴되지 않는다 → 순서 의존이 사라진다.
--   ⚠️ 맵당 판정 파트는 1개다(map1/map2 모두 "원본 저장: 1개"). 여러 개가 되면
--     "가장 작은 X"가 아니라 용도에 맞는 기준을 다시 정할 것.
_G.GetBarricadeLineX = function(mapName)
    local list = blueprints[mapName]
    if not list or #list == 0 then return nil end
    local cf = list[1].cframe
    return cf and cf.Position.X or nil
end

-- ── 유저 공격 감지 ──────────────────────────────────────
-- 근접 판정(scanSegment)은 봇 전용이다. 유저는 실제로 무기를 휘두를 때만 벽이 깎여야
-- 무기 공속 차이가 의미를 갖는다.
-- Tool.Activated 는 무기 자신의 쿨다운(Tool.Enabled 게이트)을 통과했을 때만 발생하므로
-- 별도 계산 없이 공속이 반영된다 — 단, 아래 ANTI_SPAM 이 상한으로 걸린다.
-- ⚠️ [2026-08-29] 예전 주석은 공속 범위를 "0.45초 DiamondBlade ~ 6초 Hammer"로 적었으나
--   실측과 다르다. 실제 스윙 간격은 ClassicSword 0.18 / 검류 0.5 / Hammer 1.8 /
--   Flame Hammer 2.0 이다(스킬 쿨이 아니라 평타 간격 기준).
--   이 오해 때문에 ANTI_SPAM 0.15 가 아무것도 막지 못했다.
local PLAYER_REACH = 7        -- 유저 공격 사거리(stud). 무기 길이 + 팔 길이 감안
local ANTI_SPAM    = 1.3      -- 유저 재타격 쿨다운(초)
-- ⚠️ [밸런스 2026-08-29] 0.15 → 1.3. 이름은 '스팸 방지'지만 이제 밸런스 값이다.
--   [증상] 유저 혼자 1.75초 만에 성문을 부쉈다(실측 13:47:24.437~26.187, 10타 0.18초 간격).
--     봇 10명이 6.9초 걸리는 것과 비교해도 공성이라 부를 수 없는 속도였다.
--   [원인] 위 주석이 "가장 빠른 무기(0.45)보다 훨씬 짧아 공속을 안 뭉갬"이라 적고 있는데,
--     실측한 ClassicSword 스윙 간격은 0.18초다. 전제가 틀려 0.15 가 아무것도 안 막았다.
--   [1.3 인 이유]
--     · 혼자 10타 = 13초. 공성 국면이 성립한다.
--     · 봇(BOT_HIT_COOLDOWN 1.6)보다 빨라 유저의 이점은 남는다.
--     · 느린 무기(Hammer 1.8 / Flame Hammer 2.0)는 여전히 자기 공속이 상한이라
--       "무기 공속이 의미를 갖는다"는 원래 설계가 죽지 않는다.
--   ⚠️ 이 값은 태거 HP 확정 시점과 연결돼 있다. 성문 붕괴 순간에 HP 가 확정되므로
--     (Stage2TriggerSystem.finalizeTaggerHp), 붕괴가 빠르면 러너가 덜 모인 채로 확정된다.
--     여기를 다시 내릴 거면 그 영향을 함께 볼 것.

local function frontBarricade(char)
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local origin = root.Position
    local dir = root.CFrame.LookVector
    local flat = Vector3.new(dir.X, 0, dir.Z)
    if flat.Magnitude < 0.01 then return nil end
    flat = flat.Unit

    -- ⚠️ [2026-08-23] 통짜 구조물(성문) 도입 후 두 번의 문제가 있었다.
    --   1차: 레이가 성문에 먼저 맞아 판정이 안 됐다 → Include 로 판정 파트만 노렸다.
    --   2차: 그랬더니 이번엔 성문 벽면(X 734~742)이 판정 파트(X 727.7)보다 앞에 있어
    --        러너가 성문에 막혀 판정 파트에 닿지 못했다. "어디를 때려야 하는지
    --        모르겠다"는 체감이 여기서 나왔다.
    --   → 판정 파트 + 연결 구조물을 모두 후보에 넣고, 무엇에 맞든 판정 파트를 반환한다.
    --     이러면 성문 어느 면을 때려도 인정된다.
    local barricadeFolder, gateParts, gateOwner = nil, {}, nil
    do
        -- 🗺️ [2026-08-30] 활성 맵을 최우선으로 본다.
        --   [증상] map2 라운드에서 유저가 성문을 때려도 게이지가 안 닳았다(봇 타격만 기록됨).
        --   [원인] 아래 목록을 map1 부터 훑고 먼저 걸리는 맵에서 break 했는데,
        --     비활성 맵도 workspace 에 그대로 남아 있어 map2 라운드에도 항상 map1 이 잡혔다.
        --     레이가 1500 stud 밖 map1 판정 파트를 향해 나가 아무것도 못 맞혔고,
        --     frontBarricade 가 nil 을 돌려 damageSegment 까지 도달조차 못 했다.
        --   ⚠️ AI 는 scanSegment(범위 겹침) 경로라 이 함수를 안 탄다. 그래서 봇 타격만 정상이었다.
        --   ⚠️ CapturePoint 도 똑같은 이유로 깨졌던 이력이 있다(CaptureSystem 참조). 같은 병이다.
        --   ⚠️ 하드코딩 목록은 SetCurrentMap 을 못 받았을 때의 폴백으로만 남긴다.
        local mapCandidates = {}
        if activeMapFolder and activeMapFolder.Parent then
            mapCandidates[1] = activeMapFolder
        end
        for _, mapName in ipairs({ "map1", "map2" }) do
            local m = workspace:FindFirstChild(mapName)
            if m then mapCandidates[#mapCandidates + 1] = m end
        end
        for _, mf in ipairs(mapCandidates) do
            local f = mf:FindFirstChild("Barricades")
            if f and #f:GetChildren() > 0 then
                barricadeFolder = f
                -- 연결 구조물 수집
                for _, segPart in ipairs(f:GetChildren()) do
                    local gname = segPart:GetAttribute(GATE_ATTR)
                    if gname then
                        gateOwner = segPart
                        for _, target in ipairs(string.split(gname, ",")) do
                            target = target:gsub("^%s+", ""):gsub("%s+$", "")
                            for _, obj in ipairs(mf:GetDescendants()) do
                                if obj.Name == target then gateParts[#gateParts + 1] = obj end
                            end
                        end
                    end
                end
                break
            end
        end
    end
    if not barricadeFolder then return nil end

    local includeList = { barricadeFolder }
    for _, g in ipairs(gateParts) do includeList[#includeList + 1] = g end

    for _, off in ipairs({0, 0.25, -0.25}) do
        local d = (flat + Vector3.new(-flat.Z, 0, flat.X) * off).Unit
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Include
        rp.FilterDescendantsInstances = includeList
        local hit = workspace:Raycast(origin, d * PLAYER_REACH, rp)
        if hit then
            -- 판정 파트를 직접 맞춘 경우
            if hit.Instance:GetAttribute("BarricadeHP") ~= nil then
                return hit.Instance
            end
            -- 연결 구조물(성문)을 맞춘 경우 → 그 구조물의 판정 파트를 반환
            if gateOwner and gateOwner.Parent then
                return gateOwner
            end
        end
    end
    return nil
end

local function hookTool(player, tool)
    if not tool:IsA("Tool") then return end
    if tool:GetAttribute("_BarricadeHooked") then return end
    tool:SetAttribute("_BarricadeHooked", true)
    tool.Activated:Connect(function()
        local char = player.Character
        if not char then return end
        if player:GetAttribute("Role") ~= "Runner" then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        -- 얼음(Ice 킬이펙트)에 갇힌 동안에는 벽도 못 친다
        if char:GetAttribute("IceFrozen") then return end
        -- 익스플로잇 방어: 클라가 Activated 를 연사해도 하한 이하로는 안 먹음
        local now = os.clock()
        if lastHit[char] and (now - lastHit[char]) < ANTI_SPAM then return end
        local seg = frontBarricade(char)
        if not seg then return end
        lastHit[char] = now
        damageSegment(seg, char)
    end)
end

local function watchPlayer(player)
    local function onChar(char)
        for _, c in ipairs(char:GetChildren()) do hookTool(player, c) end
        char.ChildAdded:Connect(function(c) hookTool(player, c) end)
    end
    if player.Character then onChar(player.Character) end
    player.CharacterAdded:Connect(onChar)
end

for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
Players.PlayerAdded:Connect(watchPlayer)

-- 겹침 검사 루프. Touched 대신 이걸로 "붙어 있는 동안 계속" 판정한다.
task.spawn(function()
    while true do
        task.wait(SCAN_DT)
        -- ⚠️ [2026-08-27] 라운드가 살아있을 때만 판정한다. (_G.IsRoundLive 규약)
        --   [증상] 2번째 라운드가 바리케이드 만전이 아닌 상태(7/10)로 시작.
        --   [원인] rebuild 는 태거 선정 시점에 도는데 라운드 시작은 그로부터 ~15초 뒤다.
        --     그 사이 이전 라운드 AI 러너가 아직 살아있고(정리는 spawnAIRunners 안에서
        --     다음 라운드 스폰 때 일어남), 이 스캔 루프는 라운드 상태를 안 봤다.
        --     → 새로 세운 벽 앞에 남아있던 봇이 인터미션 동안 벽을 깎았다.
        --     (실측 22:47:36 재건 → 35ms 뒤 AIRunner_10 피격, 라운드 시작 전까지 3대)
        --   ⚠️ aiRunners 정리를 앞당기면 안 된다 — 관전 대상(RoundSystem:1087),
        --     registerDownedAsKills(1404), 결과창 집계(2875)가 종료 후에도 이걸 읽는다.
        --   ⚠️ _G.IsRoundLive 가 아직 없는 부팅 직후에는 통과시킨다(fail-open). 게이트가
        --     영영 안 걸려 벽이 영구 무적이 되는 쪽이 훨씬 나쁜 실패다.
        if _G.IsRoundLive and not _G.IsRoundLive() then continue end
        for mapName in pairs(blueprints) do
            local mf = workspace:FindFirstChild(mapName)
            local folder = mf and mf:FindFirstChild("Barricades")
            if folder then
                for _, seg in ipairs(folder:GetChildren()) do
                    if seg:IsA("BasePart") then
                        local ok, err = pcall(scanSegment, seg)
                        if not ok then warn("[Barricade] scan 오류: " .. tostring(err)) end
                    end
                end
            end
        end
    end
end)

-- ⚠️ DEFAULT_HP 는 파트에 BarricadeHP 속성이 없을 때만 쓰는 폴백이다.
--   실제 워크스페이스 바리케이드는 map1·map2 모두 BarricadeHP=8 / MaxHP=8 이라
--   이 폴백은 실전에서 한 번도 쓰이지 않는다. 로그를 8 로 하드코딩하지 말 것
--   (snapshot() 이 워크스페이스 현재 상태를 청사진으로 쓰므로 값의 출처는 파트 속성이다).
print(string.format("✅ BarricadeSystem 준비 (폴백HP %d, 재타격 %.2fs, 라운드마다 재건)",
    DEFAULT_HP, HIT_COOLDOWN))
