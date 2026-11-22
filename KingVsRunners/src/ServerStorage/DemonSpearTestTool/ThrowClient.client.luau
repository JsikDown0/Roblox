-- DemonSpearTestTool 클라: 장착 후 클릭한 곳으로 데몬 스피어 투척 요청
local Tool = script.Parent
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local re = RS:WaitForChild("_DSTestThrow")
local player = Players.LocalPlayer
local mouse = player:GetMouse()

Tool.Activated:Connect(function()
	local hit = mouse.Hit
	if hit then
		re:FireServer(hit.Position)
	end
end)
