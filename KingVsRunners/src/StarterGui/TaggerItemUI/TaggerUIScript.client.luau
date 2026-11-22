-- 태거 UI 시스템 (로드아웃 기반 + 쿨타임 피드백)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera
local gui = script.Parent

local itemList = gui:WaitForChild("ItemList")
local itemContainer = itemList.Container

-- 모바일 노치/펀치홀 자동 회피
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)

-- ── 모바일 대응 UIScale ────────────────────────────────────────
-- 기준 해상도 1280×720. 화면이 더 작으면 비례 축소, 더 크면 1.0 캡.
-- 최소 0.55 로 보호 (작은 모바일에서 UI 너무 작아지는 거 방지).
local uiScale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", gui)
local BASE_W, BASE_H = 1280, 720
local function updateUIScale()
	local vp = camera.ViewportSize
	local s = math.min((vp.X * 0.85) / BASE_W, (vp.Y * 0.85) / BASE_H, 1)
	uiScale.Scale = math.max(s, 0.55)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale)
updateUIScale()

local spawnEvent = ReplicatedStorage:WaitForChild("SpawnItemEvent")
local cooldownEvent = ReplicatedStorage:WaitForChild("CooldownFeedback")
local spawnWarningEvent = ReplicatedStorage:WaitForChild("SpawnWarning")
local getLoadout = ReplicatedStorage:WaitForChild("GetPlayerLoadout")

-- [TAGGER-TUTORIAL] 선언은 여기(최상단)에 둔다.
--   ⚠️ 아이템 선택 핸들러(약 460행)가 tutLabel 을 참조하는데,
--      updateTaggerUI 근처(약 819행)에 선언하면 그보다 앞이라 nil 이 된다.
local TUT_ROUNDS   = 3
local TUT_DURATION = 7
local tutShownThisRound = false
local tutLabel, tutStroke = nil, nil

-- ⏱️ 아이템별 쿨다운 표시
-- [왜] 지금은 버튼을 눌러야 남은 쿨이 보인다. 리스트에서 바로 보이면
--   태거가 '무엇을 쓸 수 있는지' 한눈에 판단할 수 있다.
--
-- ⚠️ [2026-08-26] 여기 있던 ITEM_CD 복제 테이블을 삭제했다.
--   [왜] 어디서도 참조되지 않는 죽은 테이블인데 값까지 서버와 어긋나 있었다
--   (Frost Dragon 45 vs 실제 8, tsunami 30 vs 6, BlackHole 20 vs 7, bear_trap 5 vs 3).
--   실제 표시는 서버가 ItemCooldownStart 로 보내주는 값(아래 itemCdUntil)을 쓴다.
--   → 서버 ITEM_COOLDOWN 을 고쳐도 여기는 손댈 필요 없다. 복제본을 다시 만들지 말 것.
--   DEFAULT_CD / GLOBAL_CD 는 이벤트 인자가 nil 일 때의 폴백이라 남긴다.
local DEFAULT_CD = 3
local GLOBAL_CD  = 2

-- 🪤 [2026-08-26] 전역 쿨 면제 아이템 (서버 ItemSpawnHandler.GLOBAL_CD_EXEMPT 와 한 짝).
--   [왜] 표시는 max(개별 쿨, 전역 쿨)로 계산한다. 면제 아이템을 여기서 빼지 않으면
--   서버는 1.0 에 허용하는데 화면은 2.0 동안 잠긴 것처럼 보인다(= UI 가 거짓말).
--   ⚠️ 서버 표에 항목을 추가하면 여기도 같이 추가할 것. 안 그러면 다시 어긋난다.
local GLOBAL_CD_EXEMPT = {
    ["bear_trap"] = true,
    ["Spear"] = true,       -- 🗡️ [2026-09-19] 서버 ItemSpawnHandler.GLOBAL_CD_EXEMPT 와 한 짝
}

-- 🔒 [2026-08-27] 상태 잠금(단일 존재 아이템). 값 수신은 아래 ItemLockState 핸들러.
--   ⚠️ 선언이 여기 있는 이유: 쿨 표시 갱신 루프가 이 파일 중반에 있고, 그 클로저가
--     업밸류를 '생성 시점'에 잡는다. 핸들러 옆(파일 끝)에 선언하면 루프가 nil 을 본다.
local itemLocked = {}      -- itemName -> true
local itemLockLabel = {}   -- itemName -> "IN USE" 등

-- itemName -> 쿨 종료 시각(os.clock)
local itemCdUntil = {}
local globalCdUntil = 0

local selectedItem = nil
local isHoldingItem = false
local blueprintModel = nil

-- 쿨다운 경고 UI
local cooldownLabel = Instance.new("TextLabel")
cooldownLabel.Name = "CooldownWarning"
cooldownLabel.Size = UDim2.new(0, 300, 0, 50)
cooldownLabel.Position = UDim2.new(0.5, -150, 0.75, 0)
cooldownLabel.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
cooldownLabel.BackgroundTransparency = 0.3
cooldownLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
cooldownLabel.TextSize = 20
cooldownLabel.Font = Enum.Font.GothamBold
cooldownLabel.Text = ""
cooldownLabel.Visible = false
cooldownLabel.ZIndex = 10
cooldownLabel.Parent = gui
local cooldownCorner = Instance.new("UICorner")
cooldownCorner.CornerRadius = UDim.new(0, 10)
cooldownCorner.Parent = cooldownLabel

-- 사용법 안내 UI (특정 아이템 선택 시 표시)
local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "ItemHint"
hintLabel.Size = UDim2.new(0, 400, 0, 70)
hintLabel.Position = UDim2.new(0.5, -200, 0.62, 0)
hintLabel.BackgroundColor3 = Color3.fromRGB(40, 20, 80)
hintLabel.BackgroundTransparency = 0.2
hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hintLabel.TextSize = 16
hintLabel.Font = Enum.Font.GothamBold
hintLabel.Text = ""
hintLabel.Visible = false
hintLabel.ZIndex = 10
hintLabel.TextWrapped = true
hintLabel.Parent = gui
local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 10)
hintCorner.Parent = hintLabel
local hintStroke = Instance.new("UIStroke")
hintStroke.Color = Color3.fromRGB(150, 50, 255)
hintStroke.Thickness = 2
hintStroke.Parent = hintLabel

-- 아이템별 사용법 텍스트 (없으면 알림 표시 안 함)
local ITEM_HINTS = {
	["BlackHole"] = [[BLACK HOLE
Click the ground to throw (up to 600 studs)
Pulls nearby runners for 6s - instant kill at the center]],
	["EnergyBall"] = [[ENERGY BALL (Railgun)
Click the ground to fire in that direction
Red + Blue merge into Purple - kills every runner in a straight line (1.5s charge)]],
	["Spear"] = [[SPEAR
Click the ground or a runner to throw
Pierces and kills runners in its path - unlimited use]],
	["Demonspear"] = [[DEMON SPEAR
Click the ground or a runner to throw
Leaves a burning trail - kills runners in a wide area (area denial)]],
}

local hintToken = 0
local function showHint(itemName)
	local text = ITEM_HINTS[itemName]
	if not text then
		hintLabel.Visible = false
		return
	end
	hintLabel.Text = text
	hintLabel.Visible = true
	hintToken = hintToken + 1
	local myToken = hintToken
	task.delay(6, function()
		if myToken == hintToken then
			hintLabel.Visible = false
		end
	end)
end
local function hideHint()
	hintToken = hintToken + 1
	hintLabel.Visible = false
end

-- 소환 경고 UI (배럴 겹침 등)
local spawnWarningLabel = Instance.new("TextLabel")
spawnWarningLabel.Name = "SpawnWarning"
spawnWarningLabel.Size = UDim2.new(0, 380, 0, 55)
spawnWarningLabel.Position = UDim2.new(0.5, -190, 0.65, 0)
spawnWarningLabel.BackgroundColor3 = Color3.fromRGB(220, 120, 0)
spawnWarningLabel.BackgroundTransparency = 0.2
spawnWarningLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
spawnWarningLabel.TextSize = 18
spawnWarningLabel.Font = Enum.Font.GothamBold
spawnWarningLabel.Text = ""
spawnWarningLabel.Visible = false
spawnWarningLabel.ZIndex = 11
spawnWarningLabel.Parent = gui
local spawnWarningCorner = Instance.new("UICorner")
spawnWarningCorner.CornerRadius = UDim.new(0, 10)
spawnWarningCorner.Parent = spawnWarningLabel

local warningTween = nil
local function showSpawnWarning(msg)
    if warningTween then warningTween:Cancel() end
    spawnWarningLabel.Text = "⚠️ " .. msg
    spawnWarningLabel.Visible = true
    spawnWarningLabel.BackgroundTransparency = 0.2
    spawnWarningLabel.TextTransparency = 0
    -- 2초 후 자동으로 사라짐
    task.delay(2, function()
        spawnWarningLabel.Visible = false
    end)
end

-- 서버에서 경고 수신
spawnWarningEvent.OnClientEvent:Connect(function(msg)
    showSpawnWarning(msg)
end)

-- 청사진 로컬 빌드 (ReplicatedStorage.TaggerItemPreviews 에서 clone)
-- 이전: GetItemPreview 서버 요청 → 서버가 workspace에 청사진 생성 → MeshPart 복제 지연으로 클라 WaitForChild 타임아웃.
-- 현재: 클라가 로컬에서 직접 clone + 반투명 처리 → 즉시. (태거 본인만 봄 = info leak도 없음)
local function clearLocalBlueprint()
    if blueprintModel then
        blueprintModel:Destroy()
        blueprintModel = nil
    end
    -- Spear 투척 경로 가이드도 함께 정리 (청사진이 사라지면 가이드도 의미 없음)
    local g = workspace:FindFirstChild("_SpearPathGuide")
    if g then g:Destroy() end
    -- 🕳️ BlackHole 흡인 범위 링도 동일 (발사/ESC/역할변경 후 잔상 방지)
    local r = workspace:FindFirstChild("_BlackHoleAimRing")
    if r then r:Destroy() end
    -- 🚫 금지 거리 문턱선도 동일. 아이템을 놓거나 역할이 바뀌면 조준이 끝난 것이므로
    --    표시가 남아 있으면 안 된다. (여기선 함수가 아직 선언 전이라 직접 제거한다)
    local mr = workspace:FindFirstChild("_MinSpawnBoundary")
    if mr then mr:Destroy() end
end

local function makeBlueprintTransparent(obj)
    if obj:IsA("BasePart") then
        obj.Transparency = 0.5
        obj.CanCollide = false
        obj.Anchored = true
        -- ⚠️ 청사진은 어떤 레이캐스트도 막으면 안 된다.
        --    실제 사고: 폭격 조준 모드의 레이가 청사진(Blueprint_local)에 맞아
        --    "🎯 폭격 타겟 확정: hit Blueprint_local" → 엉뚱한 좌표로 폭격됐다.
        obj.CanQuery = false
        obj.Material = Enum.Material.ForceField
        obj.Color = Color3.fromRGB(100, 200, 255)
        if obj:IsA("MeshPart") then obj.TextureID = "" end
    end
