-- 맵 투표 시스템 (결과 발표 추가)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

print("🗳️ MapVoteSystem 시작!")

local voteEvent = ReplicatedStorage:WaitForChild("MapVoteEvent")
local updateEvent = ReplicatedStorage:WaitForChild("MapVoteUpdate")
local startEvent = ReplicatedStorage:WaitForChild("MapVoteStart")
local resultEvent = ReplicatedStorage:WaitForChild("MapVoteResult")

-- 투표 데이터
local votes = {
    map1 = {},
    map2 = {}
}

local isVoting = false

-- 투표 초기화
local function resetVotes()
    votes.map1 = {}
    votes.map2 = {}
end

-- 투표 업데이트 전송
-- VIP는 2표 (일반 1표). _G.HasVIP로 판정 (PresetManager 노출).
local function tallyVotes(voters)
    local n = 0
    for _, userId in ipairs(voters) do
        local p = Players:GetPlayerByUserId(userId)
        n = n + ((p and _G.HasVIP and _G.HasVIP(p)) and 2 or 1)
    end
    return n
end
local function broadcastVotes()
    updateEvent:FireAllClients(votes, { map1 = tallyVotes(votes.map1), map2 = tallyVotes(votes.map2) })
end

-- 플레이어 투표 처리
voteEvent.OnServerEvent:Connect(function(player, mapName)
    if not isVoting then return end
    if not votes[mapName] then return end
    
    -- 기존 투표 제거
    for map, voters in pairs(votes) do
        for i, userId in ipairs(voters) do
            if userId == player.UserId then
                table.remove(voters, i)
                break
            end
        end
    end
    
    -- 새 투표 추가
    table.insert(votes[mapName], player.UserId)
    
    print("📊 투표:", player.Name, "→", mapName)
    broadcastVotes()
end)

-- 투표 시작 함수
local function startVote(duration)
    duration = duration or 15
    
    resetVotes()
    isVoting = true
    
    print("🗳️ 맵 투표 시작! (" .. duration .. "초)")
    
    -- 모든 플레이어에게 UI 표시
    startEvent:FireAllClients(duration)
    
    -- 투표 시간 대기
    task.wait(duration)
    
    isVoting = false
    
    -- 투표 집계
    local map1Votes = tallyVotes(votes.map1)
    local map2Votes = tallyVotes(votes.map2)
    
    print("📊 투표 결과:")
    print("  map1:", map1Votes .. "표")
    print("  map2:", map2Votes .. "표")
    
    local winner
    if map1Votes > map2Votes then
        winner = "map1"
    elseif map2Votes > map1Votes then
        winner = "map2"
    else
        -- 동점 시 랜덤
        winner = (math.random(1, 2) == 1) and "map1" or "map2"
        print("  (동점 - 랜덤 선택)")
    end
    
    print("✅ 승리 맵:", winner)
    
    -- 클라이언트에 결과 전송 (2초간 표시)
    resultEvent:FireAllClients(winner)
    print("📢 결과 발표 전송:", winner)
    
    -- 결과 표시 시간 대기: 클라 발표 연출(3.5초)이 끝난 뒤 라운드 진행 (겹침 방지)
    task.wait(4)
    
    return winner
end

-- _G에 등록
_G.MapVoteSystem = {
    startVote = startVote
}

print("✅ MapVoteSystem 준비 완료!")
print("  _G.MapVoteSystem =", _G.MapVoteSystem ~= nil)
