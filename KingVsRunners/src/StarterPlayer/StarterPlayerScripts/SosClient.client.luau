-- SosClient
-- 구조 신호(SOS) 클라이언트 처리
--
-- 4가지 기능:
--   1. 본인이 다운 중일 때 Q 또는 클릭으로 SOS 발신
--   2. 모든 다운자(자신 포함) 머리 위 SOS 아이콘 표시
--      - 평소: 주황색 (도움 필요)
--      - SOS 활성: 빨간색 깜박임 (긴급)
--   3. SOS 활성 다운자: 화면 가장자리 마커 + 거리 (장거리 인지)
--   4. 본인 캐릭터 15m 이내 다운자: 자동 마커 표시 (근접 발견)

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local downStateEvent = ReplicatedStorage:WaitForChild("DownStateChanged")
local sosStateEvent  = ReplicatedStorage:WaitForChild("SosStateChanged")
local sosRequestEvent = ReplicatedStorage:WaitForChild("SosRequestEvent")

-- ── 설정 ────────────────────────────────────────────────
local SOS_KEY            = Enum.KeyCode.Q
-- ⚠️ 기존 15 는 주행거리(약 920 stud)의 2% 라 사실상 바로 옆에 있어야 마커가 떴다.
--    그래서 신규 유저는 "동료를 살릴 수 있다"는 것 자체를 모른 채 지나쳤다.
--    다운 마커는 튜토리얼 역할도 겸하므로 항상 보이게 넓힌다(SOS 를 안 눌러도).
--    SOS 는 여전히 구분된다 — updateMarkerStyle 이 색을 달리해 "급함"을 표시한다.
local NEARBY_RADIUS      = 900       -- 근접 발견 반경 (stud) — 맵 전역
local MIN_MARKER_DIST    = 5         -- 이 거리 미만이면 마커 안 보임 (눈앞이면 마커 불필요)
local SOS_ICON_OFFSET    = Vector3.new(0, 3, 0)  -- 머리 위 위치

-- 도움 요청 사운드 (SOS 발신 시 다운자 위치에서 3D 사운드 재생)
local SOS_SOUND_ID       = "rbxassetid://140558322031646"
local SOS_SOUND_VOLUME   = 1
local SOS_SOUND_MAX_DIST = 200  -- 이 거리 이상이면 안 들림 (직선 맵 길이에 맞춰 넉넉히)
local SOS_SOUND_MIN_DIST = 10   -- 이 거리 미만이면 최대 볼륨

-- 바닥 방향 화살표 (SOS 다운자가 있을 때 본인 발 앞에 표시)
local ARROW_DISTANCE_FROM_PLAYER = 5     -- 플레이어 발 앞 몇 stud 거리에 화살표 띄울지
local ARROW_HEIGHT_OFFSET        = 0.5   -- 지면 위 살짝 띄움 (Z-fighting 방지)
local ARROW_HIDE_DISTANCE        = 8     -- 다운자에게 이 거리 이내면 화살표 숨김 (이미 옆이라 불필요)
local ARROW_COLOR_FAR            = Color3.fromRGB(255, 80, 80)
local ARROW_COLOR_NEAR           = Color3.fromRGB(255, 200, 80)  -- 가까울수록 주황 (도착 임박)

-- ── 상태 ────────────────────────────────────────────────
-- character -> { billboard = ScreenGui, isSosActive = bool }
local downedHeadIcons = {}
-- character -> Frame (화면 가장자리 마커)
local edgeMarkers = {}
local screenGui   = nil  -- 마커들 담는 ScreenGui

-- ─────────────────────────────────────────────────────────────
-- ScreenGui 초기화 (마커 컨테이너)
-- ─────────────────────────────────────────────────────────────
local function getScreenGui()
    if screenGui and screenGui.Parent then return screenGui end
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SosMarkers"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 5
    screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
    return screenGui
end

