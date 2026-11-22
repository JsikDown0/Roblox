-- DamagePopupClient — 무기 공용 데미지 숫자
--
-- [왜 공용인가] ClassicSword / DiamondBladeSword / DragonFireSword 가 각자
--   같은 기능을 따로 구현해 두었다(FXRemote+FXClient / Remote+SwordClient).
--   나머지 5종(Katana, Sakura, HammerLow, HammerHigh, Gauntlet)에는 아예 없어
--   "어떤 무기는 숫자가 뜨고 어떤 무기는 안 뜨는" 상태였다.
--   여기에 5개를 더 복사하면 같은 규칙이 여덟 곳이 된다 — 하나만 고쳐지는 그 패턴이다.
-- [범위] 기존 3종은 건드리지 않는다. 콤보 카운터·LUNGE 라벨 같은 무기 전용 연출이
--   얽혀 있어 옮기다 깨뜨릴 위험이 이득보다 크다. 새로 붙이는 쪽만 이 경로를 쓴다.
-- ⚠️ 모양은 ClassicSword.FXClient 의 popDamage 를 그대로 맞췄다 — 무기마다 숫자가
--   달라 보이면 통일한 의미가 없다.

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ev = ReplicatedStorage:WaitForChild("DamagePopupEvent")

-- crit: 강타·스킬 등 '큰 한 방'이면 true → 금색 + 크게 (LUNGE 표기와 같은 규약)
local function popDamage(dmg, worldPos, crit)
	if not worldPos then return end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	-- 같은 자리에 여러 번 뜨면 겹쳐 읽히므로 살짝 흩는다(원본과 동일).
	anchor.Position = worldPos + Vector3.new(math.random(-15,15)/10, 2, math.random(-15,15)/10)
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = crit and UDim2.new(0, 270, 0, 135) or UDim2.new(0, 200, 0, 100)
	bb.AlwaysOnTop = true
	bb.Parent = anchor

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.LuckiestGuy
	lbl.TextScaled = true
	-- ⚠️ 표시에서만 반올림한다. CC 중이면 서버가 _G.DisplayDamage 로 환산한 값을
	--   보내므로 소수가 길게 나올 수 있다. 판정값은 서버가 원본으로 처리한다.
	lbl.Text = tostring(math.floor((dmg or 0) + 0.5))
	lbl.TextStrokeTransparency = 0
	if crit then
		lbl.TextColor3 = Color3.fromRGB(255, 215, 60)
		lbl.TextStrokeColor3 = Color3.fromRGB(120, 60, 0)
	else
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.TextStrokeColor3 = Color3.fromRGB(40, 40, 40)
	end
	lbl.Parent = bb

	TweenService:Create(anchor, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = anchor.Position + Vector3.new(0, 4.5, 0) }):Play()
	local fade = TweenService:Create(lbl, TweenInfo.new(0.9),
		{ TextTransparency = 1, TextStrokeTransparency = 1 })
	fade:Play()
	fade.Completed:Connect(function() anchor:Destroy() end)
	Debris:AddItem(anchor, 1.2)
end

ev.OnClientEvent:Connect(function(dmg, worldPos, crit)
	popDamage(dmg, worldPos, crit)
end)
