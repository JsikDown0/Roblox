-- 상점 클라이언트 (리스트 + 프리뷰: Rivals식, ITEM COLOR 시각 언어)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local gui = script.Parent
local mainFrame = gui:WaitForChild("MainFrame")
local closeBtn = mainFrame:WaitForChild("CloseBtn")

pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)

-- 반응형 스케일
local BASE_W, BASE_H = 700, 500
local camera = workspace.CurrentCamera
local function applyResponsiveScale()
    local vp = camera.ViewportSize
    local scale = math.min((vp.X * 0.85) / BASE_W, (vp.Y * 0.85) / BASE_H, 1)
    scale = math.max(scale, 0.55)
    local uiScale = mainFrame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", mainFrame)
    uiScale.Scale = scale
end
applyResponsiveScale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyResponsiveScale)

-- 탭
local tabContainer = mainFrame:WaitForChild("TabContainer")
local runnerTab = tabContainer:WaitForChild("RunnerTab")
local taggerTab = tabContainer:WaitForChild("TaggerTab")
local skinTab = tabContainer:WaitForChild("SkinTab")

-- 필터(리스트+프리뷰에선 우선 숨김 — 코스메틱 종류 필터는 다음 단계)
local filterContainer = mainFrame:WaitForChild("FilterContainer")
filterContainer.Visible = false

local itemScroll = mainFrame:WaitForChild("ItemScroll")

local openShopEvent = ReplicatedStorage:WaitForChild("OpenShopEvent")
local purchaseEvent = ReplicatedStorage:WaitForChild("ShopPurchaseEvent")
local getItemsEvent = ReplicatedStorage:WaitForChild("GetShopItems")

-- 상태
local currentTab = "runner"
local allItems = {}
local selectedKey = nil
local currentCards = {}

local tabColors = {
    runner = {active = Color3.fromRGB(60,120,200), inactive = Color3.fromRGB(40,70,120)},
    tagger = {active = Color3.fromRGB(200,60,60), inactive = Color3.fromRGB(120,40,40)},
    skin   = {active = Color3.fromRGB(180,100,220), inactive = Color3.fromRGB(100,60,130)},
}
local function accentColor()
    return currentTab == "runner" and Color3.fromRGB(70,130,210)
        or (currentTab == "tagger" and Color3.fromRGB(210,80,80) or Color3.fromRGB(170,100,210))
end
local function updateTabs()
    runnerTab.BackgroundColor3 = currentTab == "runner" and tabColors.runner.active or tabColors.runner.inactive
    taggerTab.BackgroundColor3 = currentTab == "tagger" and tabColors.tagger.active or tabColors.tagger.inactive
    skinTab.BackgroundColor3   = currentTab == "skin"   and tabColors.skin.active   or tabColors.skin.inactive
end

