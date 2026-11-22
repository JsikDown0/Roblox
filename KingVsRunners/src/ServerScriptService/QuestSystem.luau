-- ════════════════════════════════════════════════════════════════
-- QuestSystem  (ServerScriptService / ModuleScript)
-- ────────────────────────────────────────────────────────────────
-- 일일/주간 퀘스트의 정의 · 진행도 추적 · DataStore 영구 저장 ·
-- 일/주 단위 자동 리셋 · 보상 지급을 담당하는 핵심 모듈.
--
-- [설계]
--  · 다른 시스템은 QuestSystem.addProgress(player, "metric", amount) 한 줄만 호출.
--    metric 종류: play, win, kill, survive, coinsEarned, reachStage2,
--                 reviveGiven(부활시켜주기), reviveTaken(부활당하기)
--  · 각 퀘스트 정의가 어떤 metric을 듣는지 listens 필드로 매핑.
--  · 진행도는 메모리(activeData)에서 즉시 갱신, DataStore에 영구 저장.
--  · 일일/주간 리셋은 마지막 리셋 시각을 저장해두고, 로드/주기적으로 비교해 처리.
--
-- [저장 키] tostring(player.UserId)  (LoadoutManager 패턴과 동일)
-- ════════════════════════════════════════════════════════════════

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService  = game:GetService("DataStoreService")

local questStore = DataStoreService:GetDataStore("PlayerQuestData_v1")

local QuestSystem = {}

-- ── 리셋 주기 (초) ───────────────────────────────────────────────
local DAY_SECONDS  = 24 * 60 * 60
local WEEK_SECONDS = 7 * DAY_SECONDS

-- ════════════════════════════════════════════════════════════════
-- 퀘스트 정의
--   id       : 고유 식별자 (저장 키로도 사용)
--   category : "daily" | "weekly"
--   title    : UI 표시용 제목
--   desc     : 상세 설명
--   metric   : 이 퀘스트가 듣는 진행 신호
--   role     : nil(무관) | "Runner" | "Tagger"  (특정 진영 행동만 카운트)
--   goal     : 목표 수치
--   reward   : { coins = n, spins = n, box = "타입" }  (없는 필드는 0/nil)
-- ════════════════════════════════════════════════════════════════
local QUEST_DEFS = {
    -- ── 일일 ──────────────────────────────────────────────────
    {
        id = "d_warmup", category = "daily",
        title = "Warm Up", desc = "Play 3 rounds",
        metric = "play", role = nil, goal = 3,
        reward = { coins = 120 },
    },
    {
        id = "d_firstblood", category = "daily",
        title = "First Blood", desc = "Eliminate 3 enemies as any role",
        metric = "kill", role = nil, goal = 3,
        reward = { coins = 150 },
    },
    {
        id = "d_breaker", category = "daily",
        title = "Breakthrough", desc = "Reach Stage 2 as a Runner 2 times",
        metric = "reachStage2", role = "Runner", goal = 2,
        reward = { coins = 180 },
    },
    {
        id = "d_firstwin", category = "daily",
        title = "First Win", desc = "Win 1 round",
        metric = "win", role = nil, goal = 1,
        reward = { coins = 150 },
    },
    {
        id = "d_collector", category = "daily",
        title = "Collector", desc = "Earn 100 coins in rounds",
        metric = "coinsEarned", role = nil, goal = 100,
        reward = { coins = 100 },
    },

    -- ── 주간 ──────────────────────────────────────────────────
    {
        id = "w_guardian", category = "weekly",
        title = "Wall Guardian", desc = "Eliminate 50 Runners as King",
        metric = "kill", role = "Tagger", goal = 50,
        reward = { coins = 700 },
    },
    {
        id = "w_survivor", category = "weekly",
        title = "Comeback Survivor", desc = "Win 10 times as a Runner",
        metric = "win", role = "Runner", goal = 10,
        reward = { coins = 800 },
    },
    {
        id = "w_throughfire", category = "weekly",
        title = "Through the Fire", desc = "Reach Stage 2 as a Runner 15 times",
        metric = "reachStage2", role = "Runner", goal = 15,
        reward = { coins = 600 },
    },
    {
        id = "w_revived", category = "weekly",
        title = "Hard to Kill", desc = "Get revived by teammates 10 times as Runner",
        metric = "reviveTaken", role = "Runner", goal = 10,
        reward = { coins = 400, box = "skin" },
    },
    {
        id = "w_savior", category = "weekly",
        title = "Savior", desc = "Revive downed teammates 10 times as Runner",
        metric = "reviveGiven", role = "Runner", goal = 10,
        reward = { coins = 500, box = "skin" },
    },
    {
        id = "w_hunter", category = "weekly",
        title = "Season Hunter", desc = "100 total eliminations (both roles)",
        metric = "kill", role = nil, goal = 100,
        reward = { coins = 500, box = "skin" },   -- killeffect 박스는 소비처가 없어 스킨 박스로 대체
    },
    {
        id = "w_settler", category = "weekly",
        title = "Settler", desc = "Play 30 rounds",
        metric = "play", role = nil, goal = 30,
        reward = { coins = 900 },
    },
}
QuestSystem.QUEST_DEFS = QUEST_DEFS

