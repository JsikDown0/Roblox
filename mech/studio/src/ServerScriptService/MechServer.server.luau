-- MechServer: 메카 생성·탑승/하차(캐릭터 교체)·사격 판정·부스트 에너지, 시험장(표적·피해 발판)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Proto = RS:WaitForChild("MechProto")
local CFG = require(Proto:WaitForChild("MechConfig"))
local Remotes = Proto:WaitForChild("Remotes")
local Template = Proto:WaitForChild("MechTemplate")
local Range = workspace:WaitForChild("MechTestRange")
local BayPad = Range:WaitForChild("BayPad")
-- 출격장 두 곳(10-25 17:39 유저 "사출이 총 두 종류"): 지상형(MechTemplate) = 지하 땅굴(BayPad · UndergroundLaunch),
-- 공중형 Aero(AeroTemplate) = 공중 캐터펄트(AeroBayPad · Catapult). 기체는 보급될 때 속성 Bay 를 받고, 탈 때 LaunchSite = 사출장 이름.
-- 사출 연출·경로는 클라(MechClient)가 사출장 모델 속성으로 그린다(코드 하나, 속성만 다름)
local AeroTemplate = Proto:FindFirstChild("AeroTemplate")
local AeroPad = Range:FindFirstChild("AeroBayPad")
-- 10-26: 땅굴 출격대 기체 = CFG.GroundTemplate(기본 중장갑 HeavyTemplate). 없으면 옛 지상 프로토(MechTemplate)
local GroundTemplate = Proto:FindFirstChild(CFG.GroundTemplate or "MechTemplate") or Template
local BAYS = { { name = "Ground", pad = BayPad, template = GroundTemplate, site = "UndergroundLaunch" } }
if AeroTemplate and AeroPad then
	table.insert(BAYS, { name = "Aero", pad = AeroPad, template = AeroTemplate, site = "Catapult" })
end
-- 10-28 HORKOS(ST-01 · Rodin 몸, 유저 "실제로 타볼수있게"): 땅 위 보급대 HorkosBayPad. 사출장 없음(site = nil) → 기체 앞에서 BoardPrompt 로 타고 그 자리에서 바로 조종
local HorkosTemplate = Proto:FindFirstChild("HorkosTemplate")
local HorkosPad = Range:FindFirstChild("HorkosBayPad")
if HorkosTemplate and HorkosPad then
	table.insert(BAYS, { name = "Horkos", pad = HorkosPad, template = HorkosTemplate, site = nil })
end
-- 10-29 SKADI(LT-01 · SNIPER, 유저 "스카디도 스튜디오에 가져올까?" → "응. 하자."): HORKOS 와 같은 땅 위 보급대 SkadiBayPad(동쪽 35). 사출 없음 → 기체 앞에서 바로 탐
local SkadiTemplate = Proto:FindFirstChild("SkadiTemplate")
local SkadiPad = Range:FindFirstChild("SkadiBayPad")
if SkadiTemplate and SkadiPad then
	table.insert(BAYS, { name = "Skadi", pad = SkadiPad, template = SkadiTemplate, site = nil })
end
local function bayAt(pos)   -- 이 위치에서 24 안의 출발점(없으면 nil)
	for _, b in ipairs(BAYS) do
		if (pos - b.pad.Position).Magnitude < 24 then return b end
	end
	return nil
end

local pilotStore = ServerStorage:FindFirstChild("MechPilots") or Instance.new("Folder")
pilotStore.Name = "MechPilots"; pilotStore.Parent = ServerStorage

local lastFire, lastBoost = {}, {}
local spawnPending = false

-- 소리는 SoundManager 로만(2026-10-25). 서버에서 SM.play 하면 모든 클라가 각자 낸다
local SM = require(Proto:WaitForChild("SoundManager"))
-- 충돌 그룹(10-25 13:26): Mech = 기체 몸통 HRP(템플릿에 박음) / MechDebris = 버린 미사일 포드. 둘은 서로 안 부딪힘.
--   에디트에서 등록해 플레이스에 저장돼 있지만, 없을 때를 대비해 여기서도 확인
do
	local PS = game:GetService("PhysicsService")
	pcall(function()
		for _, g in ipairs({ "Mech", "MechDebris" }) do
			if not PS:IsCollisionGroupRegistered(g) then PS:RegisterCollisionGroup(g) end
		end
		PS:CollisionGroupSetCollidable("Mech", "MechDebris", false)
	end)
end
-- 피해 대상 판단은 MechDamage.canDamage 하나로(2026-10-25). 라이플·빔사벨·미사일·적 AI 공용
local Dmg = require(game:GetService("ServerScriptService"):WaitForChild("MechDamage"))

local function pilotMech(player)
	local c = player.Character
	if c and c:GetAttribute("IsMech") and c:GetAttribute("Pilot") == player.UserId then return c end
	return nil
end

local function groundY(pos, ignore)
	local p = RaycastParams.new(); p.FilterType = Enum.RaycastFilterType.Exclude; p.FilterDescendantsInstances = ignore
	local r = workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -200, 0), p)
	return r and r.Position.Y or pos.Y
end

local function park(mech)
	mech:SetAttribute("Pilot", nil)
	mech:SetAttribute("Weapon", nil); mech:SetAttribute("WeaponAt", nil)   -- 내리면 라이플 상태로
	mech:SetAttribute("AimYaw", 0); mech:SetAttribute("AimPitch", 0)   -- 내린 메카가 비튼 채로 서 있지 않게
	mech:SetAttribute("AimZoom", nil)                                   -- 두 손 사격 자세로 굳어 있지 않게
	mech:SetAttribute("LaunchAt", nil)                                  -- 캐터펄트 사출 표시 끔(10-25)
	mech:SetAttribute("LaunchSite", nil)
	mech:SetAttribute("BoostHold", nil); mech:SetAttribute("BoostHoldAir", nil); mech:SetAttribute("OverheatUntil", nil); mech:SetAttribute("Climb", nil)   -- 지속 부스트 끔
	mech:SetAttribute("GunSpinAt", nil)                                  -- 10-27 개틀링 회전 끔(내린 기체 총열이 계속 돌지 않게)
	mech:SetAttribute("AnchorAt", nil); mech:SetAttribute("AnchorRiseAt", nil)   -- 10-30 SKADI: 내리면 앵커 풂(꿇은 채 주차되지 않게, 쿨은 남김)
	mech:SetAttribute("UltStart", nil); mech:SetAttribute("UltEnd", nil); mech:SetAttribute("UltKeep", nil)   -- 10-30 궁극기 중 내리면 끝(게이지는 이미 씀)
	mech:SetAttribute("RKAt", nil); mech:SetAttribute("RKHitAt", nil); mech:SetAttribute("RKStopAt", nil); mech:SetAttribute("RKCarry", nil)
	mech:SetAttribute("LeapAt", nil)   -- 10-30 FELSEN 도약 중 내리면 끝(착지 피해 없음)
	mech:SetAttribute("GrabWindAt", nil); mech:SetAttribute("GrabAt", nil); mech:SetAttribute("GrabHitAt", nil); mech:SetAttribute("GrabEnd", nil)   -- 10-30 그랩 중 내리면 끝
	mech:SetAttribute("ChargeAt", nil); mech:SetAttribute("ChargeHitAt", nil)   -- 10-30 FELSEN 돌진 중 내리면 끝   -- 10-30 FALCO 라이더킥 중 내리면 끝(쿨 RKReadyAt 은 남김)
	mech:SetAttribute("FlipAt", nil)   -- 10-30 앞차기 공중제비 중 내리면 끝(주차 기체가 잠긴 채 남지 않게)
	local root = mech:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
		local prompt = root:FindFirstChild("BoardPrompt")
		if prompt then prompt.Enabled = true end
	end
end

local function exitMech(player, mech)
	local root = mech.HumanoidRootPart
	local holder = pilotStore:FindFirstChild(tostring(player.UserId))
	local body = holder and holder:FindFirstChildWhichIsA("Model")
	local spot = (root.CFrame * CFrame.new(-12, 0, 0)).Position
	local y = groundY(spot, { mech })
	park(mech)
	if body then
		body.Parent = workspace
		body:PivotTo(CFrame.new(spot.X, y + 3.2, spot.Z) * root.CFrame.Rotation)
		player.Character = body
		holder:Destroy()
	else
		player:LoadCharacter()
	end
end

local function board(player, mech)
	if mech:GetAttribute("Pilot") then return end
	local hum = mech:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local char = player.Character
	if not char or char:GetAttribute("IsMech") then return end
	local chum = char:FindFirstChildOfClass("Humanoid")
	if not chum or chum.Health <= 0 then return end
	local root = mech.HumanoidRootPart
	mech:SetAttribute("Pilot", player.UserId)
	mech:SetAttribute("Energy", CFG.stat(mech, "MaxEnergy"))   -- 18:24 기체 종류별(공중 프로토 150)
	root.BoardPrompt.Enabled = false
	local old = pilotStore:FindFirstChild(tostring(player.UserId)); if old then old:Destroy() end
	local holder = Instance.new("Folder"); holder.Name = tostring(player.UserId); holder.Parent = pilotStore
	root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero
	-- 캐터펄트(10-25): 출발점(보급대)에 서 있던 기체면 사출 — 가속이 시작될 서버 시각을 박는다(캐릭터 교체보다 먼저 = 클라가 탈 때 이미 보임).
	-- 준비 → 가속 → 출구 이탈은 조종 클라가 몬다(네트워크 주인). 다른 화면은 이 값으로 자세·셔틀·불꽃·소리를 그린다
	local bay = bayAt(root.Position)   -- 17:39: 땅굴 출발점이면 땅굴 사출, Aero 출발점이면 공중 캐터펄트 사출
	mech:SetAttribute("LaunchSite", bay and bay.site or nil)
	mech:SetAttribute("LaunchAt", (bay and bay.site) and (workspace:GetServerTimeNow() + CFG.LaunchPrep) or nil)   -- 10-28 사출장 없는 보급대(HORKOS)는 사출 안 함
	root.Anchored = false
	player.Character = mech                 -- 이제 메카가 플레이어 캐릭터: 피격·이동·카메라 기준이 전부 메카
	root:SetNetworkOwner(player)
	char.Parent = holder                    -- 원래 몸은 보관(맞지 않음)
end

local function spawnMech(bay)
	bay = bay or BAYS[1]
	local count = #CollectionService:GetTagged("Mech")
	if count >= CFG.MaxMechs then return end
	local m = bay.template:Clone()
	m.Name = "Mech"
	m:SetAttribute("Bay", bay.name)
	local root = m.HumanoidRootPart
	local top = bay.pad.Position + Vector3.new(0, bay.pad.Size.Y / 2, 0)
	m:PivotTo(CFrame.new(top + Vector3.new(0, m:GetAttribute("RootHeight") or 5, 0)))
	root.Anchored = true
	local hum = m:FindFirstChildOfClass("Humanoid")
	hum.MaxHealth = CFG.MaxHealth; hum.Health = CFG.MaxHealth
	hum.WalkSpeed = CFG.stat(m, "WalkSpeed"); hum.UseJumpPower = true; hum.JumpPower = CFG.JumpPower   -- 18:24 공중 프로토 14
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	m:SetAttribute("Energy", CFG.stat(m, "MaxEnergy"))
	m:SetAttribute("Ammo", CFG.gun(m).MagSize)   -- 10-27 그 기체 총의 탄창(예전 CFG.MagSize = 라이플 30 고정이라 개틀링·저격총이 30 으로 나왔음)
	m:SetAttribute("MissilePods", m:FindFirstChild("MissilePodL") ~= nil or m:FindFirstChild("MissilePodR") ~= nil)   -- 새 기체만 미사일 포드를 달고 나온다
	if m:GetAttribute("SubWeapon") == "Grenade" then   -- 10-26 AELLO 손목 그레네이드: 2발 들고 나옴(ReadyAt 0 = 기다릴 것 없음)
		m:SetAttribute("GrenadeAmmo", CFG.GrenadeAmmo); m:SetAttribute("GrenadeReadyAt", 0)
	elseif m:GetAttribute("SubWeapon") == "Mine" then   -- 10-30 SKADI 센서 지뢰: 2개 들고 나옴
		m:SetAttribute("MineAmmo", CFG.Mine.Ammo); m:SetAttribute("MineReadyAt", 0)
	end
	m.Parent = workspace
	CollectionService:AddTag(m, "Mech")
	root.BoardPrompt.Triggered:Connect(function(player) board(player, m) end)
	hum.Died:Connect(function()
		local pid = m:GetAttribute("Pilot")
		local e = Instance.new("Explosion"); e.BlastPressure = 0; e.BlastRadius = 0; e.DestroyJointRadiusPercent = 0
		e.Position = root.Position; e.Parent = workspace
		SM.play("MechDestroy", root.Position)   -- 기체 파괴음
		if pid then
			local h = pilotStore:FindFirstChild(tostring(pid)); if h then h:Destroy() end
		end
		task.delay(2.5, function() if m.Parent then m:Destroy() end end)
	end)
end

-- 보급: 출발점(BAYS 마다) 위에 빈 메카가 없으면 잠시 뒤 새로 놓는다
local spawnPendingBay = {}
local function freeAt(bay)   -- 이 출발점 24 안에 빈(조종사 없는, 적 아닌) 기체가 있나
	for _, m in ipairs(CollectionService:GetTagged("Mech")) do
		if m.Parent and not m:GetAttribute("EnemyMech") and not m:GetAttribute("Pilot") and m:FindFirstChild("HumanoidRootPart")
			and (m.HumanoidRootPart.Position - bay.pad.Position).Magnitude < 24 then return m end
	end
	return nil
end
task.spawn(function()
	while true do
		-- 적 메카(EnemyMech)는 빈 보급 기체로 세지 않는다 (패드 근처로 걸어오면 보급이 막히던 문제)
		local own = 0
		for _, m in ipairs(CollectionService:GetTagged("Mech")) do
			if not m:GetAttribute("EnemyMech") then own += 1 end
		end
		for _, bay in ipairs(BAYS) do
			-- 사출(10-25): 이 사출장에서 사출 중인 기체가 다 빠져나가기 전엔 출발점에 새 기체를 놓지 않는다(겹침 방지)
			local launchBusy = false
			for _, m in ipairs(CollectionService:GetTagged("Mech")) do
				local la = m:GetAttribute("LaunchAt")
				if la and (m:GetAttribute("LaunchSite") or "UndergroundLaunch") == bay.site
					and workspace:GetServerTimeNow() < la + CFG.LaunchServerGuard then launchBusy = true end
			end
			if not freeAt(bay) and not spawnPendingBay[bay] and not launchBusy then
				spawnPendingBay[bay] = true
				task.delay(own == 0 and 0 or CFG.RespawnDelay, function()
					spawnPendingBay[bay] = nil
					if not freeAt(bay) then spawnMech(bay) end
				end)
			end
		end
		task.wait(1)
	end
end)

Remotes.MechExit.OnServerEvent:Connect(function(player)
	local m = pilotMech(player); if not m then return end
	local la = m:GetAttribute("LaunchAt")
	if la and workspace:GetServerTimeNow() < la + CFG.LaunchServerGuard then return end   -- 사출 중엔 못 내림(땅굴·경사로 안에 사람이 남음)
	exitMech(player, m)
end)

-- 출격 단말기(10-25): 땅의 Range.LaunchTerminal 안 ProximityPrompt 중 속성 CatapultBoard 가 있는 것 → 출발점의 빈 기체에 태움(= 자동 사출)
-- 출발점이 공중 터널 안(바닥 높이 36)이라 기체의 BoardPrompt 에는 걸어서 닿을 수 없다
-- 17:39: 단말기가 둘(LaunchTerminal = 땅굴 Bay "Ground" · AeroLaunchTerminal = 캐터펄트 Bay "Aero"). 프롬프트 속성 Bay 로 출발점을 고른다(없으면 Ground)
do
	local bayByName = {}
	for _, b in ipairs(BAYS) do bayByName[b.name] = b end
	for _, pp in ipairs(Range:GetDescendants()) do
		if pp:IsA("ProximityPrompt") and pp:GetAttribute("CatapultBoard") then
			pp.Triggered:Connect(function(player)
				if pilotMech(player) then return end
				local bay = bayByName[pp:GetAttribute("Bay") or "Ground"]
				local m = bay and freeAt(bay)
				if m then board(player, m) end
			end)
		end
	end
end

Remotes.MechAim.OnServerEvent:Connect(function(player, p, y, z)
	if typeof(p) ~= "number" or p ~= p then return end
	local m = pilotMech(player); if not m then return end
	m:SetAttribute("AimPitch", math.clamp(p, -60, 70))
	if typeof(y) == "number" and y == y then m:SetAttribute("AimYaw", math.clamp(y, -180, 180)) end
	m:SetAttribute("AimZoom", (z == true) or nil)   -- 줌(2026-10-25): 다른 화면도 두 손 사격 자세로 그린다
end)

