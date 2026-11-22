-- ThroneExhaustSystem - wangjwa sangsil hu jugijeok talijin (jugi = DURATION + CYCLE)
--
-- [why] Capture no longer wins outright; it strips the king's authority.
--   The chained king periodically collapses (same exhaustion pose runners get
--   after a Q dash), giving runners a guaranteed 1s opening. Shared motion is
--   the point: "the king has come down to your level".
--
-- [numbers] cycle 8s / duration 1.0s / speed 6 / cannot attack
--   8s x 1.0s = 12.5% of time disabled. Over a 45s fight that is 5-6 windows,
--   about 10-12 free hits for runners. Strong but not an execution: 87.5% of
--   the time the king is normal and can still win.
--
-- [why not slower/faster]
--   6s collides with the runner dash cooldown (also 6s) and the rhythms blur.
--   Below 6s it stops being an event and becomes a permanent debuff.
--
-- [CC rules] Reuses the existing Stunned attribute + TaggerCcGuard immunity.
--   [warn] Do NOT invent a new CC type. TaggerCcGuard's comment is explicit:
--     splitting CC by category enables rotation combos (airborne -> mic -> bow
--     -> airborne) where no diminishing return ever applies.
--   If the king is CC-immune when the timer fires we SKIP and restart the timer
--   (option B). Retrying immediately would chain-CC through the immunity window,
--   which is exactly what the immunity exists to prevent.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Tell the king's own client when a burst starts, so it can run a countdown to
-- the next one. Knowing WHEN it lands is what turns this from "my controls
-- randomly break" into something he can plan around.
--   [warn] Bots have no client. FireClient needs a real Player instance -
--     guard with Players:GetPlayerFromCharacter or it errors on bot rounds.
local function notifyKing(char, phase, seconds)
    local ev = ReplicatedStorage:FindFirstChild("ThroneExhaustEvent")
    if not ev then return end
    local plr = Players:GetPlayerFromCharacter(char)
    if plr then ev:FireClient(plr, phase, seconds) end
end
local RunService    = game:GetService("RunService")

-- [tuning 2026-09-05 v2] Reworked after playtest: "the window is too short to
--   set up a counterattack".
--   v1 was 8s cycle / 1.0s burst and nothing else. The burst was over before the
--   runner could close distance, so it read as a hiccup rather than an opening.
--   v2 splits the debuff into two layers:
--     * a PERMANENT slow, so the king is worse off the whole time (and runners can
--       actually reach him), and
--     * a longer burst on a slightly longer cycle, so each opening is usable.
--   Disabled fraction: 1.5 / 9 = 16.7% (was 12.5%). Still 83% normal - not an execution.
-- 🔻 [밸런스 2026-09-20] 8.0 → 10.0 → 12.0. 탈진 주기를 늘려 킹 압박을 완화한다.
--   [시도했다 되돌림] 12.0 을 한 번 넣었다가 10.0 으로 되돌렸다(같은 날, 몇 분 차).
--     12.0 이 원래 초기값이라는 제작자 증언이 있다.
--     ⚠️ 그런데 이 파일에 12 의 흔적이 없다. 헤더가 "8cho jugi" 였고 [numbers] 블록도
--       8 기준이라, 12 → 8 로 내린 시점과 근거가 **어디에도 안 남아 있다.**
--       값이 조용히 흘러내린 사례다 — 앞으로 이 상수를 바꾸면 반드시 여기 한 줄 남길 것.
--   [무엇이 바뀌나] CYCLE 은 '회복 구간'(탈진이 끝난 뒤의 자유 시간)이지 발동 간격이 아니다.
--     실제 발동 주기 = DURATION + CYCLE.
--       8.0 → 주기 9.5초  / 무력화 15.8%
--      10.0 → 주기 11.5초 / 무력화 13.0%   ← 지금
--      12.0 → 주기 13.5초 / 무력화 11.1%   (초기값. 09-20 에 잠깐 복귀했다 되돌림)
--   ⚠️ 아래 [numbers] 주석의 "8s x 1.0s = 12.5%" 는 낡았다 — DURATION 이 1.0 → 1.5 로
--     바뀐 뒤로 안 고쳐졌다. 비율은 주석이 아니라 두 상수에서 계산할 것.
--   ⚠️ 하한은 6초다(아래 [why not slower/faster]): 러너 대시 쿨과 같아져 리듬이 뭉개진다.
--     늘리는 방향은 그 제약과 무관하다.
--   ⚠️ 되돌릴 값: 8.0 (오늘 아침까지의 값). 초기값은 12.0.
-- ⛓️ [밸런스 2026-09-21] 탈진 버스트 OFF.
--   [왜] 태거 이탈률이 문제다 — "태거 걸린 애들은 높은 확률로 다음 판 안 하고 이탈한다.
--     현재 태거 포지션은 그냥 동네북"(제작자 관찰, 09-20 라이브).
--   [무엇이 남는가] 이 파일은 붕괴 후 페널티를 **세 겹**으로 건다. 끄는 건 ③ 하나다:
--     ① 출혈    BLEED_PCT 1.2%/초 — 만피 975 기준 83초에 사망      → 유지
--     ② 상시 감속 SLOW_SPEED 12 (성문 붕괴가 이미 14로 깎은 뒤)      → 유지
--     ③ 탈진 버스트 10초마다 1.5초 속도 6 + Stunned(공격 불가)        → ★ 끔
--     셋 중 ③ 만 '조작 불능'이다. ①② 는 불리해질 뿐 계속 플레이할 수 있다.
--     이탈을 만드는 건 불리함이 아니라 조작을 뺏기는 쪽이라고 보고 여기를 골랐다.
--   ⚠️ [추측] 이탈 원인이 ③ 이라는 건 아직 측정된 게 아니다. 관찰과 형태 추론이다.
--     껐는데 이탈이 그대로면 원인은 ①② 나 결투 국면 자체에 있다 — 그때 다시 나눈다.
--   ⚠️ true 로 되돌리면 그대로 복구된다. 루프·HUD·CC 연동은 하나도 안 지웠다.
--   ⚠️ 러너 쪽 보상이 사라진다: 붕괴의 대가가 출혈·감속뿐이라 "점령하면 확실한 딜 타임"이
--     없어진다. 러너가 킹을 못 잡겠다고 하면 그건 이 변경의 부작용이다.
local BURST_ENABLED  = false

