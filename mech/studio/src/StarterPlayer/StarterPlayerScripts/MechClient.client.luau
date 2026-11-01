-- MechClient (v3)
-- 1) 내가 탄 메카: 3인칭 어깨 카메라(마우스 고정), 화면 중앙 조준, 사격·조준·부스트·하차 입력, HUD
-- 2) 모든 메카: Motor6D.Transform 으로 자세를 계산(코드 애니메이션)하고 이펙트를 그린다
--    · 이동 방향(앞/옆/뒤)에 맞춘 걷기 · 한 손 사격 자세 · 부스트 때 진행 방향으로 수그린 자세
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local Proto = RS:WaitForChild("MechProto")
local CFG = require(Proto:WaitForChild("MechConfig"))
local Remotes = Proto:WaitForChild("Remotes")
local SM = require(Proto:WaitForChild("SoundManager"))   -- 모든 소리는 SM.play(이름, 위치) 로만. Sound 를 직접 만들지 않는다
local MP = require(Proto:WaitForChild("MechPhysics"))    -- 기체끼리 밀기·솟구침 안전장치(10-25 13:26). 카메라 단계가 매 프레임 부른다

local mech = nil
local yaw, pitch = 0, 0
local firing, aimHeld = false, false
-- 사격 예약(10-25 저격총, 유저 "손을 들었는데도 총이 안 감"): 클릭 = 한 발 약속. 팔을 다 든 뒤(SHOT_RAISED)에 쏘고,
-- 연사 간격이 SHOT_BUFFER 안으로 남았을 때 누른 것도 기다렸다 쏜다. 그보다 이르면 무시(그때 팔은 앞 발 반동에서 돌아오는 중)
-- 예약은 SHOT_QUEUE_LIFE 뒤 사라진다(몸이 조준 방향으로 도는 시간 포함)
local shotQueuedAt = nil
local SHOT_BUFFER, SHOT_QUEUE_LIFE, SHOT_RAISED = 0.3, 0.6, 0.85
-- 캐터펄트 사출(10-25): 내 기체가 사출되는 동안(탄 뒤 ~ 출구 밖 컷 끝) 연출이 입력·카메라를 쥔다.
-- 아래 함수들(launchBegin·launchDrive·launchCamera…)이 값을 바꾸므로 여기서 먼저 선언(아래에서 local 을 다시 붙이지 말 것)
local launchLock, launchRel, launchPanel, launchStartPos = false, false, nil, nil
local climbLocal = setmetatable({}, { __mode = "k" })   -- 18:24 상승(공중 프로토): 기체 → 상승 표시 끝 시각(os.clock). 애니(엔진 수직·불꽃)용
local climbLocked, climbSent = false, false             -- 게이지가 바닥나면 점프 키를 뗄 때까지 상승 잠금 / 서버에 보낸 상승 상태
local launchGlideUntil, launchGlideG = 0, 30   -- 17:39 공중 캐터펄트 활공: 끝 시각(os.clock)·그동안의 중력. 그때까지 공중 관성도 안 줄어듦
local launchCamLast, launchFovLast, launchBlendT0 = nil, nil, nil
-- 줌(2026-10-25): zoomOn = 지금 줌 조건(오른쪽 클릭 + 라이플 손에 듦 + 근접·장전 아님), zoomCam = 카메라 쪽 0~1
-- 시야각(FieldOfView)은 카메라 단계 한 곳에서만 쓴다: 기본 × 줌 배율 + 부스트 킥(fovKickAt). 예전 부스트 트윈은 줌과 주인이 둘이 되어 없앰
local zoomOn, zoomCam, fovKickAt, lastZoomSent = false, 0, -99, false
local bloom = 0   -- 연사로 쌓인 탄 퍼짐(도). 쏘면 SpreadPerShot 씩, 멈추면 SpreadRecover 로 줄어듦
local lastShot, lastBoost = 0, 0
local lastAimSent, lastAimTime = 1e9, 0
local hud, diedConn, faceAlign = nil, nil, nil
local shake, moveVec = 0, Vector3.zero
local aimYawOff = 0     -- 카메라 조준 방향 - 기체 정면 (도, + = 왼쪽)
local lastYawSent = 0
local controls = nil
task.spawn(function()
	-- 기본 조작 모듈이 있으면 그 입력(키보드·패드·모바일)을 쓰고, 없으면 아래 rawMove 의 키보드 입력으로 대신한다
	local pmod = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 15)
	if pmod then
		local ok, pm = pcall(require, pmod)
		if ok and pm and pm.GetControls then controls = pm:GetControls() end
	end
end)
local function rawMove()
	if launchLock then return Vector3.zero end   -- 캐터펄트 사출 중엔 이동 입력 없음
	if controls then return controls:GetMoveVector() end
	if UIS:GetFocusedTextBox() then return Vector3.zero end
	local x, z = 0, 0
	if UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.Up) then z -= 1 end
	if UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.Down) then z += 1 end
	if UIS:IsKeyDown(Enum.KeyCode.A) or UIS:IsKeyDown(Enum.KeyCode.Left) then x -= 1 end
	if UIS:IsKeyDown(Enum.KeyCode.D) or UIS:IsKeyDown(Enum.KeyCode.Right) then x += 1 end
	local v = Vector3.new(x, 0, z)
	return v.Magnitude > 0 and v.Unit or v
end
local baseFov = nil
local recoil = setmetatable({}, { __mode = "k" })
local boostLocal = setmetatable({}, { __mode = "k" })
local lastFireAt = setmetatable({}, { __mode = "k" })
local animState = setmetatable({}, { __mode = "k" })
local meleeLocal = setmetatable({}, { __mode = "k" })   -- 내가 누른 근접: { kind, t0, yaw }
local flinch = setmetatable({}, { __mode = "k" })       -- 맞은 기체 움찔: { t0, dir }
local lastMelee, lastMeleeKind = 0, nil
local weapon, weaponAt = "rifle", -99   -- 내 기체 무장(1 라이플 / 2 빔사벨)과 바꾼 시각(os.clock)
-- 장탄: 서버 속성 Ammo / ReloadUntil 이 기준. 내 기체는 쏠 때마다 바로 줄여 보여 주고(예측), 쉬면 서버 값으로 맞춘다
local ammoLocal, reloadLocalUntil = CFG.MagSize, 0
-- 주무기(10-25 저격총): 수치는 CFG.gun(기체) — 기체 속성 Gun("rifle"|"sniper"). gunSeen = 내 기체에서 마지막으로 본 Gun(바뀌면 탄창·장전 예측을 다시 맞춤)
local gunSeen = nil
-- 점프(내 기체): 웅크림이 끝나 뜰 시각 / 마지막으로 뜬 시각 / 마지막 착지 시각 / 지난 프레임 공중이었나
-- 점프(내 기체): 기본 점프 그대로 두고, 착지 뒤 JumpCooldown 동안만 점프 상태를 꺼 둔다(2026-10-25 유저 결정)
local lastLandAt, airSince, wasAirMine = -99, -99, false
local lastJumpAt, lastHumState = -99, nil   -- 마지막으로 뛰기 시작한 시각(이중 점프 막기)
-- 오르는 동안 중력 약하게(2026-10-25): 내 기체 몸에 붙인 위쪽 힘. 뛰기 시작 ~ 꼭대기(위 속도 0)까지만 켠다
local jumpAssist, jumpRising = nil, false
-- 도약 웅크림(2026-10-25 2차): 누른 시각(os.clock). 웅크리는 동안만 값이 있고, 뜨거나 취소되면 nil
-- windStartLocal 은 뜬 뒤에도 남겨 애니 루프가 "웅크림 → 박차기"를 이어 그리게 한다(취소 때만 nil)
local jumpWindupAt, windStartLocal = nil, nil
local windDurLocal = CFG.JumpWindup   -- 이번 웅크림 길이(서서 0.4 / 부스트 점프 0.15)
local jumpBoostVel = nil              -- 부스트 점프: 웅크리기 시작할 때의 부스트 수평 속도 → 뜰 때 공중 관성으로 실음
-- 지속 부스트(2026-10-25): 누르고 있으면 대시 뒤 수평 추진(땅·공중), 높이는 중력대로. 카메라 단계의 "지속 부스트" 블록이 매 프레임 관리
local boostHeld = false               -- 부스트 키(Shift/Q)를 누르고 있나
local holdActive, holdAirSent = false, false   -- 지금 지속 추진 중(서버에 알린 상태) / 그때 공중이었나(공중은 1.5배 소모)
local holdLocked = false              -- 게이지를 바닥까지 써서 끊겼으면, 키를 뗐다 다시 눌러야 재개
local airDashUsed = false             -- 이번 체공에 공중 대시(톡)를 썼나. 땅에 닿으면 초기화
local dashUntil, dashVel = 0, nil     -- 진행 중인 대시 끝 시각·수평 속도
local carryVel = nil                  -- 공중 관성: 추진·대시가 끝난 뒤 착지까지 서서히 줄어드는 수평 속도
local ammoConn = nil
local function myReloading(now)
	return now < reloadLocalUntil or (mech ~= nil and mech:GetAttribute("ReloadUntil") ~= nil)
end

local JOINTS = { "Root", "Waist", "Neck", "ShoulderL", "ShoulderR", "ElbowL", "ElbowR",
	"HipL", "HipR", "KneeL", "KneeR", "AnkleL", "AnkleR", "SaberGrip", "Grip",
	-- 10-26 중장갑만 있는 관절: 어깨 장갑(팔을 따라감) · 스커트 4장(허벅지를 따라감). 없는 기체는 nil 이라 그냥 건너뜀
	"PadL", "PadR", "SkirtJointFL", "SkirtJointFR", "SkirtJointSL", "SkirtJointSR",
	-- 10-29 SKADI 머리 조준경(HeadScope): 줌 때 앞으로 펼침(관절 속성 Slide). 없는 기체는 nil
	"ScopeJoint",
	-- 10-30 SKADI 저격총 변형(시안 C): 총(Rifle) 안 날개 2 · 덮개 2 · 총구 1(관절 속성 Deploy / Slide — GR.rifleForm). 없는 기체는 nil
	"RifleWingJointL", "RifleWingJointR", "RifleShroudJointT", "RifleShroudJointB", "RifleMuzzleJoint" }

local function exclude(list)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = list
	return p
end

-- (출격 사출 공용 함수 launcherPath · pathFrame · launchS · launchPhase 는 "출격 사출 — 내 기체 연출" 블록에 있다: 경로 꺾임을 섞는 lsmooth 가 거기 있어서)

-- ================= 이펙트 =================
local function fxPart(color, size, cf, shape)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = Enum.Material.Neon; p.Color = color; p.Size = size; p.CFrame = cf
	if shape then p.Shape = shape end
	p.Parent = workspace.CurrentCamera
	return p
end
local function tracer(a, b, style, glowC, coreC)
	local len = (b - a).Magnitude
	if len < 0.5 then return end
	if style == "sniper" then
		-- 저격총(10-25): 굵고 오래 남는 청백색 탄도선 = 맞는 쪽이 어디서 쐈는지 안다(유저 결정 "탄도선 보임")
		-- 10-30: 색은 총 표가 주면 그 색(궁극기 표 TracerGlow·TracerCore = 분홍 빨강 — MechConfig Modes.Ult)
		local cf = CFrame.lookAt((a + b) / 2, b)
		local glow = fxPart(glowC or Color3.fromRGB(120, 225, 255), Vector3.new(0.7, 0.7, len), cf)
		glow.Transparency = 0.35
		local core = fxPart(coreC or Color3.fromRGB(235, 250, 255), Vector3.new(0.22, 0.22, len), cf)
		TweenService:Create(glow, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(0.15, 0.15, len) }):Play()
		TweenService:Create(core, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		Debris:AddItem(glow, 0.5); Debris:AddItem(core, 0.35)
		return
	end
	local p = fxPart(Color3.fromRGB(255, 205, 110), Vector3.new(0.16, 0.16, len), CFrame.lookAt((a + b) / 2, b))
	TweenService:Create(p, TweenInfo.new(0.09), { Transparency = 1 }):Play()
	Debris:AddItem(p, 0.1)
end
local function muzzleFlash(m, big)
	local rifle = m:FindFirstChild("Rifle")
	local mz = rifle and rifle:FindFirstChild("Muzzle")
	if not mz then return end
	local light = mz:FindFirstChild("FlashLight")
	if light then
		light.Enabled = true
		task.delay(big and 0.09 or 0.05, function() light.Enabled = false end)
	end
	local s0, s1 = (big and 1.8 or 0.9), (big and 4.2 or 1.6)
	local f = fxPart(Color3.fromRGB(255, 190, 80), Vector3.one * s0, mz.WorldCFrame, Enum.PartType.Ball)
	TweenService:Create(f, TweenInfo.new(big and 0.1 or 0.06), { Transparency = 1, Size = Vector3.one * s1 }):Play()
	Debris:AddItem(f, big and 0.12 or 0.08)
end
local function spark(pos, normal)
	for _ = 1, 5 do
		local dir = (normal + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)).Unit
		local sp = fxPart(Color3.fromRGB(255, 220, 140), Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos))
		TweenService:Create(sp, TweenInfo.new(0.15), { CFrame = CFrame.new(pos + dir * 1.6), Transparency = 1 }):Play()
		Debris:AddItem(sp, 0.16)
	end
end

-- 발걸음: 먼지 + 낮게 깐 쿵 소리 (+ 내 기체면 카메라 흔들림)
-- 소리(옛 thud · sfx)는 2026-10-25 SoundManager 로 옮김: Step / Land / BodyHit 은 같은 발에서 Sound 하나를 돌려 쓴다(옛 동작 그대로)
local function isHittable(inst)   -- 탄이 맞은 게 기체·표적(Humanoid 가진 모델)인가. 클래스(Model)로 묻지 않고 위로 올라가며 Humanoid 를 찾는다
	local p = inst
	while p and p ~= workspace do
		if p:FindFirstChildOfClass("Humanoid") then return true end
		p = p.Parent
	end
	return false
end
local function dust(pos, n, size)
	for _ = 1, n do
		local d = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
		d = d.Magnitude > 0 and d.Unit or Vector3.xAxis
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		p.Shape = Enum.PartType.Ball; p.Material = Enum.Material.SmoothPlastic
		p.Color = Color3.fromRGB(150, 150, 155); p.Transparency = 0.45
		p.Size = Vector3.one * size; p.CFrame = CFrame.new(pos + d * size * 0.4)
		p.Parent = workspace.CurrentCamera
		TweenService:Create(p, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(pos + d * size * 1.6 + Vector3.new(0, size * 0.3, 0)), Size = Vector3.one * size * 2.2, Transparency = 1 }):Play()
		Debris:AddItem(p, 0.6)
	end
end
local function footPlant(m, footName, strength)
	local foot = m:FindFirstChild(footName)
	if not foot then return end
	local pos = foot.Position - Vector3.new(0, foot.Size.Y / 2, 0)
	dust(pos, strength > 1 and 6 or 3, strength > 1 and 2.4 or 1.6)
	SM.play(strength > 1 and "Land" or "Step", foot, { vol = math.min(strength, 1.4) })
	if m == mech then shake = math.max(shake, CFG.StepShake * strength) end
end

-- ================= HUD =================
-- 10-30: makeHUD(옛 202~357줄)는 자식 모듈 MechHUD 로 옮김(Script.Source 20만 자 한도 — 아래 '모든 메카 코드 애니메이션' 주석)
local makeHUD = require(script:WaitForChild("MechHUD")).make

-- ================= 탑승/하차 =================
local function leave()
	if not mech then return end
	if faceAlign then faceAlign:Destroy(); faceAlign = nil end
	if jumpAssist then jumpAssist:Destroy(); jumpAssist = nil end
	jumpRising = false
	jumpWindupAt, windStartLocal = nil, nil
	-- 지속 부스트·공중 관성 속도 제약을 내린 기체에 남기지 않는다(남으면 빈 기체가 계속 밀려감)
	local oldRoot = mech:FindFirstChild("HumanoidRootPart")
	if oldRoot then
		for _, n in ipairs({ "BoostHold", "AirCarry", "LaunchLV", "ClimbLV" }) do local c = oldRoot:FindFirstChild(n); if c then c:Destroy() end end
	end
	-- 사출 연출 정리(10-25): 경로를 직접 따라가는 동안 켠 PlatformStand 를 반드시 되돌림(하차·죽음·연결 끊김으로 연출 중간에 나가도)
	do local h0 = mech:FindFirstChildOfClass("Humanoid"); if h0 and h0.PlatformStand then h0.PlatformStand = false end end
	launchLock, launchRel, launchStartPos, launchCamLast, launchBlendT0 = false, false, nil, nil, nil
	launchGlideUntil = 0
	climbLocked, climbSent = false, false
	if launchPanel then launchPanel.gui:Destroy(); launchPanel = nil end
	boostHeld, holdActive, holdAirSent, holdLocked, airDashUsed = false, false, false, false, false
	dashUntil, dashVel, carryVel, jumpBoostVel = 0, nil, nil, nil
	mech = nil
	firing, aimHeld, shotQueuedAt = false, false, nil
	zoomOn, zoomCam, fovKickAt, bloom = false, 0, -99, 0
	moveVec, shake = Vector3.zero, 0
	if baseFov then workspace.CurrentCamera.FieldOfView = baseFov end
	if diedConn then diedConn:Disconnect(); diedConn = nil end
	if ammoConn then ammoConn:Disconnect(); ammoConn = nil end
	if hud then hud.gui:Destroy(); hud = nil end
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if h then cam.CameraSubject = h end
	UIS.MouseBehavior = Enum.MouseBehavior.Default
	UIS.MouseIconEnabled = true
end

local function enter(m)
	if mech == m then return end
	leave()
	mech = m
	weapon, weaponAt = "rifle", -99   -- 탈 때는 늘 라이플 (서버 park 도 Weapon 을 지운다)
	ammoLocal, reloadLocalUntil = m:GetAttribute("Ammo") or CFG.gun(m).MagSize, 0   -- 장탄은 기체에 남는다(내렸다 다시 타도 그대로)
	gunSeen = m:GetAttribute("Gun") or "rifle"
	ammoConn = m:GetAttributeChangedSignal("Ammo"):Connect(function()
		local a = m:GetAttribute("Ammo") or CFG.gun(m).MagSize
		if a > ammoLocal + 1 then ammoLocal = a end   -- 장전 완료(올라갈 때)만 즉시 반영. 내려가는 건 내 예측이 앞선다
	end)
	local look = workspace.CurrentCamera.CFrame.LookVector
	baseFov = baseFov or workspace.CurrentCamera.FieldOfView   -- 줌·부스트 킥의 기준(탈 때 한 번)
	yaw = math.atan2(-look.X, -look.Z)
	pitch = 0
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.AutoRotate = false
		hum.PlatformStand = false   -- 사출 연출이 켰다가 못 끈 채 남은 경우 대비(10-25). 사출이면 다음 프레임 launchBegin 이 다시 켬
		-- 넘어짐/래그돌 상태에선 HipHeight 로 받쳐주지 않아 몸통이 바닥까지 내려앉는다(진단 로그로 확인). 상태 기계는 조종 클라이언트가 돌리므로 여기서 끈다
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)   -- 탈 때는 바로 뛸 수 있게
		lastLandAt, airSince, wasAirMine = -99, os.clock(), false
		lastJumpAt, lastHumState = -99, nil
		hum:ChangeState(Enum.HumanoidStateType.Running)
		diedConn = hum.Died:Connect(leave)
	end
	-- 몸 방향은 물리 제약으로 맞춘다(매 프레임 CFrame 을 덮어쓰면 고속 이동 때 떨린다)
	local root = m:FindFirstChild("HumanoidRootPart")
	if root then
		local att = root:FindFirstChild("FaceAtt") or Instance.new("Attachment")
		att.Name = "FaceAtt"; att.Parent = root
		faceAlign = Instance.new("AlignOrientation")
		faceAlign.Name = "FaceAlign"; faceAlign.Mode = Enum.OrientationAlignmentMode.OneAttachment
		faceAlign.Attachment0 = att; faceAlign.RigidityEnabled = false
		faceAlign.MaxTorque = math.huge; faceAlign.Responsiveness = CFG.TurnResponsiveness; faceAlign.MaxAngularVelocity = CFG.TurnRate
		faceAlign.CFrame = CFrame.Angles(0, yaw, 0)
		faceAlign.Parent = root
		-- 오르는 동안만 켜는 위쪽 힘(같은 방식: 조종 클라가 물리를 돌리므로 여기서 만든 제약이 그대로 먹는다)
		jumpAssist = Instance.new("VectorForce")
		jumpAssist.Name = "JumpAssist"; jumpAssist.Attachment0 = att
		jumpAssist.RelativeTo = Enum.ActuatorRelativeTo.World; jumpAssist.ApplyAtCenterOfMass = true
		jumpAssist.Force = Vector3.zero; jumpAssist.Enabled = false
		jumpAssist.Parent = root
		jumpRising = false
		jumpWindupAt, windStartLocal = nil, nil
		boostHeld = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.Q)
		holdActive, holdAirSent, holdLocked, airDashUsed = false, false, false, false
		dashUntil, dashVel, carryVel, jumpBoostVel = 0, nil, nil, nil
	end
	hud = makeHUD()
	UIS.MouseIconEnabled = false
end

local function onCharacter(c)
	if c and c:GetAttribute("IsMech") then enter(c) else leave() end
end
player.CharacterAdded:Connect(onCharacter)
player:GetPropertyChangedSignal("Character"):Connect(function() onCharacter(player.Character) end)
if player.Character then onCharacter(player.Character) end

-- ================= 입력 =================
local function aimPoint()
	local cam = workspace.CurrentCamera
	local o = cam.CFrame.Position
	local d = cam.CFrame.LookVector * math.max(600, CFG.gun(mech).Range + 50)   -- 저격총 사거리 900 까지 조준점이 닿게
	local r = workspace:Raycast(o, d, exclude({ mech }))
	return r and r.Position or (o + d)
end

-- ================= 미사일 컨테이너 (G, 2026-10-25) =================
-- 종아리 양쪽 포드 6발 일괄 사출 → 포드 버림(서버). 출격마다 한 번(속성 MissilePods).
-- 조준 사격(10-25 13:15, 유저 "A로 가자"): 록온·마름모 없음. 라이플처럼 조준점으로 쏘고, 유도 대상(쏘는 순간 조준점
--   MissileSeekCone 안의 적)은 서버가 카메라 위치·조준점으로 정한다. 판정은 서버가 날린 미사일로.
-- 화면: 서버가 보낸 사출 정보(위치·방향·사출 시각·노리는 기체)로 같은 식(약한 유도)을 서버 시각에 맞춰 날려 그린다.
--   늦게 받은 만큼은 빨리 감아 따라잡고, 터진 곳은 서버가 알려 준다("missileBoom")
local function missileBodyCenter(model)
	local r = model:FindFirstChild("HumanoidRootPart")
	return r and (r.Position + Vector3.new(0, 3, 0)) or nil   -- 서버 bodyCenter 와 같은 식
end
local function fireMissiles()
	if not mech or mech:GetAttribute("MissilePods") ~= true then return end
	local hum = mech:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	-- 조준점 + 카메라 위치(서버가 "조준점에서 몇 도" 를 재는 기준. 서버가 기체 근처인지 검사한다)
	Remotes.MechMissile:FireServer(aimPoint(), workspace.CurrentCamera.CFrame.Position)
end
-- 미사일 모습: 밝은 회색 몸통 + 빨간 탄두 색 불빛 + 연기 꼬리(Trail)
local function makeMissile()
	local p = Instance.new("Part")
	p.Name = "MissileFx"; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Size = Vector3.new(0.6, 0.6, 2.0); p.Material = Enum.Material.SmoothPlastic; p.Color = Color3.fromRGB(214, 218, 222)
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.35, 1.0); a0.Parent = p
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.35, 1.0); a1.Parent = p
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0; tr.Attachment1 = a1; tr.Lifetime = 0.6; tr.MinLength = 0.05; tr.FaceCamera = true; tr.LightEmission = 0.25
	tr.Color = ColorSequence.new(Color3.fromRGB(255, 190, 120), Color3.fromRGB(150, 150, 155))
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
	tr.Parent = p
	local l = Instance.new("PointLight"); l.Color = Color3.fromRGB(255, 150, 70); l.Brightness = 2; l.Range = 10; l.Parent = p
	p.Parent = workspace.CurrentCamera
	return p
end
local function missileBoomFx(pos, dealt, fizzle, scale)   -- scale: 크기 배율(없으면 1)
	if fizzle then   -- 연료가 다해 공중에서 소멸: 작은 연기만
		local b = fxPart(Color3.fromRGB(150, 150, 155), Vector3.one * 2, CFrame.new(pos), Enum.PartType.Ball)
		b.Material = Enum.Material.SmoothPlastic
		TweenService:Create(b, TweenInfo.new(0.4), { Size = Vector3.one * 5, Transparency = 1 }):Play()
		Debris:AddItem(b, 0.45)
		return
	end
	local b = fxPart(Color3.fromRGB(255, 160, 70), Vector3.one * 3, CFrame.new(pos), Enum.PartType.Ball)
	TweenService:Create(b, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * (dealt and 13 or 9) * (scale or 1), Transparency = 1 }):Play()
	Debris:AddItem(b, 0.4)
	spark(pos, Vector3.yAxis); spark(pos, -Vector3.yAxis)
	SM.play("MissileBoom", pos)
	local r = mech and mech:FindFirstChild("HumanoidRootPart")
	if r and (r.Position - pos).Magnitude < 45 then shake = math.max(shake, 0.6) end
end
local salvos = {}   -- [salvo] = { m, target, list = { {pos, dir, launch, simAge, alive, part, stuck} } }
local function stepMissile(sv, ms, h)
	-- 서버 fireSalvo 와 같은 식: MissileArm 뒤부터 노리는 기체 쪽으로 초당 MissileTurnRate 도까지만 꺾음
	-- 유도는 MissileGuideTime 동안만(10-25), 그 뒤엔 직진 — 서버와 같은 조건이어야 화면 궤적이 판정과 맞는다
	local arm = ms.arm or CFG.MissileArm
	if ms.simAge > arm and ms.simAge < arm + (CFG.MissileGuideTime or math.huge) and sv.target and sv.target.Parent then   -- 유도 시작 시각은 서버가 거리로 정해 보냄
		local c = missileBodyCenter(sv.target)
		if c then
			local want = c - ms.pos
			if want.Magnitude > 0.1 then
				want = want.Unit
				local ang = math.acos(math.clamp(ms.dir:Dot(want), -1, 1))
				if ang > 1e-4 then ms.dir = ms.dir:Lerp(want, math.min(1, math.rad(CFG.MissileTurnRate) * h / ang)).Unit end
			end
		end
	end
	local stepV = ms.dir * CFG.MissileSpeed * h
	-- 화면에서 무언가(벽·기체 몸)에 먼저 닿으면 거기 멈춰 서버의 터짐을 기다린다(뚫고 지나가 보이지 않게)
	if not sv.rp then
		sv.rp = RaycastParams.new(); sv.rp.FilterType = Enum.RaycastFilterType.Exclude
		sv.rp.FilterDescendantsInstances = { sv.m, workspace.CurrentCamera }   -- 쏜 기체 · 화면 이펙트(다른 미사일 포함)
	end
	local hit = workspace:Raycast(ms.pos, stepV, sv.rp)
	if hit then
		ms.pos = hit.Position; ms.stuck = true
	else
		ms.pos += stepV
	end
	ms.simAge += h
end
Remotes.MechFX.OnClientEvent:Connect(function(kind, m, salvo, x1, x2, x3, x4)
	if kind == "missile" then
		local list = {}
		for i, s in ipairs(x2 or {}) do list[i] = { pos = s.p, dir = s.d, launch = s.t, arm = s.a, simAge = 0, alive = true } end
		salvos[salvo] = { m = m, target = x1, list = list }
	elseif kind == "missileBoom" then
		local sv = salvos[salvo]
		local ms = sv and sv.list[x1]
		if ms then
			ms.alive = false
			if ms.part then ms.part:Destroy(); ms.part = nil end
		end
		missileBoomFx(x2, x3, x4)
	end
end)
RunService.RenderStepped:Connect(function()
	if next(salvos) == nil then return end
	local now = workspace:GetServerTimeNow()
	for key, sv in pairs(salvos) do
		local any = false
		for _, ms in ipairs(sv.list) do
			if ms.alive then
				any = true
				local age = now - ms.launch
				if age >= 0 then
					if not ms.part then
						ms.part = makeMissile()
						local f = fxPart(Color3.fromRGB(255, 200, 140), Vector3.one * 1.6, CFrame.new(ms.pos), Enum.PartType.Ball)
						TweenService:Create(f, TweenInfo.new(0.12), { Size = Vector3.one * 3, Transparency = 1 }):Play()
						Debris:AddItem(f, 0.15)
						SM.play("MissileLaunch", ms.pos)
					end
					if age > CFG.MissileLife + 0.6 then   -- 서버 소식이 끝내 안 오면 정리
						ms.alive = false; ms.part:Destroy(); ms.part = nil
					else
						-- 서버 시각까지 1/60 초씩 감아 따라잡는다(늦게 받은 만큼·프레임 차이 무관하게 같은 궤적)
						local guard = 0
						while not ms.stuck and ms.simAge < age and guard < 40 do
							stepMissile(sv, ms, math.min(1 / 60, age - ms.simAge)); guard += 1
						end
						ms.part.CFrame = CFrame.lookAlong(ms.pos, ms.dir)
					end
				end
			end
		end
		if not any then salvos[key] = nil end
	end
end)