-- ── 썸네일 헬퍼 (뷰포트 / 이미지 / 이모지) ────────────────────
local function buildThumbnail(holder, item)
    for _, c in ipairs(holder:GetChildren()) do
        if not c:IsA("UICorner") then c:Destroy() end
    end
    if item.modelName and not (item.imageId and item.imageId ~= "") then
        holder.BackgroundColor3 = Color3.fromRGB(16, 19, 28)
        local pf = ReplicatedStorage:FindFirstChild("RunnerItemPreviews")
        local src = pf and pf:FindFirstChild(item.modelName)
        local cDir  = src and src:GetAttribute("CameraDirection")
        local cAmb  = src and src:GetAttribute("Ambient")
        local cDist = src and src:GetAttribute("DistMul")
        local cOff  = src and src:GetAttribute("CameraOffset")
        local vp = Instance.new("ViewportFrame")
        vp.Size = UDim2.fromScale(1,1); vp.BackgroundTransparency = 1
        vp.LightColor = Color3.fromRGB(255,240,220); vp.LightDirection = Vector3.new(-1,-2,-1)
        vp.Ambient = cAmb or Color3.fromRGB(120,120,140)
        vp.Parent = holder
        if src then
            local m = src:Clone(); m.Parent = vp
            for _, p in ipairs(m:GetDescendants()) do
                if p:IsA("BasePart") then p.Anchored = true; p.CastShadow = false end
            end
            local cam = Instance.new("Camera"); cam.FieldOfView = 50; vp.CurrentCamera = cam; cam.Parent = vp
            local cf, sz
            if m:IsA("Model") then cf, sz = m:GetBoundingBox() else cf, sz = m.CFrame, m.Size end
            local md = math.max(sz.X, sz.Y, sz.Z)
            local dist = md * (cDist or 1.4)
            local dv = cDir or Vector3.new(0.7, 0.5, 0.7)
            local camPos, tgt = cf.Position + dv * dist, cf.Position
            if cOff then
                local t = CFrame.new(camPos, tgt)
                tgt = tgt + t.RightVector * (cOff.X * md) + t.UpVector * (cOff.Y * md)
            end
            cam.CFrame = CFrame.new(camPos, tgt)
        end
    elseif item.imageId and item.imageId ~= "" then
        holder.BackgroundColor3 = Color3.fromRGB(0, 0, 0)   -- 이미지 원본의 검은 배경과 매칭 → 경계 안 보이게
        local img = Instance.new("ImageLabel")
        img.Name = "_IconImg"
        img:SetAttribute("effectId", item.id)
        img:SetAttribute("tunePrefix", "shop")   -- BadgeTuner(B키)가 상점값(shopScale/shopOffX/shopOffY)으로 출력
        img.BackgroundTransparency = 1
        img.Image = "rbxassetid://" .. (tostring(item.imageId):gsub("rbxassetid://", ""))
        img.ScaleType = Enum.ScaleType.Fit
        -- 상점 전용 튜닝(shopScale/OffX/OffY) 우선 → 없으면 인벤값(imgScale...) 폴백 → 둘 다 없으면 풀사이즈(1)
        local sc = item.shopScale or item.imgScale or 1
        local ox = item.shopOffX or item.imgOffX or 0
        local oy = item.shopOffY or item.imgOffY or 0
        img.AnchorPoint = Vector2.new(0.5, 0.5)
        img.Size = UDim2.fromScale(sc, sc)
        img.Position = UDim2.fromScale(0.5 + ox, 0.5 + oy)
        img.Parent = holder
    elseif item.sub == "dash" and _G.LP_makeDashIcon and _G.LP_makeDashIcon(holder, item.id) then
        holder.BackgroundColor3 = Color3.fromRGB(16, 19, 28)
    elseif item.sub == "trail" and _G.LP_makeTrailRibbon and _G.LP_makeTrailRibbon(holder, item.id) then
        holder.BackgroundColor3 = Color3.fromRGB(16, 19, 28)
    elseif item.sub == "crown" and item.skinKey and _G.LP_makeViewport and _G.LP_makeViewport(holder, "CrownPreviews", item.skinKey) then
        holder.BackgroundColor3 = Color3.fromRGB(16, 19, 28)
    -- ⚠️ 태거 아이템(배럴 등)은 SkinPreviews 가 아니라 TaggerItemPreviews 에 있다.
    --    ItemPreviewHandler 가 두 폴더를 따로 만든다. SkinPreviews 만 보면
    --    배럴 색놀이가 상점에서 통째로 안 보인다(실측 2026-08-21).
    --    UnifiedInvenClient:1438 이 이미 같은 폴백을 갖고 있다 — 동일 패턴을 맞춘다.
    elseif item.previewModel and _G.LP_makeViewport
           and (_G.LP_makeViewport(holder, "SkinPreviews", item.previewModel)
                or _G.LP_makeViewport(holder, "TaggerItemPreviews", item.previewModel)) then
        -- ITEM COLOR: 박스 보상 카드(RareSkinRewardCard.paintModel)와 동일한 표현 —
        -- 무기 3D 뷰포트를 해당 색으로 칠하고 우상단에 색 스와치.
        -- ⚠ p.Color만 바꾸면 텍스처가 색을 덮어 원본 그대로 보임(HammerLow=12592745, ClassicSword=SwordTexture).
        --   MeshPart.TextureID / SpecialMesh.TextureId+VertexColor / SurfaceAppearance 4가지를 다 처리해야 함.
        holder.BackgroundColor3 = Color3.fromRGB(16, 19, 28)
        local col = Color3.fromRGB(item.swatch[1], item.swatch[2], item.swatch[3])
        local vp = holder:FindFirstChildOfClass("ViewportFrame")
        local model = vp and (vp:FindFirstChildWhichIsA("Model") or vp:FindFirstChildWhichIsA("BasePart"))
        if model then
            local function paintPart(p)
                if not p:IsA("BasePart") then return end
                p.Color = col
                if p:IsA("MeshPart") then p.TextureID = "" end
                local sm = p:FindFirstChildWhichIsA("SpecialMesh")
                if sm then
                    sm.TextureId = ""
                    sm.VertexColor = Vector3.new(col.R, col.G, col.B)
                end
                local sa = p:FindFirstChildWhichIsA("SurfaceAppearance")
                if sa then sa:Destroy() end   -- PBR 텍스처가 Color를 덮지 않게 (tnt 등)
            end
            if model:IsA("BasePart") then paintPart(model) end
            for _, p in ipairs(model:GetDescendants()) do paintPart(p) end
            -- 어두운 색(블랙 등)은 어두운 배경에 안 보임 → 흰색 외곽선
            if item.previewModel == "Demonspear" then
                local lum = col.R * 0.3 + col.G * 0.59 + col.B * 0.11
                if lum < 0.3 then
                    local hl = Instance.new("Highlight")
                    hl.Adornee = model
                    hl.FillTransparency = 1
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.OutlineTransparency = 0
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.Parent = model
                end
            end
        end
        -- 우상단 색 스와치. ⚠ 리스트 썸네일(~40px)과 프리뷰 패널(~340px)이 같은 함수를 쓰므로
        --   Scale로 주면 프리뷰에서 거대해짐 → 고정 픽셀.
        -- ⚠ 프리뷰 패널엔 진영 뱃지(FactionBadge)가 (1,-98,0,6) 92×22로 우상단을 먹음.
        --   y=4면 정면 충돌 → 뱃지 아래(y=32)로 내림. 리스트 썸네일엔 뱃지가 없어 여백일 뿐.
        local chip = Instance.new("Frame")
        chip.Name = "_Swatch"
        chip.AnchorPoint = Vector2.new(1, 0)
        chip.Position = UDim2.new(1, -4, 0, 32)
        chip.Size = UDim2.fromOffset(16, 16)
        chip.BackgroundColor3 = col
        chip.BorderSizePixel = 0
        chip.ZIndex = 3
        chip.Parent = holder
        Instance.new("UICorner", chip).CornerRadius = UDim.new(1, 0)
        local cs = Instance.new("UIStroke")
        cs.Color = Color3.fromRGB(235, 240, 255)
        cs.Thickness = 1
        cs.Transparency = 0.25
        cs.Parent = chip
    elseif item.swatch then
        -- ITEM COLOR: 색 자체가 상품 → 이미지/뷰포트 없이 색 칩으로 렌더.
        -- (아이콘이 전부 🎨라 이모지 폴백으로 두면 9색이 구분이 안 됨)
        holder.BackgroundColor3 = Color3.fromRGB(16, 19, 28)
        local chip = Instance.new("Frame")
        chip.Name = "_Swatch"
        chip.AnchorPoint = Vector2.new(0.5, 0.5)
        chip.Position = UDim2.fromScale(0.5, 0.5)
        chip.Size = UDim2.fromScale(0.62, 0.62)
        chip.BackgroundColor3 = Color3.fromRGB(item.swatch[1], item.swatch[2], item.swatch[3])
        chip.BorderSizePixel = 0
        chip.Parent = holder
        Instance.new("UICorner", chip).CornerRadius = UDim.new(0.15, 0)
        local st = Instance.new("UIStroke")
        st.Color = Color3.fromRGB(235, 240, 255)
        st.Thickness = 1.5
        st.Transparency = 0.35
        st.Parent = chip
    else
        holder.BackgroundColor3 = Color3.fromRGB(16, 19, 28)
        local ic = Instance.new("TextLabel")
        ic.Size = UDim2.fromScale(1,1); ic.BackgroundTransparency = 1
        ic.Text = item.icon or "❓"; ic.TextScaled = true; ic.Parent = holder
        Instance.new("UITextSizeConstraint", ic).MaxTextSize = 42
    end
