-- ════════════════════════════════════════════════════════════
-- 클래식 소드 데미지/런지 표시 + 타이밍 링 (FXClient)
-- 서버 SwordScript가 FXRemote로 전송:
--   "hitFX", dmg, isLunge, worldPos   → 데미지 숫자(+런지면 금색/LUNGE 라벨)
--   "lungeWindow", windowSec          → 슬래시 후 "지금 또 클릭하면 런지" 타이밍 링
-- ════════════════════════════════════════════════════════════
local Tool = script.Parent
local FXRemote = Tool:WaitForChild("FXRemote")
local TweenService = game:GetService("TweenService")
local LocalPlayer = game.Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "ClassicSwordFXGui"
gui.ResetOnSpawn = true  -- 사망 리스폰 시 자동 정리 (UI 잔재 방지)
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = PlayerGui

-- ── 런지 라벨 (화면 중앙 위쪽, 런지 적중 시만) ──────────────
local lungeLabel = Instance.new("TextLabel")
lungeLabel.Size = UDim2.new(0.16, 0, 0.08, 0)
lungeLabel.Position = UDim2.new(0.5, 0, 0.22, 0)
lungeLabel.AnchorPoint = Vector2.new(0.5, 0.5)
lungeLabel.BackgroundTransparency = 1
lungeLabel.Font = Enum.Font.LuckiestGuy
lungeLabel.TextScaled = true
lungeLabel.TextColor3 = Color3.fromRGB(255, 215, 60)
lungeLabel.TextStrokeColor3 = Color3.fromRGB(120, 60, 0)
lungeLabel.TextStrokeTransparency = 0.2
lungeLabel.Text = ""
lungeLabel.Visible = false
lungeLabel.Parent = gui

local lungeHideTask = nil
local function showLunge()
	lungeLabel.Text = "LUNGE!"
	lungeLabel.Visible = true
	lungeLabel.TextTransparency = 0
	lungeLabel.TextStrokeTransparency = 0.2
	local base = UDim2.new(0.16, 0, 0.08, 0)
	lungeLabel.Size = UDim2.new(0.19, 0, 0.095, 0)
	TweenService:Create(lungeLabel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = base}):Play()
	if lungeHideTask then task.cancel(lungeHideTask) end
	lungeHideTask = task.delay(0.9, function()
		local fade = TweenService:Create(lungeLabel, TweenInfo.new(0.25), {TextTransparency = 1, TextStrokeTransparency = 1})
		fade:Play()
		fade.Completed:Wait()
		lungeLabel.Visible = false
	end)
end

-- ── 데미지 숫자 (타격 위치에서 떠오르며 페이드) ─────────────
local function popDamage(dmg, isLunge, worldPos)
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
	-- 🔢 [2026-09-02] 정수로 반올림해 표시한다.
	--   [왜] CC 중이면 서버가 _G.DisplayDamage 로 환산한 값을 보낸다(아이스보우 ×1/1.43).
	--     8 → 5.594... 처럼 소수가 길게 나와 화면이 지저분하고, 순간적으로 자릿수를
	--     오해할 수 있다("5.594" 를 큰 수로 읽음).
	--   ⚠️ 표시에서만 반올림한다. 판정값은 서버가 원본으로 처리하므로 무관하다.
	lbl.Text = tostring(math.floor(dmg + 0.5))
	lbl.TextStrokeTransparency = 0
	if isLunge then
		lbl.TextColor3 = Color3.fromRGB(255, 215, 60)   -- 런지 금색
		lbl.TextStrokeColor3 = Color3.fromRGB(120, 60, 0)
		bb.Size = UDim2.new(0, 270, 0, 135)             -- 런지 더 크게
	else
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.TextStrokeColor3 = Color3.fromRGB(40, 40, 40)
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
		local dmg, isLunge, worldPos = ...
		popDamage(dmg, isLunge, worldPos or Vector3.new())
		if isLunge then showLunge() end
	end
end)

-- ════════════════════════════════════════════════════════════
-- [LUNGE-SKILL] 평타 = 클릭/탭, 강타(런지) = F키 또는 스킬 버튼
--   ⚠️ 예전엔 "0.4초 안에 두 번 클릭"이 런지였으나 게임 안에 안내가 없어
--      사실상 아무도 못 쓰는 기능이었다. 다른 무기 4종(Katana/HammerLow/
--      HammerHigh/Gauntlet)과 동일하게 F키 스킬 버튼으로 통일한다.
--   배치·스케일 규약은 CounterClient 와 동일하게 맞춘다(무기는 하나만 들므로 충돌 없음).
-- ════════════════════════════════════════════════════════════
Tool.Activated:Connect(function()
	FXRemote:FireServer("attack")
end)

local _UIS = game:GetService("UserInputService")
-- ⚠️ 모듈명은 ResponsiveScaler 다(MetaUIResponsiveScaler 는 StarterGui 의 LocalScript).
--    CounterClient:68 과 동일한 경로를 쓴다.
local _Scaler = require(game:GetService("ReplicatedStorage"):WaitForChild("ResponsiveScaler"))

