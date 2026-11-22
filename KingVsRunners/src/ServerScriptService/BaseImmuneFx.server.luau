-- ═══════════════════════════════════════════════════════════
-- 🛡️ 태거 베이스 면역 연출
--
-- [왜] 태거베이스 안의 러너는 태거 아이템에 안 맞는데, 아무 표시가 없어
--   양쪽 다 혼란스러웠다.
--     러너: "스쳤는데 왜 안 죽지?"
--     태거: "맞췄는데 왜 안 죽지?"
--   숨은 규칙은 버그로 읽힌다. 막히는 순간을 보여줘야 한다.
--
-- [설계] 경계선은 점령존(노란 테두리)과 헷갈려서 쓰지 않는다.
--   대신 '막힌 순간'에만 표시한다:
--     · 부활 무적과 같은 ForceField 오브 (ReviveSystem 재활용)
--     · "IMMUNE!" 텍스트 (런지 FXClient 와 같은 방식)
--
-- ⚠️ 각 아이템 시스템이 _G.showBaseImmune(character) 를 부르면 된다.
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local ORB_LIFETIME  = 0.55    -- 오브 유지
local TEXT_LIFETIME = 0.9     -- 텍스트 유지
local COOLDOWN      = 0.6     -- 같은 캐릭터에 연속 표시 방지

local lastShown = {}

local function makeOrb(char)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    -- ⚠️ 이미 떠 있으면 새로 만들지 않는다(연타 시 겹침 방지)
    if char:FindFirstChild("_BaseImmuneOrb") then return end

    local orb = Instance.new("Part")
    orb.Name = "_BaseImmuneOrb"
    orb.Shape = Enum.PartType.Ball
    orb.Size = Vector3.new(9, 9, 9)
    orb.Material = Enum.Material.ForceField
    -- ⚠️ 부활 무적(하늘색 120,220,255)과 구분되는 색.
    --    태거베이스가 붉은 카펫이므로 금빛으로 간다.
    orb.Color = Color3.fromRGB(255, 215, 90)
    orb.Transparency = 0.4
    orb.CanCollide = false
    orb.CanQuery = false
    orb.CanTouch = false
    orb.CastShadow = false
    orb.Massless = true
    orb.CFrame = hrp.CFrame
    orb.Parent = char

    local weld = Instance.new("WeldConstraint")
    weld.Part0 = hrp
    weld.Part1 = orb
    weld.Parent = orb

    Debris:AddItem(orb, ORB_LIFETIME)
end

local function makeText(char)
    local head = char:FindFirstChild("Head")
    if not head then return end
    local oldGui = head:FindFirstChild("_BaseImmuneText")
    if oldGui then oldGui:Destroy() end

    local bb = Instance.new("BillboardGui")
    bb.Name = "_BaseImmuneText"
    bb.Size = UDim2.new(0, 130, 0, 34)
    -- ⚠️ 부활 무적 배지(_ReviveShieldHud)가 4.4 에 고정돼 있다.
    --    떠오르는 범위가 겹치지 않게 아래에서 시작해 4.0 까지만 올린다.
    bb.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 200
    bb.Adornee = head
    bb.Parent = head

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBlack
    lbl.TextScaled = true
    lbl.Text = "IMMUNE!"
    lbl.TextColor3 = Color3.fromRGB(255, 225, 100)
    lbl.TextStrokeColor3 = Color3.fromRGB(40, 25, 0)
    lbl.TextStrokeTransparency = 0.1
    lbl.Parent = bb

    -- ⚠️ 위로 떠오르며 사라진다. 런지 텍스트와 같은 느낌.
    task.spawn(function()
        local t0 = os.clock()
        while os.clock() - t0 < TEXT_LIFETIME do
            if not bb.Parent then return end
            local a = (os.clock() - t0) / TEXT_LIFETIME
            bb.StudsOffsetWorldSpace = Vector3.new(0, 2.4 + a * 1.6, 0)
            lbl.TextTransparency = a * a
            lbl.TextStrokeTransparency = 0.1 + a * 0.9
            task.wait()
        end
        if bb.Parent then bb:Destroy() end
    end)
end

-- 🛡️ 외부에서 부르는 진입점
_G.showBaseImmune = function(character)
    if not character or not character.Parent then return end
    local now = os.clock()
    if lastShown[character] and now - lastShown[character] < COOLDOWN then return end
    lastShown[character] = now

    makeOrb(character)
    makeText(character)
end

-- 정리
Players.PlayerRemoving:Connect(function(p)
    if p.Character then lastShown[p.Character] = nil end
end)

print("🛡️ BaseImmuneFx 준비 (_G.showBaseImmune)")
