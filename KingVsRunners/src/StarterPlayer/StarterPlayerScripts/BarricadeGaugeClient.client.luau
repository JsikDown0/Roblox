-- BarricadeGaugeClient
-- 바리케이드 내구도 게이지를 라운드 참가자(태거·러너)에게 보이게 한다.
--
-- 왜 양쪽 다인가:
--   · 러너: 벽을 부수는 주체다. 남은 칸을 모르면 "얼마나 더 때려야 하나"를 알 수 없고,
--     여럿이 붙었을 때 어느 조각에 합류할지도 판단할 수 없다.
--     (두께·색 변화만으로는 근거리에서만 보이고 정확한 잔량이 안 읽힌다)
--   · 태거: 벽 너머 발치가 사각이라 "어느 조각이 뚫리기 직전인지"를 알아야
--     그쪽으로 이동해 대비할 수 있다.
--
-- 화면 혼잡은 거리 제한(MAX_VIEW_DIST)으로 관리한다 — 가까운 조각만 보인다.
-- 서버가 만든 BillboardGui 는 기본적으로 전원에게 보이므로, 여기서 역할·거리로 끈다.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ⚠️ 처음엔 태거 전용으로 만들었으나 러너에게도 보여야 한다.
--    러너는 벽을 부수는 주체인데 남은 칸을 모르면 "얼마나 더 때려야 하나"를 알 수 없고,
--    여럿이 붙었을 때 어느 조각에 합류해야 효율적인지도 판단할 수 없다.
--    (태거는 어느 조각이 뚫리기 직전인지 알아야 하고 — 두 쪽 다 필요한 정보다)
local function canSee()
    local role = player:GetAttribute("Role")
    return role == "Tagger" or role == "Runner"
end

-- 표시 거리 상한(stud). BillboardGui.MaxDistance 가 AlwaysOnTop 과 겹치면
-- 기대대로 안 잘리는 경우가 있어(실측: 762~912 스터드 게이지가 로비에서 보였음),
-- 클라에서 직접 거리를 재서 끈다.
local MAX_VIEW_DIST = 220

local function applyVisibility()
    local allowed = canSee()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    for _, mapName in ipairs({"map1", "map2"}) do
        local mf = workspace:FindFirstChild(mapName)
        local folder = mf and mf:FindFirstChild("Barricades")
        if folder then
            for _, seg in ipairs(folder:GetChildren()) do
                local bb = seg:FindFirstChild("HpGauge")
                if bb then
                    local show = allowed
                    if show and root then
                        show = (seg.Position - root.Position).Magnitude <= MAX_VIEW_DIST
                    elseif show and not root then
                        show = false   -- 캐릭터 없으면(로비 로딩 등) 숨김
                    end
                    bb.Enabled = show
                end
            end
        end
    end
end

-- 역할 변경 시 즉시 반영
player:GetAttributeChangedSignal("Role"):Connect(applyVisibility)

-- 바리케이드는 라운드마다 재생성되므로, 새로 생긴 게이지도 처리해야 한다.
-- 매 프레임 순회는 낭비라 0.5초 주기로만 확인한다(조각 10개 수준이라 부담 없음).
task.spawn(function()
    while true do
        task.wait(0.5)
        applyVisibility()
    end
end)

applyVisibility()
print("✅ BarricadeGaugeClient 활성화 (내구도 게이지 — 태거·러너 공용)")
