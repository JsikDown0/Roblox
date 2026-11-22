-- RobuxBoxClient
-- 로비의 랜덤 상자 3D 오브젝트 → 실제 로벅스 구매 연결.
--
-- ⚠️ 정책 게이트가 핵심이다.
--   RobuxStoreClient 는 유료 랜덤 상자 섹션을 이렇게 막고 있다:
--     boxSection.Visible = (player:GetAttribute("NoPaidRandom") == false)
--   즉 "명시적 false(허용)" 일 때만 노출하고, nil/true 면 숨긴다(보수적).
--   그런데 로비에 물리 상자를 세우면 그 게이트를 우회하게 된다 — 규제 대상 유저에게도
--   상자가 보이고 눌린다. 그래서 3D 쪽에도 동일 조건을 적용해 상자 자체를 숨긴다.
--
-- 구매 호출은 클라이언트에서 한다(RobuxStoreClient 와 동일 방식).

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer

local function allowed()
    return player:GetAttribute("NoPaidRandom") == false
end

local function boxFolder()
    return workspace:FindFirstChild("RobuxBoxes")
end

-- 정책에 따라 상자 표시/숨김 + 프롬프트 활성화 제어
local function applyPolicy()
    local folder = boxFolder()
    if not folder then return end
    local show = allowed()
    for _, m in ipairs(folder:GetChildren()) do
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                -- LocalTransparencyModifier 는 클라 전용이라 서버 상태를 건드리지 않는다
                d.LocalTransparencyModifier = show and 0 or 1
            elseif d:IsA("ProximityPrompt") then
                d.Enabled = show
            end
        end
    end
end

-- 프롬프트 → 구매 창
local function hook(prompt)
    if prompt:GetAttribute("_hooked") then return end
    prompt:SetAttribute("_hooked", true)
    prompt.Triggered:Connect(function(plr)
        if plr ~= player then return end
        if not allowed() then return end   -- 이중 안전장치
        local model = prompt:FindFirstAncestorOfClass("Model")
        local pid = model and model:GetAttribute("ProductId")
        if not pid then return end
        local ok, err = pcall(function()
            MarketplaceService:PromptProductPurchase(player, pid)
        end)
        if not ok then warn("[RobuxBox] 구매 창 실패: " .. tostring(err)) end
    end)
end

local function hookAll()
    local folder = boxFolder()
    if not folder then return end
    for _, d in ipairs(folder:GetDescendants()) do
        if d:IsA("ProximityPrompt") then hook(d) end
    end
end

hookAll()
applyPolicy()

-- 정책 속성이 늦게 도착하거나 바뀔 수 있음
player:GetAttributeChangedSignal("NoPaidRandom"):Connect(applyPolicy)

-- 상자가 나중에 생기거나 교체될 수 있음
workspace.ChildAdded:Connect(function(c)
    if c.Name == "RobuxBoxes" then
        task.wait(0.2)
        hookAll(); applyPolicy()
    end
end)

-- 주기 확인(가벼움: 상자 4개 수준)
task.spawn(function()
    while true do
        task.wait(1)
        hookAll()
        applyPolicy()
    end
end)

print("✅ RobuxBoxClient 활성화 (로비 랜덤 상자 — NoPaidRandom 게이트 적용)")
