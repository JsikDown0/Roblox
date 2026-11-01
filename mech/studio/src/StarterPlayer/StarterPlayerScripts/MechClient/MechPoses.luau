-- MechPoses (ModuleScript, MechClient 의 자식) — 10-30 MechClient 에서 떼어 냄
-- 유저 10-30 "메크 클라이언트를 분석하고 나눠야 할 것 같아": Script.Source 20만 자 한도(넘으면 플러그인·도구로 스크립트를 쓰는 작업이 실패 — ASMR Cart 에서 같은 이유로 _CartSystem 을 나눴음).
--   나누기 전 MechClient 200,212자 · 이 덩어리 = 옛 MechClient 2116~2797줄(자세 표·자세 함수) 그대로. 백업 = ServerStorage._MechClientSplit_before_20261030
-- 의존성 [에디트 분석 studio/luau_deps.lua — 토큰 단위]: 바깥 이름은 CFG · Debris · mech · reloadLocalUntil 넷뿐.
--   CFG·Debris 는 여기서 직접 가져오고, 바뀌는 값(mech·reloadLocalUntil — reloadElapsed 한 줄)은 MechClient 가 init 으로 넘긴 읽기 함수(ctx)로 읽는다.
-- MechClient 가 쓰는 이름 40개를 맨 아래 표로 돌려줌(MechClient 는 같은 자리에서 같은 이름의 local 로 받음 → 나머지 코드는 그대로)
-- ⚠️ 여기 새 이름을 더해 MechClient 에서 쓰려면 아래 반환 표와 MechClient 의 받는 줄(local ... = PO.…) 둘 다에 넣을 것
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local CFG = require(RS:WaitForChild("MechProto"):WaitForChild("MechConfig"))
local ctx = { mech = function() return nil end, reloadLocalUntil = function() return 0 end }   -- MechClient 가 init 으로 바꿔 끼움
-- ================= 모든 메카 코드 애니메이션 =================
-- 축은 모델 기준: X+ = 팔다리를 앞으로 / 상체를 뒤로 젖힘, Y+ = 왼쪽으로 돎(오른 어깨가 앞으로), Z+ = 팔다리를 오른쪽으로
-- 라이플은 아래팔과 나란하다: 총구 피치 = 허리X + 어깨X + 팔꿈치X - 90
local AIM_HOLD_REMOTE = 0.25   -- 다른 플레이어: 발사 간격(0.12초)을 메울 만큼만 조준 유지
local rad = math.rad
local function E(x, y, z)
	return CFrame.fromAxisAngle(Vector3.yAxis, rad(y or 0)) * CFrame.fromAxisAngle(Vector3.xAxis, rad(x or 0)) * CFrame.fromAxisAngle(Vector3.zAxis, rad(z or 0))
end
local function R(axis, deg) return CFrame.fromAxisAngle(axis, rad(deg)) end
local function setThrusters(st, on)
	if st.thrust == on then return end
	st.thrust = on
	for _, e in ipairs(st.emitters) do e.Enabled = on end
	if st.light then st.light.Enabled = on end
end

-- 빔사벨 자세. 관절 계산으로 날 끝 궤적을 맞춰 둠(2026-10-24): 등 뒤 위 → 머리 위 → 정면 오른쪽 아래로 내려벤다.
-- 15스터드 앞 기체의 머리~몸통을 들기 후 약 0.12초(누른 뒤 약 0.24초 = SaberStrike)에 지난다
-- 2026-10-24 밤: 백팩에서 뽑는 동작을 앞에 붙였다. 잡기(G) = 관절 탐색으로 손이 꽂힌 칼자루 중심·방향에 맞음(오차 0.001)
--   잡기 0~0.10 → 뽑아 올리기 0.10~0.17(빔이 몸 밖으로 나오는 0.15에 점화) → 내려베기 0.17~0.31(판정 0.30) → 마무리 ~0.43 → 복귀
local SABER_G = { Root = CFrame.new(0, -0.2, 0), Waist = E(4, 15), Neck = E(0, -10), ShoulderL = E(142, 43.8, 0), ElbowL = E(110.9), SaberGrip = E(17.1) }
local SABER_W = { Root = CFrame.new(0, -0.3, 0), Waist = E(6, 30), Neck = E(-4, -18), ShoulderL = E(165, 0, -25), ElbowL = E(45), SaberGrip = E(40) }
local SABER_S = { Root = CFrame.new(0, -1, 0), Waist = E(-16, -20), Neck = E(8, 12), ShoulderL = E(60, 0, 18), ElbowL = E(6), SaberGrip = E(-25) }
local SABER_F = { Root = CFrame.new(0, -1.2, 0), Waist = E(-14, -28), Neck = E(6, 16), ShoulderL = E(48, 0, 26), ElbowL = E(12), SaberGrip = E(-32) }
local function blendPose(A, B, a)
	local o = {}
	for n, cfA in pairs(A) do o[n] = cfA:Lerp(B[n] or CFrame.new(), a) end
	for n, cfB in pairs(B) do if not o[n] then o[n] = CFrame.new():Lerp(cfB, a) end end
	return o
end
-- 10-26: 동작 자세는 기체 모양별 묶음 Q(아래 SHAPES — Q.G 잡기·Q.W 뽑아 올림·Q.S 내려벰·Q.F 마무리 …). 프로토 = 위 표 그대로
local function saberPose(e, Q)   -- 돌려주는 값: (평상 자세와 섞는 비율, 자세)
	if e < 0.10 then
		local a = e / 0.10
		return a * a * (3 - 2 * a), Q.G                                  -- 왼손이 백팩 칼자루를 잡으러 간다
	elseif e < 0.17 then
		local a = (e - 0.10) / 0.07
		return 1, blendPose(Q.G, Q.W, a * a * (3 - 2 * a))           -- 위·바깥·뒤로 뽑아 올림
	elseif e < 0.31 then
		local a = (e - 0.17) / 0.14
		return 1, blendPose(Q.W, Q.S, a * a)       -- 가속하며 내려벤다
	elseif e < 0.43 then
		local a = (e - 0.31) / 0.12
		return 1, blendPose(Q.S, Q.F, math.sin(a * math.pi / 2))
	end
	local a = math.clamp((e - 0.43) / math.max(0.05, CFG.SaberTime - 0.43), 0, 1)
	return 1 - a * a * (3 - 2 * a), Q.F
end
-- 손에 든 칼(InHand)과 백팩에 꽂힌 칼(Holster)을 바꿔 보여 준다. 각 화면에서 따로(투명도는 복제 안 됨)
-- 주먹(왼손 스트레이트) 자세. 관절 계산으로 맞춤(2026-10-24): 당길 때 주먹이 가슴 왼쪽, 뻗으면 정면 10.3스터드·가슴 높이
-- = 11스터드 앞 기체의 몸통 앞면에 닿는다(PunchStop). 허리를 오른쪽으로 돌려 왼어깨를 밀어 넣는다
local PUNCH_W = { Root = CFrame.new(0, -0.3, 0), Waist = E(2, 28), Neck = E(0, -16), ShoulderL = E(25, 0, -8), ElbowL = E(105) }
local PUNCH_S = { Root = CFrame.new(0, -0.8, 0), Waist = E(-10, -26), Neck = E(6, 14), ShoulderL = E(86, 0, 10), ElbowL = E(4) }
local function punchPose(e, Q)   -- 돌려주는 값: (평상 자세와 섞는 비율, 자세)
	if e < 0.08 then
		local a = e / 0.08
		return a * a * (3 - 2 * a), Q.PW
	elseif e < 0.16 then
		local a = (e - 0.08) / 0.08
		return 1, blendPose(Q.PW, Q.PS, a * (2 - a))   -- 빨리 뻗고 끝에서 멈춘다
	elseif e < 0.22 then
		return 1, Q.PS
	end
	local a = math.clamp((e - 0.22) / math.max(0.05, CFG.PunchTime - 0.22), 0, 1)
	return 1 - a * a * (3 - 2 * a), Q.PS
end
-- 10-30 SKADI 앞차기(왼다리 — 오른손 저격총 쪽을 피함). K = SH.kick = { C = 당기기, X = 뻗기 } · 각 키 { J = 관절, root = 골반 내림, lean = 허리 뒤로 젖힘(도) }
--   당기기 0~0.12 → 뻗기 ~0.20(판정 0.18) → 버팀 ~0.32 → 당기기로 되돌림 ~0.47 → 평상 자세로(Kick.Time)
--   [sniper/rig/kick_check.py] 이 순서(서기→C→X→C→서기) 그대로 1/10 간격 검사: 다리가 몸·총·팔과 겹침 0 (스커트끼리만 — SH.skirt 로 줄임)
local function kickBlend(A, B, a)
	return { J = blendPose(A.J, B.J, a), root = A.root + (B.root - A.root) * a, lean = A.lean + (B.lean - A.lean) * a }
