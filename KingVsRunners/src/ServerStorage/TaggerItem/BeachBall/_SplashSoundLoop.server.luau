local sound = script.Parent:FindFirstChild("_SplashSound")
if not sound then return end
while true do
    sound:Play()
    task.wait(2)
end
