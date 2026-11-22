-- RunnerBotDriveController (멀티 + 길찾기 주행)
-- workspace의 RunnerBot 속성 모델 전부를 각각 독립 제어.
-- 분신 지팡이(DecoySystem) 주행 로직 참고:
--   PathfindingService 경로 추종(장애물 우회 + Jump 액션) → 실패 시 시크 주행 + 끼임 점프.
-- playerspawn → 태거베이스 직진 돌격. 다운당하면 RECOVER_DELAY 후 복구(쓰러지는 연출 유지).
-- 도착 시 스폰 리셋 후 재돌격(무한 반복). 걷기 애니는 NPC라 서버에서 직접 재생.
-- ⚠️ 프로덕션 기능 (삭제 금지): 라운드 AI 러너(농민 봇) 구동의 핵심.
--    spawnAIRunners(RoundSystem)가 스폰한 RunnerBot 속성 모델을 이 스크립트가 주행시킨다.
--    (과거 "테스트 전용" 주석은 폐기 — 1인 태거 모드와 군중 보충의 필수 시스템)

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 현재 라운드 맵 (SetCurrentMap으로 갱신). GOAL_POS/START_BASE를 맵별로 맞추는 데 씀.
local currentMapFolder = nil

-- ── 설정 ────────────────────────────────────────────────
local START_BASE   = Vector3.new(-229, 5, -678)  -- playerspawn 근처 기준점
local LANE_GAP     = 6                            -- 봇 간 레인 간격(Z)
-- 목표: 태거가 서는 성 윗면 평지(taggerspawn). 성은 높이 128 블록이라 윗면 Y≈137.
-- (기존 Y=74는 성 바닥이라 AI가 평지에 못 올라갔음 — 수정)
local GOAL_POS     = Vector3.new(767, 138, -675)  -- taggerspawn 평지 좌표
local GOAL_X       = 700                           -- 이 X 이상이면 평지 진입(ItemSpawnPlate X≈699)
local GOAL_ARRIVE_Y = 126                          -- 이 높이 이상이어야 "평지 도달"(계단참 Y≈129). 아랫단 봇 오판 방지.
local WALK_SPEED   = 16
local RECOVER_DELAY = 3                            -- 다운 후 복구 대기(초)
local RESET_PAUSE  = 0.8                           -- 도착 후 리셋 대기(초)
local REPATH_DT    = 1.5                           -- 경로 재계산 주기(초)
local PATHFIND_X   = 650                            -- 이 X 이상(계단 근처)에서만 길찾기 ON. 직선 구간은 시크+회피만.
local STUCK_HEARTBEATS = 8                         -- 끼임 판정(하트비트 수)
-- ── 회피(태거 아이템 인지) 설정 ─────────────────────────
-- ⚠️ [2026-09-15] 이 값은 **현재 읽히지 않는다.** cfg.radius 가 `elite and 90 or DODGE_RADIUS`
--   인데 elite 가 항상 true 라(959행) 실제 감지 반경은 늘 엘리트 쪽 값이다.
--   비엘리트 분기를 되살릴 때를 대비해 남겨두되, **여기만 고치면 아무 일도 안 일어난다.**
--   실측 근거와 값 결정 과정은 cfg.radius 주석 참조.
local DODGE_RADIUS   = 90     -- 이 거리 안의 TaggerItems 위협 감지(stud) — 즉사라 넉넉히
local DODGE_MIN_SPEED = 12    -- 이 속도 이상으로 움직이는 아이템만 위협으로 간주
local DODGE_APPROACH  = 0.15  -- 아이템 속도방향이 봇을 향하는 정도(내적 임계, 낮을수록 민감)
local DODGE_LATERAL   = 2.2   -- 회피 시 측면 강도 (전진보다 측면 우선 → 확실히 비킴)
local DODGE_NEAR       = 22   -- 이 거리 안이면 "긴급" — 전진 멈추고 측면 전력 회피
local DODGE_HOLD       = 0.5  -- 위협 사라져도 회피 방향 유지 시간(초) — 끊김 방지
-- ── 근접 공격(라운드 AI 전용) 설정 ──────────────────────
-- 갈퀴 든 농민 AI가 태거에게 근접 공격. 데미지는 주되 태거 HP 하한선 아래로는 못 내림(승부는 유저 몫).
-- ⚠️ [밸런스 2026-08-25] 9 → 6.
--    유저 무기(클래식 소드 약 5 stud)보다 두 배 가까워
--    "닿지도 않았는데 맞는다"는 체감을 줬다.
--    6 이면 유저와 비슷하되 AI 조준 부정확성을 약간 보정한다.
local ATTACK_RANGE    = 6     -- 이 거리(stud) 안이면 태거 공격
-- 🗡️ [2026-09-04] 공격 애니.
--   [이력 ①] Roblox 기본 도구 슬래시(522635514) → 로드는 성공(경고 없음)했는데 모션이
--     전혀 안 나왔다. 표준 Tool 장착 상태 전용이라 Grip 방식 무기에는 적용되지 않는다.
--   [이력 ②] 템플릿의 Famer2.Swing(105211514) → 재생 확인(길이 1.00s). 동작은 했다.
--   [현재 ③] 121604693384591 — 사용자 지정 전용 모션.
--   ⚠️ 템플릿에서 읽는 방식을 버리고 여기 직접 둔다. 그 방식의 장점은 "인스턴스만
--     바꾸면 코드를 안 건드린다"였는데, execute_luau 는 호출 간에 인스턴스 변경이
--     유지되지 않는 것으로 확인됐다(로비 프리뷰 실측). 코드에 두는 쪽이 확실하다.
--   ⚠️ 교체 후 반드시 부팅 로그의 "공격 애니 … 길이=N" 을 볼 것. 0.00s 면 이 에셋도
--     이 리그에 안 맞는다는 뜻이다 — 로드 성공은 재생 가능을 뜻하지 않는다(이력 ① 참조).
local ATTACK_ANIM = "rbxassetid://121604693384591"
local attackTracks = {}          -- bot → AnimationTrack (setupAnim 에서 봇당 1회 로드)

-- 🏁 [2026-09-04] 존 안 행동 파라미터.
--   ZONE_HOLD_RADIUS — 킹이 존에서 이만큼 안에 있을 때만 붙는다. 넘으면 자리를 지킨다.
--     ⚠️ 크게 잡지 말 것. 킹이 봇을 존 밖으로 낚아 게이지를 멈추는 게 최적해가 된다.
--   ZONE_SPREAD_RATIO — 존 안에서 봇들이 흩어지는 반경(존 반경 대비 비율). 아래 참조.
--   [2026-09-04 재조정] 30 → 18.
--     [실측] 같은 딜(SOLO 2.5배)인데 킬 판 40.7초 vs 점령 판 28.0초(킹 사망).
--       차이는 이 반경뿐이다. 점령 판은 봇이 존에 미리 모여 있다가 킹이 방어하러
--       오는 순간 전원이 달려들어 집중포화가 된다 — 킬 판보다 오히려 치명적이었다.
--     [지금] 킹이 존 '안으로' 들어와야 붙는다. 가장자리 견제는 안전해진다.
--     ⚠️ 딜(SOLO_DAMAGE_MULT)은 건드리지 않았다. 킬 판에서 40.7초로 적정했으므로
--       범인이 아니다. 이 값만 바꿔 원인을 분리한다.
local ZONE_HOLD_RADIUS = 18
-- 👊 [2026-09-05] 봇 넉백 해제 토큰. 재사용 LinearVelocity 를 '가장 최근 타격'만 끄게 한다.
--   여러 봇이 0.18초 안에 연달아 때리면 먼저 예약된 해제가 뒤 넉백을 꺼버리는 걸 막는다.
local botKnockToken = 0
-- 🐛 [버그수정 2026-09-04] ZONE_SPREAD 12 (고정) → 존 반경 대비 비율.
--   [증상] 봇이 존에 들어갔다 나갔다만 반복하고 게이지가 0→2%→0 만 오갔다(20:05 판).
--   [원인] 존 반경이 11 인데 흩어지는 반경을 12 로 줬다. 목표 지점이 존 '밖'이라
--     들어감 → 목표를 향해 나감 → inZone=false → 다시 들어감 이 무한 반복됐다.
--     존 크기를 재보지 않고 눈대중으로 넣은 값이었다(추측 금지 원칙 위반).
--   [지금] 존 Size 에서 매번 계산한다. 존 크기가 바뀌어도 같은 버그가 안 난다.
--     0.55 = 반경의 55%. 가장자리 여유를 남겨 조금 밀려도 존을 안 벗어난다.
local ZONE_SPREAD_RATIO = 0.55

-- 🧭 [버그수정 2026-09-10] 봇마다 고정된 원형 배치 각도.
--   [증상] 링 분산도 존 분산도 둘 다 무효였다. 강타 한 방에 봇 11마리 전원이 걸린다.
--   [원인] 각도를 이름 해시 (h*31 + byte) % 360 으로 뽑았는데, 봇 이름이
--     "AIRunner_1" ~ "AIRunner_11"(RoundSystem:663) 이라 접두사가 전부 같다.
--     마지막 글자만 다르면 해시도 그 바이트 차이(1)만큼만 달라진다.
--     실측 각도 = 346,347,348,...,354,334,335 → 총 스팬 20°.
--     r=4.8 에서 호 길이 1.68 stud. 11마리가 1.68 stud 안에 겹쳐 선다 = 한 점이다.
--     09-09 링 분산 수정도, 그 전 존 분산도 같은 이유로 처음부터 no-op 였다.
--     "매 스윙 10명 전원 명중"(PushTool.Server:209 실측)의 직접 원인이 이거다.
--   [해법] BotIndex 에 황금각(137.5°)을 곱한다. 어떤 인원수에서도 고르게 흩어지고,
--     인덱스가 고정이라 매 프레임 같은 값이 나온다(랜덤이면 제자리에서 떤다).
--   [실측] 각도 최소간격 1° → 20°. 최악 방향 강타 명중 11/11 → 8/11 (r=4.8).
--   ⚠️ 폴백 해시에도 황금각을 곱한다. 안 곱하면 BotIndex 없는 봇이 옛 버그로 돌아간다.
--   ⚠️ 되돌리려면 botAngle 이 math.rad(h) 를 그대로 반환하게 한다.
local GOLDEN_ANGLE = 137.5
local function botAngle(bot)
    local idx = bot:GetAttribute("BotIndex")
    if not idx then
        local h = 0
        for i = 1, #bot.Name do h = (h * 31 + bot.Name:byte(i)) % 360 end
        idx = h
    end
    return math.rad((idx * GOLDEN_ANGLE) % 360)
end

-- 봇마다 고정된 존 내 자리.
-- ⚠️ 반경은 반드시 존 파트 크기에서 뽑을 것. 상수로 두면 위 왕복 버그가 재발한다.
local function zoneOffset(bot, zone)
    local a = botAngle(bot)
    local r = zone and (math.min(zone.Size.X, zone.Size.Z) * 0.5 * ZONE_SPREAD_RATIO) or 6
    return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

local ATTACK_DAMAGE   = 10    -- 1회 공격 데미지
-- 🎲 [2026-09-04] 라운드 목적. refreshMapTargets(맵 활성화)에서 판마다 한 번 뽑는다.
--   "capture" = 지금까지의 기본(점령존으로) / "kill" = 존 무시하고 태거만 쫓는다.
--   ⚠️ 라운드 중에는 안 바뀐다. 바뀌면 봇이 우왕좌왕해 다시 비직관적이 된다.
--   확률을 0 으로 두면 예전 동작(항상 점령)으로 즉시 원복된다.
-- 🎲 [2026-09-10] 0.35 → 0. 목적 추첨을 끈다(상수는 원복 경로로 남긴다).
--   [왜] kill 판이 더 약한 모드다. 실측 — 점령 28.8 DPS / 킬 19.4·16.7 DPS.
--     "판별 난이도 리듬"을 노렸지만 한쪽이 1.5~1.7배 약하니 리듬이 아니라
--     3판에 1판이 헐거운 판이 된다. 솔로모드 긴장감 목표와 정면으로 충돌한다.
--   [왜 킬이 약한가] 점령은 킹을 묶고 킬은 킹을 푼다. 존이 차오르면 킹은 막으러
--     와야 하지만, 킬 판은 존이 없어 킹이 어디에 있을 의무가 없다. 봇은 움직이는
--     킹을 따라다니느라 사거리 안에 있는 시간을 잃는다.
--   [왜 트리거를 안 만들었나] "점령이 막히면 킬로 전환" 을 넣으려다 그만뒀다.
--     ① 그 반응 로직이 이미 점령 분기 안에 있다(1326행) — 킹이 ZONE_HOLD_RADIUS
--       안이면 봇이 직접 붙어서 때리고, 밖이면 존을 민다. 어느 쪽이든 킹이 압박받는다.
--       킬 모드가 더해 주는 건 '목표 압박을 없애는 것' 뿐이다.
--     ② 더 약한 모드로 가는 일방 전환은 악용된다 — 킹이 일부러 존을 틀어막아
--       전환을 유발하면 더 쉬운 판을 얻는다. 벌하려던 행동에 상을 주는 꼴이다.
--   ⚠️ 이걸로 판별 다양성이 0 이 된다. 그 역할은 히어로봇 수(0~3 랜덤)로 옮긴다 —
--     무기가 눈에 보여서 킹이 판 시작에 읽을 수 있고, 어느 조합이든 압박이 안 죽는다.
--   ⚠️ _G.RunnerBotsGoKill(왕좌 붕괴)은 그대로 둔다. 그건 존이 실제로 사라진
--     경우라 "약한 모드로 도망" 이 성립하지 않는다.
local KILL_ROUND_CHANCE = 0
local roundObjective    = "capture"
-- 🔄 [2026-09-04] 공격 순간 킹을 바라보는 시간(초). 이 동안 AutoRotate 를 끈다.
--   길수록 시선이 확실하지만 그만큼 이동 방향 회전이 늦다. 쿨(1.6s)의 1/4 선.
local ATTACK_FACE_TIME = 0.4
-- 👑 [2026-09-04] 태거 솔로모드 전용 배율. 유저 러너가 0명일 때만 곱한다.
--   조정은 이 값만 만진다. 되돌릴 값은 1.0. 근거는 scaledAttackDamage 주석 참조.
--   [2026-09-04 재조정] 2.5 → 2.0.
--     [왜 2.5 가 과했나] 2.5 를 정할 때 근거로 쓴 18:25 판은 ①존 안 접근·③자리 분산이
--       안 돌던 '킬 판'이었다. 그 뒤 존 안 행동이 얹히면서 실효 딜이 올라갔는데
--       배율은 그대로 뒀다 — 두 변경이 곱해진 것을 못 봤다.
--     [실측] 22:36 점령 판 — 킹 825 를 28.6초에 소진(28.8 DPS). 목표 30~40초 미달.
--       같은 조건 킬 판(22:41)은 19.4 DPS / 38.7초. 판 목적만으로 1.5배가 벌어진다.
--       ⚠️ 점령 판이 더 치명적인 구조는 그대로다. 배율은 낮은 쪽(점령)에 맞춘다.
--     [예상] 2.0 → 점령 판 23.0 DPS / 36초. 킬 판은 그만큼 여유가 생긴다.
local SOLO_DAMAGE_MULT = 2.0
-- ⚠️ 8 → 10 상향. 근거: 태거 HP 300 기준 봇 1마리 DPS 5.0/s(단독 60초)로
--    솔로 모드에서 긴장감이 없었다. AI 총원도 5 → 10 으로 늘렸으므로
--    개별 데미지를 크게 올리면 곱해져 과해진다(15였다면 10마리 94/s = 3.2초).
--    10이면 10마리 동시 접촉 시 62.5/s → 약 4.8초. 실제로는 접촉 범위(9) 때문에
--    동시 접촉이 5~6마리 수준이라 8~10초 선. F5 실측 후 재조정.
local ATTACK_COOLDOWN = 1.6   -- 공격 쿨다운(초) — 느리게(AI 약화). ⚠️ 농민(평타) 전용이다.
-- 🗡️ [2026-09-18] 히어로봇의 무기 스윙 간격. 유저와 같은 리듬을 주기 위한 값.
--   [왜 따로 두나] 이 파일의 원칙은 swingHeroWeapon 주석에 이미 적혀 있다 —
--     "쿨다운·중복은 무기가 알아서 막는다. 같은 규칙을 두 곳에 두지 않는다."
--     그런데 실제로는 무기 쿨(HIT_COOLDOWN 0.5) 위에 봇 쿨(1.6)이 겹쳐 있었다.
--     규칙이 두 곳에 있었고, 느린 쪽이 이겨 히어로가 유저의 1/3 속도로 싸웠다.
--   [실측 2026-09-18] 봇 타격 빈도 0.63 타/초 = 1/1.6 과 정확히 일치했다.
--     무기를 들든 안 들든 이 상수가 빈도를 정하고 있었다는 뜻이다.
--   [값의 근거] 러너 무기 5종이 전부 HIT_COOLDOWN 0.5 다(실측). 거기 맞춘다.
--     무기가 더 느리면 tool.Enabled 가 false 라 어차피 그 무기 쿨이 이긴다 —
--     이 값은 '상한'이 아니라 '시도 주기'다. 무기가 최종 결정권을 갖는다.
--   ⚠️ 이 값을 0 으로 두지 말 것. 매 틱 Activate() 가 돌아 무기 쿨을 관리하지 않는
--     무기가 하나라도 있으면 초당 60회 발동한다.
--   ⚠️ 평타 폴백은 이 주기를 따르지 않는다. attackTagger 안에서 ATTACK_COOLDOWN 으로
--     따로 묶는다 — 안 그러면 히어로가 0.5초마다 평타 20 을 넣어 농민의 3.2배가 된다.
local HERO_SWING_COOLDOWN = 0.5
-- 🔬 [진단 2026-09-18 → 결론] 히어로가 킹을 보고 휘두르는가. **기각됐다.**
--   [가설] 회전 연출이 1.6초 주기인데 히어로 스윙은 0.5초라, 3번 중 2번은
--     이동 방향을 보고 헛스윙할 것이다.
--   [실측 14샘플] 틀렸다. 봇은 거의 항상 킹을 보고 휘두른다 —
--       d ≥ 0.9 (25° 이내)  9건 (64%)
--       d ≥ 0.7 (45° 이내) 13건 (93%)
--       d < 0.7             1건 (86°, 7%)
--       음수(등 뒤)          0건
--     AutoRotate 가 이동 방향으로 돌리는데도 조준이 맞는 이유는,
--     봇이 킹에게 접근하는 중에 사거리에 들어오기 때문이다 — 이동 방향 = 킹 방향.
--   [그래서 전방 판정을 넣지 않았다] 넣어도 잘려나갈 스윙이 7% 뿐이라 이득이 없고,
--     임계값을 0.7 로 잡으면 오히려 정상 스윙 하나를 더 깎는다.
--   🔴 [대신 드러난 것] 같은 로그로 스윙 **횟수**가 나왔다. 히어로 4명이 31초에 12회 =
--     1인당 0.097 회/초. 무기 쿨 0.5초면 최대 2회/초이므로 **한계의 5%** 다.
--     병목은 쿨도 조준도 아니라 '킹 곁에 있는 시간'이다. 다음에 볼 곳은 그쪽.
--   ⚠️ 다시 켤 일이 있으면 측정 위치를 지킬 것 — 회전 코드보다 **먼저** 재야 한다.
--     뒤에서 재면 보정값만 찍혀 "잘 보고 있다"가 거짓으로 나온다.
local AIM_DIAG = false
local ATTACK_HP_FLOOR_RATIO = 0.15  -- 태거 HP 이 비율 아래로는 AI가 못 깎음(막타는 유저)
-- ⚠️ [밸런스 2026-08-29] 0.25 → 0.15.
--   [증상] AI 러너가 여럿 붙어도 태거 체력이 잘 안 줄었다.
--   [원인] 이 하한이 생각보다 큰 몫을 잠그고 있었다.
--     태거 HP 825 기준 206 은 AI 가 아예 손댈 수 없는 구간이었다 → 619 에서 멈춘다.
--     0.15 면 124 로 줄어 AI 가 닿는 범위가 82 만큼 넓어진다.
--   [왜 데미지가 아니라 이 값인가] ATTACK_DAMAGE 는 이미 "10마리가 동시에 때리면
--     과하다"는 판단으로 15 → 10 으로 낮춘 값이다(위 주석). 그 판단을 뒤집지 않고
--     '실제로 안 깎이던 몫'만 돌려주는 쪽을 먼저 시도한다.
--   ⚠️ "막타는 유저" 의도는 유지된다. 마지막 15% 는 여전히 유저 몫이다.
--   ⚠️ 한 번에 하나씩. 이것만으로 부족하면 그때 ATTACK_DAMAGE 나 ATTACK_COOLDOWN 을 본다.
-- 👊 [타격감 2026-09-04] 28 → 14, 그리고 넉백을 다시 켠다.
--   [껐던 이유] "AI 10체의 넉백이 누적돼 KING 이 태거베이스 뒤로 몰렸다.
--     그러면 슬랩으로 러너를 계단 쪽으로 밀 수 없어 일방적으로 다굴당했다."
--   [지금은 왜 다른가] 봇이 2단계에 킹이 아니라 점령존을 목표로 삼는다(2026-09-04).
--     실측 3판 킹 피해 5.6~11.8 DPS — 애초에 밀착하는 봇이 적어 누적이 안 일어난다.
--     그리고 그 결과 "맞는 감각이 없다"는 반대 문제가 생겼다.
--   [왜 14 인가] 예전 문제를 만든 28 의 절반. 밀리는 느낌은 주되 위치는 안 바뀌는 선을
--     노린 값이다. 부족하면 20 → 28 순으로 올린다.
--   ⚠️ 되돌릴 땐 ATTACK_KNOCKBACK_ENABLED = false 하나면 즉시 원복된다.
--   ⚠️ KB_THRESH(40)보다 작아 봇 킹의 슈퍼아머 계산에는 걸리지 않는다. 안전하게 만질 수 있다.
--   [2026-09-04 재조정] 14 → 8. 봇이 10마리라 넉백이 겹쳐 킹의 이동이 묶였다.
--     타격감은 8 로도 남는다(0 과의 차이가 크고, 14→8 은 체감이 완만하다).
--     ⚠️ 이게 옛 문제(누적 밀림)의 축소판이다. 더 필요하면 6 → 4 순으로 내린다.
local ATTACK_KNOCKBACK = 8   -- 공격 적중 시 태거 넉백 세기
local ATTACK_KNOCKBACK_ENABLED = true  -- false 로 되돌리면 예전 동작(넉백 없음)
local WALK_ANIM    = "rbxassetid://180426354"  -- R6 공식 기본 걷기 (접근 권한 문제 없음)

