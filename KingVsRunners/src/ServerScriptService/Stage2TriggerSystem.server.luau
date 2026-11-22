-- Stage2TriggerSystem
-- 러너 1명이라도 ItemSpawnPlate에 도달하면 2단계 진입 트리거.
--
-- 효과:
--   1. 모든 태거에게 PushTool 지급 (밀쳐내기 = 2단계 결투 도구)
--   2. 모든 플레이어에게 알림 발신 (Stage2Started 이벤트)
--   3. 라운드별 1회만 트리거 (이후 도달자는 무시)
--
-- 도달 감지: 매 0.2초 모든 활성 ItemSpawnPlate를 영역 검사.
--   Touched 사용 시 빠른 통과/스치는 케이스 미스 가능 → 영역 검사가 안정적.
--   현재 활성 맵의 ItemSpawnPlate만 감시 (TaggerBoundary와 동일 패턴).

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Stage2Started = ReplicatedStorage:WaitForChild("Stage2Started")

-- ── 상태 ────────────────────────────────────────────────
local stage2Active = false       -- 이번 라운드에서 이미 트리거됐는지
local currentMap   = nil
local watchConn    = nil          -- 감시 루프 connection

-- ── ItemSpawnPlate 영역 검사 ────────────────────────────
local function isInsidePlateXZ(pos, plate)
    local localPos = plate.CFrame:PointToObjectSpace(pos)
    local half = plate.Size / 2
    -- Y는 살짝 여유 (점프 도달 / 상단 밟기 모두 인정)
    return math.abs(localPos.X) <= half.X
       and math.abs(localPos.Z) <= half.Z
       and math.abs(localPos.Y) <= half.Y + 5
end

-- ═══════════════════════════════════════════════════════════
-- 👑 태거 HP 확정 — 호출 시점이 곧 '전선이 형성된 시점'이다
--
-- 🚪 [2026-08-29] 호출 시점을 '계단 진입' → '바리케이드 붕괴' 로 옮겼다.
--   [증상] 1등으로 도착한 러너가 혼자서 전체 인원분 HP 를 상대했다.
--     ODM·스피드포션으로 빨리 돌파할수록 불리해져, 아이템이 자기 강점을 스스로 벌했다.
--   [원인] 분자와 분모가 달랐다.
--       HP  = 150 × '생존' 러너 (아직 언덕에 있는 사람 포함)
--       화력 =   1 × '도착' 러너 (현장에 온 사람만)
--     설계 의도는 "다들 언덕을 거의 다 올라온 시점"이었는데(아래 원 주석 참조),
--     구현은 스냅샷을 '첫 도달자'에 찍고 있었다. 설계와 구현의 어긋남이다.
--   [해결] 바리케이드가 무너지는 순간에 찍는다. 그때가 실제 전투 개시다.
--     ⚠️ 왜 '실시간 재산정' 이 아닌가 — 그건 이미 기각된 안이다.
--       "때렸는데 킹 HP 가 늘었다"를 플레이어에게 설명할 수 없다(아래 원 주석).
--       이 안은 여전히 '한 번만' 확정한다. 확정 시점만 옮긴 것이다.
--     ⚠️ 왜 '거리 범위 안의 러너만 센다' 가 아닌가 — 악용 경로가 생긴다.
--       전원이 범위 밖에서 대기 → 1명만 계단을 밟아 낮은 HP 확정 → 전원 돌진.
--       바리케이드는 '부숴야만' 통과되므로 참여가 강제되어 그 구멍이 막힌다.
--
--   [실측 2026-08-29] 진입 → 붕괴까지 6.9초(봇 10명) ~ 11.2초(봇 7명).
--     11.2초 판에서 성문 타격 참여가 1명 → 6명으로 늘었다. 그 창이 이 수정의 값이다.
--
-- ⚠️ 붕괴가 영영 안 오면 이 함수도 안 불린다. 그 경우는 러너 전멸 = 이미 태거 승이라
--    (RoundSystem 의 '러너 전멸 감지') HP 를 확정할 필요가 없다.
-- ⚠️ 붕괴 전에는 러너가 태거에게 물리적으로 닿을 수 없다(바리케이드가 막는다).
--    곡사포·마법책은 태거 기물이라 러너의 원거리 딜 수단도 없다.
--    따라서 미확정 구간의 HP 가 무엇이든 전투에 영향이 없다.
-- ═══════════════════════════════════════════════════════════
local taggerHpLocked = false

-- 🔬 [K측정 2026-09-04] 킹이 2단계에서 받은 총 피해 누적. 유저 태거·봇 킹 공통.
--   [왜 필요한가] `[Duel] 킹 피격` 로그는 TaggerBotSystem 의 봇 킹 전용 핸들러(bHum)라
--     유저가 킹인 판에서는 구조적으로 한 줄도 안 찍힌다. 그 부재를 '피해 0'으로
--     세 번 연속 오독했다 — 로그가 없는 게 보장된 자리에 계측을 새로 세운다.
--   ⚠️ HealthChanged 는 '맞았다'가 아니라 '값이 변했다'다. 전투가 아닌 변화를 걸러낸다:
--     ① h >= MaxHealth → 풀피로 끝나는 변화(재산정·라운드 원복·회복 상한)
--     ② HpRewrite 표식 → TaggerCcGuard 의 배율 복원(부분값으로 끝나 ①로는 못 잡는다)
--     ③ 감소분만 누적  → 불기둥 지대 밖 회복이 음수로 섞이지 않게
--   ⚠️ 로비 복귀는 캐릭터를 유지해서 Humanoid 가 안 바뀐다 = 연결이 라운드마다 쌓인다.
--     세대 토큰으로 옛 연결이 다음 이벤트에서 스스로 끊기게 한다.
local kingWatchGen = 0
local function watchKingDamage(hum)
	if not hum then return end
	kingWatchGen = kingWatchGen + 1
	local myGen = kingWatchGen
	local last = hum.Health
	local conn
	conn = hum.HealthChanged:Connect(function(h)
		if myGen ~= kingWatchGen then
			if conn then conn:Disconnect() end
			return
		end
		local obs = _G.RoundObs
		if not obs or (obs.stage2At or 0) <= 0 then last = h return end
		local ch = hum.Parent
		-- 🐛 [버그수정 2026-09-11] 사망 이벤트 제외 — A-1 계측 2배의 정체.
		--   [실측] 09-11 판에서 `🔬 [KingDmg] 이상 d=825.0 | 825.0 → 0.0 | HP0=true` 가
		--     사망 시각(±13ms)에 찍혔다. 재산정(30초 전)과는 무관했다.
		--   [왜 통째로 빼도 되나] d = last - 0 이라 last 오염이 한 판 분량으로 들어온다.
		--     반대로 last 가 정상이면 이 이벤트의 실제 기여는 '남은 HP' 뿐이라 손실이 없다.
		if h <= 0 then last = h return end
		-- 🩸 [2026-09-11] 저주검 출혈 분리. ThroneExhaustSystem 이 틱마다 세우는 표식을 본다.
		--   [왜] 출혈은 TakeDamage 라 HealthChanged 를 0.5초마다 하나씩 만든다. 그게
		--     s2KingHits 에 섞여 '초당 타격'이 왕좌 붕괴 후 구간에서만 부풀었다.
		--     09-10 판 1890/61 = 봇 51타(1020) + 출혈 9틱(44.6) + 사망 1건(825) 로 소수점까지 맞는다.
		--   ⚠️ 값 범위(d < 5 등)로 거르지 않는다 — 제외 목록은 반드시 다시 깨진다. 표식으로 가른다.
		if ch and ch:GetAttribute("BleedTick") then
			local bd = last - h
			if bd > 0 then obs.s2KingBleed = (obs.s2KingBleed or 0) + bd end
			last = h
			return
		end
		if (ch and ch:GetAttribute("HpRewrite")) or h >= hum.MaxHealth then
			-- 🔬 [해결 2026-09-11] `🔬 [KingFull]` 프로브 제거 — 범인이 잡혔다.
			--   [실측] `h=825.0 Max=825.0 last=0.0` 한 줄. 킹이 0 에서 만피로 '올라갔다'.
			--   [범인] ItemDamageSystem.attachTaggerExec — HP 0 이 되면 처형 연출 동안
			--     살려두려고 hum.Health = hum.MaxHealth 로 되돌리고, 연출이 실패하면
			--     다시 0 으로 죽인다. 그래서 HealthChanged 가 0 → 825 → 0 으로 세 번 난다.
			--   ⚠️ 유저 러너가 킬러면 handled=true 라 연출 내내 만피가 유지된다.
			--     그 창의 타격은 전부 이 분기가 걸러낸다 — 프로브를 남기면 warn 이 폭주한다.
			last = h
			return
		end
		local d = last - h
		last = h
		-- 🐛 [버그수정 2026-09-04] 한 이벤트의 감소분이 MaxHealth 를 넘을 수 없다.
		--   [증상] 킹이 죽은 판마다 누적이 정확히 2배로 찍혔다(825 → 1650, 34회 고정).
		--     18:28 / 19:03 / 20:05 / 22:36 판 전부 1650 이었다 — 우연이 아니다.
		--   [원인] ❌ 당시 추정(재산정 경합)은 틀렸다. 2026-09-11 에 확정된 진짜 원인은
		--     ItemDamageSystem.attachTaggerExec 의 즉사 방지다 — 킹 HP 가 0 이 되면
		--     처형 연출을 위해 만피로 되돌렸다가 다시 0 으로 죽인다(0 → 825 → 0).
		--     그 왕복의 두 번째 구간이 한 판 분량(=MaxHealth)을 통째로 한 번 더 넣었다.
		--     재산정과 무관했다 — 실측에서 30초 떨어져 있었다.
		--   [규칙] 한 번의 피격이 최대 체력을 넘길 수 없다는 물리적 상한으로 막는다.
		--     원인 추적(경합 타이밍)에 기대지 않고 결과를 보장하는 쪽이다 —
		--     09-01 문서의 "제외 목록보다 결과 보장"과 같은 형태.
		-- 🔬 [해결 2026-09-11] 옛 `if d > 100 then warn` 진단 블록 제거 — 답이 나왔다.
		--   [정체] ① 사망 이벤트(위에서 h <= 0 로 제외) ② 저주검 출혈 틱(위에서 표식으로 분리).
		--     09-10 문서의 "약 670 을 한 이벤트가 몰아넣었다"는 61회가 전부 20.0 이라는
		--     가정에서 나온 오추정이었다. 실제로는 출혈 틱이 회수에 섞여 있었다.
		--   ⚠️ 클램프는 남긴다. 원인 추적이 아니라 결과를 보장하는 상한이다.
		if d > hum.MaxHealth then d = hum.MaxHealth end
		if d > 0 then
			obs.s2KingDmg  = (obs.s2KingDmg or 0) + d
			obs.s2KingHits = (obs.s2KingHits or 0) + 1
		end
	end)
