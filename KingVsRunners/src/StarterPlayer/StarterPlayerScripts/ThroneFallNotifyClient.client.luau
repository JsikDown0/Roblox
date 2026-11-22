-- ThroneFallNotifyClient
-- Two jobs, both about the same problem: after the throne falls, the KING has no
-- idea what happened to him. The throne is behind him, the chains sit at his feet
-- where he cannot see them, and the exhaustion that follows just feels like the
-- controls breaking.
--   1) one-shot banner  - "what happened"
--   2) persistent HUD   - "what my state is" + "when the next one lands"
-- [why both] The banner alone is forgotten three seconds later. The HUD alone
--   never explains itself. Neither works on its own.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local fellEvent    = ReplicatedStorage:WaitForChild("ThroneFellEvent")
local exhaustEvent = ReplicatedStorage:WaitForChild("ThroneExhaustEvent")

local GOLD  = Color3.fromRGB(230, 190, 90)
local DARK  = Color3.fromRGB(24, 22, 30)
local WHITE = Color3.fromRGB(255, 255, 255)

-- ── 1) banner ────────────────────────────────────────────
local function showBanner(isKing)
	local pgui = localPlayer:WaitForChild("PlayerGui")
	local existing = pgui:FindFirstChild("ThroneFellGui")
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ThroneFellGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 9
	gui.Parent = pgui

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.32, 0)
	frame.Size = UDim2.new(0, 520, 0, 92)
	frame.BackgroundColor3 = DARK
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14); corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD; stroke.Thickness = 3; stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 10)
	title.Size = UDim2.new(1, -20, 0, 38)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = GOLD
	title.Text = "THRONE FALLEN"
	title.Parent = frame

	local sub = Instance.new("TextLabel")
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.new(0.5, 0, 0, 50)
	sub.Size = UDim2.new(1, -30, 0, 32)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = WHITE
	-- [warn] Different text per side, and both name the EFFECT, not the imagery.
	--   "the chains drag you down" was the first draft - it read as flavour and
	--   left the king still wondering why his controls stopped working. State the
	--   mechanic: slower, and periodically unable to act.
	sub.Text = isKing and "CURSED — Slowed, and you will collapse periodically"
	                  or "The King is cursed — slowed and collapsing"
	sub.Parent = frame

	frame.Size = UDim2.new(0, 0, 0, 92)
	TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Back,
		Enum.EasingDirection.Out), { Size = UDim2.new(0, 520, 0, 92) }):Play()

	task.delay(3.2, function()
		if not frame.Parent then return end
		local t = TweenService:Create(frame, TweenInfo.new(0.4),
			{ BackgroundTransparency = 1 })
		TweenService:Create(title, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(sub,   TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke,TweenInfo.new(0.4), { Transparency = 1 }):Play()
		t:Play()
		t.Completed:Wait()
		gui:Destroy()
	end)
end

fellEvent.OnClientEvent:Connect(function(kingName)
	showBanner(localPlayer.Name == kingName)
end)

-- ── 2) king-only HUD: chain badge + countdown to the next exhaustion ──
--   [why a countdown] Without it the burst is random punishment. With it the king
--     can choose to back off before it lands - the debuff becomes something he
--     plays around instead of something that happens to him.
local hud, bar, label, badge
local nextAt, armed = 0, false
local barTotal = 1            -- filled from the server's "ready" payload

local function buildHud()
	local pgui = localPlayer:WaitForChild("PlayerGui")
	local old = pgui:FindFirstChild("ThroneChainHud")
	if old then old:Destroy() end

	hud = Instance.new("ScreenGui")
	hud.Name = "ThroneChainHud"
	hud.ResetOnSpawn = false
	hud.IgnoreGuiInset = true
	hud.DisplayOrder = 8
	hud.Parent = pgui

	local root = Instance.new("Frame")
	-- [warn] This was at the bottom centre (1, -120) and overlapped the tagger item
	--   cooldown bar, which sits at scale-Y 0.73 (~788px on 1080p) - the HUD spanned
	--   906~960 and the two collided on shorter screens.
	--   Top centre is free: the Round timer is above it, and both are countdowns,
	--   so they read as one column of "time left" information.
	--   ⚠️ Occupied elsewhere: emote bar (top-left), REVIVE (mid-left), Settings+HP
	--     (top-right), weapon slot (bottom-centre), F/Q skills (bottom-right).
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 74)
	root.Size = UDim2.new(0, 240, 0, 54)
	root.BackgroundColor3 = DARK
	root.BackgroundTransparency = 0.25
	root.BorderSizePixel = 0
	root.Parent = hud
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = root
	local st = Instance.new("UIStroke"); st.Color = GOLD; st.Thickness = 2; st.Parent = root

	badge = Instance.new("TextLabel")
	badge.Position = UDim2.new(0, 10, 0, 6)
	badge.Size = UDim2.new(0, 34, 0, 42)
	badge.BackgroundTransparency = 1
	badge.Font = Enum.Font.GothamBlack
	badge.TextScaled = true
	badge.TextColor3 = GOLD
	badge.Text = "⛓"
	badge.Parent = root

	label = Instance.new("TextLabel")
	label.Position = UDim2.new(0, 48, 0, 4)
	label.Size = UDim2.new(1, -58, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = WHITE
	label.Text = "COLLAPSE IN --"
	label.Parent = root

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 48, 0, 30)
	track.Size = UDim2.new(1, -60, 0, 12)
	track.BackgroundColor3 = Color3.fromRGB(60, 55, 70)
	track.BorderSizePixel = 0
	track.Parent = root
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0, 6); tc.Parent = track

	bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.BackgroundColor3 = GOLD
	bar.BorderSizePixel = 0
	bar.Parent = track
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = bar
end

local function clearHud()
	armed = false
	if hud then hud:Destroy(); hud = nil end
end

exhaustEvent.OnClientEvent:Connect(function(phase, seconds)
	if phase == "off" then clearHud(); return end
	if not hud then buildHud() end

	if phase == "start" then
		-- the burst itself: bar full red, no countdown to show
		armed = false
		bar.Size = UDim2.new(1, 0, 1, 0)
		bar.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
		label.Text = "COLLAPSED!"
	elseif phase == "ready" then
		armed = true
		barTotal = math.max(seconds or 1, 0.001)   -- avoid divide-by-zero
		nextAt = os.clock() + barTotal
		bar.BackgroundColor3 = GOLD
	end
end)

-- [warn] Count down on the client. Firing an event every second just to update a
--   number would put 8 remote calls per cycle on the wire for one label.
RunService.RenderStepped:Connect(function()
	if not (armed and hud and bar) then return end
	local left = nextAt - os.clock()
	if left < 0 then left = 0 end
	-- [warn] This used to hardcode "8.0 - 1.5" to mirror the server. That broke the
	--   moment the server changed what CYCLE means. Take the length from the event
	--   itself instead - the server already sends it, so there is nothing to keep
	--   in sync.
	local total = barTotal
	bar.Size = UDim2.new(math.clamp(left / total, 0, 1), 0, 1, 0)
	label.Text = string.format("COLLAPSE IN %.1fs", left)
end)

-- round boundary: the HUD must not survive into the next round
localPlayer.CharacterAdded:Connect(clearHud)