local CYCLE          = 10.0
local DURATION       = 1.5
local EXHAUST_SPEED  = 6      -- during the burst
-- [why 12] Runner base speed is 16. At 18 the king outruns them and can disengage
--   at will; at 14 the runner can create and hold distance, which is what "prepare
--   a counterattack" needs. Below 12 the king can do nothing at all - that is a
--   confirmed loss, not a debuff. 12 is therefore the floor, not a safe middle.
-- 🐛 [2026-09-11] 14 → 12. 이 층은 유저 킹에게 통째로 no-op 였다.
--   [증상] 왕좌가 무너져도 속도 변화가 0이라 붕괴가 몸으로 안 읽혔다. 첫 버스트(3초 뒤)
--     전까지는 붕괴 전과 완전히 동일했다.
--   [원인] Stage2TriggerSystem 의 [STAGE2-TAGGER-SLOW] 가 성문 붕괴 때 이미 14 로 깎는다.
--     keeper 루프는 `WalkSpeed > SLOW_SPEED` 일 때만 쓰므로 14 > 14 = false, 영원히 안 돈다.
--     09-11 로그에 붕괴~첫 버스트 사이 🏃 [WS] 가 한 줄도 없는 것이 그 증거다.
--   [왜 여기를 내리나] 성문 붕괴 감속(14)을 되돌려 결투 국면을 동속 16 으로 만드는 안도
--     검토했지만 기각했다 — Stage2TriggerSystem:410 이 동속에서는 추격이 수학적으로
--     불가능함을 이미 기각해 뒀고, 무엇보다 왕좌를 안 무너뜨리는 게 킹의 승리 조건이라
--     "킹이 이기고 있을 때만 감속이 안 걸리는" 역보상이 된다.
--   ⚠️ 봇 킹은 zone rush 가 18 을 쓰므로 keeper 가 18 → 12 로 끌어온다(전엔 14).
--     봇 킹 쪽 체감이 유저 킹보다 크게 바뀐다.
--   ⚠️ 로비 복원은 Stage2Slowed 속성으로 돈다. 그 속성은 성문 붕괴 감속이 세우므로
--     이 값만 바꾸는 한 추가 작업이 없다. 성문 붕괴 감속을 지우면 그때는 여기서 세워야 한다.
local SLOW_SPEED     = 12     -- permanent, from throne fall until round end (14 → 12, 2026-09-11)

