-- Speed Potion Server Script
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local useEvent = ReplicatedStorage:WaitForChild("SpeedPotionUse")

local SPEED_BOOST    = 12   -- 추가 속도 (기본 16 + 12 = 28)
local BOOST_DURATION = 5    -- 지속 시간 (초)
local COOLDOWN       = 6    -- 중복 발화 방지용 짧은 쿨다운
local DEFAULT_WALKSPEED = 16   -- DownSystem과 동일한 고정 기준값

local tool = script.Parent  -- 이 스크립트가 속한 Speed Potion Tool 인스턴스
local cooldowns = {}

useEvent.OnServerEvent:Connect(function(player)
    -- 백팩에 여러 Speed Potion이 있을 때 모든 인스턴스의 use 스크립트가 이벤트를 받음.
    -- 현재 장착된 Tool의 스크립트만 응답해야 함 (Tool.Parent == Character).
    if tool.Parent ~= player.Character then return end

    local userId = player.UserId
    local now    = tick()

    if cooldowns[userId] and now - cooldowns[userId] < COOLDOWN then return end
    cooldowns[userId] = now

    local character = player.Character
    if not character then return end
    local humanoid  = character:FindFirstChild("Humanoid")
    if not humanoid then return end

    -- 다운 상태에서는 SpeedPotion 발동 차단
    -- (다운 중에 발동하면 -12 차감 시점에 다운 상태일 경우 WalkSpeed가 음수가 됨)
    if character:GetAttribute("Downed") then
        print("🧪 SpeedPotion 사용 차단: 다운 상태 (", player.Name, ")")
        return
    end

    -- 부스트를 캐릭터 속성으로 노출 (서버 속성 → 클라 복제됨).
    -- 산데비스탄(RunnerDive)이 대시 복구 시 이 값을 합산해 라이브 계산하므로
    -- 대시 도중 포션이 만료/시작돼도 부스트 잔존(영구 가속)이나 소실이 없음.
    -- 절대값 세팅: 상대 +=/-= 누적으로 인한 꼬임 방지 (DownSystem 패턴과 일치).
    character:SetAttribute("SpeedBoost", SPEED_BOOST)
    humanoid.WalkSpeed = DEFAULT_WALKSPEED + SPEED_BOOST
    print("🧪 SpeedPotion 발동:", player.Name, "→ WalkSpeed", humanoid.WalkSpeed)
    -- [CONSUMABLE-ONUSE] 실제 발동 확정 지점. 위 Downed 가드를 통과한 뒤여야 한다.
    if _G.MarkConsumableUsed then _G.MarkConsumableUsed(player, "Speed Potion") end

    task.delay(BOOST_DURATION, function()
        -- 부스트 만료 (소스 오브 트루스 먼저 끔)
        if character then character:SetAttribute("SpeedBoost", 0) end
        if humanoid and humanoid.Parent then
            -- 다른 시스템(다운/프리즈/대시)이 WalkSpeed를 소유 중이면 건드리지 않음.
            -- 부스트된 값 그대로일 때만 기본값으로 환원 → 그 시스템들과 충돌 없음.
            if humanoid.WalkSpeed == DEFAULT_WALKSPEED + SPEED_BOOST then
                humanoid.WalkSpeed = DEFAULT_WALKSPEED
            end
            print("🧪 SpeedPotion 종료:", player.Name)
        end
        -- 자기 자신만 제거 (다른 Speed Potion 인스턴스는 손대지 않음)
        if tool and tool.Parent then
            tool:Destroy()
        end
    end)
end)