end
local function kickPose(e, K)   -- 돌려주는 값: (평상 자세와 섞는 비율, 키)
	local function sm(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end
	if e < 0.12 then return sm(e / 0.12), K.C end
	if e < 0.20 then local a = (e - 0.12) / 0.08; return 1, kickBlend(K.C, K.X, a * (2 - a)) end   -- 빨리 뻗고 끝에서 멈춤
	if e < 0.32 then return 1, K.X end
	if e < 0.47 then return 1, kickBlend(K.X, K.C, sm((e - 0.32) / 0.15)) end
	return 1 - sm((e - 0.47) / math.max(0.05, CFG.Kick.Time - 0.47)), K.C
end
-- 10-30 앞차기 공중제비: k = 진행(0~1, CFG.flipPhase). 돌려주는 값 = (웅크림 섞는 비율 w, 뒤로 도는 각 θ 라디안)
--   w: 0~0.25 웅크림 들어감 · 0.7 까지 유지 · 1 에서 다 펴고 착지 / θ: 0.9 에 한 바퀴 다 돎(꼭대기 k 0.45 즈음 거꾸로) [sniper/rig/flip_check.py 와 같은 식]
local function flipPose(k)
	local function sm(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end
	local w = (k < 0.25) and sm(k / 0.25) or ((k < 0.7) and 1 or (1 - sm((k - 0.7) / 0.3)))
	return w, 2 * math.pi * sm(k / 0.9)
end
-- 빔사벨 상태(2) 자세 (2026-10-25). 겨눔 = 관절 탐색: 손은 왼쪽 앞 가슴 아래, 빔은 앞·위·왼쪽(몸·머리 안 뚫음).
-- 왼팔만 정한다. 골반·허리·목은 그 프레임의 평상 자세를 쓴다(Rcur) — 덮으면 옆걸음 골반 틀기가 꺼져 가위질 걸음이 돌아온다
local SABER_R = { ShoulderL = E(5.2, -5.3, 9.7), ElbowL = E(83.5), SaberGrip = E(-38.1) }
local function slashPose(e, R, Q)   -- 겨눔 → 들어올리기 0.08 → 내려베기 0.22(판정 0.21) → 마무리 0.34 → 겨눔 복귀(SlashTime)
	if e < 0.08 then
		local a = e / 0.08
		return 1, blendPose(R, Q.W, a * a * (3 - 2 * a))
	elseif e < 0.22 then
		local a = (e - 0.08) / 0.14
		return 1, blendPose(Q.W, Q.S, a * a)
	elseif e < 0.34 then
		local a = (e - 0.22) / 0.12
		return 1, blendPose(Q.S, Q.F, math.sin(a * math.pi / 2))
	end
	local a = math.clamp((e - 0.34) / math.max(0.05, CFG.SlashTime - 0.34), 0, 1)
	return 1, blendPose(Q.F, R, a * a * (3 - 2 * a))
end
local function equipPose(e, R, Q)   -- 2: 백팩 칼 잡기 0.10 → 뽑아 올리기 0.17 → 겨눔(EquipTime)
	if e < 0.10 then
		local a = e / 0.10
		return a * a * (3 - 2 * a), Q.G
	elseif e < 0.17 then
		local a = (e - 0.10) / 0.07
		return 1, blendPose(Q.G, Q.W, a * a * (3 - 2 * a))
	elseif e < CFG.EquipTime then
		local a = (e - 0.17) / math.max(0.05, CFG.EquipTime - 0.17)
		return 1, blendPose(Q.W, R, a * a * (3 - 2 * a))
	end
	return 1, R
end
local function unequipPose(e, R, Q)   -- 1: 겨눔 → 백팩에 꽂기 0.15 → 평상 자세(UnequipTime)
	if e < 0.15 then
		local a = e / 0.15
		return 1, blendPose(R, Q.G, a * a * (3 - 2 * a))
	end
	local a = math.clamp((e - 0.15) / math.max(0.05, CFG.UnequipTime - 0.15), 0, 1)
	return 1 - a * a * (3 - 2 * a), Q.G
end
-- 3연격 2·3타 자세 (2026-10-25). 관절 탐색으로 손 위치·날 방향을 맞추고, 연결 구간 전체를 궤적 검사:
-- 자기 몸 관통 없음 · 15스터드 앞 기체를 판정 시각(2타 0.15 / 3타 0.20)에 지난다
local SLASH2_A = { Root = CFrame.new(0, -0.6, 0), Waist = E(-4, -30), Neck = E(0, 18), ShoulderL = E(18.9, -32.8, 1.4), ElbowL = E(91.0), SaberGrip = E(-97.7) }
local SLASH2_B = { Root = CFrame.new(0, -0.8, 0), Waist = E(-6, 28), Neck = E(0, -16), ShoulderL = E(-29.6, -35.2, -111.2), ElbowL = E(86.2), SaberGrip = E(-162.4) }
local SLASH2_C = { Root = CFrame.new(0, -0.8, 0), Waist = E(-4, 36), Neck = E(0, -20), ShoulderL = E(-25.8, -8.4, -98.1), ElbowL = E(109.0), SaberGrip = E(168.0) }
-- 3타 = 찌르기 (2026-10-25, 올려베기에서 교체). 관절 탐색 + 궤적 검사: 자기 몸·등 라이플 관통 없음,
-- 날은 내내 앞을 향하고 0.14 에 15스터드 앞 기체에 닿기 시작(판정 0.16). 날이 안쪽으로 15° 모여 정면 중심을 지난다
local SLASH3_A = { Root = CFrame.new(0, -0.8, 0), Waist = E(-4, 22), Neck = E(0, -14), ShoulderL = E(-55, -2, -15), ElbowL = E(130), SaberGrip = E(-65) }    -- 왼쪽 허리 뒤로 당김
local SLASH3_B = { Root = CFrame.new(0, -1.4, 0), Waist = E(-8, -26), Neck = E(0, 18), ShoulderL = E(89.2, -2.0, -13.4), ElbowL = E(5.0), SaberGrip = E(-85.0) } -- 쭉 뻗어 찌름(손 정면 11.5, 날끝 24)
local SLASH3_C = { Root = CFrame.new(0, -1.2, 0), Waist = E(-6, -20), Neck = E(0, 14), ShoulderL = E(84, -2, -10), ElbowL = E(16), SaberGrip = E(-82) }         -- 찌른 채 유지
local function slash2Pose(e, R, Q)   -- 1타 끝 → 오른쪽으로 감기 0.07 → 가로베기 0.19(판정 0.15) → 마무리 0.28(3타 이어짐) → 겨눔 복귀
	if e < 0.07 then
		local a = e / 0.07
		return 1, blendPose(Q.F, Q.S2A, a * a * (3 - 2 * a))
	elseif e < 0.19 then
		local a = (e - 0.07) / 0.12
		return 1, blendPose(Q.S2A, Q.S2B, a * a)
	elseif e < 0.28 then
		local a = (e - 0.19) / 0.09
		return 1, blendPose(Q.S2B, Q.S2C, math.sin(a * math.pi / 2))
	end
	local a = math.clamp((e - 0.28) / math.max(0.05, CFG.Slash2Time - 0.28), 0, 1)
	return 1, blendPose(Q.S2C, R, a * a * (3 - 2 * a))
end
local function slash3Pose(e, R, Q)   -- 2타 끝 → 허리로 당김 0.09 → 찌름 0.17(판정 0.16) → 유지 0.32 → 겨눔 복귀
	if e < 0.09 then
		local a = e / 0.09
		return 1, blendPose(Q.S2C, Q.S3A, a * a * (3 - 2 * a))
	elseif e < 0.17 then
		local a = (e - 0.09) / 0.08
		return 1, blendPose(Q.S3A, Q.S3B, a * a)                       -- 갈수록 빨라짐
	elseif e < 0.32 then
		local a = (e - 0.17) / 0.15
		return 1, blendPose(Q.S3B, Q.S3C, math.sin(a * math.pi / 2))
	end
	local a = math.clamp((e - 0.32) / math.max(0.05, CFG.Slash3Time - 0.32), 0, 1)
	return 1, blendPose(Q.S3C, R, a * a * (3 - 2 * a))
end
local SLASH_POSE = { slash1 = slashPose, slash2 = slash2Pose, slash3 = slash3Pose }
-- 휘두름 소리(임시)를 낼 시각 = 날이 움직이기 시작하는 순간(뽑아 베기는 뽑은 뒤 내려칠 때)
local SWING_AT = { saber = 0.17, slash1 = 0.08, slash2 = 0.07, slash3 = 0.09 }
-- 공중 자세(2026-10-25): 위아래 속도로 섞는다. 오를 때 다리 뻗음 → 꼭대기 무릎 당김 → 내려올 때 다리 내려 착지 준비
local AIR_RISE = { HipL = E(6), HipR = E(-8), KneeL = E(-12), KneeR = E(-8), AnkleL = E(-6), AnkleR = E(-4) }
local AIR_TUCK = { HipL = E(26), HipR = E(10), KneeL = E(-48), KneeR = E(-28), AnkleL = E(14), AnkleR = E(10) }
local AIR_FALL = { HipL = E(14), HipR = E(4), KneeL = E(-20), KneeR = E(-14), AnkleL = E(6), AnkleR = E(6) }
-- 도약·착지 웅크림(2026-10-25): 골반을 내린 만큼 다리를 접어 발은 땅에 그대로 둔다(허벅지 앞으로 α, 정강이 뒤로 β, 발목 β)
-- 다리 길이 [실측 템플릿 관절 위치]: 허벅지 Hip→Knee 3.81 · 정강이 Knee→Ankle 5.40 → β = asin(3.81·sinα / 5.40) 이면 발이 골반 바로 밑
-- 표의 "내려간 높이"는 공식이 아니라 템플릿 관절 사슬(Root→Hip→Knee→Ankle, 서기 자세 hip 4·knee −8 위에 더함)로 잰 값 [실측 10-25].
-- 이상적인 두 막대 공식은 서기 자세의 굽힘을 빼먹어 발이 0.3~0.45 떠서 버렸다. 발 앞뒤 어긋남 ≤ 0.12, 발바닥 기울기 0°
local CROUCH_TABLE = {   -- { 내려간 높이, α, β }
	{ 0.00, 0, 0.0 }, { 0.05, 4, 2.8 }, { 0.14, 8, 5.6 }, { 0.25, 12, 8.4 }, { 0.40, 16, 11.2 }, { 0.57, 20, 14.0 },
	{ 0.77, 24, 16.7 }, { 1.00, 28, 19.3 }, { 1.25, 32, 22.0 }, { 1.52, 36, 24.5 }, { 1.81, 40, 27.0 }, { 2.12, 44, 29.3 },
	{ 2.45, 48, 31.6 }, { 2.78, 52, 33.8 }, { 3.13, 56, 35.8 }, { 3.48, 60, 37.7 }, { 3.83, 64, 39.4 }, { 4.18, 68, 40.9 },
	{ 4.52, 72, 42.1 }, { 4.85, 76, 43.2 }, { 5.17, 80, 44.0 },
}
local function crouchAngles(drop, tbl)   -- tbl = 기체 모양별 웅크림 표(SHAPES.crouch, 10-26). 없으면 프로토 표
	tbl = tbl or CROUCH_TABLE
	if drop <= 0 then return 0, 0 end
	for i = 2, #tbl do
		local p0, p1 = tbl[i - 1], tbl[i]
		if drop <= p1[1] then
			local u = (drop - p0[1]) / (p1[1] - p0[1])
			return p0[2] + (p1[2] - p0[2]) * u, p0[3] + (p1[3] - p0[3]) * u
		end
	end
	local last = tbl[#tbl]
	return last[2], last[3]
end
local function sstep(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end
-- 도약(10-25 2차): ① 누르면 땅에서 CFG.JumpWindup(0.22초) 동안 JUMP_CROUCH 만큼 천천히 웅크림(힘 모으기)
--   ② 뜨는 순간부터 JUMP_EXTEND(0.2초)에 걸쳐 다리를 펴며 박참 — 발은 다리가 다 펴질 때(약 0.1초)까지 땅에 붙어 있다
--   (1차 "보이는 몸만 0.06초 웅크림"은 이미 뜬 뒤라 공중에서 다리가 발작하듯 보여 폐기 — 유저 영상 10-25)
local JUMP_CROUCH, JUMP_LEAN, JUMP_EXTEND = 2.8, 16, 0.2   -- 2.8 = 무릎 약 86° 굽힘(CROUCH_TABLE)
local WIND_HOLD_MINE, WIND_HOLD_REMOTE = 0.1, 0.3           -- 웅크림이 끝났는데 아직 안 떴을 때 버티는 시간(남의 기체는 복제 지연 감안)
-- 착지: 깊이·길이·숙임이 체공 시간에 비례(hard 0~1). 0.05초에 내려앉고 0.08초까지 버틴 뒤 천천히 일어남
local LAND_DEPTH, LAND_DEPTH_HARD = 1.4, 1.6     -- 1.4 ~ 3.0
local LAND_DUR, LAND_DUR_HARD = 0.28, 0.27       -- 0.28 ~ 0.55초
local LAND_LEAN, LAND_LEAN_HARD = 8, 6           -- 상체 숙임 8 ~ 14도

-- ================= 줌 · 두 손 사격 자세 (2026-10-25) =================
-- 오른손이 가슴 앞에서 라이플을 조준 방향으로 들고, 왼손이 탄창 앞을 받친다. 조준 높낮이·좌우를 따라가도록 매 프레임 팔 IK 로 푼다.
-- [실측] 팔이 짧다(어깨→손 최대 약 9.7)에 라이플이 길어(14.6) 정면 그대로면 왼손이 총열 덮개까지 못 닿는다(약 14 필요)
--   → 상체를 오른쪽으로 ZOOM_TWIST 만큼 틀어(왼쪽 어깨가 앞으로) 왼손을 탄창 앞에 둔다. 개머리판 끝은 가슴 앞 0.5·턱 아래(뺨 견착 모양)
-- 에디트 검증: 조준 −20~40° 에서 두 손 오차 0.00, 총구 방향 = 조준 방향. ±40~60° 끝에선 왼팔이 다 펴짐(오차 ≤ 0.19)
local ZOOM_TWIST = 25                               -- 상체를 오른쪽으로 트는 각(도). 머리는 그만큼 되돌려 정면
local ZOOM_HAND = Vector3.new(2.1, -0.4, 7.0)       -- 오른손: 가슴 가운데 기준 조준 틀에서 (오른쪽, 위, 앞)
local ZOOM_LEFT = Vector3.new(-1.2, -1.2, 0.5)      -- 왼손: 라이플 로컬(탄창 왼쪽 앞). 라이플 손잡이 (0.1,−0.5,3.29) · 탄창 Z 0~1.8 · 총열 덮개 Z −4.8~−0.6 [메시 실측]
local ZOOM_POLE_R = Vector3.new(0.7, -1, 0.4)       -- 팔꿈치가 향할 쪽(몸통 기준): 오른쪽 아래
local ZOOM_POLE_L = Vector3.new(-0.6, -1, 0.3)      -- 왼쪽 아래
-- 두 마디 팔 IK. S = 어깨 관절 틀(월드, 회전 전), a = 어깨→팔꿈치 관절, b = 팔꿈치→손(각자 쉬는 틀), 팔꿈치는 X 축으로 굽음(+ = 앞으로)
-- 돌려주는 값: 어깨 회전(Transform), 팔꿈치 각(라디안). 팔꿈치는 pole 쪽을 향한다. 못 닿으면 다 펴서 그쪽을 가리킴
local function solveArm(S, a, b, target, poleW)
	local t = S:PointToObjectSpace(target)
	local d = t.Magnitude
	local K = (d * d - a:Dot(a) - b:Dot(b)) / 2 - a.X * b.X
	local P1 = a.Y * b.Y + a.Z * b.Z
	local Q1 = a.Z * b.Y - a.Y * b.Z
	local R = math.sqrt(P1 * P1 + Q1 * Q1)
	local th = math.atan2(Q1, P1) + math.acos(math.clamp(K / R, -1, 1))
	local v = a + Vector3.new(b.X, b.Y * math.cos(th) - b.Z * math.sin(th), b.Y * math.sin(th) + b.Z * math.cos(th))
	local X1 = v.Unit
	-- 팔꿈치가 향하는 쪽 = 팔 방향 × 팔꿈치 경첩 축(X). 팔이 다 펴져도 정의된다.
	-- (10-25 버그: 예전엔 팔꿈치 위치로 잡아서, 팔이 다 펴지면 이 방향이 정의되지 않아 쏠 때마다 반동 0.6 에 왼어깨가 55~61° 씩 휙휙 돌았다 [실측])
	local hinge = Vector3.xAxis - X1 * X1.X
	local Y1 = X1:Cross(hinge).Unit
	local X2 = t.Unit
	local p = S:VectorToObjectSpace(poleW)
	local Y2 = (p - X2 * p:Dot(X2)).Unit
	local F1 = CFrame.fromMatrix(Vector3.zero, X1, Y1, X1:Cross(Y1))
	local F2 = CFrame.fromMatrix(Vector3.zero, X2, Y2, X2:Cross(Y2))
	return F2 * F1:Inverse(), th
end
local function badCF(cf) local l = cf.LookVector; return l.X ~= l.X or l.Y ~= l.Y or l.Z ~= l.Z end
-- J = 기체 관절, P = 이번 프레임 자세(Root·Waist 는 최종이어야 함), aimDir = 월드 조준 방향, kick = 반동(0~1)
-- opt(10-27 허리 사격, 없으면 줌): hand = 오른손 자리(ZoomHand 대신) · left = 왼손 자리(총 파트 로컬, LeftHand 대신)
--   · turn = 손 자리 틀만 세계 Y 축으로 돌릴 각(도, − = 오른쪽). 몸 전체를 그만큼 튼 자세라 손은 몸과 함께 돌고 총은 aimDir 그대로 [rig/hip_pose.py two_hand2]
local function twoHandPose(J, root, P, aimDir, kick, SH, opt)
	local jr, jw, sR, eR, gR, sL, eL, hL = J.Root, J.Waist, J.ShoulderR, J.ElbowR, J.Grip, J.ShoulderL, J.ElbowL, J.SaberGrip
	if not (jr and jw and sR and eR and gR and sL and eL and hL) then return nil end
	local T = root.CFrame * jr.C0 * (P.Root or CFrame.new()) * jr.C1:Inverse() * jw.C0 * (P.Waist or CFrame.new()) * jw.C1:Inverse()
	-- 가슴점·오른손 자리는 기체 모양별(10-26 SHAPES: 중장갑은 가슴이 두꺼워 손을 8.4 앞에 — 개머리판이 가슴 앞면 0.3 앞)
	local ZH = (opt and opt.hand) or (gR.Part1 and gR.Part1:GetAttribute("ZoomHand")) or (SH and SH.zoomHand) or ZOOM_HAND   -- 10-27 총별(개틀링 = 더 앞·오른쪽 [rig/gat_aim.py])
	local placeDir = (opt and opt.turn) and CFrame.Angles(0, math.rad(opt.turn), 0):VectorToWorldSpace(aimDir) or aimDir
	local A = CFrame.lookAlong(T * ((SH and SH.chest) or Vector3.new(0.1, 1.0, 0.29)), placeDir, Vector3.yAxis)        -- 가슴 가운데의 조준 틀
	local handW0 = A * Vector3.new(ZH.X, ZH.Y, -ZH.Z)                   -- 반동 없는 오른손 자리
	local handW = A * Vector3.new(ZH.X, ZH.Y, -(ZH.Z - 0.3 * kick))     -- 반동 때 손이 살짝 뒤로
	local RR0 = CFrame.lookAlong(Vector3.zero, aimDir, Vector3.yAxis)
	local RR = RR0 * CFrame.Angles(math.rad(3 * kick), 0, 0)   -- 라이플 방향(반동 때 총구가 살짝 들림)
	-- 오른팔: 손을 handW 로
	local SR = T * sR.C0
	local aR = (sR.C1:Inverse() * eR.C0).Position
	local bR = (eR.C1:Inverse() * CFrame.new(gR.C0.Position)).Position
	local RsR, thR = solveArm(SR, aR, bR, handW, T:VectorToWorldSpace(ZOOM_POLE_R))
	local ER = CFrame.fromAxisAngle(Vector3.xAxis, thR)
	local base = SR * RsR * sR.C1:Inverse() * eR.C0 * ER * eR.C1:Inverse() * gR.C0
	-- 손목: 라이플 방향만 조준 방향으로(위치는 손이 정함)
	-- 10-26 23:2x: 관절 틀(= 총 규약 틀, LookVector = 총구)을 조준 방향으로. 예전 식(… * RR * gR.C1.Rotation)은 총 "파트" 틀을 조준 방향으로 돌려
	--   C1 에 회전이 있는 총(AELLO 라이플: 메시가 총구 −Y 로 들어옴)은 총구가 66° 아래를 봤다 [실측]. 프로토·저격총·중장갑은 C1 회전 0 이라 두 식이 같음
	local G = base.Rotation:Inverse() * RR
	local rifleW = base * G * gR.C1:Inverse()
	-- 왼팔: 손을 "반동 없는" 라이플의 ZOOM_LEFT 로. 받치는 손은 반동을 흡수하고 라이플만 손 안에서 살짝 튄다
	-- (10-25: 반동 따라가게 했더니 쏠 때마다 왼팔꿈치가 17~20° 씩 초당 8번 펌프질 [실측])
	local rifle0 = CFrame.new(handW0) * RR0 * gR.C1:Inverse()
	local SL = T * sL.C0
	local aL = (sL.C1:Inverse() * eL.C0).Position
	local bL = (eL.C1:Inverse() * CFrame.new(hL.C0.Position)).Position
	-- 왼손 자리는 총마다(10-25 저격총): 총 파트 속성 LeftHand(총 로컬). 없으면 라이플 값 ZOOM_LEFT. 총 파트 = Grip 관절의 Part1
	local gunPart = gR.Part1
	local leftL = (opt and opt.left) or (gunPart and gunPart:GetAttribute("LeftHand")) or ZOOM_LEFT
	local RsL, thL = solveArm(SL, aL, bL, rifle0 * leftL, T:VectorToWorldSpace(ZOOM_POLE_L))
	local out = { ShoulderR = RsR, ElbowR = ER, Grip = G, ShoulderL = RsL, ElbowL = CFrame.fromAxisAngle(Vector3.xAxis, thL) }
	for _, cf in pairs(out) do if badCF(cf) then return nil end end   -- 겹친 벡터 등으로 NaN 이 나면 이번 프레임은 버림
	return out
end
-- ================= 10-27 FELSEN 열선 도끼 두 손 3연격 (유저 18:33 "무겁다는 컨셉이니 두 손으로 잡고 때리게") =================
-- 흐름은 빔사벨 그대로(1타 내려베기 · 2타 우→좌 가로베기 · 3타 찌르기), 키 자세 = SHAPES.Heavy.combo2h(자동 생성 rig/axe2h_export.py).
-- 왼팔·몸통 = 키 사이 회전 보간(blendPose) · 오른손 = 매 프레임 도끼 막대 점(막대 로컬 y = rh, 왼손 위)에 팔 IK(twoHandPose 와 같은 solveArm).
--   겨눔(어깨에 기댐) ↔ 두 손 구간은 '손이 갈 자리'를 빈손 자리 → 막대 점으로 바깥 둘레로 옮기며 IK 하고 빈손 관절과 섞음
--   (관절 각만 섞으면 오른팔이 옆 스커트를 지남 186칸 → 50칸 [rig/axe2h_anim.py 궤적 검사 1/40초]).
-- 키끼리 회전 보간은 가장 짧은 회전이라 도끼가 몸통을 지나던 구간(3타 당김 3,979칸)엔 경유 키 V1 · V2 · V2B · V3 → 구간 전체 최대 113칸(2타 마무리 아래팔 ↔ 가슴)
local function easeK(kind, a)
	if kind == "smooth" then return a * a * (3 - 2 * a) end
	if kind == "in" then return a * a end
	if kind == "out" then return math.sin(a * math.pi / 2) end
	return a
end
-- 돌려주는 값: (섞는 비율 1, 왼팔·몸통 자세, 두 손 정보 { w = 오른손 무게, rh, pole })
local function comboPose(C, kind, e, Rcur)
	local seq = C.seq[kind]
	if not seq then return nil end
	local t0 = 0
	for i, sg in ipairs(seq) do
		local t1 = sg[1]
		if e <= t1 or i == #seq then
			local a = math.clamp((e - t0) / math.max(1e-3, t1 - t0), 0, 1)
			local k = easeK(sg[4], a)
			local DA, DB = C.keys[sg[2]], C.keys[sg[3]]
			local JA = (sg[2] == "R") and Rcur or DA.J
			local JB = (sg[3] == "R") and Rcur or DB.J
			local w = sg[5] + (sg[6] - sg[5]) * (a * a * (3 - 2 * a))
			return 1, blendPose(JA, JB, k), { w = w, rh = DA.rh + (DB.rh - DA.rh) * k, pole = DA.poleR:Lerp(DB.poleR, k) }
		end
		t0 = t1
	end
	return nil
end
-- 오른팔 IK: P(왼팔·몸통 최종)로 도끼 막대 틀을 FK → 막대 로컬 (0, rh, 0) 에 오른손(Grip 관절 점). th = comboPose 의 두 손 정보
local function axeRightHand(J, root, P, th)
	local jr, jw, sR, eR, gR, sL, eL, hL = J.Root, J.Waist, J.ShoulderR, J.ElbowR, J.Grip, J.ShoulderL, J.ElbowL, J.SaberGrip
	if not (jr and jw and sR and eR and gR and sL and eL and hL) then return nil end
	local I = CFrame.new()
	local T = root.CFrame * jr.C0 * (P.Root or I) * jr.C1:Inverse() * jw.C0 * (P.Waist or I) * jw.C1:Inverse()
	local LA = T * sL.C0 * (P.ShoulderL or I) * sL.C1:Inverse() * eL.C0 * (P.ElbowL or I) * eL.C1:Inverse()
	local rod = LA * hL.C0 * (P.SaberGrip or I) * hL.C1:Inverse()
	local tgt = rod * Vector3.new(0, th.rh, 0)
	local SR = T * sR.C0
	local aR = (sR.C1:Inverse() * eR.C0).Position
	local bR = (eR.C1:Inverse() * CFrame.new(gR.C0.Position)).Position
	local target, k = tgt, 1
	if th.w < 0.999 then
		local free = (SR * (P.ShoulderR or I) * sR.C1:Inverse() * eR.C0 * (P.ElbowR or I) * eR.C1:Inverse() * gR.C0).Position
		target = free + (tgt - free) * th.w + root.CFrame:VectorToWorldSpace(Vector3.new(2.5, 1.5, -2.0)) * math.sin(math.pi * th.w)
		k = th.w * th.w * (3 - 2 * th.w)
	end
	local Rs, thR = solveArm(SR, aR, bR, target, T:VectorToWorldSpace(th.pole))
	local out = { ShoulderR = (P.ShoulderR or I):Lerp(Rs, k), ElbowR = (P.ElbowR or I):Lerp(CFrame.fromAxisAngle(Vector3.xAxis, thR), k) }
	for _, cf in pairs(out) do if badCF(cf) then return nil end end
	return out
end
local SLASH_TRAIL = { slash1 = { 0.05, 0.34 }, slash2 = { 0.04, 0.28 }, slash3 = { 0.09, 0.30 } }
-- 라이플 등 수납 (2026-10-25). 등 라이플 RifleStowed = 백팩 기준 대각선(개머리판 오른쪽 위), 걷기 다리·팔·칼자루와 안 겹침(계산 확인)
-- RIFLE_STOW = 관절 탐색: 오른손이 등 라이플 손잡이에 닿고(오차 0), 손목(Grip)을 돌리면 손 라이플이 등 라이플과 정확히 겹친다.
-- 낮게 든 자세 → 이 자세로 곧장 옮겨도 라이플·아래팔이 머리·백팩·칼자루를 안 지난다(계산 확인)
-- ↑ 2026-10-25 01:50 자리 변경: 등 대각선은 오른쪽 배출구를 막아 기각 → H = 백팩 등판 위쪽 가로(개머리판 오른쪽, 고정 띠 2개)
-- RIFLE_STOW 재계산(손 오차 0): 팔꿈치를 어깨 위로 들고 아래팔을 등 뒤로 내려 오른쪽 등 손잡이를 잡는다.
-- 낮게 든 자세에서 곧장 가면 라이플이 골반·몸통을 뚫어서 RIFLE_MID(오른쪽 아래로 휘두름, 총구 땅 위 1.3)를 거친다.
-- 경로 검사는 상자 근사라 팔이 골반·백팩 옆을 스치는 구간이 잡힘 — 플레이로 확인 필요
local RIFLE_STOW = { ShoulderR = E(-16.2, -166.8, 163.7), ElbowR = E(116.2), Grip = E(-5.4, 106.9, 135.0) }
local RIFLE_MID = { ShoulderR = E(-30.9, -53.0, 17.0), ElbowR = E(12.4), Grip = E(71.1, -5.1, 132.6) }
-- 재장전 동작 (2026-10-25). 관절 탐색: 오른손이 라이플을 가슴 앞 오른쪽 아래로 들어 탄창이 왼쪽 아래를 보게 기울이고,
-- 왼손이 탄창 바닥을 쥠(오차 0.11) → 2.5 아래로 뽑음(0.19). 들기·뽑기 경로에서 라이플·왼팔이 몸·라이플을 안 뚫음(계산 확인)
local RELOAD_R = { ShoulderR = E(-17.8, 29.4, 3.7), ElbowR = E(111.5), Grip = E(-20.5, -8.2, -34.1) }
local RELOAD_LA = { ShoulderL = E(10.4, -44.7, -2.2), ElbowL = E(56.6) }   -- 탄창 바닥을 쥠
local RELOAD_LD = { ShoulderL = E(8.8, -37.9, 1.3), ElbowL = E(34.6) }     -- 뽑아 내림
local RELOAD_LR = { ShoulderL = E(-10, 0, -8), ElbowL = E(20) }            -- 손 뗌

-- ================= 기체 모양별 상수 (10-26 중장갑 r2) =================
-- 위 동작표(관절 각)는 프로토 몸(팔 길이·가슴 두께·스커트 없음) 기준이다. 기체 속성 MechType 으로 묶음을 고른다(표에 없으면 프로토 = 덮어쓰기 없음).
-- 중장갑 값은 HeavyTemplate 관절로 잰 것 [실측 10-26]:
--   손이 어딘가에 닿아야 하는 자세(칼 잡기·허리 뒤 라이플·장전·두 손 사격) = 팔 IK(solveArm 과 같은 식)로 풀어 손 오차 0.
--   몸을 뚫던 자세(겨눔·마무리·2타 감기·3타 당김·주먹 당김) = 확정 복셀 모델을 그 자세로 놓고 겹침을 세며 원래 각에서 최소한만 비킴
--   (작업 공간 rig/voxcheck.py · opt.py — 파트 CFrame 은 Studio FK 와 오차 4e-6 으로 같음). 나머지(뽑아 올림·내려벰·2타 가로·3타 찌름 등)는 프로토 그대로 겹침 0.
-- 쉬는 자세: 템플릿 팔은 곧게 내린 것이 Transform 0(10-26 관절 C0/C1 에 STANCE 팔 벌림을 되돌려 넣음 — 프로토 각도가 같은 뜻이 되게).
--   대신 팔이 八 스커트에 닿으므로 평상·빈손 자세에만 armOut 만큼 바깥으로 벌린다(조준 자세는 0 — 총구 방향이 그대로)
local function CF(...) return CFrame.new(0, 0, 0, ...) end
local Q_PROTO = { G = SABER_G, W = SABER_W, S = SABER_S, F = SABER_F, R = SABER_R, PW = PUNCH_W, PS = PUNCH_S,
	S2A = SLASH2_A, S2B = SLASH2_B, S2C = SLASH2_C, S3A = SLASH3_A, S3B = SLASH3_B, S3C = SLASH3_C }
local function withQ(over)
	local q = {}
	for k, v in pairs(Q_PROTO) do q[k] = v end
	for k, v in pairs(over) do q[k] = v end
	return q
end
local SHAPE_PROTO = { Q = Q_PROTO, crouch = CROUCH_TABLE, legK = 1, armOut = 0, rifleStow = RIFLE_STOW, rifleMid = RIFLE_MID }
local SHAPES = {
	Heavy = {   -- 대표 기체 중장갑 r2 (키 28.5 · 팔 어깨→팔꿈치 4.8 · 팔꿈치→주먹 7.2 · 허벅지 5.0 · 정강이 7.0)
		-- 웅크림 표(내려간 높이, α, β): 같은 식으로 프로토 표를 다시 재면 원래 표와 맞음(α 40° 까지 ±0.01, 80° 에서 β 2° 차) [실측]
		crouch = {
			{ 0.00, 0, 0.0 }, { 0.09, 4, 2.8 }, { 0.23, 8, 5.7 }, { 0.40, 12, 8.5 }, { 0.61, 16, 11.3 }, { 0.86, 20, 14.0 },
			{ 1.15, 24, 16.7 }, { 1.46, 28, 19.4 }, { 1.81, 32, 21.9 }, { 2.18, 36, 24.4 }, { 2.58, 40, 26.8 }, { 2.99, 44, 29.1 },
			{ 3.42, 48, 31.2 }, { 3.86, 52, 33.3 }, { 4.31, 56, 35.1 }, { 4.76, 60, 36.8 }, { 5.20, 64, 38.2 }, { 5.64, 68, 39.4 },
			{ 6.06, 72, 40.4 }, { 6.47, 76, 41.1 }, { 6.86, 80, 41.5 },
		},
		legK = 1.38,      -- 같은 무릎 굽힘에 몸이 내려가는 양(무릎 52° = 프로토 2.78 · 중장갑 3.86). 웅크림·착지·사출·걸음 출렁임 깊이에 곱함
		armOut = 11,      -- 평상·빈손 팔 벌림(도) — STANCE 팔 벌림과 같은 값. 0 이면 아래팔이 옆 스커트와 겹침
		rideDrop = 2.6,   -- 땅굴 사출 중 웅크림(프로토 1.6, × legK). 1.6 이면 경사 시작(경로 77)에서 머리·백팩이 땅굴 천장 끝을 스침 [경로 스윕 실측 10-26]
		chest = Vector3.new(0, 1.55, 1.0),       -- 두 손 사격 가슴점(몸통 로컬 = 어깨 높이 몸 가운데)
		zoomHand = Vector3.new(2.6, -0.5, 8.4),  -- 두 손 사격 오른손 자리. 조준 −20~60° 두 손 오차 0.00 [실측]
		Q = withQ({
			-- 10-27 열선 도끼: 등 왼쪽 막대(Holster.AxeStowed) 손잡이를 잡음 — 잡는 순간 손 막대 = 등 막대(위치·방향 오차 0)라 바꿔 보여도 안 튐.
			--   팔 IK(손 오차 0, 팔꿈치 79.9°) · 손목 = 막대 축 기울기 15° + 축 둘레 돌림 74°(막대 단면이 거의 대칭이라 돌림은 안 보임).
			--   뽑아 올림(G→W) 동안 도끼가 몸을 지나는 칸: 어깨 장갑 최대 60(0.25 칸, 0.07초) [복셀 실측 rig/axe_fit.py]. 옛 칼자루 잡기 = ServerStorage._FelsenAxe_before_20261027
			G = { Root = CFrame.new(0, -0.2, 0), Waist = E(4, 15), Neck = E(0, -10),
				ShoulderL = CF(0.94929, -0.14170, -0.28064, -0.15701, -0.98705, -0.03272, -0.27237, 0.07512, -0.95926), ElbowL = E(79.92),
				SaberGrip = CF(0.27237, -0.96165, 0.03221, 0.93130, 0.25506, -0.26005, 0.24187, 0.10083, 0.96506) },
			-- 10-27 20:xx 겨눔 = 어깨에 기댐(유저 18:33). 옛 = E(5.2, −5.3, −11.3) · E(83.5) · E(−38.1)(몸 앞 · 날 아래 → 등 뒤 카메라에서 날 0 px)
			--   왼손 (−8, 19, −7.5) · 막대 위 55° · 날 바깥 — 도끼·팔 겹침 0 · 막대 ↔ 왼 어깨 장갑 0.41 · 날 보임 1,507 px [rig/axe2h.py GUARD · axe_guard_sheet.py]
			R = { ShoulderL = CF(0.88424, 0.46103, 0.07469, -0.44913, 0.88325, -0.1347, -0.12807, 0.08556, 0.98807), ElbowL = CF(1, 0, 0, 0, -0.0155, -0.99988, 0, 0.99988, -0.0155),
				SaberGrip = CF(-0.17559, 0.81026, 0.55915, -0.86882, 0.13955, -0.47506, -0.46295, -0.56922, 0.67946) },
			-- 10-27 23:2x 부스트 겨눔(유저 "원래 쓰던 앞으로 든 자세는 히트호크 들고 부스트 켰을 때 포즈로") = 옛 겨눔에 어깨만 바깥 7.7° 더
			--   (옛 값 그대로면 숙인 부스트 몸에서 아래팔 ↔ 옆 스커트 96칸 → 0, 어깨 ↔ 앞 섞는 길 0 [rig/axe2h_heavy.py])
			RB = { ShoulderL = E(5.2, -5.3, -19), ElbowL = E(83.5), SaberGrip = E(-38.1) },
			F = { Root = CFrame.new(0, -1.2, 0), Waist = E(-14, -28), Neck = E(6, 16), ShoulderL = E(48, 14, 2), ElbowL = E(12), SaberGrip = E(-32) },    -- 마무리: 가슴·스커트(내려베기→마무리→겨눔·2타 감기 섞는 길까지 검사)
			S2A = { Root = CFrame.new(0, -0.6, 0), Waist = E(-4, -30), Neck = E(0, 18), ShoulderL = E(18.9, -10.8, -6.6), ElbowL = E(91.0), SaberGrip = E(-97.7) },   -- 2타 감기: 가슴
			S3A = { Root = CFrame.new(0, -0.8, 0), Waist = E(-4, 22), Neck = E(0, -14), ShoulderL = E(-46, -16, -42), ElbowL = E(129), SaberGrip = E(-65) },          -- 3타 당김: 어깨 장갑
			PW = { Root = CFrame.new(0, -0.3, 0), Waist = E(2, 28), Neck = E(0, -16), ShoulderL = E(25, 0, -6), ElbowL = E(95) },                                   -- 주먹 당김: 어깨 장갑
		}),
		combo2h = {   -- 10-27 23:2x 도끼 두 손 3연격 "육중하게"(자동 생성 rig/axe2h_heavy.py export_lua). keys.J = 관절 Transform · rh = 오른손 막대 y · poleR = 오른 팔꿈치 쪽(몸통 로컬) · seq = { 끝 시각, 시작 키, 끝 키, 보간, 오른손 무게 시작, 끝 } · …d = 마무리 처짐(골반 0.5↓ 허리 5°) · RV1/RV2 = 겨눔으로 돌아가는 길 경유(한 손)
			--   20:xx 판 = ServerStorage._AxeHeavy_before_20261027.MechClient. 구간 검사(1/20초, 키 사이 포함) 최대 1타 48 · 2타 108 · 3타 85칸 — 옛 판은 1·2타에서 멈추고 돌아갈 때 3,701 · 1,773칸(도끼가 몸통을 지남)
			keys = {
				F1d = { J = { Root = CFrame.new(0, -1.7, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.95106, -0.19025, 0.24351, 0, 0.78801, 0.61566, -0.30902, -0.58553, 0.74944), Neck = CF(0.96126, -0.04786, -0.27145, 0, 0.98481, -0.17365, 0.27564, 0.16692, 0.94666), ShoulderL = CF(0.51442, -0.4297, -0.74212, -0.85736, -0.23986, -0.45542, 0.01769, 0.87053, -0.49179), ElbowL = CF(1, 0, 0, 0, 0.8471, -0.53143, 0, 0.53143, 0.8471), SaberGrip = CF(0.28148, -0.66768, -0.68918, -0.56997, -0.69413, 0.43968, -0.77195, 0.26905, -0.57594) }, rh = -1.500, poleR = Vector3.new(1.00, 0.00, 0.30) },
				RV1 = { J = { Root = CF(1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(1, 0, 0, 0, 0.99863, 0.05234, 0, -0.05234, 0.99863), Neck = CF(1, 0, 0, 0, 1, 0, 0, 0, 1), ShoulderL = CF(0.78163, 0.62197, -0.04708, -0.55461, 0.65846, -0.50876, -0.28543, 0.42377, 0.85962), ElbowL = CF(1, 0, 0, 0, 0.45888, -0.8885, 0, 0.8885, 0.45888), SaberGrip = CF(0.25601, 0.61114, 0.74898, -0.96476, 0.21023, 0.15823, -0.06076, -0.76309, 0.64343) }, rh = -1.500, poleR = Vector3.new(0.60, -1.00, 0.30) },
				RV2 = { J = { Root = CF(1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(1, 0, 0, 0, 0.99863, 0.05234, 0, -0.05234, 0.99863), Neck = CF(1, 0, 0, 0, 1, 0, 0, 0, 1), ShoulderL = CF(0.8515, 0.48986, -0.18703, -0.52284, 0.76612, -0.37376, -0.0398, 0.41604, 0.90847), ElbowL = CF(1, 0, 0, 0, 0.18863, -0.98205, 0, 0.98205, 0.18863), SaberGrip = CF(0.1258, 0.57854, 0.80589, -0.92041, -0.23504, 0.31241, 0.37016, -0.78105, 0.50293) }, rh = -1.500, poleR = Vector3.new(0.60, -1.00, 0.30) },
				S1 = { J = { Root = CFrame.new(0, -1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.94832, -0.13158, 0.28873, 0, 0.90996, 0.41469, -0.3173, -0.39326, 0.86294), Neck = CF(0.95106, -0.04301, -0.30601, 0, 0.99027, -0.13917, 0.30902, 0.13236, 0.9418), ShoulderL = CF(-0.13099, -0.04124, -0.99053, -0.89004, -0.43517, 0.13582, -0.43665, 0.8994, 0.0203), ElbowL = CF(1, 0, 0, 0, 0.42863, -0.90348, 0, 0.90348, 0.42863), SaberGrip = CF(-0.79011, -0.52488, -0.3166, -0.54724, 0.37133, 0.7501, -0.27615, 0.76591, -0.58062) }, rh = -1.250, poleR = Vector3.new(0.00, -1.00, 0.60) },
				S2A = { J = { Root = CFrame.new(0, -0.6, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.86603, 0.02181, -0.49952, 0, 0.99905, 0.04362, 0.5, -0.03778, 0.8652), Neck = CF(0.90631, 0, 0.42262, 0, 1, 0, -0.42262, 0, 0.90631), ShoulderL = CF(0.47641, 0.04945, -0.87783, -0.79402, 0.45297, -0.40541, 0.37759, 0.89015, 0.25506), ElbowL = CF(1, 0, 0, 0, 0.79245, -0.60994, 0, 0.60994, 0.79245), SaberGrip = CF(0.81813, 0.31421, -0.4816, -0.17479, 0.93377, 0.31229, 0.54782, -0.17131, 0.81887) }, rh = -1.500, poleR = Vector3.new(0.40, -0.30, -1.00) },
				S2B = { J = { Root = CFrame.new(0, -0.8, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.99027, -0.02656, 0.13662, 0, 0.98163, 0.19081, -0.13917, -0.18895, 0.97207), Neck = CF(0.95106, 0, -0.30902, 0, 1, 0, 0.30902, 0, 0.95106), ShoulderL = CF(0.00952, 0.05249, -0.99858, -0.95882, 0.28394, 0.00578, 0.28384, 0.9574, 0.05303), ElbowL = CF(1, 0, 0, 0, 0.5407, -0.84122, 0, 0.84122, 0.5407), SaberGrip = CF(0.68154, 0.07591, 0.72783, -0.3095, -0.87136, 0.3807, 0.6631, -0.48473, -0.57038) }, rh = -2.500, poleR = Vector3.new(0.40, -0.30, -1.00) },
				S2Cd = { J = { Root = CFrame.new(0, -1.3, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.71934, -0.31537, 0.61895, 0, 0.89101, 0.45399, -0.69466, -0.32657, 0.64094), Neck = CF(0.86603, 0, -0.5, 0, 1, 0, 0.5, 0, 0.86603), ShoulderL = CF(-0.16568, -0.35496, -0.92009, -0.81704, -0.47307, 0.32963, -0.55226, 0.80636, -0.21164), ElbowL = CF(1, 0, 0, 0, 0.83522, -0.54991, 0, 0.54991, 0.83522), SaberGrip = CF(0.97272, 0.22054, -0.07199, 0.07924, -0.60747, -0.79038, -0.21804, 0.76312, -0.60837) }, rh = -0.500, poleR = Vector3.new(0.40, -0.30, -1.00) },
				S3A = { J = { Root = CFrame.new(0, -0.8, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.61566, 0.04811, 0.78654, 0, 0.99813, -0.06105, -0.78801, 0.03759, 0.61451), Neck = CF(0.81915, 0, -0.57358, 0, 1, 0, 0.57358, 0, 0.81915), ShoulderL = CF(0.36972, 0.65704, -0.65697, -0.6162, 0.70259, 0.3559, 0.69542, 0.27324, 0.66463), ElbowL = CF(1, 0, 0, 0, -0.00871, -0.99996, 0, 0.99996, -0.00871), SaberGrip = CF(0.61218, 0.78849, 0.05931, -0.52271, 0.34727, 0.77858, 0.5933, -0.50763, 0.62474) }, rh = 0.500, poleR = Vector3.new(0.40, -0.30, -1.00) },
				S3B = { J = { Root = CFrame.new(0, -1.4, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.92718, -0.09063, 0.36348, 0, 0.9703, 0.24192, -0.37461, -0.22431, 0.89964), Neck = CF(0.92718, 0, -0.37461, 0, 1, 0, 0.37461, 0, 0.92718), ShoulderL = CF(-0.11415, 0.05063, -0.99217, -0.91771, -0.38788, 0.08579, -0.3805, 0.92032, 0.09075), ElbowL = CF(1, 0, 0, 0, 0.36493, -0.93103, 0, 0.93103, 0.36493), SaberGrip = CF(0.95632, -0.17282, -0.23578, 0.07135, -0.64418, 0.76154, -0.2835, -0.74509, -0.60371) }, rh = -1.500, poleR = Vector3.new(1.00, -0.60, 0.00) },
				S3Cd = { J = { Root = CFrame.new(0, -1.7, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.96126, -0.07366, 0.26561, 0, 0.96363, 0.26724, -0.27564, -0.25689, 0.9263), Neck = CF(0.93969, 0, -0.34202, 0, 1, 0, 0.34202, 0, 0.93969), ShoulderL = CF(-0.05027, 0.27988, -0.95872, -0.98458, -0.17493, 0.00055, -0.16755, 0.94396, 0.28436), ElbowL = CF(1, 0, 0, 0, 0.24818, -0.96872, 0, 0.96872, 0.24818), SaberGrip = CF(0.9955, -0.05525, -0.077, 0.03072, -0.58043, 0.81373, -0.08965, -0.81243, -0.57612) }, rh = -1.500, poleR = Vector3.new(0.40, -0.30, -1.00) },
				V1 = { J = { Root = CFrame.new(0, -0.65, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.90814, -0.04558, 0.41617, 0, 0.99406, 0.10887, -0.41866, -0.09887, 0.90275), Neck = CF(0.94552, -0.00568, -0.32552, 0, 0.99985, -0.01745, 0.32557, 0.0165, 0.94537), ShoulderL = CF(-0.15236, 0.0623, -0.98636, -0.84786, -0.52108, 0.09805, -0.50786, 0.85123, 0.13221), ElbowL = CF(1, 0, 0, 0, 0.31646, -0.94861, 0, 0.94861, 0.31646), SaberGrip = CF(-0.82589, -0.55482, -0.10038, -0.53902, 0.82917, -0.14813, 0.16541, -0.06823, -0.98386) }, rh = -2.375, poleR = Vector3.new(1.00, 0.00, 0.30) },
				V2 = { J = { Root = CFrame.new(0, -0.9, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.99452, 0.03187, -0.09955, 0, 0.9524, 0.30486, 0.10453, -0.30319, 0.94718), Neck = CF(0.99692, 0.00684, 0.07816, 0, 0.99619, -0.08716, -0.07846, 0.08689, 0.99312), ShoulderL = CF(0.42581, -0.03939, -0.90395, -0.89933, 0.09141, -0.42762, 0.09947, 0.99503, 0.0035), ElbowL = CF(1, 0, 0, 0, 0.76142, -0.64826, 0, 0.64826, 0.76142), SaberGrip = CF(-0.63898, 0.75832, 0.12903, -0.44719, -0.50269, 0.73981, 0.62587, 0.41503, 0.66033) }, rh = -0.500, poleR = Vector3.new(0.40, -0.30, -1.00) },
				V2B = { J = { Root = CFrame.new(0, -0.7, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.98163, 0.02243, -0.18949, 0, 0.99307, 0.11754, 0.19081, -0.11538, 0.97482), Neck = CF(0.99813, 0, 0.06105, 0, 1, 0, -0.06105, 0, 0.99813), ShoulderL = CF(0.4688, 0.18597, -0.86351, -0.78133, 0.54329, -0.30718, 0.412, 0.81869, 0.4), ElbowL = CF(1, 0, 0, 0, 0.51389, -0.85786, 0, 0.85786, 0.51389), SaberGrip = CF(0.54173, 0.78858, 0.29097, -0.63691, 0.15921, 0.75432, 0.54852, -0.59396, 0.58851) }, rh = -1.000, poleR = Vector3.new(1.00, -0.60, 0.00) },
				V3 = { J = { Root = CFrame.new(0, -0.8, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.66913, -0.30522, 0.67757, 0, 0.91176, 0.41072, -0.74314, -0.27482, 0.61009), Neck = CF(0.84339, 0, -0.5373, 0, 1, 0, 0.5373, 0, 0.84339), ShoulderL = CF(-0.10301, 0.11335, -0.9882, -0.93353, -0.35398, 0.05671, -0.34337, 0.92836, 0.14228), ElbowL = CF(1, 0, 0, 0, 0.27099, -0.96258, 0, 0.96258, 0.27099), SaberGrip = CF(0.86476, -0.17764, 0.46971, -0.0732, -0.96994, -0.23206, 0.49682, 0.16629, -0.85177) }, rh = -1.000, poleR = Vector3.new(0.60, -1.00, -0.40) },
				W1 = { J = { Root = CFrame.new(0, -0.3, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1), Waist = CF(0.85717, 0.10708, 0.50378, 0, 0.97815, -0.20791, -0.51504, 0.17822, 0.83844), Neck = CF(0.93969, 0.03575, -0.34015, 0, 0.99452, 0.10453, 0.34202, -0.09822, 0.93454), ShoulderL = CF(-0.18447, 0.18787, -0.96472, -0.76673, -0.6416, 0.02166, -0.61489, 0.74367, 0.2624), ElbowL = CF(1, 0, 0, 0, 0.30257, -0.95313, 0, 0.95313, 0.30257), SaberGrip = CF(-0.78842, -0.44952, 0.41991, -0.59973, 0.40987, -0.68727, 0.13683, -0.79368, -0.59274) }, rh = -2.500, poleR = Vector3.new(0.40, -0.30, -1.00) },
				R = { rh = -1.500, poleR = Vector3.new(0.60, -1.00, 0.30) },   -- 겨눔: 관절은 Rcur(그 프레임 몸통 + 겨눔 왼팔)
			},
			seq = {
				slash1 = { { 0.42, "R", "W1", "smooth", 0, 1 }, { 0.50, "W1", "W1", "lin", 1, 1 }, { 0.58, "W1", "V1", "in", 1, 1 }, { 0.64, "V1", "S1", "lin", 1, 1 }, { 0.78, "S1", "F1d", "out", 1, 1 }, { 0.90, "F1d", "F1d", "lin", 1, 1 }, { 1.12, "F1d", "RV1", "smooth", 1, 0 }, { 1.40, "RV1", "R", "smooth", 0, 0 } },
				slash2 = { { 0.20, "F1d", "V2", "smooth", 1, 1 }, { 0.40, "V2", "S2A", "smooth", 1, 1 }, { 0.46, "S2A", "S2A", "lin", 1, 1 }, { 0.53, "S2A", "V2B", "in", 1, 1 }, { 0.58, "V2B", "S2B", "lin", 1, 1 }, { 0.72, "S2B", "S2Cd", "out", 1, 1 }, { 0.82, "S2Cd", "S2Cd", "lin", 1, 1 }, { 1.04, "S2Cd", "RV2", "smooth", 1, 0 }, { 1.32, "RV2", "R", "smooth", 0, 0 } },
				slash3 = { { 0.20, "S2Cd", "V3", "smooth", 1, 1 }, { 0.40, "V3", "S3A", "smooth", 1, 1 }, { 0.48, "S3A", "S3A", "lin", 1, 1 }, { 0.58, "S3A", "S3B", "in", 1, 1 }, { 0.82, "S3B", "S3Cd", "out", 1, 1 }, { 1.37, "S3Cd", "R", "smooth", 1, 0 } },
			},
		},
		-- 허리 뒤 라이플(몸통에 묶음) 손잡이를 잡음: 팔꿈치 오른쪽 뒤, 손 오차 0
		rifleStow = { ShoulderR = CF(0.77251, -0.35405, 0.52713, -0.45199, 0.27648, 0.84809, -0.44601, -0.89342, 0.05355), ElbowR = E(89.8),
			Grip = CF(0.44601, -0.45199, 0.77251, 0.89359, 0.27378, -0.35573, -0.05072, 0.84897, 0.52601) },
		rifleMid = { ShoulderR = E(-12, 0, 22), ElbowR = E(30), Grip = CFrame.new() },   -- 옆으로 내림(총구 땅 위 1.8, 스커트 바깥)
		-- 경유 자세: 수납 자리에서 오른쪽 5·뒤 3(옆 스커트 뒤). 옆 → 뒤로 곧장 가면 아래팔이 옆 스커트를 지나감(가는 길 최대 973칸 → 52) [복셀 실측]
		rifleVia = { ShoulderR = CF(0.74519, -0.60285, 0.28506, -0.27939, 0.10590, 0.95432, -0.60550, -0.79080, -0.08951), ElbowR = E(63.1),
			Grip = CF(0.60550, -0.27939, 0.74519, 0.66457, -0.33766, -0.66658, 0.43786, 0.89885, -0.01878) },
		-- 장전: 프로토 동작(가슴 앞 비스듬히·탄창 왼쪽 아래)을 큰 가슴 앞으로 옮김. 왼손 = 프로토와 같은 라이플 로컬 점(탄창 바닥 / 2.5 아래)
		reloadR = { ShoulderR = CF(0.60915, -0.10111, 0.78658, 0.60915, 0.69475, -0.38243, -0.50781, 0.71211, 0.48480), ElbowR = E(57.9),
			Grip = CF(0.33256, 0.93946, 0.08253, -0.88524, 0.34114, -0.31618, -0.32519, 0.03209, 0.94510) },
		reloadLA = { ShoulderL = CF(0.79836, -0.12225, -0.58964, -0.32739, 0.73370, -0.59540, 0.50541, 0.66838, 0.54573), ElbowL = E(34.6) },
		reloadLD = { ShoulderL = CF(0.79605, -0.05587, -0.60265, -0.32433, 0.80130, -0.50271, 0.51099, 0.59564, 0.61976), ElbowL = E(25.4) },
		reloadLR = { ShoulderL = E(-10, 0, -19), ElbowL = E(20) },
		-- 어깨 장갑: 앞뒤로 든 각은 팔과 같이(어깨 관절점), 옆으로 든 각(z0 넘는 만큼)은 장갑 안쪽 위 모서리 경첩으로 들어 올림.
		--   전부 따라가면 옆으로 들 때 장갑이 가슴을 파고들고(2타 2347칸), 안 따라가면 조준 때 팔이 장갑을 뚫음(+600) [복셀 실측]
		pad = { hingeX = 1.3, hingeY = 3.2, z0 = 15 },
		-- 스커트(위 경첩): 허벅지가 앞으로 든 각의 front 배(앞 스커트) / side 배 + 바깥 sideOut 배(옆 스커트). 안 따라가면 웅크림 때 앞 스커트 250칸 겹침
		-- 10-30 sideZ = 허벅지를 옆으로 든 각(엉덩이 Z)의 sideZ 배로 옆 스커트도 옆으로 듦(FALCO 날아 옆차기 — 안 따라가면 왼 옆 스커트가 허벅지에 박힘 [에디트 FK]).
		--   이때까지 엉덩이를 옆으로 드는 자세가 없어서 다른 동작은 그대로
		skirt = { front = 0.5, side = 0.5, sideOut = 0.15, sideZ = 0.8 },
	},
}
-- 10-26 23:1x LF-01 AELLO(MechType "Aero" — 리메이크 템플릿, 중장갑과 같은 규약: 팔 곧게 = Transform 0 · 어깨 장갑 · 스커트 4장).
-- 1차: 손이 어딘가에 닿아야 하는 자세(칼 잡기·허리 뒤 라이플·장전·겨눔 등)는 중장갑 값을 빌려 씀(칼자루·라이플 자리를 중장갑과 같은 곳에 둠 —
--   유저 결정 "안 A"). 팔 길이가 달라(AELLO 어깨→팔꿈치 4.4 · 팔꿈치→주먹 5.9 vs 중장갑 4.8 · 7.2) 손이 조금 어긋날 수 있음 → AELLO 로 다시 푸는 건 다음 단계.
-- 몸 크기 값만 새로 [실측 AeroTemplate 관절]: 웅크림 표(허벅지 6.21 · 정강이 7.80, 중장갑과 같은 사슬 측정 — 발 앞뒤 어긋남 ≤ 0.25) ·
--   legK = 무릎 52° 내려감 5.05 / 프로토 2.78 · 팔 벌림 = STANCE 9° · 가슴점 = 어깨 관절 높이 · 오른손 = 개머리판 끝이 가슴판 앞면 0.3 앞
--   (가슴판 앞 2.3 + 0.3 + 손잡이→개머리 4.14) · 어깨 장갑 경첩 = 장갑 안쪽 위 모서리(관절에서 안 0.9 · 위 3.6)
SHAPES.Aero = setmetatable({
	crouch = {
		{ 0.00, 0, 0.0 }, { 0.11, 4, 3.2 }, { 0.28, 8, 6.4 }, { 0.50, 12, 9.5 }, { 0.77, 16, 12.7 }, { 1.08, 20, 15.8 },
		{ 1.45, 24, 18.9 }, { 1.86, 28, 21.9 }, { 2.31, 32, 24.9 }, { 2.80, 36, 27.9 }, { 3.32, 40, 30.7 }, { 3.87, 44, 33.5 },
		{ 4.45, 48, 36.2 }, { 5.05, 52, 38.8 }, { 5.66, 56, 41.3 }, { 6.28, 60, 43.5 }, { 6.90, 64, 45.6 }, { 7.51, 68, 47.5 },
		{ 8.11, 72, 49.2 }, { 8.69, 76, 50.5 }, { 9.24, 80, 51.6 },
	},
	legK = 1.82,
	armOut = 9,
	rideDrop = 1.6,                              -- 캐터펄트(천장 140, 직립 머리 127.9 [실측]) — 프로토 값 그대로
	chest = Vector3.new(0, 1.55, 0.10),
	zoomHand = Vector3.new(1.4, -0.6, 6.7),
	pad = { hingeX = 0.9, hingeY = 3.6, z0 = 15 },
	-- 10-28 AELLO 는 빔사벨 — FELSEN 도끼 두 손 3연격(SHAPES.Heavy.combo2h)을 __index 로 물려받지 않게 막음(false = 있는 값이라 __index 를 안 탐).
	--   10-27 도끼 작업 뒤 AELLO 빔사벨 3연격이 도끼 동작으로 나오던 원인(유저 10-28 00:44 "빔샤벨은 이전 모션으로")
	combo2h = false,
	-- 손이 물건에 닿는 두 자세만 AELLO 관절로 다시 풂(중장갑 각에서 출발해 최소한만 움직임) [실측 AeroTemplate FK]:
	--   칼 잡기 G = 손이 등 위 왼쪽 칼자루 가운데(꼭지 쪽 1.4)에 닿음, 오차 0.001, 손목 8.7°(칼자루 축 둘레 비틀기를 손목이 가장 덜 꺾이게 고름)
	--   허리 뒤 라이플 rifleStow = 손 라이플이 등 라이플과 겹침(위치 오차 0.008, 방향 0°). 중장갑 값 그대로면 1.67 어긋났음
	Q = (function()
		local q = {}
		for k, v in pairs(SHAPES.Heavy.Q) do q[k] = v end
		q.G = { Root = CFrame.new(0, -0.2, 0), Waist = E(4, 15), Neck = E(0, -10),
			ShoulderL = CF(0.72383, 0.28331, -0.62913, 0.04261, -0.92843, -0.36905, -0.68866, 0.24032, -0.68410), ElbowL = E(106.1),
			SaberGrip = CF(0.99148, 0.00352, -0.13020, -0.01355, 0.99700, -0.07617, 0.12954, 0.07729, 0.98856) }
		-- 10-28 겨눔 = 10-27 이전 빔사벨 겨눔(몸 앞 · 날 아래). 중장갑 Q 를 복사하면 도끼용 어깨 기댐(R)·부스트 겨눔(RB)까지 따라오므로 되돌림
		q.R = { ShoulderL = E(5.2, -5.3, -11.3), ElbowL = E(83.5), SaberGrip = E(-38.1) }
		q.RB = nil
		return q
	end)(),
	rifleStow = { ShoulderR = CF(0.76830, -0.28503, 0.57311, -0.36177, 0.54528, 0.75616, -0.52804, -0.78831, 0.31582), ElbowR = E(64.4),
		Grip = CF(0.52804, -0.36177, 0.76830, 0.84738, 0.16504, -0.50467, 0.05578, 0.91754, 0.39371) },
}, { __index = SHAPES.Heavy })
-- 10-28 ST-01 HORKOS(MechType "Horkos" — Rodin 생성 몸 2칸 블록, 유저 "실제로 타볼수있게"). AELLO 와 같은 규약(팔 곧게 = Transform 0 · 어깨 장갑 · 빔사벨).
-- 1차: 손이 물건에 닿는 자세(칼 잡기 G · 허리 뒤 라이플 rifleStow · 장전 등)는 AELLO 값을 빌려 씀 — 템플릿의 등 라이플 자리는 이 rifleStow 로 손 라이플을 놓은 자리로 맞춤.
-- 몸 크기 값만 새로 [rig/horkos_template_data.py · rig_pose.py, 템플릿과 같은 관절점]: 허벅지 4.29 · 정강이 7.89 · 위팔 2.92 · 아래팔 5.22.
--   웅크림 표 = 서기(hip 4 · knee −8) 위에 Hip α · Knee −(α+β) · Ankle β, 발목 앞뒤 어긋남 0 · legK = 무릎 52° 내려감 3.08 / 프로토 2.78.
--   팔 벌림 10°(곧은 팔이면 주먹이 골반 치마에 478칸 겹침 → 8° 부터 0) · 가슴점 = 어깨 관절 높이(몸통 파트 로컬 — 몸통 상자가 뒤 머리카락까지라 가운데가 뒤로 2.0)
--   · 어깨 장갑 경첩 = 장갑 안쪽 위 모서리(왼 1.55/2.75 · 오른 1.03/2.55 의 평균)
--   두 손 사격 오른손 = (1.4, 0, 5.1): 팔이 짧아(어깨→손 오른 7.79 · 왼 8.14 [실측 템플릿 관절]) 개머리판을 가슴판 앞에 두는 자리(Z 7.18)는
--   조준 −20~40° 에서 오른손 9.5 · 왼손 9.8 이 필요해 둘 다 못 닿음 [에디트 FK 실측, twoHandPose 와 같은 식]. 못 닿으면 팔이 다 펴진 채 총이 그만큼 몸 쪽에 와서
--   어차피 개머리판이 가슴에 묻히므로, 두 손이 다 닿는 가장 앞(오른 7.46 · 왼 7.83 필요)으로 당김 — 대신 개머리판 끝이 가슴판 앞면보다 1.8 안쪽
SHAPES.Horkos = setmetatable({
	crouch = {
		{ 0.00, 0, 0.0 }, { 0.07, 4, 2.2 }, { 0.17, 8, 4.4 }, { 0.31, 12, 6.6 }, { 0.47, 16, 8.8 }, { 0.67, 20, 10.9 },
		{ 0.89, 24, 13.1 }, { 1.14, 28, 15.2 }, { 1.41, 32, 17.3 }, { 1.71, 36, 19.3 }, { 2.03, 40, 21.3 }, { 2.37, 44, 23.2 },
		{ 2.72, 48, 25.0 }, { 3.08, 52, 26.7 }, { 3.46, 56, 28.3 }, { 3.83, 60, 29.8 }, { 4.21, 64, 31.1 }, { 4.59, 68, 32.3 },
		{ 4.96, 72, 33.3 }, { 5.32, 76, 34.1 }, { 5.67, 80, 34.7 },
	},
	legK = 1.11,
	armOut = 10,
	chest = Vector3.new(1.0, 2.75, -2.035),
	zoomHand = Vector3.new(1.4, 0, 5.1),
	pad = { hingeX = 1.3, hingeY = 2.65, z0 = 15 },
}, { __index = SHAPES.Aero })
-- 10-29 LT-01 SKADI(MechType "Skadi" — 저격 기체 복셀 이식, 전용 저격총). HORKOS 와 같은 규약(팔 곧게 = Transform 0 · 어깨 장갑 · 스커트 4장 · 빔사벨).
-- 1차: 손이 물건에 닿는 자세(칼 잡기 G · 장전 등)는 AELLO 값을 빌려 씀. 등 라이플(RifleStowed)은 없음 — 빔사벨을 들면 손 저격총이 숨기만 함.
-- 몸 크기 값만 새로 [sniper/rig/*.py, 템플릿과 같은 관절점]: 허벅지 6.30 · 정강이 7.40 · 위팔 2.80 · 아래팔 6.05.
--   웅크림 표 = 서기(hip 4 · knee −8) 위에 Hip α · Knee −(α+β) · Ankle β, 발목 앞뒤 어긋남 0 [에디트 FK — HORKOS 표를 같은 식으로 재현 확인] · legK = 무릎 52° 내려감 4.98 / 프로토 2.78.
--   팔 벌림 8°(6° 부터 팔·로우 레디 저격총이 옆 스커트와 겹침 0, 곧은 팔이면 2,948칸 — HORKOS 처럼 2° 여유) [rig/armout_check.py · 걷기 끝 다리 흔들어도 0 rig/walk_rifle_check.py]
--   · 가슴점 = 어깨 관절 높이(몸통 파트 로컬) · 어깨 장갑 경첩 = 장갑 안쪽 위 모서리(관절에서 안 1.2 · 위 1.6) [복셀]
--   두 손 견착: 팔이 짧아(어깨→주먹 8.85 이하) 저격총(20.3)의 받침까지 상체를 35° 틂(공용 ZOOM_TWIST 25 면 왼팔이 거의 다 펴짐 — 팔꿈치 6~17°).
--   기본 사격도 두 손(유저 10-29 21:37) = 총 파트 속성 HipHand · HipLeft · HipTwist −35(개틀링 허리 사격 형태, 손 자리는 줌과 같음 → 줌 들고 날 때 자세 이음매 없음).
--   에디트 IK: 조준 −40~60° 두 손 오차 0, −60° 만 왼팔 다 펴짐(0.23) · 몸과 겹침 0(팔꿈치 접힘 칸만) [rig/aim_vox_check.py]
SHAPES.Skadi = setmetatable({
	crouch = {
		{ 0.00, 0, 0.0 }, { 0.09, 4, 3.4 }, { 0.24, 8, 6.8 }, { 0.44, 12, 10.2 }, { 0.69, 16, 13.6 }, { 1.00, 20, 16.9 },
		{ 1.35, 24, 20.2 }, { 1.76, 28, 23.5 }, { 2.21, 32, 26.7 }, { 2.70, 36, 29.9 }, { 3.22, 40, 33.0 }, { 3.78, 44, 36.0 },
		{ 4.37, 48, 38.9 }, { 4.98, 52, 41.7 }, { 5.60, 56, 44.4 }, { 6.23, 60, 46.9 }, { 6.86, 64, 49.1 }, { 7.48, 68, 51.1 },
		{ 8.09, 72, 52.8 }, { 8.66, 76, 54.1 }, { 9.20, 80, 55.0 },
	},
	legK = 1.79,
	armOut = 8,
	chest = Vector3.new(0, 0.137, -1.517),
	zoomHand = Vector3.new(2.36, -1.4, 4.83),
	zoomTwist = 35,
	pad = { hingeX = 1.2, hingeY = 1.6, z0 = 15 },
	-- 스커트 따라가기 = 중장갑 값 그대로(앞 0.5 · 옆 0.5 · 바깥 0.15). 10-30 한때 0.8/0.15/0.3 으로 바꿨다가 되돌림 —
	--   근거였던 겹침(옆 스커트 ↔ 뒤 스커트)은 검사 도구 버그(기울인 파트를 원점 둘레로 돌림)가 만든 가짜였음. 고친 도구로 0~90° 전부 0 [sniper/rig/skirt_check.py]
	-- 10-30 앞차기(R) 키 자세 [sniper/rig/kick_check.py + kick_keys_v2.json — 다리 vs 몸·총·팔 0, 뻗은 발끝 = 몸 앞 17.5 · 골반보다 3.6 아래]
	--   디딤 다리(오른쪽) = 웅크림 표대로 골반 내린 만큼(0.6 · 0.8) 접음 → 디딤 발 바닥 어긋남 ≤ 0.07
	kick = {
		C = { J = { HipL = E(78), KneeL = E(-100), AnkleL = E(15), HipR = E(18.9), KneeR = E(-35.6), AnkleR = E(15.1), ShoulderL = E(-14, 0, -18), ElbowL = E(30) }, root = -0.6, lean = 6 },
		X = { J = { HipL = E(84), KneeL = E(-6), AnkleL = E(-25), HipR = E(21.4), KneeR = E(-40.2), AnkleR = E(17.2), ShoulderL = E(-24, 0, -20), ElbowL = E(26) }, root = -0.8, lean = 14 },
	},
	-- 10-30 앞차기 → 뒤 공중제비(유저 10:48 "상대 기체를 디딤발 삼아 뒤로 공중제비 한 바퀴") — 진행 k = CFG.flipPhase · 섞는 비율·각 = flipPose
	--   J = 웅크림(무릎을 가슴으로 · 총은 세워 듦 — 접은 허벅지와 안 겹침) · center = 웅크린 몸 무게중심(Root 관절 틀, 골반 기준) = 도는 중심
	--   [sniper/rig/flip_check.py: 앞차기 키 → 웅크림 → 한 바퀴를 41 등분 — 다리 ↔ 몸·총·팔 겹침 0 · 공중 최저 3.7(총구, 포물선 꼭대기 8)]
	flip = {
		J = { HipL = E(105), HipR = E(100), KneeL = E(-130), KneeR = E(-125), AnkleL = E(30), AnkleR = E(30), Waist = E(-12),
			ShoulderR = E(48, 0, 10), ElbowR = E(70), ShoulderL = E(30, 0, -14), ElbowL = E(80), Grip = E(0) },
		center = Vector3.new(0, 0.34, 0),   -- 10-30 11:2x 골반 앞 3.3(무게중심) → 0: 앞 절반 동안 몸이 앞으로 휘어 제자리처럼 보였음(rig/flip_travel.py)
	},
	-- 10-30 앵커(C) 꿇기 자세 [sniper/rig/anchor_solve.py → anchor_scan.json "-28_11"]: 오른 무릎 꿇음(정강이 수평 · 정강이 칼날 0.3 박힘 · 발끝 땅) · 왼발 앞에 평평히.
	--   허벅지 6.3 < 정강이 7.4 라 앞 정강이를 기울여 맞춤. 골반 내림 = CFG.Anchor.Drop(8.15) · lean = 허리 숙임(waistX 에 더함, − = 앞).
	--   게임 스커트(0.5/0.5/0.15)로 다시 셈 [rig/anchor_check.py]: 다리끼리 관절 접힘만 · 두 손 자세 −20° 에서 오른 아래팔 ↔ 옆 스커트 74칸(서 있어도 55칸)
	anchor = { J = { HipR = E(-28), KneeR = E(-65), AnkleR = E(-31.1), HipL = E(91.5), KneeL = E(-52), AnkleL = E(-39.5) }, lean = -6 },
}, { __index = SHAPES.Aero })
local function shapeOf(m)
	local t = m:GetAttribute("MechType")
	return (t and SHAPES[t]) or SHAPE_PROTO
end
-- 어깨 장갑 Transform(10-26): sh = 그 프레임의 어깨 Transform, side 1 = 왼쪽 / -1 = 오른쪽
local function padTransform(sh, side, pad)
	local d = sh.Rotation * Vector3.new(0, -1, 0)                    -- 위팔 방향(몸통 기준)
	local th = math.atan2(-d.Z, -d.Y)                                -- 앞으로 든 각(+ = 앞)
	if th < -math.rad(120) then th += 2 * math.pi end                -- 머리 위로 넘긴 팔(뽑아 올림 165°)이 −180° 로 뒤집히지 않게
	local ph = math.deg(math.asin(math.clamp(-side * d.X, -1, 1)))   -- 바깥으로 벌린 각
	local lat = math.rad(math.max(0, ph - pad.z0))
	local h = Vector3.new(side * pad.hingeX, pad.hingeY, 0)
	return CFrame.fromAxisAngle(Vector3.xAxis, th) * CFrame.new(h) * CFrame.fromAxisAngle(Vector3.zAxis, -side * lat) * CFrame.new(-h)
end
local function reloadElapsed(m)   -- 장전 시작 뒤 지난 시간, 장전 중 아니면 nil (장전 시간은 그 기체 주무기 기준)
	local RT = CFG.gun(m).ReloadTime
	-- 10-30 FALCO 마비 덫: 장전이 시작할 때 둔화 배율(s)로 길어졌으면 동작표 시각 = 지난 시간 ÷ s(내 기체 = MechClient GR.reloadSlow · 남 = 서버 속성 ReloadSlow)
	if m == ctx.mech() and os.clock() < ctx.reloadLocalUntil() then
		local s = (ctx.reloadSlow and ctx.reloadSlow()) or 1
		return (RT * s - (ctx.reloadLocalUntil() - os.clock())) / s
	end   -- 10-30 모듈로 옮기며 MechClient 상태는 ctx 로 읽음
	local u = m:GetAttribute("ReloadUntil")
	if u then local s = m:GetAttribute("ReloadSlow") or 1; return math.max(0, RT * s - (u - workspace:GetServerTimeNow())) / s end
	return nil
end
local function reloadPose(e, SH)   -- 0.2 들어 기울이며 탄창 쥠 · 0.42 뽑음 · 0.9 아래(새 탄창) · 1.15 올려 끼움 · 1.4 손 뗌 · 끝까지 복귀
	local function sm(x) x = math.clamp(x, 0, 1); return x * x * (3 - 2 * x) end
	-- 자세 묶음은 기체 모양별(10-26 SHAPES). 없으면 프로토 표
	local RR, LA, LD, LR = (SH and SH.reloadR) or RELOAD_R, (SH and SH.reloadLA) or RELOAD_LA, (SH and SH.reloadLD) or RELOAD_LD, (SH and SH.reloadLR) or RELOAD_LR
	local w = (e < 0.2) and sm(e / 0.2) or ((e > 1.4) and 1 - sm((e - 1.4) / math.max(0.05, CFG.ReloadTime - 1.4)) or 1)
	local L
	if e < 0.2 then L = LA
	elseif e < 0.42 then L = blendPose(LA, LD, sm((e - 0.2) / 0.22))
	elseif e < 0.9 then L = LD
	elseif e < 1.15 then L = blendPose(LD, LA, sm((e - 0.9) / 0.25))
	else L = blendPose(LA, LR, sm((e - 1.15) / 0.25)) end
	local grip = RR.Grip
	if e > 1.15 and e < 1.35 then grip = grip * E(-10 * math.sin((e - 1.15) / 0.2 * math.pi)) end   -- 끼우고 철컥(라이플이 살짝 튐)
	return w, { ShoulderR = RR.ShoulderR, ElbowR = RR.ElbowR, Grip = grip, ShoulderL = L.ShoulderL, ElbowL = L.ElbowL }
end
local function dropMag(m)   -- 다 쓴 탄창: 왼손 위치에서 떨어뜨림(화면마다 따로, 3초 뒤 사라짐)
	local la, sg, rifle = m:FindFirstChild("LowerArmL", true), m:FindFirstChild("SaberGrip", true), m:FindFirstChild("Rifle")
	if not la or not sg or not rifle then return end
	local p = Instance.new("Part")
	p.Name = "DroppedMag"; p.Size = Vector3.new(0.8, 2.4, 1.2); p.Color = Color3.fromRGB(52, 56, 64)
	p.Material = Enum.Material.SmoothPlastic; p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanQuery = false; p.CanTouch = false
	p.CFrame = CFrame.new((la.CFrame * sg.C0).Position) * rifle.CFrame.Rotation
	p.AssemblyLinearVelocity = -rifle.CFrame.UpVector * 10
	p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 6
	p.Parent = workspace
	Debris:AddItem(p, 3)
end
local function setRifle(st, m, stowed)   -- 손 라이플 ↔ 등 라이플을 바꿔 보여 준다(각 화면에서 따로)
	local hand, back = m:FindFirstChild("Rifle"), m:FindFirstChild("RifleStowed")
	-- 총을 바꾸면(거치대, 10-25) 파트가 새것이라 같은 상태라도 다시 칠한다(새 파트는 견본 투명도로 들어옴)
	if st.rifleStowed == stowed and st.rifleHand == hand and st.rifleBack == back then return end
	st.rifleStowed, st.rifleHand, st.rifleBack = stowed, hand, back
	if hand then hand.Transparency = stowed and 1 or 0 end
	if back then back.Transparency = stowed and 0 or 1 end
	-- 10-27 개틀링: 손 총 안의 파트(회전부·총열)도 같이 숨김/보임
	if hand then for _, p in ipairs(hand:GetDescendants()) do if p:IsA("BasePart") then p.Transparency = stowed and 1 or 0 end end end
end
local function saberParts(st, m)
	if st.saberParts then return st.saberParts end
	local sp = { hand = {}, beam = {}, holster = {}, pop = {} }
	local f = m:FindFirstChild("Saber")
	if f then
		local hand, hol = f:FindFirstChild("InHand"), f:FindFirstChild("Holster")
		if hand then for _, p in ipairs(hand:GetChildren()) do
			-- 10-27 FELSEN 열선 도끼: 날·갈고리·창끝(AxePop)은 빔 목록에 넣지 않는다 — 켜고 끌 때 한 번에 나타나지 않고 '뿅' 커지고 솟아야 함(axeUpdate)
			if p:IsA("BasePart") and p:GetAttribute("AxePop") then
				table.insert(sp.pop, { p = p, j = p:FindFirstChild("AxeJoint"), kind = p:GetAttribute("AxePop"), size = p:GetAttribute("Size0") or p.Size,
					c = p:GetAttribute("PopC") or Vector3.zero, slide = p:GetAttribute("Slide") or 0,
					hot = p:GetAttribute("HeatColor"), cold = p:GetAttribute("ColdColor") })
			elseif p:IsA("BasePart") then table.insert(p:GetAttribute("SaberBeam") and sp.beam or sp.hand, p) end   -- 빔(날·빛)은 따로 켠다
		end end
		if hol then for _, p in ipairs(hol:GetChildren()) do if p:IsA("BasePart") then table.insert(sp.holster, p) end end end
		sp.trail = f:FindFirstChild("SaberTrail", true)
		sp.light = f:FindFirstChild("SaberLight", true)
		local col = CFG.stat(m, "SaberColor")   -- 10-26 기체별(MechType 표에 있으면 그것, 없으면 공용 하늘색)
		if col then
			local glow = f:FindFirstChild("SaberGlow", true); if glow then glow.Color = col end
			if sp.trail then sp.trail.Color = ColorSequence.new(col) end
			if sp.light then sp.light.Color = col end
		end
	end
	st.saberParts = sp
	return sp
end
-- 10-27 FELSEN 열선 도끼(r5 X3 ×1.7): 평소 = 막대(손잡이 + 머리 통). 빔이 켜지는 순간(뽑기 0.15 · 2 들기 0.15 · 베기 상태 내내)
-- 날·갈고리가 통 앞뒤에서 '뿅'(크기 0 → 1.1 → 1.0, AXE_POP 초), 창끝은 통 속에서 위로 솟음(AXE_SPEAR 초). 다 나온 뒤 AXE_HEAT 초 지나 열선 점화(Neon + 불빛).
-- 빔이 꺼지면(1 수납 0.04) 열선 먼저 끄고 AXE_IN 초에 거꾸로 들어감 → 0.15 에 등 막대(Holster.AxeStowed)로 바뀔 때는 이미 막대.
-- 크기 = MeshPart.Size 직접(화면마다 따로, 판정과 무관) · 자리 = 관절 Transform (k − 1)·(파트 가운데 − 뿅 중심) = 뿅 중심 기준 확대.
local AXE_POP, AXE_SPEAR, AXE_IN, AXE_HEAT = 0.10, 0.12, 0.08, 0.03
local function axePopK(u)   -- 0 → 1.1(70%) → 1.0
	if u <= 0 then return 0 end
	if u < 0.7 then local a = u / 0.7; return 1.1 * a * (2 - a) end
	local a = math.min(1, (u - 0.7) / 0.3)
	return 1.1 - 0.1 * a * a * (3 - 2 * a)
end
local function axeUpdate(st, sp, handOn, beamOn)
	local now = os.clock()
	local dt = math.min(0.1, now - (st.axeLast or now)); st.axeLast = now
	local u, s = st.axeU or 0, st.axeS or 0
	if beamOn then u = math.min(1, u + dt / AXE_POP); s = math.min(1, s + dt / AXE_SPEAR)
	else u = math.max(0, u - dt / AXE_IN); s = math.max(0, s - dt / AXE_IN) end
	if beamOn and u >= 1 and s >= 1 then st.axeFull = st.axeFull or now else st.axeFull = nil end
	local hot = beamOn and handOn and st.axeFull ~= nil and now - st.axeFull >= AXE_HEAT
	local key = (handOn and 1 or 0) + (hot and 2 or 0)
	if u == st.axeU and s == st.axeS and key == st.axeKey then return end   -- 다 나왔거나 다 들어가 멈춤 = 할 일 없음
	st.axeU, st.axeS, st.axeKey = u, s, key
	local k, ks = axePopK(u), s * (2 - s)
	for _, q in ipairs(sp.pop) do
		local vis
		if q.kind == "spear" then
			vis = handOn and ks > 0.02
			if q.j then q.j.Transform = CFrame.new(0, -q.slide * (1 - ks), 0) end
		else
			vis = handOn and k > 0.03
			if vis then q.p.Size = q.size * Vector3.new(math.max(k, 0.35), k, k) end
			if q.j then q.j.Transform = CFrame.new(q.c * (k - 1)) end
		end
		q.p.Transparency = vis and 0 or 1
		if q.hot then
			q.p.Material = hot and Enum.Material.Neon or Enum.Material.SmoothPlastic
			q.p.Color = hot and q.hot or q.cold
		end
	end
	if sp.light then sp.light.Enabled = hot end
end
local function setSaber(st, m, handOn, beamOn)
	local sp = saberParts(st, m)
	if st.saberHand ~= handOn then
		st.saberHand = handOn
		for _, p in ipairs(sp.hand) do p.Transparency = handOn and (p:GetAttribute("SaberVis") or 0) or 1 end
		for _, p in ipairs(sp.holster) do p.Transparency = handOn and 1 or 0 end
	end
	if st.saberBeam ~= beamOn then
		st.saberBeam = beamOn
		for _, p in ipairs(sp.beam) do p.Transparency = beamOn and (p:GetAttribute("SaberVis") or 0) or 1 end
		if sp.light and #sp.pop == 0 then sp.light.Enabled = beamOn end   -- 도끼 불빛은 열선과 같이(axeUpdate)
		if not beamOn then
			st.trailOn = false
			if sp.trail then sp.trail.Enabled = false end
		end
	end
	if #sp.pop > 0 then axeUpdate(st, sp, handOn, beamOn) end
end
return {
	init = function(c) ctx = c end,
	AIM_HOLD_REMOTE = AIM_HOLD_REMOTE,
	AIR_FALL = AIR_FALL,
	AIR_RISE = AIR_RISE,
	AIR_TUCK = AIR_TUCK,
	E = E,
	JUMP_CROUCH = JUMP_CROUCH,
	JUMP_EXTEND = JUMP_EXTEND,
	JUMP_LEAN = JUMP_LEAN,
	LAND_DEPTH = LAND_DEPTH,
	LAND_DEPTH_HARD = LAND_DEPTH_HARD,
	LAND_DUR = LAND_DUR,
	LAND_DUR_HARD = LAND_DUR_HARD,
	LAND_LEAN = LAND_LEAN,
	LAND_LEAN_HARD = LAND_LEAN_HARD,
	R = R,
	SLASH_POSE = SLASH_POSE,
	SLASH_TRAIL = SLASH_TRAIL,
	SWING_AT = SWING_AT,
	WIND_HOLD_MINE = WIND_HOLD_MINE,
	WIND_HOLD_REMOTE = WIND_HOLD_REMOTE,
	ZOOM_TWIST = ZOOM_TWIST,
	axeRightHand = axeRightHand,
	blendPose = blendPose,
	comboPose = comboPose,
	crouchAngles = crouchAngles,
	dropMag = dropMag,
	equipPose = equipPose,
	kickPose = kickPose,
	flipPose = flipPose,   -- 10-30 앞차기 공중제비(MechClient 는 PO.flipPose 로 부름 — 최상위 지역 변수 개수 한계라 목록에 안 넣음)
	padTransform = padTransform,
	punchPose = punchPose,
	reloadElapsed = reloadElapsed,
	reloadPose = reloadPose,
	saberPose = saberPose,
	setRifle = setRifle,
	setSaber = setSaber,
	setThrusters = setThrusters,
	shapeOf = shapeOf,
	sstep = sstep,
	twoHandPose = twoHandPose,
	unequipPose = unequipPose,
}
