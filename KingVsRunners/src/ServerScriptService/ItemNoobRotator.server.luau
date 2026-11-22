-- ItemNoob 지속 회전 (모델 내부에 있을 때만 작동)
local RunService = game:GetService("RunService")
local model = script.Parent

-- ServerScriptService 등에 직접 있으면 작동 안 함
if not model:IsA("Model") and not model:IsA("BasePart") then
    -- 이 스크립트는 ItemNoob 모델 내부에 복사되어야 작동함
    return
end

-- PrimaryPart 찾기
local primaryPart = model:IsA("Model") and model.PrimaryPart or model

if not primaryPart or not primaryPart:IsA("BasePart") then
    warn("ItemNoobRotator: PrimaryPart가 BasePart가 아님!")
    return
end

print("✅ ItemNoob 회전 시작:", model.Name)

-- 매 프레임마다 회전 추가
local connection
connection = RunService.Heartbeat:Connect(function()
    if primaryPart and primaryPart.Parent then
        -- 현재 회전 속도 가져오기
        local success, currentAngularVel = pcall(function()
            return primaryPart.AssemblyAngularVelocity
        end)
        
        if success then
            -- 앞으로 굴러가는 회전 (X축) 지속 적용
            -- 회전이 느려지면 다시 추가
            if math.abs(currentAngularVel.X) < 10 then
                primaryPart.AssemblyAngularVelocity = Vector3.new(
                    20,  -- X축 회전 (앞으로 굴러가기)
                    currentAngularVel.Y,
                    currentAngularVel.Z
                )
            end
        end
    else
        -- 아이템이 삭제되면 연결 해제
        if connection then
            connection:Disconnect()
        end
    end
end)