local skillGui = Instance.new("ScreenGui")
skillGui.Name = "ClassicLungeGui"
-- ⚠️ 다른 무기(CounterClient 등)와 동일하게 true. false 로 두면 리스폰 때 살아남아
--    라운드마다 새 검이 지급될 때 GUI 가 계속 쌓인다.
skillGui.ResetOnSpawn = true
skillGui.IgnoreGuiInset = true
skillGui.Enabled = false           -- 장착 중에만 표시
skillGui.Parent = PlayerGui

_Scaler.applyEdge(skillGui, nil, {
	baseW = 1280, baseH = 720,
	Mobile = { minScale = 0.55 },
	PC     = { minScale = 0.55 },
})

local SKILLBTN_POS  = {
	Mobile = UDim2.new(1, -187, 1, -128),
	PC     = UDim2.new(1, -365, 1, -170),  -- -20 → -100 (2026-08-21): 하단에 너무 붙어 있어 올림
}
local SKILLBTN_SIZE = { Mobile = 120, PC = 150 }

local btn = Instance.new("TextButton")
btn.Name = "LungeButton"
btn.AnchorPoint = Vector2.new(1, 1)
btn.BackgroundTransparency = 1
btn.TextTransparency = 1
btn.AutoButtonColor = false
btn.Parent = skillGui

local function syncSkillBtnPos()
	local dev = _Scaler.device()
	btn.Size = UDim2.fromOffset(SKILLBTN_SIZE[dev] or SKILLBTN_SIZE.PC,
	                            SKILLBTN_SIZE[dev] or SKILLBTN_SIZE.PC)
	btn.Position = SKILLBTN_POS[dev] or SKILLBTN_POS.PC
end
syncSkillBtnPos()
_UIS:GetPropertyChangedSignal("KeyboardEnabled"):Connect(syncSkillBtnPos)
_UIS:GetPropertyChangedSignal("TouchEnabled"):Connect(syncSkillBtnPos)

local icon = Instance.new("ImageLabel")
icon.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
icon.BackgroundTransparency = 0.15
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.fromScale(1, 1)
-- ⚠️ 업로드로 받은 ID(109500808042809)는 Decal 이라 ImageLabel 에 넣으면 안 그려진다.
--    아래는 그 안의 실제 Image ID. 이미지가 안 보이면 AssetTypeId 부터 확인할 것(13=Decal, 1=Image).
icon.Image = "rbxassetid://138582652101220"
icon.Parent = btn
local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(0.2, 0); ic.Parent = icon
local st = Instance.new("UIStroke")
st.Thickness = 2; st.Color = Color3.fromRGB(255, 215, 120); st.Parent = icon

-- 키 힌트 (PC 에서만)
local hint = Instance.new("TextLabel")
hint.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
hint.BackgroundTransparency = 0.35
hint.AnchorPoint = Vector2.new(1, 0)
hint.Position = UDim2.new(0.96, 0, 0.04, 0)
hint.Size = UDim2.new(0.32, 0, 0.32, 0)
hint.Font = Enum.Font.GothamBold
hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(255, 190, 60)
hint.Text = "F"
hint.ZIndex = 4
hint.Parent = btn
local hc = Instance.new("UICorner"); hc.CornerRadius = UDim.new(0.3, 0); hc.Parent = hint
local function updateHint()
	-- 터치 전용 기기에서는 키 힌트를 숨긴다
	hint.Visible = not (_UIS.TouchEnabled and not _UIS.KeyboardEnabled)
end
updateHint()
_UIS:GetPropertyChangedSignal("TouchEnabled"):Connect(updateHint)
_UIS:GetPropertyChangedSignal("KeyboardEnabled"):Connect(updateHint)

-- 쿨다운 표시
local cdLabel = Instance.new("TextLabel")
cdLabel.Name = "CooldownLabel"
cdLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
cdLabel.BackgroundTransparency = 0.5
cdLabel.Size = UDim2.fromScale(1, 1)
cdLabel.Font = Enum.Font.GothamBold
cdLabel.TextScaled = true
cdLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
cdLabel.TextStrokeTransparency = 0.3
cdLabel.ZIndex = 5
cdLabel.Text = ""
cdLabel.Visible = false
cdLabel.Parent = btn
local cc2 = Instance.new("UICorner"); cc2.CornerRadius = UDim.new(0.2, 0); cc2.Parent = cdLabel