-- ================= 장탄·재장전 =================
-- 속성 Ammo(남은 발) + ReloadUntil(장전 끝나는 서버 시각, 장전 중일 때만). 각 화면이 이걸로 HUD·장전 동작을 그린다.
-- 무장을 바꾸면 ReloadUntil 을 지워 장전 취소(MechWeapon). 끝내는 예약은 이 상주 스크립트 소유라 회수되지 않고,
-- 시각이 일치할 때만 채운다(취소·새 장전이면 그냥 지나감)
-- 탄창·장전 시간은 주무기별(CFG.gun(m), 10-25 저격총). 총을 바꾸면 ReloadUntil 을 지워 이 예약도 그냥 지나간다
local function startReload(m)
	if not m.Parent or m:GetAttribute("ReloadUntil") then return end
	if CFG.ultPhase(m) then return end   -- 10-30 궁극기(탄창 무한) 동안 장전 안 함 — 끝나면 탄창이 가득 참
	local G = CFG.gun(m)
	if G.Heat then return end   -- 10-27 과열 총(개틀링)은 장전 없음
	if (m:GetAttribute("Ammo") or G.MagSize) >= G.MagSize then return end
	local sl = CFG.slowMul(m)   -- 10-30 마비 덫: 시작할 때 둔화 배율로 끝까지(화면은 속성 ReloadSlow 로 같은 배율)
	local untilT = workspace:GetServerTimeNow() + G.ReloadTime * sl
	m:SetAttribute("ReloadSlow", sl ~= 1 and sl or nil)
	m:SetAttribute("ReloadUntil", untilT)
	task.delay(G.ReloadTime * sl, function()
		if m.Parent and m:GetAttribute("ReloadUntil") == untilT then   -- 그 사이 다른 장전으로 바뀌지 않았을 때만
			m:SetAttribute("Ammo", G.MagSize)
			m:SetAttribute("ReloadUntil", nil)
		end
	end)
end
-- 도약 웅크림 시작 알림(2026-10-25): 실제 점프는 조종 클라 물리. 다른 화면도 웅크림을 그리도록 속성 JumpWindAt(서버 시각)만 남긴다
local lastJumpMsg = {}
Remotes.MechJump.OnServerEvent:Connect(function(player, dur)
	local m = pilotMech(player); if not m then return end
	local now = os.clock()
	if lastJumpMsg[player] and now - lastJumpMsg[player] < 0.12 then return end
	lastJumpMsg[player] = now
	-- 웅크림 길이(서서 0.4 / 부스트 점프 0.15)도 같이 → 다른 화면이 같은 빠르기로 웅크림
	m:SetAttribute("JumpWindDur", (typeof(dur) == "number" and dur == dur) and math.clamp(dur, 0.05, 0.8) or CFG.JumpWindup)
	m:SetAttribute("JumpWindAt", workspace:GetServerTimeNow())
end)
Players.PlayerRemoving:Connect(function(p) lastJumpMsg[p] = nil end)

Remotes.MechReload.OnServerEvent:Connect(function(player)
	local m = pilotMech(player); if m then startReload(m) end
end)

-- 10-30 총구가 루트에서 갈 수 있는 가장 먼 거리: 총 파트 → 루트까지 관절 자리 사이 길이를 더함(삼각 부등식 — 관절을 어떻게 돌려도 이보다 멀 수 없음)
--   + 10(루트 관절 이동: 앵커 꿇기 Drop 8.15 · 웅크림). 기체마다 한 번 재서 기억 [에디트: SKADI 31.65 · HORKOS 27.61 · FALCO 27.67 · FELSEN 36.56]
local reachCache = setmetatable({}, { __mode = "k" })
local function gunReach(m)
	local r = reachCache[m]
	if r then return r end
	local root, rifle = m:FindFirstChild("HumanoidRootPart"), m:FindFirstChild("Rifle")
	local mz = rifle and rifle:FindFirstChild("Muzzle")
	if not (root and mz) then return 0 end
	local motors = {}
	for _, d in ipairs(m:GetDescendants()) do if d:IsA("Motor6D") and d.Part1 then motors[d.Part1] = d end end
	local sum, prev, part = 0, mz.WorldPosition, rifle
	for _ = 1, 10 do
		if part == root then break end
		local j = motors[part]
		if not (j and j.Part0) then break end
		local pivot = (j.Part0.CFrame * j.C0).Position
		sum += (prev - pivot).Magnitude
		prev, part = pivot, j.Part0
	end
	r = sum + (prev - root.Position).Magnitude + 10
	reachCache[m] = r
	return r
end

Remotes.MechFire.OnServerEvent:Connect(function(player, target, from)
	if typeof(target) ~= "Vector3" then return end
	local m = pilotMech(player); if not m then return end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	local now = os.clock()
	-- 빔사벨을 들고 있거나 라이플로 바꾸는 중(백팩에 꽂는 동작)에는 쏠 수 없다
	if (m:GetAttribute("Weapon") or "rifle") ~= "rifle" then return end
	local wat = m:GetAttribute("WeaponAt")
	if wat and workspace:GetServerTimeNow() - wat < CFG.UnequipTime * 0.8 then return end
	local G = CFG.gun(m)   -- 주무기 수치(라이플/저격총)
	local slF = CFG.slowMul(m)   -- 10-30 마비 덫: 간격 ×1.5. 막 걸린 0.3초는 봐줌(화면이 아직 모를 수 있음 — 쏜 줄 알았는데 안 나가는 일 없게)
	if slF ~= 1 and workspace:GetServerTimeNow() - (m:GetAttribute("SlowAt") or 0) < 0.3 then slF = 1 end
	if lastFire[player] and now - lastFire[player] < G.FireInterval * slF * 0.8 then return end
	if CFG.stunned(m) then return end   -- 10-27 작살 그랩에 걸려 끌려오는 중·경직 중
	local aph = CFG.anchorPhase(m)
	if aph and aph ~= "on" then return end   -- 10-30 SKADI 앵커: 꿇거나 일어나는 중엔 못 쏨
	local nowS = workspace:GetServerTimeNow()
	local ammo
	if G.SpinUp then
		-- 10-27 회전 총(개틀링): 돌기 시작(속성 GunSpinAt, MechSpin) 뒤 SpinUp 이 지나야 나감
		local sp = m:GetAttribute("GunSpinAt")
		if not sp or nowS - sp < G.SpinUp * 0.7 then return end   -- 0.7 = 요청 지연 여유
	end
	if G.Heat then
		-- 과열 총(Heat = true): 탄창 대신 과열, 강제 냉각 중엔 못 쏨. 10-27 16:16 개틀링은 탄창으로 바뀌어 지금 쓰는 총 없음
		local _, locked = CFG.gunHeat(m, nowS)
		if locked then return end
	elseif G.NoAmmo then
		-- 10-30 SKADI 궁극기 사격 창(Modes.Ult): 탄창 무한 — 탄을 안 세고 장전도 안 기다림(시작할 때 장전 취소)
	else
		-- 장전 중이거나 탄창이 비었으면 못 쏜다(비었으면 장전 시작)
		if m:GetAttribute("ReloadUntil") then return end
		ammo = m:GetAttribute("Ammo") or G.MagSize
		if ammo <= 0 then startReload(m); return end
	end
	local rifle = m:FindFirstChild("Rifle")
	local mz = rifle and rifle:FindFirstChild("Muzzle")
	if not mz then return end
	lastFire[player] = now
	if G.Heat or G.HeatLook then   -- 10-27 HeatLook = 총열 색만(규칙 없음): 같은 속성을 적되 강제 냉각은 Heat 총만
		local h = CFG.gunHeat(m, nowS) + G.HeatPerShot
		if h >= 1 then h = 1; if G.Heat then m:SetAttribute("GunLockUntil", nowS + G.OverheatTime) end end   -- 끝까지 참 → 강제 냉각
		m:SetAttribute("GunHeat", h); m:SetAttribute("GunHeatAt", nowS)
	end
	if not G.Heat and not G.NoAmmo then
		m:SetAttribute("Ammo", ammo - 1)
		if ammo - 1 <= 0 then startReload(m) end
	end
	local muzzle = mz.WorldPosition
	-- 10-30 화면이 보낸 총구(든 팔·두 손 견착·앵커 꿇기 — 애니는 화면에서만)를 믿을 수 있으면 그 자리에서 쏨. 손목 그레네이드(GrenadeMuzzleTrust)와 같은 형태.
	--   서버 팔은 쉬는 자세(총을 아래로 늘어뜨림)라 총구가 화면과 다르고, SKADI 는 땅속 3.1 [에디트 FK: 루트 아래 20.75 · 루트 높이 17.65] →
	--   발밑 바닥이 두꺼우면 바로 앞 엄폐물을 땅속으로 지나가고, 얇은 바닥이면 바닥 밑면에 막힘. 꿇으면 8.15 더 내려감.
	--   믿는 거리 = gunReach(관절 사슬 길이 합 — 어떤 자세에서도 총구가 루트에서 이보다 멀 수 없음) + 루트 이동 여유 + 속도 지연. 벗어나면 예전대로 서버 총구
	local root0 = m.HumanoidRootPart
	if typeof(from) == "Vector3" and from == from and (from - root0.Position).Magnitude <= gunReach(m) + root0.AssemblyLinearVelocity.Magnitude * 0.15 then
		muzzle = from
	end
	local d = target - muzzle
	if d.Magnitude < 1 then return end
	local look = m.HumanoidRootPart.CFrame.LookVector
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude > 0.5 then
		local cosA = math.clamp(Vector3.new(look.X, 0, look.Z).Unit:Dot(flat.Unit), -1, 1)
		if math.deg(math.acos(cosA)) > (CFG.FireArc or 25) + 20 then return end   -- 등 뒤로는 못 쏜다
	end
	d = d.Unit * G.Range
	local p = RaycastParams.new(); p.FilterType = Enum.RaycastFilterType.Exclude; p.FilterDescendantsInstances = { m }
	local hit = workspace:Raycast(muzzle, d, p)
	local hitPos = hit and hit.Position or (muzzle + d)
	local hitHum = false   -- 기체·표적을 맞혔나 → 다른 클라가 적중음을 낸다
	if hit then
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		while model do
			local h = model:FindFirstChildOfClass("Humanoid")
			if h then
				if Dmg.canDamage(m, model) then   -- 아군이면 막힐 뿐 피해·적중음 없음
					Dmg.hurt(m, model, h, G.Damage)   -- 10-30 궁극기 게이지도 여기서 셈
					hitHum = true
				end
				break
			end
			model = model:FindFirstAncestorOfClass("Model")
		end
	end
	Remotes.MechFX:FireAllClients("fire", m, muzzle, hitPos, player.UserId, hit and hit.Normal or Vector3.yAxis, hitHum)
end)

Remotes.MechBoost.OnServerEvent:Connect(function(player, kind, on, inAir, climb)
	local m = pilotMech(player); if not m then return end
	-- 지속 부스트(2026-10-25): 클라가 누르고 있는 동안 "hold" 켬/끔. 소모·과열은 아래 에너지 루프가 한다
	-- 속성 BoostHold(+ BoostHoldAir) → 다른 화면도 부스트 자세·불꽃
	if kind == "hold" then
		if on == true then
			if (m:GetAttribute("Energy") or 0) <= 0 or (m:GetAttribute("OverheatUntil") or 0) > workspace:GetServerTimeNow() or CFG.stunned(m) or CFG.anchorPhase(m) then   -- 10-27 그랩 경직 중 · 10-30 앵커 중엔 못 켬
				m:SetAttribute("BoostHold", nil); m:SetAttribute("BoostHoldAir", nil); m:SetAttribute("Climb", nil)
				return
			end
			m:SetAttribute("BoostHold", true)
			m:SetAttribute("BoostHoldAir", (inAir == true) or nil)
			m:SetAttribute("Climb", (climb == true and CFG.stat(m, "Climb") == true) or nil)   -- 18:24 상승(공중 프로토만): 소모는 지속 부스트와 같은 통로
		else
			m:SetAttribute("BoostHold", nil); m:SetAttribute("BoostHoldAir", nil); m:SetAttribute("Climb", nil)
		end
		return
	end
	local now = os.clock()
	if CFG.stunned(m) then return end   -- 10-27 그랩 경직 중 대시 못 함
	if CFG.anchorPhase(m) then return end   -- 10-30 앵커 중 대시 못 함
	if lastBoost[player] and now - lastBoost[player] < CFG.BoostCooldown * 0.8 then return end
	local e = m:GetAttribute("Energy") or 0
	if e < CFG.BoostCost then return end
	lastBoost[player] = now
	m:SetAttribute("Energy", e - CFG.BoostCost)
	m:SetAttribute("BoostUntil", workspace:GetServerTimeNow() + CFG.BoostTime)
end)

-- ================= 미사일 컨테이너 (G, 2026-10-25) =================
-- 종아리 양쪽 포드(MissilePodL/R, 관마다 Attachment "Tube1~3"). 누르면 6발 일괄 사출 → 포드를 버림. 속성 MissilePods = 아직 있음.
-- 판정은 서버가 날린다(약한 유도 — 초당 MissileTurnRate 도까지만 꺾임). 모습은 각 화면이 같은 식으로 날려 그리고(MechFX "missile"),
-- 터진 곳·맞았는지는 서버가 알려 준다(MechFX "missileBoom"). 예약은 이 상주 스크립트의 Heartbeat 가 소유
local Debris = game:GetService("Debris")
local function podTubes(m)
	local list = {}
	local pods = { m:FindFirstChild("MissilePodL"), m:FindFirstChild("MissilePodR") }
	for i = 1, 3 do   -- 왼1, 오1, 왼2, 오2 … 번갈아 나가게
		for _, pod in ipairs(pods) do
			local a = pod and pod:FindFirstChild("Tube" .. i)
			if a then table.insert(list, { att = a, side = (pod.Name == "MissilePodL") and -1 or 1, row = i }) end
		end
	end
	return list, pods
end
local function bodyCenter(model)
	local r = model:FindFirstChild("HumanoidRootPart")
	return r and (r.Position + Vector3.new(0, 3, 0)) or nil   -- 골반(HRP) 보다 조금 위 = 몸통 가운데쯤
end
local function humanoidModelOf(inst)   -- 맞은 파트에서 위로 올라가며 Humanoid 를 가진 모델(클래스로 묻지 않음)
	local p = inst
	while p and p ~= workspace do
		if p:FindFirstChildOfClass("Humanoid") then return p end
		p = p.Parent
	end
	return nil
