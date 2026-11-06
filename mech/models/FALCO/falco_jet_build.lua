local D = {["center_imp"] = {["JetBody"] = {-0.0, -0.2, -1.775}, ["JetCockpit"] = {-0.0, 0.075, -3.6}, ["JetWingL"] = {-3.525, -0.25, 0.05}, ["JetWingR"] = {3.525, -0.25, 0.05}, ["JetTailL"] = {-1.4793, 1.201, 3.45}, ["JetTailR"] = {1.4793, 1.201, 3.45}}, ["center"] = {["JetBody"] = {0.0, -0.4, -3.55}, ["JetCockpit"] = {0.0, 0.15, -7.2}, ["JetWingL"] = {-7.05, -0.5, 0.1}, ["JetWingR"] = {7.05, -0.5, 0.1}, ["JetTailL"] = {-2.9585, 2.4021, 6.9}, ["JetTailR"] = {2.9585, 2.4021, 6.9}}, ["size"] = {["JetBody"] = {9.7, 4.1, 22.0}, ["JetCockpit"] = {2.5, 3.0, 5.1}, ["JetWingL"] = {8.2, 1.5, 6.9}, ["JetWingR"] = {8.2, 1.5, 6.9}, ["JetTailL"] = {1.676, 3.5101, 7.5}, ["JetTailR"] = {1.676, 3.5101, 7.5}}, ["pivot"] = {["JetBody"] = {0.0, 0.0, 0.0}, ["JetCockpit"] = {0.0, 0.0, -7.2}, ["JetWingL"] = {-3.0, -0.4, 0.4}, ["JetWingR"] = {3.0, -0.4, 0.4}, ["JetTailL"] = {-2.5, 0.9, 5.2}, ["JetTailR"] = {2.5, 0.9, 5.2}}, ["att"] = {["JetNozzleL"] = {["part"] = "JetBody", ["pos"] = {-3.9, -0.1, 6.7}, ["dir"] = "+Z"}, ["JetWingNozzleL"] = {["part"] = "JetWingL", ["pos"] = {-10.6, -0.25, 2.2}, ["dir"] = "+Z"}, ["JetMuzzleL"] = {["part"] = "JetBody", ["pos"] = {-1.4, -0.6, -6.4}, ["dir"] = "-Z"}, ["JetNozzleR"] = {["part"] = "JetBody", ["pos"] = {3.9, -0.1, 6.7}, ["dir"] = "+Z"}, ["JetWingNozzleR"] = {["part"] = "JetWingR", ["pos"] = {10.6, -0.25, 2.2}, ["dir"] = "+Z"}, ["JetMuzzleR"] = {["part"] = "JetBody", ["pos"] = {1.4, -0.6, -6.4}, ["dir"] = "-Z"}, ["JetMissile1"] = {["part"] = "JetBody", ["pos"] = {-3.1, -2.05, -3.3}, ["dir"] = "-Z"}, ["JetMissile2"] = {["part"] = "JetWingL", ["pos"] = {-5.4, -0.9, -3.5}, ["dir"] = "-Z"}, ["JetMissile3"] = {["part"] = "JetBody", ["pos"] = {3.1, -2.05, -3.3}, ["dir"] = "-Z"}, ["JetMissile4"] = {["part"] = "JetWingR", ["pos"] = {5.4, -0.9, -3.5}, ["dir"] = "-Z"}, ["JetFlashAtt"] = {["part"] = "JetBody", ["pos"] = {0.0, 0.0, 0.0}, ["dir"] = nil}}, ["glow"] = {["GlowLightAtt_Visor"] = {["part"] = "JetCockpit", ["pos"] = {0.0, 1.6, -7.3}}, ["GlowLightAtt_Chest"] = {["part"] = "JetBody", ["pos"] = {0.0, 1.5, -3.0}}, ["GlowLightAtt_NozzleL"] = {["part"] = "JetBody", ["pos"] = {-3.9, -0.1, 6.0}}, ["GlowLightAtt_NozzleR"] = {["part"] = "JetBody", ["pos"] = {3.9, -0.1, 6.0}}, ["GlowLightAtt_NozzleC"] = {["part"] = "JetBody", ["pos"] = {0.0, 0.2, 6.8}}}, ["hitbox"] = {["size"] = {7.6, 4.0, np.float64(22.0)}, ["center"] = {0.0, -0.2, -3.55}}, ["bbox_min"] = {-11.15, -2.45, -14.55}, ["bbox_max"] = {11.15, 4.14, 10.65}, ["com"] = {-0.0, -0.096, 0.107}, ["source"] = "FalcoJet_r3_20261106.glb"}
-- FalcoJet(FALCO 비행 형태) 조립 — Studio 명령 바에서 한 번 실행 (2026-11-06, jet_export.py 가 위 D 표를 붙여 만듦)
-- 준비: D.source 의 glb 를 3D 가져오기로 workspace 에 넣는다(크기·위치 그대로, 메시 이름 X_JetBody ...).
-- 하는 일: ReplicatedStorage.MechProto.FalcoJet 를 새로 만든다. AeroTemplate · 스크립트 · ServerStorage._Archive* 는 읽기만 하고 건드리지 않는다.
--   이미 FalcoJet 가 있으면 지우지 않고 ServerStorage._FalcoJet_before_<시각> 으로 옮긴다. 가져온 원본은 ServerStorage._Import_<원본 이름> 으로 옮긴다.
local Proto = game.ReplicatedStorage.MechProto
local aero = Proto.AeroTemplate
local SRC = D.source:gsub("%.glb$", "")
local imp = workspace:FindFirstChild(SRC)
assert(imp, "workspace 에 가져온 모델 " .. SRC .. " 가 없음")
local out = {}
local function V(t) return Vector3.new(t[1], t[2], t[3]) end
local function find(name)
	return imp:FindFirstChild("X_" .. name, true) or imp:FindFirstChild(name, true)
