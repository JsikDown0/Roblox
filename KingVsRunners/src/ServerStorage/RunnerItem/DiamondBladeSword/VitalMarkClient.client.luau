-- VitalMarkClient — 세공 표식 렌더 + 완주 연출 (자기 표식만 로컬 표시, 남에겐 안 보임)
-- 서버(SwordMain) 신호: markSync(상태)/markHit(idx)/markReset/markClear/markComplete.
-- 표식 = 태거 몸 주위 월드 0/120/240°. 완주 시 표식 깨짐 + 태거 감싸는 다이아 셸 등장→깨짐 + 사운드.
local Tool = script.Parent
local Remote = Tool:WaitForChild("Remote", 10)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local LocalPlayer = Players.LocalPlayer

-- ⚠️ [2026-09-08] 3 → 2. SwordMain 의 MARK_COUNT 와 반드시 같아야 한다.
--   상수가 두 파일에 복제돼 있어서, 한쪽만 고치면 표시 개수와 판정 개수가 어긋난다
--   (표식 3개가 보이는데 2개만 켜지거나, 켜졌는데 안 보이거나).
--   MARK_DIRS 는 이 값으로 자동 생성되므로 각도는 따라온다.
local MARK_COUNT = 2
local MARK_RADIUS = 4.5
local PAD_DIST = 3.6
local PAD_LENGTH = 5.5
local PAD_WIDTH = 3.0
local GROUND_DROP = 2.6
local DIAMOND_SIZE = Vector3.new(1.3, 1.4, 1.3)
local SHATTER_SOUND = "rbxassetid://89962151545919"
local MARK_DIRS = {}
for i = 0, MARK_COUNT - 1 do
	local a = math.rad(i * (360 / MARK_COUNT))
	MARK_DIRS[i + 1] = Vector3.new(math.sin(a), 0, math.cos(a))
end

local DIAMOND_COLOR = Color3.new(0.686275, 0.866667, 1)
local DIAMOND_REFLECT = 0.6

-- Ice Crystal Blade skin: frost-themed marks when the Tool has the IceMarks attribute
-- (set at grant time by Stage2TriggerSystem / /diasword). Otherwise default diamond look.
local ICE_COLOR = Color3.fromRGB(180, 235, 255)
local function applyMarkLook(p)
	if Tool:GetAttribute("IceMarks") then
		p.Material = Enum.Material.Ice
		p.Color = ICE_COLOR
		p.Reflectance = 0.15
	else
		p.Material = Enum.Material.Glass
		p.Color = DIAMOND_COLOR
		p.Reflectance = DIAMOND_REFLECT
	end
end

local marks = {}
local hitState = {}
local renderConn = nil

local gemTemplate = nil
local iceTemplate = nil
local function getGemTemplate()
	-- Ice Crystal Blade skin: use the ice cube mesh instead of the diamond gem.
	if Tool:GetAttribute("IceMarks") then
		if iceTemplate then return iceTemplate end
		local isrc = game:GetService("ReplicatedStorage")
		:WaitForChild("ItemTemplates"):WaitForChild("icecube", 10)
		if isrc and isrc:IsA("MeshPart") then
			iceTemplate = isrc:Clone()
			iceTemplate.Parent = nil
		end
		return iceTemplate
	end
	if gemTemplate then return gemTemplate end
	local src = game:GetService("ReplicatedStorage")
	:WaitForChild("ItemTemplates"):WaitForChild("diamond", 10)
	if src and src:IsA("MeshPart") then
		gemTemplate = src:Clone()
		gemTemplate.Parent = nil
	end
	return gemTemplate
end

