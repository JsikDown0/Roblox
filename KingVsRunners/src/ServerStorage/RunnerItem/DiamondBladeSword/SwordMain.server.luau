
-- 🔊 [2026-08-25] 연타 시 소리 씹힘 방지.
-- ⚠️ 같은 Sound 에 Play() 를 다시 호출하면 재생 중이던 소리가 되감긴다.
--    평타 쿨이 음원보다 짧으면 소리가 계속 잘린다.
--    → 복제해 재생하고 Debris 로 정리한다.
local __Debris = game:GetService("Debris")
local function playOneShot(template, parent)
	if not template then return end
	local s = template:Clone()
	s.Parent = parent or template.Parent
	s:Play()
	__Debris:AddItem(s, 4)
end

--Redone by Noob3713
--I've been hit with diamond before. it hurts

Tool = script.Parent
Sword = Tool.Handle

Tool.Enabled = true

AnimFolder = Tool.Animations

Trail =Sword.Trail
Trail.Attachment0 = Sword.TrailTop
Trail.Attachment1 = Sword.TrailBottom
Trail.Enabled = true

SP1 = Sword.StarParticsTop.Twinkle
SP2 = Sword.StarParticsBottom.Twinkle
SP1.Enabled = true
SP2.Enabled = true

--ScytheFire = Scythe.FireAT.ScytheFire
--ScytheFire.Enabled = true

Running = game:GetService("RunService")
Debree = game:GetService("Debris")

Remote = (Tool:FindFirstChild("Remote") or Instance.new("RemoteEvent"));Remote.Name = "Remote";Remote.Parent = Tool
MouseInput = Tool.MouseInput

function TagHumanoid(humanoid, player)
	local Creator_Tag = Instance.new("ObjectValue")
	Creator_Tag.Name = "creator"
	Creator_Tag.Value = player
	Debree:AddItem(Creator_Tag, 2)
	Creator_Tag.Parent = humanoid
end

function UntagHumanoid(humanoid)
	for i, v in pairs(humanoid:GetChildren()) do
		if v:IsA("ObjectValue") and v.Name == "creator" then
			v:Destroy()
		end
	end
end

-- team related stuff do not steal

if Tool:FindFirstChild("TeamAttack") then
	Tool.TeamAttack:Destroy()
end

TeamSwitch = Instance.new("BoolValue")
TeamSwitch.Value = false
TeamSwitch.Name = "TeamAttack"
TeamSwitch.Parent = Tool

--setting the value to true will allow teammates to damage eachother
--setting the value to false will prevent it
--the value can be changed manually if you want i guess

function TeamAlly(person)
	Plyr2 = game.Players:GetPlayerFromCharacter(person)
	if TeamSwitch.Value == false and Plyr and Plyr2 and not Plyr.Neutral and Plyr.TeamColor == Plyr2.TeamColor then
		return true
	end
	return false
end

function MinionAlly(tempChar)
	if tempChar:FindFirstChild("Master") ~= nil and tempChar.Master.ClassName == "ObjectValue" and tempChar.Master.Value == Plyr then
		return true
	end
	return false
end

function MinionTeamAlly(tempMinion) -- NOTE: you need the above function for this to work
	TempMaster = tempMinion:FindFirstChild("Master")
	if TempMaster and TempMaster.ClassName == "ObjectValue" and TempMaster.Value and TeamAlly(TempMaster.Value.Character) then
		return true
	end
	return false
end

-- end team related stuff

OrigGrip = nil
OrigGrip2 = nil

CurrentDamage = 22

