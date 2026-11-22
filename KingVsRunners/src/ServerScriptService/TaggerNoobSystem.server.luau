-- TaggerNoobSystem
-- 태거 머릿수가 부족할 때 채우는 단순 NPC.
-- 채팅에 /taggerbot 입력 시 workspace.TaggerNoob을 태거 스폰 위치로 이동시킴.
-- 별도 AI 없음 — 그냥 자리 채우는 용도.
--
-- TaggerNoob 모델이 없으면 자동 생성 (Noob을 복제).

local Players        = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local NOOB_NAME = "TaggerNoob"

-- ─────────────────────────────────────────────────────────────
-- TaggerNoob 모델 보장 (없으면 Noob 복제해서 생성)
-- ─────────────────────────────────────────────────────────────
local function ensureTaggerNoob()
    local existing = workspace:FindFirstChild(NOOB_NAME)
    if existing and existing:FindFirstChild("HumanoidRootPart") then
        return existing
    end
    if existing then existing:Destroy() end

    -- HRP 있는 멀쩡한 Noob 찾기
    local sourceNoob = nil
    -- 1) workspace live Noob
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name == "Noob" and child:FindFirstChild("HumanoidRootPart") then
            sourceNoob = child
            break
        end
    end
    -- 2) fallback: ServerStorage._TestRigs.Noob (dev rig)
    if not sourceNoob then
        local ss = game:GetService("ServerStorage")
        local testRigs = ss:FindFirstChild("_TestRigs")
        local rig = testRigs and testRigs:FindFirstChild("Noob")
        if rig and rig:FindFirstChild("HumanoidRootPart") then
            sourceNoob = rig
        else
            -- 3) fallback: any HRP Noob anywhere in ServerStorage
            for _, d in ipairs(ss:GetDescendants()) do
                if d:IsA("Model") and d.Name == "Noob" and d:FindFirstChild("HumanoidRootPart") then
                    sourceNoob = d
                    break
                end
            end
        end
    end
    if not sourceNoob then
        warn("[TaggerNoobSystem] 복제할 Noob 원본 모델을 찾을 수 없음")
        return nil
    end

    local clone = sourceNoob:Clone()
    clone.Name = NOOB_NAME
    clone.Parent = workspace
    print("[TaggerNoobSystem] TaggerNoob 모델 자동 생성")
    return clone
end

-- ─────────────────────────────────────────────────────────────
-- TaggerNoob을 태거 스폰 위치로 이동 + 활성화
-- ─────────────────────────────────────────────────────────────
local function activateTaggerNoob(mapName)
    local noob = ensureTaggerNoob()
    if not noob then return false end

    -- 사망 상태였으면 부활
    local hum = noob:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.MaxHealth = 100
        hum.Health = 100
    end

    -- 해당 맵의 태거 스폰 위치 찾기
    local mapFolder = workspace:FindFirstChild(mapName or "map1")
    local spawnPart = mapFolder and mapFolder:FindFirstChild("taggerspawn")
    if not spawnPart then
        -- 폴백: map1의 taggerspawn
        local m1 = workspace:FindFirstChild("map1")
        spawnPart = m1 and m1:FindFirstChild("taggerspawn")
    end

    if spawnPart then
        local targetCFrame = CFrame.new(spawnPart.Position + Vector3.new(0, 5, 0))
        noob:PivotTo(targetCFrame)
    end

    -- 태거 역할 속성
    noob:SetAttribute("Role", "Tagger")
    noob:SetAttribute("IsTaggerNoob", true)

    -- 식별용 빨간 Highlight
    local existingHl = noob:FindFirstChild("TaggerHighlight")
    if existingHl then existingHl:Destroy() end
    local hl = Instance.new("Highlight")
    hl.Name = "TaggerHighlight"
    hl.FillColor = Color3.fromRGB(255, 50, 50)
    hl.FillTransparency = 0.85
    hl.OutlineColor = Color3.fromRGB(255, 100, 100)
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = noob

    -- TaggerCharacter 콜리전 그룹 (기존 시스템과 호환)
    for _, part in ipairs(noob:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                part.CollisionGroup = "TaggerCharacter"
            end)
        end
    end

    print("[TaggerNoobSystem] TaggerNoob 활성화 →", spawnPart and spawnPart.Position or "(스폰 없음)")
    return true
end

local function deactivateTaggerNoob()
    local noob = workspace:FindFirstChild(NOOB_NAME)
    if not noob then return end
    -- 멀리 보내서 안 보이게
    noob:PivotTo(CFrame.new(0, 1000, 0))
    noob:SetAttribute("Role", nil)
    print("[TaggerNoobSystem] TaggerNoob 비활성화")
end

-- ─────────────────────────────────────────────────────────────
-- 채팅 명령어: /taggerbot (활성화), /taggerbot off (비활성화)
-- ─────────────────────────────────────────────────────────────
local isDev = require(game:GetService("ServerScriptService"):WaitForChild("DevAuth")).isDev

local function onChatted(player, message)
    if not isDev(player) then return end   -- 🔒 개발자 전용
    local lower = message:lower()
    if lower == "/taggerbot" or lower == "/taggerbot on" then
        local ok = activateTaggerNoob("map1")
        print(string.format("[TaggerNoobSystem] %s가 TaggerBot 호출%s",
            player.Name, ok and " 성공" or " 실패"))
    elseif lower == "/taggerbot off" then
        deactivateTaggerNoob()
    end
end

Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(message)
        onChatted(player, message)
    end)
end)
for _, player in ipairs(Players:GetPlayers()) do
    player.Chatted:Connect(function(message)
        onChatted(player, message)
    end)
end

print("✅ TaggerNoobSystem 활성화 (/taggerbot 으로 호출, /taggerbot off 로 제거)")
