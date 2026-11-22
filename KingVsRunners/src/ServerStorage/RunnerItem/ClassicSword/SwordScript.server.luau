--Rescripted by Luckymaxer
--EUROCOW WAS HERE BECAUSE I MADE THE PARTICLES AND THEREFORE THIS ENTIRE SWORD PRETTY AND LOOK PRETTY WORDS AND I'D LIKE TO DEDICATE THIS TO MY FRIENDS AND HI LUCKYMAXER PLS FIX SFOTH SWORDS TY LOVE Y'ALl
--Updated for R15 avatars by StarWars
--Re-updated by TakeoHonorable

Tool = script.Parent
Handle = Tool:WaitForChild("Handle")
FXRemote = Tool:WaitForChild("FXRemote")  -- 데미지/콤보/타이밍 표시용 (클라 UI로 신호)

function Create(ty)
	return function(data)
		local obj = Instance.new(ty)
		for k, v in pairs(data) do
			if type(k) == 'number' then
				v.Parent = obj
			else
				obj[k] = v
			end
		end
		return obj
	end
end

local BaseUrl = "rbxassetid://"

Players = game:GetService("Players")
Debris = game:GetService("Debris")
RunService = game:GetService("RunService")

DamageValues = {
	BaseDamage = 5,
	-- 🔺 [밸런스 2026-09-08] 슬래시 8 → 15 / 런지 14 → 26.
	--   [왜] 1대1 통제 실험(킹 HP 975 고정, 8종 20판)에서 최하위였다.
	--     ClassicSword 4.4 DPS · 전체 중앙값 8.5 · 다른 무기 6.7~11.6
	--     타당 딜도 8 로, 다른 무기 13.7~28.1 의 절반 이하였다.
	--   ⚠️ 이건 '기본 지급 무기'다. 신규 유저가 처음 잡는 게 최약체면
	--     첫 2단계 경험이 가장 나쁘고, D1 리텐션과 직결된다.
	--   [목표] 최상위가 아니라 '중앙값 근처'. 2026-08-25 에 런지를 20 → 14 로
	--     내린 근거("기본 무기가 가장 센 건 상점 구조와 어긋난다")는 지금도 유효하다.
	--     타당 15 면 SakuraBlade(13.7) 와 KatanaSword2(17.1) 사이다.
	--   [산출] 실측 DPS 4.4 × (15/8) ≈ 8.3 — 중앙값 8.5 에 근접.
	--     ⚠️ 명중률(24%)과 HIT_COOLDOWN 0.5 상한은 그대로다. 이 값은
	--       '바닥 올리기'지 구조 개선이 아니다. 재측정으로 확인할 것.
	--   ⚠️ 2026-08-20 에 8 → 10 을 "근거 없이 올렸다"며 되돌린 이력이 있다.
	--     이번엔 20판 실측이 근거다. 그래도 과하면 12 로 조이는 게 다음 단계.
	--   ⚠️ 되돌릴 값: SlashDamage 8 / LungeDamage 14
	SlashDamage = 15,
	-- ⚠️ 런지는 슬래시의 1.75배 비율을 유지했다(8:14 → 15:26).
	--   런지 명중률이 슬래시보다 높다(실측 약 64% vs 24%)는 점은 감안하지 않은 값이다.
	--   재측정에서 런지 의존이 과하면 이쪽만 22 로 내릴 것.
	LungeDamage = 26
}

--For R15 avatars
Animations = {
	R15Slash = 522635514,
	R15Lunge = 522638767
}

Damage = DamageValues.BaseDamage

Grips = {
	Up = CFrame.new(0, 0, -1.70000005, 0, 0, 1, 1, 0, 0, 0, 1, 0),
	Out = CFrame.new(0, 0, -1.70000005, 0, 1, 0, 1, -0, 0, 0, 0, -1)
}

Sounds = {
	Slash = Handle:WaitForChild("SwordSlash"),
	Lunge = Handle:WaitForChild("SwordLunge"),
	Unsheath = Handle:WaitForChild("Unsheath")
}

-- 🔊 [2026-08-25] 연타 시 소리가 씹히는 문제 해결.
-- ⚠️ 같은 Sound 인스턴스에 Play() 를 다시 호출하면 재생 중이던 소리가
--    처음으로 되감긴다. 평타 쿨(0.2초)이 슬래시 음원보다 짧아,
--    빠르게 휘두르면 소리가 계속 잘렸다.
-- ⚠️ 원본을 복제해 재생하고 끝나면 지운다. 여러 개가 겹쳐 울려
--    실제 연타 속도가 소리로 전달된다.
local Debris = game:GetService("Debris")
local function playOneShot(template)
	if not template then return end
	local s = template:Clone()
	s.Parent = Handle
	s:Play()
	-- 음원 길이를 모를 수 있으므로 넉넉히 잡고 Debris 에 맡긴다
	Debris:AddItem(s, 4)
end

ToolEquipped = false

-- 같은 대상 중복 타격 방지: 한 스윙에 칼날이 여러 파트를 스쳐 Touched가 여러 번 불려도
-- 같은 캐릭터는 HIT_COOLDOWN 안에 한 번만 데미지. (즉사 버그 방지)
-- 🔬 [진단 2026-09-08] ClassicSword 명중률·실효딜 계측.
--   [배경] 1대1 실측(킹 HP 975 고정, 8종 20판)에서 이 무기만 4.4 DPS 로 최하위였다.
--     전체 중앙값 8.5 의 절반이고, 편차도 3.6~4.8 로 가장 좁아 우연이 아니다.
--   [갈라야 할 것] 타당 11.2 vs 코드값 20 의 격차가 어디서 오나
--     ① 헛스윙이 [K] 타수에 포함  → 스윙 대비 명중이 낮게 나온다
--     ② 데미지가 깎임             → '적용' 이 20 미만으로 찍힌다
--   ⚠️ 슬래시는 쿨이 없다(DoAttack 이 Tool.Enabled 를 즉시 되돌림).
--     실제 상한은 HIT_COOLDOWN 0.5 뿐이라 이론상 40 DPS 다. 실측은 그 11% 였다.
--   ⚠️ [측정 완료 2026-09-08] 결과 — 113스윙 / 명중 27 / 명중률 24%.
--     · 의도 = 적용 (슬래시 8→8.0, 런지 14→14.0). 파이프라인 감소 없음, 무적 차단 0건.
--       → ② 데미지 문제 아님. 낮은 건 기본값 자체다(다른 무기 타당 13.7~28.1 대비 8).
--     · 명중 간격이 0.500~0.515초에 딱 붙음 = HIT_COOLDOWN 0.5 가 상한.
--       붙어서 때려도 초당 2회가 최대라 0.2초 연타분은 전부 버려진다.
--       붙어 있을 때 상한 8÷0.5 = 16 DPS, 실측 3.6 (상한의 22%).
--     · 나머지 헛침은 킹과 떨어진 구간(0.2초 6연타에 명중 0인 구간이 있었다).
--   ⚠️ 주석에 '슬래시 20 / 런지 30' 이라 적힌 낡은 기록이 파일 여기저기 있다.
--     실제 DamageValues 는 8 / 14 다. 그 주석을 근거로 계산하지 말 것.
--   ⚠️ 되살릴 때: true. 릴리즈 전 이 블록과 Blow/DoAttack 안의 DBG_HIT 구간 삭제.
-- 🔬 [2026-09-09] 재활성. SLASH_COOLDOWN 0.45 → 0 되돌림의 근거를 재기 위해서다.
--   [SlashGap] 간격/막힘 + sweep 수가 이 토글에 묶여 있다.
--   ⚠️ 판단이 끝나면 다시 false 로. 릴리즈 정리 목록에 이미 올라와 있다.
local DBG_HIT     = true
local dbgSwings   = 0   -- 휘두른 횟수
local dbgHits     = 0   -- 실제 데미지가 들어간 횟수
local dbgApplied  = 0   -- 실제 적용 데미지 합
local dbgBlocked  = 0   -- 무적으로 무시된 횟수

