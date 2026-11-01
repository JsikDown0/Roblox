-- PilotJetpackClient (LocalScript, StarterPlayerScripts) — 10-29 조종사 제트팩 Shift 부스트
-- 걸어 다니는 내 캐릭터(메카 아님)가 제트팩을 메고 있을 때: Shift 를 누른 채 움직이면 게이지를 쓰며 이속 CFG.Jetpack.BoostSpeed.
-- 게이지 = 이 화면이 셈(시험장 이동용). 불꽃·소리는 서버에 켬/끔만 알려 서버가 켬(모두에게 보임) — PilotJetpackServer
-- ■ 메카 탑승 중엔 아무것도 안 함: Shift 는 메카 부스트(MechClient)가 씀. 이속도 사람 몸 Humanoid 에만 쓴다(메카 Humanoid 는 절대 안 건드림)
-- ■ 이속은 상태가 바뀔 때만 쓴다(매 프레임 덮어쓰지 않음)
-- ■ 다 쓰면(0) 잠금: Shift 를 떼고 MinRestart 만큼 찰 때까지 못 씀 — 누른 채로 0 근처에서 켜졌다 꺼졌다 깜빡이지 않게
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Proto = RS:WaitForChild("MechProto")
local CFG = require(Proto:WaitForChild("MechConfig"))
local J = CFG.Jetpack
local Remote = Proto:WaitForChild("Remotes"):WaitForChild("PilotJet")
local BASE = game:GetService("StarterPlayer").CharacterWalkSpeed

local gauge = J.Max
local boosting, lockout = false, false
local lastUse = -99
local speedHum, speedState = nil, nil   -- 마지막으로 이속을 쓴 Humanoid · 그때 상태

local function jetOf(char)
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("PilotJetpack") then return c end
	end
	return nil
end

-- ---------- 게이지 HUD: 메카 HUD BOOST 막대와 같은 결(블록 10칸 · 청록 · 꺼진 칸 짙게) ----------
local W, CYAN, DIM = Color3.new(1, 1, 1), Color3.fromRGB(90, 230, 255), Color3.fromRGB(25, 27, 32)
local NB = 10
local gui = Instance.new("ScreenGui")
gui.Name = "PilotJetHUD"; gui.ResetOnSpawn = false; gui.Enabled = false
local holder = Instance.new("Frame")
holder.BackgroundTransparency = 1; holder.AnchorPoint = Vector2.new(0.5, 1)
holder.Position = UDim2.new(0.5, 0, 1, -70); holder.Size = UDim2.fromOffset(330, 22)
holder.Parent = gui
local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1; label.Font = Enum.Font.GothamBold; label.TextSize = 13; label.TextColor3 = W
label.TextStrokeTransparency = 0.6; label.TextXAlignment = Enum.TextXAlignment.Right
label.Size = UDim2.fromOffset(92, 22); label.Position = UDim2.fromOffset(0, 0); label.Text = "JET [Shift]"
label.Parent = holder
local blocks = {}
for i = 1, NB do
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0; f.BackgroundColor3 = DIM; f.BackgroundTransparency = 0.45
	f.Size = UDim2.fromOffset(20, 8); f.Position = UDim2.fromOffset(100 + (i - 1) * 23, 7)
	f.Parent = holder
	blocks[i] = f
end
gui.Parent = player:WaitForChild("PlayerGui")
local shown, shownLock = -1, nil
local function paint()
	local n = math.clamp(math.ceil(gauge / J.Max * NB - 1e-6), 0, NB)
	if n == shown and lockout == shownLock then return end
	shown, shownLock = n, lockout
	for i, f in ipairs(blocks) do
		f.BackgroundColor3 = (i <= n) and CYAN or DIM
		f.BackgroundTransparency = (i <= n) and (lockout and 0.6 or 0.05) or 0.45   -- 잠금 중엔 찬 칸도 흐리게(아직 못 씀)
	end
	label.Text = lockout and "JET EMPTY" or "JET [Shift]"
end

RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local onFoot = hum ~= nil and hum.Health > 0 and not char:GetAttribute("IsMech") and jetOf(char) ~= nil
	local held = UIS:IsKeyDown(Enum.KeyCode.LeftShift) and UIS:GetFocusedTextBox() == nil
	if lockout and not held and gauge >= J.MinRestart then lockout = false end
	local on = onFoot and held and not lockout and gauge > 0 and hum.MoveDirection.Magnitude > 0.1
	if on then
		gauge = math.max(0, gauge - J.Drain * dt)
		lastUse = t
		if gauge <= 0 then lockout = true; on = false end
	elseif t - lastUse >= J.RegenDelay then
		gauge = math.min(J.Max, gauge + J.Regen * dt)
	end
	if on ~= boosting then
		boosting = on
		Remote:FireServer(on)
	end
	if onFoot and (hum ~= speedHum or boosting ~= speedState) then
		hum.WalkSpeed = boosting and J.BoostSpeed or BASE
		speedHum, speedState = hum, boosting
	end
	if gui.Enabled ~= onFoot then gui.Enabled = onFoot end
	if onFoot then paint() end
end)
