-- Decoy Wand Client
-- 장착 후 클릭(Activated) 시 서버에 분신 소환 요청을 보낸다.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player   = Players.LocalPlayer
local tool     = script.Parent
local useEvent = ReplicatedStorage:WaitForChild("DecoyUse")

local used = false

-- 사용 사운드 미리 생성 (지연 최소화)
local sound = Instance.new("Sound")
sound.SoundId            = "rbxassetid://92235360782852" -- Speed Potion과 동일한 마법 사운드 (필요 시 교체)
sound.Volume             = 0.9
sound.RollOffMaxDistance = 50
sound.Parent             = tool:FindFirstChild("Handle") or tool

local RETRY_AFTER = 1.5   -- 서버가 거부했을 때 다시 시도할 수 있게 되는 시간(연타 방지용)

tool.Activated:Connect(function()
    if used then return end
    used = true

    sound:Play()
    useEvent:FireServer()

    -- [DECOY-CLIENT-DESTROY] 예전엔 여기서 1.2초 뒤 tool:Destroy() 를 무조건 호출했다.
    --   서버(DecoySystem)는 다운·쿨다운·상태이상 가드에 걸리면 그냥 return 하는데,
    --   클라는 그걸 모르고 툴을 지워서 "효과도 안 나가고 툴만 사라지는" 손실이 났다
    --   (실측: 다운 중 사용 → 분신 없음 + 인벤에서 사라짐 + 차감도 안 됨).
    --   서버가 성공하면 removeTool() 로 캐릭터·백팩 양쪽에서 지우므로
    --   클라가 지울 필요가 애초에 없다. 여기선 연타만 막고 놔둔다.
    task.delay(RETRY_AFTER, function()
        if tool and tool.Parent then
            used = false   -- 서버가 안 지웠다 = 거부됨 → 다시 쓸 수 있게
        end
    end)
end)