-- ⚔️ [2026-09-08] 런지 명중 → 사거리 강화 버프
--   [왜] 이 무기만 "붙어야 딜이 나오는데 붙으면 죽는" 구조였다.
--     1대1 실측 3판 모두 킹을 30~33% 깎고 사망 — 딜을 8→15 로 올린 뒤에도 완주를 못 했다.
--     사거리를 주면 킹 평타 넉백(7.6)에 밀려나도 계속 때릴 수 있다.
--   [설계] 런지를 '맞히면' 켜진다. 지금 런지는 명중과 무관하게 발동해 보상이 없었다.
--     → 명중이 곧 보상이 되어, 죽어 있던 스킬(쿨 2.0, 8종 중 최단)이 의미를 갖는다.
--   ⚠️ 비갱신이다. 이미 켜져 있으면 재발동을 무시한다(타이머를 늘리지 않는다).
--     갱신형이면 쿨 2.0 < 지속 4.0 이라 런지만 계속 눌러 상시 유지가 된다.
--     비갱신이면 "켜진 동안 쓴 런지는 버프를 못 준다" → 언제 쓸지가 판단거리가 된다.
--   ⚠️ 런지를 잠그지는 않는다. 버프 중에도 이동용으로 자유롭게 쓴다(사용자 결정).
--   ⚠️ 판정과 시각을 나눈 유일한 예외다. 오라는 '검신을 감싸는 연출'이라
--     판정 파트로 못 쓴다(파티클·빔이라 Touched 가 없다). 그래서 이렇게 나눴다:
--       판정 = _ReachHitbox (투명 파트, Touched → Blow)
--       시각 = _ReachAura   (ServerStorage.ReachAuraTemplate 복제)
--     ⚠️ 둘의 길이를 REACH_TOTAL_Z 하나로 묶는다. 따로 두면 어긋난다.
--   [이력] 처음엔 Handle 을 늘렸다 → 메시 Scale 이 1 이라 눈엔 안 보였다.
--     다음엔 sword.mesh 를 이어 붙였다 → 손잡이가 검 중간에 또 생겨 모양이 깨졌다.
--     지금은 오라로 감싼다(Fate 엑스칼리버 식). 원본 모양을 안 건드린다.
--   ⚠️ 오라는 Light 프리셋 고정이다. "노란 빛 = 사거리 강화"를 모든 스킨이 공유한다.
--     스킨별 오라는 별도 작업으로 미룸(2026-09-09 결정).
--   ⚠️ 선언 위치 주의: Blow(아래)에서 reachStart 를 부르므로 반드시 그보다 앞에 있어야 한다.
--     Lua 지역변수는 선언이 사용보다 앞서야 한다(파일 뒤쪽에 두면 nil 참조).
--   ⚠️ 되돌릴 값: REACH_BUFF_ON = false
local REACH_BUFF_ON   = true
local REACH_DURATION  = 10.0   -- 버프 지속(초)
-- 🎯 [2026-09-09] 발동 조건: 런지 1회 명중 → 3회 명중, 지속 4초 → 10초.
--   [왜] 1회 트리거는 "붙어야 켜지는데 붙으면 슬랩 맞는" 모순이 있었고,
--     4초는 관통해 지나친 뒤 돌아서는 시간에 대부분 먹혔다.
--     3회로 대가를 키우고 10초로 보상을 키운다 — 비율은 비슷하되 한 번이 묵직해진다.
--   [왜 이동 스택이 아니라 명중인가] Q대시·넉백 기반도 검토했지만,
--     "쓰기만 하면"과 "당하면" 보상은 동기가 서지 않는다(사용자 판단).
--     런지 명중만이 실력이 들어가는 유일한 지점이다.
--   ⚠️ 버프 중에는 카운터를 쌓지 않는다. 쌓으면 런지 쿨 2초로 10초 안에 5번 더 쓸 수 있어
--     사실상 상시가 된다. 안 쌓으면 "지금은 사거리를 쓸 시간"이라는 리듬이 생긴다.
--   ⚠️ 카운터에 시간 제한을 두지 않는다. 띄엄띄엄 맞혀도 결국 보상받게 —
--     기본 지급 무기이므로 신규 유저 기준으로 관대하게 둔다.
--   ⚠️ 되돌릴 값: REACH_HITS_NEEDED 1 / REACH_DURATION 4.0
local REACH_HITS_NEEDED = 3    -- 버프 발동에 필요한 런지 명중 횟수
local reachHits         = 0    -- 현재 누적 (발동 시 0으로 소모)
-- ⚠️ [2026-09-09] REACH_TOTAL_Z 는 삭제했다. 파트 크기는 이 무기의 사거리와 무관하다.
--   실제 사거리는 SWEEP_SLASH_REACH / SWEEP_LUNGE_REACH 의 reach 값이 정한다.
--   [이력] Handle 리사이즈 → 메시 이어붙이기 → 히트박스 파트 → 전부 판정에 영향 없었다.
--     히트박스를 12.0 으로 키우고도 명중 0건인 걸 보고서야 sweepOnce 를 찾았다.
local AURA_OFFSET_Z   = 5.944  -- 오라를 검에 맞추는 상대 위치(로비 실측, 2026-09-09)
-- ⚠️ 0.124 → 5.944. 오라 Part 를 빔 길이(15.98)에 맞춰 늘리면서 중심이 앞으로 밀렸다.
--   Part 부피 = 파티클(Lightning·Specs)이 뿜는 범위라, 빔만 늘리면 입자가 가운데만 몰린다.
--   Part 를 늘리고 그만큼 앞으로 옮긴 뒤 Attachment 를 뒤로 밀어 빔 위치를 보존했다.
local reachUntil      = 0      -- 이 시각까지 버프 유지 (os.clock 기준)
local reachAura       = nil    -- 시각용 오라
local reachToken      = 0      -- 중복 타이머 무효화용

local ServerStorage   = game:GetService("ServerStorage")
local auraTemplate    = ServerStorage:FindFirstChild("ReachAuraTemplate")

local function reachClear()
	if reachAura then reachAura:Destroy(); reachAura = nil end
	reachUntil = 0
end

local function reachEnd(token)
	if token ~= reachToken then return end          -- 더 새로운 버프가 있으면 무시
	reachClear()
	if FXRemote and Player then
		pcall(function() FXRemote:FireClient(Player, "reachBuff", 0) end)
	end
end

local function reachStart()
	if not REACH_BUFF_ON then return end
	-- ⚠️ 버프 중이면 카운터를 쌓지도, 재발동하지도 않는다.
	--   쌓으면 런지 쿨 2.0 로 10초 안에 5번 더 채워 상시 버프가 된다.
	if os.clock() < reachUntil then return end

	-- 🎯 런지 명중 누적. 목표에 못 미치면 여기서 끝.
	reachHits = reachHits + 1
	if FXRemote and Player then
		pcall(function()
			FXRemote:FireClient(Player, "reachStack", reachHits, REACH_HITS_NEEDED)
		end)
	end
	if reachHits < REACH_HITS_NEEDED then return end
	reachHits = 0                                   -- 소모

	if not (Handle and Handle.Parent) then return end
	reachClear()

	-- ⚠️ [2026-09-09] 판정용 파트를 만들지 않는다. 이 무기의 실제 명중은
	--   sweepOnce 의 박스(SWEEP_SLASH / SWEEP_LUNGE)가 정한다. Handle 이나
	--   붙인 파트의 크기는 판정과 무관하다 — 히트박스를 12.0 으로 키웠는데
	--   명중이 0건이었던 게 그 증거다(실측 2026-09-09).
	--   → 사거리 강화는 openDamageWindow 의 pickBox 가 확장 박스를 고르는 방식.

	-- ── 시각: 오라 ──
	--   ⚠️ 템플릿은 원본 데모 그대로다(Attachment 가 X축 -2.04 ~ 3.79).
	--     Attachment 를 Z축으로 옮기는 방식은 폐기했다 — 파티클·빔의 회전이
	--     안 따라와 모양이 깨졌다. 대신 파트째로 Y -90° 돌려 축을 맞춘다.
	--   [수치 근거] 로비에서 검과 오라를 직접 겹쳐 맞춘 실측(2026-09-09):
	--     상대 위치 (0, 0, 0.124) / Y 회전 -90°
	--   ⚠️ 부호 근거(실측): Tool.Grip.Z = -1.50 → 자루가 Handle 로컬 -Z 끝이고,
	--     따라서 칼끝은 로컬 +Z 다. 오라 빔은 자기 +X 로 뻗으므로
	--     (Attachment -2.04 → Attachment2 +3.79), +X 를 +Z 로 보내는 -90° 가 맞다.
	--     (+90° 는 -Z = 자루 쪽으로 보낸다)
	--   ⚠️ 한때 +90° 로 바꿨다가 되돌렸다. 테스트 씬에서 검을 거꾸로 놓고 보고
	--     "오라가 반대로 뻗는다"고 오판한 것이었다 — 부호를 의심하기 전에
	--     비교 대상(검)의 방향부터 확인할 것.
	if auraTemplate then
		local au = auraTemplate:Clone()
		au.Name   = "_ReachAura"
		au.CFrame = Handle.CFrame
			* CFrame.new(0, 0, AURA_OFFSET_Z)
			* CFrame.Angles(0, -math.pi / 2, 0)
		au.Parent = Handle
		local w2 = Instance.new("WeldConstraint")
		w2.Part0 = Handle; w2.Part1 = au; w2.Parent = au
		reachAura = au
	end

	reachUntil = os.clock() + REACH_DURATION
	-- 🔊 [2026-09-09] 사거리 강화 발동음.
	--   ⚠️ SoundId 가 비어 있으면 조용히 넘어간다(playOneShot 이 template nil 만 걸러서
	--     여기서 한 번 더 본다). 음원을 넣기 전에도 기능은 정상 동작한다.
	local actSfx = Handle and Handle:FindFirstChild("ReachActivate")
	if actSfx and actSfx.SoundId ~= "" then playOneShot(actSfx) end
	reachToken = reachToken + 1
	local myToken = reachToken
	if FXRemote and Player then
		pcall(function() FXRemote:FireClient(Player, "reachBuff", REACH_DURATION) end)
	end
	task.delay(REACH_DURATION, function() reachEnd(myToken) end)
