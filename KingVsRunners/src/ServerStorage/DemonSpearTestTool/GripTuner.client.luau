-- DemonSpearTestTool 그립 튜너: 장착 후 키로 손에 든 창 위치/각도 직접 조정
-- 이동: I/K(위아래) J/L(좌우) U/M(앞뒤)  |  회전: Y/H(pitch) T/G(yaw) R/F(roll)
-- Shift = 미세(0.02 / 1도)  |  P = 현재 Grip 값 출력  |  Z = 초기화
local Tool = script.Parent
local UIS = game:GetService("UserInputService")

local grip = Tool.Grip
local function apply() Tool.Grip = grip end

local function step() return UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 0.02 or 0.1 end
local function rstep() return UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 1 or 5 end

local moves = {
	[Enum.KeyCode.I] = function() grip = grip * CFrame.new(0, step(), 0) end,
	[Enum.KeyCode.K] = function() grip = grip * CFrame.new(0, -step(), 0) end,
	[Enum.KeyCode.J] = function() grip = grip * CFrame.new(-step(), 0, 0) end,
	[Enum.KeyCode.L] = function() grip = grip * CFrame.new(step(), 0, 0) end,
	[Enum.KeyCode.U] = function() grip = grip * CFrame.new(0, 0, -step()) end,
	[Enum.KeyCode.M] = function() grip = grip * CFrame.new(0, 0, step()) end,
	[Enum.KeyCode.Y] = function() grip = grip * CFrame.Angles(math.rad(rstep()), 0, 0) end,
	[Enum.KeyCode.H] = function() grip = grip * CFrame.Angles(math.rad(-rstep()), 0, 0) end,
	[Enum.KeyCode.T] = function() grip = grip * CFrame.Angles(0, math.rad(rstep()), 0) end,
	[Enum.KeyCode.G] = function() grip = grip * CFrame.Angles(0, math.rad(-rstep()), 0) end,
	[Enum.KeyCode.R] = function() grip = grip * CFrame.Angles(0, 0, math.rad(rstep())) end,
	[Enum.KeyCode.F] = function() grip = grip * CFrame.Angles(0, 0, math.rad(-rstep())) end,
}

local active = false
Tool.Equipped:Connect(function() active = true end)
Tool.Unequipped:Connect(function() active = false end)

UIS.InputBegan:Connect(function(input, gp)
	if gp or not active then return end
	local fn = moves[input.KeyCode]
	if fn then
		fn(); apply()
	elseif input.KeyCode == Enum.KeyCode.P then
		local rx, ry, rz = grip:ToOrientation()
		print(string.format("[GRIP] CFrame.new(%.3f, %.3f, %.3f) * CFrame.fromOrientation(math.rad(%.1f), math.rad(%.1f), math.rad(%.1f))",
			grip.X, grip.Y, grip.Z, math.deg(rx), math.deg(ry), math.deg(rz)))
	elseif input.KeyCode == Enum.KeyCode.Z then
		grip = CFrame.new(); apply()
		print("[GRIP] 초기화")
	end
end)