-- ── 콤보 시스템 (휘두름 기반 + 타이밍 링) ───────────────────
-- 콤보는 "휘두를 때마다" 오른다(헛스윙 셋업 가능 = 잡기술). 단, 직전 휘두름과의 간격이
-- 적정 리듬(MIN~MAX)이어야 유지. 너무 빨리(쿨 직후 연타)거나 늦으면 1타로 리셋.
-- 클라 타이밍 링이 이 윈도우를 시각화 → "보고 맞추는" 숙련도.
-- 하이리스크 하이리턴: 완성 시 피니셔 40이 화끈하게 터짐(합 80), 실패 시 1타(16) 반복.
local COMBO_DAMAGES = {16, 24, 40}   -- 1타 / 2타 / 3타(피니셔). 완성 시 합 80
local COMBO_MIN_GAP = 0.42           -- 직전 휘두름과 이보다 가까우면(연타) 콤보 실패 → 1타
local COMBO_MAX_GAP = 1.20           -- 직전 휘두름과 이보다 멀면 콤보 끊김 → 1타
local COMBO_HOLD    = 1.50           -- 마지막 휘두름 후 이 시간 지나면 콤보 완전 리셋(셋업 방치 방지)
local COMBO_MAX     = 3             -- 피니셔 단계
local comboStep     = 0            -- 현재 콤보 단계(휘두를 때 갱신, 0=시작 전)
local lastSwingTime = 0            -- 마지막 휘두른 시각 (콤보 타이밍 기준)
local ComboDamage   = COMBO_DAMAGES[1]  -- 이번 휘두름의 데미지 (SwordHit이 참조)
local displayStep   = 1            -- 이번 타격 표시용 단계 (피니셔 리셋 전 확정)

-- 타격 윈도우 + 중복 방지 (클래식 소드와 동일 방식)
local canDamage   = false
local HIT_COOLDOWN = 0.5
local lastHitTime  = {}

-- ═══ 세공 표식(Vital Mark) 시스템 — 피오라 궁 스타일 ═══
-- 태거 몸 기준 월드 0/120/240° 3방향 표식. 러너가 그 각도에서 태거를 치면 해당 표식 점등.
-- 3개 다 점등 = 완주(보너스 폭발 + 재생성 — 다음 단계). 각 러너가 자기 표식 세트를 가짐.
local BASE_DAMAGE   = 11    -- 평타
-- ⚠️ [밸런스 2026-08-29] 4 → 11, 표식 폭발 0.40 → 0.08 (세트 조정).
--   Dragon Fire 와 같은 문제·같은 처방이다. 바닥 8 / 천장 46 의 도박 구조를
--   바닥 22 / 천장 28 로 좁힌다.
--     평타 11/0.5 = 22 DPS (표식 실패해도 Rare 목표 23 에 근접)
--     3표식 완주 (33 + 폭발) / 3.5초 → 약 28 DPS
--   ⚠️ '표식 3방향을 돌며 완주한다'는 정체성은 유지된다. 완주 보상이 여전히 크다.
--   ⚠️ 둘 중 하나만 바꾸지 말 것(아래 MARK 폭발 계수와 한 세트).
-- 🔻 [밸런스 2026-09-08] 표식 3 → 2. 완주에 필요한 이동을 절반으로 줄인다.
--   [문제] 판정은 이미 관대했다 — 360° 무결이라 각도가 틀릴 일이 없고,
--     MARK_DURATION 7초가 타격마다 갱신돼 진행이 날아가지도 않는다.
--     그런데도 완주가 어려웠던 건 '각도 맞추기'가 아니라 '킹 주위를 도는 것'이었다.
--       평타 쿨 0.5 + 120° 호 이동 0.65 + 넉백 7.6 복귀 0.48 → 1표식당 1.1~1.3초
--       3표식 완주 3.5초. 그 사이 킹은 평타 7회 + 강타 1회를 쓴다.
--     ⚠️ 넉백은 러너를 킹 '반대쪽'으로 민다 = 거리만 벌어지고 각도는 그대로다.
--       밀려나도 진행에 도움이 안 되는 최악의 조합이었다.
--   [왜 개수인가] 보상(MARK_EXPLODE_PCT)을 아무리 키워도 도달률이 낮으면 의미가 없다.
--     요구를 직접 줄이는 쪽이 정직하다. 2 면 180° 한 번 = 실질 2.3초.
--   ⚠️ MARK_HIT_DOT 을 같이 내려야 한다. 2×180° 라 경계가 cos(90°)=0 이다.
--     0.5 로 두면 좌우 120° 가 사각지대가 되어 표식이 아예 안 켜진다 — 한 세트로 본다.
--   ⚠️ -0.01 인 이유: 정확히 0 이면 경계(딱 옆구리)에서 부동소수점에 따라 갈린다.
--     3개 체계는 0.5 로 여유가 있었지만 2개는 경계가 딱 붙는다. 살짝 음수로 덮는다.
--   ⚠️ VitalMarkClient 에도 MARK_COUNT 가 따로 선언돼 있다(상수 복제).
--     그쪽을 같이 안 바꾸면 표시 3개 / 판정 2개로 어긋난다.
--   ⚠️ 완주가 쉬워진 만큼 폭발 보상(MARK_EXPLODE_PCT 0.08)이 과할 수 있다.
--     이번엔 난이도만 건드리고 보상은 그대로 둔다 — 도달률부터 보고 정한다.
--   ⚠️ 되돌릴 값: MARK_COUNT 3 / MARK_HIT_DOT 0.5
local MARK_COUNT    = 2
local MARK_HIT_DOT  = -0.01  -- 2×180°=360° 무결 (경계 여유 포함)
local MARK_DIRS = {}
for i = 0, MARK_COUNT - 1 do
	local a = math.rad(i * (360 / MARK_COUNT))
	MARK_DIRS[i + 1] = Vector3.new(math.sin(a), 0, math.cos(a))
