local Tool = script.Parent
local Remote = Tool:WaitForChild("Remote")
local Handle = Tool:WaitForChild("Handle")
local DamageScript = script:WaitForChild("Damage")
local Config = Tool:WaitForChild("Config")
local Heartbeat = game:GetService("RunService").Heartbeat

-- Hill 영역 체크용
local PickupConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("PickupConfig"))
local function isInsideHill(pos)
	local geo = PickupConfig.GetGeometry()
	local zHalf = geo.zWidth / 2
	return pos.X >= geo.hillXMin and pos.X <= geo.hillXMax
		and pos.Z >= (geo.zCenter - zHalf) and pos.Z <= (geo.zCenter + zHalf)
end

local LeftDown = false

local AttackAble = true
local AttackVelocity = Config.Velocity.Value

local Character = nil
local Humanoid = nil

--returns the wielding player of this tool
function getPlayer()
	local char = Tool.Parent
	return game:GetService("Players"):GetPlayerFromCharacter(Character)
end

function Toss(direction)
	local handlePos = Vector3.new(Tool.Handle.Position.X, 0, Tool.Handle.Position.Z)
	local spawnPos = Character.Head.Position
	spawnPos  = spawnPos + (direction * 5)
	Tool.Handle.Transparency = 1
	local Object = Tool.Handle:Clone()
	Object.Parent = workspace
	Object.Transparency = 1
	Object.Swing.Pitch = math.random(90, 110)/100
	Object.Swing:Play()
	Object.CanCollide = true
	-- 태거 아이템과 충돌하지 않도록 Runners 그룹에 등록 (벽/지형엔 정상 충돌)
	Object.CollisionGroup = "Runners"
	for _, child in ipairs(Object:GetDescendants()) do
		if child:IsA("BasePart") then
			child.CollisionGroup = "Runners"
		end
	end
	Object.CFrame = Tool.Handle.CFrame
	Object.Velocity = (direction*AttackVelocity) + Vector3.new(0,AttackVelocity/7.5,0)
	Object.Trail.Enabled = true
	--Object.Sparks.Enabled = true
	local rand = 11.25
	Object.RotVelocity = Vector3.new(math.random(-rand,rand),math.random(-rand,rand),math.random(-rand,rand))
	Object:SetNetworkOwner(getPlayer())
	local ScriptClone = DamageScript:Clone()
	ScriptClone.Parent = Object
	ScriptClone.Disabled = false
	local tag = Instance.new("ObjectValue")
	tag.Value = getPlayer()
	tag.Name = "creator"
	tag.Parent = Object
	Tool:Destroy()
end


script.Parent.Power.OnServerEvent:Connect(function(player, Power)
	AttackVelocity = Power
end)

Remote.OnServerEvent:Connect(function(player, mousePosition, power)
	if not AttackAble then return end
	-- Hill 영역 밖에선 투척 거부
	if Character and Character:FindFirstChild("HumanoidRootPart") and not isInsideHill(Character.HumanoidRootPart.Position) then
		Remote:FireClient(player, "OutsideHill")
		return
	end
	AttackAble = false
	if Humanoid and Humanoid.RigType == Enum.HumanoidRigType.R15 then
		Remote:FireClient(getPlayer(), "PlayAnimation", "Animation")
	end
	-- 클라이언트가 마우스 위치에 맞춰 계산한 Power 사용 (안전 클램프)
	if typeof(power) == "number" then
		AttackVelocity = math.clamp(power, 10, 500)
	end
	local targetPos = mousePosition.p
	local lookAt = (targetPos - Character.Head.Position).unit
	Toss(lookAt)
	-- [CONSUMABLE-ONUSE] 투척 확정 지점. AttackAble·Hill 범위 가드 통과 후.
	if _G.MarkConsumableUsed then _G.MarkConsumableUsed(player, "Gas Grenade") end
	LeftDown = true
end)

function onLeftUp()
	LeftDown = false
end

Tool.Equipped:Connect(function()
	Character = Tool.Parent
	Humanoid = Character:FindFirstChildOfClass("Humanoid")
end)

Tool.Unequipped:Connect(function()
	Character = nil
	Humanoid = nil
end)