-- ─────────────────────────────────────────────────────────────
-- 머리 위 SOS 아이콘 (다운자 본인 + 타인이 가까이서 봤을 때)
-- ─────────────────────────────────────────────────────────────
local function createHeadIcon(character)
    if downedHeadIcons[character] then return downedHeadIcons[character] end

    local head = character:FindFirstChild("Head")
    if not head then return nil end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "SosHeadIcon"
    billboard.Size = UDim2.new(0, 60, 0, 60)
    billboard.StudsOffset = SOS_ICON_OFFSET
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.Adornee = head
    billboard.Parent = head

    -- 배경 원 (펄스 효과)
    local pulseCircle = Instance.new("Frame")
    pulseCircle.Name = "Pulse"
    pulseCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    pulseCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
    pulseCircle.Size = UDim2.new(1, 0, 1, 0)
    pulseCircle.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    pulseCircle.BackgroundTransparency = 0.6
    pulseCircle.BorderSizePixel = 0
    pulseCircle.Parent = billboard

    local pulseCorner = Instance.new("UICorner")
    pulseCorner.CornerRadius = UDim.new(1, 0)
    pulseCorner.Parent = pulseCircle

    -- 메인 텍스트
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "🩸"
    label.TextColor3 = Color3.fromRGB(255, 200, 100)  -- 주황색 (기본 다운)
    label.TextSize = 36
    label.Font = Enum.Font.GothamBold
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.Parent = billboard

    local entry = {
        billboard   = billboard,
        pulseCircle = pulseCircle,
        label       = label,
        isSosActive = false,
        pulseConn   = nil,
    }
    downedHeadIcons[character] = entry
    return entry
end

local function updateHeadIconState(character, isSosActive)
    local entry = downedHeadIcons[character]
    if not entry then return end
    entry.isSosActive = isSosActive

    if isSosActive then
        -- SOS 활성: 빨간색 + 강한 깜박임 + "SOS" 텍스트
        entry.label.Text = "SOS"
        entry.label.TextColor3 = Color3.fromRGB(255, 80, 80)
        entry.label.TextSize = 28
        entry.pulseCircle.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    else
        -- 기본: 주황색 + 약한 펄스
        entry.label.Text = "🩸"
        entry.label.TextColor3 = Color3.fromRGB(255, 180, 80)
        entry.label.TextSize = 36
        entry.pulseCircle.BackgroundColor3 = Color3.fromRGB(255, 130, 60)
    end
end

local function removeHeadIcon(character)
    local entry = downedHeadIcons[character]
    if not entry then return end
    if entry.pulseConn then entry.pulseConn:Disconnect() end
    if entry.billboard then entry.billboard:Destroy() end
    downedHeadIcons[character] = nil
end

