local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

-- 🆓 태거 아이템 일간 무료 로테이션.
-- ⚠️ 서버(판정)와 클라(표시)가 반드시 같은 모듈을 써야 한다. 계산이 갈리면
--    "무료라고 뜨는데 장착이 거부되는" 상태가 된다.
local FreeRotation = require(ReplicatedStorage:WaitForChild("FreeRotation"))

-- 🆓 로테이션 만료로 로드아웃에서 아이템이 빠졌음을 알리는 채널.
-- ⚠️ ReplicatedStorage 에 둔다(서버→클라 알림). Tool 내부 RemoteEvent 는
--    샌드박스 경계에 막힌다(2026-08-23 Ice Bow 실측).
local rotationExpiredEvent = ReplicatedStorage:FindFirstChild("RotationExpired")
if not rotationExpiredEvent then
    rotationExpiredEvent = Instance.new("RemoteEvent")
    rotationExpiredEvent.Name = "RotationExpired"
    rotationExpiredEvent.Parent = ReplicatedStorage
end

-- ────────────────────────────────────────────────────────────────
-- 라운드 중에는 로드아웃을 바꿀 수 없다.
--   UI 를 닫는 것만으로는 부족하다 — 리모트는 클라에서 직접 호출할 수 있으므로
--   서버가 최종 방어선이 되어야 한다.
--   RoundPhase 는 RoundSystem/Stage2TriggerSystem 이 심는 속성(HudButtonClient 와 동일 규약).
-- ────────────────────────────────────────────────────────────────
local function isRoundActive()
	local phase = ReplicatedStorage:GetAttribute("RoundPhase")
	return phase == "stage1" or phase == "stage2"
end
local DataStoreService   = game:GetService("DataStoreService")

local getLoadout        = ReplicatedStorage:WaitForChild("GetPlayerLoadout")
local setLoadout        = ReplicatedStorage:WaitForChild("SetPlayerLoadout")
local checkPass         = ReplicatedStorage:WaitForChild("CheckGamePass")
local getRunnerLoadout  = ReplicatedStorage:WaitForChild("GetRunnerLoadout")
local setRunnerLoadout  = ReplicatedStorage:WaitForChild("SetRunnerLoadout")

local FROST_DRAGON_PASS = 1713666153

-- ── DataStore ─────────────────────────────────────────────────
-- consumables + runnerLoadout 함께 저장
local playerDataStore = DataStoreService:GetDataStore("PlayerRunnerData_v1")

-- ── 아이템 목록 ───────────────────────────────────────────────
local ALL_ITEMS = {
    {name = "stone",         displayName = "Stone",         icon = "rbxassetid://82371616734481",  rarity = "Normal",    premium = false, locked = false, category = "roll"},
    {name = "Wood Log",      displayName = "Wood Log",      icon = "rbxassetid://111506419006164", rarity = "Normal",    premium = false, locked = false, category = "roll"},
    {name = "Wooden Barrel", displayName = "Wooden Barrel", icon = "", rarity = "Normal",    premium = false, locked = false, category = "roll"},
    {name = "Spear",         displayName = "Spear",         icon = "rbxassetid://101585526959216",  rarity = "Normal",    premium = false, locked = true,  shopId = "spear", category = "throw"},
    {name = "Demonspear",    displayName = "Demon Spear",   icon = "",                             rarity = "Epic",      premium = false, locked = true,  shopId = "demon_spear", category = "throw"},
    {name = "ItemNoob",      displayName = "Noob",          icon = "rbxassetid://94636891514149",  rarity = "Rare",      premium = false, locked = true,  unlockAttr = "HasItemNoob", category = "roll"},
    {name = "bear_trap",     displayName = "Bear Trap",     icon = "",                             rarity = "Rare",      premium = false, locked = true,  shopId = "bear_trap", category = "trap"},
    {name = "tox_box",       displayName = "Tox Box",       icon = "",                             rarity = "Epic",      premium = false, locked = true,  shopId = "tox_box", category = "trap"},
    {name = "tsunami",       displayName = "Tsunami",       icon = "",                             rarity = "Epic",      premium = false, locked = true,  shopId = "tsunami", category = "aoe"},
    {name = "tnt",           displayName = "Bomb",          icon = "",                             rarity = "Legendary", premium = false, locked = true,  shopId = "tnt", category = "aoe"},
    {name = "BlackHole",     displayName = "Black Hole",    icon = "",                             rarity = "Epic",      premium = false, locked = true,  shopId = "black_hole", category = "aoe"},
    {name = "EnergyBall",    displayName = "Energy Ball",   icon = "rbxassetid://117068890154547",  rarity = "Legendary", premium = false, locked = true,  shopId = "energy_ball", category = "aoe"},
    {name = "Frost Dragon",  displayName = "Frost Dragon",  icon = "rbxassetid://89650402225309",  rarity = "Legendary", premium = true,  locked = false, category = "aoe"},
}

-- stage 필드: 1 = 1단계용(돌파/생존/유틸), 2 = 2단계용(반격 공격무기).
-- UI에서 stage로 분류 가능. 2단계 무기(망치/몽둥이 등) 추가 시 stage=2로 태깅.
local ALL_RUNNER_ITEMS = {
    {name = "Speed Potion", displayName = "Speed Potion",    icon = "", rarity = "Rare", premium = false, locked = false, consumable = true, stage = 1},
    {name = "Wood Shield",  displayName = "Wood Shield",     icon = "", rarity = "Normal", premium = false, locked = false, consumable = true, stage = 1},
    {name = "RevivalFlag",  displayName = "Revival Flag",    icon = "", rarity = "Epic",   premium = false, locked = false, consumable = true, stage = 1},
    {name = "Gas Grenade",  displayName = "Gas Grenade",     icon = "", rarity = "Normal",   premium = false, locked = false, consumable = true, stage = 1},
    -- 🗑️ [2026-08-29] GrappleHook 제거 (ODM 하위호환). 소모품 9종 → 8종.
    {name = "ODM Gear",     displayName = "ODM Gear",        icon = "", rarity = "Legendary",   premium = false, locked = false, consumable = true, stage = 1},
    {name = "Ice Bow",      displayName = "Ice Bow",         icon = "", rarity = "Legendary",   premium = false, locked = false, consumable = true, stage = 1},
    {name = "Mic Bomb",     displayName = "Mic Bomb",       icon = "", rarity = "Epic",   premium = false, locked = false, consumable = true, stage = 1},
    {name = "Decoy Wand",   displayName = "Decoy Wand",     icon = "", rarity = "Rare",   premium = false, locked = false, consumable = true, stage = 1},
}

