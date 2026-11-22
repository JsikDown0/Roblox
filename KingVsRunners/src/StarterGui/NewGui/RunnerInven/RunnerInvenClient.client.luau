local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- ── 모바일 대응 UIScale + 노치 회피 ────────────────────────────
do
	local _gui = script.Parent
	pcall(function() _gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
	local _camera = workspace.CurrentCamera
	local _uiScale = _gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", _gui)
	local _BASE_W, _BASE_H = 1280, 720
	local function _update()
		local vp = _camera.ViewportSize
		local s = math.min((vp.X * 0.85) / _BASE_W, (vp.Y * 0.85) / _BASE_H, 1)
		_uiScale.Scale = math.max(s, 0.55)
	end
	_camera:GetPropertyChangedSignal("ViewportSize"):Connect(_update)
	_update()
end

local player = Players.LocalPlayer

local runnerInvenGui = script.Parent
local canvas         = runnerInvenGui:WaitForChild("Canvas")
local main           = canvas:WaitForChild("Main")
local switchicon     = runnerInvenGui:WaitForChild("Switchicon")
local container      = main:WaitForChild("Container")
local tooltip        = main:WaitForChild("Tooltip")
local tooltipMain    = tooltip:WaitForChild("Main")
local closeBtn       = main:WaitForChild("Close")

local checkmarkSource = runnerInvenGui:FindFirstChild("checkmark")
if checkmarkSource then checkmarkSource.Visible = false end

canvas.Visible     = false
switchicon.Visible = false

local getRunnerLoadout = ReplicatedStorage:WaitForChild("GetRunnerLoadout")
local setRunnerLoadout   = ReplicatedStorage:WaitForChild("SetRunnerLoadout")
local useConsumableEvent = ReplicatedStorage:WaitForChild("UseConsumableEvent")

-- ── 레어리티 색상 ─────────────────────────────────────────────
local rarityColors = {
    Normal    = Color3.fromRGB(200, 200, 200),
    Uncommon  = Color3.fromRGB(80,  200, 80),
    Rare      = Color3.fromRGB(80,  140, 230),
    Epic      = Color3.fromRGB(160, 80,  220),
    Legendary = Color3.fromRGB(255, 160, 0),
}
local rarityGradient = {
    Normal    = ColorSequence.new(Color3.fromRGB(180, 180, 180), Color3.fromRGB(255, 255, 255)),
    Rare      = ColorSequence.new(Color3.fromRGB(40,  160, 40),  Color3.fromRGB(120, 255, 120)),
    Epic      = ColorSequence.new(Color3.fromRGB(120, 40,  200), Color3.fromRGB(200, 120, 255)),
    Legendary = ColorSequence.new({
        ColorSequenceKeypoint.new(0,    Color3.fromRGB(255, 200, 0)),
        ColorSequenceKeypoint.new(0.5,  Color3.fromRGB(255, 130, 0)),
        ColorSequenceKeypoint.new(1,    Color3.fromRGB(255, 200, 0)),
    }),
}
local LOCKED_GRADIENT = ColorSequence.new(Color3.fromRGB(60, 60, 60), Color3.fromRGB(100, 100, 100))

local GREEN_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    Color3.fromRGB(68,  68,  195)),
    ColorSequenceKeypoint.new(0.21, Color3.fromRGB(0,   255, 0)),
    ColorSequenceKeypoint.new(0.92, Color3.fromRGB(133, 236, 95)),
    ColorSequenceKeypoint.new(1,    Color3.fromRGB(0,   255, 0)),
})
local RED_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    Color3.fromRGB(120, 20,  20)),
    ColorSequenceKeypoint.new(0.21, Color3.fromRGB(220, 40,  40)),
    ColorSequenceKeypoint.new(0.92, Color3.fromRGB(255, 80,  80)),
    ColorSequenceKeypoint.new(1,    Color3.fromRGB(200, 30,  30)),
})

local equippedItems      = {}
local templateMap        = {}
local currentTooltipItem = nil
local consumables        = {}  -- { ["Speed Potion"] = 1, ... }

