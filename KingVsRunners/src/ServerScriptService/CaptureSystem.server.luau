-- ═══════════════════════════════════════════════════════════════
-- CaptureSystem — 2단계 왕좌 점령
--
-- [왜] 2단계에 목표가 없었다. 무기를 쥐여주지만 "뭘 하라"는 규칙이 없어
--      러너는 숨고(시간초과가 러너 승리라 그게 이득) 태거는 도망만 다녔다.
--      양쪽 다 '싸우지 않는 게 이득'이라 PvP 가 열리지 않았다.
--
-- [해법] 점령 지점을 두고, 러너가 그 안에서 일정 시간을 채우면 승리.
--   · 러너에게 목표가 생긴다 → 무기가 "저기 가는 길을 뚫는 도구"로 설명된다
--   · 태거는 도망칠 수 없다 → 자리를 비우면 점령당한다
--   · 둘이 같은 자리에서 만난다 → 여기서 비로소 PvP 가 성립한다
--
-- [진행 방식] 감쇠형(누적도 초기화도 아님)
--   ⚠️ 초기화형은 다수 러너의 릴레이로 무력화된다(A 가 끊기면 B 가 들어감).
--   ⚠️ 누적형은 태거의 개입이 '지연'일 뿐이라 결국 뚫린다 — 방어에 의미가 없다.
--   → 감쇠형이면 태거가 그 자리를 계속 지켜야만 하고(떠나면 도로 차오름),
--      러너도 완전히 좌절하지 않는다(남은 데서 재개).
-- ═══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── 튜닝 상수 (전부 여기 모아둔다) ─────────────────────────────
-- ⏳ [밸런스 2026-08-31] 목표 10 → 15초.
--   [실측] 킹이 존에 도달조차 못 하는 판이 나왔다(23:01 라운드).
--     '라인 하강' 23:01:09.7 → '점령 완료' 23:01:30.8 = 21초 동안 킹은 계속 싸웠지만
--     상대는 전부 AI 러너(_4/_5/_6/_8/_9)였고, 점령한 건 유저였다.
--     즉 "AI 가 킹을 붙잡고 유저 하나가 존에 선다"로 뚫린다.
--   [왜 감쇠로는 안 막히나] 감쇠는 존을 '떠날 때'만 걸린다. 킹이 묶여 있으면
--     러너는 떠날 이유가 없어 감쇠가 한 번도 발동하지 않는다.
--   [왜 목표 시간인가] 킹의 성문(741) → 존(815) 이동이 74 stud / 속도 14 = 5.3초다.
--     10초면 도착 후 4.7초밖에 안 남아 AI 를 끊어낼 여유가 없다. 15초면 9.7초가 남는다.
--     백도어의 '성격'은 그대로 두고 '커밋 시간'만 늘리는 방식이라,
--     "잠깐 빠져나가 밟기"가 "확실히 떼어놓고 버티기"가 된다.
--   ⚠️ [DECAY_RATE 와의 결합] 감쇠는 절대값(1.5/초)이라 목표가 커지면 상대적으로 약해진다.
--     강타 넉백 1회가 지우는 양: 목표 10 일 때 33% → 목표 15 일 때 22%.
--     감쇠/상승 비율(1.5)은 그대로라 "떠난 시간 대비 손실"은 불변이다.
--     넉백 억제력을 원래대로 유지하려면 DECAY_RATE 를 2.25 로 올려야 한다 —
--     다만 두 값을 같이 바꾸면 원인 분리가 안 되므로 이번엔 목표만 만진다.
--   ⚠️ 모든 참조가 이 파일 안에 있고 클라에는 비율(progress/CAPTURE_GOAL)로 나가므로
--     이 값만 바꾸면 UI·봇 판정이 전부 따라온다. 다른 곳에 10 을 하드코딩하지 말 것.
--   ⚠️ [되돌림 2026-09-01] 15 → 10. 위 15초 실험은 폐기한다.
--     15 로 올린 뒤 킹이 존에 도달할 여유는 생겼지만, 같은 세션에 들어간
--     KING_POWER 8 · 리시 클램프 · 감쇠 1.5 가 이미 점령을 충분히 늦췄다.
--     실측(11:29 판)은 아예 timeout(태거 승리)까지 갔다 — 목표 시간까지 늘리면
--     점령이 승리 경로로서 성립하지 않는다.
-- 🔺 [밸런스 2026-09-04] 10 → 18. 2단계 목표 길이(30~40초)에 맞춘 조정.
--   [실측 근거] 14:47 판 분해 — 성문 붕괴 → 첫 존 도달 8.1초, 채우기 13.8초, 합 22.2초.
--     이동 8.1초는 맵 구조라 못 건드리므로 채우기를 늘려 목표에 맞춘다.
--     18 이면 채우기 24.8초 → 2단계 총 32.9초로 30~40초 구간에 들어온다.
--   [왜 이 방향인가] 앞서 세 번(체크포인트 / 감쇠 / 존 안 데미지) 전부 같은 이유로 막혔다 —
--     "킹이 뭔가 해내야" 작동하는 조건이라 다수 상대로는 도달 불가능했다.
--     실측: 22초 내내 존 인원이 0 이 된 적이 없어 감쇠 분기가 한 번도 안 돌았다.
--     목표 시간은 조건 없이 무조건 걸린다. 2존 분산도 각 존이 18초를 채워야 하니 같이 완화된다.
--   ⚠️ 이건 "킹이 막을 수 있게"가 아니라 "점령이 오래 걸리게"다. 커버리지 문제
--     (몸 하나로 존 둘을 못 막음)는 그대로 남아 있다. 대신 전투 경로(실측 33.1초)와
--     시간이 비슷해져 "점령 = 전투가 가망 없을 때의 대안"이라는 원래 의도에 가까워진다.
--   ⚠️ [이전 되돌림과 조건이 다르다] 09-01 에 15 를 시도했다가 timeout 까지 가서 되돌린
--     기록이 있는데, 그때는 봇이 점령을 하지 않던 시절이라 유저 혼자 존을 밟는 상황이었다.
--     지금은 봇 10마리가 두 존을 미는 조건이라 전제가 완전히 다르다.
local CAPTURE_GOAL      = 18.0   -- 점령 완료까지 필요한 누적(초)
local FILL_RATE         = 1.0    -- 러너가 있을 때 초당 상승
-- 🔺 [밸런스 2026-09-04] 1.0 → 2.5. 위 50행 주석이 예고한 미완 조정을 완성한다.
--   [예고] "넉백 억제력을 원래대로 유지하려면 DECAY_RATE 를 2.25 로 올려야 한다 —
--     다만 두 값을 같이 바꾸면 원인 분리가 안 되므로 이번엔 목표만 만진다."
--     CAPTURE_GOAL 15→10 되돌림과 짝이었는데 그때 미뤄둔 값이다.
--   [왜 지금] 실측(13:46 판)에서 킹이 25초간 슬랩·강타를 계속 명중시켰는데
--     게이지에 아무 영향이 없었다. 킹의 확실한 수단은 데미지가 아니라 넉백인데
--     (러너 5명이면 rate +0.235 로 존에 서 있어도 계속 찬다), 떼어내도 보상이 없었다.
--     → 새 메커니즘을 만들지 않고, 이미 가진 수단에 값을 붙인다.
--   [왜 2.5 인가] CHECKPOINT_STEP 과 같은 값이다. 슬랩이 만드는 1초 공백 = 정확히
--     한 눈금. "밀어낸 만큼 지운다"가 성립하고, 과잉은 체크포인트가 자른다.
--     (예고값 2.25 보다 0.25 높은 건 눈금과 정렬시키기 위해서다)
--   ⚠️ 소수 러너 보호는 인원 함수가 아니라 체크포인트가 한다. 09-01 의 실패
--     ("1.5 는 과해서 솔로가 아예 못 이겼다")는 눈금이 하한을 잡아 재발하지 않는다.
--     한 번에 최대 한 구간(25%)만 날아간다.
--   ⚠️ 감쇠는 '존이 완전히 비었을 때만' 작동한다(아래 감쇠 분기). 이 변경의 효과는
--     킹이 존에 가서 전원을 밀어냈을 때만 나온다 — 5명을 동시에 사거리에 넣고
--     밀 수 있는지는 아직 실측이 없다. 다음 판에서 갈린다.
local DECAY_RATE        = CAPTURE_GOAL * 0.25   -- 비었을 때 초당 감쇠 (= 눈금 1칸/초)

