-- 테스트 커맨드 (채팅 명령어)
-- /tagger      → 자신을 태거로 설정
-- /runner      → 자신을 러너로 설정
-- /norole      → 역할 초기화
-- /itemtest    → 러너 역할 + map1 이동 + 러너 아이템 전부 지급(분신 지팡이 포함) + 라운드 정지 + 옆에 다운자 소환
-- /itemtestoff → 라운드 재개
-- /decoyhit    → 분신 위치에 테스트 태거 파트 생성 (분신 소멸 솔로 테스트용)
-- /freeze [N]  → Ice Bow 명중 효과 본인에게 시뮬레이션 (기본 1초, /freeze 3 가능)
-- /crown       → 본인 머리에 태거 왕관 토글 (부여/제거)
local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")
local ServerScriptService = game:GetService("ServerScriptService")
local DownSystem = require(ServerScriptService:WaitForChild("DownSystem"))

-- 🔒 개발자 전용 게이트 (공유 화이트리스트: ServerScriptService.DevAuth)
local isDev = require(ServerScriptService:WaitForChild("DevAuth")).isDev

-- map1 테스트 위치 (Hill 근처)
local TEST_POS = Vector3.new(350, 80, -674)
local NOOB_OFFSET = Vector3.new(5, 0, 0)  -- 플레이어 옆 5 stud

