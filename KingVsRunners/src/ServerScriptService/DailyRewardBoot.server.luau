-- ════════════════════════════════════════════════════════════════
-- DailyRewardBoot  (ServerScriptService / Script)
-- ────────────────────────────────────────────────────────────────
-- DailyRewardSystem 활성화: 입장/퇴장 로드·저장, 클라 조회·수령 처리.
-- ════════════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DailyRewardSystem = require(ServerScriptService:WaitForChild("DailyRewardSystem"))
_G.DailyRewardSystem = DailyRewardSystem

print("🎁 DailyRewardBoot 시작!")

-- 입장: 로드 후 클라이언트로 push
Players.PlayerAdded:Connect(function(player)
    DailyRewardSystem.load(player)
    task.delay(2, function()
        if player and player.Parent then
            DailyRewardSystem.pushToClient(player)
        end
    end)
end)

-- 부트 시점 기존 접속자
for _, player in ipairs(Players:GetPlayers()) do
    if not player:GetAttribute("_DailyRewardLoaded") then
        DailyRewardSystem.load(player)
        player:SetAttribute("_DailyRewardLoaded", true)
    end
end

-- 퇴장: 저장
Players.PlayerRemoving:Connect(function(player)
    DailyRewardSystem.unload(player)
end)

game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        DailyRewardSystem.save(player)
    end
end)

-- 클라이언트 데이터 조회
local dataEvent = ReplicatedStorage:WaitForChild("DailyRewardData")
dataEvent.OnServerInvoke = function(player)
    return DailyRewardSystem.getSnapshot(player)
end

-- 클라이언트 수령 요청
local claimEvent = ReplicatedStorage:WaitForChild("DailyRewardClaim")
claimEvent.OnServerEvent:Connect(function(player)
    local ok, reason = DailyRewardSystem.claim(player)
    if not ok then
        print(string.format("⚠️ 출석 수령 거절 (%s): %s", tostring(reason), player.Name))
    end
end)

print("✅ DailyRewardBoot 준비 완료!")