-- 🏁 [재도입 2026-09-02] 체크포인트. 25% 눈금 아래로는 '자연 감쇠'가 내려가지 않는다.
--   [폐기했다가 되돌린 경위]
--     ① 처음엔 이 형태(경합 중엔 눈금 무시)로 넣었다.
--     ② "킹이 있으면 눈금이 안 통한다"는 예외가 UI 를 거짓말하게 만들어 완전 잠금으로 바꿨다.
--     ③ 완전 잠금은 착취를 열었다 — 존을 떠나 킹을 밀어내러 가도 진행이 안 줄어
--        건틀렛·해머로 손쉽게 승리(23:47 판, 충전 0.61/s = 자리를 비웠다는 뜻).
--     ④ 그래서 통째로 제거했다. 그랬더니 이번엔 CC 무기로도 승리 불가가 됐다
--        (21:32 판, 세 번 시도 전부 "2% 시작 → 소진". 최고 50% 도달 후 전부 소멸).
--     ⑤ 결론: ①이 맞았다. 다만 그때는 킹 이속 버프가 없어 경합 자체가 안 일어났고,
--        그래서 이 규칙이 작동하는 걸 볼 수가 없었다. 조건이 바뀌었으니 판단도 바뀐다.
--   [규칙] 빈 존이 스스로 식을 때만 눈금에서 멈춘다. 킹이 밟고 있으면 눈금을 무시하고 되돌린다.
--   [왜 이 형태인가] "떠나도 잃지 않지만, 킹에게 붙잡히면 잃는다."
--     여러 번 시도한 성과가 누적돼 재도전이 의미를 갖고(실측: 매번 0부터라 50% 가 최고 기록),
--     동시에 킹의 존 방어는 여전히 되돌리기로 작동한다.
--   ⚠️ 이 규칙은 킹이 존에 도달할 수 있을 때만 균형이 잡힌다. 킹 이속 버프
--     (TaggerBotSystem.ZONE_RUSH_SPEED)와 한 짝이다 — 한쪽을 빼면 다른 쪽이 무너진다.
local CHECKPOINT_STEP   = CAPTURE_GOAL * 0.25   -- 목표의 25% (항상 4칸)
-- 🔻 [밸런스 2026-09-02] 1.5 → 1.0. 존별 게이지(zoneProgress) 도입에 맞춘 조정.
--   [왜] 1.5 는 전역 게이지 시절 값이다. 존별이 되면서 같은 벌이 존마다 따로 걸려
--     실질 강도가 올라갔다. 실측: 솔로가 태거 존재 시 점령 승리 불가능에 가까워졌다.
--     A→B 이동 3.3초에 5.0 손실 = 채우기 5초치. 왕복이 순손실이라 혼자서는
--     '왕복으로 못 이긴다'가 아니라 '아예 못 이긴다'가 됐다 — 의도 초과였다.
--   [왜 0.5 가 아닌가] 0.5 는 2026-08-31 에 실측으로 기각된 값이다(아래 주석).
--     넉백 왕복 2.2초에 11% 밖에 안 지워져 존 방어에서 넉백이 무의미했다.
--     1.0 이면 22% 라 넉백 벌이 살아 있고, 솔로 이동 비용은 5.0 → 3.3 으로 내려간다.
--   ⚠️ 이 값만 만졌다. FILL_RATE·CAPTURE_GOAL·KING_POWER·CONTEST_NEUTRAL 은 그대로다 —
--     존별 전환과 감쇠를 동시에 재려면 변수를 하나만 움직여야 원인이 분리된다.
-- ⚠️ 예전 가드레일: "감쇠가 상승과 같거나 크면 감쇠형의 의미가 없다(초기화형이 된다)".
--    이 가드레일은 TAGGER_BLOCKS 시절(킹이 존을 완전 차단)에 쓰였다. 그때는 킹이 서 있으면
--    게이지가 멈추므로 감쇠까지 세면 러너가 아무것도 못 했다. 지금은 킹이 감속만 하고
--    러너가 존에 있는 한 게이지가 계속 오르므로, 그 전제가 깨졌다. 그래서 상승을 넘긴다.
--
-- 🔺 [밸런스 2026-08-31] 감쇠 0.5 → 1.5.
--   [왜] 넉백이 점령 방어에서 작동하지 않았다. 강타 넉백 18 stud 는 존 반폭 11 을
--     확실히 넘기는데, 러너가 걸어 돌아오는 왕복 2.2초 동안 0.5/s 로는 11% 밖에 안 지워졌다.
--     "넉백이 게임의 척추"인데 점령에서만 척추가 없었던 셈이다.
--     1.5 면 강타 한 방이 진행의 33% 를 지운다 — 미는 행위가 곧 방어가 된다.
--   ⚠️ [무엇이 죽고 무엇이 사는가] 감쇠는 '존을 떠날 때만' 걸린다. 그래서:
--     · 정직한 백도어(몰래 들어가 계속 서 있기) — 10초 그대로. 설계 의도라 건드리지 않는다.
--     · 존 왕복(A↔B 튕기기) — 46 stud 이동 2.9초에 4.35 소모. 사실상 불가능해진다.
--     · 툭 밟고 빠지기 — 즉시 증발.
--     즉 착취 패턴만 골라 죽고 의도한 전술은 남는다. 이게 KING_POWER_REMOTE 안보다
--     나은 이유다 — 그쪽은 정직한 백도어까지 30초로 늘려 게릴라를 둔하게 만든다.
--   ⚠️ 아직 안 풀린 것: 러너 둘이 각 존에 하나씩 서서 안 움직이면 감쇠가 한 번도 안 걸리고,
--     킹 없는 존은 bestRate 규칙상 항상 1.0 이라 10초에 끝난다. 그건 별개 과제다.
--   ⚠️ 유예 시간이 없다. 밀려난 순간부터 바로 깎인다. 너무 가혹하면 여기에 0.3~0.5초
--     유예를 넣는 게 값을 되돌리는 것보다 낫다(넉백 억제력은 유지되므로).

-- ⚠️ [2026-08-25] 완전 차단 폐기. 아래 KING_POWER 로 감속한다.
--    이 값은 호환을 위해 남기지만 더 이상 게이지를 멈추지 않는다.
-- ⚔️ [밸런스 2026-08-30] 킹 방해력 강화: KING_POWER 2 → 4, MIN_FILL_RATE 0.25 → 0.15
--   [왜] 2단계 진입 = 사실상 점령 확정이었다. 실측 2판 모두 킹 HP 가 절반도 안 깎인 채
--     점령으로 끝났다(907 → 417 / 457). 킹이 존을 지켜도 러너를 늦추지 못했다.
--   ⚠️ 두 값은 한 세트다. MIN_FILL_RATE 는 하한 클램프인데, KING_POWER 가 2 일 땐
--     최저 배율이 0.33 이라 하한(0.25)에 한 번도 닿지 않아 사실상 죽은 값이었다.
--     KING_POWER 만 올리면 이 하한이 곧바로 새 병목이 되어 강화 효과가 잘린다.
--   [결과] 킹이 존 위에 있을 때 — 1명 50초 / 2명 30초 / 3명 23초 / 5명 18초 (킹 없으면 10초)
--   ⚠️ 더 세게: KING_POWER 를 올린다. 약하게: 4 → 3. 하한만 만지면 소수 인원만 영향받는다.
-- ⚔️ [밸런스 2026-08-31] KING_POWER 4 → 8.
--   [왜] 4 로는 킹이 러너 1명만 감당했다. 존 위 킹 기준 처치 시간과 비교하면
--     1명: 점령 50초 vs 처치 13.3초 → 킹 승 / 2명: 30초 vs 16.3초(광역 동시타)~29.6초(순차) → 러너 승
--     이동 5.3초(성문 741 → 존 815, 속도 14)를 빼면 2명부터 사실상 확정 패배였다.
--   [8 에서] 1명 66.7초 / 2명 50초 / 3명 36.7초 / 4명 30초 / 5명 26초.
--     2~3명 구간에서 킹이 처치할 시간이 나온다. 5명 이상은 여전히 러너 우세 —
--     다수면 존을 내주는 게 맞으므로 의도된 결과다.
--   ⚠️ [하한이 이제 실제로 작동한다] 위 2026-08-30 주석이 경고한 그 일이다.
--     1명일 때 원식은 1/(1+8) = 0.111 인데 MIN_FILL_RATE 0.15 에 걸려 잘린다
--     (66.7초. 하한이 없으면 90초였다). KING_POWER 2·4 시절엔 한 번도 안 닿던 값이다.
--     더 세게 하려면 KING_POWER 가 아니라 MIN_FILL_RATE 를 내려야 한다 — 이제 그쪽이 병목이다.
local KING_POWER        = 8      -- 킹 1명의 방해력(러너 N명분)
local MIN_FILL_RATE     = 0.15   -- ⚠️ [2026-09-01 폐기] 하한 클램프. CONTEST_NEUTRAL 로 대체돼
                                 --    더 이상 참조되지 않는다. 값 이력 보존용으로만 남긴다.
-- ⚔️ [2026-09-01] 킹 접전 시 진행/되돌림이 갈리는 균형점.
--    rate = 러너수/(러너수+KING_POWER) − CONTEST_NEUTRAL 이므로,
--    인원비율이 이 값보다 낮으면 rate 가 음수가 되어 게이지가 되돌아간다.
--    0.15 → 1명(0.111)은 되돌림, 2명(0.20)부터 아주 느리게 진행.
--  ⚠️ 올리면 다수 구간까지 급격히 느려진다. 분모(러너수+8)가 커서 작은 오프셋도
--    전 구간에 영향이 간다 — 0.20 이면 2명 정지, 5명 26초 → 54초.
--    되돌리려면 이 값만 0 으로 두면 예전(하한 없는) 거동이 된다.
local CONTEST_NEUTRAL   = 0.15   -- 킹 접전 시 진행/되돌림 분기점

