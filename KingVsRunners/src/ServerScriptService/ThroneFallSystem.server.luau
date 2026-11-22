-- ThroneFallSystem - jeomryeong wanryo yeonchul
-- 1) zone off  2) throne shatter  3) chain attach  4) mark
local ServerStorage     = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players       = game:GetService("Players")
local Debris        = game:GetService("Debris")

-- Collapse targets per map: the throne PLUS the structures around it.
--   [why more than the throne] "the throne alone does not read as a turning point".
--   Bringing the roof, pillars and side structures down makes the shift obvious
--   at a glance.
--   [warn] Only things that are safe to remove. Map boundary walls and the walls
--     WallBoostSystem uses (map1 Wall."Left/Right Second Wall", 600 studs out) are
--     NOT here - removing them opens fall-outs and kills the runner wall boost.
local COLLAPSE = {
	-- [warn] map1 keeps ONLY the throne and the banner. "left/right castle wall"
	--   were in this list and were removed: the invisible fall guards behind them
	--   stay on, so tearing the stone down looked like an opening that is not one.
	--   A wall you can see through but cannot walk through is worse than no change.
	--   ⚠️ To put them back, the fall guards have to go too - and that was rejected
	--     for the reasons above this table. Both or neither.
	map1 = function()
		local m = workspace:FindFirstChild("map1")
		local c = m and m:FindFirstChild("map1 castle")
		local t = { workspace:FindFirstChild("King chair") }
		if c then
			for _, n in ipairs({ "ThroneBannerPart" }) do
				local o = c:FindFirstChild(n)
				if o then t[#t+1] = o end
			end
		end
		return t
	end,
	map2 = function()
		local m = workspace:FindFirstChild("map2")
		local f = m and m:FindFirstChild("map2 castle folder")
		local c = f and f:FindFirstChild("map2 castle")
		local t = {}
		if c then
			-- [warn] "castle_ceiling2" was literally named "Part". There are 12 parts
			--   called "Part" in this model, so FindFirstChild("Part") grabs whichever
			--   comes first - it would have destroyed a random floor slab. Renamed.
			for _, n in ipairs({ "king chair2", "roof1", "roof2", "pillar3", "pillar4",
			                     "Pillar2", "desert castle pillar", "desert castle pillar2",
			                     "castle_ceiling2" }) do
				local o = c:FindFirstChild(n)
				if o then t[#t+1] = o end
			end
		end
		if m then
			local ss = m:FindFirstChild("sun symbol")
			if ss then t[#t+1] = ss end
		end
		return t
	end,
}

-- Parts that are HIDDEN instead of destroyed at collapse.
--   [why not destroy] map2's "centerpart" is the skeleton dragon's landing plate -
--     DragonEntranceClient looks it up by name and flies to it. Destroying it would
--     leave the dragon without a return point.
--   [why hide at all] It sits at Y=204 over the throne room. Once the ceiling and
--     pillars under it are gone it just floats there, which reads as a bug.
--   [warn] Transparency only. Do NOT touch CanCollide or the name - the dragon and
--     anything else pointing at it must keep working exactly as before.
local HIDE_ON_COLLAPSE = {
	map2 = { "centerpart" },
}

-- Torches that go out when the throne falls.
--   [why extinguish, not destroy] "The king's fires are out" is the point; the
--     sconces themselves staying is fine and keeps the geometry intact.
--   [warn] Both map2 torches are named "torchlight" - FindFirstChild would only
--     ever return one of them. Iterate and match by name instead.
local DOUSE_ON_COLLAPSE = {
	map2 = { "torchlight" },
}

local dousedBackup = {}   -- [Fire/PointLight] = 원래 Enabled

local function setDoused(mapName, out_)
	local m = workspace:FindFirstChild(mapName)
	local f = m and m:FindFirstChild("map2 castle folder")
	local root = (f and f:FindFirstChild("map2 castle")) or m
	if not root then return 0 end
	local names = {}
	for _, n in ipairs(DOUSE_ON_COLLAPSE[mapName] or {}) do names[n] = true end
	local n = 0
	for _, c in ipairs(root:GetChildren()) do
		if names[c.Name] then
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("Fire") or d:IsA("PointLight") or d:IsA("SpotLight")
				   or d:IsA("ParticleEmitter") then
					if out_ then
						if dousedBackup[d] == nil then dousedBackup[d] = d.Enabled end
						d.Enabled = false
					elseif dousedBackup[d] ~= nil then
						d.Enabled = dousedBackup[d]
						dousedBackup[d] = nil
					end
					n = n + 1
				end
			end
		end
	end
	return n
end

local hiddenBackup = {}   -- [part] = 원래 Transparency

local function setHidden(mapName, hide)
	local m = workspace:FindFirstChild(mapName)
	local f = m and m:FindFirstChild("map2 castle folder")
	local c = f and f:FindFirstChild("map2 castle")
	local root = c or m
	if not root then return 0 end
	local n = 0
	for _, name in ipairs(HIDE_ON_COLLAPSE[mapName] or {}) do
		local p = root:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			if hide then
				if hiddenBackup[p] == nil then hiddenBackup[p] = p.Transparency end
				p.Transparency = 1
			else
				if hiddenBackup[p] ~= nil then
					p.Transparency = hiddenBackup[p]
					hiddenBackup[p] = nil
				end
			end
			n = n + 1
		end
	end
	return n
end

-- [기각 2026-09-05] 낙사 방지 투명벽(map1 Left/Right Wall·Left Wall2, map2 Left/Right Wall)을
--   붕괴와 함께 끄는 안은 만들었다가 되돌렸다. 코드가 아니라 설계 문제다:
--     ① 새 캠핑 지점 — 가장자리를 등지면 한쪽이 막히고, 킹이 그 자리를 잡으면
--        러너는 낙사를 무릅쓰고 접근해야 한다. 없애려던 캠핑을 다른 곳에 만든다.
--     ② 넉백 무기 가치 극대화 — 떨어뜨릴 수 있는 건 킹뿐이다(강타 17.2 stud,
--        러너 무기 넉백 0). 낙사가 열리면 강타 한 방이 곧 처치가 되어,
--        디버프를 건 뒤 오히려 킹에게 처형 수단을 쥐여준다.
--   ⚠️ 다시 시도하려면 먼저 러너 쪽 넉백 수단부터 만들 것. 순서를 바꾸면 같은 결론이 난다.
--   ⚠️ TaggerWalls(그룹 TaggerBarrier)는 애초에 킹만 막는 울타리라 이 논의와 무관하다.

-- [warn] Same rule BarricadeSystem learned the hard way: a destroyed structure does
--   NOT come back on its own. Back the originals up at boot and rebuild each round.
--   Back up BEFORE anything is broken, or the broken state becomes the original.
local backups = {}   -- [mapName] = { {clone=, parent=, name=}, ... }

local function backupCollapse()
	for mapName, getter in pairs(COLLAPSE) do
		if not backups[mapName] then
			local list = {}
			for _, o in ipairs(getter()) do
				local clone = o:Clone()
				clone.Parent = ServerStorage
				list[#list+1] = { clone = clone, parent = o.Parent, name = o.Name }
			end
			if #list > 0 then
				backups[mapName] = list
				print(string.format("[ThroneFall] backup ok: %s (%d objects)", mapName, #list))
			else
				warn("[ThroneFall] nothing to back up for " .. mapName)
			end
		end
	end
end

local function restoreCollapse()
	for mapName, list in pairs(backups) do
		for _, b in ipairs(list) do
			local cur = b.parent and b.parent:FindFirstChild(b.name)
			if cur then cur:Destroy() end
			if b.parent then
				local fresh = b.clone:Clone()
				fresh.Name = b.name
				fresh.Parent = b.parent
			end
		end
	end
end

local function currentMapName()
	local cs = _G.CaptureSystem
	local zones = cs and cs.getZones and cs.getZones()
	local z = zones and zones[1]
	if z then
		local p = z
		while p and p.Parent ~= workspace do p = p.Parent end
		if p and (p.Name == "map1" or p.Name == "map2") then return p.Name end
	end
	return nil
end

-- [why fragments instead of real physics] BarricadeSystem already solved this for
--   the 620-part gatehouse: "dropping the actual parts as physics debris is more
--   than the server can handle". Our collapse list is 328 parts - same problem.
--   So the originals are destroyed instantly and a small, capped number of NEW
--   fragments sells the collapse.
--   [warn] Do not raise DEBRIS_COUNT much. This fires once per round, but a spike
--     of physics parts is exactly what drops frames on low-end mobile.
local DEBRIS_COUNT = 18
local DEBRIS_LIFE  = 4.0

-- ── 사운드 ────────────────────────────────────────────────
-- [reused, not new] Both come from systems that already shipped:
--   COLLAPSE = BarricadeSystem's gate-break sound
--   CHAIN_A/B = KillEffectSystem's coffin trigger pair, played the moment the
--     chains wrap the victim. Same event here, so the same sound reads correctly.
--   [warn] These are hardcoded strings inside those scripts, not Sound instances.
--     Searching for Sound objects will not find them - I made that mistake once.
--     If either owner changes its id, this copy silently keeps the old one.
local SFX_COLLAPSE = "rbxassetid://84981346209739"
local SFX_CHAIN_A  = "rbxassetid://128622162873827"
local SFX_CHAIN_B  = "rbxassetid://80186384271553"

-- [why pitch the collapse down] It is literally the gate-break sound. At 1.0 the
--   player hears "the barricade broke again". 0.75 keeps the same material but
--   reads as something bigger and heavier coming down.
local COLLAPSE_PITCH = 0.75

-- [why an anchor part] The throne is destroyed in the same frame, so a sound
--   parented to it dies before it plays. BarricadeSystem hit this exact problem
--   and solved it the same way: temporary part + Debris.
local function playAt(position, soundId, volume, pitch, delaySec)
	task.spawn(function()
		if delaySec and delaySec > 0 then task.wait(delaySec) end
		local anchor = Instance.new("Part")
		anchor.Name = "_ThroneSfx"
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.Position = position
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Parent = workspace
		local snd = Instance.new("Sound")
		snd.SoundId = soundId
		snd.Volume = volume
		snd.PlaybackSpeed = pitch or 1.0
		snd.RollOffMode = Enum.RollOffMode.InverseTapered
		snd.RollOffMinDistance = 30
		snd.RollOffMaxDistance = 250   -- 2단계 교전 범위를 넉넉히 덮는다
		snd.Parent = anchor
		snd:Play()
		Debris:AddItem(anchor, 8)
	end)
end

local function sampleColors(objs)
	-- take colours from what is actually being destroyed, so map1 reads as stone
	-- and map2 as sandstone without hardcoding either.
	local cols = {}
	for _, o in ipairs(objs) do
		for _, d in ipairs(o:GetDescendants()) do
			if d:IsA("BasePart") and #cols < 8 then cols[#cols+1] = d.Color end
		end
		if o:IsA("BasePart") and #cols < 8 then cols[#cols+1] = o.Color end
	end
	if #cols == 0 then cols[1] = Color3.fromRGB(160, 160, 160) end
	return cols
end

local function shatterThrone(mapName)
	local getter = COLLAPSE[mapName]
	local objs = getter and getter() or {}
	if #objs == 0 then
		warn("[ThroneFall] nothing to shatter: " .. tostring(mapName))
		return
	end

	-- centre + span from the real geometry, BEFORE destroying it.
	-- [warn] GetBoundingBox() is a Model method. Parts do not have it, and indexing
	--   a missing member on an Instance throws immediately - BEFORE pcall can run.
	--   That is why wrapping it in pcall did not help: roof1/roof2 are Parts, the
	--   call blew up, ThroneFall aborted, and neither chains nor exhaust ever fired.
	--   Branch on the class instead of guessing.
	local function boundsOf(o)
		if o:IsA("BasePart") then
			return o.Position, o.Size
		elseif o:IsA("Model") then
			local cf, sz = o:GetBoundingBox()
			return cf.Position, sz
		end
		return nil, nil
	end

	local minV, maxV
	local partCount = 0
	for _, o in ipairs(objs) do
		local pos, sz = boundsOf(o)
		if pos and sz then
			local hs = sz * 0.5
			local lo, hi = pos - hs, pos + hs
			minV = minV and Vector3.new(math.min(minV.X,lo.X), math.min(minV.Y,lo.Y), math.min(minV.Z,lo.Z)) or lo
			maxV = maxV and Vector3.new(math.max(maxV.X,hi.X), math.max(maxV.Y,hi.Y), math.max(maxV.Z,hi.Z)) or hi
		end
		for _, d in ipairs(o:GetDescendants()) do
			if d:IsA("BasePart") then partCount = partCount + 1 end
		end
		if o:IsA("BasePart") then partCount = partCount + 1 end
	end
	if not minV then return end
	local centre = (minV + maxV) * 0.5
	local span   = (maxV - minV)
	local cols   = sampleColors(objs)

	-- fragments first (needs the geometry to still exist for placement reference)
	local folder = Instance.new("Folder")
	folder.Name = "_ThroneDebris"
	folder.Parent = workspace
	Debris:AddItem(folder, DEBRIS_LIFE + 1)

	for i = 1, DEBRIS_COUNT do
		local p = Instance.new("Part")
		local sz = math.random(20, 55) / 10
		p.Size = Vector3.new(sz, sz * math.random(6, 16) / 10, sz)
		p.Color = cols[((i - 1) % #cols) + 1]
		p.Material = Enum.Material.Slate
		-- [warn] no collision/query/touch. Fragments must never push a runner or
		--   block a path - this fires mid-fight.
		p.CanCollide = false
		p.CanQuery   = false
		p.CanTouch   = false
		p.CastShadow = false
		p.Anchored   = false
		p.CFrame = CFrame.new(
			centre.X + (math.random() - 0.5) * span.X * 0.7,
			centre.Y + (math.random() - 0.2) * span.Y * 0.5,
			centre.Z + (math.random() - 0.5) * span.Z * 0.7
		) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		p.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * 40, math.random(20, 45), (math.random() - 0.5) * 40)
		p.AssemblyAngularVelocity = Vector3.new(
			math.random(-9, 9), math.random(-9, 9), math.random(-9, 9))
		p.Parent = folder
	end

	-- then remove the originals outright
	for _, o in ipairs(objs) do
		if o and o.Parent then o:Destroy() end
	end

	-- hide (not destroy) the parts that other systems still point at
	local hid = setHidden(mapName, true)
	-- put the torches out
	local dz = setDoused(mapName, true)

	-- 📳 screen shake for everyone nearby. Reuses HammerShakeEvent - the same
	--   (intensity, duration) remote the hammer and the rolling stone already use.
	--   [warn] Do NOT invent a new shake remote. A second one means a second set of
	--     intensity conventions to keep in sync, and they will drift.
	--   [scale] Hammer jab 1.3, slam 2.2, stone near-miss 0.9. A castle coming down
	--     should top the list, so 2.6 - but short (0.6s), or it reads as lag.
	--   [warn] Everyone shakes, king included. This is a world event, not a hit.
	local shakeEvent = ReplicatedStorage:FindFirstChild("HammerShakeEvent")
	if shakeEvent then
		for _, plr in ipairs(Players:GetPlayers()) do
			shakeEvent:FireClient(plr, 2.6, 0.6)
		end
	end

	-- 🔊 collapse now, chains a beat later - the order the player sees it happen.
	--   [warn] The chain pair plays at the KING, not at the throne. The two are far
	--     apart (33~45 stud) and the second sound is about him being bound, so it
	--     has to come from where he is or it reads as more rubble.
	playAt(centre, SFX_COLLAPSE, 2.4, COLLAPSE_PITCH)

	print(string.format("[ThroneFall] collapsed %s - %d objects / %d parts removed, %d fragments, %d hidden, %d doused",
		mapName, #objs, partCount, DEBRIS_COUNT, hid, dz))

	return centre   -- 저주검이 '왕좌 자리'에서 솟아야 하므로 호출부에 넘긴다
end

-- ⚔️ 저주검 — 무너지는 왕좌에서 뽑혀 나와 킹에게 박힌다.
--   [왜 왕좌에서인가] 붕괴가 그 자리에서 일어나므로 카메라가 이미 거기를 보고 있다.
--     "권좌가 그를 벤다"가 되어 점령 → 저주의 인과가 한 화면에 담긴다.
--   [왜 평소엔 안 보이나] 현수막에 전시해봤더니 '쓸 수 있는 무기'로 읽혔다.
--     ServerStorage 템플릿으로만 두고 이 순간에만 꺼낸다.
--   ⚠️ 템플릿은 원점(0,0,0) 기준으로 정렬돼 있다. CFrame 하나만 주면 배치된다.
--   ⚠️ 자식 파트는 WeldConstraint 로 묶여 있지만, 용접은 '만든 순간의 상대 위치'만
--     고정한다. 복제본을 옮길 때는 부모만 옮기면 자식이 따라온다(용접이 이미 있으므로).
--     새로 만들 때는 오프셋을 직접 배치해야 한다 — 이 프로젝트에서 두 번 겪은 함정이다.
-- 🔊 검이 몸에 박히는 순간의 소리. 붕괴음·사슬음과 겹치지 않게 늦게 온다
--   (붕괴 0.00s / 사슬 0.35s / 관통 0.90s).
local SFX_SWORD_HIT  = "rbxassetid://140277245983305"

-- 검이 꽂히는 자리. HumanoidRootPart 기준 상대 CFrame.
--   [측정] 로비에 R15 킹(King npc2)과 검을 나란히 세우고 직접 맞춘 값이다.
--     감으로 잡은 첫 값 (0, 0.6, 1.1) / X-115 는 등 뒤였는데, 실제로 보니
--     가슴을 관통하는 쪽이 맞았다 — Z 부호가 뒤집혔다.
--   ⚠️ 숫자를 손으로 고치지 말 것. 다시 맞추려면 로비에 같은 방식으로 세워
--     직접 옮기고 ToObjectSpace 로 재는 게 빠르고 정확하다.
local SWORD_OFFSET = CFrame.new(-0.367, 0.813, -1.152)
	* CFrame.Angles(math.rad(65.0), math.rad(-60.0), math.rad(-180.0))

local SWORD_FLIGHT   = 0.55   -- 왕좌 → 킹 비행 시간
local SWORD_RISE     = 0.35   -- 뽑혀 나오며 솟는 시간

local function launchCurseSword(throneCentre, king)
	local tpl = ServerStorage:FindFirstChild("curse sword")
	if not tpl then
		warn("[ThroneFall] curse sword template missing")
		return
	end
	local root = king and (king:FindFirstChild("HumanoidRootPart"))
	if not root then return end

	local sword = tpl:Clone()
	sword.Name = "_CurseSword"
	-- [warn] Only the ROOT is anchored. Anchoring the children too would detach them
	--   from physics, and then the WeldConstraints do nothing - moving the root would
	--   leave the actual blade sitting at the origin while the invisible shell flies
	--   to the throne. That is exactly what happened on the first attempt, and it is
	--   the same trap as the banner placement: anchored parts do not follow welds.
	for _, d in ipairs(sword:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false      -- ← 용접이 끌고 간다
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	sword.Anchored = true
	sword.Massless = true
	sword.CanCollide = false
	sword.CanQuery = false
	sword.CanTouch = false
	sword.Parent = workspace

	-- 용접이 살아있는지 확인. 없으면 자식이 안 따라온다.
	local weldCount = 0
	for _, d in ipairs(sword:GetDescendants()) do
		if d:IsA("WeldConstraint") then weldCount = weldCount + 1 end
	end
	print(string.format("[ThroneFall] curse sword spawned (welds=%d)", weldCount))

	-- ① 왕좌 자리에서 솟아오른다 (칼끝 위)
	local startCF = CFrame.new(throneCentre) * CFrame.Angles(0, 0, math.rad(90))
	sword.CFrame = startCF * CFrame.new(0, -6, 0)

	task.spawn(function()
		local t0 = os.clock()
		-- 솟아오르기
		while os.clock() - t0 < SWORD_RISE do
			if not sword.Parent then return end
			local a2 = (os.clock() - t0) / SWORD_RISE
			sword.CFrame = startCF * CFrame.new(0, -6 + 14 * a2, 0)
			task.wait()
		end
		-- ② 킹에게 날아가 등에 박힌다
		local from = sword.CFrame
		local t1 = os.clock()
		while os.clock() - t1 < SWORD_FLIGHT do
			if not (sword.Parent and root.Parent) then return end
			local a2 = (os.clock() - t1) / SWORD_FLIGHT
			a2 = a2 * a2                                   -- 가속: 뽑힐 땐 느리고 꽂힐 땐 빠르게
			local dest = root.CFrame * SWORD_OFFSET
			sword.CFrame = from:Lerp(dest, a2)
			task.wait()
		end
		-- ③ 박힌 채로 따라다닌다
		if not (sword.Parent and root.Parent) then return end

		-- 🔊 관통음. 임시 파트가 아니라 킹 위치에서 바로 낸다 — 소리의 출처가
		--   '박힌 자리'여야 무슨 일이 일어났는지 읽힌다.
		playAt(root.Position, SFX_SWORD_HIT, 2.8, 1.0)
		-- 마지막 위치를 확정한 뒤 앵커를 풀고 킹에게 용접한다.
		--   [warn] 순서가 중요하다. 앵커를 먼저 풀면 용접이 걸리기 전 한 프레임 동안
		--     중력을 받아 검이 아래로 샌다.
		sword.CFrame = root.CFrame * SWORD_OFFSET
		sword.Anchored = false
		local w = Instance.new("WeldConstraint")
		w.Name = "_CurseSwordWeld"
		w.Part0 = root
		w.Part1 = sword
		w.Parent = sword
	end)
end

-- [MEASURED] "chain vfx" is NOT a chain model. The R6 body parts are a shell:
--   Torso / legs / HumanoidRootPart / Left Arm are Transparency 1 (invisible),
--   only Head and Right Arm have a visible SpecialMesh, and the ACTUAL chains
--   are 4 Beams running from Effects.{Left,Right,Top,Bottom} -> Head.Top,
--   plus 4 ParticleEmitters on Effects.
--   [warn] The first attempt cloned every body part and tweened Transparency to 0.
--     That made the invisible shell visible -> a grey blob on the king, and the
--     Beams never rendered because their Attachment1 (Head.Top) was gone.
-- [approach] Clone only what carries the visual: Effects (particles + source
--   attachments) and repoint its Beams at an attachment on the king.
local function attachChains(char)
	local tpl = ServerStorage:FindFirstChild("chain vfx")
	if not tpl then
		warn("[ThroneFall] chain vfx template missing")
		return
	end
	local existing = char:FindFirstChild("_ThroneChains")
	if existing then existing:Destroy() end

	-- anchor points: core at the FEET, beams running up to the TORSO.
	--   Reads as shackles on the ground dragging the king down, rather than a
	--   halo around his head.
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	local root  = char:FindFirstChild("HumanoidRootPart")
	local foot  = char:FindFirstChild("LeftFoot") or char:FindFirstChild("Left Leg") or root
	if not (torso and root and foot) then
		warn("[ThroneFall] missing torso/root/foot - chains skipped")
		return
	end

	local holder = Instance.new("Folder")
	holder.Name = "_ThroneChains"
	holder.Parent = char

	-- beam target on the torso
	local torsoAtt = Instance.new("Attachment")
	torsoAtt.Name = "ThroneChainTop"
	torsoAtt.Parent = torso

	local srcEff = tpl:FindFirstChild("Effects")
	if not srcEff then
		warn("[ThroneFall] chain vfx.Effects missing")
		return
	end
	local eff = srcEff:Clone()
	eff.Name = "ThroneChainCore"
	eff.CanCollide = false
	eff.CanTouch = false
	eff.CanQuery = false
	eff.Massless = true
	eff.Transparency = 1
	for _, w in ipairs(eff:GetChildren()) do
		if w:IsA("WeldConstraint") then w:Destroy() end
	end
	eff.Parent = holder
	-- [follow the king, but do not swing] The core has to travel with the king, so
	--   it is welded - but NOT to a foot. Feet swing back and forth every step, so
	--   anything attached to one flails around. HumanoidRootPart is the body's
	--   stable frame: weld there and simply place the part down at ground level.
	--   Result: sits at the soles, moves as one solid piece with the king.
	--   [warn] Do not re-weld this to LeftFoot/Left Leg "because it should be at the
	--     feet" - the position is what should be at the feet, not the joint.
	eff.Anchored = false
	local groundY = foot.Position.Y - foot.Size.Y * 0.5
	eff.CFrame = CFrame.new(root.Position.X, groundY, root.Position.Z)
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = eff
	w.Parent = eff

	-- [warn] Cloning Effects already brings its 4 Beams (they live inside the
	--   Attachments). Do NOT clone them again. Just repoint Attachment1.
	-- [why not pure black] Solid black read as a dark smudge against the king's
	--   dark silhouette and the map floor - it was hard to even see. A white->black
	--   gradient keeps the "cursed iron" feel but stays legible on any background:
	--   the bright end catches the eye, the dark end says "shackle".
	-- [why so extreme] The first gradient (245 -> 120 -> 15) barely read: the beam
	--   texture repeats and its own alpha washes the midtones out, so a smooth ramp
	--   just looks like flat grey. Pushing to pure white and near-black, and putting
	--   the switch in a narrow band around 0.5, makes the transition actually visible
	--   as two distinct halves rather than a soft blur.
	-- [MEASURED] The chain runs foot -> UpperTorso, which is only ~3.2 stud on the
	--   R15 king. Keypoints are fractions of THAT, not of the 5.5 stud test rig -
	--   0.15 here is about half a stud of white.
	-- [why the flip is sharp, not a ramp] A smooth ramp was the first attempt and it
	--   read as plain white. The beam texture repeats (TextureLength 2.0) and grinds
	--   the mid greys into the pattern, so only the bright end registers. Holding a
	--   flat white then dropping inside 10% makes the two colours actually separate.
	-- [warn] Do NOT raise LightEmission to 1 to "boost contrast" - that was tried and
	--   it washes every colour out to white, which is what killed the gradient before.
	--   0.5 is the template's own value; leave it.
	local CHAIN_GRADIENT = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.15, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(8, 8, 12)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(8, 8, 12)),
	})
	local made = 0
	for _, d in ipairs(eff:GetDescendants()) do
		if d:IsA("Beam") then
			d.Attachment1 = torsoAtt
			d.Enabled = true
			d.Color = CHAIN_GRADIENT   -- bright at the foot end, black toward the torso
			-- [warn] LightEmission stays at the template's 0.5. Pushing it to 1 blows
			--   every colour out to white - that is why the gradient looked like a
			--   plain white chain in game. Transparency 0 keeps the dark half from
			--   being washed back to grey by the texture's own alpha.
			d.LightEmission = 0.5
			d.Transparency = NumberSequence.new(0)
			made = made + 1
		elseif d:IsA("ParticleEmitter") then
			d.Color = CHAIN_GRADIENT
		end
	end

	-- 🔊 the chains landing on him. Two layers at once, exactly as the coffin does.
	--   0.35s after the collapse so the two events read as cause and effect
	--   rather than one muddled crash.
	playAt(root.Position, SFX_CHAIN_A, 2.5, 1.0, 0.35)
	playAt(root.Position, SFX_CHAIN_B, 2.5, 1.0, 0.35)

	print(string.format("[ThroneFall] chains attached: %d beams + particles (%s)", made, char.Name))
end

local function findKingChar()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("Role") == "Tagger" and plr.Character then
			return plr.Character
		end
	end
	for _, m in ipairs(workspace:GetDescendants()) do
		if m:IsA("Model") and m:GetAttribute("Role") == "Tagger"
		   and m:FindFirstChildOfClass("Humanoid") then
			return m
		end
	end
	return nil
end

_G.ThroneFall = function()
	backupCollapse()

	local cs = _G.CaptureSystem
	if cs and cs.stop then
		local ok, err = pcall(cs.stop)
		if not ok then warn("[ThroneFall] capture stop failed: " .. tostring(err)) end
	end

	local mapName = currentMapName()
	local throneCentre = nil   -- shatterThrone 이 돌려주는 왕좌 중심. 저주검 시작점.
	if mapName then
		throneCentre = shatterThrone(mapName)
	else
		warn("[ThroneFall] cannot resolve current map - skip shatter")
	end

	local king = findKingChar()
	if king then
		-- ⚔️ 왕좌 자리에서 검을 뽑아 킹에게 꽂는다. 사슬보다 먼저 시작해
		--   '왕좌가 무너진다 → 검이 뽑힌다 → 사슬이 감긴다' 순으로 읽히게 한다.
		if throneCentre then
			local okS, errS = pcall(launchCurseSword, throneCentre, king)
			if not okS then warn("[ThroneFall] sword failed: " .. tostring(errS)) end
		end

		attachChains(king)
		king:SetAttribute("ThroneFallen", true)
		-- stage3: the debuff itself. Capture no longer wins - it strips authority.
		-- 📢 tell every client what just happened. The king in particular has no way
		--   to know: the throne is behind him, the chains are at his feet, and the
		--   exhaustion that follows just looks like his controls breaking.
		--   [warn] Fire to ALL, not just the king. Runners need to know their capture
		--     did something, or the reward for taking the zone is invisible too.
		local fellEvent = ReplicatedStorage:FindFirstChild("ThroneFellEvent")
		if fellEvent then
			fellEvent:FireAllClients(king and king.Name or "KING")
		end

		if _G.ThroneExhaustStart then
			local ok, err = pcall(_G.ThroneExhaustStart, king)
			if not ok then warn("[ThroneFall] exhaust start failed: " .. tostring(err)) end
		end
		-- the capture zones are gone; send the bots after the king instead of
		-- leaving them standing on an objective that no longer exists.
		if _G.RunnerBotsGoKill then pcall(_G.RunnerBotsGoKill) end
	else
		warn("[ThroneFall] king character not found - skip chains")
	end
end

-- 💀 킹이 죽으면 사슬을 즉시 뗀다.
--   [왜] 사망 순간 코핀킬 등 킬이펙트가 재생되는데, 그 연출도 사슬을 쓴다.
--     두 사슬이 겹쳐 보이면 무슨 이펙트인지 분간이 안 되고, 저주 사슬은
--     '살아 있는 왕을 묶는 것'이라 죽은 뒤에는 의미도 없다.
--   ⚠️ ThroneFallReset(라운드 리셋)만으로는 늦다. 리셋은 다음 라운드 시작 때
--     불리므로, 사망 연출이 끝날 때까지 사슬이 남아 있게 된다.
_G.ThroneChainsDetach = function(char)
	if not char then return false end
	local holder = char:FindFirstChild("_ThroneChains")
	if holder then holder:Destroy() end
	-- ⚔️ 저주검도 같이 뗀다. 킹에 용접돼 있으므로 char 하위가 아니라 workspace 에 있다.
	--   [warn] 용접만 끊으면 검이 물리로 굴러다닌다. Destroy 가 맞다.
	for _, o in ipairs(workspace:GetChildren()) do
		if o.Name == "_CurseSword" then
			local w = o:FindFirstChild("_CurseSwordWeld")
			if (w and w.Part0 and w.Part0.Parent == char) or not w then o:Destroy() end
		end
	end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	local att = torso and torso:FindFirstChild("ThroneChainTop")
	if att then att:Destroy() end
	return holder ~= nil
end

_G.ThroneFallReset = function()
	restoreCollapse()
	-- "code that hides needs code that unhides" - otherwise the plate stays
	-- invisible for every following round.
	setHidden("map2", false)
	setDoused("map2", false)
	-- [warn] "code that turns on needs code that turns off" - stop the exhaust loop
	--   or it keeps ticking on a character that is no longer the king.
	if _G.ThroneExhaustStop then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.Character then pcall(_G.ThroneExhaustStop, plr.Character) end
		end
		for _, m in ipairs(workspace:GetDescendants()) do
			if m:IsA("Model") and m:GetAttribute("ThroneFallen") then
				pcall(_G.ThroneExhaustStop, m)
			end
		end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		local c = plr.Character
		if c then
			c:SetAttribute("ThroneFallen", nil)
			local h = c:FindFirstChild("_ThroneChains")
			if h then h:Destroy() end
		end
	end
	for _, m in ipairs(workspace:GetDescendants()) do
		if m:IsA("Model") and m:GetAttribute("ThroneFallen") then
			m:SetAttribute("ThroneFallen", nil)
			local h = m:FindFirstChild("_ThroneChains")
			if h then h:Destroy() end
		end
	end
end

print("[ThroneFall] ready (_G.ThroneFall / _G.ThroneFallReset) - stage2 visual only")

-- Round boundary: reuse the same signal BarricadeSystem listens to.
-- SetCurrentMap fires at map selection, before TAGGER SELECTION.
-- [warn] Do NOT invent a new round hook. BarricadeSystem already proved this path;
--        a second rule in a second place is the classic "only one side gets fixed" bug.
local setMapEvent = game.ReplicatedStorage:FindFirstChild("SetCurrentMap")
if setMapEvent and setMapEvent:IsA("BindableEvent") then
	setMapEvent.Event:Connect(function()
		local ok, err = pcall(_G.ThroneFallReset)
		if not ok then warn("[ThroneFall] reset failed: " .. tostring(err)) end
	end)
	print("[ThroneFall] round reset hooked to SetCurrentMap")
else
	warn("[ThroneFall] SetCurrentMap not found - throne will NOT be restored between rounds")
end