local function findTaggerRoot()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer and p:GetAttribute("Role") == "Tagger" then
			local char = p.Character
			if char then
				local root = char:FindFirstChild("HumanoidRootPart")
				if root then return root end
			end
		end
	end
	-- 🤖 [2026-09-08] 봇 킹 대응. 위 루프는 Players 만 훑는다.
	--   [증상] 봇 킹에게 표식이 안 떠서 다이아 스킬을 아예 발동할 수 없었다(실측).
	--   [원인] 봇은 Players 에 없다. TaggerBotSystem:516 이 캐릭터에
	--     Role="Tagger" 속성을 직접 붙이므로, 워크스페이스를 훑어야 잡힌다.
	--   ⚠️ 이름("KING")이 아니라 속성으로 찾는다 — 이름은 바뀔 수 있다.
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("Role") == "Tagger" then
			local root = m:FindFirstChild("HumanoidRootPart")
			if root then return root end
		end
	end

	local dummy = workspace:FindFirstChild("taggerdummy")
	-- ⚠️ [2026-09-08] 로비 훈련 더미 대응.
	--   [증상] 다이아 표식이 더미 하나에만 계속 뜨고, 여러 명이 훈련장을 쓰면
	--     각자 다른 더미를 때려도 표식은 한 곳에만 나타난다.
	--   [원인] 위 FindFirstChild("taggerdummy") 는 '이름이 같은 첫 번째 하나' 만 찾는다.
	--     훈련 더미는 이름이 LobbyTrainingDummy_A~D 라 아예 안 잡히고,
	--     잡히더라도 항상 같은 하나가 걸린다.
	--   [해결] 훈련 중이면 '내가 지금 보고 있는' 더미를 고른다 — 가장 가까운 것.
	--     그래야 두 사람이 각자 다른 더미를 때려도 각자의 표식이 자기 표적에 뜬다.
	--   ⚠️ 실전에는 영향 없다. Role=="Tagger" 플레이어를 찾는 위 루프가 먼저 돌고,
	--     여기는 그게 실패했을 때의 폴백이다.
	if not dummy and LocalPlayer:GetAttribute("WeaponTrialActive") then
		local myChar = LocalPlayer.Character
		local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
		if myRoot then
			local best, bestD = nil, math.huge
			for _, m in ipairs(workspace:GetChildren()) do
				if m:IsA("Model") and m:GetAttribute("LobbyDummy") then
					local r = m:FindFirstChild("HumanoidRootPart")
					if r then
						local d = (r.Position - myRoot.Position).Magnitude
						if d < bestD then best, bestD = r, d end
					end
				end
			end
			if best then return best end
		end
	end
	if dummy then
		local root = dummy:FindFirstChild("HumanoidRootPart") or dummy.PrimaryPart or dummy:FindFirstChild("Torso")
		if root then return root end
	end
	-- 🐛 [버그수정 2026-09-05] 봇 킹(TaggerBotSystem)을 찾지 못해 표식이 안 보였다.
	--   [증상] 러너로 플레이할 때(봇 킹 상대) 표식이 전혀 표시되지 않았다.
	--   [원인] 위 두 경로가 '유저 킹(Players 중 Role=Tagger)' 과 'taggerdummy' 뿐이다.
	--     봇 킹은 플레이어가 아니고 이름도 "KING" 이라 둘 다에 안 걸린다.
	--     syncMarks 의 렌더 루프는 root 가 nil 이면 전 표식을 Transparency=1 로 숨기므로,
	--     표식이 '생성은 됐지만 영원히 투명'인 상태였다.
	--   [판별자] TaggerDummy 속성을 쓴다 — TaggerBotSystem:271 이 세우고
	--     Stage2TriggerSystem:260 이 이미 같은 방식으로 봇 킹을 찾는다. 표준 경로다.
	--   ⚠️ 이름("KING")으로 찾지 않는다. 이름은 언제든 바뀌지만 속성은 계약이다.
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("TaggerDummy") == true then
			local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
			if root then return root end
		end
	end
	return nil
end

local function clearMarks()
	if renderConn then renderConn:Disconnect(); renderConn = nil end
	for _, m in ipairs(marks) do
		if m.pad then m.pad:Destroy() end
		if m.gem then m.gem:Destroy() end
	end
	marks = {}
	hitState = {}
end

local function styleCommon(p)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	-- ⚠️ [2026-09-08] 밖에서 찾을 수 있게 표식을 남긴다.
	--   [왜] 이 파트들은 workspace 직속에 '이름 없는 Part' 로 생겨서,
	--     툴이 Destroy 된 뒤에는 아무도 이걸 찾아 지울 수 없었다.
	--     Tool.Destroying / AncestryChanged 로 자체 정리를 시도했지만,
	--     Destroy() 는 툴 안 스크립트를 즉시 정지시켜 그 핸들러가 실행되지 않는다.
	--     (오늘 관성·팔·스킬아이콘에서 반복 확인한 사실)
	--   [해결] 이름을 붙여 WeaponUICleanupClient 가 밖에서 걷어내게 한다.
	--     "정리 그물은 이름 목록으로 만들지 않는다" 의 예외가 아니라 그 반대다 —
	--     생성할 때 표식을 켜두면 소비처가 고정된 규칙 하나로 잡는다.
	p.Name = "_WeaponFx_DiamondMark"
	p.Parent = workspace