local DEFAULT_LOADOUT        = {"stone", "Wood Log", "Wooden Barrel"}
local DEFAULT_RUNNER_LOADOUT = {"Speed Potion"}  -- 신규 플레이어 기본값
local DEFAULT_CONSUMABLES    = { ["Speed Potion"] = 1 }

-- ── 플레이어 데이터 (메모리) ─────────────────────────────────
-- runnerLoadout: nil = 아직 미로드 / table = 저장된 값 (빈 테이블 포함)
local playerLoadouts       = {}  -- 태거 로드아웃 (메모리만)
local playerRunnerLoadouts = {}  -- nil=미로드, {}=빈장착, {"Speed Potion"}=장착
local playerConsumables    = {}
local playerOwnedPermanents = {}  -- uid → { [id]=true } 영구 구매 셋 (DataStore 지속)
local passCache            = {}
local dataLoaded           = {}  -- uid → true. loadPlayerData 완료 표시.
local migrationPending     = {}  -- uid → true. 레거시 키 마이그레이션 저장 대기(디바운스 경유)
-- ⚠ 이게 없으면: 로드(GetAsync, 수백ms) 중에 GrantOwnedPermanent가 불리면
--   playerOwnedPermanents[uid]가 nil이라 빈 셋이 생기고, savePlayerData가
--   기존 영구구매+소모품+러너로드아웃을 전부 빈 값으로 덮어씀 = 데이터 소실.
-- 웹 Store 탭 구매 시 ProcessReceipt이 조인 직후 발동하므로 실제로 발생 가능한 경합.

-- ── 레거시 한글 키 마이그레이션 ───────────────────────────────
-- 과거 ShopSystem이 itemData.name(한글)을 저장 키로 썼던 시기의 데이터를 정리.
-- Tool 인스턴스명(영문)으로 통일된 후로는 한글 키가 더 이상 매칭되지 않으므로
-- 기존 보유 수량이 인벤토리에서 사라진 것처럼 보이는 문제를 막아준다.
local LEGACY_KEY_MAP = {
    ["연막탄"]        = "Gas Grenade",
    ["부활 깃발"]     = "RevivalFlag",
    ["스피드 부스트"] = "Speed Potion",
}

-- consumables 테이블의 레거시 키를 영문 키로 합산 이동. 변경되면 true 반환.
local function migrateLegacyConsumableKeys(consumables)
    if type(consumables) ~= "table" then return false end
    local changed = false
    for oldKey, newKey in pairs(LEGACY_KEY_MAP) do
        local oldCount = consumables[oldKey]
        if type(oldCount) == "number" and oldCount > 0 then
            consumables[newKey] = (consumables[newKey] or 0) + oldCount
            consumables[oldKey] = nil
            changed = true
            print(string.format("🔄 레거시 키 마이그레이션: %q → %q (+%d)", oldKey, newKey, oldCount))
        elseif consumables[oldKey] ~= nil then
            -- 0이거나 비정상 값이어도 제거
            consumables[oldKey] = nil
            changed = true
        end
    end
    return changed
end