end

-- ── 좌측 리스트: 세로 배치로 전환 ─────────────────────────────
itemScroll.Size = UDim2.new(0, 215, 0, 340)
itemScroll.Position = UDim2.new(0, 15, 0, 125)
do
    local grid = itemScroll:FindFirstChildOfClass("UIGridLayout")
    if grid then grid:Destroy() end
    local pad0 = itemScroll:FindFirstChildOfClass("UIPadding")
    if pad0 then pad0:Destroy() end
    local ll = Instance.new("UIListLayout")
    ll.FillDirection = Enum.FillDirection.Vertical
    ll.Padding = UDim.new(0, 6)
    ll.SortOrder = Enum.SortOrder.LayoutOrder
    ll.Parent = itemScroll
    local up = Instance.new("UIPadding")
    up.PaddingTop = UDim.new(0,6); up.PaddingLeft = UDim.new(0,4); up.PaddingRight = UDim.new(0,4)
    up.Parent = itemScroll
end

-- ── 우측 프리뷰 패널 (런타임 생성) ────────────────────────────
local panel = mainFrame:FindFirstChild("PreviewPanel")
if panel then panel:Destroy() end
panel = Instance.new("Frame")
panel.Name = "PreviewPanel"
panel.Position = UDim2.new(0, 240, 0, 125)
panel.Size = UDim2.new(1, -255, 0, 340)
panel.BackgroundColor3 = Color3.fromRGB(24, 28, 40)
panel.BackgroundTransparency = 0.1
panel.Parent = mainFrame
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local pStroke = Instance.new("UIStroke"); pStroke.Color = Color3.fromRGB(60,70,95); pStroke.Thickness = 1.5; pStroke.Parent = panel

