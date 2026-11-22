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

local killeffectGui = script.Parent               -- KilleffectInven ScreenGui
local canvas        = killeffectGui:WaitForChild("Canvas")
local main          = canvas:WaitForChild("Main")
local container     = main:WaitForChild("Container")
local tooltip       = main:WaitForChild("Tooltip")
local tooltipMain   = tooltip:WaitForChild("Main")
local closeBtn      = main:WaitForChild("Close")
local switchicon    = killeffectGui:WaitForChild("Switchicon")

local checkmarkSource = killeffectGui:FindFirstChild("checkmark")
if checkmarkSource then checkmarkSource.Visible = false end

-- _G 스텁
_G.openKilleffectInven  = function() end
_G.closeKilleffectInven = function() end

-- 초기 상태
canvas.Visible = false

-- RemoteFunction / RemoteEvent
local getEffectData     = ReplicatedStorage:WaitForChild("GetEffectData")
local setEquippedEffect = ReplicatedStorage:WaitForChild("SetEquippedEffect")

-- ── 레어리티 색상 ─────────────────────────────────────────────
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

-- ── 상태 ─────────────────────────────────────────────────────
local cachedItems        = {}
local templateMap        = {}
local currentTooltipItem = nil
local equippedId         = nil

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

local function showWarning(msg)
    if warningLabel then warningLabel.Text = msg or "You don't own this item!" end
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

local tooltipEquip   = tooltipMain:FindFirstChild("Equip")
local tooltipSkin    = tooltipMain:FindFirstChild("Skin")
local tooltipClose2  = tooltipMain:FindFirstChild("Close2")
local equipTextLabel = tooltipEquip and tooltipEquip:FindFirstChildWhichIsA("TextLabel")
local equipGradient  = tooltipEquip and tooltipEquip:FindFirstChildWhichIsA("UIGradient")

if tooltipSkin then tooltipSkin.Visible = false end

-- 하단 버튼
local bottomEquipBtn   = main:FindFirstChild("Equip")
local bottomEquipLabel = bottomEquipBtn
    and bottomEquipBtn:FindFirstChild("Main")
    and bottomEquipBtn.Main:FindFirstChildWhichIsA("TextLabel")

local function refreshBottomLabel()
    if bottomEquipLabel then
        bottomEquipLabel.Text = equippedId and "1 Equipped" or "None Equipped"
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

local function refreshCheckMarks()
    for template, itemData in pairs(templateMap) do
        local check = template:FindFirstChild("_CheckMark")
        if check then
            check.Visible = (itemData.id == equippedId)
        end
    end
end

local function refreshTooltipButtons()
    if not currentTooltipItem then return end
    local isEquipped = (currentTooltipItem.id == equippedId)
    if equipTextLabel then equipTextLabel.Text = isEquipped and "Unequip" or "Equip" end
    if equipGradient  then equipGradient.Color = isEquipped and RED_GRADIENT or GREEN_GRADIENT end
end

local function showTooltip(itemData, isLocked, fromTemplate)
    currentTooltipItem = itemData

    if tooltipNameLabel  then tooltipNameLabel.Text  = (itemData.icon or "") .. "  " .. (itemData.name or "") end
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

    -- ✅ 버튼 상태를 먼저 설정 (TaggerInven 방식 — tooltip.Visible 이전에)
    if tooltipEquip then
        tooltipEquip.Visible = not isLocked
        print("🔧 tooltipEquip.Visible =", not isLocked, "| isLocked =", isLocked)
    else
        print("⚠️ tooltipEquip is nil!")
    end
    if tooltipSkin then tooltipSkin.Visible = false end
    refreshTooltipButtons()

    if fromTemplate then
        local mainAbs  = main.AbsolutePosition
        local mainSize = main.AbsoluteSize

        -- Size.Scale + AbsoluteSize 병행 사용
        local tipW = tooltip.Size.X.Scale
        local tipH = tooltip.Size.Y.Scale
        if main.AbsoluteSize.X > 0 and tooltip.AbsoluteSize.X > 0 then
            tipW = tooltip.AbsoluteSize.X / mainSize.X
            tipH = tooltip.AbsoluteSize.Y / mainSize.Y
        end

        local tAbs = fromTemplate.AbsolutePosition
        local tSize = fromTemplate.AbsoluteSize
        local slotCenterX = (tAbs.X - mainAbs.X + tSize.X * 0.5) / mainSize.X
        local slotCenterY = (tAbs.Y - mainAbs.Y + tSize.Y * 0.5) / mainSize.Y
        local slotW = tSize.X / mainSize.X

        local posX = slotCenterX + slotW * 0.5 - tipW * 0.55
        if posX + tipW > 1.0 then
            posX = slotCenterX - slotW * 0.5 - tipW * 0.45
        end
        local posY = math.clamp(slotCenterY, 0.02, 1 - tipH - 0.02)

        tooltip.Position    = UDim2.new(posX, 0, posY, 0)
        tooltip.AnchorPoint = Vector2.new(0, 0)
    end

    -- ✅ 모든 설정 완료 후 마지막에 visible (TaggerInven과 동일한 순서)
    tooltip.Visible = true
