-- ════════════════════════════════════════════════════════════════
-- DailyRewardSystem  (ServerScriptService / ModuleScript)
-- ────────────────────────────────────────────────────────────────
-- 일일 접속(출석) 보상. 7일 주기 단일 트랙(모든 유저 동일).
--  · 하루 1회 수령, 다음 날 다음 Day 해금
--  · 7일 모두 받으면 Day 1부터 반복
--  · 연속 끊김(하루 이상 미접속) 시 Day 1로 리셋
--  · DataStore 영구 저장
--
-- [저장 데이터] { day = 현재수령가능Day(1~7), lastClaim = 마지막수령 epoch(일 단위) }
-- ════════════════════════════════════════════════════════════════

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local rewardStore = DataStoreService:GetDataStore("PlayerDailyReward_v1")

local DailyRewardSystem = {}

-- ── 7일 보상 테이블 ──────────────────────────────────────────────
--  reward: { coins=, spins=, box=, skin= }  (표시는 icon/label/amount)
--  icon   : 보상 아이콘 에셋
--  amount : UI에 표시할 수량 텍스트
-- ⚠️ box = "skin" 은 grantReward 가 즉시 개봉한다(QuestSystem 과 동일 경로).
--    그 외 박스 타입은 PendingBox_* 속성으로 적립만 되고 소비처가 없으니 쓰지 말 것.
--    spins 는 PendingSpins 속성으로 적립된다(스핀 UI 는 별도).
--    Day 7 을 스킨 박스로 둔 이유: 7일 전부 코인이면 "매일 올 이유"가 약하다.
--    마일스톤에 다른 종류를 둬야 접속 동기가 생긴다.
local REWARDS = {
    [1] = { reward = { coins = 100 },  icon = "rbxassetid://109002720549611", amount = "100 Coins",  label = "100 Coins" },
    [2] = { reward = { coins = 120, box = "skin" }, icon = "rbxassetid://94217991091339", amount = "120 Coins\n+ Skin Box", label = "120 Coins + Skin Box" },
    [3] = { reward = { coins = 200 },  icon = "rbxassetid://109002720549611", amount = "200 Coins",  label = "200 Coins" },
    [4] = { reward = { coins = 300, box = "skin" }, icon = "rbxassetid://94217991091339", amount = "300 Coins\n+ Skin Box", label = "300 Coins + Skin Box" },
    [5] = { reward = { coins = 420 },  icon = "rbxassetid://109002720549611", amount = "420 Coins",  label = "420 Coins" },
    [6] = { reward = { coins = 600, box = "skin" }, icon = "rbxassetid://94217991091339", amount = "600 Coins\n+ Skin Box", label = "600 Coins + Skin Box" },
    [7] = { reward = { coins = 1450, boxes = { { type = "skin", grade = "plus" }, { type = "cosmetic" } } }, icon = "rbxassetid://94217991091339", amount = "1450 Coins\nRare+ & Cosmetic Box", label = "1450 Coins + Rare+ Box + Cosmetic Box" },
}
DailyRewardSystem.REWARDS = REWARDS
local TOTAL_DAYS = 7

-- ── 메모리 상태 ──────────────────────────────────────────────────
-- activeData[userId] = { day = 1~7, lastClaim = epochDay(정수) }
local activeData = {}

-- 현재 epoch을 "일 단위 정수"로 (UTC 자정 기준 날짜 번호)
local function epochDay()
    return math.floor(os.time() / 86400)
end

local function freshData()
    return { day = 1, lastClaim = 0 }  -- lastClaim=0 → 아직 한 번도 안 받음
end

-- ── 로드 ─────────────────────────────────────────────────────────
function DailyRewardSystem.load(player)
    local userId = player.UserId
    local ok, saved = pcall(function()
        return rewardStore:GetAsync(tostring(userId))
    end)

    local data
    if ok and type(saved) == "table" and saved.day then
        data = saved
        data.day = math.clamp(data.day, 1, TOTAL_DAYS)
        data.lastClaim = data.lastClaim or 0
    else
        if not ok then warn("[DailyReward] 로드 실패(새 데이터):", player.Name) end
        data = freshData()
    end

    activeData[userId] = data
    -- 연속 끊김 검사: 마지막 수령일이 어제도 오늘도 아니면 streak 리셋
    DailyRewardSystem.checkStreak(userId)
    print("🎁 출석 보상 로드:", player.Name, "Day", data.day)
    return data
end

