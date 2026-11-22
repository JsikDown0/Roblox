--majority of code by TakeoHonorable
local Tool = script.Parent

local Remote = Tool:WaitForChild("Remote",10)

local MouseInput = Tool:WaitForChild("MouseInput",10)

local Services = {
	Players = (game:FindService("Players") or game:GetService("Players")),
	TweenService = (game:FindService("TweenService") or game:GetService("TweenService")),
	RunService = (game:FindService("RunService") or game:GetService("RunService")),
	Input = (game:FindService("ContextActionService") or game:GetService("ContextActionService"))
}

local Player,Character,Humanoid

function SwordPrimary(actionName, inputState, inputObj)
	if inputState == Enum.UserInputState.Begin then 
		Remote:FireServer(Enum.KeyCode.Q)
	end
end

function SwordSecondary(actionName, inputState, inputObj)
	if inputState == Enum.UserInputState.Begin then 
		Remote:FireServer(Enum.KeyCode.E)
	end
end

function SwordTertiary(actionName, inputState, inputObj)
	if inputState == Enum.UserInputState.Begin then 
		Remote:FireServer(Enum.KeyCode.X)
	end
end

function Equipped()
	Player = Services.Players.LocalPlayer
	Character = Player.Character
	Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid or not Humanoid.Parent or Humanoid.Health <= 0 then return end

	-- [특수기 비활성 보존] 특수기 입력 바인딩 해제. Q키는 산데비스탄(대시) 전용으로 둠.
	-- 나중에 특수기 부활 시 아래 주석을 풀고, 산데비스탄과 안 겹치는 키로 변경할 것.
	--Services.Input:BindAction("SwordPrimary",SwordPrimary,true,Enum.KeyCode.Q,Enum.KeyCode.ButtonX)
	--Services.Input:BindAction("SwordSecondary",SwordSecondary,true,Enum.KeyCode.E,Enum.KeyCode.ButtonY)
	--Services.Input:BindAction("SwordTertiary",SwordTertiary,true,Enum.KeyCode.X,Enum.KeyCode.ButtonL1)
	--Services.Input:SetTitle("SwordPrimary","Diamond Rain")
	--Services.Input:SetTitle("SwordSecondary","Crystal Smash")
	--Services.Input:SetTitle("SwordTertiary","none")
	--Services.Input:SetPosition("SwordPrimary",UDim2.new(.5,0,-.5,0))
	--Services.Input:SetPosition("SwordSecondary",UDim2.new(.5,0,-.25,0))
	--Services.Input:SetPosition("SwordTertiary",UDim2.new(.5,0,0,0))
end

function Unequipped()
	Services.Input:UnbindAction("SwordPrimary")
	--Services.Input:UnbindAction("SwordSecondary")	
	--Services.Input:UnbindAction("SwordTertiary")		
end

Tool.Equipped:Connect(Equipped)
Tool.Unequipped:Connect(Unequipped)


function MouseInput.OnClientInvoke()
	return game.Players.LocalPlayer:GetMouse().Hit.p
end

-- ════════════════════════════════════════════════════════════
-- 데미지 / 콤보 표시 (타격감 연출)
-- 서버 SwordHit이 Remote:FireClient(plr, "hitFX", dmg, step, isFinisher, pos)로 전송
-- ════════════════════════════════════════════════════════════
local TweenService = game:GetService("TweenService")
local LocalPlayer = game.Players.LocalPlayer

