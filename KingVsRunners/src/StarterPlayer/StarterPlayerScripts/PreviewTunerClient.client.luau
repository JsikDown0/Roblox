-- PreviewTunerClient: 인벤/카드 ViewportFrame 카메라 수동 조정 도구
-- 카메라 = CFrame.new(타겟 + dir*거리, 타겟). 타겟 = 모델중심 + pan*maxDim. 거리 = maxDim*distMul
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
-- 🔒 [출시] dev/스튜디오 전용 게이트 (플레이어 실수 방지, 되돌리기=이 줄 삭제)
if not game:GetService("RunService"):IsStudio() and player.UserId ~= 9228200642 then return end
local playerGui = player:WaitForChild("PlayerGui")

local NL = string.char(10)  -- 줄바꿈 문자

local enabled = false
local cur = nil
local label

local function ensureUI()
	if label then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "PreviewTunerGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999
	label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 780, 0, 74)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -12)
	label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	label.BackgroundTransparency = 0.3
	label.TextColor3 = Color3.fromRGB(255, 228, 120)
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
		local d, t = cur.dir, cur.target
		local l1 = string.format("[TUNE] %s  dist=%.2f  dir=(%.2f, %.2f, %.2f)  pan=(%.2f, %.2f, %.2f)",
			cur.id, cur.distMul, d.X, d.Y, d.Z, t.X, t.Y, t.Z)
		local l2 = "Up/Dn=dist  L/R=dirX  Q/E=dirY  Z/X=dirZ  |  J/L,I/K,U/O=pan(target)  |  Enter=output  P=exit"
		label.Text = l1 .. NL .. l2
	else
		label.Text = "[TUNE ON]  click an item/card thumbnail viewport to select.  P=exit"
	end
end

local function getBounds(subject)
	if subject:IsA("Model") then return subject:GetBoundingBox() end
	if subject:IsA("BasePart") then return subject.CFrame, subject.Size end
	return CFrame.new(), Vector3.new(10, 10, 10)
end

local function updateCam()
	if not (cur and cur.cam and cur.subject) then return end
	local cf, size = getBounds(cur.subject)
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dist = maxDim * cur.distMul
	local tgt = cf.Position + cur.target * maxDim
	cur.cam.CFrame = CFrame.new(tgt + cur.dir * dist, tgt)
end

local function findVP(x, y)
	for _, o in ipairs(playerGui:GetGuiObjectsAtPosition(x, y)) do
		if o:IsA("ViewportFrame") and (o.Name == "_ItemVP" or o.Name == "_SkinVP") then return o end
		if o.Parent then
			local vp = o.Parent:FindFirstChild("_ItemVP", true) or o.Parent:FindFirstChild("_SkinVP", true)
			if vp and vp:IsA("ViewportFrame") then return vp end
		end
	end
	return nil
end

UIS.InputBegan:Connect(function(input, gp)
	local k = input.KeyCode
	if k == Enum.KeyCode.P then
		enabled = not enabled
		_G.previewTunerActive = enabled
		if not enabled then cur = nil end
		refresh()
		return
	end
	if not enabled then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local vp = findVP(input.Position.X, input.Position.Y)
		if vp then
			cur = {
				vp = vp,
				subject = vp:FindFirstChildOfClass("Model") or vp:FindFirstChildWhichIsA("BasePart"),
				cam = vp:FindFirstChildOfClass("Camera"),
				id = vp:GetAttribute("PreviewId") or "?",
				distMul = vp:GetAttribute("_tuneDist") or 2.8,
				dir = vp:GetAttribute("_tuneDir") or Vector3.new(0.3, 0.25, 1),
				target = vp:GetAttribute("_tuneTarget") or Vector3.new(0, 0, 0),
			}
			updateCam()
			refresh()
		end
		return
	end
	if not cur then return end
	local STEP = 0.1
	local PAN  = 0.05
	if k == Enum.KeyCode.Up then cur.distMul = math.max(0.4, cur.distMul - STEP)
	elseif k == Enum.KeyCode.Down then cur.distMul = cur.distMul + STEP
	elseif k == Enum.KeyCode.Left then cur.dir = cur.dir + Vector3.new(-STEP, 0, 0)
	elseif k == Enum.KeyCode.Right then cur.dir = cur.dir + Vector3.new(STEP, 0, 0)
	elseif k == Enum.KeyCode.Q then cur.dir = cur.dir + Vector3.new(0, STEP, 0)
	elseif k == Enum.KeyCode.E then cur.dir = cur.dir + Vector3.new(0, -STEP, 0)
	elseif k == Enum.KeyCode.Z then cur.dir = cur.dir + Vector3.new(0, 0, -STEP)
	elseif k == Enum.KeyCode.X then cur.dir = cur.dir + Vector3.new(0, 0, STEP)
	elseif k == Enum.KeyCode.J then cur.target = cur.target + Vector3.new(-PAN, 0, 0)
	elseif k == Enum.KeyCode.L then cur.target = cur.target + Vector3.new(PAN, 0, 0)
	elseif k == Enum.KeyCode.I then cur.target = cur.target + Vector3.new(0, PAN, 0)
	elseif k == Enum.KeyCode.K then cur.target = cur.target + Vector3.new(0, -PAN, 0)
	elseif k == Enum.KeyCode.U then cur.target = cur.target + Vector3.new(0, 0, -PAN)
	elseif k == Enum.KeyCode.O then cur.target = cur.target + Vector3.new(0, 0, PAN)
	elseif k == Enum.KeyCode.Return then
		local d, t = cur.dir, cur.target
		warn(string.format("[TUNE-OUT] %s | dist=%.2f | dir=Vector3.new(%.3f, %.3f, %.3f) | pan=Vector3.new(%.3f, %.3f, %.3f)",
			cur.id, cur.distMul, d.X, d.Y, d.Z, t.X, t.Y, t.Z))
		if cur.vp then
			cur.vp:SetAttribute("_tuneDist", cur.distMul)
			cur.vp:SetAttribute("_tuneDir", cur.dir)
			cur.vp:SetAttribute("_tuneTarget", cur.target)
		end
		return
	else return end
	updateCam()
	-- 매 조정마다 vp에 저장 → 재클릭해도 튜닝값 안 날아감 (예전엔 Enter 때만 저장)
	if cur.vp then
		cur.vp:SetAttribute("_tuneDist", cur.distMul)
		cur.vp:SetAttribute("_tuneDir", cur.dir)
		cur.vp:SetAttribute("_tuneTarget", cur.target)
	end
	refresh()
end)

print("PreviewTunerClient ready - press P to toggle tune mode")
