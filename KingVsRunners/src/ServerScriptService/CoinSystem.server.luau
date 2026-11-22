-- 코인 시스템 (서버)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

print("💰 CoinSystem 시작!")

-- 코인 데이터스토어 (나중에 저장용)
-- local coinStore = DataStoreService:GetDataStore("PlayerCoins")

-- RemoteEvents 생성
local getCoinEvent = ReplicatedStorage:FindFirstChild("GetCoinEvent")
if not getCoinEvent then
    getCoinEvent = Instance.new("RemoteFunction")
    getCoinEvent.Name = "GetCoinEvent"
    getCoinEvent.Parent = ReplicatedStorage
end

local updateCoinEvent = ReplicatedStorage:FindFirstChild("UpdateCoinEvent")
if not updateCoinEvent then
    updateCoinEvent = Instance.new("RemoteEvent")
    updateCoinEvent.Name = "UpdateCoinEvent"
    updateCoinEvent.Parent = ReplicatedStorage
end

-- 코인 단일 소스 = 프로필(DataService). 별도 테이블 없음.

-- 코인 가져오기 (프로필 = 단일 소스)
local function getCoins(player)
    local d = _G.DataService and _G.DataService.get(player)
    return d and d.Coins or 0
end

-- 코인 설정 (프로필에 기록 → ProfileStore가 세션락으로 안전 저장)
local function setCoins(player, amount)
    local d = _G.DataService and _G.DataService.get(player)
    if d then d.Coins = amount end
    player:SetAttribute("Coins", amount)
    updateCoinEvent:FireClient(player, amount)
    print("💰", player.Name, "코인:", amount)
end

-- 코인 추가
local function addCoins(player, amount)
    local current = getCoins(player)
    setCoins(player, current + amount)
end

-- 코인 차감
local function removeCoins(player, amount)
    local current = getCoins(player)
    if current >= amount then
        setCoins(player, current - amount)
        return true
    end
    return false
end

-- 플레이어 입장 시 프로필 코인 로드 → UI/속성 동기화 (0으로 덮지 않음)
Players.PlayerAdded:Connect(function(player)
    task.spawn(function()
        local d = _G.DataService and _G.DataService.waitForData(player, 20)
        if not d then return end   -- 로드 실패 시 DataService가 킥
        player:SetAttribute("Coins", d.Coins)
        updateCoinEvent:FireClient(player, d.Coins)
        print("💰", player.Name, "코인 로드:", d.Coins)
    end)
end)

-- 퇴장 시 코인 저장은 DataService(ProfileStore EndSession)가 처리 — 여기선 불필요

-- 클라이언트에서 코인 요청
getCoinEvent.OnServerInvoke = function(player)
    return getCoins(player)
end

-- 전역 함수로 등록 (다른 스크립트에서 사용)
_G.CoinSystem = {
    getCoins = getCoins,
    setCoins = setCoins,
    addCoins = addCoins,
    removeCoins = removeCoins
}

print("✅ CoinSystem 준비 완료!")