end

local HIT_COOLDOWN = 0.5
local lastHitTime = {}  -- [character] = os.clock()
-- 🔬 [진단 2026-09-09] sweepOnce 실행 수. 스윙 수(dbgSwings)와 비교해
--   "연타가 애니/윈도우를 취소하는가"를 가른다. 스윙 ≫ sweep 이면 취소되고 있다.
--   ⚠️ sweepOnce(718행)보다 앞에 있어야 한다. SLASH_COOLDOWN 주석 참조.
local dbgSweeps = 0

-- 타격 윈도우: 휘두르는 동안에만 true. 평소엔 false라 칼이 닿기만 해선 데미지 안 줌.
local canDamage = false
-- 이번 윈도우의 데미지 값(슬래시 20 / 런지 30). 전역 Damage 경합 방지:
-- 윈도우 열 때 박아두고 Blow가 이 값을 읽음 → 다음 입력이 들어와도 이전 타격 데미지가 안 바뀜.
local windowDamage = 0

--For Omega Rainbow Katana thumbnail to display a lot of particles.
for i, v in pairs(Handle:GetChildren()) do
	if v:IsA("ParticleEmitter") then
		v.Rate = 20
	end
end

Tool.Grip = Grips.Up
Tool.Enabled = true

-- ❄️ Frozen Sword 스윙 눈송이: SwingSnow 속성이 있으면 스윙 시 검신에서 눈송이 버스트.
local swingSnowEmitter = nil
local function ensureSnowEmitter()
	if not Tool:GetAttribute("SwingSnow") then return nil end
	local mesh = Handle:FindFirstChild("_SkinMesh")
	if not mesh then return nil end
	if swingSnowEmitter and swingSnowEmitter.Parent then return swingSnowEmitter end
	local att = mesh:FindFirstChild("_SnowAtt") or Instance.new("Attachment")
	att.Name = "_SnowAtt"
	att.Parent = mesh
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "_SwingSnow"
	pe.Texture = "rbxassetid://85698671947685"
	pe.Color = ColorSequence.new(Color3.fromRGB(170, 230, 255), Color3.fromRGB(225, 245, 255))
	pe.LightEmission = 0.8
	pe.LightInfluence = 0
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1.4),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(0.4, 0.8)
	pe.Rate = 0
	pe.Speed = NumberRange.new(6, 12)
	pe.SpreadAngle = Vector2.new(35, 35)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-120, 120)
	pe.Parent = att
	swingSnowEmitter = pe
	return pe
end
local function burstSwingSnow()
	local pe = ensureSnowEmitter()
	if pe then pe:Emit(18) end
end

function IsTeamMate(Player1, Player2)
	return (Player1 and Player2 and not Player1.Neutral and not Player2.Neutral and Player1.TeamColor == Player2.TeamColor)
end

function TagHumanoid(humanoid, player)
	local Creator_Tag = Instance.new("ObjectValue")
	Creator_Tag.Name = "creator"
	Creator_Tag.Value = player
	Debris:AddItem(Creator_Tag, 2)
	Creator_Tag.Parent = humanoid
end

function UntagHumanoid(humanoid)
	for i, v in pairs(humanoid:GetChildren()) do
		if v:IsA("ObjectValue") and v.Name == "creator" then
			v:Destroy()
		end
	end
end

-- ═══════════════════════════════════════════════════════════════
-- ⚔️ [LUNGE-REWORK] 강타 = 밀어내고 따라붙는 기술
--
-- 넉백 기법은 RunnerBotDriveController 의 ATTACK_KNOCKBACK 코드를 그대로 가져왔다.
-- 그 주석에 남은 실패 이력을 반드시 지킬 것:
--   ⚠️ MaxForce 를 고정값(20003 등)으로 주면 물리 솔버가 터져 "Gameplay Paused" 가 뜬다.
--      → 반드시 AssemblyMass 비례로 준다.
--   ⚠️ BodyVelocity 가 아니라 LinearVelocity + Debris 짧은 수명으로 처리한다.
--
-- ⚠️ 강도 22 는 태거의 넉백 저항 임계(KB_THRESH = 40) 아래로 잡은 값이다.
--    40 을 넘으면 저항 카운터가 누적되어(3초 창, 3타째 감쇠 0.08) 러너 여럿이
--    강타를 돌릴 때 태거가 사실상 봉쇄된다. 임계 아래면 그 문제가 구조적으로 안 생긴다.
--    농민봇 넉백이 28 인 것도 같은 이유이고, 기본 무기이므로 그보다 약하게 둔다.
-- ═══════════════════════════════════════════════════════════════
-- ⚠️ [2026-08-25] 런지 넉백 폐기. 태거의 정체성이 '밀어내기'인데
--    러너도 밀어내면 두 역할이 겹치고, 서로 튕겨나는 그림도 어색했다.
--    → 넉백 대신 '찌르며 파고드는' 돌진으로 바꾼다(런지=찌르기 모션).
local LUNGE_KNOCKBACK   = 0     -- 수평 밀어내기 강도 (폐기, 이전 38)
-- ⚠️ [2026-09-09] 38 로 되살렸다가 같은 날 다시 0 으로 되돌렸다.
--   [되살린 이유] 런지가 관통해 지나쳐서 '돌아서기'에 버프 시간을 쓰는 문제.
--     내가 도는 대신 상대를 밀면 조작 없이 거리가 생긴다고 봤다.
--   [왜 실패했나] 2026-08-25 폐기 주석의 "서로 튕겨나는 그림도 어색했다"가 그대로 재현됐다.
--     실측(15:40 판): 런지로 파고드는 순간(진입속도 55) 킹의 슬랩을 맞아 내가 래그돌,
--     동시에 내 런지 넉백으로 킹이 Freefall(속도 37.6) — 둘이 같이 날아간다.
--     결과 4.5 DPS / 9타. 넉백 없을 때는 10.6 DPS / 54타였다.
--   ⚠️ 교훈: 폐기 주석의 근거 중 '전제가 바뀐 것'과 '안 바뀐 것'을 나눠 봐야 한다.
--     "역할 중복"은 사거리 버프로 전제가 바뀌었지만, "서로 튕겨남"은 그대로였다.
--   ⚠️ 되살리려면 킹의 슬랩과 겹치지 않게 할 방법을 먼저 찾을 것.
-- ⚠️ 태거 넉백 저항 임계(KB_THRESH = 40) 바로 아래로 유지할 것.
--    40 을 넘으면 저항 카운터가 누적되어(3초 창, 3타째 감쇠 0.08)
--    러너 여럿이 강타를 돌릴 때 태거가 사실상 봉쇄된다.
-- ⚠️ [상향 근거 2026-08-23] 22 는 실효 4 stud 로, 태거 Push(17.2)에 비해
--    체감이 없었다. 38 + 지속 0.30 이면 약 11 stud 로 "밀어냈다"가 느껴진다.
--    점령 방어 중인 태거를 존 밖으로 밀어내는 게 이 기술의 핵심 용도가 됐다.
local LUNGE_KB_LIFT     = 6     -- 살짝 띄워야 지면 마찰에 걸리지 않는다 (5 → 6)
local LUNGE_KB_LIFETIME = 0.30  -- 0.18 → 0.30. 실효 거리는 강도 × 지속에 비례한다

local LUNGE_SPEED_BONUS = 4     -- 16 → 20. 넉백으로 벌어진 거리를 좁히기 위한 것
local LUNGE_SPEED_TIME  = 1.0   -- 강타 쿨(2.0초)의 절반. 상시 버프가 되지 않게