-- ════════════════════════════════════════════════════════════════
-- 완주(전체 완료) 보너스 정의
--   해당 카테고리의 모든 퀘스트를 수령(claimed)하면 추가 지급.
--   카테고리별 1회만 (claimed 플래그로 중복 방지, 리셋 시 함께 초기화)
-- ════════════════════════════════════════════════════════════════
local COMPLETION_REWARDS = {
    daily  = { coins = 200, box = "skin" },
    weekly = { coins = 1500, box = "skin", grade = "plus" },   -- Rare+ 상당
}
QuestSystem.COMPLETION_REWARDS = COMPLETION_REWARDS

-- id → 정의 빠른 조회
local DEF_BY_ID = {}
for _, def in ipairs(QUEST_DEFS) do
    DEF_BY_ID[def.id] = def
end

-- ════════════════════════════════════════════════════════════════
-- 메모리 상태
--   activeData[userId] = {
--     daily  = { lastReset = epoch, quests = { [id] = {progress=, claimed=} } },
--     weekly = { lastReset = epoch, quests = { ... } },
--   }
-- ════════════════════════════════════════════════════════════════
local activeData = {}
-- ⚠️ [SAVE-BURST] 진행도 변경 시 즉시 저장하지 않고 여기에 표시만 한다.
--    라운드 종료 시 RoundSystem 이 addProgress 를 6번 연속 호출하는데(play/win/
--    survive/kill/coin/reach), 매번 SetAsync 하면 플레이어 1명당 6회 쓰기가 된다.
--    DataStore 쓰기 큐는 30개 고정이라 8명이면 48회로 넘쳐 요청이 드롭된다
--    (실측 2026-08-22: 솔로에서도 "request was added to queue" 경고 발생).
--    ⚠️ 플래그를 켜는 곳과 끄는 곳은 반드시 짝으로 관리할 것 —
--       끄는 쪽이 빠지면 저장이 영영 안 되어 데이터 유실보다 나쁜 상태가 된다.
local dirtyQuest = {}   -- [userId] = true

-- 빈 카테고리 진행도 테이블 생성
local function freshCategory(category)
    local quests = {}
    for _, def in ipairs(QUEST_DEFS) do
        if def.category == category then
            quests[def.id] = { progress = 0, claimed = false }
        end
    end
    return { lastReset = os.time(), quests = quests, bonusClaimed = false }
end

-- 빈 전체 데이터 생성
local function freshData()
    return {
        daily  = freshCategory("daily"),
        weekly = freshCategory("weekly"),
    }
end