end
local function jettisonPods(m, pods)
	local root = m:FindFirstChild("HumanoidRootPart")
	for _, pod in ipairs(pods) do
		if pod and pod.Parent then
			for _, d in ipairs(m:GetDescendants()) do
				if (d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D")) and (d.Part0 == pod or d.Part1 == pod) then d:Destroy() end
			end
			for _, d in ipairs(pod:GetDescendants()) do
				if d:IsA("WeldConstraint") or d:IsA("Weld") then d:Destroy() end
			end
			local side = (pod.Name == "MissilePodL") and -1 or 1   -- 몸 기준 왼쪽 = −X
			local out = root and root.CFrame:VectorToWorldSpace(Vector3.new(side, 0, 0)) or Vector3.xAxis
			pod.Parent = workspace
			-- 버린 포드는 떼는 즉시 기체와 안 부딪힌다(10-25 13:26 유저 요청): 충돌 그룹 MechDebris ↔ Mech(기체 몸통 HRP) 끔.
			--   바닥(Default)과는 부딪혀야 땅 위에 떨어져 굴러간다(CanCollide 를 아예 끄면 바닥을 뚫고 빠짐)
			pod.CollisionGroup = "MechDebris"
			pod.Massless = false; pod.CanCollide = true; pod.CanQuery = false; pod.CanTouch = false
			pcall(function() pod:SetNetworkOwner(nil) end)
			pod.AssemblyLinearVelocity = out * 18 + Vector3.new(0, 12, 0)
			pod.AssemblyAngularVelocity = Vector3.new(math.random() * 6 - 3, math.random() * 6 - 3, side * 5)
			Debris:AddItem(pod, 8)
		end
	end
	SM.play("PodDrop", root and root.Position or Vector3.zero)
end
-- 근접 스플래시(10-25): 터진 곳 근처(몸 가운데 기준)의 "쏜 나 + 다칠 수 있는 기체". 아군은 안 맞는다(트롤 방지 —
--   아군 발밑에 쏴서 팀을 깎는 일 없음). direct = 그 발에 직접 맞은 기체 → 그 발의 스플래시는 또 받지 않는다.
--   연료가 다해 소멸할 땐 부르지 않는다.
--   적: MissileSplashRadius 안 MissileSplashDamage → 0 (직선)
--   나(13:01 수정): MissileSelfRadius 안 = 직격 피해 × MissileSelfMul(0.9) 전부, 그 바깥 MissileSelfFade 에 걸쳐 0
--     → 코앞에서 쏘면 적이 받는 만큼(직격 70)의 90% 를 나도 받는다. 적이 맞았는지와 무관하게 터진 거리로만
-- 반환: 적(나 말고)에게 스플래시 피해를 줬나
local function missileSplash(m, at, direct)
	local R, D = CFG.MissileSplashRadius or 0, CFG.MissileSplashDamage or 0
	local sR, sFade = CFG.MissileSelfRadius or 0, CFG.MissileSelfFade or 0
	local sFull = CFG.MissileDamage * (CFG.MissileSelfMul or 0)
	local hurtEnemy = false
	for _, o in ipairs(CollectionService:GetTagged("Mech")) do
		if o ~= direct and o.Parent and (o == m or Dmg.canDamage(m, o)) then
			local c = bodyCenter(o)
			local h = o:FindFirstChildOfClass("Humanoid")
			if c and h and h.Health > 0 then
				local d = (c - at).Magnitude
				local dmg
				if o == m then
					local w = (d <= sR) and 1 or (sFade > 0 and math.max(0, 1 - (d - sR) / sFade) or 0)
					dmg = math.floor(sFull * w + 0.5)
				else
					dmg = (R > 0) and math.floor(D * (1 - d / R) + 0.5) or 0
				end
				if dmg > 0 then
					Dmg.hurt(m, o, h, dmg)   -- 10-30 자기 피해(o == m)는 게이지 안 셈
					if o ~= m then hurtEnemy = true end
				end
			end
		end
	end
	return hurtEnemy
end
local salvoSeq = 0
-- tubesOverride(10-26 AELLO 손목 발사관): { { att, pos(총구 자리), side, row } } — 주면 포드 대신 이 관에서 쏘고 버릴 포드가 없음
local function fireSalvo(m, aimPoint, target, tubesOverride)
	local tubes, pods
	if tubesOverride then tubes, pods = tubesOverride, {} else tubes, pods = podTubes(m) end
	if #tubes == 0 then return end
	local root = m:FindFirstChild("HumanoidRootPart"); if not root then return end
	local now0 = workspace:GetServerTimeNow()
	salvoSeq += 1
	local salvo = "s" .. salvoSeq   -- 일제 사격 번호(클라가 미사일 모습을 짝지음). GetDebugId 는 플러그인 전용이라 못 씀
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { m, pods[1], pods[2] }   -- 자기 기체·버려지는 포드엔 안 맞음
	local missiles, send = {}, {}
	-- 조준 사격(10-25 13:15, 유저 "A로 가자"): 관마다 조준점으로 곧게 → 6발이 조준점에서 모인다(라이플처럼 조준한 곳으로).
	--   부채꼴·위로 튐·거리 비례(12:20)는 없앰 — 유도가 초당 10° 로 약해서 부채꼴로 퍼지면 다시 모이지 못한다.
	--   target(쏘는 순간 조준점 근처 적, 핸들러가 고름)이 있으면 날아가며 그 몸 가운데로 아주 약하게 꺾일 뿐
	local arm = CFG.MissileArm or 0
	for i, tb in ipairs(tubes) do
		local from = tb.pos or tb.att.WorldPosition
		local base = aimPoint - from
		local dir = base.Magnitude > 1 and base.Unit or root.CFrame.LookVector
		local launch = now0 + (i - 1) * CFG.MissileStagger
		missiles[i] = { pos = from, dir = dir, launch = launch, alive = true, arm = arm }
		send[i] = { p = from, d = dir, t = launch, a = arm }
	end
	Remotes.MechFX:FireAllClients("missile", m, salvo, target, send)
	local lastLaunch = now0 + (#tubes - 1) * CFG.MissileStagger
	local dropped = tubesOverride ~= nil   -- 손목 발사관은 버릴 포드가 없음(끝 조건 alive == 0 and dropped 그대로)
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		local now = workspace:GetServerTimeNow()
		if not dropped and now >= lastLaunch + CFG.MissileJettisonDelay then
			dropped = true
			jettisonPods(m, pods)
		end
		local alive = 0
		for i, ms in ipairs(missiles) do
			if ms.alive then
				alive += 1
				if now >= ms.launch then
					local age = now - ms.launch
					if age > CFG.MissileLife then
						ms.alive = false
						Remotes.MechFX:FireAllClients("missileBoom", m, salvo, i, ms.pos, false, true)   -- 연료 다 씀: 공중에서 소멸
					else
						-- 유도는 ms.arm ~ ms.arm + MissileGuideTime 동안만(10-25). 그 뒤엔 마지막 방향으로 직진 — 클라 stepMissile 과 같은 식
						if age > ms.arm and age < ms.arm + (CFG.MissileGuideTime or math.huge) and target and target.Parent then
							local c = bodyCenter(target)
							if c then
								local want = c - ms.pos
								if want.Magnitude > 0.1 then
									want = want.Unit
									local ang = math.acos(math.clamp(ms.dir:Dot(want), -1, 1))
									if ang > 1e-4 then
										local k = math.min(1, math.rad(CFG.MissileTurnRate) * dt / ang)
										ms.dir = ms.dir:Lerp(want, k).Unit
									end
								end
							end
						end
						local step = ms.dir * CFG.MissileSpeed * dt
						local hit = workspace:Raycast(ms.pos, step, rp)
						local boomAt, victim = nil, nil
						if hit then
							boomAt = hit.Position
							victim = humanoidModelOf(hit.Instance)
							ms.pos = hit.Position
						else
							ms.pos += step
							-- 근접 신관: 다칠 수 있는 기체(나·아군 제외) 몸 가운데와 가까우면. 아군 옆에선 안 터지고 지나간다
							if age > 0.1 then
								for _, o in ipairs(CollectionService:GetTagged("Mech")) do
									if o.Parent and Dmg.canDamage(m, o) then
										local c = bodyCenter(o)
										if c and (c - ms.pos).Magnitude <= CFG.MissileProximity then boomAt, victim = ms.pos, o; break end
									end
								end
							end
						end
						if boomAt then
							ms.alive = false
							local h = victim and victim:FindFirstChildOfClass("Humanoid")
							local dealt = false
							local direct = nil
							if h and h.Health > 0 and Dmg.canDamage(m, victim) then Dmg.hurt(m, victim, h, CFG.MissileDamage); dealt = true; direct = victim end
							if missileSplash(m, boomAt, direct) then dealt = true end   -- 나 자신 + 적. 직격 대상은 제외
							Remotes.MechFX:FireAllClients("missileBoom", m, salvo, i, boomAt, dealt, false)
						end
					end
				end
			end
		end
		if alive == 0 and dropped then conn:Disconnect() end
	end)
end
-- 유도 대상 고르기(10-25 13:15): 쏘는 순간 "카메라 → 조준점" 방향에서 MissileSeekCone 안, 사거리(속도×수명) 안의
--   다칠 수 있는 기체 중 각이 가장 작은 하나. 클라는 대상을 보내지 않는다(예전 록온은 클라가 골랐다).
--   카메라 위치는 클라가 보내되 기체 HRP 에서 60 안일 때만 믿는다(카메라 거리 30·어깨 6.5 → 보통 31 안팎). 아니면 머리 위로 대신
local function missileSeekTarget(m, camPos, aimPoint)
	local d0 = aimPoint - camPos
	if d0.Magnitude < 1 then return nil end
	local look = d0.Unit
	local best, bestA = nil, math.rad(CFG.MissileSeekCone or 0)
	local maxD = CFG.MissileSpeed * CFG.MissileLife
	for _, o in ipairs(CollectionService:GetTagged("Mech")) do
		if o.Parent and Dmg.canDamage(m, o) then
			local h = o:FindFirstChildOfClass("Humanoid")
			local c = bodyCenter(o)
			if h and h.Health > 0 and c then
				local d = c - camPos
				if d.Magnitude > 1 and d.Magnitude < maxD then
					local a = math.acos(math.clamp(look:Dot(d.Unit), -1, 1))
					if a < bestA then best, bestA = o, a end
				end
			end
		end
	end
	return best
end
-- ================= 손목 그레네이드 런처 (G, 2026-10-26 AELLO) =================
-- 기체 속성 SubWeapon == "Grenade"(템플릿에 박음)면 G 가 미사일 대신 이것. 왼아래팔 발사관 Attachment "GrenadeTube1/2".
-- 남은 발 = CFG.grenadeAmmo(기체, 서버 시각): 2 → 1 → 0(이때 GrenadeReadyAt = 지금 + GrenadeRefill) → 그 시각이 지나면 저절로 2
-- 비행 = 미사일 그대로(23:54 유저 "포물선 말고 내가 생각했던 건 미사일"): 한 발씩 fireSalvo 에 이 관 하나를 넘김 →
--   곧게 + 약한 유도(쏘는 순간 조준점 근처 적, missileSeekTarget) · 근접 신관 · 피해·스플래시·화면(MechFX "missile") 모두 미사일 것.
--   (23:27 의 곡사·자체 탄도는 걷어냄 — 백업 ServerStorage._MissileWingEnergy_before_20261026)
local GRN = { last = setmetatable({}, { __mode = "k" }) }
function GRN.fire(m, aimPoint, muzzle, target)
	local root = m:FindFirstChild("HumanoidRootPart"); if not root then return end
	local now0 = workspace:GetServerTimeNow()
	local n = CFG.grenadeAmmo(m, now0)
	if n <= 0 then return end
	local k = (CFG.GrenadeAmmo - n) % 2 + 1                 -- 1발째 관 1, 2발째 관 2
	local arm = m:FindFirstChild("LowerArmL")
	local tube = arm and (arm:FindFirstChild("GrenadeTube" .. k) or arm:FindFirstChild("GrenadeTube1"))
	local from = tube and tube.WorldPosition or (root.Position + Vector3.new(0, 3, 0))
	-- 화면의 든 팔 총구(애니는 화면에서만 — 서버 팔은 쉬는 자세)를 서버 총구에서 GrenadeMuzzleTrust 안일 때만 믿음
	if typeof(muzzle) == "Vector3" and muzzle == muzzle and (muzzle - from).Magnitude < CFG.GrenadeMuzzleTrust then from = muzzle end
	n -= 1
	m:SetAttribute("GrenadeAmmo", n)
	if n <= 0 then m:SetAttribute("GrenadeReadyAt", now0 + CFG.GrenadeRefill) end
	fireSalvo(m, aimPoint, target, { { att = tube, pos = from, side = -1, row = k } })
end
Remotes.MechMissile.OnServerEvent:Connect(function(player, aimPoint, camPos, muzzle)
	local m = pilotMech(player); if not m then return end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	if CFG.stunned(m) then return end   -- 10-27 그랩 경직 중
	if m:GetAttribute("SubWeapon") == "Grenade" then   -- 10-26 AELLO: 미사일 포드 없음 → 손목 그레네이드
		if typeof(aimPoint) ~= "Vector3" or aimPoint ~= aimPoint then return end
		local r = m:FindFirstChild("HumanoidRootPart"); if not r then return end
		if typeof(camPos) ~= "Vector3" or camPos ~= camPos or (camPos - r.Position).Magnitude > 60 then
			camPos = r.Position + Vector3.new(0, 10, 0)   -- 아래 미사일 경로와 같은 검사
		end
		local t = os.clock()
		if GRN.last[m] and t - GRN.last[m] < CFG.GrenadeInterval * 0.8 then return end
		GRN.last[m] = t
		GRN.fire(m, aimPoint, muzzle, missileSeekTarget(m, camPos, aimPoint))
		return
	end
	if m:GetAttribute("MissilePods") ~= true then return end   -- 출격마다 한 번
	if typeof(aimPoint) ~= "Vector3" or aimPoint ~= aimPoint then return end
	local root = m:FindFirstChild("HumanoidRootPart"); if not root then return end
	if typeof(camPos) ~= "Vector3" or camPos ~= camPos or (camPos - root.Position).Magnitude > 60 then
		camPos = root.Position + Vector3.new(0, 10, 0)
	end
	m:SetAttribute("MissilePods", false)
	fireSalvo(m, aimPoint, missileSeekTarget(m, camPos, aimPoint))
end)

-- ================= 개틀링 회전 (10-27 FELSEN, 과열 총) =================
-- 방아쇠를 당기면 클라가 true, 놓으면 false → 속성 GunSpinAt(돌기 시작한 서버 시각, 멈추면 nil).
-- 서버 사격 검사(SpinUp 지나야 나감)와 다른 화면의 총열 회전이 이 속성을 씀
Remotes.MechSpin.OnServerEvent:Connect(function(player, on)
	local m = pilotMech(player); if not m then return end
	if not CFG.gun(m).SpinUp then return end   -- 10-27 회전 총이면(과열 여부와 무관)
	local gph = CFG.grabPhase(m)   -- 10-31 그랩으로 당기는 동안 미리 돎(도착하자마자 쏘게) — 그랩 잠금 중이어도 허용
	if on == true and (not CFG.stunned(m) or gph == "reel" or gph == "recover") then
		if not m:GetAttribute("GunSpinAt") then m:SetAttribute("GunSpinAt", workspace:GetServerTimeNow()) end
	else
		m:SetAttribute("GunSpinAt", nil)
	end
end)

-- ================= 시그니처: 작살 그랩 (C, 10-27 FELSEN — 유저 "시그니처가 작살 그랩" · 왼손목) =================
-- 기체 속성 Signature == "Grab". 작살은 서버가 곧게 날림(CFG.Grab.Speed · Range, 유도 없음, 벽에 막힘,
--   다칠 수 있는 기체 몸 가운데와 HitRadius 안이면 맞음 — 미사일 근접 신관과 같은 방식). 맞든 안 맞든 쿨(속성 GrabReadyAt, 서버 시각).
-- 맞으면 상대 속성 PullTo(내 앞 Front 스터드 땅 위 서 있는 높이)·PullFace·PullAt·PullTime + StunUntil(끌려오는 시간 + Stun):
--   조종하는 클라가 그 길로 직접 끌려감(PlatformStand, 출격 사출과 같은 방식 — 몸 물리는 조종 클라 것이라서).
--   조종사 없는 기체(적 AI·주차)는 서버가 끌어옴. 경직 중엔 위 원격들(사격·부스트·대시·미사일·근접·무장)이 다 거절.
-- 화면: MechFX "grab"(쏨: 출발점·방향) / "grabEnd"(맞음·빗나감: 끝 자리·맞은 기체)
local GRAB = { seq = 0 }
-- 끌림 시작(10-30 GRAB.pull 에서 떼어 냄 — SKADI 앞차기 넉백도 같은 길): 상대를 to 로 pullTime 초에 옮기고(얼굴 face), 끝나고 stun 초 경직.
--   조종사 있음 = 그 클라가 GR.drive 로 직접(속성) / 없음 = 서버가 끌어옴. 속성·순서는 옛 GRAB.pull 그대로
-- 10-30 SKADI 앵커 풀기(C 다시 · 끌림 · 하차): 지금부터 일어남(Rise) → 그 뒤 쿨. 꿇고 있지 않으면 아무것도 안 함
local function anchorRelease(m, now)
	local ph = CFG.anchorPhase(m, now)
	if ph ~= "kneel" and ph ~= "on" then return end
	m:SetAttribute("AnchorRiseAt", now)
	m:SetAttribute("AnchorReadyAt", now + CFG.Anchor.Rise + CFG.Anchor.Cooldown)
end
local function startPull(victim, to, face, pullTime, stun, arc, ease)   -- 10-31 ease "in" = 처음 천천히·끝에 가속(그랩 — 홱 끌려와 쾅) · 없으면 예전(처음 빠름)   -- 10-30 arc = 포물선 꼭대기 높이(FALCO 라이더킥 날림 · 없으면 곧게)
	local vr, vh = victim:FindFirstChild("HumanoidRootPart"), victim:FindFirstChildOfClass("Humanoid")
	if not (vr and vh) then return end
	local now = workspace:GetServerTimeNow()
	if CFG.superArmor(victim, now) then return end   -- 10-30 FALCO 라이더킥 슈퍼아머: 안 밀림 · 경직 없음(피해는 이미 받음)
	if CFG.ultPhase(victim, now) then   -- 10-30 SKADI 궁극기(강제 앵커) 중: 안 밀림 · 경직만 먹음(그동안 못 쏨) [제안]
		victim:SetAttribute("StunUntil", math.max(victim:GetAttribute("StunUntil") or 0, now + stun))
		return
	end
	anchorRelease(victim, now)   -- 10-30 끌리거나 밀리면 앵커가 풀림(꿇은 채 미끄러지지 않게)
	victim:SetAttribute("FlipAt", nil)   -- 10-30 공중제비 중에 끌리면 공중제비 취소(끌림이 몸을 가져감)
	victim:SetAttribute("PullTo", to)
	victim:SetAttribute("PullFace", face)
	victim:SetAttribute("PullTime", pullTime)
	victim:SetAttribute("PullEase", ease)                     -- 10-31 없으면 지움
	victim:SetAttribute("PullArc", arc)                       -- 10-30 없으면 지움(곧게)
	victim:SetAttribute("StunUntil", now + pullTime + stun)
	victim:SetAttribute("PullAt", now)                       -- 마지막에(클라는 PullAt 이 바뀌면 새로 끌려감)
	victim:SetAttribute("BoostHold", nil); victim:SetAttribute("BoostHoldAir", nil); victim:SetAttribute("Climb", nil)
	victim:SetAttribute("GunSpinAt", nil)
	if not victim:GetAttribute("Pilot") then   -- 조종사 없음 → 서버가 끌어옴
		local from = vr.Position
		local h = arc or 0
		vh.PlatformStand = true
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if not victim.Parent or not vr.Parent then conn:Disconnect(); return end
			-- 10-30 새 끌림이 시작됨(라이더킥: 끌고 감 → 날림) → 이 연결은 손 뗌(몸·PlatformStand 는 새 끌림 것). 누가 PullAt 을 지웠으면 풀어 줌
			local pa = victim:GetAttribute("PullAt")
			if pa ~= now then conn:Disconnect(); if pa == nil then vh.PlatformStand = false end; return end
			local k = math.clamp((workspace:GetServerTimeNow() - now) / pullTime, 0, 1)
			vr.AssemblyLinearVelocity = Vector3.zero
			vr.CFrame = CFrame.lookAlong(from:Lerp(to, (ease == "in") and k * k or k * (2 - k)) + Vector3.new(0, 4 * h * k * (1 - k), 0), face)
			if k >= 1 then conn:Disconnect(); vh.PlatformStand = false end
		end)
	end
