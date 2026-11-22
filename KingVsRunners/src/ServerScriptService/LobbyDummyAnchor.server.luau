-- LobbyDummyAnchor — 로비 훈련 더미의 '밀림 + 제자리 복귀'
--
-- ═══ 왜 필요한가 ═══
-- 처음엔 Anchored=true 로 세웠는데, 그러면 넉백이 안 통해서
--   · 건틀렛 돌진 · 해머 슬램 · 평타 넉백
-- 이 전부 '맞긴 하는데 반응이 없는' 상태가 된다. 밀리는 걸 봐야 감이 온다.
--
-- ═══ 왜 ImmortalDummyController 에 안 넣었나 ═══
-- 거기는 'HP 회복' 담당이다. 위치 복귀는 성격이 다른 관심사고, 한 파일에 섞으면
-- "같은 규칙이 두 곳" 의 반대 문제 — 한 파일이 두 가지를 하다가 한쪽만 고쳐진다.
--
-- ═══ 설계 ═══
-- · 평소엔 물리를 켜 둔다(Anchored=false). 그래야 밀린다.
-- · 홈에서 LEASH 이상 벗어나거나, 일정 시간 이상 홈을 떠나 있으면 되돌린다.
-- · 되돌릴 때는 속도를 반드시 0 으로 만든다 — 관성이 남으면 복귀 직후 다시 밀린다
--   (오늘 건틀렛 finishDash 에서 겪은 것과 같은 함정)
-- ⚠️ 복귀를 '매 프레임 CFrame 고정' 으로 하면 안 된다. 그건 Anchored 와 같아져서
--   밀리는 맛이 사라진다. 벗어났을 때만 개입한다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SETTLE_TIME  = 12     -- 모래 밖에서 이 시간 이상 머물면 복귀
local CHECK_PERIOD = 0.25

-- ═══ 판정 영역 ═══
-- ⚠️ 반경(원)이 아니라 '모래 바닥 사각형' 을 경계로 쓴다.
--   [왜 바꿨나] 원으로 두면 야드는 사각인데 판정은 원이라 구석이 남고, 반경 하나로는
--     무기별 넉백(평타 7.6 · 스핀 22 · 돌진 28~50)을 다 담기 어려웠다.
--     LEASH 22 일 때 스핀(22.0)이 매번 걸려 "또 원복" 이 났던 게 그 증상이다.
--   [지금 규칙] 모래 위에 있으면 그대로 둔다. 밀려나도 모래 안이면 방치.
--     모래를 벗어나면 12초 뒤 복귀, 야드 자체를 벗어나면 즉시 복귀.
--   실측 (회전 반영, ori(0,180,90) 이라 Size 를 그대로 쓰면 안 된다):
--     모래 X 211.3~333.3 · Z 27.0~135.0
local SAND = { x0 = 215, x1 = 329, z0 = 31, z1 = 131 }   -- 여백 4 (울타리에 안 끼게)
-- ⚠️ HARD 는 '울타리(벽) 선' 까지 열어둔다.
--   [왜] 건틀렛에 WALL_SLAM_BONUS = 50 이 있다 — 벽에 처박으면 총 70~86 데미지.
--     경계를 벽 안쪽에 두면 벽에 닿기 전에 복귀돼서 그 보너스를 확인할 수 없다.
--   [기준] 울타리 부재 173개의 중심 범위 실측: X 211.8~335.4 · Z 24.9~136.1
--     거기까지 밀려도 그대로 두고, 벽을 '넘어' 나가면 그때 복귀시킨다.
--   ⚠️ 울타리가 물리적으로 막아주므로 실제로 넘어가는 일은 드물다.
--     넘어가더라도 FALL_Y(30) 낙하 안전망이 이중으로 잡는다.
local HARD = { x0 = 211, x1 = 336, z0 = 24, z1 = 137 }   -- 울타리 선 — 넘으면 즉시 복귀
local FALL_Y = 30                                         -- 이만큼 아래로 떨어지면 즉시 복귀

