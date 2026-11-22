-- ShieldBlockEmitClient: 서버가 보낸 위치에서 클라이언트가 직접 방패 방어 버스트 생성+Emit.
-- 서버 :Emit은 복제 안 되므로(PunchVfx와 동일 이유) 위치만 받아 로컬 생성.
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local ev = RS:WaitForChild("ShieldBlockEmit")

-- 골드~오렌지 버스트 색
local GOLD_ORANGE = ColorSequence.new({
	ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 220, 90)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 150, 30)),
	ColorSequenceKeypoint.new(1,   Color3.fromRGB(230, 100, 15)),
})

-- 원본 ShieldFx 두 파티클(팽창 링 + 글로우)
local PARTS = {
	{
		tex = "rbxassetid://17086063752",
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 6),
		}),
		transp = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.194886, 0),
			NumberSequenceKeypoint.new(0.699378, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	},
	{
		tex = "rbxassetid://17086075673",
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 4.36894),
			NumberSequenceKeypoint.new(1, 11.74758),
		}),
		transp = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.497581, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	},
}

ev.OnClientEvent:Connect(function(pos, fxType)
	if typeof(pos) ~= "Vector3" then return end
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

	if fxType == "spark" then
		-- 건틀릿 과충전 스파크 재활용 (ReplicatedStorage.ShieldSparkFx)
		local tpl = RS:FindFirstChild("ShieldSparkFx")
		if tpl then
			for _, src in ipairs(tpl:GetChildren()) do
				if src:IsA("ParticleEmitter") then
					local pe = src:Clone()
					pe.Enabled = false
					pe.Rate = 0
					pe.Parent = att
					pe:Emit(55)
				end
			end
		end
	else
		-- 골드 버스트 (Aegis)
		for _, cfg in ipairs(PARTS) do
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = cfg.tex
			pe.Color = GOLD_ORANGE
			pe.Size = cfg.size
			pe.Transparency = cfg.transp
			pe.Rate = 0
			pe.Lifetime = NumberRange.new(0.6, 0.8)
			pe.Speed = NumberRange.new(0.001)
			pe.Rotation = NumberRange.new(-5, 5)
			pe.LightEmission = 1
			pe.LightInfluence = 0
			pe.Parent = att
			pe:Emit(14)
		end
	end

	Debris:AddItem(holder, 1.5)
end)

print("✅ ShieldBlockEmitClient 활성화")