-- 🩸 [2026-09-06] 저주검 출혈. "시간을 끌면 이제 네가 진다"는 압박이 목적이다.
--   [문제] 탈진과 감속은 캠핑을 막지 못한다. 둘 다 '이동'과 '간헐적 무력화'를 건드리는데,
--     캠핑은 애초에 안 움직이는 전략이다. 축이 어긋나 있다.
--     그리고 점령이 승리가 아니게 되면서 킹이 문턱에 눌러앉을 이유는 오히려 늘었다.
--   [해결] 시계를 킹에게도 건다. 가만히 있으면 죽는다 — 캠핑의 전제 자체를 무너뜨린다.
--   [왜 최대HP 비례인가] 킹 HP 는 생존 러너 수로 480~975 까지 벌어진다. 고정값이면
--     11명 판에서는 무의미하고 3명 판에서는 처형이 된다. 비율이어야 판마다 같게 읽힌다.
--   [왜 1.2%] 만피 975 기준 83초. 라운드 총 150초이고 붕괴는 보통 2단계 30~70초에
--     일어나므로, 남은 시간(40~80초) 안에 들어온다. 실제로는 붕괴 시점에 HP 가
--     이미 깎여 있어 훨씬 짧다(실측 13:47 판이면 17초).
--   ⚠️ 1.0% 는 만피에서 100초로 라운드를 넘긴다 — 압박이 성립하지 않는다.
--   ⚠️ 2.0% 는 50초라 러너가 아무것도 안 해도 이긴다. 압박이 아니라 처형이 된다.
--   ⚠️ 다운되지 않는다. HP 0 은 정상 사망 경로를 탄다 — 별도 처리를 만들지 않는다.
local BLEED_PCT      = 0.012  -- 초당 최대HP 대비
local BLEED_TICK     = 0.5    -- 틱 간격(초). 잦으면 HealthChanged 이벤트가 과하게 늘어난다
local ANIM_ID        = "rbxassetid://86265615635745"
local FIRST_DELAY    = 3.0

local running = {}

local function isImmune(char)
	if _G.IsCcImmune then
		local ok, v = pcall(_G.IsCcImmune, char)
		if ok then return v == true end
	end
	return false
end

-- 🔒 [버그수정 2026-09-11] 세 루프(출혈·keeper·버스트)의 공통 생존 조건.
--   [증상] 킹이 살아서 라운드가 끝나면 탈진이 영구히 계속됐다. 실측 14:53 판:
--     라운드 종료 후에도 버스트가 돌고(WS 16→6), keeper 가 RoundStateResetServer 의
--     로비 복원(12→16)을 1초마다 되돌렸다(16→12). 로비에서도 출혈이 계속 깎였다.
--     루프는 디스커넥트로 char.Parent 가 nil 이 돼서야 끝났다.
--   [왜 지금까지 안 보였나] 이전 8판은 전부 킹이 죽어서 `hum.Health > 0` 에서 끊겼다.
--     킹이 이긴 판이 처음이라 드러났다 — 라운드 종료를 보는 조건이 애초에 없었다.
--   [왜 여기인가] 호출자가 Stop 을 기억하는 데 기대면 새 종료 경로가 생길 때마다 깨진다.
--     루프 조건 자체에 넣어 "라운드가 끝나면 반드시 멈춘다"를 보장한다.
--   ⚠️ _G.IsRoundLive 는 RoundSystem 이 이미 노출해둔 훅이다(PushTool.swing 도 같은 걸 쓴다).
--     훅이 없으면 통과시킨다 — 없다고 시스템이 죽으면 안 된다.
local function exhaustActive(char)
	if not (char and char.Parent) then return false end
	if not char:GetAttribute("ThroneFallen") then return false end
	if _G.IsRoundLive and not _G.IsRoundLive() then return false end
	return true
end

