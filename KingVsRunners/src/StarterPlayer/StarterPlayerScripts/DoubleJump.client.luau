-- DoubleJump (burst) — 클라이언트 더블 점프 + 추진력 발판 이펙트
-- 공중에서 점프 키를 한 번 더 누르면: 점프 동작 재생 + 더 높은 점프, 방향키 입력 시 그 방향으로 강하게 추진.
-- 이펙트는 서버 브로드캐스트로 다른 플레이어에게도 보임. 점프 움직임은 캐릭터 복제로 자동 공유됨.

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Debris           = game:GetService("Debris")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("DoubleJumpFX")

-- ── 설정 ────────────────────────────────────────
local JUMP_MULTIPLIER  = 1.4    -- 두 번째 점프 수직 힘 배율 (더 높이)
local HORIZONTAL_BURST = 55     -- 방향키 입력 시 수평 추진 속도 (멀리 날아감)
local BURST_TIME       = 0.22   -- 수평 추진 지속 시간(초)
local MIN_AIR_TIME     = 0.12   -- 첫 점프 후 이 시간 뒤부터 더블점프 허용 (오발 방지)
-- 러너 아이템 게이트: true면 player의 "DoubleJumpEnabled" 속성이 켜져 있을 때만 작동
local USE_ATTRIBUTE_GATE = true
-- 2단 점프 사운드 (발판 위치에서 3D로 재생 → 주변 플레이어 모두 들림)
local JUMP_SOUND_ID    = "rbxassetid://132022536837243"
local JUMP_SOUND_SPEED = 1.3   -- 재생 배속
local JUMP_SOUND_VOL   = 1

local character, humanoid
local canDoubleJump, hasDoubleJumped = false, false
local jumpedAt = 0

-- UseJumpPower 여부에 따라 점프 상승 속도 계산
local function getJumpVelocity(hum)
	if hum.UseJumpPower then
		return hum.JumpPower
	else
		return math.sqrt(2 * workspace.Gravity * hum.JumpHeight)
	end
end

-- ── 추진력 발판 버스트 이펙트 ───────────────────
local FX_COLOR  = Color3.fromRGB(255, 255, 255)
local FX_SPIKES = 9      -- 사방으로 뻗는 샤드 개수
local FX_RING_R = 7      -- 충격파 링 최대 반경
local FX_LIFE   = 0.35   -- 이펙트 지속 시간(초)

local function spawnJumpFX(footPos)
	-- 0) 사운드 (발판 위치에서 3D 재생 → 주변 모두 들림)
	local sndPart = Instance.new("Part")
	sndPart.Name = "DoubleJumpSound"
	sndPart.Anchored = true
	sndPart.CanCollide = false
	sndPart.CanQuery = false
	sndPart.CanTouch = false
	sndPart.Transparency = 1
	sndPart.Size = Vector3.new(1, 1, 1)
	sndPart.CFrame = CFrame.new(footPos)
	sndPart.Parent = workspace
	local snd = Instance.new("Sound")
	snd.SoundId = JUMP_SOUND_ID
	snd.PlaybackSpeed = JUMP_SOUND_SPEED
	snd.Volume = JUMP_SOUND_VOL
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.RollOffMaxDistance = 120
	snd.Parent = sndPart
	snd:Play()
	Debris:AddItem(sndPart, 6)

	-- 1) 바닥 충격파 링 (납작한 네온 원반이 퍼지며 사라짐)
	local ring = Instance.new("Part")
	ring.Name = "DoubleJumpRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 2, 2)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Massless = true
	ring.Material = Enum.Material.Neon
	ring.Color = FX_COLOR
	ring.Transparency = 0.1
	ring.CFrame = CFrame.new(footPos) * CFrame.Angles(0, 0, math.rad(90))  -- 원반축 수직 → 바닥에 눕힘
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(FX_LIFE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, FX_RING_R * 2, FX_RING_R * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, FX_LIFE + 0.15)

	-- 2) 중앙 플래시 (밝은 코어가 잠깐 부풀며 사라짐)
	local flash = Instance.new("Part")
	flash.Name = "DoubleJumpFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(1.6, 1.6, 1.6)
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Massless = true
	flash.Material = Enum.Material.Neon
	flash.Color = FX_COLOR
	flash.Transparency = 0.15
	flash.CFrame = CFrame.new(footPos + Vector3.new(0, 0.6, 0))
	flash.Parent = workspace
	TweenService:Create(flash, TweenInfo.new(FX_LIFE * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(4, 4, 4),
		Transparency = 1,
	}):Play()
	Debris:AddItem(flash, FX_LIFE)

	-- 3) 사방으로 뻗는 샤드 (바깥+위로 솟구치며 가늘어지고 사라짐)
	for i = 1, FX_SPIKES do
		local ang = (i - 1) / FX_SPIKES * math.pi * 2
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local spike = Instance.new("Part")
		spike.Name = "DoubleJumpShard"
		spike.Size = Vector3.new(0.25, 0.25, 1.8)
		spike.Anchored = true
		spike.CanCollide = false
		spike.CanQuery = false
		spike.CanTouch = false
		spike.Massless = true
		spike.Material = Enum.Material.Neon
		spike.Color = FX_COLOR
		spike.Transparency = 0.05
		local startPos = footPos + dir * 1.2 + Vector3.new(0, 0.3, 0)
		spike.CFrame = CFrame.lookAt(startPos, startPos + dir + Vector3.new(0, 0.25, 0))
		spike.Parent = workspace
		local endPos = footPos + dir * FX_RING_R + Vector3.new(0, 1.7, 0)
		TweenService:Create(spike, TweenInfo.new(FX_LIFE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(endPos, endPos + dir + Vector3.new(0, 0.25, 0)),
			Size = Vector3.new(0.05, 0.05, 2.8),
			Transparency = 1,
		}):Play()
		Debris:AddItem(spike, FX_LIFE + 0.1)
	end