-- 🗡️ [2026-08-25] 런지 = 찌르며 파고드는 돌진.
-- ⚠️ 예전엔 대상을 밀어냈다(LUNGE_KNOCKBACK 38). 그런데 태거의 정체성이
--    '밀어내기'라 역할이 겹쳤고, 서로 튕겨나는 그림도 어색했다.
--    → 대상은 그대로 두고 '내가' 앞으로 파고든다. 찌르기 모션과도 맞는다.
-- ⚠️ 히트 여부와 무관하게 발동한다. 빗나가도 앞으로 나가야 '돌격'이다.
local LUNGE_DASH_SPEED  = 55    -- 돌진 속도(stud/s)
local LUNGE_DASH_TIME   = 0.22  -- 돌진 지속. 짧게 — 이동기가 아니라 '파고들기'다.

local function applyLungeDash(attackerPlayer)
	if not attackerPlayer then return end
	local char = attackerPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 then return end
	-- ⚠️ 다운 중에는 돌진하지 않는다. 기어가는 상태에서 튀어나가면 이상하다.
	if char:GetAttribute("Downed") then return end
	-- ⚠️ [2026-09-09] 래그돌(PlatformStand) 중에도 돌진하지 않는다.
	--   [증상] "누운 상태에서 공격할수록 더 심하게 뒹군다"(사용자 제보).
	--   [원인] 슬랩 넉백 BodyVelocity 가 이미 붙어 있는데 여기서 LinearVelocity 를
	--     하나 더 얹는다. PushTool 에서 겹침을 정리해놨는데, 그 뒤에 무기가 다시 만든다.
	--     PlatformStand 중엔 지면 마찰·직립 제어가 꺼져 있어 회전이 그대로 남는다.
	--   ⚠️ 데미지는 그대로 나간다(여기서 막는 건 이동뿐). 래그돌 0.4초 동안
	--     공격이 아예 안 되게 하려면 Lunge()/Attack() 진입부를 막아야 한다 — 미적용.
	if hum.PlatformStand then return end

	local dir = root.CFrame.LookVector
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then return end
	dir = dir.Unit

	local att = root:FindFirstChild("LungeDashAtt")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "LungeDashAtt"
		att.Parent = root
	end

	-- 기존 돌진이 남아 있으면 지운다(연타 시 속도가 누적되지 않도록)
	local old = root:FindFirstChild("_LungeDashLV")
	if old then old:Destroy() end

	local lv = Instance.new("LinearVelocity")
	lv.Name = "_LungeDashLV"
	lv.Attachment0 = att
	lv.MaxForce = math.max(root.AssemblyMass, 1) * 10000
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	-- ⚠️ Y 를 0 으로 두면 중력이 그대로 먹어 계단·경사에서 뜨지 않는다.
	lv.VectorVelocity = dir * LUNGE_DASH_SPEED
	lv.Parent = root
	game:GetService("Debris"):AddItem(lv, LUNGE_DASH_TIME)

	-- ⚠️ [2026-08-25] 라운드 종료 시 캐릭터가 굳는 문제.
	--    Debris 는 인스턴스를 지우지만, 그 사이 캐릭터가 로비로 텔레포트되면
	--    LinearVelocity 가 계속 힘을 가해 이동이 막힌다.
	--    → 시간이 지나면 명시적으로 지우고, 캐릭터가 사라져도 정리한다.
	task.delay(LUNGE_DASH_TIME, function()
		if lv and lv.Parent then lv:Destroy() end
	end)
	local conn
	conn = char.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if lv and lv.Parent then lv:Destroy() end
			if conn then conn:Disconnect() end
		end
	end)
	task.delay(LUNGE_DASH_TIME + 0.5, function()
		if conn then conn:Disconnect() end
	end)
end

-- ⚠️ WalkSpeed 를 직접 대입하면 안 된다.
--    Speed Potion 은 SpeedBoost 속성 + WalkSpeed 대입을 함께 쓰고, 종료 시
--    "WalkSpeed 가 (16+12) 그대로일 때만" 되돌린다. 여기서 값을 덮으면
--    포션이 자기 값을 못 알아보고 복구를 포기하거나, 반대로 포션 종료가 이 버프를 지운다.
--    → 기준값이 아니라 '현재 값에 가산/감산'하고, 토큰으로 중복 적용을 막는다.
local function applyLungeSpeed(attackerPlayer)
	if not attackerPlayer then return end
	local char = attackerPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	if char:GetAttribute("Downed") then return end

	-- 이미 이 버프가 걸려 있으면 시간만 갱신한다(중복 가산 방지).
	local token = (char:GetAttribute("_LungeSpeedToken") or 0) + 1
	char:SetAttribute("_LungeSpeedToken", token)

	if not char:GetAttribute("_LungeSpeedOn") then
		char:SetAttribute("_LungeSpeedOn", true)
		hum.WalkSpeed = hum.WalkSpeed + LUNGE_SPEED_BONUS
	end

	task.delay(LUNGE_SPEED_TIME, function()
		if not char or not char.Parent then return end
		if char:GetAttribute("_LungeSpeedToken") ~= token then return end   -- 더 최근 강타가 갱신함
		if char:GetAttribute("_LungeSpeedOn") then
			char:SetAttribute("_LungeSpeedOn", nil)
			char:SetAttribute("_LungeSpeedToken", nil)
			local h = char:FindFirstChildOfClass("Humanoid")
			if h and h.Parent then
				h.WalkSpeed = math.max(h.WalkSpeed - LUNGE_SPEED_BONUS, 0)
			end
		end
	end)
end