end
local markState = {}   -- [player] = {false,false,false} (표식별 점등 여부)
local function resetMarks(plr)
	markState[plr] = table.create(MARK_COUNT, false)
	return markState[plr]
end
-- 러너→태거 방향으로 최근접 표식 인덱스 판정 (없으면 nil)
local function nearestMark(runnerPos, taggerPos)
	local dir = Vector3.new(runnerPos.X - taggerPos.X, 0, runnerPos.Z - taggerPos.Z)
	if dir.Magnitude < 0.05 then return nil end
	dir = dir.Unit
	local bestIdx, bestDot = nil, -2
	for i, md in ipairs(MARK_DIRS) do
		local d = dir:Dot(md)
		if d > bestDot then bestDot = d; bestIdx = i end
	end
	if bestIdx and bestDot >= MARK_HIT_DOT then return bestIdx end
	return nil
end
-- ── 완주 폭발 + 시간 만료 ────────────────────────────────────
local MARK_EXPLODE_PCT = 0.065  -- 완주 폭발: 태거 최대체력의 6.5%
-- 🔻 [밸런스 2026-09-09] 0.08 → 0.065 (약 -19%).
--   [왜] 봇 수정(사거리 밖 출격) 후 재측정에서 12.7 DPS 로 전 무기 1위였다.
--     Rare 등급인데 Legendary(KatanaSword2 11.3)보다 높다.
--     사용자가 Epic 승격을 검토 중이라, Epic 상단(10~11) 근처로 내린다.
--   [왜 평타가 아니라 폭발인가] 평타 11 은 표식 실패 시의 바닥값이다.
--     낮추면 무기가 '완주 못 하면 무의미한 도박'이 된다 — 08-29 에 4→11 로
--     올린 이유가 정확히 그것이었다. 바닥은 두고 천장만 깎는다.
--   ⚠️ [남은 문제: 풀피 스케일] 폭발이 MaxHealth 비례라 킹 HP 가 클수록
--     절대 DPS 가 오른다(975 → 78 / 315 → 25). 다른 무기는 HP 무관이라
--     다인전에서 이 무기만 유리해진다.
--     ⚠️ 비율(8%)은 일정하므로 '킬 타임'은 안 변한다 — 절대 DPS 만 스케일한다.
--     이 계수 조정으로는 스케일 자체가 안 없어진다. 없애려면 고정값 전환이
--     필요한데 그건 정체성 변경이라 별도 과제로 둔다.
--   ⚠️ 계산 DPS(약 48)와 측정 DPS(12.7)의 차이가 크다 = 완주가 실제론 드물다.
--     그래서 계수로 역산이 안 된다. 재측정으로 확인할 것.
--   ⚠️ 되돌릴 값: 0.08
-- ⚠️ [밸런스 2026-08-29] 0.40 → 0.08. 위 BASE_DAMAGE 4→11 과 한 세트다.
--   0.40 은 태거 HP 375 부터 상한 150 에 걸려 다인전에서 비율 설계가 죽었다.
--   0.08 이면 825 기준 66 으로 전 구간에서 비율이 살아 있다.
--   ⚠️ Dragon Fire 의 STACK_EXPLODE_PCT 와 같은 구조다. 한쪽만 고치지 말 것.
local MARK_EXPLODE_CAP = 150    -- 폭발 상한 (다인전 폭주 방지)
local MARK_DURATION    = 7      -- 마지막 타격 후 이 시간(초) 안 때리면 표식 리셋(스왑은 유지)
local CYCLE_GAP = 2.0   -- 완주 후 다음 표식 등장까지 틈(초) — 연출 여운 + 리듬 끊기
local markCooldownUntil = {}   -- [player] = 이 시각까지 표식 비활성(완주 직후 틈)
local expireToken = 0
-- 만료 타이머 재장전: 태거 타격마다 호출. MARK_DURATION 동안 추가 타격 없으면 리셋.
local function armExpiry()
	expireToken = expireToken + 1
	local myToken = expireToken
	task.delay(MARK_DURATION, function()
		if myToken ~= expireToken then return end   -- 그 사이 재타격 → 무시
		if Plyr then
			resetMarks(Plyr)
			pcall(function() Remote:FireClient(Plyr, "markReset") end)
		end
	end)
