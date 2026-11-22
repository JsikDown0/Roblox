-- PushTool Server
-- 태거의 밀쳐내기 도구. 데미지 없이 *위치만 이동* + 짧은 래그돌 — 시간 벌기가 핵심.
--
-- 작동:
--   1. 태거가 좌클릭 → Client가 Remote:FireServer("Push", aimDir) 발신
--   2. 쿨다운 중이면 → 남은 시간을 클라에 발신 (UI 표시용)
--   3. 가능하면 → 휘두름 시작, 윈드업 후 *영역 검사*로 후한 히트 판정
--   4. 맞은 캐릭터에게 카메라 방향 넉백 + PlatformStand 래그돌

local Players = game:GetService("Players")


-- 🔬 [진단 2026-09-08] 훈련장 슬랩 미발동 추적. 원인 확정 후 false → 블록 삭제.
local PUSH_DIAG = false
local Debris  = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tool   = script.Parent
local Remote = Tool:WaitForChild("Remote")
local Handle = Tool:WaitForChild("Handle")

-- ── 설정 ────────────────────────────────────────────────
-- 아래 두 값 = 스윙이 끝난 뒤 "실제로 기다리는 시간"(초). 상수가 곧 체감값.
-- ═══════════════════════════════════════════════════════════
-- ⚔️ [재설계 2026-08-25] 슬랩 = 기본 공격 / 차징 슬랩 = 강타
--
-- [왜] 태거가 2단계에 할 일이 없었다. 쿨 7초짜리 넉백 하나뿐이라
--   밀치고 3초 기다리는 사이 러너는 0.5초마다 계속 때렸다.
--   "밀쳐도 1~1.6초면 돌아오고, 다수면 나머지가 계속 친다"
--   → 킬 수단이 없어 무력했다.
--
-- [설계] 평타를 따로 만들면 양쪽이 말뚝딜을 하게 된다.
--   대신 슬랩 자체를 가볍게(데미지 5 / 쿨 1.0 / 넉백 15) 만들어
--   '약간 쿨 있는 평타'로 쓰고, 차징 슬랩을 킬 수단으로 둔다.
--   게임 아트에서 킹의 손이 빛나는 것과도 맞는다.
-- ═══════════════════════════════════════════════════════════
local SLAP_DAMAGE      = 7      -- 기본 슬랩 데미지
-- 🗡️ [밸런스 2026-09-02] 5 → 7. 슬랩 비중을 올려 강타 명중률 의존을 낮춘다.
--   [측정] AI 러너 HP 100 기준 명중률 실측(19:44~19:47): 강타 36% / 슬랩 73%.
--     강타가 사이클 딜의 57%(40/70)를 차지하는데 셋 중 둘이 빗나가,
--     실효 사이클 딜이 40.5 → 27 로 떨어졌다. 처치 17초 → 29초(실측과 일치).
--   [왜 슬랩인가] 잘 맞는 쪽을 키우면 실효 상승이 예측 가능하다. 강타를 올리면
--     맞는 날만 세지고 평소는 그대로다.
--   [효과] 7초 사이클 대상당 딜: 1:1 기준 70 → 82 (처치 10초 → 8.5초)
--     6명 이상(상한): 40.5 → 51 (처치 17초 → 14초)
--   ⚠️ 이번 판은 CHARGE_TIME 과 함께 바꿨다. 로그의 CHARGED 명중/빗맞힘 비율을
--     따로 세야 두 변경의 기여가 갈린다.
local CHARGE_TIME      = 1.5    -- 차징 슬랩 충전 시간(손이 빛남 = 예고)
-- ⏱️ [밸런스 2026-09-02] 2.0 → 1.5.
--   [왜] 2.0 에는 밸런스 근거가 없었다 — 차징 음원을 2.0초로 만들어서 맞춘 값이다
--     (207행 주석: "음원 2.000초 = CHARGE_TIME 2.0초로 정확히 맞아서").
--   [문제] 시전~판정이 2.55초(차징 2.0 + WINDUP 0.15 + HIT_WINDOW 0.4)나 된다.
--     회피 로직이 없는 AI 봇조차 64% 를 빗나갔다. 봇이 피해서가 아니라,
--     킹 자신의 넉백(슬랩 38 / 강타 90)에 밀려 2초 뒤엔 그 자리에 없기 때문이다.
--   [1.5 인 이유] 카타나 카운터 자세(COUNTER_HOLD_TIME 1.5)와 같은 눈금이다.
--     시전~판정 2.05초. 러너 대시(버스트 0.5초)로 피하기가 빠듯해진다.
--   ⚠️ 유저 러너에게 주는 예고 시간도 같이 줄었다. AI 로만 측정한 값이라
--     유저전에서는 체감이 더 클 수 있다.
--   ⚠️ TaggerBotSystem:1290 의 '이별 일격 폐기' 근거가 이 2.55초 계산이었다.
--     2.05초로 줄었으니 그 판단을 재검토할 수 있다.
local CHARGED_DAMAGE   = 40     -- 차징 슬랩 데미지
-- ⏱️ [밸런스 2026-09-08] 7.0 → 5.0.
--   [왜] 러너 대시(RunnerDive)가 쿨 6초 · iframe 0.5초다. 강타 쿨이 7.0 이면
--     러너는 강타 때마다 대시가 항상 준비된 상태 — 사거리가 얼마든 iframe 에
--     스치면 무효라, 1:1 에서 강타는 구조적으로 안 맞는 스킬이었다.
--   [5.0 인 이유] 대시 6.0 보다 1초 짧다. 킹이 강타를 연속으로 노리면
--     러너의 대시 쿨이 안 도는 창이 생기고, 거기서 심리전이 성립한다.
--     "대시를 아낄 것인가"가 러너의 판단거리가 된다.
--   ⚠️ 다수전 딜이 같이 오른다. 실측(209행 주석)으로 강타는 매 스윙 10명
--     전원을 때린다. SPLIT_EXP 0.5 라 10명이면 총딜 3.16배인데, 그게 7초마다
--     오던 게 5초마다 온다 = 다수 구간 실효 DPS 약 1.4배.
--     1:1 을 고치려는 값이 다수전까지 같이 올린다는 걸 알고 넣는다.
--   ⚠️ 빗맞힘도 같은 값을 문다(955행: swingCharged 면 WHIFF_COOLDOWN 을 안 쓴다).
--     그래서 WHIFF_COOLDOWN 1.2 와의 역전은 생기지 않는다 — 그쪽은 평타 전용.
--   ⚠️ 같은 판에 CHARGED_FORWARD 5 / CHARGED_SIZE 14(사거리 8→12)와
--     예고 사각형도 함께 들어갔다. 세 변경이 겹쳐 있으니 결과를 보고
--     이 값 하나의 기여로 읽지 말 것.
--   ⚠️ 되돌릴 값: 7.0
local CHARGED_COOLDOWN = 5.0    -- 차징 슬랩 쿨 (명중·빗맞힘 공통)
local CHARGED_KNOCKBACK = 90    -- 차징 슬랩 넉백(기존 PUSH_VELOCITY 값)

-- ═══════════════════════════════════════════════════════════
-- 👑 강화 단계(PushChargeStage) 차등
--
-- [왜 데미지는 안 건드리나] 킬 타임 기준선이 아직 미정이다.
--   단계가 데미지에 붙으면 밸런스 기준선 논의와 얽혀 둘 다 못 정한다.
--   래그돌 지속·화면 흔들림은 '킹에게 시간과 타격감을 주되 DPS 는 그대로'라
--   기준선과 분리해서 먼저 넣을 수 있다.
--
-- ⚠️ 서버는 원래 단계를 몰랐다(이 파일에 "stage" 문자열이 0건이었다).
--   KillEffectSystem.updateChargeStage 가 플레이어와 캐릭터 양쪽에
--   PushChargeStage 를 심으므로, 캐릭터에서 읽는다.
-- ⚠️ 넉백(CHARGED_KNOCKBACK)은 이번엔 고정으로 둔다. 존 경합에 직접
--   영향을 주는 값이라 래그돌 체감을 먼저 보고 판단한다.
-- ═══════════════════════════════════════════════════════════
local STAGE_RAGDOLL = { 0.4, 0.6, 0.8 }   -- 강화 슬랩 명중 시 래그돌 지속(초)

-- 💥 다중 명중 데미지 분할 지수. 각자 데미지 = 기본 / n^SPLIT_EXP
--    0.5 = √n. 총딜은 √n 배로만 늘어난다(10명이면 3.16배).
--    ⚠️ 올릴수록 뭉친 다수에게 약해진다. 1.0 이면 총딜이 인원과 무관해진다.
-- 🔴 [밸런스 2026-09-20] 0.5 → 0. 분산을 통째로 끈다.
--   [왜] 1단계 처치가 목표에 계속 미달했다. 09-01 SPLIT_CAP 도입(무한 분할 차단),
--     09-02 3 → 2.5 로 두 번 완화했는데도 부족했고, 라이브 실측에서 "태거가 1단계에서
--     러너를 아예 못 죽인다"가 확인됐다. 완화를 더 하는 대신 제거로 간다.
--   [효과] 유저 러너 기준 — 강타 2명 28.3→40 / 3명 이상 25.3→40 (+58%),
--     평타 3명 이상 4.4→7 (+59%). 1명 구간은 원래 분할이 없어 변화 없다.
--   ⚠️ 이 값이 0 이면 아래 SPLIT_CAP · BOT_SPLIT_WEIGHT · BOT_KING_SPLIT_WEIGHT 가
--     전부 무의미해진다 — swingSplit 을 계산은 하지만 ^0 이라 항상 1 이다.
--     값은 되돌릴 때를 위해 남겨둔다. 지우지 말 것.
--   ⚠️ 강타·평타는 같은 계수를 쓴다(:667 에서 dmg 만 공격 종류로 갈리고 나눗셈은 공통).
--     "강타만" 끄고 싶어지면 그 줄을 `if n > 1 and not swingCharged then` 으로 바꾼다.
--   ⚠️ 넉백·래그돌은 원래부터 분산과 무관하다. 이 변경은 데미지에만 영향을 준다.
--   ⚠️ 되돌릴 값은 0.5.
local SPLIT_EXP = 0

-- 🤖 분산 분모에서 AI 러너를 세는 가중치. 유저는 항상 1.0.
--   [왜] AI 는 흩어지거나 피하지 않아 '항상 최대 분산'을 만든다. 유저 다수를
--     상대로 설계한 분산이 봇전에서는 태거 일방 하향으로만 작동했다.
--   [효과] 10봇 기준 분모 10 → 5. 강타 12.6 → 17.9 (+42%).
--   ⚠️ 1.0 으로 되돌리면 예전 동작(유저·봇 동일)으로 돌아간다.
--   ⚠️ 유저 러너에는 영향이 없다 — 사람 대 사람 밸런스는 그대로다.
-- 🔬 [실험 2026-09-04] 0.5 → 0.25. 봇 1마리를 0.25명으로 센다.
--   [무엇이 달라지나] SPLIT_EXP=0.5(√N) 라 인원 구간마다 효과가 크게 다르다.
--     ⚠️ 봇 10마리에서는 결과가 '완전히 동일'하다 — 10×0.25 = 2.5 로 SPLIT_CAP 과 같아서
--       0.5 일 때(5.0→상한 2.5)와 최종 분모가 똑같아진다. 강타 25.3 그대로.
--       즉 2단계 초반(10마리 밀집)에는 변화가 없고, 봇이 줄수록 킹이 강해진다.
--     구간별 강타 데미지 — 4마리 28.3→40.0 / 5마리 25.3→35.8 / 6마리 25.3→32.7
--                          8마리 25.3→28.3 / 10마리 25.3→25.3(불변)
--   [예상 효과] 실측(14:58 판)의 다운 패턴은 '초반 24초 정체 → 후반 몰아치기'였다.
--     이 변경은 그 후반 구간을 더 빠르게 만든다. 전멸 소요 51초가 줄어들 것으로 본다.
--   ⚠️ SPLIT_CAP(2.5)이 사실상 무력화된다. 0.25 면 봇 10마리여야 겨우 상한에 닿으므로
--     그 아래 전 구간에서 상한이 안 걸린다. 로그의 "(상한, 실제 N)" 병기가 사라지면 그 신호다.
--   ⚠️ 유저 러너는 여전히 1.0 이다. 사람 대 사람 밸런스는 이 변경과 무관하다.
--   ⚠️ 되돌릴 값은 0.5. 봇전 측정을 실전으로 옮길 때 보정이 필요한 세 장치 중 하나다
--     (나머지: ItemNoob 그룹 잠금, scaledAttackDamage 의 유저수 반비례).
-- 🔙 [되돌림 2026-09-18] 0.25 → 0.5. 위 09-04 실험을 원복한다.
--   [왜 되돌리나] 그 실험의 목적이 지금과 정반대다. 당시 근거는 "다운이 후반에 몰린다 →
--     후반 구간을 더 빠르게" 였는데, 오늘 증상은 그 반대다 —
--     존을 잡은 봇 7명이 5초 만에 4명 사망(19:16:29 7명 → 19:16:34 3명).
--     🔬 [K] 간격에 0.0~0.2 초가 반복해 찍힌다 = 한 스윙이 여럿을 동시에 눕힌다.
--   [전제가 바뀌었다] 09-04 에는 봇 부활이 없었다. 다운 = 확정 사망이라 "후반 몰아치기"가
--     곧 마무리였다. 지금은 봇이 서로 살리므로(2026-09-18) 같은 값이 다르게 작동한다.
--     ⚠️ 주석의 전제부터 재확인 — 이 값의 근거는 낡았다.
--   [구간별 강타(40) 실제 피해]  4마리 40.0→28.3 / 5마리 35.8→25.3 / 7마리 30.2→25.3
--                                10마리 25.3→25.3 (불변, 상한에 걸림)
--   [핵심] 7마리 구간에서 봇이 유저보다 19% 더 맞고 있었다. 0.5 면 유저와 같아진다.
--     즉 이건 러너 상향이 아니라 **측정 정합성 개선**이다 — 봇전 결과가 유저전에 더 잘 전이된다.
--   ⚠️ 0.5 로 둔 원래 이유는 여전히 유효하다("AI 는 흩어지지 않아 항상 최대 분산을 만든다").
--     그래서 1.0 까지 가지 않는다. 1.0 은 봇이 유저보다 유리해지는 과보정이다.
--   ⚠️ 유저 러너에는 영향이 전혀 없다. 사람 대 사람 밸런스는 이 변경과 무관하다.
--   ⚠️ 되돌릴 값은 0.25. 되돌릴 때는 부활이 켜져 있는지 함께 확인할 것.
local BOT_SPLIT_WEIGHT = 0.5

-- 🤖 [밸런스 2026-09-06] 킹이 봇일 때만 쓰는 별도 가중치.
--   [증상] 솔로 태거 모드(봇 킹 vs AI 러너 10 + 유저 1)를 관전만 해봤더니,
--     봇 킹이 AI 러너를 정리하지 못하고 AI 들이 알아서 킹을 절반 이상 깎았다.
--     유저가 아무것도 안 해도 라운드가 굴러간다 — 참여할 이유가 사라진다.
--   [실측] 12:04 판 — 킹 피해 1622 중 대부분이 AI, 2단계 88초, 봇 킹 패배.
--     그때 강타는 30.2 였다(7봇 → 분모 1.75). 상한까지 가면 25.3 으로 −37%.
--   [왜 봇만] 분산은 '유저 다수가 뭉치면 약해진다'는 규칙이다. 그런데 AI 는
--     흩어지지도 피하지도 않아 항상 최대 분산을 만든다. 유저용으로 설계한 규칙이
--     봇전에서는 킹 일방 하향으로만 작동한다 — BOT_SPLIT_WEIGHT 를 만든 논리와 같고,
--     그 논리를 봇 킹 상황에 한 번 더 적용하는 것뿐이다.
--   [왜 0.10] 봇 10마리여도 분모가 1.0 이라 분산이 걸리지 않는다. 사실상 '없음'이지만
--     0 이 아니라서, 유저 러너가 섞이면 여전히 분산이 살아난다
--     (유저1 + 봇10 → 분모 2.0 → 강타 28.3). "사람이 있으면 사람 규칙" 이 유지된다.
--   ⚠️ 유저가 킹일 때는 이 값을 쓰지 않는다. 사람 대 사람 밸런스는 그대로다.
local BOT_KING_SPLIT_WEIGHT = 0.10

-- 🧢 [밸런스 2026-09-01] 분산 분모 상한. 이 인원을 넘어도 더는 안 쪼개진다.
--   [문제] 킹의 스케일링이 혼자 어긋나 있었다.
--     러너→킹 피해 ∝ N, 킹 HP ∝ N  → 생존 시간은 상수 (의도된 균형)
--     킹→러너 피해 ∝ √N, 필요 피해량 ∝ N  → 처치 능력만 ∝ 1/√N 로 무너진다.
--     실측 환산: 11명이면 러너 하나 눕히는 데 23.8초. 생존 목표가 30초라
--     "다수 상대로는 아무도 못 죽이고 버티다 끝난다" 가 2단계의 기본형이 됐다.
--   [왜 지수(SPLIT_EXP)가 아니라 상한인가]
--     ① 실패 모드가 '다수 구간'에만 있다. 지수를 낮추면 1:1·1:2 까지 같이 세진다.
--     ② SPLIT_EXP·BOT_SPLIT_WEIGHT 를 건드리면 사람 대 사람 밸런스가 흔들린다.
--        BOT_SPLIT_WEIGHT 를 따로 둔 이유(유저 밸런스 불변)와 같은 원칙이다.
--   [효과] 강타 기준 — 2명 28.3(불변) / 3명 23.1(불변) / 5명 17.9 → 23.1 / 8명 14.1 → 23.1
--     "뭉치면 약해진다" 는 3명까지 그대로 살아 있고, 그 아래로 무한히 내려가는 것만 막는다.
--   ⚠️ 넉백·래그돌은 원래부터 분산과 무관하다. 이 값은 데미지에만 영향을 준다.
--   ⚠️ 올리면(예: 5) 예전 동작에 가까워지고, 내리면(예: 2) 다수전에서 킹이 급격히 세진다.
local SPLIT_CAP = 2.5
-- 🧢 [밸런스 2026-09-02] 3 → 2.5. 다수전에서 킹을 약 10% 강화한다.
--   [왜] 1단계 처치가 목표 6명에 계속 미달했다(오늘 실측 0~3명, RoundSummary 가
--     매번 "⚠️ 1단계 약함"으로 찍힘). 다수 구간의 처치 능력이 부족하다는 신호다.
--   [효과] 강타 23.1 → 25.3 / 슬랩(7) 4.0 → 4.4. 상한에 걸리는 인원도 바뀐다 —
--     봇만이면 6마리 → 5마리, 유저면 3명 → 2.5명분부터 상한이다.
--   [왜 상한만 건드리나] 위 주석대로 SPLIT_EXP·BOT_SPLIT_WEIGHT 를 만지면
--     1:1·1:2 와 사람 대 사람 밸런스까지 같이 흔들린다. 실패 모드는 다수 구간에만 있다.
--   ⚠️ 같은 판에서 SLAP_DAMAGE 5→7, CHARGE_TIME 2.0→1.5 도 함께 바꿨다.
--     세 변경이 겹쳐 있으니 처치 수만 보고 이 값의 기여를 판단하지 말 것.

-- 화면 흔들림: HammerShakeClient 의 (intensity, duration) 규격.
-- 참고 기준선 — 망치 슬램 2.2/0.5, 킬이펙트 빅히트 2.8/0.45, 잽 1.3/0.18
local STAGE_SHAKE_VICTIM = { {1.2, 0.25}, {1.7, 0.32}, {2.4, 0.40} }
-- 때린 태거는 '타격감'이라 훨씬 약하게. 세면 조준이 흔들려 불편하다.
local STAGE_SHAKE_OWNER  = { {0.5, 0.15}, {0.7, 0.18}, {0.9, 0.22} }

local function getChargeStage()
    local ch = Tool.Parent
    local s = ch and ch:GetAttribute("PushChargeStage")
    if type(s) ~= "number" then return 1 end
    return math.clamp(math.floor(s), 1, 3)
end

local COOLDOWN         = 1.0    -- ⚠️ 7.0 → 1.0 (기본 슬랩) -- 밀치기 쿨. 5.0 → 7.0: 2단계에서 러너가 킹에게
                                --   붙어 있을 수 있는 시간을 늘린다(실측: 밀리기 전 2~3타뿐이었음).
                                --   ⚠️ WHIFF_COOLDOWN(빗맞힘) 과 한 세트 — 그쪽도 비율을 보고 조정할 것.
-- ⚠️ 8.0 → 1.2. 평타 수준이 되었으므로 헛쳐도 크게 벌하지 않는다.
local WHIFF_COOLDOWN   = 1.2    -- 빗맞힘 쿨. 명중(7.0)보다 길어야 페널티가 된다.
                                --   (COOLDOWN 을 5→7 로 올릴 때 6.0 이면 역전되어
                                --    빗맞히는 쪽이 유리해지므로 함께 올림)
local WINDUP           = 0.15   -- 휘두르기 시작 → 히트 검사 지연
local HIT_WINDOW       = 0.4    -- 히트 검사 가능 시간
local HIT_CHECK_RATE   = 0.08   -- 히트 검사 간격 (윈도우 동안 ~5번 검사)
-- ⚠️ 90 → 15. 기본 슬랩은 '살짝 밀리는' 정도.
--    강한 넉백은 차징 슬랩(CHARGED_KNOCKBACK 90)이 담당한다.
-- ⚠️ [조정] 15 → 38. 15 는 밀리는 게 거의 안 보였다.
--    평타 수준이라 강하진 않되, "밀어냈다"가 느껴져야 한다.
local PUSH_VELOCITY    = 38     -- 넉백 속도.
                                -- [이력] 80 → 110 (콤보 성립용) → 90 (2026-08-23, 콤보 해체)
                                --
                                -- ⚠️ 110 이던 이유: "Push 후 아이템 콤보가 성립하려면 밀림 거리가
                                --    MIN_SPAWN_DIST(20) 를 넘어야 한다" 였다. 즉 콤보는 의도된 설계였다.
                                --
                                -- ⚠️ 되돌린 이유: 그 의도가 2단계의 장르를 배신했다.
                                --    실측한 확정 콤보 —
                                --      Push 명중 → 넉백 21 stud(=소환 금지선 20 돌파) + 래그돌 0.4s
                                --      → 기립까지 0.6s → 회피 가능 시간 약 1.0s
                                --      → 아이템 데미지 50 × 2 = 러너 HP 100 → 다운
                                --      → Push 쿨 7s 동안 아이템 쿨 3s 로 2발 투하 가능
                                --    2단계는 PvP 단계인데, 러너를 결투 구역 밖(계단=아이템 허용 구역)으로
                                --    밀어내는 수단이 있어서 태거가 결투를 거부하고 킬존으로 배달할 수 있었다.
                                --
                                -- 계산: 수평 성분은 pushDir 의 Y 0.3 때문에 약 0.958 배 →
                                --       90 × 0.958 × PUSH_DURATION(0.2) ≈ 17.2 stud < 20 (여유 2.8)
                                -- ⚠️ 래그돌 관성이 추가로 밀어내므로 실측 필요. 여전히 20 을 넘으면 80 까지 내린다.
                                -- ⚠️ AI 러너도 AI_PUSH_MULT 를 1.25→1.0 으로 맞춰 동일하게 17.2 stud.
local PUSH_DURATION    = 0.2    -- 넉백 적용 시간
local RAGDOLL_DURATION = 0.4    -- 래그돌(PlatformStand) 지속 시간 (0.8 → 0.4, 근접·스택형 러너 행동불능 단축)
-- 스윙 락: 명중 판정이 끝날 때까지의 최소 잠금(연타/애니 스팸 방지). 허공 휘두름은 이 시간 후 바로 재사용 가능.
local SWING_LOCK       = WINDUP + HIT_WINDOW

-- 영역 검사 박스 (후한 판정 — Touched보다 훨씬 후함)
-- ⚠️ [실측 롤백 2026-08-26] 7×10×7 / FORWARD 4 → 10×10×10 / FORWARD 5 복귀.
--   [시도] 강타 한 방이 10명을 때려 실효 DPS 가 튀는 걸 박스 축소로 잡으려 했다.
--   [결과] 효과 0. 축소 전후 모두 매 스윙 10명 전원 명중이었다
--     (09:39 로그, 6스윙 연속 10/10). 봇이 성문 잔해에 한 점으로 겹쳐 서기
--     때문에 박스를 어떻게 줄여도 하나를 맞추면 전부 맞는다.
--   → 다중 명중 문제는 '기하'가 아니라 '한 스윙의 총 딜'로 풀어야 한다.
--     리치만 10 → 7.5 로 깎여 단일 대상 추격이 나빠졌으므로 되돌린다.
-- 📏 [밸런스 2026-09-05] HITBOX_FORWARD 5 → 3. 도달 10.0 → 8.0 stud.
--   [증상] 1대1에서 러너가 접근 도중 먼저 맞고 밀려나 평타를 못 넣는다.
--     실측 — 킹 도달 10.0 vs 근접 무기 약 5.5(Handle 4.0 + 팔). 격차 4.5.
--     러너는 킹의 공격 범위 안을 4.5 stud 걸어 들어가야 자기 사거리에 닿는다.
--   [왜 FORWARD 만 줄이나] SIZE 를 줄이면 좌우 폭(10)도 같이 줄어 다수전과
--     존 밀어내기가 약해진다. 그 둘은 킹의 핵심 역할이라 건드리지 않는다.
--     FORWARD 는 '박스 중심을 앞으로 얼마나 미느냐'라서 전방 도달만 바뀐다.
--   ⚠️ 위 08-26 롤백 근거("단일 대상 추격이 나빠졌다")는 재검토 결과 무효다.
--     러너 대시(Q)는 속도 80 × 0.5초 = 40 stud 순간이동인데 킹 최고속은 18 이다.
--     40 stud 를 따라가는 데 2.2초 — 사거리가 10 이든 7.5 든 추격은 애초에 불가능하다.
--     즉 그 롤백은 존재하지 않는 능력을 지키려 한 것이었다.
--   [남는 격차] 8.0 vs 5.5 = 2.5. 완전히 대등하게 만들지는 않는다 —
--     킹은 1대다를 상대하므로 어느 정도 리치 우위는 유지되어야 한다.
--   ⚠️ 이것은 "접근 중 먼저 맞는" 문제(러너 지적 ②)만 푼다. "붙어서 두 번 못 친다"
--     (지적 ①)는 래그돌 0.4초가 원인이라 이 값과 무관하다. 한 번에 하나씩 —
--     이 변경의 체감을 먼저 보고 래그돌은 그 뒤에 판단한다.
--   ⚠️ 되돌릴 값은 5.
local HITBOX_FORWARD   = 3      -- 태거 앞쪽으로 박스 중심 거리
local HITBOX_SIZE      = Vector3.new(10, 10, 10)  -- 박스 크기