-- 🎤❄️ [2026-09-01] 태거가 CC 상태면 점령이 거의 안 찬다.
--   [왜] 위 KING_POWER 감속은 '킹이 존 근처에 있을 때'만 걸린다. 마이크밤(8초)이나
--     아이스보우로 킹을 성문 앞에 묶어두면 존은 무주공산이 되어 rate 가 1.0,
--     즉 목표 10초가 그대로 나온다. CC 한 번이 곧 점령 확정이었다.
--   [값] 0.1 → 환산 100초. 마이크밤 8초로 8%, 아이스보우 3초로 3% 만 진행한다.
--   ⚠️ 양수일 때만 곱한다. 킹이 존 안에서 CC 당한 경우 rate 는 이미 음수(되돌림)인데
--     거기 0.1 을 곱하면 되돌리는 속도까지 느려져 오히려 러너에게 유리해진다.
--   ⚠️ 속성이 두 개다. 아이스보우=Frozen, 마이크밤=MicBombed 로 서로 다르다
--     (MicBombSystem 400행: Frozen 을 재사용하면 그쪽 8초 안전망이 콘서트 8초와
--     겹쳐 봉인한 Tool 을 멋대로 복구한다). 둘 중 하나라도 켜져 있으면 CC 로 본다.
local CC_FILL_MULT      = 0.1    -- CC 중 점령 상승률 배수

-- 태거(유저·봇)가 지금 CC 중인가.
local function taggerIsCC()
    local Players = game:GetService("Players")
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr:GetAttribute("Role") == "Tagger" then
            if plr:GetAttribute("Frozen") then return true end
            local c = plr.Character
            if c and (c:GetAttribute("Frozen") or c:GetAttribute("MicBombed")) then return true end
        end
    end
    -- 👑 봇 킹은 Player 가 없다. workspace 의 Model 을 Role 속성으로 찾는다
    --    (FirePressureSystem.forEachTagger 와 같은 규약 — 이름 하드코딩보다 안전).
    --    ⚠️ GetPlayerFromCharacter 가드 필수. 유저 태거 캐릭터가 위 루프와 중복으로 잡힌다.
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("Role") == "Tagger"
           and not Players:GetPlayerFromCharacter(m) then
            if m:GetAttribute("Frozen") or m:GetAttribute("MicBombed") then return true end
        end
    end
    return false
end
local TAGGER_BLOCKS     = true   -- 태거가 존 안에 있으면 점령 정지
-- ⚠️ 태거가 '막는' 방식이 이 설계의 핵심이다. 죽이지 않아도 자리만 지키면
--    점령이 멈추므로, 태거에게 다수 대응 수단이 없어도 방어가 성립한다.

local MULTI_RUNNER_BONUS = false -- 여러 명이 있어도 속도가 오르지 않는다
-- ⚠️ 켜면 다수의 이점이 너무 커져 태거가 감당 못 한다.
--    끄면 "한 명은 점령, 나머지는 태거 저지"라는 분업이 자연히 생긴다.

local TICK = 0.1                 -- 판정 주기

-- ── 상태 ───────────────────────────────────────────────────────
local progress = 0
-- 🏆 [구조변경 2026-09-02] 존별 게이지. progress 는 이제 '대표값(가장 앞선 존)'이다.
--   [왜] 게이지가 하나면 러너가 두 존을 오가며 진행을 그대로 들고 다닌다.
--     실측 5판 전부 이 루프로 러너가 이겼다 — 킹이 A 를 밟으면 B 로 가고, B 를
--     밟으면 A 로 간다. 게이지가 공유되니 이동 손실(3.3초 × 감쇠 1.5)보다
--     도착 후 회복(초당 1.0)이 빨라 순증이다. 수비자 1명이 목표 2개를 못 막는다.
--   ⚠️ 283행의 "게이지는 존이 몇 개든 하나다"는 의도적 설계였다. 이 변경은 그 결정을
--     뒤집는 것이다 — 분산 압박이라는 목적은 남기되, 진행 보존만 끊는다.
--     이제 러너는 한 존을 끝까지 밀어야 하므로 킹과의 정면 대치가 강제된다.
--   ⚠️ UI·getProgress 는 대표값을 그대로 쓴다. 클라에는 비율로 나가므로 변경 없음.
local zoneProgress = {}   -- [존 인덱스] = 진행도(초). 존이 없어지면 start/stop 에서 비운다
local zonePeak     = {}   -- [존 인덱스] = 이번 라운드 최고 진행도(진단용)

-- 🏆 [2026-09-02] 존별 게이지 월드 표시.
--   [왜] 밟아야만 보이면 "저쪽 존이 몇 % 인가"를 모른 채 판단해야 한다. 존이 2개고
--     서로 떨어져 있어서 위치+진행도가 곧 전략이다. 킹도 어디가 급한지 봐야 한다.
--   ⚠️ 크기는 스터드(Scale) 단위다. 픽셀 고정은 거리와 무관하게 같은 픽셀이라
--     원거리에서 주변 대비 거대해 보인다 — TaggerHpDisplay:30 이 같은 이유로 이미
--     기각한 방식이다. Scale 이면 원근이 적용돼 멀수록 자연히 작아진다.
--   ⚠️ AlwaysOnTop=false. 벽 너머로 비치면 시야를 가린다(HP 바와 같은 판단).
local GAUGE_NAME = "CaptureGaugeGui"

local function ensureGauge(zone)
    local gui = zone:FindFirstChild(GAUGE_NAME)
    if gui then return gui end

    gui = Instance.new("BillboardGui")
    gui.Name = GAUGE_NAME
    gui.Size = UDim2.new(10, 0, 1.4, 0)          -- 스터드 단위 (원근 적용)
    gui.StudsOffset = Vector3.new(0, 8, 0)
    gui.AlwaysOnTop = false
    gui.LightInfluence = 0
    gui.MaxDistance = 1500
    gui.Adornee = zone
    gui.Parent = zone

    local bg = Instance.new("Frame")
    bg.Name = "BarBg"
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(15, 18, 25)
    bg.BackgroundTransparency = 0.15
    bg.BorderSizePixel = 0
    bg.Parent = gui
    local c1 = Instance.new("UICorner") ; c1.CornerRadius = UDim.new(0, 6) ; c1.Parent = bg
    local st = Instance.new("UIStroke")
    st.Color = Color3.fromRGB(0, 0, 0) ; st.Thickness = 1.5 ; st.Transparency = 0.4 ; st.Parent = bg

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(0, 0, 1, -4)
    fill.Position = UDim2.new(0, 2, 0, 2)
    fill.BackgroundColor3 = Color3.fromRGB(90, 170, 255)
    fill.BorderSizePixel = 0
    fill.Parent = bg
    local c2 = Instance.new("UICorner") ; c2.CornerRadius = UDim.new(0, 4) ; c2.Parent = fill

    -- 🏁 체크포인트 눈금. "여기까지는 안 깎인다"를 설명 없이 보여준다.
    --   ⚠️ Fill 위에 그린다(ZIndex 2). 밑에 두면 채워진 구간에서 안 보인다.
    --   ⚠️ 경합 중에는 setGauge 가 이 눈금을 흐리게 만든다. 킹이 밟고 있으면 눈금이
    --     무시되므로, 그대로 선명하면 UI 가 거짓말을 한다.
    for m = CHECKPOINT_STEP, CAPTURE_GOAL - 0.01, CHECKPOINT_STEP do
        local tick = Instance.new("Frame")
        tick.Name = "Tick"
        tick.AnchorPoint = Vector2.new(0.5, 0)
        tick.Position = UDim2.new(m / CAPTURE_GOAL, 0, 0, 2)
        tick.Size = UDim2.new(0, 2, 1, -4)
        tick.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        tick.BackgroundTransparency = 0.45
        tick.BorderSizePixel = 0
        tick.ZIndex = 2
        tick.Parent = bg
    end

    local txt = Instance.new("TextLabel")
    txt.Name = "Pct"
    txt.Size = UDim2.new(1, 0, 1, 0)
    txt.BackgroundTransparency = 1
    txt.TextColor3 = Color3.fromRGB(255, 255, 255)
    txt.TextScaled = true
    txt.Font = Enum.Font.GothamBold
    txt.TextStrokeTransparency = 0
    txt.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    txt.ZIndex = 2
    txt.Parent = bg

    return gui
end

-- ratio 0~1 / contested = 킹이 그 존을 밟고 있는가(색으로 구분)
local function setGauge(zone, ratio, contested)
    local gui = ensureGauge(zone)
    local bg = gui:FindFirstChild("BarBg")
    if not bg then return end
    local fill = bg:FindFirstChild("Fill")
    if fill then
        fill.Size = UDim2.new(math.clamp(ratio, 0, 1), -4, 1, -4)
        -- 킹이 경합 중이면 주황, 아니면 파랑. "지금 막히고 있다"가 멀리서도 보인다.
        fill.BackgroundColor3 = contested
            and Color3.fromRGB(255, 150, 60)
            or  Color3.fromRGB(90, 170, 255)
    end
    local txt = bg:FindFirstChild("Pct")
    if txt then txt.Text = string.format("%d%%", math.floor(ratio * 100 + 0.5)) end

    -- 🏁 경합 중이면 눈금을 흐린다. 킹이 밟고 있을 때는 눈금이 무시되기 때문이다
    --   ("선명한 눈금 = 지금 떠나도 안전 / 흐린 눈금 = 지금은 다 잃는다").
    for _, d in ipairs(bg:GetChildren()) do
        if d.Name == "Tick" then
            d.BackgroundTransparency = contested and 0.88 or 0.45
        end
    end
end
-- 🤖 지금 게이지를 채우고 있는 존(BasePart). 차오르는 중이 아니면 nil.
--   ⚠️ step 에서 매 틱 갱신한다. stop 에서 반드시 nil 로 되돌린다(켜는 코드엔 끄는 코드를).
local activeZone = nil
local active = false
local zoneParts = {}   -- 🏁 [2026-08-27] 단수 → 복수(map1 분할 실험). 게이지는 여전히 하나.