end

local function requestBlueprint(itemName)
    clearLocalBlueprint()
    -- 💣 폭격 조준 모드 중에는 청사진을 만들지 않는다.
    --    tnt 발사 2.1초 뒤 자동 재장전이 돌면서 탑뷰 화면에 tnt 청사진이 떠 있었고,
    --    조준 레이가 그걸 맞아 착탄점이 어긋났다. (BombTargetingClient가 이 플래그를 켠다)
    if _G.BombTargeting then return end
    local previews = ReplicatedStorage:FindFirstChild("TaggerItemPreviews")
    local template = previews and previews:FindFirstChild(itemName)
    if not template then
        warn("[bp local] 템플릿 없음:", itemName, "(previews=", previews ~= nil, ")")
        return
    end
    local bp = template:Clone()
    bp.Name = "Blueprint_local"
    if bp:IsA("Model") then
        for _, d in ipairs(bp:GetDescendants()) do
            if d:IsA("Script") or d:IsA("LocalScript") then
                d:Destroy()
            else
                makeBlueprintTransparent(d)
            end
        end
    else
        makeBlueprintTransparent(bp)
    end
    bp.Parent = workspace
    -- 배럴 청사진: 스폰 시 X90 눕히므로 청사진도 같은 방향으로 (안 그러면 세로로 보임)
    if itemName == "Wooden Barrel" and bp:IsA("Model") and bp.PrimaryPart then
        bp:PivotTo(bp:GetPivot() * CFrame.Angles(0, math.rad(90), 0))
    end
    -- 🕳️ BlackHole: 서버 activateBlackHole 과 동일하게 Event Horizon 을 PrimaryPart 로.
    -- 원본 템플릿은 PrimaryPart=nil 이라 pivot 이 bbox 중심(Event Horizon보다 0.8스터드 위)이 되는데,
    -- 그 상태로 리프트하면 실제 착탄보다 그만큼 높게 표시된다.
    if itemName == "BlackHole" and bp:IsA("Model") then
        local horizon = bp:FindFirstChild("Event Horizon")
        if horizon and horizon:IsA("BasePart") then
            bp.PrimaryPart = horizon
        end
    end
    blueprintModel = bp
end

-- 아이템 버튼 생성
-- KING ITEMS thumbnail camera tuning (only 3D-viewport items = icon-less ones).
-- Edit THUMB_CAM below and hit F5 (re-enter a round to see). No Explorer attributes / Ctrl+S.
--   distMul: zoom (smaller = closer)   dir: camera direction   off: framing pan (x item size)
local THUMB_DEFAULT = { distMul = 1.4, dir = Vector3.new(0.7, 0.5, 0.7), off = Vector3.new(0, 0, 0) }
local THUMB_CAM = {
    -- ["Spear"]      = { distMul = 1.1, dir = Vector3.new(0.3, 0.4, 1),   off = Vector3.new(0, 0, 0) },
    -- ["Demonspear"] = { distMul = 1.3, dir = Vector3.new(0.7, 0.5, 0.7), off = Vector3.new(0, 0.1, 0) },
    -- add per-item overrides here, e.g. ["Wooden Barrel"] = { distMul = 1.6, dir = Vector3.new(0.7,0.5,0.7), off = Vector3.new(0,0,0) },
}

-- Live thumbnail tuner (Studio only). In a round as tagger, press K to toggle, then:
--   [ ] cycle item · = / - zoom · J/L yaw · I/O pitch · arrows pan · Enter=print line · K=exit
-- Updates live (no F5). Enter prints a ready-to-paste THUMB_CAM entry to the console.
local _tunables   = {}   -- [name] = { cam, cf, size }
local _liveParams = {}   -- [name] = { distMul, dir, off }

local function applyThumbCam(cam, cf, size, p)
    local md  = math.max(size.X, size.Y, size.Z, 0.1)
    local tgt = cf.Position + p.off * md
    cam.CFrame = CFrame.new(tgt + p.dir * (md * p.distMul), tgt)
end

local function registerThumb(name, cam, cf, size)
    if not _liveParams[name] then
        local base = THUMB_CAM[name] or THUMB_DEFAULT
        _liveParams[name] = {
            distMul = base.distMul or THUMB_DEFAULT.distMul,
            dir     = base.dir or THUMB_DEFAULT.dir,
            off     = base.off or THUMB_DEFAULT.off,
        }
    end
    _tunables[name] = { cam = cam, cf = cf, size = size }
    applyThumbCam(cam, cf, size, _liveParams[name])
end