-- 🎯 [2026-09-09] 런지 스택 · 사거리 버프 표시
--   [왜] 3회 명중으로 발동하는데 지금 몇 회인지 화면에 없어서, 언제 켜지는지 알 수 없었다.
--   ⚠️ 새 UI 를 만들지 않고 기존 런지 버튼(btn)에 얹는다. 모바일 화면을 더 복잡하게
--     만들지 않으려는 것 — 09-06 문서의 "로비 콘텐츠는 반복 노출" 원칙과 같은 이유다.
--   ⚠️ 스택은 버튼 위, 버프 남은 시간은 버튼 아래에 둔다. 쿨다운 숫자(cdLabel)는
--     버튼 한가운데라 셋이 안 겹친다.
local stackLabel = Instance.new("TextLabel")
stackLabel.Name = "ReachStack"
stackLabel.Size = UDim2.new(1, 0, 0.3, 0)
stackLabel.Position = UDim2.new(0, 0, -0.34, 0)
stackLabel.BackgroundTransparency = 1
stackLabel.Font = Enum.Font.GothamBold
stackLabel.TextScaled = true
stackLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
stackLabel.TextStrokeTransparency = 0.2
stackLabel.ZIndex = 6
stackLabel.Text = ""
stackLabel.Visible = false
stackLabel.Parent = btn

local buffLabel = Instance.new("TextLabel")
buffLabel.Name = "ReachBuff"
buffLabel.Size = UDim2.new(1, 0, 0.3, 0)
buffLabel.Position = UDim2.new(0, 0, 1.04, 0)
buffLabel.BackgroundTransparency = 1
buffLabel.Font = Enum.Font.GothamBold
buffLabel.TextScaled = true
buffLabel.TextColor3 = Color3.fromRGB(255, 240, 140)
buffLabel.TextStrokeTransparency = 0.2
buffLabel.ZIndex = 6
buffLabel.Text = ""
buffLabel.Visible = false
buffLabel.Parent = btn

local reachBuffUntil = 0
task.spawn(function()
	while true do
		task.wait(0.1)
		local remain = reachBuffUntil - os.clock()
		if remain > 0 then
			buffLabel.Visible = true
			buffLabel.Text = string.format("REACH %.1f", remain)
			-- 버프 중엔 스택이 안 쌓이므로 스택 표시는 숨긴다(위 서버 주석 참조).
			stackLabel.Visible = false
		elseif buffLabel.Visible then
			buffLabel.Visible = false
			buffLabel.Text = ""
		end
	end
end)

-- 쿨다운 카운트다운. 서버가 남은 시간을 알려주면 그걸로 동기화한다.
local cdUntil = 0
task.spawn(function()
	while true do
		task.wait(0.1)
		local remain = cdUntil - os.clock()
		if remain > 0 then
			cdLabel.Visible = true
			cdLabel.Text = string.format("%.1f", remain)
		elseif cdLabel.Visible then
			cdLabel.Visible = false
			cdLabel.Text = ""
		end
	end
end)

local function fireLunge()
	if os.clock() < cdUntil then return end   -- 클라 선반영(서버가 최종 판정)
	FXRemote:FireServer("lunge")
end

-- [LUNGE-SKILL] 서버가 알려주는 쿨다운으로 동기화.
--   ⚠️ 94행의 기존 OnClientEvent 에 넣지 않고 여기 따로 두는 이유:
--      cdUntil 이 그보다 아래에 선언돼 있어 거기서 참조하면 nil 이 된다.
FXRemote.OnClientEvent:Connect(function(kind, ...)
	if kind == "lungeCd" then
		local remain = ...
		if type(remain) == "number" then
			cdUntil = os.clock() + remain
		end

	elseif kind == "reachStack" then
		-- 🎯 런지 명중 누적. 서버가 (현재, 목표)를 보낸다.
		local cur, need = ...
		if type(cur) == "number" and type(need) == "number" then
			if cur > 0 and cur < need then
				stackLabel.Visible = true
				stackLabel.Text = string.format("%d/%d", cur, need)
			else
				-- 0(소모) 또는 목표 도달 → 버프 표시로 넘어간다
				stackLabel.Visible = false
			end
		end

	elseif kind == "reachBuff" then
		-- 🎯 사거리 버프 시작(지속초) / 종료(0)
		local dur = ...
		if type(dur) == "number" then
			reachBuffUntil = dur > 0 and (os.clock() + dur) or 0
			if dur <= 0 then
				buffLabel.Visible = false
				buffLabel.Text = ""
			end
		end
	end
end)

btn.Activated:Connect(fireLunge)
_UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F then fireLunge() end
end)

-- 장착 중에만 버튼 표시
Tool.Equipped:Connect(function() skillGui.Enabled = true end)
Tool.Unequipped:Connect(function() skillGui.Enabled = false end)

-- ⚠️ [GUI-CLEANUP] Unequipped 만으로는 부족하다.
--    라운드 종료로 Tool 이 통째로 파괴되면 Unequipped 가 안 뛰는 경우가 있어
--    아이콘이 화면에 남는다. 도구가 사라지면 GUI 도 함께 제거한다.
Tool.Destroying:Connect(function()
	if skillGui then skillGui:Destroy() end
end)
-- 백팩/캐릭터 밖으로 나가는 경우(부모 소실)도 함께 처리
Tool.AncestryChanged:Connect(function(_, parent)
	if not parent then
		if skillGui then skillGui:Destroy() end
	end
end)

if Tool.Parent and Tool.Parent:FindFirstChildOfClass("Humanoid") then
	skillGui.Enabled = true
end
