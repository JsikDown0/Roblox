-- ODM Gear 충전 UI: 우측 하단에 3개 dot 표시
local Tool = script.Parent
local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local FILLED_COLOR = Color3.fromRGB(255, 200, 80)   -- 주황 (남은 충전)
local EMPTY_COLOR  = Color3.fromRGB(60, 60, 60)     -- 회색 (소진)
local TEXT_COLOR   = Color3.fromRGB(255, 220, 130)

local screenGui = nil
local dots = {}
local label = nil

local function updateDisplay()
	if not screenGui then return end
	local charges = Tool:GetAttribute("Charges") or 0
	local maxCharges = Tool:GetAttribute("MaxCharges") or 3
	for i = 1, maxCharges do
		local dot = dots[i]
		if dot then
			if i <= charges then
				dot.BackgroundColor3 = FILLED_COLOR
				dot.BackgroundTransparency = 0
				local stroke = dot:FindFirstChildOfClass("UIStroke")
				if stroke then stroke.Transparency = 0 end
			else
				dot.BackgroundColor3 = EMPTY_COLOR
				dot.BackgroundTransparency = 0.3
				local stroke = dot:FindFirstChildOfClass("UIStroke")
				if stroke then stroke.Transparency = 0.6 end
			end
		end
	end
	if label then
		label.Text = "GRAPPLE  " .. charges .. " / " .. maxCharges
	end
end

local function createUI()
	if screenGui then return end
	local pg = Player:WaitForChild("PlayerGui")
	-- 이전 인스턴스 잔존 시 청소 (사망/재접속 등 비정상 경로 대비)
	local stale = pg:FindFirstChild("GrappleChargeUI")
	if stale then stale:Destroy() end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GrappleChargeUI"
	screenGui.ResetOnSpawn = true  -- 사망 리스폰 시 자동 정리 (UI 잔재 방지)
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = pg

	-- 컨테이너 (하단 중앙)
	local container = Instance.new("Frame", screenGui)
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -180)
	container.Size = UDim2.fromOffset(160, 56)
	container.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	container.BackgroundTransparency = 0.25
	container.BorderSizePixel = 0

	local corner = Instance.new("UICorner", container)
	corner.CornerRadius = UDim.new(0, 10)

	local stroke = Instance.new("UIStroke", container)
	stroke.Color = FILLED_COLOR
	stroke.Thickness = 1.5
	stroke.Transparency = 0.5

	-- 라벨 (상단)
	label = Instance.new("TextLabel", container)
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 4)
	label.Size = UDim2.new(1, -8, 0, 16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.TextColor3 = TEXT_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = "GRAPPLE 3 / 3"

	-- Dot 컨테이너
	local dotRow = Instance.new("Frame", container)
	dotRow.Name = "DotRow"
	dotRow.AnchorPoint = Vector2.new(0.5, 1)
	dotRow.Position = UDim2.new(0.5, 0, 1, -6)
	dotRow.Size = UDim2.new(1, -12, 0, 22)
	dotRow.BackgroundTransparency = 1

	local layout = Instance.new("UIListLayout", dotRow)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	-- 3개 dot
	local maxCharges = Tool:GetAttribute("MaxCharges") or 3
	for i = 1, maxCharges do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.LayoutOrder = i
		dot.Size = UDim2.fromOffset(22, 22)
		dot.BackgroundColor3 = FILLED_COLOR
		dot.BorderSizePixel = 0
		dot.Parent = dotRow

		local dc = Instance.new("UICorner", dot)
		dc.CornerRadius = UDim.new(1, 0)  -- 원형

		local ds = Instance.new("UIStroke", dot)
		ds.Color = Color3.fromRGB(255, 240, 200)
		ds.Thickness = 1
		ds.Transparency = 0.3

		dots[i] = dot
	end

	updateDisplay()
end

local function destroyUI()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
		dots = {}
		label = nil
	end
end

Tool.Equipped:Connect(createUI)
Tool.Unequipped:Connect(destroyUI)
Tool.Destroying:Connect(destroyUI)
Tool:GetAttributeChangedSignal("Charges"):Connect(updateDisplay)

-- Robust depletion cleanup: when charges hit 0 the server destroys the Tool
-- shortly after, but a server-side Tool:Destroy() does NOT reliably fire the
-- in-tool client handlers (Destroying/AncestryChanged) before this script is
-- itself torn down, so the PlayerGui-parented UI can linger. Debris destroys
-- the ScreenGui on its own timer, independent of this script's lifetime.
Tool:GetAttributeChangedSignal("Charges"):Connect(function()
	if (Tool:GetAttribute("Charges") or 0) <= 0 and screenGui then
		game:GetService("Debris"):AddItem(screenGui, 0.4)
	end
end)

-- 사망/캐릭터 제거 시 UI 강제 정리 (Tool.Unequipped 미발동 케이스 보완)
Player.CharacterRemoving:Connect(destroyUI)

-- 캐릭터 내 Humanoid가 죽는 즉시 정리 (CharacterRemoving보다 빠르게)
local function bindCharacterDeath(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(destroyUI)
	end
end
if Player.Character then bindCharacterDeath(Player.Character) end
Player.CharacterAdded:Connect(bindCharacterDeath)