-- 정의가 바뀌었을 때(퀘스트 추가/삭제) 저장된 데이터를 현재 정의에 맞춰 보정
local function reconcileCategory(catData, category)
    catData.quests = catData.quests or {}
    -- 현재 정의에 있는 퀘스트는 보존, 없으면 0으로 추가
    local valid = {}
    for _, def in ipairs(QUEST_DEFS) do
        if def.category == category then
            local existing = catData.quests[def.id]
            valid[def.id] = existing or { progress = 0, claimed = false }
        end
    end
    catData.quests = valid
    catData.lastReset = catData.lastReset or os.time()
    catData.bonusClaimed = catData.bonusClaimed or false
    return catData
end

-- ── 리셋 검사 ────────────────────────────────────────────────────
-- 마지막 리셋 이후 주기가 지났으면 해당 카테고리를 초기화.
local function checkReset(userId)
    local data = activeData[userId]
    if not data then return end
    local now = os.time()

    if now - data.daily.lastReset >= DAY_SECONDS then
        data.daily = freshCategory("daily")
        print("🔄 일일 퀘스트 리셋:", userId)
    end
    if now - data.weekly.lastReset >= WEEK_SECONDS then
        data.weekly = freshCategory("weekly")
        print("🔄 주간 퀘스트 리셋:", userId)
    end
end

-- ── DataStore 로드 ───────────────────────────────────────────────
function QuestSystem.load(player)
    local userId = player.UserId
    local ok, saved = pcall(function()
        return questStore:GetAsync(tostring(userId))
    end)

    local data
    if ok and type(saved) == "table" and saved.daily and saved.weekly then
        data = saved
        reconcileCategory(data.daily, "daily")
        reconcileCategory(data.weekly, "weekly")
    else
        if not ok then
            warn("[QuestSystem] 로드 실패(새 데이터로 시작):", player.Name)
        end
        data = freshData()
    end

    activeData[userId] = data
    checkReset(userId)
    print("📜 퀘스트 로드 완료:", player.Name)
    return data
end

-- ── DataStore 저장 ───────────────────────────────────────────────
function QuestSystem.save(player)
    local userId = player.UserId
    local data = activeData[userId]
    if not data then return end
    local ok, err = pcall(function()
        questStore:SetAsync(tostring(userId), data)
    end)
    -- 🛡️ [2026-09-06] 실패 보고. 여기는 이미 ok 로 dirty 플래그를 관리하고 있어
    --   실패를 '알고는' 있었지만 아무 데도 남기지 않았다.
    if not ok and _G.ReportSaveFailure then _G.ReportSaveFailure("PlayerQuestData_v1", err) end
    -- [SAVE-BURST] 성공했을 때만 플래그를 내린다.
    --   ⚠️ 실패했는데 내리면 변경분이 영영 저장되지 않는다.
    --   ⚠️ save 안에 두는 이유: claim / unload / debug 등 모든 저장 경로가
    --      자동으로 처리되어, 경로마다 해제 코드를 빠뜨릴 위험이 없다.
    if ok then dirtyQuest[userId] = nil end
    return ok
end

-- 플레이어 퇴장 시 저장 후 메모리 해제
function QuestSystem.unload(player)
    QuestSystem.save(player)
    activeData[player.UserId] = nil
    dirtyQuest[player.UserId] = nil   -- 저장 실패해도 메모리가 사라지므로 함께 정리
end

