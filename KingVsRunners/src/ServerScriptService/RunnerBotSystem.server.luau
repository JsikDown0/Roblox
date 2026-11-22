-- RunnerBotSystem
-- /runnerbot 명령어로 Noob2 NPC를 *러너 테스트 더미*로 활성화.
-- PushTool / 통나무 / 데미지 등 러너 대상 시스템들을 라운드 진행 없이 테스트 가능.
--
-- 기존 패턴 (/taggerbot, /downedbot)과 동일.
-- 라운드 시작 시 RoundSystem이 자체적으로 Noob2를 다시 적절히 설정하므로,
-- 이 시스템은 *비-라운드 테스트 환경*용.

local Players          = game:GetService("Players")
local PhysicsService   = game:GetService("PhysicsService")

-- 통로 중간 즈음 (러너가 진행하는 위치)
local TEST_POSITION = Vector3.new(400, 141, -650)

local isDev = require(game:GetService("ServerScriptService"):WaitForChild("DevAuth")).isDev

local function activateRunnerBot(player)
    if not isDev(player) then return end   -- 🔒 개발자 전용
    local noob2 = workspace:FindFirstChild("Noob2")
    if not noob2 then
        warn("[RunnerBotSystem] workspace.Noob2 모델 없음")
        return
    end

    local hum = noob2:FindFirstChildOfClass("Humanoid")
    if not hum then
        warn("[RunnerBotSystem] Noob2에 Humanoid 없음")
        return
    end

    -- 기준 파트 (R6는 Torso, R15는 HumanoidRootPart)
    local rootPart = noob2:FindFirstChild("HumanoidRootPart") or noob2:FindFirstChild("Torso")
    if not rootPart then
        warn("[RunnerBotSystem] Noob2에 Torso/HRP 없음")
        return
    end

    -- HP/상태 정상화
    hum.MaxHealth = 100
    hum.Health = 100
    hum.PlatformStand = false
    hum.WalkSpeed = 16

    -- 모든 파트: RunnerCharacter 그룹 + 비잠금
    for _, part in ipairs(noob2:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
            part.CollisionGroup = "RunnerCharacter"
        end
    end

    -- 다운/SOS/부활 등 러너 시스템 관련 속성 초기화
    noob2:SetAttribute("Downed", nil)
    noob2:SetAttribute("UsedRevive", nil)
    noob2:SetAttribute("ReviveInvul", nil)
    noob2:SetAttribute("SosActive", nil)

    -- 위치 이동 (통로 중간으로)
    rootPart.CFrame = CFrame.new(TEST_POSITION)
    rootPart.AssemblyLinearVelocity = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero

    print(string.format("🤖 RunnerBot 활성화: %s가 명령. 위치 %s",
        player and player.Name or "?", tostring(TEST_POSITION)))

    -- 사망 시 자동 부활 (테스트 편의)
    if not noob2:GetAttribute("RunnerBotAutoRespawn") then
        noob2:SetAttribute("RunnerBotAutoRespawn", true)
        hum.Died:Connect(function()
            task.wait(2)
            print("🤖 RunnerBot 자동 부활")
            -- 재귀적으로 다시 활성화 (HP 복구 + 위치 리셋)
            activateRunnerBot(player)
        end)
    end
end

-- 채팅 명령어
Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(msg)
        if msg:lower() == "/runnerbot" then
            activateRunnerBot(player)
        end
    end)
end)
for _, player in ipairs(Players:GetPlayers()) do
    player.Chatted:Connect(function(msg)
        if msg:lower() == "/runnerbot" then
            activateRunnerBot(player)
        end
    end)
end

print("✅ RunnerBotSystem 활성화 (/runnerbot 명령으로 Noob2 테스트 활성화)")
