-- GrappleUIWatchdog
-- ODM Gear의 ChargeUI("GrappleChargeUI") ScreenGui를 외부에서 청소해주는 watchdog.
--
-- 필요성: ChargeUI는 Tool 내부 LocalScript가 만들고 청소하는데,
-- Tool이 destroy되면 LocalScript도 같이 죽고 connection이 자동 disconnect됨.
-- 그래서 charges 소진→Tool destroy 또는 사망 시나리오에서 청소가 안 됨.
-- 이 스크립트는 Tool 밖에 있어서 Tool 생사와 무관하게 동작.

local Players = game:GetService("Players")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local UI_NAME = "GrappleChargeUI"
local TOOL_NAME = "ODM Gear"

local function destroyUI()
	local ui = PlayerGui:FindFirstChild(UI_NAME)
	if ui then ui:Destroy() end
end

-- Backpack/Character 어디에도 ODM Gear가 없으면 진짜 destroy된 것
local function isToolAlive()
	local backpack = Player:FindFirstChild("Backpack")
	if backpack and backpack:FindFirstChild(TOOL_NAME) then return true end
	local char = Player.Character
	if char and char:FindFirstChild(TOOL_NAME) then return true end
	return false
end

-- Tool이 컨테이너에서 제거됨 → unequip(이동)일 수도, 진짜 destroy일 수도
-- 잠깐 기다린 뒤에도 어디에도 없으면 destroy로 간주 → UI 정리
local function onChildRemoved(child)
	if child.Name ~= TOOL_NAME then return end
	task.wait(0.1)  -- equip/unequip flicker 대비
	if not isToolAlive() then
		destroyUI()
	end
end

-- 사망 즉시 청소
local function bindHumanoidDied(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.Died:Connect(destroyUI)
	end
end

-- 캐릭터별 binding (새 character마다 ChildRemoved 새로 연결)
local function bindToCharacter(character)
	bindHumanoidDied(character)
	character.ChildRemoved:Connect(onChildRemoved)
end

if Player.Character then bindToCharacter(Player.Character) end
Player.CharacterAdded:Connect(bindToCharacter)

-- Backpack은 player의 영구 자식이므로 1회만 bind
local backpack = Player:WaitForChild("Backpack")
backpack.ChildRemoved:Connect(onChildRemoved)

-- 캐릭터 hierarchy 제거 시 청소 (라운드 종료/스폰 리셋 백업)
Player.CharacterRemoving:Connect(destroyUI)