-- ═══════════════════════════════════════════════════════════
-- ✨ 점령지 강조 연출
--
-- [왜] 지금은 바닥 색만 있어 '지금 차오르는 중'인지 알기 어렵다.
--   러너는 어디를 밟아야 하는지, 태거는 어디를 막아야 하는지가
--   한눈에 보여야 한다.
--
-- [설계] 충전 중일 때만 살아난다:
--   · 테두리(SelectionBox)가 밝게 빛남
--   · 은은한 빛기둥이 위로 솟음
--   충전이 멈추면 서서히 잦아든다. 켜짐/꺼짐이 곧 상태 표시다.
-- ⚠️ 서버에서 만들고 Anchored 로 둔다. 파트 하나뿐이라 부하가 없다.
-- ═══════════════════════════════════════════════════════════
-- 🏛️ [2026-08-27 v2] 빛기둥 배열 → '이어진 낮은 띠'.
--   [v1 문제] 참조 이미지(빛의 성당)를 너무 직역했다. 기둥이 높고(80) 개별로 떨어져
--     있어 존을 감싸기보다 '거대한 구조물'이 됐고, 시야도 가렸다.
--   [v2] 네 변을 각각 '한 덩어리'로 만들어 끊김 없이 잇고, 키의 절반 높이로 낮춘다.
--     ⚠️ 개별 파트 24개 → 4개로 줄어 부하도 함께 내려간다.
local BEAM_HEIGHT   = 2.5    -- 러너 키(약 5 stud)의 절반. 발밑 경계선으로 읽힌다
local BEAM_ALPHA_ON = 0.82   -- 사실상 투명에 가깝게. 존 안이 훤히 보여야 한다
local BEAM_W        = 0.8    -- 띠 두께
local EDGE_ON       = 0      -- 테두리 불투명도(0 = 진하게)
local EDGE_OFF      = 0.65
local WALL_HEIGHT     = 5       -- 🟧 [2026-08-30] 14 → 5. 캐릭터 키와 비슷한 높이.
                                --   [왜] 14 는 키의 3배라 2단계 교전 중 시야를 가리고 존이 '구조물'로 읽혔다.
                                --   존의 경계만 알려주면 되므로 낮게 두른다.
local WALL_THICKNESS  = 0.4
local WALL_NAME       = "_CaptureNeonWall"
-- 🌀 [2026-08-30] 맥동(일렁임). 벽이 켜진 뒤 아무 변화가 없어 연출이 정적이었다.
--   면마다 위상을 어긋나게 줘서 빛이 존 둘레를 도는 것처럼 보이게 한다.
--   ⚠️ PULSE_DEPTH = 0 으로 두면 맥동이 완전히 꺼지고 예전(고정) 동작으로 돌아간다.
local PULSE_SPEED     = 0.30    -- 초당 회전수. 0.30 ≈ 3.3초에 한 바퀴
local PULSE_DEPTH     = 0.15    -- 투명도 진폭. 올릴수록 밝기 대비가 커진다