if game:GetService("RunService"):IsStudio() then
    local UIS = game:GetService("UserInputService")
    local on, idx, order, hud = false, 1, {}, nil
    local function rebuild()
        order = {}
        for n in pairs(_tunables) do order[#order + 1] = n end
        table.sort(order)
    end
    local function ensureHud()
        if hud then return end
        local sg = Instance.new("ScreenGui")
        sg.Name = "KingThumbTuner"; sg.ResetOnSpawn = false; sg.DisplayOrder = 999
        sg.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        hud = Instance.new("TextLabel")
        hud.Size = UDim2.new(0, 560, 0, 56); hud.Position = UDim2.new(0.5, -280, 0, 8)
        hud.BackgroundColor3 = Color3.fromRGB(0, 0, 0); hud.BackgroundTransparency = 0.2
        hud.TextColor3 = Color3.fromRGB(120, 255, 180); hud.Font = Enum.Font.Code
        hud.TextSize = 14; hud.TextXAlignment = Enum.TextXAlignment.Left; hud.Parent = sg
    end
    local function refresh()
        if not hud then return end
        local n = order[idx]
        if not n then hud.Text = "K-TUNE: no 3D-viewport items in the list"; return end
        local p = _liveParams[n]
        hud.Text = string.format("[%s]  dist=%.2f  dir=(%.2f,%.2f,%.2f)  off=(%.2f,%.2f,%.2f)", n, p.distMul, p.dir.X, p.dir.Y, p.dir.Z, p.off.X, p.off.Y, p.off.Z) .. string.char(10) .. "[ ]item  =/- zoom  J/L yaw  U/M pitch  2468/arrows pan  Enter=print  K=exit"
    end
    local function reapply()
        local n = order[idx]; local t = n and _tunables[n]
        if t then applyThumbCam(t.cam, t.cf, t.size, _liveParams[n]) end
        refresh()
    end
    UIS.InputBegan:Connect(function(inp, gp)
        if gp then return end
        local kc = inp.KeyCode
        if kc == Enum.KeyCode.K then
            on = not on
            if on then ensureHud(); rebuild(); idx = 1 end
            if hud then hud.Visible = on end
            refresh()
            return
        end
        if not on then return end
        if #order == 0 then rebuild() end
        local n = order[idx]; if not n then return end
        local p = _liveParams[n]
        if kc == Enum.KeyCode.LeftBracket then idx = (idx - 2) % #order + 1
        elseif kc == Enum.KeyCode.RightBracket then idx = idx % #order + 1
        elseif kc == Enum.KeyCode.Equals then p.distMul = math.max(0.2, p.distMul - 0.1)
        elseif kc == Enum.KeyCode.Minus then p.distMul = p.distMul + 0.1
        elseif kc == Enum.KeyCode.J then p.dir = CFrame.Angles(0, math.rad(-15), 0) * p.dir
        elseif kc == Enum.KeyCode.L then p.dir = CFrame.Angles(0, math.rad(15), 0) * p.dir
        elseif kc == Enum.KeyCode.U or kc == Enum.KeyCode.M then
            local horiz = Vector3.new(p.dir.Z, 0, -p.dir.X)
            if horiz.Magnitude > 0.001 then
                p.dir = CFrame.fromAxisAngle(horiz.Unit, math.rad((kc == Enum.KeyCode.U) and 15 or -15)) * p.dir
            end
        elseif kc == Enum.KeyCode.KeypadEight or kc == Enum.KeyCode.Up then p.off = p.off + Vector3.new(0, 0.05, 0)
        elseif kc == Enum.KeyCode.KeypadTwo or kc == Enum.KeyCode.Down then p.off = p.off - Vector3.new(0, 0.05, 0)
        elseif kc == Enum.KeyCode.KeypadFour or kc == Enum.KeyCode.Left then p.off = p.off - Vector3.new(0.05, 0, 0)
        elseif kc == Enum.KeyCode.KeypadSix or kc == Enum.KeyCode.Right then p.off = p.off + Vector3.new(0.05, 0, 0)
        elseif kc == Enum.KeyCode.Return then
            print(string.format(
                '    ["%s"] = { distMul = %.2f, dir = Vector3.new(%.3f, %.3f, %.3f), off = Vector3.new(%.3f, %.3f, %.3f) },',
                n, p.distMul, p.dir.X, p.dir.Y, p.dir.Z, p.off.X, p.off.Y, p.off.Z))
            return
        else return end
        reapply()
    end)
end

local function createItemButton(itemData)
    local button = Instance.new("TextButton")
    button.Name = itemData.name
    button.Size = UDim2.new(1, -10, 0, 48)
    button.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    button.BorderSizePixel = 0
    button.Text = ""
    button.Parent = itemContainer

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button

    -- ⏱️ 쿨 오버레이 (버튼 위를 덮는 반투명 막 + 남은 초)
    local cdOverlay = Instance.new("Frame")
    cdOverlay.Name = "CdOverlay"
    cdOverlay.Size = UDim2.fromScale(1, 1)
    cdOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    cdOverlay.BackgroundTransparency = 0.45
    cdOverlay.BorderSizePixel = 0
    cdOverlay.Visible = false
    cdOverlay.ZIndex = 20
    cdOverlay.Parent = button
    local ovc = Instance.new("UICorner")
    ovc.CornerRadius = UDim.new(0, 8)
    ovc.Parent = cdOverlay

    local cdText = Instance.new("TextLabel")
    cdText.Name = "CdText"
    cdText.Size = UDim2.fromScale(1, 1)
    cdText.BackgroundTransparency = 1
    cdText.Font = Enum.Font.GothamBold
    cdText.TextScaled = true
    cdText.TextColor3 = Color3.fromRGB(255, 235, 150)
    cdText.TextStrokeTransparency = 0.4
    cdText.Text = ""
    cdText.ZIndex = 21
    cdText.Parent = cdOverlay
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 10)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.Parent = cdText

    -- 🪤 설치 개수 배지 (bear_trap 전용)
    -- [왜] 쿨은 CdOverlay 로 보이는데 "몇 개 깔았는지"는 서버 로그에만 있었다.
    --   상한 5개에 걸리면 아무 일도 안 일어나서 유저가 이유를 몰랐다.
    --   (2026-08-26 실측: 한 판에서 5/5 거부 1회 + 쿨 거부 3회)
    -- ⚠️ ZIndex 는 CdOverlay(20)/CdText(21) 보다 위(22)여야 한다.
    --   쿨 중에도 개수는 계속 보여야 "지금 못 쓰는 이유"가 구분된다.
    -- ⚠️ 이름 CountBadge 는 아래 갱신 루프(파일 끝)와 한 짝이다. 바꾸면 같이 바꿀 것.
    if itemData.name == "bear_trap" then
        local badge = Instance.new("TextLabel")
        badge.Name = "CountBadge"
        badge.AnchorPoint = Vector2.new(1, 0)
        badge.Position = UDim2.new(1, -6, 0, 4)
        badge.Size = UDim2.new(0, 40, 0, 18)
        badge.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        badge.BackgroundTransparency = 0.15
        badge.BorderSizePixel = 0
        badge.Font = Enum.Font.GothamBold
        badge.TextSize = 13
        badge.TextColor3 = Color3.fromRGB(255, 235, 150)
        badge.TextStrokeTransparency = 0.5
        badge.Text = "0/5"
        badge.ZIndex = 22
        badge.Parent = button
        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 6)
        bc.Parent = badge
    end

    -- 아이콘: 이미지 ID가 있으면 ImageLabel, 없으면 ViewportFrame으로 3D 모델 프리뷰
    local hasImageIcon = itemData.icon and itemData.icon ~= "" and string.find(itemData.icon, "rbxassetid://")

    if hasImageIcon then
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Size = UDim2.new(0, 52, 0, 52)
        icon.Position = UDim2.new(0, 10, 0.5, -26)
        icon.BackgroundTransparency = 1
        icon.Image = itemData.icon
        icon.ScaleType = Enum.ScaleType.Fit
        icon.Parent = button
    else
        -- 태거 아이템은 TaggerItemPreviews 우선, 없으면 RunnerItemPreviews 폴백
        local RS_ = game:GetService("ReplicatedStorage")
        local tp = RS_:FindFirstChild("TaggerItemPreviews")
        local modelSrc = tp and tp:FindFirstChild(itemData.name)
        if not modelSrc then
            local previewFolder = RS_:FindFirstChild("RunnerItemPreviews")
            modelSrc = previewFolder and previewFolder:FindFirstChild(itemData.name)
        end
        if modelSrc then
            local vp = Instance.new("ViewportFrame")
            vp.Name = "Icon"
            vp.Size = UDim2.new(0, 52, 0, 52)
            vp.Position = UDim2.new(0, 10, 0.5, -26)
            vp.BackgroundTransparency = 1
            vp.LightColor = Color3.fromRGB(255, 240, 220)
            vp.LightDirection = Vector3.new(-1, -2, -1)
            vp.Ambient = Color3.fromRGB(120, 120, 140)
            vp.Parent = button

            local modelClone = modelSrc:Clone()
            modelClone.Parent = vp
            for _, p in ipairs(modelClone:GetDescendants()) do
                if p:IsA("BasePart") then
                    p.Anchored = true
                    p.CastShadow = false
                end
            end

            local vpCam = Instance.new("Camera")
            vpCam.FieldOfView = 50
            vp.CurrentCamera = vpCam
            vpCam.Parent = vp
            local cf, size
            if modelClone:IsA("Model") then
                cf, size = modelClone:GetBoundingBox()
            else
                cf, size = modelClone.CFrame, modelClone.Size   -- single MeshPart/BasePart
            end
            -- Per-item thumbnail camera (THUMB_CAM default + live K-key tuner in Studio).
            registerThumb(itemData.name, vpCam, cf, size)
        else
            -- 폴백: placeholder 이미지
            local icon = Instance.new("ImageLabel")
            icon.Name = "Icon"
            icon.Size = UDim2.new(0, 52, 0, 52)
            icon.Position = UDim2.new(0, 10, 0.5, -26)
            icon.BackgroundTransparency = 1
            icon.Image = "rbxassetid://7734053426"
            icon.ScaleType = Enum.ScaleType.Fit
            icon.Parent = button
        end
    end

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, -72, 1, 0)
    nameLabel.Position = UDim2.new(0, 72, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextSize = 16
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Text = itemData.name
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Parent = button

    -- ItemNoob 잠금 표시 (nameLabel 생성 후에 처리)
    if itemData.name == "ItemNoob" then
        local hasReward = player:GetAttribute("HasItemNoob")
        if not hasReward then
            button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            nameLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
            nameLabel.Text = "🔒 " .. itemData.name
        end
    end

    button.MouseButton1Click:Connect(function()
        -- 같은 아이템을 다시 누르면 선택 해제(토글).
        -- 조준을 취소하려면 ESC 를 눌러야만 했는데, 아이템 버튼이 바로 눈앞에 있으니
        -- 같은 버튼을 다시 누르는 게 더 자연스럽다.
        if selectedItem == itemData.name then
            local clearEvent = ReplicatedStorage:FindFirstChild("ClearBlueprint")
            if clearEvent then clearEvent:FireServer() end
            clearLocalBlueprint()
            selectedItem = nil
            isHoldingItem = false
            cooldownLabel.Visible = false
            hideHint()
            for _, btn in ipairs(itemContainer:GetChildren()) do
                if btn:IsA("TextButton") then
                    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
                end
            end
            return
        end

        selectedItem = itemData.name
        isHoldingItem = true
        requestBlueprint(itemData.name)
        showHint(itemData.name)
        -- [TAGGER-TUTORIAL] 골랐으면 1단계는 끝. 아이템별 상세는 showHint 가 이어받는다.
        if tutLabel then tutLabel.Visible = false end

        for _, btn in ipairs(itemContainer:GetChildren()) do
            if btn:IsA("TextButton") then
                btn.BackgroundColor3 = (btn == button) and Color3.fromRGB(100, 150, 200) or Color3.fromRGB(50, 50, 50)
            end
        end
    end)

    return button
end

-- 로드아웃 기반 버튼 생성
local function loadTaggerItems()
    -- 기존 버튼 정리
    for _, child in ipairs(itemContainer:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    
    local data = getLoadout:InvokeServer()
    if not data then return end
    
    local loadout = data.loadout or {"stone", "Wood Log", "Wooden Barrel"}
    local allItems = data.allItems or {}
    
    -- 로드아웃에 있는 아이템만 버튼 생성
    for _, itemName in ipairs(loadout) do
        local icon = "rbxassetid://7734053426"
        for _, itemInfo in ipairs(allItems) do
            if itemInfo.name == itemName then
                icon = itemInfo.icon
                break
            end
        end
        createItemButton({name = itemName, icon = icon})
    end
    
    print("✅ 태거 아이템 로드:", table.concat(loadout, ", "))
end

-- 청사진 위치 업데이트
-- taggerbase 파트 조준 → 같은 맵 ItemSpawnPlate로 X/Z clamp 투영(성엔 안 떨어짐, 밸런스 안전). 실패 시 nil.
-- 바리케이드도 투영 대상으로 취급한다: 벽이 태거 시야를 대부분 채우기 때문에
-- 벽을 클릭했을 때도 taggerbase 를 클릭한 것과 동일하게 계단 앞으로 좌표 보정되어야 한다.
-- ⚠️ [2026-08-25] 투영 가능 대상을 넓힌다.
--   [문제] 예전엔 taggerbase / Barricades 만 투영했다. 바리케이드가
--     조준을 막던 시절엔 그게 곧 '벽 뒤를 클릭한 것'이라 성립했다.
--     그런데 바리케이드를 조준에서 제외하면서, 클릭이 벽을 통과해
--     언덕에 맞게 됐다. 그러면 isProjectionSource 가 false 라
--     투영이 실패하고 굴리기류(stone/Wood Log 등)가 아예 안 나갔다.
--   [해결] 맵 안의 지형이면 어디를 클릭하든 계단으로 투영한다.
--     굴리기류는 '어디를 찍든 계단에서 굴러 내려온다'가 원래 규칙이다.
local function isProjectionSource(inst)
    local n = inst.Name:lower()
    if n:find("taggerbase") then return true end
    local p = inst.Parent
    if p ~= nil and p.Name == "Barricades" then return true end
    -- 🗺️ 맵 폴더 안의 BasePart 면 투영 대상으로 본다.
    --    (언덕·계단·성벽 어디든 → 계단으로 투영)
    -- ⚠️ MAP_NAMES 는 이 함수보다 아래에 선언돼 있어 쓸 수 없다.
    --    이름 패턴으로 직접 거슬러 올라간다.
    local cur = inst
    while cur and cur ~= workspace do
        if cur.Parent == workspace and cur.Name:lower():find("map") then
            return true
        end
        cur = cur.Parent
    end
    return false
end

local function projectOntoPlate(hitInstance, hitPos)
    if not isProjectionSource(hitInstance) then
        -- 진단: 무엇에 맞았는지 확인 (레이가 taggerbase 위의 다른 파트를 먼저 잡는지 추적)
        -- 출시 전 제거: 매 프레임 찍혀 콘솔을 도배함
        -- print(string.format("[project-miss] hit=%s parent=%s (taggerbase 아님)",
        --     hitInstance.Name, tostring(hitInstance.Parent and hitInstance.Parent.Name)))
        return nil
    end
    local mapFolder = hitInstance:FindFirstAncestor("map1") or hitInstance:FindFirstAncestor("map2")
    if not mapFolder then
        -- print("[project-miss] mapFolder 없음: "..hitInstance:GetFullName())
        return nil
    end
    local plate
    for _, d in ipairs(mapFolder:GetDescendants()) do
        if d:IsA("BasePart") and (d.Name == "ItemSpawnPlate" or d.Name:lower():find("spawnplate")) then plate = d break end
    end
    if not plate then
        -- print("[project-miss] plate 없음 in "..mapFolder.Name)
        return nil
    end
    -- ⚠️ 플레이트가 회전돼 있을 수 있으므로 로컬 좌표계에서 clamp 한다.
    --    월드 X/Z 로 clamp 하면 회전된 플레이트에서는 결과가 실제 판 안쪽이 아니게 되고
    --    (실측: 월드 clamp 결과가 로컬 X 11.86 → 한계 11.11 을 0.76 초과),
    --    서버의 isOnTaggerBase(로컬 좌표 기준 판정)에서 "플레이트 밖"으로 걸러져 스폰이 막힌다.
    local half = plate.Size / 2
    local lp = plate.CFrame:PointToObjectSpace(hitPos)
    local INSET = 0.5   -- 경계 정확히 붙이지 않고 살짝 안쪽으로 (부동소수점 여유)
    local cx = math.clamp(lp.X, -half.X + INSET, half.X - INSET)
    local cz = math.clamp(lp.Z, -half.Z + INSET, half.Z - INSET)
    local world = plate.CFrame:PointToWorldSpace(Vector3.new(cx, 0, cz))
    return Vector3.new(world.X, plate.Position.Y + half.Y, world.Z), plate
end

-- 🕳️ BlackHole 조준 표시 상수
-- ⚠️ 아래 3개는 ServerScriptService.BlackHoleSystem 값과 반드시 일치해야 함.
--    (불일치 시 청사진이 실제 착탄 위치/흡인 범위를 거짓말하게 됨)
local BH_LIFT_HEIGHT  = 8    -- = BlackHoleSystem.LIFT_HEIGHT (지면에서 띄우는 높이)
local BH_PULL_RADIUS  = 70   -- = BlackHoleSystem.PULL_RADIUS (흡인 시작 반경)
local BH_RING_COLOR   = Color3.fromRGB(80, 20, 120)  -- 서버 BlackHolePullZone과 동일 보라
local BH_RING_TRANSP  = 0.82 -- 존(0.6)보다 옅게 — 조준 중 상시 표시라 시야 방해 최소화

-- 표면 정렬 (BlackHoleSystem.alignToSurface 와 동일 공식 — 결과 일치 보장)
local function alignToSurface(position, normal)
    local right = normal:Cross(Vector3.new(0, 1, 0))
    if right.Magnitude < 0.001 then
        right = normal:Cross(Vector3.new(1, 0, 0))
    end
    right = right.Unit
    local forward = right:Cross(normal).Unit
    return CFrame.fromMatrix(position, right, normal, -forward)
end

-- Cylinder primitive 정렬용: local +X 축이 normal 방향 (BlackHoleSystem.cframeForCylinder 와 동일)
local function cframeForCylinder(centerPos, normal)
    local up = normal.Unit
    local arbitrary = math.abs(up.Y) < 0.99 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
    local right = up:Cross(arbitrary).Unit
    local fwd = up:Cross(right).Unit
    return CFrame.fromMatrix(centerPos, up, right, fwd)
end

-- 흡인 범위 링 (클라 로컬 = 태거 본인만 봄)
local function clearBlackHoleRing()
    local r = workspace:FindFirstChild("_BlackHoleAimRing")
    if r then r:Destroy() end
end

local function updateBlackHoleRing(groundPos, normal)
    local ring = workspace:FindFirstChild("_BlackHoleAimRing")
    if not ring then
        ring = Instance.new("Part")
        ring.Name = "_BlackHoleAimRing"
        ring.Shape = Enum.PartType.Cylinder
        ring.Material = Enum.Material.Neon
        ring.Color = BH_RING_COLOR
        ring.Transparency = BH_RING_TRANSP
        ring.Anchored = true
        ring.CanCollide = false
        ring.CanQuery = false   -- 조준 레이캐스트에 절대 안 잡히게 (자기 자신 히트 방지)
        ring.CastShadow = false
        ring.Size = Vector3.new(0.5, BH_PULL_RADIUS * 2, BH_PULL_RADIUS * 2)
        ring.Parent = workspace
    end
    ring.CFrame = cframeForCylinder(groundPos + normal * 0.15, normal)
end

-- ═══════════════════════════════════════════════════════════════
-- 🚫 [MIN-SPAWN-DIST] 자기 근처 소환 금지 거리의 시각화
--
-- [문제] 서버는 "태거 ↔ 소환지점 거리 < MIN_SPAWN_DIST" 를 거부하는데(캠핑 방지),
--        피드백이 클릭 실패 후 경고문 하나뿐이었다. 클릭 전에는 그 거리가 어느
--        정도인지 볼 방법이 전혀 없어 감에 의존하게 되고, 신규 태거는
--        "아까는 소환되더니 왜 지금은 안 되지"를 겪는다. 이유를 들어도 납득이 어렵다.
--
-- [해법] 위반 중일 때'만' 신호를 준다:
--          · 청사진이 빨개진다      → 여기 놓으면 실패한다
--          · 발밑에 금지 반경 링    → 이만큼 물러나야 한다
--        정상 거리에서는 아무것도 뜨지 않으므로 시야를 어지럽히지 않는다.
--        텍스트가 없어 저연령·해외 유저에게도 그대로 통한다.
--        (같은 계열의 선례: BlackHole 흡인 반경 링 — 판정 범위는 보여줘야 한다)
--
-- ⚠️ 반경을 여기 하드코딩하면 안 된다. 서버 값만 바뀌면 "빨간데 소환되네" 또는
--    "안 빨간데 거부되네" 가 되어 지금보다 더 나쁜 거짓말이 된다.
--    → 서버가 ReplicatedStorage 속성으로 띄운 값을 읽고, 없을 때만 폴백한다.
-- ═══════════════════════════════════════════════════════════════
local MSD_FALLBACK    = 20   -- 속성을 못 읽었을 때만 쓰는 값 (서버 기본값과 동일)
local MSD_MARK_COLOR  = Color3.fromRGB(255, 70, 70)
local MSD_MARK_TRANSP = 0.5
local MSD_MARK_WIDTH  = 16   -- 조준 방향에 '수직'인 폭 (문턱선의 길이)
local MSD_MARK_HEIGHT = 5    -- 높이. 경사 지면에서 묻히지 않을 만큼만
local MSD_MARK_THICK  = 0.4  -- 두께(진행 방향)
local BP_OK_COLOR     = Color3.fromRGB(100, 200, 255)  -- = makeBlueprintTransparent 의 기본색
local BP_BLOCK_COLOR  = Color3.fromRGB(255, 65, 65)

local function getMinSpawnDist()
    return ReplicatedStorage:GetAttribute("MinSpawnDist") or MSD_FALLBACK
end

local function clearMinDistMark()
    local m = workspace:FindFirstChild("_MinSpawnBoundary")
    if m then m:Destroy() end
end

-- 조준선 위 '문턱선'. 태거에서 조준 방향으로 정확히 radius 만큼 간 지점에,
-- 그 방향과 수직으로 선다. 의미: "이 선을 넘겨서 놓아라".
--
-- ⚠️ [설계 이력] 처음엔 태거 발밑에 반경 20 원판을 깔았는데 실패했다. 세 가지 이유고,
--    앞으로 비슷한 표시를 만들 때 같은 함정을 피하려면 기억해 둘 것:
--      1. Cylinder 는 속이 꽉 찬 원판이라 '경계'가 아니라 붉은 얼룩으로 보인다.
--      2. 조준 중 카메라는 거의 수평이라 발밑 원판이 납작하게 눌려 원으로 인식되지 않는다.
--      3. 결정적 — 원은 "밖으로 나가라"를 뜻하는데, 실제 해법은 "더 멀리 조준하라"다.
--         태거는 움직일 필요가 없다. 경계를 '태거 주변'에 그린 것 자체가 틀린 은유였다.
--    → 경계는 태거 주변이 아니라 '조준선 위'에 있어야 행동과 표시가 일치한다.
local function updateMinDistMark(radius, aimPos)
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then clearMinDistMark() return end

    -- ⚠️ 수평 성분만 쓴다. Y 를 포함하면 위/아래를 조준할 때 문턱선이 공중으로 뜨거나
    --    땅에 박혀 흔들린다. 서버 판정은 3D 거리지만, 표시의 '방향'은 평면이 안정적이다.
    local flat = Vector3.new(aimPos.X - hrp.Position.X, 0, aimPos.Z - hrp.Position.Z)
    if flat.Magnitude < 0.1 then clearMinDistMark() return end
    local dir = flat.Unit

    local m = workspace:FindFirstChild("_MinSpawnBoundary")
    if not m then
        m = Instance.new("Part")
        m.Name = "_MinSpawnBoundary"
        m.Material = Enum.Material.Neon
        m.Color = MSD_MARK_COLOR
        m.Transparency = MSD_MARK_TRANSP
        m.Anchored = true
        m.CanCollide = false
        -- ⚠️ CanQuery=false 필수. 조준 레이가 이 판에 맞으면 착탄점이 판 표면으로
        --    잡혀 버린다(과거 청사진이 레이를 막아 폭격이 어긋난 사고와 같은 유형).
        m.CanQuery = false
        m.CastShadow = false
        m.Size = Vector3.new(MSD_MARK_WIDTH, MSD_MARK_HEIGHT, MSD_MARK_THICK)
        m.Parent = workspace
    end
    -- 발밑 높이에서 위로 세운다. HRP 중심은 지면보다 약 3 위.
    local center = Vector3.new(
        hrp.Position.X + dir.X * radius,
        hrp.Position.Y - 2.9 + MSD_MARK_HEIGHT / 2,
        hrp.Position.Z + dir.Z * radius)
    -- lookAt: LookVector(=Size 의 Z축, 두께 방향)가 조준 방향을 향한다 → 판이 조준선을 가로막는 자세.
    m.CFrame = CFrame.lookAt(center, center + dir)
end

-- 청사진 전체를 물들인다 (Model / 단일 BasePart 양쪽 대응).
-- ⚠️ 파트별 원본 색을 보관할 필요가 없다. makeBlueprintTransparent 가 모든 BasePart 를
--    BP_OK_COLOR 하나로 통일해 칠해두기 때문에, 복원은 그 상수로 되돌리면 정확하다.
local function tintBlueprint(model, blocked)
    if not model then return end
    local c = blocked and BP_BLOCK_COLOR or BP_OK_COLOR
    if model:IsA("BasePart") then
        model.Color = c
    else
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then d.Color = c end
        end
    end
end

-- ─── 조준 대상(include) 목록 캐시 ────────────────────────────────
-- ⚠️ 이전에는 이 목록을 RenderStepped 마다 새로 만들었다.
--    실측: map1+map2 자손 4691개 순회 → include 2767개, 1프레임 2.97ms
--    (데스크톱 기준 60fps 예산의 17.8%. 모바일은 수 배 더 나쁘고, 하필 태거가
--     조준 중 = 전투 한복판에서만 발생한다.)
--    → 맵은 workspace 상주라 매 프레임 다시 지을 이유가 없다. 캐시 + dirty 플래그로 전환.
--
-- 무효화 조건: 맵 폴더 자체의 추가/제거, 맵 안 BasePart 의 추가/제거.
-- (파트의 CollisionGroup 을 런타임에 바꾸는 코드가 생기면 이 캐시도 함께 갱신해야 함)
local MAP_NAMES        = {"map1", "map2"}
-- ⚠️ [2026-08-25] TaggerBarrier 추가.
--    TaggerWall_* 는 Transparency 1 + CanQuery true 라 보이지 않으면서
--    조준 레이를 막았다. 1단계에 태거가 언덕을 겨냥할 수 없었다.
local AIM_EXCLUDE_CG   = { Mountains = true, Walls = true, ItemBarrier = true, TaggerBarrier = true, TaggerItems = true }

-- ⚠️ [2026-08-26] 이름 기준 조준 제외.
--
-- [문제] map2 에서만 태거가 성문 너머를 조준할 수 없었다(프로스트 드래곤·에너지볼 등).
--   원인은 `map2 castle` 안에 있는 두 번째 `taggerbase2` 다:
--     · map1.taggerbase        Y  74.0  ← 태거 발밑보다 한참 아래라 조준을 안 막음
--     · map2.taggerbase2       Y  61.5  ← 마찬가지
--     · map2 castle.taggerbase2 Y 128.4  ← 태거가 선 높이(≈140) 바로 아래, X 710~796
--   셋째 것이 성문·계단을 통째로 덮는 바닥이라, 아래쪽을 겨냥하면 자기 발밑에 막힌다.
--   CollisionGroup 이 Default 라 AIM_EXCLUDE_CG 에 안 걸리고,
--   BarricadeGate 목록에도 없어 성문 구조물로도 안 잡혔다.
--
-- [왜 제외해도 되나] 태거 베이스 구역은 ItemSpawnHandler 가 이미 소환을 막는다
--   ("🚫 태거 베이스 구역 소환 금지"). 조준 대상일 이유가 애초에 없다.
-- [왜 CollisionGroup 이 아니라 이름인가] 그룹을 바꾸면 물리 충돌까지 바뀌고
--   인스턴스 변경이라 저장이 필요하다. 조준만 빼는 게 목적이므로 이름으로 건다.
-- ⚠️ 맵에서 이 파트 이름을 바꾸면 여기도 같이 고쳐야 한다.
local AIM_EXCLUDE_NAME = { taggerbase = true, taggerbase2 = true }
-- placement형(맵 지형 raw hit 조준) 아이템 — 청사진·클릭 양쪽에서 공용
local MAP_AIM_ITEMS    = { BlackHole = true, EnergyBall = true, Spear = true, Demonspear = true }
-- 투척류: 조준 시 바리케이드를 무시한다(벽 표면에 클릭이 물리면 창이 코앞에 꽂힘)
local THROW_ITEMS      = { Spear = true, Demonspear = true }

local aimIncludeCache  = nil
local aimCacheDirty    = true
local hookedMapFolders = {}   -- 중복 연결 방지

local function markAimCacheDirty()
    aimCacheDirty = true
    aimIncludeNoBarricade = nil
end

-- 맵 폴더 안에서 BasePart 가 드나들 때만 무효화 (VFX·Attachment 등은 무시 → 불필요한 재빌드 방지)
local function hookMapFolder(mf)
    if hookedMapFolders[mf] then return end
    hookedMapFolders[mf] = true
    mf.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then markAimCacheDirty() end
    end)
    mf.DescendantRemoving:Connect(function(d)
        if d:IsA("BasePart") then markAimCacheDirty() end
    end)
end

for _, name in ipairs(MAP_NAMES) do
    local mf = workspace:FindFirstChild(name)
    if mf then hookMapFolder(mf) end
end
workspace.ChildAdded:Connect(function(c)
    if c.Name == "map1" or c.Name == "map2" then hookMapFolder(c); markAimCacheDirty() end
end)
workspace.ChildRemoved:Connect(function(c)
    if c.Name == "map1" or c.Name == "map2" then markAimCacheDirty() end
end)

local aimIncludeNoBarricade = nil   -- 투척류용: 바리케이드 제외 목록

local function getAimIncludeList(skipBarricade)
    if skipBarricade then
        -- ⚠️ 투척류(Spear/Demonspear)는 바리케이드를 조준 대상에서 뺀다.
        --   벽이 시야를 채우므로, 포함하면 클릭이 항상 "벽 표면"으로 잡혀
        --   창이 코앞에 꽂힌다. 서버에서 좌표를 재해석해봤지만 태거 위치·각도에
        --   따라 착탄이 5~1011스터드까지 요동쳐 더 나빴다(실측) → 조준 단계에서 뺀다.
        --   벽은 어차피 태거 자신의 것이라 투척을 막을 이유가 없다.
        if aimIncludeNoBarricade and not aimCacheDirty then return aimIncludeNoBarricade end
        local list = {}
        -- 🏰 [2026-08-24] 성문 구조물도 제외 대상이다.
        -- ⚠️ 예전엔 부모 이름이 "Barricades" 인 판정 파트만 걸렀다. 그런데 통짜
        --    구조물로 바꾸면서 실제 벽은 map1 castle 안의 Gatehouse(620파트)가
        --    되었고, 그건 이 조건에 안 걸려 조준을 가로막았다.
        --    → 판정 파트의 BarricadeGate 속성을 읽어 연결 구조물 전체를 제외한다.
        local gateNames = {}
        for _, mapName in ipairs(MAP_NAMES) do
            local mf = workspace:FindFirstChild(mapName)
            local bf = mf and mf:FindFirstChild("Barricades")
            if bf then
                for _, seg in ipairs(bf:GetChildren()) do
                    local g = seg:GetAttribute("BarricadeGate")
                    if g then
                        for _, t in ipairs(string.split(g, ",")) do
                            gateNames[t:gsub("^%s+", ""):gsub("%s+$", "")] = true
                        end
                    end
                end
            end
        end

        local function isGatePart(d)
            -- 자신 또는 조상 중 하나가 성문 구조물이면 제외
            local cur = d
            while cur and cur ~= workspace do
                if gateNames[cur.Name] then return true end
                cur = cur.Parent
            end
            return false
        end

        for _, mapName in ipairs(MAP_NAMES) do
            local mf = workspace:FindFirstChild(mapName)
            if mf then
                for _, d in ipairs(mf:GetDescendants()) do
                    local inBar = d.Parent and d.Parent.Name == "Barricades"
                    if d:IsA("BasePart") and not AIM_EXCLUDE_CG[d.CollisionGroup]
                       and not AIM_EXCLUDE_NAME[d.Name]
                       and not inBar and not isGatePart(d) then
                        list[#list + 1] = d
                    end
                end
            end
        end
        aimIncludeNoBarricade = list
        return list
    end
    if aimIncludeCache and not aimCacheDirty then return aimIncludeCache end
    local include = {}
    for _, mapName in ipairs(MAP_NAMES) do
        local mf = workspace:FindFirstChild(mapName)
        if mf then
            for _, d in ipairs(mf:GetDescendants()) do
                -- 바리케이드는 조준 대상에 포함한다(투척류 제외).
                --   벽을 클릭하면 projectOntoPlate 가 taggerbase 와 동일하게 처리해
                --   계단 앞으로 좌표를 보정한다(isProjectionSource 참고).
                if d:IsA("BasePart") and not AIM_EXCLUDE_CG[d.CollisionGroup]
                   and not AIM_EXCLUDE_NAME[d.Name] then
                    include[#include + 1] = d
                end
            end
        end
    end
    aimIncludeCache = include
    aimCacheDirty = false
    return include
end

-- 🚧 [2026-08-26] Exclude 방식 조준의 공용 무시 목록.
--
-- [왜 함수로 뽑았나] 청사진(updateBlueprintPosition)과 클릭(Button1Down)이
--   각자 무시 목록을 만들고 있었고, 그래서 규칙이 어긋났다:
--     · 클릭  : Barricades 폴더 + taggerwall/base/spawn 이름 매치
--     · 청사진: bpIgnore 만 (벽도 성문도 안 뺌)
--   결과 — "청사진은 벽 위에 뜨는데 실제 발사는 다른 곳" 불일치,
--   그리고 벽을 바라본 채 언덕을 클릭하면 "성에는 소환할 수 없다" 가 떴다.
--   두 곳이 같은 함수를 부르면 다시 어긋날 수 없다.
--
-- ⚠️ 성문은 BarricadeGate 속성으로 찾는다. 이름을 하드코딩하면
--   map2 성문(Gate2/GateBlocker2/Gatehouse2)처럼 새 구조물이 늘 때마다 누락된다.
-- ⚠️ MAP_AIM_ITEMS(Include 방식)는 getAimIncludeList 를 쓴다. 이 함수는
--   그 외 아이템(bear_trap, Frost Dragon, tnt 등) 전용이다.
local function buildAimIgnoreList(base)
    local ignore = base or {}

    local gateNames = {}
    for _, mapName in ipairs(MAP_NAMES) do
        local mf = workspace:FindFirstChild(mapName)
        local bf = mf and mf:FindFirstChild("Barricades")
        if bf then
            for _, seg in ipairs(bf:GetChildren()) do
                local g = seg:GetAttribute("BarricadeGate")
                if g then
                    for _, t in ipairs(string.split(g, ",")) do
                        gateNames[t:gsub("^%s+", ""):gsub("%s+$", "")] = true
                    end
                end
            end
        end
    end

    for _, mapName in ipairs(MAP_NAMES) do
        local mf = workspace:FindFirstChild(mapName)
        if mf then
            local bf = mf:FindFirstChild("Barricades")
            if bf then table.insert(ignore, bf) end
            for _, d in ipairs(mf:GetDescendants()) do
                -- 성문 구조물은 최상위 모델째로 (자손 전부 무시됨)
                if gateNames[d.Name] then
                    table.insert(ignore, d)
                -- ⚠️ [2026-08-26] 곡사포·마법책도 제외한다.
                --   태거 앞 8스터드에 서 있는 자기 설비인데, 정면 조준을
                --   넓게 가린다(실측: map2 Z 880~975 구간 전부 MagicBook 에 걸림).
                --   태거 자신의 것이라 조준 대상일 이유가 없다.
                elseif d.Name == "Cannon" or d.Name == "MagicBook" then
                    table.insert(ignore, d)
                elseif d:IsA("BasePart") then
                    local nm = d.Name:lower()
                    -- ⚠️ taggerbase: 성 바닥이 언덕보다 높아, 성 안에서 밖을
                    --    조준하면 바닥 가장자리에 레이가 걸린다.
                    --    성 안은 어차피 소환 금지 구역이라 오작동이 없다.
                    -- ⚠️ taggerspawn: 스폰 표식일 뿐인데 레이를 막는다.
                    if d.CollisionGroup == "TaggerBarrier"
                       or nm:find("taggerwall")
                       or nm:find("taggerbase")
                       or nm:find("taggerspawn") then
                        table.insert(ignore, d)
                    end
                end
            end
        end
    end
    return ignore
end

-- 🧭 [2026-08-26] 러너 방향(taggerspawn → playerspawn) 계산.
--
-- [왜] 청사진이 원본 모델의 회전을 그대로 보존하는데, 서버 스폰은 회전을
--   따로 계산한다. 그래서 프로스트 드래곤·배럴 청사진이 옆면을 보고 떠 있었다.
--     · Frost Dragon : CFrame.lookAt(startPos, startPos + dir)  ← 러너 쪽을 봄
--     · Wooden Barrel: CFrame.fromMatrix(pos, sideAxis, up)     ← 원통축을 좌우로
--   (ItemSpawnHandler 1102·1204 행)
-- ⚠️ 서버와 같은 기준을 써야 한다. 태거 위치·클릭 지점이 아니라
--   맵의 고정점(taggerspawn → playerspawn)이다. 다른 기준을 쓰면
--   "청사진이 본 방향 ≠ 실제 소환 방향" 이 된다.
-- ⚠️ 두 맵이 동시에 workspace 에 있으므로, 태거와 가장 가까운 맵을 고른다.
local function getRunnerDirection()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local taggerPos = hrp and hrp.Position or Vector3.new(0, 0, 0)

    local function findPrefix(mf, pfx)
        for _, d in ipairs(mf:GetDescendants()) do
            if (d:IsA("BasePart") or d:IsA("SpawnLocation"))
               and d.Name:lower():sub(1, #pfx) == pfx then
                return d
            end
        end
    end

    local bestMap, bestDist = nil, math.huge
    for _, mf in ipairs(workspace:GetChildren()) do
        if mf.Name:lower():find("map") then
            local t = findPrefix(mf, "taggerspawn") or findPrefix(mf, "taggerbase")
            if t then
                local dd = (t.Position - taggerPos).Magnitude
                if dd < bestDist then bestDist = dd; bestMap = mf end
            end
        end
    end

    local dir = Vector3.new(-1, 0, 0)   -- 서버와 동일한 기본값
    if bestMap then
        local tRef = findPrefix(bestMap, "taggerspawn") or findPrefix(bestMap, "taggerbase")
        local rRef = findPrefix(bestMap, "playerspawn") or findPrefix(bestMap, "playerbase")
        if tRef and rRef then
            local flat = Vector3.new(rRef.Position.X - tRef.Position.X, 0,
                                     rRef.Position.Z - tRef.Position.Z)
            if flat.Magnitude > 0.1 then dir = flat.Unit end
        end
    end
    return dir
end

local function updateBlueprintPosition()
    if not blueprintModel or not isHoldingItem then
        return
    end
    local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    local bpIgnore = {player.Character, blueprintModel}
    -- 스폰된 태거 아이템은 표식으로 통째 제외 (CollisionGroup 만 보면 Default 쓰는 ItemNoob 계열 누락)
    for _, o in ipairs(workspace:GetChildren()) do
        if o:GetAttribute("TaggerSpawnedItem") then table.insert(bpIgnore, o) end
    end
    -- placement형(맵 지형 raw hit 조준) 여부 — 아래 필터 분기·투영 스킵에서 공용
    local useMapAim = MAP_AIM_ITEMS[selectedItem] == true
    -- 클릭 판정과 동일한 규칙: 맵 지형에만 조준 (스폰 아이템 위에 청사진이 뜨지 않게)
    -- 자세한 이유는 Button1Down 쪽 주석 참고.
    if useMapAim then
        raycastParams.FilterType = Enum.RaycastFilterType.Include
        -- 투척류는 바리케이드를 조준 대상에서 제외 (벽 표면에 클릭이 물려 코앞에 꽂히는 문제)
        -- ⚠️ [2026-08-25] 모든 태거 아이템이 바리케이드를 통과한다.
        --    예전엔 THROW_ITEMS(Spear/Demonspear)만 통과시켜,
        --    EnergyBall·tnt·bear_trap 은 보이지 않는 벽에 조준이 막혔다.
        --    원칙: 바리케이드는 1단계 플레이에 아무 영향도 주면 안 된다.
        raycastParams.FilterDescendantsInstances = getAimIncludeList(true)
    else
        -- ⚠️ [수정 2026-08-26] 예전엔 bpIgnore(캐릭터+청사진)만 썼다.
        --   벽·성문이 조준 대상에 남아, 청사진이 벽 위에 뜨는데 실제 발사는
        --   다른 곳으로 가는 불일치가 있었다. 클릭과 같은 헬퍼를 쓴다.
        raycastParams.FilterDescendantsInstances = buildAimIgnoreList(bpIgnore)
    end
    local result = workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 1000, raycastParams)
    if result then
        -- placement형은 클릭과 동일하게 raw hit 사용 — plate 투영 안 함.
        -- (맵 지형 조준이 정상 케이스라 projectOntoPlate의 [project-miss] 프레임 스팸도 방지)
        -- 단, 바리케이드를 맞은 경우는 placement 여도 투영한다 — 클릭 로직과 동일하게 맞춰야
        -- 청사진이 벽 위에 뜨는데 실제 발사는 계단 앞으로 가는 불일치가 없다.
        local hitBarricade = result.Instance.Parent ~= nil and result.Instance.Parent.Name == "Barricades"
        local proj = nil
        if not useMapAim or hitBarricade then
            proj = projectOntoPlate(result.Instance, result.Position)
        end
        local pos = proj or result.Position
        local hitNormal = result.Normal
        if selectedItem == "BlackHole" then
            -- 🕳️ 실제 스폰과 동일하게 재현:
            --    서버 activateBlackHole = PrimaryPart(Event Horizon)를 groundPos + normal*8 에 두고
            --    alignToSurface 로 표면에 정렬한다. 청사진도 같은 기준을 써야 착탄 위치가 일치한다.
            --    (지면에 딱 붙이면 실제보다 8스터드 낮게 보이고, 지면 잡동사니에 파묻힌다)
            blueprintModel:PivotTo(alignToSurface(pos + hitNormal * BH_LIFT_HEIGHT, hitNormal))
            -- 흡인 반경(70 = 지름 140)은 원반 시각 크기(지름 ~83)보다 훨씬 넓다.
            -- 링이 없으면 태거가 실제 판정 범위를 알 수 없음.
            updateBlackHoleRing(pos, hitNormal)
        elseif blueprintModel:IsA("Model") then
            clearBlackHoleRing()
            -- ⚠️ MoveTo는 목표 지점에 다른 파트가 겹치면 모델을 Y로 밀어올림(엔진 내장 장애물 회피).
            --    쓰나미가 지나는 지면을 조준하면 청사진이 파도 꼭대기로 떠오르던 원인.
            --    → 충돌 보정이 전혀 없는 PivotTo로 교체. (CFrame.new(pos)만 쓰면 회전 리셋되므로 기존 회전 보존)
            --
            -- 🧭 [2026-08-26] 서버가 회전을 계산하는 아이템은 청사진도 같이 계산한다.
            --    안 그러면 원본 회전 그대로 떠서 옆면을 보인다(실측 증상).
            if selectedItem == "Frost Dragon" then
                -- 서버: CFrame.lookAt(startPos, startPos + dir) — 러너 쪽을 바라봄
                local dir = getRunnerDirection()
                blueprintModel:PivotTo(CFrame.lookAt(pos, pos + dir))
            elseif selectedItem == "Wooden Barrel" then
                -- 서버: 원통축(PrimaryPart 로컬 X)을 진행방향과 수직인 좌우축에 맞춤.
                --   fromMatrix(pos, rightVector=원통축, upVector) 형태를 그대로 재현한다.
                local rollDir = getRunnerDirection()
                local sideAxis = Vector3.new(0, 1, 0):Cross(rollDir)
                if sideAxis.Magnitude > 0.01 then
                    blueprintModel:PivotTo(CFrame.fromMatrix(pos, sideAxis.Unit, Vector3.new(0, 1, 0)))
                else
                    local pv = blueprintModel:GetPivot()
                    blueprintModel:PivotTo((pv - pv.Position) + pos)
                end
            else
                local pv = blueprintModel:GetPivot()
                blueprintModel:PivotTo((pv - pv.Position) + pos)
            end
        else
            clearBlackHoleRing()
            blueprintModel.Position = pos + Vector3.new(0, blueprintModel.Size.Y/2, 0)
        end

        -- 🗡️ Spear/Demonspear: 투척 경로(= 실제 판정 범위) 표시.
        -- 판정이 창 전체를 쓸고 지나가는 Blockcast 라 "착지점"만 보면 어디까지 맞는지 알 수 없다.
        -- 태거 → 착지점 경로를 판정 폭(6스터드)으로 그려 사거리·굵기를 함께 인지시킨다.
        if selectedItem == "Spear" or selectedItem == "Demonspear" then
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local from = hrp.Position + Vector3.new(0, 2, 0)
                local dir = (pos - from)
                local dist = dir.Magnitude
                if dist > 1 then
                    local guide = workspace:FindFirstChild("_SpearPathGuide")
                    if not guide then
                        guide = Instance.new("Part")
                        guide.Name = "_SpearPathGuide"
                        guide.Anchored = true
                        guide.CanCollide = false
                        guide.CanQuery = false
                        guide.CastShadow = false
                        guide.Material = Enum.Material.Neon
                        guide.Color = Color3.fromRGB(150, 215, 255)
                        guide.Transparency = 0.82
                        guide.Parent = workspace
                    end
                    guide.Size = Vector3.new(6, 6, dist)   -- HIT_RADIUS(3)*2 = 판정 폭
                    guide.CFrame = CFrame.lookAt(from + dir.Unit * (dist / 2), pos)
                end
            end
        else
            local g = workspace:FindFirstChild("_SpearPathGuide")
            if g then g:Destroy() end
        end

        -- 🚫 [MIN-SPAWN-DIST] 금지 거리 실시간 판정 — 클릭 '전에' 알려준다.
        --   서버 판정(ItemSpawnHandler.handleSpawnRequest)과 완전히 같은 식이다:
        --     (소환좌표 - 태거 HRP).Magnitude < MIN_SPAWN_DIST  → 거부
        --   pos 는 투영(projectOntoPlate)까지 끝난 '실제로 소환될 좌표'이므로
        --   여기서 재면 서버 결과와 어긋나지 않는다. (raw 좌표로 재면 벽 클릭 시 불일치)
        do
            local minD = getMinSpawnDist()
            local mChar = player.Character
            local mHrp  = mChar and mChar:FindFirstChild("HumanoidRootPart")
            local blocked = false
            if mHrp then
                blocked = (pos - mHrp.Position).Magnitude < minD
            end
            tintBlueprint(blueprintModel, blocked)
            if blocked then updateMinDistMark(minD, pos) else clearMinDistMark() end
        end
    else
        -- 레이가 아무것도 안 맞은 경우: 청사진을 이전 위치에 그대로 둔다.
    end
end

-- 💣 폭격 조준 모드 연동 훅 (BombTargetingClient가 호출)
--   true  → 청사진 제거 + 재장전 차단 (탑뷰에서 조준을 방해하지 않게)
--   false → 차단 해제 + 아이템이 선택돼 있으면 청사진 복구
_G.TaggerBlueprintSuppress = function(state)
    _G.BombTargeting = state and true or false
    if state then
        clearLocalBlueprint()
    elseif selectedItem and player:GetAttribute("Role") == "Tagger" then
        isHoldingItem = true
        requestBlueprint(selectedItem)
    end
end

-- ════════════════════════════════════════════════════════════════
-- [TAGGER-TUTORIAL] 신규 태거에게 "리스트에서 고르고 → 언덕/계단을 조준" 만 알린다.
--   ⚠️ 아이템별 상세는 이미 showHint(ITEM_HINTS)가 선택 직후 6초간 띄운다.
--      여기서 또 설명하면 중복이고, 종류가 많아 읽지도 않는다.
--      빠진 건 '그 앞 단계' — 아이템을 고르지 않으면 소환 자체가 안 되는데
--      그걸 모르면 시작조차 못 한다.
--   ⚠️ RoundsPlayed < 3 인 신규만. 숙련자에겐 잔소리가 된다.
-- ════════════════════════════════════════════════════════════════
local function showTaggerTutorial()
    if tutShownThisRound then return end
    local rp = player:GetAttribute("RoundsPlayed")
    if rp ~= nil and rp >= TUT_ROUNDS then return end
    tutShownThisRound = true

    if not tutLabel then
        tutLabel = Instance.new("TextLabel")
        tutLabel.Name = "TaggerTutorial"
        -- 리스트(우측 세로) 왼쪽에 붙인다. 화면 중앙을 가리지 않는다.
        tutLabel.AnchorPoint = Vector2.new(1, 0.5)
        tutLabel.Position = UDim2.new(1, -220, 0.5, -25)
        tutLabel.Size = UDim2.fromOffset(300, 98)   -- 3행이라 높이 확대
        tutLabel.BackgroundColor3 = Color3.fromRGB(40, 20, 80)
        tutLabel.BackgroundTransparency = 0.15
        tutLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        tutLabel.TextSize = 17
        tutLabel.Font = Enum.Font.GothamBold
        tutLabel.TextWrapped = true
        tutLabel.ZIndex = 12
        tutLabel.Active = false
        tutLabel.Selectable = false
        tutLabel.Text = "1. Pick an item from the list →\n2. Aim at the hill or stairs and click\n3. Switch items to throw faster"
        tutLabel.Parent = gui
        Instance.new("UICorner", tutLabel).CornerRadius = UDim.new(0, 10)
        local st = Instance.new("UIStroke", tutLabel)
        st.Color = Color3.fromRGB(150, 50, 255) ; st.Thickness = 2
        st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    end
    tutLabel.Visible = true

    -- 리스트 자체를 점멸시켜 "여기를 보라"를 시각으로 전달한다(문구만으론 약하다).
    if not tutStroke then
        tutStroke = itemList:FindFirstChildOfClass("UIStroke")
        if not tutStroke then
            tutStroke = Instance.new("UIStroke", itemList)
            tutStroke.Thickness = 0
        end
    end
    task.spawn(function()
        local TS = game:GetService("TweenService")
        local base = tutStroke.Thickness
        local t0 = tick()
        while tick() - t0 < TUT_DURATION do
            TS:Create(tutStroke, TweenInfo.new(0.35),
                { Color = Color3.fromRGB(180, 110, 255), Thickness = 5 }):Play()
            task.wait(0.35)
            TS:Create(tutStroke, TweenInfo.new(0.35), { Thickness = base }):Play()
            task.wait(0.35)
        end
        tutStroke.Thickness = base
    end)

    task.delay(TUT_DURATION, function()
        if tutLabel then tutLabel.Visible = false end
    end)
end

-- 태거 UI 표시/숨김
local function updateTaggerUI()
    local role = player:GetAttribute("Role")
    if role == "Tagger" then
        loadTaggerItems()
        itemList.Visible = true
        showTaggerTutorial()
    else
        itemList.Visible = false
        clearLocalBlueprint()
        isHoldingItem = false
        selectedItem = nil
        cooldownLabel.Visible = false
        -- [TAGGER-TUTORIAL] 다음에 다시 태거가 되면 또 보여줄 수 있게 초기화
        tutShownThisRound = false
        if tutLabel then tutLabel.Visible = false end
    end
end

player:GetAttributeChangedSignal("Role"):Connect(updateTaggerUI)
updateTaggerUI()

-- (청사진은 이제 클라 로컬 빌드 — ReceiveItemPreview 수신 불필요, 서버도 발사 안 함)

-- 쿨다운 피드백
cooldownEvent.OnClientEvent:Connect(function(remaining)
    cooldownLabel.Text = string.format("Cooldown: %.1fs", remaining)
    cooldownLabel.Visible = true
    task.delay(remaining, function()
        cooldownLabel.Visible = false
        if selectedItem and player:GetAttribute("Role") == "Tagger" then
            isHoldingItem = true
            requestBlueprint(selectedItem)
        end
    end)
end)

-- 청사진 위치 업데이트
RunService.RenderStepped:Connect(function()
    if isHoldingItem and blueprintModel and blueprintModel.Parent then
        updateBlueprintPosition()
    end
end)

-- ✋ Placement-style 아이템: spawn plate가 아니라 hill 등 어디든 마우스 hit 위치에 직접 설치
-- (서버에서 사거리/role 등 검증한다)
local PLACEMENT_ITEMS = {
    ["bear_trap"] = true,
    ["BlackHole"] = true,  -- 어디든 클릭한 곳으로 포물선 투척
    ["EnergyBall"] = true, -- 겨냥한 방향으로 레일건 발사
    ["Spear"] = true,      -- 겨냥한 곳으로 창 투척
    ["Demonspear"] = true, -- 겨냥한 곳으로 데몬 창 투척 (불 궤적)
    ["Frost Dragon"] = true, -- 클릭한 곳에 소환 → 다운레인지 얼음 라인
    -- 💣 tnt: 이 클릭은 "폭격 지점"이 아니라 조준 모드를 여는 트리거일 뿐이다.
    --    실제 착탄점은 탑뷰에서 다시 고른다. 그런데 placement 가 아니면 taggerbase 플레이트로
    --    투영이 성공해야만 요청이 나가서, 언덕을 클릭하면 [project-miss] 로 막혀 조준 모드가 안 열렸다.
    ["tnt"] = true,
}

-- 마우스 클릭
mouse.Button1Down:Connect(function()
    if not selectedItem or not isHoldingItem then return end
    -- 💣 폭격 조준 모드 중(및 종료 직후)에는 이 핸들러가 클릭을 먹으면 안 된다.
    --    BombTargetingClient의 InputBegan 과 같은 클릭에 둘 다 반응하기 때문에,
    --    막지 않으면 "착탄 확정 → 즉시 새 스폰 요청 → 조준 모드 재진입"이 무한 반복된다.
    --    (실제 로그: 타겟 확정 31ms 뒤 SPAWN REQUEST → 타겟팅 모드 재진입)
    if _G.BombTargeting then return end
    if os.clock() - (_G.BombTargetingEndedAt or 0) < 0.25 then return end
    
    local mouseRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    local ignoreList = {player.Character}
    if blueprintModel then table.insert(ignoreList, blueprintModel) end

    -- 🕳️⚡🗡️ BlackHole/EnergyBall/Spear/Demonspear: 맵 지형에만 조준한다.
    -- ⚠️ Blacklist(제외 목록) 방식은 실패했다 — 지형(hill2/DesertSandFloor 등)과
    --    스폰 아이템(Wood Log/stone/ItemNoob)이 둘 다 CollisionGroup="Default" 라
    --    그룹으로 구분이 안 되고, 표식(TaggerSpawnedItem)은 스폰 경로가 늘 때마다 누락된다.
    --    → Include 로 뒤집어 "선택된 맵 폴더 안의 것"만 조준 대상으로 삼는다.
    --      스폰된 아이템은 workspace 최상위에 붙으므로 자동으로 전부 배제된다.
    --      산/벽/장벽은 맵 안에 있으므로 별도로 제외 목록을 유지한다.
    if MAP_AIM_ITEMS[selectedItem] then
        raycastParams.FilterType = Enum.RaycastFilterType.Include
        -- 청사진 쪽과 동일 규칙이어야 "보이는 곳 ≠ 꽂히는 곳" 불일치가 안 생긴다
        -- ⚠️ [2026-08-25] 모든 태거 아이템이 바리케이드를 통과한다.
        --    예전엔 THROW_ITEMS(Spear/Demonspear)만 통과시켜,
        --    EnergyBall·tnt·bear_trap 은 보이지 않는 벽에 조준이 막혔다.
        --    원칙: 바리케이드는 1단계 플레이에 아무 영향도 주면 안 된다.
        raycastParams.FilterDescendantsInstances = getAimIncludeList(true)
    else
        -- ⚠️ MAP_AIM_ITEMS 에 없는 아이템(bear_trap, Frost Dragon 등)도
        --    바리케이드·성문을 통과해야 한다. Exclude 방식이므로 무시 목록에 넣는다.
        --
        -- ⚠️ [수정 2026-08-26] 성문 구조물 제외가 이 분기에만 빠져 있었다.
        --   [증상] 화면을 돌려 언덕을 직접 보면 소환되는데, 벽을 바라본 채
        --     언덕을 클릭하면 "성에는 소환할 수 없다" 가 떴다.
        --     레이가 성문에 먼저 맞아 그 좌표(=성 안)를 서버로 보냈기 때문이다.
        --   [해결] 청사진과 같은 헬퍼를 쓴다. 두 곳이 각자 목록을 만들면
        --     또 어긋난다("보이는 곳 ≠ 꽂히는 곳").
        raycastParams.FilterDescendantsInstances = buildAimIgnoreList(ignoreList)
    end
    
    local result = workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 1000, raycastParams)
    if not result then return end

    -- 🕳️⚡ BlackHole/EnergyBall: 유효 바닥 어디든 조준 발사 (벽/산/배리어는 레이캐스트에서 이미 무시됨 → 맵 무관)

    -- 🗡️🔥 Spear/Demonspear: 유효 바닥 또는 러너 어디든 조준 (벽/산/배리어는 이미 무시됨 → 맵 무관)

    -- Placement 아이템: 어디 클릭이든 OK (hill, baseplate, spawn plate 모두)
    -- 일반 아이템: spawn plate 표면 클릭만 OK
    local isPlacement = PLACEMENT_ITEMS[selectedItem]
    local isSpawnPlate = result.Instance.Name == "ItemSpawnPlate" or result.Instance.Name:lower():find("spawnplate")
    -- ⚠️ 바리케이드를 맞은 경우는 placement 여도 raw 좌표를 쓰면 안 된다.
    --    벽 좌표는 태거 베이스 안이라 서버가 "태거 베이스 구역 소환 금지"로 거부한다.
    --    → 벽 클릭은 항상 계단 앞으로 투영한다(taggerbase 클릭과 동일 취급).
    local hitBarricade = result.Instance.Parent ~= nil and result.Instance.Parent.Name == "Barricades"

    local fireInst, firePos
    if (isPlacement or isSpawnPlate) and not hitBarricade then
        fireInst, firePos = result.Instance, result.Position
    else
        local projPos, plate = projectOntoPlate(result.Instance, result.Position)
        if projPos then
            fireInst, firePos = plate, projPos
        end
    end
    if fireInst then
        spawnEvent:FireServer(fireInst, selectedItem, firePos)
        -- ⏱️ 쿨은 서버가 확정한 뒤 ItemCooldownStart 로 알려준다.
        --    여기서 미리 돌리면 서버가 거부해도 쿨이 도는 문제가 생긴다.
        clearLocalBlueprint()
        isHoldingItem = false
        hideHint()
        
        -- 쿨타임 후 자동 재준비
        task.delay(2.1, function()
            if selectedItem and player:GetAttribute("Role") == "Tagger" then
                isHoldingItem = true
                requestBlueprint(selectedItem)
            end
        end)
    end
end)

-- ESC 취소
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.Escape and (isHoldingItem or selectedItem) then
        local clearEvent = ReplicatedStorage:FindFirstChild("ClearBlueprint")
        if clearEvent then clearEvent:FireServer() end
        clearLocalBlueprint()
        isHoldingItem = false
        selectedItem = nil
        cooldownLabel.Visible = false
        hideHint()
        for _, btn in ipairs(itemContainer:GetChildren()) do
            if btn:IsA("TextButton") then
                btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
            end
        end
    end
end)

print("✅ Tagger UI Ready! (Loadout-based)")


-- ═══════════════════════════════════════════════════════════
-- ⏱️ 아이템 쿨 표시 갱신
-- ⚠️ 버튼은 런타임에 만들어지므로 매번 Container 를 훑는다.
--    아이템 수가 5~8개라 부담이 없다.
-- ═══════════════════════════════════════════════════════════
task.spawn(function()
    local RunService = game:GetService("RunService")
    RunService.RenderStepped:Connect(function()
        local now = os.clock()
        for _, btn in ipairs(itemContainer:GetChildren()) do
            if btn:IsA("TextButton") then
                local ov = btn:FindFirstChild("CdOverlay")
                local txt = ov and ov:FindFirstChild("CdText")
                if ov and txt then
                    local until_ = itemCdUntil[btn.Name] or 0
                    -- 전역 쿨과 개별 쿨 중 더 늦은 쪽 (면제 아이템은 개별 쿨만)
                    local eff = GLOBAL_CD_EXEMPT[btn.Name]
                        and until_
                        or  math.max(until_, globalCdUntil)
                    local remain = eff - now
                    -- 🔒 상태 잠금이 시간 쿨을 이긴다.
                    --   [왜] Frost Dragon / tox_box / tnt 는 표 쿨이 끝나도 효과가 살아 있으면
                    --     못 쓴다. 숫자를 먼저 보여주면 0 에 닿았는데 안 열려 UI 가 거짓말을 한다.
                    --   ⚠️ 잠금 중엔 숫자를 지운다. 남은 시간을 모르는데 숫자를 남기면
                    --     그게 곧 거짓 정보다.
                    if itemLocked[btn.Name] then
                        ov.Visible = true
                        txt.Text = itemLockLabel[btn.Name] or "IN USE"
                    elseif remain > 0.05 then
                        ov.Visible = true
                        txt.Text = string.format("%.1f", remain)
                    else
                        ov.Visible = false
                    end
                end

                -- 🪤 설치 개수 배지 갱신 (TrapSystem.syncTrapCount 가 올리는 속성)
                -- ⚠️ 값이 안 바뀌면 쓰지 않는다 — 매 프레임 SetProperty 는 낭비다.
                -- 상한 도달 시 빨간색으로 바꿔 "쿨이 아니라 개수가 막힌 것"을 구분시킨다.
                local badge = btn:FindFirstChild("CountBadge")
                if badge then
                    local cur = player:GetAttribute("TrapCount") or 0
                    local max = player:GetAttribute("TrapMax") or 5
                    local s = string.format("%d/%d", cur, max)
                    if badge.Text ~= s then
                        badge.Text = s
                        badge.TextColor3 = (cur >= max)
                            and Color3.fromRGB(255, 110, 110)
                            or  Color3.fromRGB(255, 235, 150)
                    end
                end
            end
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════
-- 📢 태거 알림 (함정 개수 초과, 설치 불가 구역 등)
-- [왜] 서버가 거부해도 화면에 아무 표시가 없어 유저가 이유를 몰랐다.
-- ═══════════════════════════════════════════════════════════
do
    local noticeEv = ReplicatedStorage:FindFirstChild("TaggerNoticeEvent")
    if noticeEv then
        local noticeLabel = Instance.new("TextLabel")
        noticeLabel.Name = "TaggerNotice"
        noticeLabel.Size = UDim2.new(0, 320, 0, 44)
        noticeLabel.Position = UDim2.new(0.5, -160, 0.62, 0)
        noticeLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        noticeLabel.BackgroundTransparency = 0.25
        noticeLabel.Font = Enum.Font.GothamBold
        noticeLabel.TextScaled = true
        noticeLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
        noticeLabel.Text = ""
        noticeLabel.Visible = false
        noticeLabel.ZIndex = 50
        noticeLabel.Parent = gui
        local nc = Instance.new("UICorner")
        nc.CornerRadius = UDim.new(0, 10)
        nc.Parent = noticeLabel
        local np = Instance.new("UIPadding")
        np.PaddingLeft = UDim.new(0, 12)
        np.PaddingRight = UDim.new(0, 12)
        np.PaddingTop = UDim.new(0, 8)
        np.PaddingBottom = UDim.new(0, 8)
        np.Parent = noticeLabel

        local noticeToken = 0
        noticeEv.OnClientEvent:Connect(function(msg)
            if type(msg) ~= "string" then return end
            noticeToken = noticeToken + 1
            local myToken = noticeToken
            noticeLabel.Text = msg
            noticeLabel.Visible = true
            noticeLabel.TextTransparency = 0
            noticeLabel.BackgroundTransparency = 0.25
            task.delay(1.6, function()
                if noticeToken ~= myToken then return end
                -- 부드럽게 사라짐
                for i = 0, 1, 0.08 do
                    if noticeToken ~= myToken then return end
                    noticeLabel.TextTransparency = i
                    noticeLabel.BackgroundTransparency = 0.25 + i * 0.75
                    task.wait(0.02)
                end
                if noticeToken == myToken then noticeLabel.Visible = false end
            end)
        end)
    end
end


-- 🔔 [2026-08-26] 함정 발동 알림 — 소유자 전용 2D 사운드.
-- [왜] 밟힘 사운드는 함정 HitBox 에 붙은 위치 사운드라 80 stud 밖에선 안 들린다.
--   맵 X축이 약 870 stud 라, 멀리 깔아둔 함정은 걸렸는지조차 알 수 없었다.
-- [방식] SoundService 에 붙이면 비위치(2D) 재생이라 거리 개념이 없다.
--   BasePart/Attachment 밑에 두면 다시 3D 가 되므로 부모를 바꾸지 말 것.
-- ⚠️ 이건 '시점' 만 알린다. '누구/어디' 는 PlayerMarkerClient 가 마커로 표시한다.
-- 🔜 태거 아이템 SFX 를 ElevenLabs 로 제작하면 SFX_TRAP_CAUGHT 만 갈아끼우면 된다.
do
    local SFX_TRAP_CAUGHT = "rbxassetid://2019418800"   -- TrapSystem.SND_SNAP 과 동일 음원
    local caughtEv = ReplicatedStorage:FindFirstChild("TrapCaughtEvent")
        or ReplicatedStorage:WaitForChild("TrapCaughtEvent", 10)
    if caughtEv then
        local SoundService = game:GetService("SoundService")
        caughtEv.OnClientEvent:Connect(function(victimName, lockDuration)
            local s = Instance.new("Sound")
            s.Name = "TrapCaught2D"
            s.SoundId = SFX_TRAP_CAUGHT
            s.Volume = 0.85
            s.Parent = SoundService      -- ⚠️ 2D 재생의 핵심
            s:Play()
            game:GetService("Debris"):AddItem(s, 5)
        end)
    end
end


-- 🔒 [2026-08-27] 단일 존재 아이템의 '상태 잠금' 표시.
--   [왜] Frost Dragon / tox_box / tnt 는 표에 적힌 쿨이 끝나도 효과가 살아 있으면
--     다시 못 쓴다. 지금까지 UI 는 그걸 몰라 "열린 것처럼" 보였고,
--     태거는 눌렀는데 아무 일도 안 일어나는 경험을 했다.
--   [왜 숫자가 아닌가] 종료 시점이 예측 불가다(톡스박스=지형·거리, TNT=본인 조준,
--     프드=파쇄 기둥 수에 따라 24~28초). 숫자를 띄우면 0 에 닿아도 안 열려 또 거짓말이 된다.
--   ⚠️ itemCdUntil(시간 기반)과 별도 테이블이다. 섞으면 남은 시간 계산이 꼬인다.
--   ⚠️ 서버가 잠글 때 true, 풀릴 때 false 를 짝으로 보낸다. 한쪽만 오면 영구 잠김이므로
--     서버 쪽에 SetItemLock 을 추가할 땐 반드시 해제 경로도 같이 넣을 것.
do
    local lockEv = ReplicatedStorage:FindFirstChild("ItemLockState")
        or ReplicatedStorage:WaitForChild("ItemLockState", 10)
    if lockEv then
        lockEv.OnClientEvent:Connect(function(itemName, locked, label)
            if type(itemName) ~= "string" then return end
            if locked then
                itemLocked[itemName] = true
                itemLockLabel[itemName] = tostring(label or "IN USE")
            else
                itemLocked[itemName] = nil
                itemLockLabel[itemName] = nil
            end
        end)
    end
end

-- 🧹 [ITEMLOCK-RESET 2026-08-27] 라운드가 끝나면 잠금을 전부 푼다.
--   [왜] 서버는 '해제 이벤트'가 발생할 때만 false 를 보낸다. 그런데 라운드가
--     중간에 끝나면(전멸·타임아웃·이탈) 얼음이 파쇄되기 전에, 박스가 베이스에
--     닿기 전에 정리돼 해제 신호가 안 온다. 그대로 두면 다음 라운드에도
--     그 아이템이 잠긴 채로 보인다.
--   ⚠️ "상태를 켜는 코드에는 끄는 코드를 같이" — 서버 짝만 믿으면 이 경로에서 샌다.
--   ⚠️ 라운드로 '들어갈' 때가 아니라 '나갈' 때 푼다. stage1→stage2 전환에서
--     풀면 진행 중인 잠금이 사라져 UI 가 열린 것처럼 보인다.
do
    local RS = game:GetService("ReplicatedStorage")
    RS:GetAttributeChangedSignal("RoundPhase"):Connect(function()
        local ph = RS:GetAttribute("RoundPhase")
        if ph == "stage1" or ph == "stage2" then return end
        for k in pairs(itemLocked) do itemLocked[k] = nil end
        for k in pairs(itemLockLabel) do itemLockLabel[k] = nil end
    end)
end
-- ⏱️ 서버가 확정한 쿨을 받아 표시한다.
do
    local cdEv = ReplicatedStorage:FindFirstChild("ItemCooldownStart")
        or ReplicatedStorage:WaitForChild("ItemCooldownStart", 10)
    if cdEv then
        cdEv.OnClientEvent:Connect(function(itemName, itemCd, globalCd)
            if type(itemName) ~= "string" then return end
            local now = os.clock()
            itemCdUntil[itemName] = now + (tonumber(itemCd) or DEFAULT_CD)
            -- ⚠️ 면제 아이템은 서버가 globalCd=0 을 보낸다. 그대로 대입하면
            --   전역 쿨이 통째로 풀린 것처럼 되어(now+0) 다른 아이템까지 열려 보인다.
            --   → 0 이하면 기존 globalCdUntil 을 건드리지 않는다.
            local g = tonumber(globalCd) or GLOBAL_CD
            if g > 0 then
                globalCdUntil = now + g
            end
        end)
    end
end