-- 봇별 상태 저장
local controllers = {}  -- [model] = true (이미 제어 중)

-- ── 공용 위협 레지스트리 ────────────────────────────────────
-- 왜 필요한가 (2가지 문제를 동시에 해결):
--
-- ① 인지 누락: 기존 판정은 p.AssemblyLinearVelocity 로만 속도를 봤다.
--    이 값은 물리 엔진이 굴리는 파트에만 잡히고, Anchored=true 로 두고
--    CFrame 을 직접 대입해 움직이는 연출형 아이템은 아무리 빨라도 0 이다.
--    → 쓰나미(WAVE_SPEED=60)가 완전히 미인지 상태였다. 실측 확인:
--      Anchored + CFrame 이동 = 0.00 / Anchored=false + 속도부여 = 120.00
--    → 물리속도가 0 이면 "직전 프레임 위치와의 차이 / dt" 로 실속도를 역산한다.
--
-- ② 성능: detectThreatDodge 가 봇마다 매 Heartbeat 로 workspace:GetDescendants()
--    (자손 8108개, 1회 3.33ms)를 돌았다. 봇 4마리면 프레임당 13.3ms 로
--    서버 예산 16.7ms 를 거의 다 먹는다.
--    → 스캔을 전 봇이 공유하는 1회로 합치고, 갱신도 주기적으로만 한다.
--
-- ⚠️ CollisionGroup 이 "TaggerItems" 인 파트만 대상이다. Spear/Demonspear/
--    BlackHole/EnergyBall/tnt 는 아직 CG 가 "Default" 라 여기 안 잡힌다(별도 건).
local THREAT_RESCAN_DT = 0.1   -- 전수 재스캔 주기(초). 짧을수록 신규 위협 인지가 빠르지만 비쌈
local PHYS_VEL_EPS     = 0.1   -- 이 이하면 "물리속도 없음"으로 보고 위치 역산 사용

local threatParts = {}         -- [part] = { lastPos, vel }
local threatList  = {}         -- 순회용 배열 (매 프레임 재사용)
local lastRescan  = 0

-- ⚠️ 대상 판정: CollisionGroup "TaggerItems" 이거나, BotThreat 속성이 켜진 파트.
--    후자가 필요한 이유 — Spear/Demonspear 는 CanCollide/CanQuery/CanTouch 가 전부
--    false 라 CG 를 바꿔도 물리 영향은 없지만, ItemMarkerClient 가 CG=="TaggerItems"
--    파트에 러너용 마커를 붙인다. CG 로 태그하면 "날아오는 창에 마커가 뜨는"
--    게임플레이 변경이 따라온다. 봇 인지만 원하면 BotThreat 속성으로 옵트인한다.
--    (마커까지 원하면 해당 시스템에서 CG 를 "TaggerItems" 로 바꾸면 됨)
-- 🚧 [진단 스위치 2026-08-26] 래그돌 인지 로그.
--   ⚠️ PushTool.Server 의 RAGDOLL_DIAG 와 한 세트다. 둘 다 켜야 전체 흐름이 보인다.
--   [끈 이유] 검증 완료 — 주행 루프는 항상 래그돌을 정상 인지했다.
--     한 판에 100줄 넘게 찍혀 밸런스 로그를 덮었다.
local RAGDOLL_DIAG = false

-- 🔬 [진단 2026-09-15 → 결론 2026-09-18] 회피 판정 로그. detectThreatDodge 끝에서 찍는다.
--   [무엇을 확정하려 했나] 회피 로직·배선·시간예산은 코드로 정상인데 봇이 굴리기에 계속 맞는다.
--     ① 회피 방향 쏠림  ② 회피한 쪽에 다른 위협
--   [결과 — 09-18 실측 수천 줄]
--     ① 기각. side 가 +1/−1 양쪽으로 갈린다(같은 봇도 위협에 따라 바뀜).
--     ② 거의 아니다. '동시위협 2~3' 인 줄이 흔한데도 '회피쪽위협=YES' 는 극히 드물다.
--     → 남은 후보는 둘 다 아니다. 맞는 원인은 판정 이전(속도·타이밍·경로) 쪽에 있다.
--       다시 볼 때는 회피 '시작 시각 vs 피격 시각' 을 재는 로그가 맞다 — 방향이 아니라 타이밍.
--   ⚠️ [왜 껐나] 봇 10마리 × 매 프레임이라 초당 수십 줄이 나온다. 09-18 판에서
--     로그의 95% 를 덮어 밸런스 측정이 불가능했다. 09-11 에도 같은 이유로 한 번 껐던 스위치다.
--     ⚠️ 다시 켤 때는 반드시 1~2마리로 줄이거나 샘플링을 넣을 것. 전수는 읽을 수 없다.
local DODGE_DIAG = false

local function isThreatPart(p)
    if not p:IsA("BasePart") then return false end
    return p.CollisionGroup == "TaggerItems" or p:GetAttribute("BotThreat") == true
end

-- ── 위험 영역(경고 표시) 레지스트리 ────────────────────────
-- 속도 기반 회피로는 못 막는 아이템이 있다. 실측:
--   EnergyBall : 사거리 1000을 0.6초 → 1667 stud/s. 감지반경 75를 0.045초(2.7프레임)에
--                통과해 인지해도 방향 틀 시간이 없다. 대신 경고선을 1.5초 띄운다.
--   tnt        : 수직 낙하라 수평속도 ≈ 0 → detectThreatDodge 가 nil 을 반환(무반응).
--                대신 경고 원(반경 70)이 약 7.75초 표시된다(AC130 절반비행 6.25s + 낙하 1.5s).
--   BlackHole  : 착탄 후 흡인 영역(BlackHolePullZone)은 Anchored 라 속도 0 →
--                발사체는 BotThreat 로 피하지만, 착탄 뒤 남은 흡인 범위는 못 본다.
--                범위 안에 들어가면 WalkSpeed 0 + 중심 고정이라 탈출 자체가 불가능하므로,
--                "들어가기 전에 나가는" 판단이 유일한 대응이다. 경고 원과 같은 취급.
-- → 이들은 "발사체"가 아니라 "경고 표시"를 봐야 한다. 사람 러너의 대응 창과 동일하다.
--
-- 탈출 기준은 경고 원(70)이다. 실제 즉사 반경은 75라 5스터드 더 넓지만,
-- 봇이 사람에게 안 보이는 정보를 쓰지 않게 하기 위해 의도적으로 경고 기준을 쓴다.
-- (그래서 가장자리에서 늦게 튄 봇은 사람과 똑같이 죽을 수 있다)
-- ⚠️ 이름으로 등록한다. 해당 시스템에서 파트 이름을 바꾸면 여기도 같이 고쳐야 한다.
local ZONE_CIRCLE_NAMES = { ["_BombWarning"] = true, ["BlackHolePullZone"] = true }
local ZONE_LANE_NAMES   = { ["EnergyBallWarning"] = true }
local ZONE_Y_TOLERANCE  = 50   -- 층이 다른 경고를 오인하지 않도록 수직 허용치

-- 🧊 [2026-09-15] 위험지대 진단 스위치. ⚠️ 릴리즈 전 false.
--   [왜 필요한가] 영역 탈출 경로에는 print 가 하나도 없었다. detectThreatDodge 만
--     🔬 [Dodge] 를 찍기 때문에, 지대 회피는 성공해도 실패해도 로그가 똑같이 비어 있다.
--     그래서 "폭격이 Dodge 로그에 없다 → 봇이 폭격을 인지 못 한다"로 오독한 적이 있다.
--     실제로는 폭격은 경고원(_BombWarning)으로 이 경로에서 정상 처리되고 있었다.
local ZONE_DIAG = true

local dangerZones = {}         -- { {part, kind, center, radius} ... }

