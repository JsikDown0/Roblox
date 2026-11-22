-- ═══════════════════════════════════════════════════════════════
-- 🧊 BarrelSlipClient — 배럴 액체 지대 미끄러짐 (플레이어 전용)
--
-- [왜 클라이언트인가] 플레이어 캐릭터는 클라이언트가 물리 소유권을 가진다.
--   서버에서 AssemblyLinearVelocity 를 써도 클라가 매 프레임 덮어쓴다.
--   서버가 이기게 하려면 SetNetworkOwner(nil) 이 필요한데, 그러면 조작이
--   고무줄처럼 되어 "미끄럽다" 가 아니라 "렉 걸린다" 로 느껴진다.
--   → 이동 감각은 클라이언트에서 만드는 게 맞다.
--   (AI 러너는 서버 소유라 BarrelSpillSystem 이 서버에서 처리한다)
--
-- [실패 기록 2026-08-26] 처음엔 서버에서 마찰(CustomPhysicalProperties)을
--   0 에 가깝게 낮췄으나 체감이 거의 없었다. Humanoid 는 WalkSpeed 로 목표
--   속도를 직접 만들어내므로 지면 마찰을 이겨버린다.
--   → 속도를 '직전 속도' 쪽으로 끌어당겨 방향 전환 자체를 둔하게 만든다.
-- ═══════════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- ⚠️ 상수는 전부 공유 모듈에서 읽는다. 서버(BarrelSpillSystem)도 같은 모듈을
--   쓰므로 값이 어긋날 수 없다. 값 변경은 BarrelSpillConfig 에서만.
--   (여기에 복사해 두면 한쪽만 고쳤을 때 플레이어와 봇이 다른 규칙으로 미끄러진다)
local CFG = require(ReplicatedStorage:WaitForChild("BarrelSpillConfig"))

local RADIUS        = CFG.RADIUS
local HEIGHT_SLACK  = CFG.HEIGHT_SLACK
local SLIP_RESPONSE = CFG.SLIP_RESPONSE

-- 웅덩이 목록은 이름으로 추적한다. 서버가 workspace 직속으로 만든다.
local pools = {}
local function watch(inst)
	if inst.Name == "_BarrelSpill" then pools[inst] = true end
end
for _, d in ipairs(workspace:GetChildren()) do watch(d) end
workspace.ChildAdded:Connect(watch)
workspace.ChildRemoved:Connect(function(inst) pools[inst] = nil end)

local prevVel = nil   -- 직전 수평 속도

RunService.Heartbeat:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (hrp and hum and hum.Health > 0) then
		prevVel = nil
		return
	end

	-- ⚠️ 태거는 제외. 자기 아이템에 미끄러지면 결투 판정이 무너진다.
	if player:GetAttribute("Role") ~= "Runner" then
		prevVel = nil
		return
	end

	-- 다운·래그돌 상태면 어차피 못 움직인다. 속도를 건드리면 연출이 깨진다.
	-- ⚠️ PlatformStand 도 함께 본다 — 푸시툴 슬랩 래그돌이 이 상태를 쓴다.
	if char:GetAttribute("Downed") or hum.PlatformStand then
		prevVel = nil
		return
	end

	local inside = false
	for pool in pairs(pools) do
		if pool.Parent then
			local d = Vector3.new(hrp.Position.X - pool.Position.X, 0,
				hrp.Position.Z - pool.Position.Z).Magnitude
			if d <= RADIUS and math.abs(hrp.Position.Y - pool.Position.Y) < HEIGHT_SLACK then
				inside = true
				break
			end
		else
			pools[pool] = nil
		end
	end

	if not inside then
		prevVel = nil
		-- 🚫 [2026-08-27] 웅덩이 밖 → 대시 봉인 해제.
		--   "켜는 코드에는 끄는 코드를 같이" — 안 지우면 웅덩이를 벗어나도 Q 가 영영 안 나간다.
		if char:GetAttribute("InBarrelSpill") then
			char:SetAttribute("InBarrelSpill", nil)
			-- 🦘 안 되돌리면 웅덩이를 벗어나도 영영 못 뛴다. 속성 해제와 반드시 한 쌍.
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
		end
		return
	end

	-- 🚫 [2026-08-27] 웅덩이 안에서는 대시(Q) 봉인.
	--   [증상] 웅덩이가 디버프가 아니라 버프였다. Q 를 쓰면 오히려 더 빨랐다(실측 2026-08-27).
	--   [원인] 아래 관성 유지 로직은 '직전 속도를 붙잡는' 방식이다. 걷기(16~22)엔 방향 전환을
	--     둔하게 만드는 페널티지만, 대시(BURST_SPEED 80)에는 그 80 을 오래 유지시켜 준다.
	--     즉 느린 이동엔 벌, 빠른 이동엔 상 — 러너의 최적해가 "웅덩이 보면 Q" 가 됐다.
	--   [해결] 웅덩이 안에서는 대시를 못 쓰게 한다. RunnerDive.tryDash 가 이 속성을 본다.
	--   ⚠️ 속성은 캐릭터에 건다. RunnerDive 도 같은 캐릭터를 보므로 별도 통신이 필요 없다.
	--   ⚠️ 이미 대시 중인 상태로 웅덩이에 들어오는 건 막지 않는다(발동 시점 판정).
	--     밖에서 대시로 뛰어드는 건 "대시를 써서 장애물을 넘었다" 라 정당한 사용이다.
	--   🦘 [2026-08-31] 점프도 같이 봉인한다.
	--     [왜] 대시만 막으니 체감이 없었다. Q 는 쿨 6초라 웅덩이 통과(약 3초) 중에
	--       마침 쿨이 돌아 있어야만 봉인이 걸린다 — 절반은 원래 못 쓰던 걸 막은 셈이다.
	--       점프는 상시 자원이라 봉인이 항상 걸리고, 굴러오는 아이템을 뛰어넘는
	--       러너의 기본 회피 동작을 직접 끊는다.
	--     ⚠️ JumpPower/JumpHeight 대입은 절대 쓰지 않는다. 전 프로젝트에 36건이
	--       흩어져 있어(DownSystem 4 / KillEffectSystem 8 / PushTool Server 8 …)
	--       마지막에 쓴 쪽이 이기는 구조다. 여기서 숫자를 건드리면 다운·킬이펙트·넉백이
	--       서로 값을 덮어써 재현 안 되는 버그가 난다. 상태 토글은 그 싸움에 끼지 않는다.
	--     ⚠️ 더블점프는 이 상태를 안 탄다(UserInputService.JumpRequest 직결).
	--       DoubleJump.onJumpRequest 에 같은 속성 가드를 따로 넣어뒀다. 한쪽만 막으면
	--       공중에서 한 번 더 뛰어 그대로 빠져나간다.
	if not char:GetAttribute("InBarrelSpill") then
		char:SetAttribute("InBarrelSpill", true)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end
	end

	local cur = hrp.AssemblyLinearVelocity
	local curH = Vector3.new(cur.X, 0, cur.Z)
	if prevVel then
		-- 직전 속도 쪽으로 끌어당긴다 = 방향 전환이 둔해지고, 멈춰도 미끄러진다
		local blended = prevVel:Lerp(curH, SLIP_RESPONSE)
		-- ⚠️ Y 는 건드리지 않는다. 점프·낙하가 깨진다.
		hrp.AssemblyLinearVelocity = Vector3.new(blended.X, cur.Y, blended.Z)
		prevVel = blended
	else
		prevVel = curH
	end
end)

print("✅ BarrelSlipClient 준비 (액체 지대 미끄러짐 — 클라이언트)")
