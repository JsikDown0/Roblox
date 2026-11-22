local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = script.Parent
local panel = gui:WaitForChild("LoadoutPanel")

-- 모바일 노치/펀치홀 자동 회피
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)

-- ── 반응형 스케일 (디바이스별, 공통 모듈) ────────────────────
local Scaler = require(ReplicatedStorage:WaitForChild("ResponsiveScaler"))
Scaler.applyPanel(panel, {
    baseW = 550, baseH = 550,
    Mobile = { frac = 0.85, minScale = 0.55 },  -- 현재 값 (동결)
    PC     = { frac = 0.85, minScale = 0.55 },  -- ← PC용. 자유 조정
})

local tabContainer  = panel:WaitForChild("TabContainer")
local runnerTab     = tabContainer:WaitForChild("RunnerTab")
local taggerTab     = tabContainer:WaitForChild("TaggerTab")
local skinTab       = tabContainer:WaitForChild("SkinTab")
local runnerContent = panel:WaitForChild("RunnerContent")
local taggerContent = panel:WaitForChild("TaggerContent")
local skinContent   = panel:WaitForChild("SkinContent")
local confirmBtn    = panel:WaitForChild("ConfirmButton")
local closeBtn      = panel:WaitForChild("CloseButton")
local getLoadout    = ReplicatedStorage:WaitForChild("GetPlayerLoadout")
local setLoadout    = ReplicatedStorage:WaitForChild("SetPlayerLoadout")

local currentTab = "runner"
local panelOpen  = false
local taggerSelectedItems = {}
local taggerAllItemsData  = {}
local hasPass = false
local passId  = 0
local runnerSelectedItems = {}

local tabColors = {
    runner = {active = Color3.fromRGB(60, 120, 200), inactive = Color3.fromRGB(40, 70, 120)},
    tagger = {active = Color3.fromRGB(200, 60, 60),  inactive = Color3.fromRGB(120, 40, 40)},
    skin   = {active = Color3.fromRGB(180, 100, 220),inactive = Color3.fromRGB(100, 60, 130)},
}

function updateConfirmButton()
    local selectedItems = currentTab == "tagger" and taggerSelectedItems or runnerSelectedItems
    local count = 0
    for _, v in pairs(selectedItems) do if v then count += 1 end end
    local tabText = currentTab == "tagger" and "Tagger" or "Runner"
    if count < 1 then
        confirmBtn.Text = "Select at least 1"
        confirmBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    elseif count > 4 then
        confirmBtn.Text = "Max 4 items"
        confirmBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
    else
        confirmBtn.Text = tabText .. " Confirm (" .. count .. "/4)"
        confirmBtn.BackgroundColor3 = Color3.fromRGB(50, 180, 80)
    end
end

local function switchTab(tabName)
    currentTab = tabName
    runnerContent.Visible = (tabName == "runner")
    taggerContent.Visible = (tabName == "tagger")
    skinContent.Visible   = (tabName == "skin")
    runnerTab.BackgroundColor3 = tabColors.runner[tabName == "runner" and "active" or "inactive"]
    taggerTab.BackgroundColor3 = tabColors.tagger[tabName == "tagger" and "active" or "inactive"]
    skinTab.BackgroundColor3   = tabColors.skin[tabName == "skin"   and "active" or "inactive"]
    updateConfirmButton()
end

runnerTab.MouseButton1Click:Connect(function() switchTab("runner") end)
taggerTab.MouseButton1Click:Connect(function() switchTab("tagger") end)
skinTab.MouseButton1Click:Connect(function()   switchTab("skin")   end)

local taggerContainer = taggerContent:FindFirstChild("InventoryScroll")

local function updateButtonVisual(btn, itemName, isPremium, selectedItems)
    local isSelected = selectedItems[itemName] == true
    local locked = isPremium and not hasPass
    if locked then
        btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        local l = btn:FindFirstChild("LockLabel")  if l then l.Visible = true  end
        local c = btn:FindFirstChild("CheckLabel") if c then c.Visible = false end
    elseif isSelected then
        btn.BackgroundColor3 = Color3.fromRGB(50, 120, 180)
        local l = btn:FindFirstChild("LockLabel")  if l then l.Visible = false end
        local c = btn:FindFirstChild("CheckLabel") if c then c.Visible = true  end
    else
        btn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        local l = btn:FindFirstChild("LockLabel")  if l then l.Visible = false end
        local c = btn:FindFirstChild("CheckLabel") if c then c.Visible = false end
    end
end

