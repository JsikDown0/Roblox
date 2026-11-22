-- Vishnu(Ascendant) 스킨 전용: 황금 광배 + 4팔. 물리 간섭 방지 위해 캐릭터에 용접하지 않고
-- 워크스페이스에 두고 매 프레임 등을 CFrame 추종. 원본 양팔 숨김. 푸시/그랩 시 4팔 랜덤 스윙.
local SS = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local SWING_ANIM = "rbxassetid://127887511089441"
local ARMS_OFFSET = CFrame.new(0, 0.3, 0.9)                         -- 마운트=등 뒤
-- 광배: 사용자가 배치한 위치 측정값 (HRP 기준 LocalCF — 링 비주얼이 등에 오는 파트 위치)
local HALO_OFFSET = CFrame.new(0, 0.68, -5.779) * CFrame.Angles(math.rad(15), 0, 0)

local active = {}   -- [char] = {folder=, conn=, mount=}
local pushGodBurst   -- forward 선언 (VishnuAttach에서 먼저 참조)

local function getTorso(char) return char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") end

local function setArmsHidden(char, hidden)
	for _, side in ipairs({"Right", "Left"}) do
		for _, part in ipairs({"UpperArm", "LowerArm", "Hand", "Arm"}) do
			local p = char:FindFirstChild(side..part)
			if p and p:IsA("BasePart") then
				if hidden then p:SetAttribute("_VishnuOldTr", p.Transparency); p.Transparency = 1
				else local o = p:GetAttribute("_VishnuOldTr"); if o ~= nil then p.Transparency = o; p:SetAttribute("_VishnuOldTr", nil) end end
			end
		end
	end
end