-- runnerLoadout 배열의 레거시 한글 항목을 영문으로 치환 (중복 제거 포함).
local function migrateLegacyLoadout(loadout)
    if type(loadout) ~= "table" then return false end
    local changed = false
    local seen = {}
    local newList = {}
    for _, name in ipairs(loadout) do
        local mapped = LEGACY_KEY_MAP[name] or name
        if mapped ~= name then changed = true end
        if not seen[mapped] then
            seen[mapped] = true
            table.insert(newList, mapped)
        else
            changed = true  -- 중복 제거됨
        end
    end
    if changed then
        for i = 1, math.max(#loadout, #newList) do loadout[i] = newList[i] end
    end
    return changed
end

-- ── DataStore 저장/로드 ───────────────────────────────────────
-- 영구 구매 셋(playerOwnedPermanents[uid])을 저장용 배열로 직렬화
local function ownedArray(uid)
    local t = {}
    for id in pairs(playerOwnedPermanents[uid] or {}) do t[#t + 1] = id end
    return t
end

local function loadPlayerData(player)
    local ok, data = pcall(function()
        return playerDataStore:GetAsync(tostring(player.UserId))
    end)
    if ok and type(data) == "table" then
        -- 기존 플레이어: 저장된 값 그대로 사용 (빈 배열도 존중)
        playerRunnerLoadouts[player.UserId] = data.runnerLoadout  -- nil일 수도 있음
        playerConsumables[player.UserId]    = data.consumables or {}

        -- 영구 구매 복원 (OwnedItem_ 어트리뷰트 재세팅 + 메모리 셋 채움)
        local owned = {}
        if type(data.ownedPermanents) == "table" then
            for _, id in ipairs(data.ownedPermanents) do
                if type(id) == "string" and id ~= "" then
                    owned[id] = true
                    player:SetAttribute("OwnedItem_" .. id, true)
                end
            end
        end
        playerOwnedPermanents[player.UserId] = owned

        -- 레거시 한글 키 마이그레이션 (consumables + runnerLoadout)
        local migratedC = migrateLegacyConsumableKeys(playerConsumables[player.UserId])
        local migratedL = migrateLegacyLoadout(playerRunnerLoadouts[player.UserId])
        if migratedC or migratedL then
            print("📦 마이그레이션 적용 → 저장 예약:", player.Name)
            -- 💾 [2026-08-29] 즉시 SetAsync → 디바운스 예약으로 변경.
            --   [증상] 접속 순간 같은 키에 "(x2)" 큐 경고.
            --   [원인] 바로 위에서 GetAsync 를 한 직후라, 읽기+쓰기가 연달아 나갔다.
            --     Roblox 는 같은 키 연속 접근을 제한하므로 즉시 큐에 쌓인다.
            --   [해결] 마이그레이션은 급하지 않다. 6초 뒤 한 번만 쓰면 충분하고,
            --     그 전에 퇴장해도 PlayerRemoving 의 saveNow 가 같은 데이터를 저장한다.
            --   ⚠️ savePlayerData 는 아래에서 선언되므로 여기서 직접 못 부른다.
            --     dataLoaded 를 먼저 세워야 saveNow 의 방어 검사를 통과하므로,
            --     함수 끝의 dataLoaded 세팅 이후로 예약을 미룬다(migrationPending 플래그).
            migrationPending[player.UserId] = true
        end

        local loadoutStr = data.runnerLoadout and table.concat(data.runnerLoadout, ", ") or "(없음)"
        print("📂 플레이어 데이터 로드:", player.Name, "| 러너 로드아웃:", loadoutStr)
    else
        -- 신규 플레이어: 기본값 적용 (runnerLoadout은 nil → DEFAULT 반환)
        playerRunnerLoadouts[player.UserId] = nil  -- nil = 신규, getRunnerLoadout에서 DEFAULT 반환
        playerConsumables[player.UserId]    = { ["Speed Potion"] = 1 }
        playerOwnedPermanents[player.UserId] = {}
        print("🆕 신규 플레이어 기본 설정:", player.Name)
    end
    dataLoaded[player.UserId] = true   -- 이 시점부터 GrantOwnedPermanent/savePlayerData 안전
    -- 💾 마이그레이션 저장 예약. dataLoaded 를 세운 '뒤'라야 saveNow 의 방어 검사를 통과한다.
    --   ⚠️ savePlayerData 는 아래에서 선언되므로 직접 못 부른다 → task.defer 로 미룬다.
    --     defer 는 이 함수가 끝난 뒤 실행되므로 그때는 savePlayerData 가 이미 존재한다.
    if migrationPending[player.UserId] then
        migrationPending[player.UserId] = nil
        task.defer(function()
            if player.Parent then savePlayerData(player) end
        end)
    end
end

-- 💾 [2026-08-29] 저장 디바운스.
--   [증상] Studio 에서 "DataStore request was added to queue" 경고.
--     실측 22:44:01 — 같은 키(9228200642)에 0.2초 안에 2회 쓰기.
--   [원인] savePlayerData 가 8곳에서 불린다. 특히 deductConsumable 한 함수에만 3곳이라,
--     소모품을 연달아 쓰면 매번 DataStore 쓰기가 나갔다.
--     Roblox 는 같은 키 연속 쓰기를 약 6초로 제한하므로 즉시 큐에 쌓인다.
--   [해결] 여러 번 호출돼도 SAVE_DELAY 뒤에 '한 번만' 실제로 쓴다.
--     소모품 3개를 연속으로 써도 저장은 1회다.
--   ⚠️ PlayerRemoving 은 디바운스를 쓰면 안 된다 — 예약이 실행되기 전에
--     플레이어가 사라져 데이터가 통째로 유실된다. 거기서는 saveNow 를 직접 부른다.
--   ⚠️ 값은 메모리(playerRunnerLoadouts 등)에 즉시 반영된다. 디바운스는 '디스크 쓰기'만
--     미루는 것이라, 지연 중에 조회해도 최신값이 나온다.
local SAVE_DELAY = 6          -- 같은 키 쓰기 제한과 같은 값
local savePending = {}        -- [userId] = true (예약됨)

local function saveNow(player)
    -- 최후 방어: 로드 전 저장은 기존 데이터를 빈 값으로 덮어쓰므로 무조건 차단.
    if not dataLoaded[player.UserId] then
        warn("⚠ savePlayerData: 로드 전 저장 시도 차단 (데이터 소실 방지):", player.Name)
        return
    end
    local data = {
        runnerLoadout   = playerRunnerLoadouts[player.UserId],  -- nil이어도 저장 안 함 (신규 유지)
        consumables     = playerConsumables[player.UserId] or {},
        ownedPermanents = ownedArray(player.UserId),
    }
    -- 아무 데이터도 없는 신규만 저장 생략 (영구 구매가 하나라도 있으면 저장)
    if data.runnerLoadout == nil and next(data.consumables) == nil and #data.ownedPermanents == 0 then return end
    -- 🛡️ [2026-09-06] 저장 실패를 삼키지 않고 보고한다.
    --   [왜] 여기는 로드아웃·소모품·영구구매가 들어 있어 유실 시 피해가 가장 크다.
    --     그런데 pcall 이 에러를 통째로 삼켜서, 실패해도 아무 데도 안 남았다.
    --     크리에이터 허브 '오류'에도 안 잡힌다(pcall 로 잡혔으므로).
    --   ⚠️ 동작은 그대로다 — 실패해도 여전히 서버를 죽이지 않는다. 기록만 추가한다.
    --   ⚠️ 7개 시스템 중 여기만 먼저 연결했다. 한 번에 다 고치면 무엇이 깨졌는지 못 가른다.
    local ok, err = pcall(function()
        playerDataStore:SetAsync(tostring(player.UserId), data)
    end)
    if not ok and _G.ReportSaveFailure then
        _G.ReportSaveFailure("PlayerRunnerData_v1", err)
    end
end

local function savePlayerData(player)
    local uid = player.UserId
    if savePending[uid] then return end   -- 이미 예약됨 — 그 예약이 최신값을 쓴다
    savePending[uid] = true
    task.delay(SAVE_DELAY, function()
        savePending[uid] = nil
        -- ⚠️ 지연 중 퇴장했을 수 있다. PlayerRemoving 이 이미 saveNow 로 저장했으므로
        --    여기서 또 쓰지 않는다(없는 플레이어에 대한 쓰기 = 낭비 + 큐 압박).
        if player.Parent then saveNow(player) end
    end)
end

-- ── 패스 확인 ─────────────────────────────────────────────────
local function hasPass(player)
    local ok, result = pcall(function()
        return MarketplaceService:UserOwnsGamePassAsync(player.UserId, FROST_DRAGON_PASS)
    end)
    return ok and result
end

-- Frost Dragon 소유 = 게임패스 OR 번들 구매(OwnedItem_frost_dragon).
-- 게임패스는 로블록스 서버가 진실이라 개발자상품(Frost Lord Bundle)으론 부여 불가 →
-- 번들 구매자는 GrantOwnedPermanent로 OwnedItem_frost_dragon을 받고 여기 두 번째 항으로 통과.
-- ⚠ passCache는 패스 결과만 캐시. 번들 속성은 매번 읽어야 함(구매 즉시 반영 + 캐시 오염 방지).
local function hasPassCached(player)
    if passCache[player.UserId] == nil then
        passCache[player.UserId] = hasPass(player)
    end
    if passCache[player.UserId] then return true end
    return player:GetAttribute("OwnedItem_frost_dragon") == true
end

-- ── 태거 로드아웃 ─────────────────────────────────────────────
local function validateLoadout(player, items)
    if type(items) ~= "table" or #items < 1 then return DEFAULT_LOADOUT end
    if #items > 4 then items = {items[1], items[2], items[3], items[4]} end
    local valid = {}
    local owns  = hasPassCached(player)
    for _, itemName in ipairs(items) do
        for _, data in ipairs(ALL_ITEMS) do
            if data.name == itemName then
                local unlocked = (not data.locked)
                    or (data.shopId and player:GetAttribute("OwnedItem_" .. data.shopId))
                    or (data.unlockAttr and player:GetAttribute(data.unlockAttr))
                    -- 🆓 오늘의 무료 로테이션도 해금으로 친다.
                    -- ⚠️ 이 판정은 getLoadout 의 표시 계산과 반드시 같은 모듈을 써야 한다.
                    --    다르면 "무료라고 뜨는데 장착이 거부되는" 상태가 된다.
                    or FreeRotation.isFreeToday(data.name)
                if not (data.premium and not owns) and unlocked then
                    table.insert(valid, itemName)
                end
                break
            end
        end
    end
    -- ⚠️ 유효한 게 하나도 없을 때만 기본값으로 되돌린다.
    --    [주의] 이 폴백은 '유저가 보낸 입력'을 검증할 때만 의미가 있다.
    --    로테이션 만료로 아이템이 빠지는 경우는 pruneExpiredRotation 이 담당하며,
    --    거기서는 빈 배열을 그대로 둔다 — 만료됐다고 유저가 짠 구성을
    --    stone/Wood Log/Wooden Barrel 로 덮어써 버리면 안 되기 때문이다.
    return #valid >= 1 and valid or DEFAULT_LOADOUT
end

-- ── 🆓 로테이션 만료 정리 ──────────────────────────────────────
-- 무료 기간에 장착해둔 아이템은 로테가 넘어가면 더 이상 쓸 수 없다.
-- 그런데 playerLoadouts 에는 그대로 남아 있어서, 인벤은 "장착됨"으로 보이는데
-- 라운드에서는 validateLoadout 이 걸러내 안 나온다. 이 불일치를 없앤다.
--
-- ⚠️ 구매자는 건드리지 않는다. 무료 기간에 마음에 들어 구매했다면 만료와 무관하다.
--    판정 순서상 shopId 보유가 먼저 통과하므로 아래 canUseWithoutRotation 이 true 다.
-- ⚠️ 기본 아이템으로 치환하지 않는다. 무엇으로 채울지는 유저가 정할 문제고,
--    보유 아이템이 많은 유저에게 stone 을 꽂아주면 오히려 의도에서 멀어진다.
--    → 빼고 알린다. 유저가 인벤에서 직접 다시 채운다.
local function canUseWithoutRotation(player, data, owns)
    if data.premium then return owns end
    if not data.locked then return true end
    if data.shopId and player:GetAttribute("OwnedItem_" .. data.shopId) then return true end
    if data.unlockAttr and player:GetAttribute(data.unlockAttr) then return true end
    return false
end

-- 만료된 로테 아이템을 로드아웃에서 제거한다.
-- @return 제거된 이름 배열 (없으면 빈 배열)
local function pruneExpiredRotation(player)
    local cur = playerLoadouts[player.UserId]
    if not cur then return {} end

    local owns = hasPassCached(player)
    local kept, removed = {}, {}
    for _, itemName in ipairs(cur) do
        local data
        for _, d in ipairs(ALL_ITEMS) do
            if d.name == itemName then data = d break end
        end
        if not data then
            -- 알 수 없는 이름(구버전 잔재)은 조용히 버린다
        elseif canUseWithoutRotation(player, data, owns) or FreeRotation.isFreeToday(itemName) then
            table.insert(kept, itemName)
        else
            table.insert(removed, data.displayName or itemName)
        end
    end

    if #removed > 0 then
        -- ⚠️ [최소 보장] 하나도 안 남으면 기본 아이템을 넣는다.
        --    치환하지 않는다는 원칙은 "아직 쓸 게 남아 있을 때 게임이 대신 고르지 말라"는
        --    뜻이지, 빈 손으로 내보내라는 뜻이 아니다. 로테 아이템만으로 로드아웃을
        --    채운 사람이 만료를 맞으면 아이템 0개로 태거가 되어 플레이 자체가 불가능해진다.
        --    (알림을 놓쳤거나 인벤을 안 열고 라운드에 들어가는 경우가 실제로 있다)
        -- ⚠️ 남은 게 있으면 채우지 않는다. 그때는 무엇으로 메울지가 유저의 선택이다.
        local filledDefault = false
        if #kept == 0 then
            for _, nm in ipairs(DEFAULT_LOADOUT) do table.insert(kept, nm) end
            filledDefault = true
        end

        playerLoadouts[player.UserId] = kept
        rotationExpiredEvent:FireClient(player, removed, filledDefault)
        print(("🆓 [Rotation] %s 로드아웃에서 만료 제거: %s%s")
            :format(player.Name, table.concat(removed, ", "),
                filledDefault and " (전부 비어 기본값으로 보충)" or ""))
    end
    return removed
end

getLoadout.OnServerInvoke = function(player)
    -- 🆓 인벤을 열 때마다 만료분을 정리한다.
    -- ⚠️ 여기서 안 하면 인벤은 "장착됨"으로 보이는데 라운드에서는 걸러져
    --    "인벤엔 있는데 안 나오는" 불일치가 계속 남는다.
    pruneExpiredRotation(player)
    -- ⚠️ or DEFAULT_LOADOUT 은 nil 만 걸러내고 '빈 테이블'은 통과시킨다.
    --    로테 만료로 전부 빠진 경우를 대비해 길이도 함께 검사한다.
    local loadout = playerLoadouts[player.UserId]
    if type(loadout) ~= "table" or #loadout == 0 then loadout = DEFAULT_LOADOUT end
    local owns    = hasPassCached(player)
    -- 플레이어별 실제 해금 상태로 allItems 재계산 (locked=true여도 OwnedItem 구매 시 해금)
    local items = {}
    for _, data in ipairs(ALL_ITEMS) do
        local d = {}
        for k, v in pairs(data) do d[k] = v end
        if data.premium then
            d.locked = not owns                       -- 게임패스 아이템: 소유 시 해금
        elseif data.locked and data.shopId then
            d.locked = not player:GetAttribute("OwnedItem_" .. data.shopId)  -- 상점 구매 시 해금
        elseif data.locked and data.unlockAttr then
            d.locked = not player:GetAttribute(data.unlockAttr)  -- 특수 해금(예: 그룹 보상 HasItemNoob)
        end

        -- 🆓 오늘의 무료 로테이션.
        -- ⚠️ freeToday 는 locked 와 '별도' 필드다. locked 만 풀면 UI 가 구매 버튼을
        --    숨겨서 "써보고 산다"는 전환 경로가 끊긴다. 소유 여부(owned)를 따로 남겨
        --    카드가 "오늘 무료 + 구매 가능"을 동시에 보여줄 수 있게 한다.
        if FreeRotation.isFreeToday(data.name) then
            d.ownedReal = not d.locked   -- 진짜로 보유 중인가(로테이션 제외)
            d.freeToday = true
            d.locked = false             -- 장착은 가능
        end

        items[#items + 1] = d
    end
    return { loadout = loadout, allItems = items, hasPass = owns, passId = FROST_DRAGON_PASS }
end

setLoadout.OnServerEvent:Connect(function(player, items)
	if isRoundActive() then return end   -- 라운드 중 로드아웃 변경 차단
    playerLoadouts[player.UserId] = validateLoadout(player, items)
    if _G.PM_onEdit then _G.PM_onEdit(player) end
end)

checkPass.OnServerInvoke = function(player)
    return hasPassCached(player)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
    if passId == FROST_DRAGON_PASS and purchased then
        passCache[player.UserId] = true
    end
end)

-- ── 러너 로드아웃 ─────────────────────────────────────────────
-- 🗑️ [2026-08-29] 없어진 아이템을 로드아웃에서 걸러낸다.
--   [왜] 아이템을 제거해도 유저 DataStore 에는 이름이 그대로 남는다.
--     저장 경로(_G.LM_applyLoadouts, setRunnerLoadout)에는 ALL_RUNNER_ITEMS 대조가
--     있는데 '로드' 경로에는 없어서, 인벤을 만지지 않는 유저는 영영 정리되지 않았다.
--     → 슬롯 하나가 "인벤엔 보이는데 라운드에선 안 나오는" 유령 상태로 남는다.
--     (같은 불일치를 로테이션 만료에서 이미 겪었다 — pruneExpiredRotation 주석 참조)
--   [계기] Grappling Hook 제거(ODM 하위호환). 앞으로 다른 아이템을 빼도 그대로 작동한다.
--   ⚠️ 알림을 띄우지 않는다. 로테이션 만료는 "빌린 게 끝났다"는 설명 가능한 사건이지만,
--     아이템 제거는 유저가 되찾을 방법이 없어 알려도 답을 줄 수 없다. 조용히 뺀다.
--   ⚠️ 저장은 하지 않는다. 읽을 때마다 거르기만 하면 충분하고,
--     여기서 savePlayerData 를 부르면 인벤을 열 때마다 DataStore 쓰기가 발생한다.
local function filterRemovedItems(list)
    if type(list) ~= "table" then return list end
    local out = {}
    for _, itemName in ipairs(list) do
        for _, data in ipairs(ALL_RUNNER_ITEMS) do
            if data.name == itemName then
                table.insert(out, itemName)
                break
            end
        end
    end
    return out
end

getRunnerLoadout.OnServerInvoke = function(player)
    local saved = playerRunnerLoadouts[player.UserId]
    local loadout
    if saved == nil then
        -- 신규 플레이어: DEFAULT (Speed Potion 장착)
        loadout = DEFAULT_RUNNER_LOADOUT
    else
        -- 기존 플레이어: 저장된 값 그대로 (빈 배열이어도 존중)
        --   ⚠️ 단, 제거된 아이템은 걸러낸다(위 filterRemovedItems 참조).
        loadout = filterRemovedItems(saved)
    end
    local consumables = playerConsumables[player.UserId] or DEFAULT_CONSUMABLES
    return {
        loadout     = loadout,
        allItems    = ALL_RUNNER_ITEMS,
        consumables = consumables,
    }
end

setRunnerLoadout.OnServerEvent:Connect(function(player, items)
	if isRoundActive() then return end   -- 라운드 중 로드아웃 변경 차단
    if type(items) ~= "table" then return end

    -- 유효한 아이템만 필터링 (빈 결과도 그대로 저장 → 0개 장착 허용)
    local valid = {}
    for _, itemName in ipairs(items) do
        for _, data in ipairs(ALL_RUNNER_ITEMS) do
            if data.name == itemName and not data.locked then
                table.insert(valid, itemName)
                break
            end
        end
    end
    playerRunnerLoadouts[player.UserId] = valid  -- {} (빈 배열) 포함 저장
    savePlayerData(player)
    print("✅", player.Name, "러너 로드아웃 저장:", #valid == 0 and "(없음)" or table.concat(valid, ", "))
    if _G.PM_onEdit then _G.PM_onEdit(player) end
end)

-- ── _G 함수 (RoundSystem에서 사용) ───────────────────────────
_G.GetRunnerLoadout = function(player)
    local saved = playerRunnerLoadouts[player.UserId]
    if saved == nil then return DEFAULT_RUNNER_LOADOUT end
    -- 🗑️ 제거된 아이템 필터(위 getRunnerLoadout 과 같은 규칙 — 한쪽만 고치지 말 것).
    --   ⚠️ 지급부(RoundSystem)에 FindFirstChild nil 가드가 있어 에러는 안 나지만,
    --     여기서 거르지 않으면 "슬롯은 찼는데 아무것도 안 나오는" 상태가 유지된다.
    return filterRemovedItems(saved)
end

-- ── 프리셋 시스템용 노출 (PresetManager가 capture/apply에 사용) ──
_G.LM_getLoadouts = function(player)
    -- 🆓 라운드 시작 전에도 정리한다. 인벤을 한 번도 안 열고 바로 라운드에
    --    들어가는 경우가 있어서, getLoadout 만으로는 새는 경로가 생긴다.
    pruneExpiredRotation(player)
    local runner = playerRunnerLoadouts[player.UserId]
    if runner == nil then runner = DEFAULT_RUNNER_LOADOUT end   -- 신규(미저장): Speed Potion 기본 (getRunnerLoadout과 일치)
    runner = filterRemovedItems(runner)   -- 🗑️ 제거된 아이템 필터(세 경로 공통 규칙)

    -- ⚠️ [최후 방어선] 태거 아이템이 0개면 라운드를 맨손으로 진행하게 된다.
    --    pruneExpiredRotation 이 이미 보충하지만, 다른 경로로 빈 배열이 저장돼 있을
    --    수도 있으므로 지급 직전에 한 번 더 막는다. (or DEFAULT_LOADOUT 은 nil 만
    --    걸러내고 '빈 테이블'은 통과시킨다 — #t == 0 검사가 따로 필요하다)
    local taggerList = playerLoadouts[player.UserId]
    if type(taggerList) ~= "table" or #taggerList == 0 then
        taggerList = DEFAULT_LOADOUT
    end

    return {
        tagger = taggerList,
        runner = runner,
    }
end

_G.LM_applyLoadouts = function(player, taggerItems, runnerItems)
    -- 태거: 소유 검증 후 메모리 세팅 (setLoadout 핸들러와 동일 규칙)
    playerLoadouts[player.UserId] = validateLoadout(player, taggerItems or {})
    -- 러너: 유효/미잠금 필터 후 세팅 (setRunnerLoadout 핸들러와 동일) + 저장
    local valid = {}
    for _, itemName in ipairs(runnerItems or {}) do
        for _, data in ipairs(ALL_RUNNER_ITEMS) do
            if data.name == itemName and not data.locked then
                table.insert(valid, itemName)
                break
            end
        end
    end
    playerRunnerLoadouts[player.UserId] = valid
    savePlayerData(player)
end

_G.AddConsumable = function(player, itemName)
    local c = playerConsumables[player.UserId]
    if not c then return end
    c[itemName] = (c[itemName] or 0) + 1
    savePlayerData(player)
    print("🎒 소모품 추가:", player.Name, itemName, "→", c[itemName])
end

_G.GetConsumableCount = function(player, itemName)
    local c = playerConsumables[player.UserId]
    if not c then return nil end
    return c[itemName]
end

_G.UseConsumable = function(player, itemName)
    local c = playerConsumables[player.UserId]
    if not c or type(c[itemName]) ~= "number" then return false end
    if c[itemName] <= 0 then return false end
    c[itemName] = math.max(0, c[itemName] - 1)
    savePlayerData(player)
    print("💊 소모품 차감:", player.Name, itemName, "→ 남은:", c[itemName])
    -- Tool 지급 (Wood Shield 등 설치형 아이템)
    local runnerItems = game:GetService("ServerStorage"):FindFirstChild("RunnerItem")
    local toolTemplate = runnerItems and runnerItems:FindFirstChild(itemName)
    if toolTemplate and toolTemplate:IsA("Tool") then
        local char    = player.Character
        local backpack = player:FindFirstChild("Backpack")
        local alreadyHas = (char and char:FindFirstChild(itemName))
            or (backpack and backpack:FindFirstChild(itemName))
        if not alreadyHas then
            local clone = toolTemplate:Clone()
            clone.Parent = backpack or char
            print("🎒 Tool 지급:", player.Name, itemName)
        end
    end
    return true
end


-- ── [CONSUMABLE-ONUSE] 사용 시점 차감 규약 ────────────────────────────
-- 기존: RoundSystem 이 라운드 시작에 지급과 동시에 차감했다.
--   → 안 쓰고 죽어도, 아예 손도 안 대도 소모품이 사라진다.
-- 목표: 각 툴이 "실제로 썼을 때" _G.MarkConsumableUsed 를 부르고 그때 차감한다.
--
-- ⚠️ 전환은 아이템 단위로 한다(아래 ONUSE_ITEMS). 훅이 들어간 것만 여기서 차감하고,
--    나머지는 RoundSystem 이 기존대로 라운드 시작에 차감한다.
--    한 아이템이 양쪽에 다 걸리면 이중 차감, 양쪽 다 빠지면 무한이 된다 — 반드시 배타적으로.

-- 훅이 실제로 들어간 아이템만 '사용 시점 차감'으로 전환한다.
--   여기 있는 것: RoundSystem 이 지급만 하고 차감 안 함 → 아래 MarkConsumableUsed 가 차감
--   여기 없는 것: 기존대로 RoundSystem 이 라운드 시작에 차감 (동작 변경 없음)
-- ⚠️ 훅이 실제로 발동하는 걸 로그로 확인한 아이템만 추가할 것.
--    확인 없이 넣으면 그 아이템은 아무도 안 깎아서 무한이 된다.
-- 검증 상태(2026-08-20):
--   ODM Gear / Speed Potion / Ice Bow / Decoy Wand — 실측 확인 완료
--   Wood Shield / Gas Grenade / Mic Bomb / RevivalFlag — 훅 삽입 완료, 발동 로그 미확인
--   (GrappleHook 은 2026-08-29 아이템 자체를 제거해 목록에서 뺐다)
--   ↑ 출시 전에 5종 모두 실제로 써서 차감되는지 반드시 확인할 것
local ONUSE_ITEMS = {
    ["Speed Potion"] = true,
    ["ODM Gear"]     = true,
    ["Ice Bow"]      = true,
    ["Decoy Wand"]   = true,
    ["Wood Shield"]  = true,
    ["Gas Grenade"]  = true,
    ["Mic Bomb"]     = true,
    ["RevivalFlag"]  = true,
}

-- RoundSystem 이 "이 아이템은 지급만 하고 차감하지 말 것"을 판별하는 데 쓴다
_G.IsOnUseConsumable = function(itemName)
    return itemName ~= nil and ONUSE_ITEMS[itemName] == true
end

-- 이번 라운드에 이미 사용 처리한 (유저, 아이템).
--   규약: 1회 지급 = 인벤에서 1개 소모. ODM Gear(3충전)처럼 한 라운드에
--   여러 번 쓰는 툴도 인벤에서는 1개만 빠져야 하므로 아이템별 1회만 유효하다.
local roundConsumableUsed = {}

-- 순수 차감 (Tool 재지급 없음).
--   _G.UseConsumable 은 차감과 '지급'을 겸하는데(375~388행), 다 쓴 툴은 이미
--   파괴돼 있어 alreadyHas 가 false 가 된다. 그걸 그대로 쓰면 툴이 되살아난다.
local function deductConsumable(player, itemName)
    local c = playerConsumables[player.UserId]
    if not c or type(c[itemName]) ~= "number" then return false end
    if c[itemName] <= 0 then return false end
    c[itemName] = math.max(0, c[itemName] - 1)
    savePlayerData(player)
    print("💊 소모품 차감(사용 시점):", player.Name, itemName, "→ 남은:", c[itemName])
    return true
end

-- 라운드 시작 지급 시 호출 — 이번 라운드 사용 플래그 초기화
_G.BeginConsumableRound = function(player, itemName)
    if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
    if not itemName then return end
    local u = roundConsumableUsed[player.UserId]
    if u then u[itemName] = nil end
end

-- 각 툴이 '실제 사용' 시점에 호출한다. 라운드당 아이템별 1회만 유효.
_G.MarkConsumableUsed = function(player, itemName)
    -- 태거봇은 pseudoPlayer(Lua 테이블)라 Instance 가드 필요
    if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
    if not itemName then return end
    local uid = player.UserId
    roundConsumableUsed[uid] = roundConsumableUsed[uid] or {}
    if roundConsumableUsed[uid][itemName] then return end
    roundConsumableUsed[uid][itemName] = true
    if ONUSE_ITEMS[itemName] then
        deductConsumable(player, itemName)
    else
        -- 화이트리스트 밖: RoundSystem 이 이미 라운드 시작에 깎았으므로 여기서 또 깎으면 이중 차감
        print("[ConsumeMark] 사용 감지:", player.Name, itemName, "(차감은 라운드 시작에 이미 됨)")
    end
end

_G.ClearConsumable = function(player, itemName)
    -- 소모품 수량 0으로 (영구 전환 환불 후 정리). 반환: 정리 전 수량
    local c = playerConsumables[player.UserId]
    local prev = (c and type(c[itemName]) == "number") and c[itemName] or 0
    if c then c[itemName] = 0 end
    if prev > 0 then savePlayerData(player) end
    return prev
end

-- 반환 false = 지속 저장 실패(로드 미완). 호출측(ProcessReceipt 등)은 완료 처리하지 말 것.
_G.GrantOwnedPermanent = function(player, id)
    if type(id) ~= "string" or id == "" then return false end
    -- 로드 완료까지 대기. 안 기다리면 빈 셋으로 기존 데이터를 덮어씀(위 dataLoaded 주석 참고).
    local t = 0
    while not dataLoaded[player.UserId] do
        if player.Parent ~= Players then return false end
        if t >= 20 then
            warn("⚠ GrantOwnedPermanent: 데이터 로드 대기 초과 → 지급 보류:", player.Name, id)
            return false
        end
        task.wait(0.1); t = t + 0.1
    end
    player:SetAttribute("OwnedItem_" .. id, true)
    local set = playerOwnedPermanents[player.UserId]
    if not set then set = {}; playerOwnedPermanents[player.UserId] = set end
    if not set[id] then
        set[id] = true
        savePlayerData(player)
        print("🔓 영구 구매 지속:", player.Name, id)
    end
    return true
end

-- itemName(모델명) → 영구 SKU id. 영구 소유 시 매 라운드 무상 지급(차감 없음)
-- 🗑️ [2026-08-29] ODM/Ice Bow 영구 SKU 제거로 비었다(ShopSystem 참조).
--   [왜 함수를 안 지우나] 테이블이 비면 OwnsPermanentItem 이 항상 false 를 반환해
--     RoundSystem 의 영구 지급 분기가 자연히 꺼진다. 나중에 다른 영구제를 넣을 때
--     여기 한 줄만 추가하면 되므로 구조는 남겨둔다.
local PERMANENT_SKU = {
}
_G.OwnsPermanentItem = function(player, itemName)
    local id = PERMANENT_SKU[itemName]
    return id ~= nil and player:GetAttribute("OwnedItem_" .. id) == true
end

-- UseConsumableEvent 핸들러
local useConsumableEvent = game:GetService("ReplicatedStorage"):WaitForChild("UseConsumableEvent")
useConsumableEvent.OnServerEvent:Connect(function(player, itemName)
    -- 🔒 [2026-08-30] 리모트 인자 검증. 클라가 보내는 값은 신뢰하지 않는다.
    --   [무엇이 이미 막혀 있나] _G.UseConsumable 안에서 보유 수량을 확인하므로
    --     "안 가진 아이템을 쓰는" 것은 원래 불가능하다. 아래는 그 앞단 방어다.
    --   ① 타입: 문자열이 아니면 즉시 차단(테이블·숫자·nil 로 내부 로직을 흔드는 시도).
    --   ② 화이트리스트: ALL_RUNNER_ITEMS 에 없는 이름은 거부.
    --     ServerStorage.RunnerItem 에 있는 아무 Tool 이나 부르는 것을 막는다
    --     (예: 태거 전용 도구가 같은 폴더에 추가되면 그대로 뚫린다).
    --   ③ 라운드 검사: 로비에서 호출하면 Tool 이 지급돼 로비에서 무기를 들고 다닐 수 있다.
    --   ⚠️ 여기서 막아도 _G.UseConsumable 자체는 서버 내부에서 계속 쓰인다.
    --     내부 호출은 신뢰 대상이므로 그쪽에 가드를 넣지 않는다.
    if type(itemName) ~= "string" or #itemName == 0 or #itemName > 40 then return end

    local allowed = false
    for _, data in ipairs(ALL_RUNNER_ITEMS) do
        if data.name == itemName and data.consumable then allowed = true break end
    end
    if not allowed then
        warn("🚫 [Remote] 알 수 없는 소모품 요청:", player.Name, tostring(itemName))
        return
    end

    -- 라운드 밖(로비)에서는 소모품을 쓸 수 없다.
    if player:GetAttribute("Role") == nil then return end

    _G.UseConsumable(player, itemName)
end)

-- -- ── 플레이어 이벤트 ───────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
    loadPlayerData(player)
end)

Players.PlayerRemoving:Connect(function(player)
    -- 💾 ⚠️ 여기만 saveNow(즉시). savePlayerData 는 6초 디바운스라
    --    예약이 실행되기 전에 플레이어가 사라져 데이터가 통째로 유실된다.
    saveNow(player)
    playerLoadouts[player.UserId]       = nil
    playerRunnerLoadouts[player.UserId] = nil
    playerConsumables[player.UserId]    = nil
    roundConsumableUsed[player.UserId]  = nil   -- [CONSUMABLE-ONUSE] 누수 방지
    playerOwnedPermanents[player.UserId] = nil
    passCache[player.UserId]            = nil
    dataLoaded[player.UserId]           = nil
end)

-- 🔌 [2026-08-30] 서버 종료 시 전원 저장.
--   [왜] 위 PlayerRemoving 의 saveNow 는 서버 종료 시 완료가 보장되지 않는다.
--     핸들러가 SetAsync 를 끝내기 전에 프로세스가 내려갈 수 있다.
--     BindToClose 는 로블록스가 최대 30초 기다려 주는 유일한 지점이다.
--   [유실 시나리오] 소모품을 쓰면 savePlayerData 가 6초 디바운스로 예약된다.
--     그 6초 안에 서버가 닫히면 예약은 실행되지 않고 변경분이 통째로 날아간다.
--   ⚠️ QuestBoot·DailyRewardBoot·BattlePassSystem 은 이미 같은 처리를 한다.
--     LoadoutManager 만 빠져 있었다(2026-08-30 전수 확인).
--   ⚠️ 여기선 savePlayerData(디바운스) 가 아니라 saveNow 를 부른다. 미루면 저장할 기회가 없다.
game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        saveNow(player)
    end
end)

for _, player in ipairs(Players:GetPlayers()) do
    loadPlayerData(player)
end

print("✅ LoadoutManager 준비 완료! (기본값: Wood Log)")