-- ── 경고 UI ──────────────────────────────────────────────────
local oldWarning = main:FindFirstChild("_EquipWarning")
if oldWarning then oldWarning:Destroy() end

local warningTween  = nil
local warningThread = nil

local warningFrame = Instance.new("Frame")
warningFrame.Name = "_EquipWarning"
warningFrame.Size = UDim2.new(0.75, 0, 0, 60)
warningFrame.AnchorPoint = Vector2.new(0.5, 0)
warningFrame.Position = UDim2.new(0.5, 0, 0, 8)
warningFrame.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
warningFrame.BackgroundTransparency = 0.1
warningFrame.ZIndex = 20
warningFrame.Visible = false
warningFrame.Parent = main
Instance.new("UICorner", warningFrame).CornerRadius = UDim.new(0, 10)
local st = Instance.new("UIStroke", warningFrame)
st.Color = Color3.fromRGB(255, 100, 100); st.Thickness = 2
local warnIcon = Instance.new("TextLabel", warningFrame)
warnIcon.Name = "_WarnIcon"
warnIcon.Size = UDim2.new(0, 40, 1, 0)
warnIcon.Position = UDim2.new(0, 8, 0, 0)
warnIcon.BackgroundTransparency = 1
warnIcon.Text = "⚠️"
warnIcon.TextSize = 20
warnIcon.Font = Enum.Font.GothamBold
warnIcon.ZIndex = 21
local warningLabel = Instance.new("TextLabel", warningFrame)
warningLabel.Name = "_WarnMsg"
warningLabel.Size = UDim2.new(1, -56, 1, 0)
warningLabel.Position = UDim2.new(0, 48, 0, 0)
warningLabel.BackgroundTransparency = 1
warningLabel.Text = ""
warningLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
warningLabel.TextSize = 15
warningLabel.TextXAlignment = Enum.TextXAlignment.Left
warningLabel.Font = Enum.Font.GothamBold
warningLabel.ZIndex = 21

local function showEquipWarning(msg)
    if warningLabel then warningLabel.Text = msg or "Max 4 items can be equipped!" end
    if warningTween  then warningTween:Cancel() end
    if warningThread then task.cancel(warningThread) end
    warningFrame.BackgroundTransparency = 0.1
    warningFrame.Visible = true
    warningThread = task.delay(1.5, function()
        warningTween = TweenService:Create(warningFrame,
            TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 1})
        warningTween:Play()
        warningTween.Completed:Connect(function()
            warningFrame.Visible = false
            warningFrame.BackgroundTransparency = 0.1
        end)
    end)
end

-- ── Tooltip 요소 ─────────────────────────────────────────────
local tooltipNameLabel, tooltipRarityLabel
local tidx = 0
for _, c in ipairs(tooltipMain:GetChildren()) do
    if c:IsA("TextLabel") then
        tidx += 1
        if tidx == 1 then tooltipNameLabel   = c end
        if tidx == 2 then tooltipRarityLabel = c end
    end
end

local tooltipEquip  = tooltipMain:FindFirstChild("Equip")
local tooltipSkin   = tooltipMain:FindFirstChild("Skin")
local tooltipClose2 = tooltipMain:FindFirstChild("Close2")
local equipTextLabel = tooltipEquip and tooltipEquip:FindFirstChildWhichIsA("TextLabel")
local equipGradient  = tooltipEquip and tooltipEquip:FindFirstChildWhichIsA("UIGradient")

local function equippedCount()
    local n = 0
    for _ in pairs(equippedItems) do n += 1 end
    return n
end

local bottomEquipBtn   = main:FindFirstChild("Equip")
local bottomEquipLabel = bottomEquipBtn
    and bottomEquipBtn:FindFirstChild("Main")
    and bottomEquipBtn.Main:FindFirstChildWhichIsA("TextLabel")

local function refreshBottomEquip()
    if bottomEquipLabel then
        bottomEquipLabel.Text = string.format("Equip (%d/4)", equippedCount())
    end