end

local function finalizeTaggerHp(reason)
    if taggerHpLocked then return end
    taggerHpLocked = true
    print(string.format("👑 [Stage2] 태거 HP 확정 시점: %s", reason or "?"))
    -- 🩸 [2026-08-29] HP 바 노출 신호. TaggerHpDisplay 가 이 속성을 본다.
    --   [왜] 확정 전에 바를 띄우면 캐릭터 기본값 100 이 잠깐 보였다가 825 로 튄다.
    --     러너 입장에선 "때리지도 않았는데 HP 가 늘었다"로 읽혀 버그처럼 보인다.
    --   ⚠️ 세우는 곳은 여기 하나, 지우는 곳은 라운드 리셋 두 곳(taggerHpLocked 와 한 짝).
    ReplicatedStorage:SetAttribute("TaggerHpReady", true)

    -- ═══════════════════════════════════════════════════════════
    -- 👑 태거 HP 재산정
    --
    -- [왜 여기서] 라운드 시작 시점에 정하면 1단계 성과가 반영되지 않는다.
    --   태거가 열심히 줄여도 HP 는 시작 인원 기준이라, 소수만 도착해도
    --   태산 같은 HP 를 마주하게 된다. 2단계 진입 시점의 '살아있는 러너'로
    --   다시 계산해야 1단계에서 잘한 만큼 상대가 가벼워진다.
    --
    -- ⚠️ [수정 2026-08-26] 다운자를 '반만' 센다 (DOWNED_WEIGHT).
    --
    --   [기존] "다운은 부활하면 다시 싸우니 살아있는 것으로 센다" → 1.0 으로 셈.
    --   [문제 1] 부활은 ReviveSystem.startRevive 가 하는데 그건
    --     requestEvent.OnServerEvent 에서만 호출된다 = 진짜 Player 만 가능하다.
    --     봇은 부활 경로가 아예 없어, 유저 러너가 0명이면 다운자는 사망 확정이다.
    --     (실측 11:38 판: 진입 시 6마리 다운인데 10명으로 세어 HP 825 = 만피)
    --   [문제 2] 그렇다고 0 으로 세면 반대로 틀린다. HP 는 진입 순간에 굳는데
    --     부활 여부는 그 뒤 10초 안에 결정된다. 스냅샷으로는 예측이 불가능하다.
    --       · 다 부활 → 킹이 2명분 HP 로 6명과 싸움 (킹 과소)
    --       · 다 사망 → 킹이 6명분 HP 로 2명과 싸움 (킹 과잉)
    --     어느 쪽으로 굳혀도 최대 3배 오차가 난다.
    --   [해결] 다운자를 0 으로 센다. 지금 싸울 수 있는 인원만 HP 에 반영한다.
    --     (0.5 → 0.25 → 0 순으로 내려왔다. 실제 유저는 부활을 잘 시도하지 않고,
    --      솔로 태거 모드에서는 부활 경로가 아예 없어 다운 = 확정 사망이다)
    --     예: 2정상 + 5다운 진입 시  w=0.25 → HP 268 / w=0 → HP 165.
    --     268 은 존재하지 않는 화력을 가정한 값이었다.
    --
    -- ⚠️ w=0 의 부작용: 멀티에서 다운자가 실제로 부활하면 킹은 그 인원분 HP 를
    --   못 받는다(5명분 HP 로 7명과 싸움). 부활률이 실제로 높아지면 되돌릴 것.
    -- ⚠️ 이 값은 '진입 시점' 만 정확하게 만든다. 진입 후 러너가 죽어 소수만
    --   남는 경우는 다루지 않는다 — 그건 태거가 잘한 결과이므로 의도된 동작이다.
    --   (HP 실시간 감소안은 그래서 채택하지 않았다)
    --
    -- ⚠️ 실시간 HP 갱신(러너가 죽을 때마다 최대치 조정)도 검토했으나 폐기했다.
    --   "때렸는데 킹 HP 가 늘었다"(동료 부활 시)를 플레이어에게 설명할 방법이 없다.
    -- ⚠️ 봇 가중치 0.55 — 봇 DPS 10 / 유저 18.8 실측 비율.
    -- ⚠️ 부활 유인을 키우고 싶어지면 이 값을 올리는 게 아니라 부활 자체의
    --   보상·속도를 손보는 게 맞다. 이 값은 '누가 지금 싸울 수 있나' 를 세는 것이다.
    -- ═══════════════════════════════════════════════════════════
    local DOWNED_WEIGHT = 0    -- 다운자는 인원 환산에서 제외 (지금 싸울 수 없다)
    do
        -- 인원 환산치: 정상 1.0 / 다운 DOWNED_WEIGHT / 사망 0
        -- ⚠️ 예전엔 '부활 가능한 유저 러너가 있는가' 를 따로 검사해 다운 가중치를
        --   조건부로 적용했다. DOWNED_WEIGHT 가 0 이 된 지금은 두 분기가 같은 값이라
        --   검사 자체가 무의미해져 제거했다.
        --   → 가중치를 다시 0 보다 크게 올릴 일이 생기면 그 검사도 함께 되살릴 것.
        local function aliveWeight(char, hum)
            if not (hum and hum.Health > 0) then return 0 end
            if char:GetAttribute("Downed") then return DOWNED_WEIGHT end
            return 1
        end

        local userRunners, botRunners, downedSeen = 0, 0, 0
        -- 🔬 [측정 2026-09-18] 히어로/농민을 따로 센다. **밸런스에 영향 없음 — 기록 전용.**
        --   [왜] 킹 피해 DPS 를 히어로·농민으로 분해하려면 판마다 (히어로 h, 농민 f)가
        --     필요하다. 지금 로그는 "봇 5" 라고만 찍어서, 죽은 게 히어로였는지
        --     농민이었는지 사후에 알 방법이 없다(실측 09-18: 두 판 다 분해 불가).
        --   [쓰는 법] 판마다 한 식이 나온다 →  DPS = h·H + f·F
        --     2판이면 자유도 0 이라 잔차가 항상 0(정보 없음). 3판째부터 검증이 시작된다.
        --   ⚠️ 이 값은 다운 가중치를 적용한 **환산치**가 아니라 실제 머릿수다.
        --     환산치는 아래 effN 이 따로 쓴다 — 두 축을 섞지 않는다.
        --   ⚠️ 표식은 이름이 아니라 HeroRunner 속성이다(RoundSystem:707 에서 부여).
        --     이름 목록으로 세면 스폰 순서가 바뀌는 순간 조용히 깨진다.
        local heroAlive, farmAlive = 0, 0
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr:GetAttribute("Role") == "Runner" then
                local ch = plr.Character
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                if ch then
                    userRunners = userRunners + aliveWeight(ch, hum)
                    if hum and hum.Health > 0 and ch:GetAttribute("Downed") then
                        downedSeen = downedSeen + 1
                    end
                end
            end
        end
        for _, m in ipairs(workspace:GetChildren()) do
            if m:IsA("Model") and m:GetAttribute("AIRunner") then
                local hum = m:FindFirstChildOfClass("Humanoid")
                botRunners = botRunners + aliveWeight(m, hum)
                -- 🔬 다운은 빼고 센다. "지금 싸울 수 있는 인원"이 DPS 를 만든다 —
                --   effN 의 DOWNED_WEIGHT=0 과 같은 기준이어야 두 숫자가 어긋나지 않는다.
                if hum and hum.Health > 0 and not m:GetAttribute("Downed") then
                    if m:GetAttribute("HeroRunner") then heroAlive = heroAlive + 1
                    else farmAlive = farmAlive + 1 end
                end
                if hum and hum.Health > 0 and m:GetAttribute("Downed") then
                    downedSeen = downedSeen + 1
                end
            end
        end
        if downedSeen > 0 then
            print(string.format("   ↳ 다운 %d명은 HP 계산에서 제외 (가중치 %.2f)",
                downedSeen, DOWNED_WEIGHT))
        end

        local effN = math.max(1, userRunners + botRunners * 0.55)
        local hp = math.floor(math.min(1600, 150 * effN))

        -- 🔬 [측정 2026-09-18] 화력 구성 기록. 위 heroAlive/farmAlive 주석 참조.
        --   ⚠️ 이 한 줄이 H·F 분해의 유일한 입력이다. 지우면 측정이 다시 막힌다.
        --   ⚠️ 무행동 판에서만 연립이 성립한다. 킹이 싸우면 2단계 내내 구성이 변해
        --     "총피해/총시간" 이 구성 불변을 전제한 식과 안 맞는다(09-18 두 판이 그랬다).
        print(string.format("🔬 [화력구성] 히어로 %d + 농민 %d + 유저 %.2f | 환산 %.2f | HP %d",
            heroAlive, farmAlive, userRunners, effN, hp))

        -- 📋 [2026-08-26] 라운드 요약용 관측. 여기가 '생존 러너' 를 세는 유일한 자리라
        --   중복 집계 없이 그대로 넘긴다. RoundSystem 이 종료 시 채점에 쓴다.
        -- ⚠️ HP 환산치(userRunners/botRunners)는 다운을 0.25 로 세는 소수다.
        --   요약은 "몇 명이 올라왔나" 를 보는 거라 환산치가 아니라 실제 머릿수를 쓴다.
        --   (환산치를 그대로 넘기면 "처치 3.75/10" 같은 읽기 어려운 값이 나온다)
        -- ⚠️ 밸런스에 영향 없음. 관측 전용.
        if _G.RoundObs then
            local headcount = 0
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr:GetAttribute("Role") == "Runner" then
                    local ch = plr.Character
                    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then headcount = headcount + 1 end
                end
            end
            for _, m in ipairs(workspace:GetChildren()) do
                if m:IsA("Model") and m:GetAttribute("AIRunner") then
                    local hum = m:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then headcount = headcount + 1 end
                end
            end
            _G.RoundObs.stage2At     = os.clock()
            _G.RoundObs.stage2Alive  = headcount        -- 다운 포함 실제 머릿수
            _G.RoundObs.stage2Downed = downedSeen       -- 그중 다운 상태인 수
            _G.RoundObs.stage2EffN   = effN             -- HP 계산에 쓰인 환산치
        end

        local applied = 0
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr:GetAttribute("Role") == "Tagger" then
                local ch = plr.Character
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    hum.MaxHealth = hp
                    hum.Health = hp
                    applied = applied + 1
                    print(string.format("👑 [Stage2] 태거 HP 재산정: %d (생존 러너 유저 %d + 봇 %d → 환산 %.1f)",
                        hp, userRunners, botRunners, effN))
                    watchKingDamage(hum)   -- 🔬 재산정 '뒤'에 건다 — 재산정 자체를 피해로 세지 않게
                end
            end
        end

        -- 🤖 [버그수정 2026-09-01] 봇 킹에도 같은 재산정을 적용한다.
        --   [증상] 솔로 모드에서 킹 HP 가 매 판 907 로 고정이었다. 실측(11:29 판):
        --     스폰 시점 러너 11명 → 907. 성문 붕괴 시엔 8명이 이미 죽어 2단계 진입이
        --     3명뿐이었는데도 907 그대로였다 = 사실상 항상 풀피.
        --   [원인] 위 루프가 Players:GetPlayers() 만 돈다. 봇 킹은 Player 인스턴스가
        --     아니라 Workspace 의 Model 이라 이 순회에 잡히지 않는다.
        --     TaggerBotSystem:229 주석이 "봇은 그 경로가 없다 — 필요해지면 같은 훅을
        --     붙일 것"으로 이미 예고해 둔 미구현 지점이다.
        --   ⚠️ 봇을 이름이 아니라 TaggerDummy 속성으로 찾는다(TaggerBotSystem:250 에서 부여).
        --     DisplayName 이 티어별로 다르고(하드는 🔥 KING) 이름 매칭은 조용히 깨진다.
        --     Role=="Tagger" 도 같이 확인해 다른 더미와 섞이지 않게 한다.
        --   ⚠️ Health 를 MaxHealth 와 같이 올린다. 유저 태거와 동일한 취급 —
        --     이 시점이 '전투 시작'이라 이전 피해는 없는 게 정상이다.
        for _, m in ipairs(workspace:GetChildren()) do
            if m:IsA("Model") and m:GetAttribute("TaggerDummy") == true
               and m:GetAttribute("Role") == "Tagger" then
                local hum = m:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    -- 🛡️ [2026-09-02] CC 배율이 걸려 있으면 재산정 값에도 같이 곱한다.
                    --   [왜] TaggerCcGuard 가 CC 중 MaxHealth 를 ×2 해두는데, 여기서 맨값을
                    --     덮어쓰면 배율이 사라진다. 그 상태로 CC 가 끝나면 ÷2 만 걸려
                    --     킹 HP 가 의도의 절반이 된다(480 → 240).
                    --   ⚠️ 아이스보우는 관통이라 성문 붕괴 순간에 Frozen 이 살아 있을 수 있다.
                    --     이론상 위험이 아니라 실제로 도달 가능한 경로다.
                    --   ⚠️ 아래 print 는 배율을 뺀 '의도값'을 찍는다. 로그 비교 기준 유지.
                    local ccScale = m:GetAttribute("CcHpScale") or 1
                    hum.MaxHealth = hp * ccScale
                    hum.Health = hp * ccScale
                    applied = applied + 1
                    print(string.format("👑 [Stage2] 봇 킹 HP 재산정: %d (생존 러너 유저 %d + 봇 %d → 환산 %.1f)",
                        hp, userRunners, botRunners, effN))
                    watchKingDamage(hum)   -- 🔬 재산정 '뒤'에 건다 — 재산정 자체를 피해로 세지 않게
                end
            end
        end

        if applied == 0 then
            warn("[Stage2] ⚠️ HP 재산정 대상이 없다 — 태거도 봇 킹도 못 찾았다")
        end
    end