end

-- ── 등 뒤 바람 트레일 ───────────────────────────
local WIND_TIME   = 0.5    -- 트레일 방출 시간(초)
local WIND_COLOR  = Color3.fromRGB(255, 255, 255)
local WIND_LIFE   = 0.4    -- 각 streak가 남아있는 시간
-- 등(뒤)쪽 좌/중/우 + 위/아래 어태치먼트로 리본 폭을 만들고, 캐릭터가 움직이며 streak가 생김
local WIND_X_OFFSETS = { -0.8, 0, 0.8 }

local function spawnWindTrail(char)
	if not char then return end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if not torso then return end

	for _, xo in ipairs(WIND_X_OFFSETS) do
		-- 등쪽(+Z 뒤) 위/아래 두 어태치먼트 → 트레일 리본의 폭
		local a0 = Instance.new("Attachment")
		a0.Name = "WindTrailTop"
		a0.Position = Vector3.new(xo, 0.9, 0.6)
		a0.Parent = torso
		local a1 = Instance.new("Attachment")
		a1.Name = "WindTrailBottom"
		a1.Position = Vector3.new(xo, -0.9, 0.6)
		a1.Parent = torso

		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = WIND_LIFE
		trail.Color = ColorSequence.new(WIND_COLOR)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		})
		trail.LightEmission = 0.7
		trail.LightInfluence = 0
		trail.FaceCamera = true
		trail.Parent = torso

		-- 버스트 순간만 방출하고 끄기 (남은 streak는 Lifetime 동안 자연스럽게 사라짐)
		task.delay(WIND_TIME, function()
			if trail and trail.Parent then trail.Enabled = false end
		end)
		Debris:AddItem(a0, WIND_TIME + WIND_LIFE + 0.2)
		Debris:AddItem(a1, WIND_TIME + WIND_LIFE + 0.2)
		Debris:AddItem(trail, WIND_TIME + WIND_LIFE + 0.2)
	end
end

-- 다른 플레이어의 더블점프 이펙트 수신 (서버 브로드캐스트)
remote.OnClientEvent:Connect(function(footPos, jumper)
	if typeof(footPos) == "Vector3" then
		spawnJumpFX(footPos)
	end
	-- 점프한 플레이어의 캐릭터 등 뒤에 바람 트레일
	if jumper and jumper.Character then
		spawnWindTrail(jumper.Character)
	end
end)

-- ── 공중제비(플립) — 두 번째 점프 때 한 바퀴 회전 ──
local FLIP_TIME = 0.45   -- 한 바퀴 도는 데 걸리는 시간(초). 짧을수록 빠른 회전
local flipping = false
local flipConn = nil

local function stopFlip()
	if flipConn then flipConn:Disconnect() flipConn = nil end
	if not flipping then return end
	flipping = false
	if humanoid and humanoid.Parent then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
	end
	-- 업라이트로 정리 (수평 방향 유지)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	end
