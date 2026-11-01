-- VictoryPoseFix (ModuleScript, ReplicatedStorage) — 승리포즈 데이터 위에 얹는 보정 (2026-10-29)
-- 생성 데이터(VictoryPoseData, export_studio.py)는 손대지 않고, 재생 직전에 여기서 고친 사본을 만든다.
--
-- A 무릎 쏴 높이(10-29 18:10 유저 "가상 배경 기준이었어서 그런지 무릎 꿇는 높이가 맞질않아"):
--   원인 [실측 Studio FK, 템플릿 실제 C0/C1]: 미리보기의 땅 맞춤이 "가장 낮은 점(왼발) = 바닥" 하나만 걸어서
--   마무리에서 오른 무릎 관절이 y 6.42 · 오른 발목 y 10.46 — 무릎이 땅에서 떠 있었다(왼발은 바닥 −0.07).
--   규칙(결과 보장): 마무리 자세에서 오른 무릎이 바닥에 닿게 골반을 내린다. 내릴 양 = (마무리 오른 무릎 관절 높이 − kneeContact)
--     → 위(Python)에서 고쳐져 이미 닿아 있으면 0 이 되어 아무것도 안 바뀜.
--   · 무릎 꿇는 구간(1.9~2.8초, anim5 AS2 → AF)의 뒤쪽 t0~t1 에 smoothstep 으로 섞어 넣음.
--     t0 = 1.9 로 하면 오른발이 아직 땅에 있을 때 골반이 먼저 내려가 오른발이 최대 0.77 파묻힘 [실측 probe 메시 레이캐스트, f52~64]
--     → 오른발이 땅을 뜨는 2.2초부터(2.2 · 2.35 · 2.45 모두 전 구간 최저 −0.06 = 원래 데이터의 왼발 값)
--   · 왼발 = 그 프레임의 원래 자리·방향 그대로(왼다리 2관절 IK: 무릎 각 = 엉덩이~발목 거리, 엉덩이 = 최소 회전)
--   · 오른발 = 발목 관절 높이 ankleH 가 되게 무릎을 조금 펴고, 발끝 아래 모서리가 toeY 가 되게 발목을 돌림(마무리에서 구해 구간에 섞음)
--   · 앞 스커트(SkirtJointFL)는 왼 허벅지가 더 든 만큼 skirtFollow 배 따라 듦(데이터의 스커트 근사 70% 와 같은 비율)
--   · 카메라도 내린 만큼 같이 내림(camFollow) — 승인된 화면 구도 유지
local Fix = {}

Fix.KNEEL_A = {
	t0 = 2.2, t1 = 2.8,      -- 골반 내리는 구간(초) — 위 설명
	kneeContact = 2.68,      -- 무릎 관절 중심 높이 → 무릎 메시 바닥 +0.01 [실측 probe: 2.2 면 −0.48 파묻힘]
	ankleH = 4.8,            -- 오른 발목 관절 목표 높이(발끝 세움)
	toeY = -0.2,             -- 오른발 발끝 상자 모서리 목표 → 메시 발끝 +0.03 [실측 probe: 0 이면 +0.20 뜸]
	skirtFollow = 0.7,
	camFollow = 1.0,
}

local STAGE_HRP = CFrame.new(0, 17.2, 0)   -- 무대 원점(발밑 가운데) 기준 HRP 자리 [실측]

function Fix.rig(model)
	local R = { hrp = model:FindFirstChild("HumanoidRootPart"), by0 = {}, mot = {} }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			R.by0[d.Part0] = R.by0[d.Part0] or {}
			table.insert(R.by0[d.Part0], d)
			R.mot[d.Name] = d
		end
	end
	return R
end