-- ════════════════════════════════════════════════════════════════
-- 진행도 추가 (다른 시스템이 호출하는 단 하나의 진입점)
--   metric : "play"|"win"|"kill"|"survive"|"coinsEarned"
--            |"reachStage2"|"reviveGiven"|"reviveTaken"
--   amount : 증가량 (기본 1)
--   role   : 이 행동을 한 시점의 진영 ("Runner"/"Tagger"/nil)
--            → 정의의 role과 비교해 진영 한정 퀘스트를 필터링
-- ════════════════════════════════════════════════════════════════
function QuestSystem.addProgress(player, metric, amount, role)
    amount = amount or 1
    if amount <= 0 then return end

    local data = activeData[player.UserId]
    if not data then return end

    checkReset(player.UserId)

    local changed = false
    for _, def in ipairs(QUEST_DEFS) do
        if def.metric ~= metric then continue end
        -- 진영 한정 퀘스트면 행동 진영이 일치해야 함
        if def.role ~= nil and def.role ~= role then continue end

        local catData = (def.category == "daily") and data.daily or data.weekly
        local q = catData.quests[def.id]
        if not q then continue end
        if q.claimed then continue end          -- 이미 보상 수령
        if q.progress >= def.goal then continue end -- 이미 목표 달성(미수령 대기)

        q.progress = math.min(q.progress + amount, def.goal)
        changed = true

        if q.progress >= def.goal then
            print(string.format("✅ 퀘스트 달성: [%s] %s (%s)",
                def.category, def.title, player.Name))
        end
    end

    if changed then
        -- [SAVE-BURST] 즉시 저장하지 않는다. 플래그만 세우고 flushDirty 가 모아서 저장.
        --   pushToClient 는 유지 — UI 갱신은 DataStore 와 무관하고 비용도 없다.
        dirtyQuest[player.UserId] = true
        QuestSystem.pushToClient(player)
    end
end

-- [SAVE-BURST] 변경분이 있는 플레이어만 저장한다. 라운드 종료·이탈·종료 시 호출.
--   ⚠️ 플래그는 저장 '뒤에' 내린다. 앞에서 내리면 저장 실패 시 변경분이 사라진다.
function QuestSystem.flushDirty(player)
    if not player then return false end
    if not dirtyQuest[player.UserId] then return false end
    -- 해제는 save 내부에서 처리된다(성공 시에만).
    return QuestSystem.save(player) and true or false
end

-- ════════════════════════════════════════════════════════════════
-- 보상 수령
--   목표 달성 + 미수령 상태일 때만 지급. 코인은 즉시, 그 외(스핀/박스)는
--   속성 누적으로 표시(추후 해당 시스템이 소비). 성공 시 claimed=true.
-- ════════════════════════════════════════════════════════════════
-- ── 보상 지급 공통 헬퍼 ──────────────────────────────────────────
-- reward = { coins=, spins=, box= } 형태를 받아 실제 지급.
local function grantReward(player, r)
    r = r or {}
    if r.coins and r.coins > 0 then
        if _G.CoinSystem and _G.CoinSystem.addCoins then
            _G.CoinSystem.addCoins(player, r.coins)
        else
            player:SetAttribute("Coins", (player:GetAttribute("Coins") or 0) + r.coins)
        end
    end
    if _G.BattlePass then
        _G.BattlePass.addXP(player, r.xp or _G.BattlePass.QUEST_XP_DEFAULT, "quest")
    end
    if r.spins and r.spins > 0 then
        player:SetAttribute("PendingSpins", (player:GetAttribute("PendingSpins") or 0) + r.spins)
    end
    if r.box then
        if r.box == "skin" then
            -- 스킨 박스: 즉시 개봉 (rare chest 추첨 로직 재사용) → 클라 상자 컷신 발동
            -- [BOX-GRADE] r.grade 로 등급 지정. 로벅스 상점과 같은 체계다:
            --   common = Color Skin Box(R$18) / plus = Rare+ Box(R$45) / mega = Epic+ Box(R$90)
            --   ⚠️ mega 는 유료 최상위라 무료 경로에서 주지 않는다. plus 까지가 상한.
            --   grade 가 nil 이면 전체 풀 균등 추첨(기존 동작).
            local skinResult = _G.grantRandomSkin and _G.grantRandomSkin(player, r.grade) or nil
            local ev = ReplicatedStorage:FindFirstChild("RareSkinReward")
            if skinResult and ev then
                skinResult.fromBox = true   -- fromBox 플래그 → 클라가 상자 열림 컷신으로 표시
                ev:FireClient(player, skinResult)
            elseif _G.CoinSystem and _G.CoinSystem.addCoins then
                _G.CoinSystem.addCoins(player, 100)   -- 스킨 전부 보유 → 코인 폴백
            end
        elseif r.box == "cosmetic" then
            -- 코스메틱 박스: 트레일/대시/크라운/킬이펙트 풀. 로벅스 Cosmetic Box(R$45)와 같은 경로.
            local res = _G.grantRandomCosmetic and _G.grantRandomCosmetic(player, r.grade) or nil
            local ev = ReplicatedStorage:FindFirstChild("RareSkinReward")
            if res and ev then
                res.fromBox = true
                -- [COSMETIC-BOX-SKIN] 컷신 외형 변주 플래그 (RareSkinRewardCard:483)
                res.cosmeticBox = true
                ev:FireClient(player, res)
            elseif _G.CoinSystem and _G.CoinSystem.addCoins then
                _G.CoinSystem.addCoins(player, 100)   -- 전부 보유 → 코인 폴백
            end
        else
            -- ⚠️ 아래 경로는 소비처가 없다. 새 박스 타입을 쓰려면 위처럼 개봉 분기를 먼저 만들 것.
            local key = "PendingBox_" .. r.box
            player:SetAttribute(key, (player:GetAttribute(key) or 0) + 1)
        end
    end
