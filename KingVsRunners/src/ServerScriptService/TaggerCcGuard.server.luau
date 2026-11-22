-- ═══════════════════════════════════════════════════════════════
-- 🛡️ TaggerCcGuard — CC 당한 태거가 받는 피해를 줄인다.
--
-- [왜] 마이크밤(8초)·아이스보우(3초)로 킹을 묶어두면 반격을 못 하는 동안
--   러너 전원이 무료로 두들긴다. 2026-09-02 실측(08:02:21~29, easy 티어):
--     콘서트 8초 동안 킹이 16회 피격 → 697 → 537 (초당 20).
--   킹이 못 때리니 오히려 평소보다 더 맞았다.
--
-- [왜 MicBombSystem 의 콜리전 격리로는 안 되나]
--   그쪽 주석(409행)은 "물리적으로 안 닿게 하면 근접 판정이 원천 차단된다"고 적었지만
--   전제가 틀렸다. 콜리전 그룹은 Touched / GetPartsInPart 만 막는다.
--   러너 무기는 거리(magnitude) 판정이라 그대로 통과한다 — 위 실측이 그 증거다.
--   ⚠️ 러너가 마이크밤을 맞았을 때의 8초 무적은 의도된 동작이라 건드리지 않는다.
--     이 스크립트는 '태거일 때만' 작동한다.
--
-- [방식] MaxHealth·Health 를 같은 배율로 올린다. 들어오는 피해는 절대값이므로
--   최대체력이 2배면 비율상 정확히 절반이 된다.
--     CC 시작: 480/480 → 960/960
--     8초간 160 피격 → 800/960  (= 400/480 상당)
--     CC 종료: 800/960 → 400/480
--   [왜 사후 환불이 아닌가] 환불 방식(맞은 뒤 절반 되돌리기)은 체력바가 떨어졌다
--     튀어오르고, 죽는 타격을 못 막는다(되살리면 좀비가 된다). 배율은 둘 다 없다.
--     비율이 그대로라 체력바는 아예 움직이지 않는다.
--
-- ⚠️ 대입 순서가 중요하다. 올릴 땐 MaxHealth 먼저, 내릴 땐 Health 먼저.
--   반대로 하면 Roblox 가 Health 를 현재 Max 에 클램프해 체력이 통째로 잘린다.
-- ⚠️ 선행 조건: TaggerBotSystem 의 HealthChanged 핸들러에 lastMax 가드가 있어야 한다.
--   없으면 배율 복원(960→480)이 "킹 피격 -480"으로 오독돼 위협이 폭주한다.
-- ⚠️ Stage2TriggerSystem 의 성문 붕괴 HP 재산정이 CcHpScale 을 읽어 같이 곱한다.
--   아이스보우는 관통이라 그 순간 Frozen 이 살아 있을 수 있다.
-- ═══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")

-- 🎤❄️ [2026-09-02] CC 종류별 감소율. 마이크밤과 아이스보우는 성격이 다르다.
--   · 마이크밤 8초 / 완전 이동 봉쇄 → 50% 감소 (원래 '완전 면역'이던 것을 완화한 값)
--   · 아이스보우 3초 / Tool 봉인 + 슬로우(16→12) → 30% 감소
--   [왜 다르게] 아이스보우는 원래 피해 감소가 없던 아이템이다. 마이크밤 면역을 50%로
--     바꾸면서 같은 상수를 공유하게 됐는데, 3초짜리 가벼운 CC 에 8초짜리와 같은
--     보호를 주는 건 신설 너프였다. 잔탄 2발이라 총 6초지만 실측상 나눠 쓴다
--     (11:31 / 11:38 — 9초 간격). 즉 한 번에 버는 시간은 3초다.
--   ⚠️ 점령 감속(CaptureSystem.CC_FILL_MULT 0.1)은 두 아이템 공통으로 유지한다.
--     그쪽을 완화하면 무료 점령이 다시 열린다 — 오늘 이미 반대 방향으로 한 번 겪었다.
local CC_SCALE_MICBOMB = 2.0     -- 피해 50% 감소
local CC_SCALE_FROZEN  = 1.43    -- 피해 30% 감소 (1 / 1.43 ≈ 0.70)
local SCAN_INTERVAL    = 0.5     -- 태거 탐색 주기(초)
local MAX_CC_HOLD      = 15      -- 안전 상한(초). CC 최장이 8초라 이보다 길면 이상 상황이다.