local previewHolder = Instance.new("Frame")
previewHolder.Name = "Preview"
previewHolder.Size = UDim2.new(1, -24, 0, 178)
previewHolder.Position = UDim2.new(0, 12, 0, 12)
previewHolder.BackgroundColor3 = Color3.fromRGB(16, 19, 28)
previewHolder.Parent = panel
Instance.new("UICorner", previewHolder).CornerRadius = UDim.new(0, 10)

local pName = Instance.new("TextLabel")
pName.Name = "PName"
pName.Size = UDim2.new(1, -24, 0, 26)
pName.Position = UDim2.new(0, 12, 0, 198)
pName.BackgroundTransparency = 1
pName.TextColor3 = Color3.fromRGB(255,255,255)
pName.Font = Enum.Font.BuilderSansExtraBold
pName.TextXAlignment = Enum.TextXAlignment.Left
pName.TextScaled = true
pName.Text = ""
pName.Parent = panel
Instance.new("UITextSizeConstraint", pName).MaxTextSize = 20

local pDesc = Instance.new("TextLabel")
pDesc.Name = "PDesc"
-- 📝 [2026-08-29] 폰트 13 → 16, 높이 68 → 104.
--   [증상] 무기 설명 글자가 너무 작아 읽기 힘들었다.
--   [원인] 이름(pName)은 UITextSizeConstraint 로 최대 20 인데 설명은 13 이라
--     대비가 커서 "부속 정보"처럼 보였다.
--   ⚠️ 폰트만 키우면 68px 안에 안 들어가 잘린다. TextWrapped 는 이미 true 라
--     줄바꿈은 되지만 라벨 높이를 넘으면 그대로 사라진다. 높이를 함께 늘린다.
--   ⚠️ 아래 btnArea 는 Position 이 (1, -54) = 패널 '바닥' 기준이라
--     desc 가 길어져도 버튼을 밀지 않는다. 그래서 안전하게 늘릴 수 있다.
--   [계산] 16pt 로 줄당 약 20px, 5줄 = 100px. 104 면 5줄까지 들어간다.
pDesc.Size = UDim2.new(1, -24, 0, 104)
pDesc.Position = UDim2.new(0, 12, 0, 226)
pDesc.BackgroundTransparency = 1
pDesc.TextColor3 = Color3.fromRGB(196, 205, 218)   -- 살짝 밝게 (가독성)
pDesc.Font = Enum.Font.BuilderSans
pDesc.TextXAlignment = Enum.TextXAlignment.Left
pDesc.TextYAlignment = Enum.TextYAlignment.Top
pDesc.TextWrapped = true
pDesc.TextSize = 16
pDesc.LineHeight = 1.15   -- 줄 간격을 살짝 벌려 빽빽함을 덜어낸다
pDesc.Text = ""
pDesc.Parent = panel

local btnArea = Instance.new("Frame")
btnArea.Name = "BtnArea"
btnArea.Size = UDim2.new(1, -24, 0, 42)
btnArea.Position = UDim2.new(0, 12, 1, -54)
btnArea.BackgroundTransparency = 1
btnArea.Parent = panel
local bl = Instance.new("UIListLayout")
bl.FillDirection = Enum.FillDirection.Horizontal
bl.HorizontalAlignment = Enum.HorizontalAlignment.Center
bl.VerticalAlignment = Enum.VerticalAlignment.Center
bl.Padding = UDim.new(0, 8)
bl.Parent = btnArea