end

-- ── 카테고리 완주 상태 계산 ──────────────────────────────────────
-- 반환: claimedCount(수령 완료 수), total(퀘스트 수), allClaimed(전부 수령?)
local function getCategoryCompletion(catData, category)
    local total, claimedCount = 0, 0
    for _, def in ipairs(QUEST_DEFS) do
        if def.category == category then
            total += 1
            local q = catData.quests[def.id]
            if q and q.claimed then claimedCount += 1 end
        end
    end
    return claimedCount, total, (total > 0 and claimedCount >= total)
end

-- ════════════════════════════════════════════════════════════════
-- 완주(전체 완료) 보너스 수령
--   해당 카테고리의 모든 퀘스트가 claimed 상태일 때만 1회 지급.
-- ════════════════════════════════════════════════════════════════
function QuestSystem.claimCompletion(player, category)
    if category ~= "daily" and category ~= "weekly" then
        return false, "badcategory"
    end
    local data = activeData[player.UserId]
    if not data then return false, "nodata" end

    local catData = (category == "daily") and data.daily or data.weekly
    if catData.bonusClaimed then return false, "already" end

    local _, _, allClaimed = getCategoryCompletion(catData, category)
    if not allClaimed then return false, "incomplete" end

    grantReward(player, COMPLETION_REWARDS[category])
    catData.bonusClaimed = true

    local r = COMPLETION_REWARDS[category]
    print(string.format("🏆 완주 보너스 수령: [%s] %s → 코인%d 박스%s",
        category, player.Name, r.coins or 0, tostring(r.box or "-")))

    QuestSystem.save(player)
    QuestSystem.pushToClient(player)
    -- [CLAIM-FEEDBACK] 완주 보너스도 내역을 돌려준다.
    return true, nil, { title = (category == "daily") and "All Dailies" or "All Weeklies", reward = r }
end

function QuestSystem.claim(player, questId)
    local def = DEF_BY_ID[questId]
    if not def then return false, "unknown" end

    local data = activeData[player.UserId]
    if not data then return false, "nodata" end

    local catData = (def.category == "daily") and data.daily or data.weekly
    local q = catData.quests[questId]
    if not q then return false, "missing" end
    if q.claimed then return false, "already" end
    if q.progress < def.goal then return false, "incomplete" end

    -- 보상 지급
    local r = def.reward or {}
    grantReward(player, r)

    q.claimed = true
    print(string.format("🎁 보상 수령: [%s] %s (%s) → 코인%d 스핀%d 박스%s",
        def.category, def.title, player.Name,
        r.coins or 0, r.spins or 0, tostring(r.box or "-")))

    QuestSystem.save(player)
    QuestSystem.pushToClient(player)
    -- [CLAIM-FEEDBACK] 무엇을 받았는지 알리기 위해 보상 내역과 제목을 함께 반환한다.
    --   QuestBoot 가 이걸 QuestUpdateEvent 에 실어 클라에 보낸다(새 리모트 불필요).
    return true, nil, { title = def.title, reward = r }
