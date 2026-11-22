-- ⚰️ CoffinCutsceneCleanup
-- StarterPlayerScripts에 위치 → respawn에도 영향 안 받고 살아남음
-- 컷씬 도중 LoadCharacter가 일어나면 카메라 CFrame이 컷씬 끝 위치에 박혀
-- Custom 모드여도 카메라가 새 캐릭터를 못 따라감.
-- → CameraSubject 명시적 갱신 + CFrame 강제 리셋으로 CameraModule을 깨움.

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local function resetCameraToCharacter(character)
    local camera = workspace.CurrentCamera
    if not camera or not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")

    camera.CameraType = Enum.CameraType.Custom
    if humanoid then
        camera.CameraSubject = humanoid
    end
    if hrp then
        local pos = hrp.Position
        camera.CFrame = CFrame.new(pos + Vector3.new(0, 5, 12), pos)
    end
end

-- respawn 시마다 카메라를 새 캐릭터로 강제 재바인딩
localPlayer.CharacterAdded:Connect(function(character)
    character:WaitForChild("HumanoidRootPart", 3)
    character:WaitForChild("Humanoid", 3)
    task.wait(0.1)
    resetCameraToCharacter(character)
end)

print("✅ CoffinCutsceneCleanup 준비 완료")