-- ── 연속 끊김 검사 ───────────────────────────────────────────────
-- 마지막 수령일과 오늘 차이가 2일 이상이면(=하루 통째로 빠짐) Day 1로 리셋.
function DailyRewardSystem.checkStreak(userId)
    local data = activeData[userId]
    if not data then return end
    if data.lastClaim == 0 then return end  -- 첫 수령 전이면 검사 불필요

    local today = epochDay()
    local gap = today - data.lastClaim
    if gap >= 2 and data.day > 1 then
        -- 하루 이상 건너뜀 → 연속 리셋
        -- ⚠️ [2026-08-26] `data.day > 1` 가드 추가.
        --   [증상] 접속 한 번에 "🔄 출석 연속 끊김 → Day 1 리셋" 이 4번 찍혔다.
        --   [원인] checkStreak 를 load(1회) + claim + getSnapshot 이 각각 부르는데,
        --     getSnapshot 은 클라가 UI 상태를 물을 때마다 돈다(접속 시 3회).
        --     이미 Day 1 인데도 매번 day=1 을 다시 쓰고 로그를 뱉었다.
        --   [범위] DataStore 는 건드리지 않으므로 낭비가 아니라 로그 노이즈였다.
        --     다만 실제 리셋 시점을 로그에서 구분할 수 없게 만들어 진단을 방해했다.
        --   → 이제 "실제로 값이 바뀌는 순간" 한 번만 찍힌다.
        data.day = 1
        print("🔄 출석 연속 끊김 → Day 1 리셋:", userId)
    end
end

-- ── 저장 ─────────────────────────────────────────────────────────
function DailyRewardSystem.save(player)
    local data = activeData[player.UserId]
    if not data then return end
    local ok, err = pcall(function()
        rewardStore:SetAsync(tostring(player.UserId), data)
    end)
    if not ok and _G.ReportSaveFailure then _G.ReportSaveFailure("PlayerDailyReward_v1", err) end
end

function DailyRewardSystem.unload(player)
    DailyRewardSystem.save(player)
    activeData[player.UserId] = nil
end

-- ── 오늘 수령 가능 여부 ──────────────────────────────────────────
-- 마지막 수령일이 오늘이 아니면 수령 가능.
function DailyRewardSystem.canClaim(userId)
    local data = activeData[userId]
    if not data then return false end
    return data.lastClaim ~= epochDay()
end

-- ── 보상 지급 공통 헬퍼 ──────────────────────────────────────────
local function grantReward(player, r)
    r = r or {}
    if r.coins and r.coins > 0 then
        if _G.CoinSystem and _G.CoinSystem.addCoins then
            _G.CoinSystem.addCoins(player, r.coins)
        else
            player:SetAttribute("Coins", (player:GetAttribute("Coins") or 0) + r.coins)
        end
    end
    if r.spins and r.spins > 0 then
        player:SetAttribute("PendingSpins", (player:GetAttribute("PendingSpins") or 0) + r.spins)
    end
    -- ⚠️ [BOX-GRANT] PendingBox_* 속성만 세우면 아무도 소비하지 않는다.
    --    전수 검색 결과 소비처가 0곳이라, 유저는 받은 걸 영영 못 연다
    --    (실측 2026-08-21). QuestSystem 과 동일하게 즉시 개봉한다.
    -- [BOX-GRADE] grade 는 로벅스 상점과 같은 체계:
    --    common = Color Skin Box(R$18) / plus = Rare+ Box(R$45) / mega = Epic+ Box(R$90)
    --    ⚠️ mega 는 유료 최상위라 무료 경로에서 주지 않는다.
    local function openOneBox(boxType, grade)
        local ev = ReplicatedStorage:FindFirstChild("RareSkinReward")
        local res
        if boxType == "skin" then
            res = _G.grantRandomSkin and _G.grantRandomSkin(player, grade) or nil
        elseif boxType == "cosmetic" then
            res = _G.grantRandomCosmetic and _G.grantRandomCosmetic(player, grade) or nil
            -- [COSMETIC-BOX-SKIN] 클라 컷신이 이 플래그를 보고 상자 외형을 바꾼다
            --   (RareSkinRewardCard:483 — 바이올렛 우드 + 골드 트림).
            --   ⚠️ 이 플래그가 없으면 일반 스킨 박스와 똑같이 보인다.
            if res then res.cosmeticBox = true end
        else
            -- 개봉 경로가 없는 타입. 새 타입을 쓰려면 여기 분기를 먼저 만들 것.
            local key = "PendingBox_" .. tostring(boxType)
            player:SetAttribute(key, (player:GetAttribute(key) or 0) + 1)
            return
        end
        if res and ev then
            res.fromBox = true   -- 클라 상자 열림 컷신
            ev:FireClient(player, res)
        elseif _G.CoinSystem and _G.CoinSystem.addCoins then
            _G.CoinSystem.addCoins(player, 100)   -- 전부 보유 → 코인 폴백
        end
    end

    -- 단일: box/grade  ·  복수: boxes = { {type=, grade=}, ... }
    --   ⚠️ 복수일 때 클라의 boxQueue 가 순차 처리하므로 연출이 겹치지 않는다.
    if r.box then openOneBox(r.box, r.grade) end
    if r.boxes then
        for _, b in ipairs(r.boxes) do openOneBox(b.type, b.grade) end
    end
