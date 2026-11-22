-- ════════════════════════════════════════════════════════════
-- Dragon Fire Sword 데미지/화염 스택 표시 (FXClient)
-- 서버 SwordScript가 FXRemote로 전송:
--   "hitFX", dmg, worldPos, stacks, exploded
--     → 데미지 숫자(튀어오름) + 화염 스택 카운터(N/10) + 폭발 강조
-- ════════════════════════════════════════════════════════════
local Tool = script.Parent
local FXRemote = Tool:WaitForChild("FXRemote")
local TweenService = game:GetService("TweenService")
local LocalPlayer = game.Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "DragonFireFXGui"
gui.ResetOnSpawn = true  -- 사망 리스폰 시 자동 정리 (UI 잔재 방지)
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = PlayerGui

-- ── 화염 스택 카운터 (화면 중앙 위쪽) ────────────────────────
local stackLabel = Instance.new("TextLabel")
stackLabel.Size = UDim2.new(0.18, 0, 0.09, 0)
stackLabel.Position = UDim2.new(0.5, 0, 0.24, 0)
stackLabel.AnchorPoint = Vector2.new(0.5, 0.5)
stackLabel.BackgroundTransparency = 1
stackLabel.Font = Enum.Font.LuckiestGuy
stackLabel.TextScaled = true
stackLabel.TextColor3 = Color3.fromRGB(255, 150, 40)
stackLabel.TextStrokeColor3 = Color3.fromRGB(120, 30, 0)
stackLabel.TextStrokeTransparency = 0.1
stackLabel.Text = ""
stackLabel.Visible = false
stackLabel.Parent = gui

local stackHideTask = nil
local function showStacks(stacks, exploded)
	if exploded then
		stackLabel.Text = "🔥 BURN! 🔥"
		stackLabel.TextColor3 = Color3.fromRGB(255, 80, 0)
	else
		stackLabel.Text = "🔥 " .. stacks .. "/6"
		-- 스택이 높을수록 점점 붉게
		local t = stacks / 6
		stackLabel.TextColor3 = Color3.fromRGB(255, math.floor(180 - 140*t), math.floor(60 - 50*t))
	end
	stackLabel.Visible = true
	stackLabel.TextTransparency = 0
	stackLabel.TextStrokeTransparency = 0.1
	-- 살짝 팝 애니메이션
	local big = exploded and UDim2.new(0.26, 0, 0.13, 0) or UDim2.new(0.2, 0, 0.1, 0)
	local base = UDim2.new(0.18, 0, 0.09, 0)
	stackLabel.Size = big
	TweenService:Create(stackLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = base}):Play()
	if stackHideTask then task.cancel(stackHideTask) end
	stackHideTask = task.delay(exploded and 1.2 or 0.9, function()
		local fade = TweenService:Create(stackLabel, TweenInfo.new(0.25), {TextTransparency = 1, TextStrokeTransparency = 1})
		fade:Play()
		fade.Completed:Wait()
		stackLabel.Visible = false
	end)
end

-- ── 데미지 숫자 (타격 위치에서 떠오르며 페이드) ─────────────
local function popDamage(dmg, worldPos, exploded)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = worldPos + Vector3.new(math.random(-15,15)/10, 2, math.random(-15,15)/10)
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = exploded and UDim2.new(0, 320, 0, 160) or UDim2.new(0, 160, 0, 80)
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
	if exploded then
		lbl.TextColor3 = Color3.fromRGB(255, 80, 0)        -- 폭발(처형) = 강렬한 주황 강조
		lbl.TextStrokeColor3 = Color3.fromRGB(80, 10, 0)
	else
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)      -- 일반 타격 = 흰색
		lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	end
	lbl.Parent = bb

	local riseTween = TweenService:Create(anchor, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = anchor.Position + Vector3.new(0, 4.5, 0)})
	local fadeTween = TweenService:Create(lbl, TweenInfo.new(0.9), {TextTransparency = 1, TextStrokeTransparency = 1})
	riseTween:Play()
	fadeTween:Play()
	fadeTween.Completed:Connect(function() anchor:Destroy() end)
	game:GetService("Debris"):AddItem(anchor, 1.2)
end

FXRemote.OnClientEvent:Connect(function(kind, ...)
	if kind == "hitFX" then
		local dmg, worldPos, stacks, exploded = ...
		-- 폭발 시엔 폭발 데미지(100)를 숫자로 보여줌
		local shownDmg = exploded and 100 or dmg
		popDamage(shownDmg, worldPos or Vector3.new(), exploded)
		showStacks(stacks or 0, exploded)
	end
end)