function Blow(Hit)
	if not Hit or not Hit.Parent or not CheckIfAlive() or not ToolEquipped then
		return
	end
	local RightArm = Character:FindFirstChild("Right Arm") or Character:FindFirstChild("RightHand")
	if not RightArm then
		return
	end
	local RightGrip = RightArm:FindFirstChild("RightGrip")
	if not RightGrip or (RightGrip.Part0 ~= Handle and RightGrip.Part1 ~= Handle) then
		return
	end
	local character = Hit.Parent
	if character == Character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health == 0 then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	-- 진영 체크: 러너 무기는 태거만 공격 가능. 아군(러너 플레이어/AI 러너봇) 오사 차단.
	if player then
		-- 맞은 대상이 플레이어 → 태거가 아니면 무시 (러너끼리 안 때림)
		if player == Player or player:GetAttribute("Role") ~= "Tagger" then
			return
		end
	else
		-- 맞은 대상이 NPC → AI 러너봇이면 무시 (아군 농민봇)
		if character:GetAttribute("AIRunner") or character:GetAttribute("RunnerBot")
			or (character.Parent and (character.Parent:GetAttribute("AIRunner") or character.Parent:GetAttribute("RunnerBot"))) then
			return
		end
	end
	-- 타격 윈도우 체크: 휘두르는 중이 아니면 데미지 없음 (그냥 닿기만 한 경우 무시)
	if not canDamage then
		return
	end
	-- 같은 대상 중복 타격 방지 (한 스윙에 여러 파트 접촉 → 1회만 적용)
	local now = os.clock()
	local last = lastHitTime[character]
	if last and (now - last) < HIT_COOLDOWN then
		-- 🔬 [SlashGap 2026-09-09] 쿨에 막힌 타격. 이게 많으면 쿨이 병목이다.
		if DBG_HIT then
			print(string.format("🔬 [SlashGap] 막힘 %.3f (쿨 %.2f)", now - last, HIT_COOLDOWN))
		end
		return
	end
	-- 🔬 [SlashGap 2026-09-09] 통과한 타격의 '실제 명중 간격'.
	--   ⚠️ 스윙 간격이 아니라 명중 간격이다 — lastHitTime 이 명중 시각에 찍히므로.
	--   0.9 근처에 몰리면 쿨 문제, 2초대로 흩어지면 사거리 문제.
	if DBG_HIT and last then
		print(string.format("🔬 [SlashGap] 간격 %.3f", now - last))
	end
	lastHitTime[character] = now

	UntagHumanoid(humanoid)
	TagHumanoid(humanoid, Player or Character)
	-- 🏷️ 봇이면 캐릭터 모델로 태그(다른 무기와 같은 처리).
	--   Player 가 nil 이면 TagHumanoid 가 기존 태그를 지우고 nil 을 넣어
	--   유저가 남긴 creator 까지 날아간다. 킬 크레딧·어그로가 이 태그를 읽는다.
	if _G.IsDamageImmune and _G.IsDamageImmune(humanoid.Parent) then
		-- 🔬 [진단 2026-09-08] 무적으로 걸러진 타격도 세어야 '헛침'과 구분된다.
		if DBG_HIT then
			dbgBlocked = dbgBlocked + 1
			print(string.format("🗡️ [Dbg] 무적으로 무시 → %s (누적 차단 %d)",
				humanoid.Parent.Name, dbgBlocked))
		end
		return
	end
	-- 🔬 [진단 2026-09-08] 실제 적용 데미지를 잰다.
	--   [왜] 1대1 실측에서 28회 / 314딜 = 타당 11.2 인데 코드값은 슬래시 20 이다.
	--     절반이 어디로 갔는지 모르는 채로 값을 만지면 엉뚱한 데를 고친다.
	--   [읽는 법]
	--     적용 20  → 데미지는 정상. [K] 의 '타수'가 헛스윙까지 세는 것이다 = 명중률 문제
	--     적용 <20 → 파이프라인에서 깎인다 (TaggerCcGuard 등) = 데미지 문제
	--   ⚠️ TakeDamage 는 반환값이 없다. HP 를 전후로 재서 실제 감소분을 본다.
	--     MaxHealth 배율 방식(TaggerCcGuard)으로 깎이면 여기서 드러난다.
	--   ⚠️ 원인 확정되면 DBG_HIT=false. 릴리즈 전 블록째 삭제.
	local hpBefore = humanoid.Health
	humanoid:TakeDamage(windowDamage)  -- 이번 윈도우의 데미지(전역 Damage 경합 방지)
	-- 🔊 [2026-09-09] 강화 타격음. 스윙이 아니라 '명중' 지점에서 낸다.
	--   [왜] 스윙은 쿨이 없어 클릭하는 만큼 나가지만(실측 113회), 실제 타격은
	--     HIT_COOLDOWN 0.5 에 묶여 초당 2회다(실측 27회). 스윙마다 울리면
	--     소리가 4배로 겹쳐 뭉친다.
	--   ⚠️ 기존 슬래시음(Attack 의 playOneShot)은 그대로 둔다 — 역할이 다르다.
	--     휘두름 = Sounds.Slash / 타격 = SlashEmpowered. 두 겹이지만 자연스럽다.
	--   ⚠️ 버프 중에만. SoundId 가 비면 조용히 넘어간다.
	if REACH_BUFF_ON and os.clock() < reachUntil then
		local emp = Handle and Handle:FindFirstChild("SlashEmpowered")
		if emp and emp.SoundId ~= "" then playOneShot(emp) end
	end
	-- ⚔️ [2026-09-08] 런지가 '명중했을 때만' 사거리 버프. 위 reachStart 주석 참조.
	--   ⚠️ windowDamage 로 판별한다. isLunge 플래그가 Blow 까지 안 내려오므로,
	--     이번 타격 윈도우에 박아둔 데미지값이 런지 것인지로 가른다.
	--   ⚠️ 진영·무적 체크를 모두 통과한 뒤다. 아군 오사나 무적 대상엔 안 켜진다.
	if windowDamage == DamageValues.LungeDamage then
		reachStart()
	end
	if DBG_HIT then
		local applied = hpBefore - humanoid.Health
		dbgHits = dbgHits + 1
		dbgApplied = dbgApplied + applied
		print(string.format("🗡️ [Dbg] %s 의도 %d → 적용 %.1f | 명중 %d회 누적 %.0f (평균 %.1f)",
			(windowDamage == DamageValues.LungeDamage) and "런지" or "슬래시",
			windowDamage, applied, dbgHits, dbgApplied, dbgApplied / dbgHits))
	end

	-- 데미지/콤보 표시: 공격자 클라로 타격 정보 전송 (튀어오르는 숫자 + 런지 라벨)
	if Player then
		local isLunge = (windowDamage == DamageValues.LungeDamage)
		local hitPos = Hit.Position
		-- 🔢 CC 중이면 화면 숫자를 실효값으로 환산한다(판정은 원본 그대로).
		FXRemote:FireClient(Player, "hitFX",
			(_G.DisplayDamage and _G.DisplayDamage(humanoid.Parent, windowDamage)) or windowDamage,
			isLunge, hitPos)

		-- ⚔️ [LUNGE-REWORK] 강타 명중 시: 대상 넉백 + 본인 이속 버프
		--   [배경] 강타는 이름이 Lunge 인데 돌진 요소가 없었다. 원래 있던 BodyVelocity 는
		--          주석 처리된 데다 Vector3(0,10,0) 이라 전방 이동이 아니라 살짝 뜨는 것뿐이었다.
		--          결국 "데미지만 센 평타"라 변칙성이 없었다.
		--   [의도] 밀어내고 따라붙는 기술로 바꾼다. 넉백만 있으면 동속(둘 다 16)이라
		--          떼어놓기만 하고 다시 못 붙는다 → 이속 버프가 반드시 세트여야 의미가 생긴다.
		--   ⚠️ 명중 시에만 발동한다. 여기는 이미 타격 윈도우·중복타격 가드를 통과한 지점이다.
		if isLunge then
			-- ⚠️ [2026-08-25] 돌진은 Lunge() 로 옮겼다.
			--    히트해야만 나가면 '돌격'이 아니라 '명중 보상'이 된다.
			--    빗나가도 앞으로 파고들어야 찌르기 모션과 맞는다.
			-- ⚠️ [2026-08-25] 명중 시 이속 버프 제거.
			--    런지가 '돌진'으로 바뀌면서 이동 효과가 중복됐고,
			--    때리고 빨라지는 건 '찌르며 파고든다'와 방향이 다르다.

			-- 🔙 [2026-09-09] 런지 넉백 부활 (2026-08-25 에 폐기했던 것)
			--   [왜 되살리나] 폐기 당시엔 "태거의 정체성이 밀어내기인데 러너도 밀면
			--     역할이 겹친다"가 근거였다. 그 사이 사거리 강화 버프가 생기면서
			--     전제가 바뀌었다 — 이제 밀어내는 것이 곧 '카이팅 시작'이다.
			--   [무엇을 푸나] 런지는 관통해서 지나간다(55 × 0.22 ≈ 12 stud).
			--     붙으려고 쓴 스킬이 오히려 등을 보이게 만들어, 버프 4초 중 1초 넘게
			--     '돌아서기'에 썼다. 카메라를 자동으로 돌려봤지만 어지러워 폐기.
			--     → 내가 도는 대신 상대를 민다. 조작 없이 거리가 생기고,
			--       그 자리에서 사거리 16 으로 바로 때릴 수 있다.
			--   ⚠️ 강도는 KB_THRESH(40) 아래로 유지한다. 넘기면 태거 넉백 저항이
			--     누적돼(3초 창, 3타째 감쇠 0.08) 러너 여럿이 돌릴 때 태거가 봉쇄된다.
			--   ⚠️ 명중 시에만 나간다. 이 지점은 진영·윈도우·중복 가드를 모두 통과했다.
			--   ⚠️ 되돌리려면 LUNGE_KNOCKBACK = 0.
			if LUNGE_KNOCKBACK > 0 then
				local tRoot = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
				local myRoot = Character and Character:FindFirstChild("HumanoidRootPart")
				if tRoot and myRoot then
					-- 방향은 '나 → 대상'. 내 시선이 아니라 실제 위치 차이를 쓴다
					-- (관통해 지나친 뒤엔 시선과 위치가 어긋나 있다).
					local dir = (tRoot.Position - myRoot.Position)
					dir = Vector3.new(dir.X, 0, dir.Z)
					if dir.Magnitude > 0.1 then
						dir = dir.Unit
						local lv = Instance.new("LinearVelocity")
						lv.Attachment0 = tRoot:FindFirstChildOfClass("Attachment")
							or Instance.new("Attachment", tRoot)
						lv.RelativeTo = Enum.ActuatorRelativeTo.World
						lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
						lv.VectorVelocity = dir * LUNGE_KNOCKBACK + Vector3.new(0, LUNGE_KB_LIFT, 0)
						-- ⚠️ MaxForce 는 질량 비례로. 고정값을 주면 물리 솔버가 터진다.
						lv.MaxForce = tRoot.AssemblyMass * 10000
						lv.Parent = tRoot
						game:GetService("Debris"):AddItem(lv, LUNGE_KB_LIFETIME)
					end
				end
			end
		end
	end
end