-- ─────────────────────────────────────────────────────────────
-- 화면 가장자리 마커 (장거리 인지)
-- ─────────────────────────────────────────────────────────────
local function createEdgeMarker(character)
    if edgeMarkers[character] then return edgeMarkers[character] end

    local gui = getScreenGui()
    local frame = Instance.new("Frame")
    frame.Name = "SosMarker_" .. character.Name
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Size = UDim2.new(0, 52, 0, 52)   -- 80 → 52 (봇을 덮을 만큼 컸음)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    frame.BackgroundTransparency = 0.4
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 60, 60)
    stroke.Thickness = 3
    stroke.Parent = frame

    -- 화살표/아이콘
    local icon = Instance.new("TextLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(1, 0, 0.55, 0)
    icon.Position = UDim2.new(0, 0, 0, 4)
    icon.BackgroundTransparency = 1
    icon.Text = "🩸"
    icon.TextColor3 = Color3.fromRGB(255, 100, 100)
    icon.TextSize = 20
    icon.Font = Enum.Font.GothamBold
    icon.Parent = frame

    -- 거리 표시
    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "Dist"
    distLabel.Size = UDim2.new(1, 0, 0.4, 0)
    distLabel.Position = UDim2.new(0, 0, 0.55, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.Text = ""
    distLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    distLabel.TextSize = 11
    distLabel.Font = Enum.Font.GothamBold
    distLabel.Parent = frame

    edgeMarkers[character] = {
        frame     = frame,
        stroke    = stroke,
        icon      = icon,
        distLabel = distLabel,
        isSos     = false,  -- 장거리 SOS 마커인지 / 근접 발견인지
    }
    return edgeMarkers[character]
end

local function updateMarkerStyle(marker, isSos)
    marker.isSos = isSos
    if isSos then
        -- SOS: 빨간 강조
        marker.stroke.Color = Color3.fromRGB(255, 60, 60)
        marker.icon.TextColor3 = Color3.fromRGB(255, 100, 100)
    else
        -- 근접 발견: 주황 (덜 위급해 보이게)
        marker.stroke.Color = Color3.fromRGB(255, 160, 60)
        marker.icon.TextColor3 = Color3.fromRGB(255, 180, 100)
    end
end

local function removeEdgeMarker(character)
    local m = edgeMarkers[character]
    if not m then return end
    if m.frame then m.frame:Destroy() end
    edgeMarkers[character] = nil
end

-- ─────────────────────────────────────────────────────────────
-- 화면 위치 계산 (월드 → 스크린 좌표 + 가장자리 클램프)
-- ─────────────────────────────────────────────────────────────
local function worldToScreenWithEdgeClamp(worldPos)
    local camera = workspace.CurrentCamera
    if not camera then return nil end

    local screenPos, onScreen = camera:WorldToViewportPoint(worldPos)
    local viewSize = camera.ViewportSize
    local margin = 60  -- 화면 가장자리에서 들어올 여백

    if onScreen and screenPos.Z > 0 then
        -- 화면 안: 그대로 표시 (단, 가장자리 근처면 살짝 안쪽으로)
        local x = math.clamp(screenPos.X, margin, viewSize.X - margin)
        local y = math.clamp(screenPos.Y, margin, viewSize.Y - margin)
        return Vector2.new(x, y), true  -- 두 번째 값: 화면 안 여부
    else
        -- 화면 밖 또는 뒤쪽: 가장자리에 클램프
        local centerX = viewSize.X / 2
        local centerY = viewSize.Y / 2
        local dx = screenPos.X - centerX
        local dy = screenPos.Y - centerY

        -- Z < 0 (카메라 뒤)면 방향 반전
        if screenPos.Z <= 0 then
            dx = -dx
            dy = -dy
        end

        if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then
            return Vector2.new(centerX, margin), false
        end

        -- 화면 사각형 가장자리에 닿는 지점 계산
        local scaleX = (viewSize.X / 2 - margin) / math.abs(dx)
        local scaleY = (viewSize.Y / 2 - margin) / math.abs(dy)
        local scale = math.min(scaleX, scaleY)

        local edgeX = centerX + dx * scale
        local edgeY = centerY + dy * scale
        return Vector2.new(edgeX, edgeY), false
    end
end

-- ─────────────────────────────────────────────────────────────
-- 도움 요청 사운드 재생 (다운자 위치에서 3D 공간 사운드)
-- 모든 클라이언트가 자기 위치에 따라 거리감 있는 볼륨으로 들음.
-- 부모를 HumanoidRootPart로 하여 캐릭터 이동 시에도 위치가 따라감.
-- ─────────────────────────────────────────────────────────────
local function playSosSound(character)
    if not character or not character.Parent then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local sound = Instance.new("Sound")
    sound.Name = "SosCry"
    sound.SoundId = SOS_SOUND_ID
    sound.Volume = SOS_SOUND_VOLUME
    sound.RollOffMode = Enum.RollOffMode.InverseTapered
    sound.RollOffMaxDistance = SOS_SOUND_MAX_DIST
    sound.RollOffMinDistance = SOS_SOUND_MIN_DIST
    sound.Parent = hrp
    sound:Play()

    -- 재생 종료 시 자동 정리 (메모리 누수 방지)
    sound.Ended:Connect(function()
        sound:Destroy()
    end)
    -- 안전망: 10초 후 강제 정리 (Ended가 안 발생하는 경우 대비)
    task.delay(10, function()
        if sound and sound.Parent then sound:Destroy() end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- 다운된 캐릭터 추적 (자동 마커 + 머리 아이콘 관리)
-- ─────────────────────────────────────────────────────────────
local downedCharacters = {}  -- character -> true (다운 상태)
local sosActiveCharacters = {}  -- character -> true (SOS 보낸 다운자)
local sosCooldownActive = false  -- 본인 SOS 쿨다운 진행 중 여부 (버튼 비활성화 표시용)

-- 다운/SOS 이벤트 처리
downStateEvent.OnClientEvent:Connect(function(eventType, character)
    if eventType == "character_downed" and character then
        downedCharacters[character] = true
        createHeadIcon(character)
        updateHeadIconState(character, false)
    elseif eventType == "character_died" or eventType == "character_revived" then
        if character then
            downedCharacters[character] = nil
            sosActiveCharacters[character] = nil
            removeHeadIcon(character)
            removeEdgeMarker(character)
        end
    elseif eventType == "downed" then
        -- 본인 다운 (DownClient가 다른 처리 담당, 여기선 머리 아이콘만)
        local char = localPlayer.Character
        if char then
            downedCharacters[char] = true
            createHeadIcon(char)
            updateHeadIconState(char, false)
        end
    elseif eventType == "died" or eventType == "revived" then
        local char = localPlayer.Character
        if char then
            downedCharacters[char] = nil
            sosActiveCharacters[char] = nil
            removeHeadIcon(char)
            removeEdgeMarker(char)
        end
        -- 다운 종료 시 쿨다운 상태도 리셋 (다음 다운 시 깔끔한 상태로 시작)
        sosCooldownActive = false
    end
end)

sosStateEvent.OnClientEvent:Connect(function(eventType, character)
    if eventType == "sos_activated" and character then
        sosActiveCharacters[character] = true
        updateHeadIconState(character, true)
        -- 태거에게는 SOS 사운드 차단 (정보 비대칭 — 위치 노출 방지)
        if localPlayer:GetAttribute("Role") ~= "Tagger" then
            playSosSound(character)
        end
        -- 본인이라면 쿨다운 시작 (서버 SOS_COOLDOWN과 동일 — 3초)
        if character == localPlayer.Character then
            sosCooldownActive = true
        end
    elseif eventType == "sos_cleared" and character then
        sosActiveCharacters[character] = nil
        if downedCharacters[character] then
            updateHeadIconState(character, false)
        end
    elseif eventType == "cooldown_ended" then
        -- 쿨다운 종료 알림 (본인에게만 발신됨)
        sosCooldownActive = false
    end
end)

-- ─────────────────────────────────────────────────────────────
-- 바닥 방향 화살표
-- SOS 활성된 다운자가 있으면 본인 발 앞에 화살표를 띄워 그 방향을 가리킴.
-- 가장 가까운 SOS 다운자 한 명만 표시 (다중 화살표는 오히려 혼란).
--
-- ReplicatedStorage의 "arrow sign" 모델을 템플릿으로 사용 (게임에 직접 보이지 않음).
-- 모델의 +Z 방향(LookVector) = 화살촉이 가리키는 방향.
-- ─────────────────────────────────────────────────────────────
local ARROW_TEMPLATE_NAME = "arrow sign"
local ARROW_SCALE = 0.4   -- 원본 모델이 너무 큼 (11.25×7.5) → 0.4배로 축소

local groundArrow = nil  -- 클라이언트 측 화살표 모델 사본

local function createGroundArrow()
    if groundArrow and groundArrow.Parent then return groundArrow end

    -- ReplicatedStorage의 arrow sign 모델을 템플릿으로 사용
    -- (ReplicatedStorage에 두면 게임에 직접 보이지 않으면서 클라이언트에서 접근 가능)
    local template = ReplicatedStorage:FindFirstChild(ARROW_TEMPLATE_NAME)
    if not template then
        warn("[SosClient] ReplicatedStorage에 '" .. ARROW_TEMPLATE_NAME .. "' 모델이 없음")
        return nil
    end

    -- 복제하여 클라이언트 전용 사본 생성
    local arrow = template:Clone()
    arrow.Name = "SosGroundArrow_Local"

    -- 모든 Part: 충돌 비활성, 발광, 살짝 투명
    for _, part in ipairs(arrow:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = true
            part.CanCollide = false
            part.CanQuery = false
            part.CanTouch = false
            part.Material = Enum.Material.Neon
            part.Transparency = 0.2
        end
    end

    -- 모델의 BoundingBox를 기준으로 모든 Part를 BoundingBox 중심 + ARROW_SCALE 배율로 재배치.
    -- 이렇게 하면 Part들의 상대 위치는 유지되면서 모델 전체가 축소됨.
    local origCFrame, origSize = arrow:GetBoundingBox()
    local origCenter = origCFrame.Position

    for _, part in ipairs(arrow:GetDescendants()) do
        if part:IsA("BasePart") then
            -- BoundingBox 중심으로부터의 상대 위치를 ARROW_SCALE 배율로 축소
            local rel = part.Position - origCenter
            part.Position = origCenter + rel * ARROW_SCALE
            -- 크기도 같은 비율로 축소
            part.Size = part.Size * ARROW_SCALE
        end
    end

    -- 보이지 않는 기준 Part 추가 (PrimaryPart 용도).
    -- 모델 안의 body, wedge 등이 자체 회전을 가지고 있어서 이를 PrimaryPart로 쓰면
    -- PivotTo 시 의도치 않은 회전이 적용됨. 새 Part를 회전 없이 만들어서 기준으로 사용.
    -- 이 기준 Part의 +Z 방향 = 화살촉 방향이 되도록 명시적으로 정렬.
    local anchor = Instance.new("Part")
    anchor.Name = "ArrowAnchor"
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.Transparency = 1
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Anchored = true
    -- 위치: 축소 후 BoundingBox 중심 (Y=원본 그대로 유지 위함이라 그대로 origCenter 사용)
    anchor.CFrame = CFrame.new(origCenter)
    anchor.Parent = arrow
    arrow.PrimaryPart = anchor

    arrow.Parent = workspace
    groundArrow = arrow
    return arrow
end

local function removeGroundArrow()
    if groundArrow then
        groundArrow:Destroy()
        groundArrow = nil
    end
end

local function setArrowColor(arrow, color)
    for _, part in ipairs(arrow:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Color = color
        end
    end
end

local function updateGroundArrow()
    local myChar = localPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

    -- 본인이 다운 중이거나 태거면 화살표 안 보임
    if not myRoot or (myChar and myChar:GetAttribute("Downed")) then
        removeGroundArrow()
        return
    end
    if localPlayer:GetAttribute("Role") == "Tagger" then
        removeGroundArrow()
        return
    end

    -- SOS 활성된 다운자 중 가장 가까운 한 명 찾기
    local closestChar, closestDist = nil, math.huge
    for char, _ in pairs(sosActiveCharacters) do
        if char and char.Parent and char ~= myChar then
            local targetRoot = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if targetRoot and hum and hum.Health > 0 then
                local dist = (myRoot.Position - targetRoot.Position).Magnitude
                if dist < closestDist then
                    closestChar = char
                    closestDist = dist
                end
            end
        end
    end

    -- 표시 조건: SOS 다운자가 있고, 너무 가까이 가지 않았을 때
    if not closestChar or closestDist < ARROW_HIDE_DISTANCE then
        removeGroundArrow()
        return
    end

    local arrow = createGroundArrow()
    if not arrow then return end

    local targetRoot = closestChar:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        removeGroundArrow()
        return
    end

    -- 본인 위치에서 다운자 방향 (Y 평탄화 — 지면 평면에만)
    local myPos = myRoot.Position
    local targetPos = targetRoot.Position
    local direction = targetPos - myPos
    direction = Vector3.new(direction.X, 0, direction.Z)
    if direction.Magnitude < 0.01 then
        removeGroundArrow()
        return
    end
    direction = direction.Unit

    -- 화살표 위치: 본인 발 앞 ARROW_DISTANCE_FROM_PLAYER stud + 지면 위 약간
    -- 모델이 세로 방향(Y축)으로 서 있는 게 아니라, X-Z 평면에 누워있는 형태로 만들어야 함.
    -- 원본 모델은 Y축이 두께(1.875)고 X-Z가 평면 모양 → 그대로 두면 위에서 봤을 때 화살표.
    local feetY = myPos.Y - 2.5
    local arrowPos = Vector3.new(
        myPos.X + direction.X * ARROW_DISTANCE_FROM_PLAYER,
        feetY + ARROW_HEIGHT_OFFSET,
        myPos.Z + direction.Z * ARROW_DISTANCE_FROM_PLAYER
    )

    -- 회전: 화살표의 +Z(화살촉)가 direction을 향하게.
    -- CFrame.lookAt은 LookVector를 카메라처럼 -Z 방향으로 만들기 때문에,
    -- 모델의 +Z(화살촉)가 direction을 향하려면 target을 반대로 넣어야 함.
    -- (lookAt(eye, eye - direction) → -Z = -direction → +Z = direction)
    arrow:PivotTo(CFrame.lookAt(arrowPos, arrowPos - direction))

    -- 거리에 따라 색상 보간 (멀면 빨강, 가까우면 주황)
    local t = math.clamp((closestDist - ARROW_HIDE_DISTANCE) / 30, 0, 1)
    local lerpedColor = ARROW_COLOR_NEAR:Lerp(ARROW_COLOR_FAR, t)
    setArrowColor(arrow, lerpedColor)
end

-- 캐릭터 재생성 시 화살표 정리
localPlayer.CharacterAdded:Connect(function()
    removeGroundArrow()
end)

-- ─────────────────────────────────────────────────────────────
-- 메인 루프: 마커 위치 업데이트 + 근접 감지
-- ─────────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function()
    local myChar = localPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

    -- 본인이 다운 중이거나 태거면 다른 다운자 마커 숨김
    --   다운 중: 구조 받는 입장이라 정보 불필요
    --   태거: 정보 비대칭 보장 (다운자 위치 노출 시 캠핑 메타로 변질)
    local imDowned = myChar and myChar:GetAttribute("Downed")
    local imTagger = localPlayer:GetAttribute("Role") == "Tagger"
    local hideMarkers = imDowned or imTagger

    -- ⚠️ 마커 개수 상한.
    --   NEARBY_RADIUS 를 맵 전역(900)으로 넓히면서, 봇 10마리가 동시에 다운되면
    --   80px 마커가 10개까지 뜰 수 있다(772 폭 화면에서 가로를 뒤덮는다).
    --   가까운 순으로 정렬해 상위 N개만 표시한다 — 구조하러 갈 대상은 결국 가까운 쪽이다.
    local MAX_MARKERS = 3
    local allowed = nil
    if not hideMarkers and myRoot then
        local cand = {}
        for character in pairs(downedCharacters) do
            if character ~= myChar and character.Parent then
                local r = character:FindFirstChild("HumanoidRootPart")
                local h = character:FindFirstChildOfClass("Humanoid")
                if r and (not h or h.Health > 0) then
                    cand[#cand + 1] = { c = character, d = (myRoot.Position - r.Position).Magnitude }
                end
            end
        end
        table.sort(cand, function(a, b) return a.d < b.d end)
        allowed = {}
        for i = 1, math.min(#cand, MAX_MARKERS) do
            allowed[cand[i].c] = true
        end
    end

    for character, _ in pairs(downedCharacters) do
        -- 본인 캐릭터 또는 무효 캐릭터는 마커 안 띄움
        if character == myChar or not character.Parent then
            removeEdgeMarker(character)
        else
            local targetRoot = character:FindFirstChild("HumanoidRootPart")
            local hum = character:FindFirstChildOfClass("Humanoid")

            -- 죽은 캐릭터는 마커 제거
            if not targetRoot or (hum and hum.Health <= 0) then
                removeEdgeMarker(character)
            elseif hideMarkers then
                -- 본인이 다운 중이거나 태거면 모든 마커 숨김
                removeEdgeMarker(character)
            else
                local distance = myRoot and (myRoot.Position - targetRoot.Position).Magnitude or math.huge
                local isSos = sosActiveCharacters[character] == true
                local isNearby = distance <= NEARBY_RADIUS

                -- 마커 표시 조건: (SOS 활성 OR 근접) + 가까운 상위 MAX_MARKERS 이내
                local inTopN = (allowed == nil) or (allowed[character] == true)
                local shouldShow = (isSos or isNearby) and distance >= MIN_MARKER_DIST and inTopN

                if shouldShow then
                    local marker = createEdgeMarker(character)
                    -- 스타일은 SOS 우선 (둘 다 해당될 때 SOS 색깔)
                    if marker.isSos ~= isSos then
                        updateMarkerStyle(marker, isSos)
                    end

                    -- 위치 + 거리 갱신
                    local screenPos = worldToScreenWithEdgeClamp(targetRoot.Position)
                    if screenPos then
                        marker.frame.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y)
                        -- 거리 + 사망까지 남은 시간. DownEndAt 은 DownSystem 이 심는 캐릭터 속성이라
                        -- 이벤트 유실과 무관하게 항상 현재 값을 읽을 수 있다(서버 시계 기준).
                        local endAt = character:GetAttribute("DownEndAt")
                        if endAt then
                        	local left = math.max(0, endAt - workspace:GetServerTimeNow())
                        	marker.distLabel.Text = string.format("%dm · %.1fs", math.floor(distance), left)
                        	-- 3초 미만이면 붉게 — 지금 안 가면 늦는다는 신호
                        	marker.distLabel.TextColor3 = (left <= 3)
                        		and Color3.fromRGB(255, 90, 90) or Color3.fromRGB(255, 255, 255)
                        else
                        	marker.distLabel.Text = string.format("%dm", math.floor(distance))
                        	marker.distLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                        end
                    end
                else
                    removeEdgeMarker(character)
                end
            end
        end
    end

    -- 바닥 방향 화살표 갱신 (SOS 활성된 가장 가까운 다운자를 가리킴)
    updateGroundArrow()
end)

-- ─────────────────────────────────────────────────────────────
-- 입력: Q 키 또는 SOS 버튼 클릭으로 SOS 발신 (다운 상태일 때만 작동)
-- ─────────────────────────────────────────────────────────────
local function trySendSos()
    -- ⚠️ 다운이 아닐 때 Q 는 대시 키다. 여기서 조용히 반환해야 한다 —
    --   예전엔 매 Q 마다 "다운 상태 아님" 을 찍어 로그가 대시 스팸으로 덮였다.
    local char = localPlayer.Character
    if not char then return end
    if not char:GetAttribute("Downed") then return end
    print("[SosClient] SOS 요청 전송")
    sosRequestEvent:FireServer()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == SOS_KEY then
        if gameProcessed then return end
        trySendSos()
    end
end)

-- ─────────────────────────────────────────────────────────────
-- SOS 버튼 UI (다운 상태일 때만 표시, 클릭으로 발신)
-- ─────────────────────────────────────────────────────────────
local sosButtonGui = nil
local sosButton = nil

local function createSosButton()
    if sosButtonGui then return end

    sosButtonGui = Instance.new("ScreenGui")
    sosButtonGui.Name = "SosButtonGui"
    sosButtonGui.ResetOnSpawn = false
    sosButtonGui.IgnoreGuiInset = true
    sosButtonGui.Enabled = false  -- 기본 숨김
    sosButtonGui.Parent = localPlayer:WaitForChild("PlayerGui")

    sosButton = Instance.new("TextButton")
    sosButton.Name = "SosButton"
    -- 모바일에서는 다운 UI 와 함께 압축·하단 밀착 (캐릭터 가림 방지)
	local _sosScaler = require(game:GetService("ReplicatedStorage"):WaitForChild("ResponsiveScaler"))
	local _sosMobile = _sosScaler.isMobile()
	local SOS_W = _sosMobile and 130 or 170
	local SOS_H = _sosMobile and 36 or 44
	local DOWN_Y = _sosMobile and 0.97 or 0.90   -- DownClient.BOX_Y 와 동일
	local DOWN_H = _sosMobile and 52 or 80       -- DownClient.BOX_H 와 동일
	sosButton.AnchorPoint = Vector2.new(0.5, 1)
    -- ⚠️ 다운 UI(DownClient: anchor 0.5,1 / pos 0.5,0.85 / 높이 80) 바로 위에 붙인다.
	-- 기존 0.7 비율 배치는 화면이 작을수록 다운 UI 와 겹쳤다(772x360 에서 56px 겹침).
	-- 다운 UI 상단(0.85H-80) 에서 12px 위 = offset -92. 해상도와 무관하게 간격 유지.
	sosButton.Position = UDim2.new(0.5, 0, DOWN_Y, -(DOWN_H + 10))  -- 다운 타이머 UI 위쪽
    sosButton.Size = UDim2.new(0, SOS_W, 0, SOS_H)
    sosButton.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
    sosButton.BorderSizePixel = 0
    sosButton.Text = "SOS - Call for help (Q)"  -- 초기 텍스트, 상태에 따라 동적 변경
    sosButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    sosButton.TextSize = _sosMobile and 14 or 17
    sosButton.Font = Enum.Font.GothamBold
    sosButton.AutoButtonColor = true
    sosButton.Parent = sosButtonGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = sosButton

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 200, 200)
    stroke.Thickness = 2
    stroke.Parent = sosButton

    sosButton.Activated:Connect(function()
        print("[SosClient] SOS 버튼 클릭")
        trySendSos()
    end)
end

local function updateSosButtonVisibility()
    if not sosButtonGui then createSosButton() end
    local char = localPlayer.Character
    local isDowned = char and char:GetAttribute("Downed")
    sosButtonGui.Enabled = isDowned == true

    -- 버튼 시각 상태:
    --   1. 발신 가능: 빨강 + "SOS - Call for help (Q)"
    --   2. SOS 활성 또는 쿨다운: 검정 + "Calling for help..." (입력 무시 상태)
    if sosButton and char then
        local isSosActive = sosActiveCharacters[char] == true
        local isOnCooldown = sosCooldownActive
        local isUnavailable = isSosActive or isOnCooldown

        if isUnavailable then
            sosButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
            sosButton.Text = "Calling for help..."
            sosButton.AutoButtonColor = false
        else
            sosButton.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
            sosButton.Text = "SOS - Call for help (Q)"
            sosButton.AutoButtonColor = true
        end
    end
end

-- 다운/SOS 상태 변경 시마다 버튼 갱신
RunService.Heartbeat:Connect(updateSosButtonVisibility)

-- 초기 생성
createSosButton()

-- 캐릭터 재생성 시 정리
localPlayer.CharacterAdded:Connect(function()
    -- 모든 자기 마커 제거
    for char, _ in pairs(downedCharacters) do
        if not char.Parent then
            downedCharacters[char] = nil
            sosActiveCharacters[char] = nil
            removeHeadIcon(char)
            removeEdgeMarker(char)
        end
    end
end)

print("✅ SosClient 활성화 (Q 또는 클릭으로 SOS, 근접 감지", NEARBY_RADIUS, "stud)")