-- [character] = 적용 중인 배율(숫자). nil 이면 미적용.
--   ⚠️ true 가 아니라 '값'을 담는다. 복원할 때 걸었던 배율 그대로 나눠야 하는데,
--     상수를 참조하면 종류가 바뀐 뒤 엉뚱한 값으로 나누게 된다.
local scaled = setmetatable({}, { __mode = "k" })

-- 아이스보우=Frozen / 마이크밤=MicBombed. 속성이 서로 다르다
-- (MicBombSystem 400행: Frozen 을 재사용하면 그쪽 8초 안전망이 콘서트와 겹쳐
--  봉인한 Tool 을 멋대로 복구한다).
-- ⚠️ 둘 다 걸려 있으면 강한 쪽(마이크밤)만 쓴다. 곱하지 않는다 —
--   65% 감소는 의도한 적 없는 값이고, 겹침은 드물지만 가능하다.
-- 🛡️ [2026-09-02] CC 재적용 면역.
--   [증상] 러너 11명이 마이크밤(8초)·아이스보우(3초)·에어본(1.2초)·카타나 스턴(0.5초)을
--     이어붙이면 킹이 2단계 내내 아무것도 못 하고 끝난다. 소모품 둘은 쿨다운이 없어
--     인원수만큼 그대로 누적된다.
--   [왜 '지속 단축'이 아니라 '면역'인가] 지속을 줄이면 러너가 던지는 시점에 결과를
--     알 수 없다(8초일지 4초일지). 결정론적인데 무작위로 느껴지는 게 제일 나쁜 불투명함이다.
--     면역은 걸리나/안 걸리나 두 상태뿐이라 표시 하나로 예고할 수 있고, 태거베이스
--     면역(_G.showBaseImmune)과 같은 문법이라 학습 비용도 없다.
--     구현도 여기 한 곳에서 끝난다 — 거는 쪽(마이크밤·아이스보우·해머·카타나) 코드를
--     하나도 건드리지 않는다. 지속 단축은 CC 마다 방식이 달라 누더기가 된다
--     (마이크밤은 무대·애니·사운드가 8초 고정이라 애초에 못 줄인다).
--   [값] 면역 시간 = 직전 CC 지속 × IMMUNE_RATIO. 상수 하나로 모든 CC 가 커버된다.
--     마이크밤 8초 → 6초 / 아이스보우 3초 → 2.25초 / 에어본 1.2초 → 0.9초
--   ⚠️ 에어본 연쇄(5명이 6초 쿨을 엇갈려 돌리기)는 이걸로 못 막는다. 의도적이다 —
--     그 정도로 조직화된 팀에게는 져도 된다는 설계 판단이다. 나중에 막아야 하면
--     최소 면역 시간 하한 상수만 추가하면 된다.
local IMMUNE_RATIO = 0.75

-- [character] = CC 가 걸린 시각. 해제 시점에 지속을 역산해 면역 시간을 정한다.
local ccStartedAt = setmetatable({}, { __mode = "k" })
local immuneToken = setmetatable({}, { __mode = "k" })   -- 중복 해제 방지

-- 지금 킹이 CC 에 묶여 있는가. 종류를 구분하지 않고 '묶였다'는 사실만 센다.
--   ⚠️ 종류별로 나누면 순환 콤보가 성립한다(에어본 → 마이크밤 → 아이스보우 → 에어본…).
--     각 카운터가 1회차라 감쇠가 한 번도 안 걸린다. 그래서 통합해서 본다.
--   ⚠️ [2026-09-13] HammerStunned 를 Humanoid → Character 로 옮겼다. 표식 5종 중 이것만
--     Humanoid 에 붙어 있었고, 그래서 라운드 정리 그물(RoundSystem·RoundStateResetServer)에
--     한 번도 안 걸렸다 — 정리 경로 0곳이었다. 이제 다섯이 전부 Character 에 있다.
--     소유권도 WalkSpeedManager 의 flags 축이 쥔다(HammerHigh 이관과 한 짝).
local function ccActive(char, hum)
	return char:GetAttribute("MicBombed") == true
	    or char:GetAttribute("Frozen") == true
	    or char:GetAttribute("Stunned") == true
	    or char:GetAttribute("Grabbed") == true
	    or char:GetAttribute("HammerStunned") == true
