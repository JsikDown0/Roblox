-- DoubleJumpServer: 클라가 더블점프 시 발판 이펙트 위치를 보내면, 다른 모든 클라에게 브로드캐스트
-- (이펙트는 각 클라에서 그려져 모두가 보게 됨). 점프 움직임 자체는 캐릭터 복제로 이미 보임.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("DoubleJumpFX")

local MIN_INTERVAL = 0.15   -- 플레이어별 스팸 방지
local MAX_OFFSET   = 14     -- 캐릭터에서 이 거리 안의 위치만 허용 (남용 방지)
local lastFire = {}

remote.OnServerEvent:Connect(function(player, footPos)
	if typeof(footPos) ~= "Vector3" then return end
	local now = os.clock()
	if lastFire[player] and now - lastFire[player] < MIN_INTERVAL then return end
	lastFire[player] = now

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if (root.Position - footPos).Magnitude > MAX_OFFSET then return end  -- 위치 검증

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			remote:FireClient(other, footPos, player)
		end
	end
end)

Players.PlayerRemoving:Connect(function(p) lastFire[p] = nil end)

print("✅ DoubleJumpServer ready (발판 이펙트 브로드캐스트)")