-- ================= 손목 미사일 런처 (G, 2026-10-26 AELLO) =================
-- 기체 속성 SubWeapon == "Grenade"(런처 이름) 면 G 가 종아리 포드 대신 이것. 비행·피해·화면 = 미사일 것 그대로
--   (MechMissile → 서버 GRN.fire → fireSalvo 에 손목 관 하나 → MechFX "missile"/"missileBoom" → 위 미사일 그리기).
--   23:54 유저 "포물선 말고 내가 생각했던 건 미사일" → 23:27 의 곡사 탄·자체 그리기는 걷어냄. 다른 건 탄 수(2발 + 다시 참)뿐.
-- 누르면 왼팔을 라이플 조준 자세로 잠깐 들고(GR.AIM_HOLD), GR.SEND_DELAY 뒤 든 팔의 총구 자리를 같이 보낸다(서버 팔은 차렷이라).
-- 덮개(GLCoverL): 쏠 때 팔꿈치 쪽으로 밀려 열렸다 닫힘 — 관절 GLCoverJointL 의 속성 SlideOpen(C0 축 = 아래팔 축, 템플릿에 박음)
-- 최상위 local 개수 한도(200) 때문에 표 하나(GR)에 모음
local GR = { AIM_HOLD = 0.45, SEND_DELAY = 0.1, localAt = 0,
	aimAt = setmetatable({}, { __mode = "k" }),    -- [기체] = 쏜 시각(os.clock) → animOne 이 조준 자세 유지에 씀
	cover = setmetatable({}, { __mode = "k" }) }   -- [기체] = 덮개 연 시각(os.clock)
-- 10-30 FALCO 라이더킥(C) · 마비 덫(X) 화면 쪽 = 자식 모듈 MechFalco(Source 20만 자 한도) — 쓰는 것만 넘김
GR.F = require(script:WaitForChild("MechFalco"))
GR.F.init({ mech = function() return mech end, aimPoint = aimPoint, fxPart = fxPart, exclude = exclude, spark = spark,
	shake = function(v) shake = math.max(shake, v) end })
-- 10-30 FELSEN 궁극기(X) 도끼 도약 내려찍기 화면 쪽 = 자식 모듈 MechFelsen(같은 이유) — 비행 · 도끼 자세 시각 · 착지 원 · 내려찍기 이펙트
GR.FE = require(script:WaitForChild("MechFelsen"))
GR.FE.init({ mech = function() return mech end, fxPart = fxPart, spark = spark, shake = function(v) shake = math.max(shake, v) end })
GR.reloadSlow = 1      -- 10-30 내 장전 예측의 둔화 배율(마비 덫 — MechPoses.reloadElapsed 가 읽음)
GR.meleeSlowLast = 1   -- 10-30 마지막 근접을 누를 때 둔화 배율(쿨 검사)
function GR.fire()   -- 손목 런처 기체면 true(쏘든 못 쏘든 — 종아리 미사일로 넘어가지 않게), 아니면 false
	local m = mech
	if not m or m:GetAttribute("SubWeapon") ~= "Grenade" then return false end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return true end
	if CFG.grenadeAmmo(m, workspace:GetServerTimeNow()) <= 0 then return true end
	local now = os.clock()
	if now - GR.localAt < CFG.GrenadeInterval then return true end
	GR.localAt = now
	GR.aimAt[m] = now
	task.delay(GR.SEND_DELAY, function()   -- 이 LocalScript 는 상주라 예약이 회수되지 않음
		if mech ~= m then return end
		local arm = m:FindFirstChild("LowerArmL")
		local n = CFG.grenadeAmmo(m, workspace:GetServerTimeNow())
		local tube = arm and arm:FindFirstChild("GrenadeTube" .. ((CFG.GrenadeAmmo - n) % 2 + 1))
		Remotes.MechMissile:FireServer(aimPoint(), workspace.CurrentCamera.CFrame.Position, tube and tube.WorldPosition or nil)
	end)
	return true
end
-- ================= 10-30 SKADI 센서 지뢰 (G) — 규칙·수치 = MechConfig CFG.Mine · 판정 = MechServer MINE =================
-- 내 기체: 속성 SubWeapon == "Mine" 이면 G = 지뢰 깔기(서버가 개수·자리·필드 최대를 다 정함). 지뢰 기체면 true(깔든 못 깔든 — 미사일로 안 넘어가게)
-- 모든 화면: 지뢰(태그 "MechMine")의 속성 시각으로 렌즈(MineLens)를 그림 — 켜지기 전 흐린 깜빡임 · 켜짐 = 숨쉬듯 은은히 ·
--   감지(WarnAt) = 빨강 빠른 깜빡임 + 땅에 범위 원(반지름 = 판정 Radius — 예고와 판정이 같은 모양). 서버 파트를 이 화면에서만 바꿈(복제 안 됨)
--   10-30 02:15 버그(유저 "지뢰가 터진 이후 경고 표시가 사라지질 않아"): 범위 원을 약한 키 표([지뢰] = 원)에 두고 "지뢰가 사라지면 원을 지움"으로 짰는데,
--   인스턴스를 약한 키로 쓰면 Lua 쪽 껍데기가 가비지 수거되며 줄이 먼저 빠짐 → 지울 원을 못 찾고 화면에 남음 [에디트 실측: 파트가 workspace 에 있는데도 0.5초 안에 줄 0].
--   → 원을 지뢰 모델 안(이 화면에서만)에 넣음 = 서버가 지뢰를 지우면 같이 사라짐(지우는 코드 자체가 없음 · 결과 보장)
GR.mineAt = 0
GR.MINE_GREEN, GR.MINE_RED = Color3.fromRGB(90, 255, 160), Color3.fromRGB(255, 64, 64)
GR.ULT_RED = Color3.fromRGB(255, 56, 72)   -- 10-30 궁극기 발광 빨강(SkadiPalette_UltRed 발광 칸과 같은 색)
function GR.mine()
	local m = mech
	if not m or m:GetAttribute("SubWeapon") ~= "Mine" then return false end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return true end
	if CFG.mineAmmo(m, workspace:GetServerTimeNow()) <= 0 then return true end
	local now = os.clock()
	if now - GR.mineAt < CFG.Mine.Interval then return true end
	GR.mineAt = now
	Remotes.MechMine:FireServer()
	return true
end
RunService.RenderStepped:Connect(function()
	local list = CollectionService:GetTagged("MechMine")
	if #list == 0 then return end
	local now = workspace:GetServerTimeNow()
	for _, mn in ipairs(list) do
		local lens = mn:FindFirstChild("MineLens")
		if lens then
			local arm, warnAt = mn:GetAttribute("ArmAt") or 0, mn:GetAttribute("WarnAt")
			local col, tr = GR.MINE_GREEN, 0
			if warnAt then
				col, tr = GR.MINE_RED, ((math.floor((now - warnAt) * 16) % 2 == 0) and 0 or 0.85)   -- 초당 8번
			elseif now < arm then
				tr = (math.floor(now * 4) % 2 == 0) and 0.55 or 0.9                                  -- 켜지는 중: 초당 2번 흐리게
			else
				tr = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(now * 2 * math.pi * 0.7))                    -- 켜짐: 은은히
			end
			if lens.Color ~= col then
				lens.Color = col
				for _, p in ipairs(mn:GetChildren()) do   -- 발톱 발광 줄(ClawGlow*)도 같은 색(깜빡임은 렌즈만)
					if p:IsA("BasePart") and p.Name:sub(1, 8) == "ClawGlow" then p.Color = col end
				end
			end
			if lens.Transparency ~= tr then lens.Transparency = tr end
			if warnAt and not mn:FindFirstChild("MineRing") then
				local body = mn.PrimaryPart or lens
				local base = body.Position - Vector3.new(0, (mn:GetAttribute("Bottom") or 0.25) - 0.06, 0)
				local R = CFG.Mine.Radius
				local ring = fxPart(GR.MINE_RED, Vector3.new(0.08, R * 2, R * 2), CFrame.new(base) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
				ring.Name = "MineRing"; ring.Transparency = 0.72
				ring.Parent = mn   -- 지뢰 모델 안 = 지뢰와 함께 사라짐(위 버그 설명)
			end
		end
	end
end)
Remotes.MechFX.OnClientEvent:Connect(function(kind, owner, pos, hit)
	if kind ~= "mineBoom" or typeof(pos) ~= "Vector3" then return end
	missileBoomFx(pos, hit, false, 24 / 13)   -- 불덩이 최대 지름 24 = 판정 범위(Radius 12)
	local R = CFG.Mine.Radius
	local ring = fxPart(GR.MINE_GREEN, Vector3.new(0.12, 4, 4), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Enum.PartType.Cylinder)
	ring.Transparency = 0.3
	TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.12, R * 2, R * 2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.35)
