-- Mic Bomb 조준/발사 (독자 설계: 바닥 원형 리티클 + 클릭 투척, 일회용)
-- 장착하면 마우스 지점에 조준 원이 표시되고, 클릭하면 그 지점으로 투척.

local Tool = script.Parent
local RM = Tool:WaitForChild("RemoteEvent")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local MAX_DISTANCE = 250
local COLOR_IN  = Color3.fromRGB(255, 90, 170)   -- 사거리 안
local COLOR_OUT = Color3.fromRGB(120, 120, 120)  -- 사거리 밖(클램프됨)

local mouse, fired, reticle, conn

local function destroyReticle()
	if conn then conn:Disconnect() conn = nil end
	if reticle then reticle:Destroy() reticle = nil end
end

local function makeReticle()
	destroyReticle()
	reticle = Instance.new("Part")
	reticle.Name = "MicAimReticle"
	reticle.Shape = Enum.PartType.Cylinder
	reticle.Size = Vector3.new(0.2, 18, 18)   -- 얇은 원반 (X=두께, Y/Z=지름, 착탄 반경에 맞춤)
	reticle.Anchored = true
	reticle.CanCollide = false
	reticle.CanQuery = false
	reticle.CanTouch = false
	reticle.Material = Enum.Material.Neon
	reticle.Color = COLOR_IN
	reticle.Transparency = 0.45
	reticle.Parent = workspace
end

local function update()
	if not (reticle and mouse) then return end
	local p = mouse.Hit and mouse.Hit.Position
	if not p then return end
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local clamped = false
	if hrp then
		local to = p - hrp.Position
		if to.Magnitude > MAX_DISTANCE then
			p = hrp.Position + to.Unit * MAX_DISTANCE
			clamped = true
		end
	end
	-- 조준점 바로 위에서 아래로 레이캐스트 → hill 표면 위치/법선 (캐릭터/더미는 무시)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { reticle }
	if char then filter[#filter + 1] = char end
	rayParams.FilterDescendantsInstances = filter
	local origin = p + Vector3.new(0, 60, 0)
	local hit
	for _ = 1, 6 do
		hit = workspace:Raycast(origin, Vector3.new(0, -400, 0), rayParams)
		if not hit then break end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			-- Humanoid 더미/캐릭터에 맞으면 제외하고 다시 쏨 (실제 바닥만 찾기)
			filter[#filter + 1] = model
			rayParams.FilterDescendantsInstances = filter
		else
			break
		end
	end
	local surfPos = (hit and hit.Position) or p
	local up = (hit and hit.Normal) or Vector3.new(0, 1, 0)
	-- 법선(up)에 직교하는 기저 구성 후, 원반(실린더 로컬 X축)을 up에 맞춰 눕히기
	local ref = math.abs(up.Y) > 0.99 and Vector3.new(0, 0, -1) or Vector3.new(0, 1, 0)
	local right = ref:Cross(up)
	if right.Magnitude < 1e-3 then right = Vector3.new(1, 0, 0) end
	right = right.Unit
	reticle.CFrame = CFrame.fromMatrix(surfPos + up * 0.1, right, up) * CFrame.Angles(0, 0, math.rad(90))
	reticle.Color = clamped and COLOR_OUT or COLOR_IN
end

Tool.Equipped:Connect(function(m)
	mouse = m
	fired = false
	-- 마우스 레이가 플레이어 본체를 무시하고 뒤쪽 지형에 캐스팅되게
	if LocalPlayer.Character then m.TargetFilter = LocalPlayer.Character end
	makeReticle()
	if conn then conn:Disconnect() end
	conn = RunService.RenderStepped:Connect(update)
end)

Tool.Activated:Connect(function()
	if fired or not mouse then return end
	local p = mouse.Hit and mouse.Hit.Position
	if not p then return end
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local to = p - hrp.Position
		if to.Magnitude > MAX_DISTANCE then
			p = hrp.Position + to.Unit * MAX_DISTANCE
		end
	end
	fired = true
	destroyReticle()
	RM:FireServer(p)
end)

Tool.Unequipped:Connect(function()
	mouse = nil
	destroyReticle()
end)

Tool.Destroying:Connect(destroyReticle)
LocalPlayer.CharacterRemoving:Connect(destroyReticle)