end

-- ── 수령 ─────────────────────────────────────────────────────────
function DailyRewardSystem.claim(player)
    local userId = player.UserId
    local data = activeData[userId]
    if not data then return false, "nodata" end

    DailyRewardSystem.checkStreak(userId)

    if not DailyRewardSystem.canClaim(userId) then
        return false, "alreadyToday"
    end

    local dayInfo = REWARDS[data.day]
    if not dayInfo then return false, "baddata" end

    grantReward(player, dayInfo.reward)
    print(string.format("🎁 출석 보상 수령: %s Day %d (%s)",
        player.Name, data.day, dayInfo.label or "?"))

    -- 다음 Day로 진행 (7일 넘으면 1로 순환)
    data.lastClaim = epochDay()
    data.day = data.day + 1
    if data.day > TOTAL_DAYS then data.day = 1 end

    DailyRewardSystem.save(player)
    DailyRewardSystem.pushToClient(player)
    return true
end

-- ── 클라이언트 스냅샷 ────────────────────────────────────────────
function DailyRewardSystem.getSnapshot(player)
    local data = activeData[player.UserId]
    if not data then return nil end
    DailyRewardSystem.checkStreak(player.UserId)

    local canClaimToday = DailyRewardSystem.canClaim(player.UserId)
    local days = {}
    for i = 1, TOTAL_DAYS do
        local info = REWARDS[i]
        local state
        if i < data.day then
            state = "claimed"          -- 이미 받은 날
        elseif i == data.day then
            state = canClaimToday and "claimable" or "locked"  -- 오늘 받을 날
        else
            state = "locked"           -- 미래
        end
        table.insert(days, {
            day    = i,
            icon   = info.icon,
            amount = info.amount,
            label  = info.label,
            state  = state,
        })
    end

    -- 다음 수령 가능까지 남은 초 계산
    -- epochDay는 UTC 자정 기준 → 다음 자정 = (현재epochDay+1)*86400
    local now = os.time()
    local nextResetEpoch = (epochDay() + 1) * 86400
    local secondsLeft = canClaimToday and 0 or math.max(0, nextResetEpoch - now)

    return {
        days        = days,
        currentDay  = data.day,
        canClaim    = canClaimToday,
        totalDays   = TOTAL_DAYS,
        secondsLeft = secondsLeft,  -- 다음 수령까지 남은 초 (0이면 지금 수령 가능)
        serverNow   = now,
    }
end

-- [REWARD-DEBUG] 테스트용. 오늘 수령 기록만 지워 다시 수령 가능하게 만든다.
--   ⚠️ data.day(진행 일차)는 건드리지 않는다 → 같은 Day 를 반복 검증할 수 있다.
--   isDev 게이트는 호출부(DownedBotSystem)가 담당. 검증 후 이 함수와 커맨드를 함께 제거할 것.
function DailyRewardSystem.debugResetClaim(player)
    local data = activeData[player.UserId]
    if not data then return false end
    data.lastClaim = nil
    DailyRewardSystem.save(player)
    DailyRewardSystem.pushToClient(player)
    return true
end

-- [REWARD-DEBUG] 특정 Day 로 점프 (Day 2/7 같은 마일스톤 검증용)
function DailyRewardSystem.debugSetDay(player, day)
    local data = activeData[player.UserId]
    if not data then return false end
    day = tonumber(day)
    if not day or day < 1 or day > TOTAL_DAYS then return false end
    data.day = day
    data.lastClaim = nil
    DailyRewardSystem.save(player)
    DailyRewardSystem.pushToClient(player)
    return true
end

function DailyRewardSystem.pushToClient(player)
    local ev = ReplicatedStorage:FindFirstChild("DailyRewardUpdate")
    if ev then
        ev:FireClient(player, DailyRewardSystem.getSnapshot(player))
    end
end

return DailyRewardSystem
