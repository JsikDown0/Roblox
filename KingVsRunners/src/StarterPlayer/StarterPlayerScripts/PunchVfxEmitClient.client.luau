-- PunchVfxEmitClient: 서버가 보낸 위치에서 *클라이언트가 직접* 임팩트 emitter 생성+Emit.
-- 서버 :Emit은 복제 안 됨 + 갓 만든 emitter는 복제 전이라, 위치만 받아 로컬 생성 = 복제 경쟁 없음.
-- 모든 클라가 각자 호출하므로 모두가 봄.
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local ev = RS:WaitForChild("PunchVfxEmit")

local PUNCH_IMG = "rbxassetid://9660494013"   -- 타격 이미지(검은 배경). LightEmission=1로 검은색 키아웃.

ev.OnClientEvent:Connect(function(pos, sizeStuds)
	if typeof(pos) ~= "Vector3" then return end
	sizeStuds = sizeStuds or 10
	local holder = Instance.new("Part")
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CFrame = CFrame.new(pos)
	holder.Parent = workspace
	local att = Instance.new("Attachment")
	att.Parent = holder
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = PUNCH_IMG
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.30)
	pe.Speed = NumberRange.new(0)
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1))
	pe.Rotation = NumberRange.new(-180, 180)
	pe.RotSpeed = NumberRange.new(-50, 50)
	pe.ZOffset = 2
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    sizeStuds * 0.55),
		NumberSequenceKeypoint.new(0.18, sizeStuds * 1.08),
		NumberSequenceKeypoint.new(1,    sizeStuds * 0.95),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    0),
		NumberSequenceKeypoint.new(0.55, 0.1),
		NumberSequenceKeypoint.new(1,    1),
	})
	pe.Parent = att
	pe:Emit(2)
	Debris:AddItem(holder, 1.0)
end)

print("✅ PunchVfxEmitClient 활성화")