-- ═══════════════════════════════════════════════════════════════
-- 🗡️ [HITBOX-SWEEP 2026-08-31] Touched 단독 판정 → 전방 박스 질의 보강
--
-- [증상] 런지가 보기엔 맞았는데 데미지가 안 들어간다.
-- [원인] 판정이 Handle.Touched 하나뿐인데 Handle 은 1.00 × 0.80 × 4.00 이다.
--   칼날 길이(4)는 충분하다. 문제는 단면이 1 × 0.8 이라 좌우로 1.5 stud 나
--   위아래로 0.8 stud 만 어긋나도 접촉 자체가 발생하지 않는다는 것.
--   R6 토르소가 2 × 2 × 1 이니 세로 0.8 이 특히 좁다.
-- [앞뒤 문제가 아니다] 60fps 에서 런지는 프레임당 0.92 stud 이동하고
--   (LUNGE_DASH_SPEED 55 / 60) 칼날이 4 stud 라 진행축 터널링은 없다.
--   놓치는 건 전부 단면 쪽이다 — 그래서 길이가 아니라 폭·높이를 넓힌다.
--
-- [해결] 타격 윈도우 동안 캐릭터 전방 박스 안의 태거를 찾아 Blow 로 넘긴다.
--   ⚠️ Touched 는 제거하지 않는다. 둘 중 뭐가 먼저 잡든 Blow 안의
--     HIT_COOLDOWN(0.5s)이 중복을 막는다. ToxBoxSystem:550 이 같은 이유로
--     "폴링 백업"을 붙인 선례를 그대로 따른다.
--   ⚠️ 기준점은 Handle 이 아니라 HumanoidRootPart 다. 칼날 자세는 애니메이션이
--     만드는 값이고 관절 소유권은 클라에 있어 서버에서 신뢰할 수 없다.
--     몸통 기준이면 서버가 항상 같은 값을 본다.
--   ⚠️ GetPartBoundsInBox 를 쓰지 않는다. 이 게임은 콜리전 그룹을 많이 쓰는데
--     (TaggerCharacter / Runners / AIRunnerChar / TaggerItems …) OverlapParams 는
--     그룹 필터를 타므로 "안 잡히는데 이유를 모르는" 함정이 된다.
--     러너 무기는 어차피 태거만 때리므로 후보가 1~2명뿐이다. 순회가 더 싸고 확실하다.
--   ⚠️ 데미지·진영·중복 판정은 전부 Blow 안에 있다. 여기서 다시 구현하지 말 것 —
--     같은 로직이 두 곳에 있으면 나중에 한쪽만 고쳐진다.
-- ═══════════════════════════════════════════════════════════════

-- 전방 박스(HumanoidRootPart 중심 기준, stud). 기존 실효 단면은 1.0 × 0.8 이었다.
--   halfW/halfH = 좌우·상하 반폭 / reach = 전방 사거리
--   ⚠️ 좁게 되돌리려면 halfH 부터 줄일 것. 체감 대부분이 세로에서 온다.
local SWEEP_SLASH = { halfW = 2.5, halfH = 3.0, reach = 6 }
local SWEEP_LUNGE = { halfW = 3.0, halfH = 3.5, reach = 9 }

-- ⚔️ [2026-09-09] 사거리 강화 버프용 확장 박스.
--   ⚠️ 이 게 진짜 사거리다. Handle 크기도, 파트를 붙이는 것도 판정과 무관하다 —
--     Blow 는 Touched 로도 불리지만 실제 명중은 sweepOnce 의 이 박스가 정한다.
--     (히트박스 파트를 12.0 으로 키웠는데 판정이 0건이었던 이유가 이것이다.)
--   [기준] 킹 평타 넉백 7.6 — 이보다 길어야 "밀려나도 계속 때린다"가 성립한다.
--     reach 6 → 11 이면 넉백 한 번을 흡수하고도 닿는다.
--   ⚠️ halfW/halfH 는 조금만 키운다. 세로를 키우면 체감이 급격히 넓어진다(위 주석).
local SWEEP_SLASH_REACH = { halfW = 3.0, halfH = 3.2, reach = 22 }
local SWEEP_LUNGE_REACH = { halfW = 3.5, halfH = 3.7, reach = 24 }
-- ⚠️ [2026-09-09] reach 6 → 11 → 16 → 22 (지속은 10초 유지).
--   16 은 오라 빔 끝(15.94)에 맞춘 값이었는데, 3회 조건으로 바뀌며 대가가 3배가 됐다.
--   대가에 맞춰 보상을 키운다 — 22 면 평상시(6)의 3.7배다.
--   ⚠️ 22 는 킹 강타 도달(12)의 1.8배, 봇 킹 SWING_RANGE(9)의 2.4배다.
--     버프 10초 동안 킹의 모든 공격 밖에서 때릴 수 있다는 뜻이다.
--     봇전으로는 이 값의 강도를 못 잰다 — 봇이 홀드 라인 때문에 안 쫓아온다.
--     실유저 킹 상대로 확인하기 전까지는 미검증으로 둘 것.
--   ⚠️ 오라(시각)는 15.94 까지만 뻗는다. 판정이 6 더 길어 "안 닿았는데 맞음"이 생긴다.
--     체감이 어긋나면 오라를 늘리거나 reach 를 내릴 것.

-- 태거 후보 순회. 유저 태거 + 봇 킹 + 로비 훈련더미를 본다.
-- ⚠️ 봇 킹은 Player 가 아니라 workspace 의 Model 이다.
--    CaptureSystem:291 이 같은 함정에 걸렸었다("Role==Tagger 로 넓혔다").
-- ⚠️ [2026-09-09] TaggerDummy 추가. 안 넣었더니 로비 더미가 스윕 대상에서 빠져
--    "무기를 휘둘러도 스윕은 아무도 못 잡는" 상태였다. 그래서 로비 딜은 전부
--    Handle.Touched 경로(접촉 거리)로만 들어갔고, 사거리 변경이 로비에서
--    영원히 검증되지 않았다 — 사거리 강화를 5번 고쳐 쓴 진짜 원인이 이것이다.
--    ⚠️ 교훈: 값을 고치기 전에 "이 테스트 환경이 그 값을 잴 수 있나"를 먼저 확인할 것.
--    로비 더미 속성: ImmortalDummy / LobbyDummy / TaggerDummy (Role 은 nil)
local function forEachTagger(fn)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= Player and plr:GetAttribute("Role") == "Tagger" then
			local ch = plr.Character
			if ch then fn(ch) end
		end
	end
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and not Players:GetPlayerFromCharacter(m)
			and (m:GetAttribute("Role") == "Tagger" or m:GetAttribute("IsTaggerNoob")
				or m:GetAttribute("TaggerDummy")) then
			fn(m)
		end
	end
end

local function sweepOnce(box)
	if not canDamage then return end
	dbgSweeps = dbgSweeps + 1   -- 🔬 [2026-09-09] 실제 실행 수 (canDamage 통과분만)
	local root = Character and Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	forEachTagger(function(targetChar)
		local tRoot = targetChar:FindFirstChild("HumanoidRootPart")
		local hum = targetChar:FindFirstChildOfClass("Humanoid")
		if not tRoot or not hum or hum.Health <= 0 then return end
		-- 로컬 좌표: LookVector 가 -Z 라 전방은 rel.Z 가 음수다.
		local rel = root.CFrame:PointToObjectSpace(tRoot.Position)
		if math.abs(rel.X) <= box.halfW
			and math.abs(rel.Y) <= box.halfH
			and rel.Z <= 0 and rel.Z >= -box.reach then
			Blow(tRoot)
		end
	end)
end

-- 타격 윈도우를 여는 유일한 지점. Attack / Lunge 둘 다 여기를 쓴다.
-- ⚠️ 토큰이 필요한 이유: 예전엔 스윙마다 task.delay 를 따로 걸어서, 이전 스윙의
--    타이머가 다음 스윙의 윈도우를 조기에 닫을 수 있었다(슬래시 0.35 → 런지 0.5).
--    windowDamage 가 이미 같은 부류의 값 경합을 막고 있었다 — 창 닫기도 같이 막는다.
local sweepToken = 0
-- ⚔️ [2026-09-09] 버프 상태에 따라 박스를 고른다. 호출부가 아니라 여기서 갈라야
--   Attack / Lunge 두 경로가 자동으로 같은 규칙을 따른다(한쪽만 고쳐지는 걸 막는다).
local function pickBox(base)
	if REACH_BUFF_ON and os.clock() < reachUntil then
		return (base == SWEEP_LUNGE) and SWEEP_LUNGE_REACH or SWEEP_SLASH_REACH
	end
	return base
end
local function openDamageWindow(dmg, duration, box)
	box = pickBox(box)
	windowDamage = dmg
	canDamage = true
	sweepToken = sweepToken + 1
	local myToken = sweepToken
	task.delay(duration, function()
		if sweepToken == myToken then canDamage = false end
	end)
	task.spawn(function()
		while canDamage and sweepToken == myToken do
			sweepOnce(box)
			RunService.Heartbeat:Wait()
		end
	end)
end