-- 👑 [2026-09-08] 강타 전용 리치. 평타는 위 값 그대로.
--   [왜] 강타와 평타가 완전히 같은 박스여서 "크게 휘두른다"는 감각이 없었다.
--     차징 예고 사각형을 양쪽에 보여주기 시작했으므로(PushChargeFxViewer),
--     회피 기회를 준 만큼 성공했을 때의 보상을 리치로 돌려준다.
--   [값] 전방 도달 8.0 → 12.0.
--   ⚠️ FORWARD 만 올리면 박스 중심이 앞으로 밀려 바로 앞이 비고, 붙어 있는
--     러너를 강타로 못 때린다 — 플레이어에겐 버그로 읽힌다. 그래서 깊이를
--     같은 폭(+4)으로 함께 키워 뒤쪽 경계를 -2 로 고정한다.
--       평타  중심 3, 깊이 10 → 판정 -2 ~  8
--       강타  중심 5, 깊이 14 → 판정 -2 ~ 12
--   ⚠️ 좌우 폭 10 은 건드리지 않는다. 09-05 주석대로 다수전·존 밀어내기가
--     킹의 핵심 역할이고 그건 폭이 담당한다. 폭을 늘리면 "매 스윙 10명 전원
--     명중"(실측)이 더 심해지고 SPLIT_EXP 까지 같이 봐야 한다.
--   ⚠️ PushChargeFxViewer 의 TELE_* 가 이 두 값을 복제한다(차징 중 표시는
--     항상 강타 기준). 여기를 바꾸면 그쪽도 반드시 같이 바꿀 것 —
--     한쪽만 고치면 "표시됐는데 안 맞음"이 된다.
--   ⚠️ 되돌릴 값: 강타도 HITBOX_FORWARD / HITBOX_SIZE 를 쓰게 하면 원복이다.
local CHARGED_FORWARD  = 5
local CHARGED_SIZE     = Vector3.new(10, 10, 14)

-- ── 그랩 스킬 설정 (로켓펀치 / 블츠 Q 방식) ─────────────
local GRAB_COOLDOWN       = 4.0    -- 그랩 쿨다운(초, 명중 무관)
local GRAB_MAX_RANGE      = 50     -- 손이 날아가는 최대 사거리(stud)  (60 → 50, 조금 짧게)
-- ⚠️ [밸런스 2026-08-25] 0.3 → 0.6.
--    사거리 50 을 0.3초에 가면 속도 167 — Demonspear(220) 급이라
--    보고 피할 수 없었다. 블리츠크랭크식으로 '보고 옆으로 비키는'
--    스킬이 되려면 속도 60~85 대여야 한다(0.6초 = 83).
--    ⚠️ 근접(5stud)은 여전히 0.06초라 못 피한다 — 의도된 것.
local GRAB_OUT_TIME       = 0.6    -- 최대 사거리까지 나가는 시간 (속도 유지: 60/0.3 = 200/s)
local GRAB_IN_TIME        = 0.35   -- 회귀 시간
local GRAB_HAND_RADIUS    = 4      -- 날아가는 손의 명중 반경(stud)
local GRAB_STUN           = 1.0    -- 러너 스턴 시간(초)  (0.5 → 1.0)
-- ── 농민(AI 러너) 비대칭 위력 ─────────────────────────────
-- 서사: 왕의 일격에 농민은 나가떨어지지만 영웅(플레이어)은 버틴다.
-- 밸런스: 농민 다굴 스턴락 방지 — 멀리 날리고 오래 묶어 복귀 텀 확보.
local AI_PUSH_MULT = 1.0   -- 농민 넉백 속도 배율 (거리도 비례 증가)
--   1.7 → 1.25 (2026-08-20): PUSH_VELOCITY 를 80→110 으로 올릴 때 이 배율을
--   같이 내리지 않아 AI 넉백이 의도보다 37% 세져 있었다.
--     80 시절 : 80 × 1.7  = 136
--     상향 후 : 110 × 1.7 = 187  ← 과도
--
--   1.25 → 1.0 (2026-08-23): 사람 러너의 Push→아이템 콤보를 끊으려고
--   PUSH_VELOCITY 를 110→90 으로 내렸는데, 이 배율 때문에 봇에게만 콤보가 남아 있었다.
--     90 × 1.25 × 0.958 × 0.2 = 21.6 stud  ← MIN_SPAWN_DIST(20) 돌파, 콤보 성립
--     90 × 1.0  × 0.958 × 0.2 = 17.2 stud  ← 사람과 동일, 금지선 안
--   콤보 차단이 봇/사람 모두에게 일관되게 적용되어야 해서 사람과 같은 값으로 맞췄다.
--
--   ⚠️ 이 변경으로 위 두 목적이 약해진다:
--      · 서사("농민은 나가떨어진다") — 이제 농민도 영웅과 같은 거리만큼 밀린다.
--      · 밸런스(다굴 스턴락 방지) — 봇이 덜 날아가고 더 빨리 복귀한다. 솔로 태거 모드에서
--        봇 4~5마리와 동시 교전 시 태거가 숨 돌릴 틈이 줄어들 수 있다.
--   ⚠️ 그 부작용이 실제로 나타나면, 거리를 되돌리지 말고 RAGDOLL_DURATION 을 봇에 한해
--      늘리는 쪽으로 보완할 것("멀리 날리고" 대신 "오래 묶어"로 목적 달성).
--      거리를 다시 올리면 콤보가 그대로 부활한다.
--     현재    : 110 × 1.25 = 138  ← 예전 체감 복원
--   ⚠️ PUSH_VELOCITY 를 다시 손대면 이 값도 함께 재계산할 것.
--      두 값이 곱해지므로 한쪽만 바꾸면 조용히 배가된다.
local AI_GRAB_STUN = 1.0   -- AI 그랩 스턴. 2.5 → 1.0: 사람(GRAB_STUN)과 동일하게 맞춘다.
                           --   그랩→푸시 콤보에서 CC 가 대응 시간을 통째로 덮는 문제 때문.
                           --   (봇이든 사람이든 같은 규칙이어야 밸런스 판단이 가능)
local function isAIRunner(char)
    return char ~= nil and char:GetAttribute("AIRunner") == true
end
local function grabStunFor(char)
    return isAIRunner(char) and AI_GRAB_STUN or GRAB_STUN
end
local GRAB_HOLD_DIST      = 3.5    -- 회귀 완료 시 태거 앞 몇 stud에 놓을지
local GRAB_HAND_START_FWD = 2      -- 손 시작점: 태거 앞 stud
local GRAB_HAND_HEIGHT    = 1.2    -- 손 시작/비행 높이(HRP 기준)
local GRAB_HAND_ROT       = CFrame.Angles(0, 0, math.rad(180))  -- 날아가는 손 회전 보정(거꾸로 뒤집힘 방지)
local REACT_ANIM_ID       = "rbxassetid://86265615635745"  -- 산데비스탄 탈진 애니(카탈로그 이모트 = 소유 불필요)
local REACT_ANIM_SPEED    = 1.5    -- 리액션 애니 배속

-- ── 사운드 (모든 푸시툴 공통: 그랩 시작 + 푸시 스윙이 같은 whoosh 공유) ──
local GRAB_START_SOUND = 87655902227952   -- 그랩 시작 + 푸시 스윙(허공 포함) whoosh
local GRAB_HIT_SOUND   = 85989790827098   -- 그랩 성공(명중)

-- 💥 [2026-08-28] 파워 슬랩(차징) 전용 사운드 3종. 서로 역할이 다르다.
--   차징 CHARGE : 음원 2.000초. CHARGE_TIME 이 그보다 짧으면 PlaybackSpeed 로 압축한다
--     (startChargeSound 에서 2.0 / CHARGE_TIME 을 자동 계산). 루프는 필요 없다.
--     ⚠️ [2026-09-02] CHARGE_TIME 2.0 → 1.5 로 바뀌어 이제 1.33배속으로 재생된다.
--       상수만 고치면 배속이 따라가므로 이 줄을 다시 손댈 일은 없다.
--   발동 SWING  : 헛쳐도 '항상' 난다. 차징 2초를 들인 행동이라 결과와 무관하게
--     피드백이 있어야 한다. 별도로 뽑은 음원이라 피치 가공을 하지 않는다.
--   명중 HIT    : 실제로 맞았을 때만 '추가로' 겹쳐 난다(발동음을 대체하는 게 아니다).
--     ⚠️ 스윙당 1회다. 피해자마다 틀면 광역 10명에서 10겹으로 터진다.
--       그래서 swingHit 이 false→true 로 바뀌는 첫 순간에만 재생한다.
local POWER_SLAP_CHARGE = 138623499528059
local POWER_SLAP_SWING  = 125644820775449
local POWER_SLAP_HIT    = 118985958978033
local CHARGE_VOLUME     = 0.75
local SWING_VOLUME      = 1.0
local HIT_VOLUME        = 1.0

-- 단발 재생. playGrabSound 와 달리 Vishnu 스킵이 없다 —
-- 이건 공용 whoosh 가 아니라 '스킬 전용' 소리라 스킨과 무관하게 나야 한다.
-- 🔍 [진단 2026-08-28] 파워 슬랩 소리 3종이 각각 언제 나는지 — ⚠️ 확인 후 삭제
--   [왜] "허공에 휘둘렀는데 3종이 다 난다"는 신고. 그런데 명중음 가드는
--     applyPushTo(유효 대상 있을 때만 호출) 안에 있어 논리상 날 수 없다.
--     swing() 이 원래부터 Boom(무음) + GRAB_START_SOUND(whoosh) 를 내므로
--     '기존 whoosh 를 명중음으로 오인'했을 가능성이 있다. 귀로는 구분이 안 되니 찍는다.
--   ✅ [2026-09-13 결론] 가설이 맞았다. 09-13 판 로그에서 허공 스윙 때 찍힌 건
--     "⚠️ 기존 whoosh(GRAB_START_SOUND) 재생 — 강타/평타 공통" 한 줄뿐이고,
--     ①차징음 ②발동음 ③명중음 3종은 실제 강타 명중 때만 순서대로 나왔다.
--     즉 신고는 '기존 whoosh 를 명중음으로 오인'한 것이고 가드는 정상이다.
--   ⚠️ 릴리즈 전 이 토글과 [SlapSFX] print 들을 삭제할 것. 지금은 false 로만 둔다.
local DIAG_SLAP_SFX = false

local function playOneShot(parent, soundId, volume)
	if not parent then return end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. soundId
	s.Volume = volume or 1
	s.Parent = parent
	s:Play()
	game:GetService("Debris"):AddItem(s, 5)
end

-- 차징 중인 Sound. ⚠️ 취소 경로에서 반드시 꺼야 한다 — 안 끄면 소리가 계속 남는다.
local chargeSound = nil

local function stopChargeSound()
	if chargeSound then
		chargeSound:Destroy()
		chargeSound = nil
	end
end

local function startChargeSound(parent)
	if not parent then return end
	stopChargeSound()   -- 이전 게 남아 있으면 먼저 정리(연속 차징 대비)
	local s = Instance.new("Sound")
	s.Name = "PowerSlapCharge"
	s.SoundId = "rbxassetid://" .. POWER_SLAP_CHARGE
	s.Volume = CHARGE_VOLUME
	-- 🔊 [2026-09-02] 음원(2.000초)을 CHARGE_TIME 에 맞춰 압축한다.
	--   CHARGE_TIME 을 1.5 로 줄이면서 그냥 두면 소리가 0.5초 잘려 끝이 안 난다.
	--   PlaybackSpeed 로 재생 속도를 올리면 피치도 같이 올라가는데, 차징음에서는
	--   "빨리 차오른다"로 읽혀 오히려 자연스럽다.
	--   ⚠️ CHARGE_TIME 을 또 바꾸면 이 줄이 자동으로 따라간다. 상수만 고치면 된다.
	s.PlaybackSpeed = 2.0 / CHARGE_TIME
	s.Parent = parent
	s:Play()
	chargeSound = s
	if DIAG_SLAP_SFX then print("[SlapSFX] ① 차징음 재생") end
end

-- ✋ [2026-09-20] 그랩 예고음. 강타 예고음(POWER_SLAP_CHARGE)을 그대로 공유한다.
--   [왜 없었나] 그랩 예고는 부채꼴 + 하이라이트뿐이라 시각 전용이었다. 화면 밖이나
--     등 뒤의 러너는 킹이 그랩을 켠 것을 알 방법이 없었다.
--   [왜 같은 음원] 둘 다 "킹이 뭔가를 모으고 있다"는 같은 종류의 예고다. 새 신호를
--     늘리는 것보다 이미 익힌 신호를 재사용하는 쪽이 읽기 쉽다. 어느 스킬인지는
--     소리가 아니라 예고 도형(부채꼴 vs 사각형)이 구분한다 — 축을 나눈다.
--   ⚠️ 전용 변수를 쓴다. chargeSound 를 재사용하면 안 된다 — beginGrab 주석대로
--     "차징 중 그랩"이 허용돼 있어 두 스킬이 동시에 돈다. 한 변수를 공유하면
--     나중에 시작한 쪽이 먼저 것을 Destroy 해서 소리가 끊긴다
--     (grabCdEnd / realGrabCdEnd 를 분리한 것과 같은 이유).
--   ⚠️ Handle 에 붙인다. 서버 생성이라 전 클라에 복제되고 3D 위치를 갖는다 —
--     러너가 "어디서 그랩이 켜졌나"를 소리로 안다. 예고의 목적 그대로다.
--     툴이 파괴되면 Handle 과 함께 사라져 소리 잔존 경로가 없다.
local GRAB_TELEGRAPH_VOLUME = CHARGE_VOLUME   -- 따로 조이려면 이 값만 만진다
local grabTelegraphSound = nil

local function stopGrabTelegraphSound()
	if grabTelegraphSound then
		grabTelegraphSound:Destroy()
		grabTelegraphSound = nil
	end
end

local function startGrabTelegraphSound(parent, windup)
	if not parent then return end
	stopGrabTelegraphSound()   -- 이전 게 남아 있으면 먼저 정리(연속 시전 대비)
	local s = Instance.new("Sound")
	s.Name = "GrabTelegraph"
	s.SoundId = "rbxassetid://" .. POWER_SLAP_CHARGE
	s.Volume = GRAB_TELEGRAPH_VOLUME
	-- 🔊 음원 2.000초를 경고 시간에 맞춰 압축한다(startChargeSound 와 같은 공식).
	-- ⚠️ windup 을 인자로 받는다. GRAB_WINDUP 은 이 줄보다 한참 아래(1400행대)에
	--   선언돼 있어 여기서 직접 읽으면 전역 nil 이다. 이 파일이 이미 세 번 낸
	--   "local 은 정의 이후에만 보인다" 사고다 — 하드코딩으로 때우지 말 것.
	s.PlaybackSpeed = 2.0 / math.max(windup or 1, 0.01)
	s.Parent = parent
	s:Play()
	grabTelegraphSound = s
end

local function playGrabSound(parent, soundId, volume)
    if not parent then return end
    -- Vishnu(Ascendant): 공용 그랩/스윙 whoosh 스킵 (전용 사운드만 사용)
    if Tool.Parent and Tool.Parent:GetAttribute("VishnuAura") then return end
    local s = Instance.new("Sound")
    s.SoundId = "rbxassetid://" .. soundId
    s.Volume = volume or 0.6
    s.Parent = parent
    s:Play()
    game:GetService("Debris"):AddItem(s, 5)
end

-- ── 상태 ────────────────────────────────────────────────
local canSwing       = true
local swingStartTime = 0     -- 마지막 휘두름 시작 시점 (쿨다운 계산용)
local hitVictims     = {}    -- 한 휘두름 당 같은 사람 중복 히트 방지
local swingSplit     = 1     -- 이번 접촉의 데미지 분할 분모 (SPLIT_CAP 로 잘린 값)
local swingSplitRaw  = 1     -- 상한 적용 전 실제 가중 인원. 로그에만 쓴다 —
                             -- 상한이 실제로 물렸는지 판별하려면 원값이 필요하다.

-- 🚧 [진단 스위치 2026-08-26] 래그돌 실측 로그.
--   [끈 이유] 목표 0.4초 대비 실측이 0.40~0.42초로 수십 회 연속 정확했다.
--     검증이 끝난 진단인데 한 판에 200줄 넘게 찍혀 밸런스 로그를 덮었다.
--   [되살릴 때] true 로 바꾸면 된다. 래그돌 지속·덮어쓰기를 다시 의심하게 되면.
--   ⚠️ RunnerBotDriveController 730행에도 같은 태그의 '주행 정지' 로그가 있다.
--     그쪽은 별도 파일이라 따로 꺼야 한다.
-- ⚠️ [2026-09-08] 재활성화. "슬랩 래그돌이 변화무쌍하다"(살짝 밀림 vs 누워서 허우적)를
--   가르기 위해서다. 이번엔 AI 뿐 아니라 유저도 찍고, '복원 포기' 경로도 로그가 붙었다.
--   확인 끝나면 다시 false.
-- ✅ [2026-09-11] 다시 false. 두 목적이 모두 끝났다.
--   ① 래그돌 변화무쌍: 잔여속도가 KB 값으로만 갈렸다(38→11~14 / 90→26~27).
--      진입속도와 무관하고 실측 0.40~0.42s 로 일정하다 — 덮어쓰기 의심은 기각.
--   ② 좀비 러너 지문(`복원 포기 | Downed=nil HP=0`): scheduleKill 수정 후 2판 0건.
--   ⚠️ 되살릴 때는 RunnerBotDriveController 226행도 같이 켠다(한 세트).
local RAGDOLL_DIAG = false
local pushDirection  = nil   -- 클라가 보낸 조준 방향
-- 캐릭터별 최근 래그돌 ID — 연속 푸시 시 이전 풀기가 새 래그돌을 끝내는 것 방지
-- weak key로 캐릭터 사라지면 자동 정리
local ragdollIds = setmetatable({}, {__mode = "k"})
local swingHit       = false
-- ⚠️ 이번 스윙이 차징 슬랩인지. applyPushTo 가 이걸 보고
--    데미지·넉백을 다르게 준다.
local swingCharged   = false
-- ⚠️ [수정 2026-08-25] 차징 쿨을 기본 슬랩과 분리한다.
--    예전엔 canSwing/cooldownUntil 을 공유해, 차징을 쓰면
--    7초 동안 기본 슬랩(쿨 1초)까지 막혔다.
--    두 기술은 역할이 다르므로 쿨도 따로 돌아야 한다.
local canCharge       = true

-- 🤖 [2026-08-30] 차징 준비 여부를 캐릭터 속성으로 노출한다. (사용처: TaggerBotSystem 라인 하강 판단)
--   [왜] canCharge 는 이 툴의 로컬이라 밖에서 못 읽는다. 봇은 지금까지 그냥 쏘고
--     서버가 거부하는 식이었다("[Charge] 거부: 차징 쿨 N초"). 그래서 봇이 스스로
--     "지금 강타를 쓸 수 있나"를 판단할 방법이 없었다.
--   ⚠️ 반드시 이 setter 로만 바꾼다. canCharge 를 직접 대입하면 속성과 어긋나
--     봇이 낡은 값을 보고 판단한다(상태가 두 벌이 되는 전형적인 사고).
--   ⚠️ 속성이 nil 이면 '준비됨'으로 읽어야 한다 — 초기값이 true 이고,
--     장착 직후엔 아직 한 번도 쓰이지 않아 속성이 없을 수 있다.
local function setCanCharge(v)
    canCharge = v
    local ch = Tool.Parent
    if ch and ch:IsA("Model") then ch:SetAttribute("PushChargeReady", v) end
end
local chargeCdUntil   = 0  -- 이번 휘두름이 유효 대상에 명중했는지
local cooldownUntil  = 0      -- 실제 쿨다운(명중 후) 종료 os.clock(), 없으면 0

-- 그랩 상태
local canGrab          = true
local grabbing         = false   -- 그랩 진행 중(태거 잠금 + 푸시 차단)
local grabSessionId    = 0       -- 세션 가드 — 모든 정리는 자기 세션일 때만
local grabCooldownUntil = 0      -- 그랩 쿨다운 종료 os.clock()
local stunIds = setmetatable({}, {__mode = "k"})  -- 러너별 스턴 세션(중복 그랩 안전)

-- ── 헬퍼 ────────────────────────────────────────────────
local function getOwner()
    return Players:GetPlayerFromCharacter(Tool.Parent)
end

local function getRootPart(character)
    return character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Torso")
end

-- 대상이 *유효한 밀쳐내기 대상*인지
local function isValidTarget(victimChar)
    if not victimChar or victimChar == Tool.Parent then return false end

    local victimHum = victimChar:FindFirstChildOfClass("Humanoid")
    if not victimHum or victimHum.Health <= 0 then return false end

    -- ⚠️ [2026-09-08] 로비 훈련장 체험과 실전 라운드를 여기서 가른다.
    --   [왜 필요] 아래 태거 필터는 Role == "Tagger" 인 대상만 걸러낸다.
    --     로비에서는 모두 Role 이 nil 이라 그 검사를 통과해 '다른 플레이어를 전부 밀 수
    --     있는' 상태가 된다. 무기 8종은 반대로 Role == "Tagger" 만 때리므로 로비에서
    --     안전했는데, PushTool 은 조건이 뒤집혀 있어 그리핑이 가능해진다.
    --     로비는 구름 위 부유섬이라 밀려 떨어지면 낙사한다.
    --   [판별 기준] 소유자의 WeaponTrialActive — WeaponTrialSystem 이 야드 진입에만
    --     세우고 이탈·라운드 시작에 지운다. 라운드 중에는 절대 켜지지 않는다.
    --   [체험 중 규칙] LobbyDummy 표식이 있는 더미만 민다. 플레이어·NPC 전부 제외.
    local owner = getOwner()
    if owner and owner:GetAttribute("WeaponTrialActive") then
        return victimChar:GetAttribute("LobbyDummy") == true
    end

    -- 다른 태거는 밀치지 않음
    local victimPlayer = Players:GetPlayerFromCharacter(victimChar)
    if victimPlayer and victimPlayer:GetAttribute("Role") == "Tagger" then
        return false
    end

    return true
end

-- 💥 [2026-09-11] 태거 타격 표식. 러너(아이스보우·바리케이드)와 같은 문법이다.
--   [왜] 러너 무기엔 HIT 표시가 있는데 태거는 사운드뿐이라 "맞췄는지"가 안 읽혔다.
--     타격 피드백이 한쪽에만 있으면 같은 게임의 두 진영이 다른 완성도로 느껴진다.
--   [베낀 곳] BarricadeSystem.showHitMark (그쪽은 아이스보우를 베꼈다). 텍스트·수명·
--     떠오르는 연출을 그대로 맞춘다 — 진영마다 다르게 생기면 오히려 이질적이다.
--   ⚠️ 앵커가 다르다. 바리케이드는 판정 파트가 27×20×238 거대 박스라 '공격자' 기준으로
--     띄웠지만, 여기는 피격자 위치를 정확히 알므로 '피격자' 에 띄운다.
--   ⚠️ 데미지 팝업과 같은 지점이면 겹친다 → Y 오프셋으로 위에 쌓는다.
--   ⚠️ 크기는 스터드(Scale) 단위. 픽셀 고정은 원거리에서 거대해 보인다
--     (TaggerHpDisplay:30 이 같은 이유로 기각한 방식).
--   ⚠️ 서버 생성 BillboardGui 는 모든 클라에 자동 복제된다 — 맞은 러너도 본다. 의도한 것이다.
--     (데미지 숫자는 때린 사람에게만 보이는 규약이라 서로 역할이 다르다)
local HIT_MARK_LIFE = 0.7      -- 표식 수명(초)
local HIT_MARK_RISE = 3.5      -- 떠오르는 높이(stud)