end

-- 🚪 바리케이드가 이 함수를 부른다(BarricadeSystem 붕괴 훅).
--   ⚠️ 전역 노출이 필요한 이유: BarricadeSystem 은 별도 스크립트라 이 지역 함수를 못 본다.
--     CannonSystem 이 같은 붕괴 훅을 이미 쓰고 있으므로 그 옆에 나란히 붙인다.
_G.FinalizeTaggerHp = finalizeTaggerHp

-- 👊 [변경 2026-09-02] 유저 태거 PushTool 지급을 '성문 붕괴' 시점으로 미룬다.
--   [왜] 2단계 진입(러너가 계단 도달)과 성문 붕괴 사이 ~10초 동안 태거가 결투 무기로
--     바리케이드 앞 러너를 때릴 수 있었다. 공성 구간에는 공성 도구(굴리기·곡사포·
--     마법책)로만 견제하는 게 설계 의도다.
--   [봇은 이미 처리됨] TaggerBotSystem.enterDuelMode 가 TaggerHpReady 를 보고 게이트한다
--     (2026-09-02). 이건 그 유저 버전이다 — 같은 규칙이 두 곳에 있으니 한쪽만 고치면 어긋난다.
--   ⚠️ 2단계 감속(Stage2Slowed)도 이 블록 안에 있어 같이 미뤄진다. 의도한 것이다 —
--     감속은 '결투 국면'의 규칙이고, 공성 중에는 태거가 원래 속도로 움직여야 한다.
--   ⚠️ 러너 무기 지급은 이 함수 밖(triggerStage2)이라 2단계 진입 시점 그대로다.
--     러너는 바리케이드를 때려야 하므로 미루면 안 된다.
local function grantTaggerPushTool()
    -- 모든 태거에게 PushTool 지급
    local pushTemplate = ReplicatedStorage:FindFirstChild("PushTool")
    if not pushTemplate then
        warn("[Stage2] ReplicatedStorage.PushTool 없음")
    else
        for _, player in ipairs(Players:GetPlayers()) do
            if player:GetAttribute("Role") == "Tagger" and player.Character then
                -- 이미 가지고 있으면 중복 지급 안 함
                local pB = player.Backpack:FindFirstChild("PushTool")
                local pC = player.Character:FindFirstChild("PushTool")
                local hasAlready = (pB and pB:IsA("Tool")) or (pC and pC:IsA("Tool"))
                -- 🔴 [계측 2026-09-20] 위 러너 무기 지급과 **같은 침묵 스킵**이 여기에도 있다.
                --   [왜 같이 넣나] 러너 쪽만 고치면 이 프로젝트가 반복해서 데인
                --     "한쪽만 고치고 나머지가 안 따라온" 형태가 그대로 재현된다
                --     (코핀만 고치고 5종이 안 따라온 이력이 두 번).
                --   [여기서 스킵되면] 킹이 2단계에 근접 무기(PushTool) 없이 들어간다.
                --     러너 무기가 없는 것보다 조용히 더 치명적이다 — 킹은 대안이 없다.
                --   ⚠️ 캐릭터·Backpack 이 라운드를 넘어 유지되므로(71행) 잔재 조건이 동일하다.
                if hasAlready then
                    warn(string.format(
                        "⚠️ [Stage2] %s PushTool 지급 스킵 — 이미 보유(이전 라운드 잔재 의심) | 백팩=%s 손=%s",
                        player.Name, tostring(pB ~= nil), tostring(pC ~= nil)))
                end
                if not hasAlready then
                    local tool = pushTemplate:Clone()
                    -- 푸시툴 색놀이 스킨 적용: 장착 스킨 → Handle 색/재질 (무지개는 순환 템플릿 삽입)
                    if _G.getEquippedSkin and _G.getSwordSkinData then
                        local skinName = _G.getEquippedSkin(player, "PushTool")
                        local skinData = skinName and _G.getSwordSkinData("PushTool", skinName)
                        local handle = tool:FindFirstChild("Handle")
                        if skinData and handle then
                            if skinData.meshSwap then
                                -- mesh-swap skin (Glitch/Cursor Hand): hide Handle mesh + weld WeaponSkins model
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
                            elseif skinData.cycle then
                                local tmpl = game:GetService("ServerStorage"):FindFirstChild("RainbowCycleTemplate")
                                if tmpl then
                                    local cyc = tmpl:Clone()
                                    cyc.Name = "RainbowCycle"
                                    cyc.Disabled = false
                                    cyc.Parent = handle
                                end
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
                        elseif handle then
                            -- _Custom: PushColor/PushMaterial 속성 있으면 Handle 색칠 (없으면 원본 글러브 유지)
                            local colorName = player:GetAttribute("PushColor_Fist")
                            if colorName then
                                local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
                                if palette.COLORS[colorName] then
                                    local cfg = palette.getConfig("PushTool")
                                    local finishKey = player:GetAttribute("PushMaterial_Fist") or cfg.materialDefault
                                    palette.applyFinish(handle, finishKey, palette.COLORS[colorName])
                                end
                            end
                        end
                    end
                    tool.Parent = player.Backpack
                    -- [STAGE2-AUTOEQUIP] 지급에 그치지 않고 손에 쥐여 준다.
                    --   백팩에만 넣으면 "무기가 안 나왔다"고 오해하는 경우가 많다.
                    --   ⚠️ 해제는 자유 — EquipTool 은 강제 장착만 하고 잠그지 않는다.
                    --   ⚠️ Humanoid 가 없거나 사망 중이면 EquipTool 이 실패하므로 가드.
                    do
                        local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                            pcall(function() hum:EquipTool(tool) end)
                        end
                    end
                    print("👊 PushTool 지급+장착:", player.Name)

                    -- 👊 [2026-09-16] 차징 속성 감시자 — 툴 '바깥'에 둔다.
                    --   [증상] 라운드 종료 직전에 강타를 쓰면 PushCharging 이 true 로 고착되고
                    --     예고 사각형이 로비까지 따라온다.
                    --   [왜 툴 안에서 못 고치나] PushTool.Server 의 자동 발동은
                    --     task.delay(CHARGE_TIME) 이고, 그 예약은 툴 스크립트 소유다.
                    --     라운드 종료로 툴이 회수되면 콜백째 사라진다 —
                    --     "예약형 task.delay 는 호출자 혈통에 묶인다". 에러도 안 남는다.
                    --     실측 09-16: 그 콜백 안에 복구자를 넣었더니 복구자까지 같이 죽었다.
                    --     Tool.Destroying 훅도 안 먹는다 — 툴은 애초에 파괴되지 않는다
                    --     (종료 후에도 '툴=PushTool(En=true)' 가 계속 찍힌다).
                    --   [해결] 이 스크립트는 ServerScriptService 상주라 죽지 않는다.
                    --     여기서 건 예약은 툴의 생사와 무관하게 살아남는다. 그게 핵심이다.
                    --   ⚠️ 사각형만의 문제가 아니다. RunnerBotDriveController 의 봇 강타
                    --     회피가 같은 속성을 읽는다. true 로 고착되면 다음 라운드 내내
                    --     봇들이 있지도 않은 강타를 피해 옆으로 빠져서, 그 판의
                    --     처치 수·1단계 길이가 조용히 오염된다. 측정값이 더 큰 피해다.
                    --   ⚠️ 3.0 = CHARGE_TIME(1.5)의 2배. 정상 발동은 1.5초에 끝나므로
                    --     이 시점까지 true 면 정상 경로가 죽은 것이다. 랙 여유 포함.
                    --   ⚠️ _ChargeWatchdog 표식으로 중복 연결을 막는다. 캐릭터는 라운드가
                    --     바뀌어도 교체되지 않아(RoundStateResetServer = 상태 복구),
                    --     표식이 없으면 판마다 연결이 쌓인다.
                    do
                        local ch2 = player.Character
                        if ch2 and not ch2:GetAttribute("_ChargeWatchdog") then
                            ch2:SetAttribute("_ChargeWatchdog", true)
                            local gen = 0
                            ch2:GetAttributeChangedSignal("PushCharging"):Connect(function()
                                if not ch2:GetAttribute("PushCharging") then return end
                                gen += 1
                                local myGen = gen
                                task.delay(3.0, function()
                                    if gen ~= myGen then return end   -- 새 차징이 주인이다
                                    if not ch2.Parent then return end
                                    if ch2:GetAttribute("PushCharging") then
                                        ch2:SetAttribute("PushCharging", false)
                                        warn("👊 [ChargeWatchdog] 고착 해제 — " .. player.Name)
                                    end
                                end)
                            end)
                        end
                    end

                    -- 👑 [2026-09-15] 몸집 강화에 맞춰 무기도 키운다.
                    --   [왜] 킹은 1단계 처치 수에 따라 최대 2.5배까지 커지는데(KillEffectSystem
                    --     applyKingScale), 툴은 여기서 **나중에** 지급된다. 그대로 두면
                    --     커진 손에 원본 크기 무기가 붙어 우스꽝스럽다.
                    --   [무엇을 곱하나] Handle.Size 와 Grip 의 **위치만**.
                    --     ⚠️ Grip 의 회전 성분은 건드리지 않는다. CFrame 을 통째로 곱하면
                    --       쥐는 각도가 틀어진다 — 오늘 Motor6D 에서 같은 실수를 했다.
                    --   ⚠️ 판정은 안 건드린다. PushTool.Server 의 박스 판정(vMult)은
                    --     "시각만 거대, 판정은 원본"이 비슈누 스킨 때 이미 내려진 결정이다.
                    --     성과 보상과 스킨은 근거가 다르지만, 우선 시각만 키우고
                    --     "커졌는데 안 닿는다"가 실제로 체감되는지 보고 판단한다.
                    do
                        local ch = player.Character
                        local ks = ch and ch:GetAttribute("KingScale") or 1
                        if ks > 1.001 then
                            local handle = tool:FindFirstChild("Handle")
                            if handle then handle.Size = handle.Size * ks end
                            local g = tool.Grip
                            tool.Grip = CFrame.new(g.Position * ks) * (g - g.Position)
                            print(string.format("👑 [KingScale] 무기 확대 ×%.2f → %s", ks, player.Name))
                        end
                    end

                    -- ⚠️ [STAGE2-TAGGER-SLOW] 2단계 한정 태거 감속.
                    --   [이유] 태거와 러너가 둘 다 WalkSpeed 16(동속)이라 추격이 수학적으로
                    --          불가능했다. 같은 속도면 거리가 영원히 줄지 않는다.
                    --          러너의 유일한 접근 수단인 대시는 6초 쿨에 순이득 22 stud 뿐이라
                    --          태거가 등만 돌리면 2단계 내내 못 잡는다.
                    --   [값 근거] 러너16 / 태거14 = 1.143. 추격이 성립하는 업계 기준선이
                    --          "추격자 +10~15%"(Dead by Daylight 생존자 4.0 vs 킬러 4.6 = 115%)인데
                    --          여기서는 러너가 추격자 역할이므로 그 비율을 그대로 뒤집어 적용했다.
                    --   ⚠️ 1단계는 건드리지 않는다. 1단계는 태거 우위가 설계 의도다.
                    --   ⚠️ 라운드 종료 시 복원이 필요하다. 종료 시 캐릭터를 리스폰하지 않고
                    --      같은 몸으로 로비 이동하므로, 안 되돌리면 감속이 로비까지 따라간다.
                    --      복원은 RoundSystem 의 로비 복귀 루프에서 이 속성을 보고 처리한다.
                    --      (속성으로 표시하는 이유: 러너의 스피드 포션까지 싸잡아 되돌리지 않기 위해)
                    do
                        local thum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                        if thum and thum.Health > 0 then
                            -- 🏃 [2026-09-12] WalkSpeedManager 로 이관.
                            --   [왜 base 인가] 이건 CC 가 아니라 '기준 속도 변경'이다.
                            --     배율로 걸면 CC 배율과 곱해져 의미가 흐려지고,
                            --     CC 가 풀릴 때 16 으로 되돌아가 감속이 사라진다.
                            --   ⚠️ 직접 대입으로 두면 슬램 스턴이 풀릴 때 16 으로 복원돼
                            --     2단계 감속이 날아간다 — 이관하지 않으면 안 되는 이유.
                            if _G.WalkSpeed then
                                _G.WalkSpeed.setBase(player.Character, 14)
                            else
                                thum.WalkSpeed = 14
                            end
                            thum:SetAttribute("Stage2Slowed", true)
                            print("🐢 태거 2단계 감속: 16 → 14 (" .. player.Name .. ")")
                        end
                    end
                end
            end
        end
    end