-- ── 아이템 선택 → 프리뷰/상세/버튼 갱신 ───────────────────────
local function selectItem(key)
    selectedKey = key
    local cd = currentCards[key]
    if not cd then return end
    buildThumbnail(previewHolder, cd.thumbItem)
    pName.Text = cd.name
    pDesc.Text = cd.desc or cd.short or ""
    -- 진영 뱃지 (프리뷰 우상단)
    local fac = cd.thumbItem and cd.thumbItem.faction
    if fac then
        local fb = Instance.new("TextLabel")
        fb.Name = "FactionBadge"
        fb.Size = UDim2.new(0, 92, 0, 22); fb.Position = UDim2.new(1, -98, 0, 6)
        fb.BackgroundColor3 = (fac == "tagger") and Color3.fromRGB(190, 60, 60) or Color3.fromRGB(55, 110, 200)
        fb.BackgroundTransparency = 0.05
        fb.Text = (fac == "tagger") and "KING ONLY" or "RUNNER ONLY"
        fb.TextColor3 = Color3.fromRGB(255, 255, 255)
        fb.Font = Enum.Font.BuilderSansExtraBold; fb.TextScaled = true; fb.ZIndex = 10
        fb.Parent = previewHolder
        Instance.new("UICorner", fb).CornerRadius = UDim.new(0, 5)
        Instance.new("UITextSizeConstraint", fb).MaxTextSize = 12
    end
    for _, c in ipairs(btnArea:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
    local n = #cd.buttons
    -- 이 그룹(baseId)에 영구 SKU를 이미 보유했는지 → 보유 시 같은 그룹 1판(소모) 버튼 잠금
    local permOwnedInGroup = false
    for _, b in ipairs(cd.buttons) do
        if b.itemType == "permanent" and player:GetAttribute("OwnedItem_" .. b.id) then
            permOwnedInGroup = true
            break
        end
    end
    for _, b in ipairs(cd.buttons) do
        local owned  = (b.itemType == "permanent") and player:GetAttribute("OwnedItem_" .. b.id)
        local locked = (b.itemType == "consumable") and permOwnedInGroup
        local disabled = owned or locked
        local bundleLock = (b.bundlePass ~= nil) and not owned   -- 번들 전용 → 코인 대신 로벅스 번들 프롬프트
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1/n, n > 1 and -4 or 0, 1, 0)
        btn.BackgroundColor3 = owned and Color3.fromRGB(70,92,80)
            or (locked and Color3.fromRGB(48,52,62) or Color3.fromRGB(235,190,40))
        btn.AutoButtonColor = not disabled
        btn.Font = Enum.Font.BuilderSansExtraBold
        btn.TextScaled = true
        btn.TextColor3 = owned and Color3.fromRGB(185,215,195)
            or (locked and Color3.fromRGB(130,138,150) or Color3.fromRGB(45,32,0))
        btn.Text = owned and "Owned"
            or (locked and "Owned (perm)" or ((b.label and (b.label .. string.char(10)) or "") .. "💰" .. b.price))
        btn.Parent = btnArea
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
        Instance.new("UITextSizeConstraint", btn).MaxTextSize = 15
        if bundleLock then
            btn.BackgroundColor3 = Color3.fromRGB(126, 92, 214)   -- 번들 보라
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Text = "🔒 Frost Lord" .. string.char(10) .. "R$799"
            btn.AutoButtonColor = true
        end
        if bundleLock then
            btn.MouseButton1Click:Connect(function()
                MarketplaceService:PromptGamePassPurchase(player, b.bundlePass)
            end)
        elseif not disabled then
            btn.MouseButton1Click:Connect(function()
                purchaseEvent:FireServer(b.id, currentTab, b.itemType)
            end)
        end
    end
    -- 리스트 선택 하이라이트
    for _, row in ipairs(itemScroll:GetChildren()) do
        if row:IsA("TextButton") then
            local rs = row:FindFirstChildOfClass("UIStroke")
            if rs then
                rs.Thickness = (row.Name == key) and 2.5 or 1
                rs.Color = (row.Name == key) and accentColor() or Color3.fromRGB(55,62,82)
            end
        end
    end
end

