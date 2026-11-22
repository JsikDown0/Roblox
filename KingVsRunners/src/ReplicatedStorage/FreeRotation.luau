-- ═══════════════════════════════════════════════════════════════
-- FreeRotation — 태거 아이템 일간 무료 로테이션
--
-- [왜] 무료 기본 아이템이 3종뿐인데 로드아웃은 4칸이다. 신규 태거는 구조적으로
--      빈 슬롯을 들고 시작한다("3/4 Equipped"). 그리고 유료 아이템 8종을
--      써볼 기회가 없어 구매 판단 근거도 없다.
--
-- [설계] 매일 2종을 무료 개방. Epic 까지만, Legendary/게임패스는 제외한다.
--   ⚠️ 2종인 이유: 태거가 되는 빈도가 낮다. 실측 기준 10명 판에서 태거 1회에
--      약 36분이 걸려(피티 시스템 기준 평균 주기 = 인원수 라운드), 세션당
--      0.4~0.8회다. 1종만 열면 그 한 번이 취향에 안 맞을 때 로테이션의 존재조차
--      모르고 지나간다. 2종이면 한 번의 기회에 선택지가 생긴다.
--   ⚠️ 무료 3종 + 로테 2종 = 5종이라 4칸을 채우고도 하나 남는다(빈 슬롯 해소).
--
-- [기준 시각] UTC 자정. 서버 로컬 시간을 쓰면 서버마다 결과가 달라져
--   "친구는 되는데 나는 안 된다"가 생긴다. 출석 보상도 날짜 기반이라 기준이 일치한다.
--
-- ⚠️ 서버와 클라가 모두 이 모듈을 쓴다. 한쪽이 다른 계산을 하면
--    "무료라고 표시되는데 장착이 거부되는" 상태가 된다.
-- ═══════════════════════════════════════════════════════════════

local FreeRotation = {}

-- 로테이션 대상. ⚠️ Legendary(tnt/EnergyBall)와 게임패스(Frost Dragon)는 넣지 않는다.
--   최상위 등급까지 무료로 돌면 "기다리면 다 써볼 수 있다"가 되어 구매 동기가 사라진다.
-- ⚠️ 이름은 ALL_ITEMS 의 name 과 정확히 일치해야 한다(대소문자 포함).
FreeRotation.POOL = {
    "Spear",
    "Demonspear",
    "ItemNoob",
    "bear_trap",
    "tox_box",
    "tsunami",
    "BlackHole",
}

FreeRotation.COUNT = 2   -- 하루에 여는 개수

-- UTC 기준 일련일. 이 값이 바뀌면 로테이션도 바뀐다.
-- ⚠️ 테스트용 오프셋(DayShift)을 더한다. 하루를 기다리지 않고 다음 날 로테이션을
--    확인하기 위한 것이고, 서버가 ReplicatedStorage 속성으로 심으면 클라도 같이 읽는다.
--    (같은 모듈을 양쪽이 쓰므로 오프셋도 자동으로 공유된다)
function FreeRotation.dayIndex()
    local shift = 0
    local ok, v = pcall(function()
        return game:GetService("ReplicatedStorage"):GetAttribute("FreeRotDayShift")
    end)
    if ok and type(v) == "number" then shift = v end
    return math.floor(os.time() / 86400) + shift
end

-- 다음 리셋까지 남은 초.
function FreeRotation.secondsUntilReset()
    return 86400 - (os.time() % 86400)
end

-- 오늘 열린 아이템 이름 배열.
-- ⚠️ 난수를 쓰지 않는다. 서버·클라·재접속이 모두 같은 결과여야 하므로
--    dayIndex 로부터 결정적으로 계산한다.
-- ⚠️ 단순히 (day % N) 로 두 개를 연속으로 뽑으면 매일 같은 짝이 붙어 다닌다.
--    두 번째 오프셋에 서로소인 보폭을 줘서 짝 조합이 매일 달라지게 한다.
function FreeRotation.todayItems()
    local pool = FreeRotation.POOL
    local n = #pool
    if n == 0 then return {} end

    local day = FreeRotation.dayIndex()
    local out, seen = {}, {}

    -- 보폭 3 은 7(POOL 크기)과 서로소라 모든 조합을 순회한다.
    -- POOL 크기를 바꾸면 이 값이 여전히 서로소인지 확인할 것.
    local STRIDE = 3
    for k = 0, FreeRotation.COUNT - 1 do
        local idx = ((day + k * STRIDE) % n) + 1
        -- 중복 방지(COUNT 가 n 에 가까울 때)
        local guard = 0
        while seen[idx] and guard < n do
            idx = (idx % n) + 1
            guard = guard + 1
        end
        seen[idx] = true
        out[#out + 1] = pool[idx]
    end
    return out
end

-- 특정 아이템이 오늘 무료인가.
function FreeRotation.isFreeToday(itemName)
    if not itemName then return false end
    for _, nm in ipairs(FreeRotation.todayItems()) do
        if nm == itemName then return true end
    end
    return false
end

-- "07:12" 형태의 남은 시간 문자열 (UI 표시용)
function FreeRotation.formatRemaining()
    local s = FreeRotation.secondsUntilReset()
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    return string.format("%02d:%02d", h, m)
end

return FreeRotation
