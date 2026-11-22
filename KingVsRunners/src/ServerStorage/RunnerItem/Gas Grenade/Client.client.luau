local Player = game:GetService("Players").LocalPlayer
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Mouse = Player:GetMouse()
local Tool = script.Parent
local Remote = Tool:WaitForChild("Remote")
local Tracks = {}
local InputType = Enum.UserInputType
local IsEquipped = false
local BeganConnection

-- ===== 동적 파워 계산 (마우스 위치 = 착지 지점) =====
local GRAVITY = workspace.Gravity
local UP_KICK_RATIO = 1 / 7.5  -- 서버 Toss 공식의 수직 추가 성분
local MIN_POWER = 30
local MAX_POWER = 300

local function computePower(launchPos, targetPos)
	local toTarget = targetPos - launchPos
	local distance = toTarget.Magnitude
	local d = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude
	if d < 0.5 or distance < 0.001 then
		return MIN_POWER
	end
	local u = toTarget / distance
	local m_horiz = math.sqrt(u.X * u.X + u.Z * u.Z)
	local m_y = u.Y + UP_KICK_RATIO
	local h = toTarget.Y
	-- P² = 0.5·g·d² / (m_horiz · (m_y·d − h·m_horiz))
	local denom = m_horiz * (m_y * d - h * m_horiz)
	if denom <= 0.01 then return MAX_POWER end
	local P_squared = 0.5 * GRAVITY * d * d / denom
	if P_squared <= 0 then return MAX_POWER end
	return math.clamp(math.sqrt(P_squared), MIN_POWER, MAX_POWER)
end

local function pickAnimation(Power)
	if Power < 80 then return "Low"
	elseif Power < 170 then return "Med"
	else return "High" end
end

-- ===== 빨강 궤도 미리보기 =====
local TRAJECTORY_SEGMENTS = 50
local TRAJECTORY_DT = 0.04
local DOT_COLOR = Color3.fromRGB(255, 35, 35)
local MARKER_COLOR = Color3.fromRGB(255, 80, 80)
local DOT_SIZE = Vector3.new(0.5, 0.5, 0.5)
local MARKER_SIZE = Vector3.new(1.4, 1.4, 1.4)

-- 첫 충돌 후 연장: 튕김 반사로 자연스러운 호 표현
local EXTENSION_RATIO = 0.3       -- 비행 스텝의 30%만큼 추가 시뮬 (최소 4 스텝)
local BOUNCE_FRICTION = 0.7       -- 접선 방향 (수평) 속도 보존율 = 마찰
local BOUNCE_RESTITUTION = 0.3    -- 법선 방향 (수직) 반사 강도 = 탄성

local trajectoryFolder = nil
local trajectoryParts = {}
local trajectoryConn = nil
local landingMarker = nil

local function createTrajectory()
	if trajectoryFolder then return end
	trajectoryFolder = Instance.new("Folder")
	trajectoryFolder.Name = "GasGrenadeTrajectory"
	trajectoryFolder.Parent = workspace.CurrentCamera
	for i = 1, TRAJECTORY_SEGMENTS do
		local p = Instance.new("Part")
		p.Name = "TrajDot"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Material = Enum.Material.Neon
		p.Color = DOT_COLOR
		p.Shape = Enum.PartType.Ball
		p.Size = DOT_SIZE
		p.Transparency = 1
		p.Parent = trajectoryFolder
		trajectoryParts[i] = p
	end
	-- 착지 지점 큰 마커
	landingMarker = Instance.new("Part")
	landingMarker.Name = "LandingMarker"
	landingMarker.Anchored = true
	landingMarker.CanCollide = false
	landingMarker.CanQuery = false
	landingMarker.CanTouch = false
	landingMarker.Massless = true
	landingMarker.Material = Enum.Material.Neon
	landingMarker.Color = MARKER_COLOR
	landingMarker.Shape = Enum.PartType.Ball
	landingMarker.Size = MARKER_SIZE
	landingMarker.Transparency = 1
	landingMarker.Parent = trajectoryFolder
end

local function destroyTrajectory()
	if trajectoryConn then
		trajectoryConn:Disconnect()
		trajectoryConn = nil
	end
	if trajectoryFolder then
		trajectoryFolder:Destroy()
		trajectoryFolder = nil
	end
	trajectoryParts = {}
	landingMarker = nil
end

local function hideTrajectoryFrom(idx)
	for i = idx, TRAJECTORY_SEGMENTS do
		local part = trajectoryParts[i]
		if part then part.Transparency = 1 end
	end
	if landingMarker then landingMarker.Transparency = 1 end
end

