-- LobbyFlagAnimator
-- 로비 상점에 전시된 리바이벌 플래그의 깃을 실제 스폰본처럼 흩날리게 한다.
--
-- 방식: 원본(ReplicatedStorage["revival flag"].AnimatedFlag.Animate)과 동일한
--   "프레임 16장을 순서대로 하나만 보이게" 방식. 깃 모양이 미리 조각나 있어
--   Transparency 토글만으로 펄럭임이 표현된다.
--
-- 원본과 다른 점(최적화):
--   · 원본은 매 프레임 reset() 으로 16개를 전부 순회한다(프레임당 16회 쓰기).
--     여기서는 "이전 프레임만 숨기고 다음 프레임만 보이기"로 2회 쓰기로 줄였다.
--   · 로비 장식이라 라운드 중에는 멈춘다(불필요한 연산 제거).
--
-- ⚠️ 라운드 중 로비 이펙트 숨김 목록에 이 깃발도 포함된다(LobbyEffectGate 참조).

local FRAME_TIME = 0.04   -- 원본과 동일 간격

local function findFlagFrames()
    local shop = workspace:FindFirstChild("shop")
    local holder = shop and shop:FindFirstChild("DisplayProps")
    local flagModel = holder and holder:FindFirstChild("Display_RevivalFlag")
    if not flagModel then return nil end
    -- 깃 프레임들은 Flag 서브모델 안의 MeshPart 이며 이름이 "1"~"16"
    local flag = flagModel:FindFirstChild("Flag")
    if not flag then
        -- ScaleTo/PivotTo 과정에서 계층이 바뀌었을 수 있어 이름으로 탐색
        for _, d in ipairs(flagModel:GetDescendants()) do
            if d:IsA("Model") and d.Name == "Flag" then flag = d break end
        end
    end
    if not flag then return nil end

    local frames = {}
    for i = 1, 16 do
        local p = flag:FindFirstChild(tostring(i))
        if p and p:IsA("BasePart") then frames[#frames + 1] = p end
    end
    if #frames < 2 then return nil end
    return frames
end

task.spawn(function()
    local frames
    -- 상점/전시물이 준비될 때까지 대기
    for _ = 1, 60 do
        frames = findFlagFrames()
        if frames then break end
        task.wait(0.5)
    end
    if not frames then
        warn("[LobbyFlag] Display_RevivalFlag 의 깃 프레임을 찾지 못함 — 애니메이션 생략")
        return
    end

    -- 시작 상태: 1번만 보이게
    for i, p in ipairs(frames) do
        p.Transparency = (i == 1) and 0 or 1
    end
    print(string.format("✅ LobbyFlagAnimator 시작 (프레임 %d장, %.2fs 간격)", #frames, FRAME_TIME))

    local idx = 1
    while true do
        task.wait(FRAME_TIME)
        -- 라운드 중에는 멈춘다(로비 장식이므로 연산 낭비 방지)
        if _G.IsRoundLive and _G.IsRoundLive() then
            -- 정지 상태에서도 한 장은 보이게 유지
            continue
        end
        local prev = frames[idx]
        idx = (idx % #frames) + 1
        local nxt = frames[idx]
        -- 원본의 reset() 전체 순회 대신 2회 쓰기로 처리
        if prev and prev.Parent then prev.Transparency = 1 end
        if nxt and nxt.Parent then nxt.Transparency = 0 end
        if not (nxt and nxt.Parent) then
            -- 전시물이 교체/삭제됨 → 다시 탐색
            frames = findFlagFrames()
            if not frames then return end
            idx = 1
        end
    end
end)
