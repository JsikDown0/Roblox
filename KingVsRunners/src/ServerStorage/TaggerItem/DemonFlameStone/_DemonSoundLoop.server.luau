local sound = script.Parent:FindFirstChild("_DemonSound")
if not sound then return end
while true do
    sound:Play()
    task.wait(2)
end