local function updateTrajectory()
	if not IsEquipped or not trajectoryFolder then return end
	local char = Player.Character
	if not char then hideTrajectoryFrom(1) return end
	local head = char:FindFirstChild("Head")
	local handle = Tool:FindFirstChild("Handle")
	if not head or not handle then hideTrajectoryFrom(1) return end

	-- 서버 Toss와 동일한 공식 (direction은 Head 기준)
	local mouseHit = Mouse.Hit.Position
	local direction = mouseHit - head.Position
	if direction.Magnitude < 0.001 then hideTrajectoryFrom(1) return end
	direction = direction.Unit

	local Power = computePower(head.Position, mouseHit)
	local startPos = handle.Position
	local vel = direction * Power + Vector3.new(0, Power / 7.5, 0)
	local gravity = Vector3.new(0, -workspace.Gravity, 0)

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { char, trajectoryFolder, Tool }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true

	-- 일단 마커 숨김 (착지 발견 시 다시 표시)
	if landingMarker then landingMarker.Transparency = 1 end

	local pos = startPos
	local hitGround = false
	local visibleLimit = TRAJECTORY_SEGMENTS

	for i = 1, TRAJECTORY_SEGMENTS do
		local part = trajectoryParts[i]
		if not part then break end

		if i > visibleLimit then
			part.Transparency = 1
		else
			local prevPos = pos
			vel = vel + gravity * TRAJECTORY_DT
			pos = pos + vel * TRAJECTORY_DT

			local result = workspace:Raycast(prevPos, pos - prevPos, rayParams)
			if result then
				if not hitGround then
					-- ===== 1차 착지: 튕김 반사 =====
					hitGround = true
					visibleLimit = math.min(
						TRAJECTORY_SEGMENTS,
						i + math.max(4, math.floor(i * EXTENSION_RATIO))
					)

					pos = result.Position
					-- 법선 기준 속도 분해 후 감쇠
					local normal = result.Normal
					local vDotN = vel:Dot(normal)
					local vNormal = vDotN * normal      -- 표면으로 들어가는 성분
					local vTangent = vel - vNormal      -- 표면을 따라가는 성분
					-- 반사 + 감쇠: 접선은 마찰, 법선은 탄성으로 튕겨나옴
					vel = vTangent * BOUNCE_FRICTION - vNormal * BOUNCE_RESTITUTION
					-- 즉시 재충돌 방지를 위해 살짝 띄움
					pos = pos + normal * 0.1

					part.Position = result.Position
					part.Transparency = 0
					if landingMarker then
						landingMarker.Position = result.Position
						landingMarker.Transparency = 0
					end
				else
					-- ===== 2차 착지: 여기서 종료 + 마커 이동 =====
					pos = result.Position
					part.Position = pos
					part.Transparency = 0
					if landingMarker then
						landingMarker.Position = pos
					end
					visibleLimit = i  -- 이후 dot 숨김
				end
			else
				part.Position = pos
				part.Transparency = 0.05 + (i / TRAJECTORY_SEGMENTS) * 0.2
			end
		end
	end
end

-- ===== 애니메이션 =====
function playAnimation(animName)
	if Tracks[animName] then
		Tracks[animName]:Play()
	else
		local anim = Tool:FindFirstChild(animName)
		if anim and Tool.Parent and Tool.Parent:FindFirstChild("Humanoid") then
			Tracks[animName] = Tool.Parent.Humanoid:LoadAnimation(anim)
			playAnimation(animName)
		end
	end
end

-- ===== 좌클릭 투척 =====
function inputBegan(input)
	if input.UserInputType ~= InputType.MouseButton1 then return end
	if not IsEquipped then return end

	local char = Player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then return end

	-- 클릭 순간의 마우스 위치 → 그에 맞는 Power 산출
	local hitCFrame = Mouse.Hit
	local Power = computePower(head.Position, hitCFrame.Position)

	-- 던지기 commit: 궤도 미리보기 즉시 제거
	destroyTrajectory()

	-- [GRENADE-ANIM] 투척 자세 애니 호출을 막았다.
	--   Low/Med/High 세 애니 모두 00scorpion00 소유(마켓플레이스 툴에 딸려온 것)라
	--   재생이 안 되고 "액세스 권한이 없습니다" 에러만 로그를 더럽혔다.
	--   ⚠️ 아래 wait(1.15) 는 남긴다 — 투척 타이밍이 여기 걸려 있어서
	--      같이 지우면 던지기가 1.15초 빨라져 밸런스가 바뀐다.
	--   되살리려면 애니를 직접 업로드해 Low/Med/High 의 AnimationId 를 교체한 뒤
	--   아래 한 줄의 주석을 풀면 된다.
	-- playAnimation(pickAnimation(Power))
	wait(1.15)
	if not IsEquipped then return end
	Remote:FireServer(hitCFrame, Power)
end

function onEquip()
	BeganConnection = UIS.InputBegan:Connect(inputBegan)
	IsEquipped = true
	createTrajectory()
	trajectoryConn = RunService.RenderStepped:Connect(updateTrajectory)
end

function onUnequip()
	if BeganConnection then
		BeganConnection:Disconnect()
		BeganConnection = nil
	end
	IsEquipped = false
	destroyTrajectory()
end

Tool.Equipped:Connect(onEquip)
Tool.Unequipped:Connect(onUnequip)

-- 안전망: Tool 파괴 시(예: 서버에서 Tool:Destroy()) 궤도 잔존 방지
script.Destroying:Connect(destroyTrajectory)

-- 서버에서 "OutsideHill" 메시지 받으면 채팅 알림
Remote.OnClientEvent:Connect(function(action, ...)
	if action == "OutsideHill" then
		pcall(function()
			game:GetService("StarterGui"):SetCore("ChatMakeSystemMessage", {
				Text  = "⚠️ 연막탄은 언덕에서만 사용할 수 있습니다",
				Color = Color3.fromRGB(255, 180, 100),
				Font  = Enum.Font.SourceSansBold,
				TextSize = 18,
			})
		end)
	end
end)
