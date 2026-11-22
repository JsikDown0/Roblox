-- KingAbsorbClient : 처치 → 킹 흡수 연출
--
-- [왜] 몸집 강화가 조용히 일어나서 눈치채기 어렵다는 실측(2026-09-15).
--   "커졌다"는 결과만 있고 "왜 커졌는지"를 잇는 순간이 없었다.
--   처치한 자리에서 정기가 빨려오는 연출이 그 인과를 만든다.
--
-- [형태] 처치 위치 → 킹 몸통으로 날아가는 파티클 + 도착 순간 펄스.
--   ⚠️ 전원에게 보인다. 러너도 "저 킹이 지금 강해졌다"를 읽어야 한다 —
--     카운터 표식(킹 전용)과 반대 판단이다. 저건 킹의 판단 재료였고, 이건 경고다.
--
-- [색] ReplicatedStorage.PushChargeFx 의 단계 색을 그대로 쓴다.
--   Stage1 주황(255,190,110) / Stage2 금(255,235,130) / Stage3 적(255,90,60)
--   ⚠️ 새 팔레트를 만들지 않는다. 손 이펙트와 같은 색이라 "같은 힘"으로 읽힌다.
--   ⚠️ 진영색 규칙(킹 크림슨 / 러너 청 / 금색=VIP)과는 축이 다르다 —
--     이건 진영 표시가 아니라 강화 단계 표시이고, 이미 그 팔레트가 있다.
--
-- ⚠️ 서버가 위치를 보낸다. 클라가 캐릭터를 직접 찾으면 아직 복제 안 된 순간이 있다.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local remote = ReplicatedStorage:WaitForChild("KingAbsorbFx")

local STAGE_COLOR = {
	[1] = Color3.fromRGB(255, 190, 110),
	[2] = Color3.fromRGB(255, 235, 130),
	[3] = Color3.fromRGB(255,  90,  60),
}

local TRAVEL   = 0.55    -- 날아가는 시간(초)
local ORB_SIZE = 1.4

-- 🔊 흡수 도착음.
--   ⚠️ 배율이 오를수록 피치를 올려 "차오른다"를 소리로도 전달한다.
--     상한(2.5) 에서 1.25 배. 그 이상은 찢어진다.
--   ⚠️ [2026-09-15] Gauntlet FullChargeSound(126858420392396) 재사용에서 교체.
--     그건 차징 완료음이라 "강화됐다"와 의미가 어긋났다.
local ABSORB_SOUND = "rbxassetid://100023990178384"   -- 레벨업
-- ⚠️ 이 음원은 3.74초로 길다(실측). 연속 처치 간격이 0.2초까지 나오므로
--   (실측 2026-09-15 10:55:34.121 → 34.320) 그냥 두면 소리가 겹겹이 쌓인다.
--   → 재생 중이면 앞의 것을 끊고 새로 시작한다. 마지막 처치의 피치가 들리는 게 맞다.
local absorbSnd   -- 현재 재생 중인 인스턴스 (하나만 유지)

local function playAbsorb(root, scale)
	if absorbSnd and absorbSnd.Parent then
		absorbSnd:Destroy()
	end
	local s = Instance.new("Sound")
	s.SoundId = ABSORB_SOUND
	s.Volume = 0.5
	-- 1.0 → 1.25 로 선형. scale 은 1.0~2.5 범위다.
	s.PlaybackSpeed = 1 + math.clamp((scale - 1) / 1.5, 0, 1) * 0.25
	s.RollOffMaxDistance = 140
	s.Parent = root
	s:Play()
	absorbSnd = s
	Debris:AddItem(s, 5)
end

local function makeOrb(pos, color)
	local p = Instance.new("Part")
	p.Name = "_AbsorbOrb"
	p.Size = Vector3.new(ORB_SIZE, ORB_SIZE, ORB_SIZE)
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Position = pos
	p.Parent = workspace

	local att = Instance.new("Attachment", p)
	local trail = Instance.new("ParticleEmitter")
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 1
	trail.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = NumberRange.new(0.25, 0.4)
	trail.Rate = 120
	trail.Speed = NumberRange.new(0)
	trail.Parent = att
	return p
end

-- 도착 펄스. 킹 몸통에서 한 번 터진다.
local function pulse(root, color)
	local a = Instance.new("Attachment", root)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 3.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.35, 0.5)
	e.Speed = NumberRange.new(6, 11)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = a
	e:Emit(26)
	Debris:AddItem(a, 1.2)
end

remote.OnClientEvent:Connect(function(fromPos, kingChar, stage, scale)
	if typeof(fromPos) ~= "Vector3" then return end
	local color = STAGE_COLOR[stage] or STAGE_COLOR[1]
	local root = kingChar and kingChar:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local orb = makeOrb(fromPos, color)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		-- ⚠️ 킹이 움직이므로 목표를 매 프레임 다시 읽는다. 시작 시점에 고정하면
		--   빗나가서 "빨려든다"가 안 읽힌다.
		if not (orb.Parent and root.Parent) then
			conn:Disconnect()
			if orb.Parent then orb:Destroy() end
			return
		end
		local a = math.clamp((os.clock() - t0) / TRAVEL, 0, 1)
		-- 가속: 끝에서 빨라져야 '빨려든다'로 읽힌다
		local e = a * a
		orb.Position = orb.Position:Lerp(root.Position, math.clamp(e * 0.55 + 0.08, 0, 1))
		if a >= 1 then
			conn:Disconnect()
			pulse(root, color)
			playAbsorb(root, scale or 1)
			orb:Destroy()
		end
	end)
	Debris:AddItem(orb, TRAVEL + 1.5)   -- 안전망: 루프가 끊겨도 남지 않는다
end)
