-- BadgeTunerClient: 킬이펙트 배지(_IconImg) 크기/위치 수동 조정 도구
-- 인벤 슬롯 배지를 눈으로 맞춘 뒤 값 출력 → EffectSystem KILL_EFFECTS 행에 imgScale/imgOffX/imgOffY로 박기
-- 렌더 기준(UnifiedInvenClient): Size=(scale,scale), Pos=(0.5+offX, 0.5+offY), Anchor=0.5,0.5
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
-- 🔒 [출시] dev/스튜디오 전용 게이트 (플레이어 실수 방지, 되돌리기=이 줄 삭제)
if not game:GetService("RunService"):IsStudio() and player.UserId ~= 9228200642 then return end
local playerGui = player:WaitForChild("PlayerGui")

local NL = string.char(10)

local enabled = false
local cur = nil
local label

local function ensureUI()
	if label then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "BadgeTunerGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999
	label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 720, 0, 74)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -12)
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(140, 220, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextWrapped = true
	label.ZIndex = 50
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 8)
	label.Parent = gui
	gui.Parent = playerGui
end

local function refresh()
	ensureUI()
	if not enabled then label.Visible = false return end
	label.Visible = true
	if cur then
		local l1 = string.format("[BADGE:%s] %s   scale=%.3f  offX=%.3f  offY=%.3f",
			cur.prefix or "img", cur.id, cur.scale, cur.offX, cur.offY)
		local l2 = "Arrows=move   +/-=size   |   Enter=output   B=exit"
		label.Text = l1 .. NL .. l2
	else
		label.Text = "[BADGE TUNE ON]  click a badge in the inventory to select.   B=exit"
	end
end

-- 커서 밑에서 _IconImg(배지 이미지) 찾기 (_ClickBtn이 위에 덮여 있어도 형제에서 회수)
local function findBadge(x, y)
	for _, o in ipairs(playerGui:GetGuiObjectsAtPosition(x, y)) do
		if o:IsA("ImageLabel") and o.Name == "_IconImg" then return o end
		if o.Parent then
			local im = o.Parent:FindFirstChild("_IconImg", true)
			if im and im:IsA("ImageLabel") then return im end
		end
	end
	return nil
end

local function apply()
	if not (cur and cur.img and cur.img.Parent) then return end
	cur.img.Size = UDim2.new(cur.scale, 0, cur.scale, 0)
	cur.img.Position = UDim2.new(0.5 + cur.offX, 0, 0.5 + cur.offY, 0)
end

UIS.InputBegan:Connect(function(input, gp)
	local k = input.KeyCode
	if k == Enum.KeyCode.B and not gp then
		enabled = not enabled
		_G.badgeTunerActive = enabled
		if not enabled then cur = nil end
		refresh()
		return
	end
	if not enabled then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local img = findBadge(input.Position.X, input.Position.Y)
		if img then
			cur = {
				img = img,
				id = img:GetAttribute("effectId") or "?",
				prefix = img:GetAttribute("tunePrefix") or "img",
				scale = img.Size.X.Scale,
				offX = img.Position.X.Scale - 0.5,
				offY = img.Position.Y.Scale - 0.5,
			}
			refresh()
		end
		return
	end

	if not cur then return end
	local MOVE = 0.02
	local SZ = 0.03
	if k == Enum.KeyCode.Left then cur.offX = cur.offX - MOVE
	elseif k == Enum.KeyCode.Right then cur.offX = cur.offX + MOVE
	elseif k == Enum.KeyCode.Up then cur.offY = cur.offY - MOVE
	elseif k == Enum.KeyCode.Down then cur.offY = cur.offY + MOVE
	elseif k == Enum.KeyCode.Equals or k == Enum.KeyCode.KeypadPlus then cur.scale = cur.scale + SZ
	elseif k == Enum.KeyCode.Minus or k == Enum.KeyCode.KeypadMinus then cur.scale = math.max(0.05, cur.scale - SZ)
	elseif k == Enum.KeyCode.Return then
		local p = cur.prefix or "img"
		warn(string.format("[BADGE-TUNE] %s  %sScale = %.3f, %sOffX = %.3f, %sOffY = %.3f",
			cur.id, p, cur.scale, p, cur.offX, p, cur.offY))
		return
	else
		return
	end
	apply()
	refresh()
end)

print("BadgeTunerClient ready - press B to toggle badge tune mode")