end

-- ── 체크마크 ─────────────────────────────────────────────────
local function ensureCheckMark(template)
    if template:FindFirstChild("_CheckMark") then return end
    local check
    if checkmarkSource then
        check = checkmarkSource:Clone()
    else
        check = Instance.new("TextLabel")
        check.BackgroundColor3       = Color3.fromRGB(30, 170, 60)
        check.BackgroundTransparency = 0
        check.Text                   = "✔"
        check.TextColor3             = Color3.fromRGB(255, 255, 255)
        check.TextScaled             = true
        check.Font                   = Enum.Font.GothamBold
        Instance.new("UICorner", check).CornerRadius = UDim.new(0.3, 0)
    end
    check.Name        = "_CheckMark"
    check.Size        = UDim2.new(0.35, 0, 0.35, 0)
    check.AnchorPoint = Vector2.new(1, 1)
    check.Position    = UDim2.new(1, 0, 1, 0)
    check.ZIndex      = 4
    check.Visible     = false
    check.Parent      = template
end

local function saveLoadout()
    local list = {}
    for name in pairs(equippedItems) do table.insert(list, name) end
    setRunnerLoadout:FireServer(list)
    print("✅ 러너 로드아웃 저장:", table.concat(list, ", "))
end

local function refreshCheckMarks()
    for template, itemData in pairs(templateMap) do
        local check = template:FindFirstChild("_CheckMark")
        if check then
            check.Visible = equippedItems[itemData.name] == true
        end
    end
end

local function refreshTooltipButtons()
    if not currentTooltipItem then return end
    local isEquipped = equippedItems[currentTooltipItem.name] == true
    if equipTextLabel then equipTextLabel.Text = isEquipped and "Unequip" or "Equip" end
    if equipGradient  then equipGradient.Color = isEquipped and RED_GRADIENT or GREEN_GRADIENT end
end

local function showTooltip(itemData, isLocked, fromTemplate)
    currentTooltipItem = itemData
    if tooltipNameLabel  then tooltipNameLabel.Text  = itemData.displayName or itemData.name end
    if tooltipRarityLabel then
        tooltipRarityLabel.Text = itemData.rarity or ""
        local rColor = {
            Normal    = Color3.fromHex("#9d9d9d"),
            Rare      = Color3.fromHex("#4cd964"),
            Epic      = Color3.fromHex("#b44fff"),
            Legendary = Color3.fromHex("#ffd700"),
        }
        tooltipRarityLabel.TextColor3 = rColor[itemData.rarity] or Color3.fromHex("#9d9d9d")
    end
    if tooltipEquip then tooltipEquip.Visible = not isLocked end
    if tooltipSkin  then tooltipSkin.Visible  = false end  -- 러너는 스킨 없음
    refreshTooltipButtons()

    if fromTemplate then
        local mainAbs  = main.AbsolutePosition
        local mainSize = main.AbsoluteSize
        local tAbs     = fromTemplate.AbsolutePosition
        local tSize    = fromTemplate.AbsoluteSize
        local tipSize  = tooltip.AbsoluteSize

        local slotCenterX = (tAbs.X - mainAbs.X + tSize.X * 0.5) / mainSize.X
        local slotCenterY = (tAbs.Y - mainAbs.Y + tSize.Y * 0.5) / mainSize.Y
        local slotW = tSize.X / mainSize.X
        local tipW  = tipSize.X / mainSize.X
        local tipH  = tipSize.Y / mainSize.Y

        local posX = slotCenterX + slotW * 0.5 - tipW * 0.55
        if posX + tipW > 1.0 then
            posX = slotCenterX - slotW * 0.5 - tipW * 0.45
        end
        local posY = math.clamp(slotCenterY, 0.02, 1 - tipH - 0.02)

        tooltip.Position    = UDim2.new(posX, 0, posY, 0)
        tooltip.AnchorPoint = Vector2.new(0, 0)
    end

    tooltip.Visible = true
end