end

local function startFlip(root)
	if flipping then return end
	flipping = true
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true   -- 물리 제어로 두고 자유 회전 (속도/중력은 그대로 유지됨)

	-- 시작 시점의 수평 바라보는 방향(yaw) 고정
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	flat = flat.Unit

	local t0 = tick()
	flipConn = RunService.RenderStepped:Connect(function()
		if not (character and root and root.Parent and humanoid and humanoid.Parent)
			or humanoid:GetState() == Enum.HumanoidStateType.Dead then
			stopFlip()
			return
		end
		local a = (tick() - t0) / FLIP_TIME
		if a >= 1 then
			stopFlip()
			return
		end
		-- 현재 위치(물리가 옮긴 위치)는 유지하고, 우측 축 기준 피치 회전만 적용 → 앞구르기 한 바퀴
		local angle = a * math.pi * 2
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat) * CFrame.Angles(-angle, 0, 0)
	end)
end

-- ── 더블 점프 실행 ──────────────────────────────
local function doDoubleJump()
	if not (character and humanoid) then return end
	if humanoid:GetState() == Enum.HumanoidStateType.Dead then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- 1) 한 바퀴 공중제비 (물리 회전)
	startFlip(root)

	-- 2) 수직: 더 높게
	local vUp = getJumpVelocity(humanoid) * JUMP_MULTIPLIER
	local vel = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(vel.X, vUp, vel.Z)

	-- 3) 수평: 방향키 입력이 있으면 그 방향으로 강하게 추진 (짧은 시간 LinearVelocity로 밀어줌)
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude > 0.1 then
		local dir = moveDir.Unit
		local att = Instance.new("Attachment")
		att.Name = "DJBurstAtt"
		att.Parent = root
		local lv = Instance.new("LinearVelocity")
		lv.Attachment0 = att
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		lv.MaxAxesForce = Vector3.new(1e5, 0, 1e5)  -- 수평만 구동 (수직은 점프 물리 그대로 → 자연스러운 포물선)
		lv.VectorVelocity = Vector3.new(dir.X * HORIZONTAL_BURST, 0, dir.Z * HORIZONTAL_BURST)
		lv.Parent = root
		Debris:AddItem(lv, BURST_TIME)
		Debris:AddItem(att, BURST_TIME)
	end

	-- 4) 발판 버스트 이펙트 (로컬 즉시 + 서버에 알려 다른 클라에도 표시)
	local footY = root.Position.Y - (root.Size.Y * 0.5) - (humanoid.HipHeight or 0)
	local footPos = Vector3.new(root.Position.X, footY, root.Position.Z)
	spawnJumpFX(footPos)
	-- 5) 등 뒤 바람 트레일 (로컬 즉시 — 다른 클라는 서버 브로드캐스트로 받아 생성)
	spawnWindTrail(character)
	remote:FireServer(footPos)
end

local function onJumpRequest()
	if USE_ATTRIBUTE_GATE and not player:GetAttribute("DoubleJumpEnabled") then return end
	if not (character and humanoid) then return end
	-- 🦘 [2026-08-31] 배럴 웅덩이 안에서는 더블점프도 봉인.
	--   기본 점프는 BarrelSlipClient 가 Jumping 상태를 꺼서 막는데, 더블점프는
	--   JumpRequest 에 직결돼 그 상태를 타지 않는다. 여기서 따로 막지 않으면
	--   웅덩이 안에서 공중으로 한 번 더 떠서 그대로 빠져나간다.
	--   ⚠️ RunnerDive.tryDash 와 같은 속성·같은 판정(발동 시점만)이다.
	if character:GetAttribute("InBarrelSpill") then return end
	if not canDoubleJump or hasDoubleJumped then return end
	if tick() - jumpedAt < MIN_AIR_TIME then return end
	hasDoubleJumped = true
	canDoubleJump = false
	doDoubleJump()
end

local function onCharacterAdded(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")
	canDoubleJump, hasDoubleJumped = false, false

	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			jumpedAt = tick()
		elseif newState == Enum.HumanoidStateType.Freefall then
			if not hasDoubleJumped then canDoubleJump = true end
		elseif newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.Seated then
			canDoubleJump, hasDoubleJumped = false, false
			stopFlip()  -- 착지하면 회전 중이어도 즉시 정리
		end
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then onCharacterAdded(player.Character) end

UserInputService.JumpRequest:Connect(onJumpRequest)