function Attack()
	Damage = DamageValues.SlashDamage
	playOneShot(Sounds.Slash)
	burstSwingSnow()   -- ❄️ Frozen Sword: 스윙 눈송이 버스트

	-- 타격 윈도우 열기 (슬래시 모션 동안만 데미지) + 전방 박스 스윕 시작.
	openDamageWindow(DamageValues.SlashDamage, 0.35, SWEEP_SLASH)

	if Humanoid then
		if Humanoid.RigType == Enum.HumanoidRigType.R6 then
			local Anim = Instance.new("StringValue")
			Anim.Name = "toolanim"
			Anim.Value = "Slash"
			Anim.Parent = Tool
		elseif Humanoid.RigType == Enum.HumanoidRigType.R15 then
			local Anim = Tool:FindFirstChild("R15Slash")
			if Anim then
				local Track = Humanoid:LoadAnimation(Anim)
				Track:Play(0)
			end
		end
	end	
end

function Lunge()
	Damage = DamageValues.LungeDamage

	-- 🗡️ 휘두르는 순간 앞으로 파고든다(명중 여부 무관).
	applyLungeDash(Player)

	playOneShot(Sounds.Lunge)
	burstSwingSnow()   -- ❄️ Frozen Sword: 스윙 눈송이 버스트

	-- 타격 윈도우 열기 (런지 찌르기 동안만 데미지) + 전방 박스 스윕 시작.
	openDamageWindow(DamageValues.LungeDamage, 0.5, SWEEP_LUNGE)
	
	if Humanoid then
		if Humanoid.RigType == Enum.HumanoidRigType.R6 then
			local Anim = Instance.new("StringValue")
			Anim.Name = "toolanim"
			Anim.Value = "Lunge"
			Anim.Parent = Tool
		elseif Humanoid.RigType == Enum.HumanoidRigType.R15 then
			local Anim = Tool:FindFirstChild("R15Lunge")
			if Anim then
				local Track = Humanoid:LoadAnimation(Anim)
				Track:Play(0)
			end
		end
	end	
	--[[
	if CheckIfAlive() then
		local Force = Instance.new("BodyVelocity")
		Force.velocity = Vector3.new(0, 10, 0) 
		Force.maxForce = Vector3.new(0, 4000, 0)
		Debris:AddItem(Force, 0.4)
		Force.Parent = Torso
	end
	]]
	
	-- ⚠️ [LUNGE-BLOCK] 예전엔 여기서 wait(0.2)+wait(0.6)=0.8초를 동기로 기다렸다.
	--    Lunge() 는 DoAttack 이 Tool.Enabled=false 로 잠근 채 호출하므로,
	--    이 대기가 끝날 때까지 다음 공격이 통째로 막혔다
	--    (실측 2026-08-20: 재타격 간격이 전부 1.48초 이상, 카타나는 0.58초).
	--    그립 전환은 연출일 뿐 판정과 무관하므로 비동기로 뺀다.
	--    ⚠️ 그립은 반드시 Up 으로 되돌려야 한다. 중간에 툴이 해제되면
	--       Out 자세로 굳으므로 Unequipped 에서도 복구한다.
	task.spawn(function()
		task.wait(0.2)
		if Tool and Tool.Parent then Tool.Grip = Grips.Out end
		task.wait(0.6)
		if Tool and Tool.Parent then Tool.Grip = Grips.Up end
		Damage = DamageValues.SlashDamage
	end)
end

Tool.Enabled = true
LastAttack = 0

-- [LUNGE-SKILL] 런지를 더블클릭 → 스킬 버튼(F)으로 전환.
--   ⚠️ 예전 방식(0.4초 내 두 번 클릭)은 게임 안에 안내가 전혀 없어 사실상
--      아무도 쓰지 못하는 기능이었다. 다른 무기 4종(Katana/HammerLow/HammerHigh/
--      Gauntlet)은 전부 F키 스킬 버튼을 쓰는데 기본 무기만 숨은 조작을 요구했다.
--   쿨다운을 서버에서 강제한다. 클라 판정만 믿으면 조작으로 무한 런지가 가능하다.
local LUNGE_COOLDOWN = 2.0
local lungeReadyAt = 0

-- [LUNGE-LOCK] 런지 후 잠금 시간. 슬래시는 안 잠근다.
--   버튼 방식으로 바뀌어 '교대 강제' 역할은 끝났지만, 런지 모션이 끝나기 전
--   다음 입력이 겹치는 것은 여전히 막아야 한다. 쿨다운(2.0)이 더 길어 실질 상한은 그쪽.
local LUNGE_LOCK = 0.5

-- ⚔️ [2026-09-09] 슬래시 쿨다운 신설. 예전엔 0 이었다(클릭하는 만큼 나감).
--   [왜] 실제 타격은 HIT_COOLDOWN 0.5 에 묶여 초당 2회인데, 스윙은 무제한이라
--     실측에서 113 스윙 / 명중 27 = 24% 였다. 4번 중 3번이 버려지는 입력이다.
--     소리·애니메이션만 요란하고 딜은 안 늘어 "빠른데 안 맞는" 느낌을 만들었다.
--   [값] 0.45 — HIT_COOLDOWN 0.5 보다 살짝 짧게 둔다.
--     같게 하면 타이밍이 어긋날 때마다 한 박자씩 밀려 실효 DPS 가 떨어진다.
--     조금 짧아야 매 판정 창을 놓치지 않는다.
--   ⚠️ DPS 는 이 값에 거의 영향받지 않아야 정상이다(어차피 상한이 0.5).
--     재측정에서 DPS 가 떨어지면 0.45 가 너무 긴 것 — 0.35 로 내릴 것.
--   ⚠️ 되돌릴 값: 0 (즉시 해제)
-- ⚠️ [되돌림 2026-09-09 (같은 날)] 0.45 → 0. 이 세션에 넣었다가 같은 세션에 뺀다.
--   [왜 0.45 가 틀렸나] 판단의 '방향'은 맞았는데 착지점이 최악이었다.
--     lastHitTime 은 스윙이 아니라 '명중' 시각에 찍힌다(Blow 안). 연타하면:
--       t=0    스윙 → 명중 (lastHit=0)
--       t=0.45 스윙 → 0.45 < HIT_COOLDOWN(0.5) → 막힘
--       t=0.90 스윙 → 명중            ← 막힌 스윙이 다음 기회를 0.90 으로 민다
--     명중 간격 공식: C × ceil(0.5 / C)
--       C=0.45 → 0.90 (최악)  C=0.35 → 0.70  C=0.25/0.50 → 0.50
--     즉 0.5 '바로 아래'가 전 구간에서 가장 나쁘다.
--   ⚠️ [그래도 0.50 / 0.25 로 가면 안 된다] 위 원래 주석의 경고가 맞다.
--     gap = C + (δ₂ − δ₁).  δ = 스윙 후 sweepOnce 가 표적을 잡기까지의 지연.
--     표적이 늦게 들어와 δ₁ 이 크고 다음엔 이미 안에 있어 δ₂ 가 0 이면
--     간격이 C 밑으로 떨어져 거부된다 → 다시 두 배로 밀린다.
--     0.5 의 정수배(0.25 · 0.50)는 전부 이 경계에 착지한다.
--   [왜 0.55 가 아니라 0 인가] 0.55 는 명중률 100%·경계 안전이지만,
--     '쿨이 실제로 물고 있었는지' 자체가 미검증이다. 원래 근거였던
--     "113 스윙 / 27 명중 = 24%" 를 다시 계산하면:
--       쿨 창(명중 후 0.5초)에 들어갈 스윙은 명중 1회당 1~2개 → 최대 27~54회.
--       남은 59~86 회는 사거리 밖·킹 이동으로 빗나간 것이라 쿨과 무관하다.
--     버려진 입력의 최대 1/3 만 쿨 탓이고, 오히려 '헛친 뒤 즉시 재시도'를 막아 손해다.
--   [그래서] 0 = 이 세션 이전 상태 = 알려진 기준선으로 되돌리고,
--     아래 [SlashGap] 로그로 병목이 쿨인지 사거리인지부터 가른다. 값은 그 다음.
--   ⚠️ 되돌릴 값: 0.55 (0.50/0.25 는 경계라 금지). 판단 기준은 아래 로그 읽는 법.
local SLASH_COOLDOWN = 0

-- 🔬 [진단 2026-09-09] 슬래시 병목이 '쿨'인지 '사거리'인지 가르는 계측.
--   DBG_HIT 에 묶는다(릴리즈 정리 목록에 이미 올라와 있어 삭제 누락이 없다).
--   [읽는 법]
--     간격이 0.9 근처에 몰림      → 쿨이 실제로 물었다. 0.55 도입 검토
--     간격이 2초대로 흩어짐       → 사거리가 병목. 쿨은 애초에 논점이 아니었다
--     막힘 0 건                   → 같은 결론 (쿨 0 이라 당연하지만 대조군이 된다)
--     스윙 ≫ sweep                → 연타가 애니/윈도우를 취소한다. 게이트에 진짜 이유가 있음
--   ⚠️ 스윙 수는 위 dbgSwings 를 그대로 쓴다. 여기선 sweep 실행 수만 따로 센다.
--   ⚠️ 실제 선언은 sweepOnce(718행)보다 앞이어야 해서 HIT_COOLDOWN 근처로 올렸다.

