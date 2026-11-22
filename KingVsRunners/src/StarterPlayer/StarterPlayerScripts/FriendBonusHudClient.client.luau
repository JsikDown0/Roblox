-- FriendBonusHudClient
-- 친구 보너스 상태 표시 + 초대 버튼.
--
-- 왜 필요한가:
--   보너스가 조용히 들어가면 유저가 "친구를 데려오면 이득"이라는 사실 자체를 모른다.
--   그러면 초대 유인이 0이 되어 기능이 없는 것과 같아진다.
--   친구가 0명일 때도 표시해야 "데려오면 올라간다"는 것을 학습한다(그 자체가 광고).
--
-- 구조 메모:
--   · HUD 는 StarterGui.NewGui.HUD (Canvas > Currency / Buttons) — 스크립트가 갱신한다.
--     Currency 아래 빈 구간(Y 0.396 ~ 0.641)에 얹어 기존 레이아웃을 건드리지 않는다.
--   · 친구 수는 서버(FriendBonusSystem)가 FriendBonusCount 속성으로 갱신한다.
--   · 라운드 중에는 HudButtonClient 가 좌측 HUD 를 숨기므로, 같은 조건으로 함께 숨긴다.

local Players       = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local RunService    = game:GetService("RunService")

local player = Players.LocalPlayer

local GOLD  = Color3.fromRGB(255, 214, 0)
local DIM   = Color3.fromRGB(170, 170, 180)

local gui, root, label, inviteBtn

local function build()
    if gui and gui.Parent then return end
    gui = Instance.new("ScreenGui")
    gui.Name = "FriendBonusHud"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 6
    gui.Parent = player:WaitForChild("PlayerGui")

    root = Instance.new("Frame")
    root.Name = "Bar"
    root.AnchorPoint = Vector2.new(0, 0)
    -- ⚠️ 좌측 HUD 는 스케일이 아니라 픽셀 오프셋 좌표계를 쓴다(HudButtonClient 의 HUD_LAYOUT).
    --    스케일로 잡으면 해상도/디바이스마다 어긋난다. 아래 anchorToBanner() 에서
    --    실제 PromoBanner 의 위치·크기를 읽어 그 아래로 맞춘다(값 하드코딩 회피).
    root.Position = UDim2.new(0, 24, 0, 486)   -- 임시값, anchorToBanner 가 덮어씀
    root.Size = UDim2.new(0, 280, 0, 34)
    root.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    root.BackgroundTransparency = 0.25
    root.BorderSizePixel = 0
    root.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.3, 0)
    corner.Parent = root

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(0, 0, 0)
    stroke.Thickness = 2
    stroke.Transparency = 0.35
    stroke.Parent = root

    label = Instance.new("TextLabel")
    label.Name = "Text"
    label.AnchorPoint = Vector2.new(0, 0.5)
    label.Position = UDim2.new(0.04, 0, 0.5, 0)
    label.Size = UDim2.new(0.72, 0, 0.72, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.FredokaOne
    label.TextScaled = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    -- 세로 중앙 정렬: AnchorPoint 0.5 + Position 0.5 만으로는 프레임 기준 중앙이고,
    -- 라벨 "내부"의 글자 정렬은 TextYAlignment 가 결정한다. 둘 다 필요.
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextColor3 = DIM
    label.Text = "Friend Bonus: +0 Pass XP"
    label.Parent = root

    local ls = Instance.new("UIStroke")
    ls.Color = Color3.new(0, 0, 0)
    ls.Thickness = 2
    ls.Transparency = 0.3
    ls.Parent = label

    -- 초대 버튼: 로블록스 내장 초대 창을 띄운다(별도 UI 불필요)
    inviteBtn = Instance.new("TextButton")
    inviteBtn.Name = "Invite"
    inviteBtn.AnchorPoint = Vector2.new(1, 0.5)
    inviteBtn.Position = UDim2.new(0.97, 0, 0.5, 0)
    inviteBtn.Size = UDim2.new(0.19, 0, 0.78, 0)
    inviteBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 90)
    inviteBtn.BorderSizePixel = 0
    inviteBtn.Font = Enum.Font.GothamBold
    inviteBtn.Text = "+"
    inviteBtn.TextScaled = true
    inviteBtn.TextColor3 = Color3.new(1, 1, 1)
    inviteBtn.Parent = root

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0.25, 0)
    bc.Parent = inviteBtn

    inviteBtn.MouseButton1Click:Connect(function()
        -- 플랫폼/정책에 따라 초대가 불가할 수 있어 pcall 로 감싼다
        local ok, canInvite = pcall(function()
            return SocialService:CanSendGameInviteAsync(player)
        end)
        if ok and canInvite then
            pcall(function() SocialService:PromptGameInvite(player) end)
        end
    end)
