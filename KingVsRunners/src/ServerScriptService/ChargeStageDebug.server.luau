-- 🎨 차징 슬랩 색 단계 테스트 커맨드
-- ⚠️ 릴리즈 전 삭제 대상.
--
-- [왜] 색 단계는 1단계에서 5~9킬을 해야 나온다. 매번 그렇게 채우면
--   연출 확인에 몇 분씩 걸린다. 값을 직접 넣어 즉시 확인한다.

local Players = game:GetService("Players")

-- ⚠️ 다른 디버그 시스템과 같은 방식으로 개발자를 판별한다.
--    Studio 에서는 항상 허용, 라이브에서는 지정 UserId 만.
local DEV_IDS = {
    [9228200642] = true,   -- melonberrystrong
}
local function isDev(player)
    if game:GetService("RunService"):IsStudio() then return true end
    return DEV_IDS[player.UserId] == true
end

local function setStage(player, stage)
    stage = math.clamp(math.floor(stage), 1, 3)
    -- ⚠️ 라운드 시작 시 초기화되지 않게 잠근다.
    --    /stageoff 로 해제한다.
    player:SetAttribute("_ChargeStageLocked", true)
    player:SetAttribute("PushChargeStage", stage)
    local ch = player.Character
    if ch then ch:SetAttribute("PushChargeStage", stage) end
    local names = { "흰색", "노랑", "빨강" }
    print(string.format("🎨 [ChargeDebug] %s → %d단계 (%s)",
        player.Name, stage, names[stage]))
    -- 🚫 [2026-09-02] 강화 단계는 현재 비활성이다(KillEffectSystem 에서 1 고정).
    --   이 명령은 '되살릴지 판단하려면 노랑·빨강을 실제로 봐야 한다'는 이유로 남겼다.
    --   즉 여기로 세운 단계는 정상 플레이에서는 절대 나오지 않는 상태다.
    if stage > 1 then
        print("   ⚠️ 강화 단계는 비활성 상태다 — 이 값은 디버그로 강제한 것이며 자연 발생하지 않는다")
    end
end

local function onChat(player, msg)
    if msg:sub(1,1) == "/" then
        print("[ChargeDebug] 수신 " .. msg .. " dev=" .. tostring(isDev(player)))
    end
    if not isDev(player) then return end
    local m = msg:lower()

    -- /stage1 /stage2 /stage3
    local n = m:match("^/stage(%d)$")
    if n then
        setStage(player, tonumber(n))
        return
    end

    -- /stagenext — 다음 단계로 순환
    if m == "/stagenext" then
        local cur = player:GetAttribute("PushChargeStage") or 1
        setStage(player, (cur % 3) + 1)
        return
    end

    -- 🧪 /capfill [비율] — 점령 게이지를 채운다 (기본 95%). ⚠️ 릴리즈 전 삭제
    --   [왜] 점령 완료 연출(ThroneFall)을 보려면 매번 18초를 채워야 하는데,
    --     봇전에서 그 상황까지 판당 1분 이상 걸려 반복 검증이 사실상 불가능했다.
    --   [기본 100%] 처음엔 95%로 뒀는데 한 번도 완료되지 않았다 — 테스트 중에는
    --     존이 비어 있어 감쇠가 먼저 돌아 75% 체크포인트로 떨어졌기 때문이다.
    --     100%는 체크포인트가 곧 목표치라 감쇠가 못 깎는다. 완료 판정과 그 뒤 연출은
    --     여전히 실제 라운드와 같은 코드가 실행한다.
    --     [부분 채우기] /capfill 50 처럼 숫자를 주면 그 비율로 채운다(감쇠 관찰용).
    --   ⚠️ 2단계 진입(점령 시작) 전에는 실패한다. 그때는 아직 존이 없다.
    local cf = m:match("^/capfill%s*(%d*)$")
    if cf then
        -- 🧱 바리케이드도 1칸으로. 성문 부수는 30초가 매 테스트마다 낭비됐다.
        --   ⚠️ 점령 전에 부를 수도 있으므로 게이지 채우기와 독립적으로 먼저 처리한다.
        --     (2단계 진입 전에는 debugFill 이 실패하는데, 그때도 바리케이드는 낮춰둬야
        --      바로 뚫고 들어갈 수 있다.)
        if _G.DebugWeakenBarricades then
            local okB, hit, tot = pcall(_G.DebugWeakenBarricades)
            if okB then
                print(string.format("🧱 [ChargeDebug] 바리케이드 %d/%d 개 → HP 1", hit or 0, tot or 0))
            else
                warn("🧱 [ChargeDebug] 바리케이드 약화 실패: " .. tostring(hit))
            end
        end

        local cs = _G.CaptureSystem
        if not (cs and cs.debugFill) then
            print("🧪 [ChargeDebug] CaptureSystem.debugFill 없음")
            return
        end
        local pct = tonumber(cf)
        local ratio = pct and (pct / 100) or 1.0
        local ok, info = cs.debugFill(ratio)
        print("🧪 [ChargeDebug] /capfill → " .. (ok and ("성공: " .. info) or ("실패: " .. tostring(info))))
        return
    end

    -- /killscore N — 점수를 직접 넣어 단계 계산까지 확인
    local sc = m:match("^/killscore%s+(%d+)$")
    if sc then
        local score = tonumber(sc)
        player:SetAttribute("RoundKills", score)
        player:SetAttribute("RoundAIKills", 0)
        local stage = (score >= 9) and 3 or (score >= 5) and 2 or 1
        setStage(player, stage)
        print(string.format("🎨 [ChargeDebug] 점수 %d → %d단계", score, stage))
        return
    end

    if m == "/stageoff" then
        player:SetAttribute("_ChargeStageLocked", nil)
        setStage(player, 1)
        player:SetAttribute("_ChargeStageLocked", nil)
        print("🎨 [ChargeDebug] 잠금 해제 — 이제 킬 수대로 오른다")
        return
    end

    if m == "/stagehelp" then
        print("🎨 [ChargeDebug] /stage1~3, /stagenext, /killscore N, /stageoff")
        return
    end
end

local function hook(player)
    player.Chatted:Connect(function(msg) onChat(player, msg) end)
end
for _, p in ipairs(Players:GetPlayers()) do hook(p) end
Players.PlayerAdded:Connect(hook)

print("🎨 ChargeStageDebug 준비 (/stage1~3, /stagenext, /killscore N)")