local function saveCurrentSelection()
    local taggerItems = {}
    for name, v in pairs(taggerSelectedItems) do
        if v then table.insert(taggerItems, name) end
    end
    if #taggerItems >= 1 and #taggerItems <= 4 then
        setLoadout:FireServer(taggerItems)
        print("✅ 태거 로드아웃 저장:", table.concat(taggerItems, ", "))
    end
end

local function createTaggerItemButtons(items, loadout)
    if not taggerContainer then return end
    for _, child in ipairs(taggerContainer:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    taggerSelectedItems = {}
    for _, name in ipairs(loadout or {}) do taggerSelectedItems[name] = true end

    for i, itemData in ipairs(items) do
        local btn = Instance.new("TextButton")
        btn.Name = itemData.name
        btn.Size = UDim2.new(0, 90, 0, 100)
        btn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
        btn.Text = ""
        btn.LayoutOrder = i
        btn.Parent = taggerContainer
        local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,8); corner.Parent = btn

        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"; icon.Size = UDim2.new(1,0,0,60)
        icon.BackgroundTransparency = 1; icon.Image = itemData.icon or ""
        icon.ScaleType = Enum.ScaleType.Fit; icon.Parent = btn

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NameLabel"; nameLabel.Size = UDim2.new(1,-6,0,35)
        nameLabel.Position = UDim2.new(0,3,0,50); nameLabel.BackgroundTransparency = 1
        nameLabel.Text = itemData.displayName or itemData.name
        nameLabel.TextColor3 = Color3.fromRGB(255,255,255); nameLabel.TextSize = 11
        nameLabel.Font = Enum.Font.GothamBold; nameLabel.TextWrapped = true
        nameLabel.TextScaled = true; nameLabel.Parent = btn

        local checkLabel = Instance.new("TextLabel")
        checkLabel.Name = "CheckLabel"; checkLabel.Size = UDim2.new(0,24,0,24)
        checkLabel.Position = UDim2.new(1,-26,0,2)
        checkLabel.BackgroundColor3 = Color3.fromRGB(50,180,80)
        checkLabel.Text = "✓"; checkLabel.TextColor3 = Color3.fromRGB(255,255,255)
        checkLabel.TextSize = 16; checkLabel.Visible = false; checkLabel.Parent = btn
        local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0,12); cc.Parent = checkLabel

        local lockLabel = Instance.new("TextLabel")
        lockLabel.Name = "LockLabel"; lockLabel.Size = UDim2.new(0,24,0,24)
        lockLabel.Position = UDim2.new(1,-26,0,2)
        lockLabel.BackgroundColor3 = Color3.fromRGB(80,80,80)
        lockLabel.Text = "🔒"; lockLabel.TextSize = 14; lockLabel.Visible = false; lockLabel.Parent = btn
        local lc = Instance.new("UICorner"); lc.CornerRadius = UDim.new(0,12); lc.Parent = lockLabel

        updateButtonVisual(btn, itemData.name, itemData.premium, taggerSelectedItems)

        btn.MouseButton1Click:Connect(function()
            if itemData.premium and not hasPass then
                if passId and passId > 0 then
                    MarketplaceService:PromptGamePassPurchase(player, passId)
                end
                return
            end
            taggerSelectedItems[itemData.name] = not taggerSelectedItems[itemData.name]
            updateButtonVisual(btn, itemData.name, itemData.premium, taggerSelectedItems)
            updateConfirmButton()
        end)
    end

    local grid = taggerContainer:FindFirstChild("UIGridLayout")
    if grid then
        taggerContainer.CanvasSize = UDim2.new(0, 0, 0, math.ceil(#items / 4) * 110 + 20)
    end
    updateConfirmButton()
end

local function loadData()
    local data = getLoadout:InvokeServer()
    if data then
        taggerAllItemsData = data.allItems or {}
        hasPass = data.hasPass or false
        passId  = data.passId  or 0
        createTaggerItemButtons(taggerAllItemsData, data.loadout or {"Wood Log"})
    end
end

local function openLoadout()
    panelOpen = not panelOpen
    panel.Visible = panelOpen
    if panelOpen then switchTab("runner"); loadData() end
end
_G.openLoadout = openLoadout

closeBtn.MouseButton1Click:Connect(function()
    saveCurrentSelection(); panelOpen = false; panel.Visible = false
end)

confirmBtn.MouseButton1Click:Connect(function()
    local selectedItems = currentTab == "tagger" and taggerSelectedItems or runnerSelectedItems
    local count = 0
    for _, v in pairs(selectedItems) do if v then count += 1 end end
    if count < 1 or count > 4 then return end
    saveCurrentSelection(); panelOpen = false; panel.Visible = false
end)

local function updateBagVisibility()
    local role = player:GetAttribute("Role")
    if role ~= nil then
        if panelOpen then saveCurrentSelection() end
        panelOpen = false; panel.Visible = false
    end
end
player:GetAttributeChangedSignal("Role"):Connect(updateBagVisibility)
updateBagVisibility()

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(_, gpId, purchased)
    if gpId == passId and purchased then
        hasPass = true
        for _, data in ipairs(taggerAllItemsData) do
            local b = taggerContainer:FindFirstChild(data.name)
            if b then updateButtonVisual(b, data.name, data.premium, taggerSelectedItems) end
        end
    end
end)

-- ==================== 스킨 탭 ====================
local getShopItems      = ReplicatedStorage:WaitForChild("GetShopItems")
local skinContentFrame  = panel:WaitForChild("SkinContent")
-- ✅ 수정: EmoteScroll → SkinScroll, EmotePreviewFrame → PreviewFrame
local skinScroll        = skinContentFrame:FindFirstChild("SkinScroll") or skinContentFrame:FindFirstChild("EmoteScroll")
local killEffectScroll  = skinContentFrame:FindFirstChild("KillEffectScroll")
local skinPreviewFrame  = skinContentFrame:FindFirstChild("PreviewFrame") or skinContentFrame:FindFirstChild("EmotePreviewFrame")
local killEffectFrame   = skinContentFrame:FindFirstChild("KillEffectFrame")

local equippedSkin = nil
local equippedKillEffect = nil

local function updateSkinPreview()
    if not skinPreviewFrame then return end
    local skinName = skinPreviewFrame:FindFirstChild("SkinName")
    if skinName then skinName.Text = equippedSkin and equippedSkin.name or "Default Skin" end
end

local function updateKillEffectPreview()
    if not killEffectFrame then return end
    local icon      = killEffectFrame:FindFirstChild("KillEffectIcon")
    local nameLabel = killEffectFrame:FindFirstChild("KillEffectName")
    if icon then
        icon.Text = equippedKillEffect and (equippedKillEffect.icon or "🔥") or ""
        icon.Visible = equippedKillEffect ~= nil
    end
    if nameLabel then
        nameLabel.Text = equippedKillEffect and equippedKillEffect.name or "None"
        nameLabel.TextColor3 = equippedKillEffect and Color3.fromRGB(255,150,50) or Color3.fromRGB(150,150,150)
    end
    local stroke = killEffectFrame:FindFirstChild("UIStroke")
    if stroke then
        stroke.Color = equippedKillEffect and Color3.fromRGB(255,120,30) or Color3.fromRGB(100,100,100)
    end
    local setKillEffectEvent = ReplicatedStorage:FindFirstChild("SetKillEffect")
    if setKillEffectEvent then
        setKillEffectEvent:FireServer(equippedKillEffect and equippedKillEffect.id or "none")
    end
end

local function createSkinCard(itemData, isKillEffect, targetScroll)
    local btn = Instance.new("TextButton")
    btn.Name = itemData.id; btn.Size = UDim2.new(0,90,0,100)
    btn.BackgroundColor3 = Color3.fromRGB(40,40,50); btn.Text = ""
    btn.AutoButtonColor = false; btn.Parent = targetScroll

    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,8); corner.Parent = btn
    local stroke = Instance.new("UIStroke"); stroke.Name = "CardStroke"
    stroke.Color = Color3.fromRGB(80,80,80); stroke.Thickness = 1.5; stroke.Parent = btn

    local icon = Instance.new("TextLabel"); icon.Size = UDim2.new(1,0,0,52)
    icon.Position = UDim2.new(0,0,0,5); icon.BackgroundTransparency = 1
    icon.Text = itemData.icon or (isKillEffect and "🔥" or "✨"); icon.TextSize = 30; icon.Parent = btn

    local nameLabel = Instance.new("TextLabel"); nameLabel.Size = UDim2.new(1,-4,0,26)
    nameLabel.Position = UDim2.new(0,2,0,55); nameLabel.BackgroundTransparency = 1
    nameLabel.Text = itemData.name; nameLabel.TextColor3 = Color3.fromRGB(220,220,220)
    nameLabel.TextSize = 10; nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextScaled = true; nameLabel.TextWrapped = true; nameLabel.Parent = btn

    local badgeLabel = Instance.new("TextLabel"); badgeLabel.Name = "BadgeLabel"
    badgeLabel.Size = UDim2.new(1,0,0,18); badgeLabel.Position = UDim2.new(0,0,1,-20)
    badgeLabel.BackgroundTransparency = 1; badgeLabel.TextSize = 10
    badgeLabel.Font = Enum.Font.GothamBold; badgeLabel.Parent = btn

    local function refreshCard()
        local owned = player:GetAttribute("OwnedItem_" .. itemData.id) == true
        local isEquipped = isKillEffect
            and (equippedKillEffect and equippedKillEffect.id == itemData.id)
            or (not isKillEffect and equippedSkin and equippedSkin.id == itemData.id)
        local activeColor  = isKillEffect and Color3.fromRGB(255,130,50)  or Color3.fromRGB(200,100,255)
        local baseBg       = isKillEffect and Color3.fromRGB(55,35,20)    or Color3.fromRGB(50,30,70)
        local activeStroke = isKillEffect and Color3.fromRGB(200,80,30)   or Color3.fromRGB(150,80,200)
        if not owned then
            btn.BackgroundColor3 = Color3.fromRGB(35,35,45); stroke.Color = Color3.fromRGB(70,70,70)
            stroke.Thickness = 1; badgeLabel.Text = "🔒 Locked"; badgeLabel.TextColor3 = Color3.fromRGB(130,130,130)
        elseif isEquipped then
            btn.BackgroundColor3 = isKillEffect and Color3.fromRGB(100,45,15) or Color3.fromRGB(65,25,95)
            stroke.Color = activeColor; stroke.Thickness = 2.5
            badgeLabel.Text = "✅ Equipped"; badgeLabel.TextColor3 = Color3.fromRGB(100,230,100)
        else
            btn.BackgroundColor3 = baseBg; stroke.Color = activeStroke; stroke.Thickness = 1.5
            badgeLabel.Text = "Equip"; badgeLabel.TextColor3 = Color3.fromRGB(180,180,180)
        end
    end
    refreshCard()

    btn.MouseButton1Click:Connect(function()
        local owned = player:GetAttribute("OwnedItem_" .. itemData.id) == true
        if not owned then return end
        if isKillEffect then
            equippedKillEffect = (equippedKillEffect and equippedKillEffect.id == itemData.id) and nil or itemData
            updateKillEffectPreview()
        else
            equippedSkin = (equippedSkin and equippedSkin.id == itemData.id) and nil or itemData
            updateSkinPreview()
        end
        for _, child in ipairs(targetScroll:GetChildren()) do
            if child:IsA("TextButton") then
                local b = child:FindFirstChild("BadgeLabel")
                local s = child:FindFirstChild("CardStroke")
                local childOwned = player:GetAttribute("OwnedItem_" .. child.Name) == true
                if b and s and childOwned then
                    local activeC = isKillEffect and Color3.fromRGB(200,80,30) or Color3.fromRGB(150,80,200)
                    local baseB   = isKillEffect and Color3.fromRGB(55,35,20)  or Color3.fromRGB(50,30,70)
                    child.BackgroundColor3 = baseB; s.Color = activeC; s.Thickness = 1.5
                    b.Text = "Equip"; b.TextColor3 = Color3.fromRGB(180,180,180)
                end
            end
        end
        refreshCard()
    end)
    player:GetAttributeChangedSignal("OwnedItem_" .. itemData.id):Connect(refreshCard)
    return btn
end

local function loadSkinTab()
    if skinScroll then
        for _, child in ipairs(skinScroll:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
    end
    if killEffectScroll then
        for _, child in ipairs(killEffectScroll:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
    end
    local allSkinItems = getShopItems:InvokeServer("skin")
    if not allSkinItems then return end
    local skinCount, killCount = 0, 0
    for _, item in ipairs(allSkinItems) do
        if item.id:find("kill_effect") then
            if killEffectScroll then createSkinCard(item, true, killEffectScroll); killCount += 1 end
        else
            if skinScroll then createSkinCard(item, false, skinScroll); skinCount += 1 end
        end
    end
    if skinScroll then skinScroll.CanvasSize = UDim2.new(0,0,0, math.ceil(skinCount/2)*110+20) end
    if killEffectScroll then killEffectScroll.CanvasSize = UDim2.new(0,0,0, math.ceil(killCount/2)*110+20) end
    updateSkinPreview(); updateKillEffectPreview()
end

skinTab.MouseButton1Click:Connect(loadSkinTab)

task.wait(1)
loadData()
print("✅ LoadoutUI 준비 완료!")