end

-- 🛡️ CC 면역 여부. CC 를 거는 쪽이 발동 직전에 부른다.
--   ⚠️ 이 함수만으로는 아무것도 막지 못한다. 속성은 표식일 뿐이고 실제 효과(무대 소환,
--     Tool 봉인, 부양)는 각 시스템이 직접 실행하기 때문이다. 반드시 거는 쪽에서
--     "면역이면 발동하지 않는다"를 지켜야 한다 — _G.IsDamageImmune 과 같은 형태다.
_G.IsCcImmune = function(character)
	if not character then return false end
	return character:GetAttribute("CcImmune") == true
end

local function ccScaleFor(char)
	if char:GetAttribute("MicBombed") == true then return CC_SCALE_MICBOMB end
	if char:GetAttribute("Frozen") == true then return CC_SCALE_FROZEN end
	return nil
end

-- 🩹 HP 를 다시 쓰는 동안 표식을 세운다.
--   [왜] TaggerBotSystem 의 피격 관찰자는 HP 감소를 전부 '피격'으로 읽는다. 그쪽의
--     기본 가드는 'h >= MaxHealth'(꽉 찬 상태로 끝나는 변화 = 전투 아님)인데,
--     배율 복원은 부분값으로 끝난다(800/960 → 400/480). 그래서 표식이 따로 필요하다.
--   ⚠️ task.defer 로 끈다. 대입이 만든 HealthChanged 들이 큐에서 빠져나간 뒤에 꺼져야
--     한다. 즉시 끄면 관찰자가 표식을 못 보고 유령 피격을 찍는다.
local function rewriteHp(char, fn)
	char:SetAttribute("HpRewrite", true)
	fn()
	task.defer(function()
		if char.Parent then char:SetAttribute("HpRewrite", nil) end
	end)
end

local function applyScale(char, hum, scale)
	if scaled[char] then return end
	scaled[char] = scale
	char:SetAttribute("CcHpScale", scale)   -- Stage2TriggerSystem·TaggerHpDisplay 가 읽는다
	rewriteHp(char, function()
		hum.MaxHealth = hum.MaxHealth * scale   -- ⚠️ Max 먼저
		hum.Health    = math.min(hum.MaxHealth, hum.Health * scale)
	end)

	-- 🕒 안전 상한. CC 해제 신호를 놓쳐 배율이 영구히 남는 걸 막는다
	--    ("켜는 코드에는 끄는 코드를 같이" — 여기선 신호 유실까지 대비한다).
	task.delay(MAX_CC_HOLD, function()
		local s = scaled[char]
		if s and char.Parent then
			warn("⚠️ [CcGuard] CC 배율이 " .. MAX_CC_HOLD .. "초 넘게 남아 강제 복원: " .. char.Name)
			local h2 = char:FindFirstChildOfClass("Humanoid")
			if h2 then
				scaled[char] = nil
				char:SetAttribute("CcHpScale", nil)
				-- ⚠️ removeScale 과 같은 대입이다. 표식도 똑같이 세워야 한다 —
				--   한쪽만 고치면 강제 복원 때만 유령 피격이 남는다.
				rewriteHp(char, function()
					h2.Health    = h2.Health / s
					h2.MaxHealth = h2.MaxHealth / s
				end)
			end
		end
	end)
end

local function removeScale(char, hum)
	local s = scaled[char]
	if not s then return end
	scaled[char] = nil
	char:SetAttribute("CcHpScale", nil)
	rewriteHp(char, function()
		hum.Health    = hum.Health / s      -- ⚠️ Health 먼저
		hum.MaxHealth = hum.MaxHealth / s
	end)