-- 무대 좌표 FK: Part1 = Part0 · C0 · T · C1⁻¹ (엔진과 같은 식)
function Fix.fk(R, T)
	local cf = { [R.hrp] = STAGE_HRP }
	local q, i = { R.hrp }, 1
	while q[i] do
		local p0 = q[i]; i += 1
		for _, m in ipairs(R.by0[p0] or {}) do
			cf[m.Part1] = cf[p0] * m.C0 * (T[m.Name] or CFrame.identity) * m.C1:Inverse()
			q[#q + 1] = m.Part1
		end
	end
	return cf
end

local function getQ(t, f)
	local b = f * 4
	return CFrame.new(0, 0, 0, t[b + 1], t[b + 2], t[b + 3], t[b + 4])
end

local function quat(cf)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local w = math.sqrt(math.max(0, 1 + r00 + r11 + r22)) / 2
	local x = math.sqrt(math.max(0, 1 + r00 - r11 - r22)) / 2
	local y = math.sqrt(math.max(0, 1 - r00 + r11 - r22)) / 2
	local z = math.sqrt(math.max(0, 1 - r00 - r11 + r22)) / 2
	if r21 - r12 < 0 then x = -x end
	if r02 - r20 < 0 then y = -y end
	if r10 - r01 < 0 then z = -z end
	local n = math.sqrt(x * x + y * y + z * z + w * w)
	return x / n, y / n, z / n, w / n
end

local function setQ(t, f, cf)
	local x, y, z, w = quat(cf)
	if f > 0 then   -- 부호 이어 붙이기(보간이 먼 길로 안 돌게, export 와 같음)
		local b = (f - 1) * 4
		if x * t[b + 1] + y * t[b + 2] + z * t[b + 3] + w * t[b + 4] < 0 then x, y, z, w = -x, -y, -z, -w end
	end
	local b = f * 4
	t[b + 1], t[b + 2], t[b + 3], t[b + 4] = x, y, z, w
end

function Fix.frameT(clip, f)
	local T = {}
	for j, t in pairs(clip.q) do T[j] = getQ(t, f) end
	local p = clip.rootp
	T.Root = CFrame.new(p[f * 3 + 1], p[f * 3 + 2], p[f * 3 + 3]) * T.Root
	return T
end

local function jointPos(cf, m) return (cf[m.Part0] * m.C0).Position end

-- g(x) = 0 인 x 중 0 에 가장 가까운 것([lo, hi], 1° 간격으로 훑고 이분법)
local function rootNear0(g, lo, hi)
	local step = math.rad(1)
	local g0 = g(0)
	if math.abs(g0) < 1e-4 then return 0 end
	for k = 1, math.ceil(math.max(-lo, hi) / step) do
		for _, sgn in ipairs({ 1, -1 }) do
			local a, b = (k - 1) * step * sgn, k * step * sgn
			if b >= lo and b <= hi then
				local ga, gb = g(a), g(b)
				if ga * gb <= 0 then
					for _ = 1, 40 do
						local m = (a + b) / 2
						local gm = g(m)
						if ga * gm <= 0 then b = m else a, ga = m, gm end
					end
					return (a + b) / 2
				end
			end
		end
	end
	return nil
end

-- 다리 2관절 IK: 발목 관절을 target 에 놓음(무릎 = X 경첩, 엉덩이 = 원래 방향에서 최소 회전)
local function solveLeg(R, T, s, target)
	local m = R.mot
	local hip, knee, ank = m["Hip" .. s], m["Knee" .. s], m["Ankle" .. s]
	local cf = Fix.fk(R, T)
	local W = cf[hip.Part0] * hip.C0
	local H = W.Position
	local want = (target - H).Magnitude
	local hipInThigh = hip.C1.Position
	local function ankInThigh(k) return (knee.C0 * CFrame.Angles(k, 0, 0) * knee.C1:Inverse() * ank.C0).Position end
	local k0 = select(1, T["Knee" .. s]:ToEulerAnglesXYZ())
	local dk = rootNear0(function(x) return (ankInThigh(k0 + x) - hipInThigh).Magnitude - want end, math.rad(-120), math.rad(120))
	if not dk then return false end
	T["Knee" .. s] = CFrame.Angles(k0 + dk, 0, 0)
	local thigh = W * T["Hip" .. s] * hip.C1:Inverse()
	local a = (thigh * ankInThigh(k0 + dk)) - H
	local b = target - H
	local axis = a:Cross(b)
	if axis.Magnitude > 1e-6 then
		local ang = math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
		local Rw = W.Rotation
		T["Hip" .. s] = Rw:Inverse() * CFrame.fromAxisAngle(axis.Unit, ang) * Rw * T["Hip" .. s]
	end
	return true
end

local function pitchIn(cf, pelvis, part, m)   -- 허벅지(엉덩이 관절 → 무릎 관절)의 골반 기준 앞으로 든 각
	local v = cf[pelvis]:VectorToObjectSpace(jointPos(cf, m.KneeL) - jointPos(cf, m.HipL))
	return math.atan2(-v.Z, -v.Y)
end

local function footToeY(cf, foot)
	local s = foot.Size / 2
	local y = math.huge
	for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do
		y = math.min(y, (cf[foot] * Vector3.new(sx * s.X, sy * s.Y, -s.Z)).Y)   -- 발끝 = 로컬 −Z 면(발목 C1 이 +Z 쪽)
	end end
	return y
end

-- A 보정 사본 + 보고서. P 생략 = Fix.KNEEL_A
function Fix.kneelA(clip, R, P)
	P = P or Fix.KNEEL_A
	local m = R.mot
	local n = clip.frames
	local endT = Fix.frameT(clip, n - 1)
	local cfEnd = Fix.fk(R, endT)
	local drop = math.max(0, jointPos(cfEnd, m.KneeR).Y - P.kneeContact)
	local rep = { drop = drop }
	if drop < 0.05 then return clip, rep end

	-- 마무리에서 오른 무릎·발목 보정량
	local Te = Fix.frameT(clip, n - 1)
	Te.Root = CFrame.new(0, -drop, 0) * Te.Root
	local K0, A0 = Te.KneeR, Te.AnkleR
	local footR = m.AnkleR.Part1
	local dkR = rootNear0(function(x)
		Te.KneeR = CFrame.Angles(x, 0, 0) * K0
		return jointPos(Fix.fk(R, Te), m.AnkleR).Y - P.ankleH
	end, math.rad(-80), math.rad(80)) or 0
	Te.KneeR = CFrame.Angles(dkR, 0, 0) * K0
	local daR = rootNear0(function(x)
		Te.AnkleR = CFrame.Angles(x, 0, 0) * A0
		return footToeY(Fix.fk(R, Te), footR) - P.toeY
	end, math.rad(-90), math.rad(90)) or 0
	rep.dkR, rep.daR = math.deg(dkR), math.deg(daR)

	local out = table.clone(clip)
	out.q = table.clone(clip.q)
	for _, j in ipairs({ "HipL", "KneeL", "AnkleL", "KneeR", "AnkleR", "SkirtJointFL", "Root" }) do out.q[j] = table.clone(clip.q[j]) end
	out.rootp = table.clone(clip.rootp)
	out.cam = table.clone(clip.cam)
	local pelvis = m.Root.Part1
	local footL = m.AnkleL.Part1
	local worstFoot = 0
	for f = 0, n - 1 do
		local t = f / clip.fps
		local u = math.clamp((t - P.t0) / (P.t1 - P.t0), 0, 1)
		u = u * u * (3 - 2 * u)
		if u > 0 then
			local T = Fix.frameT(clip, f)
			local cf0 = Fix.fk(R, T)
			local footL0 = cf0[footL]
			local ankL0 = jointPos(cf0, m.AnkleL)
			local pitch0 = pitchIn(cf0, pelvis, nil, m)
			local d = drop * u
			T.Root = CFrame.new(0, -d, 0) * T.Root
			out.rootp[f * 3 + 2] = clip.rootp[f * 3 + 2] - d
			T.KneeR = CFrame.Angles(dkR * u, 0, 0) * T.KneeR
			T.AnkleR = CFrame.Angles(daR * u, 0, 0) * T.AnkleR
			if solveLeg(R, T, "L", ankL0) then
				local cf1 = Fix.fk(R, T)
				local Wa = cf1[m.AnkleL.Part0] * m.AnkleL.C0
				T.AnkleL = (Wa:Inverse() * footL0 * m.AnkleL.C1).Rotation
				local dp = pitchIn(cf1, pelvis, nil, m) - pitch0
				if dp > 0 then T.SkirtJointFL = CFrame.Angles(dp * P.skirtFollow, 0, 0) * T.SkirtJointFL end
				local cf2 = Fix.fk(R, T)
				worstFoot = math.max(worstFoot, (cf2[footL].Position - footL0.Position).Magnitude)
			end
			for _, j in ipairs({ "HipL", "KneeL", "AnkleL", "KneeR", "AnkleR", "SkirtJointFL" }) do setQ(out.q[j], f, T[j]) end
			out.cam[f * 7 + 2] = clip.cam[f * 7 + 2] - d * P.camFollow
		end
	end
	rep.worstFootL = worstFoot
	return out, rep
end

return Fix