-- ── 헬퍼: ServerStorage.RunnerItem에서 Tool을 백팩에 지급 ─────
local function giveRunnerItem(player, itemName)
	local char     = player.Character
	local backpack = player:FindFirstChild("Backpack")
	if not char and not backpack then return end

	-- 기존 중복 제거
	for _, loc in ipairs({char, backpack}) do
		if loc then
			local t = loc:FindFirstChild(itemName)
			if t then t:Destroy() end
		end
	end

	local runnerItems = ServerStorage:FindFirstChild("RunnerItem")
	local template    = runnerItems and runnerItems:FindFirstChild(itemName)
	if template then
		local clone = template:Clone()

		-- 카타나 색놀이: 장착 스킨 색을 검은 파트에 적용 + SkinColor 속성 (테스트 지급에도 반영)
		if itemName == "KatanaSword2" and _G.getEquippedSkin and _G.getSwordSkinData then
			local skinName = _G.getEquippedSkin(player, "KatanaSword2")
			local skinData = skinName and _G.getSwordSkinData("KatanaSword2", skinName)
			if skinData and skinData.meshSwap then
				-- 모델 교체 스킨(Crimson Fang): Stage2TriggerSystem과 동일 처리.
				-- 카타나는 부품 10개라 Handle만 숨기면 칼날이 남음 → 전체 순회.
				local handle = clone:FindFirstChild("Handle")
				for _, p in ipairs(clone:GetDescendants()) do
					if p:IsA("BasePart") then
						p.Transparency = 1
						local msh = p:FindFirstChildWhichIsA("SpecialMesh")
						if msh then msh.TextureId = "" end
						for _, dec in ipairs(p:GetChildren()) do
							if dec:IsA("Decal") or dec:IsA("Texture") then dec:Destroy() end
						end
					end
				end
				local bank = game:GetService("ServerStorage"):FindFirstChild("WeaponSkins")
				local src = bank and bank:FindFirstChild(skinData.meshSwap)
				if handle and src then
					local sk = src:Clone()
					sk.Name = "_SkinModel"
					local off = skinData.swapOffset or {0, 0, 0}
					local rot = skinData.swapRot or {0, 0, 0}
					local target = handle.CFrame
						* CFrame.new(off[1], off[2], off[3])
						* CFrame.fromOrientation(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
					if sk:IsA("Model") and sk.PrimaryPart then
						-- ⚠ Model:PivotTo() 금지: 임포트 모델은 Pivot이 월드 원점에 잡혀 큰 오프셋 발생.
						--    PrimaryPart 기준 상대 CFrame을 직접 계산해 파트를 개별 배치.
						local ref = sk.PrimaryPart.CFrame
						sk.Parent = clone
						for _, p in ipairs(sk:GetDescendants()) do
							if p:IsA("BasePart") then
								local rel = ref:ToObjectSpace(p.CFrame)
								p.CFrame = target * rel
								p.Anchored = false; p.CanCollide = false; p.Massless = true
								local w = Instance.new("WeldConstraint")
								w.Part0 = handle; w.Part1 = p; w.Parent = handle
							end
						end
					end
					local glow = sk:FindFirstChild("Glow", true)
					clone:SetAttribute("SkinColor", glow and glow.Color or Color3.fromRGB(255, 0, 1))
     clone:SetAttribute("LegendarySkin", true)   -- 카운터 EMP 트리거
					-- [진단] 적용 결과 위치 확인 (값 확정 후 삭제)
					task.delay(0.5, function()
						local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						print("═══ [SkinDiag] ═══")
						print("  Handle pos =", handle and handle.Position)
						for _, p in ipairs(sk:GetDescendants()) do
							if p:IsA("BasePart") then
								local d = hrp and (p.Position - hrp.Position).Magnitude or -1
								print(string.format("  %-8s pos=%s  HRP거리=%.1f  투명=%.2f  부모=%s",
									p.Name, tostring(p.Position), d, p.Transparency, p.Parent.Name))
							end
						end
						print("  _SkinModel 부모 =", sk.Parent and sk.Parent:GetFullName() or "nil")
						print("══════════════════")
					end)
					print("🗡️ [TEST] 모델교체 스킨 적용:", skinData.meshSwap)
				else
					warn("[TEST] WeaponSkins." .. tostring(skinData.meshSwap) .. " 없음")
				end
			elseif skinData and skinData.color then
				for _, p in ipairs(clone:GetDescendants()) do
					if p:IsA("BasePart") then
						local c = p.Color
						if c.R*255 < 80 and c.G*255 < 80 and c.B*255 < 80 then
							p.Color = skinData.color
							if skinData.rainbow then
								p:SetAttribute("RainbowPart", true)  -- 순환 대상 표시
							end
						end
					end
				end
				clone:SetAttribute("SkinColor", skinData.color)
				if skinData.rainbow then
					clone:SetAttribute("RainbowSkin", true)  -- 참격 무지개 신호
					-- 무지개 순환 스크립트 복제 삽입 (.Source 런타임 작성 불가 → 템플릿 Clone)
					local tmpl = game:GetService("ServerStorage"):FindFirstChild("KatanaRainbowTemplate")
					if tmpl then
						local cyc = tmpl:Clone()
						cyc.Name = "KatanaRainbow"
						cyc.Disabled = false
						cyc.Parent = clone
					end
				end
			elseif not skinData then
				-- _Custom: KatanaColor/KatanaMaterial 속성 있으면 태그 파트 칠 + SkinColor
				local colorName = player:GetAttribute("KatanaColor_Blade")
				if colorName then
					local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
					if palette.COLORS[colorName] then
						local cfg = palette.getConfig("KatanaSword2")
						local finishKey = player:GetAttribute("KatanaMaterial_Blade") or cfg.materialDefault
						local col = palette.COLORS[colorName]
						for _, p in ipairs(clone:GetDescendants()) do
							if p:IsA("BasePart") and p:GetAttribute("SkinPaintPart") then
								palette.applyFinish(p, finishKey, col)
							end
						end
						clone:SetAttribute("SkinColor", col)
					end
				end
			end
		end

		-- 망치 색놀이: 장착 스킨의 색/이펙트색을 속성으로 심음 (HammerScript가 읽어 적용)
		-- Diamond Blade mesh-swap skin (Ice Crystal Blade): same weld pattern as Stage2.
		if itemName == "DiamondBladeSword" and _G.getEquippedSkin and _G.getSwordSkinData then
			local skinName = _G.getEquippedSkin(player, "DiamondBladeSword")
			local skinData = skinName and _G.getSwordSkinData("DiamondBladeSword", skinName)
			local handle = clone:FindFirstChild("Handle")
			if skinData and handle and skinData.meshSwap then
				handle.Transparency = 1
				local hmesh = handle:FindFirstChild("Mesh")
				if hmesh then hmesh.TextureId = "" end
				local bank = ServerStorage:FindFirstChild("WeaponSkins")
				local skinMesh = bank and bank:FindFirstChild(skinData.meshSwap)
				if skinMesh then
					local m = skinMesh:Clone()
					m.Name = "_SkinMesh"
					m.Anchored = false; m.CanCollide = false; m.Massless = true
					local sc = skinData.swapScale or 1
					m.Size = skinMesh.Size * sc
					local off = skinData.swapOffset or {0,0,0}
					local rot = skinData.swapRot or {0,0,0}
					local rel = CFrame.new(off[1], off[2], off[3])
						* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
					m.CFrame = handle.CFrame * rel
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = handle; weld.Part1 = m; weld.Parent = m
					m.Parent = handle
					if skinData.iceMarks then
						clone:SetAttribute("IceMarks", true)
						-- pale icy trail + frost snowflakes (from Frost Dragon)
						local trail = handle:FindFirstChild("Trail")
						if trail then trail.Color = ColorSequence.new(Color3.fromRGB(120, 195, 235)) end
						local fd = ServerStorage:FindFirstChild("TaggerItem")
						fd = fd and fd:FindFirstChild("Frost Dragon")
						local ifx = fd and fd:FindFirstChild("icefx_point")
						ifx = ifx and ifx:FindFirstChild("pt1")
						local snowSrc = ifx and ifx:FindFirstChild("ParticleEmitter")
						if snowSrc then
							local snow = snowSrc:Clone()
							snow.Name = "_FrostSnow"
							snow.Enabled = true
							snow.Parent = handle
						end
					end
					print("[TEST] Ice Crystal Blade skin applied")
				end
			end
		end

		-- Mech Gauntlet mesh-swap skin: hide all gauntlet parts + weld the WeaponSkins mesh.
		if itemName == "Gauntlet" and _G.getEquippedSkin and _G.getSwordSkinData then
			local skinName = _G.getEquippedSkin(player, "Gauntlet")
			local skinData = skinName and _G.getSwordSkinData("Gauntlet", skinName)
			local handle = clone:FindFirstChild("Handle")
			if skinData and handle and skinData.meshSwap then
				for _, d in ipairs(clone:GetDescendants()) do
					if d:IsA("BasePart") then d.Transparency = 1 end
				end
				local bank = game:GetService("ServerStorage"):FindFirstChild("WeaponSkins")
				local skinMesh = bank and bank:FindFirstChild(skinData.meshSwap)
				if skinMesh then
					local m = skinMesh:Clone()
					m.Name = "_SkinMesh"
					m.Anchored = false; m.CanCollide = false; m.Massless = true
					local sc = skinData.swapScale or 1
					m.Size = skinMesh.Size * sc
					local off = skinData.swapOffset or {0,0,0}
					local rot = skinData.swapRot or {0,0,0}
					local rel = CFrame.new(off[1], off[2], off[3])
						* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
					m.CFrame = handle.CFrame * rel
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = handle; weld.Part1 = m; weld.Parent = m
					m.Parent = handle
					-- booster stick parts: reposition by stored LocalCF, then weld (source welds are removed)
					for _, bp in ipairs(m:GetChildren()) do
						local lcf = bp:GetAttribute("LocalCF")
						if bp:IsA("BasePart") and lcf then
							bp.CFrame = m.CFrame * lcf
							local bw = Instance.new("WeldConstraint")
							bw.Part0 = m; bw.Part1 = bp; bw.Parent = bp
						end
					end
					print("[TEST] Mech Gauntlet skin applied")
				end
			end
		end

		-- Flame Hammer mesh-swap skin: hide all hammer parts + weld the WeaponSkins mesh.
		if itemName == "HammerHigh" and _G.getEquippedSkin and _G.getSwordSkinData then
			local skinName = _G.getEquippedSkin(player, "HammerHigh")
			local skinData = skinName and _G.getSwordSkinData("HammerHigh", skinName)
			local handle = clone:FindFirstChild("Handle")
			if skinData and handle and skinData.meshSwap then
				for _, d in ipairs(clone:GetDescendants()) do
					if d:IsA("BasePart") then d.Transparency = 1 end
				end
				if skinData.flameOffset then
					local ft = clone:FindFirstChild("flame tail")
					if ft then
						for _, w in ipairs(clone:GetDescendants()) do
							if w:IsA("WeldConstraint") and (w.Part1 == ft or w.Part0 == ft) then w:Destroy() end
						end
						local rel = handle.CFrame:ToObjectSpace(ft.CFrame)
						local fo = skinData.flameOffset
						ft.CFrame = handle.CFrame * (CFrame.new(fo[1], fo[2], fo[3]) * (rel - rel.Position))
						local fw = Instance.new("WeldConstraint")
						fw.Part0 = handle
						fw.Part1 = ft
						fw.Parent = ft
					end
				end
				local bank = game:GetService("ServerStorage"):FindFirstChild("WeaponSkins")
				local skinMesh = bank and bank:FindFirstChild(skinData.meshSwap)
				if skinMesh then
					local m = skinMesh:Clone()
					m.Name = "_SkinMesh"
					m.Anchored = false; m.CanCollide = false; m.Massless = true
					local sc = skinData.swapScale or 1
					m.Size = skinMesh.Size * sc
					local off = skinData.swapOffset or {0,0,0}
					local rot = skinData.swapRot or {0,0,0}
					local rel = CFrame.new(off[1], off[2], off[3])
						* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
					m.CFrame = handle.CFrame * rel
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = handle; weld.Part1 = m; weld.Parent = m
					m.Parent = handle
					for _, cp in ipairs(m:GetChildren()) do
						local lcf = cp:GetAttribute("LocalCF")
						if cp:IsA("BasePart") and lcf then
							cp.CFrame = m.CFrame * lcf
							local cw = Instance.new("WeldConstraint")
							cw.Part0 = m; cw.Part1 = cp; cw.Parent = cp
						end
					end
					print("[TEST] Flame Hammer skin applied")
				end
			end
		end

		if itemName == "HammerLow" and _G.getEquippedSkin and _G.getSwordSkinData then
			local skinName = _G.getEquippedSkin(player, "HammerLow")
			local skinData = skinName and _G.getSwordSkinData("HammerLow", skinName)
			if skinData then
				if skinData.color then clone:SetAttribute("SkinColor", skinData.color) end
				if skinData.material then clone:SetAttribute("SkinMaterial", skinData.material) end
				if skinData.effectColor then clone:SetAttribute("EffectColor", skinData.effectColor) end
				if skinData.effectModel then clone:SetAttribute("EffectModel", skinData.effectModel) end
				if skinData.particle then clone:SetAttribute("Particle", skinData.particle) end
				if skinData.thunderStrike then clone:SetAttribute("ThunderStrike", true) end
				if skinData.auraParticle then clone:SetAttribute("AuraParticle", skinData.auraParticle) end
				if skinData.keepTexture then clone:SetAttribute("KeepTexture", true) end
				if skinData.meshSwap then
					clone:SetAttribute("MeshSwap", skinData.meshSwap)
					if skinData.swapScale then clone:SetAttribute("SwapScale", skinData.swapScale) end
					if skinData.swapOffset then clone:SetAttribute("SwapOffset", Vector3.new(skinData.swapOffset[1], skinData.swapOffset[2], skinData.swapOffset[3])) end
					if skinData.swapRot then clone:SetAttribute("SwapRot", Vector3.new(skinData.swapRot[1], skinData.swapRot[2], skinData.swapRot[3])) end
				end
				if skinData.rainbow then
					-- 무지개: Handle을 순환 대상으로 표시 + 이펙트 순환 신호 + 순환 스크립트 삽입
					local handle = clone:FindFirstChild("Handle")
					if handle then
						local mesh = handle:FindFirstChildOfClass("SpecialMesh")
						if mesh then mesh.TextureId = "" end   -- Neon 단색이 보이게
						handle.Material = Enum.Material.Neon
						handle:SetAttribute("RainbowPart", true)
					end
					clone:SetAttribute("RainbowSkin", true)   -- HammerScript가 이펙트 Beam도 순환
					local tmpl = game:GetService("ServerStorage"):FindFirstChild("HammerRainbowTemplate")
					if tmpl then
						local cyc = tmpl:Clone()
						cyc.Name = "HammerRainbow"
						cyc.Disabled = false
						cyc.Parent = clone
					end
				end
			elseif not skinData then
				-- _Custom: HammerColor/HammerMaterial → SkinColor/EffectColor/SkinMaterial (HammerScript용)
				local colorName = player:GetAttribute("HammerColor_Head")
				if colorName then
					local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
					if palette.COLORS[colorName] then
						local cfg = palette.getConfig("HammerLow")
						local finishKey = player:GetAttribute("HammerMaterial_Head") or cfg.materialDefault
						local col = palette.COLORS[colorName]
						local f = palette.FINISHES[finishKey]
						clone:SetAttribute("SkinColor", col)
						clone:SetAttribute("SkinMaterial", (f and f.material) or "Neon")
						clone:SetAttribute("EffectColor", col)
					end
				end
			end
		end

		-- 클래식 소드 색놀이: effect 색 스킨 or _Custom (Stage2 지급과 동일)
		if itemName == "ClassicSword" and _G.getEquippedSkin and _G.getSwordSkinData then
			local skinName = _G.getEquippedSkin(player, "ClassicSword")
			local skinData = skinName and _G.getSwordSkinData("ClassicSword", skinName)
			local handle = clone:FindFirstChild("Handle")
			if skinData and handle then
				if skinData.material then handle.Material = Enum.Material[skinData.material] end
				if skinData.cycle then
					local mesh = handle:FindFirstChild("Mesh")
					if mesh then mesh.TextureId = ""; mesh.VertexColor = Vector3.new(1,1,1) end
					local tmpl = ServerStorage:FindFirstChild("RainbowCycleTemplate")
					if tmpl then local cyc = tmpl:Clone(); cyc.Name = "RainbowCycle"; cyc.Disabled = false; cyc.Parent = handle end
				elseif skinData.color then
					local mesh = handle:FindFirstChild("Mesh")
					if mesh then mesh.TextureId = ""; mesh.VertexColor = Vector3.new(1,1,1) end
					handle.Color = skinData.color
				end
			elseif handle then
				local colorName = player:GetAttribute("ClassicColor_Blade")
				if colorName then
					local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
					if palette.COLORS[colorName] then
						local cfg = palette.getConfig("ClassicSword")
						local finishKey = player:GetAttribute("ClassicMaterial_Blade") or cfg.materialDefault
						palette.applyFinish(handle, finishKey, palette.COLORS[colorName])
					end
				end
			end
		end

		-- 무기 색놀이 스킨 적용 (공통): 장착된 스킨 데이터를 읽어 속성 부여.
		-- 무지개는 RainbowSkin, 단색은 SkinHue/Sat/Val. 무기 스크립트가 속성을 읽어 칠함.
		if _G.getEquippedSkin and _G.getSwordSkinData then
			local skinName = _G.getEquippedSkin(player, itemName)
			local skinData = skinName and _G.getSwordSkinData(itemName, skinName)
			if skinData then
				if skinData.rainbow then
					clone:SetAttribute("RainbowSkin", true)
				elseif skinData.solidHSV then
					-- 단색: HSV를 속성으로 부여 → 무기 스크립트가 한 번 칠함
					clone:SetAttribute("SkinHue", skinData.solidHSV[1])
					clone:SetAttribute("SkinSat", skinData.solidHSV[2])
					clone:SetAttribute("SkinVal", skinData.solidHSV[3])
					if skinData.loveEffect then clone:SetAttribute("LoveEffect", true) end
					if skinData.iceGround then clone:SetAttribute("IceGround", true) end
					if skinData.snowEffect then clone:SetAttribute("SnowEffect", true) end
					if skinData.swingAnim then clone:SetAttribute("SwingAnim", skinData.swingAnim) end
					if skinData.inspectAnim then clone:SetAttribute("InspectAnim", skinData.inspectAnim) end
				end
			elseif not skinData then
				-- _Custom: hsvApply 무기(SakuraBlade 등)는 색→HSV→SkinHue/Sat/Val (무기스크립트가 칠)
				local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
				local cfg = palette.getConfig(itemName)
				if cfg and cfg.hsvApply then
					local colorName = player:GetAttribute((cfg.colorAttr or "") .. "_" .. cfg.zones[1])
					local col = colorName and palette.COLORS[colorName]
					if col then
						local h, s, v = col:ToHSV()
						clone:SetAttribute("SkinHue", h)
						clone:SetAttribute("SkinSat", s)
						clone:SetAttribute("SkinVal", v)
						if cfg.materialAttr then
							local finishKey = player:GetAttribute(cfg.materialAttr .. "_" .. cfg.zones[1]) or cfg.materialDefault
							local f = finishKey and palette.FINISHES[finishKey]
							clone:SetAttribute("SkinMaterial", (f and f.material) or "Metal")
						end
					end
				end
			end
		end

		clone.Parent = backpack or char
		print("📦 [TEST] 지급:", itemName, "→", player.Name)
	else
		warn("[TEST] " .. itemName .. " 템플릿 못 찾음")
	end
end

-- ── 헬퍼: Noob을 플레이어 옆으로 이동 + 다운 상태로 ─────────
local function spawnDownedNoobNear(player)
	local noob = workspace:FindFirstChild("Noob")
	if not noob then
		warn("[TEST] workspace.Noob 모델 없음")
		return
	end

	local playerChar = player.Character
	local playerRoot = playerChar and (playerChar:FindFirstChild("HumanoidRootPart") or playerChar:FindFirstChild("Torso"))
	if not playerRoot then return end

	-- Noob 상태 정상화 먼저 (이전 라운드 잔여 상태 청소)
	local hum = noob:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- 기존 다운 상태면 clearDown으로 초기화
	if noob:GetAttribute("Downed") then
		DownSystem.clearDown(noob, 1.0)   -- 1.0 = 풀피. 테스트 더미 기준선 유지(부활 아님)
	end

	-- 모든 파트: Anchored 해제 + RunnerCharacter 그룹
	for _, part in ipairs(noob:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			pcall(function() part.CollisionGroup = "RunnerCharacter" end)
		end
	end

	-- HP/스피드 초기화
	hum.MaxHealth = 100
	hum.Health = 100
	hum.PlatformStand = false
	hum.WalkSpeed = 16

	-- 플레이어 옆으로 이동
	local rootPart = noob:FindFirstChild("HumanoidRootPart") or noob:FindFirstChild("Torso")
	if rootPart then
		rootPart.CFrame = CFrame.new(playerRoot.Position + NOOB_OFFSET)
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end

	-- 잠시 안정화 후 다운 상태로
	task.delay(0.2, function()
		if noob and noob.Parent and hum.Health > 0 then
			DownSystem.triggerDown(noob)
			print("🩸 [TEST] Noob 다운 소환 → 옆에 배치")
		end
	end)
end

-- runnerdummy2 홈 위치 + 원본 템플릿 캡처 (/reply 부활용)
-- 죽은 Humanoid는 Health만 올려선 안 되살아나므로 신선한 복제본으로 리스폰
local dummyHomeCF = nil
local dummyTemplate = nil
do
	local dummy = workspace:FindFirstChild("runnerdummy2")
	if dummy then
		dummyHomeCF = dummy:GetPivot()
		dummyTemplate = dummy:Clone()
		dummyTemplate:SetAttribute("ImmortalDummy", nil)  -- 복제본은 불사신 아님
		dummyTemplate.Parent = game:GetService("ServerStorage")
	end
end

-- Crim crown attach helper (runtime-adjustable via /crimsize /crimup /crimfwd)
local CRIM_DEF_SCALE = 1.3   -- absolute scale vs original 1.306 (tuned)
local CRIM_DEF_UP    = 1.7
local CRIM_DEF_FWD   = 0.0

local function attachCrimCrown(player)
	local char = player.Character
	if not char then return false, "no character" end
	local head = char:FindFirstChild("Head")
	if not head then return false, "no Head" end
	local old = char:FindFirstChild("CrimCrown")
	if old then old:Destroy() end
	local tmpl = ServerStorage:FindFirstChild("CrimCrownTemplate")
	if not tmpl then return false, "template missing" end
	local scale = player:GetAttribute("CrimScale") or CRIM_DEF_SCALE
	local up    = player:GetAttribute("CrimUp")    or CRIM_DEF_UP
	local fwd   = player:GetAttribute("CrimFwd")   or CRIM_DEF_FWD
	local mdl = tmpl:Clone()
	mdl.Name = "CrimCrown"
	mdl:ScaleTo(scale)
	local body = mdl.PrimaryPart or mdl:FindFirstChild("Handle1")
	for _, p in ipairs(mdl:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.Massless = true
			p.CastShadow = false
		end
	end
	local targetCF = head.CFrame * CFrame.new(0, up, -fwd)
	local bodyCF = body.CFrame
	for _, p in ipairs(mdl:GetDescendants()) do
		if p:IsA("BasePart") and p ~= body then
			p.CFrame = targetCF * bodyCF:ToObjectSpace(p.CFrame)
		end
	end
	body.CFrame = targetCF
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = body
	weld.Parent = body
	mdl.Parent = char
	print(string.format("[CrimTest] %s crown: scale=%.3f up=%.2f fwd=%.2f", player.Name, scale, up, fwd))
	return true
end
-- ── 채팅 명령어 ─────────────────────────────────────────────
-- 채팅 명령 연결.
--   ⚠️ PlayerAdded 만 쓰면 '이미 접속한 상태에서 스크립트가 재시작될 때'
--     이벤트가 오지 않아 명령이 통째로 안 먹는다(스튜디오 편집 중 흔함).
local function hookChat(player)
	player.Chatted:Connect(function(msg)
		if not isDev(player) then return end   -- 🔒 개발자만 (프로덕션 익스플로잇 차단)
		local lower = msg:lower()

		if lower == "/tagger" then
			player:SetAttribute("Role", "Tagger")
			-- ✅ 태거 캐릭터 파트에 TaggerCharacter 콜리전 그룹 적용
			--    (정식 라운드와 동일 — 자기 아이템에 부딪히지 않도록)
			local char = player.Character
			if char then
				for _, part in ipairs(char:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CollisionGroup = "TaggerCharacter"
					end
				end
			end
			print("🎯 [TEST]", player.Name, "→ Tagger 설정 (TaggerCharacter 그룹 적용)")

		elseif lower == "/runner" then
			player:SetAttribute("Role", "Runner")
			print("🏃 [TEST]", player.Name, "→ Runner 설정")

		elseif lower == "/norole" then
			player:SetAttribute("Role", nil)
			print("⬜ [TEST]", player.Name, "→ Role 초기화")

		elseif lower == "/killbots" or lower == "/kb" then
			-- ⚠️ [2026-09-08] /kb 축약 추가. 측정 중 반복 입력이라 짧은 쪽을 쓴다.
			--   원래 이름도 남긴다 — 기존 습관·문서(09-04 측정 절차)가 /killbots 를 쓴다.
			-- 🔬 [측정 2026-09-04] 농민봇 전원 제거 — 1대1 측정용.
			--   [왜] 2단계에서 러너가 킹에게 못 붙는 게 '봇 AI 한계'인지 '게임 구조'인지
			--     가르려면, 유저 러너 1명 vs 킹 1명만 남겨야 한다.
			--   ⚠️ 안전 근거: checkRunners()(RoundSystem:1326)는 AIRunner 를 승패 카운트에서
			--     제외한다. 그래서 봇을 전부 지워도 '러너 전멸 → 태거 승'으로 끝나지 않는다.
			--     단 전제가 있다 — 유저 러너가 최소 1명 살아 있어야 한다.
			--     네가 킹인 판에서 쓰면 유저 러너가 0명이라 즉시 라운드가 끝난다.
			--   ⚠️ Destroy 전에 다운 타이머를 취소한다. 안 그러면 10초 뒤 killDowned 가 돌아
			--     K측정의 s2Deaths 가 유령 증가한다(다운 없는 사망으로 집계돼 정합성 검증이 깨짐).
			local okDs, Ds = pcall(function()
				return require(game.ServerScriptService:WaitForChild("DownSystem", 2))
			end)
			local removed, wasDowned = 0, 0
			for _, m in ipairs(workspace:GetChildren()) do
				if m:IsA("Model") and m:GetAttribute("AIRunner") then
					if m:GetAttribute("Downed") then wasDowned += 1 end
					if okDs and Ds and Ds.cancelDeathTimer then
						pcall(Ds.cancelDeathTimer, m)
					end
					m:Destroy()
					removed += 1
				end
			end
			print(string.format("🧹 [TEST] 농민봇 %d체 제거 (다운 상태 %d) — 라운드는 계속된다",
				removed, wasDowned))

		elseif lower == "/sd" then
			-- Wood Shield 리필 (방패 FX 반복 테스트용)
			giveRunnerItem(player, "Wood Shield")
			print("🛡️ [TEST]", player.Name, "→ Wood Shield 지급")

		elseif lower == "/spawnfree" then
			-- 🧪 [TEST 2026-08-30] 라운드 밖에서도 아이템 소환 허용 (ItemSpawnHandler:590 가드 우회)
			--   ⚠️ 릴리즈 전 이 분기와 ItemSpawnHandler 의 AllowSpawnOffRound 조건을 함께 삭제할 것.
			--   ⚠️ 켜는 코드에 끄는 코드를 같이 — 토글이라 한 번 더 치면 꺼진다.
			_G.AllowSpawnOffRound = not _G.AllowSpawnOffRound
			print(string.format("🧪 [TEST] 라운드 밖 소환 %s",
				_G.AllowSpawnOffRound and "허용 (다시 /spawnfree 로 해제)" or "차단(기본값)"))

		elseif lower == "/pv" then
			-- 임팩트 버스트 미리보기: 앞 6stud에 실제 인게임과 동일(서버 Rate 0.18초 켜기)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				print("[/pv] 캐릭터 없음")
			else
				local IMG = "rbxassetid://109080603319948"
				local sizeStuds = 12
				print("[/pv] 임팩트 버스트 미리보기: 앞 6stud")
				local holder = Instance.new("Part")
				holder.Size = Vector3.new(0.2, 0.2, 0.2)
				holder.Transparency = 1
				holder.Anchored = true
				holder.CanCollide = false
				holder.CanQuery = false
				holder.CFrame = hrp.CFrame * CFrame.new(0, 1, -6)
				holder.Parent = workspace
				local att = Instance.new("Attachment")
				att.Parent = holder
				local pe = Instance.new("ParticleEmitter")
				pe.Texture = IMG
				pe.Rate = 14
				pe.Enabled = true
				pe.Lifetime = NumberRange.new(0.30)
				pe.Speed = NumberRange.new(0)
				pe.LightEmission = 0
				pe.LightInfluence = 0
				pe.Color = ColorSequence.new(Color3.new(1, 1, 1))
				pe.Rotation = NumberRange.new(-180, 180)
				pe.RotSpeed = NumberRange.new(-50, 50)
				pe.ZOffset = 2
				pe.Size = NumberSequence.new({
					NumberSequenceKeypoint.new(0,    sizeStuds * 0.55),
					NumberSequenceKeypoint.new(0.18, sizeStuds * 1.08),
					NumberSequenceKeypoint.new(1,    sizeStuds * 0.95),
				})
				pe.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0,    0),
					NumberSequenceKeypoint.new(0.55, 0.1),
					NumberSequenceKeypoint.new(1,    1),
				})
				pe.Parent = att
				task.delay(0.18, function() if pe and pe.Parent then pe.Enabled = false end end)
				game:GetService("Debris"):AddItem(holder, 1.2)
			end

		elseif lower == "/all" then
			-- /itemtest + /tagger + 봇 출발을 한 번에 실행
			-- 순서: ① itemtest로 환경/아이템 세팅 → ② tagger로 역할·콜리전 전환 → ③ 봇 출발
			print("🎬 [ALL] /itemtest + /tagger + /start 통합 실행:", player.Name)

			-- ① /itemtest 동작
			player:SetAttribute("Role", "Runner")
			if _G.PauseRound then _G.PauseRound() end
			local char0 = player.Character
			if char0 then
				local hrp = char0:FindFirstChild("HumanoidRootPart")
				if hrp then hrp.CFrame = CFrame.new(TEST_POS + Vector3.new(0, 5, 0)) end
			end
			task.delay(0.3, function()
				giveRunnerItem(player, "Wood Shield")
				giveRunnerItem(player, "RevivalFlag")
				giveRunnerItem(player, "Gas Grenade")
				giveRunnerItem(player, "ODM Gear")
				giveRunnerItem(player, "Ice Bow")
				giveRunnerItem(player, "Mic Bomb")
				giveRunnerItem(player, "Decoy Wand")
			end)
			task.delay(0.5, function() spawnDownedNoobNear(player) end)
			task.delay(0.5, function()
				local noob2 = workspace:FindFirstChild("Noob2")
				if noob2 and _G.setupNpcRunnerVisuals then
					_G.setupNpcRunnerVisuals(noob2)
				end
			end)

			-- ② /tagger 동작 (itemtest 세팅 끝난 뒤 역할/콜리전 덮어쓰기)
			task.delay(0.7, function()
				player:SetAttribute("Role", "Tagger")
				local char = player.Character
				if char then
					for _, part in ipairs(char:GetDescendants()) do
						if part:IsA("BasePart") then
							part.CollisionGroup = "TaggerCharacter"
						end
					end
				end
				print("🎯 [ALL] Tagger 설정 + TaggerCharacter 그룹 적용")
			end)

			-- ③ 봇 출발 (역할 전환 후)
			task.delay(0.9, function()
				if _G.startRunnerBots then
					_G.startRunnerBots()
					print("🚦 [ALL] 러너봇 출발")
				else
					warn("⚠️ [ALL] _G.startRunnerBots 없음 — 컨트롤러 미로드?")
				end
			end)

		elseif lower == "/itemtest" then
			-- 1. 러너 역할 부여
			player:SetAttribute("Role", "Runner")

			-- 2. 라운드 일시정지
			if _G.PauseRound then _G.PauseRound() end

			-- 3. map1 (Hill 근처)로 텔레포트
			local char = player.Character
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.CFrame = CFrame.new(TEST_POS + Vector3.new(0, 5, 0))
				end
			end

			-- 4. 테스트용 아이템 지급 (Wood Shield + RevivalFlag + Gas Grenade + ODM Gear + Ice Bow + Mic Bomb + Decoy Wand)
			task.delay(0.3, function()
				giveRunnerItem(player, "Wood Shield")
				giveRunnerItem(player, "RevivalFlag")
				giveRunnerItem(player, "Gas Grenade")
				giveRunnerItem(player, "ODM Gear")
				giveRunnerItem(player, "Ice Bow")
				giveRunnerItem(player, "Mic Bomb")
				giveRunnerItem(player, "Decoy Wand")
			end)

			-- 5. Noob을 옆에 다운 상태로 소환 (부활 깃발 테스트용)
			task.delay(0.5, function()
				spawnDownedNoobNear(player)
			end)

			-- 6. Noob2 더미에 러너 비주얼 켜기 (라운드 시작 안 하니까 RoundSystem이 자동으로 못 함)
			task.delay(0.5, function()
				local noob2 = workspace:FindFirstChild("Noob2")
				if noob2 and _G.setupNpcRunnerVisuals then
					_G.setupNpcRunnerVisuals(noob2)
					print("🔆 [ItemTest] Noob2 러너 비주얼 활성화 (profile/beam/highlight)")
				end
			end)

			print("🧪 [ItemTest]", player.Name,
				"→ map1 이동 + Wood Shield/부활깃발/가스수류탄 지급 + Noob 다운 소환 + 라운드 정지")

		elseif lower == "/itemtestoff" then
			if _G.ResumeRound then _G.ResumeRound() end
			print("▶️ [ItemTest]", player.Name, "→ 라운드 재개")

		elseif lower == "/odds" then
			-- [검증] 네 박스의 실제 확률 출력. 추첨과 동일한 풀을 쓰므로 이 값이 곧 실제 확률.
			local function dump(label, o)
				if not o then print("  " .. label .. " : 함수 없음(nil)") return end
				if o.each then
					print(string.format("  [%s] 미보유 풀 %d개 · 개별 %.4f%%", label, o.total, o.each))
				else
					print(string.format("  [%s] 미보유 풀 %d개 · 개별 가변(가중 추첨)", label, o.total))
				end
				if o.total == 0 then print("     (전부 보유 → 코인 폴백 구간)") return end
				local sum = 0
				for r, v in pairs(o.byRarity) do
					print(string.format("     %-10s %3d개  %6.2f%%", r, v.count, v.chance))
					sum = sum + v.chance
				end
				if o.byKind then
					for k, v in pairs(o.byKind) do
						print(string.format("      ·%-9s %3d개  %6.2f%%", k, v.count, v.chance))
					end
				end
				if o.byCategory then
					for c, v in pairs(o.byCategory) do
						print(string.format("      ·%-9s %3d개  %6.2f%%", c, v.count, v.chance))
					end
				end
				print(string.format("     등급 합계 %.2f%%  (100.00 이어야 정상)", sum))
			end
			print("═══ 박스 확률 검증 :", player.Name, "═══")
			dump("Basic(common)", _G.getBoxOdds and _G.getBoxOdds(player, "common"))
			dump("Rare+(plus)",   _G.getBoxOdds and _G.getBoxOdds(player, "plus"))
			dump("Epic+(mega)",   _G.getBoxOdds and _G.getBoxOdds(player, "mega"))
			dump("Cosmetic",      _G.getCosmeticOdds and _G.getCosmeticOdds(player, nil))
			-- 신규 계정 기준(보유 0). buildPool이 player:GetAttribute만 쓰므로 더미로 대체 가능.
			local fresh = { GetAttribute = function() return nil end }
			print("───── 신규 계정 기준 (보유 0) ─────")
			dump("Basic(common)", _G.getBoxOdds and _G.getBoxOdds(fresh, "common"))
			dump("Rare+(plus)",   _G.getBoxOdds and _G.getBoxOdds(fresh, "plus"))
			dump("Epic+(mega)",   _G.getBoxOdds and _G.getBoxOdds(fresh, "mega"))
			dump("Cosmetic",      _G.getCosmeticOdds and _G.getCosmeticOdds(fresh, nil))
			print("═══════════════════════════════════")

		elseif lower == "/ktune" then
			-- [튜닝] workspace._KatanaTune 에서 맞춘 위치 → swapOffset/swapRot 값 산출
			local f = workspace:FindFirstChild("_KatanaTune")
			local ref = f and f:FindFirstChild("REF_Handle")
			local sk = f and f:FindFirstChild("TUNE_LegendKatana")
			local grip = sk and sk:FindFirstChild("_Grip")
			if not (ref and grip) then
				print("⚠️ [ktune] _KatanaTune / REF_Handle / _Grip 없음")
			else
				local rel = ref.CFrame:ToObjectSpace(grip.CFrame)
				local rx, ry, rz = rel:ToOrientation()
				print("═══ [ktune] SkinManager LegendKatana 에 넣을 값 ═══")
				print(string.format("  swapOffset = {%.4f, %.4f, %.4f}", rel.X, rel.Y, rel.Z))
				print(string.format("  swapRot    = {%.2f, %.2f, %.2f}",
					math.deg(rx), math.deg(ry), math.deg(rz)))
				print("═══════════════════════════════════════════")
			end

		elseif lower == "/accapply" then
			-- [튜닝] workspace._AccentTune.EDIT_Accent 의 위치/크기를 원본 모델에 반영
			local f = workspace:FindFirstChild("_AccentTune")
			local edit = f and f:FindFirstChild("EDIT_Accent")
			local refG = f and f:FindFirstChild("REF__Grip")
			local m = game:GetService("ServerStorage").WeaponSkins:FindFirstChild("LegendKatana")
			local acc = m and m:FindFirstChild("Accent")
			if not (edit and refG and acc and m.PrimaryPart) then
				print("⚠️ [accapply] _AccentTune / EDIT_Accent / REF__Grip / Accent 확인 필요")
			else
				local rel = refG.CFrame:ToObjectSpace(edit.CFrame)
				acc.Size = edit.Size
				acc.CFrame = m.PrimaryPart.CFrame * rel
				print("✅ [accapply] 반영 완료")
				print(string.format("   Size = %s", tostring(acc.Size)))
				print(string.format("   그립기준 pos = (%.4f, %.4f, %.4f)", rel.X, rel.Y, rel.Z))
				local rx, ry, rz = rel:ToOrientation()
				print(string.format("   그립기준 rot = (%.1f, %.1f, %.1f)", math.deg(rx), math.deg(ry), math.deg(rz)))
				print("   ⚠ Ctrl+S 해야 유지됨")
			end
		elseif lower == "/ps" or lower == "/ps off" then
			-- [테스트] 태거 더미가 2초마다 푸시툴로 밀치는 상황을 반복 재현.
			-- 실제 푸시툴을 휘두르지 않고 PushTool.Server 와 동일 경로
			-- (_G.katanaCounters[victimChar]) 를 호출한다. 카운터 자세(1.5s)가
			-- 짧아 수동 타이밍이 어려우므로 반복 방식으로 검증.
			_G._PsLoop = _G._PsLoop or {}
			local uid = player.UserId
			if lower == "/ps off" or _G._PsLoop[uid] then
				_G._PsLoop[uid] = nil
				print("⏹️ [ps] 반복 푸시 중지")
			else
				_G._PsLoop[uid] = true
				print("▶️ [ps] 2초마다 푸시 시작 — 다시 /ps 로 중지")
				task.spawn(function()
					while _G._PsLoop[uid] do
						local char = player.Character
						local dummy = workspace:FindFirstChild("taggerdummy")
						if char and dummy then
							local hrp = char:FindFirstChild("HumanoidRootPart")
							local droot = dummy:FindFirstChild("HumanoidRootPart")
							if hrp and droot then
								droot.CFrame = hrp.CFrame * CFrame.new(0, 0, -6)
							end
							local fn = _G.katanaCounters and _G.katanaCounters[char]
							if fn then
								local ok, countered = pcall(fn, dummy)
								if ok and countered then
									print("⚔️ [ps] 카운터 성공 — 참격 발동")
								end
							end
						end
						task.wait(2)
					end
				end)
			end

		elseif lower == "/dgview" then
			-- 드래곤 관찰용: 지정 위치로 TP + 라운드 정지 (재개는 /itemtestoff)
			if _G.PauseRound then _G.PauseRound() end
			local char = player.Character
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.CFrame = CFrame.new(-185, -4.5, 894)
				end
			end
			print("[DGView]", player.Name, "→ TP(-185,-4.5,894) + 라운드 정지 (재개: /itemtestoff)")

		elseif lower == "/robux" then
			-- 임시: Robux 상점 열기 (클라 RobuxStoreClient가 속성 변화 감지)
			player:SetAttribute("_OpenRobuxStore", tick())
			print("[Robux]", player.Name, "→ Robux 상점 열기 신호")

		elseif lower == "/pass" then
			-- 임시: 배틀패스 열기 (클라 BattlePassClient가 속성 변화 감지)
			player:SetAttribute("_OpenBattlePass", tick())
			print("[Pass]", player.Name, "→ 배틀패스 열기 신호")

		elseif lower == "/skinbox" or lower:match("^/skinbox ") then
			-- 임시: 스킨 박스 개봉 (등급 옵션: /skinbox [common|plus|mega], 없으면 균등)
			local grade = msg:match("^/skinbox%s+(%a+)")   -- nil이면 균등(하위호환)
			local skinResult = _G.grantRandomSkin and _G.grantRandomSkin(player, grade) or nil
			local ev = game:GetService("ReplicatedStorage"):FindFirstChild("RareSkinReward")
			if skinResult and ev then
				skinResult.fromBox = true
				ev:FireClient(player, skinResult)
				print("[SkinBox]", player.Name, "grade="..tostring(grade or "uniform"), "→", tostring(skinResult.display), "("..tostring(skinResult.rarity)..")")
			elseif ev then
				print("[SkinBox]", player.Name, "grade="..tostring(grade or "uniform"), "→ 허용 등급 스킨 전부 보유(폴백, 컷신 없음)")
			else
				warn("[SkinBox] RareSkinReward 또는 _G.grantRandomSkin 없음")
			end

		elseif lower == "/cosmeticbox" then
			-- 코스메틱 박스 테스트 개봉 (킬/트레일/대시/크라운 랜덤)
			if _G.grantCosmeticBox then
				_G.grantCosmeticBox(player, 100)
				print("[CosmeticBox]", player.Name, "→ 개봉")
			else
				warn("[CosmeticBox] _G.grantCosmeticBox 없음")
			end

		elseif lower == "/trail" or lower:match("^/trail ") then
			-- test: equip a trail skin instantly, e.g. /trail Watermelon. no arg / off / none clears it. skinKey is case-sensitive.
			local key = msg:match("^/trail%s+(%S+)")
			if not key or key:lower() == "off" or key:lower() == "none" then
				player:SetAttribute("TrailSkin", "")
				print("[Trail]", player.Name, "-> cleared")
			else
				player:SetAttribute("TrailSkin", key)
				print("[Trail]", player.Name, "-> TrailSkin="..key)
			end

		elseif lower == "/dash" or lower:match("^/dash ") then
			-- test: equip a dash skin instantly, e.g. /dash Watermelon. no arg / off / none = default. skinId is case-sensitive.
			local key = msg:match("^/dash%s+(%S+)")
			if not key or key:lower() == "off" or key:lower() == "none" then
				player:SetAttribute("DashSkin", "")
				print("[Dash]", player.Name, "-> default")
			else
				player:SetAttribute("DashSkin", key)
				print("[Dash]", player.Name, "-> DashSkin="..key)
			end

		elseif lower == "/wm" or lower:match("^/wm ") then
			-- live-tune the watermelon push skin (LocalOffset/LocalRot/Scale) + re-apply instantly.
			--   /wm x 0.2 | y -0.1 | z 0.3   = position add (studs, cumulative)
			--   /wm rx 15 | ry 90 | rz -30   = rotation add (degrees, cumulative)
			--   /wm s 3.5                     = set scale
			--   /wm dump                      = print current values | /wm reset = zero offset+rot
			local SS = game:GetService("ServerStorage")
			local tpl = SS:FindFirstChild("WatermelonSliceVFX")
			if not tpl then
				print("[wm] no WatermelonSliceVFX template")
			else
				local field, val = msg:match("^/wm%s+(%a+)%s*([%-%+%d%.]*)")
				local off = tpl:GetAttribute("LocalOffset") or Vector3.new(0, 0, 0)
				local rot = tpl:GetAttribute("LocalRot") or Vector3.new(0, 0, 0)
				local scale = tpl:GetAttribute("Scale") or 1
				local num = tonumber(val)
				local ok = true
				if field == "dump" then
					print(string.format("[wm] LocalOffset=(%.3f, %.3f, %.3f)  LocalRot=(%.1f, %.1f, %.1f)  Scale=%.3f",
						off.X, off.Y, off.Z, rot.X, rot.Y, rot.Z, scale))
					ok = false
				elseif field == "reset" then
					off = Vector3.new(0, 0, 0); rot = Vector3.new(0, 0, 0)
				elseif num then
					if     field == "x"  then off = off + Vector3.new(num, 0, 0)
					elseif field == "y"  then off = off + Vector3.new(0, num, 0)
					elseif field == "z"  then off = off + Vector3.new(0, 0, num)
					elseif field == "rx" then rot = rot + Vector3.new(num, 0, 0)
					elseif field == "ry" then rot = rot + Vector3.new(0, num, 0)
					elseif field == "rz" then rot = rot + Vector3.new(0, 0, num)
					elseif field == "s"  then scale = num
					else print("[wm] unknown field: "..tostring(field)); ok = false end
				else
					print("[wm] usage: /wm x|y|z|rx|ry|rz <n> | s <n> | dump | reset"); ok = false
				end
				if ok then
					tpl:SetAttribute("LocalOffset", off)
					tpl:SetAttribute("LocalRot", rot)
					tpl:SetAttribute("Scale", scale)
					local char = player.Character
					local pt = (char and char:FindFirstChild("PushTool")) or (player.Backpack and player.Backpack:FindFirstChild("PushTool"))
					local handle = pt and pt:FindFirstChild("Handle")
					if handle then
						local oldv = handle:FindFirstChild("WatermelonSliceVFX")
						if oldv then oldv:Destroy() end
						tpl:Clone().Parent = handle
						print(string.format("[wm] applied off=(%.2f,%.2f,%.2f) rot=(%.0f,%.0f,%.0f) s=%.2f",
							off.X, off.Y, off.Z, rot.X, rot.Y, rot.Z, scale))
					else
						print("[wm] values saved, but no equipped PushTool Handle to preview (equip it first)")
					end
				end
			end

		elseif lower == "/give" or lower:match("^/give ") then
			-- test: give any RunnerItem tool by exact name, e.g. /give Coconut Juice
			local name = msg:match("^/give%s+(.+)")
			if name then
				name = name:gsub("%s+$", "")
				giveRunnerItem(player, name)
				print("[Give]", player.Name, "-> "..name)
			else
				print("[Give] usage: /give <RunnerItem name>")
			end

		elseif lower:match("^/pushskin") then
			-- test: give push tool with a specific skin applied by name, e.g. /pushskin WatermelonFist
			local RS = game:GetService("ReplicatedStorage")
			local tmpl = RS:FindFirstChild("PushTool")
			local char = player.Character
			local skinName = msg:match("^/pushskin%s+(%S+)")
			if tmpl and char and skinName then
				local old = player.Backpack:FindFirstChild("PushTool") or char:FindFirstChild("PushTool")
				if old then old:Destroy() end
				local tool = tmpl:Clone()
				local handle = tool:FindFirstChild("Handle")
				local skinData = _G.getSwordSkinData and _G.getSwordSkinData("PushTool", skinName)
				if skinData and handle then
					if skinData.material then handle.Material = Enum.Material[skinData.material] end
					if skinData.color then handle.Color = skinData.color end
					if skinData.vfxAttachment then
						local vfx = game:GetService("ServerStorage"):FindFirstChild(skinData.vfxAttachment)
						if vfx then
							local oldv = handle:FindFirstChild(skinData.vfxAttachment)
							if oldv then oldv:Destroy() end
							vfx:Clone().Parent = handle
						end
					end
				end
				tool.Parent = player.Backpack
				print("[PushSkin]", player.Name, "->", skinName)
			else
				print("[PushSkin] usage: /pushskin <skinName>")
			end

		elseif lower == "/potionskin" or lower:match("^/potionskin ") then
			-- test: equip a Speed Potion skin by name (or 'off'), then re-give the potion. e.g. /potionskin Coconut
			local skinName = msg:match("^/potionskin%s+(%S+)")
			if skinName and skinName:lower() == "off" then skinName = nil end
			if _G.setEquippedSkin then
				_G.setEquippedSkin(player, "Speed Potion", skinName)
				print("[PotionSkin]", player.Name, "-> Speed Potion:", tostring(skinName))
				local old = (player.Backpack and player.Backpack:FindFirstChild("Speed Potion"))
					or (player.Character and player.Character:FindFirstChild("Speed Potion"))
				if old then old:Destroy() end
				giveRunnerItem(player, "Speed Potion")
			else
				print("[PotionSkin] _G.setEquippedSkin missing")
			end

		elseif lower == "/cs" or lower:match("^/cs ") then
			-- test: give ClassicSword with a skin applied (default PoolNoodle). e.g. /cs | /cs RedSword | /cs off
			local SS = game:GetService("ServerStorage")
			local tmpl = SS.RunnerItem:FindFirstChild("ClassicSword")
			if not tmpl then
				print("[cs] no ServerStorage.RunnerItem.ClassicSword")
			else
				local skinName = msg:match("^/cs%s+(%S+)")
				if skinName == nil then skinName = "PoolNoodle" end
				if skinName:lower() == "off" or skinName:lower() == "none" then skinName = nil end
				local old = (player.Backpack and player.Backpack:FindFirstChild("ClassicSword"))
					or (player.Character and player.Character:FindFirstChild("ClassicSword"))
				if old then old:Destroy() end
				local tool = tmpl:Clone()
				local handle = tool:FindFirstChild("Handle")
				local skinData = skinName and _G.getSwordSkinData and _G.getSwordSkinData("ClassicSword", skinName)
				if skinData and handle and skinData.meshSwap then
					-- 모델 교체 스킨(Frozen Sword): Handle 투명화 + WeaponSkins 메시 용접(정렬값)
					handle.Transparency = 1
					local hmesh = handle:FindFirstChild("Mesh")
					if hmesh then hmesh.TextureId = "" end
					local skinMesh = SS:FindFirstChild("WeaponSkins")
					skinMesh = skinMesh and skinMesh:FindFirstChild(skinData.meshSwap)
					if skinMesh then
						local m = skinMesh:Clone()
						m.Name = "_SkinMesh"
						m.Anchored = false; m.CanCollide = false; m.Massless = true
						local sc = skinData.swapScale or 1
						m.Size = skinMesh.Size * sc
						local off = skinData.swapOffset or {0,0,0}
						local rot = skinData.swapRot or {0,0,0}
						local rel = CFrame.new(off[1], off[2], off[3])
							* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
						m.CFrame = handle.CFrame * rel
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = handle; weld.Part1 = m; weld.Parent = m
						m.Parent = handle
						if skinData.swingSnow then tool:SetAttribute("SwingSnow", true) end
					end
				elseif skinData and handle then
					if skinData.material then handle.Material = Enum.Material[skinData.material] end
					if skinData.color then
						local mesh = handle:FindFirstChild("Mesh")
						if mesh then mesh.TextureId = ""; mesh.VertexColor = Vector3.new(1, 1, 1) end
						handle.Color = skinData.color
					end
					if skinData.vfxAttachment then
						local vfx = SS:FindFirstChild(skinData.vfxAttachment)
						if vfx then
							local oldv = handle:FindFirstChild(skinData.vfxAttachment)
							if oldv then oldv:Destroy() end
							vfx:Clone().Parent = handle
						end
					end
				end
				tool.Parent = player.Backpack
				print("[cs]", player.Name, "-> ClassicSword skin:", tostring(skinName))
			end

		elseif lower == "/fs" or lower:match("^/fs ") then
			-- Frozen Sword 라이브 정렬 튜너: 들고 있는 ClassicSword의 _SkinMesh를 실시간 조정.
			--   /fs give              → 얼음검 지급(장착)
			--   /fs x|y|z <n>         → 오프셋 누적(스터드)
			--   /fs rx|ry|rz <n>      → 회전 누적(도)
			--   /fs s <n>             → 스케일 설정
			--   /fs dump | /fs reset  → 값 출력 | 초기화
			-- 조정 후 최종값을 SkinManager swapOffset/swapRot/swapScale에 박으면 됨.
			local SS = game:GetService("ServerStorage")
			local sub = msg:match("^/fs%s+(%S+)")
			if sub == "give" then
				local tmpl = SS.RunnerItem:FindFirstChild("ClassicSword")
				local old = (player.Backpack and player.Backpack:FindFirstChild("ClassicSword"))
					or (player.Character and player.Character:FindFirstChild("ClassicSword"))
				if old then old:Destroy() end
				local tool = tmpl:Clone()
				local handle = tool:FindFirstChild("Handle")
				local skinData = _G.getSwordSkinData and _G.getSwordSkinData("ClassicSword", "FrozenSword")
				if skinData and handle and skinData.meshSwap then
					handle.Transparency = 1
					local hmesh = handle:FindFirstChild("Mesh")
					if hmesh then hmesh.TextureId = "" end
					local skinMesh = SS:FindFirstChild("WeaponSkins")
					skinMesh = skinMesh and skinMesh:FindFirstChild(skinData.meshSwap)
					if skinMesh then
						local m = skinMesh:Clone()
						m.Name = "_SkinMesh"
						m.Anchored = false; m.CanCollide = false; m.Massless = true
						m.Size = skinMesh.Size * (skinData.swapScale or 1)
						local off = skinData.swapOffset or {0,0,0}
						local rot = skinData.swapRot or {0,0,0}
						m.CFrame = handle.CFrame * CFrame.new(off[1],off[2],off[3])
							* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = handle; weld.Part1 = m; weld.Parent = m
						m.Parent = handle
						-- 현재 튜닝값을 tool 속성에 저장(누적 조정 기준)
						tool:SetAttribute("FSoff", Vector3.new(off[1],off[2],off[3]))
						tool:SetAttribute("FSrot", Vector3.new(rot[1],rot[2],rot[3]))
						tool:SetAttribute("FSscale", skinData.swapScale or 1)
					end
				end
				tool.Parent = player.Backpack
				print("[fs] 얼음검 지급 — 장착 후 /fs x|y|z|rx|ry|rz|s 로 조정")
			else
				-- 들고 있는 ClassicSword + _SkinMesh 찾기
				local tool = (player.Character and player.Character:FindFirstChild("ClassicSword"))
					or (player.Backpack and player.Backpack:FindFirstChild("ClassicSword"))
				local handle = tool and tool:FindFirstChild("Handle")
				local mesh = handle and handle:FindFirstChild("_SkinMesh")
				if not mesh then
					print("[fs] _SkinMesh 없음 — 먼저 /fs give 로 지급하고 장착해")
				else
					local off = tool:GetAttribute("FSoff") or Vector3.new(0,0,0)
					local rot = tool:GetAttribute("FSrot") or Vector3.new(0,0,0)
					local scale = tool:GetAttribute("FSscale") or 1
					local field, val = msg:match("^/fs%s+(%a+)%s*([%-%+%d%.]*)")
					local num = tonumber(val)
					local ok = true
					if field == "dump" then
						print(string.format("[fs] swapOffset={%.3f, %.3f, %.3f}  swapRot={%.1f, %.1f, %.1f}  swapScale=%.4f",
							off.X, off.Y, off.Z, rot.X, rot.Y, rot.Z, scale))
						ok = false
					elseif field == "reset" then
						off = Vector3.new(0,0,0); rot = Vector3.new(0,0,0)
					elseif num then
						if     field == "x"  then off = off + Vector3.new(num,0,0)
						elseif field == "y"  then off = off + Vector3.new(0,num,0)
						elseif field == "z"  then off = off + Vector3.new(0,0,num)
						elseif field == "rx" then rot = rot + Vector3.new(num,0,0)
						elseif field == "ry" then rot = rot + Vector3.new(0,num,0)
						elseif field == "rz" then rot = rot + Vector3.new(0,0,num)
						elseif field == "s"  then scale = num
						else print("[fs] unknown: "..tostring(field)); ok = false end
					else
						print("[fs] usage: /fs give | x|y|z|rx|ry|rz <n> | s <n> | dump | reset"); ok = false
					end
					if ok then
						tool:SetAttribute("FSoff", off)
						tool:SetAttribute("FSrot", rot)
						tool:SetAttribute("FSscale", scale)
						-- 용접 제거 → CFrame 재설정 → 용접 재생성 (용접된 파트는 CFrame 직접수정 안 먹힘)
						for _, w in ipairs(mesh:GetChildren()) do
							if w:IsA("WeldConstraint") or w:IsA("Weld") or w:IsA("Motor6D") then w:Destroy() end
						end
						for _, w in ipairs(handle:GetChildren()) do
							if (w:IsA("WeldConstraint")) and (w.Part1 == mesh or w.Part0 == mesh) then w:Destroy() end
						end
						local skinMesh = SS:FindFirstChild("WeaponSkins")
						skinMesh = skinMesh and skinMesh:FindFirstChild("FrozenSword")
						if skinMesh then mesh.Size = skinMesh.Size * scale end
						mesh.CFrame = handle.CFrame * CFrame.new(off.X,off.Y,off.Z)
							* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = handle; weld.Part1 = mesh; weld.Parent = mesh
						print(string.format("[fs] off={%.2f,%.2f,%.2f} rot={%.0f,%.0f,%.0f} s=%.3f (용접 재생성)",
							off.X, off.Y, off.Z, rot.X, rot.Y, rot.Z, scale))
					end
				end
			end

		elseif lower == "/stune" or lower:match("^/stune ") then
			-- generic skin-template live tuner; re-applies to whatever tool currently wears it.
			--   /stune <Template> x|y|z|rx|ry|rz <n> | s <n> | dump | reset
			--   e.g. /stune PalmTreeVFX y 0.5 | /stune PalmTreeVFX s 0.12 | /stune PalmTreeVFX dump
			local SS = game:GetService("ServerStorage")
			local tname, field, val = msg:match("^/stune%s+(%S+)%s+(%a+)%s*([%-%+%d%.]*)")
			local tpl = tname and SS:FindFirstChild(tname)
			if not tpl then
				print("[stune] usage: /stune <TemplateName> x|y|z|rx|ry|rz <n> | s <n> | dump | reset")
			else
				local off = tpl:GetAttribute("LocalOffset") or Vector3.new(0, 0, 0)
				local rot = tpl:GetAttribute("LocalRot") or Vector3.new(0, 0, 0)
				local scale = tpl:GetAttribute("Scale") or 1
				local num = tonumber(val)
				local ok = true
				if field == "dump" then
					print(string.format("[stune] %s  LocalOffset=(%.3f, %.3f, %.3f)  LocalRot=(%.1f, %.1f, %.1f)  Scale=%.4f",
						tname, off.X, off.Y, off.Z, rot.X, rot.Y, rot.Z, scale))
					ok = false
				elseif field == "reset" then
					off = Vector3.new(0, 0, 0); rot = Vector3.new(0, 0, 0)
				elseif num then
					if     field == "x"  then off = off + Vector3.new(num, 0, 0)
					elseif field == "y"  then off = off + Vector3.new(0, num, 0)
					elseif field == "z"  then off = off + Vector3.new(0, 0, num)
					elseif field == "rx" then rot = rot + Vector3.new(num, 0, 0)
					elseif field == "ry" then rot = rot + Vector3.new(0, num, 0)
					elseif field == "rz" then rot = rot + Vector3.new(0, 0, num)
					elseif field == "s"  then scale = num
					else print("[stune] unknown field: "..tostring(field)); ok = false end
				else
					print("[stune] usage: /stune <TemplateName> x|y|z|rx|ry|rz <n> | s <n> | dump | reset"); ok = false
				end
				if ok then
					tpl:SetAttribute("LocalOffset", off)
					tpl:SetAttribute("LocalRot", rot)
					tpl:SetAttribute("Scale", scale)
					local applied = false
					local roots = {}
					if player.Character then roots[#roots+1] = player.Character end
					if player.Backpack then roots[#roots+1] = player.Backpack end
					for _, root in ipairs(roots) do
						for _, tool in ipairs(root:GetChildren()) do
							if tool:IsA("Tool") then
								local handle = tool:FindFirstChild("Handle")
								local worn = handle and handle:FindFirstChild(tname)
								if worn then
									worn:Destroy()
									tpl:Clone().Parent = handle
									applied = true
								end
							end
						end
					end
					print(string.format("[stune] %s off=(%.2f,%.2f,%.2f) rot=(%.0f,%.0f,%.0f) s=%.4f reapplied=%s",
						tname, off.X, off.Y, off.Z, rot.X, rot.Y, rot.Z, scale, tostring(applied)))
				end
			end

		elseif lower == "/bp" or lower:match("^/bp ") then
			-- battle pass XP test: /bp (status) | /bp <n> (add XP) | /bp round (round XP, tests cap)
			if not _G.BattlePass then
				print("[bp] _G.BattlePass missing")
			else
				local arg = msg:match("^/bp%s+(%S+)")
				if arg == nil then
					print(string.format("[bp] %s | XP=%d tier=%d/%d", player.Name,
						_G.BattlePass.getXP(player), _G.BattlePass.getTier(player), _G.BattlePass.MAX_TIER))
				elseif arg == "round" then
					_G.BattlePass.addXP(player, _G.BattlePass.ROUND_XP, "round")
				elseif arg == "prem" then
					local now = not (player:GetAttribute("BP_HasPremium") == true)
					player:SetAttribute("BP_HasPremium", now)
					print("[bp]", player.Name, "premium ->", now)
				elseif arg == "save" then
					if _G.BattlePass_save then _G.BattlePass_save(player); print("[bp] force-saved", player.Name)
					else print("[bp] _G.BattlePass_save missing") end
				else
					local n = tonumber(arg)
					if n then
						_G.BattlePass.addXP(player, n, "test")
					else
						print("[bp] usage: /bp | /bp <amount> | /bp round")
					end
				end
			end

		elseif lower == "/fxunlock" then
			local n = _G.UnlockAllKillEffects and _G.UnlockAllKillEffects(player) or 0
			print("[FXUnlock]", player.Name, "->", n, "kill effects unlocked")
		elseif lower == "/reply" then
			-- runnerdummy2 부활: 죽은 Humanoid는 Health만으론 복구 불가 → 신선한 복제본 리스폰
			if not dummyTemplate then
				print("[Reply] no template (runnerdummy2 missing at load?)")
			else
				local old = workspace:FindFirstChild("runnerdummy2")
				if old then old:Destroy() end
				local fresh = dummyTemplate:Clone()
				fresh.Name = "runnerdummy2"
				fresh:SetAttribute("ImmortalDummy", nil)
				if dummyHomeCF then fresh:PivotTo(dummyHomeCF) end
				fresh.Parent = workspace
				local hum = fresh:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.Health = hum.MaxHealth
					hum.WalkSpeed = 16
					hum.JumpPower = 50
				end
				print("[Reply] runnerdummy2 respawned (fresh) at home")
			end
		elseif lower == "/killfx" or lower:match("^/killfx ") then
			-- 임시: 킬 이펙트 시각 테스트 (/killfx rainbow) — 내 캐릭터 위치에 발동
			local fx = msg:match("^/killfx%s+(%a+)")
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local pos = hrp.Position
				if fx == "rainbow" and _G.SpawnRainbowEffect then
					_G.SpawnRainbowEffect(player, char, pos)
					print("[KillFX] rainbow @", tostring(pos))
				elseif fx == "sword" and _G.SpawnSwordRainEffect then
					_G.SpawnSwordRainEffect(player, char, pos)
					print("[KillFX] sword @", tostring(pos))
				elseif (fx == "hell" or fx == "hellfire") and _G.SpawnHellfireEffect then
					_G.SpawnHellfireEffect(player, char, pos)
					print("[KillFX] hellfire @", tostring(pos))
				elseif fx == "glitch" and _G.SpawnGlitchEffect then
					_G.SpawnGlitchEffect(player, char, pos)
					print("[KillFX] glitch @", tostring(pos))
					-- test-only: die after effect (~2.1s) -> natural respawn
					local hum = char:FindFirstChildOfClass("Humanoid")
					task.delay(2.3, function()
						if hum and hum.Parent and hum.Health > 0 then hum.Health = 0 end
					end)
				elseif (fx == "tornado" or fx == "tor") and _G.SpawnTornadoEffect then
					_G.SpawnTornadoEffect(player, char, pos)
					print("[KillFX] tornado @", tostring(pos))
					local hum = char:FindFirstChildOfClass("Humanoid")
					task.delay(1.1, function()
						if hum and hum.Parent and hum.Health > 0 then hum.Health = 0 end
					end)
				elseif fx == "portal" and _G.SpawnPortalEffect then
					_G.SpawnPortalEffect(player, char, pos)
					print("[KillFX] portal @", tostring(pos))
					local hum = char:FindFirstChildOfClass("Humanoid")
					task.delay(1.7, function()
						if hum and hum.Parent and hum.Health > 0 then hum.Health = 0 end
					end)
				elseif fx == "emp" and _G.SpawnEmpEffect then
					_G.SpawnEmpEffect(player, char, pos)
					print("[KillFX] emp @", tostring(pos))
				elseif fx == "grave" and _G.SpawnGraveEffect then
					_G.SpawnGraveEffect(player, char, pos)
					print("[KillFX] grave @", tostring(pos))
				elseif fx == "punch" and _G.SpawnPunchEffect then
					_G.SpawnPunchEffect(player, char, pos)
					print("[KillFX] punch @", tostring(pos))
					local hum = char:FindFirstChildOfClass("Humanoid")
					task.delay(1.9, function()
						if hum and hum.Parent and hum.Health > 0 then hum.Health = 0 end
					end)
				else
					print("[KillFX] 알수없거나 미구현:", tostring(fx))
				end
			else
				print("[KillFX] 캐릭터/HRP 없음")
			end

		elseif lower == "/map1" then
			-- map1 관찰용: ItemSpawnPlate 위치로 TP + 라운드 정지 (재개: /itemtestoff)
			if _G.PauseRound then _G.PauseRound() end
			local char = player.Character
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				local map1 = workspace:FindFirstChild("map1")
				local plate = map1 and map1:FindFirstChild("ItemSpawnPlate")
				if hrp and plate then
					hrp.CFrame = plate.CFrame + Vector3.new(0, 5, 0)  -- 플레이트 위
				end
			end
			print("[Map1]", player.Name, "→ ItemSpawnPlate TP + 라운드 정지 (재개: /itemtestoff)")

		elseif lower == "/map2" then
			-- map2 관찰용: ItemSpawnPlate2 위치로 TP + 라운드 정지 (재개: /itemtestoff)
			if _G.PauseRound then _G.PauseRound() end
			local char = player.Character
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				local map2 = workspace:FindFirstChild("map2")
				local plate = map2 and map2:FindFirstChild("ItemSpawnPlate2")
				if hrp and plate then
					hrp.CFrame = plate.CFrame + Vector3.new(0, 5, 0)  -- 플레이트 위
				end
			end
			print("[Map2]", player.Name, "→ ItemSpawnPlate2 TP + 라운드 정지 (재개: /itemtestoff)")

		elseif lower == "/diasword" then
			-- 다이아몬드 블레이드(콤보 검) 테스트: 손에 쥐여줌
			giveRunnerItem(player, "DiamondBladeSword")
			print("💎 [TEST]", player.Name, "→ DiamondBladeSword 지급 (콤보 검 테스트)")

		elseif lower == "/dragonfire" or lower == "/df" then
			-- 드래곤파이어(화상 + 스택6→폭발100 검) 테스트: 손에 쥐여줌
			giveRunnerItem(player, "DragonFireSword")
			print("🔥 [TEST]", player.Name, "→ DragonFireSword 지급 (화상+스택폭발 검)")

		elseif lower == "/sw" then
			-- 무기 테스트: 라운드 정지 + 태거 더미 옆으로 이동 + 손에 쥐여줌
			player:SetAttribute("Role", "Runner")
			if _G.PauseRound then _G.PauseRound() end

			-- 태거 더미 옆으로 텔레포트 (더미를 칠 수 있게)
			local char = player.Character
			local dummy = workspace:FindFirstChild("taggerdummy")
			if char and dummy then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				local dummyRoot = dummy:FindFirstChild("HumanoidRootPart")
				if hrp and dummyRoot then
					hrp.CFrame = dummyRoot.CFrame * CFrame.new(0, 0, 6)  -- 더미 앞 6 stud
				end
			end

			task.delay(0.3, function()
				-- 테스트 편의: Crimson Fang(Legendary) 자동 장착 후 지급.
				-- 보유 속성이 없으면 함께 부여(Studio 전용 테스트 경로).
				if not player:GetAttribute("Has_LegendKatana") then
					player:SetAttribute("Has_LegendKatana", true)
				end
				if _G.setEquippedSkin then
					_G.setEquippedSkin(player, "KatanaSword2", "LegendKatana")
					print("🎨 [TEST] Crimson Fang 자동 장착")
				end
				giveRunnerItem(player, "KatanaSword2")
			end)
			print("🗡️ [TEST]", player.Name, "→ KatanaSword2 지급 (라운드 정지 + 더미 옆 이동)")

		elseif lower == "/sakura" then
			-- 사쿠라 블레이드(가속 스택 검증용) 지급
			player:SetAttribute("Role", "Runner")
			if _G.PauseRound then _G.PauseRound() end

			local char = player.Character
			local dummy = workspace:FindFirstChild("taggerdummy")
			if char and dummy then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				local dummyRoot = dummy:FindFirstChild("HumanoidRootPart")
				if hrp and dummyRoot then
					hrp.CFrame = dummyRoot.CFrame * CFrame.new(0, 0, 6)
				end
			end

			task.delay(0.3, function()
				giveRunnerItem(player, "SakuraBlade")
			end)
			print("🌸 [TEST]", player.Name, "→ SakuraBlade 지급 (가속 스택 검증)")

		elseif lower == "/hammer" then
			-- 저급 망치(HammerLow) 지급 (일반 공격 + 스핀 슬래시 검증용)
			player:SetAttribute("Role", "Runner")
			if _G.PauseRound then _G.PauseRound() end

			local char = player.Character
			local dummy = workspace:FindFirstChild("taggerdummy")
			if char and dummy then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				local dummyRoot = dummy:FindFirstChild("HumanoidRootPart")
				if hrp and dummyRoot then
					hrp.CFrame = dummyRoot.CFrame * CFrame.new(0, 0, 6)
				end
			end

			task.delay(0.3, function()
				giveRunnerItem(player, "HammerLow")
			end)
			print("🔨 [TEST]", player.Name, "→ HammerLow 지급 (저급 망치 검증)")

		elseif lower:match("^/hammerskin") then
			-- 망치 스킨 장착 후 재지급. 예: /hammerskin DruidHammer  (또는 off)
			local skinName = msg:match("^/hammerskin%s+(%S+)")
			if _G.setEquippedSkin then
				_G.setEquippedSkin(player, "HammerLow", skinName)
				print("[HammerSkin]", player.Name, "-> HammerLow:", tostring(skinName))
				local old = (player.Backpack and player.Backpack:FindFirstChild("HammerLow"))
					or (player.Character and player.Character:FindFirstChild("HammerLow"))
				if old then old:Destroy() end
				giveRunnerItem(player, "HammerLow")
			else
				print("[HammerSkin] _G.setEquippedSkin 없음")
			end

		elseif lower == "/hammer2" then
			-- 고급 망치(HammerHigh) 지급 (일반 공격 + 차지-도약 슬램 검증용)
			player:SetAttribute("Role", "Runner")
			if _G.PauseRound then _G.PauseRound() end

			local char = player.Character
			local dummy = workspace:FindFirstChild("taggerdummy")
			if char and dummy then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				local dummyRoot = dummy:FindFirstChild("HumanoidRootPart")
				if hrp and dummyRoot then
					-- 슬램은 도약 거리가 있으니 더 멀리 배치(차지-도약 검증)
					hrp.CFrame = dummyRoot.CFrame * CFrame.new(0, 0, 40)
				end
			end

			task.delay(0.3, function()
				giveRunnerItem(player, "HammerHigh")
			end)
			print("🔨 [TEST]", player.Name, "→ HammerHigh 지급 (고급 망치 차지-슬램 검증)")

		elseif lower:sub(1, 8) == "/gcolor " then
			-- 건틀렛 컬러 커스텀 테스트: /gcolor <body|point|handle> <색이름>
			-- 예: /gcolor body white  →  플레이어 속성 저장. 건틀렛 다시 들면 적용됨.
			local zone, colorName = msg:match("^/gcolor%s+(%S+)%s+(%S+)")
			if zone and colorName then
				zone = zone:lower()
				colorName = colorName:lower()
				local zoneMap = { body = "Body", point = "Point", handle = "Handle" }
				local zoneKey = zoneMap[zone]
				local mod = game:GetService("ServerStorage"):FindFirstChild("GauntletColorPalette")
				local palette = mod and require(mod)
				if not zoneKey then
					print("🎨 [TEST] 부위는 body/point/handle 중 하나 (입력:", zone, ")")
				elseif not (palette and palette.isValidColor(colorName)) then
					print("🎨 [TEST] 색 이름 없음:", colorName, "(black/white/gray/navy/beige/orange/pink/red/cyan/purple/rainbow)")
				else
					player:SetAttribute("GauntletColor_" .. zoneKey, colorName)
					print(("🎨 [TEST] %s → %s = %s 저장됨 (건틀렛 다시 들면 적용)"):format(player.Name, zoneKey, colorName))
				end
			else
				print("🎨 [TEST] 형식: /gcolor <body|point|handle> <색이름>")
			end

		elseif lower == "/gunlock" then
			-- (테스트용) 건틀렛 유료색 전부 보유 처리 → 자물쇠 풀려 선택/APPLY 가능
			local paid = { "pink", "red", "cyan", "purple", "lime", "emerald", "yellow", "royal", "crimson", "rainbow", "gold", "silver", "bronze" }
			for _, c in ipairs(paid) do
				player:SetAttribute("Has_GColor_" .. c, true)
			end
			print("🎨 [TEST]", player.Name, "→ 건틀렛 유료색 전부 해금 (pink/red/cyan/purple/lime/emerald/yellow/royal/crimson/rainbow/gold/silver/bronze)")

		elseif lower == "/dashunlock" then
			-- (테스트용) 대시 색 스킨 전부 보유 처리 → 인벤에서 자물쇠 풀려 장착 가능
			local dashes = { "dash_default", "dash_red", "dash_violet", "dash_toxic", "dash_magenta", "dash_amber", "dash_cobalt", "dash_spectral", "dash_solar", "dash_ice", "dash_prism", "dash_vaporwave", "dash_shadow" }
			for _, d in ipairs(dashes) do
				player:SetAttribute("OwnedItem_" .. d, true)
			end
			print("💨 [TEST]", player.Name, "→ 대시 색 전부 해금 (default/red/violet/toxic/magenta/amber/cobalt/spectral/solar/prism/vaporwave/shadow)")

		elseif lower == "/trailunlock" then
			-- (테스트용) 트레일 스킨 전부 보유 처리 → 인벤에서 자물쇠 풀려 장착 가능
			local trails = { "trail_white", "trail_crimson", "trail_cyan", "trail_violet", "trail_toxic", "trail_amber", "trail_black", "trail_sunset", "trail_vaporwave", "trail_ocean", "trail_ice", "trail_shadow", "trail_rainbow", "trail_rainbowcycle" }
			for _, t in ipairs(trails) do
				player:SetAttribute("OwnedItem_" .. t, true)
			end
			print("✨ [TEST]", player.Name, "→ 트레일 스킨 전부 해금 (white/crimson/cyan/violet/toxic/amber/black/sunset/vaporwave/ocean/shadow/rainbow/rainbowcycle)")

		elseif lower == "/crownunlock" then
			-- (테스트용) 왕관 스킨 전부 보유 처리
			local crowns = { "crown_gold", "crown_crimson", "crown_cyan", "crown_emerald", "crown_amethyst", "crown_rose", "crown_royal", "crown_diamond", "crown_silver", "crown_black", "crown_white", "crown_rainbow", "crown_flower", "crown_money", "crown_darkrainbow", "crown_void", "crown_8bit", "crown_blackstar", "crown_angel", "crown_magenta_angel" }
			for _, c in ipairs(crowns) do
				player:SetAttribute("OwnedItem_" .. c, true)
			end
			print("👑 [TEST]", player.Name, "→ 왕관 스킨 전부 해금 (틴트12 + 모델8: flower/money/darkrainbow/void/8bit/blackstar/angel/magenta_angel)")

		elseif lower == "/emoteunlock" then
			-- (테스트용) 이미지 이모트 12종 전부 보유 처리 → 인벤 자물쇠 풀려 장착 가능
			local RS = game:GetService("ReplicatedStorage")
			local ok, EmoteData = pcall(require, RS:WaitForChild("EmoteData"))
			local n = 0
			if ok and type(EmoteData) == "table" then
				for _, e in ipairs(EmoteData) do
					player:SetAttribute("OwnedItem_" .. e.id, true)
					n += 1
				end
			end
			print("🎭 [TEST]", player.Name, "→ 이모트", n, "종 전부 해금")

		elseif lower == "/crownskin" then
			-- (테스트용) 다음 왕관 스킨으로 순환 + 즉시 적용(왕관 없으면 씌움)
			local order = { "Gold", "Crimson", "Cyan", "Emerald", "Amethyst", "Rose", "Royal", "Diamond", "Silver", "Black", "White", "Rainbow", "Flower", "Money", "DarkRainbow", "Void", "EightBit", "Blackstar", "Angel", "MagentaAngel" }
			local cur = player:GetAttribute("CrownSkin") or "Gold"
			local idx = 1
			for i, k in ipairs(order) do if k == cur then idx = i break end end
			local nextKey = order[(idx % #order) + 1]
			player:SetAttribute("CrownSkin", nextKey)
			if _G.attachCrownToTagger then
				_G.attachCrownToTagger(player)
			else
				print("❌ RoundSystem 로드 안 됨 (attachCrownToTagger 없음)")
			end
			print("👑 [CrownTest]", player.Name, "→ 왕관 스킨:", nextKey)

		elseif lower == "/crownmat" then
			-- (테스트용) 재질 변형 2종만 토글: Royal(Metal 금속) ↔ Diamond(Glass 유리)
			local cur = player:GetAttribute("CrownSkin")
			local nextKey = (cur == "Royal") and "Diamond" or "Royal"
			player:SetAttribute("CrownSkin", nextKey)
			if _G.attachCrownToTagger then
				_G.attachCrownToTagger(player)
			else
				print("❌ RoundSystem 로드 안 됨 (attachCrownToTagger 없음)")
			end
			print("💎 [CrownMat]", player.Name, "→ 재질 변형:", nextKey)

		elseif lower:match("^/cs%s+") then
			-- (테스트용) 왕관 스킨 바로 지정: /cs <이름> (예: /cs void, /cs 8bit, /cs magenta)
			local arg = lower:match("^/cs%s+(.+)$")
			arg = arg and arg:gsub("%s+", "")
			local alias = {
				gold="Gold", crimson="Crimson", cyan="Cyan", emerald="Emerald",
				amethyst="Amethyst", rose="Rose", royal="Royal", diamond="Diamond",
				silver="Silver", black="Black", white="White", rainbow="Rainbow",
				flower="Flower", money="Money", darkrainbow="DarkRainbow",
				void="Void", eightbit="EightBit", ["8bit"]="EightBit",
				blackstar="Blackstar", angel="Angel",
				magentaangel="MagentaAngel", magenta="MagentaAngel",
			}
			local key = arg and alias[arg]
			if key then
				player:SetAttribute("CrownSkin", key)
				-- 스킨 바꿀 때 넛지 리셋 (스킨마다 새로 튜닝)
				for _, a in ipairs({"CN_X","CN_Y","CN_Z","CN_S","CN_RX","CN_RY","CN_RZ","WN_X","WN_Y","WN_Z","WN_S","WN_RX","WN_RY","WN_RZ"}) do
					player:SetAttribute(a, nil)
				end
				if _G.attachCrownToTagger then _G.attachCrownToTagger(player) end
				print("👑 [CrownSet]", player.Name, "→", key, "(넛지 리셋됨)")
			else
				print("❓ [CrownSet] 알 수 없는 스킨:", tostring(arg), "| 예: /cs void  /cs 8bit  /cs angel  /cs magenta")
			end

		elseif lower:match("^/cn") then
			-- (테스트용) 머리 모델 크라운 넛지: /cn y +0.5 | z -0.3 | x 0.2 | s 1.5 | rx 90 | ry 90 | rz 45 | reset
			--   x/y/z = 오프셋 가감(누적), s = 스케일(절대), rx/ry/rz = 각 축 회전 각도(절대). 적용 후 [CrownDbg]에 최종값.
			local field, val = lower:match("^/cn%s+(%a+)%s*([%-%+%d%.]*)")
			if field == "reset" then
				for _, a in ipairs({"CN_X","CN_Y","CN_Z","CN_S","CN_RX","CN_RY","CN_RZ"}) do player:SetAttribute(a, nil) end
				print("🔧 [CN] 머리 넛지 리셋")
			elseif field then
				local n = tonumber(val)
				if field == "x" and n then player:SetAttribute("CN_X", (player:GetAttribute("CN_X") or 0) + n)
				elseif field == "y" and n then player:SetAttribute("CN_Y", (player:GetAttribute("CN_Y") or 0) + n)
				elseif field == "z" and n then player:SetAttribute("CN_Z", (player:GetAttribute("CN_Z") or 0) + n)
				elseif field == "s" and n then player:SetAttribute("CN_S", n)
				elseif field == "rx" and n then player:SetAttribute("CN_RX", n)
				elseif field == "ry" and n then player:SetAttribute("CN_RY", n)
				elseif field == "rz" and n then player:SetAttribute("CN_RZ", n)
				else print("❓ [CN] 사용: /cn y +0.5 | z -0.3 | x 0.2 | s 1.5 | rx 90 | ry 90 | rz 45 | reset") end
			end
			if _G.attachCrownToTagger then _G.attachCrownToTagger(player) end

		elseif lower:match("^/wn") then
			-- (테스트용) 엔젤 날개 넛지: /wn y +0.5 | z -0.3 | x 0.2 | s 1.5 | rx 90 | ry 90 | rz 45 | reset
			local field, val = lower:match("^/wn%s+(%a+)%s*([%-%+%d%.]*)")
			if field == "reset" then
				for _, a in ipairs({"WN_X","WN_Y","WN_Z","WN_S","WN_RX","WN_RY","WN_RZ"}) do player:SetAttribute(a, nil) end
				print("🔧 [WN] 날개 넛지 리셋")
			elseif field then
				local n = tonumber(val)
				if field == "x" and n then player:SetAttribute("WN_X", (player:GetAttribute("WN_X") or 0) + n)
				elseif field == "y" and n then player:SetAttribute("WN_Y", (player:GetAttribute("WN_Y") or 0) + n)
				elseif field == "z" and n then player:SetAttribute("WN_Z", (player:GetAttribute("WN_Z") or 0) + n)
				elseif field == "s" and n then player:SetAttribute("WN_S", n)
				elseif field == "rx" and n then player:SetAttribute("WN_RX", n)
				elseif field == "ry" and n then player:SetAttribute("WN_RY", n)
				elseif field == "rz" and n then player:SetAttribute("WN_RZ", n)
				else print("❓ [WN] 사용: /wn y +0.5 | z -0.3 | x 0.2 | s 1.5 | rx 90 | ry 90 | rz 45 | reset") end
			end
			if _G.attachCrownToTagger then _G.attachCrownToTagger(player) end

		elseif lower == "/crowndump" then
			-- (진단용) 캐릭터에 붙은 모든 액세서리/모델/크라운 파트를 머리 기준 ΔY·색·메시로 출력
			local char = player.Character
			if char then
				local head = char:FindFirstChild("Head")
				local hy = head and head.Position.Y
				print("===== CROWN DUMP ["..player.Name.."] CrownSkin="..tostring(player:GetAttribute("CrownSkin")).." =====")
				for _, c in ipairs(char:GetChildren()) do
					if c:IsA("Accessory") or c:IsA("Hat") or c:IsA("Model") or c.Name == "TaggerCrown" then
						print(("● [%s] %s"):format(c.ClassName, c.Name))
						for _, d in ipairs(c:GetDescendants()) do
							if d:IsA("BasePart") then
								local dy = hy and (d.Position.Y - hy) or 0
								local mesh = d:FindFirstChildWhichIsA("SpecialMesh")
								local mid = (d:IsA("MeshPart") and d.MeshId) or (mesh and mesh.MeshId) or "-"
								print(("    · %s  ΔY=%.2f  color=(%d,%d,%d)  mesh=%s"):format(
									d.Name, dy,
									math.floor(d.Color.R*255), math.floor(d.Color.G*255), math.floor(d.Color.B*255),
									tostring(mid)))
							end
						end
					end
				end
				print("===== END DUMP =====")
			end

		elseif lower == "/push" then
			-- (테스트용) 푸시툴 즉시 지급 + 장착 스킨 적용 (색놀이 테스트용)
			local RS = game:GetService("ReplicatedStorage")
			local tmpl = RS:FindFirstChild("PushTool")
			local char = player.Character
			if tmpl and char then
				local old = player.Backpack:FindFirstChild("PushTool") or char:FindFirstChild("PushTool")
				if old then old:Destroy() end
				local tool = tmpl:Clone()
				local applied = "기본(스킨없음)"
				if _G.getEquippedSkin and _G.getSwordSkinData then
					local skinName = _G.getEquippedSkin(player, "PushTool")
					local skinData = skinName and _G.getSwordSkinData("PushTool", skinName)
					local handle = tool:FindFirstChild("Handle")
					if skinData and handle then
						if skinData.meshSwap then
							handle.Transparency = 1
							for _, d in ipairs(handle:GetChildren()) do
								if d:IsA("BasePart") then d.Transparency = 1 end
							end
							local bank = game:GetService("ServerStorage"):FindFirstChild("WeaponSkins")
							local skinMesh = bank and bank:FindFirstChild(skinData.meshSwap)
							if skinMesh then
								local m = skinMesh:Clone()
								m.Name = "_SkinMesh"
								m.Anchored = false; m.CanCollide = false; m.Massless = true
								local sc = skinData.swapScale or 1
								m.Size = skinMesh.Size * sc
								local off = skinData.swapOffset or {0,0,0}
								local rot = skinData.swapRot or {0,0,0}
								local rel = CFrame.new(off[1], off[2], off[3])
									* CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
								m.CFrame = handle.CFrame * rel
								local weld = Instance.new("WeldConstraint")
								weld.Part0 = handle
								weld.Part1 = m
								weld.Parent = m
								m.Parent = handle
							end
							applied = tostring(skinName)
						elseif skinData.cycle then
							local rt = game:GetService("ServerStorage"):FindFirstChild("RainbowCycleTemplate")
							if rt then local cyc = rt:Clone(); cyc.Name = "RainbowCycle"; cyc.Disabled = false; cyc.Parent = handle end
						else
							if skinData.material then handle.Material = Enum.Material[skinData.material] end
							if skinData.color then handle.Color = skinData.color end
						end
						-- VFX 부착(블랙홀 등): ServerStorage 템플릿 Attachment 복제 → 항상 방출
						if skinData.vfxAttachment then
							local vfx = game:GetService("ServerStorage"):FindFirstChild(skinData.vfxAttachment)
							if vfx then
								local oldv = handle:FindFirstChild(skinData.vfxAttachment)
								if oldv then oldv:Destroy() end
								vfx:Clone().Parent = handle
							end
						end
						applied = tostring(skinName)
					elseif handle then
						-- _Custom: PushColor/PushMaterial 속성 있으면 Handle 색칠 (없으면 원본 글러브)
						local colorName = player:GetAttribute("PushColor_Fist")
						if colorName then
							local palette = require(RS:WaitForChild("NoobColorPalette"))
							if palette.COLORS[colorName] then
								local cfg = palette.getConfig("PushTool")
								local finishKey = player:GetAttribute("PushMaterial_Fist") or cfg.materialDefault
								palette.applyFinish(handle, finishKey, palette.COLORS[colorName])
								applied = "_Custom " .. colorName .. "/" .. finishKey
							end
						end
					end
				end
				tool.Parent = player.Backpack
				print("👊 [TEST] PushTool 지급 → 스킨:", applied)
			else
				print("❓ [TEST] PushTool 템플릿 또는 캐릭터 없음")
			end

		elseif lower:match("^/pg") then
			-- (테스트용) 푸시툴 Grip 라이브 조정 — 떠 있는 주먹을 오른손에 맞추기.
			--   /pg x 0.2 | y -0.5 | z 0.3   = 위치 가감(누적)
			--   /pg rx 15 | ry -30 | rz 45   = 로컬축 회전 가감(누적, 도)
			--   /pg dump = 현재 Grip 출력(베이크용) | /pg reset = 위치만 0으로(회전 유지)
			-- ⚠ 런타임 변경이라 정지하면 사라짐. 최종값은 dump 찍어서 Edit에서 베이크 + Ctrl+S.
			local RS = game:GetService("ReplicatedStorage")
			local tmpl = RS:FindFirstChild("PushTool")
			local field, val = lower:match("^/pg%s+(%a+)%s*([%-%+%d%.]*)")
			local function dumpGrip(tag)
				local g = tmpl.Grip
				local ex, ey, ez = g:ToEulerAnglesXYZ()
				print(string.format("%s GripPos=(%.2f, %.2f, %.2f) | euler°=(%.1f, %.1f, %.1f)",
					tag, g.X, g.Y, g.Z, math.deg(ex), math.deg(ey), math.deg(ez)))
				print("   CFrame =", tostring(g))
				local h = tmpl:FindFirstChild("Handle")
				if h then print(string.format("   Handle.Size = Vector3.new(%.3f, %.3f, %.3f)", h.Size.X, h.Size.Y, h.Size.Z)) end
			end
			if not tmpl then
				print("❓ [PG] ReplicatedStorage.PushTool 템플릿 없음")
			elseif field == "reset" then
				local rot = tmpl.Grip - tmpl.Grip.Position
				tmpl.Grip = CFrame.new(0, 0, 0) * rot
				local char = player.Character
				local live = (char and char:FindFirstChild("PushTool"))
					or (player:FindFirstChild("Backpack") and player.Backpack:FindFirstChild("PushTool"))
				if live then live.Grip = tmpl.Grip end
				dumpGrip("🔧 [PG] reset(위치0) →")
			elseif field == nil or field == "dump" then
				dumpGrip("📋 [PG]")
			else
				local n = tonumber(val)
				if field == "s" and n then
					-- 주먹 크기 배율(누적). Handle.Size를 n배 (라이브+템플릿). 키운 뒤 위치 재조정 필요할 수 있음.
					local function scaleHandle(t)
						local h = t and t:FindFirstChild("Handle")
						if h then h.Size = h.Size * n end
					end
					scaleHandle(tmpl)
					local char = player.Character
					local live = (char and char:FindFirstChild("PushTool"))
						or (player:FindFirstChild("Backpack") and player.Backpack:FindFirstChild("PushTool"))
					scaleHandle(live)
					dumpGrip(string.format("🔧 [PG] size×%.3f →", n))
				else
					local g = tmpl.Grip
					local pos = g.Position
					local rot = g - pos
					local ok = true
					if field == "x" and n then pos = pos + Vector3.new(n, 0, 0)
					elseif field == "y" and n then pos = pos + Vector3.new(0, n, 0)
					elseif field == "z" and n then pos = pos + Vector3.new(0, 0, n)
					elseif field == "rx" and n then rot = rot * CFrame.Angles(math.rad(n), 0, 0)
					elseif field == "ry" and n then rot = rot * CFrame.Angles(0, math.rad(n), 0)
					elseif field == "rz" and n then rot = rot * CFrame.Angles(0, 0, math.rad(n))
					else ok = false; print("❓ [PG] 사용: /pg x 0.2 | y -0.5 | z 0.3 | rx 15 | ry -30 | rz 45 | s 1.2 | dump | reset") end
					if ok then
						tmpl.Grip = CFrame.new(pos) * rot
						local char = player.Character
						local live = (char and char:FindFirstChild("PushTool"))
							or (player:FindFirstChild("Backpack") and player.Backpack:FindFirstChild("PushTool"))
						if live then live.Grip = tmpl.Grip end
						dumpGrip("🔧 [PG]")
					end
				end
			end

		elseif lower == "/gcustom" then
			-- 건틀렛 커스텀 화면 열기 (ViewportFrame 프리뷰 검증용)
			local pg = player:FindFirstChild("PlayerGui")
			local gui = pg and pg:FindFirstChild("GauntletCustomGui")
			if gui then
				gui.Enabled = true
				print("🎨 [TEST]", player.Name, "→ 건틀렛 커스텀 화면 열기")
			else
				print("🎨 [TEST] GauntletCustomGui 없음 (PlayerGui에 아직 복제 안 됨 — 새 F5 필요할 수 있음)")
			end

		elseif lower == "/skin" then
			-- 스킨 전시(_GauntletSkinTest) 앞으로 순간이동 + 라운드 멈춤 (색감/발광 확인용)
			if _G.PauseRound then _G.PauseRound() end
			local folder = workspace:FindFirstChild("_GauntletSkinTest")
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if folder and hrp then
				-- 전시 모델들 중 가운데쯤(index 기준 중앙)을 골라 그 앞에 세움 → 전체가 한눈에
				local models = {}
				for _, m in ipairs(folder:GetChildren()) do
					local idx = tonumber(m.Name:match("^Gauntlet_(%d+)_"))
					if idx and m.PrimaryPart then table.insert(models, {idx = idx, model = m}) end
				end
				table.sort(models, function(a, b) return a.idx < b.idx end)
				if #models > 0 then
					local mid = models[math.ceil(#models / 2)].model
					local pivot = mid:GetPivot()
					-- 전시 줄 정면에서 약간 떨어져 바라보게(전시가 X+ 방향 일렬이므로 -Z 쪽에서)
					hrp.CFrame = CFrame.new(pivot.Position + Vector3.new(0, 0, -10), pivot.Position)
					print("🎨 [TEST]", player.Name, "→ 스킨 전시 앞으로 순간이동 (전시", #models, "개)")
				else
					print("🎨 [TEST] 전시 모델 없음 (_GauntletSkinTest 비어있음)")
				end
			else
				print("🎨 [TEST] _GauntletSkinTest 폴더 없음 — 먼저 전시를 생성하세요")
			end

		elseif lower == "/g" then
			-- 건틀렛(Gauntlet) 지급 (오른손 장착 + 그립 확인용)
			player:SetAttribute("Role", "Runner")
			if _G.PauseRound then _G.PauseRound() end

			local char = player.Character
			local dummy = workspace:FindFirstChild("taggerdummy")
			if char and dummy then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				local dummyRoot = dummy:FindFirstChild("HumanoidRootPart")
				if hrp and dummyRoot then
					hrp.CFrame = dummyRoot.CFrame * CFrame.new(0, 0, 6)
				end
			end

			task.delay(0.3, function()
				giveRunnerItem(player, "Gauntlet")
			end)
			print("🥊 [TEST]", player.Name, "→ Gauntlet 지급 (오른손 장착 검증)")

		elseif lower:sub(1, 3) == "/w " or lower == "/w" then
			-- ⚔️ [2026-08-29] 실전 밸런스 측정용 무기 지급.
			--   [왜 새로 만드나] 기존 무기 커맨드(/g, /hammer2, /df ...)는 전부
			--     PauseRound + Role 강제 변경 + 더미 앞 순간이동을 한다. 그건 '그립·스킨이
			--     제대로 붙었나'를 보는 용도라 라운드를 멈추는 게 맞았다.
			--     지금 필요한 건 '실제 태거를 상대로 몇 초에 잡히나'라서 정반대다.
			--   [차이] 라운드 유지 · 역할 유지 · 위치 유지. 무기만 손에 쥐여준다.
			--   ⚠️ giveRunnerItem 을 그대로 쓴다. 스킨(메시 교체·색놀이) 처리가 그 안에 있어서,
			--     직접 Clone 하면 스킨이 빠진 채로 측정하게 된다.
			local WEAPON_ALIAS = {
				sw = "ClassicSword",      classic = "ClassicSword",
				ham = "HammerLow",        hammer  = "HammerLow",
				fh  = "HammerHigh",       flame   = "HammerHigh",
				df  = "DragonFireSword",  dragon  = "DragonFireSword",
				dia = "DiamondBladeSword",diamond = "DiamondBladeSword",
				sak = "SakuraBlade",      sakura  = "SakuraBlade",
				kat = "KatanaSword2",     katana  = "KatanaSword2",
				g   = "Gauntlet",         gauntlet= "Gauntlet",
			}
			local arg = lower:match("^/w%s+(%S+)")
			local target = arg and WEAPON_ALIAS[arg]
			if not target then
				local keys = {}
				for k in pairs(WEAPON_ALIAS) do keys[#keys+1] = k end
				table.sort(keys)
				print("⚔️ [TEST] /w <무기>  — 라운드 유지한 채 무기만 지급")
				print("   " .. table.concat(keys, " / "))
			else
				giveRunnerItem(player, target)
				print(string.format("⚔️ [TEST] %s → %s 지급 (라운드·역할·위치 유지)",
					player.Name, target))
			end

		elseif lower == "/shake" then
			-- 화면 흔들림 테스트 (본인 화면에 태거 강도로 흔들림 발사)
			local ev = game:GetService("ReplicatedStorage"):FindFirstChild("HammerShakeEvent")
			if ev then
				ev:FireClient(player, 2.2, 0.5)   -- 태거 흔들림과 동일 강도/지속
				print("📳 [TEST]", player.Name, "→ 화면 흔들림 발사 (강도 2.2 / 0.5초)")
			else
				warn("📳 [TEST] HammerShakeEvent 없음 — Ctrl+S 후 F5 새 세션 필요")
			end

		elseif lower == "/slash" then
			-- 참격 이펙트만 바로 그림 (카운터 로직 건너뜀, 비주얼 확인용).
			-- 플레이어가 든 카타나의 CounterRemote로 클라에 CounterSlash 신호 전송.
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				print("⚠️ [TEST] 캐릭터 없음")
			else
				-- 카타나 찾기 (손 또는 백팩)
				local katana = (char and char:FindFirstChild("KatanaSword2"))
					or (player.Backpack and player.Backpack:FindFirstChild("KatanaSword2"))
				if not katana then
					print("⚠️ [TEST] KatanaSword2 없음 — 먼저 /sw 로 지급하세요")
				else
					local remote = katana:FindFirstChild("CounterRemote")
					if not remote then
						print("⚠️ [TEST] CounterRemote 없음")
					else
						-- 플레이어 정면으로 from→to 두 점 (참격이 앞쪽에 그려짐)
						local fromPos = hrp.Position
						local toPos = hrp.Position + hrp.CFrame.LookVector * 12
						local skinColor = katana:GetAttribute("SkinColor")
						local isRainbow = katana:GetAttribute("RainbowSkin") == true
						remote:FireClient(player, "CounterSlash", fromPos, toPos, skinColor, isRainbow)
						print("⚔️ [TEST] 참격 출력 (skinColor=" .. tostring(skinColor) .. " rainbow=" .. tostring(isRainbow) .. ")")
					end
				end
			end

		elseif lower == "/push" then
			-- 태거 더미가 푸시툴을 계속 자동으로 휘두르게 (카타나 카운터 솔로 테스트용).
			-- 더미가 죽고 부활(_TaggerDummyRespawner가 새 모델로 교체)해도
			-- 감시 루프가 새 더미를 찾아 푸시툴을 자동 재장착 → 끊기지 않음.
			if _G.dummyAutoPush then
				-- 토글 해제
				_G.dummyAutoPush = false
				local d = workspace:FindFirstChild("taggerdummy")
				if d then
					d:SetAttribute("AutoPush", false)
					local pt = d:FindFirstChild("PushTool")
					if pt then pt:Destroy() end
				end
				print("🛑 [TEST] 더미 자동 푸시 중지")
			else
				_G.dummyAutoPush = true
				print("👊 [TEST] 더미 자동 푸시 시작 (다시 /push 로 중지)")
				task.spawn(function()
					while _G.dummyAutoPush do
						local d = workspace:FindFirstChild("taggerdummy")
						if d then
							local hum = d:FindFirstChildOfClass("Humanoid")
							-- 살아있고 푸시툴 없으면 재장착
							if hum and hum.Health > 0 and not d:FindFirstChild("PushTool") then
								d:SetAttribute("AutoPush", true)
								local tool = game:GetService("ReplicatedStorage").PushTool:Clone()
								tool.Parent = d
								hum:EquipTool(tool)
							end
						end
						task.wait(1)
					end
				end)
			end

		elseif lower == "/decoyhit" then
			-- 분신 소멸(태거 아이템 접촉) 솔로 테스트:
			-- 분신이 떠 있는 위치(러너 오른쪽 4 studs)에만 작은 TaggerItems 파트를 잠깐 띄운다.
			-- 본인(RunnerCharacter)과는 거리가 있어 안 맞고, 분신만 맞아 소멸한다.
			local char = player.Character
			local hrp  = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local pos = hrp.Position + hrp.CFrame.RightVector * 4
				local orb = Instance.new("Part")
				orb.Shape        = Enum.PartType.Ball
				orb.Size         = Vector3.new(2, 2, 2)
				orb.Anchored     = true
				orb.CanCollide   = true
				orb.CanTouch     = true
				orb.Color        = Color3.fromRGB(255, 60, 60)
				orb.Material     = Enum.Material.Neon
				orb.Transparency = 0.2
				orb.CFrame       = CFrame.new(pos)
				pcall(function() orb.CollisionGroup = "TaggerItems" end)
				orb.Parent = workspace  -- DescendantAdded → ItemDamageSystem이 Touched 연결
				game:GetService("Debris"):AddItem(orb, 2)
				print("🎯 [DecoyHit]", player.Name, "→ 분신 위치에 테스트 태거 파트 생성")
			end

		elseif lower == "/freeze" or lower:sub(1, 8) == "/freeze " then
			-- Ice Bow 명중 시 효과를 본인에게 시뮬레이션
			-- 사용법: /freeze (기본 3초) 또는 /freeze 5 (5초)
			local arg = lower:sub(9)
			local duration = tonumber(arg) or 3
			duration = math.clamp(duration, 0.2, 10)

			-- 화면 효과 (얼음 가장자리 + Blur)
			local fx = game:GetService("ReplicatedStorage"):FindFirstChild("TaggerFreezeEffect")
			if fx then
				fx:FireClient(player, duration)
			end

			-- Player Attribute로 태거 아이템 시스템 차단 (ItemSpawnHandler/Preview가 체크)
			player:SetAttribute("Frozen", true)

			-- WalkSpeed 슬로우 (16 → 12, -25%)
			local char = player.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			local oldWalkSpeed = nil
			if humanoid then
				oldWalkSpeed = humanoid.WalkSpeed
				humanoid.WalkSpeed = 12
			end

			-- 보너스: Tool 들고 있으면 봉인 시뮬레이션
			local backpack = player:FindFirstChild("Backpack")
			local frozen = {}
			local equipped = char and char:FindFirstChildOfClass("Tool")
			if equipped and equipped.Enabled then
				equipped.Enabled = false
				table.insert(frozen, equipped)
			end
			if backpack then
				for _, tool in ipairs(backpack:GetChildren()) do
					if tool:IsA("Tool") and tool.Enabled then
						tool.Enabled = false
						table.insert(frozen, tool)
					end
				end
			end
			task.delay(duration, function()
				player:SetAttribute("Frozen", nil)
				if humanoid and humanoid.Parent and oldWalkSpeed then
					humanoid.WalkSpeed = oldWalkSpeed
				end
				for _, tool in ipairs(frozen) do
					if tool and tool.Parent then tool.Enabled = true end
				end
			end)

			print("❄️ [FreezeTest]", player.Name, "→", duration, "초 freeze")

		elseif lower == "/tsunami" then
			-- 본인 위치에서 본인 LookVector 방향으로 쓰나미 발동 (테스트용)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				print("❌ /tsunami: 캐릭터 없음")
				return
			end
			if _G.fireTsunami then
				_G.fireTsunami(player, hrp.Position)
				print("🌊 [TsunamiTest]", player.Name, "발동")
			else
				print("❌ TsunamiSystem 로드 안 됨")
			end
		elseif lower:sub(1, 5) == "/bomb" then
			-- /bomb 또는 /bomb <거리> : 본인 정면 N stud 위치를 폭격 (기본 80)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				print("❌ /bomb: 캐릭터 없음")
				return
			end
			local distStr = lower:match("^/bomb%s+(%-?%d+)")
			local dist = tonumber(distStr) or 80
			local targetPos = hrp.Position + hrp.CFrame.LookVector * dist
			if _G.fireBombAt then
				_G.fireBombAt(player, targetPos)
				print(string.format("💣 [BombTest] %s | dist=%d | target=(%.0f, %.0f, %.0f)",
					player.Name, dist, targetPos.X, targetPos.Y, targetPos.Z))
			else
				print("❌ BombSystem 로드 안 됨")
			end
		elseif lower == "/toxreset" then
			if _G.resetToxBox then
				_G.resetToxBox()
				print("🧹 [ToxReset]", player.Name, "→ 모든 ToxBox 정리")
			else
				print("❌ ToxBoxSystem 로드 안 됨")
			end
		elseif lower == "/micbomb" then
			-- Mic Bomb 피격 효과를 본인에게 시뮬레이션 (마이크 던지기 단계 건너뜀)
			local char = player.Character
			if not char then
				print("❌ /micbomb: 캐릭터 없음")
				return
			end
			if _G.simulateMicBomb then
				_G.simulateMicBomb(char)
				print("🎤 [MicBombTest]", player.Name, "→ 콘서트 효과 발동")
			else
				print("❌ MicBombSystem 로드 안 됨")
			end
		elseif lower == "/blackhole" then
			-- 블랙홀 본인 앞 20 stud 지점에 즉시 활성화 (투척 단계 건너뜀)
			local char = player.Character
			if not char then
				print("❌ /blackhole: 캐릭터 없음")
				return
			end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			local targetPos = hrp.Position + hrp.CFrame.LookVector * 20
			if _G.activateBlackHole then
				_G.activateBlackHole(player, targetPos)
				print("🕳️ [BlackHoleTest]", player.Name, "→ 앞쪽 20 stud에 블랙홀 활성화")
			else
				print("❌ BlackHoleSystem 로드 안 됨")
			end
		elseif lower == "/blackholeme" then
			-- 본인이 피해자가 되는 체험 모드 (ownerId 면역 해제)
			local char = player.Character
			if not char then
				print("❌ /blackholeme: 캐릭터 없음")
				return
			end
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then return end
			-- 흡인 판정 범위 끝자락에서 소환 (살짝 안쪽이라 즉시 끌림 시작)
			local pullRadius = _G.BLACKHOLE_PULL_RADIUS or 100
			local spawnDist = pullRadius - 3
			local targetPos = hrp.Position + hrp.CFrame.LookVector * spawnDist
			if _G.activateBlackHole then
				-- player를 nil로 패스 → ownerId = 0 → 본인 면역 해제 (체험 모드)
				_G.activateBlackHole(nil, targetPos)
				print(string.format("🕳️ [BlackHoleMe] %s → 앞쪽 %d stud (판정 끝자락, 본인 면역 해제)", player.Name, spawnDist))
			else
				print("❌ BlackHoleSystem 로드 안 됨")
			end
		elseif lower == "/energyball" or lower == "/eb" then
			-- 본인 정면 방향으로 EnergyBall 발사 (마우스 클릭 시뮬레이션)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				print("❌ /energyball: 캐릭터 없음")
				return
			end
			if _G.fireEnergyBall then
				-- LookVector 방향 100 stud 지점을 클릭 위치로
				local clickPos = hrp.Position + hrp.CFrame.LookVector * 100
				_G.fireEnergyBall(player, clickPos)
				print(string.format("⚡ [EnergyBallTest] %s → forward 100 stud 발사", player.Name))
			else
				print("❌ EnergyBallSystem 로드 안 됨 (_G.fireEnergyBall nil)")
			end
		elseif lower == "/spear" or lower == "/sp" then
			-- 본인 정면 방향으로 Spear 투척 (마우스 클릭 시뮬레이션)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				print("❌ /spear: 캐릭터 없음")
				return
			end
			if _G.throwSpear then
				local clickPos = hrp.Position + hrp.CFrame.LookVector * 240
				_G.throwSpear(player, clickPos)
				print(string.format("🗡️ [SpearTest] %s → forward 240 stud 투척", player.Name))
			else
				print("❌ SpearSystem 로드 안 됨 (_G.throwSpear nil)")
			end
		elseif lower:match("^/atk") then
			-- 🧪 [TEST 2026-08-30] "나를 향해 쏜다" — 방패 원거리 차단 검증용.
			--   [왜 필요한가] 방패는 '맞는 러너'의 것을 조회한다(WoodShieldManager 원거리 API).
			--     태거가 되어 자기 방패에 쏘면 피격자가 없어 판정에 아예 안 걸린다.
			--     그래서 러너인 채로 공격이 나에게 날아오는 구성이 필요하다.
			--   [무엇을 하나] 내 +X 쪽 OFFSET 지점에서 나를 향해 아이템을 발사한다.
			--     러너는 -X → +X 로 전진하므로 +X 가 태거 방향이고, 방패도 그쪽을 본다.
			--   ⚠️ 아이템마다 발사 방식이 다르다:
			--     · tsunami — 좌표에서 태어나 -X 로 쓸고 온다. 시전자 불필요.
			--     · spear / energy — '시전자 캐릭터'에서 출발한다. 내가 쏘면 나에게서 나가므로
			--       발사 지점에 더미 시전자를 세워야 한다(아래 makeCaster).
			--   ⚠️ tsunami 는 피격 대상에서 태거를 제외하므로 반드시 /runner 상태여야 한다.
			--   ⚠️ 릴리즈 전 삭제할 것.
			local which = lower:match("^/atk%s+(%a+)") or "tsunami"
			-- 📏 발사 거리(선택). `/atk dragon 60` 처럼 뒤에 숫자를 붙인다.
			--   ⚠️ 기본 140 은 언덕 위(ItemSpawnPlate 근처)에서 쏘면 태거 베이스 안으로 들어가
			--     "🚫 태거 베이스 구역 소환 금지" 로 거부된다(실측 12:36 판). 그때 줄일 것.
			local OFFSET = tonumber(lower:match("^/atk%s+%a+%s+(%d+)")) or 140
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hrp then
				print("❌ /atk: 캐릭터 없음")
				return
			end
			if player:GetAttribute("Role") == "Tagger" then
				warn("⚠️ [/atk] 현재 Tagger 다. 방패 판정은 러너만 받는다 — /runner 로 바꾼 뒤 다시 시도할 것")
			end
			-- 🛡️ [2026-08-30] 태거 베이스 안이면 어떤 태거 아이템도 나를 못 때린다.
			--   [증상] 에너지볼이 그냥 통과하고 방패 판정이 호출조차 안 됐다(실측 12:40 판).
			--   [원인] ItemSpawnPlate 근처는 태거 베이스 구역이라 _G.IsCharInTaggerBase 가 true 다.
			--     그러면 EnergyBall·DemonSpear 등이 대상에서 통째로 제외한다(면역).
			--     같은 이유로 프드는 "🚫 태거 베이스 구역 소환 금지" 로 거부됐다.
			--   ⚠️ /map2 는 ItemSpawnPlate2 로 보내므로 바로 이 자리다. 언덕 아래로 내려가야 한다.
			if _G.IsCharInTaggerBase and _G.IsCharInTaggerBase(char) then
				warn("⚠️ [/atk] 지금 태거 베이스 구역 안이다 — 아이템 면역이라 아무것도 안 맞는다. 언덕 아래(-X)로 내려간 뒤 다시 시도할 것")
			end
			local from = hrp.Position + Vector3.new(OFFSET, 0, 0)

			-- 📏 [2026-08-30] 발사점이 태거 베이스면 자동으로 당긴다.
			--   [증상] /atk dragon 이 매번 "🚫 태거 베이스 구역 소환 금지" 로 거부됐다.
			--     내 위치는 멀쩡한데 +140 지점이 성 안이었다(실측 12:52 판, X=646 → 786).
			--   ⚠️ 거리를 명시로 준 경우(/atk dragon 60)는 존중한다 — 사용자가 의도한 값이다.
			if not lower:match("^/atk%s+%a+%s+%d+") then
				local function baseAt(pos)
					if not _G.IsCharInTaggerBase then return false end
					local pm = Instance.new("Model")
					local p = Instance.new("Part")
					p.Name = "HumanoidRootPart"; p.Anchored = true; p.CanCollide = false
					p.CanQuery = false; p.Transparency = 1; p.Size = Vector3.new(1,1,1)
					p.Position = pos; p.Parent = pm
					local r = _G.IsCharInTaggerBase(pm)
					pm:Destroy()
					return r
				end
				local tries = 0
				while baseAt(from) and OFFSET > 30 and tries < 10 do
					OFFSET -= 20
					from = hrp.Position + Vector3.new(OFFSET, 0, 0)
					tries += 1
				end
				if tries > 0 then
					warn(string.format("📏 [/atk] 발사점이 태거 베이스라 %d 까지 당겼다", OFFSET))
				end
			end

			-- 🔎 [진단 2026-08-30] 실행 시점의 관문 상태를 한 번에 찍는다.
			--   [왜] 방패 검증에서 관문이 넷이나 순차로 드러나 왕복이 길었다
			--     (라운드 가드 → 맵 판별 → 시전자 구조 → 베이스 면역).
			--     하나씩 추측으로 좁히는 대신 매번 전부 보여준다.
			--   ⚠️ 검증이 끝나면 이 블록과 /atk 전체를 함께 삭제할 것.
			do
				local L = {}
				L[#L+1] = string.format("── /atk 진단 ── (%s)", which)
				L[#L+1] = string.format("  역할        : %s", tostring(player:GetAttribute("Role")))
				L[#L+1] = string.format("  내 위치     : (%.0f, %.0f, %.0f)",
					hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
				L[#L+1] = string.format("  발사점      : (%.0f, %.0f, %.0f)  [X+%d]",
					from.X, from.Y, from.Z, OFFSET)
				L[#L+1] = string.format("  태거베이스  : 내위치=%s%s",
					tostring(_G.IsCharInTaggerBase and _G.IsCharInTaggerBase(char)),
					(_G.IsCharInTaggerBase and _G.IsCharInTaggerBase(char)) and "  ← 면역! 아무것도 안 맞는다" or "")
				-- ⚠️ [2026-08-30] 발사점도 따로 본다. 프드는 '소환 지점'이 베이스면 거부된다
				--   (실측 12:48 판 — 내 위치는 false 인데 발사점이 베이스라 막혔다).
				do
					local probe = Instance.new("Part")
					probe.Anchored = true; probe.CanCollide = false; probe.CanQuery = false
					probe.Transparency = 1; probe.Size = Vector3.new(1,1,1)
					probe.Name = "HumanoidRootPart"
					probe.Position = from
					local pm = Instance.new("Model"); probe.Parent = pm
					local inBase = _G.IsCharInTaggerBase and _G.IsCharInTaggerBase(pm)
					pm:Destroy()
					L[#L+1] = string.format("              발사점=%s%s", tostring(inBase),
						inBase and "  ← 프드 등 '소환형'은 여기서 거부된다. 거리를 줄일 것(/atk dragon 60)" or "")
				end
				L[#L+1] = string.format("  라운드 라이브: %s / spawnfree=%s",
					tostring(_G.IsRoundLive and _G.IsRoundLive()), tostring(_G.AllowSpawnOffRound))
				L[#L+1] = string.format("  차단 API    : %s",
					_G.WoodShieldBlocks and "있음" or "❌ 없음(WoodShieldManager 미로드)")
				-- 방패 상태
				local sd = _G.DebugShieldState and _G.DebugShieldState(player)
				if sd then
					L[#L+1] = string.format("  방패        : %s", sd)
				else
					L[#L+1] = "  방패        : ❌ 활성 방패 없음 (설치했는가? 이미 소모됐는가?)"
				end
				for _, line in ipairs(L) do warn(line) end
			end

			-- 🤖 가짜 시전자. 창·에너지볼은 '시전자 캐릭터'에서 출발점을 잡으므로
			--   내가 쏘면 나에게서 나간다(거리 0). 발사 지점에 더미를 세워 그걸 시전자로 넘긴다.
			--   ⚠️ TaggerBotSystem 의 pseudoPlayer 와 같은 수법 — 시스템들은 Role 을 안 보고
			--     .Character 와 좌표만 쓴다.
			--   ⚠️ 만들었으면 치운다. Debris 로 수명을 걸어 테스트가 쌓이지 않게 한다.
			local function makeCaster()
				-- 📐 [2026-08-30] 발사점의 실제 지면 높이를 찾아 그 위에 세운다.
				--   [증상] 에너지볼이 나를 그냥 지나갔다(판정 로그조차 없음, 실측 12:47 판).
				--   [원인] 더미를 내 Y 그대로 놓았는데, 발사점은 X+140 이라 언덕 경사상
				--     지면이 훨씬 높다. 더미가 지면에 파묻힌 채 발사돼 표면 추적이 어긋났다.
				--     (fireEnergyBall 은 startPos = hrp.Position - Y/2 로 발밑에서 쏜다)
				--   ⚠️ 위에서 아래로 쏴 지면을 찾는다. 못 찾으면 원래 Y 를 쓴다.
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { char }
				local hit = workspace:Raycast(from + Vector3.new(0, 300, 0), Vector3.new(0, -800, 0), rp)
				local spawnAt = hit and (hit.Position + Vector3.new(0, 3, 0)) or from

				local m = Instance.new("Model")
				m.Name = "_AtkCaster"
				local root = Instance.new("Part")
				root.Name = "HumanoidRootPart"
				root.Size = Vector3.new(2, 2, 1)
				root.Anchored = true
				root.CanCollide = false
				root.CanQuery = false
				root.Transparency = 1
				root.Position = spawnAt
				root.Parent = m
				m.PrimaryPart = root
				m.Parent = workspace
				game:GetService("Debris"):AddItem(m, 8)
				return {
					Name = "_ATK", UserId = -888, Character = m,
					-- ⚠️ 콜론 호출 대응(self 가 첫 인자). TaggerBotSystem.pseudoPlayer 와 같은 모양이어야 한다.
					--   [증상] 창이 "attempt to call missing method 'GetAttribute' of table" 로 터졌다
					--     (SpearSystem:130 이 player:GetAttribute 로 스킨 색을 읽는다).
					--   [원인] 평범한 테이블을 넘겨 메서드가 없었다. pseudoPlayer 는 이미 이걸 붙여뒀는데
					--     내가 그 모양을 따라하지 않았다.
					GetAttribute = function(_, n) if n == "Role" then return "Tagger" end return nil end,
					SetAttribute = function() end,
				}
			end

			local ok = true
			if which == "tsunami" or which == "ts" then
				-- 파도는 좌표에서 태어나 -X 로 쓸고 온다 → 시전자 불필요
				if _G.fireTsunami then _G.fireTsunami(player, from) else ok = false end
			elseif which == "spear" or which == "sp" then
				if _G.throwSpear then _G.throwSpear(makeCaster(), hrp.Position) else ok = false end
			elseif which == "energy" or which == "eb" or which == "energyball" then
				if _G.fireEnergyBall then _G.fireEnergyBall(makeCaster(), hrp.Position) else ok = false end
			elseif which == "demon" or which == "ds" then
				-- ⚠️ 데몬스피어도 '시전자 캐릭터'에서 출발한다 → 더미 시전자 필요.
				--   ⚠️ 직접 /ds 로 던지면 안 된다. 그러려면 내가 태거가 되어야 하는데,
				--     태거는 아이템의 피격 대상이 아니라 방패 판정에 들어가지도 못한다
				--     (실측 13:20 판 — 스택이 안 닳은 이유가 이것이었다).
				-- ⚠️ 목표는 '내 몸'도 '내 발밑'도 아니라 '내 조금 앞쪽 지면'이다.
				--   몸을 주면 창이 머리에 꽂히고, 발밑을 줘도 창이 나를 관통해야 도달하므로
				--   비행 판정이 나를 먼저 잡아 몸에 꽂힌다(실측 13:29 판).
				--   실전에서 태거는 멀리서 땅을 노리므로 관통 각이 잘 안 나온다 —
				--   테스트가 실전과 달라지면 안 되므로 조준점을 앞으로 뺀다.
				local aimGround = hrp.Position + Vector3.new(18, 0, 0)   -- 내 앞(+X) 18
				local rpg = RaycastParams.new()
				rpg.FilterType = Enum.RaycastFilterType.Exclude
				rpg.FilterDescendantsInstances = { char }
				local gh = workspace:Raycast(aimGround + Vector3.new(0, 40, 0), Vector3.new(0, -200, 0), rpg)
				local aimAt = gh and gh.Position or (aimGround - Vector3.new(0, 3, 0))
				if _G.throwDemonSpear then _G.throwDemonSpear(makeCaster(), aimAt) else ok = false end
			elseif which == "dragon" or which == "fd" then
				-- ⚠️ 프드는 '발사 지점에 소환'이라 더미 시전자가 필요 없다.
				--   오히려 더미로 부르면 소유권 검사(게임패스/번들)에 걸려 거부된다.
				-- ⚠️ [2026-08-30] ItemSpawnHandler:675 가 Role=="Tagger" 를 요구한다.
				--   검증은 러너 상태로 해야 하므로 소환 순간만 잠깐 바꾸고 되돌린다.
				--   ⚠️ 켜는 코드에 끄는 코드를 같이 — 되돌리지 않으면 러너인데 태거로 남는다.
				-- ⚠️ 브레스 방향은 시전자 위치를 참고한다(ItemSpawnHandler:1546). 한때 소환 순간
				--   나를 발사점으로 옮겨봤으나, 방패를 뒤에 설치하고 앞으로 나오는 쪽이
				--   더 단순해서 되돌렸다. 위치는 건드리지 않는다.
				local prevRole = player:GetAttribute("Role")
				player:SetAttribute("Role", "Tagger")
				if _G.BotSpawnItem then _G.BotSpawnItem(player, nil, "Frost Dragon", from) else ok = false end
				task.delay(0.5, function()
					if player and player.Parent then player:SetAttribute("Role", prevRole) end
				end)
			elseif which == "tox" or which == "toxbox" then
				-- 📦 [TEST 2026-08-31] 톡스박스를 내 앞에 세워 나에게 굴린다.
				--   [왜 필요한가] 킹 봇이 랜덤 타이밍·랜덤 위치로만 쏘는 데다 한 번에 하나만
				--     존재해서, "플레이어가 방패 뒤에서 박스를 맞는" 상황 자체가 두 판 연속
				--     안 잡혔다(실측 15:19 / 15:33 — 피격자가 둘 다 AI 러너였다).
				--   ⚠️ 소환 전 기존 박스를 반드시 지운다. spawnToxBox 는 playerActiveBox 에
				--     이전 박스가 남아 있으면 "❌ 이전 박스 살아있음" 으로 거부한다.
				--     forceCleanupAllBoxes 가 그 테이블까지 비우므로(ToxBoxSystem:537)
				--     이 순서라야 연속 실행이 된다.
				--   ⚠️ 굴림 방향은 소환점 → 러너 베이스다(ToxBoxSystem:629).
				--     발사점이 내 +X 라 박스는 나를 향해 -X 로 온다.
				--   ⚠️ runPattern 이 전진/측면을 번갈아 하므로 멀면 옆으로 샌다.
				--     기본 140 보다 짧게 주는 게 잘 맞는다(/atk tox 60).
				--   ⚠️ 릴리즈 전 삭제할 것.
				if _G.resetToxBox then _G.resetToxBox() end
				if _G.spawnToxBox then
					ok = _G.spawnToxBox(makeCaster(), from) and true or false
				else
					ok = false
				end
			else
				print("❓ /atk <tsunami|spear|energy|demon|dragon|tox> [거리]")
				return
			end
			if ok then
				print(string.format("🧪 [/atk] %s → %s (발사점 X+%d)", player.Name, which, OFFSET))
			else
				print("❌ [/atk] 해당 시스템 미로드: " .. which)
			end

		elseif lower:match("^/st") and not lower:match("^/stage") then
			-- 🧪 [TEST 2026-08-30] 방패 검증 세팅을 한 번에. (/runner + /spawnfree + /map2 + /sd)
			--   [왜] 매번 세 커맨드를 치는 게 번거로워 실수가 잦았다(태거인 채로 테스트한 적 있음).
			--   ⚠️ /spawnfree 는 토글이라 '켜기'로만 강제한다 — 두 번 실행해도 꺼지지 않게.
			--   ⚠️ 릴리즈 전 삭제할 것.
			--   ⚠️ /stage1~3 과 접두사가 겹치므로 제외 조건을 둔다(ChargeStageDebug).
			player:SetAttribute("Role", "Runner")
			print("🏃 [/st] Role = Runner")

			_G.AllowSpawnOffRound = true
			print("🧪 [/st] 라운드 밖 소환 허용 (해제: /spawnfree)")

			-- map2 ItemSpawnPlate2 근처로 이동하되, 언덕 아래로 좀 내려준다.
			--   ⚠️ 플레이트 바로 위는 태거 베이스라 아이템 면역이다. 거기 세우면
			--     아무것도 안 맞아 "왜 안 막히지"로 시간을 버린다(실측 12:40 판).
			local mf = workspace:FindFirstChild("map2")
			local plate = mf and mf:FindFirstChild("ItemSpawnPlate2", true)
			local ch = player.Character
			local hrp2 = ch and ch:FindFirstChild("HumanoidRootPart")
			if plate and hrp2 then
				local BACK = 90   -- 플레이트에서 -X 로 이만큼 내려간다
				local target = plate.Position + Vector3.new(-BACK, 0, 0)
				-- 지면 위로 올려 세운다
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = { ch }
				local hit = workspace:Raycast(target + Vector3.new(0, 300, 0), Vector3.new(0, -800, 0), rp)
				local pos = hit and (hit.Position + Vector3.new(0, 5, 0)) or (target + Vector3.new(0, 5, 0))
				hrp2.CFrame = CFrame.new(pos)
				print(string.format("🗺️ [/st] map2 언덕 (%.0f, %.0f, %.0f) 로 이동", pos.X, pos.Y, pos.Z))
			else
				warn("[/st] map2 ItemSpawnPlate2 못 찾음 — 이동 생략")
			end

			if _G.PauseRound then pcall(_G.PauseRound) end
			task.delay(0.4, function()
				giveRunnerItem(player, "Wood Shield")
				print("🛡️ [/st] Wood Shield 지급 — 설치하고 /atk 로 쏴볼 것")
			end)

		elseif lower == "/demonspear" or lower == "/ds" then
			-- 데몬 스피어 테스트 툴 지급 (장착 후 클릭한 곳으로 투척)
			local tool = game:GetService("ServerStorage"):FindFirstChild("DemonSpearTestTool")
			if not tool then
				print("❌ /ds: DemonSpearTestTool 템플릿 없음")
				return
			end
			local bp = player:FindFirstChildOfClass("Backpack")
			local char = player.Character
			-- 중복 제거 (Backpack + 착용중)
			if bp then for _, t in ipairs(bp:GetChildren()) do if t.Name == "DemonSpearTestTool" then t:Destroy() end end end
			if char then for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") and t.Name == "DemonSpearTestTool" then t:Destroy() end end end
			if bp then
				tool:Clone().Parent = bp
				print(string.format("🔥🗡️ [DemonSpearTest] %s 인벤 지급 완료 — 장착 후 클릭으로 투척", player.Name))
			else
				print("❌ /ds: Backpack 없음")
			end
		elseif lower == "/crown" then
			-- 토글: 왕관 없으면 부여, 있으면 제거
			local char = player.Character
			if not char then
				print("❌ /crown: 캐릭터 없음")
				return
			end
			local existing = char:FindFirstChild("TaggerCrown")
			if existing then
				if _G.removeCrownFromPlayer then
					_G.removeCrownFromPlayer(player)
				else
					existing:Destroy()
				end
				print("👑 [CrownTest]", player.Name, "→ 왕관 제거")
			else
				if _G.attachCrownToTagger then
					_G.attachCrownToTagger(player)
				else
					print("❌ RoundSystem 로드 안 됨 (attachCrownToTagger 없음)")
				end
			end
		elseif lower == "/crim" then
			-- Toggle Crim crown
			local char = player.Character
			if char and char:FindFirstChild("CrimCrown") then
				char.CrimCrown:Destroy()
				print("[CrimTest] "..player.Name.." -> Crim crown removed")
			else
				local ok, err = attachCrimCrown(player)
				if not ok then print("[CrimTest] fail: "..tostring(err)) end
			end
		elseif lower:match("^/crimsize") then
			local n = tonumber(lower:match("^/crimsize%s+([%-%d%.]+)"))
			if n then player:SetAttribute("CrimScale", n); attachCrimCrown(player)
			else print("[CrimTest] usage: /crimsize 1.2  (cur def "..CRIM_DEF_SCALE..")") end
		elseif lower:match("^/crimup") then
			local n = tonumber(lower:match("^/crimup%s+([%-%d%.]+)"))
			if n then player:SetAttribute("CrimUp", n); attachCrimCrown(player)
			else print("[CrimTest] usage: /crimup 0.8  (negative = lower)") end
		elseif lower:match("^/crimfwd") then
			local n = tonumber(lower:match("^/crimfwd%s+([%-%d%.]+)"))
			if n then player:SetAttribute("CrimFwd", n); attachCrimCrown(player)
			else print("[CrimTest] usage: /crimfwd 0.2  (positive = toward face)") end
		elseif lower == "/botmode" or lower:match("^/botmode%s") then
			-- 🎲 [테스트 2026-09-04] 봇 러너의 라운드 목적을 고정한다.
			--   /botmode capture — 점령 판만
			--   /botmode kill    — 태거 처치 판만
			--   /botmode random  — 강제 해제(확률 추첨으로 복귀)
			--   [왜] 목적이 판마다 추첨이라 특정 모드를 재려면 원하는 판이 뜰 때까지
			--     기다려야 했다. 측정에는 같은 조건을 반복해서 뽑는 게 필요하다.
			--   ⚠️ 다음 라운드부터 적용된다. 목적은 refreshMapTargets(맵 활성화) 시점에
			--     한 번 정해지고 라운드 중에는 안 바뀐다 — 바뀌면 봇이 우왕좌왕한다.
			local arg = lower:match("^/botmode%s+(%S+)")
			if arg == "capture" or arg == "kill" then
				_G.ForceBotObjective = arg
				print(string.format("🎲 [TEST] 봇 목적 고정: %s (다음 라운드부터) — 해제: /botmode random",
					arg == "kill" and "태거 처치" or "점령"))
			elseif arg == "random" or arg == "off" then
				_G.ForceBotObjective = nil
				print("🎲 [TEST] 봇 목적 강제 해제 → 확률 추첨으로 복귀")
			else
				local cur = _G.ForceBotObjective
				print(string.format("🎲 [TEST] 현재: %s | 사용법: /botmode capture | kill | random",
					cur and (cur .. " 고정") or "확률 추첨"))
			end

		elseif lower == "/ib" then
			-- Ice Bow 지급 (ServerStorage.RunnerItem.Ice Bow → Backpack)
			local template = game:GetService("ServerStorage"):FindFirstChild("RunnerItem")
			template = template and template:FindFirstChild("Ice Bow")
			if template and player:FindFirstChild("Backpack") then
				local tool = template:Clone()
				tool.Parent = player.Backpack
				print("🏹 [TEST] Ice Bow 지급 →", player.Name)
			else
				print("❓ [TEST] Ice Bow 템플릿 또는 Backpack 없음")
			end
		end
	end)
end

Players.PlayerAdded:Connect(hookChat)
for _, plr in ipairs(Players:GetPlayers()) do hookChat(plr) end

print("✅ TestCommands 준비! (/tagger /runner /norole /killbots(/kb) /botmode /itemtest /itemtestoff /diasword /sw /decoyhit /freeze [N] /tsunami /bomb [거리] /toxreset /micbomb /blackhole /blackholeme /energyball /crown /crim /skin)")