local function playExhaustAnim(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = ANIM_ID
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = true
		track:Play(0.15)
		return track
	end
	return nil
end

print("[ThroneExhaust] part1 loaded")

-- One exhaustion burst.
-- [warn] Attacking is blocked by PushTool.Server's swing() guard, which already
--   checks Humanoid.PlatformStand (added 2026-09-05 for the airborne fix).
--   We reuse that instead of adding a second rule in a second place.
local function doExhaust(char)
	-- ⛓️ [밸런스 2026-09-21] 여기서 막는다. 루프를 지우지 않고 진입만 끊는 이유:
	--   running[char] 를 비우는 게 저 루프의 끝단(:276)이다. 루프를 통째로 없애면
	--   재진입 가드가 영구히 잠긴 채 남는다("끄는 코드에 도달이 보장되는가").
	if not BURST_ENABLED then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not (hum and hum.Parent and hum.Health > 0) then return end

	-- [warn] Do NOT use Humanoid.PlatformStand here. It already has three owners
	--   (PushTool charged ragdoll, DownSystem, DoubleJump flip) and clearing it
	--   unconditionally after 1s releases whatever THEY set - the king's posture
	--   and movement broke exactly this way. The 09-01 note is explicit:
	--   "if the symptom comes back, suspect PlatformStand before the anim layer".
	--   Attacking is blocked by the Stunned attribute instead (see PushTool swing guard).
	hum.WalkSpeed = EXHAUST_SPEED
	char:SetAttribute("Stunned", true)   -- read by TaggerCcGuard.ccActive AND swing()

	-- ⚠️ Cancel any charge-up FIRST. The charge track is frozen with AdjustSpeed(0)
	--   on its last frame, so it holds the pose and buries the exhaustion animation
	--   underneath. Symptom was "the king freezes mid-charge and the collapse never
	--   shows"; it only cleared when he charged again.
	--   [warn] Must run before playExhaustAnim, or the new track is still smothered.
	if _G.PushToolCancelCharge then pcall(_G.PushToolCancelCharge, char) end

	notifyKing(char, "start", DURATION)
	local track = playExhaustAnim(char)

	task.delay(DURATION, function()
		if track then pcall(function() track:Stop(0.2) end) end
		-- 🔒 [2026-09-11] 라운드가 끝났으면 속도를 되돌리지 않는다.
		--   [증상] 버스트 도중 라운드가 끝나면 이 delay 가 로비에서 터져 WalkSpeed 를
		--     SLOW_SPEED(12) 로 눌렀다. 실측 14:53 판의 `6.0 → 12.0` 두 줄이 이것이다.
		--   [지금] 복원은 RoundStateResetServer 가 소유하게 두고 여기서는 손을 뗀다.
		--     Stunned 해제는 아래에서 그대로 한다 — 안 풀면 킹이 영구히 못 때린다.
		if hum and hum.Parent and exhaustActive(char) then
			-- [warn] Restore to the live value, not the snapshot, in case some other
			--   system changed WalkSpeed meanwhile. prevSpeed is only a fallback.
			-- [warn] Restore to SLOW_SPEED, not to the pre-burst value and not to 18.
			--   The permanent slow must survive every burst; snapshotting WalkSpeed
			--   would capture 6 on an overlapping burst, and a hard 18 would erase
			--   the slow entirely - the debuff would quietly undo itself.
			hum.WalkSpeed = SLOW_SPEED
		end
		if char and char.Parent then
			-- [warn] Clearing Stunned is ALL we do. TaggerCcGuard watches ccActive()
			--   (which reads Stunned) and grants immunity on its own:
			--   immune time = duration x IMMUNE_RATIO(0.75) = 0.75s here.
			--   There is no _G.GrantCcImmune - do not invent one. Adding a second
			--   immunity path would be the classic "same rule in two places" bug.
			char:SetAttribute("Stunned", nil)
			-- the recovery window starts now and lasts exactly CYCLE.
			notifyKing(char, "ready", CYCLE)
		end
	end)
end

local function startLoop(char)
	if running[char] then return end
	running[char] = true
	-- 🩸 bleed loop. Runs alongside the slow keeper and the burst cycle.
	--   [warn] TakeDamage, not Health -= x. TakeDamage respects ForceField and is the
	--     same entry point every other damage source uses; writing Health directly
	--     would bypass guards that already exist.
	--   [warn] Do NOT tag a creator. This is environmental - the round-end code has a
	--     fallback for "no creator" (getLastAttackerName) so the runner who actually
	--     fought still gets the kill credit. Tagging a fake creator would break that.
	task.spawn(function()
		while exhaustActive(char) do
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not (hum and hum.Health > 0) then break end
			-- 🔬 [2026-09-11] 계측 분리 표식. watchKingDamage 가 이걸 보고 출혈을
			--   봇 평타와 따로 센다. 섞이면 '초당 타격'이 붕괴 후 구간에서만 부푼다
			--   (09-10 판 61회 중 9회가 출혈 틱이었다 = 1.40 이 아니라 1.17).
			--   ⚠️ task.defer 여야 한다 — 대입이 만든 HealthChanged 가 큐에서 빠진 뒤에
			--     꺼야 표식이 제 몫을 한다. HpRewrite 가 같은 형태로 이미 쓰고 있다.
			char:SetAttribute("BleedTick", true)
			hum:TakeDamage(hum.MaxHealth * BLEED_PCT * BLEED_TICK)
			task.defer(function()
				if char.Parent then char:SetAttribute("BleedTick", nil) end
			end)
			task.wait(BLEED_TICK)
		end
	end)

	-- permanent slow: apply immediately and keep re-applying.
	--   [why a keeper loop] TaggerBotSystem writes WalkSpeed itself (zone rush sets 18).
	--     A one-shot assignment gets silently reverted a second later and the slow
	--     looks like it "randomly stopped working". Re-assert it every second.
	--   [warn] Skip while a burst is active, or the keeper would cancel the burst.
	task.spawn(function()
		while exhaustActive(char) do
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not (hum and hum.Health > 0) then break end
			if char:GetAttribute("Stunned") ~= true and hum.WalkSpeed > SLOW_SPEED then
				hum.WalkSpeed = SLOW_SPEED
			end
			task.wait(1.0)
		end
	end)

	task.spawn(function()
		-- ⛓️ [밸런스 2026-09-21] 버스트가 꺼져 있으면 HUD 카운트다운을 아예 안 띄운다.
		--   오지 않을 탈진을 세는 카운트다운은 UI 가 거짓말을 하는 것이다.
		--   붕괴 사실 자체는 ThroneFellEvent 의 1회성 배너가 따로 알린다 — 정보 손실 없음.
		if BURST_ENABLED then notifyKing(char, "ready", FIRST_DELAY) end
		task.wait(FIRST_DELAY)
		while exhaustActive(char) do
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not (hum and hum.Health > 0) then break end
			if isImmune(char) then
				-- Option B: skip and restart the cycle. Do not retry immediately.
				print("[ThroneExhaust] skipped (cc immune) - timer restarted")
			else
				doExhaust(char)
			end
			-- [warn] CYCLE is the RECOVERY window, measured from when the burst
			--   ENDS - not from when it starts. doExhaust returns immediately
			--   (recovery is a task.delay), so waiting only CYCLE here would let
			--   the timer run during the 1.5s burst and leave just 6.5s of free
			--   time. Wait out the burst first, then the full cycle.
			task.wait(DURATION + CYCLE)
		end
		running[char] = nil
		notifyKing(char, "off", 0)   -- "code that turns on needs code that turns off"
		print("[ThroneExhaust] loop ended")
	end)
end

_G.ThroneExhaustStart = function(char)
	if not char then return end
	startLoop(char)
	print("[ThroneExhaust] started (cycle " .. CYCLE .. "s / dur " .. DURATION .. "s)")
end

-- 🐛 [버그수정 2026-09-11] Stop 이 아무것도 멈추지 않고 있었다.
--   [원인] 세 루프는 전부 `ThroneFallen` 속성을 보는데 이 함수는 `running` 만 지웠다.
--     끄는 코드가 켜는 코드와 짝이 안 맞는 전형(09-01 "켜는 코드와 함께 넣을 것").
--   [지금] 루프의 실제 게이트인 ThroneFallen 을 지운다. 표식류도 같이 정리한다.
--   ⚠️ WalkSpeed 는 건드리지 않는다. 라운드 종료 복원과 RoundStateResetServer 가
--     이미 소유한 값이라, 여기서 또 쓰면 소유자가 셋이 된다.
_G.ThroneExhaustStop = function(char)
	if not char then return end
	running[char] = nil
	char:SetAttribute("ThroneFallen", nil)
	char:SetAttribute("BleedTick", nil)
	char:SetAttribute("Stunned", nil)
	notifyKing(char, "off", 0)
end

print("[ThroneExhaust] ready (_G.ThroneExhaustStart / Stop)")