end

-- ── Tooltip Equip 버튼 클릭 ──────────────────────────────────
if tooltipEquip then
    tooltipEquip.MouseButton1Click:Connect(function()
        if not currentTooltipItem then return end
        if not currentTooltipItem.owned then
            showWarning("You don't own this item!")
            return
        end

        local id = currentTooltipItem.id
        if equippedId == id then
            equippedId = nil
        else
            equippedId = id
        end

        setEquippedEffect:FireServer("killEffect", equippedId or "none")

        for _, item in ipairs(cachedItems) do
            item.equipped = (item.id == equippedId)
        end

        refreshCheckMarks()
        refreshTooltipButtons()
        refreshBottomLabel()
        print("✅ 킬이펙트 장착:", equippedId or "없음")
    end)
end

-- ── All / Owned 토글 ─────────────────────────────────────────
local function getOwned() return _G.ownedOnlyState == true end
local function setOwned(v) _G.ownedOnlyState = v end

local toggleFrame = main:FindFirstChild("_OwnedToggle")
local toggleFill  = toggleFrame and toggleFrame:FindFirstChild("_Fill")
local lblAll      = toggleFrame and toggleFrame:FindFirstChild("_LblAll")
local lblOwned    = toggleFrame and toggleFrame:FindFirstChild("_LblOwned")
local toggleBtn   = toggleFrame and toggleFrame:FindFirstChild("_ToggleBtn")

if toggleFrame then
    toggleFrame.Size     = UDim2.new(0.18, 0, 0.09, 0)
    toggleFrame.Position = UDim2.new(0.75, 0, 0.095, 0)
    if lblAll   then lblAll.TextScaled   = true; lblAll.Text   = "All"   end
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