end
function GRAB.pull(att, victim)
	local ar, vr = att:FindFirstChild("HumanoidRootPart"), victim:FindFirstChild("HumanoidRootPart")
	local vh = victim:FindFirstChildOfClass("Humanoid")
	if not (ar and vr and vh) then return end
	local G = CFG.Grab
	local lv = ar.CFrame.LookVector
	local look = Vector3.new(lv.X, 0, lv.Z)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local to = ar.Position + look * G.Front
	to = Vector3.new(to.X, groundY(to, { att, victim }) + vh.HipHeight + vr.Size.Y / 2, to.Z)
	startPull(victim, to, -look, G.PullTime, G.Stun, nil, "in")
	victim:SetAttribute("GrabStunUntil", workspace:GetServerTimeNow() + G.PullTime + G.Stun)   -- 10-31 화면 방전 표시(MechFelsen) — 슈퍼아머로 안 끌렸으면 아래에서 지움
	if victim:GetAttribute("PullEase") ~= "in" then victim:SetAttribute("GrabStunUntil", nil) end
end
-- 10-30 SKADI 앞차기 넉백: 찬 방향(dir, 수평)으로 KnockDist. 벽·지형이 앞에 있으면 그 4 앞에서 멈춤(벽 속으로 안 밀림). 상대는 찬 쪽을 봄
local function knockback(att, victim, dir, dist0, time0, stun0, arc0)   -- 10-30 FALCO 라이더킥이 거리·시간·경직을 넘김(없으면 앞차기 값)
	local vr, vh = victim:FindFirstChild("HumanoidRootPart"), victim:FindFirstChildOfClass("Humanoid")
	if not (vr and vh) or dir.Magnitude < 0.1 then return end
	local K = CFG.Kick
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { att, victim }
	local dist = dist0 or K.KnockDist
	local hit = workspace:Raycast(vr.Position, dir * (dist + 4), rp)
	if hit then dist = math.max(0, (hit.Position - vr.Position):Dot(dir) - 4) end
	local to = vr.Position + dir * dist
	to = Vector3.new(to.X, groundY(to, { att, victim }) + vh.HipHeight + vr.Size.Y / 2, to.Z)
	startPull(victim, to, -dir, time0 or K.KnockTime, stun0 or K.Stun, arc0)
end
-- 10-30 10:48 SKADI 앞차기 공중제비(유저 "상대 기체를 디딤발 삼아 뒤로 공중제비 한 바퀴 돌아 착지" · 맞았을 때만 · 내 후퇴 약 15) — 수치 CFG.Kick.Flip
--   착지 자리 = 찬 방향 반대로 Back. 출발 높이·꼭대기 높이 두 줄로 뒤를 재서 벽·지형이 있으면 그 4 앞(넉백과 같은 규칙) · 땅 위 서 있는 높이
--   속성을 쓰면 끝: 조종 화면이 FlipAt 부터 Time 동안 포물선을 직접 따라가고(GR.flipDrive) 모든 화면이 한 바퀴 도는 자세를 그림.
--   잠금(CFG.stunned)·자세 모두 시각으로 계산 → 끄는 코드 없음. 조종사 없는 기체(적 AI)는 안 돔(끌어 줄 화면이 없음)
local function kickFlip(m, dir, ignore)
	if not m:GetAttribute("Pilot") then return end
	local r, h = m:FindFirstChild("HumanoidRootPart"), m:FindFirstChildOfClass("Humanoid")
	if not (r and h and h.Health > 0) or dir.Magnitude < 0.1 then return end
	local F = CFG.Kick.Flip
	local now = workspace:GetServerTimeNow()
	local back = -dir
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = ignore
	local dist = F.Back
	for _, up in ipairs({ 0, F.Height }) do
		local o = r.Position + Vector3.new(0, up, 0)
		local hit = workspace:Raycast(o, back * (F.Back + 4), rp)
		if hit then dist = math.min(dist, math.max(0, (hit.Position - o):Dot(back) - 4)) end
	end
	local to = r.Position + back * dist
	to = Vector3.new(to.X, groundY(to, ignore) + h.HipHeight + r.Size.Y / 2, to.Z)
	m:SetAttribute("BoostHold", nil); m:SetAttribute("BoostHoldAir", nil); m:SetAttribute("Climb", nil)
	m:SetAttribute("FlipTo", to)
	m:SetAttribute("FlipFace", dir)
	m:SetAttribute("FlipAt", now + F.Delay)   -- 마지막에(클라는 FlipAt 이 바뀌면 새로 뜀)
end
function GRAB.fire(m, aimPoint, muzzle)
	local root = m:FindFirstChild("HumanoidRootPart"); if not root then return end
	local G = CFG.Grab
	local now = workspace:GetServerTimeNow()
	if (m:GetAttribute("GrabReadyAt") or 0) > now then return end
	m:SetAttribute("GrabReadyAt", now + G.Cooldown)
	m:SetAttribute("GrabHitAt", nil); m:SetAttribute("GrabEnd", nil)
	m:SetAttribute("GrabAt", now)   -- 10-30 그랩 중 잠금·전용 자세(CFG.grabPhase) — 끝 시각은 아래 날아가기가 끝날 때
	local arm = m:FindFirstChild("LowerArmL")
	local mzA = arm and arm:FindFirstChild("GrappleMuzzle", true)
	local from = mzA and mzA.WorldPosition or (root.Position + Vector3.new(0, 3, 0))
	-- 화면의 든 팔 손목(서버 팔은 쉬는 자세)을 서버 자리에서 GrenadeMuzzleTrust 안일 때만 믿음(AELLO 손목 런처와 같은 규칙)
	if typeof(muzzle) == "Vector3" and muzzle == muzzle and (muzzle - from).Magnitude < CFG.GrenadeMuzzleTrust then from = muzzle end
	local d = aimPoint - from
	local dir = d.Magnitude > 1 and d.Unit or root.CFrame.LookVector
	GRAB.seq += 1
	local id = GRAB.seq
	Remotes.MechFX:FireAllClients("grab", m, id, from, dir)
	SM.play("PodDrop", from)   -- 임시: 철컥(발사음은 SoundManager 에 따로 넣을 것)
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { m }
	local pos, travelled = from, 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not m.Parent then conn:Disconnect(); return end
		local step = math.min(G.Speed * dt, G.Range - travelled)
		local hit = workspace:Raycast(pos, dir * step, rp)
		local segEnd = hit and hit.Position or (pos + dir * step)
		local victim
		local seg = segEnd - pos
		local L2 = seg:Dot(seg)
		for _, o in ipairs(CollectionService:GetTagged("Mech")) do
			if o ~= m and o.Parent and Dmg.canDamage(m, o) then
				local c = bodyCenter(o); local h = o:FindFirstChildOfClass("Humanoid")
				if c and h and h.Health > 0 then
					local u = L2 > 0 and math.clamp((c - pos):Dot(seg) / L2, 0, 1) or 0
					if (pos + seg * u - c).Magnitude <= G.HitRadius then victim = o; segEnd = pos + seg * u; break end
				end
			end
		end
		if not victim and hit then
			local o = humanoidModelOf(hit.Instance)
			if o and o:GetAttribute("IsMech") and Dmg.canDamage(m, o) then victim = o end
		end
		travelled += (segEnd - pos).Magnitude
		pos = segEnd
		if victim or hit or travelled >= G.Range - 0.01 then
			conn:Disconnect()
			if victim then GRAB.pull(m, victim) end
			local tEnd = workspace:GetServerTimeNow()
			m:SetAttribute("GrabEnd", tEnd + (victim and (G.PullTime + 0.15) or 0.25))   -- 10-30 줄이 다 감기는 시각(화면 감기 그림과 같은 값)
			m:SetAttribute("GrabHitAt", tEnd)
			Remotes.MechFX:FireAllClients("grabEnd", m, id, pos, victim)
		end
	end)
end
-- ================= 10-30 SKADI 보조: 센서 지뢰 (G) — 규칙·수치 = MechConfig CFG.Mine =================
-- 기체 속성 SubWeapon == "Mine"(SkadiTemplate). 남은 개수 = CFG.mineAmmo(속성 MineAmmo · MineReadyAt — 손목 그레네이드와 같은 시각 충전, 채우는 코드 없음)
-- 지뢰 = ServerStorage.SkadiMine 복제(workspace.MechMines · 태그 "MechMine" · 속성 PlacedAt · ArmAt · WarnAt = 서버 시각) → 각 화면이 렌즈 깜빡임·범위 원을 그림
-- 떨어짐·켜짐·감지·폭발·정리 = 이 상주 스크립트의 Heartbeat 하나(MINE.step). task.delay 예약은 안 씀(부른 쪽 혈통에 묶여 회수될 수 있음)
-- 주인 기체가 없어지거나 · 죽거나 · 내려 빈 기체가 되면(Pilot 도 EnemyMech 도 없음) 그 주인의 지뢰는 조용히 사라짐
local MINE = { list = {}, lastAt = setmetatable({}, { __mode = "k" }) }   -- list = { owner, model, from, pos, yaw, placedAt, armAt, landed, armed, warnAt }
function MINE.alive(o)   -- 지금 싸우는 기체인가(조종 중이거나 적 AI · 살아 있음)
	if not (o and o.Parent) then return false end
	if not (o:GetAttribute("Pilot") or o:GetAttribute("EnemyMech")) then return false end
	local h = o:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end
function MINE.inZone(e, o)   -- 감지·피해 범위: 수평 Radius 안 · 높이 차(루트 − 지뢰) −Below ~ 그 기체 루트 높이 + RiseAbove
	local r = o:FindFirstChild("HumanoidRootPart"); if not r then return false end
	local d = r.Position - e.pos
	local K = CFG.Mine
	if d.Y < -K.Below or d.Y > (o:GetAttribute("RootHeight") or 10) + K.RiseAbove then return false end
	return Vector3.new(d.X, 0, d.Z).Magnitude <= K.Radius
