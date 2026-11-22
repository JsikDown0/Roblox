-- 내구도 소모음 재생 (DurabilitySystem 이 FireAllClients 로 알림)
--
-- ⚠️ 왜 클라에서 재생하는가: 서버에서 Sound 를 만들어 Play() 하면
--    SoundService.RespectFilteringEnabled = true 환경에서 클라에 안 들린다.
--    (2026-08-23 부활 보호막 사운드에서 실측: 서버 playing=true 인데 무음)
--    이 이벤트는 모든 클라에 오므로 각자 재생하면 전원이 듣는다.
--
-- ⚠️ 가공하지 않는다. EqualizerSoundEffect / PlaybackSpeed 를 걸었다가
--    소리가 죽은 전례가 있다. 원본 그대로 재생한다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("DurabilityHitSfx")

local SFX_ID = "rbxassetid://117793859307433"
local VOLUME = 2        -- 이 게임 효과음 관례(1.4~3.5)의 중간
local MAX_DIST = 90     -- 국지적 사건 — 전장 끝까지 들릴 필요 없음

-- 🛡️ [2026-08-26] 원거리 시각 피드백.
--
-- [문제] 태거는 X≈710 의 소환대에서 던지는데 러너는 X=100~400 에 있다.
--   즉 상시 300~600 stud 거리다. 그런데 기존 피드백은 둘 다 근거리 전용이었다:
--     · 머리 위 내구도 게이지: MaxDistance 160
--     · 이 효과음: RollOffMaxDistance 90
--   → 태거 화면에서는 아무 반응이 없고 러너도 안 죽는다.
--     "명중했는데 왜 안 죽지?" 하는 어색함이 남는다(실측 체감).
--
-- [해결] ItemMarkerClient 가 검증한 패턴을 쓴다 — BillboardGui + MaxDistance 2000.
--   빌보드는 원근으로 작아질 뿐 컬링돼도 그려지므로 전장 끝에서도 읽힌다.
-- ⚠️ 태거에게만 띄운다. 러너는 자기 게이지가 이미 눈앞에 있고,
--    전원에게 띄우면 다수 흡수 시 화면이 표식으로 덮인다.
-- ⚠️ 효과음 거리는 그대로 둔다. 소리는 "가까이서 일어난 일" 이라는 정보가 맞고,
--    전장 전체에 들리면 누구 소린지 알 수 없어 오히려 노이즈가 된다.
local SHIELD_COLOR = Color3.fromRGB(255, 210, 60)   -- DurabilitySystem.COL_FILL 과 동일
local POPUP_BASE_Y = 6.2    -- 시작 높이(stud)
local POPUP_RISE   = 4.5    -- 떠오르는 높이(stud)
local POPUP_TIME   = 0.9    -- 표시 시간(초)

local function isTagger()
    return player:GetAttribute("Role") == "Tagger"
end

local function showBlockPopup(character)
    local head = character:FindFirstChild("Head")
    if not head then return end

    local gui = Instance.new("BillboardGui")
    gui.Name = "_DurabilityBlockPopup"
    gui.Adornee = head
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.MaxDistance = 2000          -- 전장 반대편에서도 보이게 (ItemMarkerClient 와 동일)
    gui.Size = UDim2.fromOffset(120, 40)
    -- ⚠️ 머리 위 게이지들 위로 띄운다. 아래에서부터:
    --     HP 바 3.2 / 태거 HP 3.5 / 내구도 게이지 4.9 / 이 팝업 6.2
    --   겹치면 "막혔다"는 순간 정보가 게이지에 묻혀 안 읽힌다.
    gui.StudsOffset = Vector3.new(0, POPUP_BASE_Y, 0)
    gui.Parent = head

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextScaled = true
    label.Text = "🛡 BLOCKED"
    label.TextColor3 = SHIELD_COLOR
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.2
    label.Parent = gui

    -- 위로 떠오르며 사라진다. 여러 명이 동시에 막아도 서로 구분된다.
    -- ⚠️ 목표값은 POPUP_BASE_Y 기준이어야 한다. 하드코딩하면 시작 높이를
    --   바꿀 때 팝업이 아래로 떨어진다.
    TweenService:Create(gui, TweenInfo.new(POPUP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        StudsOffset = Vector3.new(0, POPUP_BASE_Y + POPUP_RISE, 0),
    }):Play()
    TweenService:Create(label, TweenInfo.new(POPUP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    }):Play()

    Debris:AddItem(gui, POPUP_TIME + 0.2)
end

remote.OnClientEvent:Connect(function(character)
    if not character or not character.Parent then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local sfx = Instance.new("Sound")
    sfx.Name = "_DurabilityHitSfx"
    sfx.SoundId = SFX_ID
    sfx.Volume = VOLUME
    sfx.RollOffMaxDistance = MAX_DIST
    sfx.Parent = hrp
    sfx:Play()
    Debris:AddItem(sfx, 4)

    if isTagger() then
        showBlockPopup(character)
    end
end)