-- ── 슬롯 채우기 ──────────────────────────────────────────────
local function populateSlots(items)
    local templates = {}
    for _, c in ipairs(container:GetChildren()) do
        if c:IsA("Frame") and c.Name == "Template" then
            table.insert(templates, c)
        end
    end
    templateMap = {}

    if equippedId == nil then
        for _, item in ipairs(items) do
            if item.equipped then equippedId = item.id end
        end
    end

    for i, template in ipairs(templates) do
        local itemData  = items[i]
        local mainFrame = template:FindFirstChild("Main")

        local old = template:FindFirstChild("_ClickBtn")
        if old then old:Destroy() end
        local oldCheck = template:FindFirstChild("_CheckMark")
        if oldCheck then oldCheck:Destroy() end
        local oldEmoji = template:FindFirstChild("_EmojiIcon")
        if oldEmoji then oldEmoji:Destroy() end
        -- _LockOverlay는 Visible만 토글하므로 Destroy 불필요

        ensureCheckMark(template)

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
                        if     tIdx == 1 then c.Text = itemData.rarity or ""
                        elseif tIdx == 2 then c.Text = itemData.name or ""
                        end
                    end
                end
            end

            local isLocked = not itemData.owned

            -- ✅ _LockOverlay: 최초 1회만 생성, 이후 Visible만 토글 (Destroy 방식 제거)
            local lockOverlay = template:FindFirstChild("_LockOverlay")
            if not lockOverlay then
                lockOverlay = Instance.new("Frame")
                lockOverlay.Name = "_LockOverlay"
                lockOverlay.Size = UDim2.new(1, 0, 1, 0)
                lockOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                lockOverlay.BackgroundTransparency = 0.5
                lockOverlay.ZIndex = 5
                Instance.new("UICorner", lockOverlay).CornerRadius = UDim.new(0.1, 0)
                local lockIcon = Instance.new("TextLabel", lockOverlay)
                lockIcon.Size = UDim2.new(1, 0, 0.6, 0)
                lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
                lockIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
                lockIcon.BackgroundTransparency = 1
                lockIcon.Text = "🔒"
                lockIcon.TextScaled = true
                lockIcon.ZIndex = 6
                lockIcon.Parent = lockOverlay
                lockOverlay.Parent = template
            end
            lockOverlay.Visible = isLocked
            print("🔒 overlay", itemData.name, "| isLocked =", isLocked, "| Visible =", lockOverlay.Visible)

            -- ✅ 기존 Studio 템플릿의 "Locked" 프레임도 토글
            local lockedFrame = template:FindFirstChild("Locked")
            if lockedFrame then
                lockedFrame.Visible = isLocked
            end

            local strokeFrame = template:FindFirstChild("Stroke")
            if strokeFrame then
                local uistroke = strokeFrame:FindFirstChildWhichIsA("UIStroke")
                if uistroke then
                    local grad = uistroke:FindFirstChildWhichIsA("UIGradient")
                    if grad then
                        grad.Color = isLocked and LOCKED_GRADIENT or (rarityGradient[itemData.rarity] or rarityGradient.Normal)
                    end
                end

                local iconLabel = strokeFrame:FindFirstChildWhichIsA("ImageLabel")
                local glow = mainFrame and mainFrame:FindFirstChild("Glow")

                -- ✅ 소유 여부 관계없이 항상 아이콘 표시 (자물쇠는 lockedFrame이 담당)
                if itemData.imageId and itemData.imageId ~= "" then
                    if glow then
                        glow.Image             = itemData.imageId
                        glow.ImageTransparency = 0
                        glow.Size              = UDim2.new(0.72, 0, 0.72, 0)
                        glow.Position          = UDim2.new(0.5, 0, 0.46, 0)
                        glow.AnchorPoint       = Vector2.new(0.5, 0.5)
                        glow.ScaleType         = Enum.ScaleType.Fit
                        if iconLabel then iconLabel.Visible = false end
                    end
                else
                    if glow then glow.ImageTransparency = 1 end
                    if iconLabel then iconLabel.Visible = false end

                    if itemData.icon and itemData.icon ~= "" then
                        local emojiLabel = Instance.new("TextLabel")
                        emojiLabel.Name = "_EmojiIcon"
                        emojiLabel.Size = UDim2.new(0.6, 0, 0.5, 0)
                        emojiLabel.AnchorPoint = Vector2.new(0.5, 0.5)
                        emojiLabel.Position = UDim2.new(0.5, 0, 0.42, 0)
                        emojiLabel.BackgroundTransparency = 1
                        emojiLabel.Text = itemData.icon
                        emojiLabel.TextScaled = true
                        emojiLabel.ZIndex = 3  -- lockedFrame(Locked)보다 낮아서 자물쇠가 위에 보임
                        emojiLabel.Parent = template
                    end
                end
            end

            local capturedItem   = itemData
            local capturedLocked = isLocked

            local clickBtn = Instance.new("TextButton")
            clickBtn.Name               = "_ClickBtn"
            clickBtn.Size               = UDim2.new(1, 0, 1, 0)
            clickBtn.BackgroundTransparency = 1
            clickBtn.Text               = ""
            clickBtn.ZIndex             = 2
            clickBtn.Parent             = template
            clickBtn.MouseButton1Click:Connect(function()
                if capturedLocked then return end  -- 미소유 → 무반응
                showTooltip(capturedItem, capturedLocked, template)
            end)
        end
    end

    refreshCheckMarks()
    refreshBottomLabel()
end

-- 토글 버튼
if toggleBtn then
    toggleBtn.MouseButton1Click:Connect(function()
        setOwned(not getOwned())
        applyToggleVisual()
        tooltip.Visible    = false
        currentTooltipItem = nil
        local filtered = {}
        for _, item in ipairs(cachedItems) do
            if not getOwned() or item.owned then
                table.insert(filtered, item)
            end
        end
        populateSlots(filtered)
    end)
end

-- ── 데이터 로드 ───────────────────────────────────────────────
local function loadData()
    local data = getEffectData:InvokeServer("killEffect")
    cachedItems = data or {}
    equippedId  = nil
    applyToggleVisual()
    local filtered = {}
    for _, item in ipairs(cachedItems) do
        if not getOwned() or item.owned then
            table.insert(filtered, item)
        end
    end
    populateSlots(filtered)
end

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
end

_G.openKilleffectInven  = openInven
_G.closeKilleffectInven = closeInven

closeBtn.MouseButton1Click:Connect(closeInven)
if tooltipClose2 then
    tooltipClose2.MouseButton1Click:Connect(function()
        tooltip.Visible    = false
        currentTooltipItem = nil
    end)
end


-- ── Switchicon: Kill Effect → Emote 전환 ─────────────────────
switchicon.MouseButton1Click:Connect(function()
    local pg        = player:WaitForChild("PlayerGui")
    local newGui    = pg:FindFirstChild("NewGui")
    local emoteGui  = newGui and newGui:FindFirstChild("EmoteInven")
    if not emoteGui then return end

    closeInven()

    local openFn = _G.openEmoteInven
    if openFn then
        openFn()
    else
        emoteGui.Canvas.Visible     = true
        emoteGui.Switchicon.Visible = true
    end
end)
print("✅ KilleffectInvenClient 준비! (AbsoluteSize fix)")