end
-- 완주 여부 (3표식 다 점등)
local function isComplete(marks)
	for i = 1, MARK_COUNT do if not marks[i] then return false end end
	return true
end
-- 표식 점등 성공음: 기존 리듬 콤보 성공음(Crit)을 재활용, 단계별 피치 상승(1→2→3).
local function playMarkChime(hitCount)
	local handle = Tool:FindFirstChild("Handle")
	local base = handle and handle:FindFirstChild("Crit")
	if not base then return end
	local s = base:Clone()
	s.PlaybackSpeed = 0.95 + hitCount * 0.13   -- 1단계 1.08 → 2단계 1.21 → 3단계(완주) 1.34
	s.Volume = (hitCount >= MARK_COUNT) and base.Volume or (base.Volume * 0.55)
	s.Parent = handle
	s:Play()
	game:GetService("Debris"):AddItem(s, 2)
end


Special1 = true
Special2 = true
Special3 = true
DoingSpecial = false

stuff = {}
moreStuff = {}

Deflect = false

function CheckForForcefield(part)
	if part.Parent == game.Workspace or (part.Parent ~= game.Workspace and part.Parent:FindFirstChild("ForceField") == nil) or(part.Parent.Parent ~= game.Workspace and part.Parent.Parent:FindFirstChild("ForceField") == nil) then
		return false
	end
	return true
end

function DiamondStorm()
	DoingSpecial = true
	SpecialAnim = Hum:LoadAnimation(AnimSet.Special)
	if SpecialAnim then SpecialAnim:Play() end
	DS = script.DiamondRainScript:Clone()
	DS.Parent = game.Workspace
	TeamSwitch:Clone().Parent = DS
	TagHumanoid(DS,Plyr)
	DS.Disabled = false
	OrigGrip = Tool.Grip
	Tool.Grip = OrigGrip * CFrame.Angles(math.rad(45),0,0)
	wait(1.7)
	Tool.Grip = OrigGrip
	DoingSpecial = false
	while DS.Parent ~= nil do
		Running.Heartbeat:wait()
	end
end

function ShootingStar()
	--DoingSpecial = true
	--wait(2)
	--DoingSpecial = false
end

InvisoTimer = 600
SaveFire = false

function DoSpecial(Client, Key)
	-- [특수기 비활성 보존] DiamondStorm 등 특수기는 현재 비활성. 나중에 프리미엄 기능으로
	-- 부활시킬 때 아래 return 한 줄만 제거하면 됨. (Q키 산데비스탄 대시 충돌 방지)
	do return end
	if not Client or Client ~= Plyr or not Key or not Tool.Enabled or Hum.Health <= 0 or DoingSpecial then return end
	if Key == Enum.KeyCode.Q then
		if Special1 == true then
			Special1 = false
			SP1.Enabled = false
			SP2.Enabled = false
			DiamondStorm()
			wait(30)
			Special1 = true
			SP1.Enabled = true
			SP2.Enabled = true
		end
	elseif Key == Enum.KeyCode.E then
		if Special2 == true then
			Special2 = false
			--ShootingStar()
			wait(25)
			Special2 = true
		end
	elseif Key == Enum.KeyCode.X then
		if Special3 == true then
			Special3 = false
			--Inviso()
			--wait(20)
			Special3 = true
		end
	end