end

local function evaluate(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	-- 🛡️ CC 시작/종료를 잡아 면역 시간을 건다. 지속을 실측으로 역산하므로
	--   CC 종류가 늘어나도 ccActive 에 속성만 추가하면 된다.
	local active = ccActive(char, hum)
	if active and not ccStartedAt[char] then
		ccStartedAt[char] = os.clock()
	elseif not active and ccStartedAt[char] then
		local dur = os.clock() - ccStartedAt[char]
		ccStartedAt[char] = nil
		local immuneFor = dur * IMMUNE_RATIO
		if immuneFor > 0.05 then
			char:SetAttribute("CcImmune", true)
			local token = (immuneToken[char] or 0) + 1
			immuneToken[char] = token
			task.delay(immuneFor, function()
				-- ⚠️ 토큰으로 최신 면역만 해제한다. 안 그러면 짧은 CC 의 해제가
				--   그 뒤에 걸린 긴 면역을 조기에 꺼버린다.
				if immuneToken[char] == token and char.Parent then
					char:SetAttribute("CcImmune", nil)
				end
			end)
		end
	end

	local want = ccScaleFor(char)
	local cur  = scaled[char]
	-- 배율이 바뀌는 경우(아이스보우 중에 마이크밤이 겹치는 등)는 먼저 원복하고 다시 건다.
	-- 안 그러면 걸었던 값과 다른 값으로 나누게 되어 HP 가 어긋난다.
	if cur and cur ~= want then
		removeScale(char, hum)
		cur = nil
	end
	if want and not cur then applyScale(char, hum, want) end
end

local function hook(char)
	if char:GetAttribute("_CcGuardHooked") then return end
	if not char:FindFirstChildOfClass("Humanoid") then return end
	char:SetAttribute("_CcGuardHooked", true)

	char:GetAttributeChangedSignal("Frozen"):Connect(function() evaluate(char) end)
	char:GetAttributeChangedSignal("MicBombed"):Connect(function() evaluate(char) end)
	-- 🛡️ 스턴·에어본도 '묶임'이다. 면역 카운터는 종류를 안 가린다.
	char:GetAttributeChangedSignal("Stunned"):Connect(function() evaluate(char) end)
	char:GetAttributeChangedSignal("Grabbed"):Connect(function() evaluate(char) end)
	-- ⚠️ [2026-09-13] HammerStunned 도 Character 속성이 됐다(ccActive 주석 참조).
	--   예전엔 Humanoid 에 붙어서 여기만 hum0 을 따로 잡았다. 그 분기가 사라졌다.
	char:GetAttributeChangedSignal("HammerStunned"):Connect(function() evaluate(char) end)
	evaluate(char)   -- 훅 시점에 이미 CC 중일 수 있다
end

-- 👑 유저 태거 + KING 봇을 모두 훑는다.
--   ⚠️ 봇은 진짜 Player 가 아니라 workspace 의 Model 이다. Role 속성으로 찾는다
--     (FirePressureSystem.forEachTagger 와 같은 규약 — 이름 하드코딩보다 안전).
--   ⚠️ GetPlayerFromCharacter 가드 필수. 유저 태거 캐릭터도 workspace 의 Model 이라
--     이게 없으면 두 루프에 중복으로 잡힌다.
task.spawn(function()
	while true do
		task.wait(SCAN_INTERVAL)
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr:GetAttribute("Role") == "Tagger" and plr.Character then
				hook(plr.Character)
			end
		end
		for _, m in ipairs(workspace:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("Role") == "Tagger"
			   and not Players:GetPlayerFromCharacter(m) then
				hook(m)
			end
		end
	end
end)

print(string.format("🛡️ TaggerCcGuard 준비 (마이크밤 %.0f%% / 아이스보우 %.0f%% 피해 감소 — MaxHealth 배율 방식)",
	(1 - 1 / CC_SCALE_MICBOMB) * 100, (1 - 1 / CC_SCALE_FROZEN) * 100))
