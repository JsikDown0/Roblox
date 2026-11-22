-- Wood Shield Server Script
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")
local PhysicsService    = game:GetService("PhysicsService")

local placeEvent   = ReplicatedStorage:WaitForChild("WoodShieldPlace")
local clearEvent   = ReplicatedStorage:WaitForChild("WoodShieldClear")

local SHIELD_DURATION = 3       -- 충돌 후 소멸까지 시간(초)

-- 🛡️ 방패 확대 배율.
-- ⚠️ 클라(WoodShieldClient)의 SHIELD_SCALE 과 반드시 같은 값. 다르면 청사진과 실물이 어긋난다.
--    클라는 이 값으로 Y_LIFT 도 보정하므로(커진 높이의 절반만큼 올림),
--    한쪽만 바꾸면 방패가 지면에 묻히거나 공중에 뜬다.
local SHIELD_SCALE    = 1.5
local MAX_PLACE_DIST  = 80      -- 직사각형 모서리 대각선 길이(~72) + 여유
--   ⚠️ 이 값은 클라(WoodShieldClient)의 RANGE_W/RANGE_L 에서 파생된다.
--      계산: √((RANGE_W/2)² + RANGE_L²) = √(17² + 70²) ≈ 72 → 여유 포함 80.
--      [이력] 45 였을 때는 옛 범위(W 55 / L 28)의 대각선 ~39 기준이었다.
--      ⚠️ 클라 범위를 바꾸면 여기도 반드시 다시 계산할 것. 이 값이 작으면
--         청사진은 초록인데 서버가 거부하는 "되는 줄 알았는데 안 되는" 상태가 된다.
local COOLDOWN        = 8       -- 설치 후 쿨다운(초)

local cooldowns = {}

local tool = script.Parent  -- 이 스크립트가 속한 Wood Shield Tool 인스턴스

-- 원본 모델 참조
local shieldTemplate = game:GetService("ReplicatedStorage")
	:WaitForChild("ItemTemplates"):FindFirstChild("wood Shield")

local function makeHealthBar(shieldModel, maxBlocks)
	-- Union(방패 중심)에 부착해서 정중앙에 표시
	local anchor = nil
	for _, p in ipairs(shieldModel:GetDescendants()) do
		if p:IsA("UnionOperation") then anchor = p break end
	end
	if not anchor then anchor = shieldModel:FindFirstChildWhichIsA("BasePart") end
	if not anchor then return nil, nil, nil end

	-- HP 바 BillboardGui
	local hpBB = Instance.new("BillboardGui")
	hpBB.Name = "ShieldHPBar"
	hpBB.Size = UDim2.new(0, 90, 0, 18)
	hpBB.StudsOffset = Vector3.new(0, 4.5, 0)
	hpBB.AlwaysOnTop = true
	hpBB.ResetOnSpawn = false
	hpBB.Parent = anchor

	local bg = Instance.new("Frame", hpBB)
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel = 0
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0.5, 0)

	local bar = Instance.new("Frame", bg)
	bar.Name = "Bar"
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
	bar.BorderSizePixel = 0
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0.5, 0)

	local hpLabel = Instance.new("TextLabel", bg)
	hpLabel.Size = UDim2.new(1, 0, 1, 0)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Text = maxBlocks .. "/" .. maxBlocks
	hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hpLabel.TextScaled = true
	hpLabel.Font = Enum.Font.GothamBold
	hpLabel.ZIndex = 2

	-- 타이머 BillboardGui (HP 바와 별개로 위에 배치)
	local timerBB = Instance.new("BillboardGui")
	timerBB.Name = "ShieldTimer"
	timerBB.Size = UDim2.new(0, 70, 0, 18)
	timerBB.StudsOffset = Vector3.new(0, 6.5, 0)
	timerBB.AlwaysOnTop = true
	timerBB.ResetOnSpawn = false
	timerBB.Parent = anchor

	local timerLabel = Instance.new("TextLabel", timerBB)
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, 0, 1, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "30s"
	timerLabel.TextColor3 = Color3.fromRGB(255, 220, 80)
	timerLabel.TextScaled = true
	timerLabel.Font = Enum.Font.GothamBold

	return bar, hpLabel, timerLabel
end

local function updateHealthBar(bar, label, current, max)
	if bar  then bar.Size = UDim2.new(current / max, 0, 1, 0) end
	if label then label.Text = current .. "/" .. max end
end

