local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

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

-- _G 스텁 (HudButtonClient fallback용)
_G.openEffectInven  = function()
	local c = script.Parent:FindFirstChild("Canvas")
	if c then c.Visible = true end
end
_G.closeEffectInven = function()
	local c = script.Parent:FindFirstChild("Canvas")
	if c then c.Visible = false end
end

local sg        = script.Parent
local canvas    = sg:WaitForChild("Canvas")
local main      = canvas:WaitForChild("Main")
local container = main:WaitForChild("Container")
local closeBtn  = main:WaitForChild("Close")
local equipBtn  = main:WaitForChild("EquipBtn")
local infoPanel = main:WaitForChild("InfoPanel")
local nameLabel = infoPanel:WaitForChild("NameLabel")
local descLabel = infoPanel:WaitForChild("DescLabel")
local rarityLabel = infoPanel:WaitForChild("RarityLabel")
local warnFrame = main:WaitForChild("_EquipWarning")
local warnMsg   = warnFrame:WaitForChild("_WarnMsg")

local getEffectData     = ReplicatedStorage:WaitForChild("GetEffectData")
local setEquippedEffect = ReplicatedStorage:WaitForChild("SetEquippedEffect")

canvas.Visible = false

-- ── 상태 ──────────────────────────────────────────────────────
local selectedItem  = nil   -- 현재 선택된 아이템
local cachedItems   = {}    -- 서버에서 받은 아이템 목록
local slotMap       = {}    -- { Frame → itemData }
local warningThread = nil
local warningTween  = nil

-- ── 레어리티 색상 ─────────────────────────────────────────────
local rarityColor = {
	Normal    = Color3.fromRGB(180, 180, 180),
	Rare      = Color3.fromRGB(80,  200, 80),
	Epic      = Color3.fromRGB(160, 80,  220),
	Legendary = Color3.fromRGB(255, 180, 0),
}

-- ── 경고 ──────────────────────────────────────────────────────
local function showWarning(msg)
	warnMsg.Text = msg
	if warningTween  then warningTween:Cancel() end
	if warningThread then task.cancel(warningThread) end
	warnFrame.BackgroundTransparency = 0.1
	warnFrame.Visible = true
	warningThread = task.delay(1.5, function()
		warningTween = TweenService:Create(warnFrame,
			TweenInfo.new(0.4), {BackgroundTransparency = 1})
		warningTween:Play()
		warningTween.Completed:Connect(function()
			warnFrame.Visible = false
			warnFrame.BackgroundTransparency = 0.1
		end)
	end)
end

-- ── 정보 패널 업데이트 ─────────────────────────────────────────
local function updateInfoPanel(itemData)
	if not itemData then
		infoPanel.Visible = false
		equipBtn.Visible  = false
		return
	end

	nameLabel.Text  = itemData.icon .. "  " .. itemData.name
	descLabel.Text  = itemData.desc or ""
	rarityLabel.Text = itemData.rarity or ""
	rarityLabel.TextColor3 = rarityColor[itemData.rarity] or rarityColor.Normal

	if itemData.owned then
		equipBtn.Visible = true
		if itemData.equipped then
			equipBtn.Text = "Unequip"
			equipBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
		else
			equipBtn.Text = "Equip"
			equipBtn.BackgroundColor3 = Color3.fromRGB(60, 200, 80)
		end
	else
		equipBtn.Visible = false
	end

	infoPanel.Visible = true
end

-- ── 슬롯 하이라이트 ───────────────────────────────────────────
local function highlightSlot(slot)
	for s, _ in pairs(slotMap) do
		local stroke = s:FindFirstChildWhichIsA("UIStroke")
		if stroke then stroke.Thickness = 1.5 end
		s.BackgroundColor3 = Color3.fromRGB(30, 15, 50)
	end
	if slot then
		local stroke = slot:FindFirstChildWhichIsA("UIStroke")
		if stroke then stroke.Thickness = 3.5 end
		slot.BackgroundColor3 = Color3.fromRGB(70, 30, 120)
	end
end

-- ── 슬롯 체크마크 갱신 ────────────────────────────────────────
local function refreshCheckmarks()
	for slot, item in pairs(slotMap) do
		local check = slot:FindFirstChild("_CheckMark")
		if check then check.Visible = item.equipped end
	end
end