if tooltipEquip then
    tooltipEquip.MouseButton1Click:Connect(function()
        if not currentTooltipItem then return end
        local name = currentTooltipItem.name
        -- 소모품(Wood Shield 등): 사용 이벤트 발사
        if currentTooltipItem.consumable then
            useConsumableEvent:FireServer(name)
            tooltip.Visible = false
            currentTooltipItem = nil
            return
        end
        if equippedItems[name] then
            equippedItems[name] = nil
        else
            if equippedCount() >= 4 then
                showEquipWarning()
                return
            end
            equippedItems[name] = true
        end
        saveLoadout()
        refreshCheckMarks()
        refreshTooltipButtons()
        refreshBottomEquip()
    end)
end



-- _G.ownedOnlyState 로 Tagger/Runner 간 공유
local function getOwned() return _G.ownedOnlyState == true end
local function setOwned(v) _G.ownedOnlyState = v end

local cachedAllItems = nil

local toggleFrame = main:FindFirstChild("_OwnedToggle")
local toggleFill  = toggleFrame and toggleFrame:FindFirstChild("_Fill")
local lblAll      = toggleFrame and toggleFrame:FindFirstChild("_LblAll")
local lblOwned    = toggleFrame and toggleFrame:FindFirstChild("_LblOwned")
local toggleBtn   = toggleFrame and toggleFrame:FindFirstChild("_ToggleBtn")

-- 모바일 대응: Scale 기반으로 크기 재설정
if toggleFrame then
	toggleFrame.Size     = UDim2.new(0.18, 0, 0.09, 0)
	toggleFrame.Position = UDim2.new(0.75, 0, 0.095, 0)
	if lblAll   then lblAll.TextScaled = true; lblAll.Text   = "All"   end
	if lblOwned then lblOwned.TextScaled = true; lblOwned.Text = "Owned" end
end

local TWEEN_TOGGLE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function applyToggleVisual()
	if not toggleFill then return end
	local owned = getOwned()
	local targetPos = owned and UDim2.new(0.5, 0, 0, 0) or UDim2.new(0, 0, 0, 0)
	TweenService:Create(toggleFill, TWEEN_TOGGLE, {Position = targetPos}):Play()
	toggleFill.BackgroundColor3 = owned and Color3.fromRGB(50, 160, 255) or Color3.fromRGB(80, 80, 80)
	if lblAll   then lblAll.TextColor3   = owned and Color3.fromRGB(180,180,180) or Color3.fromRGB(255,255,255) end
	if lblOwned then lblOwned.TextColor3 = owned and Color3.fromRGB(255,255,255) or Color3.fromRGB(180,180,180) end
end