-- 설치 요청 처리
placeEvent.OnServerEvent:Connect(function(player, placeCFrame)
	-- 백팩에 여러 Wood Shield가 있을 때 모든 인스턴스의 use 스크립트가 이벤트를 받음.
	-- 현재 장착된 Tool의 스크립트만 응답해야 함 (Tool.Parent == Character).
	if tool.Parent ~= player.Character then return end

	local userId = player.UserId
	local now = tick()

	if cooldowns[userId] and now - cooldowns[userId] < COOLDOWN then return end

	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- 수평 거리만 체크 (Y 차이 무시)
	local pPos = placeCFrame.Position
	local hPos = hrp.Position
	local horzDist = Vector3.new(pPos.X - hPos.X, 0, pPos.Z - hPos.Z).Magnitude
	if horzDist > MAX_PLACE_DIST then
		print("❌ Wood Shield: 설치 거리 초과", horzDist)
		return
	end

	-- Tool 자체가 소모품 (라운드 시작 시 이미 차감됨)
	-- 추가 차감 없이 Tool 존재 여부만 확인
	local char2 = player.Character
	local bp2 = player:FindFirstChild("Backpack")
	if not (char2 and char2:FindFirstChild("Wood Shield")) and not (bp2 and bp2:FindFirstChild("Wood Shield")) then
		print("❌ Wood Shield: Tool 없음")
		return
	end

	cooldowns[userId] = now
	-- [CONSUMABLE-ONUSE] 설치 확정 지점. 위 소유·쿨다운·거리·Tool존재 가드를
	--   모두 통과한 뒤여야 한다(가드에 걸려 return 되면 쓴 게 아니다).
	if _G.MarkConsumableUsed then _G.MarkConsumableUsed(player, "Wood Shield") end

	-- 청사진 제거 신호
	clearEvent:FireClient(player)

	-- 원본 모델 클론
	if not shieldTemplate then
		shieldTemplate = game:GetService("ReplicatedStorage")
			:WaitForChild("ItemTemplates"):FindFirstChild("wood Shield")
	end
	if not shieldTemplate then
		warn("wood Shield 모델을 찾을 수 없습니다!")
		return
	end

	-- 러너 장착 스킨 확인 → 템플릿 교체 (없으면 원본 나무 방패)
	local activeTemplate = shieldTemplate
	local skinUpright = false  -- 스킨 방패는 기본 기울기(30도) 없이 똑바로 세움
	local blockFxType = nil    -- 방어 성공 FX 종류("aegis"/"spark") — 스킨 데이터가 선언
	if _G.getEquippedSkin and _G.getSwordSkinData then
		local skinName = _G.getEquippedSkin(player, tool.Name)
		if skinName then
			local sd = _G.getSwordSkinData(tool.Name, skinName)
			if sd and sd.templateSwap then
				local swap = ServerStorage:FindFirstChild("WeaponSkins")
				swap = swap and swap:FindFirstChild(sd.templateSwap)
				if swap then activeTemplate = swap; skinUpright = true; blockFxType = sd.blockFx end
			end
		end
	end

	local shield = activeTemplate:Clone()
	shield.Name = "PlacedWoodShield_" .. userId

	-- 🛡️ 확대. ⚠️ 클라(WoodShieldClient)의 SHIELD_SCALE 과 반드시 같은 값이어야 한다.
	--    다르면 청사진으로 본 크기와 실제 설치물이 어긋난다.
	--    ⚠️ Anchored 를 세우기 '전에' 스케일해야 한다. 고정 후 크기를 바꾸면
	--       파트가 제자리에서 커지며 서로 어긋날 수 있다.
	--    ⚠️ 스킨 교체 템플릿(templateSwap)도 같은 배율을 받는다. 스킨마다 원본 크기가
	--       다르면 결과도 달라지므로, 스킨 방패가 이상하면 여기를 먼저 볼 것.
	if shield:IsA("Model") then
		pcall(function() shield:ScaleTo(SHIELD_SCALE) end)
	end
	if skinUpright then shield:SetAttribute("IsLegendShield", true) end  -- 스킨 방패 표식(외형 보존용)
	if blockFxType then shield:SetAttribute("ShieldBlockFx", blockFxType) end  -- 방어 성공 FX 종류(aegis/spark)
	shield.Parent = workspace
	-- PivotTo 전에 먼저 Anchored 설정 (물리로 흩어짐 방지)
	for _, part in ipairs(shield:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	-- 위치 설정 (PivotTo 사용: 바운딩박스 중심 기준)
	local finalCFrame = placeCFrame
	if skinUpright then
		-- placeCFrame는 pos * Y회전 * Z(30도)이므로, Z-30을 곱해 기울기만 상쇄(태거 방향 유지)
		finalCFrame = placeCFrame * CFrame.Angles(0, 0, math.rad(-30))
	end
	shield:PivotTo(finalCFrame)

	-- 모든 파트 고정 (원래 색상 그대로 유지)
	for _, part in ipairs(shield:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CollisionGroup = "WoodShield"
			-- 투명도는 템플릿 원본 유지 (유리 스킨 반투명 + 앵커/히트박스 투명 보존)
		end
	end

		-- HP/타이머 UI 생성
		local MAX_BLOCKS = 1
		local bar, hpLabel, timerLabel = makeHealthBar(shield, MAX_BLOCKS)

		-- 충돌/타이머는 Tool 밖 WoodShieldManager에서 처리 (Tool 삭제돼도 유지)
		if _G.StartWoodShield then
			_G.StartWoodShield(shield, timerLabel, player, finalCFrame)
		else
			warn("WoodShieldManager not loaded!")
		end

		-- 자기 자신만 제거 (다른 Wood Shield 인스턴스는 손대지 않음)
		if tool and tool.Parent then
			tool:Destroy()
		end
		print("🛡️ Wood Shield 설치:", player.Name)
	end)
print("✅ Wood Shield Server ready!")