local function showHitMark(victimChar, charged)
    local vr = victimChar and victimChar:FindFirstChild("HumanoidRootPart")
    if not vr then return end

    local anchor = Instance.new("Part")
    anchor.Name = "_PushHitMark"
    anchor.Size = Vector3.new(0.2, 0.2, 0.2)
    anchor.Transparency = 1
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Anchored = true
    -- 데미지 숫자(피격자 중심)보다 위. 둘이 나란히 떠오른다.
    anchor.CFrame = CFrame.new(vr.Position + Vector3.new(0, 3.4, 0))
    anchor.Parent = workspace

    local gui = Instance.new("BillboardGui")
    gui.Size = charged and UDim2.new(5.5, 0, 2.2, 0) or UDim2.new(4, 0, 1.6, 0)
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.MaxDistance = 300
    gui.Adornee = anchor
    gui.Parent = anchor

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "HIT!"
    -- 강타는 더 뜨겁게. 평타는 바리케이드와 같은 노랑 = 같은 문법.
    lbl.TextColor3 = charged and Color3.fromRGB(255, 170, 60) or Color3.fromRGB(255, 220, 90)
    lbl.TextScaled = true
    lbl.Font = Enum.Font.GothamBold
    lbl.TextStrokeTransparency = 0
    lbl.TextStrokeColor3 = Color3.fromRGB(40, 20, 0)
    lbl.Parent = gui

    local TweenService = game:GetService("TweenService")
    local info = TweenInfo.new(HIT_MARK_LIFE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(anchor, info, {
        CFrame = anchor.CFrame + Vector3.new(0, HIT_MARK_RISE, 0)
    }):Play()
    TweenService:Create(lbl, info, {
        TextTransparency = 1, TextStrokeTransparency = 1
    }):Play()

    game:GetService("Debris"):AddItem(anchor, HIT_MARK_LIFE + 0.1)
end

-- ── 단일 캐릭터에게 밀쳐내기 효과 적용 ─────────────────
local function applyPushTo(victimChar)
    if hitVictims[victimChar] then return end
    if not isValidTarget(victimChar) then return end

    local victimRoot = getRootPart(victimChar)
    local myRoot = getRootPart(Tool.Parent)
    if not victimRoot or not myRoot then return end

    hitVictims[victimChar] = true

    -- ── 카타나 카운터 가로채기 ──────────────────────────────
    -- 대상이 카타나 카운터 자세 중이면, 밀침 대신 반격당함.
    -- (카타나 SwordScript가 _G.katanaCounters[char]에 함수를 등록해둠)
    if _G.katanaCounters and _G.katanaCounters[victimChar] then
        local ok, countered = pcall(_G.katanaCounters[victimChar], Tool.Parent)
        if ok and countered then
            print(string.format("[PushTool] %s의 카타나 카운터에 막힘!", victimChar.Name))
            return  -- 밀치기 무효
        end
    end

    -- 💥 강타 명중음. 발동음에 '추가로' 겹쳐 난다(대체가 아니다).
    --   ⚠️ swingHit 이 아직 false 인 지금 = 이번 스윙의 '첫' 명중이다.
    --     아래 대입보다 앞에 둬야 스윙당 1회가 보장된다. 뒤로 옮기면 피해자마다
    --     울려서 광역 10명일 때 10겹으로 터진다.
    --   ⚠️ 카타나 카운터에 막힌 경우는 위에서 return 되므로 여기 안 온다 — 의도된 동작.
    if swingCharged and not swingHit then
        playOneShot(Handle, POWER_SLAP_HIT, HIT_VOLUME)
        if DIAG_SLAP_SFX then
            print("[SlapSFX] ③ 명중음 재생 → " .. tostring(victimChar and victimChar.Name))
        end
    end
    swingHit = true  -- 유효 대상에 명중(카운터 안 당함) → 이번 휘두름은 쿨다운 부여

    -- ⚔️ 데미지 적용. 예전엔 밀어내기만 하고 데미지가 없어,
    --    태거가 러너를 직접 잡을 수단이 아예 없었다.
    -- ⚠️ 광역이므로 단일 기준으로 정하면 뭉친 러너에게 과해진다.
    --
    -- ═══════════════════════════════════════════════════════════
    -- 💥 [밸런스 2026-08-26] 다중 명중 시 데미지 분할 (1/n^SPLIT_EXP)
    --
    -- [문제] 실측 09:39 판: 강타/평타 가릴 것 없이 매 스윙 10명 전원 명중.
    --   실효 60 DPS 로 1000HP(봇 10) 를 16.5초에 정리했다.
    --   같은 판에서 '점령 저지' 경로는 98~112초가 걸린다 → 6배 차이라
    --   저지 경로가 죽은 콘텐츠가 된다. 두 승리 경로를 같은 시간대에 둬야 한다.
    --
    -- [왜 히트박스가 아닌가] 박스를 10³ → 7³ 로 줄여봤지만 효과 0 이었다.
    --   러너가 한 점에 겹쳐 서면 어떤 크기든 하나를 맞추면 전부 맞는다.
    --   기하가 아니라 '한 스윙의 총 딜' 로 풀어야 한다.
    --
    -- [왜 인원 상한(캡)이 아닌가] 손이 전방을 휩쓰는 모션이 보이는데
    --   "여섯 번째는 안 맞음" 은 픽션이 깨진다. 전원 맞되 힘이 나뉜다.
    -- [왜 거리·순서 감쇠가 아닌가] 겹쳐 선 상황이 문제인데 거리로 나누면
    --   전원이 똑같이 만피 데미지를 받는다. 순서로 나누면 반환 순서라는
    --   보이지 않는 값이 딜을 가른다. 둘 다 자의적이다.
    --
    -- [채택] 열 명을 동시에 후려치면 한 명일 때만큼의 힘이 각자에게 실릴 수 없다.
    --   전원 명중(모션 일치) + 전원 동일 데미지(자의성 없음) + 인원만 반영.
    --   1명 40 / 2명 28 / 4명 20 / 10명 12.6  (총딜은 √n 배로만 증가)
    -- ⚠️ n=1 이면 보정이 없다. 저인원 구도에는 영향을 주지 않는다.
    -- ⚠️ 데미지만 나눈다. 넉백·래그돌은 전원 그대로 받는다.
    --   → 다수를 상대할 때 킹의 최적해가 '터뜨리기' 에서 '묶어두기' 로 바뀐다.
    -- ⚠️ 지수를 올리면 더 가파르게 깎인다(0.5 = √n, 0.6 이면 더 강한 하향).
    -- ═══════════════════════════════════════════════════════════
    do
        local vHum = victimChar:FindFirstChildOfClass("Humanoid")
        -- 🥊 [훈련장 2026-09-19] 로비 훈련 더미의 슬랩은 **데미지를 주지 않는다**.
        --   넉백·래그돌만 남겨 회피·거리 감각 연습용으로 쓴다.
        --   [왜 무피해인가] 로비에서 죽을 수 있으면 안 된다. 로비 사망 경로
        --     (리스폰·상태 복구)가 검증된 적이 없어 부작용을 예측할 수 없다.
        --     연습 목적은 "언제 밀려나는가"라 넉백·래그돌만 있으면 충분하다.
        --   [왜 진짜 PushTool 인가] 흉내로 만들면 쿨 1.0 · 넉백 15 · 래그돌 길이가
        --     실제 킹과 미세하게 달라진다 — 연습이 잘못된 타이밍을 가르치게 된다.
        --     데미지 한 축만 빼고 나머지는 전부 실제와 같은 코드를 태운다.
        --   [판별] 때리는 쪽 캐릭터의 LobbyDummy 속성. 이름 목록이 아니라 속성이라
        --     더미를 늘려도 자동으로 적용된다.
        --   ⚠️ 아래 처형 분기(elseif)에도 같은 가드가 있다. 한쪽만 걸면 샌다.
        --   ⚠️ 되돌리려면 이 변수와 두 조건의 `and not trainOnly` 를 지운다.
        local trainOnly = Tool.Parent and Tool.Parent:GetAttribute("LobbyDummy") == true
        if vHum and vHum.Health > 0 and not victimChar:GetAttribute("Downed")
           and not trainOnly then
            local dmg = swingCharged and CHARGED_DAMAGE or SLAP_DAMAGE
            local n = math.max(1, swingSplit or 1)
            if n > 1 then
                dmg = dmg / (n ^ SPLIT_EXP)
            end
            vHum:TakeDamage(dmg)
            -- 🔢 [2026-09-11] 데미지 표기. 러너 무기엔 있는데 태거만 없었다.
            --   [왜 필요한가] 태거는 타격 피드백이 사운드뿐이라 "맞췄는지"도 애매했다.
            --     그리고 √n 분할 때문에 같은 강타가 40~12.6 으로 갈리는데,
            --     숫자가 안 보이면 "뭉친 적에게 약해진다"는 설계 의도가 전달되지 않는다.
            --   ⚠️ 표시 전용이다. TakeDamage '뒤' 에 두어 판정에 영향이 없게 한다
            --     (DamagePopupServer 주석: "표시와 판정이 한 곳에 섞이면 사고가 난다").
            --   ⚠️ crit=swingCharged — 강타는 금색·크게. 평타와 구분된다.
            --   ⚠️ 봇 킹은 getOwner() 가 nil 이라 _G.ShowDamage 가 조용히 무시한다.
            do
                local ow = getOwner()
                if ow and _G.ShowDamage then
                    local vRoot = getRootPart(victimChar)
                    if vRoot then
                        _G.ShowDamage(ow, math.floor(dmg + 0.5), vRoot.Position, swingCharged)
                    end
                end
            end
            -- 💥 HIT 표식. 숫자 위에 함께 뜬다(showHitMark 주석 참조).
            --   ⚠️ 피격자마다 1개다. 광역 10명이면 10개가 각자 위치에 뜬다 —
            --     같은 지점에 겹치는 게 아니라 분산되므로 의도한 동작이다.
            showHitMark(victimChar, swingCharged)

        -- ☠️ [2026-08-27] 다운자 처형 — 강화 슬랩 전용.
        --   [왜 필요한가] 2단계엔 태거 아이템 반입이 금지(결투 구역)라, HP 소진이
        --     다운으로 바뀌면 킹에게 마무리 수단이 아예 없어진다. 다운자를 밀 수는
        --     있지만 아이템이 다운자를 무시하므로 밀어봐야 처치가 안 된다.
        --     압박선도 다운자를 명시적으로 제외한다(FirePressureSystem.applyZoneDamage).
        --     → 강타를 "터뜨리기"가 아니라 "마무리"로 재정의한다.
        --
        --   [왜 강타만인가] 기본 슬랩은 쿨 1.0초다. 그걸로 처형이 되면 다운시킨 킹이
        --     1초 뒤 지워버려 부활이 원천 봉쇄된다 = 즉사와 같아져 B패치가 무의미해진다.
        --     강타는 예열 2.0 + 쿨 7.0 이라 구조 창이 최소 2초, 최대 9초 확보된다.
        --     (부활 홀드 1.5초 — 2초 창이면 아슬아슬하게 성립한다)
        --
        --   ⚠️ 봇 킹이 강타를 '즉발'로 쓰는 한 이 설계는 성립하지 않는다.
        --     예열이 없으면 예고 없이 다운자가 지워져 구조 창이 0이 된다.
        --     TaggerBotSystem 의 ChargedPush 를 beginCharge 경로로 바꾸는 패치와 한 세트.
        --
        --   ⚠️ √n 분할을 적용하지 않는다. 처형은 데미지가 아니라 판정이다.
        --     다수를 상대해도 쓰러진 하나는 확실히 마무리된다 — 그게 '묶어두고 하나씩'이라는
        --     최적해를 성립시킨다.
        elseif swingCharged and vHum and vHum.Health > 0 and not trainOnly
               and victimChar:GetAttribute("Downed") then
            local ok = _G.KillDownedRunner and _G.KillDownedRunner(victimChar, getOwner())
            if not ok then
                -- 폴백: 전용 경로가 없으면 그냥 죽인다(다운 해제는 사망 처리가 담당).
                vHum.Health = 0
            end
            warn(string.format("[Duel] 처형 → %s (강화 슬랩)", victimChar.Name))
        end

        -- 📳 강화 슬랩 적중 시 화면 흔들림 (양쪽 다, 단계별 차등)
        -- ⚠️ 기본 슬랩은 흔들지 않는다. 쿨 1초로 자주 나가는데 매번 흔들리면
        --    화면이 계속 요동쳐 어지럽다. 강타에만 준다.
        --
        -- ⚠️ [수정 2026-08-25] BarricadeShakeEvent → HammerShakeEvent.
        --   [문제] BarricadeShakeEvent 는 ReplicatedStorage 에 실재하지만
        --   아무도 수신하지 않는 고아 인스턴스다(이름을 바꾸다 남은 잔재).
        --   BarricadeShakeClient 가 기다리는 이름은 "BarricadeShake" 다.
        --   → FindFirstChild 도 FireClient 도 성공해서 nil 체크에 안 걸렸고,
        --      흔들림만 한 번도 안 나왔다. 조용한 실패.
        --   [해결] HammerShakeEvent 는 HammerShakeClient 가 실제로 듣고,
        --   (intensity, duration) 2인자라 단계 차등에 맞다.
        --   KillEffectSystem 도 이미 이걸 재사용한다(선례 있음).
        if swingCharged then
            local shakeEv = ReplicatedStorage:FindFirstChild("HammerShakeEvent")
            if shakeEv then
                local st = getChargeStage()
                -- 맞은 러너: 강하게
                -- ⚠️ AI 러너는 Player 가 아니라 vp 가 nil 이다(솔로 테스트 시
                --    태거 쪽 흔들림만 보인다 — 버그가 아니다).
                local v = STAGE_SHAKE_VICTIM[st]
                local vp = Players:GetPlayerFromCharacter(victimChar)
                if vp and v then shakeEv:FireClient(vp, v[1], v[2]) end
                -- 때린 태거: 약하게 (타격감)
                local o = STAGE_SHAKE_OWNER[st]
                local ap = getOwner()
                if ap and o then shakeEv:FireClient(ap, o[1], o[2]) end
            end
        end
    end


    -- 넉백 방향: 카메라 방향 우선, 없으면 태거→러너 폴백
    local horizontalDir
    if pushDirection then
        horizontalDir = Vector3.new(pushDirection.X, 0, pushDirection.Z)
        if horizontalDir.Magnitude > 0.001 then
            horizontalDir = horizontalDir.Unit
        else
            horizontalDir = myRoot.CFrame.LookVector
            horizontalDir = Vector3.new(horizontalDir.X, 0, horizontalDir.Z).Unit
        end
    else
        local delta = victimRoot.Position - myRoot.Position
        horizontalDir = Vector3.new(delta.X, 0, delta.Z)
        if horizontalDir.Magnitude > 0.001 then
            horizontalDir = horizontalDir.Unit
        else
            horizontalDir = Vector3.new(0, 0, 1)
        end
    end

    -- Y 성분 살짝 추가 (공중에 띄우는 느낌)
    local pushDir = (horizontalDir + Vector3.new(0, 0.3, 0)).Unit

    -- 🔬 [진단 2026-09-08] 넉백 적용 '직전' 상태를 잡는다.
    --   [왜] 래그돌은 정상이었다(9건 전부 목표 0.4 → 실측 0.40~0.42, 덮어쓰기·복원포기 0).
    --     그런데도 결과가 "살짝 밀림" vs "누워서 허우적"으로 갈린다.
    --     → 시간이 아니라 '맞는 순간의 물리 상태'가 변수라는 뜻이다.
    --   [가설] 이동기(런지 대시 55 × 0.22초) 사용 중에 맞으면 기존 속도가 살아 있어
    --     넉백과 합성되거나, 같은 파트의 무버끼리 경합해 자세가 튄다.
    --   [읽는 법]
    --     진입 ~0~5   → 서 있다 맞음. 여기서 눕는다면 가설이 틀린 것
    --     진입 30~60  → 이동기 사용 중. 여기서만 눕는다면 가설 확정
    --     무버 1개+   → BodyVelocity/LinearVelocity 가 이미 붙어 있음 = 경합 상태
    --   ⚠️ bv 를 만들기 '전'에 읽어야 한다. 아래에서 붙이면 우리 것까지 세어진다.
    local dbgSpeed, dbgMovers = 0, 0
    if RAGDOLL_DIAG then
        dbgSpeed = victimRoot.AssemblyLinearVelocity.Magnitude
        for _, d in ipairs(victimRoot:GetChildren()) do
            if d:IsA("BodyVelocity") or d:IsA("LinearVelocity") or d:IsA("BodyMover") then
                dbgMovers = dbgMovers + 1
            end
        end
    end

    -- 🧹 [2026-09-09] 피격자의 '진행 중인 이동기 무버'를 먼저 정리한다.
    --   [증상] 런지(돌진) 중에 슬랩을 맞으면 "잠깐 밀리는" 게 아니라
    --     바닥에 누워 0.4초보다 훨씬 오래 허우적댄다(사용자 제보 + 실측).
    --   [원인] 무버 두 개가 반대 방향으로 동시에 작용한다:
    --     러너 런지  LinearVelocity 전방 55 × 0.22초
    --     킹  슬랩   BodyVelocity  후방 38 × 0.20초 (MaxForce 1e9)
    --     둘 다 매 물리 스텝에 목표 속도를 강제하므로 서로 잡아당겨 몸이 회전한다.
    --     09-04 문서의 "무버는 매 스텝마다 목표를 다시 강제한다"와 같은 함정이다.
    --   [해결] 넉백을 걸기 전에 상대의 이동기 무버를 제거한다. 킹을 너프하지 않고
    --     '겹침' 자체를 없앤다 — 밀림 거리는 그대로고 회전만 사라진다.
    --   ⚠️ 이름으로 찾는다. 새 이동기를 추가할 때 여기 이름도 추가할 것.
    --     ClassicSword 런지 = LungeDashAtt (Attachment). 그 자식 LinearVelocity 가 대상.
    --   ⚠️ Q대시(RunnerDive)는 무적 0.5초를 끼고 있어 애초에 이 지점에 안 온다.
    for _, d in ipairs(victimRoot:GetChildren()) do
        if d:IsA("Attachment") and d.Name == "LungeDashAtt" then
            for _, mv in ipairs(d:GetChildren()) do
                if mv:IsA("LinearVelocity") or mv:IsA("VectorForce") then
                    mv:Destroy()
                end
            end
        elseif d:IsA("LinearVelocity") and d.Name == "LungeDash" then
            d:Destroy()
        end
    end

    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    -- ⚠️ 차징 슬랩이면 강한 넉백, 기본 슬랩이면 약한 넉백
    local kbPower = swingCharged and CHARGED_KNOCKBACK or PUSH_VELOCITY
    bv.Velocity = pushDir * kbPower * (isAIRunner(victimChar) and AI_PUSH_MULT or 1)
    bv.Parent = victimRoot
    Debris:AddItem(bv, PUSH_DURATION)

    -- 래그돌 (다운자에게는 적용 안 함 — 다운 시스템과 충돌 방지)
    -- sentinel ID 사용 — 연속 푸시 시 이전 task.delay가 새 래그돌을 풀어버리는 것 방지.
    -- ⚠️ [2026-08-25] 강화 슬랩은 단계별로 래그돌이 길어진다(0.4 / 0.6 / 0.8).
    --   [왜 여기냐] WalkSpeed 슬로우는 이 파일 566~580 행의 '영구 감속 버그'
    --   자리(다운·스턴이 같은 값을 두고 경합)에 세 번째 writer 를 붙이는 셈이라
    --   위험하다. 래그돌은 ragdollIds 센티널이 이미 겹침을 정확히 처리한다.
    -- ⚠️ 기본 슬랩은 단계와 무관하게 RAGDOLL_DURATION 을 쓴다.
    local victimHum = victimChar:FindFirstChildOfClass("Humanoid")
    if victimHum and not victimChar:GetAttribute("Downed") then
        local newId = (ragdollIds[victimChar] or 0) + 1
        ragdollIds[victimChar] = newId

        local rdTime = RAGDOLL_DURATION
        if swingCharged then
            rdTime = STAGE_RAGDOLL[getChargeStage()] or RAGDOLL_DURATION
        end

        victimHum.PlatformStand = true

        -- ⛔ [철회 2026-08-25] 회전 임펄스(AssemblyAngularVelocity) 제거.
        --
        -- [왜 넣었나] 래그돌 0.8초가 체감상 짧게 느껴진다는 보고.
        -- [왜 뺐나] 실측 결과 지속시간은 정확히 0.80~0.82초였다
        --   (RagdollDiag 복원 로그, 9마리 전수). 즉 시간 문제가 아니었다.
        --   그런데 회전은 '연출'이 아니라 실제 성능을 바꾼다:
        --     · 0.8초 뒤 PlatformStand 가 풀려도 회전 중인 몸은
        --       자세를 되잡는 데 추가 시간이 든다 → 실효 무력화 시간 증가
        --     · 회전체는 마찰로 굴러가 넉백 거리가 늘어난다
        --   래그돌이 봇에게 처음 먹히게 된 것만으로 이미 큰 태거 버프이고,
        --   그 효과가 아직 측정되지 않았다. 그 위에 미측정 버프를 얹으면
        --   나중에 원인을 분리할 수 없다.
        -- ⚠️ 다시 넣으려면 '연출'이 아니라 밸런스 결정으로 다뤄야 한다.
        --   킬 타임 기준선이 정해진 뒤에.

        -- 🚧 [진단 2026-08-25 — 확인 후 삭제] 봇 래그돌 미작동 원인 격리용.
        --   "PlatformStand 를 걸었는데 물리가 안 먹은 것"인지
        --   "애초에 이 분기에 안 들어온 것"인지 가른다. (RAGDOLL_DIAG 로 토글)
        -- ⚠️ [2026-09-08] isAIRunner 게이트 제거 — 유저도 찍는다.
        --   [왜] "슬랩 래그돌이 변화무쌍하다"는 제보. 어떤 땐 살짝 밀리고 어떤 땐 누워서 허우적댄다.
        --   [갈라야 할 것] 셋 중 무엇인가 —
        --     ① 넉백 거리 차이   평타 38 vs 강타 90 (2.4배). 래그돌 시간은 둘 다 0.4 로 같다
        --        (단계 시스템이 꺼져 있어 STAGE_RAGDOLL[1]=0.4 = RAGDOLL_DURATION)
        --     ② 연속 피격 누적   0.4초 안에 또 맞으면 ragdollIds 센티널로 앞 타이머가 무효화되고
        --        뒤 것만 남는다 → 실효 무력화가 0.8초 가까이 늘어난다 ("덮어쓰기됨" 줄로 잡힌다)
        --     ③ 복원 실패        Downed 가드에 걸려 여기서 복구를 포기한 경우
        --        ("복원" 줄이 아예 안 찍힌다 = DownSystem.clearDown 에 인계된 것)
        --   [읽는 법] 한 번 맞을 때마다 시작→(덮어쓰기|복원) 이 짝으로 나와야 정상이다.
        --     짝이 안 맞거나 실측이 목표보다 길면 그게 원인이다.
        --   ⚠️ 원인 확정되면 RAGDOLL_DIAG=false. 릴리즈 전 세 블록 모두 삭제.
        if RAGDOLL_DIAG then
            warn(string.format("[RagdollDiag] %s PS=true rd=%.1fs charged=%s KB=%d | 진입속도 %.1f 무버 %d개 anchored=%s",
                victimChar.Name, rdTime, tostring(swingCharged),
                swingCharged and CHARGED_KNOCKBACK or PUSH_VELOCITY,
                dbgSpeed, dbgMovers,
                tostring(victimRoot and victimRoot.Anchored)))
        end
        local rdStart = os.clock()
        task.delay(rdTime, function()
            -- 더 새 래그돌이 시작됐으면 무시 (그 래그돌의 task.delay에 위임)
            if ragdollIds[victimChar] ~= newId then
                -- 🚧 [진단 — 확인 후 삭제] 덮어써져 조기 종료된 경우. (RAGDOLL_DIAG 로 토글)
                --   ⚠️ 이 줄이 연달아 나오면 원인 ② (연속 피격 누적)다.
                if RAGDOLL_DIAG then
                    warn(string.format("[RagdollDiag] %s 래그돌 덮어쓰기됨 (%.2fs 만에) — 연속 피격",
                        victimChar.Name, os.clock() - rdStart))
                end
                return
            end
            if victimHum and victimHum.Parent and victimHum.Health > 0
               and victimChar.Parent and not victimChar:GetAttribute("Downed") then
                -- ⚠️ [2026-09-01] `not Downed` 가드는 유지한다 — 다운 중에 PlatformStand 를
                --   풀면 다운 자세 연출이 깨진다. 다만 그 경우 여기서 복구를 '포기'하므로,
                --   다운이 끝날 때 DownSystem.clearDown 이 대신 무조건 false 로 되돌린다.
                --   [사고 이력] 그 인계가 없어서, 강타 래그돌과 다운이 겹치면(실측 2 ms 차)
                --     다운이 풀린 뒤에도 PlatformStand=true 로 남아 로비에서 자세가 굳었다.
                --   ⚠️ 한쪽만 고치지 말 것. 이 가드를 없애면 다운 연출이 깨지고,
                --     DownSystem 쪽 복구를 없애면 이 버그가 그대로 돌아온다.
                victimHum.PlatformStand = false
                -- 🛑 [2026-09-08] 래그돌 해제 시 잔여 속도 감쇠.
                --   [증상] 슬랩 맞은 결과가 매번 달랐다 — 어떤 땐 살짝 밀리고,
                --     어떤 땐 바닥에 누워 허우적댄다. 러너가 이동기(런지)를 쓰던
                --     중인지와도 무관했다(사용자 관찰 + 아래 실측).
                --   [원인] 시간 불일치다.
                --     PUSH_DURATION  0.2초 — 넉백이 미는 시간
                --     RAGDOLL_DURATION 0.4초 — PlatformStand 지속
                --     그 차이 0.2초 동안 몸은 날아가는데 PlatformStand 가 켜져 있어
                --     Humanoid 의 지면 마찰·직립 제어가 꺼진 상태다 = 브레이크가 없다.
                --   [실측 2026-09-08] 진입속도와 무관하게 잔여속도가 일정했다 —
                --     진입 9.0 → 잔여 38.3 / 진입 16.0 → 21.0 / 진입 34.0 → 36.8
                --     진입 54.4 → 36.9 / 진입 55.4 → 36.3   (강타는 70.1)
                --     넉백 BodyVelocity 가 MaxForce 1e9 로 이전 속도를 덮어쓰기 때문에
                --     '무엇을 하다 맞았는지'는 결과에 영향을 주지 않는다.
                --   [왜 결과가 갈리나] 잔여속도는 늘 같고, 그 36 으로 미끄러지다
                --     '어디서 멈추느냐'가 지형에 달렸다. 평지면 스르륵 서고,
                --     경사·계단·벽이면 걸리거나 구른다. 그래서 매번 달라 보였다.
                --   ⚠️ 0 으로 완전히 지우지 않는다. 넉백 실효 거리의 상당 부분이
                --     이 0.2초 관성 활강에서 나온다. 09-06 규칙서가 못박은
                --     "평타 넉백은 태거의 유일한 문턱 방어 수단"을 깎게 된다.
                --     0.3 이면 36 → 11 로, 밀림은 대체로 유지되고 착지만 안정된다.
                --   ⚠️ 되돌릴 값: 이 두 줄 삭제(감쇠 없음).
                --   ⚠️ 다운 중에는 여기 안 온다(위 가드). 그쪽은 DownSystem.clearDown 담당.
                local vRoot = victimChar:FindFirstChild("HumanoidRootPart")
                if vRoot then
                    vRoot.AssemblyLinearVelocity = vRoot.AssemblyLinearVelocity * 0.3
                end
                -- 🚧 [진단 — 확인 후 삭제] 실제 유지 시간 실측. (RAGDOLL_DIAG 로 토글)
                if RAGDOLL_DIAG then
                    -- ⚠️ 복원 시점의 잔여 속도. 여기가 크면 PlatformStand 가 풀려도
                    --   몸이 계속 미끄러져 "허우적"으로 보인다 (넉백은 0.2초에 끝나는데
                    --   래그돌은 0.4초라, 남은 0.2초의 관성이 그대로 이어진다).
                    local vr = victimChar:FindFirstChild("HumanoidRootPart")
                    warn(string.format("[RagdollDiag] %s 복원 — 실측 %.2fs (목표 %.1fs) | 잔여속도 %.1f",
                        victimChar.Name, os.clock() - rdStart, rdTime,
                        vr and vr.AssemblyLinearVelocity.Magnitude or -1))
                end
            elseif RAGDOLL_DIAG then
                -- 🚧 [진단 2026-09-08 — 확인 후 삭제] 복구를 '포기'한 경우.
                --   원래 여기는 로그가 없어서, 복원이 안 된 건지 애초에 안 걸린 건지 못 갈랐다.
                --   Downed=true 면 정상(인계) — DownSystem.clearDown 이 대신 푼다.
                --   Downed=false 인데 여기 오면 그게 진짜 버그다(사망·캐릭터 소멸 외).
                warn(string.format("[RagdollDiag] %s 복원 포기 (%.2fs) | Downed=%s HP=%s parent=%s",
                    victimChar.Name, os.clock() - rdStart,
                    tostring(victimChar:GetAttribute("Downed")),
                    victimHum and tostring(victimHum.Health) or "nil",
                    tostring(victimChar.Parent ~= nil)))
            end
        end)
    end

    -- 사운드 (명중 "짝!")
    local smack = Handle:FindFirstChild("Smack")
    if smack then
        -- Vishnu(Ascendant): 짝! 타격음은 유지하되 볼륨 줄임 (전용음과 균형)
        if Tool.Parent and Tool.Parent:GetAttribute("VishnuAura") then
            local q = smack:Clone()
            q.Volume = smack.Volume * 0.35
            q.Parent = Handle
            q:Play()
            Debris:AddItem(q, 3)
        else
            smack:Play()
        end
    end

    -- ⚠️ [수정] 예전엔 COOLDOWN 을 하드코딩해 찍어서, 차징 스윙도 "쿨 1s" 로 보였다.
    --    로그만 보고 강타/평타를 구분할 수 없었다. 실제 값으로 찍는다.
    -- ⚠️ [2026-09-01] 분모가 SPLIT_CAP 에 걸리면 "3.0명(상한, 실제 5.5)" 로 병기한다.
    --    상한이 실제로 물렸는지 로그만 보고 판별하려면 원값이 필요하다.
    -- ⚠️ [2026-09-06] 진단 로그 OFF.
    --   [왜] warn 은 Creator Hub Error report 에 '경고'로 집계된다. 밀치기 1회마다
    --     찍혀서 28일간 [Duel] 계열만 약 6,000건이 쌓였고(봇 10마리도 각각 찍힘),
    --     진짜 에러가 그 안에 묻혔다. 서버 부하와 로그 오염 둘 다 실측으로 확인됨.
    --   [되돌리려면] DUEL_DIAG 를 true 로. 밸런스 재측정할 때만 켠다.
    -- 🔬 [측정 2026-09-10 완료 → OFF] botAngle 분산 수정 검증에 썼다.
    --   [결과] 강타 명중 10명 전원 → 5~9명(킬 모드 링) / 5~6명(점령 모드 존).
    --     splitTag 실측이 min(n,2.5)^0.5 모델과 전 구간 일치했고,
    --     SPLIT_CAP(2.5)은 3판 내내 한 번도 안 걸렸다(최대 2.25 = 봇 9마리).
    --   ⚠️ 봇전 기준이라 분산 효과가 과소평가된다 — BOT_SPLIT_WEIGHT 0.25 때문에
    --     봇 9마리가 2.25명분이다. 유저 9명이면 상한에 걸려 25.3 이 된다.
    local DUEL_DIAG = false
    if DUEL_DIAG then
    local splitTag = (swingSplitRaw > swingSplit)
        and string.format("%.1f명(상한, 실제 %.1f)", swingSplit, swingSplitRaw)
        or  string.format("%.1f명", swingSplit)
    warn(string.format("[Duel] %s 명중 → %s (dmg %.1f ×%s / 쿨 %.1fs%s)",
        swingCharged and "CHARGED" or "SLAP",
        victimChar.Name,
        (swingCharged and CHARGED_DAMAGE or SLAP_DAMAGE) / (swingSplit ^ SPLIT_EXP),
        splitTag,
        swingCharged and CHARGED_COOLDOWN or COOLDOWN,
        swingCharged and string.format(" / %d단계 래그돌 %.1fs", getChargeStage(),
            STAGE_RAGDOLL[getChargeStage()] or RAGDOLL_DURATION) or ""))
    print(string.format("[PushTool] %s가 %s를 밀침", Tool.Parent.Name, victimChar.Name))
    end
end

-- ── 영역 검사 ────────────────────────────────────────────
-- 태거 앞쪽 박스 영역 안의 모든 캐릭터 검사 (Touched보다 훨씬 후함)
local function performHitCheck()
    local myRoot = getRootPart(Tool.Parent)
    if not myRoot then return end

    -- 검사 방향: 항상 캐릭터 전방 (근접 밀치기 — 카메라 조준이 아니라 몸이 보는 쪽)
    local forward = myRoot.CFrame.LookVector
    forward = Vector3.new(forward.X, 0, forward.Z)
    if forward.Magnitude < 0.001 then return end
    forward = forward.Unit

    -- Vishnu(Ascendant) 스킨: 판정은 원본과 동일 (시각만 거대 — 스킨이 성능 이점 없게)
    local vMult = 1

    -- 👑 [2026-09-15] 몸집 강화에 따른 판정 확대.
    --   ⚠️ vMult 와 **반드시 분리한다.** 둘 다 "몸이 커진다"지만 근거가 반대다:
    --     vMult(스킨)  과금으로 사는 것 → 판정 이점을 주면 P2W. 그래서 영원히 1
    --     sMult(강화)  1단계 성과로 얻는 것 → 이점이 목적
    --     한 변수에 섞으면 "비슈누 스킨 쓴 킹만 판정이 크다"는 버그가 난다.
    --   [왜 절반인가] 몸 배율을 그대로 쓰면 강타 사거리 12 → 30 이다. 2단계 존 간 거리가
    --     20~50 이라 화면 절반을 덮는 원거리기가 된다. 절반이면 12 → 21 로,
    --     "팔이 길어졌다"가 읽히는 선에서 멈춘다.
    --   ⚠️ 박스가 커지면 걸리는 인원이 늘고, SPLIT_EXP 0.5 분할로 개별 데미지는 오히려
    --     줄어든다. 총딜은 오르지만 '한 명 끊기'는 어려워질 수 있다 — 실측으로 볼 것.
    --   [경위] 처음엔 시각만 키웠는데 실측 결과가 "메리트를 못 느끼겠다"였다.
    --     히트박스는 2.5배로 커져 더 잘 맞는데 리치는 그대로라, 보상이 아니라 벌이었다.
    local sMult = 1
    do
        local myChar = Tool.Parent
        local ks = myChar and myChar:GetAttribute("KingScale")
        if ks and ks > 1 then sMult = 1 + (ks - 1) * 0.5 end
    end

    -- 👑 강타면 늘어난 박스를 쓴다(CHARGED_FORWARD / CHARGED_SIZE 주석 참조).
    --   ⚠️ swingCharged 는 이 파일 최상위 지역변수(385행)라 여기서 읽힌다.
    local fwdDist = swingCharged and CHARGED_FORWARD or HITBOX_FORWARD
    local boxSize = swingCharged and CHARGED_SIZE    or HITBOX_SIZE

    -- 박스 중심 = 태거 앞쪽 fwdDist stud
    local hitCenter = myRoot.Position + forward * (fwdDist * vMult * sMult)
    -- 박스 회전: 카메라 방향 따라 정렬
    local hitCFrame = CFrame.lookAt(hitCenter, hitCenter + forward)

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {Tool.Parent}

    local parts = workspace:GetPartBoundsInBox(hitCFrame, boxSize * vMult * sMult, params)

    -- 🔬 [진단 2026-09-15] 강화 판정이 실제로 커지는지. 배율이 1 이 아닐 때만 찍는다.
    --   ⚠️ 도달 거리 = 중심거리 + 박스Z/2 다. CHARGED_SIZE 의 Z(14)를 사거리로 읽으면 틀린다.
    --   ⚠️ 확인 끝나면 이 블록 삭제. 스윙마다 한 줄이라 쌓인다.
    if sMult > 1.001 then
        local reach = (fwdDist + boxSize.Z / 2) * sMult
        print(string.format("🔬 [Reach] %s ×%.2f | 도달 %.1f (기본 %.1f) | 폭 %.1f | 걸린파트 %d",
            swingCharged and "강타" or "평타", sMult, reach, fwdDist + boxSize.Z / 2,
            boxSize.X * sMult, #parts))
    end

    -- BasePart들의 부모 캐릭터 추출 (중복 제거)
    -- ⚠️ [2026-08-26] 2패스로 바꿨다. 먼저 '이번 접촉에 걸린 인원'을 세고,
    --    그 수로 데미지를 나눈 뒤에 때린다(아래 SPLIT_EXP 참조).
    --    한 패스로 때리면서 세면 먼저 처리된 사람이 더 아프게 되어,
    --    같은 자리에 겹쳐 선 러너끼리 딜이 갈린다.
    local seen = {}
    local batch = {}
    for _, part in ipairs(parts) do
        local victimChar = part:FindFirstAncestorOfClass("Model")
        if victimChar and not seen[victimChar] then
            seen[victimChar] = true
            -- Humanoid가 있는 모델만 (다른 발사체/오브젝트 제외)
            -- ⚠️ applyPushTo 의 선행 조건과 같은 것만 센다. 이미 맞은 사람이나
            --    무효 대상을 세면 분모가 부풀어 나머지가 부당하게 약해진다.
            if victimChar:FindFirstChildOfClass("Humanoid")
               and not hitVictims[victimChar]
               and isValidTarget(victimChar) then
                table.insert(batch, victimChar)
            end
        end
    end

    -- 이번 접촉의 분할 계수를 정한 뒤 때린다.
    -- 🤖 [밸런스 2026-08-29] AI 러너는 분모에 BOT_SPLIT_WEIGHT 만큼만 센다.
    --   [증상] 봇들이 너무 오래 살아남아 2단계 긴장이 떨어졌다.
    --   [원인] 분산이 인원수 기준이라 AI 10명이 뭉치면 강타가 12.6 으로 쪼개진다.
    --     그런데 AI 는 유저와 달리 흩어지거나 피하지 않아 '항상 최대 분산'을 만든다.
    --     유저 다수를 상대로 설계한 분산이 봇전에서는 태거 일방 하향으로만 작동했다.
    --   [해결] 봇은 0.5 명으로 센다. 10봇이면 분모 5 → 강타 17.9 (12.6 대비 +42%).
    --   ⚠️ 유저는 1.0 그대로다. 사람 대 사람 밸런스는 건드리지 않는다.
    --   ⚠️ 데미지만 나눈다. 넉백·래그돌은 여전히 전원 그대로 받는다.
    -- 🤖 킹이 봇이면 AI 러너를 더 가볍게 센다. 판별은 '이 툴의 주인이 Player 인가'로
    --   한다 — TaggerDummy 속성은 봇의 pseudoPlayer 테이블에 붙지 캐릭터에 붙지 않아
    --   여기서는 읽히지 않는다. GetPlayerFromCharacter 는 같은 함수가 이미 쓰는 방식이다.
    local kingChar = Tool.Parent
    local kingIsBot = kingChar and not Players:GetPlayerFromCharacter(kingChar)
    local botWeight = kingIsBot and BOT_KING_SPLIT_WEIGHT or BOT_SPLIT_WEIGHT

    local weighted = 0
    for _, v in ipairs(batch) do
        weighted += Players:GetPlayerFromCharacter(v) and 1 or botWeight
    end
    swingSplitRaw = math.max(1, weighted)
    swingSplit    = math.min(swingSplitRaw, SPLIT_CAP)
    for _, victimChar in ipairs(batch) do
        applyPushTo(victimChar)
    end
end

-- ── 휘두름 발동 ─────────────────────────────────────────
-- ⚠️ charged=true 면 차징 슬랩(데미지 40 / 넉백 90 / 쿨 7)
--    charged=false 면 기본 슬랩(데미지 5 / 넉백 15 / 쿨 1)
local function swing(aimDirection, charged)
    -- 🛡️ [버그수정 2026-09-11] 스윙이 막히면 차징 상태를 반드시 되돌린다.
    --   [증상] 탈진 버스트가 차징 중에 들어오면 그 뒤로 강타가 영원히 안 나간다.
    --     beginCharge 가 "[Charge] 거부: 차징 쿨 0.0s 남음" 만 반복한다 — 쿨은 이미
    --     지났는데 canCharge 가 false 로 굳은 상태다 (실측 09-11 12:28 판:
    --     12:28:57.5 차징 → 12:28:59.0 버스트 → 그 뒤 강타 0회).
    --   [원인] canCharge 를 true 로 되돌리는 곳은 아래 히트 판정 뒤의 task.delay 두 줄뿐이다.
    --     진입부 가드가 조기 return 하면 그 예약이 통째로 건너뛰어지는데, beginCharge 는
    --     이미 setCanCharge(false) 를 해둔 뒤라 복구자가 세상에서 사라진다.
    --   [왜 가드를 하나씩 안 고치나] 같은 사고가 세 번째다 —
    --     09-08 훈련장(IsRoundLive) / 09-11 탈진(Stunned) / 해머 슬램(PlatformStand).
    --     "막는 곳마다 정리"는 제외 목록이라 가드가 하나 늘 때마다 다시 깨진다.
    --     '막히면 반드시 복구된다'는 결과를 보장하는 쪽으로 뒤집는다.
    --   [쿨 정책] 빗맞힘과 동일하게 CHARGED_COOLDOWN 을 문다. 차징은 실제로 소모됐고,
    --     즉시 복구하면 CC 가 예상되는 순간에 차징을 눌러두는 쪽이 이득이 된다.
    --   ⚠️ 평타(charged=false)는 여기서 아직 canSwing 을 안 내렸으므로 되돌릴 게 없다.
    --   ⚠️ 가드를 새로 추가할 때는 `return end` 가 아니라 `return abortCharged() end` 로 쓸 것.
    local function abortCharged()
        if not charged then return end
        chargeCdUntil = os.clock() + CHARGED_COOLDOWN
        task.delay(CHARGED_COOLDOWN, function() setCanCharge(true) end)
        local ow = getOwner()
        if ow then Remote:FireClient(ow, "ChargeCooldown", CHARGED_COOLDOWN) end
    end
    -- 🔒 [버그수정 2026-09-04] 라운드가 끝났으면 공격이 나가지 않는다.
    --   [증상] 점령 승리로 라운드가 끝난 뒤에도 12초간 계속 때릴 수 있었고,
    --     그때마다 새 킬이펙트가 생겨 endRound 의 연출 대기가 끝나지 않았다.
    --     "분명 졌는데 라운드가 안 끝난다"의 직접 원인이다(실측 23:44 판).
    --   [왜 여기인가] swing 은 슬랩·강타의 공통 진입점이라 한 곳만 막으면 둘 다 걸린다.
    --   ⚠️ _G.IsRoundLive 는 RoundSystem 이 이미 노출해둔 훅이다
    --     ("종료 후 행동 차단용 (아이템 스폰/봇 AI 등)"). 새 규칙을 만들지 않고 그걸 쓴다.
    --   ⚠️ 훅이 없으면(단독 테스트 등) 통과시킨다 — 없다고 무기가 죽으면 안 된다.
    -- ⚠️ [2026-09-08] 훈련장 예외. 이 한 줄이 평타·강타를 둘 다 막고 있었다.
    --   [증상] 로비 훈련장에서 슬랩이 전혀 안 나갔다. 게이트 로그는 전부 통과였고
    --     (owner일치=true / Enabled=true / canSwing=true) swing 까지 도달했는데
    --     여기서 조용히 return 됐다. 훈련장은 인터미션이라 IsRoundLive()=false 다.
    --   [강타도 같은 원인] beginCharge 는 이 검사를 안 타서 차징은 시작되지만,
    --     발동 순간 swing 이 여기서 막힌다. 그래서 "[Charge] 발동" 로그만 찍히고
    --     타격이 없었고, setCanCharge(true) 예약도 안 되어 canCharge=false 로 굳었다
    --     ("차징 쿨 0.0s 남음" 의 정체).
    --   ⚠️ 예외는 WeaponTrialActive 로만 연다. 라운드 종료 후 차단이라는
    --     원래 목적(킬이펙트가 endRound 연출을 막던 버그)은 그대로 유지된다.
    local trialOwner = getOwner()
    local inTrial = trialOwner and trialOwner:GetAttribute("WeaponTrialActive")
    -- 🥊 [훈련장 2026-09-19] 로비 훈련 더미도 예외에 넣는다.
    --   [증상] 반격 더미가 움찔거리기만 하고 슬랩이 안 나갔다(사용자 제보).
    --   [원인] 위 예외는 **플레이어 전용**이다 — WeaponTrialActive 는 Player 속성이고
    --     더미는 getOwner() 가 nil 이라 trialOwner 자체가 없다. 그래서 inTrial=false,
    --     로비는 IsRoundLive()=false → 여기서 조용히 return 됐다.
    --     (앵커 문제가 아니다. 더미 HRP 는 Anchored=false 로 실측 확인)
    --   ⚠️ 09-08 에 같은 게이트가 유저 슬랩을 막았고 같은 방식으로 뚫었다.
    --     **주인 없는 시전자가 또 생기면 여기도 같이 볼 것** — 세 번째다.
    --   [범위] LobbyDummy 속성이 붙은 캐릭터가 든 툴만. 라운드 종료 후 차단이라는
    --     원래 목적은 그대로다(더미는 로비에만 있다).
    local isTrainDummy = Tool.Parent and Tool.Parent:GetAttribute("LobbyDummy") == true
    if not inTrial and not isTrainDummy
       and _G.IsRoundLive and not _G.IsRoundLive() then return abortCharged() end

    -- 🌀 [버그수정 2026-09-05] 에어본/래그돌 중에는 공격이 나가지 않는다.
    --   [증상] 해머 슬램(SLAM_DAMAGE 80)이 태거를 STUN_DURATION 1.2초 띄우는데,
    --     그 동안에도 태거가 슬랩·강타를 그대로 썼다. 실측 제보 —
    --     "에어본 도중임에도 태거가 행동을 계속해서 CC기의 의미가 없다".
    --   [원인] 슬램은 PlatformStand=true 로 CC 를 건다(HammerHighScript:947).
    --     그런데 공격 경로 어디에도 그 상태를 보는 곳이 없었다.
    --     ⚠️ 봇 킹은 특히 심하다 — TaggerBotSystem 전체에 PlatformStand 참조가
    --     하나도 없어서, AI 루프가 공중에 뜬 채로 평소처럼 계속 때린다.
    --   [왜 여기인가] swing 은 슬랩·강타의 공통 진입점이다. 위 라운드 가드와
    --     같은 이유로 한 곳만 막으면 둘 다 걸린다.
    --   ⚠️ 데미지를 막는 게 아니라 '행동'을 막는다. 이미 날아간 스윙은 그대로 둔다.
    --   ⚠️ 이건 CC 를 '작동하게' 만드는 수정이지 새 CC 를 넣는 게 아니다.
    --     STUN_DURATION 1.2초는 원래 설계값이고, 지금까지 실현되지 않았을 뿐이다.
    --   ⚠️ 되돌리려면 이 블록을 지운다. 그러면 예전처럼 CC 중에도 공격이 나간다.
    do
        local ch = Tool.Parent
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum and hum.PlatformStand then return abortCharged() end
        -- ⛓️ [2026-09-05] 왕좌 상실 탈진도 여기서 막는다.
        --   [왜 PlatformStand 가 아닌가] 탈진이 PlatformStand 를 쓰면 소유자가 넷이 되고
        --     (강타 래그돌 / DownSystem / DoubleJump / 탈진), 1초 뒤 무조건 false 로
        --     되돌리면서 남이 세운 래그돌까지 풀어버린다. 실제로 킹의 자세와 이동이
        --     그렇게 깨졌다. 그래서 탈진은 Stunned 속성만 세우고, 차단은 여기서 한다.
        --   ⚠️ Stunned 는 TaggerCcGuard.ccActive 가 이미 읽는 표식이다. 새 속성을 만들지 말 것 —
        --     종류를 나누면 순환 콤보가 성립한다(그쪽 주석 참조).
        if ch and ch:GetAttribute("Stunned") == true then return abortCharged() end
    end
    canSwing = false
    swingStartTime = os.clock()
    hitVictims = {}
    pushDirection = aimDirection
    swingHit = false
    swingCharged = charged and true or false

    -- 클라에 애니메이션 재생 + 짧은 스윙 락만 발신 (쿨다운은 명중 확인 후 결정)
    local owner = getOwner()
    if owner then
        -- ⚠️ 차징 여부를 함께 보낸다. 강타는 더 묵직하게 재생한다.
        Remote:FireClient(owner, "PlaySwing", SWING_LOCK, charged and true or false)
    end

    -- 윈드업 사운드
    local boom = Handle:FindFirstChild("Boom")
    if boom then
        boom.Pitch = math.random(80, 100) / 100
        boom:Play()
    end
    playGrabSound(Handle, GRAB_START_SOUND)   -- 스윙 whoosh (그랩 시작음과 공유, 허공 포함)
    if DIAG_SLAP_SFX then print("[SlapSFX] ⚠️ 기존 whoosh(GRAB_START_SOUND) 재생 — 강타/평타 공통") end

    -- 윈드업 후 히트 검사 (HIT_WINDOW 동안 여러 번), 끝나면 명중 여부로 쿨다운 결정
    task.delay(WINDUP, function()
        -- 💥 [2026-08-28] 강타 발동음을 여기서 낸다. swing() 진입 시점이 아니다.
        --   [증상] 발동음(②)과 명중음(③)이 165ms 어긋나 두 번 친 것처럼 들렸다
        --     (실측 17:48:14.793 → 14.958).
        --   [원인] ②는 swing() 즉시, ③은 WINDUP 뒤 히트 검사에서 났다. 그 간격이 WINDUP 이다.
        --   [해결] ②를 히트 검사 '바로 앞'으로 옮긴다. 첫 검사에서 맞으면 ③이 같은
        --     프레임에 나므로 두 소리가 겹친다.
        --   ⚠️ 헛쳐도 반드시 난다 — 이 줄은 performHitCheck 보다 앞이고 조건이 없다.
        --     아래 while 안으로 옮기지 말 것(검사마다 반복 재생된다).
        --   ⚠️ WINDUP 을 늘리면 소리도 그만큼 늦어진다. 스윙 모션과 어긋나면
        --     여기가 아니라 WINDUP 자체를 봐야 한다.
        if charged then
            playOneShot(Handle, POWER_SLAP_SWING, SWING_VOLUME)
            if DIAG_SLAP_SFX then print("[SlapSFX] ② 발동음 재생 (강타)") end
        end

        local startTime = os.clock()
        pcall(function()
            while os.clock() - startTime <= HIT_WINDOW do
                performHitCheck()
                task.wait(HIT_CHECK_RATE)
            end
        end)
        pushDirection = nil

        if swingHit then
            -- ⚠️ 차징과 기본은 각자의 쿨을 문다.
            if swingCharged then
                chargeCdUntil = os.clock() + CHARGED_COOLDOWN
                canSwing = true   -- 기본 슬랩은 즉시 풀어준다
                if owner then Remote:FireClient(owner, "ChargeCooldown", CHARGED_COOLDOWN) end
                task.delay(CHARGED_COOLDOWN, function() setCanCharge(true) end)
            else
                cooldownUntil = os.clock() + COOLDOWN
                if owner then Remote:FireClient(owner, "Cooldown", COOLDOWN) end
                task.delay(COOLDOWN, function() canSwing = true end)
            end
        else
            -- [2026-09-06] 진단 로그 OFF (위 DUEL_DIAG 와 같은 이유 — 로그 스팸)
            --   빗맞힘은 28일간 1,721건. 되살리려면 아래 false 를 true 로.
            if false then
            warn(string.format("[Duel] %s 빗맞힘 (쿨 %.1fs)",
                swingCharged and "CHARGED" or "SLAP",
                swingCharged and CHARGED_COOLDOWN or WHIFF_COOLDOWN))
            end
            -- 허공 휘두름 → 페널티 쿨다운 (스윙 해소 시점부터 WHIFF_COOLDOWN초 = 실제 대기)
            -- ⚠️ 차징을 헛쳐도 차징 쿨만 문다. 기본 슬랩은 계속 쓸 수 있다.
            local remaining = swingCharged and CHARGED_COOLDOWN or WHIFF_COOLDOWN
            if swingCharged then
                chargeCdUntil = os.clock() + remaining
                canSwing = true
                if owner then Remote:FireClient(owner, "ChargeCooldown", remaining) end
                task.delay(remaining, function() setCanCharge(true) end)
            elseif remaining > 0 then
                cooldownUntil = os.clock() + remaining
                if owner then Remote:FireClient(owner, "Cooldown", remaining) end
                task.delay(remaining, function() canSwing = true end)
            else
                cooldownUntil = 0
                canSwing = true
                if owner then Remote:FireClient(owner, "Ready") end
            end
        end
    end)
end

-- ═══════════════════════════════════════════════════════════
-- ✋ 차징 슬랩
--
-- ⚠️ 곡사포·마법책과 같은 문법이다(꾹 누르면 차징 → 놓으면 발동).
--    태거의 조작 언어를 통일해 배울 것을 줄인다.
-- ⚠️ 차징 중 손이 빛나는 것은 러너에게도 보이는 예고다.
--    예고 없는 강타는 '갑자기 죽었다'가 되어 불쾌하다.
-- ═══════════════════════════════════════════════════════════
local charging        = false
local chargeStartTime = 0
local chargeSessionId = 0
-- 👊 [2026-09-16] 차징 중인 캐릭터를 따로 붙든다.
--   [왜] 아래 세 곳(시작 1984 / 발동 2050 / 취소 2122)이 전부 Tool.Parent 를 그 자리에서
--     읽는다. 그런데 툴이 파괴되는 순간엔 Tool.Parent 가 이미 nil 이라 속성을 되돌릴
--     대상이 없다. vishnuChar 와 같은 이유·같은 형태다(하단 cleanupVishnu 주석 참조).
local chargeChar = nil

-- ⚠️ [재설계 2026-08-25] 홀드 감지에 의존하지 않는다.
--    실측: 버튼을 꾹 눌러도 0.6초마다 MouseButton1Up 이 발동해
--    차징이 계속 끊겼다(로그의 start/stop 반복).
--    → CHARGE_TIME 이 차면 '자동으로' 발동한다. 떼는 걸 기다리지 않는다.
--    곡사포 ProximityPrompt(HoldDuration)와 같은 방식이다.
-- ⚠️ 손을 떼면 releaseCharge 가 '취소'만 담당한다.
local pendingAimDir = nil
-- 🤖 봇 차징 애니 트랙. ⚠️ 재생하는 곳(beginCharge)과 멈추는 곳(발동/취소)이 한 짝이다.
--   안 멈추면 Looped=true 라 차징 자세로 영원히 굳는다.
local botChargeTrack = nil
local function stopBotChargeAnim()
	if botChargeTrack then
		-- ⚠️ [2026-08-30] Stop 전에 AdjustSpeed(1) 로 되돌린다.
		--   beginCharge 가 마지막 프레임에서 AdjustSpeed(0) 으로 얼리므로,
		--   속도를 안 풀고 Stop 만 부르면 차징 자세 그대로 굳는다.
		--   (PushTool.Client 도 같은 이유로 항상 짝으로 처리한다 — 1077행 unfreezeAllTracks)
		pcall(function() botChargeTrack:AdjustSpeed(1); botChargeTrack:Stop(0.1) end)
		botChargeTrack = nil
	end
end

-- ═══════════════════════════════════════════════════════════
-- 🖐️ [2026-09-11] Q 광역 그랩 — 범위 안 러너를 킹 앞으로 끌어온다
--
-- [왜 필요한가] 2단계에 킹이 쓸 수 있는 건 푸시툴 하나뿐이다(F 그랩은 폐기된 잔재).
--   러너는 Q대시 + F웨폰스킬 + 무기 기믹인데 킹만 버튼이 하나고, 그 하나가
--   긴 차징이라 탈진(9.5초마다 1.5초)에 정확히 약하다.
--
-- [진짜 목적은 점령 저지다] 왕복으로는 두 존을 못 막는다 — 실측:
--     킹 편도 46 ÷ 12 = 3.83초   러너 편도 46 ÷ 17 = 2.71초
--   러너가 1.1초 먼저 도착하므로 킹은 영원히 '빈 존'을 쫓는다. 추격이 구조적으로
--   성립하지 않는다. CaptureSystem.step 주석이 이걸 설계로 명시한다
--   ("킹을 왕복시키는 게 러너의 플레이가 된다").
--   → 그랩은 '이동하지 않고 반대 존에 개입하는' 수단이다.
--
-- [값의 근거 — 셋이 서로를 지탱한다. 하나만 바꾸지 말 것]
--   존 실측: 22×22 (반경 11) · 중심간 46 · 가장자리 틈 24  (양 맵 동일)
--   · 사거리 40 : A 중앙 → B 가까운 가장자리가 24+11 = 35 다. 40이면 B '바깥쪽만'
--       닿는다 → 러너 대응이 생긴다("존 안쪽으로 붙어라").
--       ⚠️ 46 이상이면 B 전체를 덮어 왕복이 무의미해지고 점령 승리 경로가 죽는다.
--   · 쿨 20초 : 그랩 1회 = 러너 복귀 1.1초 + 감쇠(4.5/s) ≈ 게이지 6초분 되돌림.
--       목표 18초 안에 0.9회 → "한 번 버티면 두 번째 시도에 성공한다".
--       ⚠️ 12초면 1.5회(되돌림 9)로 점령이 거의 봉쇄된다.
--   · 예열 2.0초 : 17 속도로 34 stud — 사거리 40 밖으로는 못 나가고 존 안쪽으로
--       붙기엔 충분하다. 사거리와 맞물려 대응을 만든다.
--       ⚠️ 예열이 곧 상호작용 창이다(강타 처형 주석의 "구조 창" 과 같은 규칙).
--
-- [데미지 0 인 이유]
--   ① 끌어온 자리가 곧 킹의 사거리라 이미 딜로 이어진다 — 붙이면 두 번 세는 셈
--   ② 축이 흐려진다. 강타·평타는 HP 를 깎고 그랩은 '배치'를 바꾼다
--   ③ √n 분할 적용 여부를 또 정해야 한다. 면제하면 예외가 생기고, 적용하면 무의미.
--      0 이면 이 결정 자체가 사라진다
--   → 피드백은 숫자가 아니라 게이지 하락 + HIT! 표식 + 연출이 맡는다
--   ⚠️ 쳐보고 심심하면 그때 올린다. 0에서 올리는 건 쉽고, 붙여놓고 빼는 건 어렵다
--
-- ⚠️ 봇 킹이 '즉발'로 쓰면 예열 2.0 이 0 이 된다. 강타 처형 주석이 남긴 경고와
--   같은 함정 — beginGrab 경로를 타게 할 것. 솔로에서 러너로 플레이하면 드러난다.
-- ⚠️ 끌어온 지점이 한 점이면 최악이다. 러너가 겹치면 √n 분할이 10명분(12.6)으로
--   걸리고 물리 겹침도 동시에 터진다 → 황금각으로 부채꼴 분산한다.
-- ═══════════════════════════════════════════════════════════
local GRAB_RANGE      = 40      -- stud. 경계값 35(=틈24+반경11)에서 유도
-- 👑 [2026-09-18] 그랩은 KingScale(몸집 강화)의 **적용 대상이 아니다.** 누락이 아니라 의도다.
--   [사실] 판정 3곳(수집·포획·하이라이트)이 전부 GRAB_RANGE 를 날것으로 쓴다.
--     평타·강타는 sMult 를 곱하는데(performHitCheck) 그랩만 안 곱한다 — 그게 맞다.
--   [왜] sMult 를 몸 배율의 절반으로 깎은 근거가 그대로, 더 크게 걸린다:
--       "몸 배율을 그대로 쓰면 강타 사거리 12 → 30 이다. 2단계 존 간 거리가 20~50 이라
--        화면 절반을 덮는 원거리기가 된다"
--     그랩은 **출발점이 이미 40**이다. sMult 1.75(9킬 상한)를 곱하면:
--       사거리 40 → 70   부채꼴 60° → 105°
--     존 하나를 통째로 덮고 전방위에 가까워진다. 강타가 30 에서 기각된 선을 훨씬 넘는다.
--   [결과] 그랩은 0킬이든 9킬이든 40 stud / 60° 로 동일하다.
--     예고(_GrabTelegraph)도 같은 상수를 쓰므로 예고 = 판정이 이미 성립한다.
--   ⚠️ 나중에 "그랩만 안 커지는데 버그 아닌가"를 또 묻게 된다. 답은 여기 있다.
--     바꾸려면 사거리와 부채꼴을 **같이** 재설계할 것 — 배율만 곱하는 건 답이 아니다.
-- 🔻 [밸런스 2026-09-21] 20 → 15. 아래 원주석의 "내리지 말 것"을 **의도적으로 한 단계만** 어긴다.
--   [왜] 태거 이탈 완화 2단계다. 1단계는 ThroneExhaustSystem 의 탈진 버스트 OFF(같은 날).
--     "태거 걸린 애들은 높은 확률로 다음 판 안 하고 이탈한다. 현재 태거 포지션은 그냥
--     동네북"(제작자 관찰 09-20 라이브).
--   [요청값은 10 이었다] 역산표를 놓고 15 로 합의했다. 10 은 되돌림 10.8초라 원주석이
--     "거의 봉쇄"라고 못박은 12초(되돌림 9)보다 **더 아래**다.
--   [역산표] 점령 목표 18초 기준. 되돌림 = 그랩 횟수 × 6초 (원주석 수치 9/13.5 에서 역산).
--       20초 → 0.9회  / 되돌림  5.4 / 유효 점령 12.6   (~09-20. "한 번 버티면 두 번째에 성공")
--       15초 → 1.2회  / 되돌림  7.2 / 유효 점령 10.8   ← 지금
--       12초 → 1.5회  / 되돌림  9.0 / 유효 점령  9.0   "거의 봉쇄" (원주석)
--       10초 → 1.8회  / 되돌림 10.8 / 유효 점령  7.2   (요청됐다 기각)
--        8초 → 2.25회 / 되돌림 13.5 / 유효 점령  4.5   "완전히 불가능" (원주석)
--   ⚠️ 되돌릴 값: 20. 더 내린다면 12 가 다음이자 마지막 한계선이다.
--   ⚠️ 같은 파일 :296 에 **동명의 GRAB_COOLDOWN(4.0)** 이 있다 — 폐기된 옛 로켓펀치 그랩 것이다.
--     실제 소비처(:2085~)는 이 선언보다 아래라 이 값을 읽는다. 위쪽을 고치면 아무 일도 안 난다.
--   ⚠️ 오늘 킹 버프가 둘이다(탈진 OFF + 쿨 20→15). 이탈률이 나아져도 어느 쪽 덕인지
--     이 조합만으로는 못 가른다. 되돌릴 땐 반드시 하나씩.
--   ⚠️ 클라 PushTool.Client 의 realGrabCdTotal 폴백도 같이 15 로 맞췄다(서버가 갱신하지만
--     첫 그랩 전까지의 분모라 값이 조용히 어긋나는 걸 막는다).
local GRAB_COOLDOWN   = 15      -- 초. 목표 18초 안에 1.2회
                                --   ⚠️ [원주석 — 값이 20 이던 시절] 내리지 말 것. 역산표: 쿨 12초면
                                --   1.5회(되돌림 9)로 점령이 거의 봉쇄되고, 8초면 2.25회(13.5)로
                                --   완전히 불가능해진다.  → 09-21 에 15 로 한 단계 내렸다(위 블록 참조).
-- ⏱️ [2026-09-11 개정] 경고와 발동을 분리한다.
--   [왜] 손이 2초에 걸쳐 느릿느릿 나갔다 오니 ① 언제 확정됐는지 모호하고
--     ② 속도 13 stud/s 라 '로켓펀치'의 위력이 안 느껴졌다.
--     옛 그랩은 0.6초에 50 stud(속도 83)였다 — 그게 블리츠크랭크 문법이다.
--   [지금] 1.5초는 경고만(손 없음) → 끝나는 순간 손이 튀어나가 0.8초에 끌고 온다.
--     경고 = 피할 시간 / 발동 = 결과. 역할이 갈려서 러너가 배우기 쉽다.
--   ⚠️ 발사 방향은 '발동 순간'에 확정된다 — 경고 중엔 조준을 고칠 수 있다.
-- ⏱️ [밸런스 2026-09-20] 1.5 → 1.0. 총 1.8초(경고 1.0 + 발동 0.8). 쿨 20초 대비 여전히 무관.
--   ⚠️ AIM_LOCK(0.4) 은 그대로라 조준 추종이 1.1초 → 0.6초로 줄고, 고정 구간 비중이
--     27% → 40% 로 커진다. 러너 보호는 오히려 두터워지는 방향이다 — 의도한 것.
--   ⚠️ 클라 게이지 분모는 GrabBegin 이 보내는 이 값을 쓴다(하드코딩 1.5 제거, 2026-09-20).
--   ⚠️ 되돌릴 값은 1.5.
local GRAB_WINDUP     = 1.0     -- 경고 시간 (러너의 대응 창)
local GRAB_STRIKE     = 0.8     -- 발동 시간. 손이 나갔다 끌고 오기까지
                                --   속도 = 26 / 0.44 ≈ 59 stud/s (옛 그랩 83 에 근접)
local GRAB_PULL_DIST  = 12      -- 킹 앞 몇 stud 에 내려놓나 (겹침 방지용 기준 반경)
local GRAB_MAX_TARGETS = 8      -- 한 번에 끌 최대 인원 (물리 폭주 방지)
local GRAB_GOLDEN     = 137.5   -- 분산 각도 (botAngle 과 같은 이유)

local grabbing       = false
local canGrab        = true
local grabCdUntil    = 0
local grabSessionId  = 0

local function setCanGrab(v)
    canGrab = v
    local ow = getOwner()
    if ow then Remote:FireClient(ow, v and "GrabReady" or "GrabLocked") end
end

-- 🖐️ 그랩 발동 — 범위 안 러너를 킹 앞 부채꼴로 끌어온다.
--   ⚠️ 여기서 데미지를 주지 않는다(상단 주석 [데미지 0 인 이유]).
--   ⚠️ 대상 선별은 isValidTarget 을 재사용한다. 다른 태거·다운자 제외 규칙이
--     푸시툴과 갈리면 "같은 규칙이 두 곳에" 사고가 된다.
local function executeGrab()
    local myChar = Tool.Parent
    local myRoot = myChar and getRootPart(myChar)
    if not myRoot then return end

    -- 범위 안 대상 수집 (가까운 순)
    local found = {}
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m ~= myChar then
            local r = m:FindFirstChild("HumanoidRootPart")
            local h = m:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health > 0 and isValidTarget(m) then
                local d = (r.Position - myRoot.Position).Magnitude
                if d <= GRAB_RANGE then
                    found[#found + 1] = { char = m, root = r, dist = d }
                end
            end
        end
    end
    if #found == 0 then
        print("[Grab] 발동 — 범위 내 대상 없음")
        return
    end
    table.sort(found, function(a, b) return a.dist < b.dist end)

    -- 킹 앞 부채꼴로 분산 배치.
    --   ⚠️ 한 점에 모으면 √n 분할이 최악(12.6)이 되고 물리 겹침도 터진다.
    --     황금각으로 벌려 놓으면 둘 다 완화된다 — botAngle 과 같은 해법.
    local look = myRoot.CFrame.LookVector
    local base = myRoot.Position + Vector3.new(look.X, 0, look.Z).Unit * GRAB_PULL_DIST
    local n = math.min(#found, GRAB_MAX_TARGETS)

    for i = 1, n do
        local t = found[i]
        local ang = math.rad((i * GRAB_GOLDEN) % 360)
        local spread = 4 + (i % 3) * 2.5        -- 4 / 6.5 / 9 stud 링으로 층을 나눈다
        local dest = base + Vector3.new(math.cos(ang) * spread, 0, math.sin(ang) * spread)

        -- ⚠️ CFrame 직접 대입이다. BodyMover 로 끌면 도중에 지형에 끼거나
        --   서로 밀어내면서 솟구친다(봇 넉백 솟구침과 같은 계열의 위험).
        --   "최종 좌표를 직접 확정한다"가 이 프로젝트의 원칙이다.
        local ok = pcall(function()
            t.root.AssemblyLinearVelocity = Vector3.zero
            t.root.CFrame = CFrame.new(dest + Vector3.new(0, 3, 0), myRoot.Position)
        end)
        if ok then
            showHitMark(t.char, false)   -- 💥 피드백. 데미지 숫자가 없으므로 이게 유일한 명중 신호
        end
    end

    print(string.format("[Grab] 발동 → %d명 끌어옴 (범위 내 %d)", n, #found))
end

-- ⚠️ [전방 선언 2026-09-11] makeFlyingHand / playGrabSound 는 옛 그랩 블록(1800행대)에서
--   정의하는데, 아래 playGrabHandFx 가 그보다 앞에서 호출한다.
--   Lua 의 local function 은 정의 지점 이후에만 보이므로 선언이 없으면
--   "attempt to call a nil value" 가 난다.
--   ⚠️ 오늘 같은 사고를 세 번 냈다(updateGrabHud · 클라 HUD · 여기).
--     CaptureSystem 의 setCaptureFx 주석에도 같은 이력이 있다.
--     새 코드를 '기존 함수보다 위'에 넣을 때는 정의 위치부터 확인할 것.
--   ⚠️ playGrabSound 는 388행이라 이미 앞에 있다 — 전방 선언하면 오히려 nil 로 덮는다.
--     "선언이 필요한가"는 정의 위치를 확인하고 판단할 것. 습관으로 붙이지 말 것.
local makeFlyingHand

-- 🖐️ 범위 안 대상 수집 — **전방 부채꼴**. ⚠️ '누가 걸리나'를 정하는 유일한 지점이다.
--   [왜 반경이 아니라 부채꼴인가] 연출은 손이 정면으로 뻗는데 판정이 전방위면
--     "뒤에 있었는데 끌려왔다"가 된다. 대처 불가에 가깝고, 블리츠크랭크식 그랩의
--     문법과도 안 맞는다.
--   [왜 60°인가] 사거리 40 끝에서 좌우 폭이 약 40 stud — 점령 존(22×22) 하나를
--     정확히 덮는 크기다. 즉 "존 하나를 통째로 노린다"가 되고 두 존을 동시에는 못 잡는다.
--     그게 사거리 40 을 정할 때의 의도(왕복 완화하되 없애지 않음)와 맞아떨어진다.
--   ⚠️ 각도는 수평(XZ)으로만 잰다. 계단·단상 높이차로 판정이 갈리면 안 된다.
--   손이 최대로 뻗은 순간에 한 번만 부른다 — 그 뒤 도망쳐도 이미 잡힌 것이다
--   (옛 그랩의 findGrabTarget 도 명중 순간에 확정하고 그 뒤엔 안 바뀐다).
local GRAB_ARC_DEG = 60    -- 전체 각도. 좌우 각 30°
local function captureGrabTargets(myChar, myRoot, forward)
    local cosHalf = math.cos(math.rad(GRAB_ARC_DEG / 2))
    local found = {}
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m ~= myChar then
            local r = m:FindFirstChild("HumanoidRootPart")
            local h = m:FindFirstChildOfClass("Humanoid")
            if r and h and h.Health > 0 and isValidTarget(m) then
                local off = r.Position - myRoot.Position
                local flat = Vector3.new(off.X, 0, off.Z)
                local d = flat.Magnitude
                if d <= GRAB_RANGE and d > 0.1 then
                    -- ⚠️ 바로 앞(거리 3 이내)은 각도 검사를 건너뛴다.
                    --   가까울수록 각도가 민감해져 붙어 있는 대상이 빠지는 게 어색하다.
                    if d <= 3 or flat.Unit:Dot(forward) >= cosHalf then
                        found[#found + 1] = { char = m, root = r, hum = h, dist = d }
                    end
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.dist < b.dist end)
    while #found > GRAB_MAX_TARGETS do table.remove(found) end
    return found
end

-- 🖐️ 최종 배치 — 킹 앞 부채꼴로 흩어 놓는다.
--   ⚠️ 한 점에 모으면 √n 분할이 최악(12.6)이 되고 물리 겹침도 터진다.
--     황금각으로 벌려 놓으면 둘 다 완화된다 — botAngle 과 같은 해법.
local function placeGrabTargets(list, myRoot)
    local look = myRoot.CFrame.LookVector
    local base = myRoot.Position + Vector3.new(look.X, 0, look.Z).Unit * GRAB_PULL_DIST
    for i, t in ipairs(list) do
        if t.root and t.root.Parent then
            local ang = math.rad((i * GRAB_GOLDEN) % 360)
            local spread = 4 + (i % 3) * 2.5        -- 4 / 6.5 / 9 stud 링으로 층을 나눈다
            local dest = base + Vector3.new(math.cos(ang) * spread, 0, math.sin(ang) * spread)
            pcall(function()
                t.root.AssemblyLinearVelocity = Vector3.zero
                t.root.CFrame = CFrame.new(dest + Vector3.new(0, 3, 0), myRoot.Position)
            end)
            showHitMark(t.char, false)   -- 💥 데미지 숫자가 없으므로 이게 유일한 명중 신호
        end
    end
end

-- ✋ [2026-09-11] 예열 연출용 비행 손 — 뻗었다가 돌아온다. (연출 전용, 판정 없음)
--
-- 🚨 [사고 이력 — 반드시 읽을 것] 첫 구현이 맵 전체를 2.6배로 키웠다.
--     local root = hand.Parent:IsA("Model") and hand.Parent or nil   ← 여기가 재앙
--   makeFlyingHand 은 손을 workspace 에 붙이는데, 로블록스에서
--   **Workspace 는 Model 의 하위 클래스다**(Workspace → WorldRoot → Model).
--   그래서 root = workspace 가 됐고 workspace:GetDescendants() 를 전부 곱했다.
--   ⚠️ `:IsA("Model")` 로 "모델인가"를 묻지 말 것. 컨테이너도 참이다.
--     정체 판별은 makeFlyingHand 이 세워둔 `_VishnuHandModel` 속성으로 한다.
--
-- [확대 규칙 — Vishnu 선례를 따른다 (makeFlyingHand 내 1.7배 분기와 같은 형태)]
--   MeshPart → .Size 를 곱한다  /  그 외 → SpecialMesh.Scale 을 곱한다
--   ⚠️ _SkinMesh 가 있으면 clone 은 Transparency=1 이고 보이는 건 skinMesh 다.
--
-- [⏱️ 타임라인 — 손과 끌려오는 것이 반드시 붙어 있어야 한다]
--   실측 23:18 판: 손이 빈손으로 갔다 와서 사라진 '뒤'에 러너가 순간이동했다.
--   "타임라인이 전혀 안 맞고 따로 논다"가 그것이다. 옛 그랩은 phase "in" 에서
--   grabbedRoot 를 손 위치에 매 프레임 붙여 끌고 온다 — 그 구조를 그대로 쓴다.
--     0.00 ~ 0.65×W   손이 나간다
--     0.65×W          ★ 대상 확정(captureGrabTargets) + 잡는 사운드
--     0.65×W ~ W      손이 돌아오며 대상이 따라온다 (CFrame 추종)
--     W               최종 부채꼴 배치 + HIT 표식 → 그 다음에 손 정리
--   ⚠️ 정리(손 삭제)는 배치 '뒤'다. 먼저 지우면 다시 따로 논다.
local GRAB_FX_SCALE = 2.2    -- 연출용 손 배율 (Vishnu 1.7 보다 조금 크게)
local GRAB_FX_REACH = 26     -- 뻗는 거리(stud)

-- 손(또는 Vishnu 모델)의 시각 크기만 키운다. ⚠️ 위 [확대 규칙] 주석 참조.
local function scaleHandVisual(hand, mul)
    local function scaleOne(p)
        if p:IsA("MeshPart") then
            p.Size = p.Size * mul
        else
            local sm = p:FindFirstChildOfClass("SpecialMesh")
            if sm then sm.Scale = sm.Scale * mul else p.Size = p.Size * mul end
        end
    end
    if hand:GetAttribute("_VishnuHandModel") == true then
        -- Vishnu: hand 는 프록시고 형제들이 실제 손이다. 부모 '모델'만 훑는다.
        local model = hand.Parent
        if model then
            for _, p in ipairs(model:GetChildren()) do
                if p:IsA("BasePart") then scaleOne(p) end
            end
        end
        return
    end
    scaleOne(hand)
    -- mesh-swap 스킨: 보이는 건 skinMesh 다(makeFlyingHand 이 clone 을 투명하게 만든다)
    local skin = hand:FindFirstChild("_SkinMesh")
    if skin and skin:IsA("BasePart") then scaleOne(skin) end
end

local function playGrabHandFx(windup)
    local myChar = Tool.Parent
    local myRoot = myChar and getRootPart(myChar)
    if not myRoot then return function() end end

    local ok, hand = pcall(makeFlyingHand)
    if not ok or not hand then
        warn("[GrabFx] 손 생성 실패 — " .. tostring(hand))
        return function() end
    end
    pcall(scaleHandVisual, hand, GRAB_FX_SCALE)

    local isVishnu = hand:GetAttribute("_VishnuHandModel") == true
    -- 🔄 [2026-09-11] 회전 보정은 '일반 Handle 전용'이다.
    --   [실측] VishnuGrabHand 의 파트 3종(Open/Half/Fist)은 전부 euler(0,0,0) —
    --     보정이 필요 없는 정방향으로 제작돼 있다. 거기에 GRAB_HAND_ROT(Z 180°)를
    --     걸면 위아래가 뒤집힌다.
    --   ⚠️ 옛 grab() 도 같은 줄을 쓰므로 원래 있던 버그다. 그랩이 2026-08-25 에
    --     폐기된 뒤 비슈누가 들어와서, 이 경로가 한 번도 실행된 적이 없었다.
    --   ⚠️ 옛 grab() 을 되살릴 일이 생기면 거기도 같이 고칠 것(2138·2230·2277행 근처).
    local handRot = isVishnu and CFrame.new() or GRAB_HAND_ROT

    -- 진짜 Handle 숨김 (손이 떠난 연출). ⚠️ 반드시 되돌린다 — 안 하면 빈손이 된다.
    local savedHandleTr = Handle.Transparency
    local equippedSkin  = Handle:FindFirstChild("_SkinMesh")
    local savedSkinTr   = equippedSkin and equippedSkin.Transparency
    Handle.Transparency = 1
    if equippedSkin then equippedSkin.Transparency = 1 end
    playGrabSound(Handle, GRAB_START_SOUND)

    -- 이동: grab() 의 out/in 루프와 같은 형태.
    -- ⚠️ [2026-09-11 정정] 발사 방향은 **시전 순간**(startGrabTelegraph 가 박아둔
    --   GrabAim) 이다. 예전엔 여기서 발사 시점의 LookVector 를 새로 읽어, 경고는
    --   A 방향인데 실제로는 B 방향을 잡는 일이 생겼다("경고 없는 쪽에서 끌려온다").
    --   [왜 시전 고정인가] 조준 수정이 되면 명중률이 올라가고, 데미지 0 인 저지기가
    --   "끌어서 강타" 콤보 시작기로 성격이 바뀐다. 그리고 마지막 순간에 홱 돌리면
    --   러너의 반응 시간이 0 이 되어 예고가 무의미해진다.
    --   ⚠️ 명중률이 낮아도 괜찮다 — 피하려고 존에서 나가면 게이지가 DECAY 4.5/s 로
    --   깎인다. "나가든 끌려나가든 킹이 이긴다"가 이 스킬의 성립 근거다.
    local ax = myChar and myChar:GetAttribute("GrabAimX")
    local az = myChar and myChar:GetAttribute("GrabAimZ")
    local fwd
    if ax and az then
        fwd = Vector3.new(ax, 0, az)
    else
        local lv0 = myRoot.CFrame.LookVector
        fwd = Vector3.new(lv0.X, 0, lv0.Z)
    end
    fwd = (fwd.Magnitude > 0.001) and fwd.Unit or Vector3.new(0, 0, -1)

    local outT = windup * 0.55
    local inT  = math.max(windup - outT, 0.01)
    local speedOut = GRAB_FX_REACH / outT
    local speedIn  = GRAB_FX_REACH / inT
    local dist, phase = 0, "out"
    local captured = nil        -- 최대 확장 시점에 확정된다
    local conn
    local done = false

    conn = RunService.Heartbeat:Connect(function(dt)
        local r = getRootPart(Tool.Parent or myChar)
        if done or not r or not hand.Parent then return end
        local oPos = r.Position + fwd * GRAB_HAND_START_FWD + Vector3.new(0, GRAB_HAND_HEIGHT, 0)

        if phase == "out" then
            dist = dist + speedOut * dt
            if dist >= GRAB_FX_REACH then
                dist = GRAB_FX_REACH
                phase = "in"
                -- ★ 여기서 대상 확정. 손이 끝까지 뻗은 순간이다.
                --   ⚠️ 그 순간의 fwd 를 넘긴다 — 부채꼴 기준이 '손이 향한 방향'이어야 한다.
                captured = captureGrabTargets(myChar, r, fwd)
                if #captured > 0 then
                    playGrabSound(Handle, GRAB_HIT_SOUND)   -- 잡는 소리
                    -- 끌려오는 동안 제자리 걷기·물리 저항을 막는다.
                    --   ⚠️ PlatformStand 는 반드시 되돌린다(아래 정리 함수).
                    for _, t in ipairs(captured) do
                        if t.hum and t.hum.Parent then t.hum.PlatformStand = true end
                    end
                end
            end
        else
            dist = math.max(dist - speedIn * dt, 0)
        end

        local hp = oPos + fwd * dist
        hand.CFrame = CFrame.lookAt(hp, hp + fwd) * handRot

        -- 🖐️ 회귀 중에는 대상이 손을 따라온다. 옛 grab() phase "in" 과 같은 방식.
        --   ⚠️ 전원을 한 점(손)에 붙이면 겹친다 → 잡힌 순서대로 손 뒤쪽에 줄지어 세운다.
        if phase == "in" and captured then
            for i, t in ipairs(captured) do
                if t.root and t.root.Parent and t.hum and t.hum.Health > 0 then
                    local back = fwd * -(i - 1) * 3.5
                    local side = Vector3.new(-fwd.Z, 0, fwd.X) * (((i % 2) == 0) and 2.5 or -2.5)
                    local p = hp + back + (i > 1 and side or Vector3.zero)
                    t.root.AssemblyLinearVelocity = Vector3.zero
                    t.root.CFrame = CFrame.lookAt(p, p - fwd)
                end
            end
        end
    end)

    return function()
        if done then return end
        done = true
        if conn then conn:Disconnect() end

        -- ⏱️ 최종 배치가 '먼저'다. 손을 먼저 지우면 다시 따로 논다(상단 타임라인 주석).
        local r = getRootPart(Tool.Parent or myChar)
        if captured and #captured > 0 and r then
            for _, t in ipairs(captured) do
                if t.hum and t.hum.Parent then t.hum.PlatformStand = false end
            end
            placeGrabTargets(captured, r)
            print(string.format("[Grab] 발동 → %d명 끌어옴", #captured))
        else
            print("[Grab] 발동 — 범위 내 대상 없음")
        end

        -- ⚠️ Vishnu 는 프록시라 부모 모델을 지운다(cleanup 과 같은 규칙).
        pcall(function()
            if isVishnu and hand.Parent and hand.Parent:IsA("Model") then
                hand.Parent:Destroy()
            else
                hand:Destroy()
            end
        end)
        pcall(function()
            if Handle and Handle.Parent then Handle.Transparency = savedHandleTr end
            if equippedSkin and equippedSkin.Parent then equippedSkin.Transparency = savedSkinTr end
        end)
        -- 📌 시전 방향 표식 제거. ⚠️ 안 지우면 다음 시전이 옛 방향을 읽는다.
        if myChar then
            myChar:SetAttribute("GrabAimX", nil)
            myChar:SetAttribute("GrabAimZ", nil)
        end
        local ow2 = getOwner()
        if ow2 then Remote:FireClient(ow2, "StopGrab") end
    end
end

-- 📣 [2026-09-11] 그랩 예고 연출 — 예열 2.0초 동안만 존재한다.
--   [왜 필수인가] 예열이 안 보이면 러너에게 '순간이동으로 끌려감'이다. 그건 오늘
--     기각한 "대처 불가" 설계와 같아진다(3-3 밀침→소환 콤보의 기각 사유).
--     예열은 시간이 아니라 '보이는 시간'이어야 상호작용 창이 된다.
--   [무엇을 보여주나]
--     ① 바닥 원 — 킹 발밑에 사거리 40 만큼. 커지면서 차오른다 = 남은 시간
--     ② 대상 하이라이트 — 지금 걸려 있는 러너. 범위를 벗어나면 사라진다
--        ⚠️ 0.1초마다 갱신한다. 고정하면 "빠져나갔는데 여전히 표시"가 되어 거짓말을 한다
--   ⚠️ 서버 생성이라 전 클라에 복제된다 — 러너도 본다. 그게 목적이다.
--   ⚠️ 임시 연출이다. 거대손 이펙트가 들어오면 교체할 것.
local function startGrabTelegraph()
    local myChar = Tool.Parent
    local myRoot = myChar and getRootPart(myChar)
    if not myRoot then return function() end end

    -- 🔊 [2026-09-20] 예고음. 시각 예고(부채꼴·하이라이트)와 같은 순간에 시작해
    --   같은 정리 함수에서 끝난다 — 소리와 그림이 한 상태를 공유한다.
    startGrabTelegraphSound(Handle, GRAB_WINDUP)

    -- ① 전방 부채꼴 (판정과 같은 모양이어야 한다)
    --   ⚠️ 원으로 그리면 예고가 거짓말을 한다 — 판정은 60° 부채꼴인데 원을 보여주면
    --     "원 안인데 안 끌려갔다 / 원 밖인데 끌려갔다"가 된다.
    --   [구현] 진짜 부채꼴 메시가 없으므로 얇고 긴 판을 각도별로 깔아 근사한다.
    --     5개면 60°를 12° 간격으로 덮는다. 파트 5개는 0.1초짜리 연출에 부담이 없다.
    local TweenService = game:GetService("TweenService")
    local discs = {}
    local lv0 = myRoot.CFrame.LookVector
    local fwd0 = Vector3.new(lv0.X, 0, lv0.Z)
    fwd0 = (fwd0.Magnitude > 0.001) and fwd0.Unit or Vector3.new(0, 0, -1)

    -- 📏 [2026-09-18] 예고 판을 눕힐 기준 Y — 체격을 가정하지 않는다.
    --   [증상] 봇 킹의 부채꼴 예고가 한 번도 안 보였다(09-18 솔로 7판 전부).
    --   [원인] 옛 상수 -2.8 은 '표준 아바타'를 가정한 값이었다. 실측:
    --     유저 아바타   HRP→발바닥 3.01 → 예고가 바닥 +0.21  (보임)
    --     King npc2     HRP→발바닥 2.33 → 예고가 바닥 -0.47  (완전히 묻힘)
    --     파트 두께 0.2 라 윗면도 바닥 -0.37 — 구조적으로 보일 수 없었다.
    --   [규칙] 체격을 묻지 말고 발바닥을 계산해 그 위에 눕힌다.
    --     "리그가 무엇이든 예고는 바닥 위에 있다" = 새 캐릭터가 와도 안 깨진다.
    --     데몬스피어 법선("무엇을 맞았든 판정원은 바닥에 눕는다")과 같은 형태다.
    --   ⚠️ R6 는 HipHeight 를 0 으로 보고한다 — 실측 Noob·Famer2 둘 다 0(실제 3.00).
    --     R15 만 정확하다(King npc2 오차 0.02 / runnerdummy2 오차 0.00).
    --     그래서 0 이하면 R6 다리 길이 2 로 폴백한다. 이 분기를 지우면 농민봇류가 깨진다.
    --   ⚠️ LIFT 0.2 는 옛 상수가 유저 아바타에서 만들던 여유(+0.21)와 같은 값이다.
    --     유저 킹이 보던 그림은 그대로 두고 봇 킹만 같은 자리로 올라온다 —
    --     즉 이 수정은 봇 킹만 바꾼다. 유저 킹 쪽 회귀는 없다.
    --   ⚠️ 추종 루프(아래 by)도 같은 함수를 쓴다. 한쪽만 바꾸면 예열 중 높이가 튄다.
    local TELEGRAPH_LIFT = 0.2
    local function telegraphY()
        local hum = myChar and myChar:FindFirstChildOfClass("Humanoid")
        local hip = (hum and hum.HipHeight) or 0
        if hip <= 0 then hip = 2 end
        return myRoot.Position.Y - (hip + myRoot.Size.Y * 0.5) + TELEGRAPH_LIFT
    end
    local baseY = telegraphY()

    -- 📌 시전 방향을 캐릭터에 박는다. 발동(playGrabHandFx)이 같은 값을 읽어야
    --   예고·표식·판정 셋이 한 방향이 된다. ⚠️ 정리 함수에서 지운다.
    if myChar then myChar:SetAttribute("GrabAimX", fwd0.X) end
    if myChar then myChar:SetAttribute("GrabAimZ", fwd0.Z) end

    -- 🎯 [2026-09-15] 경고 중 조준 추종 + 후반 잠금.
    --   [왜] 시전 순간 완전 고정이라 조준이 지나치게 빡빡했다(실사용 판단).
    --   [원칙 유지] 예고·표식·판정이 전부 GrabAimX/Z 한 값을 읽는 구조는 그대로다.
    --     여기서 그 값을 갱신하면 부채꼴도 같이 돌기 때문에 09-11 사고
    --     ("예고는 A인데 B를 잡는다")는 재발하지 않는다. 돌리는 건 값 하나뿐이다.
    --   ⚠️ 그래서 부채꼴 파트의 CFrame 도 여기서 같이 돌린다. 안 돌리면
    --     값만 바뀌고 그림이 안 따라와서 정확히 그 사고가 된다.
    --   [후반 잠금] 마지막 AIM_LOCK 초는 고정한다. 문서 경고("마지막 순간에 홱 돌리면
    --     반응 시간이 0")를 지키는 장치다 — 조준은 되지만 최후 순간 회전은 막힌다.
    --   ⚠️ Tween 은 Size 를 돌리는 중이다. CFrame 은 다른 속성이라 동시 대입해도 안전하다.
    local AIM_LOCK   = 0.4                      -- 발동 직전 고정 구간(초)
    local aimDeadline = os.clock() + math.max(0, GRAB_WINDUP - AIM_LOCK)
    local aimConn
    aimConn = game:GetService("RunService").Heartbeat:Connect(function()
        -- 잠금 시점 도달 / 캐릭터 소실 / 파트 정리 → 추종 종료
        if os.clock() >= aimDeadline or not (myChar and myChar.Parent)
           or not (myRoot and myRoot.Parent) then
            if aimConn then aimConn:Disconnect(); aimConn = nil end
            return
        end
        local lv = myRoot.CFrame.LookVector
        local f = Vector3.new(lv.X, 0, lv.Z)
        if f.Magnitude < 0.001 then return end
        f = f.Unit
        myChar:SetAttribute("GrabAimX", f.X)
        myChar:SetAttribute("GrabAimZ", f.Z)

        local by = telegraphY()
        local org = Vector3.new(myRoot.Position.X, by, myRoot.Position.Z)
        for _, d in ipairs(discs) do
            if d.part and d.part.Parent then
                local a = d.ang            -- 부채꼴 내 상대 각도(고정)
                local dir = Vector3.new(
                    f.X * math.cos(a) - f.Z * math.sin(a), 0,
                    f.X * math.sin(a) + f.Z * math.cos(a)
                )
                d.dir = dir                -- 소비처가 dir 을 읽을 수 있으므로 같이 갱신
                -- 📐 [2026-09-18] 중심은 사거리의 절반 지점. 판 길이가 GRAB_RANGE 로
                --   고정됐으므로 여기도 같은 기준이어야 한 끝이 킹에 붙는다.
                --   ⚠️ 예전엔 거리 1 이었다. 그때는 성장 루프가 매 프레임 len/2 로
                --     다시 덮어써서 두 루프가 같은 CFrame 을 놓고 싸웠다. 이제 하나뿐이다.
                local half = GRAB_RANGE / 2
                d.part.CFrame = CFrame.lookAt(org + dir * half, org + dir * (half + 1))
            end
        end
    end)
    -- ⚠️ 어떤 경로로 끝나든 연결을 끊는다. 안 끊으면 라운드가 끝나도 Heartbeat 가 돈다.
    task.delay(GRAB_WINDUP + 0.1, function()
        if aimConn then aimConn:Disconnect(); aimConn = nil end
    end)

    for i = -2, 2 do
        local ang = math.rad(i * 12)
        local dir = Vector3.new(
            fwd0.X * math.cos(ang) - fwd0.Z * math.sin(ang), 0,
            fwd0.X * math.sin(ang) + fwd0.Z * math.cos(ang)
        )
        local p = Instance.new("Part")
        p.Name = "_GrabTelegraph"
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.CanTouch = false
        p.CastShadow = false
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(200, 60, 90)      -- 킹 진영색(크림슨)
        p.Transparency = 0.78
        p.Size = Vector3.new(6, 0.2, GRAB_RANGE)
        p.CFrame = CFrame.lookAt(
            Vector3.new(myRoot.Position.X, baseY, myRoot.Position.Z) + dir * (GRAB_RANGE / 2),
            Vector3.new(myRoot.Position.X, baseY, myRoot.Position.Z) + dir * (GRAB_RANGE / 2 + 1))
        p.Parent = workspace
        -- ⚠️ ang(부채꼴 내 상대 각도)을 같이 저장한다. 조준 추종이 매 프레임
        --   "새 정면 + 이 각도"로 다시 계산하기 때문에 없으면 못 돈다.
        discs[#discs + 1] = { part = p, dir = dir, ang = ang }

        -- 📐 [2026-09-18] 처음부터 완성 범위로 띄운다. 예전엔 GRAB_WINDUP 동안 자랐다.
        --   [왜] 강타 예고는 즉시 완성 사각형인데 그랩만 자라나서 두 스킬의 읽는 법이 달랐다.
        --     자라는 예고는 "지금 이 길이"가 판정인지 "최종 길이"가 판정인지 모호하다 —
        --     러너는 매 순간 다른 도형을 보고 판단해야 했다.
        --   [원칙] 예고·표식·판정은 같은 모양이어야 한다(09-11 그랩 사고에서 세운 것).
        --     판정은 항상 GRAB_RANGE 전체이므로 예고도 처음부터 전체여야 맞다.
        --   ⚠️ 잃는 것: 자라는 길이가 남은 예열 시간을 알려주던 단서가 사라진다.
        --     강타도 그 단서가 없으므로 일관성 쪽을 택했다. 타이밍 표시가 필요하면
        --     길이가 아니라 **다른 축**으로 준다(명도·점멸) — 길이는 판정이 쓰는 축이다.
        --   ⚠️ Tween 과 성장 루프를 함께 제거했다. 그 둘이 조준 추종 루프와 매 프레임
        --     같은 CFrame 을 놓고 싸우고 있었다(한쪽은 거리 1, 다른 쪽은 len/2).
    end

    -- ② 대상 하이라이트 (0.1초마다 갱신)
    --   ⚠️ [2026-09-11 정정] 방향은 **시전 순간의 fwd0 고정**이다. 예전엔 루프 안에서
    --     매번 킹의 현재 LookVector 를 읽어서, 같은 함수 안인데도 부채꼴(고정)과
    --     하이라이트(추종)가 서로 다른 방향을 가리켰다.
    --   [왜 고정인가] 따라다니는 예고는 예고가 아니다. 지상 범위기 예고는 시전 시점에
    --     고정되는 게 표준이고, 안 그러면 킹이 마지막 순간에 홱 돌려 러너의 반응
    --     시간을 0으로 만들 수 있다.
    --   ⚠️ 판정(captureGrabTargets)도 같은 fwd0 를 써야 한다. 셋(예고·표식·판정)이
    --     한 방향이 아니면 UI 가 거짓말을 한다.
    local marks = {}
    local alive = true
    local cosHalf = math.cos(math.rad(GRAB_ARC_DEG / 2))
    task.spawn(function()
        while alive do
            local center = getRootPart(Tool.Parent or myChar)
            if not center then break end
            local cf = fwd0
            local seen = {}
            for _, m in ipairs(workspace:GetChildren()) do
                if m:IsA("Model") and m ~= myChar then
                    local r = m:FindFirstChild("HumanoidRootPart")
                    local h = m:FindFirstChildOfClass("Humanoid")
                    if r and h and h.Health > 0 and isValidTarget(m) then
                        local off = r.Position - center.Position
                        local flat = Vector3.new(off.X, 0, off.Z)
                        local d = flat.Magnitude
                        local inArc = d > 0.1 and d <= GRAB_RANGE
                            and (d <= 3 or flat.Unit:Dot(cf) >= cosHalf)
                        if inArc then
                        seen[m] = true
                        if not marks[m] then
                            local hl = Instance.new("Highlight")
                            hl.Name = "_GrabMark"
                            hl.FillColor = Color3.fromRGB(255, 90, 120)
                            hl.FillTransparency = 0.6
                            hl.OutlineColor = Color3.fromRGB(255, 200, 210)
                            hl.OutlineTransparency = 0
                            -- ⚠️ Occluded. AlwaysOnTop 이면 벽 너머로 비쳐 위치가 노출된다
                            --   (TaggerHpDisplay 의 CcImmuneShield 와 같은 이유).
                            hl.DepthMode = Enum.HighlightDepthMode.Occluded
                            hl.Adornee = m
                            hl.Parent = m
                            marks[m] = hl
                        end
                        end
                    end
                end
            end
            -- 부채꼴을 벗어난 대상은 표식을 지운다 = "빠져나갔다"가 보인다
            for m, hl in pairs(marks) do
                if not seen[m] then
                    hl:Destroy()
                    marks[m] = nil
                end
            end
            task.wait(0.1)
        end
    end)

    return function()
        alive = false
        -- ⚠️ 시각 정리와 같은 자리에서 끈다. 여기가 완료·취소 양쪽이 모이는 유일한
        --   경로다("켜는 코드에 끄는 코드를 같이").
        stopGrabTelegraphSound()
        for _, hl in pairs(marks) do pcall(function() hl:Destroy() end) end
        table.clear(marks)
        for _, d in ipairs(discs) do pcall(function() d.part:Destroy() end) end
        table.clear(discs)
    end
end

local function beginGrab()
    local myChar = Tool.Parent
    -- ⚠️ 탈진 중 금지. beginCharge 와 같은 Stunned 표식을 본다 — 새 CC 종류를 만들지 말 것.
    if myChar and myChar:GetAttribute("Stunned") == true then
        warn("[Grab] 거부: 탈진 중")
        return
    end
    if grabbing then
        warn("[Grab] 거부: 이미 예열 중")
        return
    end
    -- ⚔️ [2026-09-11] 차징 중 그랩 허용. 두 스킬은 독립이다.
    --   [왜 막지 않나] 반대 방향(그랩 중 차징)은 이미 허용돼 있었다. 한쪽만 막으면
    --     플레이어가 배울 규칙이 없는 임의의 비대칭이 된다.
    --   [예고가 겹치지 않는가] 안 겹친다. 차징 예고는 Handle 이 아니라 PushCharging
    --     속성으로 돈다(PushChargeFxViewer). 그랩이 Handle 을 숨겨도 예고 사각형은 남는다.
    --     러너는 부채꼴 + 사각형 두 예고를 동시에 본다 — 판단할 정보가 충분하다.
    --   [자동 균형] 강타가 먼저 터지면 넉백 90 으로 날아간다 → 그 뒤 그랩이 닿으려면
    --     사거리 40 안에 남아 있어야 한다. 실패 여지가 커서 따로 조일 필요가 없다.
    --   ⚠️ 되돌리려면 `if charging then return end` 을 여기 되살린다.
    if not canGrab then
        warn(string.format("[Grab] 거부: 쿨 %.1fs 남음", math.max(0, grabCdUntil - os.clock())))
        return
    end

    grabbing = true
    setCanGrab(false)
    grabSessionId = grabSessionId + 1
    local session = grabSessionId
    if myChar then myChar:SetAttribute("PushGrabbing", true) end

    local ow = getOwner()
    if ow then Remote:FireClient(ow, "GrabBegin", GRAB_WINDUP) end

    -- ✋ 손 애니는 '발동 순간'에 재생한다(아래). 경고 중에는 손이 없다.
    --   ⚠️ 봇은 owner 가 nil 이라 이 경로를 못 탄다 — 봇 손 연출은 별도 과제.

    -- 📣 경고만 시작한다. 손은 아직 안 나간다(상단 타임라인 주석).
    local clearTelegraph = startGrabTelegraph()

    -- ⏳ 경고 GRAB_WINDUP → 발동 GRAB_STRIKE
    task.delay(GRAB_WINDUP, function()
        clearTelegraph()
        if session ~= grabSessionId then return end   -- 중간에 취소/재시도됨
        grabbing = false
        if myChar then myChar:SetAttribute("PushGrabbing", nil) end

        -- ⚠️ 라운드 가드를 두지 않는다. 그랩은 월드에 아무것도 남기지 않으므로
        --   (데미지 0 · 생성물 0 · 남는 건 러너 위치뿐) 로비에서 써도 깨질 게 없다.
        --   ItemSpawnHandler 의 라운드 가드는 "인터미션에 굴린 통나무가 다음 라운드까지
        --   남는다"는 실제 문제를 막는 것이라 성격이 다르다 — 베끼지 말 것.
        --   ✅ 오히려 로비 훈련장에서 연습할 수 있어야 한다. 러너는 WeaponTrialSystem 으로
        --     웨폰 스킬을 시험하는데 태거만 못 하면 일관성이 안 맞고, 태거는 희소 자리라
        --     연습 기회가 더 필요하다. (WeaponTrial 이 이미 PushTool 을 시험 무기로 준다)
        -- ⚠️ 스턴 가드는 남긴다. beginGrab 의 Stunned 거부와 앞뒤가 맞아야 한다.
        -- ⚠️ [2026-09-11] executeGrab 호출 제거. 포획·추종·배치가 전부 손 연출 루프
        --   안으로 들어갔다(playGrabHandFx). 여기서 또 부르면 두 번 끌어온다.
        --   clearHandFx() 가 곧 "최종 배치 + 손 정리"다 — 순서가 그 안에 보장돼 있다.
        local stunned = myChar and myChar:GetAttribute("Stunned") == true
        if stunned or not Tool.Parent then
            print("[Grab] 경고 완료했으나 발동 조건 불충족 (스턴)")
            -- ⚠️ 발동을 안 타면 정리 함수도 안 돈다. 표식을 여기서 지운다.
            if myChar then
                myChar:SetAttribute("GrabAimX", nil)
                myChar:SetAttribute("GrabAimZ", nil)
            end
        else
            -- ★ 발동. 손이 튀어나가 잡고 끌고 온다. 발사 방향은 이 순간에 확정된다.
            local ow2 = getOwner()
            if ow2 then Remote:FireClient(ow2, "PlayGrab", GRAB_STRIKE) end
            local clearHandFx = playGrabHandFx(GRAB_STRIKE)
            task.delay(GRAB_STRIKE, clearHandFx)
        end

        grabCdUntil = os.clock() + GRAB_COOLDOWN
        task.delay(GRAB_COOLDOWN, function() setCanGrab(true) end)
        local ow2 = getOwner()
        if ow2 then Remote:FireClient(ow2, "GrabCooldown", GRAB_COOLDOWN) end
    end)
end

local function beginCharge(aimDirection)
    -- 🚧 [진단 2026-08-25] 조용한 return 이 "모션만 나오는" 증상의 절반이었다.
    --    거부는 드물게만 찍히므로 스팸이 아니다. 릴리즈에도 남길 것.
    -- ⛓️ [2026-09-11] 탈진 중에는 차징 시작 자체를 막는다.
    --   [왜] releaseCharge 의 강제취소 쿨 면제와 한 세트다. 면제만 하면 킹이 버스트
    --     중에 다시 차징할 수 있고, 그게 버스트 끝나기 전에 발동하면 swing 의 Stunned
    --     가드에 막혀 abortCharged 로 5초를 문다 — 면제한 의미가 사라진다.
    --   ⚠️ swing 과 같은 Stunned 표식을 본다. 새 CC 종류를 만들지 말 것.
    if Tool.Parent and Tool.Parent:GetAttribute("Stunned") == true then
        print("[Charge] 거부: 탈진 중")
        -- 🧊 같은 이유로 취소 신호를 보낸다(위 차징 쿨 거부 주석 참조).
        local ow = getOwner()
        if ow then Remote:FireClient(ow, "ChargeCancel") end
        return
    end
    if charging then
        print("[Charge] 거부: 이미 차징 중")
        return
    end
    -- ⚠️ 차징은 자기 쿨만 본다. 기본 슬랩 쿨과 무관하다.
    if not canCharge then
        print(string.format("[Charge] 거부: 차징 쿨 %.1fs 남음", math.max(0, chargeCdUntil - os.clock())))
        -- 🧊 [2026-09-11] 거부를 클라에 알린다. 안 보내면 클라가 이미 재생한 차징 애니가
        --   마지막 프레임에서 얼어 "손 뻗은 자세로 굳는다"가 된다.
        --   ⚠️ 클라에도 가드를 넣었지만(attemptPush) 쿨 종료 직전 경합은 여기서만 막힌다.
        local ow = getOwner()
        if ow then Remote:FireClient(ow, "ChargeCancel") end
        return
    end
    setCanCharge(false)
    charging = true
    chargeStartTime = os.clock()
    chargeSessionId = chargeSessionId + 1
    local session = chargeSessionId
    pendingAimDir = aimDirection
    local myChar = Tool.Parent
    if myChar then myChar:SetAttribute("PushCharging", true) end
    chargeChar = myChar   -- 🧹 툴이 파괴돼도 되돌릴 수 있게 붙든다 (하단 cleanupCharge)
    -- 🔬 [2026-09-16] 차징 '시작'을 찍는다. ⚠️ 릴리즈 전 삭제.
    --   [왜] 지금은 '발동' 로그만 있어서, 로그가 조용할 때 두 가지를 구별할 수 없다 —
    --     (a) 차징을 아예 안 걸었다  (b) 걸었는데 발동 콜백이 죽었다.
    --     09-16 에 그 침묵을 (a)로 읽고 "재현 안 됨"이라 단정했다가 틀렸다.
    --     시작이 찍히면 침묵의 의미가 (b) 하나로 확정된다.
    print("[Charge] 시작")
    local owner = getOwner()
    if owner then Remote:FireClient(owner, "ChargeBegin", CHARGE_TIME) end
    -- 🤖 [2026-08-29] 봇 전용 차징 애니메이션.
    --   [증상] 봇 킹이 강화 슬랩을 써도 모션이 전혀 안 보였다.
    --   [원인] 차징 애니(ChargeR15/ChargeR6)는 PushTool.Client 에서만 재생된다.
    --     LocalScript 는 '도구를 든 플레이어'에게만 실행되므로, 봇에게는
    --     스크립트 자체가 돌지 않아 애니가 로드조차 안 됐다.
    --     이펙트(PushChargeFxViewer)를 고쳐도 모션은 여전히 없는 이유가 이것이다.
    --   ⚠️ 서버 재생 트랙은 가중치·루프가 클라에 복제되지 않는 게 원칙이지만,
    --     봇은 '조종하는 클라이언트가 없어' 서버가 재생하는 것 말고 방법이 없다.
    --     단발 재생이라 가중치 블렌딩이 필요 없어 이 경우엔 성립한다.
    if not owner then
        local h = myChar and myChar:FindFirstChildOfClass("Humanoid")
        local animator = h and h:FindFirstChildOfClass("Animator")
        if animator then
            local isR6 = (h.RigType == Enum.HumanoidRigType.R6)
            local anim = Tool:FindFirstChild(isR6 and "ChargeR6" or "ChargeR15")
            if anim then
                local ok, tr = pcall(function() return animator:LoadAnimation(anim) end)
                if ok and tr then
                    tr.Priority = Enum.AnimationPriority.Action4
                    -- ⚠️ Looped = false. PushTool.Client 와 같은 설정이어야 한다.
                    --   true 로 두면 차징 2초 동안 자세가 반복 재생돼
                    --   "슬랩 뒤에 3연격을 날리는" 것처럼 보인다(실측 제보).
                    tr.Looped = false
                    tr:Play(0.1)
                    botChargeTrack = tr

                    -- 🧊 [2026-08-30] 마지막 프레임에서 얼린다(PushTool.Client:766 과 같은 기법).
                    --   [증상] 봇 킹의 차징 자세가 유저와 달랐다 — '모은 자세'로 멈추지 않고
                    --     애니가 끝나면 스르륵 원 자세로 풀렸다.
                    --   [원인] 프리징(AdjustSpeed(0))이 클라에만 있었다. 봇은 owner 가 nil 이라
                    --     FireClient 경로를 안 타므로 그 코드가 아예 실행되지 않는다.
                    --   ⚠️ 서버가 봇의 네트워크 소유자라 여기서는 지속 제어가 먹는다.
                    --     (플레이어 캐릭터였다면 클라 소유라 이 방식이 안 통한다)
                    --   ⚠️ 얼린 트랙은 반드시 푸는 짝이 필요하다 → stopBotChargeAnim 이 담당한다.
                    --     Stop 전에 AdjustSpeed(1) 로 되돌리지 않으면 그 자세로 굳는다.
                    task.spawn(function()
                        while tr.IsPlaying and botChargeTrack == tr do
                            local len = tr.Length
                            if len > 0 and tr.TimePosition >= len - 0.05 then
                                tr:AdjustSpeed(0)
                                tr.TimePosition = len - 0.01
                                break
                            end
                            RunService.Heartbeat:Wait()
                        end
                    end)
                end
            end
        end
    end
    startChargeSound(Handle)   -- 🔊 차징음 (음원 2.0s = CHARGE_TIME 2.0s)

    -- ⏱️ 다 차면 자동 발동
    task.delay(CHARGE_TIME, function()
        -- 🔴 [2026-09-16] 조기 return 에 복구자를 붙인다.
        --   [증상] 라운드 종료 직전에 강타를 쓰면 예고 사각형이 로비까지 영구히 남았다.
        --   [원인] PushCharging 을 false 로 내리는 코드는 아래 한 곳뿐인데,
        --     이 두 가드에서 튕기면 거기 도달하지 못한다. "해제 코드는 있는데
        --     그 경로에 도달을 못 해서 상태가 고착" — 09-11 에 세 건 고친 그 형태다.
        --   ⚠️ 툴 파괴 훅(cleanupCharge)으로는 못 잡는다. 라운드가 끝나도 PushTool 은
        --     파괴되지 않는다(PUSHTOOL-LOCK 이 재장착하고, RoundSystem 에 제거 코드가 없다).
        --     실측: 종료 후에도 '툴=PushTool(En=true)' 가 계속 찍힌다.
        --   ⚠️ 새 차징이 시작된 경우는 건드리면 안 된다 — 그쪽이 속성의 주인이다.
        --     그래서 세션이 아니라 charging 으로 가른다. 새 차징 중이면 charging=true 라
        --     이 분기에 걸리지 않는다.
        --   ⚠️ 속성 고착은 사각형만의 문제가 아니다. RunnerBotDriveController:1290 의
        --     봇 강타 회피가 같은 속성을 읽어, 다음 라운드 내내 있지도 않은 강타를
        --     피해 옆으로 빠진다 — 그 판의 처치 수·1단계 길이가 조용히 오염된다.
        if chargeSessionId ~= session or not charging then
            if not charging and chargeChar then
                pcall(function() chargeChar:SetAttribute("PushCharging", false) end)
                warn("👊 [Charge] 미발동 차징 — 속성 강제 해제")
                chargeChar = nil
            end
            return
        end
        charging = false
        stopChargeSound()   -- 🔊 인스턴스 정리(소리는 이미 자연히 끝났다)
        local ch = Tool.Parent
        -- ⚠️ [2026-09-08] nil 이 아니라 false. 속성을 '삭제'하면 다음 라운드에
        --   PushChargeFxViewer 가 없는 속성에 GetAttributeChangedSignal 을 걸게 되어
        --   봇 킹의 예고 사각형이 뜨지 않았다(실측). 값만 바꾸고 속성은 남긴다.
        --   소비처 3곳 모두 truthy 검사(`if ... then`)라 false 로 바꿔도 안전하다.
        if ch then ch:SetAttribute("PushCharging", false) end
        chargeChar = nil   -- 🧹 정상 발동 — 붙들 이유가 사라졌다
        -- ⚠️ 클라의 aiming 상태를 풀어준다. 안 그러면 기본 슬랩이 영영 막힌다.
        if owner then Remote:FireClient(owner, "ChargeFired") end
        stopBotChargeAnim()   -- 🤖 봇 차징 애니 정지(발동 경로)
        -- 🤖 [2026-08-29] 봇 발동 타격 애니. 클라(PushTool.Client)는 ChargeFired 에서
        --   AttackR15/R6 을 재생한다 — 봇도 같은 동작을 해야 자세가 맞는다.
        --   ⚠️ 차징 애니를 먼저 멈추고 재생한다. 겹치면 자세가 깨진다(클라 주석과 동일).
        if not owner then
            local ch2 = Tool.Parent
            local h2 = ch2 and ch2:FindFirstChildOfClass("Humanoid")
            local an2 = h2 and h2:FindFirstChildOfClass("Animator")
            if an2 then
                local isR6b = (h2.RigType == Enum.HumanoidRigType.R6)
                local aObj = Tool:FindFirstChild(isR6b and "AttackR6" or "AttackR15")
                if aObj then
                    local okA, tr2 = pcall(function() return an2:LoadAnimation(aObj) end)
                    if okA and tr2 then
                        tr2.Priority = Enum.AnimationPriority.Action4
                        tr2.Looped = false
                        tr2:Play(0.05)
                    end
                end
            end
        end
        print("[Charge] 발동 → 강타 스윙")
        swing(pendingAimDir, true)
    end)
end

-- ✋ 손을 뗐다 = 취소. 발동은 beginCharge 의 타이머가 담당한다.
-- ⚠️ 다 찬 뒤에 떼면 이미 발동했으므로 아무 일도 없다.
local function releaseCharge(aimDirection, forced)
    if not charging then return end
    charging = false
    chargeSessionId = chargeSessionId + 1   -- 예약된 타이머 무효화
    -- 🐛 [버그수정 2026-09-11] 취소해도 차징이 돌아오게 한다. 이게 "강타 영구 봉인"의 본체다.
    --   [증상] `[Charge] 거부: 차징 쿨 0.0s 남음` 이 무한 반복된다. 쿨은 지났는데 막힌다.
    --     실측 14:01 판 — 39.606 차징 → 40.374 탈진 버스트로 취소 → 42.022 거부(0.0s).
    --   [원인] beginCharge 가 setCanCharge(false) 를 먼저 하는데, 되돌리는 코드는
    --     swing() 안쪽의 task.delay 두 줄뿐이다. 그런데 releaseCharge 는 '취소 전용'이라
    --     swing 을 아예 호출하지 않는다 — 발동은 beginCharge 의 타이머가 따로 한다.
    --     그래서 취소되면 canCharge 를 true 로 되돌릴 주체가 세상에서 사라진다.
    --   ⚠️ 탈진 전용 버그가 아니다. 그냥 차징하다 마우스를 떼도 같은 일이 난다.
    --     ChargeRelease(유저 취소) · _G.PushToolCancelCharge(탈진) 둘 다 여기로 들어온다.
    --   [왜 여기인가] 취소 경로의 유일한 통로다. 호출처마다 정리하면 새 호출처가
    --     생길 때 또 깨진다 — 09-11 에 swing 쪽을 먼저 고쳤다가 경로를 잘못 짚었다.
    --   [쿨 정책] 빗맞힘과 동일하게 CHARGED_COOLDOWN. 차징은 실제로 소모됐고,
    --     즉시 복구하면 '눌렀다 떼기'로 아무 비용 없이 상태를 초기화할 수 있게 된다.
    --   ⚠️ swing() 의 abortCharged 와 역할이 겹치지 않는다. 그쪽은 '발동은 됐는데
    --     가드에 막힌' 경로(라운드 종료·에어본·스턴)고, 여기는 '발동 자체가 취소된' 경로다.
    --   [쿨 정책 2026-09-11 정정] 유저가 스스로 뗀 취소만 CHARGED_COOLDOWN 을 문다.
    --     탈진처럼 '강제로 끊긴' 취소는 쿨을 면제한다(forced=true).
    --     [왜] 탈진 1.5초 + 쿨 5초 = 6.5초 무력화라 강제 CC 에 이중 처벌이 됐다.
    --     빗맞힘과 같은 규칙으로 묶은 게 잘못이었다 — 빗맞힘은 선택이고 탈진은 아니다.
    --   ⚠️ 면제하면 킹이 버스트 '중' 에 다시 차징할 수 있게 되는데, 그게 버스트가 끝나기
    --     전에 발동하면 swing 의 Stunned 가드에 막혀 abortCharged 로 5초를 문다.
    --     그래서 beginCharge 쪽에도 Stunned 가드를 세웠다 — 한 세트다.
    if forced then
        setCanCharge(true)
        chargeCdUntil = 0
        local ow = getOwner()
        if ow then Remote:FireClient(ow, "Ready") end
    else
        chargeCdUntil = os.clock() + CHARGED_COOLDOWN
        task.delay(CHARGED_COOLDOWN, function() setCanCharge(true) end)
        local ow = getOwner()
        if ow then Remote:FireClient(ow, "ChargeCooldown", CHARGED_COOLDOWN) end
    end
    stopChargeSound()   -- 🔊 ⚠️ 필수. 여기서 안 끄면 취소해도 차징음이 끝까지 울린다.
    stopBotChargeAnim() -- 🤖 봇 차징 애니 정지(취소 경로). 위 발동 경로와 한 짝.
    local myChar = Tool.Parent
    -- ⚠️ [2026-09-08] nil → false. 위 발동 경로(1109행)와 같은 이유 — 한 짝이다.
    if myChar then myChar:SetAttribute("PushCharging", false) end
    chargeChar = nil   -- 🧹 취소 경로. 위 발동 경로와 한 짝
    local owner = getOwner()
    if owner then Remote:FireClient(owner, "ChargeCancel") end
    -- 🔬 [진단 2026-09-11] "취소했는데 차징 자세가 재시전까지 유지" 추적용. 원인 확정 후 삭제.
    --   경로(탈진 → PushToolCancelCharge → releaseCharge → ChargeCancel → 클라 Stop)가
    --   코드상으로는 안 끊겨 있는데 증상이 남는다. 어느 칸에서 끊기는지 실측한다.
    print(string.format("[ChargeDiag/S] 취소 통보 forced=%s owner=%s",
        tostring(forced == true), owner and owner.Name or "nil(봇)"))
end

-- ⛓️ [2026-09-05] 외부에서 차징을 끊을 수 있게 노출한다. (사용처: ThroneExhaustSystem)
--   [증상] 강타 차징 중에 왕좌 탈진이 걸리면 킹이 차징 자세로 굳고, 탈진 모션이
--     아예 안 보였다. 강타를 다시 쓰면 그제야 풀렸다.
--   [원인] 차징 트랙은 마지막 프레임에서 AdjustSpeed(0) 으로 얼려둔 상태다
--     (위 stopBotChargeAnim 주석 참조). 그 트랙을 안 멈추면 탈진 애니가 그 아래
--     깔려 보이지 않는다. "강타 재시전 시 풀림"은 beginCharge 가 정지를 호출해서다.
--   [왜 releaseCharge 를 그대로 쓰나] 취소에 필요한 네 가지(사운드·애니·속성·클라
--     통보)를 이미 한 곳에서 처리한다. 탈진용으로 따로 만들면 그 중 하나를 빠뜨리고,
--     "같은 규칙이 두 곳에" 사고가 된다.
--   ⚠️ 차징 중이 아니면 releaseCharge 가 스스로 즉시 return 한다. 호출 측이 상태를
--     확인할 필요 없다.
_G.PushToolCancelCharge = function(char)
    if char and Tool.Parent ~= char then return end   -- 다른 캐릭터의 툴이면 무시
    releaseCharge(nil, true)   -- forced: 강제 취소라 쿨 면제 (releaseCharge 주석 참조)
end

-- ── 그랩 스킬 ───────────────────────────────────────────
local taggerSaved = nil  -- 그랩 잠금 전 태거 원래 이동값

local function lockTagger(lock)
    local char = Tool.Parent
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then taggerSaved = nil; return end
    if lock then
        if not taggerSaved then
            taggerSaved = { ws = hum.WalkSpeed, jp = hum.JumpPower, jh = hum.JumpHeight }
        end
        hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0
    else
        if taggerSaved then
            hum.WalkSpeed  = taggerSaved.ws
            hum.JumpPower  = taggerSaved.jp
            hum.JumpHeight = taggerSaved.jh
            taggerSaved = nil
        end
    end
end

-- 러너 스턴: Stunned 속성 + 이동/점프 봉쇄, duration 뒤 복원 (세션 가드로 중복 안전)
local function stunVictim(victimChar, duration)
    local hum = victimChar:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local newId = (stunIds[victimChar] or 0) + 1
    stunIds[victimChar] = newId
    if victimChar:GetAttribute("_PreStunWS") == nil then
        -- ⚠️ 이미 감속(다운 등) 상태면 그 값을 저장하지 않는다.
        --    나중에 복원할 때 감속이 굳어버린다.
        local ws = hum.WalkSpeed
        if ws < 8 then ws = 16 end
        victimChar:SetAttribute("_PreStunWS", ws)
        victimChar:SetAttribute("_PreStunJP", hum.JumpPower)
        victimChar:SetAttribute("_PreStunJH", hum.JumpHeight)
    end
    victimChar:SetAttribute("Stunned", true)
    hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0
    task.delay(duration, function()
        if stunIds[victimChar] ~= newId then return end
        -- ⚠️ [DASH-ESCAPE] 대시로 스턴을 탈출한 경우 그 뒤 속도는 RunnerDive 가 소유한다.
        --    여기서 _PreStunWS(스턴 직전 값, 보통 16)로 되돌리면 대시의 탈진 감속(4)이
        --    풀려 "리스크 없는 탈출"이 된다. 설계 의도는 '스턴에서 벗어나는 것 자체가 보상'이고
        --    탈진 페널티는 그대로 치르는 것이다.
        --    → Exhausted(탈진) 또는 Diving(대시 중)이면 속도 복원을 건너뛴다.
        --      Stunned 플래그와 _PreStun* 정리는 그대로 수행한다.
        local _owner = Players:GetPlayerFromCharacter(victimChar)
        local _dashOwned = _owner ~= nil
            and (_owner:GetAttribute("Exhausted") == true or _owner:GetAttribute("Diving") == true)
        if hum and hum.Parent and not _dashOwned then
            -- ⚠️ [수정 2026-08-25] 저장값을 그대로 복원하면 영구 감속 버그가 난다.
            --    시나리오: 러너가 다운(WalkSpeed 4) → 그 상태로 스턴 →
            --    _PreStunWS 에 4 가 저장됨 → 다운이 먼저 풀려 16 이 됨 →
            --    스턴이 풀리며 4 로 덮어씀. 간헐적인 이유는 두 상태가
            --    겹칠 때만 생기기 때문이다.
            --    → 복원 시점에 현재 상태를 다시 보고 결정한다.
            local saved = victimChar:GetAttribute("_PreStunWS") or 16
            local isDowned = victimChar:GetAttribute("Downed") == true
            if isDowned then
                -- 아직 다운 중이면 다운 속도를 유지한다(DownSystem 이 관리)
                saved = hum.WalkSpeed
            elseif saved < 8 then
                -- 다운이 이미 풀렸는데 저장값이 감속 상태였다면 기본값으로
                saved = 16
            end
            hum.WalkSpeed  = saved
            hum.JumpPower  = victimChar:GetAttribute("_PreStunJP") or 50
            hum.JumpHeight = victimChar:GetAttribute("_PreStunJH") or 7.2
        end
        victimChar:SetAttribute("Stunned", false)
        victimChar:SetAttribute("_PreStunWS", nil)
        victimChar:SetAttribute("_PreStunJP", nil)
        victimChar:SetAttribute("_PreStunJH", nil)
    end)
end

-- 그랩 명중 판정: 앞쪽 박스 안 첫 유효 대상 반환 (푸시 박스 로직 재사용)
-- 손 위치 주변 첫 유효 대상 찾기 (반경 검사)
local function findGrabTarget(pos, ignore)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    local parts = workspace:GetPartBoundsInRadius(pos, GRAB_HAND_RADIUS, params)
    local seen = {}
    for _, part in ipairs(parts) do
        local vc = part:FindFirstAncestorOfClass("Model")
        if vc and not seen[vc] then
            seen[vc] = true
            if vc:FindFirstChildOfClass("Humanoid") and isValidTarget(vc) then
                return vc
            end
        end
    end
    return nil
end

-- 날아가는 손(투사체) 생성: Handle 시각 복제, 웰드/스크립트/히트디텍터 제거
-- ⚠️ local 을 붙이지 않는다 — 위에서 전방 선언했다(playGrabHandFx 가 먼저 호출한다).
function makeFlyingHand()
    -- Vishnu(Ascendant): 3단계 그랩손 (펼침→반쥠→주먹 스왑용 모델). 반환 = 앵커 프록시(PrimaryPart)
    if Tool.Parent and Tool.Parent:GetAttribute("VishnuAura") then
        local SS = game:GetService("ServerStorage")
        local tmpl = SS:FindFirstChild("VishnuGrabHand")
        if tmpl then
            local model = tmpl:Clone()
            local proxy = model.PrimaryPart
            for _, m in ipairs(model:GetChildren()) do
                if m:IsA("BasePart") then
                    m.Anchored = (m == proxy)
                    m.CanCollide = false; m.CanQuery = false; m.CanTouch = false; m.Massless = true
                end
            end
            proxy:SetAttribute("_VishnuHandModel", true)
            model.Parent = workspace
            -- ⚠️ 안전망: 그랩이 비정상 종료되면 손 모델이 영구히 남는다(2026-08-23 실측)
            Debris:AddItem(model, 10)
            return proxy
        end
    end
    local clone = Handle:Clone()
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("Motor6D")
           or d:IsA("JointInstance") or d:IsA("Script") or d:IsA("LocalScript")
           or d.Name == "MeshPart" then
            d:Destroy()
        end
    end
    clone.Name = "_GrabFlyingHand"
    clone.Anchored = true
    clone.CanCollide = false
    clone.CanQuery = false
    clone.CanTouch = false
    clone.Massless = true
    clone.Transparency = 0   -- ★ 복제 시점에 진짜 Handle이 이미 투명(1)이라, 강제로 보이게
    clone.LocalTransparencyModifier = 0
    -- Vishnu(Ascendant): 금색 거대 신의 손 (흰 장갑 → 골드 네온 + 확대)
    if Tool.Parent and Tool.Parent:GetAttribute("VishnuAura") then
        clone.Color = Color3.fromRGB(255, 210, 80)
        clone.Material = Enum.Material.Neon
        if clone:IsA("MeshPart") then
            clone.Size = clone.Size * 1.7
            clone.TextureID = ""
        else
            local sm = clone:FindFirstChildOfClass("SpecialMesh")
            if sm then sm.Scale = sm.Scale * 1.7; sm.TextureId = "" end
        end
    end
    -- mesh-swap skin: the welded _SkinMesh survives the loop but its weld got removed.
    -- Keep the original Handle hidden and re-weld the skin mesh so the flying hand shows the skin.
    local skinMesh = clone:FindFirstChild("_SkinMesh")
    if skinMesh then
        clone.Transparency = 1
        skinMesh.Transparency = 0
        skinMesh.LocalTransparencyModifier = 0
        skinMesh.Anchored = false
        skinMesh.Massless = true
        skinMesh.CanCollide = false
        skinMesh.CanQuery = false
        skinMesh.CanTouch = false
        local w = Instance.new("WeldConstraint")
        w.Part0 = clone
        w.Part1 = skinMesh
        w.Parent = skinMesh
    end
    clone.Parent = workspace
    -- ⚠️ 최후 안전망. 그랩 시퀀스가 정상 종료되면 아래 로직이 즉시 지우지만,
    --    라운드가 중간에 끝나거나 태거가 죽으면 그 분기를 못 타서 손이 영구히 남는다.
    --    (실측 2026-08-23: 라운드 종료 후에도 공중에 손이 떠 있었다)
    --    RoundSystem 의 라운드 종료 청소와 이중으로 막는다.
    Debris:AddItem(clone, 10)
    return clone
end

-- 예상 경로 표시(서버 파트 → 전원에게 보임)
local function makePathIndicator(originPos, forward)
    local p = Instance.new("Part")
    p.Name = "_GrabPath"
    p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.Massless = true
    p.Material = Enum.Material.Neon
    p.Color = Color3.fromRGB(255, 80, 80)
    p.Transparency = 0.5
    p.Size = Vector3.new(0.6, 0.6, GRAB_MAX_RANGE)
    local mid = originPos + forward * (GRAB_MAX_RANGE / 2)
    p.CFrame = CFrame.lookAt(mid, mid + forward)
    p.Parent = workspace
    Debris:AddItem(p, 6)   -- ⚠️ 안전망: 조준선 잔상 방지(그랩 비정상 종료 대비)
    return p
end

-- 피격 러너 리액션 애니메이션 재생 (서버 Animator → 전 클라 복제). 스턴 시간만큼만.
-- [REACT-ANIM-LEAK] 대상별 현재 리액션 트랙. 그랩이 겹치거나 중도 종료돼도 확실히 끄기 위함.
--   ⚠️ 예전엔 task.delay 하나에만 의존했다. Looped=true + Action4 라
--      해제가 새면 걷기·대기 모션을 영구히 눌러 "스턴 모션이 안 풀리는" 상태가 된다.
--      연속 그랩 시 앞 delay 가 뒤 트랙을 끄고 뒤 delay 는 끌 대상을 잃는 구조였다
--      (ODM Gear 의 Grapple_BV 와 동일한 유형).
local reactTracks = {}

local function stopReactAnim(victimChar)
    local t = reactTracks[victimChar]
    if t then
        reactTracks[victimChar] = nil
        pcall(function() if t.IsPlaying then t:Stop(0.15) end end)
    end
end

local function playReactAnim(victimChar)
    local hum = victimChar:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = hum
    end
    -- 이전 트랙이 남아 있으면 먼저 정리(겹침 방지)
    stopReactAnim(victimChar)
    local anim = Instance.new("Animation")
    anim.AnimationId = REACT_ANIM_ID
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    if not ok or not track then return end
    track.Priority = Enum.AnimationPriority.Action4
    track.Looped = true                    -- 탈진(호흡) 루프 — 스턴 동안 반복
    track:Play(0.1, 1, REACT_ANIM_SPEED)   -- 세 번째 인자 = 배속(1.5)
    reactTracks[victimChar] = track
    task.delay(grabStunFor(victimChar), function()
        -- 그 사이 새 그랩이 들어왔으면 그쪽 트랙이므로 건드리지 않는다
        if reactTracks[victimChar] == track then stopReactAnim(victimChar) end
    end)
end

-- ── 블랙홀 그랩 경로 링 (단일 보라색 원형링이 펼쳐지는 연출) ───────────
local RING_SPACING = 7       -- 경로상 링 간격(stud)
local RING_R0      = 0.5     -- 시작 반지름
local RING_R1      = 4.5     -- 펼쳐진 반지름
local RING_THICK   = 0.45    -- 링 두께(바깥-안쪽 반지름)
local RING_HEIGHT  = 0.2     -- 링 띠 깊이(축 방향)
local RING_LIFE    = 0.45    -- 펼침+페이드 시간(초)
local RING_COLOR   = Color3.fromRGB(205, 170, 255)  -- 블랙홀 보라(연하게)
local RING_TRANSP  = 0.55    -- 시작 투명도(클수록 연함/투명, 0~1)

-- 경로 한 지점에 단일 원형링 생성(CylinderHandleAdornment). forward에 수직(손이 통과하는 링)으로 펼쳐지며 사라짐.
local function spawnRingAt(center, forward)
    local TweenService = game:GetService("TweenService")
    -- 링 평면이 forward를 향하도록 보이지 않는 앵커 파트 배치
    local anchor = Instance.new("Part")
    anchor.Size = Vector3.new(0.2, 0.2, 0.2)
    anchor.Transparency = 1
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CastShadow = false
    anchor.CFrame = CFrame.lookAt(center, center + forward)
    anchor.Parent = workspace

    local ring = Instance.new("CylinderHandleAdornment")
    ring.Adornee = anchor
    ring.Angle = 360
    ring.Height = RING_HEIGHT
    ring.Radius = RING_R0
    ring.InnerRadius = math.max(0, RING_R0 - RING_THICK)
    ring.Color3 = RING_COLOR
    ring.Transparency = RING_TRANSP
    ring.AlwaysOnTop = false
    ring.Parent = anchor

    local ti = TweenInfo.new(RING_LIFE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(ring, ti, {
        Radius = RING_R1,
        InnerRadius = math.max(0, RING_R1 - RING_THICK),
        Transparency = 1,
    }):Play()
    game:GetService("Debris"):AddItem(anchor, RING_LIFE + 0.1)
end

-- ── 그랩 발동 (로켓펀치) ────────────────────────────────
local function grab(aimDirection)
    canGrab = false
    grabbing = true
    grabSessionId = grabSessionId + 1
    local session = grabSessionId
    grabCooldownUntil = os.clock() + GRAB_COOLDOWN

    local owner = getOwner()
    local myChar = Tool.Parent
    local taggerRoot = myChar and getRootPart(myChar)
    if not taggerRoot then grabbing = false; lockTagger(false); return end

    -- 발사 방향(수평) 고정 (스킬샷)
    local forward
    if aimDirection then forward = Vector3.new(aimDirection.X, 0, aimDirection.Z) end
    if not forward or forward.Magnitude < 0.001 then
        local lv = taggerRoot.CFrame.LookVector
        forward = Vector3.new(lv.X, 0, lv.Z)
    end
    forward = (forward.Magnitude > 0.001) and forward.Unit or Vector3.new(0, 0, -1)

    lockTagger(true)
    if owner then Remote:FireClient(owner, "PlayGrab", GRAB_COOLDOWN) end
    task.delay(GRAB_COOLDOWN, function() canGrab = true end)

    local function originPos()
        return taggerRoot.Position + forward * GRAB_HAND_START_FWD + Vector3.new(0, GRAB_HAND_HEIGHT, 0)
    end

    -- 진짜 Handle 숨김(손이 떠난 연출)
    local savedHandleTr = Handle.Transparency
    Handle.Transparency = 1
    -- mesh-swap skin: hide the equipped skin mesh too (avoid two hands during grab)
    local equippedSkin = Handle:FindFirstChild("_SkinMesh")
    local savedSkinTr = equippedSkin and equippedSkin.Transparency
    if equippedSkin then equippedSkin.Transparency = 1 end
    playGrabSound(Handle, GRAB_START_SOUND)   -- 그랩 시작 사운드(공통)

    local hand = makeFlyingHand()
    local path = makePathIndicator(originPos(), forward)
    -- Vishnu: 4팔 중 하나 발사 연출 (숨김) + 쥐기 스왑 함수
    local isVishnuHand = hand:GetAttribute("_VishnuHandModel") == true
    local vishnuHiddenArm = nil
    if isVishnuHand and _G.VishnuGrabArmHide then
        vishnuHiddenArm = _G.VishnuGrabArmHide(myChar)
    end
    local function vishnuClench()
        if not isVishnuHand then return end
        local model = hand.Parent
        if not model then return end
        local o = model:FindFirstChild("VishnuHand_Open")
        local h = model:FindFirstChild("VishnuHand_Half")
        local f = model:FindFirstChild("VishnuHand_Fist")
        task.spawn(function()
            if o and h then o.Transparency = 1; h.Transparency = 0 end
            task.wait(0.07)
            if h and f then h.Transparency = 1; f.Transparency = 0 end
        end)
    end

    -- 블랙홀 스킨 전용: 손이 지나가는 길마다 보라색 원형링이 펼쳐짐.
    local isBlackhole = Handle:FindFirstChild("BlackHoleVFX") ~= nil
    local lastRingDist = -math.huge

    local grabbedChar, grabbedRoot, grabbedHum = nil, nil, nil
    local savedColl = nil

    local cleaned = false
    local conn
    local function cleanup()
        if cleaned then return end
        cleaned = true
        if conn then conn:Disconnect() end
        if hand then
            if isVishnuHand and hand.Parent and hand.Parent:IsA("Model") then hand.Parent:Destroy() else hand:Destroy() end
        end
        if vishnuHiddenArm and _G.VishnuGrabArmShow then _G.VishnuGrabArmShow(vishnuHiddenArm) end
        if path then path:Destroy() end
        if Handle and Handle.Parent then Handle.Transparency = savedHandleTr end
        if equippedSkin and equippedSkin.Parent then equippedSkin.Transparency = savedSkinTr end
        if savedColl then
            for p, was in pairs(savedColl) do
                if p and p.Parent then p.CanCollide = was end
            end
        end
        if grabbedHum and grabbedHum.Parent then grabbedHum.PlatformStand = false end
        if grabbedRoot and grabbedRoot.Parent then pcall(function() grabbedRoot:SetNetworkOwnershipAuto() end) end
        -- [REACT-ANIM-LEAK] 리액션 애니도 여기서 확실히 끈다.
        --   카타나 카운터·바리케이드 차단 등으로 그랩이 중도 종료되면
        --   task.delay 만으로는 안 꺼져 스턴 모션이 남는다.
        if grabbedChar then stopReactAnim(grabbedChar) end
        grabbing = false
        lockTagger(false)
        if owner then Remote:FireClient(owner, "GrabEnd") end
    end

    -- 안전 정리: 어떤 경로로든 무조건 종료 (태거 영구 빙결/투사체 잔존 방지)
    task.delay(GRAB_OUT_TIME + GRAB_IN_TIME + 0.5, function()
        if grabSessionId == session then cleanup() end
    end)

    local speedOut = GRAB_MAX_RANGE / GRAB_OUT_TIME
    local speedIn  = GRAB_MAX_RANGE / GRAB_IN_TIME
    local dist = 0
    local phase = "out"

    conn = RunService.Heartbeat:Connect(function(dt)
        if grabSessionId ~= session or not taggerRoot.Parent then cleanup(); return end
        local oPos = originPos()

        if phase == "out" then
            dist = dist + speedOut * dt
            local handPos = oPos + forward * dist

            -- ⚠️ 바리케이드 차단: 손이 벽을 뚫고 나가 벽 너머 러너를 끌어오는 문제.
            --    벽이 멀쩡한데 관통하면 "부술 이유"가 사라져 바리케이드 시스템이 무의미해진다.
            --    (태거 입장에서도 안으로 끌어와봐야 이득이 없어 의도된 플레이가 아님)
            --    → 발사점~손 사이에 부서지지 않은 바리케이드가 있으면 거기서 회수 단계로 전환.
            do
                local bp = RaycastParams.new()
                bp.FilterType = Enum.RaycastFilterType.Exclude
                bp.FilterDescendantsInstances = { myChar, hand, path }
                local seg = handPos - oPos
                if seg.Magnitude > 0.5 then
                    local r = workspace:Raycast(oPos, seg, bp)
                    if r and r.Instance.Parent and r.Instance.Parent.Name == "Barricades" then
                        -- 벽면 바로 앞에서 손을 멈추고 되돌린다
                        dist = math.max((r.Position - oPos).Magnitude - 1, 0)
                        local stopPos = oPos + forward * dist
                        hand.CFrame = CFrame.lookAt(stopPos, stopPos + forward) * GRAB_HAND_ROT
                        phase = "in"
                        if path then path:Destroy(); path = nil end
                        return
                    end
                end
            end

            hand.CFrame = CFrame.lookAt(handPos, handPos + forward) * GRAB_HAND_ROT
            -- 손이 지나간 자리에 보라색 원형링이 펼쳐짐 (블랙홀 스킨 전용, 진행형)
            if isBlackhole and (dist - lastRingDist) >= RING_SPACING then
                lastRingDist = dist
                spawnRingAt(handPos, forward)
            end
            if not grabbedChar then
                local hit = findGrabTarget(handPos, {myChar, hand, path})
                if hit then
                    local vRoot = getRootPart(hit)
                    local vHum  = hit:FindFirstChildOfClass("Humanoid")
                    if vRoot and vHum then
                        grabbedChar, grabbedRoot, grabbedHum = hit, vRoot, vHum
                        stunVictim(hit, grabStunFor(hit))
                        -- 만화풍 헤롱헤롱 별 링: 전 클라가 자기 화면에서 렌더
                        local dz = ReplicatedStorage:FindFirstChild("StunDizzyEffect")
                        if dz then dz:FireAllClients(hit, grabStunFor(hit)) end
                        playReactAnim(hit)   -- 피격 리액션 애니(1.5배속)
                        pcall(function() vRoot:SetNetworkOwner(nil) end)
                        vHum.PlatformStand = true
                        savedColl = {}
                        for _, p in ipairs(hit:GetDescendants()) do
                            if p:IsA("BasePart") and p.CanCollide then
                                savedColl[p] = true; p.CanCollide = false
                            end
                        end
                        playGrabSound(Handle, GRAB_HIT_SOUND)   -- 그랩 성공 사운드(공통)
                        vishnuClench()   -- Vishnu: 펼침→반쥠→주먹 쥐기 스왑
                        print(string.format("[PushTool] %s가 %s를 그랩(로켓펀치)", myChar.Name, hit.Name))
                    end
                    phase = "in"
                end
            end
            if dist >= GRAB_MAX_RANGE then phase = "in" end
            -- ★ 손이 끝까지 뻗는 순간(명중/최대사거리) 예상 경로 즉시 제거
            if phase == "in" and path then path:Destroy(); path = nil end
        else
            dist = dist - speedIn * dt
            local handPos = oPos + forward * math.max(dist, 0)
            hand.CFrame = CFrame.lookAt(handPos, handPos + forward) * GRAB_HAND_ROT
            if grabbedRoot and grabbedRoot.Parent and grabbedHum and grabbedHum.Health > 0 then
                grabbedRoot.CFrame = CFrame.lookAt(handPos, handPos - forward)
            end
            if dist <= 0 then
                if grabbedRoot and grabbedRoot.Parent then
                    local endPos = oPos + forward * GRAB_HOLD_DIST
                    grabbedRoot.CFrame = CFrame.lookAt(endPos, endPos - forward)
                    -- Vishnu(Ascendant): 스턴 동안 금색 주먹이 피해자를 계속 쥐고 있는 연출
                    if myChar and myChar:GetAttribute("VishnuAura") and hand then
                        local grip
                        if isVishnuHand and hand.Parent and hand.Parent:IsA("Model") then
                            local f = hand.Parent:FindFirstChild("VishnuHand_Fist")
                            if f then grip = f:Clone(); grip.Transparency = 0 end
                        else
                            grip = hand:Clone()
                        end
                        if grip then
                            for _, w in ipairs(grip:GetChildren()) do if w:IsA("WeldConstraint") or w:IsA("Weld") then w:Destroy() end end
                            grip.Anchored = true
                            grip.Name = "_VishnuGripHand"
                            grip.CFrame = CFrame.lookAt(endPos, endPos + forward) * GRAB_HAND_ROT
                            grip.Parent = workspace
                            -- ⚠️ 안전망: 그랩 중 라운드가 끝나면 이 손이 남는다
                            Debris:AddItem(grip, 10)
                            local vroot = grabbedRoot
                            local gconn
                            gconn = RunService.Heartbeat:Connect(function()
                                if vroot.Parent and grip.Parent then
                                    grip.CFrame = CFrame.new(vroot.Position) * (grip.CFrame - grip.CFrame.Position)
                                end
                            end)
                            task.delay(grabStunFor(hit), function()
                                if gconn then gconn:Disconnect() end
                                if grip and grip.Parent then grip:Destroy() end
                            end)
                        end
                    end
                end
                cleanup()
            end
        end
    end)
end

-- ── 이벤트 처리 ─────────────────────────────────────────
-- ── 태거 봇(서버) 액션 훅 ─────────────────────────────
-- TaggerBotSystem이 BotAction:Fire(action, aimDirection)으로 스윙/그랩 구동.
-- Remote 경로(유저)와 동일 검증·실행. owner(Player) 검증만 없음 — 봇은 Player가 아님.
-- swing/grab 내부 FireClient는 전부 owner nil 가드가 있어 봇 장착 시 안전.
local BotAction = Tool:WaitForChild("BotAction")
BotAction.Event:Connect(function(action, aimDirection)
    local myChar = Tool.Parent
    if myChar and myChar:GetAttribute("Stunned") then return end
    -- [MICBOMB-SEAL] 봇은 BindableEvent 로 직접 발동하므로 Tool.Enabled 를 거치지 않는다.
    --   그 탓에 마이크밤 콘서트 중에도 킹이 푸시를 성공시켰다
    --   (실측 2026-08-20: 콘서트 52.181~60.185 구간의 59.552 에 PUSH 명중).
    --   Enabled 를 여기서 직접 존중해 도구 봉인이 봇에게도 먹히게 한다.
    if not Tool.Enabled then return end
    local validDir = nil
    if typeof(aimDirection) == "Vector3" then
        local mag = aimDirection.Magnitude
        if mag > 0.01 and mag < 1e6 then validDir = aimDirection end
    end
    if action == "Push" then
        -- ⚠️ [2026-08-30] 차징 중엔 기본 슬랩이 나가지 않는다.
        --   [증상] 봇 킹이 차징하는 도중에 평타가 함께 나갔다
        --     (실측 09:43:17.140 차징 시작 → 17.557 SLAP 명중 → 19.156 강타 발동).
        --   [원인] 유저 경로(Remote, 아래 action == "Push")엔 이 가드가 있는데
        --     봇 경로(BotAction)에만 빠져 있었다. 같은 규칙이 두 곳에 필요한데 한쪽만 적용된 사례다.
        --   ⚠️ 두 경로는 앞으로도 짝으로 유지할 것. 한쪽에 규칙을 추가하면 다른 쪽도 확인한다.
        if charging then return end
        if not canSwing then return end
        swing(validDir, false)
    elseif action == "ChargedPush" then
        -- ⏳ [2026-08-29] 봇도 차징 경로를 탄다. 예전엔 swing(dir, true) 즉발이었다.
        --   [증상] 봇 킹의 강화 슬랩에 애니·이펙트가 안 나와 러너가 대응할 수 없었다.
        --   [왜 중요한가] 이건 연출 문제가 아니라 설계 전제였다.
        --     위 '다운자 처형' 블록의 주석이 명시한다 —
        --     "봇 킹이 강타를 '즉발'로 쓰는 한 이 설계는 성립하지 않는다.
        --      예열이 없으면 예고 없이 다운자가 지워져 구조 창이 0이 된다."
        --     예열 2.0초가 있어야 아군이 부활(홀드 1.5초)을 시도할 창이 생긴다.
        --   [해결] beginCharge 를 부른다. CHARGE_TIME 이 차면 자동 발동하므로
        --     봇이 '떼는' 동작을 흉내 낼 필요가 없다(유저도 같은 방식이다).
        --     차징 사운드·손 발광·PushChargeFxViewer 예고가 전부 따라온다.
        --   ⚠️ canSwing 이 아니라 canCharge 를 본다. 차징은 자기 쿨만 본다(beginCharge 주석).
        --     여기서 canSwing 을 검사하면 기본 슬랩 쿨에 묶여 강타가 안 나간다.
        beginCharge(validDir)
    elseif action == "Grab" then
        -- 🖐️ [2026-09-18] 봇 경로 부활. 09-11 에 Q 광역 그랩을 되살리면서
        --   유저 경로(Remote, action == "Grab")만 beginGrab() 으로 바꾸고
        --   이 봇 경로는 08-25 폐기 상태(return)로 남아 있었다.
        --   [증상] 봇 킹이 그랩을 한 번도 못 썼다. TaggerBotSystem 은 그랩 조건을
        --     판정(거리 40, grabChance, lookAt 조준)한 뒤 Fire("ChargedPush") 로
        --     쏘고 있었으므로 실제로 나간 건 강타였다. 그랩 사거리에서 강타가
        --     발사되니 대부분 허공이었고, 부채꼴 예고도 안 나왔다
        --     (예고는 beginGrab 안에 있고 서버가 그린다 — 봇/유저 구분 없음).
        --   [근거] 이 파일 위쪽 주석이 미리 경고해 둔 그 지점이다 —
        --     "봇 킹이 '즉발'로 쓰면 예열 2.0 이 0 이 된다. beginGrab 경로를 타게 할 것.
        --      솔로에서 러너로 플레이하면 드러난다." 2026-09-18 솔로 4판에서 드러났다.
        --   ⚠️ 유저 경로와 같은 함수를 인자 없이 부른다. beginGrab 은 시전 순간의
        --     캐릭터 정면(fwd0)을 예고·표식·판정 셋에 공통으로 쓰므로, 봇도 발사 직전
        --     lookAt 으로 몸을 돌려야 방향이 맞는다
        --     (TaggerBotSystem 의 [BOT-GRAB-RANGE] 분기가 이미 그렇게 한다).
        --   ⚠️ TaggerBotSystem 의 Fire("Grab") 과 짝이다. 한쪽만 고치면 안 바뀐다 —
        --     위 [MICBOMB-SEAL] 주석이 남긴 "같은 규칙이 두 곳에" 교훈과 같다.
        beginGrab()
    end
end)

Remote.OnServerEvent:Connect(function(player, action, aimDirection)
    -- 🔬 [진단 2026-09-08] 훈련장 슬랩이 안 나가는 원인 추적.
    --   증상: PushTool 지급·장착은 됐는데(로그 확인) 평타가 전혀 안 나가고,
    --         강타는 한 번 나간 뒤 "차징 쿨 0.0s 남음" 으로 계속 거부됐다.
    --   여기서 갈린다: 요청이 서버에 오긴 하는가 / 어느 게이트에서 막히는가.
    --   ⚠️ 원인 확정 후 이 블록을 지울 것.
    if PUSH_DIAG then
        local mc = Tool.Parent
        warn(string.format("🔬 [Push] 수신 action=%s | owner일치=%s | Stunned=%s | Enabled=%s",
            tostring(action),
            tostring(player == getOwner()),
            tostring(mc and mc:GetAttribute("Stunned")),
            tostring(Tool.Enabled)))
        warn(string.format("🔬 [Push]   canSwing=%s canCharge=%s charging=%s | Tool.Parent=%s",
            tostring(canSwing), tostring(canCharge), tostring(charging),
            mc and mc.Name or "nil"))
    end
    if player ~= getOwner() then return end

    -- 카타나 카운터로 스턴 중이면 아무 동작 불가
    local myChar = Tool.Parent
    if myChar and myChar:GetAttribute("Stunned") then return end

    -- aimDirection 검증(공용)
    local validDir = nil
    if typeof(aimDirection) == "Vector3" then
        local mag = aimDirection.Magnitude
        if mag > 0.01 and mag < 1e6 then validDir = aimDirection end
    end

    if action == "Push" then
        if charging then return end   -- 차징 중엔 기본 슬랩이 나가지 않는다
        if not canSwing then
            local now = os.clock()
            if now < cooldownUntil then
                Remote:FireClient(player, "Cooldown", cooldownUntil - now)
            end
            return
        end
        swing(validDir, false)
        if _G.VishnuSwing then _G.VishnuSwing(myChar) end   -- Vishnu: 4팔 랜덤 스윙

    elseif action == "ChargeBegin" then
        -- ✋ 차징 시작. 클라가 버튼을 누르고 있는 동안.
        beginCharge(validDir)

    elseif action == "ChargeRelease" then
        -- ✋ 손을 뗐다. 충분히 찼으면 강타가 나간다.
        releaseCharge(validDir)

    elseif action == "Grab" then
        -- 🖐️ [2026-09-11] 폐기됐던 "Grab" 액션을 Q 광역 그랩이 이어받는다.
        --   [옛 주석] "2026-08-25 그랩 폐기. 차징 슬랩이 그 자리를 대신한다.
        --              코드는 남겨두되 호출만 끊는다."
        --   그 잔재(lockTagger / taggerSaved / GRAB_START_SOUND)가 B-4 로 미결에 올라
        --   있었는데, 새 스킬이 같은 자리에 들어오면서 리모트 분기는 재사용된다.
        --   ⚠️ 옛 그랩 로직(단일 대상 붙잡기)은 여전히 죽은 코드다. 별건으로 정리할 것.
        beginGrab()
    end
end)

-- ── 장착/해제 ───────────────────────────────────────────
local autoPushActive = false

local function startAutoPush()
    if autoPushActive then return end
    autoPushActive = true
    task.spawn(function()
        local PUSH_INTERVAL = 3  -- 고정 간격(초) — 카운트다운 예측 가능하게

        -- 더미 머리 위 카운트다운 표시 만들기
        local function ensureTimerGui(char)
            local head = char:FindFirstChild("Head")
            if not head then return nil end
            local gui = head:FindFirstChild("PushTimerGui")
            if not gui then
                gui = Instance.new("BillboardGui")
                gui.Name = "PushTimerGui"
                gui.Size = UDim2.fromScale(4, 1.2)
                gui.StudsOffset = Vector3.new(0, 3.5, 0)
                gui.AlwaysOnTop = true
                gui.Parent = head
                local lbl = Instance.new("TextLabel")
                lbl.Name = "Label"
                lbl.Size = UDim2.fromScale(1, 1)
                lbl.BackgroundTransparency = 1
                lbl.Font = Enum.Font.GothamBold
                lbl.TextScaled = true
                lbl.TextColor3 = Color3.fromRGB(255, 230, 80)
                lbl.TextStrokeTransparency = 0
                lbl.Text = ""
                lbl.Parent = gui
            end
            return gui:FindFirstChild("Label")
        end

        while autoPushActive and Tool.Parent do
            local char = Tool.Parent
            if char and char:GetAttribute("AutoPush") then
                local lbl = ensureTimerGui(char)
                -- PUSH_INTERVAL 동안 카운트다운 표시
                local t = PUSH_INTERVAL
                while t > 0 and autoPushActive and Tool.Parent do
                    if lbl then lbl.Text = string.format("PUSH IN %.1f", t) end
                    task.wait(0.1)
                    t = t - 0.1
                end
                if not (autoPushActive and Tool.Parent) then break end
                -- 푸시!
                if lbl then lbl.Text = "PUSH!" end
                if canSwing then swing(nil) end
                task.wait(0.3)
            else
                task.wait(0.3)
            end
        end
        -- 정리: 타이머 GUI 제거
        if Tool.Parent then
            local head = Tool.Parent:FindFirstChild("Head")
            local gui = head and head:FindFirstChild("PushTimerGui")
            if gui then gui:Destroy() end
        end
        autoPushActive = false
    end)
end

local vishnuChar = nil   -- Vishnu 스킨 부착된 캐릭터 (해제 시 정확한 참조용)
Tool.Equipped:Connect(function()
    canSwing = true
    canGrab = true
    grabbing = false
    hitVictims = {}
    -- Vishnu 스킨: 광배+4팔 부착
    local char = Tool.Parent
    local plr = char and game:GetService("Players"):GetPlayerFromCharacter(char)
    if plr and _G.getEquippedSkin and _G.getEquippedSkin(plr, "PushTool") == "Vishnu" and _G.VishnuAttach then
        vishnuChar = char   -- 해제 시 정확한 캐릭터 참조용
        _G.VishnuAttach(char)
    end
    -- 테스트 더미용 자동 휘두름
    if Tool.Parent and Tool.Parent:GetAttribute("AutoPush") then
        startAutoPush()
    end
end)

Tool.Unequipped:Connect(function()
    hitVictims = {}
    autoPushActive = false
    -- Vishnu 스킨: 광배+4팔 제거 + 원본 팔 복원 (장착 시 저장한 캐릭터 사용 — Tool.Parent는 이미 백팩으로 이동)
    if _G.VishnuRemove and vishnuChar then _G.VishnuRemove(vishnuChar); vishnuChar = nil end
    -- 그랩 정리: 세션 무효화(핀 루프 자동 종료·복원) + 태거 잠금 해제
    grabSessionId = grabSessionId + 1
    grabbing = false
    lockTagger(false)

    -- ⚠️ [PUSHTOOL-LOCK] 태거의 주먹은 해제할 수 없다 — 유일한 근접 수단이라
    --    실수로 내려두면 아무것도 못 하는 상태가 된다(러너 무기와 달리 대안이 없다).
    --    Unequipped 직후 다시 쥐여 준다.
    --    ⚠️ 라운드가 끝나 툴이 회수되는 중이거나 사망/다운 상태면 재장착하지 않는다.
    --       그때 붙잡으면 정리가 막히거나 다운 연출이 깨진다.
    --    ⚠️ 같은 프레임에 EquipTool 을 부르면 Unequipped 와 충돌하므로 한 틱 미룬다.
    task.defer(function()
        local _p = Tool.Parent
        if not _p then return end
        -- ⚠️ Backpack 의 부모가 Player 다. Character 로 찾으면 안 된다.
        local plr = nil
        if _p:IsA("Backpack") then
            plr = _p.Parent and _p.Parent:IsA("Player") and _p.Parent or nil
        else
            plr = Players:GetPlayerFromCharacter(_p)
        end
        if not plr then return end
        -- ⚠️ [2026-09-08] 훈련장 체험 중에는 강제 재장착을 하지 않는다.
        --   이 잠금은 '태거가 유일한 근접 수단을 잃지 않게' 하는 장치인데,
        --   체험장에서는 무기를 자유롭게 바꿔야 하므로 붙잡으면 교체가 막힌다.
        --   (Blacksmith 로 다른 무기를 골라도 주먹이 다시 손에 쥐어진다)
        if plr:GetAttribute("WeaponTrialActive") then return end
        if plr:GetAttribute("Role") ~= "Tagger" then return end
        local char = plr.Character
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not (hum and hum.Health > 0) then return end
        if char:GetAttribute("Downed") then return end
        pcall(function() hum:EquipTool(Tool) end)
    end)
end)

print("✅ PushTool Server 활성화 (쿨다운:", COOLDOWN, "초, 넉백:", PUSH_VELOCITY, ", 후한 영역 판정)")

-- ═══════════════════════════════════════════════════════════
-- 🕉️ [버그 수정 2026-08-26] Vishnu 스킨 잔존.
--
-- [증상] 라운드가 끝나도 광배와 4팔이 캐릭터에 남았다.
-- [원인] _G.VishnuRemove 호출부가 Tool.Unequipped 하나뿐이었다.
--   라운드 종료로 툴이 통째로 제거되면 Unequipped 가 오지 않는다.
--   (같은 날 애니 포즈 굳음도 완전히 같은 원인이었다 — 클라이언트 쪽)
-- [해결] 툴이 사라지는 모든 경로에서 뗀다.
--
-- ⚠️ vishnuChar 는 장착 시 저장해둔 캐릭터다. Tool.Parent 는 이 시점에
--   이미 백팩이거나 nil 이라 쓸 수 없다.
-- ⚠️ 붙이는 코드(_G.VishnuAttach)가 있으면 떼는 코드도 같은 짝으로 있어야 한다.
--   경로가 늘면 여기도 함께 늘릴 것.
-- ═══════════════════════════════════════════════════════════
local function cleanupVishnu(reason)
    if _G.VishnuRemove and vishnuChar then
        pcall(function() _G.VishnuRemove(vishnuChar) end)
        print("🕉️ [Vishnu] 제거 — " .. reason)
        vishnuChar = nil
    end
end

-- 👊 [2026-09-16] 차징 속성 고착 해제. 바로 위 cleanupVishnu 와 같은 짝이다.
--   [증상] 라운드 종료 직전에 차징하면 강타 예고 사각형이 로비까지 따라와 영구 잔존.
--   [원인] 발동 경로의 task.delay(CHARGE_TIME) 가 이 툴 스크립트 소유 스레드다.
--     라운드 종료로 툴이 회수되면 그 예약이 콜백째 회수돼
--     SetAttribute("PushCharging", false) 가 실행되지 않는다. 에러도 안 남는다.
--     (로그 대조: 라운드 종료 뒤 [Charge] '발동' 줄이 아예 없다 = 예약이 안 돌았다)
--     위 Vishnu 잔존과 완전히 같은 원인·같은 형태다.
--   ⚠️ 눈에 보이는 사각형만의 문제가 아니다. RunnerBotDriveController:1290 의
--     봇 강타 회피가 이 속성을 읽는다. true 로 고착되면 다음 라운드 내내 봇들이
--     있지도 않은 강타를 피해 옆으로 빠진다 — 그 판의 처치 수·1단계 길이가
--     조용히 오염된다. 측정값을 망가뜨리는 쪽이 더 큰 피해다.
--   ⚠️ Tool.Parent 는 이 시점에 이미 nil 이다. 반드시 chargeChar 를 쓸 것.
--   ⚠️ Unequipped 는 일부러 안 건다 — PUSHTOOL-LOCK 이 즉시 재장착하므로
--     여기서 끄면 정상 차징을 취소해버린다. 툴이 '사라지는' 경로만 잡는다.
local function cleanupCharge(reason)
    if chargeChar then
        pcall(function() chargeChar:SetAttribute("PushCharging", false) end)
        print("👊 [Charge] 속성 해제 — " .. reason)
    end
    chargeChar = nil
    charging = false
    chargeSessionId = chargeSessionId + 1   -- 살아남은 예약이 있어도 세션으로 무효화
end

-- 툴이 workspace/캐릭터에서 완전히 빠질 때 (라운드 종료 회수 포함)
Tool.AncestryChanged:Connect(function(_, parent)
    if parent then return end
    cleanupVishnu("툴 제거")
    cleanupCharge("툴 제거")
end)

Tool.Destroying:Connect(function()
    cleanupVishnu("툴 파괴")
    cleanupCharge("툴 파괴")
end)

-- 태거가 죽거나 리스폰될 때도 뗀다 (툴이 남아 있어도 몸은 바뀐다)
do
    local ch = Tool.Parent
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.Died:Connect(function() cleanupVishnu("태거 사망") end)
    end
end