-- 슬롯 채우기 ──────────────────────────────────────────────────
local function populateSlots(allItems)
	local displayItems = allItems
	if getOwned() then
		displayItems = {}
		for _, item in ipairs(allItems) do
			if not item.locked then
				table.insert(displayItems, item)
			end
		end
	end
    local templates = {}
    for _, c in ipairs(container:GetChildren()) do
        if c:IsA("Frame") and c.Name == "Template" then
            table.insert(templates, c)
        end
    end
    templateMap = {}

    for i, template in ipairs(templates) do
        local itemData  = displayItems[i]
        local mainFrame = template:FindFirstChild("Main")

        local old = template:FindFirstChild("_ClickBtn")
        if old then old:Destroy() end
        local oldCheck = template:FindFirstChild("_CheckMark")
        if oldCheck then oldCheck:Destroy() end

        ensureCheckMark(template)

        -- 아이템 없는 슬롯은 숨김 처리
        if not itemData then
            template.Visible = false
        else
            template.Visible = true
            templateMap[template] = itemData

            if mainFrame then
                local tIdx = 0
                for _, c in ipairs(mainFrame:GetChildren()) do
                    if c:IsA("TextLabel") then
                        tIdx += 1
                        if     tIdx == 1 then c.Text = "Lv 1"
                        elseif tIdx == 2 then c.Text = itemData.displayName or itemData.name
                        end
                    end
                end
            end

            local isLocked = itemData.locked

            local lockedFrame = template:FindFirstChild("Locked")
            if lockedFrame then lockedFrame.Visible = isLocked end

            local strokeFrame = template:FindFirstChild("Stroke")
            if strokeFrame then
                local uistroke = strokeFrame:FindFirstChildWhichIsA("UIStroke")
                if uistroke then
                    local grad = uistroke:FindFirstChildWhichIsA("UIGradient")
                    if grad then
                        grad.Color = isLocked and LOCKED_GRADIENT or (rarityGradient[itemData.rarity] or rarityGradient.Normal)
                    end
                end
                -- 아이콘 이미지 설정
                local iconLabel = strokeFrame:FindFirstChildWhichIsA("ImageLabel")
                local glow = mainFrame and mainFrame:FindFirstChild("Glow")
                if not isLocked then
                    if itemData.icon and itemData.icon ~= "" then
                        -- 에셋 아이콘 사용 (기존 방식)
                        if glow and iconLabel then
                            glow.Image             = itemData.icon
                            glow.ImageTransparency = 0
                            glow.Size              = UDim2.new(0.72, 0, 0.72, 0)
                            glow.Position          = UDim2.new(0.5, 0, 0.46, 0)
                            glow.AnchorPoint       = Vector2.new(0.5, 0.5)
                            glow.ScaleType         = Enum.ScaleType.Fit
                            iconLabel.Visible      = false
                        end
                    else
                        -- ViewportFrame 3D 미리보기 fallback
                        if iconLabel then iconLabel.Visible = false end
                        if glow then glow.ImageTransparency = 1 end
                        local previewFolder = game:GetService("ReplicatedStorage"):FindFirstChild("RunnerItemPreviews")
                        local previewModel  = previewFolder and previewFolder:FindFirstChild(itemData.name)
                        if previewModel and not strokeFrame:FindFirstChild("_ItemVP") then
                            local vp = Instance.new("ViewportFrame")
                            vp.Name                 = "_ItemVP"
                            vp.Size                 = UDim2.new(0.88, 0, 0.88, 0)
                            vp.AnchorPoint          = Vector2.new(0.5, 0.5)
                            vp.Position             = UDim2.new(0.5, 0, 0.5, 0)
                            vp.BackgroundTransparency = 1
                            vp.LightDirection       = Vector3.new(-1, -2, -1)
                            vp.LightColor           = Color3.new(1, 1, 1)
                            vp.Ambient              = Color3.fromRGB(120, 120, 160)
                            vp.ZIndex               = iconLabel and iconLabel.ZIndex or 2
                            vp.Parent               = strokeFrame

                            local clone = previewModel:Clone()
                            clone.Parent = vp

                            local cam = Instance.new("Camera")
                            cam.FieldOfView = 35
                            cam.Parent      = vp
                            vp.CurrentCamera = cam

                            local cf, size
                            if clone:IsA("Model") then cf, size = clone:GetBoundingBox() else cf, size = clone.CFrame, clone.Size end
                            local maxDim = math.max(size.X, size.Y, size.Z)
                            local dist   = maxDim * 2.8
                            cam.CFrame = CFrame.new(
                                cf.Position + Vector3.new(dist * 0.3, dist * 0.25, dist),
                                cf.Position
                            )
                        end
                    end
                end
            end

            local capturedItem   = itemData
            local capturedLocked = isLocked

            -- ── 소모품 수량 배지 ────────────────────────────────────
            local oldBadge = template:FindFirstChild("_CountBadge")
            if oldBadge then oldBadge:Destroy() end
            if itemData.consumable then
                local count = consumables[itemData.name] or 0
                local badge = Instance.new("TextLabel")
                badge.Name              = "_CountBadge"
                badge.Size              = UDim2.new(0.38, 0, 0.28, 0)
                badge.AnchorPoint       = Vector2.new(1, 0)
                badge.Position          = UDim2.new(1, -2, 0, 3)
                badge.BackgroundColor3  = Color3.fromRGB(20, 20, 20)
                badge.BackgroundTransparency = 0.15
                badge.TextColor3        = count > 0 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 80, 80)
                badge.Text              = "×" .. count
                badge.TextScaled        = true
                badge.Font              = Enum.Font.GothamBold
                badge.ZIndex            = 5
                badge.Parent            = template
                Instance.new("UICorner", badge).CornerRadius = UDim.new(0.3, 0)
            end
            local clickBtn = Instance.new("TextButton")
            clickBtn.Name               = "_ClickBtn"
            clickBtn.Size               = UDim2.new(1, 0, 1, 0)
            clickBtn.BackgroundTransparency = 1
            clickBtn.Text               = ""
            clickBtn.ZIndex             = 3
            clickBtn.Parent             = template
            clickBtn.MouseButton1Click:Connect(function()
                if capturedLocked then return end
                showTooltip(capturedItem, capturedLocked, template)
            end)
        end
    end

    refreshCheckMarks()
    refreshBottomEquip()
