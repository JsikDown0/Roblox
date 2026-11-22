local ReplicatedStorage = game:GetService("ReplicatedStorage")
local emitEvent = ReplicatedStorage:WaitForChild("EmitParticlesEvent")

-- 파티클별 반복 루프 관리 (target 소멸 시 자동 종료)
local activeLoops = {}  -- target → 루프 active 플래그

emitEvent.OnClientEvent:Connect(function(target)
    if not target or not target.Parent then return end

    -- 이미 실행 중인 루프가 있으면 중지
    if activeLoops[target] then
        activeLoops[target] = false
    end
    activeLoops[target] = true

    -- 파티클별로 Lifetime.Max 주기마다 Emit 반복
    for _, d in ipairs(target:GetDescendants()) do
        if d:IsA("ParticleEmitter") then
            local fillCount = math.ceil(d.Rate * d.Lifetime.Max)
            fillCount = math.min(fillCount, 10)
            fillCount = math.max(fillCount, 1)

            local interval = d.Lifetime.Max  -- 수명이 끝날 때마다 재발사

            task.spawn(function()
                while activeLoops[target] and target.Parent and d.Parent do
                    d:Emit(fillCount)
                    task.wait(interval)
                end
            end)
        end
    end

    print("✅ [Client] Emit 루프 시작:", target.Name)
end)

print("✅ ParticleEmitClient_TEST 준비 완료")