-- ── 슬롯 채우기 ───────────────────────────────────────────────
local function populateSlots(items)
	-- 기존 슬롯 제거
	for _, c in ipairs(container:GetChildren()) do
		if not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	slotMap = {}
	selectedItem = nil
	infoPanel.Visible = false
	equipBtn.Visible  = false

	for _, item in ipairs(items) do
		-- 슬롯 프레임
		local slot = Instance.new("Frame")
		slot.Name = "Slot_" .. item.id
		slot.Size = UDim2.new(0, 90, 0, 90)
		slot.BackgroundColor3 = Color3.fromRGB(30, 15, 50)
		slot.BorderSizePixel = 0
		slot.ZIndex = 3
		slot.Parent = container
		Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 10)

		-- 테두리
		local stroke = Instance.new("UIStroke", slot)
		stroke.Color = item.owned
			and (rarityColor[item.rarity] or Color3.fromRGB(160, 80, 220))
			or  Color3.fromRGB(70, 70, 70)
		stroke.Thickness = 1.5

		-- 이모지 아이콘
		local icon = Instance.new("TextLabel", slot)
		icon.Size = UDim2.new(1, 0, 0.6, 0)
		icon.Position = UDim2.new(0, 0, 0.05, 0)
		icon.BackgroundTransparency = 1
		icon.Text = item.icon
		icon.TextScaled = true
		icon.ZIndex = 4

		-- 이름
		local nameLbl = Instance.new("TextLabel", slot)
		nameLbl.Size = UDim2.new(1, -4, 0.3, 0)
		nameLbl.Position = UDim2.new(0, 2, 0.68, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = item.name
		nameLbl.TextColor3 = item.owned
			and Color3.fromRGB(230, 210, 255)
			or  Color3.fromRGB(100, 100, 100)
		nameLbl.TextScaled = true
		nameLbl.Font = Enum.Font.Gotham
		nameLbl.ZIndex = 4

		-- 잠금 오버레이
		if not item.owned then
			local lock = Instance.new("TextLabel", slot)
			lock.Size = UDim2.new(1, 0, 1, 0)
			lock.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			lock.BackgroundTransparency = 0.5
			lock.Text = "🔒"
			lock.TextScaled = true
			lock.ZIndex = 5
			Instance.new("UICorner", lock).CornerRadius = UDim.new(0, 10)
		end

		-- 체크마크 (장착 중 표시)
		local check = Instance.new("Frame", slot)
		check.Name = "_CheckMark"
		check.Size = UDim2.new(0.32, 0, 0.32, 0)
		check.AnchorPoint = Vector2.new(1, 0)
		check.Position = UDim2.new(1, -3, 0, 3)
		check.BackgroundColor3 = Color3.fromRGB(30, 180, 60)
		check.BackgroundTransparency = 0
		check.ZIndex = 6
		check.Visible = item.equipped
		Instance.new("UICorner", check).CornerRadius = UDim.new(0.5, 0)
		local chkTxt = Instance.new("TextLabel", check)
		chkTxt.Size = UDim2.new(1, 0, 1, 0)
		chkTxt.BackgroundTransparency = 1
		chkTxt.Text = "✔"
		chkTxt.TextScaled = true
		chkTxt.TextColor3 = Color3.fromRGB(255, 255, 255)
		chkTxt.Font = Enum.Font.GothamBold
		chkTxt.ZIndex = 7

		-- 클릭
		local clickBtn = Instance.new("TextButton", slot)
		clickBtn.Size = UDim2.new(1, 0, 1, 0)
		clickBtn.BackgroundTransparency = 1
		clickBtn.Text = ""
		clickBtn.ZIndex = 8

		local capturedItem = item
		local capturedSlot = slot
		slotMap[slot] = item

		clickBtn.MouseButton1Click:Connect(function()
			if not capturedItem.owned then
				showWarning("You don't own this item!")
				return
			end
			selectedItem = capturedItem
			highlightSlot(capturedSlot)
			updateInfoPanel(capturedItem)
		end)
	end
end

-- ── 데이터 로드 ────────────────────────────────────────────────
local function loadData()
	local data = getEffectData:InvokeServer("killEffect")
	cachedItems = data or {}
	populateSlots(cachedItems)
end

-- ── Equip 버튼 클릭 ───────────────────────────────────────────
equipBtn.MouseButton1Click:Connect(function()
	if not selectedItem then return end
	setEquippedEffect:FireServer("killEffect", selectedItem.id)
	-- 로컬 즉시 반영
	local wasEquipped = selectedItem.equipped
	for _, item in ipairs(cachedItems) do
		item.equipped = false
	end
	selectedItem.equipped = not wasEquipped
	refreshCheckmarks()
	updateInfoPanel(selectedItem)
end)

-- ── 열기 / 닫기 ───────────────────────────────────────────────
local function openInven()
	canvas.Visible = true
	loadData()
end

local function closeInven()
	canvas.Visible = false
	selectedItem = nil
	if warningThread then task.cancel(warningThread) end
	warnFrame.Visible = false
end

_G.openEffectInven  = openInven
_G.closeEffectInven = closeInven

closeBtn.MouseButton1Click:Connect(closeInven)

print("✅ EffectInvenClient ready!")