end

local function loadData()
    local data = getRunnerLoadout:InvokeServer()
    if not data or not data.allItems then
        warn("RunnerInvenClient: 데이터 로드 실패")
        return
    end
    equippedItems = {}
    for _, name in ipairs(data.loadout or {}) do
        equippedItems[name] = true
    end
    consumables = data.consumables or {}
    cachedAllItems = data.allItems
    applyToggleVisual()
    populateSlots(cachedAllItems)
end

-- 토글 버튼 클릭 연결
if toggleBtn then
	toggleBtn.MouseButton1Click:Connect(function()
		setOwned(not getOwned())
		applyToggleVisual()
		if _G.syncTaggerToggle then _G.syncTaggerToggle() end  -- Tagger 비주얼 동기화
		if cachedAllItems then
			tooltip.Visible    = false
			currentTooltipItem = nil
			populateSlots(cachedAllItems)
		end
	end)
end

-- 외부에서 Runner 비주얼 동기화용
_G.syncRunnerToggle = applyToggleVisual

-- ── 열기 / 닫기 ──────────────────────────────────────────────
local function openInven()
    tooltip.Visible    = false
    currentTooltipItem = nil
    canvas.Visible     = true
    switchicon.Visible = true
    loadData()
end

local function closeInven()
    canvas.Visible     = false
    switchicon.Visible = false
    tooltip.Visible    = false
    currentTooltipItem = nil
    if warningThread then task.cancel(warningThread) end
    if warningFrame  then warningFrame.Visible = false end
    -- TaggerInven switchicon + Blue_Glow도 정리
    local pg = player:FindFirstChild("PlayerGui")
    local newGui = pg and pg:FindFirstChild("NewGui")
    local taggerInven = newGui and newGui:FindFirstChild("TaggerInven")
    if taggerInven then
        local tSw = taggerInven:FindFirstChild("Switchicon")
        if tSw then tSw.Visible = false end
        local blueGlow = taggerInven:FindFirstChild("Blue_Glow")
        if blueGlow then blueGlow.Visible = false end
    end
end

_G.openRunnerInven  = openInven
_G.closeRunnerInven = closeInven

closeBtn.MouseButton1Click:Connect(closeInven)
if tooltipClose2 then
    tooltipClose2.MouseButton1Click:Connect(function()
        tooltip.Visible    = false
        currentTooltipItem = nil
    end)
end

-- ── Switchicon: Runner → Tagger 전환 ─────────────────────────
switchicon.MouseButton1Click:Connect(function()
    local pg = player:WaitForChild("PlayerGui")
    local newGui = pg:FindFirstChild("NewGui")
    local taggerInven = newGui and newGui:FindFirstChild("TaggerInven")
    if not taggerInven then return end
    local blueGlow = taggerInven:FindFirstChild("Blue_Glow")
    if blueGlow then blueGlow.Visible = false end
    canvas.Visible             = false
    switchicon.Visible         = false
    taggerInven.Canvas.Visible = true
end)

print("✅ RunnerInvenClient 준비!")