end

build()

local function refresh()
    if not root then return end
    local n = player:GetAttribute("FriendBonusCount") or 0
    local each = 10   -- BattlePassSystem.FRIEND_XP_EACH 와 맞춘 표시값
    if n > 0 then
        label.Text = string.format("Friend Bonus: +%d Pass XP", each * n)
        label.TextColor3 = GOLD
    else
        label.Text = "Friend Bonus: +0 Pass XP"
        label.TextColor3 = DIM
    end
end

player:GetAttributeChangedSignal("FriendBonusCount"):Connect(refresh)
refresh()

-- 로벅스 홍보 배너(PromoBanner) 아래에 정렬한다.
-- 배너는 HudButtonClient 가 런타임에 만들고 디바이스별 크기가 달라(PC 280×84 / 모바일 128×56),
-- 값을 하드코딩하면 한쪽에서 어긋난다 → 실제 인스턴스를 읽어 맞춘다.
local function anchorToBanner()
    -- ⚠️ HUD 는 PlayerGui.NewGui.HUD 에 있다(최상위 아님) → 재귀 검색
    local banner = player.PlayerGui:FindFirstChild("PromoBanner", true)
    if not (banner and root) then return false end
    local bx = banner.Position.X.Offset
    local by = banner.Position.Y.Offset
    local bw = banner.Size.X.Offset
    local bh = banner.Size.Y.Offset
    if bw <= 0 or bh <= 0 then return false end
    root.Position = UDim2.new(0, bx, 0, by + bh + 8)
    root.Size = UDim2.new(0, bw, 0, math.max(28, math.floor(bh * 0.42)))
    return true
end

task.spawn(function()
    -- 배너가 생성될 때까지 대기 후 정렬
    for _ = 1, 80 do
        if anchorToBanner() then break end
        task.wait(0.25)
    end
    -- 배너 위치/크기가 바뀌면 따라간다
    -- ⚠️ HUD 는 PlayerGui.NewGui.HUD 에 있다(최상위 아님) → 재귀 검색
    local banner = player.PlayerGui:FindFirstChild("PromoBanner", true)
    if banner then
        banner:GetPropertyChangedSignal("Position"):Connect(anchorToBanner)
        banner:GetPropertyChangedSignal("Size"):Connect(anchorToBanner)
    end
end)

-- 라운드 중 숨김.
--   예전엔 PromoBanner.Visible 을 따라갔다. 그런데 PromoBanner 는 HUD(ResetOnSpawn=true)
--   안에 있어 리스폰마다 새 객체로 교체되는데, 이 스크립트는 ResetOnSpawn=false 라 살아남아
--   파괴된 옛 배너를 계속 붙잡고 있었다 → 첫 리스폰 이후 연동이 끊겨 라운드 중에도 표시됨.
--   남의 UI 상태에 의존하지 말고 ReplicatedStorage.RoundPhase 를 직접 읽는다
--   (HudButtonClient 와 동일 규약).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function syncRoundVisibility()
	if not root then return end
	local phase = ReplicatedStorage:GetAttribute("RoundPhase")
	local inRound = (phase == "stage1" or phase == "stage2")
	root.Visible = not inRound
end

ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(syncRoundVisibility)
syncRoundVisibility()

print("✅ FriendBonusHudClient 활성화")