end

-- ════════════════════════════════════════════════════════════════
-- 클라이언트 전송용 스냅샷 생성 (UI 연동 2단계에서 사용)
--   정의 + 현재 진행/수령 상태를 합쳐 직렬화하기 쉬운 형태로 반환.
-- ════════════════════════════════════════════════════════════════
function QuestSystem.getSnapshot(player)
    local data = activeData[player.UserId]
    if not data then return nil end
    checkReset(player.UserId)

    local function buildCat(catData, category)
        local list = {}
        for _, def in ipairs(QUEST_DEFS) do
            if def.category == category then
                local q = catData.quests[def.id] or { progress = 0, claimed = false }
                table.insert(list, {
                    id       = def.id,
                    title    = def.title,
                    desc     = def.desc,
                    goal     = def.goal,
                    progress = q.progress,
                    claimed  = q.claimed,
                    complete = q.progress >= def.goal,
                    reward   = def.reward,
                })
            end
        end
        local claimedCount, total, allClaimed = getCategoryCompletion(catData, category)
        return {
            quests        = list,
            lastReset     = catData.lastReset,
            claimedCount  = claimedCount,
            total         = total,
            allClaimed    = allClaimed,
            bonusClaimed  = catData.bonusClaimed or false,
            bonusReward   = COMPLETION_REWARDS[category],
        }
    end

    return {
        daily       = buildCat(data.daily, "daily"),
        weekly      = buildCat(data.weekly, "weekly"),
        dayLength   = DAY_SECONDS,
        weekLength  = WEEK_SECONDS,
        serverNow   = os.time(),
    }
end

-- 클라이언트로 최신 스냅샷 push (UI 자동 갱신용)
-- ════════════════════════════════════════════════════════════════
-- [QUEST-DEBUG] 테스트용 조작 API. isDev 게이트는 호출부(DownedBotSystem)가 담당한다.
--   ⚠️ activeData 가 로컬이라 외부에서 손댈 수 없어 여기에 둔다.
--   원인 확정/검증이 끝나면 이 블록과 채팅 커맨드를 함께 제거할 것.
-- ════════════════════════════════════════════════════════════════

-- 진행도·수령 상태를 전부 0 으로 (리셋 타이머는 건드리지 않음)
function QuestSystem.debugReset(player, category)
    local data = activeData[player.UserId]
    if not data then return false, "nodata" end
    for _, cat in ipairs({ "daily", "weekly" }) do
        if category == nil or category == cat then
            local catData = data[cat]
            if catData then
                for id, q in pairs(catData.quests or {}) do
                    q.progress = 0
                    q.claimed = false
                end
                catData.bonusClaimed = false
            end
        end
    end
    QuestSystem.save(player)
    QuestSystem.pushToClient(player)
    return true
end

-- 해당 카테고리의 모든 퀘스트를 목표치까지 채운다(수령은 안 함 → Claim 버튼 검증용)
function QuestSystem.debugComplete(player, category)
    local data = activeData[player.UserId]
    if not data then return false, "nodata" end
    for _, def in ipairs(QUEST_DEFS) do
        if category == nil or def.category == category then
            local catData = (def.category == "daily") and data.daily or data.weekly
            local q = catData and catData.quests and catData.quests[def.id]
            if q then
                q.progress = def.goal
                q.claimed = false
            end
        end
    end
    QuestSystem.save(player)
    QuestSystem.pushToClient(player)
    return true
end

function QuestSystem.pushToClient(player)
    local ev = ReplicatedStorage:FindFirstChild("QuestUpdateEvent")
    if ev then
        ev:FireClient(player, QuestSystem.getSnapshot(player))
    end
end

return QuestSystem