end

NewAnim = nil
SlashAnim = nil
AnimSpeed = 1

function Swing()
	if Tool.Enabled == true and DoingSpecial == false then
		Tool.Enabled = false

		-- 콤보 단계 판정 (휘두름 기반): 직전 휘두름과의 간격이 적정 리듬이면 단계 증가(셋업 가능),
		-- 너무 빠르거나(MIN 전) 늦으면(MAX 후) 1타로 리셋.
		local now = os.clock()
		local gap = now - lastSwingTime
		if gap >= COMBO_MIN_GAP and gap <= COMBO_MAX_GAP and comboStep < COMBO_MAX and comboStep > 0 then
			comboStep = comboStep + 1
		else
			comboStep = 1
		end
		lastSwingTime = now
		displayStep = comboStep   -- 표시용 확정 (피니셔 리셋 전)

		-- 단계별 데미지 + 애니메이션 (1타 Left, 2타 Right, 3타 피니셔 OverHead)
		ComboDamage = COMBO_DAMAGES[comboStep] or COMBO_DAMAGES[1]
		local animName
		if comboStep == 1 then animName = "LeftSlash"
		elseif comboStep == 2 then animName = "RightSlash"
		else animName = "OverHeadSwing" end

		local chosen = AnimSet:FindFirstChild(animName) or Anims[math.random(1,#Anims)]
		SlashAnim = Hum:LoadAnimation(chosen)
		-- 피니셔는 살짝 느리고 묵직하게, 일반타는 빠르게
		if comboStep == COMBO_MAX then
			AnimSpeed = 1.1
			Sword.Crit:Play()   -- 피니셔에 크릿 사운드
		else
			AnimSpeed = 1.6
		end
		if SlashAnim then SlashAnim:Play(nil, nil, AnimSpeed) end
		playOneShot(Sword.SlashSound)

		-- 타격 윈도우 열기 (휘두르는 동안만 데미지)
		canDamage = true
		task.delay(0.35, function() canDamage = false end)


		-- 피니셔 후엔 콤보 리셋
		if comboStep == COMBO_MAX then
			comboStep = 0
		end

		-- 상한 타이머: 이 휘두름 후 COMBO_HOLD 안에 다음 휘두름 없으면 콤보 완전 리셋(방치 방지)
		local swingStamp = lastSwingTime
		task.delay(COMBO_HOLD, function()
			if lastSwingTime == swingStamp then
				comboStep = 0
			end
		end)

		wait(0.45)
		Tool.Enabled = true
	end
end

function DiamondKill(victim)
	--FF1 = Instance.new("ForceField")
	--FF1.Visible = false
	--FF1.Parent = hit.Parent
	--FF2 = Instance.new("ForceField")
	--FF2.Visible = false
	--FF2.Parent = Char
	--Debree:AddItem(FF2,1)
	stuff = victim:GetDescendants()
	for a = 1,#stuff do
		if stuff[a]:IsA("BasePart") then
			stuff[a]:BreakJoints()
			stuff[a].BrickColor = BrickColor.new("Cyan")
			stuff[a].Material = "Plastic"
			stuff[a].Reflectance = 0.1
			stuff[a].Velocity = CFrame.new(Root.Position,stuff[a].Position).lookVector * 50 + Vector3.new(math.random(-15,15),math.random(20,25),math.random(-15,15))
		end
		if stuff[a].ClassName == "MeshPart" then
			stuff[a].TextureID = ""
			stuff[a].BrickColor = BrickColor.new("Cyan")
		end
		if stuff[a].ClassName == "SpecialMesh" then
			stuff[a].TextureId = ""
		end
		if stuff[a].ClassName == "Shirt" or stuff[a].ClassName == "Pants" then
			stuff[a]:Destroy()
		end
	end
	Sword.Crit:Play()
	--wait(0.5)
	SP = Instance.new("Part")
	SP.Anchored = true
	SP.CanCollide = false
	SP.Transparency = 1
	SP.Size = Vector3.new(0,0,0)
	SP.Position = victim.Head.Position
	SP.Parent = game.Workspace
	Debree:AddItem(SP,3)

	Sparks = script.Sparkles:Clone()
	Sparks.Parent = SP
	Sparks:Emit(150)
	--for b = 1,#charParts do
		--charParts[b].Anchored = false
	--end
	--FF1:Destroy()
	--FF2:Destroy()
	--tempParts = {}
	--charParts = {}
end

Hand = nil
TempHum = nil

tempParts = {}
charParts = {}

Critting = false

function SwordHit(hit)
	if hit == nil or hit.Parent == nil or hit:IsDescendantOf(Char) then return end
	-- 타격 윈도우 체크: 휘두르는 중이 아니면 데미지 없음 (닿기만 한 경우 무시)
	if not canDamage then return end

	local character = hit.Parent
	local TempHum = character:FindFirstChildOfClass("Humanoid")
	if TempHum == nil or TempHum.Health <= 0 then return end

	-- 진영 체크: 러너 무기는 태거만 공격 가능. 아군(러너 플레이어/AI 러너봇) 오사 차단.
	local victimPlayer = game.Players:GetPlayerFromCharacter(character)
	if victimPlayer then
		if victimPlayer == Plyr or victimPlayer:GetAttribute("Role") ~= "Tagger" then return end
	else
		if character:GetAttribute("AIRunner") or character:GetAttribute("RunnerBot")
			or (character.Parent and (character.Parent:GetAttribute("AIRunner") or character.Parent:GetAttribute("RunnerBot"))) then
			return
		end
	end

	-- 같은 대상 중복 타격 방지 (한 스윙에 여러 파트 접촉 → 1회만 적용)
	local now = os.clock()
	local last = lastHitTime[character]
	if last and (now - last) < HIT_COOLDOWN then return end
	lastHitTime[character] = now

	-- 콤보는 Swing(휘두름)에서 이미 정해짐. 여기선 그 데미지를 적용만.
	local hitStep = displayStep
	local isFinisher = (hitStep == COMBO_MAX)

	UntagHumanoid(TempHum)
	TagHumanoid(TempHum, Plyr)
	-- 세공 표식 판정: 러너가 태거의 어느 각도에서 쳤나 → 최근접 표식 점등
	local taggerRoot = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart or character:FindFirstChild("Torso")
	if Plyr and Root and taggerRoot and not (markCooldownUntil[Plyr] and os.clock() < markCooldownUntil[Plyr]) then
		local marks = markState[Plyr] or resetMarks(Plyr)
		armExpiry()   -- 태거 때리는 중엔 만료 갱신 (같은 각도 반복이라도)
		local idx = nearestMark(Root.Position, taggerRoot.Position)
		if idx and not marks[idx] then
			marks[idx] = true
			local hitCount = 0
			for i = 1, MARK_COUNT do if marks[i] then hitCount = hitCount + 1 end end
			Remote:FireClient(Plyr, "markHit", idx, hitCount)   -- idx=점등 표식, hitCount=현재 타수(1/2/3)
			playMarkChime(hitCount)   -- 단계별 상승 성공음 (리듬 콤보 Crit 재활용)
			-- 완주: 3표식 다 점등 → 프리즘 폭발(%+캡) + 리셋/재생성
			if isComplete(marks) then
				local dmg = math.min(MARK_EXPLODE_CAP, TempHum.MaxHealth * MARK_EXPLODE_PCT)
				if not (_G.IsDamageImmune and _G.IsDamageImmune(TempHum.Parent)) then
				TempHum:TakeDamage(dmg) end
				-- 완주 연출: 표식 깨짐 + 태거 감싸는 다이아 셸 등장→깨짐 (클라에서 재생, 사운드 포함)
				Remote:FireClient(Plyr, "markComplete")
				-- 완주 후 틈: 표식 숨김 → CYCLE_GAP 후 재등장
				markState[Plyr] = nil
				markCooldownUntil[Plyr] = os.clock() + CYCLE_GAP
				Remote:FireClient(Plyr, "markClear")
				local plr = Plyr
				task.delay(CYCLE_GAP, function()
					if plr and plr.Parent and (markCooldownUntil[plr] or 0) <= os.clock() then
						resetMarks(plr)
						pcall(function() Remote:FireClient(plr, "markSync", markState[plr]) end)
					end
				end)
			end
		end
	end
	if _G.IsDamageImmune and _G.IsDamageImmune(TempHum.Parent) then return end
	TempHum:TakeDamage(BASE_DAMAGE)  -- 평타(약함) — 완주 폭발이 주력(다음 단계)

	-- 데미지/콤보 표시: 공격자 클라이언트로 타격 정보 전송 (튀어오르는 숫자 + 콤보 카운터)
	if Plyr then
		local hitPos = (hit.Position or (Root and Root.Position) or Vector3.new())
		-- 🔢 CC 중이면 화면 숫자를 실효값으로 환산한다(판정은 원본 그대로).
		Remote:FireClient(Plyr, "hitFX",
			(_G.DisplayDamage and _G.DisplayDamage(TempHum.Parent, BASE_DAMAGE)) or BASE_DAMAGE,
			hitStep, isFinisher, hitPos)
	end
end

IgnoreDamage = false
NewHealth = 100

DamageReducer = .3

function ReduceDamage()
	NewHealth = Hum.Health
	if not IgnoreDamage and NewHealth ~= Hum.MaxHealth and NewHealth > 0 then
		if NewHealth < CurrentHealth then
			local DamageDealt = (CurrentHealth - NewHealth)
			IgnoreDamage = true
			Hum.Health = Hum.Health + (DamageDealt * DamageReducer)
			IgnoreDamage = false
		end
	end
	CurrentHealth = NewHealth
end

CurrentHeath = 100

Char = nil
Hum = nil
Plyr = nil
Root = nil
AnimSet = nil
function Equip()
	Char = Tool.Parent
	Hum = Char:FindFirstChild("Humanoid")
	Plyr = game.Players:GetPlayerFromCharacter(Char)
	Root = Char:FindFirstChild("HumanoidRootPart") or Char:FindFirstChild("Torso")
	AnimSet = AnimFolder:FindFirstChild(Hum.RigType.Name)  -- EnumItem → 문자열("R6"/"R15")
	Anims = {AnimSet.LeftSlash,AnimSet.RightSlash,AnimSet.OverHeadSwing}
	
	EquipAnim = Hum:LoadAnimation(AnimSet.Equip)
	if EquipAnim then EquipAnim:Play(nil, nil, 1.6) end
	
	Sword.EquipSound:Play()
	-- 세공 표식 초기화 + 클라 렌더 시작 (자기 표식만 클라에서 그림)
	-- 🐛 [버그수정 2026-09-05] 장착 시 표식이 안 보였다.
	--   [원인] 여기서 markState[Plyr] 를 '읽기만' 하고 초기화하지 않았다. 첫 장착이면
	--     그 값이 nil 이라 markSync 에 nil 이 실려 나가고, 클라는 그릴 데이터가 없다.
	--     resetMarks 가 불리는 세 곳(만료 타이머 / 타격 처리 / 완주 후)이 전부
	--     '이미 한 번 때린 뒤'라, 때리기 전까지는 표식이 존재하지 않았다.
	--   ⚠️ 주석은 "표식 초기화"라고 적혀 있었지만 실제로는 초기화 코드가 없었다 —
	--     주석과 동작이 어긋난 자리다.
	--   [규칙] 완주 직후 틈(CYCLE_GAP) 중에는 초기화하지 않는다. 그 구간은 의도적으로
	--     표식을 숨기는 시간이라(markClear 로 지움), 여기서 되살리면 연출이 깨진다.
	if Plyr then
		if not markState[Plyr] and (markCooldownUntil[Plyr] or 0) <= os.clock() then
			resetMarks(Plyr)
		end
		Remote:FireClient(Plyr, "markSync", markState[Plyr])
	end
	
	--DamageDodge = Hum.Changed:connect(ReduceDamage)
	--CurrentHealth = Hum.Health
	--Ghostify(Char,0.5)
end

function Unequip()
	if Plyr then Remote:FireClient(Plyr, "markClear") end
	--DamageDodge:Disconnect()
	if EquipAnim then EquipAnim:Stop() end
end

Tool.Equipped:Connect(Equip)
Tool.Unequipped:Connect(Unequip)
Tool.Activated:Connect(Swing)
Sword.Touched:Connect(SwordHit)
Remote.OnServerEvent:Connect(DoSpecial)
