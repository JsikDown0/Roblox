-- 🎯 곡사포 프롬프트를 태거에게만 보이게
--
-- [왜] ProximityPrompt 는 서버에서 만들면 전원에게 보인다. 러너에게도
--      "곡사포 / 발사" 가 떠서 눌러보게 되는데, 서버가 역할을 검사하므로
--      작동은 안 한다. 눌러도 아무 일 없는 버튼은 혼란만 준다.
--
-- ⚠️ PickupPromptFilter 와 같은 방식이다.
--    Style 을 Custom 으로 바꾸면 기본 UI 가 그려지지 않는다.
--    (커스텀 UI 를 따로 만들지 않으므로 결과적으로 아무것도 안 보인다)
-- ⚠️ prompt.Enabled 를 끄지 않는다. 그건 서버가 쿨다운·단계 제어에 쓰는
--    값이라, 클라가 건드리면 서버 상태와 충돌한다.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local localPlayer = Players.LocalPlayer

local function isCannonPrompt(prompt)
    if prompt.Name ~= "CannonPrompt" then return false end
    local part = prompt.Parent
    if not part then return false end
    local model = part:FindFirstAncestorOfClass("Model")
    -- ⚠️ map1 Cannon / map2 MagicBook 둘 다 러너에게 숨긴다.
    return model ~= nil and (model.Name == "Cannon" or model.Name == "MagicBook")
end

local function getRole()
    -- ⚠️ Role 은 플레이어와 캐릭터 양쪽에 실릴 수 있다(기존 규약).
    local role = localPlayer:GetAttribute("Role")
    if role then return role end
    local char = localPlayer.Character
    if char then
        role = char:GetAttribute("Role")
        if role then return role end
    end
    return nil
end

ProximityPromptService.PromptShown:Connect(function(prompt)
    if not isCannonPrompt(prompt) then return end
    local role = getRole()
    -- 태거만 기본 UI 를 본다. 그 외(러너·관전자)는 숨긴다.
    if role == "Tagger" then return end
    prompt.Style = Enum.ProximityPromptStyle.Custom
end)

-- ⚠️ 역할이 바뀌면 이미 Custom 이 된 프롬프트를 되돌려야 한다.
--    다음 라운드에 태거가 됐는데 계속 안 보이면 곡사포를 못 쓴다.
local function restoreStyle()
    if getRole() ~= "Tagger" then return end
    for _, mapFolder in ipairs(workspace:GetChildren()) do
        if mapFolder:IsA("Folder") or mapFolder:IsA("Model") then
            for _, d in ipairs(mapFolder:GetChildren()) do
                if d:IsA("Model") and (d.Name == "Cannon" or d.Name == "MagicBook") then
                    local b = d.PrimaryPart or d:FindFirstChild("Barrel")
                    local p = b and b:FindFirstChild("CannonPrompt")
                    if p then p.Style = Enum.ProximityPromptStyle.Default end
                end
            end
        end
    end
end

localPlayer:GetAttributeChangedSignal("Role"):Connect(restoreStyle)
localPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    restoreStyle()
end)
restoreStyle()

print("✅ CannonPromptFilter 활성화 (러너에게 곡사포 prompt 숨김)")
