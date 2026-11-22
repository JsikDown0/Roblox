-- HammerSpinFxClient: DruidHammer 스핀 시 세계수 Billboard(페이드) + 나뭇잎 파티클.
-- 서버가 FireAllClients(targetPlayer, "start"/"stop") 보내면 로컬 생성/정리.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ev = RS:WaitForChild("HammerSpinFx")

local WORLDTREE_ID = "rbxassetid://90288427315816"
local LEAF_ID      = "rbxassetid://80993745818039"  -- 네잎클로버

-- 플레이어별 활성 FX 추적 (중복 방지 + 정리)
local active = {}  -- [player] = {tree=BillboardGui, leafPart=Part}

-- 🤖 [2026-09-12] 인자를 Player → Character 로 바꿨다.
--   [왜] 봇은 Player 가 없다. 캐릭터 모델이면 유저·봇을 같은 코드로 다룰 수 있다.
--   ⚠️ active 테이블의 키도 캐릭터가 된다. 리스폰하면 새 모델이라 자동으로 갈린다.
local function startFx(char)
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if active[char] then return end  -- 이미 실행 중

	local rec = {}

	-- ① 세계수 Billboard (러너 위, 정면 고정, 페이드 인)
	local anchor = Instance.new("Part")
	anchor.Name = "_WorldTreeAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Massless = true
	anchor.CFrame = hrp.CFrame
	anchor.Parent = workspace
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hrp; weld.Part1 = anchor; weld.Parent = anchor
	anchor.Anchored = false

	local bb = Instance.new("BillboardGui")
	bb.Name = "WorldTreeBB"
	bb.Size = UDim2.fromScale(18, 18)       -- 크기 (F5 튜닝 대상)
	bb.StudsOffset = Vector3.new(0, 8, 0) -- 러너 머리 위 높이
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Adornee = anchor
	bb.Parent = anchor

	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = WORLDTREE_ID
	img.ImageTransparency = 1  -- 페이드 인 시작
	img.Parent = bb
	rec.tree = anchor
	rec.treeImg = img

	-- 페이드 인 (0.4초)
	task.spawn(function()
		local t = 0
		while t < 0.4 and img.Parent do
			t = t + task.wait()
			img.ImageTransparency = math.clamp(1 - (t/0.4), 0, 1)
		end
		if img.Parent then img.ImageTransparency = 0 end
	end)

	-- ② 나뭇잎 파티클 (러너에 부착, 흩날림)
	local leafPart = Instance.new("Part")
	leafPart.Name = "_LeafFxPart"
	leafPart.Size = Vector3.new(0.2,0.2,0.2)
	leafPart.Transparency = 1
	leafPart.CanCollide = false
	leafPart.CanQuery = false
	leafPart.CanTouch = false
	leafPart.Massless = true
	leafPart.CFrame = hrp.CFrame
	leafPart.Parent = workspace
	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = hrp; w2.Part1 = leafPart; w2.Parent = leafPart
	leafPart.Anchored = false
	-- 나뭇잎을 스핀 이펙트 범위(반경 ~13)의 링 위 여러 지점에서 방출 → 회오리 주변에 흩뿌림
	local RING_R = 13
	local POINTS = 12
	for i = 1, POINTS do
		local ang = (i / POINTS) * math.pi * 2
		local att = Instance.new("Attachment")
		att.Position = Vector3.new(math.cos(ang) * RING_R, 1, math.sin(ang) * RING_R)
		att.Parent = leafPart
		local leaf = Instance.new("ParticleEmitter")
		leaf.Texture = LEAF_ID
		leaf.Color = ColorSequence.new(Color3.fromRGB(255,255,255))
		leaf.LightEmission = 0.3
		leaf.LightInfluence = 1
		leaf.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.3),
			NumberSequenceKeypoint.new(1, 1.0),
		})
		leaf.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.8, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		leaf.Rotation = NumberRange.new(-180, 180)
		leaf.RotSpeed = NumberRange.new(-90, 90)
		leaf.Speed = NumberRange.new(1, 4)
		leaf.SpreadAngle = Vector2.new(60, 60)
		leaf.Lifetime = NumberRange.new(1.0, 1.6)
		leaf.Acceleration = Vector3.new(0, -6, 0)
		leaf.Rate = 12   -- 지점당 12 (총 144)
		leaf.Parent = att
	end
	rec.leafPart = leafPart

	active[char] = rec
end

local function stopFx(char)
	local rec = active[char]
	if not rec then return end
	active[char] = nil

	-- 나뭇잎: 방출 중단 (남은 잎은 수명대로 사라짐), 파트는 잠시 후 제거
	if rec.leafPart then
		for _, e in ipairs(rec.leafPart:GetDescendants()) do
			if e:IsA("ParticleEmitter") then e.Rate = 0 end
		end
		Debris:AddItem(rec.leafPart, 2)
	end

	-- 세계수: 서서히 페이드 아웃 (1.2초에 걸쳐)
	if rec.tree and rec.treeImg then
		local img = rec.treeImg
		local anchor = rec.tree
		task.spawn(function()
			local FADE = 1.2
			local t = 0
			local startT = img.ImageTransparency
			while t < FADE and img.Parent do
				t = t + task.wait()
				img.ImageTransparency = math.clamp(startT + (1-startT)*(t/FADE), 0, 1)
			end
			if anchor and anchor.Parent then anchor:Destroy() end
		end)
	end
end

ev.OnClientEvent:Connect(function(target, action)
	-- 🤖 [2026-09-12] 봇 지원. 예전엔 Player 만 받아 봇 스핀에 이펙트가 안 나왔다.
	--   [왜] 서버가 FireAllClients(Plyr, ...) 로 보내는데 봇은 Plyr 가 nil 이라
	--     이 가드에서 즉시 return 됐다. 신호는 갔는데 아무도 안 그렸다.
	--   [지금] 서버가 Player 또는 Character 모델을 보낸다. 둘 다 캐릭터로 환산한다.
	local char
	if typeof(target) == "Instance" then
		if target:IsA("Player") then
			char = target.Character
		elseif target:IsA("Model") and target:FindFirstChild("HumanoidRootPart") then
			char = target
		end
	end
	if not char then return end
	if action == "start" then
		startFx(char)
	elseif action == "stop" then
		stopFx(char)
	end
end)

print("🌳 HammerSpinFxClient 활성화")