end
function MINE.targets(e)
	local out = {}
	for _, o in ipairs(CollectionService:GetTagged("Mech")) do
		if o ~= e.owner and MINE.alive(o) and Dmg.canDamage(e.owner, o) and MINE.inZone(e, o) then out[#out + 1] = o end
	end
	return out
end
function MINE.remove(i)
	local e = table.remove(MINE.list, i)
	if e and e.model then e.model:Destroy() end
end
function MINE.place(m)
	local root = m:FindFirstChild("HumanoidRootPart"); if not root then return end
	local tpl = ServerStorage:FindFirstChild("SkadiMine"); if not tpl then return end
	local K = CFG.Mine
	local now = workspace:GetServerTimeNow()
	local n = CFG.mineAmmo(m, now)
	if n <= 0 then return end
	if now - (MINE.lastAt[m] or -99) < K.Interval * 0.8 then return end
	-- 놓을 자리 = 기체 앞 Front 의 땅. 기체들은 레이에서 뺌(지뢰는 CanQuery 꺼져 있어 안 걸림). 땅이 없으면(높이 떠 있음) 안 깔고 개수도 안 씀
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z); flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
	local rh = m:GetAttribute("RootHeight") or 10
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = CollectionService:GetTagged("Mech")
	local hit = workspace:Raycast(root.Position + flat * K.Front + Vector3.new(0, 4, 0), Vector3.new(0, -(rh + 60), 0), rp)
	if not hit then return end
	MINE.lastAt[m] = now
	n -= 1
	m:SetAttribute("MineAmmo", n)
	if n <= 0 then m:SetAttribute("MineReadyAt", now + K.Refill) end
	-- 필드 최대: 이 주인의 지뢰가 이미 MaxField 개면 가장 오래된 것부터 사라짐(list 는 깐 순서)
	local mine = {}
	for i, e in ipairs(MINE.list) do if e.owner == m then mine[#mine + 1] = i end end
	for k = #mine - K.MaxField + 1, 1, -1 do MINE.remove(mine[k]) end
	local e = { owner = m, placedAt = now, armAt = now + K.ArmTime,
		pos = hit.Position + Vector3.new(0, tpl:GetAttribute("Bottom") or 0.25, 0),
		from = (root.CFrame * CFrame.new(-3.2, -rh * 0.35, 0.5)).Position,   -- 골반 왼쪽 아래(오른쪽은 저격총)에서 떨어짐
		yaw = CFrame.Angles(0, math.random() * 2 * math.pi, 0) }
	local model = tpl:Clone()
	model:PivotTo(CFrame.new(e.from) * e.yaw)
	model:SetAttribute("PlacedAt", now); model:SetAttribute("ArmAt", e.armAt)
	local f = workspace:FindFirstChild("MechMines")
	if not f then f = Instance.new("Folder"); f.Name = "MechMines"; f.Parent = workspace end
	model.Parent = f
	CollectionService:AddTag(model, "MechMine")
	e.model = model
	table.insert(MINE.list, e)
end
function MINE.explode(i)
	local e = MINE.list[i]
	local K = CFG.Mine
	local now = workspace:GetServerTimeNow()
	local hitAny = false
	for _, o in ipairs(MINE.targets(e)) do   -- 예고(범위 원) = 판정: 터지는 순간 범위 안에 남은 적만
		local h = o:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then
			Dmg.hurt(e.owner, o, h, K.Damage)
			if not CFG.superArmor(o, now) then o:SetAttribute("StunUntil", math.max(o:GetAttribute("StunUntil") or 0, now + K.Stun)) end   -- 작살 그랩과 같은 경직(CFG.stunned)
			hitAny = true
		end
	end
	Remotes.MechFX:FireAllClients("mineBoom", e.owner, e.pos, hitAny)
	SM.play("MineBoom", e.pos)
	MINE.remove(i)
end
function MINE.step()
	if #MINE.list == 0 then return end
	local now = workspace:GetServerTimeNow()
	local K = CFG.Mine
	for i = #MINE.list, 1, -1 do
		local e = MINE.list[i]
		if not (e.model and e.model.Parent) or not MINE.alive(e.owner) then
			MINE.remove(i)
		elseif not e.landed then   -- 떨어지는 중: 수평은 고르게 · 위로 살짝 호를 그리며 · 돌면서
			local u = math.clamp((now - e.placedAt) / K.DropTime, 0, 1)
			e.model:PivotTo(CFrame.new(e.from:Lerp(e.pos, u) + Vector3.new(0, 2.5 * math.sin(math.pi * u), 0)) * e.yaw * CFrame.Angles(0, (1 - u) * 6, 0))
			if u >= 1 then e.landed = true; SM.play("MineDrop", e.pos) end
		elseif not e.armed then
			if now >= e.armAt then e.armed = true; SM.play("MineArm", e.pos) end
		elseif not e.warnAt then
			if #MINE.targets(e) > 0 then
				e.warnAt = now
				e.model:SetAttribute("WarnAt", now)
				SM.play("MineBeep", e.pos)
			end
		elseif now - e.warnAt >= K.Warn then
			MINE.explode(i)
		end
	end
end
RunService.Heartbeat:Connect(MINE.step)
Remotes.MechMine.OnServerEvent:Connect(function(player)
	local m = pilotMech(player); if not m then return end
	if m:GetAttribute("SubWeapon") ~= "Mine" then return end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	if CFG.stunned(m) then return end
	MINE.place(m)
end)

-- ================= 10-30 SKADI 시그니처: 앵커 자세 (C) — 규칙·수치 = MechConfig CFG.Anchor =================
-- on = true: 땅에 서 있고 · 경직 아님 · 쿨 끝 · 근접 동작 중 아님 · 이미 꿇거나 일어나는 중 아님 → AnchorAt = 지금(지속 부스트 끔)
-- on = false: 꿇는 중·꿇은 상태면 풀기(anchorRelease)
Remotes.MechAnchor.OnServerEvent:Connect(function(player, on)
	local m = pilotMech(player); if not m then return end
	if m:GetAttribute("Signature") ~= "Anchor" then return end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	local now = workspace:GetServerTimeNow()
	if on == true then
		if CFG.anchorPhase(m, now) then return end
		if (m:GetAttribute("AnchorReadyAt") or 0) > now then return end
		if CFG.stunned(m) then return end
		-- 공중이면 못 꿇음. 조종 클라 소유 몸이라 서버 FloorMaterial 은 믿지 않고 발밑을 직접 잼(루트 높이 + 3 안에 뭔가 있어야)
		local root = m:FindFirstChild("HumanoidRootPart"); if not root then return end
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { m }
		if not workspace:Raycast(root.Position, Vector3.new(0, -((m:GetAttribute("RootHeight") or 10) + 3), 0), rp) then return end
		local ma, mk = m:GetAttribute("MeleeAt"), m:GetAttribute("MeleeKind")
		if ma and mk == "kick" and now - ma < CFG.Kick.Time then return end
		m:SetAttribute("BoostHold", nil); m:SetAttribute("BoostHoldAir", nil); m:SetAttribute("Climb", nil)
		m:SetAttribute("AnchorRiseAt", nil)
		m:SetAttribute("AnchorAt", now)
	else
		if CFG.ultPhase(m, now) then return end   -- 10-30 궁극기(강제 앵커) 동안 풀기 막힘 [결정 10-29 22:39 경계 규칙 5]
		anchorRelease(m, now)
	end
end)

-- ================= 10-30 궁극기 (X) — 게이지 = MechDamage.hurt · 규칙·수치 = MechConfig CFG.Ult / CFG.ForcedAnchor =================
-- 기체 속성 Ultimate(템플릿)이 그 기체의 궁극기. 게이지(속성 UltGauge)가 Max 면 X → 그 궁극기 → 게이지 0
-- 지금 = SKADI "ForcedAnchor"(강제 앵커 연사) 하나. 상태 = 속성 UltStart · UltEnd · UltKeep(시각 — 모든 화면이 CFG.ultPhase 로 읽음)
-- 끝 처리(탄창 가득 · 원래 앵커가 아니었으면 일어남 → 앵커 쿨)는 이 상주 스크립트 Heartbeat(ULT.step)가 UltEnd 가 지나면 한 번(task.delay 예약 안 씀)
local ULT = { list = {} }   -- [기체] = true (끝 처리 기다림)
function ULT.forcedAnchor(m, now)
	local A = CFG.Anchor
	local ph = CFG.anchorPhase(m, now)
	if ph == "rise" then return false end   -- 일어나는 중엔 못 씀(다 일어난 뒤 다시)
	local start, keep
	if ph == "on" then
		start, keep = now, true                                   -- 이미 다 꿇음 → 바로 · 끝나도 꿇은 채
	elseif ph == "kneel" then
		start, keep = m:GetAttribute("AnchorAt") + A.Kneel, true   -- 꿇는 중 → 다 꿇는 순간부터
	else
		-- 땅에서만(공중에선 못 꿇음 [경계 규칙 1]). 발밑은 서버가 직접 잼(MechAnchor 와 같은 식)
		local root = m:FindFirstChild("HumanoidRootPart"); if not root then return false end
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { m }
		if not workspace:Raycast(root.Position, Vector3.new(0, -((m:GetAttribute("RootHeight") or 10) + 3), 0), rp) then return false end
		m:SetAttribute("BoostHold", nil); m:SetAttribute("BoostHoldAir", nil); m:SetAttribute("Climb", nil)
		m:SetAttribute("AnchorRiseAt", nil)
		m:SetAttribute("AnchorAt", now)
		start, keep = now + A.Kneel, false                        -- 꿇기 끝나는 순간부터 · 끝나면 일어남
	end
	m:SetAttribute("ReloadUntil", nil)   -- 장전 취소(탄창 무한 창 — 장전 동작이 사격을 가리지 않게)
	m:SetAttribute("UltKeep", keep)
	m:SetAttribute("UltStart", start)
	m:SetAttribute("UltEnd", start + CFG.ForcedAnchor.Duration)
	return true
end
ULT.kinds = { ForcedAnchor = ULT.forcedAnchor }
-- ================= 10-30 FALCO 궁극기: 마비 덫 (Ultimate = "ParalysisTrap") — 규칙·수치 = MechConfig CFG.Trap =================
-- X(화면이 보낸 조준점) → Range 안으로 줄이고 그 아래 땅(기체 몸은 빼고)을 가운데로 한 변 Side 사각형(방향 = 쏜 기체가 보던 쪽). 위치는 누르는 순간 고정.
--   땅이 없으면(허공) 안 씀 → 게이지 그대로. 공중에서도 씀(SKADI 강제 앵커와 달리 UltStart/UltEnd 를 안 씀 — 그 둘은 앵커·레이저·탄창 규칙이 묶여 있음)
-- 속성(쏜 기체) TrapPos · TrapYaw · TrapAt(마지막) → 모든 화면이 CFG.trapPhase 로 못 날기 · 박힘 · 전기 · 사각형을 그림(MechClient.MechFalco)
-- 지대(on) 동안 이 상주 Heartbeat(TRAP.step)가: 사각형 안 · 땅 가까이(높이 제한) · 싸우는 기체(MINE.alive) · 다칠 수 있는 상대 →
--   SlowUntil = 지금 + Refresh(남은 게 0.15 아래일 때만 다시 씀) · 처음 걸리면 SlowAt = 지금. 나가면 Refresh 뒤 저절로 풀림(해제 코드 없음 — 영구 둔화 사고 방지)
-- 쏜 기체가 없어지면 지대도 끝(화면도 그 기체 속성으로 그려서 같이 사라짐)
local TRAP = { list = {} }   -- [쏜 기체] = { cf = 가운데 땅 · 사각형 방향, onAt, endAt, at }
function TRAP.cast(m, now, aim)
	local root = m:FindFirstChild("HumanoidRootPart"); if not root then return false end
	if typeof(aim) ~= "Vector3" or aim ~= aim then return false end
	local T = CFG.Trap
	local d = aim - root.Position
	if d.Magnitude > T.Range then aim = root.Position + d.Unit * T.Range end
	local ex = {}
	for _, tag in ipairs({ "Mech", "MechDisplay" }) do
		for _, o in ipairs(CollectionService:GetTagged(tag)) do ex[#ex + 1] = o end
	end
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = ex
	local hit = workspace:Raycast(aim + Vector3.new(0, 30, 0), Vector3.new(0, -400, 0), rp)
	if not hit then return false end
	local lv = root.CFrame.LookVector
	local yaw = math.atan2(-lv.X, -lv.Z)
	m:SetAttribute("TrapPos", hit.Position)
	m:SetAttribute("TrapYaw", yaw)
	m:SetAttribute("TrapAt", now)   -- 마지막에(화면은 TrapAt 이 바뀌면 새 덫)
	TRAP.list[m] = { cf = CFrame.new(hit.Position) * CFrame.Angles(0, yaw, 0), at = now,
		onAt = now + T.FlyTime + T.LinkDelay, endAt = now + T.FlyTime + T.LinkDelay + T.Duration }
	SM.play("PodDrop", root)   -- 임시: 등에서 못이 떨어져 나가는 철컥
	return true
end
-- 10-30 14:2x 유저 "스카디 궁 밸류에 비해 팔코 궁이 너무 약해" → 고른 안 = 전기선을 벽으로(수치 = CFG.Trap WallHeight · Shock*)
--   지대(on)가 켜진 뒤 처음 보는 순간 각 적이 사각형 안/밖 어느 쪽인지 기억(z.side) → 반대쪽으로 넘으면 TRAP.shock:
--   피해 ShockDamage + 원래 쪽(벽에서 ShockPush)으로 끌려 돌아감(startPull — 넉백·작살과 같은 길, 조종 화면이 직접 끌려감) + 경직 ShockStun
--   발이 벽 위(WallHeight)거나 한참 아래로 떨어졌으면 넘어가도 감전 없이 그쪽을 새로 기억. 슈퍼아머(라이더킥 중)는 안 끌려가므로 피해만 받고 새 쪽으로
--   판정 벽 = 화면 벽(MechFalco makeEdges: 가운데 땅에서 WallHeight 까지 네 면) — 같은 모양
function TRAP.shock(m, z, o, l, inside0, now)
	local T = CFG.Trap
	local h = T.Side / 2
	local r, vh = o:FindFirstChild("HumanoidRootPart"), o:FindFirstChildOfClass("Humanoid")
	if not (r and vh and vh.Health > 0) then return end
	Dmg.hurt(m, o, vh, T.ShockDamage)
	local tx, tz
	if inside0 then   -- 안으로 되돌림(두 축 모두 벽에서 ShockPush 안쪽)
		tx = math.clamp(l.X, -h + T.ShockPush, h - T.ShockPush)
		tz = math.clamp(l.Z, -h + T.ShockPush, h - T.ShockPush)
	else              -- 밖으로 밀어냄(가장 가까운 변 바깥 ShockPush)
		tx, tz = l.X, l.Z
		if h - math.abs(l.X) < h - math.abs(l.Z) then tx = (l.X >= 0 and 1 or -1) * (h + T.ShockPush)
		else tz = (l.Z >= 0 and 1 or -1) * (h + T.ShockPush) end
	end
	local ex, ez = math.clamp(l.X, -h, h), math.clamp(l.Z, -h, h)   -- 넘은 자리(벽 위의 점)
	if not inside0 then
		if tx ~= l.X then ex = (l.X >= 0 and 1 or -1) * h else ez = (l.Z >= 0 and 1 or -1) * h end
	end
	local edge = z.cf * Vector3.new(ex, l.Y, ez)
	local to = z.cf * Vector3.new(tx, 0, tz)
	to = Vector3.new(to.X, groundY(to, { m, o }) + vh.HipHeight + r.Size.Y / 2, to.Z)
	local face = Vector3.new(edge.X - to.X, 0, edge.Z - to.Z)   -- 벽 쪽을 봄
	face = face.Magnitude > 0.1 and face.Unit or r.CFrame.LookVector
	if vh.Health > 0 then startPull(o, to, face, T.ShockPull, T.ShockStun) end
	Remotes.MechFX:FireAllClients("trapShock", m, o, edge)
	SM.play("BodyHit", edge)
end
function TRAP.step()
	if next(TRAP.list) == nil then return end
	local now = workspace:GetServerTimeNow()
	local T = CFG.Trap
	local h = T.Side / 2
	for m, z in pairs(TRAP.list) do
		if not m.Parent or now >= z.endAt or m:GetAttribute("TrapAt") ~= z.at then
			TRAP.list[m] = nil
		elseif now >= z.onAt then
			z.side = z.side or {}
			z.shockAt = z.shockAt or {}
			for _, o in ipairs(CollectionService:GetTagged("Mech")) do
				if o ~= m and MINE.alive(o) and Dmg.canDamage(m, o) then
					local r = o:FindFirstChild("HumanoidRootPart")
					if r then
						local l = z.cf:PointToObjectSpace(r.Position)
						local rh = o:GetAttribute("RootHeight") or 10
						local inside = math.abs(l.X) <= h and math.abs(l.Z) <= h
						-- 둔화: 안 · 땅 가까이(공중은 안 걸림)
						if inside and l.Y >= -T.Below and l.Y <= rh + T.Rise then
							local u = o:GetAttribute("SlowUntil") or 0
							if u <= now then o:SetAttribute("SlowAt", now) end
							if u - now < 0.15 then o:SetAttribute("SlowUntil", now + T.Refresh) end
						end
						-- 벽: 기억한 쪽과 다르면 감전
						local s0 = z.side[o]
						if s0 == nil or l.Y - rh > T.WallHeight or l.Y < -T.Below - 10 then
							z.side[o] = inside
						elseif inside ~= s0 and now - (z.shockAt[o] or -99) >= T.ShockGap then
							z.shockAt[o] = now
							TRAP.shock(m, z, o, l, s0, now)
							if CFG.superArmor(o, now) then z.side[o] = inside end   -- 안 끌려감 → 넘어간 쪽을 새로
						end
					end
				end
			end
		end
	end
end
RunService.Heartbeat:Connect(TRAP.step)
ULT.kinds.ParalysisTrap = TRAP.cast
-- ================= 10-30 FELSEN 궁극기: 도끼 도약 내려찍기 (Ultimate = "AxeLeap") — 규칙·수치 = MechConfig CFG.Leap =================
-- 유저 10-30 16:25 "조준 위치를 향해 도끼를 번쩍 머리 위로 들고 뛰어들어서 도착하면 쿵 하면서 도끼를 내려찍고 지반을 흔드는 거야.
--   직격당한 적일수록 카메라 흔들림 + 큰 데미지" · 16:28 "착지 원이 적에게도 보이고, 공중 적도 부딪혔으니 직격에 해당하는 데미지"
--   · 16:31 "부딪혀도 펠젠은 그대로 날아가게" · 16:32 날아가는 시간 1.2초 · 16:38 준비 동작 없음 · 거리 무관 고정 · 날아가다 몸 충돌은 공중에 뜬 적만
-- X(조준점) → 수평 Range 안으로 줄이고 그 아래 땅 = 착지 자리(누르는 순간 고정 — 모든 화면이 원으로 그림, MechClient.MechFelsen).
--   가는 포물선(꼭대기 Height)을 8토막 광선으로 재서 막히면 막힌 곳에서 Wall 만큼 내 쪽 땅에 내려찍음. 땅이 없으면 안 씀(게이지 그대로)
-- 속성 LeapFrom · LeapTo(서 있는 높이) · LeapGround(원 가운데 땅) · LeapAt(마지막) → CFG.leapPhase "fly"(Time) · "land"(Recover)
--   조종 화면이 그 길을 직접 따라감 · 잠금 = CFG.stunned · 날아가는 동안 슈퍼아머 · 도끼를 든 상태(Weapon = "saber")로 바꿈
-- 상주 Heartbeat LEAP.step(서버 시각으로 계산한 같은 길 — 조종 화면 위치를 안 믿음):
--   날아가는 동안 = 공중에 뜬(발밑 AirHeight 안에 아무것도 없음) 적의 몸 막대와 FELSEN 뿌리가 AirHit 안 → 직격 Core 피해 + 바로 아래 땅으로 떨어짐(DownTime) + 쓰러짐 Down
--   착지(Time) = 원 안(수평 Radius) · 땅 근처(발 높이 ±HitHeight) 적 → 가운데(CoreRadius 안) Core 피해 + 쓰러짐 Down, 바깥으로 Edge 까지 줄어듦(쓰러짐 없음)
--   한 번 맞은 적은 다시 안 맞음(공중 충돌 → 착지) · 화면 흔들림 세기 = 가운데 1 → 가장자리 0(MechFX "leapSlam")
-- 쏜 기체가 죽거나 내리면(park 가 LeapAt 을 지움) 거기서 끝(착지 피해 없음)
local LEAP = { list = {} }   -- [기체] = { at, from, to, ground, hit = { [맞은 기체] = true } }
function LEAP.params()   -- 기체 몸(Mech · MechDisplay) 빼고 땅·벽만
	local ex = {}
	for _, tag in ipairs({ "Mech", "MechDisplay" }) do
		for _, o in ipairs(CollectionService:GetTagged(tag)) do ex[#ex + 1] = o end
	end
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = ex
	return rp
end
function LEAP.cast(m, now, aim)
	local root, hum = m:FindFirstChild("HumanoidRootPart"), m:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return false end
	if typeof(aim) ~= "Vector3" or aim ~= aim then return false end
	local L = CFG.Leap
	local from = root.Position
	local flat = Vector3.new(aim.X - from.X, 0, aim.Z - from.Z)
	if flat.Magnitude > L.Range then flat = flat.Unit * L.Range end
	local rp = LEAP.params()
	local function groundAt(p)
		local g = workspace:Raycast(Vector3.new(p.X, math.max(p.Y, from.Y) + 30, p.Z), Vector3.new(0, -500, 0), rp)
		return g and g.Position
	end
	local g = groundAt(Vector3.new(from.X + flat.X, aim.Y, from.Z + flat.Z))
	if not g then return false end
	local stand = hum.HipHeight + root.Size.Y / 2
	local to = g + Vector3.new(0, stand, 0)
	-- 가는 길(포물선) 8토막 — 착지 자리 근처(서 있는 높이 + 4 안)에 닿는 건 착지라서 빼고, 막히면 막힌 곳에서 Wall 만큼 내 쪽 땅으로
	local prev = from
	for i = 1, 8 do
		local k = i / 8
		local p = from:Lerp(to, k) + Vector3.new(0, 4 * L.Height * k * (1 - k), 0)
		local hit = workspace:Raycast(prev, p - prev, rp)
		if hit and (hit.Position - to).Magnitude > stand + 4 then
			local back = Vector3.new(hit.Position.X - from.X, 0, hit.Position.Z - from.Z)
			local d = math.max(0, back.Magnitude - L.Wall)
			local g2 = groundAt(from + (back.Magnitude > 0.01 and back.Unit * d or Vector3.zero))
			if not g2 then return false end
			g, to = g2, g2 + Vector3.new(0, stand, 0)
			break
		end
		prev = p
	end
	m:SetAttribute("BoostHold", nil); m:SetAttribute("BoostHoldAir", nil); m:SetAttribute("Climb", nil)
	m:SetAttribute("ReloadUntil", nil)
	if (m:GetAttribute("Weapon") or "rifle") ~= "saber" then   -- 도끼를 든 상태로(조종 화면은 X 누를 때 같이 바꿈 — GR.ult)
		m:SetAttribute("Weapon", "saber"); m:SetAttribute("WeaponAt", now)
	end
	m:SetAttribute("LeapFrom", from); m:SetAttribute("LeapTo", to); m:SetAttribute("LeapGround", g)
	m:SetAttribute("LeapAt", now)   -- 마지막에(화면은 LeapAt 이 바뀌면 새 도약)
	LEAP.list[m] = { at = now, from = from, to = to, ground = g, hit = {} }
	return true
end
function LEAP.airborne(o)   -- 발밑(뿌리 높이 + AirHeight) 안에 아무것도 없음 = 공중
	local r = o:FindFirstChild("HumanoidRootPart"); if not r then return false end
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { o }
	return workspace:Raycast(r.Position, Vector3.new(0, -((o:GetAttribute("RootHeight") or 10) + CFG.Leap.AirHeight), 0), rp) == nil
end
function LEAP.airHit(m, o)   -- 날아가다 공중 적에 부딪힘: 직격 피해 + 바로 아래 땅으로 떨어뜨림 + 쓰러짐(슈퍼아머면 피해만 — startPull 이 거름)
	local L = CFG.Leap
	local r, vh = o:FindFirstChild("HumanoidRootPart"), o:FindFirstChildOfClass("Humanoid")
	if not (r and vh) then return end
	local p = r.Position
	Dmg.hurt(m, o, vh, L.Core)
	if vh.Health > 0 then
		local to = Vector3.new(p.X, groundY(p, { m, o }) + vh.HipHeight + r.Size.Y / 2, p.Z)
		local lv = r.CFrame.LookVector
		local face = Vector3.new(lv.X, 0, lv.Z)
		startPull(o, to, face.Magnitude > 0.1 and face.Unit or Vector3.new(0, 0, -1), L.DownTime, L.Down)
	end
	Remotes.MechFX:FireAllClients("leapAirHit", m, o, p)
	SM.play("BodyHit", p)
end
function LEAP.slam(m, e)   -- 착지: 원 안 · 땅 근처 적에게 거리만큼 피해(가운데 Core + 쓰러짐 → 가장자리 Edge)
	local L = CFG.Leap
	local c = e.ground
	local now = workspace:GetServerTimeNow()
	local vs, ks = {}, {}
	for _, o in ipairs(CollectionService:GetTagged("Mech")) do
		if o ~= m and not e.hit[o] and MINE.alive(o) and Dmg.canDamage(m, o) then
			local r, vh = o:FindFirstChild("HumanoidRootPart"), o:FindFirstChildOfClass("Humanoid")
			if r and vh and vh.Health > 0 then
				local d = Vector3.new(r.Position.X - c.X, 0, r.Position.Z - c.Z).Magnitude
				local foot = r.Position.Y - (o:GetAttribute("RootHeight") or 10) - c.Y
				if d <= L.Radius and math.abs(foot) <= L.HitHeight then
					local k = (d <= L.CoreRadius) and 1 or (1 - (d - L.CoreRadius) / (L.Radius - L.CoreRadius))
					e.hit[o] = true
					Dmg.hurt(m, o, vh, math.floor(L.Edge + (L.Core - L.Edge) * k + 0.5))
					if d <= L.CoreRadius and vh.Health > 0 and not CFG.superArmor(o, now) then
						o:SetAttribute("StunUntil", math.max(o:GetAttribute("StunUntil") or 0, now + L.Down))   -- 쓰러짐 = 경직(지뢰 경직과 같은 방식)
					end
					vs[#vs + 1] = o; ks[#ks + 1] = k
				end
			end
		end
	end
	Remotes.MechFX:FireAllClients("leapSlam", m, c, vs, ks)
	SM.play("MineBoom", c)
end
function LEAP.step()
	if next(LEAP.list) == nil then return end
	local now = workspace:GetServerTimeNow()
	local L = CFG.Leap
	for m, e in pairs(LEAP.list) do
		local mh = m:FindFirstChildOfClass("Humanoid")
		if not (m.Parent and mh and mh.Health > 0) or m:GetAttribute("LeapAt") ~= e.at then
			LEAP.list[m] = nil
		else
			local k = math.clamp((now - e.at) / L.Time, 0, 1)
			if k < 1 then
				local pos = e.from:Lerp(e.to, k) + Vector3.new(0, 4 * L.Height * k * (1 - k), 0)
				for _, o in ipairs(CollectionService:GetTagged("Mech")) do
					if o ~= m and not e.hit[o] and MINE.alive(o) and Dmg.canDamage(m, o)
						and CFG.bodyDist(o, pos) <= L.AirHit and LEAP.airborne(o) then
						e.hit[o] = true
						LEAP.airHit(m, o)
					end
				end
			else
				LEAP.list[m] = nil
				LEAP.slam(m, e)
			end
		end
	end
end
RunService.Heartbeat:Connect(LEAP.step)
ULT.kinds.AxeLeap = LEAP.cast
-- ================= 10-30 FELSEN 궁극기: 돌진 내려찍기 (Ultimate = "AxeCharge") — 규칙·수치 = MechConfig CFG.Charge =================
-- 유저 10-30 16:58 "사이온의 궁극기: 긴 선딜(1초) + 앞으로 돌진하며 점점 가속(최대치) + 부딪힌 적이나 지형지물이 있으면 즉시 들었던 도끼를
--   내려찍으며 즉시 정지 + 맞은 적에게 큰 데미지, 주변에는 광역" · 17:02 꺾기 가능 · 멀리서 달려올수록 피해 · 공중 적도 멈추고 내려찍기 ·
--   옆에 닿으면 밀쳐내고 계속(Claude 안 동의) · 17:13 도끼를 왼 어깨 옆으로 치켜든 사이드 돌격 자세
-- 움직임은 조종 화면이 직접(PlatformStand · 매 프레임 CFrame — 라이더킥과 같은 방식). 서버는 시작 · 멈춤(내려찍기) 받기 · 피해만
--   X → 속성 ChargeAt(마지막) → CFG.chargePhase "windup"(Windup) · "run"(최대 MaxTime) · "slam"(ChargeHitAt 부터 Slam)
--   원격 MechCharge "slam"(내 뿌리 자리, 맞은 기체 또는 nil) — 앞 부채꼴에 기체가 닿음 · 벽·지형에 막힘 · 다 달림
--     → ChargeHitAt · ChargeHitPos → Swing 초 뒤(도끼가 땅에 닿는 때) 상주 Heartbeat 가 피해:
--     직격(맞은 기체) = BaseDamage + 달린 거리 × PerStud(최대 MaxDamage) + 띄움 Launch(10-30 18:09 — 공중에 잠시 · 경직 1.5초) · 광역(내려찍은 자리 AoeRadius 안 · 직격 기체 빼고) = 직격 × AoeMul + 경직 AoeStun
--     달린 거리 = 서버 시각으로 계산(CFG.chargeDist — 꺾어도 거리는 같음, 조종 화면 말을 안 믿음)
--   "side"(옆에 닿은 기체) — 한 번에 한 번 SideDamage + 옆으로 SidePush 밀쳐냄 + 경직 SideStun(돌진은 계속)
--   신호가 안 오면(화면이 끊김) Windup + MaxTime + 0.6 에 지금 자리에서 저절로 내려찍음(맞은 기체 없음)
-- 잠금 = CFG.stunned · 슈퍼아머 = 선딜부터 내려찍고 거둘 때까지 · 도끼를 든 상태(Weapon = "saber")로 바꿈 · 내리면(park 가 ChargeAt 을 지움) 끝
local CHG = { list = {} }   -- [기체] = { at, sides = {}, slamAt, pos, dir, victim }
function CHG.cast(m, now, aim)
	local root, hum = m:FindFirstChild("HumanoidRootPart"), m:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return false end
	m:SetAttribute("BoostHold", nil); m:SetAttribute("BoostHoldAir", nil); m:SetAttribute("Climb", nil)
	m:SetAttribute("ReloadUntil", nil)
	if (m:GetAttribute("Weapon") or "rifle") ~= "saber" then   -- 도끼를 든 상태로(조종 화면은 X 누를 때 같이 바꿈 — GR.ult)
		m:SetAttribute("Weapon", "saber"); m:SetAttribute("WeaponAt", now)
	end
	m:SetAttribute("ChargeHitAt", nil); m:SetAttribute("ChargeHitPos", nil)
	m:SetAttribute("ChargeAt", now)   -- 마지막에(화면은 ChargeAt 이 바뀌면 새 돌진)
	CHG.list[m] = { at = now, sides = {} }
	return true
end
function CHG.slam(m, e, now, pos, victim)   -- 멈춤: 속성(모든 화면 자세) → Swing 뒤 피해(CHG.step)
	local root = m:FindFirstChild("HumanoidRootPart")
	local lv = root and root.CFrame.LookVector or Vector3.new(0, 0, -1)
	local fl = Vector3.new(lv.X, 0, lv.Z)
	e.slamAt, e.pos, e.victim = now, pos, victim
	e.dir = fl.Magnitude > 0.05 and fl.Unit or Vector3.new(0, 0, -1)
	m:SetAttribute("ChargeHitPos", pos)
	m:SetAttribute("ChargeHitAt", now)
	SM.play("SaberSwing", root or pos)
end
function CHG.impact(m, e)
	local C = CFG.Charge
	local now = workspace:GetServerTimeNow()
	local t = math.clamp(e.slamAt - e.at - C.Windup, 0, C.MaxTime)
	local dmg = math.floor(math.min(C.MaxDamage, C.BaseDamage + CFG.chargeDist(t) * C.PerStud) + 0.5)
	local c = e.pos + e.dir * C.Reach
	c = Vector3.new(c.X, groundY(c, { m }), c.Z)   -- 도끼가 닿는 땅
	local vs, ks = {}, {}
	local v = e.victim
	if v and v.Parent and v:IsDescendantOf(workspace) and MINE.alive(v) and Dmg.canDamage(m, v) then
		local vh = v:FindFirstChildOfClass("Humanoid")
		if vh and vh.Health > 0 then
			Dmg.hurt(m, v, vh, dmg)
			local vr = v:FindFirstChild("HumanoidRootPart")
			if vh.Health > 0 and vr then   -- 10-30 띄움: 그 자리 위로 Height → Air 초에 아래 땅으로 · 경직 Total(슈퍼아머면 startPull 이 거름)
				local LA = C.Launch
				local p = vr.Position
				local to = Vector3.new(p.X, groundY(p, { m, v }) + vh.HipHeight + vr.Size.Y / 2, p.Z)
				local lv = vr.CFrame.LookVector
				local face = Vector3.new(lv.X, 0, lv.Z)
				startPull(v, to, face.Magnitude > 0.1 and face.Unit or -e.dir, LA.Air, LA.Total - LA.Air, LA.Height)
			end
			vs[#vs + 1] = v; ks[#ks + 1] = 1
		end
	end
	local aoe = math.floor(dmg * C.AoeMul + 0.5)
	for _, o in ipairs(CollectionService:GetTagged("Mech")) do
		if o ~= m and o ~= v and MINE.alive(o) and Dmg.canDamage(m, o) and CFG.bodyDist(o, c) <= C.AoeRadius then
			local oh = o:FindFirstChildOfClass("Humanoid")
			if oh and oh.Health > 0 then
				Dmg.hurt(m, o, oh, aoe)
				if oh.Health > 0 and not CFG.superArmor(o, now) then
					o:SetAttribute("StunUntil", math.max(o:GetAttribute("StunUntil") or 0, now + C.AoeStun))
				end
				vs[#vs + 1] = o; ks[#ks + 1] = C.AoeMul
			end
		end
	end
	Remotes.MechFX:FireAllClients("chargeSlam", m, c, vs, ks)
	SM.play("MineBoom", c)
end
function CHG.side(m, e, v)   -- 옆에 닿음: 밀쳐냄(돌진 방향에서 옆으로) + 작은 피해 + 경직
	local C = CFG.Charge
	local r, vr, vh = m:FindFirstChild("HumanoidRootPart"), v:FindFirstChild("HumanoidRootPart"), v:FindFirstChildOfClass("Humanoid")
	if not (r and vr and vh and vh.Health > 0) then return end
	e.sides[v] = true
	if not (MINE.alive(v) and Dmg.canDamage(m, v)) then return end
	Dmg.hurt(m, v, vh, C.SideDamage)
	local lv = r.CFrame.LookVector
	local fwd = Vector3.new(lv.X, 0, lv.Z); fwd = fwd.Magnitude > 0.05 and fwd.Unit or Vector3.new(0, 0, -1)
	local rel = Vector3.new(vr.Position.X - r.Position.X, 0, vr.Position.Z - r.Position.Z)
	local side = rel - fwd * rel:Dot(fwd)
	side = side.Magnitude > 0.1 and side.Unit or fwd:Cross(Vector3.yAxis).Unit
	if vh.Health > 0 then
		local to = vr.Position + side * C.SidePush
		to = Vector3.new(to.X, groundY(to, { m, v }) + vh.HipHeight + vr.Size.Y / 2, to.Z)
		startPull(v, to, -side, C.SidePull, C.SideStun)
	end
	Remotes.MechFX:FireAllClients("chargeSide", m, v, vr.Position)
	SM.play("BodyHit", vr.Position)
end
function CHG.step()
	if next(CHG.list) == nil then return end
	local now = workspace:GetServerTimeNow()
	local C = CFG.Charge
	for m, e in pairs(CHG.list) do
		local mh = m:FindFirstChildOfClass("Humanoid")
		if not (m.Parent and mh and mh.Health > 0) or m:GetAttribute("ChargeAt") ~= e.at then
			CHG.list[m] = nil
		elseif e.slamAt then
			if now >= e.slamAt + C.Swing then
				CHG.list[m] = nil
				CHG.impact(m, e)
			end
		elseif now > e.at + C.Windup + C.MaxTime + 0.6 then   -- 화면 신호가 안 옴 → 지금 자리에서
			local r = m:FindFirstChild("HumanoidRootPart")
			if r then CHG.slam(m, e, now, r.Position, nil) else CHG.list[m] = nil end
		end
	end
end
RunService.Heartbeat:Connect(CHG.step)
ULT.kinds.AxeCharge = CHG.cast
Remotes.MechCharge.OnServerEvent:Connect(function(player, kind, a, b)
	local m = pilotMech(player); if not m then return end
	local e = CHG.list[m]; if not e or e.slamAt then return end
	local root = m:FindFirstChild("HumanoidRootPart"); if not root then return end
	local C = CFG.Charge
	local now = workspace:GetServerTimeNow()
	if now < e.at + C.Windup - 0.25 then return end   -- 달리기 전(0.25 = 화면 시계 어긋남 여유)
	if kind == "slam" then
		if typeof(a) ~= "Vector3" or a ~= a then return end
		if (a - root.Position).Magnitude > 25 + C.MaxSpeed * 0.35 then a = root.Position end   -- 서버 뿌리는 지연 — 몸을 CFrame 으로 놓아 복제 속도 0
		local victim = nil
		if typeof(b) == "Instance" and b ~= m and b:IsDescendantOf(workspace) and CollectionService:HasTag(b, "Mech")
			and CFG.bodyDist(b, a) <= C.Contact + 14 then victim = b end   -- 상대 자리 지연 여유
		CHG.slam(m, e, now, a, victim)
	elseif kind == "side" then
		if typeof(a) ~= "Instance" or a == m or e.sides[a] or not a:IsDescendantOf(workspace) or not CollectionService:HasTag(a, "Mech") then return end
		if CFG.bodyDist(a, root.Position) > C.Contact + 14 + C.MaxSpeed * 0.2 then return end
		CHG.side(m, e, a)
	end
end)
function ULT.step()
	if next(ULT.list) == nil then return end
	local now = workspace:GetServerTimeNow()
	for m in pairs(ULT.list) do
		local e = m:GetAttribute("UltEnd")
		if not m.Parent or not e then
			ULT.list[m] = nil
		elseif now >= e then
			ULT.list[m] = nil
			m:SetAttribute("Ammo", CFG.gun(m).MagSize); m:SetAttribute("ReloadUntil", nil)   -- 끝나면 탄창 가득 [경계 규칙 3]
			if not m:GetAttribute("UltKeep") and CFG.anchorPhase(m, e) == "on" then
				m:SetAttribute("AnchorRiseAt", e)   -- 원래 앵커가 아니었으면 끝난 시각부터 일어남(Rise 1.0) → 그 뒤 앵커 쿨 [경계 규칙 2]
				m:SetAttribute("AnchorReadyAt", e + CFG.Anchor.Rise + CFG.Anchor.Cooldown)
			end
			m:SetAttribute("UltStart", nil); m:SetAttribute("UltEnd", nil); m:SetAttribute("UltKeep", nil)
		end
	end
end
RunService.Heartbeat:Connect(ULT.step)
Remotes.MechUlt.OnServerEvent:Connect(function(player, aim)   -- 10-30 aim = 화면 조준점(FALCO 마비 덫 자리 · SKADI 는 안 씀)
	local m = pilotMech(player); if not m then return end
	local fn = ULT.kinds[m:GetAttribute("Ultimate") or ""]; if not fn then return end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	local now = workspace:GetServerTimeNow()
	if CFG.stunned(m, now) or CFG.ultPhase(m, now) or CFG.trapPhase(m, now) then return end
	if (m:GetAttribute("UltGauge") or 0) < CFG.Ult.Max then return end
	if not fn(m, now, aim) then return end
	m:SetAttribute("UltGauge", 0)
	ULT.list[m] = true
	SM.play("UltActivate", m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart)
end)

-- ================= 10-30 FALCO 시그니처: 라이더킥 (C) — 규칙·수치 = MechConfig CFG.RiderKick =================
-- 움직임은 조종 화면이 직접(PlatformStand · 매 프레임 CFrame — 앞차기 공중제비와 같은 방식). 서버는 시작 조건 · 맞음 판정 · 피해 · 끌고 감 · 날림만
--   "start"(뿌리 자리, 방향): 공중 · 경직 아님 · 쿨 끝 → 속성 RKFrom · RKDir · RKReadyAt · RKAt(마지막)
--   "hit"(맞은 기체, 발끝 자리): 급강하 중 한 번. 발끝이 내 뿌리에서 갈 수 있는 거리 · 상대 몸과의 거리를 다시 잼(지연 여유) → RKCarry · RKHitAt(마지막)
--     10-30 유저 "맞았을 때 상대를 밀고 가다 마지막에 크게 날림(추가 동작 없이 만화풍으로 피해를 누적받다 날아가는 느낌)":
--     다칠 수 있는 기체(IsMech · 슈퍼아머 아님) → RKCarry = Carry.Time. 찬 방향(수평)으로 Carry.Dist 끌고 감(넉백과 같은 길 = startPull) +
--       Carry.Gap 마다 TickDamage × Ticks(첫 대는 닿는 순간) → Carry.Time 에 나머지 피해(Damage − 대 합) + 멀리 날림(Launch, 포물선 Arc)
--       — 셈은 부팅 스레드 상주 Heartbeat(RK.step, 덫 TRAP.step 과 같은 형태). 찬 기체·맞은 기체가 죽거나 없어지면 거기서 끝(남은 피해·날림 없음)
--     기체 아님 · 슈퍼아머(다른 FALCO 가 킥 중) → 한 번에 Damage(안 끌림). 아군 → 피해 없음. 둘 다 RKCarry 없음 → 화면이 바로 튕김
--   "stop": 땅·벽에 닿았거나 다 감 → RKStopAt(자세 풀림). 안 와도 시각(RKAt + Ready + Range/Speed)이 지나면 저절로 끝
-- 슈퍼아머(CFG.superArmor) = startPull · 지뢰 경직이 봄 · 잠금 = CFG.stunned 에 포함(끌고 가는 동안도)
local RK = { list = {} }   -- [찬 기체] = { v = 맞은 기체, at = RKHitAt, n = 준 대 수, flat = 찬 방향(수평) }
function RK.diving(m, now)   -- 급강하 중(맞음·멈춤 전) + 지연 여유 0.3초
	local at = m:GetAttribute("RKAt")
	if not at or m:GetAttribute("RKHitAt") or m:GetAttribute("RKStopAt") then return false end
	local K = CFG.RiderKick
	return now >= at and now <= at + K.Ready + K.Range / K.Speed + 0.3
end
function RK.point(e)   -- 맞는 자리 = 상대 몸 앞(찬 쪽) — 화면 번쩍·소리
	local r = e.v:FindFirstChild("HumanoidRootPart")
	return r and (r.Position - e.flat * 3) or nil
end
function RK.tick(m, e, vh)   -- 끌고 가는 동안 한 대
	e.n += 1
	Dmg.hurt(m, e.v, vh, CFG.RiderKick.Carry.TickDamage)   -- 궁극기 게이지도 여기서 셈
	local p = RK.point(e)
	if p then
		Remotes.MechFX:FireAllClients("riderTick", m, e.v, p, e.n)
		SM.play("GunHit", p)
	end
end
function RK.launch(m, e, vh)   -- 끌고 간 끝: 나머지 피해 + 멀리 날림
	local K = CFG.RiderKick
	local rest = K.Damage - K.Carry.Ticks * K.Carry.TickDamage
	if rest > 0 then Dmg.hurt(m, e.v, vh, rest) end
	if vh.Health > 0 then knockback(m, e.v, e.flat, K.Launch.Dist, K.Launch.Time, K.Launch.Stun, K.Launch.Arc) end
	local p = RK.point(e)
	if p then
		Remotes.MechFX:FireAllClients("riderHit", m, e.v, p, true)
		SM.play("BodyHit", p)
	end
end
function RK.step()
	if next(RK.list) == nil then return end
	local now = workspace:GetServerTimeNow()
	local C = CFG.RiderKick.Carry
	for m, e in pairs(RK.list) do
		local mh, vh = m:FindFirstChildOfClass("Humanoid"), e.v:FindFirstChildOfClass("Humanoid")
		if not (m.Parent and mh and mh.Health > 0) or m:GetAttribute("RKHitAt") ~= e.at   -- 내림(park 가 RKHitAt 을 지움)·죽음
			or not e.v:IsDescendantOf(workspace) or not (vh and vh.Health > 0) or not Dmg.canDamage(m, e.v) then
			RK.list[m] = nil
		else
			while e.n < C.Ticks and now >= e.at + e.n * C.Gap and vh.Health > 0 do RK.tick(m, e, vh) end
			if now >= e.at + C.Time then
				RK.list[m] = nil
				if vh.Health > 0 then RK.launch(m, e, vh) end
			end
		end
	end
end
RunService.Heartbeat:Connect(RK.step)
Remotes.MechRiderKick.OnServerEvent:Connect(function(player, kind, a, b)
	local m = pilotMech(player); if not m then return end
	if m:GetAttribute("Signature") ~= "RiderKick" then return end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	local root = m:FindFirstChild("HumanoidRootPart"); if not root then return end
	local K = CFG.RiderKick
	local now = workspace:GetServerTimeNow()
	if kind == "start" then
		if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" or a ~= a or b ~= b or b.Magnitude < 0.5 then return end
		if CFG.stunned(m, now) or CFG.anchorPhase(m, now) then return end   -- stunned 안에 라이더킥 중도 들어 있음
		if (m:GetAttribute("RKReadyAt") or 0) > now + 0.2 then return end   -- 0.2 = 화면 시계 어긋남 여유
		if (a - root.Position).Magnitude > 16 + root.AssemblyLinearVelocity.Magnitude * 0.25 then return end
		-- 공중에서만: 발밑(뿌리 높이 + 2 안)에 아무것도 없어야(앵커의 땅 검사를 거꾸로 — 화면도 같은 검사)
		local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { m }
		if workspace:Raycast(root.Position, Vector3.new(0, -((m:GetAttribute("RootHeight") or 10) + 2), 0), rp) then return end
		m:SetAttribute("BoostHold", nil); m:SetAttribute("BoostHoldAir", nil); m:SetAttribute("Climb", nil)
		m:SetAttribute("RKHitAt", nil); m:SetAttribute("RKStopAt", nil); m:SetAttribute("RKCarry", nil)
		m:SetAttribute("RKFrom", a)
		m:SetAttribute("RKDir", CFG.riderDir(b))
		m:SetAttribute("RKReadyAt", now + K.Cooldown)
		m:SetAttribute("RKAt", now)   -- 마지막에(화면은 RKAt 이 바뀌면 새 킥)
		SM.play("JetIgnite", root)
	elseif kind == "hit" then
		if typeof(a) ~= "Instance" or typeof(b) ~= "Vector3" or b ~= b then return end
		if not RK.diving(m, now) then return end
		local victim = a
		if victim == m or not victim:IsDescendantOf(workspace) or not CollectionService:HasTag(victim, "Mech") then return end
		local vh = victim:FindFirstChildOfClass("Humanoid"); if not vh or vh.Health <= 0 then return end
		-- 발끝 = 뿌리에서 약 19 [에디트 FK] + 서버 뿌리 지연(몸을 CFrame 으로 놓아 복제 속도가 0 → 급강하 속도 × 0.35초로 봐줌)
		if (b - root.Position).Magnitude > 30 + K.Speed * 0.35 then return end
		if CFG.bodyDist(victim, b) > K.HitRadius + 14 then return end   -- 상대 자리 지연 여유(부스트 75 × 0.15 + 여유)
		local dir = m:GetAttribute("RKDir")
		local lv = root.CFrame.LookVector
		local flat = typeof(dir) == "Vector3" and Vector3.new(dir.X, 0, dir.Z) or Vector3.new(lv.X, 0, lv.Z)
		flat = flat.Magnitude > 0.05 and flat.Unit or Vector3.new(0, 0, -1)
		local dealt = Dmg.canDamage(m, victim) and true or false
		local carry = dealt and victim:GetAttribute("IsMech") and not CFG.superArmor(victim, now) and true or false
		m:SetAttribute("RKCarry", carry and K.Carry.Time or nil)
		m:SetAttribute("RKHitAt", now)   -- 마지막에(화면: RKCarry 가 있으면 끌고 감 · 없으면 튕김)
		if carry then
			local e = { v = victim, at = now, n = 0, flat = flat }
			RK.list[m] = e
			RK.tick(m, e, vh)   -- 첫 대 = 닿는 순간
			if vh.Health > 0 then knockback(m, victim, flat, K.Carry.Dist, K.Carry.Time, K.Carry.Stun)
			else RK.list[m] = nil end
		else
			if dealt then Dmg.hurt(m, victim, vh, K.Damage) end   -- 궁극기 게이지도 여기서 셈
			Remotes.MechFX:FireAllClients("riderHit", m, victim, b, dealt)
			if dealt then SM.play("BodyHit", b) end
		end
	elseif kind == "stop" then
		if not RK.diving(m, now) then return end
		m:SetAttribute("RKStopAt", now)
	end
end)

Remotes.MechGrab.OnServerEvent:Connect(function(player, aimPoint, muzzle)
	local m = pilotMech(player); if not m then return end
	if m:GetAttribute("Signature") ~= "Grab" then return end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	local now = workspace:GetServerTimeNow()
	if aimPoint == "wind" then   -- 10-31 준비 동작 시작(모든 화면이 GrabWindAt 으로 팔을 뒤로 당김) · 쏘기는 클라가 Windup 뒤 다시 보냄
		if CFG.stunned(m, now) or (m:GetAttribute("GrabReadyAt") or 0) > now then return end
		m:SetAttribute("GrabWindAt", now)
		return
	end
	if CFG.grabPhase(m, now) ~= "wind" and CFG.stunned(m, now) then return end   -- 준비 동작 중(내 잠금)엔 쏠 수 있음
	if typeof(aimPoint) ~= "Vector3" or aimPoint ~= aimPoint then return end
	GRAB.fire(m, aimPoint, muzzle)
end)
_G.MechGrabFire = GRAB.fire   -- 시험·디버그용

-- ================= 근접 (R 빔사벨) =================
-- 판정은 서버: 누른 뒤 strike 초에 기체 앞 부채꼴 안의 메카·표적을 한 번씩 맞힌다(같은 대상 두 번 X).
-- 휘두르는 모습은 속성 MeleeKind / MeleeAt(서버 시각)으로 모든 클라가 같은 식으로 그린다.
-- 판정 시각의 내 위치도 상대 위치도 서버가 아는 값이라, 요청 지연과 위치 지연이 같은 방향으로 겹쳐 대체로 맞는다.
local MELEE = {
	saber = { damage = CFG.SaberDamage, cooldown = CFG.SaberCooldown, strike = CFG.SaberStrike, range = CFG.SaberRange, arc = CFG.SaberArc },
	punch = { damage = CFG.PunchDamage, cooldown = CFG.PunchCooldown, strike = CFG.PunchStrike, range = CFG.PunchRange, arc = CFG.PunchArc, weapon = "rifle" },
	-- 10-30 SKADI 앞차기(템플릿 속성 Melee = "Kick" 인 기체만 · 그 기체는 빔사벨 종류를 못 씀): 한 번 판정 + 넉백(knock)
	kick = { damage = CFG.Kick.Damage, cooldown = CFG.Kick.Cooldown, strike = CFG.Kick.Strike, range = CFG.Kick.Range, arc = CFG.Kick.Arc, weapon = "rifle", knock = true },
	-- 빔사벨을 든 상태(2)에서 좌클릭 베기: 뽑는 동작이 없어 판정이 빠르다
	-- activeEnd(10-25 14:24) = 판정 구간 끝(동작표 시각). strike ~ activeEnd 동안 매 프레임 검사(meleeStrike). 없으면 strike 한 순간
	slash1 = { damage = CFG.SlashDamage, cooldown = CFG.SlashCooldown, strike = CFG.SlashStrike, activeEnd = CFG.SlashActiveEnd, range = CFG.SaberRange, arc = CFG.SaberArc, weapon = "saber" },
	-- 3연격 2·3타: 바로 앞 타에 이어서만 받는다(아래 lastSlash)
	slash2 = { damage = CFG.Slash2Damage, cooldown = CFG.SlashCooldown, strike = CFG.Slash2Strike, activeEnd = CFG.Slash2ActiveEnd, range = CFG.SaberRange, arc = CFG.SaberArc, weapon = "saber" },
	-- 3타 찌르기: 더 멀리(Slash3Range) 대신 좁게(Slash3Arc)
	slash3 = { damage = CFG.Slash3Damage, cooldown = CFG.SlashCooldown, strike = CFG.Slash3Strike, activeEnd = CFG.Slash3ActiveEnd, range = CFG.Slash3Range, arc = CFG.Slash3Arc, weapon = "saber" },
}
local SLASH_STEP = { slash1 = 1, slash2 = 2, slash3 = 3 }
-- 빔사벨 휘두르는 속도(2026-10-25): 판정 시각도 CFG.SaberSlow 배(클라가 동작을 같은 배율로 느리게 그린다). 주먹은 그대로
-- 판정 구간 길이 window(실제 초) = (activeEnd − strike) × 같은 배율
for kind, s in pairs(MELEE) do
	local slow = (kind ~= "punch" and kind ~= "kick") and (CFG.SaberSlow or 1) or 1   -- 10-30 앞차기도 주먹처럼 실제 초
	if s.activeEnd then s.window = math.max(0, s.activeEnd - s.strike) * slow end
	s.strike *= slow
end
-- 10-27 기체별 근접 수치(CFG.Types[MechType].Melee — FELSEN 열선 도끼 두 손 3연격). 있으면 그 기체 3연격 판정표를 따로 만듦(기체 종류마다 한 번).
--   시각은 그 표의 slow 배(도끼 = 1, 실제 초). 없는 기체·없는 종류(saber 뽑아 베기·punch)는 위 MELEE 그대로
local meleeCache = {}
local function meleeSpecFor(m, kind)
	local base = MELEE[kind]
	local mo = CFG.meleeOver(m)
	local o = mo and mo[kind]
	if not (base and o) then return base end
	local key = (m:GetAttribute("MechType") or "?") .. "/" .. kind
	local c = meleeCache[key]
	if c then return c end
	local slow = mo.slow or 1
	c = {}
	for k, v in pairs(base) do c[k] = v end
	c.damage = o.damage or base.damage
	c.cooldown = o.cooldown or base.cooldown
	c.range = o.range or base.range
	c.arc = o.arc or base.arc
	c.strike = (o.strike or 0) * slow
	c.window = o.activeEnd and math.max(0, o.activeEnd - (o.strike or 0)) * slow or base.window
	meleeCache[key] = c
	return c
end
local lastSlash = {}   -- [player] = { step, at(os.clock) }
MELEE.saber.weapon = "rifle"   -- R 뽑아 베기는 라이플 상태에서만(빔사벨 상태에선 클라가 slash 로 보낸다)
local lastMelee, lastMeleeSlow = {}, {}   -- 10-30 lastMeleeSlow = 마지막 근접을 받을 때 둔화 배율(마비 덫 — 쿨도 그만큼)

-- 임시 진단(10-25 14:24): 판정 구간이 들어간 빔사벨 베기마다 출력 창에 한 줄 요약(맞음/빗나감, 가장 가까웠을 때 거리·각·높이차).
--   유저 테스트 로그로 "대시 연계 판정" 원인을 확인한 뒤 false 로 끈다
local MELEE_DIAG = false   -- 14:36 확인 끝(유저 "이대로 두자") → 끔. 다시 볼 때 true

-- 판정(10-25 14:24 구간 판정): strike 시각에 한 번 보고, spec.window(> 0)가 있으면 그 시간 동안 매 Heartbeat 다시 본다.
--   원점 = 그 프레임의 내 몸 위치(대시로 파고드는 것 반영), 방향 dir 은 누른 순간 값 고정. 같은 대상은 한 번만(done).
--   예전: strike 한 순간만 → 대시 연계 때 그 순간의 거리(대시 0.05초 = 약 6스터드)에 따라 맞고 안 맞음이 갈렸다(유저 영상 9번 중 3번만)
local function meleeStrike(m, dir, spec, kind)
	if not m.Parent then return end
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	if not m:FindFirstChild("HumanoidRootPart") then return end
	local cosArc = math.cos(math.rad(spec.arc))
	local done = {}
	local flipped = false   -- 10-30 앞차기 공중제비: 한 번 차기에 한 번(여럿 맞혀도)
	local diag = (MELEE_DIAG and spec.window) and {} or nil   -- [model] = { d, ang, dy, lim, hitAt }
	local function consider(model, origin, tOff)
		if model == m or done[model] or not model.Parent then return end
		if not Dmg.canDamage(m, model) then return end
		local h = model:FindFirstChildOfClass("Humanoid")
		local r = model:FindFirstChild("HumanoidRootPart")
		if not h or not r or h.Health <= 0 then return end
		local d = r.Position - origin
		local flat = Vector3.new(d.X, 0, d.Z)
		local bodyR = model:GetAttribute("IsMech") and 4 or 1.5      -- 상대 몸 반지름만큼 더 닿는다
		if diag then
			local rec = diag[model]
			if not rec or flat.Magnitude < rec.d then
				local ang = flat.Magnitude > 0.01 and math.deg(math.acos(math.clamp(flat.Unit:Dot(dir), -1, 1))) or 0
				diag[model] = { d = flat.Magnitude, ang = ang, dy = d.Y, lim = spec.range + bodyR, hitAt = rec and rec.hitAt }
			end
		end
		if flat.Magnitude - bodyR > spec.range or math.abs(d.Y) > 16 then return end
		if flat.Magnitude > 3 and flat.Unit:Dot(dir) < cosArc then return end
		done[model] = true
		if diag and diag[model] then diag[model].hitAt = tOff end
		Dmg.hurt(m, model, h, spec.damage)   -- 10-30 궁극기 게이지도 여기서 셈
		Remotes.MechFX:FireAllClients("melee", m, model, kind)
		if spec.knock and model:GetAttribute("IsMech") and h.Health > 0 then knockback(m, model, dir) end   -- 10-30 SKADI 앞차기
		if spec.knock and model:GetAttribute("IsMech") and not flipped then   -- 10-30 맞힌 기체를 디딤발 삼아 뒤로 공중제비(쓰러뜨렸어도)
			flipped = true
			kickFlip(m, dir, { m, model })
		end
	end
	-- 메카끼리만: 시험장 표적(높이 9)은 날이 지나는 높이보다 낮아 화면에선 안 닿는데 맞는 셈이 되어 뺐다
	local function pass(tOff)
		local r0 = m:FindFirstChild("HumanoidRootPart"); if not r0 then return end
		for _, other in ipairs(CollectionService:GetTagged("Mech")) do consider(other, r0.Position, tOff) end
	end
	local function report()
		if not diag then return end
		for model, rec in pairs(diag) do
			print(string.format("[MeleeDiag] %s %s  가장 가까울 때: 몸 중심 %.1f (한계 %.0f) · 정면에서 %.0f° (한계 %.0f°) · 높이차 %.1f  · 구간 %.2fs",
				kind, rec.hitAt and string.format("맞음 +%.2fs", rec.hitAt) or "빗나감",
				rec.d, rec.lim, rec.ang, spec.arc, rec.dy, spec.window))
		end
		if next(diag) == nil then print(string.format("[MeleeDiag] %s 빗나감  (다칠 수 있는 기체 없음)", kind)) end
	end
	pass(0)
	local dur = spec.window or 0
	if dur <= 0 then report(); return end
	-- 끝내는 길 보장: 시간이 다 됐거나 내 기체가 없어지거나 죽으면 먼저 끊고, 검사는 pcall(한 프레임 오류로 연결이 영영 남지 않게)
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local e = os.clock() - t0
		local alive = m.Parent ~= nil and hum.Health > 0
		local last = e >= dur or not alive
		if last then conn:Disconnect() end
		if alive then pcall(pass, math.min(e, dur)) end
		if last then report() end
	end)
end
_G.MechMeleeStrike = meleeStrike   -- 적 메카 AI(MechEnemy)가 같은 판정을 쓴다

local function startMelee(m, kind, dir)
	local spec = meleeSpecFor(m, kind); if not spec then return false end
	local root = m:FindFirstChild("HumanoidRootPart"); if not root then return false end
	local lv = root.CFrame.LookVector
	local look = Vector3.new(lv.X, 0, lv.Z).Unit
	if typeof(dir) == "Vector3" and dir == dir then dir = Vector3.new(dir.X, 0, dir.Z) else dir = look end
	if dir.Magnitude < 0.1 then dir = look else dir = dir.Unit end
	if dir:Dot(look) < -0.2 then dir = look end   -- 몸이 도는 중이라 정면과 조금 달라도 받되, 등 뒤 방향은 정면으로
	-- 10-30 마비 덫: 시작할 때 둔화 배율로 끝까지(판정 시각·구간 × 배율 — 표는 같이 쓰므로 복사해서). 화면은 속성 MeleeSlow 로 같은 배율
	local sl = CFG.slowMul(m)
	if sl ~= 1 then
		local c = {}
		for k, v in pairs(spec) do c[k] = v end
		c.strike = spec.strike * sl
		if spec.window then c.window = spec.window * sl end
		spec = c
	end
	m:SetAttribute("MeleeSlow", sl ~= 1 and sl or nil)
	m:SetAttribute("MeleeKind", kind)
	m:SetAttribute("MeleeAt", workspace:GetServerTimeNow())
	task.delay(spec.strike, meleeStrike, m, dir, spec, kind)
	return true
end
_G.MechStartMelee = startMelee

Remotes.MechMelee.OnServerEvent:Connect(function(player, kind, dir)
	if not MELEE[kind] then return end
	local m = pilotMech(player); if not m then return end
	local spec = meleeSpecFor(m, kind)   -- 10-27 기체별(도끼 두 손 3연격)
	local mo = CFG.meleeOver(m)
	local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
	if CFG.stunned(m) then return end   -- 10-27 그랩 경직 중
	-- 10-30 근접 칸 = 기체 속성 Melee: "Kick"(SKADI) 이면 앞차기·주먹만, 아니면 앞차기 못 씀
	local isKick = m:GetAttribute("Melee") == "Kick"
	if kind == "kick" and not isKick then return end
	if isKick and kind ~= "kick" and kind ~= "punch" then return end
	if CFG.anchorPhase(m) then return end   -- 10-30 앵커 중엔 근접 못 함(다리가 박혀 있음)
	local now = os.clock()
	-- 무장 조건(플레이어만. 적 AI 는 startMelee 를 바로 부른다): 빔사벨 베기는 들기 동작이 끝난 뒤
	local wNow = m:GetAttribute("Weapon") or "rifle"
	if spec.weapon and spec.weapon ~= wNow then return end
	local wat = m:GetAttribute("WeaponAt")
	if wat and workspace:GetServerTimeNow() - wat < ((wNow == "saber") and CFG.EquipTime or CFG.UnequipTime) * 0.8 then return end
	local step = SLASH_STEP[kind]
	if step and step > 1 then
		-- 2·3타: 바로 앞 타가 있었고, 이어지는 시각(Chain) 언저리일 때만. 지연을 감안해 앞뒤로 여유
		local last = lastSlash[player]
		if not last or last.step ~= step - 1 then return end
		local o1 = mo and mo["slash" .. (step - 1)]   -- 앞 타의 chain(이어지는 시각)
		local chain = (o1 and o1.chain) and (o1.chain * (mo.slow or 1)) or (((step == 2) and CFG.SlashChain1 or CFG.SlashChain2) * (CFG.SaberSlow or 1))
		chain *= (last.slow or 1)   -- 10-30 마비 덫: 앞 타가 느려졌으면 이어지는 시각도
		local dt = now - last.at
		if dt < chain * 0.8 or dt > chain + 0.45 then return end
	else
		-- 3타(찌르기) 뒤엔 마무리 빈틈만큼 더 기다린다
		local cd = spec.cooldown
		if lastSlash[player] and lastSlash[player].step == 3 then cd = math.max(cd, (mo and mo.slash3Cooldown) or CFG.Slash3Cooldown) end
		if lastMelee[player] and now - lastMelee[player] < cd * (lastMeleeSlow[player] or 1) * 0.8 then return end
	end
	local slM = CFG.slowMul(m)
	lastMelee[player] = now
	lastMeleeSlow[player] = slM
	lastSlash[player] = step and { step = step, at = now, slow = slM } or nil   -- 빔사벨 아닌 근접(주먹·뽑아 베기)이면 연격 기록 지움
	startMelee(m, kind, dir)
end)

-- ================= 무장 교체 (1 라이플 / 2 빔사벨) =================
-- 상태 = 속성 Weapon("rifle"|"saber", 없으면 rifle) + WeaponAt(바꾼 서버 시각). 모든 클라가 이걸로 들기·넣기 동작을 그린다
local lastSwitch = {}
Remotes.MechWeapon.OnServerEvent:Connect(function(player, w)
	if w ~= "rifle" and w ~= "saber" then return end
	local m = pilotMech(player); if not m then return end
	if (m:GetAttribute("Weapon") or "rifle") == w then return end
	if CFG.stunned(m) then return end   -- 10-27 그랩 경직 중
	if w == "saber" and m:GetAttribute("Melee") == "Kick" then return end   -- 10-30 SKADI 는 빔사벨 없음(근접 = 앞차기)
	m:SetAttribute("GunSpinAt", nil)    -- 10-27 개틀링: 무장을 바꾸면 회전 멈춤
	local now = os.clock()
	if lastSwitch[player] and now - lastSwitch[player] < 0.25 then return end
	lastSwitch[player] = now
	m:SetAttribute("Weapon", w)
	m:SetAttribute("WeaponAt", workspace:GetServerTimeNow())
	-- 무장을 바꾸면 장전 취소(2026-10-25 유저 결정). 남은 발은 그대로, 끝내는 예약은 시각이 안 맞아 아무것도 안 한다
	m:SetAttribute("ReloadUntil", nil)
end)

-- ================= 주무기 교체 (2026-10-25 저격총) — 시험장 무기 거치대 =================
-- 총 견본: ReplicatedStorage.MechProto.Guns.<rifle|sniper> 안에 Hand(손에 드는 MeshPart: 속성 GripC1·LeftHand, 자식 Muzzle)
--   + Stowed(등에 다는 MeshPart: 속성 StowCF = 백팩 기준 자리). 기체 속성 Gun 이 지금 든 총.
-- ⚠️ 손 파트는 늘 "Rifle", 등 파트는 늘 "RifleStowed" 라는 이름으로 넣는다(주무기 "자리" 이름. 라이플·장전·두 손 자세 코드가 이 이름으로 찾음)
-- ⚠️ Grip 관절은 새로 만들지 않고 같은 인스턴스를 새 파트로 옮긴다 — 각 클라 애니(st.J.Grip)가 처음 찾은 관절을 붙잡고 있어서
--    새 관절을 만들면 그 관절은 애니가 안 돌아 총이 굳는다
local GunsFolder = Proto:WaitForChild("Guns", 5)
local function setGun(m, kind)
	local def = GunsFolder and GunsFolder:FindFirstChild(kind)
	if not def or not CFG.Guns[kind] then return false end
	if (m:GetAttribute("Gun") or "rifle") == kind then return false end
	local old, oldS = m:FindFirstChild("Rifle"), m:FindFirstChild("RifleStowed")
	local grip = old and old:FindFirstChild("Grip")
	-- 수납 기준 파트(10-26): 기체 속성 StowPart(중장갑 = Torso, 허리 뒤 라이플). 없으면 백팩. StowAdjust 도 이 파트 기준
	local bp = m:FindFirstChild(m:GetAttribute("StowPart") or "Backpack")
	local hT, sT = def:FindFirstChild("Hand"), def:FindFirstChild("Stowed")
	if not (old and oldS and grip and bp and hT and sT) then return false end
	-- 손
	local hand = hT:Clone(); hand.Name = "Rifle"
	hand.CFrame = old.CFrame
	hand.Parent = m
	grip.Part1 = hand
	grip.C1 = hT:GetAttribute("GripC1") or grip.C1
	grip.Parent = hand
	old:Destroy()
	-- 등: 먼저 백팩 기준 자리에 놓고 그 자리에서 묶는다(WeldConstraint 는 만들 때의 상대 위치를 고정할 뿐)
	local back = sT:Clone(); back.Name = "RifleStowed"
	-- 기체 속성 StowAdjust(10-25 Aero): 기체마다 수납 자리 보정(Aero = 등 가운데 세로, 오른쪽 엔진 피함). 없으면 그대로
	local sCF = sT:GetAttribute("StowCF")
	back.CFrame = sCF and (bp.CFrame * (m:GetAttribute("StowAdjust") or CFrame.new()) * sCF) or oldS.CFrame
	local w = Instance.new("WeldConstraint"); w.Part0 = bp; w.Part1 = back; w.Parent = back
	back.Parent = m
	oldS:Destroy()
	m:SetAttribute("Gun", kind)
	m:SetAttribute("ReloadUntil", nil)                    -- 장전 취소(예약은 시각이 안 맞아 그냥 지나감)
	m:SetAttribute("Ammo", CFG.Guns[kind].MagSize)        -- 새 총은 꽉 찬 탄창
	for _, a in ipairs({ "GunHeat", "GunHeatAt", "GunLockUntil", "GunSpinAt" }) do m:SetAttribute(a, nil) end   -- 10-27 과열·회전은 총마다 처음부터
	SM.play("PodDrop", bp.Position)                       -- 임시: 철컥(교체음)
	return true
end
_G.MechSetGun = setGun   -- 시험·디버그용

-- 거치대: workspace.MechTestRange.WeaponRack 안의 ProximityPrompt 중 속성 RackGun(= 총 이름)이 있는 것. 이름으로 찾지 않는다
local lastGunSwap = {}
local function hookRack(rack)
	for _, pp in ipairs(rack:GetDescendants()) do
		if pp:IsA("ProximityPrompt") and pp:GetAttribute("RackGun") then
			pp.Triggered:Connect(function(player)
				local m = pilotMech(player); if not m then return end            -- 기체에 탄 채로만
				local hum = m:FindFirstChildOfClass("Humanoid"); if not hum or hum.Health <= 0 then return end
				local now = os.clock()
				if lastGunSwap[player] and now - lastGunSwap[player] < 0.5 then return end
				lastGunSwap[player] = now
				setGun(m, pp:GetAttribute("RackGun"))
			end)
		end
	end
end
do
	local rack = Range:FindFirstChild("WeaponRack")
	if rack then hookRack(rack) end
end
Players.PlayerRemoving:Connect(function(p) lastGunSwap[p] = nil end)

-- 에너지 회복·지속 부스트 소모(10Hz)
-- 지속 중(BoostHold): 초당 BoostHoldDrain(공중 × BoostAirDrainMul) 소모, 회복 없음. 바닥나면 지속을 끄고 과열(OverheatUntil) 동안 회복 정지
-- 10-27 유저 "공중 부스트 소모는 좀 줄이되 게이지의 회복은 땅에서만"(AELLO): 소모 두 값을 기체 종류별(CFG.stat)로 읽고,
--   종류 표 AirRegen = false 면 떠 있는 동안 회복하지 않는다. 떠 있음 = 서버가 HRP 아래로 (서 있는 높이 + AIR_MARGIN) 광선을 쏴
--   아무것도 안 맞음 — 클라가 보내는 공중 여부를 믿지 않음(거짓 '땅' 으로 공중 회복 못 하게). 서 있는 높이 = HipHeight + HRP 높이/2 (AELLO 17.25 · 중장갑 15.05 실측)
local AIR_MARGIN = 3   -- 걷기 출렁임·웅크림은 HRP 가 낮아지는 쪽이라 땅으로 남고, 점프는 3 넘게 뜨면 공중
local airRay = RaycastParams.new(); airRay.FilterType = Enum.RaycastFilterType.Exclude
local function airborne(m)
	local r = m:FindFirstChild("HumanoidRootPart"); local h = m:FindFirstChildOfClass("Humanoid")
	if not r or not h then return false end
	airRay.FilterDescendantsInstances = { m }
	return workspace:Raycast(r.Position, Vector3.new(0, -(h.HipHeight + r.Size.Y / 2 + AIR_MARGIN), 0), airRay) == nil
end
task.spawn(function()
	while true do
		local dt = task.wait(0.1)
		local nowS = workspace:GetServerTimeNow()
		for _, m in ipairs(CollectionService:GetTagged("Mech")) do
			if m:GetAttribute("Pilot") then
				local e = m:GetAttribute("Energy") or 0
				if m:GetAttribute("BoostHold") then
					e -= CFG.stat(m, "BoostHoldDrain") * (m:GetAttribute("BoostHoldAir") and CFG.stat(m, "BoostAirDrainMul") or 1) * dt
					if e <= 0 then
						e = 0
						m:SetAttribute("BoostHold", nil); m:SetAttribute("BoostHoldAir", nil); m:SetAttribute("Climb", nil)
						m:SetAttribute("OverheatUntil", nowS + CFG.BoostOverheat)
					end
					m:SetAttribute("Energy", e)
				elseif (m:GetAttribute("OverheatUntil") or 0) <= nowS and e < CFG.stat(m, "MaxEnergy")
					and (CFG.stat(m, "AirRegen") ~= false or not airborne(m)) then
					m:SetAttribute("Energy", math.min(CFG.stat(m, "MaxEnergy"), e + CFG.stat(m, "EnergyRegen") * dt))   -- 18:24 기체 종류별
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local h = pilotStore:FindFirstChild(tostring(player.UserId)); if h then h:Destroy() end
	lastFire[player] = nil; lastBoost[player] = nil; lastMelee[player] = nil; lastMeleeSlow[player] = nil; lastSwitch[player] = nil; lastSlash[player] = nil
end)

-- ================= 시험장 =================
-- 표적: 죽지 않고 0이 되면 체력이 다시 찬다
for _, d in ipairs(Range:GetChildren()) do
	if d:GetAttribute("TargetDummy") then
		local h = d:FindFirstChildOfClass("Humanoid")
		h:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		h.BreakJointsOnDeath = false
		local label = d:FindFirstChild("HP", true)
		local function refresh()
			if label then label.Text = string.format("%d / %d", math.max(0, math.floor(h.Health + 0.5)), h.MaxHealth) end
		end
		h.HealthChanged:Connect(function(v)
			refresh()
			if v <= 0 then
				task.delay(0.6, function() h.Health = h.MaxHealth; refresh() end)
			end
		end)
		refresh()
	end
end
-- 피해 발판: 위에 있는 휴머노이드에 0.5초마다 15 피해 (메카에 탄 상태면 메카가 맞는다)
local pad = Range:FindFirstChild("DamagePad")
if pad then
	local op = OverlapParams.new()
	task.spawn(function()
		while true do
			task.wait(0.5)
			local seen = {}
			for _, part in ipairs(workspace:GetPartBoundsInBox(pad.CFrame + Vector3.new(0, 4, 0), Vector3.new(pad.Size.X, 8, pad.Size.Z), op)) do
				local model = part:FindFirstAncestorOfClass("Model")
				local h = model and model:FindFirstChildOfClass("Humanoid")
				if h and not seen[h] and h.Health > 0 and not model:GetAttribute("TargetDummy") then
					seen[h] = true
					h:TakeDamage(15)
				end
			end
		end
	end)
end