local function buildNeonWall(part)
	if part:FindFirstChild(WALL_NAME) then return part:FindFirstChild(WALL_NAME) end
	local folder = Instance.new("Folder")
	folder.Name = WALL_NAME
	local sx, sz = part.Size.X, part.Size.Z
	local halfY = part.Size.Y / 2
	local faces = {
		{ Vector3.new(WALL_THICKNESS, WALL_HEIGHT, sz), Vector3.new( sx/2, 0, 0) },
		{ Vector3.new(WALL_THICKNESS, WALL_HEIGHT, sz), Vector3.new(-sx/2, 0, 0) },
		{ Vector3.new(sx, WALL_HEIGHT, WALL_THICKNESS), Vector3.new(0, 0,  sz/2) },
		{ Vector3.new(sx, WALL_HEIGHT, WALL_THICKNESS), Vector3.new(0, 0, -sz/2) },
	}
	-- 🟧 [2026-08-30] 0.35 → 0.55 로 올렸다가, 너무 흐려서 0.45 / 0.80 으로 되돌림.
	--   ⚠️ 여기 값이 각 파트의 _BaseT 로 들어가고, 페이드 루프가 이 값을 목표로 삼는다.
	--     즉 이 표가 '가장 진할 때'의 투명도다. 흐리게 하려면 올리고, 진하게 하려면 내린다(0 = 불투명).
	local tiers = { {0.45, 0.0}, {0.80, 0.5} }
	-- 🌀 면 번호(fi)로 위상을 나눈다. 네 면이 순서대로 밝아져 빛이 둘레를 도는 것처럼 보인다.
	--   위상이 같으면 네 면이 동시에 깜빡여서 '회전'이 아니라 '점멸'이 된다.
	for fi, f in ipairs(faces) do
		for _, t in ipairs(tiers) do
			local w = Instance.new("Part")
			w.Name       = "Wall"
			w.Size       = Vector3.new(f[1].X, WALL_HEIGHT / 2, f[1].Z)
			w.CFrame     = part.CFrame * CFrame.new(f[2].X, halfY + WALL_HEIGHT * (0.25 + t[2]), f[2].Z)
			w.Anchored   = true
			w.CanCollide = false
			w.CanQuery   = false
			w.CanTouch   = false
			w.Massless   = true
			w.CastShadow = false
			w.Material   = Enum.Material.Neon
			w.Color      = part.Color
			w:SetAttribute("_BaseT", t[1])   -- 페이드 루프가 파트별 목표를 이걸로 계산
			-- 🌀 면 순서(0 / 0.25 / 0.5 / 0.75) + 위단은 살짝 더 지연 → 대각선으로 흐르는 느낌
			w:SetAttribute("_Phase", (fi - 1) / #faces + t[2] * 0.12)
			w.Transparency = 1               -- 생성 직후엔 숨김 — setCaptureFx 가 켠다
			w.Parent     = folder
		end
	end
	folder.Parent = part
	return folder
end


-- ── 전방 선언 (FX 상태) ────────────────────────────────────────
-- ⚠️ [2026-08-30] fxState · fxConn 의 실제 선언은 아래 FX 블록(약 352·401행)에 있는데
--   clearCaptureFx 는 그보다 앞이라, 그대로 두면 둘 다 전역 nil 을 본다.
--   · fxState → pairs(nil) 로 터진다. stop() 이 죽으면서 endRound 가 중단됐다
--     (점령 승리 순간 승리 연출·보상·정리가 통째로 안 돌았다).
--   · fxConn  → 에러가 안 난다. `if fxConn then` 이 nil 을 보고 그냥 통과해서
--     라운드가 끝나도 Heartbeat FX 루프가 안 끊겼다. 조용히 새던 쪽이 더 위험하다.
-- ⚠️ 아래 두 선언에 local 을 다시 붙이면 새 지역변수가 생겨 이 선언을 가린다 — 붙이지 말 것.
local fxState
local fxConn

local function clearCaptureFx()
	if fxConn then fxConn:Disconnect(); fxConn = nil end
	for zone, st in pairs(fxState) do
		-- ⚠️ 기둥을 하나씩 지우지 말고 폴더째 지운다. 기둥이 존당 24개라
		--    개별 Destroy 는 낭비이고, 폴더가 남으면 다음 라운드에 중복 생성된다.
		if st.folder and st.folder.Parent then st.folder:Destroy() end
		fxState[zone] = nil
	end
end
local loopConn = nil

-- 클라 표시용 채널
local capEvent = ReplicatedStorage:FindFirstChild("CaptureState")
if not capEvent then
    capEvent = Instance.new("RemoteEvent")
    capEvent.Name = "CaptureState"
    capEvent.Parent = ReplicatedStorage
end

-- ── 존 탐색 ────────────────────────────────────────────────────
-- ⚠️ [실패 기록 2026-08-23] 예전엔 workspace 를 순회하며 첫 CapturePoint 를 잡았다.
--    그런데 map1/map2 가 둘 다 workspace 에 남아 있어서 항상 map1 존이 반환됐고,
--    map2 라운드에서 러너가 존을 밟아도 게이지가 안 찼다.
--    → RoundSystem 이 SetCurrentMap 으로 알려주는 '활성 맵'에서만 찾는다.
local activeMapFolder = nil
do
    local setMapEvent = ReplicatedStorage:FindFirstChild("SetCurrentMap")
    if setMapEvent and setMapEvent:IsA("BindableEvent") then
        setMapEvent.Event:Connect(function(folder)
            activeMapFolder = folder
        end)
    end
end

-- 🏁 [2026-08-27] 존을 '여러 개' 찾는다. map1 = 2개 분할 실험 / map2 = 1개(기존).
--   [규칙] 이름이 "CapturePoint" 로 시작하는 파트를 전부 존으로 본다.
--     → 스튜디오에서 파트를 복제하고 CapturePointB 로 이름만 바꾸면 코드 수정 없이 늘어난다.
--     (BarricadeSystem.snapshot 과 같은 '워크스페이스가 청사진' 패턴)
-- ⚠️ [폐기 2026-09-02] 예전엔 "게이지는 존이 몇 개든 하나"였다. 이제 존별로 쌓인다.
--    분할의 목적(킹이 두 곳을 동시에 못 지키게)은 그대로지만, 게이지가 공유되면
--    러너 혼자 두 존을 오가며 진행을 보존해 수비가 성립하지 않았다(실측 5판 전패).
--    자세한 근거는 zoneProgress 선언부 주석 참조.
local function collectZones(root)
    local out = {}
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("BasePart") and d.Name:sub(1, 12) == "CapturePoint" then
            out[#out + 1] = d
        end
    end
    return out
end

local function findZones()
    -- 1순위: 활성 맵 (정확)
    if activeMapFolder and activeMapFolder.Parent then
        local zs = collectZones(activeMapFolder)
        if #zs > 0 then return zs end
    end
    -- 2순위: workspace 의 맵 폴더 중 존을 가진 게 '하나뿐'이면 그것
    -- ⚠️ 여기서 세는 건 '맵 개수'지 '존 개수'가 아니다. 한 맵이 존을 2개
    --    가지는 건 정상이고, 두 맵이 각각 가진 경우만 모호하다.
    local byMap = {}
    for _, mapFolder in ipairs(workspace:GetChildren()) do
        if mapFolder:IsA("Folder") or mapFolder:IsA("Model") then
            local zs = collectZones(mapFolder)
            if #zs > 0 then byMap[#byMap + 1] = { folder = mapFolder, zones = zs } end
        end
    end
    if #byMap == 1 then return byMap[1].zones end
    if #byMap > 1 then
        warn("[Capture] 존을 가진 맵이 " .. #byMap .. "개 — 활성 맵을 특정하지 못했다")
        return byMap[1].zones
    end
    return {}
end

-- 존 안에 있는가 (XZ 평면 + 높이 여유)
local function isInZone(char, zone)
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local p, zp, zs = hrp.Position, zone.Position, zone.Size
    local dx = math.abs(p.X - zp.X)
    local dz = math.abs(p.Z - zp.Z)
    local dy = p.Y - zp.Y
    -- ⚠️ Y 는 넉넉히 본다. 점프하거나 계단에 걸쳐도 점령이 끊기면 안 된다.
    return dx <= zs.X / 2 and dz <= zs.Z / 2 and dy > -8 and dy < 25
end

-- ── 전방 선언 ─────────────────────────────────────────────────
-- ⚠️ [2026-08-30] setCaptureFx 의 정의는 아래 FX 블록(약 428행)에 있는데
--   step 은 그보다 앞(308행)에서 이미 호출한다. Lua 의 local function 은
--   정의 지점 이후에만 보이므로, 그대로 두면 step 안에서 nil 이 되어
--   "attempt to call a nil value" 로 매 프레임 터졌다.
--   → 308행 아래가 통째로 실행되지 않아 게이지·네온벽이 전부 죽어 있었다.
--   여기서 이름만 먼저 만들고, 아래 정의는 local 없이 이 변수에 담는다.
-- ⚠️ 아래 정의에 local 을 다시 붙이면 새 지역변수가 생겨 이 선언을 가린다 — 붙이지 말 것.
local setCaptureFx

-- ── 한 틱 판정 ─────────────────────────────────────────────────
-- 🏁 [2026-08-27] 존이 여러 개일 때의 규칙: **가장 유리한 존의 속도를 쓴다.**
--   [왜] 킹은 한 번에 한 존에만 설 수 있다. 킹이 없는 존에 러너가 있으면
--     그쪽은 감속을 안 받는다 — 이게 분할의 유일한 존재 이유다.
--     존별 속도를 '합산'하면 두 곳을 동시에 밟는 게 2배가 되어 점령이 너무 빨라지고,
--     '평균'을 내면 빈 존이 진행을 깎아 분할이 오히려 페널티가 된다. 그래서 최대값이다.
--   [결과] 킹이 A 를 지키면 러너는 B 로 가서 정상 속도로 채운다.
--     킹이 따라오면 러너는 다시 A 로 — 킹을 왕복시키는 게 러너의 플레이가 된다.
-- ⚠️ 존이 1개면(map2) 아래 루프가 한 번만 돌아 기존 동작과 완전히 같다.
local function step(dt)
    if not active or #zoneParts == 0 then return end

    -- 존별로 러너 수 / 태거 유무를 따로 센다.
    local perZone = {}
    local anyRunners = 0
    local anyTagger = false
    -- 🔬 [진단 2026-09-03] 킹 캐릭터 참조. 아래 두 루프는 '존 안'일 때만 태거를 잡지만
    --   이건 존 밖이어도 잡아둔다 — "킹 없음"이 '못 왔다'인지 '왔다가 밀려났다'인지는
    --   거리로만 구분되기 때문이다. ⚠️ 제거할 땐 이 변수 + 아래 두 대입 + 출력부를 같이.
    local kingChar = nil
    for i, zone in ipairs(zoneParts) do
        perZone[i] = { runners = 0, tagger = false, zone = zone }
    end

    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char and not char:GetAttribute("Downed") then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local role = plr:GetAttribute("Role")
                if role == "Tagger" then kingChar = char end   -- 🔬 진단: 존 밖이어도 잡는다
                for i, zone in ipairs(zoneParts) do
                    if zone.Parent and isInZone(char, zone) then
                        if role == "Runner" then
                            perZone[i].runners = perZone[i].runners + 1
                            anyRunners = anyRunners + 1
                        elseif role == "Tagger" then
                            perZone[i].tagger = true
                            anyTagger = true
                        end
                    end
                end
            end
        end
    end

    -- AI 태거(봇)도 방어자로 친다.
    -- ⚠️ 솔로 모드에서는 태거가 봇이다. 이걸 빼면 봇전에서 점령이 무조건 성공한다.
    if TAGGER_BLOCKS then
        for _, m in ipairs(workspace:GetChildren()) do
            -- 🤖 [2026-08-30] 조건을 Role=="Tagger" 로 넓혔다.
            --   [증상] 봇 킹이 존 안에 있어도 방어자로 안 잡혀 감속이 걸리지 않았다.
            --   [원인] IsTaggerNoob 은 TaggerNoobSystem(/taggerbot)이 세우는 속성이다.
            --     TaggerBotSystem 의 KING 봇은 Role="Tagger" / TaggerDummy 를 세우므로
            --     이 조건에 안 걸렸다. PushChargeFxViewer 에서도 같은 실수가 있었다.
            --   ⚠️ 유저 캐릭터도 workspace 의 Model 이고 Role 을 갖는다.
            --     위 Players 루프가 이미 처리하므로 GetPlayerFromCharacter 로 걸러
            --     같은 태거를 두 번 세지 않는다.
            local isBotTagger = (m:GetAttribute("Role") == "Tagger"
                                 or m:GetAttribute("IsTaggerNoob"))
                                and not Players:GetPlayerFromCharacter(m)
            if m:IsA("Model") and isBotTagger then
                local hum = m:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    kingChar = kingChar or m   -- 🔬 진단: 존 밖이어도 잡는다 (유저 킹이 우선)
                    for i, zone in ipairs(zoneParts) do
                        if zone.Parent and isInZone(m, zone) then
                            perZone[i].tagger = true
                            anyTagger = true
                        end
                    end
                end
            end
        end
    end

    -- 🤖 [2026-09-04] AI 러너도 점령 인원으로 센다.
    --   [왜] 위 Players 루프는 유저만 돈다. 봇 러너는 workspace 의 Model 이라
    --     존 안에 서 있어도 z.runners = 0 이었고, 아래 `if z.runners > 0` 에 걸려
    --     게이지가 아예 오르지 않았다 — 봇에게 점령 경로가 존재하지 않았다.
    --   ⚠️ 위 TAGGER_BLOCKS 블록과 대칭이다. 방어(태거)는 봇을 세는데
    --     공격(러너)은 안 세던 비대칭을 맞추는 것이다.
    --   ⚠️ 가중치 없음 — 유저 1명 = 봇 1마리로 센다. 실측 후 조정한다.
    --     지금 값을 정하면 봇이 존에 몇 초에 도달하는지도 모르는 채 추측하게 된다.
    --   ⚠️ 다운된 봇은 제외. 위 유저 루프의 Downed 검사와 같은 규칙이다.
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("AIRunner")
           and not m:GetAttribute("Downed") then
            local hum = m:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                for i, zone in ipairs(zoneParts) do
                    if zone.Parent and isInZone(m, zone) then
                        perZone[i].runners = perZone[i].runners + 1
                        anyRunners = anyRunners + 1
                    end
                end
            end
        end
    end

    local before = progress
    -- ═══════════════════════════════════════════════════════════
    -- 🏆 점령 진행
    --
    -- ⚠️ [밸런스 2026-08-25] 태거가 있으면 '완전 정지' → '감속'.
    --   [왜] 완전히 막으면 '태거를 죽여야만 점령 가능'이 되어,
    --   점령이 승리 조건이 아니라 킹 처치 뒤의 사후 절차가 된다.
    --   두 승리 조건이 서로 사족이 되는 문제였다.
    --
    -- ⚠️ 감속률은 인원 비례다. 혼자면 킹을 못 이기고, 뭉치면 뚫린다.
    --   감속률 = 러너수 / (러너수 + KING_POWER), 하한 MIN_FILL_RATE
    --   ⚠️ [갱신 2026-09-01] 아래 수치는 KING_POWER=8 · MIN_FILL_RATE=0.15 · 목표 10초 기준.
    --     예전 주석(KING_POWER=4 시절의 "1명 0.33 / 3명 0.60 / 5명 0.71")은 폐기했다.
    --   러너 1명 → 0.111 이지만 하한에 걸려 0.15 (66.7초)
    --        2명 → 0.20  (50.0초)
    --        3명 → 0.273 (36.7초)
    --        5명 → 0.385 (26.0초)
    --   ⚠️ 1명 구간은 이제 하한이 실제로 작동한다. KING_POWER 2·4 시절엔 한 번도
    --     안 닿던 값이라 '죽은 상수'였다. 더 세게 하려면 KING_POWER 가 아니라
    --     MIN_FILL_RATE 를 내려야 한다 — 병목이 그쪽으로 옮겨갔다.
    -- ═══════════════════════════════════════════════════════════
    -- ⚔️ [밸런스 2026-09-01] 킹이 존에 붙으면 '감속' → '되돌림'.
    --   [왜] 하한이 아무리 낮아도 양수라 게이지가 단조 증가했다. 킹이 존에 도달해도
    --     66.7초로 늦출 뿐 결국 진다 → 존에 갈 이유가 없었다. 실측(R4): 존 방어 전환은
    --     게이지 1% 에서 정상 발동했는데도 25초간 아무것도 못 막고 점령당했다.
    --     이제 1명 상대로는 rate 가 음수라 킹이 서 있는 한 절대 완료되지 않는다.
    --     ⚠️ 다만 되돌리는 속도 자체는 느리다(1명 −0.039/s → 만충 지우는 데 257초).
    --       즉 이 값의 효과는 '삭제'가 아니라 '동결'이다. 러너는 킹이 떠나길 기다리면
    --       진행이 보존된다. 처치와 비교하면 킹이 이긴다(1명 처치 13.3초 ≪ 동결).
    --   [방식] 하한 클램프 대신 균형점 오프셋. rate = 인원비율 − CONTEST_NEUTRAL.
    --     인원 비례 설계(혼자면 킹을 못 이기고, 뭉치면 뚫린다)를 그대로 살린다.
    --     1명 −0.039(되돌림) / 2명 +0.05(200초) / 3명 +0.123(81초) / 5명 +0.235(42.5초)
    --   ⚠️ sentinel 을 0 → nil 로 바꿨다. 음수 rate 가 0 에 밀려 버려지면 되돌림이
    --     통째로 죽고 대신 DECAY_RATE(1.5)가 잘못 걸린다(의도값의 38배).
    --     nil = "존에 아무도 없음"(기존 감쇠), 숫자 = "누군가 밟고 있음"(양수든 음수든 그 값).
    --   ⚠️ 두 존 중 max 를 고르는 규칙은 손대지 않았다. 킹 없는 존이 하나라도 있으면
    --     여전히 1.0 이 채택되므로 2존 분할 착취는 이 변경으로 안 잡힌다(별개 과제, 67~68행 참고).
    --   ⚠️ [갱신 2026-09-02] 아래 max 규칙은 '어느 존이 가장 빠른가'를 고를 뿐이고,
    --     게이지는 이제 존마다 따로 쌓인다. 그래서 킹 없는 존이 1.0 이어도 그 존을
    --     처음부터 채워야 한다 — 2존 분할 착취가 여기서 끊긴다.
    local bestRate = nil
    local threatIdx, threatProg = nil, nil   -- 차오르는 존 중 가장 완료에 가까운 곳
    local leadIdx, leadProg = nil, 0         -- 존 무관 최대 진행도(대표값)

    for i, z in ipairs(perZone) do
        zoneProgress[i] = zoneProgress[i] or 0
        local prev = zoneProgress[i]

        if z.runners > 0 then
            local rate = 1
            if z.tagger then
                rate = z.runners / (z.runners + KING_POWER) - CONTEST_NEUTRAL
            end
            -- ⚠️ 보너스는 양수일 때만 곱한다. 음수에 곱하면 인원이 많을수록 더 빨리
            --    되돌아가는 역효과가 난다(지금은 false 라 휴면 상태지만 켤 때 터진다).
            if MULTI_RUNNER_BONUS and rate > 0 then rate = rate * math.min(z.runners, 3) end
            -- 🎤❄️ CC 중이면 상승률을 눌러 무료 점령을 막는다(CC_FILL_MULT 주석 참조).
            if rate > 0 and taggerIsCC() then rate = rate * CC_FILL_MULT end
            zoneProgress[i] = math.clamp(prev + FILL_RATE * dt * rate, 0, CAPTURE_GOAL)
            -- 📈 [진단] 존별 최고점 갱신 시 기록. "몇 %까지 갔다가 실패했나"를 남긴다.
            --   [왜 필요] 지금까지 로그에 게이지 수치가 없어서 "라인 하강 2%" 만 보였다.
            --     그게 하강 시점 값이라 최고점을 알 수 없었고, 판단이 기억에 의존했다.
            --   ⚠️ 25% 단위로만 찍는다. 매 틱 찍으면 로그가 묻힌다.
            local pk = zonePeak[i] or 0
            if zoneProgress[i] > pk then
                zonePeak[i] = zoneProgress[i]
                local before = math.floor(pk / CHECKPOINT_STEP + 1e-6)
                local after  = math.floor(zoneProgress[i] / CHECKPOINT_STEP + 1e-6)
                if after > before then
                    -- 🔬 [진단 2026-09-03] 킹까지의 거리를 같이 찍는다.
                    --   [왜] 09-03 실측은 6건 전부 "킹 없음"이었다. 그런데 그건 킹이 못 온 게
                    --     아니라, 유저가 해머 스핀으로 존 문턱에서 계속 밀어내던 상황이었다.
                    --     두 경우는 처방이 정반대인데(이속 보강 vs 밀림 대응) 로그가 못 갈랐다.
                    --   [읽는 법] 거리 100+ = 못 온 것(이속·경로 문제).
                    --     거리 20~50 이 계속 유지 = 문 앞에서 밀려나는 것(밀림 문제).
                    local kdist = -1
                    if kingChar then
                        local kr = kingChar:FindFirstChild("HumanoidRootPart")
                        if kr then kdist = (kr.Position - z.zone.Position).Magnitude end
                    end
                    print(string.format("📈 [Capture] 존%d 최고 %.0f%% — 러너 %d명 / 킹 %s (거리 %s)",
                        i, zoneProgress[i] / CAPTURE_GOAL * 100,
                        z.runners, z.tagger and "있음" or "없음",
                        kdist >= 0 and string.format("%.0f", kdist) or "불명"))
                end
            end
            if bestRate == nil or rate > bestRate then bestRate = rate end
        else
            -- 아무도 안 밟은 존은 스스로 식는다. 존별이라 '옆 존으로 옮겨 진행을
            -- 보존하는' 착취가 성립하지 않는다 — 옮기면 그쪽은 0 부터다.
            -- 🏁 다만 체크포인트 아래로는 안 내려간다. 재도전이 누적되게 하는 규칙이다.
            --    ⚠️ 여기(빈 존 감쇠)에만 건다. 경합 분기는 눈금을 무시하고 되돌려야
            --      킹의 존 방어가 살아 있다 — 둘 다 막으면 착취가 열린다(실측).
            local mark = math.floor(prev / CHECKPOINT_STEP + 1e-6) * CHECKPOINT_STEP
            zoneProgress[i] = math.max(mark, prev - DECAY_RATE * dt)
        end

        -- ✨ 차오르는 '그 존'만 켠다. 나머지는 반드시 끈다("켜는 코드에 끄는 코드를 같이").
        --    ⚠️ 존별 게이지가 되면서 두 존이 동시에 차오를 수 있다. 그건 정상이다 —
        --      러너가 갈라져 두 곳을 미는 상황이고, 그때는 둘 다 빛나야 옳다.
        local rise = zoneProgress[i] > prev
        local zp = zoneParts[i]
        if zp then
            setCaptureFx(zp, rise)
            -- 🏆 게이지는 밟지 않아도 항상 보인다(양쪽 상태를 알아야 전략이 선다).
            setGauge(zp, zoneProgress[i] / CAPTURE_GOAL, z.tagger == true)
        end

        if rise and (threatProg == nil or zoneProgress[i] > threatProg) then
            threatIdx, threatProg = i, zoneProgress[i]
        end
        if zoneProgress[i] > leadProg then leadIdx, leadProg = i, zoneProgress[i] end
    end

    progress = leadProg   -- UI·getProgress 용 대표값

    -- 🤖 [2026-08-30] 지금 막아야 할 존을 밖에 알린다(TaggerBotSystem 이 읽는다).
    --   ⚠️ [갱신 2026-09-02] 예전엔 '상승률이 가장 큰 존'이었다. 존별 게이지에서는
    --     그게 답이 아니다 — 이제 '차오르는 존 중 완료에 가장 가까운 곳'을 준다.
    --     막 시작한 존보다 90% 찬 존이 급하다.
    --   ⚠️ 차오르는 중이 아니면 nil 이다. 식는 중인 존으로 봇을 보낼 이유가 없다.
    activeZone = threatIdx and zoneParts[threatIdx] or nil

    if progress ~= before then
        capEvent:FireAllClients("progress", progress / CAPTURE_GOAL, anyRunners, anyTagger)
    end

    if leadProg >= CAPTURE_GOAL then
        active = false
        print(string.format("👑 [Capture] 점령 완료 — 러너 승리 (존 %d)", leadIdx or 0))

        -- ⛓️ [설계전환 2026-09-05 · 1단계] 점령의 역할을 '승리'에서 '왕 약화'로 옮기는 중.
        --   [왜] 점령 승리에 손맛이 없다. 게이지가 차는 동안 플레이어가 내리는 결정이 0개고,
        --     최적해가 "가만히 서 있기"로 수렴한다. 반면 전투는 아슬아슬할수록 짜릿하다.
        --     → 점령을 승리 조건이 아니라 "전투를 이길 수 있게 만드는 준비"로 바꾼다.
        --   [최종 그림] 점령 100% → 점령지 소멸 → 왕좌 파괴 → 검은 사슬 부착
        --     → 8초 주기 탈진(1초, 속도 6, 공격 불가) → 전투로 결착.
        --   [왜 오버워치처럼 못 만드나] 그쪽 점령의 재미("비벼비벼", 땅따먹기)는
        --     전부 '죽어도 몇 초 뒤 돌아온다'에서 나온다. 이 게임은 한 번 죽으면 끝이라
        --     존 위 교전이 한 번뿐이고, 밀고 밀림이 물리적으로 성립하지 않는다.
        --     → 점령 '중'은 재미없는 채로 두고, 결과를 재미있는 것(전투)으로 넘긴다.
        --
        --   ⚠️ 지금은 1단계다. 훅만 부르고 승리 처리(_G.CaptureWin)는 그대로 둔다.
        --     연출을 검증하는 동안 라운드가 안 끝나면 테스트가 불가능해지기 때문이다.
        --   ⚠️ 3단계에서 아래 _G.CaptureWin 줄을 지우는 순간이 되돌리기 어려운 지점이다.
        --     그 전까지는 훅이 실패해도 게임이 예전처럼 굴러간다.
        if _G.ThroneFall then
            local ok, err = pcall(_G.ThroneFall)
            -- ⚠️ pcall 은 반드시 에러를 찍는다. 조용히 삼키면 "연출이 왜 안 나오지"로 하루를 쓴다.
            if not ok then warn("[Capture] ThroneFall 실패: " .. tostring(err)) end
        end

        --   ⚠️ [3단계 완료 2026-09-05] _G.CaptureWin 호출을 제거했다.
        --     이제 점령은 승리가 아니라 '왕좌 상실'이다 — 킹이 사슬에 묶이고
        --     8초마다 탈진하며, 결착은 전투가 낸다.
        --   ⚠️ 되돌리려면 아래 한 줄을 되살린다:  if _G.CaptureWin then _G.CaptureWin() end
        --     그러면 예전처럼 점령 즉시 라운드가 끝난다(연출은 그대로 나온다).
        --   ⚠️ 이 변경으로 러너의 승리 경로는 '킹 처치' 하나가 된다.
        --     타임아웃(=태거 승)이 실질적으로 도달 불가라는 RoundSystem 기록이 전제다 —
        --     만약 점령 후 전투가 길어져 타임아웃이 자주 나오면 그 값을 함께 봐야 한다.
    end
end

-- ── 외부 API ───────────────────────────────────────────────────
local CaptureSystem = {}

-- ── 존 표시 켜기/끄기 ──────────────────────────────────────────
-- ⚠️ [2026-08-24] 점령존이 항상 보이는 게 문제였다.
--    · 1단계 내내 노란 판이 성 안에 떠 있어 러너에게 혼란을 준다
--      (아직 갈 수 없는 곳인데 목표처럼 보인다)
--    · 로비(Y 304)에서 아래를 내려다보면, 스트리밍으로 주변 지형이 언로드된
--      상태에서 존만 남아 "공중에 둥둥 뜬" 것처럼 보인다
--    → 2단계에만 보이게 한다. 점령은 2단계 전용 규칙이므로 그게 맞다.
local ZONE_VISIBLE_TRANSPARENCY = 0.55

fxState = setmetatable({}, { __mode = "k" })   -- zone -> { beams, on, alpha, edge } | ⚠️ local 없음 — 위 전방 선언에 담는다

-- 네 변을 각각 하나의 긴 파트로. 모서리에서 서로 겹쳐 끊김이 없다.
--   ⚠️ 겹치는 폭(BEAM_W)만큼 길이를 더해야 모서리에 빈틈이 안 생긴다.
local function edgeSpecs(sizeX, sizeZ)
	local hx, hz = sizeX / 2, sizeZ / 2
	return {
		{ size = Vector3.new(sizeX + BEAM_W, BEAM_HEIGHT, BEAM_W), off = Vector3.new(0, 0, -hz) },
		{ size = Vector3.new(sizeX + BEAM_W, BEAM_HEIGHT, BEAM_W), off = Vector3.new(0, 0,  hz) },
		{ size = Vector3.new(BEAM_W, BEAM_HEIGHT, sizeZ + BEAM_W), off = Vector3.new(-hx, 0, 0) },
		{ size = Vector3.new(BEAM_W, BEAM_HEIGHT, sizeZ + BEAM_W), off = Vector3.new( hx, 0, 0) },
	}
end

local function ensureFx(zone)
	if not zone or not zone.Parent then return nil end
	local st = fxState[zone]
	if st and st.beams and st.beams[1] and st.beams[1].Parent then return st end

	local folder = Instance.new("Folder")
	folder.Name = "_CaptureBeams"
	folder.Parent = zone.Parent

	local beams = {}
	for _, e in ipairs(edgeSpecs(zone.Size.X, zone.Size.Z)) do
		local p = Instance.new("Part")
		p.Name = "_Beam"
		p.Size = e.size
		p.CFrame = CFrame.new(zone.Position + e.off + Vector3.new(0, BEAM_HEIGHT / 2, 0))
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 220, 90)
		p.Transparency = 1
		p.Parent = folder
		beams[#beams + 1] = p
	end

	st = st or { on = false, alpha = 1, edge = EDGE_OFF }
	st.beams  = beams
	st.folder = folder
	fxState[zone] = st
	return st
end

-- ⚠️ 트윈 대신 직접 보간한다. 연결은 하나만 두고 모든 존을 훑는다.
fxConn = nil   -- ⚠️ local 없음 — 위 전방 선언에 담는다

local function startFxLoop()
	if fxConn then return end
	local RunService = game:GetService("RunService")
	fxConn = RunService.Heartbeat:Connect(function(dt)
		local k = math.min(dt * 4, 1)
		local now = os.clock()   -- 🌀 맥동 위상용. 존마다 다시 부르지 않는다.
		for zone, st in pairs(fxState) do
			if st.beams then
				for _, b in ipairs(st.beams) do
					if b.Parent then
						local cur = b.Transparency
						b.Transparency = cur + (st.alpha - cur) * k
					end
				end
			end
			if zone and zone.Parent then
				local edge = zone:FindFirstChildOfClass("SelectionBox")
				if edge then
					local e = edge.Transparency
					edge.Transparency = e + (st.edge - e) * k
				end
				-- 🟧 네온 잔상벽 페이드. 각 파트의 기본 투명도(_BaseT)와 1(완전투명) 사이를 오간다.
				--   ⚠️ 파트마다 기본 투명도가 다르다(아래단 0.45 / 위단 0.80 — buildNeonWall 의 tiers).
				--     일괄 값으로 밀면 2단 잔상 효과가 사라지므로 파트별로 목표를 계산한다.
				local wall = zone:FindFirstChild(WALL_NAME)
				if wall and st.wallAlpha then
					-- 🌀 [2026-08-30] 고정 밝기 → 둘레를 도는 맥동.
					--   ⚠️ 진폭은 반드시 swell(= 1 - wallAlpha) 로 눌러야 한다.
					--     벽이 꺼진 상태(wallAlpha = 1)에서도 맥동하면, 안 보여야 할 벽이
					--     주기적으로 깜빡여 존이 항상 켜진 것처럼 보인다.
					local swell = 1 - st.wallAlpha
					for _, w in ipairs(wall:GetChildren()) do
						local base = w:GetAttribute("_BaseT") or 0.45
						local target = base + (1 - base) * st.wallAlpha
						if swell > 0 and PULSE_DEPTH > 0 then
							local ph   = w:GetAttribute("_Phase") or 0
							local wave = math.sin((now * PULSE_SPEED + ph) * math.pi * 2)
							-- wave 가 +일 때 투명도가 내려간다 = 그 면이 밝아진다
							target = math.clamp(target - wave * PULSE_DEPTH * swell, 0, 1)
						end
						w.Transparency = w.Transparency + (target - w.Transparency) * k
					end
				end
			end
		end
	end)
end

function setCaptureFx(zone, on)   -- ⚠️ local 없음 — 위(약 208행) 전방 선언에 담는다
	local st = ensureFx(zone)
	if not st then return end
	if st.on == on then return end     -- 존별로 판정한다(예전엔 전역 fxOn 이라 한쪽만 먹혔다)
	st.on = on
	startFxLoop()
	st.alpha = on and BEAM_ALPHA_ON or 1
	st.edge  = on and EDGE_ON or EDGE_OFF
	-- 🟧 [2026-08-30] 네온 잔상벽도 '점령 중'에만 켠다.
	--   ⚠️ 켜는 시점에 없으면 만든다(지연 생성). 부팅 때 전 맵에 만들 필요가 없다.
	--   ⚠️ 실제 페이드는 위 루프가 st.wallAlpha 를 향해 보간한다.
	--     즉시 대입하면 딱딱 켜졌다 꺼져 잔상 느낌이 사라진다.
	if on and not zone:FindFirstChild(WALL_NAME) then buildNeonWall(zone) end
	st.wallAlpha = on and 0 or 1   -- 0 = 각 파트의 기본 투명도, 1 = 완전 투명
end

local function setZoneVisible(part, on)
    if not part then return end
    part.Transparency = on and ZONE_VISIBLE_TRANSPARENCY or 1
    -- 🟧 SelectionBox 는 setCaptureFx 의 페이드가 관리한다. 여기선 건드리지 않는다.
    -- 🟧 [2026-08-30] 네온 벽은 '점령 중'에만 켠다(setCaptureFx).
    --   [왜] 2단계 내내 켜두니 노란 상자가 계속 서 있어 "점령지"로 안 읽히고
    --     그냥 벽처럼 보였다. 아무도 안 밟아도 켜져 있으니 정보가 없었다.
    --   [지금] 밟는 순간에만 솟는다 → 벽이 켜지는 것 자체가 "누가 점령 중"이라는 신호다.
    --   여기서는 존이 꺼질 때(라운드 종료) 벽도 확실히 숨기는 역할만 한다.
    if not on then
        local wall = part:FindFirstChild(WALL_NAME)
        if wall then
            for _, w in ipairs(wall:GetChildren()) do w.Transparency = 1 end
        end
    end
end

-- 부팅 시 모든 맵의 존을 숨긴다.
-- ⚠️ Edit 모드에서 배치할 땐 보여야 하므로 파트 자체는 보이는 상태로 두고,
--    런타임에 이 코드가 끈다.
do
    for _, mapFolder in ipairs(workspace:GetChildren()) do
        if mapFolder:IsA("Folder") or mapFolder:IsA("Model") then
            for _, z in ipairs(collectZones(mapFolder)) do setZoneVisible(z, false) end
        end
    end
end

function CaptureSystem.start()
    zoneParts = findZones()
    if #zoneParts == 0 then
        warn("[Capture] CapturePoint 를 찾지 못했다 — 점령 비활성")
        return false
    end
    progress = 0
    zoneProgress = {}   -- ⚠️ 존별 게이지도 같이 비운다. 안 비우면 지난 라운드 진행이 이어진다
    zonePeak = {}       -- ⚠️ 최고점 기록도 같이. 안 비우면 다음 라운드에 로그가 안 찍힌다
    active = true
    for _, z in ipairs(zoneParts) do setZoneVisible(z, true) end   -- 🏆 2단계 진입 — 이제 목표가 보인다
    capEvent:FireAllClients("start", 0, 0, false)
    if loopConn then loopConn:Disconnect() end
    local acc = 0
    loopConn = RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc >= TICK then
            step(acc)
            acc = 0
        end
    end)
    print(string.format("👑 [Capture] 점령 시작 — 목표 %.0f초 / 존 %d개 (대표 %s)",
        CAPTURE_GOAL, #zoneParts, zoneParts[1]:GetFullName():gsub("^game%.", "")))
    return true
end

function CaptureSystem.stop()
	clearCaptureFx()
    active = false
    if loopConn then loopConn:Disconnect() ; loopConn = nil end
    progress = 0
    zoneProgress = {}   -- ⚠️ 존별 게이지도 같이 비운다("켜는 코드에는 끄는 코드를")
    zonePeak = {}
    -- 🏆 월드 게이지 제거. 라운드가 끝나도 남으면 로비에서 40% 짜리 바가 떠 있다.
    for _, z in ipairs(zoneParts) do
        local g = z and z.Parent and z:FindFirstChild(GAUGE_NAME)
        if g then g:Destroy() end
    end
    activeZone = nil   -- ⚠️ 안 지우면 라운드가 끝나도 봇이 이전 존으로 계속 향한다
    -- ⚠️ 라운드가 끝나면 반드시 숨긴다. "켜는 코드에는 끄는 코드를 같이"
    --    안 그러면 로비로 돌아가서도 존이 보인다.
    -- ⚠️ zoneParts 만 끄면 부족하다. 맵이 바뀌었거나 start 가 실패했으면
    --    다른 맵의 존이 켜진 채 남을 수 있으므로 전부 훑는다.
    for _, mapFolder in ipairs(workspace:GetChildren()) do
        if mapFolder:IsA("Folder") or mapFolder:IsA("Model") then
            for _, z in ipairs(collectZones(mapFolder)) do setZoneVisible(z, false) end
        end
    end
    capEvent:FireAllClients("stop", 0, 0, false)
end

function CaptureSystem.getProgress()
    return progress / CAPTURE_GOAL
end

-- 🤖 [2026-08-30] 태거봇이 "지금 어느 존을 막아야 하나"를 물을 때 쓴다.
--   차오르는 중인 존을 반환하고, 아니면 nil.
function CaptureSystem.getActiveZone()
    return activeZone
end

-- 🤖 [2026-09-04] 봇 러너가 점령을 목표로 삼을 수 있게 존과 판정을 함께 내준다.
--   [왜 판정까지] 봇 쪽에서 "존 안인가"를 따로 구현하면 같은 규칙이 두 곳에 생긴다.
--     09-01 문서의 "같은 규칙이 두 곳에 있으면 한쪽만 고쳐진다" 사고 유형이고,
--     실제로 태거 베이스 판정이 SpearSystem 에서 그 이유로 깨진 이력이 있다.
--     → 봇은 여기서 받은 존 목록과 이 판정 함수만 쓴다.
--   ⚠️ getZones 는 파괴된 파트를 걸러서 넘긴다. 라운드 사이 재건 타이밍에
--     Parent 가 nil 인 항목이 섞인다.
function CaptureSystem.getZones()
    local out = {}
    for _, z in ipairs(zoneParts) do
        if z.Parent then table.insert(out, z) end
    end
    return out
end

function CaptureSystem.isCharInZone(char, zone)
    if not (char and zone and zone.Parent) then return false end
    return isInZone(char, zone)
end

-- 🤖 [2026-09-04] 존별 진행도(0~1). 봇이 "어느 존이 앞섰나"를 판단하는 데 쓴다.
--   [왜 필요] 봇이 '가까운 존'으로만 가니 스폰 위치에 따라 8:2 로 갈렸고,
--     양쪽 다 안 차서 킹이 어느 쪽도 못 막는 그림이 나왔다(22:57 판).
--   ⚠️ 비율로 내준다. 봇이 CAPTURE_GOAL 을 알 필요가 없다 —
--     목표치가 바뀌어도 호출부를 안 고친다.
function CaptureSystem.getZoneProgress(zone)
    if not (zone and zone.Parent) then return 0 end
    for i, z in ipairs(zoneParts) do
        if z == zone then
            return math.clamp((zoneProgress[i] or 0) / CAPTURE_GOAL, 0, 1)
        end
    end
    return 0
end

-- 🧪 [테스트 2026-09-05] 점령 게이지를 원하는 비율로 채운다. /capfill 이 부른다.
--   [왜 필요] 점령 완료 연출(ThroneFall)을 검증하려면 매번 18초를 채워야 하는데,
--     봇전에서 그 상황까지 가는 데 판당 1분 이상 걸려 반복 확인이 사실상 불가능했다.
--   [왜 여기인가] zoneProgress 는 이 파일의 지역 변수라 밖에서 못 건드린다.
--     외부에 노출하는 대신 "채우기"라는 좁은 동작만 API 로 연다.
--   ⚠️ [수정 2026-09-05] 기본값 0.95 → 1.0. 95%는 한 번도 완료되지 않았다.
--     [실측] "/capfill → 95%" 직후 로그가 "존 침범 감지 (점령 75%)" 였다.
--     [원인] step() 은 ①채움 ②빈 존 감쇠 ③완료판정 순서다. 테스트 중에는 존이
--       비어 있으므로 ②가 먼저 돌아 17.1 → 체크포인트 13.5(75%)로 떨어지고,
--       ③은 18 에 도달한 걸 볼 기회가 없었다.
--     [왜 1.0 은 되나] 빈 존 감쇠는 체크포인트 아래로 못 내려간다:
--       mark = floor(18/4.5)*4.5 = 18 → math.max(18, 18-감쇠) = 18. 그대로 남는다.
--   ⚠️ 그래도 '테스트 전용 완료 처리'를 만들지는 않았다. 게이지만 세우고 완료 판정과
--     그 뒤(ThroneFall·연출·봇 전환)는 전부 실제 라운드와 같은 코드가 실행한다.
--   ⚠️ 릴리즈 전 삭제. DevAuth 게이트가 있지만 이 함수 자체가 테스트 전용이다.
function CaptureSystem.debugFill(ratio)
    if not active then return false, "점령이 시작되지 않았다(2단계 진입 전)" end
    if #zoneParts == 0 then return false, "존이 없다" end
    local r = math.clamp(tonumber(ratio) or 1.0, 0, 1)
    local target = CAPTURE_GOAL * r
    -- 대표 존(1번)만 채운다. 둘 다 채우면 어느 쪽이 완료를 냈는지 분간이 안 된다.
    zoneProgress[1] = target
    if zonePeak then zonePeak[1] = math.max(zonePeak[1] or 0, target) end
    progress = target
    return true, string.format("존1 게이지 %.0f%% (%.1f/%.1f)", r * 100, target, CAPTURE_GOAL)
end

_G.CaptureSystem = CaptureSystem

print("✅ CaptureSystem 로드됨 (목표 " .. CAPTURE_GOAL .. "초 / 상승 "
    .. FILL_RATE .. " / 감쇠 " .. DECAY_RATE .. ")")