-- ── 좌측 리스트 미니행 ────────────────────────────────────────
local function createListRow(cd)
    local row = Instance.new("TextButton")
    row.Name = cd.key
    row.Size = UDim2.new(1, 0, 0, 52)
    row.BackgroundColor3 = Color3.fromRGB(34, 40, 56)
    row.AutoButtonColor = true
    row.Text = ""
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
    local rs = Instance.new("UIStroke"); rs.Color = Color3.fromRGB(55,62,82); rs.Thickness = 1; rs.Parent = row

    local th = Instance.new("Frame")
    th.Size = UDim2.new(0, 42, 0, 42); th.Position = UDim2.new(0, 5, 0.5, -21)
    th.BackgroundColor3 = Color3.fromRGB(18,21,30); th.Parent = row
    Instance.new("UICorner", th).CornerRadius = UDim.new(0, 6)
    buildThumbnail(th, cd.thumbItem)

    local nm = Instance.new("TextLabel")
    nm.Size = UDim2.new(1, -110, 0, 20); nm.Position = UDim2.new(0, 54, 0, 7)
    nm.BackgroundTransparency = 1; nm.Text = cd.name
    nm.TextColor3 = Color3.fromRGB(240,244,250); nm.Font = Enum.Font.BuilderSansMedium
    nm.TextXAlignment = Enum.TextXAlignment.Left; nm.TextScaled = true; nm.Parent = row
    Instance.new("UITextSizeConstraint", nm).MaxTextSize = 13

    local minPrice = math.huge
    for _, b in ipairs(cd.buttons) do minPrice = math.min(minPrice, b.price) end
    local pr = Instance.new("TextLabel")
    pr.Size = UDim2.new(1, -58, 0, 16); pr.Position = UDim2.new(0, 54, 0, 28)
    pr.BackgroundTransparency = 1
    pr.Text = (#cd.buttons > 1 and "💰" .. minPrice .. "~" or "💰" .. minPrice)
    pr.TextColor3 = Color3.fromRGB(235,200,90); pr.Font = Enum.Font.BuilderSansExtraBold
    pr.TextXAlignment = Enum.TextXAlignment.Left; pr.TextScaled = true; pr.Parent = row
    Instance.new("UITextSizeConstraint", pr).MaxTextSize = 12
    if cd.thumbItem and cd.thumbItem.bundlePass then
        pr.Text = "🔒 R$799"; pr.TextColor3 = Color3.fromRGB(190, 160, 255)
    end

    local fac = cd.thumbItem and cd.thumbItem.faction
    if fac then
        local fb = Instance.new("TextLabel")
        fb.Size = UDim2.new(0, 50, 0, 15); fb.Position = UDim2.new(1, -54, 0, 6)
        fb.BackgroundColor3 = (fac == "tagger") and Color3.fromRGB(190, 60, 60) or Color3.fromRGB(55, 110, 200)
        fb.BackgroundTransparency = 0.1
        fb.Text = (fac == "tagger") and "KING" or "RUNNER"
        fb.TextColor3 = Color3.fromRGB(255, 255, 255)
        fb.Font = Enum.Font.BuilderSansExtraBold; fb.TextScaled = true; fb.Parent = row
        Instance.new("UICorner", fb).CornerRadius = UDim.new(0, 4)
        Instance.new("UITextSizeConstraint", fb).MaxTextSize = 9
    end
    -- 보유 항목: 살짝 어둡게 (Active=false라 클릭은 통과 → 선택 가능)
    local owned = false
    for _, b in ipairs(cd.buttons) do
        if b.itemType == "permanent" and player:GetAttribute("OwnedItem_" .. b.id) then
            owned = true; break
        end
    end
    if owned then
        local dim = Instance.new("Frame")
        dim.Size = UDim2.fromScale(1, 1)
        dim.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
        dim.BackgroundTransparency = 0.45
        dim.BorderSizePixel = 0
        dim.Active = false
        dim.ZIndex = 8
        Instance.new("UICorner", dim).CornerRadius = UDim.new(0, 8)
        dim.Parent = row
    end
    row.MouseButton1Click:Connect(function() selectItem(cd.key) end)
    return row
end

-- ── 목록 표시 (필터 없이 전체 → SKU 묶기 → 좌측 리스트) ──────
-- ── 서브필터(종류 칩) 상태 ────────────────────────────────────
local currentSub = nil   -- nil = 필터 없음(전체)
local SUB_LABEL = { item = "ITEM", weapon = "WEAPON", effect = "EFFECT", emote = "EMOTE", trail = "TRAIL", crown = "CROWN", dash = "DASH",
    -- ITEM COLOR 색놀이: 108종이라 한 칩에 몰면 스크롤 지옥 → 팩션·종류로 분리 (서버가 sub을 이렇게 부여)
    -- ⚠️ [2026-08-27] 진영 접두어(KING/RUNNER) 제거. 탭 자체가 이미 진영을 말해주므로 중복이었다.
    --    라벨 규칙: 접미사 COLOR = "이미 가진 것의 색 변형" / 접미사 없음 = "그 자체가 물건".
    --    (DASH·TRAIL·CROWN 은 그 자체가 코스메틱이라 접미사가 없다)
    --    "SKIN" 대신 "COLOR" 인 이유: 실제로 팔레트 스왑이고, 서버 로그·sub 접두어(ic_ = item color)도
    --    이미 color 라고 부른다. WEAPON / WEAPON COLOR 처럼 나란히 두면 구분이 즉시 선다.
    ic_tagger_item   = "ITEM COLOR",
    ic_tagger_weapon = "FIST COLOR",
    ic_runner_weapon = "WEAPON COLOR",
}

local function displayItems()
    for _, c in ipairs(itemScroll:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    currentCards = {}

    local cards, baseIndex = {}, {}
    for _, item in ipairs(allItems) do
        local subOk = (currentSub == nil) or (item.sub or "item") == currentSub
        if subOk and item.baseId then
            local idx = baseIndex[item.baseId]
            if not idx then
                table.insert(cards, {key = item.baseId, name = item.name, short = item.short, desc = item.desc, thumbItem = item, buttons = {}})
                idx = #cards; baseIndex[item.baseId] = idx
            end
            table.insert(cards[idx].buttons, {id = item.id, price = item.price, itemType = item.itemType, label = (item.itemType == "permanent") and "Permanent" or "1 Round"})
        elseif subOk then
            table.insert(cards, {key = item.id, name = item.displayName or item.name, short = item.short, desc = item.desc, thumbItem = item,
                buttons = {{id = item.id, price = item.price, itemType = item.itemType, label = nil, bundlePass = item.bundlePass}}})
        end
    end
    for _, cd in ipairs(cards) do
        if #cd.buttons == 2 then table.sort(cd.buttons, function(a, _) return a.itemType == "consumable" end) end
    end

    for i, cd in ipairs(cards) do
        currentCards[cd.key] = cd
        local row = createListRow(cd)
        row.LayoutOrder = i
        row.Parent = itemScroll
    end

    local rowH, rowPad = 52, 6
    itemScroll.CanvasSize = UDim2.fromOffset(0, #cards * (rowH + rowPad) + 12)
    print("[Shop] tab=", currentTab, "cards=", #cards, "scrollW=", itemScroll.AbsoluteSize.X)

    if cards[1] then selectItem(cards[1].key) end
end

-- allItems에서 종류(sub) 칩 생성 + currentSub 결정. sub 1개면 필터 숨김.
local function buildSubFilters()
    -- 칩 8개 × 82px + 패딩 = ~700px. 모바일 패널 폭(~370px)에 1줄로 안 들어가고,
    -- 2줄로 해도 4개/줄이라 칩이 하나만 늘면 3줄이 됨 → 가로 스크롤이 유일하게 확장 가능.
    -- filterContainer는 Frame이라 클래스를 못 바꿈 → 안에 ScrollingFrame을 넣고 칩을 거기 담는다.
    -- (UIListLayout + 고정 픽셀 조합이라 "그리드+Scale 셀" 폭주 함정과 무관)
    -- StarterGui 템플릿에 디자이너가 박아둔 칩 4개(FilterAll/FilterSkin/FilterKillEffect/FilterEmote)가 있음.
    -- 원래 코드가 매번 destroy하던 것 — chipScroll로 옮기면서 빠뜨리면 이중으로 보임.
    for _, c in ipairs(filterContainer:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    local chipScroll = filterContainer:FindFirstChild("_ChipScroll")
    if not chipScroll then
        chipScroll = Instance.new("ScrollingFrame")
        chipScroll.Name = "_ChipScroll"
        chipScroll.Size = UDim2.fromScale(1, 1)
        chipScroll.BackgroundTransparency = 1
        chipScroll.BorderSizePixel = 0
        chipScroll.ScrollBarThickness = 3
        chipScroll.ScrollBarImageTransparency = 0.5
        chipScroll.ScrollingDirection = Enum.ScrollingDirection.X
        chipScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
        chipScroll.CanvasSize = UDim2.new()
        chipScroll.Parent = filterContainer
    end
    local flayout = chipScroll:FindFirstChildOfClass("UIListLayout")
    if not flayout then
        flayout = Instance.new("UIListLayout")
        flayout.FillDirection = Enum.FillDirection.Horizontal
        flayout.Padding = UDim.new(0, 6)
        flayout.VerticalAlignment = Enum.VerticalAlignment.Center
        flayout.SortOrder = Enum.SortOrder.LayoutOrder
        flayout.Parent = chipScroll
    end
    for _, c in ipairs(chipScroll:GetChildren()) do
        if c:IsA("TextButton") then c:Destroy() end
    end
    local seen, subs = {}, {}
    for _, it in ipairs(allItems) do
        local s = it.sub or "item"
        if not seen[s] then seen[s] = true; subs[#subs + 1] = s end
    end
    -- 칩 표시 순서: 공용 → 러너(trail/dash/runner wpn 인접) → 태거(crown/king item/king fist 인접)
    -- ic_* 미등록 시 셋 다 99가 되어 table.sort가 동점을 임의 배치 → 칩 순서가 매번 바뀜. 명시 등록 필수.
    local SUB_ORDER = { item = 1, weapon = 2, effect = 3, emote = 4,
        trail = 5, dash = 6, ic_runner_weapon = 7,
        crown = 8, ic_tagger_item = 9, ic_tagger_weapon = 10 }
    table.sort(subs, function(a, b) return (SUB_ORDER[a] or 99) < (SUB_ORDER[b] or 99) end)
    if #subs <= 1 then
        filterContainer.Visible = false
        currentSub = nil
        return
    end
    filterContainer.Visible = true
    local valid = false
    for _, s in ipairs(subs) do if s == currentSub then valid = true break end end
    if not valid then currentSub = subs[1] end
    local chips = {}
    local function highlight()
        for s, btn in pairs(chips) do
            btn.BackgroundColor3 = (s == currentSub) and Color3.fromRGB(70, 130, 210) or Color3.fromRGB(38, 42, 54)
        end
    end
    for i, s in ipairs(subs) do
        local chip = Instance.new("TextButton")
        chip.Size = UDim2.new(0, 82, 1, -6)
        chip.LayoutOrder = i
        chip.Text = SUB_LABEL[s] or string.upper(s)
        chip.Font = Enum.Font.BuilderSansExtraBold
        chip.TextScaled = true
        chip.TextColor3 = Color3.fromRGB(230, 235, 245)
        chip.BorderSizePixel = 0
        chip.Parent = chipScroll
        Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 6)
        Instance.new("UITextSizeConstraint", chip).MaxTextSize = 13
        chips[s] = chip
        chip.MouseButton1Click:Connect(function()
            currentSub = s
            highlight()
            displayItems()
        end)
    end
    highlight()
end

-- 탭 로드: fetch → 칩 생성 → 필터 렌더
local function loadTab()
    local items = getItemsEvent:InvokeServer(currentTab)
    allItems = items or {}
    buildSubFilters()
    displayItems()
end

local function switchTab(t)
    currentTab = t
    updateTabs()
    loadTab()
end

runnerTab.MouseButton1Click:Connect(function() switchTab("runner") end)
taggerTab.MouseButton1Click:Connect(function() switchTab("tagger") end)
skinTab.MouseButton1Click:Connect(function() switchTab("skin") end)

local function openShop()
    mainFrame.Visible = true
    local sg = mainFrame:FindFirstAncestorWhichIsA("ScreenGui")
    if sg then sg.DisplayOrder = 20 end   -- 인벤(10) 위로 겹치게
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.Size = UDim2.new(0, 700, 0, 500)
    mainFrame.BackgroundTransparency = 0
    switchTab("runner")
end
local function closeShop() mainFrame.Visible = false end
closeBtn.MouseButton1Click:Connect(closeShop)
openShopEvent.OnClientEvent:Connect(openShop)
_G.openCoinShop = openShop   -- HUD Shop 버튼 등 외부에서 코인샵 열기

-- LoadoutPreview / 인벤 재사용: 상점 열고 특정 아이템으로 점프(이름 매칭). x0 구매 유도용.
-- ⚠ openShop()은 항상 switchTab("runner")를 하므로, 태거 아이템으로 점프하려면 tabHint가 필요함.
--   (없으면 Spear를 요청해도 러너 탭이 열려서 못 찾음)
_G.OpenShopToItem = function(itemName, subHint, tabHint)
    if subHint then currentSub = subHint end   -- 원하는 서브탭 미리 지정(weapon 등) → buildSubFilters가 유지
    openShop()   -- Visible + switchTab("runner")
    if tabHint and tabHint ~= "runner" then
        if subHint then currentSub = subHint end   -- switchTab이 리셋했을 수 있으니 재지정
        switchTab(tabHint)
    end
    for key, cd in pairs(currentCards) do
        if cd.name == itemName then selectItem(key); return true end
    end
    return false
end

local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.Escape and mainFrame.Visible then closeShop() end
end)

-- 구매 알림
local purchaseResultEvent = ReplicatedStorage:WaitForChild("ShopPurchaseResult")
local function showNotification(success, message)
    local ex = mainFrame:FindFirstChild("PurchaseNotif"); if ex then ex:Destroy() end
    local notif = Instance.new("Frame")
    notif.Name = "PurchaseNotif"; notif.Size = UDim2.new(0,280,0,50); notif.Position = UDim2.new(0.5,-140,0,10)
    notif.BackgroundColor3 = success and Color3.fromRGB(40,160,70) or Color3.fromRGB(180,50,50)
    notif.BackgroundTransparency = 0.1; notif.ZIndex = 10; notif.Parent = mainFrame
    Instance.new("UICorner", notif).CornerRadius = UDim.new(0,8)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1,-10,1,0); label.Position = UDim2.new(0,5,0,0); label.BackgroundTransparency = 1
    label.Text = (success and "✅ " or "❌ ") .. message; label.TextColor3 = Color3.fromRGB(255,255,255)
    label.TextSize = 14; label.Font = Enum.Font.BuilderSansExtraBold; label.TextScaled = true; label.ZIndex = 11; label.Parent = notif
    if success then
        task.delay(0.3, function()
            local keep = selectedKey
            displayItems()
            if keep and currentCards[keep] then selectItem(keep) end
        end)
    end
    task.delay(2, function()
        if notif and notif.Parent then
            TweenService:Create(notif, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
            TweenService:Create(label, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
            task.delay(0.3, function() if notif and notif.Parent then notif:Destroy() end end)
        end
    end)
end
purchaseResultEvent.OnClientEvent:Connect(function(success, message)
    showNotification(success, message)
    if success then
        if selectedKey then selectItem(selectedKey) end                 -- 상점 버튼 갱신(영구 구매 시 1판 잠금 등)
        if _G.LoadoutPreviewRefresh then _G.LoadoutPreviewRefresh() end  -- LoadoutPreview 재고 뱃지 실시간 갱신
    end
end)

print("✅ ShopClient 준비! (리스트 + 프리뷰)")