end

-- 0) 가져온 자리 → 템플릿 좌표(원점 = HRP 중심): 템플릿 = (가져온 위치 − O) × 2, 회전 없음
local O = find("JetBody").Position - V(D.center_imp.JetBody)
local maxdev, maxsz = 0, 0
for name, c in pairs(D.center_imp) do
	local s = find(name)
	assert(s and s:IsA("MeshPart"), "가져온 메시 없음: " .. name)
	maxdev = math.max(maxdev, ((s.Position - V(c)) - O).Magnitude)
	maxsz = math.max(maxsz, (s.MeshSize * 2 - V(D.size[name])).Magnitude)
	assert(s.CFrame.Rotation:FuzzyEq(CFrame.new(), 1e-4), "회전된 채 들어옴: " .. name)
end
table.insert(out, string.format("가져온 자리 어긋남 %.5f · 크기 어긋남 %.5f", maxdev, maxsz))
assert(maxdev < 0.01 and maxsz < 0.01, "가져오기 축이 예전과 다름 — 결과를 Claude 에게 보내 줘")

-- 1) 인간형에서 빌려 올 것(읽기만): 표면 · 재질 · 불꽃 · 발광 불빛
local refT = aero:FindFirstChild("Torso")
assert(refT, "AeroTemplate.Torso 없음")
local SA = refT:FindFirstChildOfClass("SurfaceAppearance")
assert(SA, "AeroTemplate.Torso 에 SurfaceAppearance 없음")
local FLAME
for _, d in ipairs(aero:GetDescendants()) do
	if d:IsA("ParticleEmitter") and d.Name == "Flame" then FLAME = d; break end
end
assert(FLAME, "AeroTemplate 안에 ParticleEmitter Flame 없음")
local LIGHT
for _, d in ipairs(aero:GetDescendants()) do
	if d:IsA("PointLight") and d.Name == "GlowLight" then LIGHT = d; break end
end

-- 2) 모델 · 파트
local old = Proto:FindFirstChild("FalcoJet")
if old then old.Name = "_FalcoJet_before_" .. os.date("%Y%m%d_%H%M%S"); old.Parent = game.ServerStorage end
local m = Instance.new("Model"); m.Name = "FalcoJet"
local P = {}
for name in pairs(D.center_imp) do
	local src = find(name)
	local p = src:Clone()
	p:ClearAllChildren()
	p.Name = name
	p.Size = src.MeshSize * 2
	p.CFrame = CFrame.new((src.Position - O) * 2)
	p.Anchored = false; p.CanCollide = false; p.CanTouch = false; p.CanQuery = true
	p.Massless = true; p.CastShadow = true; p.Material = refT.Material; p.CollisionGroup = refT.CollisionGroup
	SA:Clone().Parent = p
	p.PivotOffset = CFrame.new(p.CFrame:PointToObjectSpace(V(D.pivot[name])))   -- 날개·꼬리·카나드 = 뿌리, 동체 = 원점
	p.Parent = m
	P[name] = p
