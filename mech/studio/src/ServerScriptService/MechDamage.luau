-- MechDamage: "누가 누구를 다치게 할 수 있나" 판단은 여기 한 곳(2026-10-25)
-- 라이플(MechServer·MechEnemy)·빔사벨(meleeStrike)·미사일(직격·근접 신관·스플래시)이 전부 canDamage 로 묻는다.
-- 지금은 팀이 없어서 "나 말고 전부". 팀이 생기면 teamOf 만 고치면 모든 무기가 같이 따라온다.
--   팀 출처(속성 우선): 모델 속성 Team → 조종사 Player.Team(Neutral 이면 없음). 이름·클래스로 판별하지 않는다
-- ⚠️ 자기 피해(미사일 근접 스플래시)는 canDamage 가 허용하지 않는다(victim == attacker 는 false).
--    자기 피해를 주는 쪽이 victim == attacker 를 따로 다룬다(MechServer missileSplash)
-- ⚠️ 가해자가 없는 피해(시험장 피해 발판)는 이걸 거치지 않는다
local Players = game:GetService("Players")
local M = {}

function M.teamOf(model)
	if typeof(model) ~= "Instance" then return nil end
	local t = model:GetAttribute("Team")
	if t ~= nil then return t end
	local pilot = model:GetAttribute("Pilot")
	local plr = (pilot and Players:GetPlayerByUserId(pilot)) or Players:GetPlayerFromCharacter(model)
	if plr and plr.Team and not plr.Neutral then return plr.Team end
	return nil
end

-- attacker = 쏜/벤 기체(모델), victim = Humanoid 를 가진 모델
function M.canDamage(attacker, victim)
	if typeof(victim) ~= "Instance" or victim == attacker then return false end
	local a, b = M.teamOf(attacker), M.teamOf(victim)
	if a ~= nil and a == b then return false end   -- 같은 팀
	return true
end

-- ================= 10-30 궁극기 공용 게이지(규칙·수치 = MechConfig CFG.Ult) =================
-- 가해자가 있는 피해는 전부 M.hurt 로 준다(MechServer 사격·근접·미사일 직격/스플래시·센서 지뢰 · MechEnemy 사격).
--   판정이 끝난 뒤 실제로 깎인 HP(넘친 피해 X)만큼: 가해자 += 준 피해 · 피해자 += 받은 피해 × TakenMul.
--   자기 피해(attacker == victim, 미사일 근접 스플래시)는 안 셈 — 내 발밑에 쏴서 게이지를 채우지 못하게.
--   가해자 없는 피해(시험장 피해 발판)는 이 함수를 안 거침 → 안 참.
-- ⚠️ HealthChanged 로 세지 않는다: 값이 변한 것(재산정·회복·원복)까지 피격으로 읽힌다(프로젝트 교훈). 피해를 주는 곳에서 직접 센다
local CFG = require(game:GetService("ReplicatedStorage"):WaitForChild("MechProto"):WaitForChild("MechConfig"))
function M.addUlt(m, v)
	if typeof(m) ~= "Instance" or not m:GetAttribute("IsMech") or v <= 0 then return end
	if CFG.ultPhase(m) or CFG.trapPhase(m) or CFG.leapPhase(m) or CFG.chargePhase(m) then return end   -- 10-30 FELSEN 도약 중에도 안 참   -- 궁극기 쓰는 동안은 안 참
	local cur = m:GetAttribute("UltGauge") or 0
	if cur >= CFG.Ult.Max then return end
	m:SetAttribute("UltGauge", math.min(CFG.Ult.Max, cur + v))
end
-- 돌려주는 값 = 실제로 깎인 HP
function M.hurt(attacker, victim, h, amount)
	if not (h and h.Health > 0) then return 0 end
	local before = h.Health
	h:TakeDamage(amount)
	local dealt = math.clamp(before - math.max(0, h.Health), 0, amount)   -- 넘친 피해 X(HP 가 0 아래로 적혀도 0 까지만)
	if dealt > 0 and attacker ~= nil and attacker ~= victim then
		M.addUlt(attacker, dealt)
		M.addUlt(victim, dealt * CFG.Ult.TakenMul)
	end
	return dealt
end

return M