end

local function makeGem()
	local tmpl = getGemTemplate()
	local gem
	if tmpl then
		gem = tmpl:Clone()
	else
		gem = Instance.new("Part")
		gem.Shape = Enum.PartType.Ball
	end
	if not Tool:GetAttribute("IceMarks") then
		applyMarkLook(gem)  -- diamond look; the ice cube keeps its own icy appearance
	end
	gem.Size = DIAMOND_SIZE
	gem.Transparency = 0.5
	styleCommon(gem)
	return gem
end

local function makePad()
	local pad = Instance.new("Part")
	applyMarkLook(pad)
	pad.Size = Vector3.new(PAD_WIDTH, 0.25, PAD_LENGTH)
	pad.Transparency = 0.6
	styleCommon(pad)
	return pad
end

local function syncMarks(state)
	clearMarks()
	for i = 1, MARK_COUNT do
		marks[i] = { pad = makePad(), gem = makeGem() }
		hitState[i] = (type(state) == "table" and state[i]) and true or false
		if hitState[i] and marks[i].gem then marks[i].gem.Size = DIAMOND_SIZE * 1.3 end
	end
	renderConn = RunService.RenderStepped:Connect(function()
		local root = findTaggerRoot()
		if not root then
			for _, m in ipairs(marks) do
				if m.pad then m.pad.Transparency = 1 end
				if m.gem then m.gem.Transparency = 1 end
			end
			return
		end
		local c = root.Position
		local ground = Vector3.new(c.X, c.Y - GROUND_DROP, c.Z)
		local spin = os.clock() * 1.5
		for i = 1, MARK_COUNT do
			local m = marks[i]
			local dir = MARK_DIRS[i]
			if m.pad then
				local padPos = ground + dir * PAD_DIST
				m.pad.CFrame = CFrame.lookAt(padPos, padPos + dir)
				m.pad.Transparency = hitState[i] and 0.2 or 0.6
			end
			if m.gem then
				local gemPos = c + dir * MARK_RADIUS
				m.gem.CFrame = CFrame.new(gemPos) * CFrame.Angles(0, spin, 0)
				m.gem.Transparency = hitState[i] and 0.05 or 0.5
			end
		end
	end)
end

local function lightMark(i)
	local m = marks[i]
	if not m then return end
	hitState[i] = true
	if m.gem then m.gem.Size = DIAMOND_SIZE * 1.3 end
end

local function resetVisual()
	for i = 1, MARK_COUNT do
		hitState[i] = false
		local m = marks[i]
		if m and m.gem then m.gem.Size = DIAMOND_SIZE end
	end
end

-- ── 완주 연출: 파편 깨짐 ──────────────────────────────────────
local function makeShard(pos)
	local sh = Instance.new("Part")
	-- 💥 [2026-09-05] 0.45 → 0.9. 완주 파편이 태거 코앞에서 터지는데 너무 작아 안 보였다.
	sh.Size = Vector3.new(0.9, 0.9, 0.9)
	applyMarkLook(sh)
	sh.Transparency = 0.15
	sh.CanCollide = false
	sh.CanQuery = false
	sh.CanTouch = false
	sh.Massless = true
	sh.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
	sh.Parent = workspace
	local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.2, math.random() - 0.5)
	if dir.Magnitude < 0.01 then dir = Vector3.new(0, 1, 0) end
	sh.AssemblyLinearVelocity = dir.Unit * (26 + math.random() * 16)   -- 18~30 → 26~42, 더 멀리 흩어진다
	TweenService:Create(sh, TweenInfo.new(0.9), { Transparency = 1, Size = Vector3.new(0.1, 0.1, 0.1) }):Play()
	Debris:AddItem(sh, 1.0)
end

local function shatterAt(pos, count)
	for _ = 1, (count or 6) do makeShard(pos) end
end