end)
-- ================= 10-30 궁극기 (X) — 공용 게이지·규칙 = MechConfig CFG.Ult · 판정 = MechServer ULT / MechDamage.hurt =================
-- 내 기체: 속성 Ultimate 가 있고 게이지(UltGauge)가 Max 면 X → 서버 MechUlt. 서버가 조건(땅·경직·이미 쓰는 중)을 다시 봄
-- 모든 화면: SKADI 강제 앵커 동안(꿇는 중 + 사격 창) 총구에서 겨눈 방향으로 레이저 + 끝 점 [결정 10-29 경계 규칙 4 — 적도 노리는 곳을 앎]
--   방향 = 내 기체는 카메라 조준점 · 남의 기체는 서버 속성 AimYaw·AimPitch(두 손 자세 IK 와 같은 식). 지형·기체에 막히면 거기서 끝
--   10-30 02:15 유저 "궁극기 지속시간 동안 기존 초록 발광이 빨강으로": 기체 발광(SurfaceAppearance)을 궁극기 모습으로 갈아 끼움(GR.setUltLook)
--     + 레이저도 같은 빨강(원래 결정은 초록 레이저 — 몸만 빨강이면 따로 놀아서 맞춤 [제안])
-- 표는 강한 키 + 매 프레임 "기체가 사라졌으면 정리"(약한 키는 인스턴스 껍데기 수거로 줄이 먼저 빠져 파트가 남음 — 지뢰 범위 원 버그와 같은 구조)
GR.ultAt, GR.laser, GR.ultLook = 0, {}, {}
-- 궁극기 모습: 색 지도(ColorMap)는 실행 중 스크립트로 못 바꿈 → 미리 만든 SurfaceAppearance(MechProto.<속성 UltLook> — SKADI = SkadiUltLook,
--   발광 칸만 빨강인 팔레트 SkadiPalette_UltRed)를 파트마다 갈아 끼우고, 원래 것은 기억했다가 끝나면 되돌림. 발광 세기·마스크는 원래와 같음
--   (발광 = 색 지도 × 틴트 × 세기라 틴트만 빨강으로 바꾸면 초록 색 지도에 곱해져 칙칙한 노랑·주황이 됨 → 색 지도째 바꿈)
function GR.setUltLook(m, on)
	local cur = GR.ultLook[m]
	if on and not cur then
		local tpl = Proto:FindFirstChild(m:GetAttribute("UltLook") or "")
		if not (tpl and tpl:IsA("SurfaceAppearance")) then return end
		local list = {}
		for _, sa in ipairs(m:GetDescendants()) do
			if sa:IsA("SurfaceAppearance") and sa.Parent and sa.Parent:IsA("MeshPart") then list[#list + 1] = sa end
		end
		cur = {}
		for _, sa in ipairs(list) do
			local part = sa.Parent
			local red = tpl:Clone()
			sa.Parent = nil
			red.Parent = part
			cur[sa] = { part = part, red = red }
		end
		GR.ultLook[m] = cur
		GR.ultParticles(m, true)
		if not GR.ultLookLogged then   -- 10-30 진단(한 번만): 처음 갈아 끼우는 순간 색 지도를 다 받아 뒀나 — Success 인데도 회색이면 원인은 받기가 아님
			GR.ultLookLogged = true
			local CP = game:GetService("ContentProvider")
			local s = {}
			for _, id in ipairs(GR.ultLookIds or {}) do
				local ok, st = pcall(CP.GetAssetFetchStatus, CP, id)
				s[#s + 1] = id .. "=" .. tostring(ok and st or "?")
			end
			print("[UltLook] 첫 갈아 끼움 — 색 지도 받기 상태: " .. (#s > 0 and table.concat(s, ", ") or "(미리 받기 목록 없음)"))
		end
	elseif not on and cur then
		for sa, x in pairs(cur) do
			x.red:Destroy()
			if x.part.Parent then sa.Parent = x.part end
		end
		GR.ultLook[m] = nil
		GR.ultParticles(m, false)
	end
end
-- 10-30 09:42 유저 "궁극기 사용 시 붉은 입자가 부스터 쓰듯 등 뒤에서 지속적으로 흩날리게": 등 노즐의 ParticleEmitter "UltFlame"(템플릿에 박음 —
--   studio/build_SkadiBoostParticles.lua 줄기·가루 2개씩)을 발광 빨강과 같은 때 켜고 끔. 부스트 입자("Flame")와 이름이 달라 setThrusters 가 안 건드림
function GR.ultParticles(m, on)
	for _, e in ipairs(m:GetDescendants()) do
		if e:IsA("ParticleEmitter") and e.Name == "UltFlame" and e.Enabled ~= on then e.Enabled = on end
	end
end
-- 10-30 10:28 유저 "궁극기 처음 쓸 때 잠시 스카디가 회색이 되더라 — 프리로드": 궁극기 모습 색 지도(SkadiUltLook ColorMap — 원래 것과 이것만 다름,
--   발광 마스크는 같음)는 처음 갈아 끼울 때 받기 시작해 받는 동안 색 지도 없이(회색) 그려짐 [추측: "처음만" 이라는 증상 + 다른 칸은 다 같은 그림이라는 측정]
--   → 이 화면이 뜰 때 MechProto 바로 밑 SurfaceAppearance(= 궁극기 모습들, 이름 목록 없이)의 색 지도를 미리 받음. 남의 궁극기를 처음 볼 때도 같이 해결
--   10-30 10:33 유저 "여전히 첫 시전 때 회색" → 첫 판은 헛돌았음 [에디트 실측]: PreloadAsync 에 SurfaceAppearance 를 넣으면 아무것도 안 받음(콜백 0번 · 0초),
--     ID 문자열로 넣으면 Failure(원래 색 지도도 같음). Decal·ImageLabel 에 같은 ID 를 넣어 주면 Success → 빈 Decal(부모 없음)에 담아 받음
--   ID = SA.ColorMap(실행 중 읽히면) 아니면 SA 속성 ColorMapId(에디트에서 박음 — ⚠️ 색 지도를 바꾸면 이 속성도 같이)
--   ⚠️ 받은 뒤에도 회색이면 원인은 받기가 아님 → 갈아 끼울 때 찍는 [UltLook] 줄(받기 상태)로 가름(GR.setUltLook)
task.spawn(function()
	local CP = game:GetService("ContentProvider")
	local list, ids = {}, {}
	for _, x in ipairs(Proto:GetChildren()) do
		if x:IsA("SurfaceAppearance") then
			local ok, id = pcall(function() return x.ColorMap end)
			if not (ok and type(id) == "string" and id ~= "") then id = x:GetAttribute("ColorMapId") end
			if type(id) == "string" and id ~= "" then
				local d = Instance.new("Decal"); d.Texture = id
				list[#list + 1] = d; ids[#ids + 1] = id
			end
		end
	end
	GR.ultLookIds = ids
	if #list == 0 then return end
	local bad = 0
	local ok, err = pcall(function()
		CP:PreloadAsync(list, function(_, status)
			if status ~= Enum.AssetFetchStatus.Success then bad += 1 end
		end)
	end)
	for _, d in ipairs(list) do d:Destroy() end
	print(("[UltLook] 궁극기 모습 미리 받기 끝 — %d개 · 실패 %d%s"):format(#list, bad, ok and "" or (" · 오류 " .. tostring(err))))
end)
-- 10-30 10:04 유저 "이대로 가자"(SKADI 저격총 변형 시안 C — 양각대 대신 총이 바뀜): 총(Rifle) 안 관절 5개 = 템플릿 studio/build_SkadiRifleC.lua
--   날개 RifleWingJointL/R = 앵커 꿇은 정도(anW)만큼 Deploy(경첩 둘레 회전 — 바깥 65° · 아래 12°)
--   덮개 RifleShroudJointT/B · 총구 RifleMuzzleJoint = 궁극기 정도만큼 Slide(위·아래 0.3 · 앞 0.8)
--   궁극기 정도 = CFG.ultPhase(꿇는 중 + 사격 창 — 빨강 발광과 같은 때)면 1 로, 아니면 0 으로 초당 6 씩 다가감
--     (서버 시각 속성으로 매 프레임 다시 계산 → 끄는 코드 없이 저절로 닫힘 · 모든 화면이 같음)
--   총구 부착점(Rifle.Muzzle)도 늘어난 만큼 앞으로 = 불꽃·탄도선·레이저 출발점이 보이는 총구에서(이 화면에서만 — 서버 판정은 화면이 보낸 총구, gunReach 여유 10 안)
--   관절 틀 = 템플릿 축(C0·C1 회전 없음, Rifle 도 쉬는 자세 회전 없음) → 부착점(Rifle 로컬)에 Slide 를 그대로 더함
--   ⚠️ 이 함수는 아래쪽에서 정의되는 지역 함수(sstep 등)를 못 봄 — 부드럽게 하는 식을 안에 씀
GR.RIFLE_FORM = { "RifleWingJointL", "RifleWingJointR", "RifleShroudJointT", "RifleShroudJointB", "RifleMuzzleJoint" }
function GR.rifleForm(m, st, J, P, anW, dt)
	if not (J.RifleWingJointL or J.RifleMuzzleJoint) then return end
	local f = st.ultForm or 0
	f += ((CFG.ultPhase(m) and 1 or 0) - f) * math.min(1, dt * 6)
	st.ultForm = f
	local u = f * f * (3 - 2 * f)
	for _, n in ipairs(GR.RIFLE_FORM) do
		local j = J[n]
		if j then
			local dep, sl = j:GetAttribute("Deploy"), j:GetAttribute("Slide")
			if dep then P[n] = CFrame.new():Lerp(dep, anW)
			elseif sl then P[n] = CFrame.new(sl * u) end
		end
	end
	local mj = J.RifleMuzzleJoint
	local mz = mj and mj.Part0 and mj.Part0:FindFirstChild("Muzzle")
	local sl = mj and mj:GetAttribute("Slide")
	if mz and sl then
		if st.muzzleAtt ~= mz then st.muzzleAtt, st.muzzle0 = mz, mz.CFrame end   -- 처음 볼 때(또는 총이 새것일 때) 원래 자리 기억
		mz.CFrame = st.muzzle0 + sl * u
	end
end
function GR.ult()
	local m = mech
	if not m or not m:GetAttribute("Ultimate") then return end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	if (m:GetAttribute("UltGauge") or 0) < CFG.Ult.Max or CFG.ultPhase(m) or CFG.trapPhase(m) or GR.locked(m) then return end
	local kindU = m:GetAttribute("Ultimate")   -- 10-30 FALCO 마비 덫(ParalysisTrap)은 공중에서도 · 아래 두 줄은 SKADI 강제 앵커만
	if kindU == "ForcedAnchor" and CFG.anchorPhase(m) == "rise" then return end
	if kindU == "ForcedAnchor" and not CFG.anchorPhase(m) and hum.FloorMaterial == Enum.Material.Air then return end   -- 공중에선 못 꿇음(서버도 거절)
	local now = os.clock()
	if now - GR.ultAt < 0.5 then return end
	GR.ultAt = now
	if (kindU == "AxeLeap" or kindU == "AxeCharge") and GR.setWeapon then GR.setWeapon("saber") end   -- 10-30 FELSEN 도약 = 도끼를 든 상태로(서버도 Weapon 을 바꿈)
	Remotes.MechUlt:FireServer(aimPoint())   -- 10-30 조준점 = FALCO 마비 덫 자리(SKADI 는 안 씀)
end
RunService.RenderStepped:Connect(function()
	local nowS = workspace:GetServerTimeNow()
	for _, m in ipairs(CollectionService:GetTagged("Mech")) do
		local L = GR.laser[m]
		local on = m.Parent ~= nil and m:GetAttribute("UltEnd") ~= nil and CFG.ultPhase(m, nowS) ~= nil
		if m:GetAttribute("UltLook") then GR.setUltLook(m, on) end   -- 궁극기 동안 발광 빨강
		local mz = on and m:FindFirstChild("Rifle") and m.Rifle:FindFirstChild("Muzzle")
		local root = m:FindFirstChild("HumanoidRootPart")
		if mz and root then
			local from = mz.WorldPosition
			local dir
			if m == mech then
				dir = aimPoint() - from
			else
				local yo, pd = m:GetAttribute("AimYaw") or 0, m:GetAttribute("AimPitch") or 0
				dir = (root.CFrame.Rotation * CFrame.Angles(0, math.rad(yo), 0) * CFrame.Angles(math.rad(pd), 0, 0)).LookVector
			end
			if dir.Magnitude > 0.01 then
				dir = dir.Unit * CFG.gun(m).Range
				local hit = workspace:Raycast(from, dir, exclude({ m, workspace.CurrentCamera }))
				local to = hit and hit.Position or (from + dir)
				if not L then
					L = { beam = fxPart(GR.ULT_RED, Vector3.new(0.14, 0.14, 1), CFrame.new(from)),
						dot = fxPart(GR.ULT_RED, Vector3.one * 0.9, CFrame.new(to), Enum.PartType.Ball) }
					L.beam.Transparency = 0.3
					GR.laser[m] = L
				end
				local len = (to - from).Magnitude
				L.beam.Size = Vector3.new(0.14, 0.14, len)
				L.beam.CFrame = CFrame.lookAt((from + to) / 2, to)
				L.dot.CFrame = CFrame.new(to)
				L.dot.Transparency = hit and 0.1 or 1   -- 하늘로 향하면 끝 점은 안 보임
			end
		elseif L then
			L.beam:Destroy(); L.dot:Destroy(); GR.laser[m] = nil
		end
	end
	for m, L in pairs(GR.laser) do   -- 사라진 기체
		if not m.Parent then L.beam:Destroy(); L.dot:Destroy(); GR.laser[m] = nil end
	end
	for m in pairs(GR.ultLook) do   -- 사라진 기체(갈아 낀 것도 기체와 함께 사라짐 — 기억만 지움)
		if not m.Parent then GR.ultLook[m] = nil end
	end
end)
Remotes.MechFX.OnClientEvent:Connect(function(kind, m)
	-- 손목 런처 기체가 쏜 미사일 소식이면 덮개를 열고(모두의 화면), 남의 기체는 팔도 듦. 탄 그리기는 위 미사일 처리기가 함
	if kind == "missile" and m and m:GetAttribute("SubWeapon") == "Grenade" then
		GR.cover[m] = os.clock()
		if m ~= mech then GR.aimAt[m] = os.clock() end
	end
end)
RunService.RenderStepped:Connect(function()
	-- 덮개: 0.06초에 열림 → 0.45초까지 열린 채 → 0.15초에 닫힘. 끝나면 0(닫힘)으로 되돌려 놓고 목록에서 뺌
	for m, t0 in pairs(GR.cover) do
		local e = os.clock() - t0
		local k = (e < 0.06) and (e / 0.06) or (e < 0.45) and 1 or (e < 0.6) and (1 - (e - 0.45) / 0.15) or 0
		local j = m.Parent and m:FindFirstChild("GLCoverJointL", true)
		if j then j.Transform = CFrame.new((j:GetAttribute("SlideOpen") or Vector3.zero) * k) end
		if e >= 0.6 then GR.cover[m] = nil end
	end
end)

-- ================= 10-27 FELSEN: 과열 개틀링 · 작살 그랩(시그니처 C) — 최상위 local 한도 때문에 GR 표에 얹음 =================
-- [개틀링] 주무기 수치 Heat = true(CFG.Guns.gatling). 내 기체: 방아쇠를 당기면 회전(GR.spin → 서버 MechSpin → 속성 GunSpinAt),
--   SpinUp 이 지나야 나감 · 과열은 서버 속성(CFG.gunHeat) · 회전 중 걷기 × MoveMul.
--   모든 화면: 총(파트 "Rifle") 안의 관절 "GatlingSpin"(Part1 = 총열 뭉치, C0/C1 의 Z = 총열 축)을 돌리고,
--   속성 HeatGlow 가 있는 파트(총열)를 과열에 따라 금속 → 달궈짐 → 빨강 → 백열 주황(0.7 부터 Neon)으로, "HeatLight"(PointLight)·"HeatSmoke"(연기) 켬
-- [그랩] 기체 속성 Signature == "Grab": C → 왼팔 조준 자세(GR.aimAt, 손목 런처와 같은 경로) → SendDelay 뒤 손목 "GrappleMuzzle" 자리와 함께 MechGrab.
--   맞은 기체(조종사 = 나)는 속성 PullAt/PullTo/PullFace/PullTime 대로 직접 끌려감(GR.drive, PlatformStand) · StunUntil 까지 입력 무시(GR.locked)
--   화면: MechFX "grab"(작살이 날아감 + 줄) / "grabEnd"(맞으면 상대를 따라 끌려옴, 빗나가면 감겨 돌아옴)
GR.spinLocal, GR.spinSince = false, 0
GR.gat = setmetatable({}, { __mode = "k" })      -- [기체] = 총 그리기 상태(총열 회전 각·속도·마지막 과열)
GR.hooks, GR.grabAt, GR.pullSeen = {}, 0, setmetatable({}, { __mode = "k" })
GR.HEAT = { Color3.fromRGB(72, 76, 82), Color3.fromRGB(112, 44, 34), Color3.fromRGB(196, 48, 26), Color3.fromRGB(255, 120, 44) }
function GR.spin(want)   -- 내 기체 회전 상태가 바뀔 때만 서버에 알림
	if want == GR.spinLocal then return end
	GR.spinLocal, GR.spinSince = want, os.clock()
	Remotes.MechSpin:FireServer(want)
end
function GR.spunUp(G) return GR.spinLocal and os.clock() - GR.spinSince >= (G.SpinUp or 0) end
function GR.heatColor(h)
	local C = GR.HEAT
	if h < 0.35 then return C[1]:Lerp(C[2], h / 0.35) end
	if h < 0.7 then return C[2]:Lerp(C[3], (h - 0.35) / 0.35) end
	return C[3]:Lerp(C[4], math.min(1, (h - 0.7) / 0.3))
end
function GR.locked(m) return m ~= nil and (CFG.stunned(m) or (m == mech and (GR.F.busy() or GR.FE.grabBusy()))) end   -- 10-30 내 그랩도 누른 순간부터   -- 10-30 내 라이더킥은 서버 속성이 오기 전부터
-- 10-27 총별 자세 속성(손 총 파트 "Rifle" 의 속성, 없으면 기체 모양 SH 값): ArmOut(로우 레디 팔 벌림) · ZoomHand(두 손 오른손 자리)
--   · Stow*/Via*(등·허리 뒤 수납 잡기·경유 자세 CFrame). 개틀링은 라이플보다 크고 허리 뒤 자리가 달라서 [rig/gat_*.py]
GR.poseCache = setmetatable({}, { __mode = "k" })
function GR.gunAttr(st, m, k) local g = st.rifleHand or m:FindFirstChild("Rifle"); return g and g:GetAttribute(k) end
function GR.gunPose(g)
	if not g then return nil end
	local c = GR.poseCache[g]
	if c == nil then
		c = false
		if g:GetAttribute("StowShoulderR") then
			c = { stow = { ShoulderR = g:GetAttribute("StowShoulderR"), ElbowR = g:GetAttribute("StowElbowR"), Grip = g:GetAttribute("StowGrip") } }
			if g:GetAttribute("ViaShoulderR") then c.via = { ShoulderR = g:GetAttribute("ViaShoulderR"), ElbowR = g:GetAttribute("ViaElbowR"), Grip = g:GetAttribute("ViaGrip") } end
		end
		GR.poseCache[g] = c
	end
	return c or nil
end
-- 10-27 16:16 허리 사격 자세 C(유저 "총구는 안쪽, 두 손으로 받쳐 쏘게" → "몸체를 틀어서 총열 = 발사 각"): 총 속성
--   HipHand(오른손 자리, 줌의 ZoomHand 와 같은 가슴 조준 틀) · HipLeft(왼손, 총 파트 로컬) · HipTurn(몸 전체 = Root 를 돌릴 각, − = 오른쪽)
--   · HipTwist(허리를 더 틀 각). 있는 총(개틀링)만 조준 때 한 손 뻗기 대신 이 자세. 없으면 nil
--   kh = 조준 섞임 k × (1 − 줌) — 줌(우클릭)은 기존 두 손 자세가 이김. 몸 방향 = 다리 방향(legYaw) + HipTurn·kh(±75 안),
--   몸통 = 그 위에 허리로 (HipTurn + HipTwist)·kh 만큼(다리 방향과 무관), 목은 그만큼 되돌림 [rig/hip_pose.py hip4 · 측정: 총열 ↔ 탄 0° · 총 보임 51~59%]
function GR.hipParams(st, m, wsMode, k, kz, legYaw)
	if wsMode == "saber" then return nil end
	local hand = GR.gunAttr(st, m, "HipHand")
	if not hand then return nil end
	local kh = k * (1 - kz)
	local turn, twist = GR.gunAttr(st, m, "HipTurn") or 0, GR.gunAttr(st, m, "HipTwist") or 0
	return { kh = kh, rootYaw = math.clamp(legYaw + turn * kh, -75, 75), torso = (turn + twist) * kh,
		opt = { hand = hand, left = GR.gunAttr(st, m, "HipLeft"), turn = turn } }
end
-- 10-27 16:56 등 탄약통 장전(유저 "A로 가자" — 실제 미니건처럼 탄약통을 통째로 바꿈): 백팩 Motor6D "AmmoBoxJoint"(Part1 = 탄약통, 적용 스크립트가 만듦)
--   장전 0.15초: 빈 통이 떨어짐(복제본, 화면마다 따로, 바깥·위로 튕겨 3초 뒤 사라짐) · 그동안 새 통은 백팩 안(관절 속성 Slide = 관절 틀 −X 2.3)
--   · 0.6~1.4초: 밀려 나옴 · 2.3초: 철컥(바깥으로 0.12 튐 + 총열 한 바퀴) [rig/ammo_anim.py]. 장전이 아니면 제자리(Transform 0)
--   통이 없는 기체(가져오기 전·다른 총)는 아무것도 안 함. 뒤 카메라에서 가장 잘 보이는 자리라 내 화면에서도 장전이 보임
-- 17:15 유저 "탄띠로 총과 탄약통을 잇자": 손 총 파트 안 Beam "AmmoBelt"(Attachment1 = 총 뒤 뚜껑 "BeltIn") ↔ 통 급탄관 "BeltOut"(Attachment0, 여기서 이음).
--   카메라를 보는 띠(FaceCamera) + 탄 그림 되풀이(TextureLength = 탄 간격). 보임 = 총을 손에 들었을 때(허리 뒤 수납이면 숨김) · 장전 0.15~1.4초(통 교체 중) 숨김.
--   흐름(TextureSpeed): 쏘는 동안 18(초당 발 수 [추측: 단위 = 그림 길이/초, 방향 = 통 → 총]) · 장전 1.4~2.3초 급탄 8 · 그 밖 0
--   곡선(CurveSize 5 · 5)과 자리는 겹침 검사로 고름 — 허리 사격 C·로우 레디·줌·장전·걷기 겹침 0~3칸 [rig/belt_fit.py]
function GR.belt(st, m, re)
	local hand = st.rifleHand or m:FindFirstChild("Rifle")
	local beam = hand and hand:FindFirstChild("AmmoBelt")
	if not beam then return end
	local out = st.beltOut
	if out == nil or (out and not out.Parent) then out = m:FindFirstChild("BeltOut", true) or false; st.beltOut = out end
	if out and beam.Attachment0 ~= out then beam.Attachment0 = out end
	local show = out and not st.rifleStowed and not (re and re >= 0.15 and re < 1.4) or false
	if beam.Enabled ~= show then beam.Enabled = show end
	local spd = ((os.clock() - (lastFireAt[m] or -99)) < 0.12 and not re) and 18 or ((re and re >= 1.4 and re < 2.3) and 8 or 0)
	if beam.TextureSpeed ~= spd then beam.TextureSpeed = spd end
end
function GR.ammoBox(st, m, re, root)
	GR.belt(st, m, re)
	local j = st.ammoJoint
	if j == nil or (j and not j.Parent) then j = m:FindFirstChild("AmmoBoxJoint", true) or false; st.ammoJoint = j end
	if not j then return end
	if not re then
		if st.ammoOff then j.Transform = CFrame.new(); st.ammoOff = false end
		st.ammoDropped = nil
		return
	end
	local slide = j:GetAttribute("Slide") or Vector3.new(-2.3, 0, 0)
	local x = math.clamp((re - 0.6) / 0.8, 0, 1)
	local u = (re < 0.6) and 1 or (1 - x * x * (3 - 2 * x))
	local ck = (re > 2.3 and re < 2.5) and math.sin((re - 2.3) / 0.2 * math.pi) or 0
	j.Transform = CFrame.new(slide * u - slide.Unit * 0.12 * ck); st.ammoOff = true
	if re >= 0.15 and not st.ammoDropped and j.Part1 and j.Part0 then
		st.ammoDropped = true
		if re < 0.6 then   -- 장전 중간에 본 화면(늦게 들어옴)은 안 떨굼
			local c = j.Part1:Clone()
			for _, d in ipairs(c:GetDescendants()) do if d:IsA("JointInstance") or d:IsA("Constraint") then d:Destroy() end end
			c.Name = "DroppedAmmoBox"; c.Anchored = false; c.CanQuery = false; c.CanTouch = false; c.CanCollide = true
			c.CFrame = j.Part0.CFrame * j.C0 * j.C1:Inverse()   -- 제자리(Transform 0)에서 떨어짐
			c.AssemblyLinearVelocity = root.CFrame.RightVector * 4 + Vector3.new(0, 2, 0) - root.CFrame.LookVector
			c.AssemblyAngularVelocity = -root.CFrame.LookVector * 2.5
			c.Parent = workspace
			Debris:AddItem(c, 3)
		end
	end
	local gv = GR.gat[m]
	if gv and ck > 0 then gv.speed = math.max(gv.speed, 0.9) end
end
function GR.grab()
	local m = mech
	if not m or m:GetAttribute("Signature") ~= "Grab" then return end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	if GR.locked(m) or (m:GetAttribute("GrabReadyAt") or 0) > workspace:GetServerTimeNow() then return end
	local now = os.clock()
	if now - GR.grabAt < 0.5 then return end
	GR.grabAt = now
	GR.FE.grabPress()   -- 10-30 FELSEN 그랩 전용 자세·잠금(MechFelsen) — 옛 왼팔 조준 자세(GR.aimAt) 대신
	Remotes.MechGrab:FireServer("wind")   -- 10-31 준비 동작(모든 화면이 팔을 뒤로 당김 — GrabWindAt)
	task.delay(CFG.Grab.Windup + 0.06, function()   -- 10-31 내지른 뒤 손등 발사구 자리로 쏨(내 화면은 Windup 에 0.07초 내지름) · 상주 LocalScript 라 예약이 회수되지 않음
		if mech ~= m then return end
		local arm = m:FindFirstChild("LowerArmL")
		local mz = arm and arm:FindFirstChild("GrappleMuzzle", true)
		Remotes.MechGrab:FireServer(aimPoint(), mz and mz.WorldPosition or nil)
	end)
end
-- 10-30 SKADI 시그니처: 앵커 자세(C, 속성 Signature == "Anchor"). 수치·규칙 = MechConfig CFG.Anchor
--   C → 서버 MechAnchor(true/false) → 서버가 속성 AnchorAt·AnchorRiseAt·AnchorReadyAt 를 씀 → 모든 화면이 CFG.anchorPhase 로 꿇기 자세를 그림
--   anchored = 꿇는 중·꿇음·일어나는 중(이동·점프·부스트·근접 막음) / busy = 꿇는 중·일어나는 중(사격도 막음 — 다 꿇은 "on" 에서만 쏨)
GR.anchorSent = 0
function GR.anchored(m) return m ~= nil and CFG.anchorPhase(m) ~= nil end
function GR.anchorBusy(m) local ph = m and CFG.anchorPhase(m); return ph == "kneel" or ph == "rise" end
function GR.anchor()
	local m = mech
	if not m or m:GetAttribute("Signature") ~= "Anchor" then return end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	local now = os.clock()
	if now - GR.anchorSent < 0.25 then return end   -- 연타로 켬/끔이 엇갈려 가지 않게
	local ph = CFG.anchorPhase(m)
	if ph == "rise" then return end
	if ph and CFG.ultPhase(m) then return end   -- 10-30 궁극기(강제 앵커) 동안 풀기 막힘(서버도 거절)
	if not ph then
		if GR.locked(m) or (m:GetAttribute("AnchorReadyAt") or 0) > workspace:GetServerTimeNow() then return end
		if hum.FloorMaterial == Enum.Material.Air then return end   -- 공중에선 못 꿇음(서버도 거절)
	end
	GR.anchorSent = now
	Remotes.MechAnchor:FireServer(ph == nil)
end
-- 내 기체가 작살에 맞았으면 그 길로 직접 끌려감. 끌려오는 중이면 true
function GR.drive(m, root, hum)
	local at = m:GetAttribute("PullAt")
	local T = m:GetAttribute("PullTime") or CFG.Grab.PullTime
	local nowS = workspace:GetServerTimeNow()
	if not at or nowS > at + T + 0.05 then
		if GR.pulling then GR.pulling = false; hum.PlatformStand = false end
		return false
	end
	local to, face = m:GetAttribute("PullTo"), m:GetAttribute("PullFace")
	if typeof(to) ~= "Vector3" then return false end
	if GR.pullSeen[m] ~= at then GR.pullSeen[m] = at; GR.pullFrom = root.Position; GR.pullK0 = math.clamp((nowS - at) / T, 0, 0.9) end
	GR.pulling = true
	hum.PlatformStand = true
	local k = math.clamp((nowS - at) / T, 0, 1)
	-- 10-30 FALCO 라이더킥 날림 = 포물선(꼭대기 PullArc, 없으면 곧게). 늦게 봤으면 남은 시간에 다시 맞춤 → 첫 프레임에 위로 튀지 않음(공중제비와 같은 방식)
	local arc, ka = m:GetAttribute("PullArc") or 0, math.clamp((k - GR.pullK0) / (1 - GR.pullK0), 0, 1)
	root.AssemblyLinearVelocity = Vector3.zero
	local kp = (m:GetAttribute("PullEase") == "in") and ka * ka or k * (2 - k)   -- 10-31 그랩 = 처음 천천히·끝에 가속(홱 끌려와 쾅) · 나머지 = 예전(처음 빠름)
	root.CFrame = CFrame.lookAlong(GR.pullFrom:Lerp(to, kp) + Vector3.new(0, 4 * arc * ka * (1 - ka), 0), typeof(face) == "Vector3" and face or root.CFrame.LookVector)
	return true
end
-- 10-30 10:48 SKADI 앞차기 공중제비(내 기체): 서버 속성 FlipAt(뜨는 서버 시각)·FlipTo(착지 자리)·FlipFace(찬 방향)대로 포물선을 직접 따라감
--   (GR.drive 와 같은 방식 — PlatformStand, 매 프레임 CFrame. 끌림이 먼저: 끌리면 서버가 FlipAt 을 지움)
--   높이 = CFG.Kick.Flip.Height(꼭대기) · 수평 = 처음 본 자리 → 착지 자리 직선. 늦게 봤으면(지연) 남은 시간에 포물선을 다시 맞춤 → 첫 프레임에 위로 튀지 않음
--   끝(Time + 0.05)에 놓아 줌: 착지 자리는 땅 위 서 있는 높이라 바로 섬. 하차·죽음은 기체 정리 쪽이 PlatformStand 를 되돌림
--   자세(웅크리고 한 바퀴)는 모든 화면이 animOne 에서 따로 그림
GR.flipSeen, GR.flipping, GR.flipFrom, GR.flipK0 = nil, false, nil, 0
function GR.flipDrive(m, root, hum)
	local F = CFG.Kick.Flip
	local at = m:GetAttribute("FlipAt")
	local to, face = m:GetAttribute("FlipTo"), m:GetAttribute("FlipFace")
	local nowS = workspace:GetServerTimeNow()
	if not at or nowS < at or nowS > at + F.Time + 0.05 or typeof(to) ~= "Vector3" then
		if GR.flipping then GR.flipping = false; hum.PlatformStand = false end
		return false
	end
	local k = math.clamp((nowS - at) / F.Time, 0, 1)
	if GR.flipSeen ~= at then GR.flipSeen, GR.flipFrom, GR.flipK0 = at, root.Position, (k < 0.95) and k or 0 end
	GR.flipping = true
	hum.PlatformStand = true
	local u = math.clamp((k - GR.flipK0) / (1 - GR.flipK0), 0, 1)
	root.AssemblyLinearVelocity = Vector3.zero
	-- 10-30 11:2x 수평 = 박차고 빠르게(u(2−u) — 처음에 가장 빨리 멀어짐, 유저 "돌면서 멀어져야") · 높이 = 포물선
	root.CFrame = CFrame.lookAlong(GR.flipFrom:Lerp(to, u * (2 - u)) + Vector3.new(0, 4 * F.Height * u * (1 - u), 0),
		typeof(face) == "Vector3" and face or root.CFrame.LookVector)
	return true
end
Remotes.MechFX.OnClientEvent:Connect(function(kind, m, id, a, b)
	if kind == "grab" and m and m.Parent then
		-- 10-30 남의 기체 그랩 자세 = 서버 속성 GrabAt(MechFelsen grabPose) — 옛 GR.aimAt 왼팔 들기는 뺌
		-- 10-30 FELSEN 손등 작살(E2 메시): 팔의 작살 머리 "GrappleHead" 를 복제해 날림 · 팔의 것은 이 화면에서 숨김(LocalTransparencyModifier, 끝나면 되돌림)
		--   머리 화살촉 축 = 파트 속성 HeadAxis(파트 로컬, 적용 스크립트가 박음) → rfix 로 그 축을 진행 방향(−Z)에 맞춤. 머리가 없는 기체는 옛 회색 막대
		local head = m:FindFirstChild("GrappleHead", true)
		local hook, tip, rfix, a1
		if head and head:IsA("BasePart") then
			hook = head:Clone()
			for _, d in ipairs(hook:GetDescendants()) do if d:IsA("JointInstance") or d:IsA("Constraint") or d:IsA("Attachment") then d:Destroy() end end
			hook.Name = "GrabHook"; hook.Anchored = true; hook.CanCollide = false; hook.CanQuery = false; hook.CanTouch = false
			hook.Transparency = 0; hook.LocalTransparencyModifier = 0
			local ax = head:GetAttribute("HeadAxis") or Vector3.new(0, -1, 0)
			rfix = CFrame.fromRotationBetweenVectors(ax, Vector3.new(0, 0, -1))
			hook.CFrame = CFrame.lookAlong(a, b) * rfix
			a1 = Instance.new("Attachment"); a1.Position = -ax * (head:GetAttribute("HeadBack") or 1.6); a1.Parent = hook
			head.LocalTransparencyModifier = 1
		else
			head = nil
			hook = Instance.new("Part")
			hook.Name = "GrabHook"; hook.Anchored = true; hook.CanCollide = false; hook.CanQuery = false; hook.CanTouch = false
			hook.Size = Vector3.new(0.9, 0.9, 2.6); hook.Color = Color3.fromRGB(122, 126, 130); hook.Material = Enum.Material.Metal
			hook.CFrame = CFrame.lookAlong(a, b)
			tip = Instance.new("Part")
			tip.Name = "Tip"; tip.Anchored = true; tip.CanCollide = false; tip.CanQuery = false; tip.CanTouch = false
			tip.Size = Vector3.new(1.3, 1.3, 0.7); tip.Color = Color3.fromRGB(214, 110, 34); tip.Material = Enum.Material.SmoothPlastic
			tip.Parent = hook
			a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, 0, 1.3); a1.Parent = hook
		end
		local arm = m:FindFirstChild("LowerArmL")
		local a0 = arm and arm:FindFirstChild("GrappleMuzzle", true)
		if not a0 and arm then a0 = Instance.new("Attachment"); a0.Name = "GrabCableTmp"; a0.Parent = arm end
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Width0, beam.Width1 = head and 1.3 or 0.35, head and 1.3 or 0.35; beam.Segments = 1; beam.FaceCamera = true   -- 10-30 작살 메시 = 굵은 줄
		beam.Color = ColorSequence.new(head and Color3.fromRGB(96, 99, 106) or Color3.fromRGB(46, 48, 52)); beam.LightInfluence = head and 0.6 or 1   -- 10-30 19:23 유저 "줄이 너무 얇아서 잘 안 보임" → 1.3 · 밝은 금속색
		beam.Parent = hook
		-- 10-30 23:09 유저 "패치한 뒤로 끝 촉만 보이고 줄이 안 보여" → 작살 메시 기체는 Beam 대신 실제 파트 줄(굵기 0.9, 매 프레임 발사구 ↔ 작살 뒤끝으로 늘임)
		local rope = nil
		if head then
			beam.Enabled = false
			rope = Instance.new("Part")
			rope.Name = "GrabRope"; rope.Anchored = true; rope.CanCollide = false; rope.CanQuery = false; rope.CanTouch = false; rope.CastShadow = false
			rope.Material = Enum.Material.Metal; rope.Color = Color3.fromRGB(78, 80, 86); rope.Size = Vector3.new(0.9, 0.9, 0.2)
			rope.CFrame = CFrame.new(a)
			rope.Parent = hook
		end
		hook.Parent = workspace
		do   -- 10-31 쏠 때 발사구 번쩍 + 내 화면 살짝 흔들림
			local fl = fxPart(Color3.fromRGB(255, 190, 110), Vector3.new(1.6, 1.6, 1.6), CFrame.new(a), Enum.PartType.Ball)
			TweenService:Create(fl, TweenInfo.new(0.12), { Transparency = 1, Size = Vector3.new(6, 6, 6) }):Play()
			Debris:AddItem(fl, 0.14)
			if m == mech then shake = math.max(shake, 0.3) end
		end
		GR.hooks[id] = { m = m, from = a, dir = b, t0 = os.clock(), hook = hook, tip = tip, beam = beam, tmp = (a0 and a0.Name == "GrabCableTmp") and a0 or nil, rfix = rfix, head = head, rope = rope }
	elseif kind == "grabEnd" and m then
		local hk = GR.hooks[id]
		if hk then hk.endPos, hk.victim, hk.endT = a, b, os.clock() end
	end
end)
RunService.RenderStepped:Connect(function(dt)
	local nowS = workspace:GetServerTimeNow()
	if GR.lastMech ~= mech then GR.lastMech, GR.spinLocal, GR.pulling = mech, false, false; GR.F.reset(); GR.FE.reset() end   -- 타고 내릴 때 회전·끌림 상태 초기화
	-- 개틀링: 총열 회전 · 과열 색
	for _, tag in ipairs({ "Mech", "MechDisplay" }) do
		for _, m in ipairs(CollectionService:GetTagged(tag)) do
			local rifle = m:FindFirstChild("Rifle")
			local Gm = CFG.gun(m)
			if rifle and (Gm.Heat or Gm.HeatLook or Gm.SpinUp) then   -- 10-27 16:16 개틀링은 탄창 총이 됐지만 회전·달궈진 색(HeatLook)은 그대로
				local v = GR.gat[m]
				if not v or v.rifle ~= rifle then
					v = { rifle = rifle, spin = rifle:FindFirstChild("GatlingSpin", true), barrels = {}, ang = 0, speed = 0, lastH = -1,
						light = rifle:FindFirstChild("HeatLight", true), smoke = rifle:FindFirstChild("HeatSmoke", true) }
					if rifle:GetAttribute("HeatGlow") then table.insert(v.barrels, rifle) end
					for _, p in ipairs(rifle:GetDescendants()) do
						if p:IsA("BasePart") and p:GetAttribute("HeatGlow") then table.insert(v.barrels, p) end
					end
					GR.gat[m] = v
				end
				local spinning = (m == mech) and GR.spinLocal or (m:GetAttribute("GunSpinAt") ~= nil)
				v.speed += ((spinning and 1 or 0) - v.speed) * math.min(1, dt * (spinning and 2.5 or 1.2))
				if v.spin and v.speed > 0.002 then
					v.ang = (v.ang + v.speed * dt * math.pi * 2 * 2.5) % (math.pi * 2)   -- 최고 초당 2.5바퀴(화면 깜빡임 피함)
					v.spin.Transform = CFrame.Angles(0, 0, v.ang)
				end
				local h, locked = CFG.gunHeat(m, nowS)
				if math.abs(h - v.lastH) > 0.01 or locked ~= v.locked then
					v.lastH, v.locked = h, locked
					local col = GR.heatColor(h)
					for _, p in ipairs(v.barrels) do
						p.Color = col
						p.Material = (h >= 0.7) and Enum.Material.Neon or Enum.Material.SmoothPlastic
					end
					if v.light then v.light.Enabled = h > 0.5; v.light.Brightness = math.max(0, h - 0.5) * 6 end
					if v.smoke then v.smoke.Enabled = locked or h > 0.75 end
				end
			end
		end
	end
	-- 작살: 날아감 → 맞으면 상대 몸을 따라 끌려옴 / 빗나가면 0.25초에 감겨 돌아옴
	local now = os.clock()
	for id, hk in pairs(GR.hooks) do
		local dead = not hk.hook.Parent or not hk.m.Parent
		if not dead then
			local p
			if not hk.endT then
				local d = math.min(CFG.Grab.Range, CFG.Grab.Speed * (now - hk.t0))
				p = hk.from + hk.dir * d
			elseif hk.victim and hk.victim.Parent and now - hk.endT < CFG.Grab.PullTime + 0.15 then
				local vr = hk.victim:FindFirstChild("HumanoidRootPart")
				p = vr and vr.Position or hk.endPos
				local ep = now - hk.endT
				if ep < CFG.Grab.PullTime then   -- 10-31 감는 동안: 손등 발사구 스파크 · 줄 떨림
					if (hk.sparkT or 0) <= now and hk.beam.Attachment0 then hk.sparkT = now + 0.06; spark(hk.beam.Attachment0.WorldPosition, hk.dir) end
					if hk.rope then local wv = 0.9 + 0.18 * math.sin(now * 90); hk.rope.Size = Vector3.new(wv, wv, hk.rope.Size.Z) end
				elseif not hk.impact then   -- 10-31 도착 쾅: 번쩍 + 스파크 + 흔들림(맞은 쪽·당긴 쪽)
					hk.impact = true
					local fl = fxPart(Color3.fromRGB(255, 220, 160), Vector3.new(3, 3, 3), CFrame.new(p), Enum.PartType.Ball)
					TweenService:Create(fl, TweenInfo.new(0.16), { Transparency = 1, Size = Vector3.new(11, 11, 11) }):Play()
					Debris:AddItem(fl, 0.18)
					spark(p, -hk.dir); spark(p + Vector3.new(0, 2, 0), -hk.dir)
					SM.play("BodyHit", p)
					if hk.victim == mech then shake = math.max(shake, 0.9) elseif hk.m == mech then shake = math.max(shake, 0.55) end
				end
			else
				local e = (now - hk.endT - (hk.victim and CFG.Grab.PullTime + 0.15 or 0)) / 0.25
				local arm = hk.m:FindFirstChild("LowerArmL")
				local home = (hk.beam.Attachment0 and hk.beam.Attachment0.WorldPosition) or (arm and arm.Position) or hk.endPos
				hk.retFrom = hk.retFrom or hk.lastP or hk.endPos   -- 감기 시작 자리(맞았으면 끌려온 상대 자리)
				p = hk.retFrom:Lerp(home, math.clamp(e, 0, 1))
				dead = e >= 1
			end
			hk.lastP = p
			hk.hook.CFrame = CFrame.lookAlong(p, hk.dir) * (hk.rfix or CFrame.new())
			if hk.tip then hk.tip.CFrame = hk.hook.CFrame * CFrame.new(0, 0, -1.5) end
			if hk.rope and hk.beam.Attachment0 and hk.beam.Attachment1 then   -- 10-30 파트 줄: 발사구 ↔ 작살 뒤끝
				local q0, q1 = hk.beam.Attachment0.WorldPosition, hk.beam.Attachment1.WorldPosition
				local L = (q1 - q0).Magnitude
				hk.rope.Transparency = (L > 0.3) and 0 or 1
				if L > 0.05 then hk.rope.Size = Vector3.new(0.9, 0.9, L); hk.rope.CFrame = CFrame.lookAt((q0 + q1) / 2, q1) end
			end
		end
		if dead or now - hk.t0 > 6 then
			hk.hook:Destroy()
			if hk.tmp then hk.tmp:Destroy() end
			if hk.head and hk.head.Parent then hk.head.LocalTransparencyModifier = 0 end   -- 10-30 팔 작살 머리 다시 보임
			GR.hooks[id] = nil
		end
	end
end)

-- 수평 속도 제약(이름별 하나): 지속 부스트 "BoostHold" · 공중 관성 "AirCarry". vel = nil 이면 없앤다.
-- 대시와 같은 방식(Plane: 수평만 잡고 높이는 휴머노이드·중력에 맡김 — 위아래로 싸우면 떨림)
local function setBoostLV(root, name, vel)
	local v = root:FindFirstChild(name)
	if not vel then
		if v then v:Destroy() end
		return
	end
	if not v then
		local att = root:FindFirstChild("BoostAtt")
		if not att then att = Instance.new("Attachment"); att.Name = "BoostAtt"; att.Parent = root end
		v = Instance.new("LinearVelocity")
		v.Name = name; v.Attachment0 = att; v.MaxForce = math.huge
		v.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		v.PrimaryTangentAxis = Vector3.xAxis; v.SecondaryTangentAxis = Vector3.zAxis
		v.RelativeTo = Enum.ActuatorRelativeTo.World
		v.Parent = root
	end
	MP.setWant(v, Vector2.new(vel.X, vel.Z))   -- 원하는 속도는 속성 Want 에도(닿아 있으면 MP.clipPush 가 그쪽 성분을 지움)
end

-- 상승(10-25 18:24 공중 프로토): 위아래만 잡는 LinearVelocity(Line, Y). 힘 = 질량 × (중력 + accel) 까지 → 수평 부스트(Plane)와 같이 걸려 대각선 상승
local function setClimbLV(root, vy, accel)
	local v = root:FindFirstChild("ClimbLV")
	if not vy then
		if v then v:Destroy() end
		return
	end
	if not v then
		local att = root:FindFirstChild("BoostAtt")
		if not att then att = Instance.new("Attachment"); att.Name = "BoostAtt"; att.Parent = root end
		v = Instance.new("LinearVelocity")
		v.Name = "ClimbLV"; v.Attachment0 = att
		v.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		v.LineDirection = Vector3.yAxis
		v.RelativeTo = Enum.ActuatorRelativeTo.World
		v.Parent = root
	end
	v.MaxForce = root.AssemblyMass * (workspace.Gravity + (accel or 120))
	v.LineVelocity = vy
end
local function tryBoost()
	if not mech then return end
	if GR.anchored(mech) then return end   -- 10-30 앵커 중(꿇기·일어나기 포함) 대시 못 함(서버도 거절)
	local now = os.clock()
	local root = mech:FindFirstChild("HumanoidRootPart")
	local hum = mech:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return end
	local inAir = hum.FloorMaterial == Enum.Material.Air
	-- 공중 대시(톡)는 점프 한 번에 1회. 이미 썼으면 대시 없이, 누르고 있으면 카메라 단계가 지속 추진만 이어 준다
	if inAir and airDashUsed then return end
	if now - lastBoost < CFG.BoostCooldown then return end
	if (mech:GetAttribute("Energy") or 0) < CFG.BoostCost then return end
	-- 회피 우선: 점프 웅크리는 중이면 점프 취소하고 대시
	if jumpWindupAt then jumpWindupAt, windStartLocal, jumpBoostVel = nil, nil, nil end
	-- 지속 추진·공중 관성 제약과 겹치지 않게 대시 동안은 걷어 낸다(대시가 끝나면 카메라 단계가 다시 판단)
	setBoostLV(root, "BoostHold", nil); setBoostLV(root, "AirCarry", nil)
	lastBoost = now
	local dir = hum.MoveDirection
	if dir.Magnitude < 0.1 then
		local lv = root.CFrame.LookVector
		dir = Vector3.new(lv.X, 0, lv.Z)
	end
	dir = dir.Unit
	local att = root:FindFirstChild("BoostAtt")
	if not att then att = Instance.new("Attachment"); att.Name = "BoostAtt"; att.Parent = root end
	-- 수평 속도만 잡고 높이는 휴머노이드에 맡긴다(위아래로 싸우면 떨림)
	local v = Instance.new("LinearVelocity")
	v.Attachment0 = att
	v.MaxForce = math.huge
	v.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	v.PrimaryTangentAxis = Vector3.xAxis
	v.SecondaryTangentAxis = Vector3.zAxis
	v.RelativeTo = Enum.ActuatorRelativeTo.World
	v.PlaneVelocity = Vector2.new(dir.X, dir.Z) * (CFG.BoostSpeed / CFG.slowMul(mech))   -- 10-30 마비 덫: 대시 ÷1.5
	v.Parent = root
	Debris:AddItem(v, CFG.BoostTime)
	if inAir then
		airDashUsed = true   -- 살짝 띄워 주는 것도 이 1회만
		root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, math.max(root.AssemblyLinearVelocity.Y, CFG.BoostLift), root.AssemblyLinearVelocity.Z)
	end
	dashUntil, dashVel = now + CFG.BoostTime, dir * (CFG.BoostSpeed / CFG.slowMul(mech))   -- 대시가 공중에서 끝나면 이 속도가 관성으로 이어짐
	boostLocal[mech] = now + CFG.BoostTime
	local st = animState[mech]
	if st then st.boostDir = root.CFrame:VectorToObjectSpace(dir) end
	Remotes.MechBoost:FireServer()
	shake = math.max(shake, CFG.BoostShake or 0.4)
	fovKickAt = os.clock()   -- 시야각 +9 에서 0.5초 동안 풀림(카메라 단계가 그린다 — 줌과 같은 곳)
end

-- ================= 근접 (R 빔사벨) =================
-- 누르면 화면 정면의 가까운 적 쪽으로 짧게 내딛고(LinearVelocity) 왼손으로 벤다. 판정은 서버(MechServer 근접)
local MELEE_SPEC = {
	-- lunge = 화면 정면으로 내딛는 고정 거리(2026-10-25: 적 쪽 거리 보정 삭제)
	saber = { time = CFG.SaberTime, cooldown = CFG.SaberCooldown, lunge = CFG.SaberLunge, lungeTime = CFG.LungeTime },
	punch = { time = CFG.PunchTime, cooldown = CFG.PunchCooldown, lunge = CFG.PunchLunge, lungeTime = CFG.PunchLungeTime },
	kick = { time = CFG.Kick.Time, cooldown = CFG.Kick.Cooldown, lunge = CFG.Kick.Lunge, lungeTime = CFG.Kick.LungeTime },   -- 10-30 SKADI 앞차기(R, 속성 Melee = "Kick")
	-- 빔사벨 3연격: strike = 판정 시각(이 뒤에 누르면 다음 타 예약), chain = 다음 타가 이어지는 시각
	slash1 = { time = CFG.SlashTime, cooldown = CFG.SlashCooldown, strike = CFG.SlashStrike, chain = CFG.SlashChain1, lunge = CFG.SlashLunge, lungeTime = CFG.SlashLungeTime },
	slash2 = { time = CFG.Slash2Time, cooldown = CFG.SlashCooldown, strike = CFG.Slash2Strike, chain = CFG.SlashChain2, lunge = CFG.Slash2Lunge, lungeTime = CFG.Slash2LungeTime },
	slash3 = { time = CFG.Slash3Time, cooldown = CFG.SlashCooldown, strike = CFG.Slash3Strike, chain = 99, lunge = CFG.Slash3Lunge, lungeTime = CFG.Slash3LungeTime },
}
local SLASH_STEP = { slash1 = 1, slash2 = 2, slash3 = 3 }
-- 빔사벨 휘두르는 속도(2026-10-25): 동작표(자세 시각·판정·연결 시각·SWING_AT·잔상)는 그대로 두고,
-- 흐른 시간을 CFG.SaberSlow 로 나눠 "동작표 시각"으로 바꿔 쓴다 = 전부 같은 비율로 느려진다. 주먹은 그대로
-- 10-27 기체별 근접 수치(CFG.Types[MechType].Melee — FELSEN 열선 도끼 두 손 3연격): 있으면 그 기체 3연격만 그 표 · 그 slow(도끼 = 1, 실제 초).
--   없는 기체(AELLO·프로토·적)와 R 뽑아 베기('saber')·주먹은 위 MELEE_SPEC · 공통 SaberSlow 그대로. 서버 meleeSpecFor 와 같은 규칙
local meleeSpecCache = {}
local function meleeSpec(m, kind)
	local base = MELEE_SPEC[kind]
	local mo = CFG.meleeOver(m)
	local o = mo and mo[kind]
	if not (base and o) then return base end
	local key = (m:GetAttribute("MechType") or "?") .. "/" .. kind
	local c = meleeSpecCache[key]
	if c then return c end
	c = {}
	for k, v in pairs(base) do c[k] = v end
	for k, v in pairs(o) do c[k] = v end
	meleeSpecCache[key] = c
	return c
end
local function meleeScale(m, kind)
	if SLASH_STEP[kind] then
		local mo = CFG.meleeOver(m)
		if mo and mo[kind] then return mo.slow or 1 end
	end
	return (kind == "saber" or SLASH_STEP[kind] ~= nil) and (CFG.SaberSlow or 1) or 1
end
-- 10-27 23:2x 맞았을 때 멈칫(히트스톱, 유저 "육중하게"): 휘두르는 쪽 동작을 그 휘두름에서 한 번 hitStop 초 멈춤(Melee 표에 hitStop 이 있는 기체만 — 도끼).
--   meleeHold[m] = { key = 그 휘두름 표식(내 기체 meleeLocal.t0 / 남 기체 MeleeAt), at, dur } → 동작 시각에서 멈춘 만큼 뺌(그동안 자세가 서 있음).
--   판정·연결은 서버 그대로(연결 허용 +0.45 안) — 보이는 동작만 늦어짐
local meleeHold = {}
local function holdOff(m, key)
	local h = meleeHold[m]
	if not h or h.key ~= key then return 0 end
	return math.clamp(os.clock() - h.at, 0, h.dur)
end
local function meleeElapsed(m)
	-- 내 기체는 누른 시각(즉시 반응), 다른 기체는 서버가 남긴 속성 MeleeAt(서버 시각)으로 계산. 돌려주는 값은 동작표 시각
	if m == mech then
		local ml = meleeLocal[m]
		if not ml then return nil end
		local e = (os.clock() - ml.t0 - holdOff(m, ml.t0)) / (meleeScale(m, ml.kind) * (ml.slow or 1))   -- 10-30 마비 덫: 누를 때 배율
		if e < meleeSpec(m, ml.kind).time then return e, ml.kind end
		meleeLocal[m] = nil
		return nil
	end
	local at, kind = m:GetAttribute("MeleeAt"), m:GetAttribute("MeleeKind")
	local spec = kind and meleeSpec(m, kind)
	if at and spec then
		local e = (workspace:GetServerTimeNow() - at - holdOff(m, at)) / (meleeScale(m, kind) * (m:GetAttribute("MeleeSlow") or 1))
		if e >= 0 and e < spec.time then return e, kind end
	end
	return nil
end

-- ================= 무장 교체 (1 라이플 / 2 빔사벨) =================
local function weaponState(m)
	-- 내 기체는 누른 시각(즉시 반응), 다른 기체는 서버 속성 Weapon / WeaponAt(서버 시각)
	if m == mech then return weapon, os.clock() - weaponAt end
	local at = m:GetAttribute("WeaponAt")
	return m:GetAttribute("Weapon") or "rifle", at and (workspace:GetServerTimeNow() - at) or 99
end
local function updateWeaponHUD()
	if not hud or not hud.wl then return end
	local on, off = '<font color="#FFFFFF"><b>%s</b></font>', '<font color="#8A93A0">%s</font>'
	-- 라이플 옆 남은 발: 장전 중이면 "장전", 1/5 이하면 주황(조작 가능 = 주황 원칙과 같은 색)
	local ammoTxt
	local Gh = CFG.gun(mech)
	if Gh.NoAmmo then
		ammoTxt = '<font color="#5AFFA0">∞</font>'   -- 10-30 SKADI 궁극기 사격 창: 탄창 무한
	elseif Gh.Heat then
		-- 10-27 과열 총: 과열 % (70 넘으면 주황), 강제 냉각 중이면 주황 "과열 n.n"(남은 초)
		local nowS = workspace:GetServerTimeNow()
		local h, locked = CFG.gunHeat(mech, nowS)
		if locked then ammoTxt = ('<font color="#FF7818">과열 %.1f</font>'):format(math.max(0, (mech:GetAttribute("GunLockUntil") or nowS) - nowS))
		elseif h >= 0.7 then ammoTxt = ('<font color="#FF7818">열 %d%%</font>'):format(math.floor(h * 100 + 0.5))
		else ammoTxt = ("열 %d%%"):format(math.floor(h * 100 + 0.5)) end
	elseif myReloading(os.clock()) then ammoTxt = "장전"
	elseif ammoLocal <= math.floor(Gh.MagSize / 5) then ammoTxt = ('<font color="#FF7818">%d</font>'):format(ammoLocal)
	else ammoTxt = tostring(ammoLocal) end
	local meleeName = (mech and mech:GetAttribute("MeleeLabel")) or "빔사벨"   -- 10-27 FELSEN = "열선 도끼"(템플릿 속성)
	-- 10-27 HUD 재배치: 조준점 오른쪽 세로 목록(줄바꿈 SEP). 옛 = 화면 아래 한 줄(빈칸 6)
	local SEP = string.char(10)
	local txt = ((weapon == "rifle") and on or off):format("1 " .. Gh.Label .. " " .. ammoTxt) .. SEP .. ((weapon == "saber") and on or off):format("2 " .. meleeName)
	-- 10-30 SKADI(속성 Melee = "Kick"): 2번 칸 대신 앞차기 쿨 — 준비되면 흰색 "R Kick", 쿨이면 회색 "R Kick n.n"(새 글자는 영어 — 10-29 결정)
	if mech and mech:GetAttribute("Melee") == "Kick" then
		local left = (lastMeleeKind == "kick") and (CFG.Kick.Cooldown - (os.clock() - lastMelee)) or 0
		txt = ((weapon == "rifle") and on or off):format("1 " .. Gh.Label .. " " .. ammoTxt) .. SEP
			.. ((left <= 0) and '<font color="#FFFFFF">R Kick</font>' or ('<font color="#8A93A0">R Kick %.1f</font>'):format(left))
	end
	-- 10-27 시그니처: 작살 그랩(C) — 준비되면 흰색, 쿨이면 회색 "C 그랩 n.n"
	if mech and mech:GetAttribute("Signature") == "Grab" then
		local left = (mech:GetAttribute("GrabReadyAt") or 0) - workspace:GetServerTimeNow()
		txt ..= SEP .. ((left <= 0) and '<font color="#FFFFFF">C 그랩</font>' or ('<font color="#8A93A0">C 그랩 %.1f</font>'):format(left))
	end
	-- 10-30 시그니처: 앵커 자세(C) — 준비 흰색 "C Anchor" · 꿇는 중·꿇음 초록 "C Anchor ON" · 일어나는 중·쿨 회색 "C Anchor n.n"
	if mech and mech:GetAttribute("Signature") == "Anchor" then
		local nowS = workspace:GetServerTimeNow()
		local ph = CFG.anchorPhase(mech, nowS)
		local left = (mech:GetAttribute("AnchorReadyAt") or 0) - nowS
		if ph == "kneel" or ph == "on" then txt ..= SEP .. '<font color="#5AFFA0">C Anchor ON</font>'
		elseif left > 0 then txt ..= SEP .. ('<font color="#8A93A0">C Anchor %.1f</font>'):format(left)
		else txt ..= SEP .. '<font color="#FFFFFF">C Anchor</font>' end
	end
	-- 미사일(일회용): 남아 있으면 흰색 "G 미사일 6", 쓰면 회색 "—"
	-- 10-30 FALCO 시그니처: 라이더킥(C) — 준비·공중 흰색 "C Rider Kick" · 땅 회색 "C Rider Kick (air)" · 쿨 회색 "C Rider Kick n.n"
	if mech and mech:GetAttribute("Signature") == "RiderKick" then
		local left = (mech:GetAttribute("RKReadyAt") or 0) - workspace:GetServerTimeNow()
		if left > 0 then txt ..= SEP .. ('<font color="#8A93A0">C Rider Kick %.1f</font>'):format(left)
		else
			local hm = mech:FindFirstChildOfClass("Humanoid")
			local inAir = hm ~= nil and hm.FloorMaterial == Enum.Material.Air
			txt ..= SEP .. (inAir and '<font color="#FFFFFF">C Rider Kick</font>' or '<font color="#8A93A0">C Rider Kick (air)</font>')
		end
	end
	-- 10-30 FALCO 마비 덫에 걸림: 주황 "SLOWED"
	if mech and CFG.slowMul(mech) > 1 then txt ..= SEP .. '<font color="#FFB43C">SLOWED</font>' end
	if mech ~= nil and mech:GetAttribute("SubWeapon") == "Mine" then
		-- 10-30 SKADI 센서 지뢰: 남은 개수 흰색 "G Mine 2" · 다 쓰면 회색 "G Mine 12.3"(두 개가 한꺼번에 참)
		local now = workspace:GetServerTimeNow()
		local n = CFG.mineAmmo(mech, now)
		if n > 0 then
			txt ..= SEP .. ('<font color="#FFFFFF">G Mine %d</font>'):format(n)
		else
			txt ..= SEP .. ('<font color="#8A93A0">G Mine %.1f</font>'):format(math.max(0, (mech:GetAttribute("MineReadyAt") or now) - now))
		end
	elseif mech ~= nil and mech:GetAttribute("SubWeapon") == "Grenade" then
		-- 손목 미사일 런처(10-26): 남은 발(흰색) / 다 쓰면 회색 "장전 n.n"(두 발이 한꺼번에 참)
		local now = workspace:GetServerTimeNow()
		local n = CFG.grenadeAmmo(mech, now)
		if n > 0 then
			txt ..= SEP .. ('<font color="#FFFFFF">G 미사일 %d</font>'):format(n)
		else
			txt ..= SEP .. ('<font color="#8A93A0">G 미사일 장전 %.1f</font>'):format(math.max(0, (mech:GetAttribute("GrenadeReadyAt") or now) - now))
		end
	else
		local pods = mech ~= nil and mech:GetAttribute("MissilePods") == true
		txt ..= SEP .. (pods and '<font color="#FFFFFF">G 미사일 6</font>' or '<font color="#8A93A0">G 미사일 —</font>')
	end
	if hud.wl.Text ~= txt then hud.wl.Text = txt end
end
local function requestReload()   -- E, 또는 탄창이 비었을 때. 서버도 비면 알아서 시작하므로 겹쳐 보내도 괜찮다
	if not mech then return end
	if CFG.gun(mech).Heat then return end   -- 10-27 과열 총(개틀링)은 장전 없음
	if CFG.ultPhase(mech) then return end   -- 10-30 궁극기(탄창 무한) 동안 장전 안 함 — 끝나면 서버가 탄창을 채움
	local now = os.clock()
	if ammoLocal >= CFG.gun(mech).MagSize or myReloading(now) then return end
	GR.reloadSlow = CFG.slowMul(mech)   -- 10-30 마비 덫(서버 ReloadSlow 와 같은 배율)
	reloadLocalUntil = now + CFG.gun(mech).ReloadTime * GR.reloadSlow
	Remotes.MechReload:FireServer()
	updateWeaponHUD()
end
local function setWeapon(w)
	if not mech or w == weapon or meleeElapsed(mech) then return end
	if w == "saber" and mech:GetAttribute("Melee") == "Kick" then return end   -- 10-30 SKADI 는 빔사벨 없음(서버도 거절)
	local now = os.clock()
	if now - weaponAt < 0.25 then return end
	weapon, weaponAt = w, now
	reloadLocalUntil = 0   -- 무장을 바꾸면 장전 취소(서버도 ReloadUntil 을 지움)
	Remotes.MechWeapon:FireServer(w)
	updateWeaponHUD()
end
GR.setWeapon = setWeapon   -- 10-30 FELSEN 궁극기(GR.ult — 이 함수보다 위에 있음)가 도끼를 들게

-- 근접 내딛기 (2026-10-25 너프): 화면 정면으로 고정 거리만. 예전 meleeTarget(정면 45° · 50 안의 적에게
-- 방향을 틀고 최대 30까지 끌려가던 보정)은 삭제. 정면 통로(좌우 6) 안에 기체가 있으면 몸이 겹치기 전에 멈추기만 한다
local function lungeTravel(root, dir, want)
	local travel = want
	for _, m in ipairs(CollectionService:GetTagged("Mech")) do
		if m ~= mech and m:IsDescendantOf(workspace) then
			local r, h = m:FindFirstChild("HumanoidRootPart"), m:FindFirstChildOfClass("Humanoid")
			if r and h and h.Health > 0 then
				local d = r.Position - root.Position
				local ahead = d.X * dir.X + d.Z * dir.Z
				local side = math.abs(d.X * dir.Z - d.Z * dir.X)
				if ahead > 0 and side < 6 and math.abs(d.Y) < 20 then
					travel = math.min(travel, math.max(0, ahead - CFG.LungeBodyGap))
				end
			end
		end
	end
	return travel
end

local function tryMelee(kind, chained)   -- chained = 3연격 다음 타(쿨다운 대신 연계 시각으로 이미 판단함)
	local spec = mech and meleeSpec(mech, kind)
	if not mech or not spec then return end
	if GR.anchored(mech) then return end   -- 10-30 앵커 중엔 근접 못 함(다리가 박혀 있음 — 서버도 거절)
	local now = os.clock()
	if now - weaponAt < ((weapon == "saber") and CFG.EquipTime or CFG.UnequipTime) then return end   -- 무기 바꾸는 동작 중엔 못 벤다
	local cd = spec.cooldown
	if lastMeleeKind == "slash3" then cd = math.max(cd, (CFG.meleeOver(mech) or {}).slash3Cooldown or CFG.Slash3Cooldown) end   -- 3타 찌르기 뒤 빈틈(10-27 기체별)
	if not chained and now - lastMelee < cd * GR.meleeSlowLast then return end   -- 10-30 마비 덫: 앞 근접이 느려졌으면 쿨도(서버와 같음)
	local root, hum = mech:FindFirstChild("HumanoidRootPart"), mech:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end
	lastMelee, lastMeleeKind = now, kind
	local slM = CFG.slowMul(mech)   -- 10-30 마비 덫: 이 근접은 끝까지 이 배율(서버 속성 MeleeSlow 와 같음)
	GR.meleeSlowLast = slM
	local camLook = workspace.CurrentCamera.CFrame.LookVector
	local dir = Vector3.new(camLook.X, 0, camLook.Z)
	dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(0, 0, -1)
	local travel = lungeTravel(root, dir, spec.lunge)
	-- 부스트 중이면 끊고 근접으로 이어 간다(속도 제약이 둘이면 서로 싸운다)
	for _, c in ipairs(root:GetChildren()) do if c:IsA("LinearVelocity") then c:Destroy() end end
	boostLocal[mech] = 0
	if travel > 0.5 then
		local att = root:FindFirstChild("BoostAtt")
		if not att then att = Instance.new("Attachment"); att.Name = "BoostAtt"; att.Parent = root end
		local v = Instance.new("LinearVelocity")
		v.Name = "MeleeLunge"; v.Attachment0 = att; v.MaxForce = math.huge
		v.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		v.PrimaryTangentAxis = Vector3.xAxis; v.SecondaryTangentAxis = Vector3.zAxis
		v.RelativeTo = Enum.ActuatorRelativeTo.World
		local lt = spec.lungeTime * meleeScale(mech, kind) * slM   -- 휘두름이 느려진 만큼 내딛기도 같이(거리는 그대로)
		v.PlaneVelocity = Vector2.new(dir.X, dir.Z) * (travel / lt)
		v.Parent = root
		Debris:AddItem(v, lt)
	end
	meleeLocal[mech] = { kind = kind, t0 = now, yaw = math.atan2(-dir.X, -dir.Z), slow = slM }
	moveVec = Vector3.zero   -- 관성 속도가 내딛기 뒤에 이어지지 않게
	Remotes.MechMelee:FireServer(kind, dir)
end

-- 서버가 맞았다고 알려 줌: 각 화면의 상대 위치 기준으로 몸통의 때린 쪽 표면에 불꽃, 맞은 기체는 움찔
-- 빔사벨 3연격: 판정 뒤에 다시 누르면(누르고 있으면) 다음 타를 예약했다가 이어지는 시각(chain)에 바로 시작.
-- chain 을 조금(0.15초) 넘겨 눌러도 이어 준다. 그보다 늦으면 겨눔으로 돌아가고, 쿨다운 뒤 1타부터
local slashQueued = false
local function trySlash()
	if not mech or weapon ~= "saber" then return end
	local ml = meleeLocal[mech]
	local step = ml and SLASH_STEP[ml.kind]
	if step then
		local spec = meleeSpec(mech, ml.kind)
		local e = (os.clock() - ml.t0 - holdOff(mech, ml.t0)) / (meleeScale(mech, ml.kind) * (ml.slow or 1))   -- 동작표 시각(10-27 멈칫만큼 뺌)
		if e < spec.time then
			if step < 3 and e >= spec.strike then
				if e < spec.chain then
					slashQueued = true
				elseif e <= spec.chain + 0.15 then
					tryMelee("slash" .. (step + 1), true)
				end
			end
			return
		end
	end
	tryMelee("slash1")
end
local function updateSlashQueue()
	if not slashQueued or not mech then return end
	local ml = meleeLocal[mech]
	local step = ml and SLASH_STEP[ml.kind]
	if not step or step >= 3 then slashQueued = false; return end
	if (os.clock() - ml.t0 - holdOff(mech, ml.t0)) / (meleeScale(mech, ml.kind) * (ml.slow or 1)) >= meleeSpec(mech, ml.kind).chain then
		slashQueued = false
		tryMelee("slash" .. (step + 1), true)
	end
end

local function meleeHit(attacker, target, kind)
	local tr = target:FindFirstChild("HumanoidRootPart")
	if not tr then return end
	local ar = attacker and attacker:FindFirstChild("HumanoidRootPart")
	local d = ar and (tr.Position - ar.Position) or -tr.CFrame.LookVector
	d = Vector3.new(d.X, 0, d.Z)
	d = d.Magnitude > 0.01 and d.Unit or Vector3.zAxis
	flinch[target] = { t0 = os.clock(), dir = d }
	local body = target:FindFirstChild("Torso") or tr
	local pos = body.Position - d * (body.Size.Z / 2) + Vector3.new(0, 1.5, 0)   -- 몸통 앞면(10-26: 기체 크기별 — 프로토 Torso 깊이 5 → 예전 값 2.5 그대로)
	spark(pos, -d); spark(pos + Vector3.new(0, 1.2, 0), -d)
	if kind == "saber" or SLASH_STEP[kind] ~= nil then SM.play("SaberHit", pos) end   -- 빔사벨 적중
	local col = (kind == "saber" or SLASH_STEP[kind] ~= nil) and (CFG.stat(attacker, "SaberColor") or Color3.fromRGB(90, 230, 255)) or Color3.fromRGB(255, 200, 120)   -- 10-26 기체별 사벨 색(AELLO 노랑)
	local flash = fxPart(col, Vector3.new(1.5, 1.5, 1.5), CFrame.new(pos), Enum.PartType.Ball)
	TweenService:Create(flash, TweenInfo.new(0.12), { Transparency = 1, Size = Vector3.new(4, 4, 4) }):Play()
	Debris:AddItem(flash, 0.14)
	SM.play("BodyHit", body)
	-- 10-27 23:2x 도끼: 맞으면 휘두른 쪽 멈칫(그 휘두름에 한 번) + 흔들림 크게(Melee 표 hitStop · hitShake). 없는 기체·종류는 예전 그대로
	local mo = attacker and CFG.meleeOver(attacker)
	local o = mo and mo[kind]
	if o and o.hitStop then
		local key = (attacker == mech) and (meleeLocal[attacker] and meleeLocal[attacker].t0) or attacker:GetAttribute("MeleeAt")
		local h = meleeHold[attacker]
		if key and not (h and h.key == key) then meleeHold[attacker] = { key = key, at = os.clock(), dur = o.hitStop } end
	end
	if target == mech then shake = math.max(shake, math.max(0.6, (o and o.hitShake) or 0)) end
	if attacker == mech then shake = math.max(shake, (o and o.hitShake) or 0.3) end
end

UIS.InputBegan:Connect(function(input, gp)
	if not mech or UIS:GetFocusedTextBox() then return end
	if launchLock then return end   -- 캐터펄트 사출 연출 중(10-25): 사격·부스트·무장·하차 입력 무시(서버도 하차를 막음)
	if GR.locked(mech) then   -- 10-27 작살 그랩에 끌려오는 중·경직 중(서버도 다 거절)
		-- 10-31 그랩(내 잠금) 중 누른 공격은 기억 → 풀리는 순간 이어짐: 좌클릭은 누르고 있음(firing) · R 은 GR.meleeBuf
		if input.UserInputType == Enum.UserInputType.MouseButton1 then firing = true
		elseif input.KeyCode == Enum.KeyCode.R and not gp then GR.meleeBuf = os.clock() end
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		firing = true
		if weapon == "rifle" then   -- 주무기 상태: 다음 발까지 SHOT_BUFFER 안이면 예약(짧게 톡 눌러도 팔을 든 뒤 나감)
			local rem = CFG.gun(mech).FireInterval * CFG.slowMul(mech) - (os.clock() - lastShot)
			if rem <= SHOT_BUFFER then shotQueuedAt = os.clock() end
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		aimHeld = true
	elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.Q then
		boostHeld = true   -- 누르고 있으면 카메라 단계가 대시 뒤 지속 추진을 이어 준다
		tryBoost()
	elseif input.KeyCode == Enum.KeyCode.F and not gp then
		Remotes.MechExit:FireServer()
	elseif input.KeyCode == CFG.Grab.Key and not gp then
		-- 시그니처 키 C: 10-27 작살 그랩(Signature "Grab", 왼손목) · 10-30 앵커 자세(Signature "Anchor", 켬/끔)
		local sig = mech:GetAttribute("Signature")
		if sig == "Anchor" then GR.anchor() elseif sig == "RiderKick" then GR.F.riderKick() else GR.grab() end   -- 10-30 FALCO 라이더킥
	elseif input.KeyCode == CFG.Ult.Key and not gp then
		GR.ult()   -- 10-30 궁극기(X): 공용 게이지가 차면 그 기체의 궁극기(속성 Ultimate)
	elseif input.KeyCode == Enum.KeyCode.R and not gp then
		if mech:GetAttribute("Melee") == "Kick" then tryMelee("kick")     -- 10-30 SKADI: 근접 = 앞차기(총을 든 채 바로)
		elseif weapon == "saber" then trySlash() else tryMelee("saber") end     -- 빔사벨 상태에선 그냥 베기
	elseif input.KeyCode == Enum.KeyCode.V and not gp then
		if weapon == "rifle" then tryMelee("punch") end         -- 왼손이 칼을 쥐고 있으면 주먹 없음
	elseif (input.KeyCode == Enum.KeyCode.One or input.KeyCode == Enum.KeyCode.KeypadOne) and not gp then
		setWeapon("rifle")
	elseif (input.KeyCode == Enum.KeyCode.Two or input.KeyCode == Enum.KeyCode.KeypadTwo) and not gp then
		setWeapon("saber")
	elseif input.KeyCode == Enum.KeyCode.E and not gp then
		requestReload()
	elseif input.KeyCode == Enum.KeyCode.G and not gp then
		-- 보조(속성 SubWeapon): 10-30 "Mine" 센서 지뢰 · "Grenade" 손목 그레네이드 · 없으면 미사일 일괄 사출(출격마다 한 번)
		if not (GR.mine() or GR.fire()) then fireMissiles() end
elseif (input.KeyCode == Enum.KeyCode.LeftBracket or input.KeyCode == Enum.KeyCode.RightBracket or input.KeyCode == Enum.KeyCode.H) and not gp then
		-- 14:22 모니터 테 맞춤(유저 "축소·확장·아예 닫기"): [ 작게 · ] 크게(테가 꺼져 있으면 다시 켬) · H 테 끄기/켜기(HP·BOOST·무장·조준선은 남음)
		--   플레이어 속성 HudFrame(1~4) · HudFrameOff 에 기억(이 세션만) → HUD 를 새로 만듦(출격 연출로 숨겨 둔 상태는 그대로)
		if input.KeyCode == Enum.KeyCode.H then
			player:SetAttribute("HudFrameOff", not player:GetAttribute("HudFrameOff"))
		else
			local d = (input.KeyCode == Enum.KeyCode.RightBracket) and 1 or -1
			player:SetAttribute("HudFrame", math.clamp((player:GetAttribute("HudFrame") or 4) + d, 1, 4))
			player:SetAttribute("HudFrameOff", false)
		end
		if hud then local en = hud.gui.Enabled; hud.gui:Destroy(); hud = makeHUD(); hud.gui.Enabled = en end
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.Q then
		boostHeld = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.Q)   -- 둘 다 떼야 멈춤
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then firing = false end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then aimHeld = false end
end)

-- ================= 탄 퍼짐 (2026-10-25) =================
-- 지금 쏘면 퍼질 원뿔 반각(도). 비조준 = 기본 + 연사 블룸 + 이동·공중·부스트, 줌하면 전체 × ZoomSpreadMul (줌 들어가는 정도만큼)
-- (위에서 선언된 bloom·zoomCam·boostLocal·wasAirMine·airSince 를 쓰므로 여기, 카메라 단계 바로 위에 둔다)
local function currentSpread(root, hum, now)
	local s = CFG.SpreadBase + bloom + (CFG.gun(mech).Spread or 0)   -- 10-27 총마다 기본 퍼짐(개틀링 1.5°)
	local v = root.AssemblyLinearVelocity
	s += CFG.SpreadMove * math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / CFG.WalkSpeed, 0, 1)
	if hum.FloorMaterial == Enum.Material.Air and wasAirMine and now - airSince > 0.1 then s += CFG.SpreadAir end
	if (boostLocal[mech] or 0) > now then s += CFG.SpreadBoost end
	local zc = zoomCam * zoomCam * (3 - 2 * zoomCam)
	return s * (1 + (CFG.ZoomSpreadMul - 1) * zc)
end

-- ================= 출격 사출 — 지하 땅굴 → 지상 격납고 문 (2026-10-25 16:24) =================
-- 구조물 = Range.UndergroundLaunch: 바닥 경로 F1(땅굴 출발점) → F2(경사 아래) → F3(경사 위 = 격납고 바닥) → F4(문 밖 놓는 곳)
-- 시각표(가속 시작 = 0, 서버 시각 LaunchAt): 탐 −2.0 → 패널 CLEAR −1.6/−1.2/−0.8 → LAUNCH −0.4 → 0~1.0 가속(0→120, 땅굴 평지 60)
-- → 120 으로 경사 오르고 격납고 지나 철문 밖(약 2.0초) → 놓아 줌: 땅을 긁으며 0.9초 미끄러져 섬 → 조작 돌려줌 → 0.45초 카메라 섞음
-- 주행 중엔 기체를 경로에 직접 놓는다(PlatformStand, 몸은 바닥 기울기를 따름) — 빠른 속도로 경사 꺾임을 물리에 맡기면 튀거나 걸림
-- 컷: A 준비(땅굴 출발점 앞 낮은 곳) / B 주행(경로를 따라 뒤 아래, 경사에선 같이 기울어 오름) / C 경사 위를 지나면 문 밖 오른쪽 고정
local function lsmooth(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end   -- (애니 쪽 sstep 은 이 아래에서 정의돼 여기선 못 씀)
local PANEL_CLEAR = { -1.6, -1.2, -0.8 }   -- SYSTEM · THROTTLE · CATAPULT 가 CLEAR 되는 시각
local PANEL_GO = -0.4                      -- 셋 다 LAUNCH
local function makeLaunchPanel()   -- 영상의 LAUNCH CONTROL: 왼쪽 ABORT(빨강) → LAUNCH(하늘색), 오른쪽 항목 이름(노랑) → CLEAR(흰색)
	local g = Instance.new("ScreenGui")
	g.Name = "LaunchPanel"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 6
	local fr = Instance.new("Frame")
	fr.AnchorPoint = Vector2.new(1, 0.5); fr.Size = UDim2.fromOffset(380, 280); fr.Rotation = -6
	fr.BackgroundColor3 = Color3.fromRGB(12, 14, 18); fr.BackgroundTransparency = 0.15; fr.BorderSizePixel = 0
	fr.Parent = g
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(70, 80, 95); st.Thickness = 2; st.Parent = fr
	local function label(parent, text, pos, size, color, font, xa)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1; t.Position = pos; t.Size = size; t.Text = text; t.TextScaled = true
		t.Font = font or Enum.Font.GothamBold; t.TextColor3 = color; t.TextXAlignment = xa or Enum.TextXAlignment.Left
		t.Parent = parent
		return t
	end
	local green = Color3.fromRGB(110, 235, 120)
	label(fr, "LAUNCH CONTROL SYSTEM", UDim2.fromOffset(16, 10), UDim2.new(1, -32, 0, 24), green, Enum.Font.GothamBlack)
	label(fr, "MECH-01   " .. CFG.gun(mech).Label, UDim2.fromOffset(16, 37), UDim2.new(1, -32, 0, 18), green, Enum.Font.GothamMedium)
	local rows = {}
	for i, name in ipairs({ "SYSTEM", "THROTTLE", "CATAPULT" }) do
		local y = 64 + (i - 1) * 68
		local L = Instance.new("Frame")
		L.Position = UDim2.fromOffset(16, y); L.Size = UDim2.fromOffset(170, 58); L.BackgroundColor3 = Color3.fromRGB(215, 40, 50); L.BorderSizePixel = 0; L.Parent = fr
		local lt = label(L, "ABORT", UDim2.fromScale(0.08, 0.15), UDim2.fromScale(0.84, 0.7), Color3.fromRGB(255, 235, 235), Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
		local Rb = Instance.new("Frame")
		Rb.Position = UDim2.fromOffset(194, y); Rb.Size = UDim2.fromOffset(170, 58); Rb.BackgroundColor3 = Color3.fromRGB(20, 22, 26); Rb.BorderSizePixel = 0; Rb.Parent = fr
		local rs = Instance.new("UIStroke"); rs.Color = Color3.fromRGB(90, 96, 108); rs.Thickness = 1; rs.Parent = Rb
		local rt = label(Rb, name, UDim2.fromScale(0.08, 0.2), UDim2.fromScale(0.84, 0.6), Color3.fromRGB(240, 200, 60), Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
		rows[i] = { L = L, lt = lt, R = Rb, rt = rt }
	end
	fr.Position = UDim2.new(1, 420, 0.45, 0)   -- 오른쪽 밖에서 미끄러져 들어옴
	g.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(fr, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(1, -60, 0.45, 0) }):Play()
	return { gui = g, frame = fr, rows = rows, cleared = {}, go = false, out = false }
end
local function updateLaunchPanel(lp)
	local P = launchPanel
	if not P then return end
	local root = mech and mech:FindFirstChild("HumanoidRootPart")
	for i, at in ipairs(PANEL_CLEAR) do
		if lp >= at and not P.cleared[i] then
			P.cleared[i] = true
			local r = P.rows[i]
			r.R.BackgroundColor3 = Color3.fromRGB(240, 242, 245); r.rt.Text = "CLEAR"; r.rt.TextColor3 = Color3.fromRGB(20, 22, 26)
			if root then SM.play("LaunchBeep", root) end
		end
	end
	if lp >= PANEL_GO and not P.go then
		P.go = true
		for _, r in ipairs(P.rows) do
			r.L.BackgroundColor3 = Color3.fromRGB(150, 235, 255); r.lt.Text = "LAUNCH"; r.lt.TextColor3 = Color3.fromRGB(20, 60, 110)
		end
		if root then SM.play("LaunchGo", root) end
	end
	if lp >= 0.25 and not P.out then   -- 사출 직후 오른쪽으로 빠짐
		P.out = true
		TweenService:Create(P.frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1, 420, 0.45, 0) }):Play()
		local g = P.gui
		task.delay(0.3, function() g:Destroy() end)
		launchPanel = nil
	end
end
-- ---------- 사출장(10-25 17:39 유저 "사출이 총 두 종류": 지하 땅굴 UndergroundLaunch · 공중 캐터펄트 Catapult) ----------
-- 사출장 = workspace.MechTestRange 안 모델. 기체 속성 LaunchSite = 그 이름(없으면 땅굴). 코드는 하나, 사출장 속성만 다름:
--   경로 F1..Fn · RootUp · CutS(컷 C 시작 거리) · ShuttleStopS · ExitCam
--   LaunchSpeed · LaunchAccelTime (없으면 CFG.LaunchSpeed / LaunchAccelTime)
--   ExitMode: "skid"(문 밖 땅을 긁으며 섬, CFG.LaunchSkidTime/Pow) | "glide"(놓을 때 위로 ExitUp, GlideTime 동안 중력 GlideGravity·관성 유지, ExitHold 뒤 조작)
--   연출: DoorOpenAt(문 열기 시작, 가속 시작 기준 초) · DoorOpenTime · DoorCloseTime · ShuttleReturn(초당)
-- 바닥 경로를 구간으로 나누고, 꺾이는 곳 앞뒤 LAUNCH_BLEND 에 걸쳐 진행·위 방향을 섞는다
local LAUNCH_SITES = { "UndergroundLaunch", "Catapult" }
local LAUNCH_BLEND = 10
local launchPathCache = setmetatable({}, { __mode = "k" })
local function launcherPath(site)
	local R = workspace:FindFirstChild("MechTestRange")
	local L = R and R:FindFirstChild(site or "UndergroundLaunch")
	if not L then return nil end
	local cached = launchPathCache[L]
	if cached then return cached end
	local pts = {}
	for i = 1, 8 do
		local p = L:GetAttribute("F" .. i)
		if typeof(p) ~= "Vector3" then break end
		pts[i] = p
	end
	if #pts < 2 then return nil end
	local segs, total = {}, 0
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local t = (b - a).Unit
		local side = t:Cross(Vector3.yAxis)
		side = side.Magnitude > 1e-3 and side.Unit or Vector3.xAxis   -- 진행 방향 오른쪽(수평)
		segs[i] = { a = a, t = t, n = side:Cross(t).Unit, len = (b - a).Magnitude, s0 = total }
		total += segs[i].len
	end
	local V = L:GetAttribute("LaunchSpeed") or CFG.LaunchSpeed
	local TA = L:GetAttribute("LaunchAccelTime") or CFG.LaunchAccelTime
	local mode = L:GetAttribute("ExitMode") or "skid"
	local exitDir = segs[#segs].t
	local P = {
		model = L, site = L.Name, pts = pts, segs = segs, total = total, V = V, TA = TA, mode = mode,
		rootUp = L:GetAttribute("RootUp") or 11.8,
		exitDir = exitDir,
		side = Vector3.new(-exitDir.Z, 0, exitDir.X).Unit,      -- 사출 방향 기준 오른쪽
		runTime = TA + math.max(0, total - V * TA / 2) / V,     -- 놓아 주는 곳(마지막 점)까지 걸리는 시간
		cutS = L:GetAttribute("CutS") or (total - 30),
		stopS = L:GetAttribute("ShuttleStopS") or (total - 18),
		exitCam = L:GetAttribute("ExitCam"),
		exitUp = L:GetAttribute("ExitUp") or 20,
		glideTime = L:GetAttribute("GlideTime") or 0.8,
		glideG = L:GetAttribute("GlideGravity") or 30,
		after = (mode == "glide") and (L:GetAttribute("ExitHold") or 0.9) or CFG.LaunchSkidTime,   -- 놓은 뒤 조작을 돌려줄 때까지
		doorAt = L:GetAttribute("DoorOpenAt") or 0.2,
		doorOpenT = L:GetAttribute("DoorOpenTime") or 1.3,
		doorCloseT = L:GetAttribute("DoorCloseTime") or 2.0,
		shuttleRet = L:GetAttribute("ShuttleReturn") or 40,
	}
	launchPathCache[L] = P
	return P
end
local function pathFrame(P, s)   -- (발 자리, 진행 방향, 위 방향)
	s = math.clamp(s, 0, P.total)
	local segs = P.segs
	local i = #segs
	for k = 1, #segs do if s < segs[k].s0 + segs[k].len then i = k; break end end
	local g = segs[i]
	local foot = g.a + g.t * (s - g.s0)
	local t, n = g.t, g.n
	local nx, pv = segs[i + 1], segs[i - 1]
	if nx then
		local d = g.s0 + g.len - s
		if d < LAUNCH_BLEND then local w = 0.5 * lsmooth(1 - d / LAUNCH_BLEND); t = t:Lerp(nx.t, w).Unit; n = n:Lerp(nx.n, w).Unit end
	end
	if pv then
		local d = s - g.s0
		if d < LAUNCH_BLEND then local w = 0.5 * lsmooth(1 - d / LAUNCH_BLEND); t = t:Lerp(pv.t, w).Unit; n = n:Lerp(pv.n, w).Unit end
	end
	return foot, t, n
end
local function pathProject(P, pos)   -- 몸 중심 위치 → 경로 위 거리(남의 화면에서 셔틀을 기체 발밑에 붙일 때)
	local best, bestD = 0, math.huge
	for _, g in ipairs(P.segs) do
		local q = math.clamp((pos - g.a):Dot(g.t), 0, g.len)
		local dd = (pos - (g.a + g.t * q + g.n * P.rootUp)).Magnitude
		if dd < bestD then best, bestD = g.s0 + q, dd end
	end
	return best
end
local function launchS(p, P)   -- 가속 시작 뒤 p 초에 간 거리
	if p <= 0 then return 0 end
	local V, TA = P.V, P.TA   -- 사출장마다(땅굴 120·1.0 / 캐터펄트 150·1.2)
	if p < TA then return 0.5 * V / TA * p * p end
	return V * TA / 2 + V * (p - TA)
end
local function launchPhase(m)   -- (가속 시작 기준 경과 초 — 준비 중 음수, 경로). 사출 아님·다 끝남이면 nil
	local la = m and m:GetAttribute("LaunchAt")
	if type(la) ~= "number" then return nil end
	local P = launcherPath(m:GetAttribute("LaunchSite"))
	if not P then return nil end
	local p = workspace:GetServerTimeNow() - la
	if p < -CFG.LaunchPrep - 0.5 or p > P.runTime + P.after + 0.05 then return nil end
	return p, P
end
-- ---------- 내 기체 ----------
local function launchUnpin()   -- 경로를 따라가는 동안 끈 것들을 되돌림(놓을 때 · 연출 끝). 하차·죽음은 leave, 다음 탑승은 enter 가 따로 되돌림
	local hum = mech and mech:FindFirstChildOfClass("Humanoid")
	if hum and hum.PlatformStand then hum.PlatformStand = false end
	if faceAlign then faceAlign.Enabled = true end
end
local function launchBegin(P)
	local dir = P.exitDir
	yaw = math.atan2(-dir.X, -dir.Z); pitch = math.rad(-3)   -- 시점·몸 방향 = 사출 방향(연출 중엔 마우스로 안 돎)
	firing, aimHeld, shotQueuedAt = false, false, nil
	boostHeld = false
	jumpWindupAt, windStartLocal = nil, nil
	launchRel, launchCamLast, launchBlendT0 = false, nil, nil
	local root = mech:FindFirstChild("HumanoidRootPart")
	launchStartPos = root and root.Position or nil
	-- 경로를 직접 따라가는 동안 휴머노이드가 버티지 않게(PlatformStand), 경사에서 몸을 기울이므로 방향 제약도 끔
	local hum = mech:FindFirstChildOfClass("Humanoid")
	if hum then hum.PlatformStand = true end
	if faceAlign then faceAlign.Enabled = false end
	if hud then hud.gui.Enabled = false end
	if launchPanel then launchPanel.gui:Destroy() end
	launchPanel = makeLaunchPanel()
end
local function launchEnd()   -- 조작을 돌려줌: HUD 다시, 남은 패널·속도 제약 정리, 카메라는 LaunchReturn 동안 섞음
	launchUnpin()
	if hud then hud.gui.Enabled = true end
	if launchPanel then launchPanel.gui:Destroy(); launchPanel = nil end
	local root = mech and mech:FindFirstChild("HumanoidRootPart")
	if root then setBoostLV(root, "LaunchLV", nil) end
	if launchCamLast then launchBlendT0 = os.clock() end
end
-- 발 → 몸 중심 높이(10-26 중장갑): 사출장 RootUp 은 지상 프로토(속성 RootHeight 11.6) 기준이라 기체 키 차이만큼 더한다(프로토·Aero 는 그대로)
local function launchRootUp(P)
	return P.rootUp + (((mech and mech:GetAttribute("RootHeight")) or 11.6) - 11.6)
end
local function launchDrive(root, p, P)
	local V = P.V
	local dirF = Vector3.new(P.exitDir.X, 0, P.exitDir.Z).Unit
	if launchRel then
		if P.mode ~= "skid" then return end   -- 활공(캐터펄트): 놓은 뒤엔 공중 관성(AirCarry)·활공 중력이 이어 받음
		-- 미끄러짐: 문 밖에서 속도 V → 0 (LaunchSkidTime, 지수 LaunchSkidPow = 처음에 세게 잡히는 땅 마찰). 수평만 잡고 높이는 휴머노이드
		local k = math.clamp(1 - (p - P.runTime) / CFG.LaunchSkidTime, 0, 1) ^ (CFG.LaunchSkidPow or 1)
		setBoostLV(root, "LaunchLV", k > 0.02 and dirF * V * k or nil)
		return
	end
	local s = launchS(p, P)
	if s >= P.total then
		-- 놓아 줌(마지막 점 = 문 밖): 똑바로 세움
		launchRel = true
		launchUnpin()
		local pos = P.pts[#P.pts] + Vector3.new(0, launchRootUp(P), 0) + dirF * (s - P.total)
		root.CFrame = CFrame.lookAt(pos, pos + dirF)
		root.AssemblyAngularVelocity = Vector3.zero
		if P.mode == "glide" then
			-- 공중 캐터펄트(17:39 되살림, 값은 옛 16:03 활공과 같음): 위로 ExitUp 띄우고 GlideTime 동안 중력 GlideGravity · 공중 관성 유지, 부스터 켬
			root.AssemblyLinearVelocity = dirF * V + Vector3.new(0, P.exitUp, 0)
			setBoostLV(root, "LaunchLV", nil)
			carryVel = dirF * V                 -- 공중 관성: 지속 부스트 블록의 AirCarry 가 착지까지 이어 줌
			lastJumpAt = os.clock()             -- 막 뜬 것으로(= 공중 판정). 안 그러면 땅 판정이 남은 첫 프레임에 관성이 지워짐
			airDashUsed = false
			launchGlideUntil, launchGlideG = os.clock() + P.glideTime, P.glideG
			boostLocal[mech] = os.clock() + P.glideTime + 0.1   -- 부스터 불꽃·자세(활공 내내) — Aero 는 엔진 노즐 불꽃도(이름 Flame)
			local st = animState[mech]
			if st then st.boostDir = Vector3.new(0, 0, -1) end
		else
			-- 땅굴: 땅 위에 두고 같은 속도로 미끄러지기 시작
			root.AssemblyLinearVelocity = dirF * V
			setBoostLV(root, "LaunchLV", dirF * V)
		end
		return
	end
	-- 경로를 직접 따라감: 발 = 경로, 몸 중심 = 발 + 위 방향 × RootUp, 몸은 바닥과 같이 기움(셔틀에 실린 자세)
	local foot, t, n = pathFrame(P, s)
	local pos = foot + n * launchRootUp(P)
	root.CFrame = CFrame.lookAt(pos, pos + t, n)
	root.AssemblyLinearVelocity = t * ((p <= 0) and 0 or V * math.min(1, p / CFG.LaunchAccelTime))   -- 남의 화면 보간용
	root.AssemblyAngularVelocity = Vector3.zero
end
local function launchCamera(root, p, P)   -- (CFrame, 시야각)
	local up = Vector3.yAxis
	local side = P.side
	local s0 = launchStartPos or root.Position
	if p < 0 then
		-- 컷 A: 땅굴 출발점 앞 낮은 곳에서 기체를 올려다봄. 준비 동안 천천히 다가감
		local _, t0 = pathFrame(P, 0)
		local k = lsmooth((p + CFG.LaunchPrep) / CFG.LaunchPrep)
		local pos = s0 + t0 * (28 - 6 * k) + side * 7 + up * (-6 + 2 * k)
		return CFrame.lookAt(pos, s0 + up * 3), 55
	end
	local s = launchS(p, P)
	if s < P.cutS then
		-- 컷 B: 경로를 따라 왼쪽 뒤 낮게 따라감. 경사에선 카메라도 같이 기울어 오름. 빨라질수록 조금 멀어지고 시야각 넓어짐
		local k = math.clamp(p / P.runTime, 0, 1)
		local fc, _, nc = pathFrame(P, math.max(0, s - (22 + 10 * k)))
		local _, tm, nm = pathFrame(P, s)
		local pos = fc + nc * 7 - side * 7
		return CFrame.lookAt(pos, root.Position + tm * 30 + nm * 2, nc), 68 + 18 * k
	end
	-- 컷 C: 격납고 문 앞 오른쪽 낮은 곳 고정. 열린 철문 안 어둠에서 기체가 튀어나와 땅을 긁으며 미끄러져 옴(고개만 따라 돎)
	local pos = P.exitCam or (P.pts[#P.pts] + P.exitDir * 50 + side * 40 + up * 5)
	return CFrame.lookAt(pos, root.Position + up * 2), 60
end

-- ================= 카메라·사격 (내 메카) =================
RunService:BindToRenderStep("MechCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not mech then return end
	local root = mech:FindFirstChild("HumanoidRootPart")
	if not root or not mech.Parent then leave(); return end
	local cam = workspace.CurrentCamera
	UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
	-- 캐터펄트 사출(10-25): 단계 = 기체 속성 LaunchAt 기준. 조작을 돌려주는 시각(가속 끝 + ExitShot) 전까진 연출이 입력·카메라를 쥔다
	local lpL, PL = launchPhase(mech)
	local lockNow = lpL ~= nil and lpL < PL.runTime + PL.after   -- 주행 + 미끄러짐이 끝날 때까지
	if lockNow and not launchLock then launchBegin(PL) elseif launchLock and not lockNow then launchEnd() end
	launchLock = lockNow
	if lpL then launchDrive(root, lpL, PL); updateLaunchPanel(lpL) end
	-- 줌(2026-10-25): 오른쪽 클릭 + 라이플을 손에 듦(넣고 꺼내는 중 아님) + 근접·장전 아님
	local nowZ = os.clock()
	local _, anW = CFG.anchorPhase(mech)   -- 10-30 앵커 꿇은 정도 0~1(카메라 높이·아래 한계)
	zoomOn = aimHeld and weapon == "rifle" and nowZ - weaponAt >= CFG.UnequipTime and not meleeElapsed(mech) and not myReloading(nowZ)
		and not CFG.flipPhase(mech) and not GR.F.active(mech)   -- 10-30 앞차기 공중제비 중엔 줌 풀림(몸이 도는 중)
	zoomCam = math.clamp(zoomCam + (zoomOn and dt or -dt) * CFG.ZoomSpeed, 0, 1)
	local zc = zoomCam * zoomCam * (3 - 2 * zoomCam)
	-- 연사 블룸 회복: 쏘는 중(연사 간격 1.5배 안)엔 안 줄고, 멈추면 초당 SpreadRecover
	local Gz = CFG.gun(mech)   -- 주무기 수치(줌 배율: 라이플 1.3 / 저격총 3)
	if nowZ - lastShot > Gz.FireInterval * 1.5 then bloom = math.max(0, bloom - CFG.SpreadRecover * dt) end
	local base = baseFov or 70
	local mag = 1 + (CFG.zoomMag(mech) - 1) * zc   -- 10-30 앵커면 꿇는 정도만큼 3 → 6배(CFG.zoomMag)
	local fov = math.deg(2 * math.atan(math.tan(math.rad(base) / 2) / mag))
	local ke = nowZ - fovKickAt
	if ke < 0.5 then fov += 9 * (1 - ke / 0.5) ^ 2 end   -- 부스트 킥(옛 Quad Out 0.5초 트윈과 같은 곡선)
	cam.FieldOfView = fov
	-- 줌 중엔 마우스 감도를 배율만큼 낮춘다(화면에서 같은 거리를 움직이면 같은 만큼 돌게)
	local sens = CFG.MouseSensitivity / mag
	local d = UIS:GetMouseDelta()
	if not launchLock then   -- 캐터펄트 사출 중엔 시점 고정(사출 방향)
		yaw -= d.X * sens
		-- 10-30 앵커: 꿇은 정도만큼 아래 한계 −55° → CFG.Anchor.PitchMin(−30°, 더 숙이면 총구가 땅에 닿음)
		local pMin = -55 + (CFG.Anchor.PitchMin + 55) * anW
		pitch = math.clamp(pitch - d.Y * sens, math.rad(pMin), math.rad(65))
	end
	cam.CameraType = Enum.CameraType.Scriptable
	-- 카메라 거리·높이는 기체 종류별(10-26 중장갑: 키 1.26배만큼 멀고 높게, CFG.Types)
	local camS = function(k) return CFG.stat(mech, k) end
	-- 10-30 앵커: 꿇어 내려간 몸(CFG.Anchor.Drop)만큼 카메라 중심도 내림(엄폐물 뒤에 꿇으면 보이는 것도 그만큼 낮아짐)
	local focus = root.Position + Vector3.new(0, camS("CameraFocusHeight") - CFG.Anchor.Drop * anW, 0)
	local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local shX = camS("CameraShoulderX") + (camS("ZoomShoulderX") - camS("CameraShoulderX")) * zc
	local dist = camS("CameraDistance") + (camS("ZoomCameraDistance") - camS("CameraDistance")) * zc
	-- 10-27 메카 브레이크식 가운데 카메라: 위를 볼수록 CameraLookUpRise × sin(피치) 만큼 더 올림(등·머리가 조준선 쪽으로 올라오는 것 막음)
	local want = (CFrame.new(focus) * rot * CFrame.new(shX, camS("CameraShoulderY") + (camS("CameraLookUpRise") or 0) * math.max(0, math.sin(pitch)), dist)).Position
	local hit = workspace:Raycast(focus, want - focus, exclude({ mech }))
	if hit then want = hit.Position + (focus - want).Unit * 0.8 end
	cam.CFrame = CFrame.new(want) * rot
	if shake > 0 then
		local r = function() return (math.random() - 0.5) * 2 end
		cam.CFrame = cam.CFrame * CFrame.new(r() * 0.35 * shake, r() * 0.35 * shake, 0) * CFrame.Angles(r() * 0.006 * shake, r() * 0.006 * shake, 0)
		shake = math.max(0, shake - dt * 4)
	end
	-- 출격 사출 연출 카메라(10-25): 사출 중엔 컷 카메라(위 일반 카메라를 덮음), 조작을 돌려받은 뒤 LaunchReturn 동안 일반 카메라로 섞음
	if launchLock then
		local ccf, cfov = launchCamera(root, lpL or 0, PL)
		if shake > 0 then
			local r = function() return (math.random() - 0.5) * 2 end
			ccf = ccf * CFrame.new(r() * 0.35 * shake, r() * 0.35 * shake, 0)
		end
		cam.CFrame = ccf; cam.FieldOfView = cfov
		launchCamLast, launchFovLast = ccf, cfov
	elseif launchBlendT0 and launchCamLast then
		local w = lsmooth((os.clock() - launchBlendT0) / CFG.LaunchReturn)
		cam.CFrame = launchCamLast:Lerp(cam.CFrame, w)
		cam.FieldOfView = launchFovLast + (cam.FieldOfView - launchFovLast) * w
		if w >= 1 then launchBlendT0, launchCamLast = nil, nil end
	end
	-- 관성: 입력 방향으로 서서히 가속/감속 (ControlModule 이후에 Move 를 덮어쓴다)
	local hum0 = mech:FindFirstChildOfClass("Humanoid")
	if hum0 then
		local raw = rawMove()
		local wantMove = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(raw)
		if wantMove.Magnitude > 1 then wantMove = wantMove.Unit end
		local rate = (wantMove.Magnitude > moveVec.Magnitude) and CFG.Accel or CFG.Decel
		moveVec = moveVec:Lerp(wantMove, 1 - math.exp(-dt * rate))
		if moveVec.Magnitude < 0.02 and wantMove.Magnitude == 0 then moveVec = Vector3.zero end
		-- 이동 입력 배율: 웅크리는 동안 거의 멈춤 · 줌 중 60%(줌 들어가는 정도만큼 부드럽게)
		local moveMul = (jumpWindupAt and CFG.JumpWindupMove or 1) * (1 + (CFG.ZoomMoveMul - 1) * zc)
		moveMul /= CFG.slowMul(mech)   -- 10-30 FALCO 마비 덫: 이동 ÷1.5
		if GR.spinLocal then moveMul *= (CFG.gun(mech).MoveMul or 1) end   -- 10-27 개틀링이 도는 동안 걷기 느림
		if not GR.drive(mech, root, hum0) and not GR.flipDrive(mech, root, hum0) and not GR.FE.drive(mech, root, hum0) then GR.F.drive(mech, root, hum0) end   -- 10-30 FELSEN 궁극기 도약 길도   -- 10-27 작살에 맞아 끌려오는 중이면 그 길로 직접 놓음 · 10-30 아니면 앞차기 공중제비 길
		if GR.locked(mech) or anW > 0 then moveMul = 0; carryVel = nil end   -- 10-30 앵커(꿇기~일어나기): 이동 못 함, 회전만
		hum0:Move(moveVec * moveMul, false)
		-- 점프 쿨: 착지(0.3초 넘게 떠 있었을 때만 — 땅 판정이 잠깐씩 깜빡여서) 뒤 JumpCooldown 동안 못 뜀
		local nowJ = os.clock()
		local airNow = hum0.FloorMaterial == Enum.Material.Air
		if not airNow then
			if wasAirMine and nowJ - airSince > 0.3 then lastLandAt = nowJ end
		elseif not wasAirMine then
			airSince = nowJ
		end
		wasAirMine = airNow
		-- 도약(2026-10-25 2차): 누르면 바로 뜨지 않고 JumpWindup 동안 땅에서 웅크렸다가 직접 띄운다.
		-- 입력은 hum.Jump — 기본 조작 모듈이 키보드·패드·모바일 점프 버튼을 이 프레임 앞(Input 단계)에서 넣어 준다.
		-- 읽은 뒤 false 로 지워 엔진이 스스로 뛰지 못하게 가로챈다(물리는 이 렌더 단계 뒤에 돈다) → 엔진 점프는 아예 안 일어남 = 이중 점프도 없음
		local wantJump = hum0.Jump
		if wantJump then hum0.Jump = false end
		local ready = nowJ - lastLandAt >= CFG.JumpCooldown and nowJ - lastJumpAt >= CFG.JumpCooldown
			and not (airNow and nowJ - airSince > 0.1)
		if wantJump and ready and not jumpWindupAt and not launchLock and not GR.anchored(mech) then   -- 10-30 앵커 중 점프 못 함
			-- 부스트 중(대시·지속)이면 부스트 점프: 웅크림을 짧게(JumpWindupBoost), 달리던 수평 속도를 공중 관성으로 실어 뜀
			local boostingNow = nowJ < dashUntil or holdActive
			windDurLocal = boostingNow and CFG.JumpWindupBoost or CFG.JumpWindup
			jumpBoostVel = boostingNow and ((holdActive and carryVel) or dashVel) or nil
			jumpWindupAt, windStartLocal = nowJ, nowJ
			Remotes.MechJump:FireServer(windDurLocal)   -- 다른 화면도 같은 길이로 웅크림(서버 속성 JumpWindAt·JumpWindDur)
		end
		if jumpWindupAt then
			if airNow and nowJ - airSince > 0.15 then
				jumpWindupAt, windStartLocal = nil, nil   -- 웅크리다 발밑이 꺼지면(낭떠러지) 취소
			elseif nowJ - jumpWindupAt >= windDurLocal then
				jumpWindupAt = nil
				lastJumpAt, jumpRising = nowJ, true
				if jumpBoostVel then carryVel = jumpBoostVel end   -- 부스트 점프: 달리던 속도를 공중 관성으로
				jumpBoostVel = nil
				hum0:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
				hum0:ChangeState(Enum.HumanoidStateType.Jumping)
				-- 상태 전환만 믿지 않고 위 속도도 직접 준다(10-25 첫 웅크림 버전은 "아예 안 뜸" 이력)
				local vr = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(vr.X, math.max(vr.Y, CFG.JumpPower), vr.Z)
			end
		end
		lastHumState = hum0:GetState()
		-- 상승(10-25 18:24, CFG.Types.*.Climb — 공중 프로토만): 공중에서 점프 키를 누르고 있으면 위로(제트팩). 땅에서 누르면 평소처럼 웅크렸다 뜨고,
		-- 계속 누르고 있으면 이어서 상승. 게이지는 지속 부스트와 같은 통로(서버 "hold")로 깎이고, 바닥나면(0 + 과열) 끊김 → 키를 뗐다 다시 눌러야 재개
		local climbing = false
		if CFG.stat(mech, "Climb") == true then
			local eC = mech:GetAttribute("Energy") or 0
			local overC = (mech:GetAttribute("OverheatUntil") or 0) > workspace:GetServerTimeNow()
			if climbLocked and not wantJump then climbLocked = false end
			local tryClimb = wantJump and airNow and nowJ - airSince > 0.12 and not jumpWindupAt and not launchLock and not GR.locked(mech)
			if tryClimb and (eC <= 0.5 or overC) then climbLocked = true end
			climbing = tryClimb and not climbLocked
		end
		setClimbLV(root, climbing and CFG.stat(mech, "ClimbSpeed") or nil, CFG.stat(mech, "ClimbAccel"))
		if climbing then climbLocal[mech] = nowJ + 0.1 end
		-- 메카 중력(2026-10-25): 점프로 오르는 동안 CFG.JumpRiseGravity, 내려올 땐(점프·낙하 모두, 0.1초 넘게 떠 있을 때) CFG.JumpFallGravity.
		-- workspace.Gravity 와의 차이만큼 위쪽 힘을 준다. 뛴 첫 프레임은 아직 위 속도가 0 일 수 있어 0.1초 지나서부터 "꼭대기" 판정. 오름 2.5초 안전망
		if jumpAssist and jumpAssist.Parent then
			local r = jumpAssist.Parent
			local vy = r.AssemblyLinearVelocity.Y
			if jumpRising and ((nowJ - lastJumpAt > 0.1 and vy <= 0) or nowJ - lastJumpAt > 2.5) then jumpRising = false end
			local falling = (not jumpRising) and airNow and nowJ - airSince > 0.1 and vy <= 0
			local g = jumpRising and CFG.JumpRiseGravity or (falling and CFG.stat(mech, "JumpFallGravity") or nil)   -- 18:24 공중 프로토는 천천히 내려옴(70)
			if launchLock and not launchRel then g = nil end
			if climbing then g = nil end   -- 상승 중엔 ClimbLV 가 위아래를 잡음
			if nowJ < launchGlideUntil then g = launchGlideG end   -- 17:39 공중 캐터펄트 활공: 부스터로 버팀   -- 출격 사출: 경로를 직접 따라가는 동안 점프 중력 보조 끔
			if g then jumpAssist.Force = Vector3.new(0, r.AssemblyMass * (workspace.Gravity - g), 0) end
			local on = g ~= nil
			if jumpAssist.Enabled ~= on then jumpAssist.Enabled = on end
		end
		-- Jumping 상태 켜기/끄기는 이제 "뛸 수 있음" 표시용(모바일 점프 버튼이 이 값을 보고 숨는다) + 띄우는 순간 0.1초
		local jumpOn = (ready and not jumpWindupAt) or nowJ - lastJumpAt < 0.1
		if hum0:GetStateEnabled(Enum.HumanoidStateType.Jumping) ~= jumpOn then
			hum0:SetStateEnabled(Enum.HumanoidStateType.Jumping, jumpOn)
		end
		-- ---------- 지속 부스트 · 공중 관성 (2026-10-25) ----------
		-- 규칙: 누르고 있는 동안은 어디서든 수평으로 밀어 준다(대시 뒤 이어서). 공중에서도 위로는 안 띄움 → 체공 그대로, 앞으로만 멀리.
		-- 떼면 즉시 멈춤. 게이지가 바닥나면(서버가 0 + 과열) 끊기고, 키를 뗐다 다시 눌러야 재개
		local eNow = mech:GetAttribute("Energy") or 0
		local overheated = (mech:GetAttribute("OverheatUntil") or 0) > workspace:GetServerTimeNow()
		if not airNow then airDashUsed = false end
		if holdLocked and not boostHeld then holdLocked = false end
		if holdActive and (eNow <= 0.5 or overheated) then holdLocked = true end
		local dashing = nowJ < dashUntil
		local meleeNow = meleeElapsed(mech) ~= nil
		local wantHold = boostHeld and not holdLocked and not dashing and not meleeNow and not overheated and eNow > 0.5 and not launchLock and not GR.locked(mech) and not GR.anchored(mech)   -- 10-30 앵커 중 지속 부스트 못 함
		local inAirB = (airNow and nowJ - airSince > 0.05) or nowJ - lastJumpAt < 0.25   -- 막 뛴 프레임도 공중으로
		local hdir = Vector3.new(moveVec.X, 0, moveVec.Z)   -- 이동 입력 쪽(관성 섞인 값이라 부드럽게 꺾임), 없으면 몸 정면
		if hdir.Magnitude < 0.1 then local lv = root.CFrame.LookVector; hdir = Vector3.new(lv.X, 0, lv.Z) end
		hdir = hdir.Unit
		setBoostLV(root, "BoostHold", wantHold and hdir * (CFG.stat(mech, "BoostHoldSpeed") / CFG.slowMul(mech)) or nil)   -- 18:24 공중 프로토 75
		if wantHold then
			carryVel = hdir * (CFG.stat(mech, "BoostHoldSpeed") / CFG.slowMul(mech))   -- 10-30 마비 덫: 부스트 ÷1.5
			boostLocal[mech] = nowJ + 0.1   -- 애니: 부스트 자세·불꽃 유지
			local stB = animState[mech]
			if stB then stB.boostDir = root.CFrame:VectorToObjectSpace(hdir) end
		elseif dashing then
			carryVel = dashVel
		end
		-- 서버에 지속 상태 알림(바뀔 때만): 소모는 서버가, 공중이면 1.5배
		local holdE = wantHold or climbing                   -- 18:24: 게이지 소모 = 지속 부스트 또는 상승(같은 통로)
		local airHold = (wantHold and inAirB) or climbing
		if holdE ~= holdActive or airHold ~= holdAirSent or climbing ~= climbSent then
			holdActive, holdAirSent, climbSent = holdE, airHold, climbing
			Remotes.MechBoost:FireServer("hold", holdE, airHold, climbing)
		end
		-- 공중 관성: 추진·대시가 공중에서 끝나면 그때 수평 속도를 착지까지 서서히 줄이며 이어 준다(공중에서 툭 멈추면 버그처럼 보임)
		if not wantHold and not dashing and not meleeNow and inAirB and carryVel and carryVel.Magnitude > CFG.WalkSpeed then
			if nowJ >= launchGlideUntil then carryVel *= math.exp(-dt / CFG.BoostAirCarryTau) end   -- 캐터펄트 활공 중엔 안 줄어듦
			setBoostLV(root, "AirCarry", carryVel)
		else
			setBoostLV(root, "AirCarry", nil)
			if not inAirB and not dashing and not wantHold then carryVel = nil end
		end
		-- 기체 물리 안전장치(10-25 13:26, 유저 영상 "부스트→빔사벨로 적에 부딪히면 급상승"): 대시·지속·관성·내딛기 제약이
		-- 다른 기체 몸통을 밀지 않게(닿으면 그쪽 성분 0 + 힘 유한) + 점프로 오르는 중이 아니면 위로 RiseCap 넘게 못 오름
		MP.clipPush(mech, root)
		if not (launchLock and not launchRel) then   -- 출격 사출로 경사를 오르는 동안(위 속도 약 62)은 상승 제한 안 함
			MP.capRise(root, jumpRising and CFG.RiseCapJump or CFG.stat(mech, "RiseCap"))   -- 18:24 공중 프로토 40(상승 32 를 안 막게)
		end
	end
	if faceAlign then
		local ml = meleeElapsed(mech) and meleeLocal[mech]   -- 벨 때는 내딛는 방향(적 쪽)으로 빨리 돈다
		faceAlign.CFrame = CFrame.Angles(0, GR.F.faceYaw() or GR.FE.faceYaw(mech) or (ml and ml.yaw) or yaw, 0)   -- 10-30 라이더킥 중엔 급강하 쪽
		faceAlign.MaxAngularVelocity = (ml and 20 or ((firing or aimHeld) and CFG.AimTurnRate or CFG.TurnRate)) / CFG.slowMul(mech)   -- 10-30 마비 덫: 선회 ÷1.5
	end
	local bl = root.CFrame.LookVector
	local diff = (yaw - math.atan2(-bl.X, -bl.Z) + math.pi) % (2 * math.pi) - math.pi
	aimYawOff = math.deg(diff)

	local now = os.clock()
	if shotQueuedAt and now - shotQueuedAt > SHOT_QUEUE_LIFE then shotQueuedAt = nil end
	local wantShot = (firing or shotQueuedAt ~= nil) and not launchLock and not GR.locked(mech)   -- 누르고 있음 또는 예약된 한 발(사출 연출·그랩 경직 중엔 안 쏨)
		and not GR.anchorBusy(mech)   -- 10-30 앵커: 꿇는 중·일어나는 중엔 안 쏨(서버도 거절)
	local G = CFG.gun(mech)   -- 주무기 수치(연사 간격·사거리·소리·탄도선·반동)
	if wantShot and weapon == "rifle" and not G.Heat and not G.NoAmmo and ammoLocal <= 0 then shotQueuedAt = nil; requestReload() end   -- 빈 탄창으로 당기면 장전(10-30 궁극기 탄창 무한이면 안 함)
	if reloadLocalUntil > 0 and mech:GetAttribute("UltStart") then reloadLocalUntil = 0 end   -- 10-30 궁극기 시작 = 서버가 장전 취소 → 내 예측도 지움
	-- 10-27 회전 총(개틀링): 방아쇠를 당기면 돌고(GR.spin) SpinUp 뒤부터 나감. 과열 총(Heat)이면 강제 냉각 중엔 돌기만,
	--   탄창 총(16:16 개틀링)이면 장전 중엔 안 돎 → 장전 끝나고 다시 당기면 0.6초 돌고 나감
	local gunReady
	if G.SpinUp then
		local reloadingNow = (not G.Heat) and myReloading(now)
		GR.spin((firing and weapon == "rifle" and not launchLock and not GR.locked(mech) and now - weaponAt >= CFG.UnequipTime and not meleeElapsed(mech) and not reloadingNow) or (weapon == "rifle" and not reloadingNow and GR.FE.preSpin(mech)))   -- 10-31 그랩으로 끌어오는 동안 미리 돎(도착하자마자 쏘게)
		if G.Heat then
			local _, lockedH = CFG.gunHeat(mech, workspace:GetServerTimeNow())
			gunReady = GR.spunUp(G) and not lockedH
		else
			gunReady = GR.spunUp(G) and ammoLocal > 0 and not reloadingNow
		end
	else
		if GR.spinLocal then GR.spin(false) end
		gunReady = G.NoAmmo or (ammoLocal > 0 and not myReloading(now))   -- 10-30 궁극기 사격 창 = 탄창 무한
	end
	-- 팔을 다 든 뒤에만 쏜다(10-25 동기화): 클릭 → 팔 듦(약 0.07초) → 발사. 장전·근접·무기 교체 중엔 애니가 팔을 내리므로 그동안 안 나감
	local stF = animState[mech]
	local raised = stF == nil or (stF.aim or 0) >= SHOT_RAISED
	if wantShot and weapon == "rifle" and gunReady and now - weaponAt >= CFG.UnequipTime and not meleeElapsed(mech) and now - lastShot >= G.FireInterval * CFG.slowMul(mech) and math.abs(aimYawOff) <= CFG.FireArc and raised then   -- 몸이 조준 방향을 볼 때만 발사
		lastShot = now
		shotQueuedAt = nil
		local target = aimPoint()
		local mz = mech:FindFirstChild("Rifle") and mech.Rifle:FindFirstChild("Muzzle")
		if mz then
			local from = mz.WorldPosition
			-- 탄 퍼짐: 총구→조준점 방향을 원뿔 안에서 무작위로 튼다(원판 위에 고르게). 쏜 뒤 블룸 증가
			local humF = mech:FindFirstChildOfClass("Humanoid")
			local spread = humF and currentSpread(root, humF, now) or CFG.SpreadBase
			local dir = (target - from).Unit
			local rr = math.rad(spread) * math.sqrt(math.random())
			dir = (CFrame.lookAlong(Vector3.zero, dir) * CFrame.Angles(0, 0, math.random() * 2 * math.pi) * CFrame.Angles(rr, 0, 0)).LookVector
			bloom = math.min(CFG.SpreadBloomMax, bloom + CFG.SpreadPerShot)
			local r = workspace:Raycast(from, dir * G.Range, exclude({ mech }))
			local to = r and r.Position or (from + dir * G.Range)
			tracer(from, to, G.Tracer, G.TracerGlow, G.TracerCore); muzzleFlash(mech, G.Kick > 1 or G.BigFlash == true)   -- 10-30 앵커 표는 반동 0 이라 BigFlash 로 큰 불꽃 유지
			SM.play(G.FireSound or "GunFire", mz)
			if r then
				spark(r.Position, r.Normal)
				if isHittable(r.Instance) then SM.play("GunHit", r.Position) end
			end
			recoil[mech] = G.Kick or 1                               -- 반동 크기(저격총 2.5)
			if (G.Kick or 1) > 1 then shake = math.max(shake, 0.45) end   -- 저격총: 쏠 때 화면이 한 번 튐
			lastFireAt[mech] = now
			Remotes.MechFire:FireServer(to, from)   -- 퍼진 탄이 실제로 간 지점 + 이 화면의 총구(10-30: 서버가 믿을 수 있는 거리면 이 총구에서 쏨 → 같은 줄로 같은 곳에 맞음)
			if not G.Heat and not G.NoAmmo then
				ammoLocal -= 1
				if ammoLocal <= 0 then requestReload() end
			end
		end
	end
	updateSlashQueue()
	if GR.meleeBuf and not GR.locked(mech) then   -- 10-31 그랩 중 누른 R = 풀리는 순간 바로
		local okB = os.clock() - GR.meleeBuf < 1.6
		GR.meleeBuf = nil
		if okB then if mech:GetAttribute("Melee") == "Kick" then tryMelee("kick") elseif weapon == "saber" then trySlash() else tryMelee("saber") end end
	end
	if firing and weapon == "saber" and not GR.locked(mech) then trySlash() end   -- 빔사벨 상태: 좌클릭을 누르고 있으면 쿨다운마다 벤다(그랩 경직 중 아님)
	local deg = math.deg(pitch)
	if (math.abs(deg - lastAimSent) > 2 or math.abs(aimYawOff - (lastYawSent or 0)) > 3 or zoomOn ~= lastZoomSent) and now - lastAimTime > 0.1 then
		lastAimSent, lastAimTime, lastYawSent, lastZoomSent = deg, now, aimYawOff, zoomOn
		Remotes.MechAim:FireServer(deg, aimYawOff, zoomOn)   -- 줌 여부도 같이(서버 속성 AimZoom → 다른 화면 두 손 자세)
	end
	if hud then
		local hum = mech:FindFirstChildOfClass("Humanoid")
		if hum then
			hud.setHP(math.clamp(hum.Health / hum.MaxHealth, 0, 1))
			hud.hpText.Text = string.format("HP %d", math.max(0, math.floor(hum.Health + 0.5)))
		end
		hud.setEN(math.clamp((mech:GetAttribute("Energy") or 0) / CFG.stat(mech, "MaxEnergy"), 0, 1))
		do   -- 10-30 궁극기 게이지(makeHUD setULT)
			local nowU = workspace:GetServerTimeNow()
			local gU = math.clamp((mech:GetAttribute("UltGauge") or 0) / CFG.Ult.Max, 0, 1)
			local phU = CFG.ultPhase(mech, nowU)
			local trEnd = CFG.trapPhase(mech, nowU) and CFG.trapEnd(mech)   -- 10-30 FALCO 마비 덫: 남은 시간(못 날기 + 전기 전 + 지대)
			if trEnd then
				local TP = CFG.Trap
				local leftT = math.max(0, trEnd - nowU)
				hud.setULT(leftT / (TP.FlyTime + TP.LinkDelay + TP.Duration), ('<font color="#BE78FF">ULT %.1f</font>'):format(leftT), true)
			elseif phU then
				local s, e = mech:GetAttribute("UltStart"), mech:GetAttribute("UltEnd")
				local left = math.max(0, e - math.max(nowU, s))
				hud.setULT(left / CFG.ForcedAnchor.Duration, ('<font color="#BE78FF">ULT %.1f</font>'):format(left), true)
			elseif not mech:GetAttribute("Ultimate") then
				hud.setULT(gU, '<font color="#8A93A0">ULT</font>', false)
			elseif gU >= 1 then
				local blink = math.floor(os.clock() * 3) % 2 == 0
				hud.setULT(1, blink and '<font color="#FFFFFF">ULT READY  [X]</font>' or '<font color="#BE78FF">ULT READY  [X]</font>', blink)
			else
				hud.setULT(gU, ("ULT %d%%"):format(math.floor(gU * 100)), false)
			end
		end
		updateWeaponHUD()   -- 미사일 남음/씀 표시가 서버 속성으로 바뀌므로 매 프레임(글자가 같으면 안 바꿈)
		-- 조준선 벌어짐 = 지금 쏘면 퍼질 원뿔(반각을 화면 픽셀로: tan(각)/tan(시야각/2) × 화면 높이/2). 안쪽 끝이 원뿔 가장자리
		if hum and hud.ch then
			local cam = workspace.CurrentCamera
			local px = math.tan(math.rad(currentSpread(root, hum, now))) / math.tan(math.rad(cam.FieldOfView) / 2) * cam.ViewportSize.Y / 2
			local off = math.max(9, px) + 5
			hud.ch[1].Position = UDim2.new(0.5, 0, 0.5, -off); hud.ch[2].Position = UDim2.new(0.5, 0, 0.5, off)
			hud.ch[3].Position = UDim2.new(0.5, -off, 0.5, 0); hud.ch[4].Position = UDim2.new(0.5, off, 0.5, 0)
		end
		-- 쉬는 동안엔 서버 값으로 맞춘다(서버가 거절한 발이 있으면 여기서 바로잡힘)
		if now - lastShot > 0.6 and not myReloading(now) then ammoLocal = mech:GetAttribute("Ammo") or ammoLocal end
		-- 총을 바꿨으면(거치대) 탄창·장전 예측을 새 총 기준으로 바로 맞춘다
		local gNow = mech:GetAttribute("Gun") or "rifle"
		if gNow ~= gunSeen then
			gunSeen = gNow
			ammoLocal, reloadLocalUntil = mech:GetAttribute("Ammo") or CFG.gun(mech).MagSize, 0
		end
		updateWeaponHUD()
	end
end)

Remotes.MechFX.OnClientEvent:Connect(function(kind, m, a, b, shooterId, n, hitMech)
	if kind == "fire" and shooterId ~= player.UserId and m and m.Parent then
		-- 서버가 준 출발점(a)은 휴식 자세 기준이라 화면 총구와 다르다 → 이 화면에서 보이는 총구에서 그린다
		local mz = m:FindFirstChild("Rifle") and m.Rifle:FindFirstChild("Muzzle")
		local Gm = CFG.gun(m)   -- 쏜 기체의 주무기(속성 Gun) — 저격총이면 굵은 탄도선·큰 소리
		tracer(mz and mz.WorldPosition or a, b, Gm.Tracer, Gm.TracerGlow, Gm.TracerCore); muzzleFlash(m, Gm.Kick > 1 or Gm.BigFlash == true); spark(b, n or Vector3.yAxis)
		SM.play(Gm.FireSound or "GunFire", mz or m:FindFirstChild("HumanoidRootPart"))
		if hitMech then SM.play("GunHit", b) end   -- 서버가 "기체·표적에 맞음" 을 같이 보냄
		recoil[m] = Gm.Kick or 1
		lastFireAt[m] = os.clock()
	elseif kind == "melee" and m and a and a.Parent then
		meleeHit(m, a, b)
	end
end)

-- ================= 모든 메카 코드 애니메이션 =================
-- 10-30: 자세 표·자세 함수(옛 2116~2797줄 — 기체별 상수 SHAPES · 빔사벨/주먹/앞차기/베기 자세 · 두 손 IK · 착지·웅크림 표 · 라이플/빔사벨/도끼 보이기)는
--   자식 모듈 MechPoses 로 옮김(유저 10-30 "메크 클라이언트를 분석하고 나눠야 할 것 같아" — Script.Source 20만 자 한도). 여기선 쓰는 이름 40개를 같은 이름으로 받음.
--   모듈이 MechClient 상태를 읽는 곳은 reloadElapsed 하나(내 기체 장전 예측) → 읽기 함수만 init 으로 넘김
local PO = require(script:WaitForChild("MechPoses"))
PO.init({ mech = function() return mech end, reloadLocalUntil = function() return reloadLocalUntil end, reloadSlow = function() return GR.reloadSlow or 1 end })
local AIM_HOLD_REMOTE, AIR_FALL, AIR_RISE, AIR_TUCK, E, JUMP_CROUCH, JUMP_EXTEND, JUMP_LEAN, LAND_DEPTH, LAND_DEPTH_HARD, LAND_DUR, LAND_DUR_HARD, LAND_LEAN, LAND_LEAN_HARD, R, SLASH_POSE, SLASH_TRAIL, SWING_AT, WIND_HOLD_MINE, WIND_HOLD_REMOTE, ZOOM_TWIST, axeRightHand, blendPose, comboPose, crouchAngles, dropMag, equipPose, kickPose, padTransform, punchPose, reloadElapsed, reloadPose, saberPose, setRifle, setSaber, setThrusters, shapeOf, sstep, twoHandPose, unequipPose =
	PO.AIM_HOLD_REMOTE, PO.AIR_FALL, PO.AIR_RISE, PO.AIR_TUCK, PO.E, PO.JUMP_CROUCH, PO.JUMP_EXTEND, PO.JUMP_LEAN, PO.LAND_DEPTH, PO.LAND_DEPTH_HARD, PO.LAND_DUR, PO.LAND_DUR_HARD, PO.LAND_LEAN, PO.LAND_LEAN_HARD, PO.R, PO.SLASH_POSE, PO.SLASH_TRAIL, PO.SWING_AT, PO.WIND_HOLD_MINE, PO.WIND_HOLD_REMOTE, PO.ZOOM_TWIST, PO.axeRightHand, PO.blendPose, PO.comboPose, PO.crouchAngles, PO.dropMag, PO.equipPose, PO.kickPose, PO.padTransform, PO.punchPose, PO.reloadElapsed, PO.reloadPose, PO.saberPose, PO.setRifle, PO.setSaber, PO.setThrusters, PO.shapeOf, PO.sstep, PO.twoHandPose, PO.unequipPose

-- 애니 대상 = "Mech" 태그 + "MechDisplay" 태그(2026-10-25 전시용 기체: 서버 로직(보급·최대 대수·근접 판정)은 "Mech" 태그만 보므로
-- 전시 기체는 서버에 안 보이고, 화면에서만 속성(AimZoom·AimPitch 등)대로 남의 기체와 똑같이 움직인다)
local function animTargets()
	local list = CollectionService:GetTagged("Mech")
	for _, d in ipairs(CollectionService:GetTagged("MechDisplay")) do table.insert(list, d) end
	return list
end
-- 기체 하나의 애니(10-25: 기체마다 pcall — 한 기체에서 오류가 나도 다른 기체·다음 프레임은 그대로 돌고, 처음 한 번만 경고를 남긴다.
-- 예전엔 한 기체의 오류가 이번 프레임의 나머지 기체를 통째로 멈췄다)
local animErrLogged = setmetatable({}, { __mode = "k" })
local function animOne(m, t, dt)
	do
		do
			local st = animState[m]
			if not st then
				st = { phase = 0, J = {}, emitters = {}, thrust = nil, aim = 0, boost = 0, dir = Vector3.new(0, 0, -1), boostDir = Vector3.new(0, 0, -1),
					SH = shapeOf(m) }   -- 10-26 기체 모양별 상수(MechType 은 템플릿에 박혀 바뀌지 않음)
				for _, n in ipairs(JOINTS) do st.J[n] = m:FindFirstChild(n, true) end
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("ParticleEmitter") and d.Name == "Flame" then table.insert(st.emitters, d) end
				end
				st.light = m:FindFirstChild("BoostLight", true)
				animState[m] = st
			end
			-- 관절 캐시 다시 확인(10-25, 유저 "탈 때 가끔 아무 동작 없이 뻣뻣하게 굳음" — 영상: 팔이 그대로 늘어진 휴식 자세인데
			-- 등 라이플 표시·빔은 바뀜 = 루프는 도는데 관절에만 못 씀). StreamingEnabled 라 기체가 처음 보일 때 파트·관절이 덜 들어와 있으면
			-- 그때 못 찾은 관절은 영영 nil 이었다(또는 다시 들어온 파트 = 새 인스턴스면 캐시가 낡음) [추측: 플레이 로그로 확인 필요].
			-- → 0.5초마다 빠졌거나 기체 밖으로 나간 관절만 다시 찾고, 바뀌었으면 불꽃·빔사벨 파트 캐시도 새로. 템플릿도 Atomic 스트리밍으로 바꿈
			if t >= (st.jCheckAt or 0) then
				st.jCheckAt = t + 0.5
				local changed = nil
				for _, n in ipairs(JOINTS) do
					local j = st.J[n]
					if not (j and j:IsDescendantOf(m)) then
						local nj = m:FindFirstChild(n, true)
						if nj ~= j then st.J[n] = nj; changed = n end
					end
				end
				if changed then
					st.emitters = {}
					for _, d in ipairs(m:GetDescendants()) do
						if d:IsA("ParticleEmitter") and d.Name == "Flame" then table.insert(st.emitters, d) end
					end
					st.light = m:FindFirstChild("BoostLight", true)
					st.thrust, st.saberParts, st.saberHand, st.saberBeam, st.trailOn, st.EJ = nil, nil, nil, nil, nil, nil
					st.WJ = nil   -- 10-26 날개 관절도 다시 찾음
					st.axeKey = nil   -- 10-27 도끼 파트가 새것이면 크기·투명도를 다시 칠함
					if not st.jLogged then
						st.jLogged = true
						print(("[MechAnim] %s 관절 캐시 다시 찾음(%s 등) — 처음 볼 때 덜 들어와 있었거나 새로 들어옴"):format(m:GetFullName(), changed))
					end
				end
			end
			local root = m:FindFirstChild("HumanoidRootPart")
			local hum = m:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local J = st.J
				-- ---------- 상태 ----------
				-- 출격 사출(10-25 16:24 지하 땅굴): 단계 = 가속 시작 기준 초(준비 중 음수). 준비·주행·미끄러짐 동안(riding) 버티는 자세
				-- (걷기·공중 자세 없음 — 주행 중엔 PlatformStand 라 땅 판정이 공중으로 나옴). 주행 중 + 나와서 0.3초 등 부스터 불꽃(자세는 안 바꿈)
				local lpA, PA = launchPhase(m)
				local LAa = PA and PA.runTime or 0
				local SKa = (PA and PA.mode == "skid") and PA.after or 0   -- 활공(캐터펄트)은 놓는 순간부터 공중 자세
				local riding = lpA ~= nil and lpA < LAa + SKa
				local boosting = (boostLocal[m] or 0) > t or (m:GetAttribute("BoostUntil") or 0) > workspace:GetServerTimeNow()
					or (m ~= mech and m:GetAttribute("BoostHold") == true) or GR.F.active(m) or GR.FE.charging(m)   -- 남의 기체 지속 부스트(서버 속성) · 10-30 FELSEN 돌진 = 등 불꽃
				local climbingA = (climbLocal[m] or 0) > t or (m ~= mech and m:GetAttribute("Climb") == true)   -- 18:24 상승(공중 프로토)
				setThrusters(st, boosting or climbingA or (lpA ~= nil and lpA >= 0 and lpA < LAa + ((PA and PA.mode == "glide") and PA.glideTime or 0.3)))
				-- 가동 엔진(18:24 공중 프로토): 기본 = 노즐이 아래에서 뒤로 30°(관절 C0). 상승 중 = 수직(+30°) · 부스트 중 = 더 뒤로(-25°) · 서서히 꺾임
				if st.EJ == nil then
					st.EJ = {}
					for _, n in ipairs({ "EngineJointL", "EngineJointR" }) do
						local j = m:FindFirstChild(n, true)
						if j then table.insert(st.EJ, j) end
					end
				end
				if #st.EJ > 0 then
					local wantE = climbingA and 30 or (boosting and -25 or 0)
					st.eng = (st.eng or 0) + (wantE - (st.eng or 0)) * math.min(1, dt * 8)
					local cfE = CFrame.Angles(math.rad(st.eng), 0, 0)
					for _, j in ipairs(st.EJ) do j.Transform = cfE end
				end
				st.boost = math.clamp(st.boost + (boosting and dt * 14 or -dt * 4), 0, 1)
				local kb = st.boost * st.boost * (3 - 2 * st.boost)
				local v = root.AssemblyLinearVelocity
				local localV = root.CFrame:VectorToObjectSpace(Vector3.new(v.X, 0, v.Z))
				local flat = localV.Magnitude
				if flat > 1 then
					-- 10-26 유저 "좌우 방향 전환 때 관절이 버벅이다가 돎": 반대 방향끼리 Lerp → Unit 하면 가운데가 0 근처라 다시 옛 방향으로 정규화돼
					--   제자리에 머문다(옆 성분 잡음이 커질 때까지). 좌→우 반전 0.9~1.1초, 앞→뒤는 옆 성분이 없으면 끝내 안 바뀜 [측정 10-26] —
					--   그동안 다리가 옛 방향으로 걷다가 툭 꺾였다. 120° 넘게 꺾이면 바로 새 방향(골반 틀기 legYaw 는 아래에서 부드럽게 따라감)
					local want = localV.Unit
					if st.dir:Dot(want) < -0.5 then st.dir = want
					else st.dir = st.dir:Lerp(want, math.min(1, dt * 10)).Unit end
				end
				if boosting and m ~= mech and flat > 1 then st.boostDir = localV.Unit end
				local dir = st.dir
				local axis = Vector3.new(-dir.Z, 0, dir.X)       -- 진행 방향에 수직인 회전축: 이 축으로 돌리면 다리가 진행 방향으로 나간다
				local fwd = -dir.Z                               -- 1 앞, -1 뒤
				local air = hum.FloorMaterial == Enum.Material.Air and not root.Anchored and not riding
				-- 날개(10-26 23:54 유저 "비행 시 날개가 펼쳐지면"): AELLO 의 WingJointL/R(관절 틀 = 템플릿 축, Transform 0 = 접힘).
				--   공중 0.08초 넘게 = 바깥으로 55° 펼침 · 공중 부스트 = 35° 펼침 + 뒤로 28° 젖힘 · 땅 부스트 = 뒤로 20° · 땅 = 접힘.
				--   설계(aero_r1.md 1절 "상승 = 펼침 55° · 부스트 = 뒤로 28°") 그대로.
				--   빠르기(10-27 00:15 유저 "더 빠릿하게"): 예전 초당 ×6(95% 까지 약 0.5초) + 공중 판정 0.15초 → 시간 상수 1/16초(95% 약 0.19초) + 0.08초.
				--   날개 아래 끝 노즐(WingNozzleL/R, 이름 Flame)은 다리 보조 부스터와 같은 불꽃 — 부스트·상승 때 같이 켜짐
				--   사출(riding) 중엔 air 가 거짓 → 접힘(땅굴·캐터펄트 벽 간격 유지). 날개 관절이 없는 기체는 건너뜀
				if st.WJ == nil then
					st.WJ = { m:FindFirstChild("WingJointL", true) or false, m:FindFirstChild("WingJointR", true) or false }
				end
				if st.WJ[1] or st.WJ[2] then
					st.wingAirT = (air or GR.F.active(m)) and (st.wingAirT or 0) + dt or 0   -- 10-30 라이더킥 = 공중 부스트 날개
					local inAir = st.wingAirT > 0.08
					local wS = inAir and (boosting and 35 or 55) or 0
					local wB = boosting and (inAir and 28 or 20) or 0
					-- 비틂(10-27 W2): 펼칠 때 날개를 제 긴 축으로 돌려 주황 넓은 면이 뒤·위(게임 카메라)를 봄 — 면·카메라 내적 0.55 → 0.89 [계산].
					--   공중 30° · 공중 부스트 15° · 땅 0. 긴 축 = 왼 날개 (0.057, −0.964, 0.262) [실측: 복셀], 오른쪽은 x 거울(각도 부호도 반대)
					local wT = inAir and (boosting and 15 or 30) or 0
					local kw = 1 - math.exp(-dt * 16)   -- 프레임 빠르기와 무관한 지수 따라가기
					st.wingS = (st.wingS or 0) + (wS - (st.wingS or 0)) * kw
					st.wingB = (st.wingB or 0) + (wB - (st.wingB or 0)) * kw
					st.wingT = (st.wingT or 0) + (wT - (st.wingT or 0)) * kw
					if st.WJ[1] then st.WJ[1].Transform = CFrame.Angles(-math.rad(st.wingB), 0, -math.rad(st.wingS)) * CFrame.fromAxisAngle(Vector3.new(0.057, -0.964, 0.262).Unit, math.rad(st.wingT)) end
					if st.WJ[2] then st.WJ[2].Transform = CFrame.Angles(-math.rad(st.wingB), 0, math.rad(st.wingS)) * CFrame.fromAxisAngle(Vector3.new(-0.057, -0.964, 0.262).Unit, -math.rad(st.wingT)) end
				end
				-- 부스트 속도로 걷기 주기를 돌리면 초당 열몇 번 흔들린다: 걷기 속도까지만 반영
				local WSm = CFG.stat(m, "WalkSpeed")   -- 18:24 기체 종류별 이속(공중 프로토 14) — 보폭은 자기 최고 속도 기준
				local walkSpeed = math.min(flat, WSm)
				-- 걸음 크기는 부드럽게 바꾼다(2026-10-25): 이륙 순간 0 으로 툭 끊기면 한 프레임에 자세가 튄다
				local aWant = (air or kb > 0.01 or riding) and 0 or math.clamp(walkSpeed / WSm, 0, 1)   -- 셔틀에 실려 가는 동안·미끄러지는 동안 걷지 않음
				st.aS = (st.aS or aWant) + (aWant - (st.aS or aWant)) * math.min(1, dt * 12)
				local a = st.aS
				local SH, Q = st.SH, st.SH.Q
				local LK = SH.legK                      -- 다리 길이 배율(웅크림·착지·출렁임 깊이)
				st.phase = (st.phase + dt * walkSpeed / CFG.stat(m, "StrideLength") * math.pi * 2 * (1 - kb)) % (math.pi * 2)   -- 10-26 보폭 기체별(중장갑 다리 1.3배)
				local s, c = math.sin(st.phase), math.cos(st.phase)
				-- 발이 땅에 닿는 순간: 왼발은 cos 가 +→-, 오른발은 -→+ 로 바뀔 때 (공중에선 걸음 크기가 줄어드는 중이어도 디딤 없음)
				if a > 0.25 and st.prevC and not air then
					if st.prevC > 0 and c <= 0 then footPlant(m, "FootL", 1); st.impact = 1; st.impactDecay = 3.2
					elseif st.prevC < 0 and c >= 0 then footPlant(m, "FootR", 1); st.impact = 1; st.impactDecay = 3.2 end
				end
				st.prevC = c
				-- 착지는 실제로 0.3초 넘게 떠 있었을 때만 (탑승 직후 고정이 풀리며 잠깐 '공중'으로 잡히는 것은 무시)
				-- 착지 동작(2026-10-25): 체공 시간에 비례해 깊고 길게 웅크렸다 일어난다(아래 "도약·착지 웅크림").
				-- 걸음 충격 st.impact 는 이제 걸음에만 쓴다
				local landed = (not air) and (st.airTime or 0) > 0.3 and not st.wasAnchored
				if landed then
					-- hard: 체공 0.3초 = 0, 1.8초 이상 = 1 (10-25 2차: 기본 점프 체공이 1.18초로 늘어 0.7 → 1.5 로 늘림. 기본 점프 ≈ 0.59)
					local hard = math.clamp(((st.airTime or 0) - 0.3) / 1.5, 0, 1)
					footPlant(m, "FootL", 1.1 + 0.5 * hard); footPlant(m, "FootR", 1.1 + 0.5 * hard)
					st.landT0 = t
					st.landDepth = (LAND_DEPTH + LAND_DEPTH_HARD * hard) * LK
					st.landDur = LAND_DUR + LAND_DUR_HARD * hard
					st.landLean = LAND_LEAN + LAND_LEAN_HARD * hard
					st.jumpT0 = nil
				end
				-- 도약 감지(모든 기체): 땅에서 위로 빠르게 뜨는 순간. 걷다 땅 판정이 깜빡일 때는 위 속도가 거의 0 이라 안 걸린다
				-- 방금까지 웅크리고 있었으면 그 깊이·그때 높이에서 이어서 편다(끊김 없이). 아니면(경사로에서 튀는 등) 펼 것 없음
				if v.Y > 20 and (st.airTime or 0) < 0.1 and t - (st.jumpSeen or -99) > 0.5 and not root.Anchored and not riding then   -- 사출 경사를 오를 땐 뛴 게 아님
					st.jumpSeen = t
					local fromWind = st.windDrop and t - (st.windAt or -99) < 0.15
					st.jumpT0 = t
					st.jumpFrom = fromWind and st.windDrop or 0
					st.jumpY0 = fromWind and st.windY or (root.Position.Y - v.Y * dt)
					st.landT0 = nil
				end
				st.airTime = air and (st.airTime or 0) + dt or 0
				st.wasAnchored = root.Anchored
				st.impact = math.max(0, (st.impact or 0) - dt * (st.impactDecay or 3.2))
				local imp = st.impact
				local me, mkind = meleeElapsed(m)
				do local lm, lk = GR.FE.melee(m); if lm then me, mkind = lm, lk end end   -- 10-30 FELSEN 궁극기 도약 = 도끼 1타 자세를 도약 시각으로(MechFelsen)
				-- 빔사벨 휘두르는 소리(임시): 한 번의 휘두름마다 한 번. 키 = 그 휘두름의 시작 시각
				local swingAt = me and ((meleeSpec(m, mkind) or {}).swingAt or SWING_AT[mkind])   -- 10-27 기체별(도끼 = 들어 올린 뒤)
				if me and swingAt and me >= swingAt then
					local key = (m == mech and meleeLocal[m] and meleeLocal[m].t0) or m:GetAttribute("MeleeAt")
					if key and st.swingKey ~= key then
						st.swingKey = key
						SM.play("SaberSwing", m:FindFirstChild("SaberBlade", true) or m:FindFirstChild("AxeBlade", true) or root)   -- 10-27 FELSEN 은 도끼 날
					end
				end
				local wsMode, wsE = weaponState(m)
				local pitchDeg = (m == mech) and math.deg(pitch) or (m:GetAttribute("AimPitch") or 0)
				local wantAim
				local re = (wsMode ~= "saber" and wsE >= CFG.UnequipTime and not me) and reloadElapsed(m) or nil   -- 라이플 장전 동작
				if re and re >= CFG.gun(m).ReloadTime then re = nil end
				-- 장전 동작표는 라이플(CFG.ReloadTime 1.8초) 기준 → 다른 총은 그 길이에 맞게 늘려 그린다(저격총 2.4초 = 1.33배 느리게)
				if re then re = re * CFG.ReloadTime / CFG.gun(m).ReloadTime end
				-- 줌 = 두 손 사격 자세(2026-10-25). 내 기체는 입력(zoomOn), 남의 기체는 서버 속성 AimZoom. 근접·장전·무기 바꾸는 중엔 풀림
				local zoomWant = ((m == mech) and zoomOn or (m ~= mech and m:GetAttribute("AimZoom") == true))
					and wsMode ~= "saber" and wsE >= CFG.UnequipTime and not me and not re and not CFG.flipPhase(m) and not GR.F.active(m) and not GR.FE.grabbing(m)   -- 10-30 공중제비 중 줌 자세 풀림 · 그랩 중도
				st.zoom = math.clamp((st.zoom or 0) + (zoomWant and dt or -dt) * CFG.ZoomSpeed, 0, 1)
				local kz = sstep(st.zoom)
				local AN = SH.anchor
				local _, anW = CFG.anchorPhase(m)   -- 10-30 SKADI 앵커 꿇은 정도(0~1, 서버 속성 시각 기준이라 모든 화면이 같음)
				if not AN then anW = 0 end
				if me or CFG.flipPhase(m) or GR.F.active(m) or GR.FE.grabbing(m) then wantAim = false   -- 벨 때는 라이플을 내린다 · 10-30 앞차기 공중제비 중도(웅크림 자세가 총을 세워 듦)
				elseif wsMode == "saber" then wantAim = false   -- 빔사벨을 든 동안 라이플은 내린다
				elseif re then wantAim = false               -- 장전 중엔 조준을 푼다
				else
					-- 쏜 뒤 조준 유지 = 그 총의 연사 간격(10-25 저격총 동기화: 1.4초 동안 반동에서 돌아오는 모습을 보여 주고, 다 돌아오면 다음 발)
					-- 라이플은 0.12 라 예전 남의 기체 값 0.25 를 그대로 씀
					local holdAim = math.max(AIM_HOLD_REMOTE, CFG.gun(m).FireInterval * CFG.slowMul(m))
					if m == mech then
						wantAim = firing or aimHeld or shotQueuedAt ~= nil or (t - lastShot) < holdAim
					else
						wantAim = zoomWant or (t - (lastFireAt[m] or -99)) < holdAim
					end
					-- 10-26 손목 그레네이드: 쏠 때 라이플 조준 자세를 잠깐 빌림 → 왼팔뚝(발사관)이 앞을 봄
					if (t - (GR.aimAt[m] or -99)) < GR.AIM_HOLD then wantAim = true end
					if anW > 0 then wantAim = true end   -- 10-30 앵커: 꿇는 동안 총을 견착한 채(두 손 자세)
				end
				st.aim = math.clamp(st.aim + (wantAim and dt * 12 or -dt * 12), 0, 1)   -- 약 0.08초 만에 들고/내림
				local k = st.aim * st.aim * (3 - 2 * st.aim)
				-- 반동(10-25): 쏜 순간 Kick 만큼 튀었다가 연사 간격의 85% 에 걸쳐 제자리로 → 총이 다 돌아온 때 = 다음 발을 쏠 수 있는 때.
				-- 라이플(0.12초)은 예전(초당 9 씩 줄어 약 0.11초)과 거의 같고, 저격총(1.4초)은 약 1.2초에 걸쳐 내려앉는다. 시각 기준이라 프레임과 무관
				local Gk = CFG.gun(m)
				local cyc = math.max(0.1, Gk.FireInterval * CFG.slowMul(m) * 0.85)   -- 10-30 마비 덫: 사격 동작 ×1.5
				local since = t - (lastFireAt[m] or -99)
				local kick = (since >= 0 and since < cyc) and (recoil[m] or Gk.Kick or 1) * (1 - sstep(since / cyc)) or 0

				-- ---------- 평상 자세(걷기/서기/점프) ----------
				local still = 1 - a
				-- 하체를 진행 방향으로 돌려 걷는다: 옆걸음은 골반을 최대 65도 틀어 앞으로 걷고(상체는 허리로 되돌려 정면 유지),
				-- 뒤쪽은 골반을 돌리지 않고 뒷걸음. 다리를 옆으로 벌리는 방식은 가위질처럼 보여서 쓰지 않는다
				local moveAng = math.deg(math.atan2(-dir.X, -dir.Z))   -- 0 앞, -90 오른쪽, 90 왼쪽, ±180 뒤
				local legDir, target = 1, moveAng
				if math.abs(moveAng) > 100 then
					legDir = -1
					target = moveAng > 0 and moveAng - 180 or moveAng + 180
				end
				target = math.clamp(target, -65, 65) * math.clamp(flat / 4, 0, 1)
				if air or kb > 0.01 then target = 0 end
				st.legYaw = (st.legYaw or 0) + (target - (st.legYaw or 0)) * math.min(1, dt * 8)
				local legYaw = st.legYaw
				local swingF = 26 * s * a * legDir
				local kneeL = -(8 + 36 * a * math.max(0, c)) - k * still * 6 - 10 * imp
				local kneeR = -(8 + 36 * a * math.max(0, -c)) - k * still * 4 - 10 * imp
				local hxL = 4 + k * still * 8 + swingF
				local hxR = 4 - k * still * 10 - swingF
				local P = {}
				P.HipL = E(hxL); P.HipR = E(hxR)
				P.KneeL = E(kneeL); P.KneeR = E(kneeR)
				P.AnkleL = E(-0.6 * (hxL + kneeL)); P.AnkleR = E(-0.6 * (hxR + kneeR))
				-- 공중 자세(2026-10-25): 0.1초에 걸쳐 들어가고 0.125초에 걸쳐 빠진다(예전엔 고정 자세로 한 프레임에 툭 바뀜)
				-- 위아래 속도로 고른다: 오를 때 다리 뻗음 → 꼭대기 무릎 당김 → 내려올 때 다리를 내려 착지 준비
				local airWant = air and (st.airTime or 0) > 0.05
				st.airW = math.clamp((st.airW or 0) + (airWant and dt * 10 or -dt * 14), 0, 1)   -- 빠질 땐 0.07초(착지 웅크림이 이어받음)
				if st.airW > 0 then
					local up = math.clamp(v.Y / 35, -1, 1)
					local AP = up >= 0 and blendPose(AIR_TUCK, AIR_RISE, up) or blendPose(AIR_TUCK, AIR_FALL, -up)
					local w = st.airW * st.airW * (3 - 2 * st.airW)
					for n, cf in pairs(AP) do P[n] = P[n]:Lerp(cf, w) end
				end
				local hip = GR.hipParams(st, m, wsMode, k, kz, legYaw)   -- 10-27 허리 사격(개틀링): 몸 전체를 오른쪽으로 틂 — 없으면 nil
				P.Root = CFrame.new(0, (-0.7 * a * (1 - math.abs(c)) - 0.8 * imp + 0.08 * math.sin(t * 1.7)) * LK, 0) * E(0, hip and hip.rootYaw or legYaw, 2.5 * s * a)   -- 두 발이 다 닿을 때 가장 낮고, 디딜 때 툭 꺼지며, 디딘 발 쪽으로 골반이 실림
				-- ---------- 도약·착지 웅크림 (2026-10-25) ----------
				-- drop = 보이는 몸을 내릴 높이(Root), legC = 그중 다리를 접어 흡수할 높이(발이 땅에 남게), lean = 상체 숙임
				local drop, legC, crouchLean = 0, 0, 0
				-- ① 웅크림(힘 모으기): 내 기체는 누른 시각, 남의 기체는 서버 속성 JumpWindAt(서버 시각)
				local we
				if m == mech then
					we = windStartLocal and (t - windStartLocal) or nil
				else
					local wa = m:GetAttribute("JumpWindAt")
					we = wa and (workspace:GetServerTimeNow() - wa) or nil
				end
				st.windDrop = nil
				if we and we >= 0 and not st.jumpT0 and (st.airTime or 0) < 0.1 then
					local W = (m == mech) and windDurLocal or (m:GetAttribute("JumpWindDur") or CFG.JumpWindup)   -- 서서 0.4 / 부스트 점프 0.15
					local hold = (m == mech) and WIND_HOLD_MINE or WIND_HOLD_REMOTE
					local wd, JC = 0, JUMP_CROUCH * LK   -- 10-26: 같은 무릎 굽힘(약 86°)이 되게 다리 길이만큼 깊게
					-- 힘 모으기 곡선(10-25 웅크림 0.4초): 처음 0.15초에 80% 까지 쑥 앉고, 남은 시간 동안 끝까지 천천히 더 눌러 담는다
					-- (0.4초 내내 같은 속도로 가라앉으면 "천천히 앉는 중" 으로만 보여서)
					if we < W then wd = JC * (0.8 * sstep(we / math.min(0.15, W)) + 0.2 * sstep(we / W))
					elseif we < W + hold then wd = JC
					elseif we < W + hold + 0.15 then wd = JC * (1 - sstep((we - W - hold) / 0.15))   -- 끝내 안 뜨면 천천히 일어남
					end
					if wd > 0 then
						drop, legC = wd, wd
						crouchLean = JUMP_LEAN * wd / JC
						st.windDrop, st.windAt, st.windY = wd, t, root.Position.Y
					end
				end
				-- ② 박차기: 뜬 순간부터 JUMP_EXTEND 동안 보이는 몸을 웅크린 깊이에서 실제 위치로 끌어올린다.
				--    다리는 발이 땅에 붙어 있게 접은 양(legC)만큼만 → 약 0.1초에 다 펴지며 발이 떨어짐 [계산 10-25]
				if st.jumpT0 then
					local e = t - st.jumpT0
					local from = st.jumpFrom or 0
					if e >= JUMP_EXTEND or from <= 0 then
						st.jumpT0 = nil
					else
						local rise = math.max(0, root.Position.Y - st.jumpY0)   -- 물리 몸이 이미 올라간 높이
						drop = (rise + from) * (1 - sstep(e / JUMP_EXTEND))
						legC = math.clamp(drop - rise, 0, from)
						crouchLean = JUMP_LEAN * legC / (JUMP_CROUCH * LK)
					end
				end
				if st.landT0 then
					local e = t - st.landT0
					if e >= st.landDur then
						st.landT0 = nil
					else
						local w = e < 0.05 and sstep(e / 0.05) or (e < 0.08 and 1 or 1 - sstep((e - 0.08) / (st.landDur - 0.08)))
						local d = st.landDepth * w
						drop, legC = math.max(drop, d), math.max(legC, d)
						crouchLean = math.max(crouchLean, st.landLean * w)
					end
				end
				-- ③ 캐터펄트(10-25): 준비 땐 반쯤 웅크려 버팀(0.35초에 걸쳐), 사출 순간 0.12초에 깊게 + 앞으로 숙임 → 가속 끝까지 유지
				if riding then
					local w = (lpA < 0) and 0.45 * sstep((lpA + CFG.LaunchPrep) / 0.35) or (0.45 + 0.55 * sstep(lpA / 0.12))
					local dd = (SH.rideDrop or 1.6) * w * LK
					drop, legC = math.max(drop, dd), math.max(legC, dd)
					crouchLean = math.max(crouchLean, ((lpA >= LAa) and 6 or 16) * w)   -- 미끄러질 땐 덜 숙이고 버팀
				end
				if drop > 0 then
					local al, be = crouchAngles(legC, SH.crouch)
					P.Root = CFrame.new(0, -drop, 0) * P.Root
					P.HipL = P.HipL * E(al); P.HipR = P.HipR * E(al)
					P.KneeL = P.KneeL * E(-(al + be)); P.KneeR = P.KneeR * E(-(al + be))
					P.AnkleL = P.AnkleL * E(be); P.AnkleR = P.AnkleR * E(be)
				end
				-- ---------- 10-30 SKADI 앵커: 오른 무릎 꿇기 [sniper/rig/anchor_solve.py · anchor_scan "-28_11"] ----------
				-- 다리 = 키 자세로 섞음 · 골반 = CFG.Anchor.Drop 만큼 내림(카메라도 같은 값만큼 내려감) · 숙임 = 아래 waistX 에(웅크림과 같은 식 → 조준 팔·목이 되돌림)
				if anW > 0 then
					for n, cfA in pairs(AN.J) do P[n] = (P[n] or CFrame.new()):Lerp(cfA, anW) end
					P.Root = CFrame.new(0, -CFG.Anchor.Drop * anW, 0) * P.Root
				end
				-- 숙임은 허리 각(waistX)에 넣는다 → 조준 팔·목이 waistX 를 되돌리는 식이 그대로 먹어 총구가 안 내려간다
				local waistX = -3 + 0.8 * math.sin(t * 1.7) + k * pitchDeg * 0.25 - 5 * a * legDir - 4 * imp - crouchLean + (AN and AN.lean or 0) * anW
				local waistY = (1 - k) * 6 * s * a * legDir + k * (hip and 0 or 15)   -- 허리 사격은 한 손 조준의 왼쪽 비틀기(+15) 대신 hip.torso
				-- 상체 비틀기: 다리는 묵직하게 늦게 돌고, 허리가 조준 방향으로 먼저 돈다(최대 TwistLimit). 남는 각도만 팔이 보정
				local yawOffAll = (m == mech) and aimYawOff or (m:GetAttribute("AimYaw") or 0)
				local twist = math.clamp(yawOffAll, -CFG.TwistLimit, CFG.TwistLimit)
				local armYaw = math.clamp(yawOffAll - twist, -25, 25)
				-- 줌: 상체를 오른쪽으로 ZOOM_TWIST 틀어 왼손이 라이플에 닿게. 한 손 조준의 허리 왼쪽 비틀기(waistY = +15)는 줌 동안 뺀다
				-- (10-25 버그: 그 +15 가 줌 비틀기 −25 를 상쇄해 실제론 −10 만 틀어져 왼손이 라이플에 못 닿고 팔이 다 펴져 있었다 [실측])
				-- 10-29 트는 각은 기체별(SH.zoomTwist — SKADI 35: 팔이 짧고 저격총이 길어서). 없으면 공용 ZOOM_TWIST
				local ZT = SH.zoomTwist or ZOOM_TWIST
				P.Waist = E(waistX, waistY * (1 - kz) - (hip and hip.rootYaw or legYaw) + twist - ZT * kz + (hip and hip.torso or 0))
				P.Neck = E((pitchDeg - waistX) * 0.5 * k, -waistY * (1 - kz) + armYaw + ZT * kz - (hip and hip.torso or 0))   -- 머리는 그만큼 되돌려 정면
				-- 오른팔+라이플: 평상시 허리 높이 로우 레디 / 조준 때 쭉 뻗어 총구 피치 = 조준각
				local elbowAim = 8
				local lowS = Vector3.new(12 + 5 * s * a * legDir, 0, GR.gunAttr(st, m, "ArmOut") or SH.armOut)   -- 10-27 총별 ArmOut(개틀링 20)   -- 10-26 armOut: 쉬는 팔을 스커트 바깥으로(조준 aimS 로 갈수록 0)
				local aimS = Vector3.new(90 + pitchDeg - waistX - elbowAim + kick * 4, -waistY + armYaw, 0)
				local ka = hip and 0 or k   -- 허리 사격 총은 한 손 뻗기로 가지 않고 로우 레디에서 아래 두 손 IK 로 바로 섞음
				local sR = lowS:Lerp(aimS, ka)
				P.ShoulderR = E(sR.X, sR.Y, sR.Z)
				P.ElbowR = E(62 + (elbowAim - 62) * ka)
				P.Grip = CFrame.new()   -- 오른손 손목: 평소엔 0, 라이플을 등에 넣고 꺼낼 때만 돌린다
				-- 왼팔: 평상시 걸음과 반대로 흔듦 / 조준 때 앞으로 내밀어 살짝 굽힘
				local lowL = Vector3.new(4 - 18 * s * a * legDir, 0, -4 - SH.armOut)
				local aimL = Vector3.new(40, -waistY * 0.6, -8)
				local sL = lowL:Lerp(aimL, ka)
				P.ShoulderL = E(sL.X, sL.Y, sL.Z)
				P.ElbowL = E((16 + 8 * a) + (30 - (16 + 8 * a)) * ka)

				-- ---------- 부스트 자세: 진행 방향으로 크게 수그리고 다리는 뒤로 ----------
				if kb > 0 then
					local bd = (m == mech) and st.boostDir or st.boostDir
					-- 하체를 부스트 방향으로 틀고(최대 80도) 그 방향으로 런지. 상체는 허리로 되돌려 정면(조준) 유지
					-- 다리를 옆으로 벌리면 양옆으로 찢어져 보여서 쓰지 않는다. 뒤로 부스트는 몸을 뒤로 젖히고 미끄러진다
					local bAng = math.deg(math.atan2(-bd.X, -bd.Z))
					local back = math.abs(bAng) > 110
					local bYaw = back and 0 or math.clamp(bAng, -80, 80)
					local B = {}
					B.Root = CFrame.new(0, -1.0 * LK, 0) * E(0, bYaw, 0) * E(back and 12 or -18)
					B.Waist = E(back and 4 or -10, -bYaw + twist)
					B.Neck = E(back and -6 or 18)
					if back then
						B.HipL, B.HipR = E(26), E(-8)
						B.KneeL, B.KneeR = E(-30), E(-42)
						B.AnkleL, B.AnkleR = E(-6), E(28)
					else
						B.HipL, B.HipR = E(40), E(-18)
						B.KneeL, B.KneeR = E(-50), E(-30)
						B.AnkleL, B.AnkleR = E(14), E(32)
					end
					-- 오른팔만 사격 자세로: 숙인 각도(앞뒤 성분)를 보정해 총구 피치 = 조준각
					local leanX = back and 16 or (-18 * math.cos(math.rad(bYaw)) - 10)   -- 상체가 앞뒤로 숙여진 정도
					B.ShoulderR = E(75):Lerp(E(90 + pitchDeg - leanX - 8 + kick * 4, armYaw), k)
					B.ElbowR = E(42):Lerp(E(8), k)
					B.ShoulderL = E(-42, 0, -18); B.ElbowL = E(24)
					for n, cfB in pairs(B) do
						P[n] = (P[n] or CFrame.new()):Lerp(cfB, kb)
					end
				end
				-- ---------- 근접: 빔사벨 (왼손). 부스트 자세 위에 덮는다 ----------
				-- 지금 프레임의 평상 자세 몸통(골반·허리·목) + 겨눈 왼팔 = 빔사벨 상태 기준 자세. 몸통을 덮지 않아야 옆걸음 골반 틀기가 산다
				-- 10-27 23:2x 부스트 겨눔: Q.RB 가 있으면 겨눔 왼팔을 부스트 정도만큼 Q.R(어깨에 기댐) → Q.RB(앞으로 듦)로 섞음.
				--   팔 무게는 몸(kb, 약 0.07초에 참)보다 천천히(0.2초 오름 · 0.33초 내림) — 도끼가 어깨에서 앞으로 휙 넘어가지 않게
				local QR = Q.R
				if Q.RB then
					st.boostArm = math.clamp((st.boostArm or 0) + (boosting and dt * 5 or -dt * 3), 0, 1)
					local ka = st.boostArm * st.boostArm * (3 - 2 * st.boostArm)
					if ka > 0.001 then
						QR = { ShoulderL = Q.R.ShoulderL:Lerp(Q.RB.ShoulderL, ka), ElbowL = Q.R.ElbowL:Lerp(Q.RB.ElbowL, ka), SaberGrip = Q.R.SaberGrip:Lerp(Q.RB.SaberGrip, ka) }
					end
				end
				local Rcur = { Root = P.Root, Waist = P.Waist, Neck = P.Neck, ShoulderL = QR.ShoulderL, ElbowL = QR.ElbowL, SaberGrip = QR.SaberGrip }   -- 10-26 겨눔도 기체별(Q.R)
				local handOn, beamOn, trailOn, poseW, poseP = false, false, false, nil, nil
				local twoH = nil   -- 10-27 도끼 두 손(comboPose)
				if me and mkind == "saber" then            -- 라이플 상태 R: 백팩에서 뽑아 베기
					handOn, beamOn, trailOn = me >= 0.10, me >= 0.15 and me < 0.58, me >= 0.15 and me <= 0.43
					poseW, poseP = saberPose(me, Q)
				elseif me and (SLASH_STEP[mkind] or mkind == "ultCharge") then        -- 빔사벨 상태 베기 · 10-30 FELSEN 돌진 궁극기(MechFelsen 이 도끼 두 손 표에 넣은 순서)
					local tw = (meleeSpec(m, mkind) or {}).trail or SLASH_TRAIL[mkind]
					handOn, beamOn, trailOn = true, true, me >= tw[1] and me <= tw[2]
					if SH.combo2h and SH.combo2h.seq[mkind] then   -- 10-27 FELSEN 도끼 두 손 3연격
						poseW, poseP, twoH = comboPose(SH.combo2h, mkind, me, Rcur)
					else
						poseW, poseP = SLASH_POSE[mkind](me, Rcur, Q)
					end
				elseif wsMode == "saber" then               -- 2: 들기 → 겨눔
					handOn, beamOn = wsE >= 0.10, wsE >= 0.15
					poseW, poseP = equipPose(wsE, Rcur, Q)
				elseif wsE < CFG.UnequipTime then           -- 1: 백팩에 꽂기
					handOn, beamOn = wsE < 0.15, wsE < 0.04
					poseW, poseP = unequipPose(wsE, Rcur, Q)
				end
				-- 손 칼: 잡는 순간(0.10)부터 / 빔: 몸 밖으로 나온 뒤(0.15) ~ 0.58 / 끝나면 다시 백팩에 꽂힌 모습
				setSaber(st, m, handOn, beamOn)
				if poseW and poseP then
					for n, cfM in pairs(poseP) do P[n] = (P[n] or CFrame.new()):Lerp(cfM, poseW) end
				end
				-- ---------- 오른손 라이플: 빔사벨 상태면 등에 수납 ----------
				-- 2: 0.12초 동안 등으로 가져가 붙임(그 순간 손 라이플 → 등 라이플) → 빈손을 내림(0.25)
				-- 1: 0.12초 동안 등 라이플을 잡으러 감(그 순간 등 → 손) → 낮게 든 자세로(UnequipTime)
				-- 10-26: 수납 자리·중간 자세는 기체별(SH.rifleStow/rifleMid — 중장갑은 허리 뒤), 빈손은 armOut 만큼 벌림
				local FREE_R = { ShoulderR = E(4 + 18 * s * a * legDir, 0, 4 + SH.armOut), ElbowR = E(16 + 8 * a), Grip = CFrame.new() }
				local R_STOW, R_MID, R_VIA = SH.rifleStow, SH.rifleMid, SH.rifleVia
				if GR.gunPose(st.rifleHand) then R_STOW, R_VIA = GR.gunPose(st.rifleHand).stow, GR.gunPose(st.rifleHand).via end   -- 10-27 총별 수납 자세
				-- 경유 자세가 있으면(중장갑) 수납 자리 ↔ 다른 자세를 반씩 나눠 그 자세를 거친다. 없으면 예전처럼 곧장
				local function viaPose(A, B, x)
					if not R_VIA then return blendPose(A, B, x * x * (3 - 2 * x)) end
					if x < 0.5 then local y = x * 2; return blendPose(A, R_VIA, y * y * (3 - 2 * y)) end
					local y = (x - 0.5) * 2
					return blendPose(R_VIA, B, y * y * (3 - 2 * y))
				end
				local rw, rp, stowed = nil, nil, false
				if wsMode == "saber" then
					if wsE < 0.06 then
						local x = wsE / 0.06
						rw, rp = x * x * (3 - 2 * x), R_MID                  -- 오른쪽 아래로 휘두름
					elseif wsE < 0.12 then
						local x = (wsE - 0.06) / 0.06
						rw, rp = 1, viaPose(R_MID, R_STOW, x)   -- 등(중장갑: 허리 뒤)으로 올려 붙임
					elseif wsE < 0.25 then
						local x = (wsE - 0.12) / 0.13
						rw, rp, stowed = 1, viaPose(R_STOW, FREE_R, x), true
					else
						rw, rp, stowed = 1, FREE_R, true
					end
				elseif wsE < CFG.UnequipTime then
					if wsE < 0.12 then
						local x = wsE / 0.12
						rw, rp, stowed = 1, viaPose(FREE_R, R_STOW, x), true
					elseif wsE < 0.18 then
						local x = (wsE - 0.12) / 0.06
						rw, rp = 1, viaPose(R_STOW, R_MID, x)   -- 떼어 오른쪽 아래로
					else
						local x = math.clamp((wsE - 0.18) / math.max(0.04, CFG.UnequipTime - 0.18), 0, 1)
						rw, rp = 1 - x * x * (3 - 2 * x), R_MID              -- 낮게 든 자세로
					end
				end
				if rw and rp then
					for n, cfR in pairs(rp) do P[n] = (P[n] or CFrame.new()):Lerp(cfR, rw) end
				end
				setRifle(st, m, stowed)
				-- ---------- 재장전: 라이플 상태에서만 그린다(장전 중 무장을 바꾸면 취소되어 ReloadUntil 이 사라짐) ----------
				if Gk.SpinUp then GR.ammoBox(st, m, re, root) end   -- 10-27 16:56 등 탄약통 장전(장전 아니면 제자리로)
				if re and Gk.SpinUp then
					-- 10-27 개틀링(탄띠 T2) 장전 = 등 탄약통 교체(유저 16:56 "A", 통 움직임은 GR.ammoBox). 손은 로우 레디:
					--   총구를 10° 내렸다가 철컥(2.3초) 때 살짝 튀고, 끝나기 0.3초에 걸쳐 돌아옴. 라이플 장전(탄창 뽑아 떨굼)은 안 씀
					local RT = Gk.ReloadTime
					local w = math.min(1, re / 0.25) * math.clamp((RT - re) / 0.3, 0, 1)
					local ck = (re > 2.3 and re < 2.5) and math.sin((re - 2.3) / 0.2 * math.pi) or 0
					P.Grip = (P.Grip or CFrame.new()) * E(-10 * w + 6 * ck)
				elseif re then
					local w, Pr = reloadPose(re, SH)
					for n, cfR in pairs(Pr) do P[n] = (P[n] or CFrame.new()):Lerp(cfR, w) end
					if re >= 0.42 and re < 0.9 and t - (st.magDropT or -99) > CFG.ReloadTime then
						st.magDropT = t; dropMag(m)
					end
				end
				trailOn = trailOn and beamOn
				if st.trailOn ~= trailOn then
					st.trailOn = trailOn
					local sp = st.saberParts
					if sp and sp.trail then sp.trail.Enabled = trailOn end
				end
				if me and mkind == "punch" then
					local w, Pm = punchPose(me, Q)
					for n, cfM in pairs(Pm) do P[n] = (P[n] or CFrame.new()):Lerp(cfM, w) end
				end
				-- 10-30 SKADI 앞차기: 다리·왼팔은 키 자세로 섞고, 골반 내림·허리 젖힘은 더함(골반 방향·허리 비틀기는 평상 자세 그대로)
				if me and mkind == "kick" and SH.kick then
					local w, KP = kickPose(me, SH.kick)
					for n, cfK in pairs(KP.J) do P[n] = (P[n] or CFrame.new()):Lerp(cfK, w) end
					P.Root = CFrame.new(0, KP.root * w, 0) * (P.Root or CFrame.new())
					P.Waist = (P.Waist or CFrame.new()) * E(KP.lean * w)
				end
				-- ---------- 10-27 도끼 두 손: 오른손을 도끼 막대(왼손 위)에 — 매 프레임 IK(무게·자리·pole = comboPose) ----------
				if twoH and twoH.w > 0.001 then
					local okA, AP = pcall(axeRightHand, J, root, P, twoH)
					if okA and AP then P.ShoulderR, P.ElbowR = AP.ShoulderR, AP.ElbowR end
				end
				-- ---------- 허리 사격: 두 손 받쳐 쏘기 (10-27 자세 C, 위 GR.hipParams) ----------
				-- 줌과 같은 IK(twoHandPose)에 손 자리만 HipHand/HipLeft, 손 자리 틀은 몸과 함께 HipTurn 만큼 돎. 총은 조준 방향 그대로
				if hip and hip.kh > 0.001 then
					local yawOffH = (m == mech) and aimYawOff or (m:GetAttribute("AimYaw") or 0)
					local aimDirH = (root.CFrame.Rotation * CFrame.Angles(0, math.rad(yawOffH), 0) * CFrame.Angles(math.rad(pitchDeg), 0, 0)).LookVector
					local okH, ZP = pcall(twoHandPose, J, root, P, aimDirH, kick, SH, hip.opt)
					if okH and ZP then
						for n, cfZ in pairs(ZP) do P[n] = (P[n] or CFrame.new()):Lerp(cfZ, hip.kh) end
					end
				end
				-- ---------- 줌: 두 손 사격 자세 (2026-10-25) ----------
				-- 몸통(Root·Waist)이 다 정해진 뒤에 팔을 IK 로 덮는다. 움찔은 그 위에 얹혀 몸통째 흔들린다
				if kz > 0.001 then
					local yawOff = (m == mech) and aimYawOff or (m:GetAttribute("AimYaw") or 0)
					local aimDir = (root.CFrame.Rotation * CFrame.Angles(0, math.rad(yawOff), 0) * CFrame.Angles(math.rad(pitchDeg), 0, 0)).LookVector
					local ok, Z = pcall(twoHandPose, J, root, P, aimDir, kick, SH)
					if ok and Z then
						for n, cfZ in pairs(Z) do P[n] = (P[n] or CFrame.new()):Lerp(cfZ, kz) end
					end
				end
				-- ---------- 맞았을 때 움찔 (연출만, 조작은 막지 않음) ----------
				local fl = flinch[m]
				if fl then
					local fe = t - fl.t0
					if fe >= 0.35 then
						flinch[m] = nil
					else
						local f = math.sin(fe / 0.35 * math.pi)
						local push = root.CFrame:VectorToObjectSpace(fl.dir)   -- 밀린 방향(모델 기준, +Z = 뒤)
						P.Waist = (P.Waist or CFrame.new()) * E(14 * f * math.clamp(push.Z, -1, 1))
						P.Neck = (P.Neck or CFrame.new()) * E(10 * f)
						P.Root = (P.Root or CFrame.new()) * CFrame.new(0, -0.5 * f, 0)
					end
				end
				-- ---------- 10-30 SKADI 앞차기 공중제비(유저 10:48): 진행 k = 서버 속성 FlipAt 기준(모든 화면 같음) ----------
				-- 웅크림(SH.flip.J)을 w 만큼 섞고, 웅크린 몸 무게중심(SH.flip.center, Root 관절 틀) 둘레로 뒤로 θ 회전. 이동(포물선)은 조종 화면 GR.flipDrive
				-- 어깨 장갑·스커트(아래)가 바뀐 허벅지·어깨를 따라가게 그 앞에서 [sniper/rig/flip_check.py: 공중 최저 3.7 · 다리 ↔ 몸·총·팔 겹침 0]
				do
					local fk = SH.flip and CFG.flipPhase(m)
					if fk then
						local fw, fth = PO.flipPose(fk)
						for n, cf in pairs(SH.flip.J) do P[n] = (P[n] or CFrame.new()):Lerp(cf, fw) end
						P.Root = (P.Root or CFrame.new()) * CFrame.new(SH.flip.center) * CFrame.Angles(fth, 0, 0) * CFrame.new(-SH.flip.center)
					end
				end
				GR.F.pose(m, P)   -- 10-30 FALCO 라이더킥 자세(모든 화면 · 어깨 장갑·스커트가 따라가게 그 앞)
				GR.FE.pose(m, P, pitchDeg)   -- 10-30 FELSEN 돌진 궁극기 달리는 다리(같은 이유로 그 앞) · 그랩 전용 자세(조준 위아래)
				-- ---------- 중장갑: 어깨 장갑·스커트가 팔·허벅지를 따라감 (10-26, SHAPES.pad / skirt — 다른 기체는 없음) ----------
				-- 모든 자세가 정해진 맨 끝에서(조준 IK·장전·근접이 어깨 각을 바꾼 뒤)
				if SH.pad then
					P.PadL = padTransform(P.ShoulderL or CFrame.new(), 1, SH.pad)
					P.PadR = padTransform(P.ShoulderR or CFrame.new(), -1, SH.pad)
				end
				if SH.skirt then
					local sk = SH.skirt
					for _, sd in ipairs({ "L", "R" }) do
						local rx, _, rz = (P["Hip" .. sd] or CFrame.new()):ToEulerAnglesYXZ()
						local hx, hz = math.deg(rx), math.deg(rz)                                    -- 엉덩이 앞으로 든 각 · 옆으로 든 각(10-30 FALCO 옆차기)
						local out = (sd == "L") and -1 or 1                                          -- 바깥으로 들기: 왼쪽 Z− / 오른쪽 Z+
						P["SkirtJointF" .. sd] = E(sk.front * math.max(0, hx))
						P["SkirtJointS" .. sd] = E(sk.side * hx, 0, out * sk.sideOut * math.max(0, hx) + (sk.sideZ or 0) * hz)
					end
				end
				-- 10-29 SKADI 머리 조준경: 줌(우클릭) 정도만큼 앞으로 펼침(유저 21:27 "렌즈 전개는 조준 사격할 때"). 관절 속성 Slide = 다 펼친 이동(관절 틀)
				local sj = J.ScopeJoint
				if sj then
					local sl = sj:GetAttribute("Slide")
					if sl then P.ScopeJoint = CFrame.new(sl * kz) end
				end
				GR.rifleForm(m, st, J, P, anW, dt)   -- 10-30 SKADI 저격총 변형(날개 = 앵커 · 덮개·총구 = 궁극기). 없는 기체는 바로 돌아감
				for _, n in ipairs(JOINTS) do
					local j = J[n]
					if j and P[n] then j.Transform = P[n] end
				end
			elseif st.thrust then
				setThrusters(st, false)
			end
		end
	end
end
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	for _, m in ipairs(animTargets()) do
		if m:IsDescendantOf(workspace) then
			local ok, err = pcall(animOne, m, t, dt)
			if not ok and not animErrLogged[m] then
				animErrLogged[m] = true
				warn(("[MechAnim] %s 애니 오류(이 기체만 건너뜀, 경고는 기체마다 한 번): %s"):format(m:GetFullName(), tostring(err)))
			end
		end
	end
end)

-- ================= 출격 사출 연출 — 모든 화면: 철문·셔틀·경광등·불꽃·소리 (2026-10-25 16:24 지하 땅굴) =================
-- 사출 중인 기체(속성 LaunchAt)를 보고 각 화면이 직접 그린다. 문·셔틀·경광등은 서버 파트를 이 화면에서만 바꿈(충돌 없음 · 복제 안 됨)
local lfx = setmetatable({}, { __mode = "k" })   -- [기체] = { key = LaunchAt, lock, fire, door, exit, sparkT, skidT }
local siteFx = {}   -- 17:39: 사출장 이름 → 연출 상태 { model, doors, shuttle, beacons, doorOpen, doorShown, shuttleS, shuttleShown, beaconOn }
local function sparkBurst(base, back, upv, n, life, speed)
	for _ = 1, n do
		local v = back * (speed * (0.5 + math.random())) + upv * (2 + math.random() * 5) + Vector3.new((math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 6)
		local sp = fxPart(Color3.fromRGB(255, 170 + math.random(0, 60), 60), Vector3.new(0.25, 0.25, 0.9), CFrame.lookAt(base, base + v))
		TweenService:Create(sp, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.lookAt(base + v * life, base + v * (life + 0.05)), Transparency = 1 }):Play()
		Debris:AddItem(sp, life + 0.02)
	end
end
RunService.RenderStepped:Connect(function(dt)
	local nowS = workspace:GetServerTimeNow()
	for _, site in ipairs(LAUNCH_SITES) do   -- 사출장마다 따로(땅굴 · 캐터펄트). 기체는 속성 LaunchSite 로 자기 사출장에만 잡힘
		local P = launcherPath(site)
		if P then
			local L = P.model
			local S = siteFx[site]
			if not S or S.model ~= L then
				S = { model = L, doorOpen = 0, doorShown = -1, shuttleS = 0, shuttleShown = -1, beaconOn = nil }
				siteFx[site] = S
			end
			if not S.doors then   -- 문·셔틀·경광등은 처음 볼 때 한 번(스트리밍으로 늦게 들어오면 들어온 뒤에)
				local df = L:FindFirstChild("Doors")
				local list = {}
				for _, d in ipairs(df and df:GetChildren() or {}) do
					if d:IsA("Model") and d.PrimaryPart then table.insert(list, { m = d, rest = d:GetPivot(), off = d:GetAttribute("OpenOffset") or Vector3.zero }) end
				end
				if #list > 0 then S.doors = list end
			end
			if not S.shuttle then
				local sh = L:FindFirstChild("Shuttle")
				if sh and sh.PrimaryPart then
					local f, tt, nn = pathFrame(P, 0)
					S.shuttle = { m = sh, off = CFrame.lookAt(f, f + tt, nn):Inverse() * sh:GetPivot() }
				end
			end
			if not S.beacons then
				S.beacons = {}
				for _, d in ipairs(L:GetDescendants()) do if d:IsA("BasePart") and d:GetAttribute("Beacon") then table.insert(S.beacons, d) end end
			end
			local RT, PREP, SK = P.runTime, CFG.LaunchPrep, CFG.LaunchSkidTime
			local glide = P.mode == "glide"
			local wantOpen, followS, holdEnd, alarm = false, nil, false, false
			for _, m in ipairs(CollectionService:GetTagged("Mech")) do
				local la = m:GetAttribute("LaunchAt")
				local root = type(la) == "number" and (m:GetAttribute("LaunchSite") or "UndergroundLaunch") == site and m:FindFirstChild("HumanoidRootPart")
				if root then
					local p = nowS - la
					if p > -PREP - 0.5 and p < RT + 6 then
						local fx = lfx[m]
						if not fx or fx.key ~= la then fx = { key = la }; lfx[m] = fx end
						local fd = 11.6 - (m:GetAttribute("RootHeight") or 11.6)   -- 10-26: 발 높이 보정(아래 −11 류는 프로토 기준, 중장갑은 3.45 더 아래)
						if p > P.doorAt and p < RT + 3 then wantOpen = true end      -- 문: 땅굴 = 사출 직후(0.2) / 캐터펄트 = 준비 중(-1.4) 열기 시작, 다 나간 뒤 닫힘
						if p < RT + 2 then alarm = true end                         -- 경광등: 탄 때부터 나간 뒤 2초까지 깜빡임
						if p >= RT - 0.5 and p < RT + 2.5 then holdEnd = true end    -- 셔틀: 끝(문 앞)에서 잠시 머무름
						if not fx.lock then
							fx.lock = true
							if p < -PREP + 0.6 then SM.play("CatapultLock", root) end   -- 셔틀이 발을 물음(탄 직후)
						end
						if p >= 0 and not fx.fire then
							fx.fire = true
							if p < 0.3 then   -- 늦게 본 화면(입장 등)은 지난 소리를 내지 않음
								SM.play("CatapultFire", root); SM.play("CatapultRoar", root)
								local feet = root.CFrame * Vector3.new(0, -11 + fd, 0)
								dust(feet, 8, 2.6)
								local f = fxPart(Color3.fromRGB(255, 200, 120), Vector3.one * 4, CFrame.new(feet), Enum.PartType.Ball)
								TweenService:Create(f, TweenInfo.new(0.2), { Size = Vector3.one * 14, Transparency = 1 }):Play()
								Debris:AddItem(f, 0.22)
								if m == mech then shake = math.max(shake, 1.0) end
							end
						end
						if p >= P.doorAt and not fx.door then
							fx.door = true
							local df = L:FindFirstChild("Doors")
							local dl = df and df:FindFirstChild("DoorL")
							if p < P.doorAt + 0.4 then SM.play("HangarDoor", (dl and dl.PrimaryPart) or root) end   -- 문 열림(쿵)
						end
						if p >= 0 and p < RT then
							-- 주행: 셔틀이 발밑을 따라감(기체 위치를 경로에 사영 — 남의 화면에서도 기체와 붙어 있음) + 레일 불꽃
							followS = pathProject(P, root.Position)
							if m == mech then shake = math.max(shake, 0.25) end
							fx.sparkT = (fx.sparkT or 0) + dt
							local guard = 0
							while fx.sparkT > 0.02 and guard < 3 do
								fx.sparkT -= 0.02; guard += 1
								local cf = root.CFrame
								for _, sx in ipairs({ -2, 2 }) do sparkBurst(cf * Vector3.new(sx, -11.4 + fd, 1.5), -cf.LookVector, cf.UpVector, 1, 0.22, 10) end
							end
							if guard >= 3 then fx.sparkT = 0 end
						end
						if p >= RT and not fx.exit then
							fx.exit = true
							if p < RT + 0.4 then
								if glide then
									SM.play("CatapultExit", root)   -- 캐터펄트: 출구 이탈 + 부스터 점화(공중이라 먼지·긁는 소리 없음)
									if m == mech then shake = math.max(shake, 0.6) end
								else
									SM.play("CatapultExit", root); SM.play("LaunchSkid", root)   -- 땅굴: 문 밖 착지 쿵 + 먼지 + 긁는 소리
									dust(root.CFrame * Vector3.new(0, -11 + fd, 0), 10, 3)
									if m == mech then shake = math.max(shake, 0.8) end
								end
							end
						end
						if not glide and p >= RT and p < RT + SK then
							-- 미끄러짐(땅굴): 두 발이 땅을 긁음(불꽃 + 먼지). 속도가 줄수록 덜 튐 — launchDrive 와 같은 곡선(LaunchSkidPow)
							local k = (1 - (p - RT) / SK) ^ (CFG.LaunchSkidPow or 1)
							fx.skidT = (fx.skidT or 0) + dt
							local guard = 0
							while fx.skidT > 0.03 and guard < 3 do
								fx.skidT -= 0.03; guard += 1
								local cf = root.CFrame
								for _, sx in ipairs({ -2, 2 }) do sparkBurst(cf * Vector3.new(sx, -11.5 + fd, 0), -cf.LookVector, Vector3.yAxis, math.max(1, math.floor(3 * k)), 0.25, 14 * k) end
								if math.random() < 0.5 * k then dust(cf * Vector3.new(0, -11.5 + fd, 2), 2, 2.2) end
							end
							if guard >= 3 then fx.skidT = 0 end
							if m == mech then shake = math.max(shake, 0.3 * k) end
						end
					end
				end
			end
			-- 문: 사출장 속성 DoorOpenTime 에 열리고 DoorCloseTime 에 닫힘. 바뀔 때만 옮김
			S.doorOpen = math.clamp(S.doorOpen + (wantOpen and dt / P.doorOpenT or -dt / P.doorCloseT), 0, 1)
			if S.doors and S.doorOpen ~= S.doorShown then
				S.doorShown = S.doorOpen
				local w = S.doorOpen * S.doorOpen * (3 - 2 * S.doorOpen)
				for _, d in ipairs(S.doors) do if d.m.Parent then d.m:PivotTo(d.rest + d.off * w) end end
			end
			-- 경광등: 사출 중 0.25초마다 깜빡, 아니면 어둡게
			local on = alarm and (math.floor(os.clock() * 4) % 2 == 0) or false
			if on ~= S.beaconOn then
				S.beaconOn = on
				for _, b in ipairs(S.beacons) do if b.Parent then b.Transparency = on and 0 or 0.75 end end
			end
			-- 셔틀: 주행 중엔 기체 발밑, 끝(stopS)에서 멈춤 → 잠시 뒤 ShuttleReturn(초당)으로 출발점에 돌아감
			if S.shuttle and S.shuttle.m.Parent then
				if followS then
					S.shuttleS = math.min(followS, P.stopS)
				elseif not holdEnd then
					S.shuttleS = math.max(0, S.shuttleS - dt * P.shuttleRet)
				end
				if S.shuttleS ~= S.shuttleShown then
					S.shuttleShown = S.shuttleS
					local f, tt, nn = pathFrame(P, S.shuttleS)
					S.shuttle.m:PivotTo(CFrame.lookAt(f, f + tt, nn) * S.shuttle.off)
				end
			end
		end
	end
end)