-- 콤보 카운터 UI (화면 중앙 우측, 콤보 유지 중에만 표시)
local comboGui = Instance.new("ScreenGui")
comboGui.Name = "DiamondComboGui"
comboGui.ResetOnSpawn = true  -- 사망 리스폰 시 자동 정리 (UI 잔재 방지)
comboGui.IgnoreGuiInset = true
comboGui.DisplayOrder = 50
comboGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local comboLabel = Instance.new("TextLabel")
comboLabel.Size = UDim2.new(0.16, 0, 0.08, 0)
comboLabel.Position = UDim2.new(0.5, 0, 0.22, 0)
comboLabel.AnchorPoint = Vector2.new(0.5, 0.5)
comboLabel.BackgroundTransparency = 1
comboLabel.Font = Enum.Font.LuckiestGuy
comboLabel.TextScaled = true
comboLabel.TextColor3 = Color3.fromRGB(120, 220, 255)
comboLabel.TextStrokeColor3 = Color3.fromRGB(0, 30, 60)
comboLabel.TextStrokeTransparency = 0.2
comboLabel.Text = ""
comboLabel.Visible = false
comboLabel.Parent = comboGui

local comboHideTask = nil
local function showCombo(count)
	comboLabel.Text = count .. " HIT"
	comboLabel.Visible = true
	if count >= 3 then
		comboLabel.TextColor3 = Color3.fromRGB(255, 215, 60)   -- 완성(3타) 금색
		comboLabel.Text = count .. " HIT!"
	else
		comboLabel.TextColor3 = Color3.fromRGB(120, 220, 255)  -- 1·2타 파랑
	end
	comboLabel.TextTransparency = 0
	comboLabel.TextStrokeTransparency = 0.2
	local base = UDim2.new(0.16, 0, 0.08, 0)
	comboLabel.Size = UDim2.new(0.18, 0, 0.09, 0)
	TweenService:Create(comboLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = base}):Play()
	if comboHideTask then task.cancel(comboHideTask) end
	comboHideTask = task.delay(1.0, function()
		local fade = TweenService:Create(comboLabel, TweenInfo.new(0.25), {TextTransparency = 1, TextStrokeTransparency = 1})
		fade:Play()
		fade.Completed:Wait()
		comboLabel.Visible = false
	end)
end

-- 데미지 숫자 (타격 위치에서 떠오르며 페이드)
local function popDamage(dmg, isFinisher, worldPos)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = worldPos + Vector3.new(math.random(-15,15)/10, 2, math.random(-15,15)/10)
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 200, 0, 100)
	bb.AlwaysOnTop = true
	bb.Parent = anchor

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.LuckiestGuy
	lbl.TextScaled = true
	-- 🔢 [2026-09-02] 정수로 반올림. CC 중 환산값(_G.DisplayDamage)이 소수로 오기 때문.
	--   ⚠️ 표시에서만 반올림한다. 판정값은 서버가 원본으로 처리한다.
	lbl.Text = tostring(math.floor(dmg + 0.5))
	lbl.TextStrokeTransparency = 0
	if isFinisher then
		lbl.TextColor3 = Color3.fromRGB(255, 215, 60)   -- 피니셔 금색
		lbl.TextStrokeColor3 = Color3.fromRGB(120, 60, 0)
		bb.Size = UDim2.new(0, 280, 0, 140)             -- 피니셔 더 크게
	else
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.TextStrokeColor3 = Color3.fromRGB(40, 40, 40)
	end
	lbl.Parent = bb

	-- 위로 떠오르며 페이드 (오래 보이게)
	local riseTween = TweenService:Create(anchor, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = anchor.Position + Vector3.new(0, 4.5, 0)})
	local fadeTween = TweenService:Create(lbl, TweenInfo.new(0.9), {TextTransparency = 1, TextStrokeTransparency = 1})
	riseTween:Play()
	fadeTween:Play()
	fadeTween.Completed:Connect(function() anchor:Destroy() end)
	game:GetService("Debris"):AddItem(anchor, 1.2)
end

Remote.OnClientEvent:Connect(function(kind, ...)
	if kind == "hitFX" then
		local dmg, step, isFinisher, worldPos = ...
		popDamage(dmg, isFinisher, worldPos or Vector3.new())
	elseif kind == "markHit" then
		local idx, count = ...
		showCombo(count or 1)   -- 표식 타수(1타/2타/3타) 표기
	end
end)