end
local body = P.JetBody

-- 판정 상자(투명, 쓸지는 코드 세션이 정함)
local hb = Instance.new("Part"); hb.Name = "JetHitBox"
hb.Size = V(D.hitbox.size); hb.CFrame = CFrame.new(V(D.hitbox.center))
hb.Transparency = 1; hb.Anchored = false; hb.CanCollide = false; hb.CanTouch = false; hb.CanQuery = true; hb.Massless = true
hb.CastShadow = false; hb.Parent = m
P.JetHitBox = hb

-- 3) 묶기: 모두 JetBody 에 WeldConstraint(움직일 날개·꼬리·카나드도 일단 Weld)
for name, p in pairs(P) do
	if p ~= body then
		local w = Instance.new("WeldConstraint"); w.Name = "Weld_" .. name
		w.Part0 = body; w.Part1 = p; w.Parent = p
	end
end

-- 4) 부착점: 축 = 모델 축(회전 0) → −Z = 앞(총구·미사일), +Z = 뒤(노즐 분사)
local function att(name, partName, pos)
	local a = Instance.new("Attachment"); a.Name = name
	a.CFrame = CFrame.new(P[partName].CFrame:PointToObjectSpace(V(pos)))
	a.Parent = P[partName]
	return a
end
for name, t in pairs(D.att) do
	local a = att(name, t.part, t.pos)
	if t.dir then a:SetAttribute("FireDir", t.dir) end
	if name:find("Nozzle") then
		local f = FLAME:Clone(); f.Name = "Flame"
		f.EmissionDirection = Enum.NormalId.Back      -- +Z = 뒤로 분사
		f.Enabled = false
		f.Parent = a
	end
end
for name, t in pairs(D.glow) do
	local a = att(name, t.part, t.pos)
	local l = LIGHT and LIGHT:Clone() or Instance.new("PointLight")
	l.Name = "GlowLight"; l.Range = 3.5; l.Brightness = 3
	if not LIGHT then l.Color = Color3.fromRGB(255, 214, 90); l.Shadows = false end
	l.Parent = a
end

-- 5) 모델 속성
m.PrimaryPart = body
m:SetAttribute("JetForm", true)
m:SetAttribute("FlightOf", "Aero")
m:SetAttribute("Source", D.source .. " ×2 (2026-11-06 mech/code/falco_jet · 레포 mech/models/FALCO/). 원점 = HumanoidRootPart 중심 자리, 앞 −Z")
m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
m.Parent = Proto
imp.Name = "_Import_" .. SRC; imp.Parent = game.ServerStorage

-- 6) 검사 · 보고
local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
local nP = 0
for _, d in ipairs(m:GetDescendants()) do
	if d:IsA("BasePart") then
		nP += 1
		if d.Transparency < 1 then
			local c, s = d.CFrame, d.Size
			for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
				local q = (c * CFrame.new(sx * s.X / 2, sy * s.Y / 2, sz * s.Z / 2)).Position
				mn = mn:Min(q); mx = mx:Max(q)
			end end end
		end
	end
end
local conn = #body:GetConnectedParts(true)
table.insert(out, string.format("파트 %d · 바운딩 %s (최소 %s · 최대 %s) · JetBody 에 묶인 파트 %d · 모델 피벗 %s",
	nP, tostring(mx - mn), tostring(mn), tostring(mx), conn, tostring(m:GetPivot().Position)))
table.insert(out, string.format("JetCockpit 크기 %s 위치 %s · JetHitBox 크기 %s 위치 %s",
	tostring(P.JetCockpit.Size), tostring(P.JetCockpit.Position), tostring(hb.Size), tostring(hb.Position)))
local names = {}
for _, d in ipairs(m:GetDescendants()) do if d:IsA("Attachment") then table.insert(names, d.Name) end end
table.sort(names)
for _, n in ipairs(names) do
	local a = m:FindFirstChild(n, true)
	table.insert(out, string.format("  %-22s %-11s %s", n, a.Parent.Name, tostring(a.WorldPosition)))
end
return table.concat(out, "\n")