local function rescanThreats()
    local seen = {}
    local zones = {}
    for _, p in ipairs(workspace:GetDescendants()) do
        if p:IsA("BasePart") then
            if isThreatPart(p) then
                seen[p] = true
                if not threatParts[p] then
                    threatParts[p] = { lastPos = p.Position, vel = p.AssemblyLinearVelocity }
                end
            end
            if ZONE_CIRCLE_NAMES[p.Name] then
                -- Cylinder: Size = (두께, 지름, 지름) → 반경 = Size.Y/2
                zones[#zones + 1] = { part = p, kind = "circle", center = p.Position, radius = p.Size.Y / 2 }
            elseif ZONE_LANE_NAMES[p.Name] then
                -- 레인 세그먼트: 로컬 X = 폭, 로컬 Z = 길이
                zones[#zones + 1] = { part = p, kind = "lane" }
            else
                -- 🧊 [2026-09-15] 속성 기반 지대 등록.
                --   [왜] 위 두 목록은 '이름'이라 새 지대가 생기면 자동으로 빠진다. 실제로
                --     프드 얼음(FrostIce_*)·배럴 웅덩이(_BarrelSpill)가 통째로 누락돼 있었고,
                --     봇이 즉사 지대를 그냥 걸어 들어갔다(실측 제보 2026-09-15).
                --     Anchored 라 속도 0 → detectThreatDodge 의 minSpeed 필터에서도 빠진다.
                --     두 경로 모두에서 안 잡히는 구조였다.
                --   [해결] 생성부에서 BotDangerZone 속성 한 줄만 켜면 여기를 안 고쳐도 된다.
                --     "이름 목록보다 속성" — GroundRayIgnore / TaggerSpawnedItem 과 같은 형태.
                --   ⚠️ 위 이름 3종은 지우지 말 것. 그쪽 생성부는 아직 속성을 안 켠다.
                --   ⚠️ circle 반경은 BotZoneRadius 를 우선 쓴다. 판정용 파트가 Cylinder 가
                --     아닐 수 있어(프드는 Block 레인) Size.Y/2 규약을 강제하지 않는다.
                local zKind = p:GetAttribute("BotDangerZone")
                if zKind == "circle" then
                    zones[#zones + 1] = { part = p, kind = "circle", center = p.Position,
                        radius = p:GetAttribute("BotZoneRadius") or (p.Size.Y / 2) }
                elseif zKind == "lane" then
                    zones[#zones + 1] = { part = p, kind = "lane" }
                end
            end
        end
    end
    for p in pairs(threatParts) do
        if not seen[p] or not p.Parent then threatParts[p] = nil end
    end
    dangerZones = zones
end

-- 매 프레임 1회만 호출(전 봇 공유). 각 위협의 유효속도를 갱신한다.
local function updateThreats(dt)
    local now = os.clock()
    if now - lastRescan >= THREAT_RESCAN_DT then
        lastRescan = now
        rescanThreats()
    end
    local n = 0
    for p, st in pairs(threatParts) do
        if p.Parent then
            local pos = p.Position
            local v = p.AssemblyLinearVelocity
            if v.Magnitude < PHYS_VEL_EPS and dt > 0 then
                -- Anchored + CFrame 구동 → 위치 차분으로 실속도 역산
                v = (pos - st.lastPos) / dt
            end
            st.lastPos = pos
            st.vel = v
            n += 1
            threatList[n] = p
        else
            threatParts[p] = nil
        end
    end
    for i = n + 1, #threatList do threatList[i] = nil end
end

-- 전 봇 공유 갱신 루프 (봇 수와 무관하게 프레임당 1회)
RunService.Heartbeat:Connect(updateThreats)

-- 🛡️ [2026-08-30] 회피 판정을 외부에 노출한다. (사용처: DecoySystem 분신)
--   [왜] 분신에도 회피가 필요했는데, detectThreatDodge 는 봇별 클로저라 밖에서 못 부른다.
--     그렇다고 로직을 복사하면 위협 판정이 두 벌이 되어 한쪽만 고쳐지는 사고가 난다.
--     반면 위협 레지스트리(threatList/threatParts)는 이미 위 Heartbeat 로 상시 갱신되므로,
--     "위치를 주면 회피 방향을 돌려주는" 얇은 함수만 열면 로직 복사 없이 재사용된다.
--   ⚠️ 봇이 한 마리도 없어도 위 갱신 루프는 돈다(모듈 수준 연결). 그래서 분신 단독으로도 동작한다.
--   반환: 회피방향(Vector3, 평면 단위벡터) 또는 nil, 그리고 위협까지 거리
--   ⚠️ 봇의 detectThreatDodge 와 달리 반응 지연·예측을 쓰지 않는다. 분신은 즉사만 피하면 되고,
--     너무 잘 피하면 오히려 "사람이 아니다"라는 단서가 된다(과하게 똑똑하면 위장이 깨진다).
function _G.getItemDodgeVector(pos, radius, minSpeed, approach)
    radius   = radius   or 55
    minSpeed = minSpeed or 12
    approach = approach or 0.15
    local best, bestDist = nil, nil
    for _, p in ipairs(threatList) do
        local st = threatParts[p]
        if st and p.Parent then
            local vel = st.vel
            if vel.Magnitude >= minSpeed then
                local off  = pos - p.Position
                local dist = off.Magnitude
                if dist < radius and (not bestDist or dist < bestDist) then
                    local toTarget = (dist > 0.01) and off.Unit or Vector3.zero
                    if vel.Unit:Dot(toTarget) >= approach then
                        -- 진행 방향의 수직(좌/우) 중 현재 더 벌어져 있는 쪽으로 비킨다
                        local v = Vector3.new(vel.X, 0, vel.Z)
                        if v.Magnitude > 0.01 then
                            v = v.Unit
                            local left = Vector3.new(-v.Z, 0, v.X)
                            local rel  = Vector3.new(pos.X - p.Position.X, 0, pos.Z - p.Position.Z)
                            best     = left * ((rel:Dot(left) >= 0) and 1 or -1)
                            bestDist = dist
                        end
                    end
                end
            end
        end
    end
    return best, bestDist
end


-- ── 출발 게이트 ─────────────────────────────────────────
-- /start 채팅 입력 전까지 봇은 스폰 자리에서 대기. /start 시 일제히 출발.
local Players = game:GetService("Players")
local started = false

-- 다른 스크립트(/all 등)에서 출발/정지를 부를 수 있도록 노출
_G.startRunnerBots = function()
    if not started then
        started = true
        print("🚦 [RunnerBotDrive] 출발! (외부 호출)")
    end
end
_G.stopRunnerBots = function()
    started = false
    print("🛑 [RunnerBotDrive] 대기 상태로 (외부 호출)")
end

local function onChat(msg)
    local m = msg:lower():gsub("%s+", "")
    if m == "/start" then
        if not started then
            started = true
            print("🚦 [RunnerBotDrive] /start 입력 → 봇 출발!")
        end
    elseif m == "/stop" then
        started = false
        print("🛑 [RunnerBotDrive] /stop 입력 → 봇 대기 상태로")
    end
end

local isDev = require(game:GetService("ServerScriptService"):WaitForChild("DevAuth")).isDev
local function hookChat(p)
    p.Chatted:Connect(function(msg) if isDev(p) then onChat(msg) end end)   -- 🔒 개발자 전용
end
Players.PlayerAdded:Connect(hookChat)
for _, p in ipairs(Players:GetPlayers()) do hookChat(p) end

-- 현재 맵 우선으로 taggerspawn 계열 파트 탐색
local function findTaggerSpawnIn(root)
    if not root then return nil end
    for _, m in ipairs(root:GetDescendants()) do
        if m:IsA("BasePart") and m.Name:lower():match("^taggerspawn") then
            return m
        end
    end
    return nil
end

local function getGoalPart()
    -- 길찾기 목표 파트: 현재 맵의 taggerspawn(성 윗면 평지). 맵마다 위치가 다름.
    return findTaggerSpawnIn(currentMapFolder) or findTaggerSpawnIn(workspace) or workspace:FindFirstChild("taggerbase")
end

-- 맵 확정 시 목표(GOAL_POS)/시작기준(START_BASE)을 현재 맵 좌표로 갱신.
--   핵심 수정: 이 값들이 map1에 고정돼 있어 AI가 map2에서도 map1으로 달려갔음.
local function refreshMapTargets(mapFolder)
    if not mapFolder then return end
    currentMapFolder = mapFolder
    local goal = findTaggerSpawnIn(mapFolder)
    if goal then GOAL_POS = goal.Position end
    for _, m in ipairs(mapFolder:GetDescendants()) do
        if m:IsA("BasePart") and m.Name:lower():match("^playerspawn") then
            START_BASE = m.Position
            break
        end
    end
    -- 🎲 [2026-09-04] 라운드 목적 추첨. 판마다 봇 전원의 목표가 통째로 바뀐다.
    --   [왜] 봇이 항상 점령만 노려서 킹이 매 판 같은 것만 상대했다. 판별 양상이 없다.
    --   [왜 여기인가] refreshMapTargets 는 맵 활성화(라운드 시작)마다 정확히 한 번 불린다.
    --     라운드 중에는 안 바뀌므로 "왜 갑자기 목표가 변했지"가 생기지 않는다.
    --   ⚠️ kill 판은 봇이 불리하다. 실측 — 전원 킹 추격이 16.7 DPS, 825 HP 를 49초.
    --     2단계 창(98~112초) 안에 이론상 가능하지만 킹이 잡기 시작하면 DPS 가 계속 떨어진다.
    --     '봇이 이기기 어려운 판'이 섞이는 건 의도한 것이다 — 판별 난이도 리듬이 목적이다.
    --   ⚠️ 유저가 섞인 판에도 적용된다. 봇이 킹을 물고 늘어지면 유저가 존을 밀 여지가 생긴다.
    --   🎲 [2026-09-10] 위 두 ⚠️ 는 KILL_ROUND_CHANCE=0 이 된 지금은 실행되지 않는
    --     경로의 설명이다. 확률을 되살릴 때를 위해 남긴다(원복 근거는 상수 주석 참조).
    --   [문서정정 2026-09-10] 이 헤더 주석이 두 번 복사돼 있었다. 아래 한 벌로 합친다.
    --   [테스트 강제] _G.ForceBotObjective 가 있으면 추첨 대신 그 값을 쓴다.
    --     TestCommands 의 /botmode 가 세운다. nil 이면 평소대로 확률 추첨.
    --   ⚠️ 강제값은 라운드를 넘어 유지된다. 측정을 마치면 /botmode random 으로 풀 것 —
    --     안 풀면 다음 세션까지 한쪽 판만 나와서 "왜 킬 판이 안 뜨지"로 헤맨다.
    local forced = _G.ForceBotObjective
    if forced == "kill" or forced == "capture" then
        roundObjective = forced
    else
        roundObjective = (math.random() < KILL_ROUND_CHANCE) and "kill" or "capture"
    end
    print(string.format("🎲 [RunnerBotDrive] 이번 라운드 봇 목적: %s%s",
        roundObjective == "kill" and "태거 처치 (점령 안 함)" or "점령",
        forced and "  ⚙️ (/botmode 강제)" or ""))

    print(string.format("[RunnerBotDrive] 맵 목표 갱신: %s GOAL=(%.0f,%.0f,%.0f) START=(%.0f,%.0f,%.0f)",
        mapFolder.Name, GOAL_POS.X, GOAL_POS.Y, GOAL_POS.Z, START_BASE.X, START_BASE.Y, START_BASE.Z))
end

-- ⛓️ [2026-09-05] 왕좌가 무너지면 점령은 끝났다 — 봇을 킹에게 돌린다.
--   [증상] 점령이 승리에서 디버프로 바뀐 뒤, 봇들이 이미 사라진 점령지에
--     계속 서 있었다. 목적이 라운드 시작에 한 번만 정해지기 때문이다.
--   [왜 여기인가] roundObjective 는 이 파일의 지역 변수라 밖에서 못 건드린다.
--     변수를 노출하는 대신 "킬로 전환"이라는 좁은 동작만 API 로 연다.
--   ⚠️ 되돌리지 않는다. 라운드 시작(refreshMapTargets)에서 어차피 다시 추첨하므로
--     다음 판에 영향이 없다.
_G.RunnerBotsGoKill = function()
    if roundObjective == "kill" then return end
    roundObjective = "kill"
    print("🎲 [RunnerBotDrive] 왕좌 붕괴 → 봇 목적 전환: 태거 처치")
end

local setMapEvent = ReplicatedStorage:FindFirstChild("SetCurrentMap")
if setMapEvent then
    setMapEvent.Event:Connect(refreshMapTargets)
end

-- NPC walk 애니메이션 (서버 재생)
local function setupAnim(bot, hum)
    local la = bot:FindFirstChild("Animate")
    if la and la:IsA("LocalScript") then la.Enabled = false end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator"); animator.Parent = hum
    end
    local anim = Instance.new("Animation")
    anim.AnimationId = WALK_ANIM
    local ok, track = pcall(function()
        return animator:LoadAnimation(anim)
    end)
    if not ok or not track then
        warn("⚠️ [RunnerBotDrive] 걷기 애니 로드 실패:", bot.Name, tostring(track))
        return nil
    end
    track.Looped = true
    track.Priority = Enum.AnimationPriority.Movement
    print("🎞️ [RunnerBotDrive] 걷기 애니 로드 성공:", bot.Name)

    -- 🗡️ [연출 2026-09-04] 공격 애니를 같이 로드해 캐시한다.
    --   [왜] 기존 swingPose 는 어깨 25도 + 무기 1stud 를 0.25초 움직이는 게 전부라
    --     "언제 때렸는지 모르겠다"는 체감이 나왔다. 실제 스윙 모션으로 바꾼다.
    --   [왜 여기서 캐시] LoadAnimation 을 타격마다 부르면 봇 10마리 × 1.6초 주기로
    --     계속 새 트랙이 생긴다. 봇당 1회 호출되는 여기서 만들어 재사용한다.
    --   ⚠️ 실패해도 조용히 넘어간다 — swingPose 가 옛 포즈로 폴백하므로 공격은 계속 된다.
    --     애니 에셋 의존이 새로 생기는 것이라 폴백을 반드시 남긴다.
    local aok, atrack = pcall(function()
        local a = Instance.new("Animation")
        a.AnimationId = ATTACK_ANIM
        return animator:LoadAnimation(a)
    end)
    if aok and atrack then
        atrack.Priority = Enum.AnimationPriority.Action
        attackTracks[bot] = atrack
        -- 🔬 [진단] Length 가 0 이면 에셋이 비었거나 리그가 안 맞는 것이다.
        --   [왜 필요] 1차 시도(522635514)는 로드가 '성공'했는데도 모션이 안 나왔다.
        --     경고가 없어서 실패를 못 잡았다 — 로드 성공은 재생 가능을 뜻하지 않는다.
        --   ⚠️ Length 는 에셋 로드 직후 0 으로 나올 수 있다(09-01 문서: 캐시가 0 키프레임을
        --     에러 없이 반환). 그래서 0.7초 뒤에 잰다.
        task.delay(0.8, function()
            if attackTracks[bot] then
                print(string.format("🎞️ [RunnerBotDrive] 공격 애니 %s | 길이=%.2fs %s",
                    bot.Name, atrack.Length,
                    atrack.Length <= 0 and "← ⚠️ 0초! 모션이 안 나온다" or ""))
            end
        end)
    else
        warn("⚠️ [RunnerBotDrive] 공격 애니 로드 실패(포즈로 폴백):", bot.Name, tostring(atrack))
    end
    return track
end

-- ── 근접 공격 (라운드 AI 전용) ───────────────────────────
-- 현재 태거(Role=Tagger 플레이어)의 캐릭터를 반환. 없으면 nil.
local function findTaggerChar()
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl:GetAttribute("Role") == "Tagger" and pl.Character then
            local h = pl.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                return pl.Character, h
            end
        end
    end
    -- 봇 태거(KING) 폴백: 유저 태거가 없으면 workspace의 KING 모델을 태거로 인식.
    -- (1인 러너 모드: 농민이 성까지 뚫으면 KING을 공격 — 전선이 살아있는 그림.
    --  유저 러너가 있는 한 attackTagger의 HP 하한 25%가 그대로 적용돼 막타는 유저 몫.)
    local king = workspace:FindFirstChild("KING")
    if king and king:GetAttribute("Role") == "Tagger" then
        local h = king:FindFirstChildOfClass("Humanoid")
        if h and h.Health > 0 then
            return king, h
        end
    end
    return nil
end

-- 갈퀴 찌르기 포즈: 어깨를 25도 들면서 무기(Grip)를 앞으로 1stud 내밀었다 원위치.
-- 무기 길이축(로컬Y)이 정면이라 Grip을 -Y로 밀면 앞으로 찌름. 애니 에셋 의존 없음.
local function swingPose(bot)
    -- 🗡️ [2026-09-04] 캐시된 공격 애니가 있으면 그걸 쓴다.
    --   아래 수동 포즈는 애니 로드가 실패했을 때만 도는 폴백이다.
    local at = attackTracks[bot]
    if at then
        at:Stop(0)          -- 연타 시 이전 재생을 끊고 처음부터 (반쯤 재생된 상태 방지)
        at:Play(0.05)
        return
    end
    local torso = bot:FindFirstChild("Torso")
    local shoulder = torso and torso:FindFirstChild("Right Shoulder")
    local tool = bot:FindFirstChildOfClass("Tool")
    task.spawn(function()
        local origShoulder = shoulder and shoulder.C0
        local origGrip = tool and tool.Grip
        -- 내밀기
        if shoulder then shoulder.C0 = origShoulder * CFrame.Angles(0, 0, math.rad(25)) end
        if tool and origGrip then tool.Grip = origGrip * CFrame.new(0, -1, 0) end
        task.wait(0.25)
        -- 원위치
        if shoulder then shoulder.C0 = origShoulder end
        if tool and origGrip then tool.Grip = origGrip end
    end)
end

-- 🪓 [연출 2026-09-04] 스윙 모션을 밖에서도 쓸 수 있게 노출한다.
--   [왜] 봇은 바리케이드를 '공격'하지 않는다. 밀착해 있으면 BarricadeSystem 의
--     겹침 검사가 알아서 깎는 구조라 swingPose 가 안 불렸고, 그래서 성문을 부수는
--     동안 봇이 가만히 서 있는 것처럼 보였다("바리케이드 칠 땐 애니가 안 나온다").
--   [규칙] 연출만 넘긴다. 데미지·쿨다운은 BarricadeSystem 이 그대로 소유한다 —
--     스윙 재생이 타격 판정에 관여하면 같은 규칙이 두 곳에 생긴다.
--   ⚠️ 이 함수는 애니 트랙이 없으면 수동 포즈로 폴백한다. 호출부는 신경 안 써도 된다.
_G.playBotSwing = function(bot)
    if bot and bot.Parent then swingPose(bot) end
end

-- 태거 공격: 데미지(HP 하한 클램프) + 넉백. 데미지가 하한에 막혀도 넉백은 항상 적용.
-- → 냅둬도 안 죽지만 계속 밀려서 귀찮은 "농민 군중" 압박. creator는 AI 태깅(러너 승리 제외).
-- 유저 러너 수 (0명 = 1인 태거 모드: 유저가 태거, 상대는 AI뿐)
local function countUserRunners()
    local n = 0
    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
        if p:GetAttribute("Role") == "Runner" then n += 1 end
    end
    return n
end
-- 농민 딜은 유저 러너 수에 반비례 스케일 (너프안):
-- 다수의 러너가 있으면 농민이 이미 유리 → 개별 농민 딜을 낮춰,
-- "옆에서 지켜보다 막타만" 하는 소극 플레이를 억제하고 유저 개입 필요성을 높인다.
-- 1명: 100% / 2명: 65% / 3명: 50% / 4명+: 40% (곱연산으로 부드럽게 감쇠)
-- 🗡️ [③ 2026-09-12] 히어로봇은 간이 판정 대신 '진짜 무기'를 휘두른다.
--
-- [선례] 봇 킹이 PushTool 을 그대로 구동한다(PushTool.Server 의 botChargeTrack 분기).
--   근거 주석: "서버가 봇의 네트워크 소유자라 지속 제어가 먹는다".
--   러너봇도 서버 소유이므로 같은 방식이 성립한다.
--
-- [왜 Tool.Activated 를 못 쓰나] Activated 는 Player 의 클릭으로만 발동한다.
--   봇은 Player 가 없으므로 서버가 그 자리를 대신 채워야 한다 →
--   무기 스크립트가 Activated 핸들러에 붙여둔 동작을 직접 일으킨다.
--
-- [방식] Tool 을 Activate() 로 깨운다. Roblox 의 Tool:Activate() 는
--   Player 없이도 Activated 시그널을 발동시킨다 — 무기 스크립트를 한 줄도 안 고쳐도 된다.
--   ⚠️ Tool.Enabled 가 false 면 무시된다. 그게 곧 무기 자체의 쿨다운이라
--     여기서 따로 쿨을 세지 않는다(두 벌이 되면 밸런스가 어긋난다).
--
-- ⚠️ 데미지는 무기가 낸다. 아래 attackTagger 의 간이 판정(scaledAttackDamage)을
--   같이 태우면 이중 타격이 된다 — 히어로는 그 경로를 건너뛴다.
-- ⚠️ 무기 판정은 Handle.Touched 다(DragonFireSword:318). 봇이 킹에게 실제로
--   닿아야 들어간다 — 접촉 거리는 기존 추격 로직이 이미 맞춰놨다.
-- 📏 [2026-09-18] 히어로 무기의 실제 리치. "유저가 맞힐 수 있는 거리"를 봇에게도 준다.
--   [왜 필요한가] ATTACK_RANGE 6 은 농민의 거리 판정용 값이다. 무기는 Handle.Touched 라
--     물리적으로 닿아야 하는데, 실측 리치는 전부 6 에 못 미친다 —
--       SakuraBlade 4.4 / DragonFire 4.0 / ClassicSword 3.5 / HammerLow 3.3
--       KatanaSword2 0.6 / HammerHigh 1.0   ← 손잡이만 Handle 이다
--     그래서 봇은 6 에서 휘두르고 칼은 4.4 까지만 가는 헛스윙을 반복했다.
--     유저는 칼이 닿을 때까지 붙어서 휘두른다. 그 행동을 거리로 옮긴 값이다.
--   [계산] Grip 오프셋(손에서 Handle 중심까지) + Handle 최장변의 절반.
--     ⚠️ Grip 은 Tool 의 속성이라 무기를 쥔 자세가 이미 반영돼 있다.
--   [여유 1.5] 킹의 몸 두께와 봇의 어깨너비. 둘 다 HRP 기준 거리라 표면끼리는 그만큼 가깝다.
--     ⚠️ KingScale 로 킹이 커지면 실제로는 더 유리해진다 — 여유를 더 키우지 않는다.
--   [캐시] 무기 인스턴스에 속성으로 붙인다. 복제본마다 1회만 계산되고 무기와 함께 사라진다.
--   ⚠️ 리치가 짧아 못 닿는 무기(카타나·해머하이)는 여기서 억지로 늘리지 않는다.
--     그건 무기 쪽 문제고, 히어로 딜 0 이 그 사실을 드러내는 신호다.
local function heroReach(tool)
    local cached = tool:GetAttribute("_BotReach")
    if cached then return cached end
    local h = tool:FindFirstChild("Handle")
    local r = ATTACK_RANGE
    if h and h:IsA("BasePart") then
        local longest = math.max(h.Size.X, h.Size.Y, h.Size.Z)
        r = tool.Grip.Position.Magnitude + longest / 2 + 1.5
    end
    tool:SetAttribute("_BotReach", r)
    return r
end

-- 🤝 [2026-09-18] 봇 부활 — "유저는 하는데 봇은 못 하는 것" 목록의 마지막 항목.
--   [왜] 지금까지 다운된 봇은 10초 뒤 확정 사망이었다. 유저는 서로 살리는데 봇은 못 해서,
--     솔로모드 측정값에 부활이 구조적으로 빠져 있었다 — 러너 전력을 계속 낮게 재고 있었다.
--   [설계] ReviveSystem 을 그대로 쓴다. 홀드 1.5초·반경 10·판당 1회 제한·거리 이탈 취소가
--     전부 유저와 같은 경로다. 봇에게 더 쉬운 규칙을 주지 않는다.
--   ⚠️ [상태를 불리언으로 두지 않는다] 전부 타임스탬프다. 봇이 부활 도중 죽거나 다운돼도
--     시각은 저절로 만료된다 — "끄는 코드에 도달이 보장되는가" 를 아예 물을 필요가 없게 만든다.
local BOT_REVIVE         = true  -- 🔌 마스터 스위치. 문제가 보이면 이 한 줄로 끈다
local REVIVE_SEEK_RADIUS = 35    -- 이 안의 다운자만 도우러 간다. 존을 너무 오래 비우지 않는 선
local REVIVE_START_DIST  = 8     -- 시작 거리. ⚠️ **3D 거리**다 — 아래 주석 참조
-- ⚠️ [버그 수정 2026-09-18] 이 값은 반드시 3D 로 재야 한다.
--   [무엇이 틀렸나] 처음엔 XZ 평면 거리로 쟀다. 그런데 ReviveSystem.validateRevive 는
--     (reviverRoot.Position - targetRoot.Position).Magnitude 즉 **3D** 로 REVIVE_DISTANCE(10)
--     를 본다. 평면 8 과 3D 10 을 비교해놓고 "여유를 뒀다"고 적어둔 게 오류였다.
--   [증상] 맵 높이가 121~137 로 출렁여서, 경사·계단에선 XZ 8 이어도 3D 가 12~14 가 된다.
--     봇은 "도착했다"고 판단해 매 프레임 부활을 부르고 시스템은 매번 거절한다 —
--     실측 로그: `부활 시작 거절: 거리 초과 (12m) (x12)` / `(14m) (x11)`.
--     성공률이 떨어지고 봇이 포기 타이머(7초)까지 그 자리에 묶인다.
--   ⚠️ 접근 '방향'은 여전히 XZ 다(날 수 없으므로). 판정만 3D.
--   ⚠️ 8 < 10 이므로 시작 직후 미세한 움직임으로 취소되지 않는다 — 원래 의도한 여유가
--     이제 실제로 성립한다.
local REVIVE_CLAIM_TTL   = 7     -- 한 명이 한 대상을 붙드는 최대 시간 + 포기 타이머
local REVIVE_BLOCK       = 6     -- 포기한 봇이 다시 시도하기까지
-- 👑 킹 거리 가드 — 실측에서 역산한 값이다(2026-09-18).
--   [킹의 도달거리] 강타 기본 12 × sMult 최대 1.75(9킬) = 21.0. 관측 최대 19.9(×1.66).
--     평타는 8 × 1.75 = 14.0. 강타 폭은 최대 17.5.
--   [왜 '무위험'을 못 만드나] 홀드가 1.5초인데 킹 이속이 14 라 그 사이 21 stud 를 좁힌다.
--     완전 안전은 21(도달) + 21(이동) = 42 인데, 그건 2단계 교전 구역 전체다 —
--     그 값을 쓰면 부활이 아예 성립하지 않는다.
--   [그래서] 가드의 목적은 무위험이 아니라 '명백히 자살인 시도'만 막는 것이다.
--     킹이 접근하면 대부분 중간에 취소된다. 그건 올바른 결과다 — 유저도 같은 계산을 한다.
--   ⚠️ 거리는 '봇이 서 있게 될 자리'(=다운자 위치) 기준으로 잰다. 봇 현재 위치가 아니다.
--     접근하는 동안 안전해 봐야 도착지가 사지면 의미가 없다.
local REVIVE_KING_START  = 28    -- 다운자가 킹에게서 이보다 가까우면 아예 안 간다 (강타 21 + 여유 7)
local REVIVE_KING_CANCEL = 20    -- 부활 중 킹이 이보다 가까워지면 즉시 포기 (강타 도달 안쪽)
-- 🤝 동시 부활 상한 — 대상별 선점만으로는 부족하다.
--   [증상] 선점은 '한 대상에 한 명'만 막는다. 통나무 한 방에 3명이 다운되면
--     서로 다른 대상이라 봇 3명이 동시에 멈춘다. 전열이 통째로 서는 그림이다.
--   [왜 2인가] 10체 기준 20%. 실전에서도 한 명이 빼서 살리고 나머지는 목표를 계속한다 —
--     전원이 몰려가지 않는다. 그 형태를 숫자로 옮긴 값이다.
--   ⚠️ 생존자 수에 비례시키지 않았다(예: 4명당 1명). 그게 더 맞을 수 있지만
--     지금은 근거가 없다 — 로그를 보고 정한다. 오늘 여섯 개를 한꺼번에 추측하지 않는다.
--   ⚠️ 슬롯은 만료 시각이다. 봇이 부활 도중 죽거나 취소해도 0.5초 안에 저절로 빠진다 —
--     해제 코드에 도달하지 못해 슬롯이 영구 점유되는 경로를 아예 없앤다.
-- 🔻 [밸런스 2026-09-20] 2 → 1.
--   [왜] 라이브 1단계 처치가 0/11 이었다(로드아웃 = 굴리기 3종, 바닥 구성).
--     이 값은 **단일 다운에는 영향이 0** 이고 다중 다운의 회수 속도만 반으로 만든다 —
--     광역으로 여러 명 눕히는 플레이(굴리기·쓰나미)에만 보상이 간다.
--     뉴비 킹이 들고 나오는 게 정확히 그 로드아웃이라 '바닥만 올리는' 축이다.
--     스피어로 한 명씩 잡는 숙련 플레이는 손해가 없다 = 격차를 안 벌린다.
--   [효과 예상] 3명 동시 다운 기준 회수 약 4초 → 약 6초. 1명 다운은 그대로.
--   ⚠️ [기준선이 없는 상태로 넣는다] 1단계 부활이 판당 몇 건인지 아직 측정된 적이 없다.
--     효과를 읽으려면 RoundSummary 의 🎯 [1단계] 줄에 부활 카운트가 붙어야 한다.
--     그 전까지는 처치 수 변화만 보게 되는데, 편차가 커서 2~4판으로는 판별이 안 된다
--     (09-18 GLOBAL_COOLDOWN 에서 같은 실수를 했다 — 승률이 처치 수보다 빨리 신호를 준다).
--   ⚠️ 위 [왜 2인가] 의 "생존자 수 비례가 더 맞을 수 있다"는 미결은 그대로 남는다.
--     고정 1 은 11명 판에서 9%, 4명 판에서 25% 라 소규모 판에 더 세게 먹는다.
--   🔴 [되돌릴 값] 2.
local REVIVE_MAX_CONCURRENT = 1
local REVIVE_SLOT_TTL       = 0.5
-- 🔥 불벽 여유. 불벽 X 보다 이만큼 앞이어야 구하러 간다.
--   [왜 필요한가] 불벽은 속도 10 으로 전진한다. 홀드 2초 동안 20 stud 를 좁히고,
--     접근 시간까지 더하면 "지금은 안전한 자리"가 도착할 때쯤 불 속이 된다.
--   [START 25] 홀드 2초분 20 + 여유 5. 접근 시간은 매 틱 재검사가 잡는다(아래 CANCEL).
--     ⚠️ 이 값은 ReviveSystem.REVIVE_DURATION 에 묶여 있다 — 불벽 속도 10 × 홀드 시간.
--       홀드 1.5 일 때 20, 2 일 때 25. 홀드를 바꾸면 여기도 같이 고친다.
--       (2026-09-18 홀드 1.5 → 2 에 맞춰 20 → 25)
--   [CANCEL 8] 진행 중에 벽이 여기까지 오면 즉시 놓고 도망친다. 살리다 둘 다 죽지 않는다.
--   ⚠️ 불벽이 없거나(1단계 전·라운드 종료) 갱신이 끊기면 이 판정은 통째로 건너뛴다 —
--     _G.FireLine 의 at 시각으로 만료를 본다. 값이 낡았는데 믿는 게 더 위험하다.
local REVIVE_FIRE_START  = 25
local REVIVE_FIRE_CANCEL = 8
local REVIVE_FIRE_STALE  = 1.0   -- 이 시간 넘게 갱신이 없으면 불벽 정보 무시

local reviveSlots = {}   -- [botName] = 만료시각

-- 🗡️ [2026-09-19] 점령이 성립 중이면 여유 인원이 킹을 사냥한다.
--   [문제] 봇은 존으로만 간다. 킹이 존 밖에 서 있으면 평생 접촉이 없어
--     "태거가 시비 걸지 않으면 봇이 먼저 안 싸운다"가 됐다(사용자 제보).
--     실측: 2단계 내내 킹은 존에서 27~56 stud 떨어져 있었다
--     (`📈 [Capture] 킹 없음 (거리 27/33/39/42/56)`).
--     그 결과 2단계 타수가 무기 쿨 한계의 7% 뿐이었다 — 병목은 딜이 아니라 근접 시간이다.
--
--   [왜 공짜인가 — 실측 2026-09-19, CaptureSystem 코드 확인]
--     ① 킹이 존에 없으면 상승은 FILL_RATE 1.0 **고정**이다. 인원과 무관하다.
--        (CaptureSystem 주석: "킹 없는 존은 bestRate 규칙상 항상 1.0")
--     ② 감쇠(DECAY_RATE)는 **존이 완전히 비었을 때만** 작동한다.
--        (같은 파일: "떠나도 잃지 않지만, 킹에게 붙잡히면 잃는다")
--     → 존당 1명만 남기면 나머지가 나가도 게이지에 **아무 손해가 없다**.
--     ⚠️ 이 두 전제 중 하나라도 바뀌면 이 기능의 근거가 무너진다. CaptureSystem 의
--       FILL_RATE / DECAY 분기를 고칠 때 여기도 같이 볼 것.
--
--   [왜 킹이 가까우면 복귀인가] 킹이 존에 오면 rate 가 인원 비례로 바뀐다
--     (실측 표: 1명 50초 / 5명 18초). 그때는 머릿수가 곧 방어라 비우면 손해다.
--
--   [왜 prog > 0 조건인가] "점령이 성립 중일 때만" 나간다. 라운드 초반 전원이
--     존으로 걸어가는 중에 흩어지면 아무도 존을 못 밟는다. 게이지가 실제로
--     오른 뒤에야 여유 인원이 생긴 것으로 본다.
--
--   [왜 슬롯 방식인가] reviveSlots 와 같은 형태다(선례를 따른다). 봇마다 독립적으로
--     판단하는데 전역 카운터가 없으면 "다 같이 나가거나 다 같이 남는" 진동이 난다.
--     보유자가 스스로 갱신하므로 한 번 지킴이가 된 봇은 계속 지킴이다 — 깜빡임이 없다.
--     TTL 이 있어 지킴이가 죽으면 슬롯이 풀리고, 다음 틱에 사냥꾼 하나가 복귀한다(자가 치유).
--
--   ⚠️ 히어로·농민을 **구분하지 않는다**. 킹 HP 공식(Stage2TriggerSystem)이 둘을
--     같은 0.55 로 세고 있어, 농민이 안 싸우면 공식과 현실이 어긋난다.
--   ⚠️ [농민 위험] 농민은 내구도가 없고(RoundSystem: giveDurability = isHero)
--     쿨도 1.6s 라 히어로(0.5s)의 1/3 이다. 킹 강타 한 방에 3명이 다운된 실측이 있다.
--     사망이 급증하면 HUNT_HERO_ONLY = true 로 좁힐 것.
--   ⚠️ 되돌리려면 HUNT_ENABLED = false.
local HUNT_ENABLED     = true
local HUNT_HERO_ONLY   = true   -- 히어로만 사냥(농민은 존에 남는다)
-- 🛡️ [2026-09-19] 농민 제외로 시작한다. 위 "농민 위험" 경고를 먼저 회피한다.
--   [왜] 농민은 내구도 0 · 쿨 1.6s 라 킹에게 보내면 소모될 위험이 크다.
--     한 번에 두 축(히어로 사냥 + 농민 사냥)을 넣으면 근접 시간이 늘어난 게
--     누구 덕인지, 사망이 는 게 누구 탓인지 못 가른다 — 09-18 에 쿨·홀드를
--     같이 넣어 겪은 문제와 같은 형태다.
--   [순서] ① 히어로만으로 근접 시간·킹 피해가 오르는지 본다
--          ② 효과가 확인되면 false 로 바꿔 농민을 넣고, 사망 건수를 본다
--   ⚠️ [이 값이 무의미해지는 조건] heroQuota = max(0, min(4 - 유저러너수, 봇수)) 다.
--     **유저 러너가 4명 이상이면 히어로가 0** 이라 이 기능이 통째로 안 돈다.
--     즉 지금 설정은 봇전·소수 유저 판에서만 효과가 있다. 유저 5~6명 판
--     (원래 문제 제기 시나리오)에서는 false 로 바꿔야 작동한다.
local ZONE_KEEPERS     = 1      -- 존마다 남길 봇 수. 킹이 없으면 1명이나 5명이나 같은 속도다
local HUNT_KING_DIST   = 30     -- 킹이 존에서 이 안이면 전원 복귀(경합 = 머릿수 싸움)
local KEEPER_TTL       = 1.0    -- 슬롯 만료. 지킴이가 죽으면 이 시간 뒤 풀린다
local zoneKeepers = {}   -- [zoneName] = { [botName] = 만료시각 }

-- 지킴이 슬롯을 잡는다. true = 존으로 간다 / false = 여유 인원이라 사냥한다.
--   ⚠️ 이미 보유 중이면 갱신하고 true. 그래서 한 번 지킴이가 된 봇은 계속 지킴이다.
local function claimKeeperSlot(zone, botName)
    local now = os.clock()
    local t = zoneKeepers[zone.Name]
    if not t then t = {}; zoneKeepers[zone.Name] = t end
    if t[botName] then t[botName] = now + KEEPER_TTL; return true end
    local n = 0
    for name, exp in pairs(t) do
        if exp <= now then t[name] = nil else n = n + 1 end
    end
    if n < ZONE_KEEPERS then t[botName] = now + KEEPER_TTL; return true end
    return false
end

local function reviveSlotCount(now)
    local n = 0
    for name, until_ in pairs(reviveSlots) do
        if until_ > now then n = n + 1 else reviveSlots[name] = nil end
    end
    return n
end

local _reviveMod = nil
local function reviveSystem()
    if _reviveMod == nil then
        -- ⚠️ 지연 require. 부팅 순서에 의존하지 않는다(ReviveBoot 가 이미 올려둔다).
        local ok, m = pcall(function()
            return require(game:GetService("ServerScriptService"):WaitForChild("ReviveSystem", 5))
        end)
        _reviveMod = (ok and type(m) == "table") and m or false
    end
    return _reviveMod or nil
end

-- 가까운 다운자 중 '아직 아무도 안 맡았고, 서 있어도 되는 자리'의 대상.
--   ⚠️ 위험 판정은 다운자 기준이다 — 봇이 결국 그 자리에 1.5초 서게 되므로.
--     여기서 걸러도 아래 reviveStep 이 매 틱 다시 본다(가는 도중에 상황이 바뀌므로).
--     이건 헛걸음을 줄이는 1차 필터다.
local function findReviveTarget(bot, root, kingPos, fireX, posInDanger)
    local best, bestD = nil, REVIVE_SEEK_RADIUS
    local now = os.clock()
    for _, c in ipairs(workspace:GetChildren()) do
        if c ~= bot and c:IsA("Model")
           and c:GetAttribute("Downed") and not c:GetAttribute("UsedRevive") then
            -- 선점 확인 — 남이 맡았고 아직 유효하면 건너뛴다(떼로 몰려가는 것 방지).
            local by = c:GetAttribute("_RvClaimBy")
            local at = c:GetAttribute("_RvClaimAt") or 0
            if not (by and by ~= bot.Name and (now - at) < REVIVE_CLAIM_TTL) then
                local r = c:FindFirstChild("HumanoidRootPart")
                if r then
                    local p = r.Position
                    local bad =
                        (kingPos and (p - kingPos).Magnitude < REVIVE_KING_START)
                        or (fireX and p.X < fireX + REVIVE_FIRE_START)
                        or (posInDanger and posInDanger(p))
                    if not bad then
                        local d = (p - root.Position).Magnitude
                        if d < bestD then best, bestD = c, d end
                    end
                end
            end
        end
    end
    return best, bestD
end

-- 반환: "hold"(제자리) | 방향 Vector3(접근) | nil(부활 안 함 → 기존 로직으로)
--   posInDanger(pos): 그 좌표가 위험 지대(빙판·웅덩이 등) 안인가. 호출자가 넘긴다.
local function reviveStep(bot, root, posInDanger)
    if not BOT_REVIVE then return nil end
    local RS = reviveSystem()
    if not RS or not RS.beginReviveByCharacter then return nil end
    local now = os.clock()

    -- 🔥 불벽 X. 갱신이 끊겼으면(만료) 없는 것으로 본다.
    local fireX
    do
        local fl = _G.FireLine
        if type(fl) == "table" and fl.at and (now - fl.at) <= REVIVE_FIRE_STALE then
            fireX = fl.x
        end
    end

    -- 킹 위치 (없으면 가드 없이 진행 — 1단계 등)
    local kChar = findTaggerChar()
    local kRoot = kChar and (kChar:FindFirstChild("HumanoidRootPart") or kChar:FindFirstChild("Torso"))
    local kingPos = kRoot and kRoot.Position or nil

    -- 이미 살리는 중 — 킹이나 불벽이 들어오면 즉시 포기, 아니면 제자리.
    --   ⚠️ 부활 중엔 회피가 꺼져 있다(이 함수가 틱을 조기 종료한다). 스스로 놓지 않으면
    --     제자리에 선 채로 맞는다 — 유저라면 E 를 떼고 도망칠 자리다.
    if RS.isReviving(bot) then
        local bail =
            (kingPos and (root.Position - kingPos).Magnitude < REVIVE_KING_CANCEL)
            or (fireX and root.Position.X < fireX + REVIVE_FIRE_CANCEL)
        if bail then
            RS.cancelByReviver(bot)
            reviveSlots[bot.Name] = nil
            bot:SetAttribute("_RvGiveUpAt", 0)
            bot:SetAttribute("_RvTargetName", "")
            bot:SetAttribute("_RvBlockUntil", now + REVIVE_BLOCK)
            return nil   -- 회피·이동 로직으로 즉시 복귀
        end
        reviveSlots[bot.Name] = now + REVIVE_SLOT_TTL   -- 점유 갱신
        bot:SetAttribute("_RvGiveUpAt", 0)
        return "hold"
    end

    -- 포기 타이머 만료 → 잠시 쉰다. 도달 못 하는 대상에 영원히 매달리지 않게.
    local giveUp = bot:GetAttribute("_RvGiveUpAt") or 0
    if giveUp > 0 and now > giveUp then
        reviveSlots[bot.Name] = nil
        bot:SetAttribute("_RvGiveUpAt", 0)
        bot:SetAttribute("_RvTargetName", "")
        bot:SetAttribute("_RvBlockUntil", now + REVIVE_BLOCK)
        return nil
    end
    if (bot:GetAttribute("_RvBlockUntil") or 0) > now then return nil end

    -- ⚠️ [비용] 이 함수는 봇 10체 × 매 프레임 돈다. workspace 전수 검색을 매 틱 돌리면
    --   초당 600회가 된다. 이미 대상이 있으면 이름으로 O(1) 조회하고, 없을 때만
    --   0.35초 간격으로 검색한다.
    local target
    local tname = bot:GetAttribute("_RvTargetName")
    if tname and tname ~= "" then
        local c = workspace:FindFirstChild(tname)
        if c and c:GetAttribute("Downed") and not c:GetAttribute("UsedRevive") then
            target = c
        else
            bot:SetAttribute("_RvTargetName", "")   -- 살아났거나 죽었다
            bot:SetAttribute("_RvGiveUpAt", 0)
        end
    end
    if not target then
        if (bot:GetAttribute("_RvScanAt") or 0) + 0.35 > now then return nil end
        bot:SetAttribute("_RvScanAt", now)
        target = findReviveTarget(bot, root, kingPos, fireX, posInDanger)
        if not target then
            bot:SetAttribute("_RvGiveUpAt", 0)
            return nil
        end
        bot:SetAttribute("_RvTargetName", target.Name)
    end

    local tr = target:FindFirstChild("HumanoidRootPart")
    if not tr then bot:SetAttribute("_RvTargetName", "") return nil end

    -- 가는 도중에 상황이 바뀌었으면 포기한다. 선택 시점 한 번만 보면 안 된다.
    --   ① 킹이 그 자리로 왔다  ② 불벽이 그 자리를 삼킬 참이다  ③ 그 자리가 위험 지대다
    --   ⚠️ ②③ 이 이번 추가분이다. 킹만 보던 탓에 불벽 뒤로 구하러 들어가 같이 죽었다.
    --     "무엇을 맞았나"가 아니라 "그 자리에 1.5초 서 있어도 되나"로 판정한다.
    local badSpot =
        (kingPos and (tr.Position - kingPos).Magnitude < REVIVE_KING_START)
        or (fireX and tr.Position.X < fireX + REVIVE_FIRE_START)
        or (posInDanger and posInDanger(tr.Position))
    if badSpot then
        reviveSlots[bot.Name] = nil
        bot:SetAttribute("_RvTargetName", "")
        bot:SetAttribute("_RvGiveUpAt", 0)
        return nil
    end

    -- 🤝 동시 부활 상한. 이미 슬롯을 쥔 봇(접근 중)은 계속 진행하고,
    --   새로 들어오려는 봇만 막는다 — 가다가 중간에 쫓겨나면 왕복만 하게 된다.
    if (reviveSlots[bot.Name] or 0) <= now
       and reviveSlotCount(now) >= REVIVE_MAX_CONCURRENT then
        bot:SetAttribute("_RvTargetName", "")
        bot:SetAttribute("_RvGiveUpAt", 0)
        return nil   -- 이번엔 남에게 맡기고 자기 목적을 계속한다
    end
    reviveSlots[bot.Name] = now + REVIVE_SLOT_TTL

    target:SetAttribute("_RvClaimBy", bot.Name)
    target:SetAttribute("_RvClaimAt", now)
    if giveUp == 0 then bot:SetAttribute("_RvGiveUpAt", now + REVIVE_CLAIM_TTL) end

    -- ⚠️ 판정은 3D, 이동은 XZ. 섞으면 높이차에서 어긋난다(REVIVE_START_DIST 주석 참조).
    local d3 = (tr.Position - root.Position).Magnitude
    local d = Vector3.new(tr.Position.X - root.Position.X, 0, tr.Position.Z - root.Position.Z)
    if d3 <= REVIVE_START_DIST then
        -- 🎯 [2026-09-18] 고른 대상을 그대로 넘긴다. 안 넘기면 ReviveSystem 이
        --   '제일 가까운 다운자'를 다시 골라, 위에서 한 킹·불벽·지대 검사가 무의미해진다.
        if RS.beginReviveByCharacter(bot, target) then return "hold" end
        return nil   -- 거절당했으면(이미 진행 중 등) 기존 로직으로 돌아간다
    end
    -- 바로 위/아래라 더 못 다가가는데 3D 가 여전히 멀다 = 높이로 끊긴 자리. 즉시 포기한다.
    --   ⚠️ 이게 없으면 포기 타이머(7초)까지 제자리에서 시간을 버린다.
    if d.Magnitude < 1.0 then
        reviveSlots[bot.Name] = nil
        bot:SetAttribute("_RvTargetName", "")
        bot:SetAttribute("_RvGiveUpAt", 0)
        bot:SetAttribute("_RvBlockUntil", now + REVIVE_BLOCK)
        return nil
    end
    return d.Unit
end

local function swingHeroWeapon(bot)
    local tool = bot:FindFirstChildOfClass("Tool")
    if not tool then return false end

    -- 🌀 [③ 2026-09-12] 스킬이 있는 무기면 먼저 시도한다.
    --   [규약] 무기 스크립트가 Tool 에 BindableFunction "BotSkill" 을 걸어둔다.
    --     있으면 스킬 무기, 없으면 평타 전용(DragonFireSword·SakuraBlade 등).
    --     ⚠️ 이름을 무기마다 다르게 두면(BotSpin/BotLunge/...) 여기에 분기가 쌓인다.
    --       하나로 통일해 무기가 늘어도 이 파일은 안 고치게 한다.
    --   [판단] 봇은 "쓸 수 있으면 쓴다". 쿨다운·중복은 무기가 알아서 막는다 —
    --     같은 규칙을 두 곳에 두지 않는다.
    --   ⚠️ [알려진 한계 2026-09-12] 봇 행동이 "붙어서 때린다" 하나뿐이라,
    --     거리 운영이 필요한 효과는 발동해도 이득이 없다
    --     (ClassicSword 사거리 증강 / HammerHigh 도약). 데미지는 들어가므로 쓰긴 쓴다.
    --     근본 해결은 '거리 기반 스킬 선택'이고 별도 과제다 — 인계 문서 3-9 참조.
    -- 🚪 [2026-09-13] 성문 붕괴 전에는 히어로봇 스킬을 일괄 금지한다. **봇 한정 — 유저는 제외.**
    --   [증상] 성문이 멀쩡한데 슬램이 성문 너머 킹에게 닿아 죽였다
    --     (실측 23:37:50 성문 6칸 남음 → 52 스턴 → 54 킹 사망).
    --   [왜 봇만 막나] 원인이 위 [판단] "쓸 수 있으면 쓴다"에 있다. 봇은 성문 너머에
    --     태거가 있어도 사거리만 맞으면 무조건 건다. 유저는 성문을 보고 스스로 안 쓰거나,
    --     곡사포·마법책 회피 같은 응용으로 쓴다 — 그 판단의 여지를 뺏지 않는다.
    --     ⚠️ 태거 쪽 봉인(Stage2TriggerSystem:325)과 근거가 다르다. 그쪽은 '무기를 받는
    --       시점 자체가 성문 붕괴'라 결투 수단이 없는 국면이고, 러너는 2단계 진입에
    --       이미 무기를 받는다. 대칭 규칙으로 읽어 유저까지 막지 말 것.
    --   ⚠️ 평타는 막지 않는다. 아래 tool:Activate() 로 그대로 떨어져 성문을 계속 때린다.
    --   [신호] TaggerHpReady — finalizeTaggerHp(성문 붕괴)에서만 true, 라운드 리셋 두 곳에서
    --     false. ReplicatedStorage 속성이라 이미 복제된다. 새 플래그를 만들지 않았다
    --     (TaggerBotSystem.enterDuelMode 가 쓰는 것과 같은 신호다).
    --   ⚠️ 무기별로 넣지 않는다. 여기가 봇 스킬의 유일한 진입점이라 한 곳이면 6종이 다 덮인다.
    --     무기가 늘어도 이 파일만 유지하면 된다 — BotSkill 규약을 둔 이유와 같다.
    local skillsUnlocked = game:GetService("ReplicatedStorage"):GetAttribute("TaggerHpReady") == true
    local skill = tool:FindFirstChild("BotSkill")
    if skillsUnlocked and skill and skill:IsA("BindableFunction") then
        local ok, used = pcall(function() return skill:Invoke() end)
        if ok and used then return true end
    end

    -- 🔴 [버그수정 2026-09-18] 쿨 중이면 **false**. 예전엔 true 였다.
    --   [증상] 히어로봇이 2단계에서 눈에 띄게 굼뜨다(사용자 제보 09-18).
    --   [실측] 같은 무기 구성 두 판을 분해하니 —
    --       타격 빈도는 인원에 선형(1인당 0.134 vs 0.126 타/초)인데 타당 피해가 갈렸다.
    --       농민 20.0 / 히어로 약 10  →  히어로가 7.7초에 한 대. 농민은 1.6초에 한 대.
    --     즉 무기를 든 쪽이 맨손보다 약했다. 설계 전제의 정반대다.
    --   [원인] 여기서 true 를 돌려주면 attackTagger 가 즉시 return 해서
    --     간이 판정(scaledAttackDamage)까지 건너뛴다. 스킬도 평타도 안 나가는
    --     완전 무딜 사이클이 생긴다 — 약 4.8회 중 4회가 그랬다.
    --   [무엇이 틀렸나] 옛 주석은 "'무기를 쓴다'는 사실은 참"이라 적었는데,
    --     이 반환값의 의미는 **"이번 틱에 딜이 나갔는가"** 다. 봇의 종류가 아니다.
    --     호출부가 그 뜻으로 쓰고 있다(true → 평타 스킵).
    --   [결과] 쿨 중에는 false → 농민과 같은 평타 20 으로 떨어진다.
    --     "히어로 ≥ 농민" 이 비로소 성립한다.
    --   ⚠️ 이중 타격은 안 생긴다. tool.Enabled == false 는 무기가 데미지를 못 내는
    --     상태라, 평타와 겹칠 무기 판정 자체가 없다.
    --   ⚠️ 이 수정으로 히어로 전력이 오른다. 09-18 이전의 DPS·HP 측정값은
    --     전부 이 버그가 낀 조건이다 — 가중치 작업은 재측정 뒤에 할 것.
    -- 🗡️ [2026-09-18 재수정] 무기를 든 히어로는 쿨 중이어도 **true** — 평타로 안 떨어진다.
    --   ⚠️ 같은 날 아침에 이걸 false 로 바꿨다가 되돌린다. 그때 근거는 "쿨 중엔 딜이 0이니
    --     평타라도 줘야 한다"였는데, 그건 유저에게 없는 규칙을 봇에게만 주는 것이었다.
    --   [원칙] 평타(scaledAttackDamage)는 **봇 전용 발명품**이다. 유저 러너가 킹을 때리는
    --     경로는 무기 Touched 하나뿐이고, attackTagger 는 이 파일 안에만 있다.
    --     · 농민 — 유저 대응물이 없다(무기가 없는 군중). 평타 말고 표현 수단이 없으니 맞다.
    --     · 히어로 — 대응물이 있다. 같은 무기를 든 유저 러너다. 그러니 무기로만 평가한다.
    --       평타를 얹으면 "봇만 가진 보너스"가 되어 밸런스 측정이 통째로 거짓이 된다.
    --   [부수 이득] 히어로봇이 유저 무기의 검증 장치가 된다. 리치가 짧아 안 닿는 무기는
    --     히어로 딜이 0 으로 드러나고, 그건 곧 "유저도 0" 이라는 신호다.
    --     평타 폴백은 그 신호를 20 으로 덮어버린다.
    --   ⚠️ 무기가 없으면(1단계) 위에서 이미 false 로 빠져 농민과 같은 평타를 쓴다 — 의도된 동작.
    if not tool.Enabled then return true end   -- 쿨 중 = 유저도 딜 없음. 평타로 보상하지 않는다
    local ok = pcall(function() tool:Activate() end)
    return ok
end

local function scaledAttackDamage()
    local n = countUserRunners()
    -- 👑 [밸런스 2026-09-04] 태거 솔로모드(유저 러너 0명) 전용 딜 강화.
    --   [왜] 실측 — 봇 10마리가 전부 킹에게 붙어도 11.8 DPS. 825 HP 기준 70초라
    --     2단계 창(98~112초)을 못 채운다. 타격감을 붙인 뒤에도(넉백 14·화면 흔들림·
    --     볼륨 1.0) "위기가 안 느껴진다"가 그대로였다 = 피드백이 아니라 출력 문제다.
    --   [목표] 30~40초에 승부. 필요 DPS 20~27 → 배율 2.0~2.3 구간.
    --     2.5 로 시작한다(예상 29.5 DPS / 28초). 과하면 2.0 으로 내린다.
    --   ⚠️ 유저가 섞인 판은 한 글자도 안 바뀐다. n == 0 만 새로 분기하고 아래 기존 식은
    --     그대로 둔다 — "유저 판에서 봇이 주인공이 되면 안 된다"는 원칙.
    --   ⚠️ 솔로에서는 ATTACK_HP_FLOOR_RATIO 하한도 함께 해제된다(attackTagger 의
    --     countUserRunners() == 0 분기). 즉 봇이 실제로 킹을 죽일 수 있다 — 의도한 것이다.
    if n == 0 then return ATTACK_DAMAGE * SOLO_DAMAGE_MULT end
    if n <= 1 then return ATTACK_DAMAGE end
    local mult = ({ [2] = 0.65, [3] = 0.5 })[n] or 0.4
    return ATTACK_DAMAGE * mult
end


-- 농민봇 평타 사운드.
-- BarricadeSystem 의 벽 타격음과 동일한 2종을 랜덤 재생한다.
-- (벽 칠 때만 소리가 나면 "왜 태거를 때릴 땐 조용하지?"가 되어 어색하다.
--  같은 갈퀴로 치는 것이므로 소리도 같아야 일관된다)
local BOT_HIT_SOUNDS = {
    "rbxassetid://138453047962067",
    "rbxassetid://127860004094478",
}
local BOT_HIT_VOLUME = 1.0      -- 🔊 [타격감 2026-09-04] 0.6 → 1.0.
                                --   벽(0.7)보다 작게 잡았던 근거가 "태거 피격은 다른 피드백도
                                --   겹친다" 였는데, 실제로는 넉백이 꺼져 있어 소리가 유일한
                                --   피드백이었다. 전제가 틀렸으므로 올린다.
local BOT_HIT_RANGE  = 90

local function playBotHitSound(position)
    local anchor = Instance.new("Part")
    anchor.Name = "_BotHitSfx"
    anchor.Size = Vector3.new(1, 1, 1)
    anchor.Position = position
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Parent = workspace

    local s = Instance.new("Sound")
    s.SoundId = BOT_HIT_SOUNDS[math.random(1, #BOT_HIT_SOUNDS)]
    s.Volume = BOT_HIT_VOLUME
    s.RollOffMaxDistance = BOT_HIT_RANGE
    s.RollOffMode = Enum.RollOffMode.InverseTapered
    s.Parent = anchor
    s:Play()
    game:GetService("Debris"):AddItem(anchor, 4)
end

-- 앞에 바리케이드가 있는지. 끼임 점프를 억제하는 데 쓴다.
-- (봇이 벽을 "공격"할 필요는 없다 — 밀착해 있으면 BarricadeSystem 의 겹침 검사가 깎는다)
local BARRICADE_PROBE = 5   -- 전방 감지 거리(stud)

local function isBarricadeAhead(root)
    if not root then return false end
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = { root.Parent }
    local dir = root.CFrame.LookVector
    local hit = workspace:Raycast(root.Position, Vector3.new(dir.X, 0, dir.Z).Unit * BARRICADE_PROBE, rp)
    if hit and hit.Instance.Parent and hit.Instance.Parent.Name == "Barricades" then
        return true
    end
    return false
end

-- 📳 [타격감 2026-09-04] 봇 피격 화면 흔들림 설정. attackTagger 가 쓴다.
--   [규격] HammerShakeClient 의 (intensity, duration). 기준선 — 잽 1.3/0.18,
--     망치 슬램 2.2/0.5, 강타 피격자 1.2~2.4. 봇은 가장 약한 잽보다 아래로 잡는다.
--   ⚠️ 봇은 10마리라 개별 강도보다 '빈도'가 체감을 지배한다. 세게 하지 말고
--     스로틀로 리듬을 만드는 쪽이 맞다.
local lastBotShakeAt    = 0
local BOT_SHAKE_MIN_GAP = 0.45   -- 이 간격보다 자주는 안 흔든다
local BOT_SHAKE_POWER   = 0.9
local BOT_SHAKE_TIME    = 0.16

local function attackTagger(bot, taggerHum)
    -- ⚠️ 얼음(Ice 킬이펙트)에 갇힌 봇은 공격할 수 없다.
    --   KillEffectSystem 의 빙결은 WalkSpeed/JumpPower 만 0 으로 만들어 "이동"만 막는다.
    --   그래서 얼음 속 봇이 태거를 계속 때리는 상황이 나왔다(실측 제보).
    if bot:GetAttribute("IceFrozen") then return end

    -- 🗡️ [③ 2026-09-12] 히어로봇은 무기가 데미지를 낸다 — 간이 판정을 건너뛴다.
    --   ⚠️ 둘 다 태우면 이중 타격이다. 무기 판정(Handle.Touched)과
    --     아래 scaledAttackDamage 가 같은 접촉에서 동시에 들어간다.
    --   ⚠️ 넉백·사운드·화면흔들림도 건너뛴다. 그건 '농민 군중' 연출이고,
    --     히어로는 무기 자체의 연출(불꽃·스윙음)을 쓴다.
    --   [실패 시] 무기가 없거나 Activate 가 실패하면 false → 기존 경로로 떨어진다.
    --   ⚠️ [2026-09-12] 1단계에는 히어로도 무기가 없다(2단계 진입 시 지급으로 바뀜).
    --     그동안은 이 분기가 false 로 떨어져 농민과 같은 간이 판정을 쓴다 — 의도한 동작이다.
    --     유저 러너도 1단계엔 맨손이므로 같은 조건이다.
    if bot:GetAttribute("HeroRunner") and swingHeroWeapon(bot) then
        return
    end

    -- 🛑 [2026-09-18] 평타 폴백 전용 쿨. 히어로가 0.5초마다 여기 도달하기 때문에 반드시 필요하다.
    --   [없으면] 무기 쿨 중인 히어로가 0.5초마다 평타 20 → 40 DPS.
    --     농민(1.6초당 20 = 12.5 DPS)의 3.2배가 되어 히어로 4명이 킹을 2.6초에 녹인다.
    --   [규칙] 평타는 농민과 완전히 같은 리듬(ATTACK_COOLDOWN)을 쓴다. 무기를 들었다고
    --     '맨손 공격'이 빨라질 이유는 없다. 빨라지는 건 무기 스윙뿐이다.
    --   [왜 속성인가] lastAttack 은 봇마다의 주행 루프 지역변수라 이 함수에서 못 본다.
    --     속성은 봇 인스턴스에 붙어 캐릭터가 사라지면 같이 사라진다 — 누수가 없다.
    --     "이름 목록보다 속성" 원칙과 같은 형태다.
    --   ⚠️ 농민은 애초에 1.6초마다 들어오므로 이 게이트에 걸리지 않는다. 동작 불변.
    local nowBasic = os.clock()
    if nowBasic - (bot:GetAttribute("_LastBasicAtk") or 0) < ATTACK_COOLDOWN then return end
    bot:SetAttribute("_LastBasicAtk", nowBasic)

    local floor = taggerHum.MaxHealth * ATTACK_HP_FLOOR_RATIO
    -- 🎯 1인 태거 모드(유저 러너 0명): 막타를 맡을 유저가 없으므로 하한 해제 → AI가 태거를 죽일 수 있음.
    --    (긴장감: 무조건 승리 보장 제거. 멀티에선 기존대로 하한 유지 = 막타는 유저 몫)
    if countUserRunners() == 0 then
        floor = 0
    end
    -- 데미지: 하한 위일 때만 깎음 (하한이면 데미지 0, 넉백만)
    if taggerHum.Health > floor then
        local newHealth = math.max(taggerHum.Health - scaledAttackDamage(), floor)
        -- creator 태그 (AI 모델). RoundSystem 태거 사망 핸들러가 이 태그로 AI 막타 식별.
        local existing = taggerHum:FindFirstChild("creator")
        if existing then existing:Destroy() end
        local creator = Instance.new("ObjectValue")
        creator.Name = "creator"
        creator.Value = bot
        creator.Parent = taggerHum
        game:GetService("Debris"):AddItem(creator, 2)
        -- ☠️ [2026-08-29] 하한이 0(솔로 러너 판)이면 TakeDamage 로 죽인다.
        --   [증상] 태거봇 HP 가 0 인데도 죽지 않고, 유저가 한 대 더 쳐야 사망했다
        --     (실측 19:13 판: "킹 피격 -22 → 0/907" 이 반복).
        --   [원인] Health 직접 대입은 0 이 되어도 Died 를 확실히 발동시키지 못한다.
        --     게다가 다음 타격에서 위 `Health > floor` 가 0 > 0 = false 라
        --     데미지 자체가 안 들어가 영원히 0 에서 멈췄다.
        --   ⚠️ 하한이 있는 판(멀티)에서는 기존처럼 대입이 맞다. 그 경우 절대 죽으면 안 되고,
        --     TakeDamage 를 쓰면 하한을 넘어 죽을 수 있다.
        if newHealth <= 0 then
            taggerHum:TakeDamage(taggerHum.Health)
        else
            taggerHum.Health = newHealth
        end
    end

    -- 넉백: 항상 적용 (데미지 0이어도). AI → 태거 방향으로 짧게 밀기.
    local botRoot = bot:FindFirstChild("HumanoidRootPart") or bot:FindFirstChild("Torso")
    local tRoot = taggerHum.Parent and (taggerHum.Parent:FindFirstChild("HumanoidRootPart")
        or taggerHum.Parent:FindFirstChild("Torso"))

    -- 평타 사운드: 피격 지점(태거 위치)에서 재생. 데미지 하한이라 0딜이어도 소리는 난다
    -- (때리는 동작은 똑같으므로 소리가 없으면 오히려 어색하다)
    if tRoot then
        playBotHitSound(tRoot.Position)
    elseif botRoot then
        playBotHitSound(botRoot.Position)
    end

    -- 📳 [타격감 2026-09-04] 킹 화면 흔들림.
    --   [왜] 봇 공격이 HP 숫자만 깎아서 "맞고 있다"는 감각이 전혀 없었다.
    --     넉백이 꺼져 있던 동안 피드백이 소리 하나뿐이라 지속딜 장판처럼 느껴졌다.
    --   ⚠️ 유저 킹에만 보낸다. 봇 킹은 Player 인스턴스가 아니라 FireClient 가 터진다
    --     (09-01 문서: FireClient 호출 시 Player 가드 필요).
    --   ⚠️ 스로틀 필수. 봇이 최대 10마리라 매 타격마다 흔들면 화면이 쉬지 않고 요동쳐
    --     조준이 불가능해진다. PushTool 도 같은 이유로 "기본 슬랩은 안 흔든다".
    do
        local ch = taggerHum.Parent
        local plr = ch and Players:GetPlayerFromCharacter(ch)
        if plr and (os.clock() - lastBotShakeAt) >= BOT_SHAKE_MIN_GAP then
            lastBotShakeAt = os.clock()
            local ev = game:GetService("ReplicatedStorage"):FindFirstChild("HammerShakeEvent")
            if ev then
                pcall(function() ev:FireClient(plr, BOT_SHAKE_POWER, BOT_SHAKE_TIME) end)
            end
        end
    end

    -- AI 러너의 공격 넉백은 기본 비활성.
    --   AI 는 매 라운드 10체라 넉백이 누적되어 KING 이 태거베이스 뒤로 몰렸고,
    --   그러면 슬랩으로 러너를 계단 쪽으로 밀어낼 수 없어 일방적으로 다굴당했다.
    --   AI 가 미는 건 플레이어의 의사결정이 아니므로 게임적 의미가 없다.
    --   데미지·타격음·쿨다운은 그대로 유지된다 — 넉백만 뺀다.
    --   ⚠️ ATTACK_KNOCKBACK(28) 은 TaggerBotSystem 의 KB_THRESH(40) 보다 작아
    --     봇의 슈퍼아머가 애초에 이 넉백을 감지조차 못 했다. 저항값으로는 막을 수 없었음.
    if ATTACK_KNOCKBACK_ENABLED and botRoot and tRoot then
        local dir = (tRoot.Position - botRoot.Position)
        dir = Vector3.new(dir.X, 0, dir.Z)  -- 수평 방향만 (위로 안 띄움)
        if dir.Magnitude > 0.1 then
            dir = dir.Unit
            -- 짧게 적용되고 사라지는 임펄스 (LinearVelocity + Debris)
            local att = tRoot:FindFirstChild("KnockAtt") or Instance.new("Attachment")
            att.Name = "KnockAtt"
            att.Parent = tRoot
            -- 🐛 [버그수정 2026-09-05] LinearVelocity 를 매번 새로 만들지 않고 재사용한다.
            --   [증상] 킹이 벽 쪽으로 쭉 밀려나 박힌 채 못 움직였다(실측 11:39 판:
            --     거리=62 고정 / 속도 1.2→0.0 / 상태=Freefall 지속).
            --   [원인] Attachment 는 FindFirstChild 로 재사용하면서 LinearVelocity 는
            --     매번 Instance.new 였다. 봇 10마리가 각자 만들고 수명이 0.18초라
            --     여러 개가 동시에 붙는다. MaxForce 가 질량×10000 인데 10개가 겹치면
            --     실질 10배가 되어 벽으로 처박고, 지면 판정을 잃어 Freefall 로 굳는다.
            --   ⚠️ 수직 성분은 이미 제거했는데도 Freefall 이 났다 — 뜬 게 아니라
            --     '벽에 밀착해 바닥 레이가 빗나간' 것이다. 원인이 다르므로 따로 고친다.
            --   [규칙] 대상당 하나만 존재한다. 새 넉백은 기존 것의 값을 덮어쓴다.
            --     LinearVelocity 는 속도를 '설정'하는 것이라 겹칠 이유가 없다.
            local lv = tRoot:FindFirstChild("_BotKnockLV")
            if not lv then
                lv = Instance.new("LinearVelocity")
                lv.Name = "_BotKnockLV"
                lv.Attachment0 = att
                lv.RelativeTo = Enum.ActuatorRelativeTo.World
                lv.Parent = tRoot
            end
            -- ★ 무한 힘 금지: 대상이 벽·지형에 밀착한 상태에서 math.huge 를 쓰면
            --   물리 솔버가 무한 힘 vs 무한 반력으로 발산(numerical explosion)한다.
            --   실측 사고: 태거 몸 전체 속도 20003 → 다음 프레임 좌표 (-38919, 150121, -41549)
            --   → 스트리밍 범위 밖으로 튕겨 "Gameplay Paused" 까지 발생.
            --   GauntletScript:417 이 같은 이유로 이미 질량비례 유한값을 쓰고 있다 — 동일 패턴 적용.
            --   가속도 10000 이면 어떤 질량이든 0.01초 내 목표 속도 도달(체감 동일).
            lv.MaxForce = math.max(tRoot.AssemblyMass, 1) * 10000
            -- 🐛 [버그수정 2026-09-11] Vector 모드 → Line 모드. "킹이 하늘로 솟구침"의 2차 재발.
            --   [이력] 09-04 에 하드코딩 +6 을 지웠는데, 그 자리에 '현재 Y 를 스냅샷해서 같이
            --     넣는' 코드가 들어가 같은 증상이 다른 형태로 돌아왔다. 지웠던 코드:
            --         lv.VectorVelocity = dir * ATTACK_KNOCKBACK
            --             + Vector3.new(0, tRoot.AssemblyLinearVelocity.Y, 0)
            --   [원인] Vector 모드의 LinearVelocity 는 Y 를 '그대로 두는' 게 아니라 목표값으로
            --     계속 구동한다. MaxForce 가 질량×10000 이라 중력이 감속시키지 못한다.
            --       ① 킹이 살짝 뜬다(점프 · 봇 더미 이탈) → Y = +30
            --       ② 그 순간 타격 → Y 목표가 +30 으로 박힌다. 중력이 못 깎는다
            --       ③ 0.18초 안에 다음 타격 → 여전히 +30 인 값을 다시 스냅샷
            --       ④ botKnockToken 이 이전 해제를 무효화 → ②로 되돌아간다
            --     봇 7~9마리면 타격 간격이 0.18초보다 촘촘해 등속 상승이 무한히 유지된다.
            --     타격이 끊기는 순간 떨어진다 = "잠시 솟구쳤다"의 정체.
            --   [09-04 원문 보존] 그때의 진단도 형태가 같았다 —
            --     "+6 은 언제나 같은 방향이라 누적만 된다. 10마리가 0.18초 수명을 번갈아
            --      갱신하면 계속 떠 있게 된다."  상수를 지우고 래치를 넣은 셈이었다.
            --   [지금] Line 모드는 지정한 축 하나만 구속하고 나머지는 물리에 맡긴다.
            --     Y 를 아예 쓰지 않으므로 래치가 구조적으로 불가능하다 — 값을 잘 고르는 게
            --     아니라 손댈 수 없게 만드는 쪽이다(09-01 "제외 목록보다 결과 보장").
            --   ⭐ 부수 효과: Vector 모드는 속도 벡터 '전체'를 덮어써서, 다굴당하는 동안 킹의
            --     이동 입력이 0.18초마다 지워지고 있었다(왕좌 붕괴 후 속도 12 가 무의미했다).
            --     Line 모드는 dir 축만 건드리므로 횡이동이 살아난다.
            --     ⚠️ 그래서 넉백이 약해졌다고 느낄 수 있다. 값이 준 게 아니라 버그가 빠진
            --       것이다 — 그래도 약하면 ATTACK_KNOCKBACK(8) 을 올려서 조정할 문제다.
            --   ⚠️ dir 은 위에서 이미 수평화 + 정규화된 값이다. 여기서 다시 만들지 않는다.
            --   ⚠️ 모드를 매 타격마다 세우는 이유: lv 는 재사용 인스턴스라, 예전 Vector 모드로
            --     만들어진 게 남아 있어도 여기서 반드시 Line 으로 덮인다.
            lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
            lv.LineDirection = dir
            lv.LineVelocity  = ATTACK_KNOCKBACK
            lv.Enabled = true
            -- ⚠️ Destroy 가 아니라 Enabled=false 로 끈다. 재사용 인스턴스라 파괴하면
            --   다음 타격이 또 새로 만들고, 그 사이 짧은 창에서 중복이 생긴다.
            --   ⚠️ 토큰으로 '가장 최근 타격만' 끄게 한다 — 0.18초 안에 다음 타격이
            --     오면 그게 새 토큰을 세우므로, 먼저 예약된 해제가 새 넉백을 끄지 않는다.
            --     (09-01: "상태를 끄는 코드에는 켜는 코드를 같은 편집에 함께 넣을 것")
            botKnockToken += 1
            local myToken = botKnockToken
            task.delay(0.18, function()
                if myToken ~= botKnockToken then return end
                if lv and lv.Parent then lv.Enabled = false end
            end)
        end
    end
    return true
end

-- 단일 봇 제어 (독립 코루틴)
local function driveBot(bot)
    if controllers[bot] then return end
    controllers[bot] = true

    local hum = bot:WaitForChild("Humanoid", 5)
    if not hum then warn("[RunnerBotDrive] Humanoid 없음(5s 타임아웃):", bot.Name) controllers[bot] = nil return end
    local root = bot:FindFirstChild("HumanoidRootPart") or bot:FindFirstChild("Torso")
    if not root then warn("[RunnerBotDrive] HRP 없음:", bot.Name) controllers[bot] = nil return end

    -- 라운드 편입 AI 여부 (RoundSystem이 AIRunner 속성으로 스폰).
    -- true  → 라운드 모드: /start 게이트 없이 즉시 출발, 죽으면 리스폰 안 함(승패 분리).
    -- false → 테스트 모드(기존): /start 대기 + 도착/사망 시 무한 리스폰.
    local isRoundAI = bot:GetAttribute("AIRunner") == true

    -- 봇별 레인/개성
    local idx = bot:GetAttribute("BotIndex") or 1
    -- 시작점: 테스트 봇은 고정 START_BASE, 라운드 AI는 스폰된 현재 위치
    local startPos = isRoundAI and root.Position or (START_BASE + Vector3.new(0, 0, (idx - 2.5) * LANE_GAP))
    local laneZ = GOAL_POS.Z + (idx - 2.5) * 2  -- 목표 지점도 살짝 분산(군집 느낌)

    -- ── 회피 등급 ──────────────────────────────────────
    -- 봇 3,4 = 고급(엘리트): 더 멀리 감지·예측 회피·빠른 발·더 큰 측면 회피.
    -- 봇 1,2 = 일반.
    -- (요청: 1,2에도 엘리트 회피 적용 → 전 봇 엘리트)
    local elite = true
    local cfg = {
        -- ⚠️ [2026-09-15] 엘리트 75 → 90.
        --   ⚠️ elite 가 항상 true 라 **DODGE_RADIUS 는 읽히지 않는 죽은 값**이다.
        --     실제 감지 반경은 늘 이쪽이었다 — 상수만 고치면 아무 일도 안 일어난다.
        --     (2026-09-15 에 DODGE_RADIUS 를 90 으로 고쳤다가 이 사실을 발견했다)
        --   [근거] 통나무 접근속도 실측 63 stud/s, 폭 30 → 필요 이탈 16, 봇 속도 17,
        --     지연 0.35s. 75 면 이동 가능 14.3 으로 1.7 모자라 아슬아슬하게 맞았다.
        --     90 이면 18.3 — 여유 2.3.
        --   ⚠️ 이 값은 "봇은 사람이 볼 수 있는 만큼만 본다"는 기존 선을 넘는다. 의도적이다 —
        --     봇에게는 Q 대시가 없다. 사람도 순수 이속으로는 못 피하지만 대시로 빠져나간다.
        --     그 비대칭을 인지거리로 보정한다. **봇에게 대시를 주면 75 로 되돌릴 것.**
        radius   = elite and 90  or DODGE_RADIUS,    -- 감지 반경 (측면·후방)
        -- 🔭 전방(주행 목표 방향 ±60도) 전용 반경.
        --   [근거] 사람 러너는 ItemMarkerClient 로 태거 아이템을 **거리 제한 없이** 본다
        --     (높이 45 기둥, MaxDistance 없음). 전방에 한해 90 은 사람보다 한참 좁았다.
        --   [값] 150 = 통나무 접근속도 63 기준 착탄까지 2.4초. 보수적으로 시작하고
        --     처치 수를 보며 올린다(250 이면 4.0초).
        --   ⚠️ 측면·후방까지 넓히지 않는다 — 거긴 사람이 아예 못 보는 구간이다.
        radiusFwd = elite and 150 or DODGE_RADIUS,
        minSpeed = elite and 8   or DODGE_MIN_SPEED, -- 위협 최소 속도
        approach = elite and 0.0 or DODGE_APPROACH,  -- 접근 임계(0=옆에서 와도 반응)
        lateral  = elite and 3.2 or DODGE_LATERAL,   -- 측면 강도
        near     = elite and 32  or DODGE_NEAR,      -- 긴급 거리
        predict  = elite,                            -- 예측 회피(아이템 도달지점 선점)
        -- ── 위험 영역 탈출 (난이도 손잡이) ──
        -- zoneDelay  : 영역 안에 들어온 걸 인지하고 실제로 튀기까지의 지연(초).
        --              0이면 즉시 = 초인적. 값이 클수록 가장자리 봇이 못 빠져나감.
        -- zoneAware  : 이 영역을 아예 인지할 확률(영역당 1회 추첨).
        -- 지금은 전 봇 동일값. 추후 난이도 티어를 넣으면 이 둘이 그대로 등급 파라미터가 된다.
        -- ("현재 농민봇 수준 = 노말" 기준으로 잡음 — 더 어렵게/쉽게는 이 값으로 조정)
        zoneDelay = 0.25,
        zoneAware = 1.0,
        -- ── 일반 회피 반응 지연 (난이도 손잡이) ──
        -- ⚠️ 봇은 위협 레지스트리에서 위치·속도를 직접 읽으므로 "발사 즉시" 인지한다.
        --    사람은 창을 눈으로 보고 반응하는 데 최소 0.2~0.3초가 걸린다.
        --    지연이 0이면 봇이 사람보다 유리해져 "에임핵처럼 잘 피한다"는 체감이 나온다(실측).
        --    스피어 기준: 75스터드에서 인지 = 0.71초 여유인데 옆으로 2.6스터드만 비키면
        --    회피 성공이라, 지연이 없으면 사실상 100% 회피한다.
        --    개체마다 조금씩 달라야 무리 전체가 한 몸처럼 움직이지 않는다.
        reactDelay = 0.18 + math.random() * 0.14,   -- 0.18~0.32초
    }
    local baseSpeed = elite and 17 or WALK_SPEED      -- 엘리트는 더 빠른 발
    -- ⚠️ [밸런스 2026-08-29] 20 → 17. 실제 범위 18~22 → 15~19.
    --   [증상] 농민봇이 유저보다 눈에 띄게 빨랐다.
    --   [원인] 유저 기본 WalkSpeed 가 16 인데 봇은 평균 20 으로 +25% 였다.
    --     게다가 봇은 최적 경로로 직진하고 카메라 조작·지형 걸림이 없어
    --     '실효' 속도는 표기보다 더 벌어진다.
    --   [17 인 이유] 유저 기본(16)보다 살짝 빠른 정도. 무리가 몰려오는 압박감은 남기되
    --     "따라잡을 수 없다"는 체감은 없앤다.
    --     ⚠️ 유저에게는 Q대시가 있어 순간 이동거리를 벌 수 있다. 표기 속도를
    --       완전히 같게(16) 맞추면 오히려 유저가 유리해진다.
    --   ⚠️ elite 는 현재 하드코딩 true 다(위 515행). WALK_SPEED 16 은 죽은 분기이며,
    --     난이도 티어를 도입할 때 되살아날 자리라 그대로 둔다.
    local speedVar = baseSpeed + math.random(-2, 2)

    hum.WalkSpeed = speedVar
    local walkTrack = setupAnim(bot, hum)

    local downed = false

    -- 다운 상태만 추적 (자동복구 제거: 부활 못 받으면 DownSystem 10초 타이머로 사망 → 제거 가능)
    bot:GetAttributeChangedSignal("Downed"):Connect(function()
        downed = bot:GetAttribute("Downed") == true
    end)

    local function resetToStart()
        hum.Health = hum.MaxHealth
        hum.PlatformStand = false; hum.Sit = false
        bot:SetAttribute("Downed", nil)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        bot:PivotTo(CFrame.new(startPos))
        task.wait(0.1)
    end

    -- 걷기 애니 갱신
    local function updateAnim()
        if not walkTrack then return end
        local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
        if speed > 1 and not downed then
            if not walkTrack.IsPlaying then walkTrack:Play() end
            walkTrack:AdjustSpeed(math.clamp(speed / WALK_SPEED, 0.5, 1.6))
        else
            if walkTrack.IsPlaying then walkTrack:Stop() end
        end
    end

    -- ── 태거 아이템 회피 ─────────────────────────────────
    -- 매 프레임 호출: 주변 TaggerItems 그룹 파트 중 봇으로 빠르게 접근 중인 위협을 찾아,
    -- 그 진행 방향에 대해 좌/우 수직 회피 벡터를 반환. 위협 없으면 nil.
    -- dodgeVec: 회피 방향(월드, 평면). dodgeUntil: 이 방향 유지 만료 시각.
    local dodgeVec = nil
    local dodgeUntil = 0

    -- ── 위험 영역 탈출 ───────────────────────────────────
    -- 영역 안에 있으면 밖으로 나가는 방향을 반환. 원=중심 반대, 레인=긴축 수직.
    -- zoneDelay 만큼 늦게 반응하고, zoneAware 확률로 아예 못 알아채기도 한다(영역당 1회 추첨).
    local zoneFirstSeen = {}   -- [part] = 처음 영역 안에 들어온 시각
    local zoneNoticed   = {}   -- [part] = 이 영역을 인지했는가(추첨 결과)
    local zoneLogAt     = {}   -- [part] = 진단 로그를 마지막으로 찍은 시각(0.5s 스로틀)
    local threatFirstSeen = {} -- [part] = 이 위협을 처음 본 시각 (반응 지연용)

    local function detectZoneEscape()
        local pos = root.Position
        for _, z in ipairs(dangerZones) do
            local part = z.part
            if part.Parent then
                local inside, escape = false, nil
                if z.kind == "circle" then
                    if math.abs(pos.Y - z.center.Y) <= ZONE_Y_TOLERANCE then
                        local d = Vector3.new(pos.X - z.center.X, 0, pos.Z - z.center.Z)
                        local dist = d.Magnitude
                        if dist <= z.radius then
                            inside = true
                            -- 중심에 정확히 겹치면 방향이 없으므로 진행방향 아무쪽이나
                            escape = (dist > 0.01) and d.Unit or Vector3.new(1, 0, 0)
                        end
                    end
                else
                    local cf, size = part.CFrame, part.Size
                    local lp = cf:PointToObjectSpace(pos)
                    if math.abs(lp.X) <= size.X / 2 and math.abs(lp.Z) <= size.Z / 2
                       and math.abs(lp.Y) <= ZONE_Y_TOLERANCE then
                        inside = true
                        local side = (lp.X >= 0) and 1 or -1
                        local v = cf.RightVector * side          -- 레인 폭 방향 = 로컬 X
                        escape = Vector3.new(v.X, 0, v.Z)
                        if escape.Magnitude > 0.01 then escape = escape.Unit else escape = nil end
                    end
                end
                if inside and escape then
                    if zoneNoticed[part] == nil then
                        zoneNoticed[part] = (math.random() < cfg.zoneAware)
                    end
                    -- 🧊 [2026-09-15] 지대 진단. "지대 안에 있다"가 확정된 지점에서만 찍는다.
                    --   [읽는 법]
                    --     줄이 아예 안 뜸    → 지대 등록 실패. BotDangerZone 속성부터 의심
                    --     인지=NO            → zoneAware 추첨 탈락. 값 문제 (현재 1.0이면 안 나와야 정상)
                    --     인지=YES 인데 사망 → 탈출이 늦거나 못 움직인다. 상태= 를 볼 것
                    --   ⚠️ 상태= 가 래그돌 판별이다. Physics/FallingDown 이면 조종 자체가
                    --     안 되므로 회피 로직을 아무리 고쳐도 결과가 같다. 09-15 실측에서
                    --     얼음 사망 2건이 전부 쓰나미 래그돌 3.1~3.7초 뒤였다(ZONE_TTK 3.5).
                    --   ⚠️ 매 프레임 도는 루프 안이다. 파트당 0.5초로 조인다.
                    if ZONE_DIAG then
                        local tNow = os.clock()
                        if not zoneLogAt[part] or tNow - zoneLogAt[part] >= 0.5 then
                            zoneLogAt[part] = tNow
                            local waited = zoneFirstSeen[part] and (tNow - zoneFirstSeen[part]) or 0
                            local okSt, st = pcall(function() return hum:GetState().Name end)
                            print(string.format(
                                "🧊 [Zone] %s | %s(%s) | 인지=%s | 경과 %.2f/%.2fs | 상태=%s",
                                bot.Name, z.kind, part.Name,
                                zoneNoticed[part] and "YES" or "NO",
                                waited, cfg.zoneDelay,
                                okSt and st or "?"))
                        end
                    end
                    if zoneNoticed[part] then
                        if not zoneFirstSeen[part] then zoneFirstSeen[part] = os.clock() end
                        if os.clock() - zoneFirstSeen[part] >= cfg.zoneDelay then
                            return escape
                        end
                    end
                end
            end
        end
        return nil
    end

    -- 🤝 [2026-09-18] '이 좌표가 위험한가' 판정. 부활 전용이다.
    --   [왜 필요한가] 부활은 1.5초를 제자리에 서 있어야 한다. 그동안 회피가 꺼지므로
    --     (reviveStep 이 틱을 조기 종료한다) 위험 지대 안의 동료를 구하러 가면 같이 죽는다.
    --     실제로 불벽 뒤로 구하러 들어가는 게 관측됐다.
    --   ⚠️ [왜 detectZoneEscape 를 안 쓰나] 그쪽은 **봇 자신의 현재 위치**를 보고
    --     탈출 '방향'을 돌려주며, zoneAware 추첨과 zoneDelay 반응 지연이 걸려 있다.
    --     여기 필요한 건 **임의 좌표**의 예/아니오이고, 지연·추첨을 타면 안 된다 —
    --     "가도 되나"는 봇의 인지 운을 따를 문제가 아니다.
    --   ⚠️ [기하가 두 곳에 생겼다] 위 detectZoneEscape 와 같은 규칙이다. 한쪽만 고치면
    --     어긋난다 — circle/lane 판정을 바꾸면 반드시 두 곳을 같이 본다.
    --     바로 위에 붙여둔 이유가 그것이다.
    local function posInDanger(pos)
        for _, z in ipairs(dangerZones) do
            local part = z.part
            if part.Parent then
                if z.kind == "circle" then
                    if math.abs(pos.Y - z.center.Y) <= ZONE_Y_TOLERANCE then
                        local d = Vector3.new(pos.X - z.center.X, 0, pos.Z - z.center.Z)
                        if d.Magnitude <= z.radius then return true end
                    end
                else
                    local cf, size = part.CFrame, part.Size
                    local lp = cf:PointToObjectSpace(pos)
                    if math.abs(lp.X) <= size.X / 2 and math.abs(lp.Z) <= size.Z / 2
                       and math.abs(lp.Y) <= ZONE_Y_TOLERANCE then
                        return true
                    end
                end
            end
        end
        return false
    end

    local function detectThreatDodge()
        local origin = root.Position
        local bestScore = math.huge   -- 낮을수록 위급(예측 최근접거리 + 도달시간 가중)
        local threat, threatVel, threatDist = nil, nil, nil

        -- 🔭 [2026-09-15] 방향별 인지 반경.
        --   [왜] 반경 90 을 map1 언덕에 실제로 그려보니 성문 계단 앞까지밖에 안 닿았다.
        --     그런데 사람 러너는 ItemMarkerClient 로 **거리 제한 없이** 태거 아이템을
        --     높이 45 기둥으로 본다(그 스크립트에 MaxDistance 도 사거리 상수도 없다).
        --     즉 전방에 한해서는 봇이 사람보다 한참 좁게 보고 있었다 — 눈가리개였다.
        --   ⚠️ 이전 주석이 인용하던 "봇은 사람이 볼 수 있는 만큼만" 원칙은
        --     **폭탄 경고원(70)** 얘기다. 굴리기 아이템에는 해당되지 않는다.
        --   [값] 전방 150 = 통나무 접근속도 63 기준 착탄까지 2.4초.
        --     측면·후방은 90 유지 — 거긴 사람이 아예 못 보는 구간이라 더 주면 진짜 비대칭이 된다.
        --   [기준] 봇에겐 카메라가 없으므로 '앞'은 **주행 방향**이다.
        --     ⚠️ 회피 중에는 주행 방향이 옆을 향한다. 그때 뒤쪽 반경으로 좁아지지 않도록
        --       목표(goalPos) 방향을 기준으로 삼는다 — 봇이 결국 가려는 쪽이 '앞'이다.
        local fwd
        do
            -- ⚠️ 목표 좌표는 모듈 최상위 GOAL_POS 다(refreshMapTargets 가 맵마다 갱신).
            --   실측 2026-09-15: 여기서 goalPos / currentGoalPos 같은 이름을 쓰면
            --   조용히 nil 이 되어 폴백으로 빠진다 — 오늘 같은 함정을 세 번째로 밟을 뻔했다.
            if GOAL_POS then
                local d = Vector3.new(GOAL_POS.X - origin.X, 0, GOAL_POS.Z - origin.Z)
                if d.Magnitude > 0.01 then fwd = d.Unit end
            end
            if not fwd then
                local lv = root.CFrame.LookVector
                fwd = Vector3.new(lv.X, 0, lv.Z)
                fwd = (fwd.Magnitude > 0.01) and fwd.Unit or Vector3.new(1, 0, 0)
            end
        end

        for _, p in ipairs(threatList) do
            local st = threatParts[p]
            if st then
                local vel = st.vel   -- 물리속도 또는 위치역산 속도 (updateThreats가 갱신)
                if vel.Magnitude >= cfg.minSpeed then
                    local off = origin - p.Position
                    local dist = off.Magnitude
                    -- 위협이 봇의 전방 쪽에 있으면 넓은 반경을 쓴다.
                    --   cos 0 = 정면 → 1.0 / 좌우 90도 → 0 / 뒤 → −1
                    --   전방 60도 안(cos ≥ 0.5)에서만 확장한다. 그 밖은 기존 반경.
                    local toThreat = Vector3.new(-off.X, 0, -off.Z)
                    local useRadius = cfg.radius
                    if toThreat.Magnitude > 0.01 and fwd:Dot(toThreat.Unit) >= 0.5 then
                        useRadius = cfg.radiusFwd or cfg.radius
                    end
                    if dist < useRadius then
                        local toBot = dist > 0.01 and off.Unit or Vector3.zero
                        if vel.Unit:Dot(toBot) >= cfg.approach then
                            -- 점수화: 거리 + 예측 최근접 보정(고급은 예측 우선)
                            local score = dist
                            if cfg.predict then
                                -- 아이템이 직선 등속이라 가정, 봇과 최근접하는 시점 t*
                                local relPos = p.Position - origin
                                local relVel = vel  -- 봇은 상대적으로 느리니 0 근사
                                local vv = relVel:Dot(relVel)
                                if vv > 0.01 then
                                    local tStar = math.max(0, -relPos:Dot(relVel) / vv)
                                    local closest = (relPos + relVel * tStar).Magnitude
                                    score = closest + tStar * 8  -- 가까이 + 임박할수록 작게
                                end
                            end
                            if score < bestScore then
                                bestScore = score
                                threat, threatVel, threatDist = p, vel, dist
                            end
                        end
                    end
                end
            end
        end
        if not threat then return nil end

        -- ⚠️ 반응 지연: 이 위협을 처음 본 시각을 기록하고, cfg.reactDelay 가 지나야 회피한다.
        --    없으면 봇이 발사 즉시 꺾어 사람보다 유리해진다("에임핵" 체감의 원인).
        --    위협이 사라지면 기록도 지워 다음 위협에 다시 지연이 적용되게 한다.
        local nowT = os.clock()
        if not threatFirstSeen[threat] then
            threatFirstSeen[threat] = nowT
            -- 사라진 위협 기록 정리 (안 하면 테이블이 무한히 커진다)
            -- ⚠️ [2026-08-27] `p ~= threat` 가드 필수.
            --   [증상] 660행 "attempt to perform arithmetic (sub) on number and nil" 5회.
            --   [원인] 방금 등록한 threat 자신이 이 루프에서 지워질 수 있었다.
            --     탐색 루프를 통과한 시점엔 유효했지만 그 사이 아이템이 소멸하면
            --     `not p.Parent` 나 `not threatParts[p]` 에 걸린다. 그러면 바로 아래
            --     `threatFirstSeen[threat]` 가 nil 이 되어 뺄셈에서 터진다.
            --     (실측: 배럴 파열과 같은 밀리초에 5회 — 아이템 소멸 순간이 그 틈이다)
            for p in pairs(threatFirstSeen) do
                if p ~= threat and (not p.Parent or not threatParts[p]) then
                    threatFirstSeen[p] = nil
                end
            end
        end
        -- ⚠️ 이중 안전: 위 가드에도 불구하고 비어 있으면 이번 프레임은 회피하지 않는다.
        --   터지는 것보다 한 프레임 안 피하는 게 낫다.
        local firstSeen = threatFirstSeen[threat]
        if not firstSeen then return nil end
        if nowT - firstSeen < cfg.reactDelay then return nil end

        local v = Vector3.new(threatVel.X, 0, threatVel.Z)
        if v.Magnitude < 0.01 then return nil end
        v = v.Unit
        local left = Vector3.new(-v.Z, 0, v.X)
        local rel = Vector3.new(root.Position.X - threat.Position.X, 0, root.Position.Z - threat.Position.Z)
        local side = (rel:Dot(left) >= 0) and 1 or -1

        -- 🔬 [진단 2026-09-15] 회피가 왜 잘 안 먹는지. 두 가지를 확정하려는 것:
        --   ① 회피 방향이 한쪽으로 몰리는가 — 킹이 한 지점(X≈710)에서만 굴려
        --     모든 위협의 진행방향이 비슷하다. 그러면 수직 회피도 한쪽으로 쏠린다.
        --   ② 회피하는 쪽에 다른 위협이 있는가 — detectThreatDodge 는 **가장 위급한 하나만**
        --     보고 방향을 정한다. 두 번째 위협은 구조적으로 무시되므로,
        --     피한 쪽이 다음 통나무의 경로일 수 있다.
        --   [읽는 법] side 가 +/− 로 갈리면 ①은 기각. 나란수(동시위협)가 2 이상인데
        --     '회피쪽위협' 이 자주 yes 면 ②가 확정된다.
        --   ⚠️ 확인 끝나면 이 블록 삭제. 봇 10마리 × 회피마다 찍혀 양이 많다.
        if DODGE_DIAG then
            local dodgeDir = left * side
            local nThreat, blocked = 0, false
            for _, q in ipairs(threatList) do
                local qs = threatParts[q]
                if qs and q ~= threat and qs.vel.Magnitude >= cfg.minSpeed then
                    local qoff = q.Position - root.Position
                    local qd = qoff.Magnitude
                    if qd < cfg.radius then
                        nThreat = nThreat + 1
                        -- 회피 방향 40도 안에 다른 위협이 있나
                        local flat = Vector3.new(qoff.X, 0, qoff.Z)
                        if flat.Magnitude > 0.01 and flat.Unit:Dot(dodgeDir) > 0.76 then
                            blocked = true
                        end
                    end
                end
            end
            print(string.format("🔬 [Dodge] %s | 위협=%s @%.0f | side=%+d | 동시위협 %d | 회피쪽위협=%s",
                bot.Name, threat.Name, threatDist or -1, side, nThreat, blocked and "YES" or "no"))        end

        return left * side, threatDist   -- 회피방향, 위협까지 거리
    end

    -- 👊 [2026-09-09] 강타(차징 슬랩) 회피.
    --   [왜 필요한가] 실측(00:02 판) — 강타 한 방에 봇 8마리가 동시에 래그돌,
    --     그중 5마리가 같은 초에 다운됐다. 2단계가 24.8초에 전멸로 끝났다.
    --     detectThreatDodge 는 '날아오는 아이템'만 본다(threatList = 태거 아이템).
    --     근접 강타는 발사체가 아니라 그 목록에 영원히 안 들어온다.
    --     → 봇은 창은 잘 피하는데 강타는 한 번도 안 피한다.
    --   [예고 신호는 이미 있다] PushTool.Server 가 차징 동안 킹 캐릭터에
    --     PushCharging = true 를 건다(1153행, 취소·발동 시 false).
    --     CHARGE_TIME 만큼 시간이 있으므로 사람도 이걸 보고 피한다. 봇에게 같은 정보를 준다.
    --   [어디로 피하나] 강타 박스는 CHARGED_SIZE(10 × 10 × 14)를 킹 전방 5 에 놓는다.
    --     좌우 반폭이 5 라, 킹의 '옆'으로 빠지는 게 가장 싸다. 뒤로 물러나면
    --     킹이 따라 돌면 그대로 다시 정면이라 효과가 없다.
    --     → 킹→봇 방향에 수직인 쪽으로 민다. 이미 옆에 있으면 그 방향을 유지한다.
    --   ⚠️ 무력화가 목적이 아니다. 반응 지연(cfg.reactDelay)을 그대로 태워
    --     "보고 반응하는" 수준으로 둔다. 링 분산(1263행)과 합쳐 전멸만 막는다.
    --   ⚠️ 사거리 밖이면 피할 이유가 없다. 박스 대각(약 8.6)에 여유를 얹어 12 안에서만 본다.
    --   ⚠️ 되돌리려면 이 함수와 아래 호출 한 줄을 지운다.
    local CHARGE_DODGE_RANGE = 12
    local chargeFirstSeen = nil
    local function detectChargeDodge(tRoot, taggerChar)
        if not (tRoot and taggerChar) then chargeFirstSeen = nil return nil end
        if taggerChar:GetAttribute("PushCharging") ~= true then
            chargeFirstSeen = nil
            return nil
        end
        local rel = Vector3.new(root.Position.X - tRoot.Position.X, 0,
            root.Position.Z - tRoot.Position.Z)
        local d = rel.Magnitude
        if d > CHARGE_DODGE_RANGE or d < 0.01 then return nil end

        -- 반응 지연: 차징을 '처음 본' 시각부터 cfg.reactDelay 뒤에 움직인다.
        -- (아이템 회피와 같은 규칙 — 없으면 봇이 사람보다 빠르게 반응한다)
        local nowT = os.clock()
        if not chargeFirstSeen then chargeFirstSeen = nowT end
        if nowT - chargeFirstSeen < cfg.reactDelay then return nil end

        -- 킹→봇 방향의 수직 = 옆으로 빠지는 방향. 이미 치우친 쪽을 골라 최단으로 벗어난다.
        local away = rel.Unit
        local perp = Vector3.new(-away.Z, 0, away.X)
        local h = 0
        for i = 1, #bot.Name do h = (h * 31 + bot.Name:byte(i)) % 2 end
        local sgn = (h == 0) and 1 or -1   -- 봇마다 고정된 좌/우 (한쪽으로 몰리지 않게)
        return (perp * sgn + away * 0.5).Unit, d
    end

    -- 봇 마커(초상화+빨강선)는 클라이언트(BotMarkerClient)가 "태거 시점에만" 생성한다.
    -- → 서버 생성 시 모두에게 보이므로 여기서는 만들지 않음.

    print("🏃 [RunnerBotDrive] 주행 시작:", bot.Name, elite and "[엘리트 회피]" or "[일반]", "(속도", speedVar, ")")

    -- 메인 주행 루프 (봇별 독립)
    -- 날아오는 태거 아이템을 인지해 측면 회피. 길찾기는 "향할 목표점"만 갱신.
    task.spawn(function()
        local lastRepath = 0
        local lastPos = root.Position
        local stuck = 0
        local lastAttack = 0  -- 근접 공격 쿨다운 추적(라운드 AI)
        -- 🏰 [2026-09-04] 2단계 점령 목표. 봇은 킹을 쫓지 않고 점령존으로 간다.
        --   [왜] 봇의 전투 승리 경로가 실측상 닫혀 있다(4판: 여유 1.5~2배, 마리당 1.6 DPS).
        --     인원을 늘려도 킹 HP 가 같이 올라 생존시간이 52초로 고정된다.
        --     점령은 이미 설계된 시스템인데 봇이 쓰지 않고 있었을 뿐이다.
        --   ⚠️ 존은 하나로 뭉친다. 나뉘면 두 존이 각각 느리게 차서 둘 다 안 끝난다
        --     (게이지는 존별로 따로 쌓인다 — CaptureSystem 595~597행).
        --   ⚠️ 재평가 주기를 길게 잡는다. 매 틱 고르면 킹이 다가올 때마다 반대편으로
        --     도망가서 영영 교전이 안 생긴다.
        local zoneTarget   = nil
        local zonePickedAt  = 0
        local ZONE_REPICK   = 8.0   -- 존 재선택 주기(초)
        local ragdollSince = 0   -- 래그돌 시작 시각(0 = 래그돌 아님)
        local RAGDOLL_MAX = 3.0  -- 래그돌 상한(초) — 복원 누락 시 봇이 영영 눕는 걸 방지
        local arrived = false  -- 평지 도달 래치: 한번 true면 유지(높이 변동으로 모드 토글 방지)
        local nextGoal = Vector3.new(GOAL_POS.X, root.Position.Y, laneZ)  -- 현재 향할 목표점
        local wpQueue = {}   -- 길찾기 waypoint 큐
        local wpIndex = 1

        while bot.Parent do
            -- 출발 게이트: 테스트 봇은 /start 전 대기. 라운드 AI는 게이트 무시(즉시 출발).
            if not started and not isRoundAI then
                hum:Move(Vector3.zero)
                if walkTrack and walkTrack.IsPlaying then walkTrack:Stop() end
                lastPos = root.Position; stuck = 0
                wpQueue = {}; wpIndex = 1
                RunService.Heartbeat:Wait()
                continue
            end

            -- ⚠️ 사망 검사를 다운 검사보다 먼저 한다.
            --   순서가 반대면, 다운 중 사망했을 때 아래 `if downed then ... continue` 에 갇혀
            --   break 에 도달하지 못한다. downed 플래그는 Downed 속성 변경 신호로만 풀리므로,
            --   killDowned 가 Downed=nil 을 할 때까지 루프가 계속 돌며 updateAnim 이
            --   걷기 애니(180426354)를 다시 붙잡았고, 그 구간이 '즉시 안 쓰러지는' 텀이었다.
            -- 사망 처리
            if hum.Health <= 0 then
                if isRoundAI then
                    -- 라운드 AI: 죽으면 리스폰 안 함(승패 분리). 제어 종료.
                    break
                end
                -- 테스트 봇: 무한 리스폰
                resetToStart()
                lastPos = root.Position; stuck = 0
                wpQueue = {}; wpIndex = 1
                RunService.Heartbeat:Wait()
                continue
            end

            -- ⚠️ [2026-08-25] 래그돌 중에는 주행 제어를 완전히 놓는다.
            --   [문제] 아래 도착 분기가 사거리 안에서 매 Heartbeat 마다
            --   root.CFrame 을 직접 세운다. PlatformStand 로 힘을 빼도
            --   다음 프레임에 똑바로 다시 심어져, 봇은 넘어지지도 밀려나지도
            --   않았다(실측: 강화 슬랩 래그돌 차등이 봇에게 전혀 체감 안 됨).
            --   hum:Move 도 계속 돌아 넉백 BodyVelocity 와 싸운다.
            --   → 유저 러너에게만 먹히던 CC 를 봇에게도 통하게 한다.
            -- ⚠️ 상한을 두는 이유: PlatformStand 를 푸는 쪽(PushTool 등)이
            --   복원 직전에 다운과 겹치면 복원을 건너뛴다. 그러면 봇이
            --   영영 누워 있게 되므로 여기서 강제로 일으킨다.
            if hum.PlatformStand then
                if ragdollSince == 0 then
                    ragdollSince = os.clock()
                    -- 🚧 [진단 2026-08-25] 주행 루프가 래그돌을 실제로 인지하는지.
                    --    이게 안 찍히면 PlatformStand 가 이 루프에 도달하기 전에 꺼진 것이다.
                    -- 🔇 [2026-08-26] 검증 완료 — 항상 정상 인지됐다. 한 판에 100줄 넘게
                    --    찍혀 밸런스 로그를 덮으므로 껐다. 되살리려면 true 로.
                    --    (PushTool.Server 의 RAGDOLL_DIAG 와 한 세트다 — 같이 켤 것)
                    if RAGDOLL_DIAG then
                        warn("[RagdollDiag] 주행 정지 — " .. bot.Name)
                    end
                end
                if os.clock() - ragdollSince > RAGDOLL_MAX then
                    hum.PlatformStand = false
                    ragdollSince = 0
                else
                    if walkTrack and walkTrack.IsPlaying then walkTrack:Stop() end
                    RunService.Heartbeat:Wait()
                    continue
                end
            elseif ragdollSince ~= 0 then
                ragdollSince = 0
            end

            -- 다운 중: 정지하고 연출 유지
            if downed then
                hum:Move(Vector3.zero)
                updateAnim()
                RunService.Heartbeat:Wait()
                continue
            end

            -- 🤝 [2026-09-18] 부활: 다운된 동료를 살리러 간다. 상세는 reviveStep 주석.
            --   [왜 여기인가] 아래 이동 코드가 hum:Move 를 12곳에서 부른다. 그 전부를
            --     건드리는 대신, 다운 처리와 같은 자리에서 틱을 조기 종료한다.
            --     "부활 중엔 다른 걸 안 한다" 가 한 곳에서 보장된다.
            --   ⚠️ 공격·회피도 같이 건너뛴다. 유저도 E 를 홀드하는 동안은 못 때린다 — 같은 제약이다.
            local rv = reviveStep(bot, root, posInDanger)
            if rv then
                hum:Move(rv == "hold" and Vector3.zero or rv, false)
                updateAnim()
                RunService.Heartbeat:Wait()
                continue
            end

            -- 평지 도달 래치: X(평지 입구)+Y(평지 높이)를 한번 만족하면 arrived 고정.
            -- 이후 태거를 쫓아 계단을 내려가도(높이↓) 모드가 풀리지 않음 → 베이스↔계단 왕복 진동 방지.
            if not arrived and root.Position.X >= GOAL_X and root.Position.Y >= GOAL_ARRIVE_Y then
                arrived = true
            end

            -- 도착 판정 (래치)
            if arrived then
                if isRoundAI then
                    -- 🏰 [2026-09-04] 2단계 행동: 점령존으로 간다.
                    --   [왜 바꿨나] 봇의 전투 승리 경로가 실측상 닫혀 있다 — 4판 측정에서
                    --     킹 여유 1.5~2배, 봇 마리당 1.6 DPS. 인원을 늘려도 킹 HP 가 같이
                    --     올라 생존시간이 52초로 고정된다(봇 6마리 52.7 / 10마리 51.6).
                    --     점령은 이미 만들어진 시스템인데 봇이 쓰지 않고 있었을 뿐이다.
                    --   [규칙] 존으로 이동하되, 가는 길에 킹이 사거리에 있으면 때린다.
                    --     ⚠️ 존 '밖'에서는 공격해도 멈추지 않는다. 멈추면 킹이 봇 앞에
                    --       서 있는 것만으로 전원을 묶어둘 수 있고, 그러면 "봇을 세우는 것"이
                    --       킹의 최적해가 된다 — 만들려던 딜레마가 정반대로 뒤집힌다.
                    --     ⚠️ 존 '안'에서는 멈춘다. 존 안에서 킹을 쫓으면 밀려나며 존을
                    --       벗어나고, 그 순간 DECAY_RATE(1.5)가 걸려 진행이 깎인다.
                    local taggerChar, taggerHum = findTaggerChar()
                    local tRoot = taggerChar and (taggerChar:FindFirstChild("HumanoidRootPart")
                        or taggerChar:FindFirstChild("Torso"))

                    -- ── 존 선택 ──
                    -- ⚠️ 존 판정·목록은 CaptureSystem 에서 받는다. 여기서 자체 구현하면
                    --   같은 규칙이 두 곳에 생겨 한쪽만 고쳐지는 사고가 난다.
                    local CS = _G.CaptureSystem
                    local zones = (CS and CS.getZones) and CS.getZones() or nil
                    -- 🎲 [2026-09-04] kill 판이면 존을 아예 안 고른다.
                    --   zoneTarget = nil 이면 아래 이동 블록의 폴백(태거 추격)이 그대로 작동한다.
                    --   기존 경로를 재사용하는 것이라 새 이동 로직을 만들지 않는다.
                    if roundObjective == "kill" then zones = nil end
                    if zones and #zones > 0 then
                        if (not zoneTarget) or (not zoneTarget.Parent)
                           or (os.clock() - zonePickedAt >= ZONE_REPICK) then
                            local best, bestScore = nil, -math.huge
                            for _, z in ipairs(zones) do
                                -- 🧭 [2026-09-04] 존 선택 3단 우선순위.
                                --   ① 킹이 있는 존은 배제  ② 진행도 높은 쪽  ③ 동률이면 가까운 쪽
                                --
                                --   [왜 ①이 절대 우선인가] rate 공식상 킹이 존에 있으면
                                --     8명이 몰려가도 0.35/초(51초)라 2단계 창을 넘긴다. 킹 없으면 1.0/초(18초).
                                --     "킹이 지키는 곳은 가봐야 소용없다"가 체감이 아니라 수치다.
                                --   [왜 ②가 필요한가] '가까운 존'만 보니 스폰 위치대로 8:2 로 갈렸고,
                                --     양쪽 다 안 차서 킹이 어느 쪽도 못 막는 그림이 됐다(22:57 판 실측).
                                --     앞선 쪽으로 합치면 결국 한 곳으로 모여 킹이 막을 대상이 생긴다.
                                --   [왜 ③이 남는가] 라운드 초반엔 둘 다 0% 라 ②로는 못 가른다.
                                --     그때는 가까운 쪽 = 자연스럽게 흩어지고, 화면에서도 읽힌다.
                                --
                                --   ⚠️ 킹이 존을 옮기면 목표도 뒤집힌다. 그건 되살리려는 동작이다 —
                                --     09-04 문서: 존 왕복은 버그가 아니라 안티캠핑 '기능'이다.
                                --     ZONE_REPICK(8초)이 봇마다 따로 도니 전원이 한꺼번에 돌지 않아
                                --     "뜬금없이 흩어진다"는 인상은 완화된다.
                                --   ⚠️ 진행도·존 판정은 전부 CaptureSystem 에서 받는다. 여기서
                                --     자체 계산하면 같은 규칙이 두 곳에 생긴다.
                                local kingHere = (taggerChar and CS and CS.isCharInZone)
                                    and CS.isCharInZone(taggerChar, z) or false
                                local prog = (CS and CS.getZoneProgress)
                                    and CS.getZoneProgress(z) or 0
                                local dist = (z.Position - root.Position).Magnitude
                                --   가중치: 킹(-1000) ≫ 진행도(0~100) ≫ 거리(0~-1 수준)
                                --   자릿수를 벌려 상위 조건이 하위 조건에 절대 안 밀리게 한다.
                                local score = (kingHere and -1000 or 0) + prog * 100 - dist * 0.01
                                if score > bestScore then best, bestScore = z, score end
                            end
                            zoneTarget, zonePickedAt = best, os.clock()
                        end

                        -- 🗡️ [2026-09-19] 여유 인원 → 킹 사냥. 상세 근거는 HUNT_ENABLED 주석.
                        --   [형태] zoneTarget 을 nil 로 만들면 아래 이동 폴백(태거 추격)이
                        --     그대로 작동한다. kill 모드가 쓰는 바로 그 경로라 새 이동 로직이 없다.
                        --   ⚠️ 매 틱 nil 이 되면 위 블록이 매 틱 재선택하지만, 존은 2개뿐이라
                        --     비용이 없다. 그리고 재선택 결과가 같아야 슬롯 판정이 안정된다.
                        --   ⚠️ 조건 셋을 모두 만족해야 나간다:
                        --     ① 점령이 실제로 오르는 중 (prog > 0)
                        --     ② 킹이 그 존에서 멀다 (가까우면 머릿수가 곧 방어다)
                        --     ③ 지킴이 슬롯을 못 잡았다 (= 내가 여유 인원이다)
                        if HUNT_ENABLED and zoneTarget and tRoot
                           and not (HUNT_HERO_ONLY and not bot:GetAttribute("HeroRunner")) then
                            local prog = (CS and CS.getZoneProgress)
                                and CS.getZoneProgress(zoneTarget) or 0
                            local kingNear =
                                (tRoot.Position - zoneTarget.Position).Magnitude <= HUNT_KING_DIST
                            if prog > 0 and (not kingNear)
                               and not claimKeeperSlot(zoneTarget, bot.Name) then
                                zoneTarget = nil
                            end
                        end
                    else
                        zoneTarget = nil
                    end

                    local inZone = (zoneTarget and CS and CS.isCharInZone(bot, zoneTarget)) or false
                    local moving = (zoneTarget ~= nil) and (not inZone)

                    -- 👊 [2026-09-09] 강타 회피 판정.
                    --   ⚠️ 여기서 계산만 하고, 실제 이동 덮어쓰기는 아래 이동 블록에서 한다.
                    --     공격(바로 아래)은 그대로 둔다 — 피하면서도 사거리 안이면 때린다.
                    --   ⚠️ 1단계 회피 블록(detectThreatDodge 호출부)은 이 분기가 continue 로
                    --     빠져나가기 때문에 2단계에선 아예 안 돈다. 그래서 여기 따로 둔다.
                    local chargeDodge = detectChargeDodge(tRoot, taggerChar)

                    -- ── 공격 (이동을 막지 않는다) ──
                    -- 🎯 [2026-09-12] 원거리 스킬은 접촉 사거리 밖에서도 쓴다.
                    --   [왜] 지금까지 스킬은 attackTagger 안에 있어 ATTACK_RANGE 안에서만 나갔다.
                    --     그래서 "내가 먼저 때려야만 봇이 반응한다"가 됐고(사용자 제보),
                    --     사거리 55 짜리 슬램이 접촉해야 쓰이는 모순이 생겼다.
                    --   [규약] 무기가 Tool 에 SkillRange(숫자) 속성을 두면 그 거리까지 허용한다.
                    --     없으면 기존대로 접촉 사거리 안에서만 — 제자리 스킬(스핀·카운터)은 그게 맞다.
                    --   ⚠️ 이동은 안 막는다. 던지고 계속 달린다 — 유저도 그렇게 쓴다.
                    --   🚪 [2026-09-13] 성문 붕괴 전 스킬 금지 — swingHeroWeapon:645 와 **한 짝**이다.
                    --     ⚠️ 처음엔 645 만 막고 "봇 스킬의 유일한 진입점"이라고 적었는데 틀렸다.
                    --       BotSkill 을 Invoke 하는 곳은 둘이다: 645(접촉 사거리)와 여기(원거리).
                    --       성문 너머 55스터드는 정확히 이쪽 경로라, 645 만 막으니 아무 효과가 없었다
                    --       (실측 00:21:25 성문 5칸 남은 상태에서 슬램이 그대로 들어왔다).
                    --     ⚠️ 새 Invoke 지점을 추가하면 여기도 같이 걸 것. 한쪽만 걸면 또 샌다.
                    if tRoot and taggerHum and bot:GetAttribute("HeroRunner")
                        and game:GetService("ReplicatedStorage"):GetAttribute("TaggerHpReady") == true then
                        local tool = bot:FindFirstChildOfClass("Tool")
                        local skillRange = tool and tool:GetAttribute("SkillRange")
                        if skillRange then
                            local d = (Vector3.new(tRoot.Position.X, 0, tRoot.Position.Z)
                                     - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
                            if d > ATTACK_RANGE and d <= skillRange then
                                local sk = tool:FindFirstChild("BotSkill")
                                if sk and sk:IsA("BindableFunction") then
                                    pcall(function() sk:Invoke() end)
                                end
                            end
                        end
                    end

                    if tRoot and taggerHum then
                        local flat = Vector3.new(tRoot.Position.X - root.Position.X, 0,
                            tRoot.Position.Z - root.Position.Z)
                        -- 🗡️ [2026-09-18] 무기를 든 히어로는 유저와 같은 거리·같은 리듬으로 휘두른다.
                        --   사거리 = 무기 리치(heroReach), 간격 = 무기 쿨(HERO_SWING_COOLDOWN).
                        --   무기가 없으면(1단계) 농민과 완전히 동일 — 거리 6, 간격 1.6.
                        --   ⚠️ 이동은 안 막는다. 사거리를 좁혀도 봇은 계속 접근하므로
                        --     '멀리서 멈춘다'가 되지 않는다 — 헛스윙이 실제 스윙으로 바뀔 뿐이다.
                        local heroTool = bot:GetAttribute("HeroRunner")
                            and bot:FindFirstChildOfClass("Tool") or nil
                        local atkRange = heroTool and heroReach(heroTool) or ATTACK_RANGE
                        -- 🔬 [Aim] 조준 내적을 **회전 코드보다 먼저** 뜬다. 상세는 AIM_DIAG 주석.
                        --   ⚠️ 아래 두 회전(not moving 분기 / 스윙 시 연출)이 봇을 킹 쪽으로
                        --     돌려놓기 때문에, 그 뒤에 재면 보정값만 찍혀 결론이 뒤집힌다.
                        local aimDot
                        if AIM_DIAG and heroTool then
                            local f = root.CFrame.LookVector
                            local fh = Vector3.new(f.X, 0, f.Z)
                            if fh.Magnitude > 0.01 and flat.Magnitude > 0.01 then
                                aimDot = fh.Unit:Dot(flat.Unit)
                            end
                        end
                        if flat.Magnitude <= atkRange then
                            -- ⚠️ 이동 중에는 회전시키지 않는다. Move 와 CFrame 을 같은 틱에
                            --   쓰면 AutoRotate 와 싸워 봇이 떤다(태거봇에서 겪은 문제).
                            if not moving then
                                root.CFrame = CFrame.lookAt(root.Position,
                                    Vector3.new(tRoot.Position.X, root.Position.Y, tRoot.Position.Z))
                            end
                            -- 🗡️ [2026-09-18] 무기 든 히어로는 무기 쿨(0.5), 그 외엔 봇 쿨(1.6).
                            --   1단계 히어로는 무기가 없어 농민과 같은 1.6 을 쓴다.
                            local swingGate = heroTool and HERO_SWING_COOLDOWN or ATTACK_COOLDOWN
                            if os.clock() - lastAttack >= swingGate then
                                lastAttack = os.clock()
                                -- 🔄 [연출 2026-09-04] 때리는 순간 킹을 본다.
                                --   [증상] 존으로 이동하며 때리는 봇이 옆을 본 채 공격해
                                --     "누가 나를 때리는지" 화면으로 읽을 수 없었다.
                                --   [왜 여기인가] 위 블록의 회전은 not moving 조건이라 이동 중엔 안 돈다.
                                --     그 조건은 "Move 와 CFrame 을 매 틱 같이 쓰면 AutoRotate 와 싸워
                                --     봇이 떤다"는 실측 때문이라 풀면 안 된다. 대신 여기서 —
                                --     쿨다운당 1회, 즉 1.6초에 한 번만 — 회전시키면 그 싸움이 안 난다.
                                --   [AutoRotate 를 잠깐 끄는 이유] 한 프레임만 돌리면 다음 프레임에
                                --     AutoRotate 가 이동 방향으로 되돌려 눈에 안 보인다. 짧게 붙잡아둔다.
                                --   ⚠️ AI 러너는 부활을 못 해 다운 후 사망한다(09-01 문서). 복구 실패가
                                --     누적될 경로가 없어 안전하다.
                                -- ⚠️ [2026-09-18] 히어로는 이제 0.5초마다 이 블록에 들어온다.
                                --   AutoRotate 를 0.4초(ATTACK_FACE_TIME)씩 끄면 사실상 계속 꺼진
                                --   상태가 되어, 위에 적힌 '떨림' 문제가 그대로 되살아난다.
                                --   회전 연출만은 예전 리듬(1.6초)에 묶어 둔다 — 연출 목적이라
                                --   빈도를 올릴 이유도 없다.
                                local nowFace = os.clock()
                                if hum and tRoot
                                   and nowFace - (bot:GetAttribute("_LastFace") or 0) >= ATTACK_COOLDOWN then
                                    bot:SetAttribute("_LastFace", nowFace)
                                    hum.AutoRotate = false
                                    root.CFrame = CFrame.lookAt(root.Position,
                                        Vector3.new(tRoot.Position.X, root.Position.Y, tRoot.Position.Z))
                                    task.delay(ATTACK_FACE_TIME, function()
                                        if hum and hum.Parent then hum.AutoRotate = true end
                                    end)
                                end
                                -- 🗡️ [2026-09-12] 히어로는 갈퀴 포즈를 건너뛴다.
                                --   [왜] 무기 스크립트가 자기 스윙 애니를 서버에서 직접
                                --     재생한다(DragonFireSword:283). 둘 다 Action 우선순위라
                                --     나중 것이 먼저 것을 덮어 검 모션의 시작이 뭉개진다.
                                --   ⚠️ 농민은 그대로 — 갈퀴 포즈가 유일한 공격 연출이다.
                                if not bot:GetAttribute("HeroRunner") then
                                    swingPose(bot)        -- 갈퀴 휘두르는 포즈
                                end
                                if AIM_DIAG and aimDot then
                                    print(string.format(
                                        "🔬 [Aim] %s | d=%+.2f (%d°) | 거리 %.1f/%.1f | %s",
                                        bot.Name, aimDot,
                                        math.floor(math.deg(math.acos(math.clamp(aimDot, -1, 1))) + 0.5),
                                        flat.Magnitude, atkRange, heroTool.Name))
                                end
                                attackTagger(bot, taggerHum)  -- 데미지(하한 클램프) + 넉백
                            end
                        end
                    end

                    -- ── 이동 ──
                    -- 👊 [2026-09-09] 강타 회피가 최우선. 존 진입·킹 추격·자리 지키기를 전부 덮는다.
                    --   [왜 최우선인가] 1단계의 detectZoneEscape 와 같은 성격이다 —
                    --     "맞으면 그 판이 끝나는 것"이 전진보다 급하다.
                    --     강타는 데미지 40 + 래그돌 0.8초 + 넉백 90 이라 한 방에 다운·전열 붕괴다.
                    --   ⚠️ 게이지 손실을 감수한다. 존을 잠깐 벗어나도, 전멸하면 어차피 0이다.
                    --     차징은 CHARGE_TIME 뿐이라 회피 구간도 그만큼 짧다.
                    --   ⚠️ 공격 블록(위)은 안 건드렸다. 피하는 중에도 사거리 안이면 때린다.
                    if chargeDodge then
                        hum:Move(chargeDodge, false)
                    elseif moving then
                        local toZone = Vector3.new(zoneTarget.Position.X - root.Position.X, 0,
                            zoneTarget.Position.Z - root.Position.Z)
                        if toZone.Magnitude > 0.5 then hum:Move(toZone.Unit, false) end
                    elseif zoneTarget then
                        -- 🗡️ [2026-09-04] 존 안: 무작정 서 있지 않는다.
                        --   [증상] 존에 도착하면 완전 정지라, "밀려남 → 복귀 → 정지"만
                        --     반복해 경직돼 보였다. 공격도 사거리에 들어온 김에 나가는
                        --     부수 효과라 의도가 안 읽혔다.
                        --   [지금] ① 킹이 존 근처면 사거리까지 직접 붙는다.
                        --     ③ 그 외엔 존 중심이 아니라 자기 자리(offset)를 지킨다.
                        --   ⚠️ 킹을 끝까지 쫓으면 안 된다. 존 밖으로 끌려나오면 게이지가
                        --     멈추고, 킹이 봇을 낚아 존을 비우는 게 최적해가 된다.
                        --     그래서 ZONE_HOLD_RADIUS 안에서만 붙는다.
                        local chased = false
                        if tRoot then
                            local toKing = Vector3.new(tRoot.Position.X - root.Position.X, 0,
                                tRoot.Position.Z - root.Position.Z)
                            local kingFromZone = Vector3.new(tRoot.Position.X - zoneTarget.Position.X, 0,
                                tRoot.Position.Z - zoneTarget.Position.Z).Magnitude
                            -- 킹이 존 유지 반경 안에 있고, 아직 사거리 밖이면 붙는다
                            if kingFromZone <= ZONE_HOLD_RADIUS
                               and toKing.Magnitude > ATTACK_RANGE * 0.8
                               and toKing.Magnitude > 0.5 then
                                hum:Move(toKing.Unit, false)
                                chased = true
                            end
                        end
                        if not chased then
                            -- ③ 존 안에서 각자 다른 지점에 선다. 전원이 한 점에 겹쳐 서면
                            --   정지가 더 두드러지고, 광역 강타에 통째로 쓸린다.
                            local off = zoneOffset(bot, zoneTarget)
                            local spot = zoneTarget.Position + off
                            local toSpot = Vector3.new(spot.X - root.Position.X, 0,
                                spot.Z - root.Position.Z)
                            if toSpot.Magnitude > 3 then
                                hum:Move(toSpot.Unit, false)
                            else
                                hum:Move(Vector3.zero)
                            end
                        end
                    elseif tRoot then
                        -- 폴백: 존을 못 찾은 경우에만 기존처럼 태거를 쫓는다
                        -- 🎯 [버그수정 2026-09-09] 전원이 한 점으로 몰리던 것을 각자 다른
                        --   각도에서 붙게 바꾼다. 위 ③ 블록(존 분산)과 같은 문제·같은 해법이다.
                        --   [증상] 유저가 킹일 때 강타 한 방에 5~10명이 동시에 다운.
                        --     실측(00:02 판, 태거 처치 모드): 다운 10건 중 18.8s 에 5명,
                        --     22.2s 에 3명이 같은 초에 몰렸다. 2단계가 24.8초에 전멸로 끝났다.
                        --   [원인] 이 분기는 킹의 '중심'을 목표로 준다. 10마리가 같은 점을
                        --     향하니 ATTACK_RANGE(6) 안에 전부 겹쳐 서고, 광역 강타에 통째로 쓸린다.
                        --     ③ 블록 주석이 "광역 강타에 통째로 쓸린다"고 이미 경고했는데
                        --     그 해법이 존 분기에만 들어가 있었다.
                        --   [해법] 킹 주위 링 위의 '자기 자리'를 목표로 준다.
                        --     각도는 zoneOffset 과 같은 이름 해시 → 매 프레임 같은 값이라
                        --     제자리에서 떨지 않는다. 반경은 ATTACK_RANGE 의 80% 로,
                        --     도착하면 사거리 안이라 공격은 그대로 들어간다.
                        --   ⚠️ 강타를 무력화하는 게 아니다. 여전히 링의 한쪽은 쓸린다 —
                        --     전원이 아니라 일부만 맞게 하는 것이 목적이다.
                        --   ⚠️ 되돌리려면 aimPos 를 tRoot.Position 으로 바꾼다.
                        local ringR = ATTACK_RANGE * 0.8
                        -- 🧭 [2026-09-10] 각도를 botAngle(황금각)로 통일한다. 여기 있던
                        --   인라인 이름 해시가 1° 간격을 만들어 이 분산 전체가 no-op 였다
                        --   (원인·실측은 botAngle 정의부 주석 참조).
                        -- ⚠️ ringR 0.8(=4.8)은 이번엔 건드리지 않는다. 강타 박스 반폭이 5 라
                        --   4.8 링은 옆으로 빠지는 게 물리적으로 불가능하고(최대 |X| 4.8 < 5)
                        --   후방 호로만 탈출된다. 0.95(=5.7)로 올리면 최악 명중 8 → 5 로 더
                        --   떨어지지만(실측), 사거리 6 가장자리라 봇이 공격을 놓칠 위험이 있다.
                        --   각도 수정만 먼저 F5 로 재고 그 다음에 판단한다.
                        local a = botAngle(bot)
                        local aimPos = tRoot.Position + Vector3.new(math.cos(a) * ringR, 0, math.sin(a) * ringR)
                        local flat = Vector3.new(aimPos.X - root.Position.X, 0,
                            aimPos.Z - root.Position.Z)
                        -- 자기 자리까지 2 스터드 안이면 정지. ATTACK_RANGE 판정은
                        -- 위 공격 블록이 '킹 중심 기준'으로 따로 하므로 영향 없다.
                        if flat.Magnitude > 2 then
                            hum:Move(flat.Unit, false)
                        else
                            hum:Move(Vector3.zero)
                        end
                    else
                        hum:Move(Vector3.zero)   -- 태거도 존도 없음: 대기
                    end

                    updateAnim()
                    RunService.Heartbeat:Wait()
                    continue
                end
                -- 테스트 봇: 리셋 후 재돌격
                print("🏁 [RunnerBotDrive] 태거베이스 도달 → 재돌격:", bot.Name)
                hum:Move(Vector3.zero)
                task.wait(RESET_PAUSE)
                resetToStart()
                lastPos = root.Position; stuck = 0
                wpQueue = {}; wpIndex = 1
                continue
            end

            -- 주기적 길찾기: 경로 waypoint 큐 갱신 (장애물 우회 목표점들)
            -- ⚡ 경량화: 맵 대부분은 직선 통로라 길찾기 불필요(회피 로직이 장애물 처리).
            --   계단 구간(평지 진입 직전, X > PATHFIND_X)에서만 길찾기를 켜 비용을 크게 절감.
            --   직선 구간에선 길찾기 끄고 시크+회피만 → ComputeAsync 호출 ~80% 감소.
            local goalPart = getGoalPart()
            local nearStairs = root.Position.X > PATHFIND_X
            if goalPart and nearStairs and (os.clock() - lastRepath) >= REPATH_DT then
                lastRepath = os.clock()
                local path = PathfindingService:CreatePath({
                    AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true,
                })
                local ok = pcall(function()
                    path:ComputeAsync(root.Position, Vector3.new(GOAL_POS.X, GOAL_POS.Y, laneZ))
                end)
                if ok and path.Status == Enum.PathStatus.Success then
                    wpQueue = path:GetWaypoints()
                    wpIndex = 2  -- 1번은 현재 위치
                else
                    wpQueue = {}  -- 실패 → 시크(목표 직선)로 폴백
                end
            elseif not nearStairs then
                -- 직선 구간: 길찾기 큐 비우고 시크 주행 (회피 로직이 장애물 담당)
                wpQueue = {}
            end

            -- 향할 목표점 결정: waypoint 큐가 있으면 따라가고, 없으면 최종 목표로 시크
            if wpQueue[wpIndex] then
                local wp = wpQueue[wpIndex]
                if wp.Action == Enum.PathWaypointAction.Jump then
                    hum.Jump = true
                end
                nextGoal = wp.Position
                -- 현재 waypoint에 충분히 가까우면 다음으로
                local flat = Vector3.new(wp.Position.X - root.Position.X, 0, wp.Position.Z - root.Position.Z)
                if flat.Magnitude < 4 then
                    wpIndex += 1
                end
            else
                nextGoal = Vector3.new(GOAL_POS.X, root.Position.Y, laneZ)
            end

            -- ── 이동: 위협 감지 → 거리 기반 회피 ──
            -- 🩸 [2026-08-27] 다운 중이면 아무것도 하지 않는다.
            --   [증상] 다운 표식을 단 채로 걸어다니는 농민봇이 관측됐다.
            --   [원인] downed 플래그를 '추적만' 하고(527행) 이동 루프에서 보지 않았다.
            --     DownSystem 은 WalkSpeed 를 0 이 아니라 16×0.25=4 로 낮출 뿐이라,
            --     봇이 계속 Move 를 부르면 느리게라도 계속 움직인다.
            --   ⚠️ Move(Vector3.zero) 로 명시적으로 멈춘다. return 만 하면 직전 Move 가
            --     그대로 유지되어 관성으로 계속 밀려간다.
            --   ⚠️ 점프 탈출(아래 끼임 감지)도 건너뛴다 — 다운 중에 튀어오르면 더 이상하다.
            if downed then
                hum:Move(Vector3.zero)
            else
            -- 매 프레임 위협 감지. 위협 있으면 회피 벡터/거리 갱신 + 유지시간 연장.
            local newDodge, threatDist = detectThreatDodge()
            local urgent = false
            if newDodge then
                dodgeVec = newDodge
                dodgeUntil = os.clock() + DODGE_HOLD
                urgent = (threatDist or 999) <= cfg.near
            elseif os.clock() > dodgeUntil then
                dodgeVec = nil
            end

            local to = Vector3.new(nextGoal.X - root.Position.X, 0, nextGoal.Z - root.Position.Z)
            if to.Magnitude > 0.5 then
                local fwd = to.Unit
                local move = fwd
                -- 위험 영역 안이면 탈출이 최우선 (즉사 반경 안에 서 있는 상태라 전진보다 급함).
                -- 경고선/경고원은 사람 러너도 보고 피하는 표시다 — 봇도 같은 정보로 같은 판단을 한다.
                local escapeVec = detectZoneEscape()
                if escapeVec then
                    move = escapeVec
                elseif dodgeVec then
                    if urgent then
                        -- 긴급(가까움): 전진 거의 버리고 측면으로 전력 회피
                        move = dodgeVec.Unit
                    else
                        -- 일반: 전진 + 강한 측면 섞기 (측면 우선)
                        local blended = fwd + dodgeVec * cfg.lateral
                        if blended.Magnitude > 0.01 then move = blended.Unit end
                    end
                end
                hum:Move(move, false)
            else
                hum:Move(Vector3.zero)
            end
            end   -- ⬅️ [2026-08-27] 위 `if downed then ... else` 를 닫는다.

            -- 끼임 감지 → 점프 탈출
            -- ⚠️ 단, 앞이 바리케이드면 점프하지 않는다.
            --   벽은 높이 14라 어차피 못 넘고, 점프하면 벽에서 떨어졌다 붙기를 반복해
            --   우스꽝스러운 데다 파괴 판정(겹침 검사)도 불안정해진다.
            --   벽에 밀착해 있으면 BarricadeSystem 이 알아서 깎으므로 그냥 붙어 있으면 된다.
            local moved = (root.Position - lastPos).Magnitude
            lastPos = root.Position
            if moved < 0.12 then
                stuck += 1
                if stuck >= STUCK_HEARTBEATS then
                    if not isBarricadeAhead(root) then
                        hum.Jump = true
                    end
                    stuck = 0
                end
            else
                stuck = 0
            end

            updateAnim()
            RunService.Heartbeat:Wait()
        end
        controllers[bot] = nil
        -- 라운드 AI가 사망/제거로 루프를 빠져나오면, 시체를 잠시 후 정리(연출 여유 후).
        if isRoundAI and bot.Parent then
            task.delay(3, function()
                if bot and bot.Parent then bot:Destroy() end
            end)
        end
    end)

    -- 사람처럼: 랜덤 주기 점프
    task.spawn(function()
        while bot.Parent do
            local waitT = math.random(20, 55) / 10
            task.wait(waitT)
            if bot.Parent and not downed and hum.Health > 0 then
                -- 가끔만 점프 (항상은 아님)
                if math.random() < 0.5 then hum.Jump = true end
            end
        end
    end)
end

-- 시작: 현재 존재하는 모든 RunnerBot 제어
for _, m in ipairs(workspace:GetChildren()) do
    if m:IsA("Model") and m:GetAttribute("RunnerBot") then
        driveBot(m)
    end
end
-- 이후 추가되는 봇도 자동 제어
workspace.ChildAdded:Connect(function(m)
    if m:IsA("Model") and m:GetAttribute("RunnerBot") then
        task.wait(0.2)
        driveBot(m)
    end
end)

print("✅ RunnerBotDriveController 활성화 (멀티 + 길찾기 주행)")