local function playCompletion()
	local root = findTaggerRoot()
	local center = root and root.Position or nil
	-- 깨지는 효과음 (태거 위치)
	if center then
		local sp = Instance.new("Part")
		sp.Transparency = 1; sp.Anchored = true; sp.CanCollide = false; sp.CanQuery = false
		sp.Size = Vector3.new(1, 1, 1); sp.CFrame = CFrame.new(center); sp.Parent = workspace
		local snd = Instance.new("Sound")
		snd.SoundId = SHATTER_SOUND; snd.Volume = 1.6
		snd.RollOffMaxDistance = 90; snd.RollOffMinDistance = 6
		snd.Parent = sp; snd:Play()
		Debris:AddItem(sp, 2.5)
	end
	-- 표식 3개 깨짐 (각 gem 위치에서 파편)
	for i = 1, MARK_COUNT do
		local m = marks[i]
		if m and m.gem then shatterAt(m.gem.Position, 5) end
	end
	-- 💥 [연출 수정 2026-09-05] 태거를 감싸던 다이아 셸 → 바깥으로 퍼지는 링.
	--   [증상] 완주해도 아무것도 안 보였다. 딜(-65)은 정상이라 기능이 아니라 연출 문제.
	--   [원인] 셸이 7×8×7(반경 3.5)인데 실측에서 러너가 태거로부터 2 stud 거리였다
	--     (진단 로그: center=(818,140,-690) / 내위치=(816,142,-692)).
	--     즉 카메라가 셸 '안'에 들어가 있었다 — 안에서는 파트가 안 보인다.
	--     근접 무기라 항상 붙어 있으므로 감싸는 형태는 구조적으로 못 보여준다.
	--   [규칙] 안에서 밖으로 퍼지는 형태만 근접에서 보인다. 링을 키우며 사라지게 한다.
	--   ⚠️ 파편(shatterAt)도 gem 위치라 코앞이다. 개수·크기를 키워 눈에 걸리게 한다.
	if center then
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		applyMarkLook(ring)
		ring.Size = Vector3.new(0.6, 4, 4)     -- 얇은 원판(눕혀서 링처럼)
		ring.Transparency = 0.25
		ring.CanCollide = false; ring.CanQuery = false; ring.CanTouch = false
		ring.Anchored = true; ring.Massless = true
		-- 원기둥을 눕혀 바닥과 평행하게 (X축이 두께)
		ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = workspace
		TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.6, 34, 34),   -- 반경 17 까지 확장 — 카메라를 지나쳐 간다
			Transparency = 1,
		}):Play()
		Debris:AddItem(ring, 0.6)
		-- 위로 솟는 기둥 하나 더 (링만으론 시선이 아래로 쏠린다)
		local pillar = Instance.new("Part")
		pillar.Shape = Enum.PartType.Cylinder
		applyMarkLook(pillar)
		pillar.Size = Vector3.new(14, 3, 3)
		pillar.Transparency = 0.35
		pillar.CanCollide = false; pillar.CanQuery = false; pillar.CanTouch = false
		pillar.Anchored = true; pillar.Massless = true
		pillar.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		pillar.Parent = workspace
		TweenService:Create(pillar, TweenInfo.new(0.45), {
			Size = Vector3.new(26, 0.5, 0.5), Transparency = 1,
		}):Play()
		Debris:AddItem(pillar, 0.5)
		shatterAt(center, 18)   -- 중심에서도 크게 터뜨린다
	end
	clearMarks()
end

Remote.OnClientEvent:Connect(function(action, a)
	if action == "markSync" then
		syncMarks(a)
	elseif action == "markHit" then
		lightMark(a)
	elseif action == "markReset" then
		resetVisual()
	elseif action == "markComplete" then
		playCompletion()
	elseif action == "markClear" then
		clearMarks()
	end
end)

Tool.Unequipped:Connect(clearMarks)

-- ⚠️ [2026-09-08] 툴이 '파괴' 될 때도 정리한다.
--   [증상] 무기를 바꿔도 표식(유리판·보석)이 표적에 그대로 남았다.
--   [원인] Unequipped 는 '손에서 내려놓을 때' 만 온다. 훈련장 무기 교체나
--     라운드 회수처럼 툴이 Destroy 되는 경로에서는 오지 않거나 너무 늦다.
--     그런데 renderConn(RenderStepped)은 살아남아 표식을 계속 그린다 —
--     스크립트가 죽어도 연결은 남는다.
--   [왜 여기서 고치나] 표식 파트는 workspace 직속에 '이름 없는 Part' 로 만들어져
--     밖에서 이름·속성으로 찾을 방법이 없다. 만든 쪽이 치우는 게 유일한 길이다.
--   ⚠️ AncestryChanged 를 함께 쓴다. Destroying 은 툴 내부 스크립트와 같은 운명이라
--     늦거나 아예 안 올 수 있다(WeaponUICleanupClient 주석의 같은 지적).
Tool.Destroying:Connect(clearMarks)
Tool.AncestryChanged:Connect(function(_, parent)
	if not parent then clearMarks() end
end)
