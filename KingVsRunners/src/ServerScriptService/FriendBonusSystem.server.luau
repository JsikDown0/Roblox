-- FriendBonusSystem
-- 친구와 함께 접속해 라운드를 완주하면 배틀패스 XP 보너스를 준다.
--
-- 왜 코인이 아니라 배틀패스 XP 인가:
--   시뮬레이터류는 재화가 "진행"을 사기 때문에 초대 보너스를 재화로 줘도 안전하다
--   (재화가 늘면 진행이 빨라질 뿐이고 목표는 계속 위로 늘어난다).
--   이 게임의 코인은 코스메틱(유한)을 사고, 로벅스 랜덤 상자와 직접 경쟁한다.
--   따라서 코인 인플레는 "살 게 없어짐 + 로벅스 쓸 이유 감소"로 이어진다.
--   배틀패스 XP 는 시즌마다 리셋되고 상한이 있어 어뷰징 이득이 구조적으로 제한된다.
--
-- 수치 근거 (실측 계산):
--   완주 필요 23,200 XP / 라운드 일일 상한 700 → 라운드만으로 34일
--   시즌 35일이라 여유가 +1,300(약 2일분)뿐 → 하루만 빠져도 완주 불가
--   친구 보너스 일일 상한 120 → 29일 완주, 여유 +5,500(약 7일분)
--   퍼센트(+15%/명) 방식은 폐기: 일일 상한이 고정이라 "상한을 빨리 채울" 뿐
--   총 XP가 늘지 않아 완주 단축 효과가 0 이었다.
--
-- 어뷰징 방어:
--   · 라운드 완주 필요 (RoundSystem 의 코인 지급 루프에서 호출) → 방치 차단
--   · 로블록스 친구 관계 필요 → 아무나 같은 서버에 있는 것만으로는 안 됨
--   · 일일 상한 → 뚫려도 피해 규모가 제한됨

local Players = game:GetService("Players")

local DEBUG = false

-- 친구 관계 캐시: IsFriendsWith 는 웹 호출이라 라운드마다 전원 조회하면 부담이 크다.
-- 세션 중 친구 관계가 바뀌는 일은 드물어 캐시해도 안전하다.
local friendCache = {}   -- [uidA .. "_" .. uidB] = true/false

local function cacheKey(a, b)
    if a < b then return a .. "_" .. b end
    return b .. "_" .. a
end

local function areFriends(a, b)
    local key = cacheKey(a.UserId, b.UserId)
    local cached = friendCache[key]
    if cached ~= nil then return cached end
    local ok, result = pcall(function() return a:IsFriendsWith(b.UserId) end)
    if not ok then
        -- 조회 실패 시 보너스를 주지 않는다(관대하게 처리하면 어뷰징 경로가 된다)
        return false
    end
    friendCache[key] = result
    return result
end

-- 현재 서버에 함께 있는 친구 수 (최대 FRIEND_MAX_COUNT)
local function countCoPresentFriends(player)
    local maxCount = (_G.BattlePass and _G.BattlePass.FRIEND_MAX_COUNT) or 3
    local n = 0
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            if areFriends(player, other) then
                n += 1
                if n >= maxCount then break end
            end
        end
    end
    return n
end

local function grant(player)
    if not player or not player.Parent then return 0 end
    if not (_G.BattlePass and _G.BattlePass.addXP) then return 0 end

    local friends = countCoPresentFriends(player)
    if friends <= 0 then
        player:SetAttribute("FriendBonusCount", 0)
        return 0
    end

    local each = _G.BattlePass.FRIEND_XP_EACH or 10
    local amount = each * friends
    _G.BattlePass.addXP(player, amount, "friend")
    player:SetAttribute("FriendBonusCount", friends)

    if DEBUG then
        print(string.format("[FriendBonus] %s 친구 %d명 → +%d XP", player.Name, friends, amount))
    end
    return amount
end

-- 로비 UI 표시용: 현재 친구 수를 속성으로 갱신 (라운드 밖에서도 보이게)
local function refreshAll()
    for _, p in ipairs(Players:GetPlayers()) do
        local ok = pcall(function()
            p:SetAttribute("FriendBonusCount", countCoPresentFriends(p))
        end)
        if not ok then p:SetAttribute("FriendBonusCount", 0) end
    end
end

Players.PlayerAdded:Connect(function()
    task.wait(2)      -- 프로필/친구 정보 안정화 대기
    refreshAll()
end)
Players.PlayerRemoving:Connect(function(p)
    -- 캐시에서 해당 유저 항목 제거
    local uid = p.UserId
    for k in pairs(friendCache) do
        if k:find(tostring(uid), 1, true) then friendCache[k] = nil end
    end
    task.defer(refreshAll)
end)

refreshAll()

_G.FriendBonus = {
    grant = grant,
    count = countCoPresentFriends,
}

print(string.format("✅ FriendBonusSystem ready (친구 1명당 +%d XP, 일일 상한 %d)",
    (_G.BattlePass and _G.BattlePass.FRIEND_XP_EACH) or 10,
    (_G.BattlePass and _G.BattlePass.FRIEND_XP_CAP) or 120))