_G.VishnuAttach = function(char)
	if not char or active[char] then return end
	local torso = getTorso(char)
	if not torso then warn("[Vishnu] torso 없음 — 부착 실패"); return end
	local haloSrc = SS:FindFirstChild("VishnuHalo")
	local armsSrc = SS:FindFirstChild("VishnuArms")
	print("[Vishnu] Attach 시작. torso="..torso.Name.." haloSrc="..tostring(haloSrc~=nil).." armsSrc="..tostring(armsSrc~=nil))
	if armsSrc then
		local n=0; for _,m in ipairs(armsSrc:GetChildren()) do if m:IsA("Model") then n=n+1 end end
		print("[Vishnu] 템플릿 팔 모델 "..n.."개")
	end
	-- 캐릭터 팔 파츠 이름 확인 (숨김 대상)
	local armParts = {}
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("BasePart") and (string.find(c.Name,"Arm") or string.find(c.Name,"Hand")) then armParts[#armParts+1]=c.Name end
	end
	print("[Vishnu] 캐릭터 팔 파츠: "..(table.concat(armParts,", ")))
	if not haloSrc or not armsSrc then warn("[Vishnu] 템플릿 없음"); return end

	-- 원본 양팔은 보이게 유지 (4팔 + 본체 팔 = 6팔 실루엣)
	-- setArmsHidden(char, true)
	-- PushTool 도구 손(Handle + 스킨메시)도 숨김 — Vishnu는 4팔만
	for _, t in ipairs(char:GetChildren()) do
		if t:IsA("Tool") then
			local h = t:FindFirstChild("Handle")
			if h and h:IsA("BasePart") then h:SetAttribute("_VishnuOldTr", h.Transparency); h.Transparency = 1
				local sm = h:FindFirstChild("_SkinMesh"); if sm then sm:SetAttribute("_VishnuOldTr", sm.Transparency); sm.Transparency = 1 end
			end
		end
	end
	-- 기존 잔여 폴더 정리 (중복 방지)
	local prev = workspace:FindFirstChild("_VishnuAura_"..char.Name); if prev then prev:Destroy() end
	-- ★ 캐릭터가 아니라 워크스페이스에 부착 (물리 assembly 분리)
	local folder = Instance.new("Folder"); folder.Name = "_VishnuAura_"..char.Name; folder.Parent = workspace

	local arms = armsSrc:Clone(); arms.Name = "Arms"
	local mount = arms.Mount
	-- ★ 정크(WrapTarget/제약/이름충돌) 제거된 순수 파츠라 이제 용접 안전 → 지연 0으로 딱 붙음
	local function prepPart(p)
		p.Anchored = false; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.Massless = true
	end
	prepPart(mount)
	mount.CFrame = torso.CFrame * ARMS_OFFSET
	local mw = Instance.new("WeldConstraint"); mw.Part0 = torso; mw.Part1 = mount; mw.Parent = mount
	local roots = {}
	for _, arm in ipairs(arms:GetChildren()) do
		if arm:IsA("Model") then
			local root = arm:FindFirstChild("Root")
			if root then
				for _, w in ipairs(root:GetChildren()) do if w:IsA("WeldConstraint") or w:IsA("Weld") then w:Destroy() end end
				local off = armsSrc.Mount.CFrame:ToObjectSpace(root.CFrame)
				prepPart(root)
				-- 팔 파츠 전체 물리 무해화
				for _, p in ipairs(arm:GetDescendants()) do if p:IsA("BasePart") then prepPart(p) end end
				root.CFrame = mount.CFrame * off
				local rw = Instance.new("WeldConstraint"); rw.Part0 = mount; rw.Part1 = root; rw.Parent = root
				roots[#roots+1] = root
			end
		end
	end
	arms.Parent = folder
	print("[Vishnu] 용접 부착. 팔 Root "..#roots.."개")

	-- 광배: HRP에 용접 (HRP는 걷기 애니에 안 흔들리는 루트 → 밀착 + 안정 + 지연 0)
	local halo = haloSrc:Clone(); halo.Name = "Halo"
	prepPart(halo)
	local hrp = char:FindFirstChild("HumanoidRootPart") or torso
	halo.CFrame = hrp.CFrame * HALO_OFFSET
	local hw = Instance.new("WeldConstraint"); hw.Part0 = hrp; hw.Part1 = halo; hw.Parent = halo
	halo.Parent = folder

	-- 공중부양: HipHeight 상승 + sine 둥실거림 (초월자)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local conn = nil
	local idleTrack = nil
	if hum then
		local baseHip = hum.HipHeight
		char:SetAttribute("_VishnuBaseHip", baseHip)
		local t0 = os.clock()
		conn = RunService.Heartbeat:Connect(function()
			if not char.Parent or not hum.Parent then return end
			local bob = math.sin((os.clock() - t0) * 2.2) * 0.35   -- 둥실 주기/폭
			hum.HipHeight = baseHip + 1.4 + bob
		end)
		-- 초월자 idle 애니 (부양 자세 — 루프)
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then animator = Instance.new("Animator"); animator.Parent = hum end
		-- 기본 Animate 스크립트 비활성 (걷기/점프 애니가 조인트 단위로 새는 것 원천 차단)
		local animate = char:FindFirstChild("Animate")
		if animate and animate:IsA("LocalScript") then animate.Disabled = true end
		local anim = Instance.new("Animation"); anim.AnimationId = "rbxassetid://104124357238880"
		local ok, tr = pcall(function() return animator:LoadAnimation(anim) end)
		if ok and tr then
			tr.Priority = Enum.AnimationPriority.Action   -- 걷기/기본 애니에 안 덮임 (공중 모션 유지)
			tr.Looped = true
			tr:Play(0.3)
			idleTrack = tr
		end
		-- 이미 재생 중인 기본 애니 정지 (클라 쪽은 VishnuAnimClient가 처리 — 이건 서버 보조)
		task.spawn(function()
			for i = 1, 10 do
				if not char.Parent then break end
				for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
					if t ~= idleTrack then t:Stop(0.1) end
				end
				task.wait(0.05)
			end
		end)
	end

	-- 등 뒤 상시 Specs 잔향 (지나온 길 꾸미기) — HRP 뒤쪽에 용접, 이동 시에만 방출
	local trailSrc = SS:FindFirstChild("VishnuTrailSpecs")
	if trailSrc then
		local trail = trailSrc:Clone()
		local hrpT = char:FindFirstChild("HumanoidRootPart") or torso
		trail.CFrame = hrpT.CFrame * CFrame.new(0, 0, 2.0)   -- 등 뒤 2 stud
		local tw = Instance.new("WeldConstraint"); tw.Part0 = hrpT; tw.Part1 = trail; tw.Parent = trail
		trail.Parent = folder
		local em = trail:FindFirstChildOfClass("ParticleEmitter")
		-- 이동 속도에 따라 Rate 조절: 정지=0, 달릴수록 방출
		if em then
			task.spawn(function()
				while trail.Parent and char.Parent do
					local speed = hrpT.AssemblyLinearVelocity.Magnitude
					em.Rate = (speed > 4) and math.clamp(speed * 0.6, 0, 14) or 0
					task.wait(0.1)
				end
			end)
		end
	end

	active[char] = {folder = folder, conn = conn, mount = mount, idleTrack = idleTrack}
	char:SetAttribute("VishnuAura", true)   -- 푸시 판정 확대 등 외부 참조용

	-- 장착 사운드 + 첫 장착 god effect 버스트
	local hrp0 = char:FindFirstChild("HumanoidRootPart")
	if hrp0 then
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://105841275801305"; s.Volume = 1.0
		s.Parent = hrp0; s:Play()
		game:GetService("Debris"):AddItem(s, 5)
	end
	pushGodBurst(char)   -- 강림 순간 버스트 (푸시와 동일)
end

_G.VishnuRemove = function(char)
	if not char then return end
	char:SetAttribute("VishnuAura", nil)
	-- 부양 복원
	local hum = char:FindFirstChildOfClass("Humanoid")
	local baseHip = char:GetAttribute("_VishnuBaseHip")
	if hum and baseHip then hum.HipHeight = baseHip end
	char:SetAttribute("_VishnuBaseHip", nil)
	-- 기본 Animate 재활성 (걷기 애니 복원)
	local animate = char:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then animate.Disabled = false end
	local a = active[char]
	if a then
		if a.conn then a.conn:Disconnect() end
		if a.idleTrack then a.idleTrack:Stop(0.2) end
		if a.folder then a.folder:Destroy() end
		active[char] = nil
	end
	-- 혹시 남은 워크스페이스 폴더도 정리
	local leftover = workspace:FindFirstChild("_VishnuAura_"..char.Name); if leftover then leftover:Destroy() end
	setArmsHidden(char, false)
	-- PushTool 도구 손 복원
	for _, t in ipairs(char:GetChildren()) do
		if t:IsA("Tool") then
			local h = t:FindFirstChild("Handle")
			if h and h:IsA("BasePart") then
				local o = h:GetAttribute("_VishnuOldTr"); if o ~= nil then h.Transparency = o; h:SetAttribute("_VishnuOldTr", nil) end
				local sm = h:FindFirstChild("_SkinMesh"); if sm then local o2 = sm:GetAttribute("_VishnuOldTr"); if o2 ~= nil then sm.Transparency = o2; sm:SetAttribute("_VishnuOldTr", nil) end end
			end
		end
	end
end

-- 푸시/그랩 시 4팔 중 하나가 앞으로 확 꺾어 강타 (통짜 메시 — 어깨 Motor6D C0 트윈, 앵커 없음).
local swinging = {}   -- [armModel] = true (중복 방지)
-- 푸시 순간 몸 중심에서 god effect 버스트 (켰다 끄기 — 서버 Emit 복제 문제 회피)
pushGodBurst = function(char)
	local tmpl = SS:FindFirstChild("VishnuPushBurst")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not tmpl or not hrp then return end
	local p = tmpl:Clone()
	p.Anchored = true
	p.CFrame = hrp.CFrame
	for _, d in ipairs(p:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			if d.Name == "Specs" then
				d.Rate = d.Rate * 1.0   -- Specs(파편)는 원본 그대로
			else
				d.Rate = d.Rate * 3     -- 버스트 증폭 (5는 과함)
			end
			d.Enabled = true
		elseif d:IsA("PointLight") then
			d.Brightness = d.Brightness * 0.4   -- 밝기 감소
			d.Enabled = true
		end
	end
	p.Parent = workspace
	task.delay(0.35, function()
		if p and p.Parent then
			for _, d in ipairs(p:GetDescendants()) do
				if d:IsA("ParticleEmitter") then d.Enabled = false end
			end
		end
	end)
	game:GetService("Debris"):AddItem(p, 2)
end

_G.VishnuSwing = function(char)
	if not char then return end
	local a = active[char]
	local arms = a and a.folder and a.folder:FindFirstChild("Arms")
	if not arms then return end
	pushGodBurst(char)   -- 몸 중심 god effect 버스트
	-- 스윙/그랩 공통 사운드
	local hrpS = char:FindFirstChild("HumanoidRootPart")
	if hrpS then
		local s = Instance.new("Sound"); s.SoundId = "rbxassetid://113365564593023"; s.Volume = 2.7
		s.Parent = hrpS; s:Play(); game:GetService("Debris"):AddItem(s, 3)
	end
	local models = {}
	for _, m in ipairs(arms:GetChildren()) do
		if m:IsA("Model") and not swinging[m] then models[#models+1] = m end
	end
	if #models == 0 then return end
	local arm = models[math.random(#models)]
	local root = arm:FindFirstChild("Root")
	local sh = root and root:FindFirstChild("RightShoulder")
	if not sh or not sh:IsA("Motor6D") then return end
	swinging[arm] = true
	task.spawn(function()
		local base = sh.C0
		-- 뺨때리기 (캐릭터 기준 공통 축): 팔 정지 각도와 무관하게 모든 팔이 같은 동작.
		-- 마운트(캐릭터) 공간의 회전을 root 공간으로 변환해 pre-multiply.
		local mount = a.mount
		local side = (arm.Name:sub(-1) == "L") and -1 or 1
		local conv = root.CFrame.Rotation:Inverse() * mount.CFrame.Rotation
		local function mdelta(rx, ry, rz)
			return conv * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz)) * conv:Inverse()
		end
		local windup = mdelta(10, 55 * side, 0) * base     -- 바깥·뒤로 장전
		local smash  = mdelta(-20, -115 * side, 0) * base  -- 앞을 가로질러 스매시
		local T_WIND, T_SMASH, T_HOLD, T_BACK = 0.12, 0.09, 0.05, 0.25
		local t0 = os.clock()
		while os.clock() - t0 < T_WIND do
			local al = (os.clock()-t0)/T_WIND
			sh.C0 = base:Lerp(windup, math.sin(al * math.pi * 0.5))
			task.wait()
		end
		sh.C0 = windup
		t0 = os.clock()
		while os.clock() - t0 < T_SMASH do
			local al = (os.clock()-t0)/T_SMASH
			sh.C0 = windup:Lerp(smash, al * al)   -- 가속 (스매시!)
			task.wait()
		end
		sh.C0 = smash
		task.wait(T_HOLD)
		t0 = os.clock()
		while os.clock() - t0 < T_BACK do
			local al = (os.clock()-t0)/T_BACK
			sh.C0 = smash:Lerp(base, al*al*(3-2*al))
			task.wait()
		end
		sh.C0 = base
		swinging[arm] = nil
	end)
end

-- 그랩 연출: 4팔 중 랜덤 하나를 잠시 숨김 (그 팔이 발사된 것처럼) / 복귀
_G.VishnuGrabArmHide = function(char)
	local a = active[char]
	local arms = a and a.folder and a.folder:FindFirstChild("Arms")
	if not arms then return nil end
	local models = {}
	for _, m in ipairs(arms:GetChildren()) do
		if m:IsA("Model") and not m:GetAttribute("_GrabHidden") then models[#models+1] = m end
	end
	if #models == 0 then return nil end
	local arm = models[math.random(#models)]
	arm:SetAttribute("_GrabHidden", true)
	for _, p in ipairs(arm:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Root" then p.Transparency = 1 end
	end
	return arm
end
_G.VishnuGrabArmShow = function(arm)
	if not arm or not arm.Parent then return end
	arm:SetAttribute("_GrabHidden", nil)
	for _, p in ipairs(arm:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "Root" then p.Transparency = 0 end
	end
end

-- 캐릭터 사라지면 정리
Players.PlayerRemoving:Connect(function(plr)
	if plr.Character then _G.VishnuRemove(plr.Character) end
end)

print("✅ _VishnuAuraSystem 준비 (CFrame 추종 방식, 물리 분리)")