local function inSand(p)
	return p.X >= SAND.x0 and p.X <= SAND.x1 and p.Z >= SAND.z0 and p.Z <= SAND.z1
end
local function inYard(p)
	return p.X >= HARD.x0 and p.X <= HARD.x1 and p.Z >= HARD.z0 and p.Z <= HARD.z1
end

local homes = {}   -- [model] = {cf = CFrame, lastInside = os.clock()}

-- ⚠️ Physics 상태는 엔진이 자세를 안 잡아준다. 세게 맞으면 넘어져 눕는데,
--   리시(22) 안쪽이면 goHome 이 안 돌아서 누운 채 방치된다 — 다음 무기를 못 시험한다.
--   [해결] AlignOrientation 으로 '서 있는 자세' 만 유지한다.
--     위치는 안 잡으므로 밀리는 건 그대로다. 기울기만 되돌린다.
--   ⚠️ AlignPosition 을 쓰면 안 된다. 그건 위치까지 붙잡아서 Anchored 와 같아진다.
local function keepUpright(model)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if hrp:FindFirstChild("_UprightAtt") then return end   -- 멱등

	local att = Instance.new("Attachment")
	att.Name = "_UprightAtt"
	att.Parent = hrp

	local ao = Instance.new("AlignOrientation")
	ao.Name             = "_Upright"
	ao.Mode             = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0      = att
	ao.PrimaryAxisOnly  = false
	ao.RigidityEnabled  = false
	ao.MaxTorque        = 12000     -- 넘어지지 않을 만큼만. 너무 크면 밀림도 방해한다
	ao.Responsiveness   = 25
	-- 현재 바라보는 방향을 유지하되 수평만 맞춘다
	local lv = hrp.CFrame.LookVector
	local flat = Vector3.new(lv.X, 0, lv.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(-1, 0, 0) end
	ao.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
	ao.Parent = hrp
end

local function register(model)
	if homes[model] then return end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- ⚠️ 홈은 'HumanoidRootPart 기준' 으로 잡는다.
	--   [실측 버그] 처음엔 model:GetPivot() 을 홈으로 썼는데, 거리 판정은 HRP.Position 으로
	--     한다. 이 둘이 3.225 나 달라서(피벗이 발밑, HRP 는 허리) 등록 즉시 '이탈' 로 읽혔고
	--     아무도 안 때렸는데 2.5초마다 복귀가 돌았다.
	--   → 저장과 판정이 같은 기준을 써야 한다. 둘 다 HRP 로 통일한다.
	homes[model] = { cf = hrp.CFrame, lastInside = os.clock() }

	-- 물리를 켠다. 단 HumanoidRootPart 만이 아니라 전 파트를 풀어야 리그가 자연스럽게 밀린다.
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false end
	end

	-- 걷지는 않게 한다. 넉백에 밀리기만 하고 스스로 이동하지 않는다.
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.AutoRotate = false   -- 맞을 때마다 빙글빙글 돌지 않게

		-- ⚠️ [실측] WalkSpeed=0 만으로는 안 밀린다.
		--   Humanoid 가 Running 상태면 엔진이 매 프레임 발밑을 붙잡고 이동을 제어한다.
		--   WalkSpeed=0 은 "속도 0 으로 서 있어라" 라서, 밀려도 엔진이 즉시 원위치로 스냅한다.
		--   (걸어서 돌아가는 게 아니라 엔진이 되돌리는 것 — 그래서 복귀 로그도 안 찍혔다)
		--   → Physics 상태로 고정하면 엔진이 손을 떼고 순수 물리로만 움직인다.
		for _, s in ipairs({
			Enum.HumanoidStateType.Running,
			Enum.HumanoidStateType.RunningNoPhysics,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Jumping,
			Enum.HumanoidStateType.GettingUp,
			Enum.HumanoidStateType.FallingDown,
		}) do
			pcall(function() hum:SetStateEnabled(s, false) end)
		end
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end

	-- ⚠️ 네트워크 오너를 서버로 고정한다.
	--   기본은 자동이라 가까운 플레이어에게 넘어갈 수 있는데, 그러면 밀린 위치를
	--   서버가 다르게 판단해 되돌리는 싸움이 난다.
	local hrpOwn = model:FindFirstChild("HumanoidRootPart")
	if hrpOwn then
		pcall(function() hrpOwn:SetNetworkOwner(nil) end)
	end

	keepUpright(model)   -- 넘어져 눕지 않게 자세만 유지 (위치는 안 잡음)

	print(string.format("⚓ [DummyAnchor] 등록: %s  홈(%.1f, %.1f, %.1f) · 모래 X%d~%d Z%d~%d · %d초",
		model.Name, homes[model].cf.X, homes[model].cf.Y, homes[model].cf.Z,
		SAND.x0, SAND.x1, SAND.z0, SAND.z1, SETTLE_TIME))
end

local function goHome(model, reason)
	local h = homes[model]
	if not h then return end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- ⚠️ 속도를 먼저 0 으로. 안 그러면 복귀 직후 남은 관성으로 다시 날아간다.
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.AssemblyLinearVelocity  = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end
	-- ⚠️ PivotTo 가 아니라 HRP 를 직접 옮긴다.
	--   홈을 HRP.CFrame 으로 저장했으므로 복귀도 같은 기준이어야 한다.
	--   PivotTo 를 쓰면 피벗-HRP 오프셋만큼 매번 어긋나 무한 복귀가 된다.
	hrp.CFrame = h.cf
	h.lastInside = os.clock()

	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false   -- 래그돌로 누운 상태면 일으켜 세운다
		hum.Sit = false
		-- ⚠️ 복귀 후에도 Physics 를 유지한다. Running 으로 돌아가면
		--   엔진이 다시 발밑을 붙잡아 '안 밀리는' 상태가 된다.
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end
	print(string.format("⚓ [DummyAnchor] 복귀: %s (%s)", model.Name, reason))
end

task.spawn(function()
	while true do
		task.wait(CHECK_PERIOD)
		for model, h in pairs(homes) do
			if not model.Parent then
				homes[model] = nil
			else
				local hrp = model:FindFirstChild("HumanoidRootPart")
				if hrp then
					local p = hrp.Position

					if not inYard(p) then
						-- 야드 자체를 벗어남 — 시간 안 기다리고 즉시
						goHome(model, string.format("야드 이탈 (%.0f, %.0f)", p.X, p.Z))
					elseif not inSand(p) then
						-- 모래 밖. 12초 유지되면 정리한다.
						if os.clock() - h.lastInside > SETTLE_TIME then
							goHome(model, string.format("모래 밖 %.0f초 유지 (%.0f, %.0f)",
								SETTLE_TIME, p.X, p.Z))
						end
					else
						h.lastInside = os.clock()   -- 모래 위면 타이머 리셋
					end

					-- 낙하 안전망: 바닥을 뚫고 떨어지면 즉시 복귀
					if p.Y < h.cf.Y - FALL_Y then
						goHome(model, "낙하")
					end
				end
			end
		end
	end
end)

-- 등록 대상: LobbyDummy 표식이 있는 workspace 직속 모델
-- ⚠️ workspace:GetChildren() 직속만 본다 — ImmortalDummyController 와 같은 제약이다.
--   더미를 TrainingYard 안에 넣으면 둘 다 못 찾는다.
for _, m in ipairs(workspace:GetChildren()) do
	if m:IsA("Model") and m:GetAttribute("LobbyDummy") then register(m) end
end
workspace.ChildAdded:Connect(function(m)
	if m:IsA("Model") and m:GetAttribute("LobbyDummy") then
		task.wait(0.2)
		register(m)
	end
end)

print("✅ LobbyDummyAnchor 활성화 (밀림 허용 + 제자리 복귀)")
