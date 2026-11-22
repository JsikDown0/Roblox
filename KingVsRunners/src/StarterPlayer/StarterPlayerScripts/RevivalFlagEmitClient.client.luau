-- RevivalFlagEmitClient
-- 부활 깃발 설치 시점에 *클라이언트에서* ParticleEmitter:Emit(n) 호출하여
-- 즉시 강렬한 파티클 폭발을 만듦.
--
-- 이유: ParticleEmitter:Emit()은 *호출한 클라이언트 화면에만* 보이므로,
--       모든 클라가 자기 화면에서 호출해야 모두 보임.
--       서버에서 직접 Emit() 호출 시 다른 클라에 안 보이는 문제.
--
-- 흐름:
--   서버 → RevivalFlagEmit:FireAllClients(flagEffectPart)
--   클라 → 받은 Part의 모든 ParticleEmitter 찾아서 Emit(EMIT_COUNT) 호출

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local emitEvent = ReplicatedStorage:WaitForChild("RevivalFlagEmit")

-- 각 ParticleEmitter당 즉시 방출할 파티클 개수
-- 더 큰 폭발 원하면 50~100, 절제된 효과는 15~25
local EMIT_COUNT = 30

emitEvent.OnClientEvent:Connect(function(flagEffectPart)
    if not flagEffectPart or not flagEffectPart.Parent then return end

    -- flag effect Part의 *모든 자식 ParticleEmitter*에 즉시 Emit
    -- (자식의 자식까지 포함 — Attachment 안의 ParticleEmitter 케이스)
    for _, desc in ipairs(flagEffectPart:GetDescendants()) do
        if desc:IsA("ParticleEmitter") then
            desc:Emit(EMIT_COUNT)
        end
    end
end)

print("✅ RevivalFlagEmitClient 활성화 (EMIT_COUNT:", EMIT_COUNT, ")")