end

-- 🚪 성문 붕괴 훅에서 부른다(_G.FinalizeTaggerHp 와 한 짝).
--   ⚠️ 전역 노출 사유는 FinalizeTaggerHp 와 같다 — BarricadeSystem 이 별도 스크립트다.
--   ⚠️ 순서: HP 확정 → PushTool 지급. 반대로 하면 지급 직후 HP 재산정이 돌아
--     TaggerBotSystem 의 피격 관찰자가 혼란스러운 값을 본다.
_G.GrantTaggerPushTool = grantTaggerPushTool

-- ── 트리거 발동 ────────────────────────────────────────
local function triggerStage2(reachedRunner)
    if stage2Active then return end
    stage2Active = true

    print(string.format("🎯 [Stage2] 진입! 첫 도달자: %s",
        reachedRunner and reachedRunner.Name or "?"))

    -- 🏰 [2026-09-11] 공성 인원 스케일은 여기서 부르지 않는다.
    --   [왜 뺐나] 진입 시점에 확정하면 그 뒤 킹이 계속 죽여도 반영이 안 된다.
    --     실측 16:05 판 — 진입 9명으로 9칸이 잠긴 뒤 15초간 8명이 처형돼,
    --     남은 1명이 9칸을 26초에 걸쳐 부쉈다. 고치려던 증상이 그대로 재현됐다.
    --   [지금] BarricadeSystem.damageSegment 가 '첫 타격' 에 스스로 확정한다.
    --     성문을 실제로 때리는 순간이 공성 인원이 정해지는 유일한 시점이다.

    -- ⚠️ 여기서 태거 HP 를 확정하지 않는다. 바리케이드 붕괴 시점으로 옮겼다
    --    (finalizeTaggerHp 상단 주석 참조).
    -- ⚠️ 태거 PushTool 도 여기서 주지 않는다. grantTaggerPushTool 이 성문 붕괴 훅에서
    --    불린다 — 공성 중에는 공성 도구로만 견제한다.

    -- 모든 러너에게 2단계 무기 지급 (반격 수단).
    -- 각 러너가 인벤 Weapon 탭에서 고른 EquippedWeapon 속성을 읽어 그 무기를 지급.
    -- 선택 안 했으면 기본값 ClassicSword.
    local ServerStorage = game:GetService("ServerStorage")
    local runnerItems = ServerStorage:FindFirstChild("RunnerItem")
    if not runnerItems then
        warn("[Stage2] ServerStorage.RunnerItem 없음 - 러너 무기 지급 실패")
    else
        for _, player in ipairs(Players:GetPlayers()) do
            if player:GetAttribute("Role") == "Runner" and player.Character then
                local hum = player.Character:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    -- 선택한 무기 (없으면 기본 ClassicSword)
                    local weaponName = player:GetAttribute("EquippedWeapon")
                    if not weaponName or weaponName == "" then
                        weaponName = "ClassicSword"
                    end
                    local template = runnerItems:FindFirstChild(weaponName)
                    if not template then
                        -- 선택 무기 템플릿이 없으면 기본으로 폴백
                        warn("[Stage2] 무기 템플릿 없음:", weaponName, "→ ClassicSword 폴백")
                        template = runnerItems:FindFirstChild("ClassicSword")
                    end
                    if template then
                        -- 중복 지급 방지: 이미 "Tool"을 들고 있을 때만 스킵.
                        -- (이름만 같은 잔존물 — 파괴 실패한 이펙트/부착물 — 에 속아
                        --  지급을 건너뛰면 2단계 무기 먹통이 되므로 클래스 검증 필수)
                        local exB = player.Backpack:FindFirstChild(template.Name)
                        local exC = player.Character:FindFirstChild(template.Name)
                        local hasAlready = (exB and exB:IsA("Tool")) or (exC and exC:IsA("Tool"))
                        if (exB and not exB:IsA("Tool")) or (exC and not exC:IsA("Tool")) then
                            print("⚠️ [Stage2] 이름만 같은 잔존물 감지(지급은 진행):", template.Name)
                        end
                        -- 🔴 [계측 2026-09-20] 침묵 스킵을 없앤다.
                        --   [왜] 라이브 제보: "2단계에서 클래식 소드가 손에는 있는데
                        --     인벤·스킬이 없고 사용이 안 된다". 그런데 이 경로는 로그가 없어서
                        --     '지급 실패'인지 '이미 있다고 판단해 스킵'인지 구분할 수가 없었다.
                        --     바로 위 '이름만 같은 잔존물' 분기는 print 를 남기는데,
                        --     **진짜 Tool 이 남아 있는 경우만 조용하다** — 가장 의심스러운 쪽이 안 보였다.
                        --   [왜 잔재가 남을 수 있나] 캐릭터는 라운드를 넘어 유지된다(이 파일 71행).
                        --     Backpack 도 같이 유지되므로, 라운드 종료 회수(RoundSystem 2285행)가
                        --     한 명에게만 실패하면 그 사람만 다음 라운드에 무기를 못 받는다.
                        --   ⚠️ warn 이다 — 정상 동작이 아니라 이상 신호이므로 허브에 잡혀야 한다.
                        --   ⚠️ 확인되면 이 블록은 남기되, 원인이 잡히면 회수 쪽을 고칠 것.
                        --     여기서 잔재를 지우고 새로 주는 건 증상 덮기다 — 왜 남았는지를 먼저 본다.
                        if hasAlready then
                            warn(string.format(
                                "⚠️ [Stage2] %s 무기 지급 스킵 — 이미 %s 보유(이전 라운드 잔재 의심) | 백팩=%s 손=%s",
                                player.Name, template.Name,
                                tostring(exB ~= nil), tostring(exC ~= nil)))
                        end
                        if not hasAlready then
                            local weapon = template:Clone()

                            -- 무기 스킨 색 입히기: 장착 무기가 ClassicSword면 선택한 색 스킨 적용.
                            if weaponName == "ClassicSword" and _G.getEquippedSkin and _G.getSwordSkinData then
                                local skinName = _G.getEquippedSkin(player, "ClassicSword")
                                local skinData = skinName and _G.getSwordSkinData("ClassicSword", skinName)
                                local handle = weapon:FindFirstChild("Handle")
                                if skinData and handle and skinData.meshSwap then
                                    -- 모델 교체 스킨(Frozen Sword 등): Handle 투명화 + WeaponSkins 메시 용접
                                    handle.Transparency = 1
                                    local hmesh = handle:FindFirstChild("Mesh")
                                    if hmesh then hmesh.TextureId = "" end
                                    local skinMesh = ServerStorage:FindFirstChild("WeaponSkins")
                                    skinMesh = skinMesh and skinMesh:FindFirstChild(skinData.meshSwap)
                                    if skinMesh then
                                        local m = skinMesh:Clone()
                                        m.Name = "_SkinMesh"
                                        m.Anchored = false
                                        m.CanCollide = false
                                        m.Massless = true
                                        -- 정렬값(SkinManager 실측): scale/offset/rot
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
                                        -- 스윙 눈송이: 검신 끝에 어태치먼트 + 눈송이 파티클(스윙 감지는 SwordScript가 담당하거나 상시 은은)
                                        if skinData.swingSnow then
                                            weapon:SetAttribute("SwingSnow", true)
                                        end
                                    end
                                elseif skinData and handle then
                                    if skinData.material then
                                        handle.Material = Enum.Material[skinData.material]
                                    end
                                    if skinData.cycle then
                                        -- 무지개 순환: 텍스처 제거 + 순환 스크립트 템플릿 복제 삽입.
                                        -- (런타임 서버는 .Source를 못 쓰므로 미리 만든 템플릿을 Clone)
                                        local mesh = handle:FindFirstChild("Mesh")
                                        if mesh then mesh.TextureId = ""; mesh.VertexColor = Vector3.new(1,1,1) end
                                        local tmpl = ServerStorage:FindFirstChild("RainbowCycleTemplate")
                                        if tmpl then
                                            local cyc = tmpl:Clone()
                                            cyc.Name = "RainbowCycle"
                                            cyc.Disabled = false
                                            cyc.Parent = handle
                                        end
                                    elseif skinData.color then
                                        -- 정적 색: 네온 발광 위해 텍스처 제거 + 색 적용
                                        local mesh = handle:FindFirstChild("Mesh")
                                        if mesh then mesh.TextureId = ""; mesh.VertexColor = Vector3.new(1,1,1) end
                                        handle.Color = skinData.color
                                    end
                                    -- VFX/model swap (e.g. Pool Noodle): clone ServerStorage template onto Handle
                                    if skinData.vfxAttachment then
                                        local vfx = ServerStorage:FindFirstChild(skinData.vfxAttachment)
                                        if vfx then
                                            local oldv = handle:FindFirstChild(skinData.vfxAttachment)
                                            if oldv then oldv:Destroy() end
                                            vfx:Clone().Parent = handle
                                        end
                                    end
                                elseif handle then
                                    -- _Custom: ClassicColor/ClassicMaterial 속성 있으면 칠 (없으면 원본 텍스처 검)
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

                            -- 카타나 색놀이: 검은 계열 파트를 스킨 색으로 칠하고,
                            -- 무기에 SkinColor 속성 심음(카운터 참격이 이 색을 읽음).
                            -- Diamond Blade mesh-swap skin (Ice Crystal Blade): hide Handle
                            -- SpecialMesh + weld WeaponSkins mesh. Same pattern as ClassicSword.
                            if weaponName == "DiamondBladeSword" and _G.getEquippedSkin and _G.getSwordSkinData then
                                local skinName = _G.getEquippedSkin(player, "DiamondBladeSword")
                                local skinData = skinName and _G.getSwordSkinData("DiamondBladeSword", skinName)
                                local handle = weapon:FindFirstChild("Handle")
                                if skinData and handle and skinData.meshSwap then
                                    handle.Transparency = 1
                                    local hmesh = handle:FindFirstChild("Mesh")
                                    if hmesh then hmesh.TextureId = "" end
                                    local skinMesh = ServerStorage:FindFirstChild("WeaponSkins")
                                    skinMesh = skinMesh and skinMesh:FindFirstChild(skinData.meshSwap)
                                    if skinMesh then
                                        local m = skinMesh:Clone()
                                        m.Name = "_SkinMesh"
                                        m.Anchored = false
                                        m.CanCollide = false
                                        m.Massless = true
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
                                        if skinData.iceMarks then
                                            weapon:SetAttribute("IceMarks", true)
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
                                    end
                                end
                            end

                            -- Flame Hammer mesh-swap skin: hide all hammer parts + weld the WeaponSkins mesh.
                            if weaponName == "HammerHigh" and _G.getEquippedSkin and _G.getSwordSkinData then
                                local skinName = _G.getEquippedSkin(player, "HammerHigh")
                                local skinData = skinName and _G.getSwordSkinData("HammerHigh", skinName)
                                local handle = weapon:FindFirstChild("Handle")
                                if skinData and handle and skinData.meshSwap then
                                    for _, d in ipairs(weapon:GetDescendants()) do
                                        if d:IsA("BasePart") then d.Transparency = 1 end
                                    end
                                    if skinData.flameOffset then
                                        local ft = weapon:FindFirstChild("flame tail")
                                        if ft then
                                            for _, w in ipairs(weapon:GetDescendants()) do
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
                                        weld.Part0 = handle
                                        weld.Part1 = m
                                        weld.Parent = m
                                        m.Parent = handle
                                    end
                                end
                            end

                            if weaponName == "KatanaSword2" and _G.getEquippedSkin and _G.getSwordSkinData then
                                local skinName = _G.getEquippedSkin(player, "KatanaSword2")
                                local skinData = skinName and _G.getSwordSkinData("KatanaSword2", skinName)
                                if skinData and skinData.meshSwap then
                                    -- 모델 교체 스킨(Crimson Fang 등): 기존 파트 전부 투명화 후 스킨 메시 용접.
                                    -- ⚠ ClassicSword와 달리 카타나는 Handle 외 부품이 9개 더 있어
                                    --    Handle만 숨기면 칼날/츠바가 그대로 남음 → 전체 순회 필요.
                                    local handle = weapon:FindFirstChild("Handle")
                                    for _, p in ipairs(weapon:GetDescendants()) do
                                        if p:IsA("BasePart") then
                                            p.Transparency = 1
                                            local msh = p:FindFirstChildWhichIsA("SpecialMesh")
                                            if msh then msh.TextureId = "" end
                                            for _, dec in ipairs(p:GetChildren()) do
                                                if dec:IsA("Decal") or dec:IsA("Texture") then dec:Destroy() end
                                            end
                                        end
                                    end
                                    local bank = ServerStorage:FindFirstChild("WeaponSkins")
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
                                            -- ⚠ Model:PivotTo() 금지: 임포트 모델은 Pivot이 월드 원점에
                                            --    잡혀 큰 오프셋 발생. PrimaryPart 기준 상대 CFrame으로 개별 배치.
                                            local ref = sk.PrimaryPart.CFrame
                                            sk.Parent = weapon
                                            for _, p in ipairs(sk:GetDescendants()) do
                                                if p:IsA("BasePart") then
                                                    local rel = ref:ToObjectSpace(p.CFrame)
                                                    p.CFrame = target * rel
                                                    p.Anchored = false
                                                    p.CanCollide = false
                                                    p.Massless = true
                                                    local w = Instance.new("WeldConstraint")
                                                    w.Part0 = handle; w.Part1 = p; w.Parent = handle
                                                end
                                            end
                                        else
                                            sk.Size = sk.Size * (skinData.swapScale or 1)
                                            sk.Anchored = false; sk.CanCollide = false; sk.Massless = true
                                            sk.CFrame = target
                                            sk.Parent = weapon
                                            local w = Instance.new("WeldConstraint")
                                            w.Part0 = handle; w.Part1 = sk; w.Parent = handle
                                        end
                                        -- 카운터 참격 색: 발광부 색을 따라감
                                        local glow = sk:FindFirstChild("Glow", true)
                                        weapon:SetAttribute("SkinColor", glow and glow.Color or Color3.fromRGB(255, 0, 1))
                                    weapon:SetAttribute("LegendarySkin", true)   -- 카운터 EMP 트리거
                                    end
                                elseif skinData and skinData.color then
                                    for _, p in ipairs(weapon:GetDescendants()) do
                                        if p:IsA("BasePart") then
                                            local c = p.Color
                                            if c.R*255 < 80 and c.G*255 < 80 and c.B*255 < 80 then
                                                p.Color = skinData.color
                                            end
                                        end
                                    end
                                    weapon:SetAttribute("SkinColor", skinData.color)
                                elseif not skinData then
                                    -- _Custom: KatanaColor/KatanaMaterial 속성 있으면 태그 파트 칠 + SkinColor(카운터 참격용)
                                    local colorName = player:GetAttribute("KatanaColor_Blade")
                                    if colorName then
                                        local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
                                        if palette.COLORS[colorName] then
                                            local cfg = palette.getConfig("KatanaSword2")
                                            local finishKey = player:GetAttribute("KatanaMaterial_Blade") or cfg.materialDefault
                                            local col = palette.COLORS[colorName]
                                            for _, p in ipairs(weapon:GetDescendants()) do
                                                if p:IsA("BasePart") and p:GetAttribute("SkinPaintPart") then
                                                    palette.applyFinish(p, finishKey, col)
                                                end
                                            end
                                            weapon:SetAttribute("SkinColor", col)
                                        end
                                    end
                                end
                            end

                            -- Flame Hammer(로켓 해머): 무지개 스킨 장착 시 RainbowSkin 속성 부여.
                            -- 색/순환 로직은 HammerHighScript에 내장 → 속성만 켜면 머리+flame tail 순환.
                            if weaponName == "HammerHigh" and _G.getEquippedSkin and _G.getSwordSkinData then
                                local skinName = _G.getEquippedSkin(player, "HammerHigh")
                                local skinData = skinName and _G.getSwordSkinData("HammerHigh", skinName)
                                if skinData then
                                    if skinData.rainbow then
                                        weapon:SetAttribute("RainbowSkin", true)
                                    elseif skinData.solidHSV then
                                        weapon:SetAttribute("SkinHue", skinData.solidHSV[1])
                                        weapon:SetAttribute("SkinSat", skinData.solidHSV[2])
                                        weapon:SetAttribute("SkinVal", skinData.solidHSV[3])
                                        if skinData.loveEffect then weapon:SetAttribute("LoveEffect", true) end
                                        if skinData.iceGround then weapon:SetAttribute("IceGround", true) end
                                        if skinData.snowEffect then weapon:SetAttribute("SnowEffect", true) end
                                        if skinData.swingAnim then weapon:SetAttribute("SwingAnim", skinData.swingAnim) end
                                        if skinData.inspectAnim then weapon:SetAttribute("InspectAnim", skinData.inspectAnim) end
                                    end
                                elseif not skinData then
                                    -- _Custom: FlameColor → HSV → SkinHue/Sat/Val (HammerHighScript가 본체 Neon + flame 칠)
                                    local colorName = player:GetAttribute("FlameColor_Head")
                                    if colorName then
                                        local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
                                        local col = palette.COLORS[colorName]
                                        if col then
                                            local h, s, v = col:ToHSV()
                                            weapon:SetAttribute("SkinHue", h)
                                            weapon:SetAttribute("SkinSat", s)
                                            weapon:SetAttribute("SkinVal", v)
                                        end
                                    end
                                end
                            end

                            -- Sakura Blade: 무지개 순환 / 단색. 색 로직은 SwordScript에 내장
                            -- → 속성만 부여하면 칼날 VertexColor + 오라가 그 색으로.
                            if weaponName == "SakuraBlade" and _G.getEquippedSkin and _G.getSwordSkinData then
                                local skinName = _G.getEquippedSkin(player, "SakuraBlade")
                                local skinData = skinName and _G.getSwordSkinData("SakuraBlade", skinName)
                                if skinData then
                                    if skinData.rainbow then
                                        weapon:SetAttribute("RainbowSkin", true)
                                    elseif skinData.solidHSV then
                                        weapon:SetAttribute("SkinHue", skinData.solidHSV[1])
                                        weapon:SetAttribute("SkinSat", skinData.solidHSV[2])
                                        weapon:SetAttribute("SkinVal", skinData.solidHSV[3])
                                    end
                                elseif not skinData then
                                    -- _Custom: SakuraColor → HSV → SkinHue/Sat/Val (SwordScript가 칼날 VertexColor + 오라 칠)
                                    local colorName = player:GetAttribute("SakuraColor_Blade")
                                    if colorName then
                                        local palette = require(game:GetService("ReplicatedStorage"):WaitForChild("NoobColorPalette"))
                                        local col = palette.COLORS[colorName]
                                        if col then
                                            local h, s, v = col:ToHSV()
                                            weapon:SetAttribute("SkinHue", h)
                                            weapon:SetAttribute("SkinSat", s)
                                            weapon:SetAttribute("SkinVal", v)
                                            local cfg = palette.getConfig("SakuraBlade")
                                            local finishKey = player:GetAttribute("SakuraMaterial_Blade") or cfg.materialDefault
                                            local f = palette.FINISHES[finishKey]
                                            weapon:SetAttribute("SkinMaterial", (f and f.material) or "Metal")
                                        end
                                    end
                                end
                            end

                            -- HammerLow: 색놀이/effectModel/Rainbow/Lightning + _Custom. HammerScript가 속성 읽어 본체+스핀이펙트 칠.
                            if weaponName == "HammerLow" and _G.getEquippedSkin and _G.getSwordSkinData then
                                local skinName = _G.getEquippedSkin(player, "HammerLow")
                                local skinData = skinName and _G.getSwordSkinData("HammerLow", skinName)
                                if skinData then
                                    if skinData.color then weapon:SetAttribute("SkinColor", skinData.color) end
                                    if skinData.material then weapon:SetAttribute("SkinMaterial", skinData.material) end
                                    if skinData.effectColor then weapon:SetAttribute("EffectColor", skinData.effectColor) end
                                    if skinData.effectModel then weapon:SetAttribute("EffectModel", skinData.effectModel) end
                                    if skinData.particle then weapon:SetAttribute("Particle", skinData.particle) end
                                    if skinData.thunderStrike then weapon:SetAttribute("ThunderStrike", true) end
                                    if skinData.auraParticle then weapon:SetAttribute("AuraParticle", skinData.auraParticle) end
                                    if skinData.keepTexture then weapon:SetAttribute("KeepTexture", true) end
                                    if skinData.meshSwap then
                                        weapon:SetAttribute("MeshSwap", skinData.meshSwap)
                                        if skinData.swapScale then weapon:SetAttribute("SwapScale", skinData.swapScale) end
                                        if skinData.swapOffset then weapon:SetAttribute("SwapOffset", Vector3.new(skinData.swapOffset[1], skinData.swapOffset[2], skinData.swapOffset[3])) end
                                        if skinData.swapRot then weapon:SetAttribute("SwapRot", Vector3.new(skinData.swapRot[1], skinData.swapRot[2], skinData.swapRot[3])) end
                                    end
                                    if skinData.rainbow then
                                        local handle = weapon:FindFirstChild("Handle")
                                        if handle then
                                            local mesh = handle:FindFirstChildOfClass("SpecialMesh")
                                            if mesh then mesh.TextureId = "" end
                                            handle.Material = Enum.Material.Neon
                                            handle:SetAttribute("RainbowPart", true)
                                        end
                                        weapon:SetAttribute("RainbowSkin", true)
                                        local tmpl = ServerStorage:FindFirstChild("HammerRainbowTemplate")
                                        if tmpl then
                                            local cyc = tmpl:Clone()
                                            cyc.Name = "HammerRainbow"
                                            cyc.Disabled = false
                                            cyc.Parent = weapon
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
                                            weapon:SetAttribute("SkinColor", col)
                                            weapon:SetAttribute("SkinMaterial", (f and f.material) or "Neon")
                                            weapon:SetAttribute("EffectColor", col)
                                        end
                                    end
                                end
                            end

                            weapon.Parent = player.Backpack
                            -- [STAGE2-AUTOEQUIP] 손에 쥐여 준다. 해제는 자유.
                            do
                                local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
                                if hum and hum.Health > 0 then
                                    pcall(function() hum:EquipTool(weapon) end)
                                end
                            end
                            print("⚔️ 무기 지급+장착:", player.Name, "→", template.Name)
                        end
                    end
                end
            end
        end
    end

    -- 🗡️ [③ 2026-09-12] 히어로봇도 여기서 무기를 받는다 — 유저와 같은 시점.
    --   [왜] 1단계부터 히어로만 무기를 들면 유저가 "쟤는 있는데 나는 왜 없지?"가 된다.
    --     지급 시점을 맞춰야 "2단계에 무기를 받는다"가 하나의 규칙으로 읽힌다.
    --   [차이] 유저는 Backpack → EquipTool. 봇은 Player 가 없어 Backpack 도 없으므로
    --     캐릭터에 직접 Parent 한다(그러면 자동 장착된다).
    --   ⚠️ 무기 판정은 Handle.Touched 다. 봇이 킹에게 실제로 닿아야 들어간다.
    --   ⚠️ 스킨·색 분기는 태우지 않는다. 그건 플레이어 소유 코스메틱이다.
    do
        local ServerStorage = game:GetService("ServerStorage")
        -- 🗡️ [③ 2026-09-12] 히어로 무기 랜덤 지급.
        --   [왜 랜덤인가] RunnerBotDriveController 의 KILL_ROUND_CHANCE 주석이 노린 것 —
        --     "무기가 눈에 보여서 킹이 판 시작에 읽을 수 있고, 어느 조합이든 압박이 안 죽는다".
        --     히어로 수를 max(0, 4-N) 으로 고정하면서 잃은 판별 다양성을 여기서 되살린다.
        --
        --   ⚠️ 이 목록에 있는 무기만 봇 배선이 검증됐다. 아무거나 넣지 말 것.
        --     넣기 전 확인: ① Plyr 가드가 봇에서 안 죽는가(Plyr or Char)
        --                   ② 쿨다운이 Player 속성이면 캐릭터 속성으로 열었는가
        --                   ③ F 스킬이 있으면 Tool 에 BindableFunction "BotSkill" 을 걸었는가
        --                   ④ creator 태그가 Plyr or Char 인가
        --
        --   [제외된 무기와 이유 — 인계 문서 3-9 참조]
        --     DiamondBladeSword  표식 완주에 '킹 주위를 도는' 행동 필요. DoSpecial 은 비활성
        --     Gauntlet           chargeRatio 를 클라가 잰다 / 돌진·그랩이 다중 시 경합
        --
        --   ⚠️ [알려진 한계] 봇 행동이 "붙어서 때린다" 하나뿐이라 거리 운영이 필요한
        --     효과는 발동해도 이득이 없다(ClassicSword 사거리 증강 / HammerHigh 도약).
        --     데미지는 들어가므로 쓰긴 쓴다. 근본 해결은 '거리 기반 스킬 선택'이고 별도 과제.
        local HERO_WEAPONS = {
            "HammerLow",         -- 스핀 (제자리 광역) — 봇과 가장 잘 맞는다
            "KatanaSword2",      -- 카운터 (밀치기 반격) — PushTool 이 자동 호출
            "DragonFireSword",   -- 평타 전용 (스택 폭발은 부산물)
            "SakuraBlade",       -- 평타 전용 (스택 공속·이속)
            "ClassicSword",      -- 런지
            "HammerHigh",        -- 도약 슬램
        }
        local pool = ServerStorage:FindFirstChild("RunnerItem")
        -- 🗡️ [TEST 2026-09-12] /hw 커맨드로 무기를 강제했으면 전원 그것으로.
        --   ⚠️ PushToolDebug 의 /hw 와 한 짝이다. 릴리즈 전 같이 삭제할 것.
        --   ⚠️ 강제 시에는 중복 제거가 무의미하므로 셔플을 건너뛴다.
        local forced = _G.ForceHeroWeapon
        -- 🎲 중복 없이 뽑는다(Fisher-Yates 셔플 후 앞에서부터).
        --   ⚠️ [2026-09-12] 중복 허용으로 뒀다가 HammerHigh 2명이 나온 판에서
        --     스턴이 번갈아 들어가 태거가 사실상 영구 행동불능이 됐다.
        --     스턴·CC 무기가 겹치면 개별 값이 아무리 온건해도 합이 성립하지 않는다.
        --   ⚠️ 히어로는 최대 4명, 목록은 6종이라 항상 중복 없이 채울 수 있다.
        --     목록이 4종 미만으로 줄면 이 전제가 깨진다 — 그때는 중복을 허용하되
        --     CC 무기에 "같은 대상에 하나만" 규칙을 따로 세워야 한다.
        local bag = table.clone(HERO_WEAPONS)
        for i = #bag, 2, -1 do
            local j = math.random(1, i)
            bag[i], bag[j] = bag[j], bag[i]
        end
        local nextIdx = 0

        local given, names = 0, {}
        for _, mdl in ipairs(workspace:GetChildren()) do
            if mdl:IsA("Model") and mdl:GetAttribute("HeroRunner") then
                local hum = mdl:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 and not mdl:FindFirstChildOfClass("Tool") then
                    nextIdx = nextIdx + 1
                    local pick = forced or bag[((nextIdx - 1) % #bag) + 1]
                    local tmpl = pool and pool:FindFirstChild(pick)
                    if tmpl then
                        local w = tmpl:Clone()
                        w.Parent = mdl
                        mdl:SetAttribute("HeroWeapon", pick)
                        given = given + 1
                        names[#names + 1] = pick
                    else
                        warn("🗡️ [Hero] ServerStorage.RunnerItem." .. pick .. " 없음 — 건너뜀")
                    end
                end
            end
        end
        if given > 0 then
            print(string.format("🗡️ [Hero] 2단계 무기 지급 %d체 → %s", given, table.concat(names, ", ")))
        end
    end

    -- 모든 클라이언트에 알림 (시각/사운드 피드백용)
    local reachedName = reachedRunner and reachedRunner.Name or "Runner"
    -- 조회용 상태도 갱신 (RoundSystem.broadcastPhase 와 같은 규약)
    ReplicatedStorage:SetAttribute("RoundPhase", "stage2")
    Stage2Started:FireAllClients(reachedName, os.time())  -- 2번째 인자: 시작 시각(관전 음악 동기화용)

    -- 👑 왕좌 점령 개시. 2단계의 목표를 여기서 연다.
    -- ⚠️ 여기가 유일한 시작점이다. 라운드 시작이 아니라 '2단계 진입' 시점이어야
    --    러너가 성 앞에 도달하기도 전에 점령이 도는 일이 없다.
    if _G.CaptureSystem then
        _G.CaptureSystem.start()
    end

    -- 코인 보상 분배:
    --   도달자(트리거자): +10 (영웅 보상)
    --   그 시점까지 살아있는 다른 러너 (다운자 포함): +5 (1단계 생존)
    --   사망자: 0
    -- RoundCoins 속성에 즉시 누적 → 라운드 종료 시 stats에 묶여 일괄 지급.
    local reachedPlayer = Players:GetPlayerFromCharacter(reachedRunner)
    for _, player in ipairs(Players:GetPlayers()) do
        if player:GetAttribute("Role") ~= "Runner" then continue end
        local char = player.Character
        if not char then continue end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end

        local amount = (player == reachedPlayer) and 10 or 5
        local current = player:GetAttribute("RoundCoins") or 0
        player:SetAttribute("RoundCoins", current + amount)
        -- 퀘스트용: 이 러너는 이번 라운드 2단계에 도달(생존)했음
        player:SetAttribute("ReachedStage2", true)
        print(string.format("📋 2단계 도달 보상 +%d: %s%s",
            amount, player.Name,
            (player == reachedPlayer) and " (도달자)" or " (생존자)"))
    end

    -- 불꽃벽 소멸: 1명이라도 도달하면 즉시 정지.
    -- 이유: 태거가 *밀쳐내기로 러너를 통로로 떨궈* 불꽃벽 즉사 콤보 만드는 악용 차단.
    --       2단계 = 결투 단계이므로 1단계 시간 압박(불꽃벽)은 더 이상 의미 없음.
    -- FirePressureSystem.stopFire()는:
    --   - 즉시 데미지 차단 (fireActive=false → kill.Touched 콜백 무효화)
    --   - 3.5초 후 시각 효과 자연 정리
    --   - 안전하게 다운자/통로 러너에게 영향 없음
    local stopFireEvent = ReplicatedStorage:FindFirstChild("StopFirePressure")
    if stopFireEvent then
        -- stopFireEvent:Fire()   -- ⚠️ [2026-08-24] 비활성화
        -- [왜] 2단계에 압박선이 꺼지면 러너를 앞으로 밀 것이 사라진다.
        --   시간 초과가 러너 승리라 '성문을 안 부수고 버티기'가 최선이 됐다.
        --   → 유지한다. END_X 685 에서 멈추므로 계단(687~711)은 안전하고,
        --      성문(726)까지 41 stud 여유가 있어 회피 불가 상황은 생기지 않는다.
        --   ⚠️ 즉사가 아니라 지속 데미지이므로 밀려도 빠져나올 수 있다.
            print("🔥 [Stage2] 압박선 유지 (계단 앞에서 정지)")
    else
        warn("[Stage2] StopFirePressure 이벤트 못 찾음 - 불꽃벽 정지 실패")
    end
end

-- ── 감시 루프 ───────────────────────────────────────────
-- 살아있는 유저 러너 수. 0이면 1인 태거 모드(AI 러너만 상대)로 간주한다.
-- 이 경우 AI 도 2단계를 열 수 있어야 라운드가 1단계에 갇히지 않는다.
local function countUserRunners()
    local n = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p:GetAttribute("Role") == "Runner" then
            local c = p.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then n += 1 end
        end
    end
    return n
end

local function startWatching()
    if watchConn then watchConn:Disconnect() end
    if not currentMap then return end

    -- 현재 맵의 트리거 영역들 수집:
    -- ItemSpawnPlate (정상 도달 — 계단)
    -- + taggerbase (우회 도달 — 점프 아이템 등으로 계단 건너뛰고 성에 직접 착지)
    -- 두 영역 모두 *태거의 영토*이므로 진입 = 결투 시작 시점.
    local triggerZones = {}
    for _, child in ipairs(currentMap:GetChildren()) do
        if child:IsA("BasePart") then
            local cname = child.Name:lower()
            if cname:find("itemspawnplate") or cname:find("taggerbase") then
                table.insert(triggerZones, child)
            end
        end
    end
    if #triggerZones == 0 then
        warn("[Stage2] " .. currentMap.Name .. " 에 트리거 영역(ItemSpawnPlate/taggerbase) 없음 - 2단계 트리거 불가")
        return
    end

    print(string.format("[Stage2] 감시 시작 (%s, %d개 영역)", currentMap.Name, #triggerZones))

    -- 0.2초마다 검사 (타이트하지만 부담 적음)
    local lastCheck = 0
    watchConn = RunService.Heartbeat:Connect(function()
        if stage2Active then return end
        -- ⚠️ 라운드가 진행 중일 때만 감시한다.
        --   stopWatching() 은 SetCurrentMap 이 nil 로 올 때만 호출되는데, 라운드가 끝나도
        --   맵 폴더는 남아 있어 감시 루프가 계속 돌았다. 그 결과:
        --     · 인터미션/킹 선정 중에 봇이 계단을 밟아 2단계가 발동
        --     · stage2Active=true 인 채로 다음 라운드 진입 → 알림·PushTool 지급 안 됨
        --   (실측 증상: 태거 사망 후에도 "결투 단계 시작" 알림이 로비에서 표시됨)
        if _G.IsRoundLive and not _G.IsRoundLive() then return end
        local now = os.clock()
        if now - lastCheck < 0.2 then return end
        lastCheck = now

        -- 모든 러너(플레이어 + NPC) 확인
        for _, char in ipairs(workspace:GetChildren()) do
            if char:IsA("Model") then
                local hum = char:FindFirstChildOfClass("Humanoid")
                local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
                if hum and hum.Health > 0 and hrp then
                    -- 2단계 발동은 원칙적으로 실제 유저(Role=Runner)만 가능.
                    -- NPC/AI(농민봇 등)는 보조 역할일 뿐, 불꽃벽 정지 같은 진행 분기를
                    -- 발동시키지 못함 (AI가 너무 유능해지는 것 방지 — 설계 원칙).
                    --
                    -- ⚠️ 단, 유저 러너가 0명인 경우(1인 태거 모드 = AI 러너만 상대)에는
                    --    이 규칙을 만족할 주체가 없어 2단계가 영구히 열리지 않았다.
                    --    → 태거가 PushTool 을 못 받고 라운드가 1단계에 갇힌다.
                    --    유저의 성취를 AI가 가로챌 위험이 없는 상황이므로 AI 도 발동을 허용한다.
                    local player = Players:GetPlayerFromCharacter(char)
                    local isRunner = player and (player:GetAttribute("Role") == "Runner")
                    local isAIRunner = (player == nil) and (char:GetAttribute("AIRunner") == true)
                    local canTrigger = isRunner or (isAIRunner and countUserRunners() == 0)

                    if canTrigger then
                        for _, zone in ipairs(triggerZones) do
                            if isInsidePlateXZ(hrp.Position, zone) then
                                triggerStage2(char)
                                return
                            end
                        end
                    end
                end
            end
        end
    end)
end

local function stopWatching()
    if watchConn then
        watchConn:Disconnect()
        watchConn = nil
    end
end

-- ── 맵 변경 / 라운드 시작 시 리셋 ────────────────────────
local setMapEvent = ReplicatedStorage:WaitForChild("SetCurrentMap", 5)
if setMapEvent and setMapEvent:IsA("BindableEvent") then
    setMapEvent.Event:Connect(function(mapFolder)
        currentMap = mapFolder
        stage2Active = false  -- 새 라운드 = 새 트리거 가능
        -- 🚪 [2026-08-29] HP 확정 잠금 해제. finalizeTaggerHp 의 taggerHpLocked 와 한 짝.
        --   ⚠️ 여기서 안 풀면 두 번째 라운드부터 태거 HP 가 영영 확정되지 않는다
        taggerHpLocked = false
        -- 🩸 HP 바 노출 신호도 함께 내린다(finalizeTaggerHp 의 세팅과 한 짝).
        --   ⚠️ 안 내리면 다음 라운드 1단계부터 확정 전 HP 바가 보인다.
        ReplicatedStorage:SetAttribute("TaggerHpReady", false)
        if mapFolder then
            startWatching()
        else
            stopWatching()
        end
    end)
else
    warn("[Stage2] SetCurrentMap 이벤트 못 찾음")
end

-- ── 외부 API (RoundSystem이 라운드 종료 시 직접 리셋용 — 옵션) ──
_G.Stage2TriggerSystem = {
    isActive = function() return stage2Active end,
    reset = function()
        stage2Active = false
        taggerHpLocked = false   -- 🚪 HP 확정 잠금도 함께 해제(짝 유지)
        ReplicatedStorage:SetAttribute("TaggerHpReady", false)   -- 🩸 바 노출 신호도 내림
        stopWatching()
    end,
}

print("✅ Stage2TriggerSystem 활성화 (러너 ItemSpawnPlate 도달 시 PushTool 지급)")