-- 공격 실행: 클라이언트가 더블클릭을 판정해 FXRemote로 isLunge를 보내면 그대로 실행.
-- (네트워크 지연이 더블클릭 간격에 안 섞이게 판정을 클라로 옮김)
function DoAttack(isLunge)
	if not Tool.Enabled or not ToolEquipped or not CheckIfAlive() then
		return
	end
	Tool.Enabled = false
	-- 🔬 [진단 2026-09-08] 스윙 분모. 명중률 = dbgHits / dbgSwings.
	if DBG_HIT then
		dbgSwings = dbgSwings + 1
		-- 🔬 [2026-09-09] sweep 수를 같이 찍는다. 스윙 ≫ sweep = 연타가 윈도우를 취소.
		print(string.format("🗡️ [Dbg] 스윙 #%d (%s) | sweep %d | 명중 %d (%.0f%%) | 실효딜 %.0f",
			dbgSwings, isLunge and "런지" or "슬래시", dbgSweeps, dbgHits,
			(dbgHits / dbgSwings) * 100, dbgApplied))
	end
	if isLunge then
		Lunge()
	else
		Attack()
	end
	--wait(0.5)
	-- (BaseDamage 즉시 리셋 제거: Attack()이 설정한 SlashDamage가 칼날 접촉까지 유지되도록.
	--  원본의 Damage=BaseDamage 리셋은 휘두름 직후 데미지를 5로 깎아 슬래시가 5만 들어가던 버그 유발)
	local SlashAnim = (Tool:FindFirstChild("R15Slash") or Create("Animation"){
		Name = "R15Slash",
		AnimationId = BaseUrl .. Animations.R15Slash,
		Parent = Tool
	})
	
	local LungeAnim = (Tool:FindFirstChild("R15Lunge") or Create("Animation"){
		Name = "R15Lunge",
		AnimationId = BaseUrl .. Animations.R15Lunge,
		Parent = Tool
	})
	-- [LUNGE-LOCK] 런지는 LUNGE_LOCK, 슬래시는 SLASH_COOLDOWN 만큼 잠근다.
	--   task.delay 로 빼서 이 핸들러 자체는 안 막는다(예전 동기 wait 이 문제였음).
	--   ⚠️ [2026-09-09] 슬래시도 잠근다. 예전엔 즉시 풀어 "답답함을 줄인다"였는데,
	--     실제로는 HIT_COOLDOWN 0.5 에 막혀 4번 중 3번이 버려지는 입력이 됐다.
	--     빠른 게 아니라 헛도는 것이었다 — 위 SLASH_COOLDOWN 주석 참조.
	if isLunge then
		task.delay(LUNGE_LOCK, function()
			if Tool and Tool.Parent then Tool.Enabled = true end
		end)
	elseif SLASH_COOLDOWN > 0 then
		task.delay(SLASH_COOLDOWN, function()
			if Tool and Tool.Parent then Tool.Enabled = true end
		end)
	else
		Tool.Enabled = true
	end
end

function CheckIfAlive()
	return (((Player and Player.Parent and Character and Character.Parent and Humanoid and Humanoid.Parent and Humanoid.Health > 0 and Torso and Torso.Parent) and true) or false)
end

function Equipped()
	Character = Tool.Parent
	Player = Players:GetPlayerFromCharacter(Character)
	Humanoid = Character:FindFirstChildOfClass("Humanoid")
	Torso = Character:FindFirstChild("Torso") or Character:FindFirstChild("HumanoidRootPart")
	if not CheckIfAlive() then
		return
	end
	ToolEquipped = true
	Sounds.Unsheath:Play()
end

function Unequipped()
	Tool.Grip = Grips.Up
	ToolEquipped = false
	-- ⚔️ [2026-09-08] 사거리 버프 강제 종료.
	--   ⚠️ 안 넣으면 버프 도중 무기가 회수될 때(라운드 종료 · 사망 · 스왑)
	--     _ReachAura 가 Handle 자식으로 남아 템플릿에 저장된다.
	--     다음 라운드에 그걸 달고 지급되고, 또 버프가 걸리면 계속 쌓인다.
	--   ⚠️ 토큰을 올려 예약된 reachEnd 도 무효화한다(늦게 도착해 새 파트를 지우지 않게).
	reachToken = reachToken + 1
	reachClear()
	-- ⚠️ 카운터도 초기화. 안 하면 라운드를 넘어 이어져서
	--   다음 판 첫 런지에 바로 발동하는 사고가 난다.
	reachHits = 0
	-- 🎯 UI 도 같이 끈다. 안 그러면 회수 직전의 스택·버프 표시가 화면에 남는다.
	if FXRemote and Player then
		pcall(function()
			FXRemote:FireClient(Player, "reachStack", 0, REACH_HITS_NEEDED)
			FXRemote:FireClient(Player, "reachBuff", 0)
		end)
	end
end

-- 공격 입력은 클라이언트(FXClient)가 보냄. 서버가 진영 체크·쿨다운·데미지를 통제.
--   action "attack" = 평타(슬래시), "lunge" = 스킬 버튼(F)로 발동하는 강타.
FXRemote.OnServerEvent:Connect(function(firingPlayer, action, _legacy)
	-- 이 도구의 소유자만 허용 (다른 플레이어가 남의 검 신호를 못 쏘게)
	if firingPlayer ~= Player then return end

	if action == "lunge" then
		-- [LUNGE-SKILL] 쿨다운은 반드시 서버가 판정한다.
		--   클라 판정만 믿으면 조작으로 무한 런지가 가능하다.
		local now = os.clock()
		if now < lungeReadyAt then
			-- 아직 쿨다운 중 — 남은 시간을 돌려줘 UI 가 동기화되게 한다
			FXRemote:FireClient(Player, "lungeCd", lungeReadyAt - now)
			return
		end
		if not Tool.Enabled or not ToolEquipped or not CheckIfAlive() then return end
		-- ⚠️ [2026-09-09] 래그돌 중에는 런지를 거절한다(쿨은 소모하지 않는다).
		--   [왜] 어차피 돌진이 막히므로(applyLungeDash 의 PlatformStand 가드)
		--     쓰면 쿨 2초만 날린다. 0.4초 뒤 일어나서 제대로 쓰는 게 맞다.
		--   ⚠️ 클라에 남은 쿨을 되돌려줘야 UI 가 어긋나지 않는다 — 쿨 거절과 같은 처리.
		if Humanoid and Humanoid.PlatformStand then
			FXRemote:FireClient(Player, "lungeCd", math.max(lungeReadyAt - now, 0))
			return
		end
		lungeReadyAt = now + LUNGE_COOLDOWN
		FXRemote:FireClient(Player, "lungeCd", LUNGE_COOLDOWN)
		DoAttack(true)
		return
	end

	if action ~= "attack" then return end
	DoAttack(false)
end)

-- 🤖 [③ 2026-09-12] 봇 전용 진입점. 리모트를 우회해 서버가 직접 부른다.
--   [규약] 이름은 "BotSkill" 로 통일한다(RunnerBotDriveController 가 이 이름만 찾는다).
--   [왜 리모트를 못 쓰나] 위 핸들러가 `firingPlayer ~= Player` 로 막는데
--     봇은 Player 가 없다. 서버가 그 자리를 대신 채운다.
--   ⚠️ 쿨다운·래그돌 가드는 여기서도 그대로 본다 — 같은 규칙을 두 벌로 만들지 않는다.
--   ⚠️ [알려진 한계] 런지 3회 명중 시 사거리 증강이 붙지만, 봇은 붙어서 때리므로
--     그 효과가 의미가 없다(닿는 거리에 이미 있다). 데미지 26 은 들어간다.
--     거리 운영이 가능해지면 그때 제 값을 한다 — 인계 문서 3-9 참조.
local botSkill = Instance.new("BindableFunction")
botSkill.Name = "BotSkill"
botSkill.OnInvoke = function()
	local now = os.clock()
	if now < lungeReadyAt then return false end
	if not Tool.Enabled or not ToolEquipped or not CheckIfAlive() then return false end
	if Humanoid and Humanoid.PlatformStand then return false end
	lungeReadyAt = now + LUNGE_COOLDOWN
	DoAttack(true)
	return true
end
botSkill.Parent = Tool

Tool.Equipped:Connect(Equipped)
Tool.Unequipped:Connect(Unequipped)

Connection = Handle.Touched:Connect(Blow)
