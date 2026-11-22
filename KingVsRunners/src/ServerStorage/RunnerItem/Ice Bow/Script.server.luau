-- Ice Bow 서버 로직
-- 러너 전용 반격 무기. Tagger에게 명중 시 1초간 아이템 사용 봉인 + 화면 효과.
-- 충전 2회, 소진 시 Tool destroy (ODM Gear 패턴).

local Tool = script.Parent
local Handle = Tool:WaitForChild("Handle")
local RM = Tool:WaitForChild("RemoteEvent")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TaggerFreezeEffect = ReplicatedStorage:WaitForChild("TaggerFreezeEffect")

-- 🏹 [SHOT-FEEDBACK] 사수에게 명중/빗나감을 알리는 채널.
-- ⚠️ Tool 안의 RM 을 쓰면 안 된다(2026-08-23 실측 오류):
--      "cannot fire 'RemoteEvent' ... the calling thread is sandboxed"
--    Tool 이 캐릭터 안에 들어가면 샌드박스 경계가 생겨 서버→클라 발화가 막힌다.
--    (클라→서버 OnServerEvent 는 되므로 RM 자체는 그대로 둔다)
--    → 바로 위 TaggerFreezeEffect 처럼 ReplicatedStorage 에 둔 채널을 쓴다.
local ShotResultRemote = ReplicatedStorage:FindFirstChild("IceBowShotResult")
if not ShotResultRemote then
	ShotResultRemote = Instance.new("RemoteEvent")
	ShotResultRemote.Name = "IceBowShotResult"
	ShotResultRemote.Parent = ReplicatedStorage
end

-- ─── 설정 ──────────────────────────────────────────────────
local MAX_CHARGES = 2
local ARROW_SPEED = 350           -- stud/sec
local ARROW_RANGE = 1800           -- 최대 사거리 (만렙 차지)
local ARROW_RANGE_MIN = 450       -- 최소 사거리 (15% 차지 시점)
local FREEZE_DURATION = 3         -- Tagger 봉인 시간 (초) — 화면 효과 + Tool 봉인 둘 다
local FIRE_COOLDOWN = 0.5         -- 발사 간 최소 간격

Tool:SetAttribute("Charges", MAX_CHARGES)
Tool:SetAttribute("MaxCharges", MAX_CHARGES)

-- ─── 헬퍼 함수 ─────────────────────────────────────────────
local function isTaggerCharacter(character)
	if not character then return false end
	-- NPC 태거 (Noob 이름 또는 태거 속성)
	if character.Name == "Noob" then return true end
	if character:GetAttribute("Role") == "Tagger" then return true end
	if character:GetAttribute("IsTaggerNoob") == true then return true end
	-- 플레이어 태거
	local player = Players:GetPlayerFromCharacter(character)
	return player and player:GetAttribute("Role") == "Tagger"
end

local function findOwnerPlayer()
	local parent = Tool.Parent
	if not parent then return nil end
	if parent:IsA("Backpack") then return parent.Parent end
	if parent:FindFirstChildOfClass("Humanoid") then
		return Players:GetPlayerFromCharacter(parent)
	end
	return nil
end

-- ─── Tool destroy: 충전 0 도달 시 grapple과 동일 패턴으로 정리 ─
-- ⚠️ [FREEZE-OUTLIVES-TOOL] 이 Script 의 Parent 는 Tool 자신이다.
--   Tool:Destroy() 가 돌면 이 스크립트의 스레드도 함께 종료되므로,
--   아래 freezeTaggerTools 가 걸어둔 task.delay(FREEZE_DURATION, 해제) 가
--   파괴 시점에 아직 대기 중이면 영영 실행되지 않는다.
--   → 태거의 Frozen 이 풀리지 않아 봇이 라운드 내내 무력화됐다
--     (실측 2026-08-20: 09:38:34 Tool 파괴 후 69초간 소환·이동·2단계 전무).
--   Frozen 을 지우는 곳은 이 파일과 TestCommands 뿐이고 라운드 경계 정리도 없다.
--   대책: 대기 중인 해제가 있으면 그 시각까지 파괴를 미룬다.
local destroyScheduled = false
local freezeReleaseAt = 0   -- 가장 늦은 해제 예정 시각 (tick 기준, 0 = 없음)
local function scheduleToolDestroy()
	if destroyScheduled then return end
	destroyScheduled = true
	-- ⚠️ 대기 시간을 여기서 한 번만 계산하면 안 된다.
	--   이 함수는 '발사'(Charges 0) 시점에 불리는데 동결은 '명중' 시점에 걸리므로,
	--   예약 당시엔 freezeReleaseAt 이 아직 0 이다. 깨어난 뒤 다시 확인한다.
	task.delay(0.3, function()
		while tick() < freezeReleaseAt do
			task.wait(0.2)
		end
		if Tool and Tool.Parent then
			print("🏹 Ice Bow destroy (charges depleted)")
			Tool:Destroy()
		end
	end)
end

Tool:GetAttributeChangedSignal("Charges"):Connect(function()
	if (Tool:GetAttribute("Charges") or 0) <= 0 then
		scheduleToolDestroy()
	end
end)

-- ─── Tagger 봉인: Tool 비활성화 + Frozen Attribute + 슬로우 ──────────────────
local SLOW_WALKSPEED = 12   -- 16 → 12 (-25%, 약한 슬로우)

local function freezeTaggerTools(taggerCharacter, taggerPlayer)
	-- 🛡️ [2026-09-02] CC 면역 중이면 동결하지 않는다(TaggerCcGuard).
	--   ⚠️ 여기서 막아야 한다. Frozen 속성만 걸러도 Tool 봉인·슬로우는 그대로 실행된다.
	if _G.IsCcImmune and _G.IsCcImmune(taggerCharacter) then return end
	-- Player Attribute로 태거 아이템 시스템 차단 (ItemSpawnHandler, ItemPreviewHandler가 체크)
	if taggerPlayer then
		taggerPlayer:SetAttribute("Frozen", true)
	end
	-- ❄️ 봇 태거(KING)는 Player 가 없어 위 경로를 못 탄다.
	--    캐릭터 속성으로 걸어두면 TaggerBotSystem 의 AI 루프가 이를 보고 행동을 멈춘다.
	--    (1단계 투척 / 2단계 결투 모두 정지)
	taggerCharacter:SetAttribute("Frozen", true)

	-- WalkSpeed 슬로우 (원래값 저장 후 적용)
	local humanoid = taggerCharacter:FindFirstChildOfClass("Humanoid")
	local oldWalkSpeed = nil
	if humanoid then
		oldWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = SLOW_WALKSPEED
	end

	-- 캐릭터에 장착된 Tool들
	local equipped = taggerCharacter:FindFirstChildOfClass("Tool")
	if equipped then
		equipped.Enabled = false
	end
	-- 백팩의 Tool들도 같이 봉인 (장착 전환해도 못 쓰게)
	local backpack = taggerPlayer and taggerPlayer:FindFirstChild("Backpack")
	local frozen = {}
	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") and tool.Enabled then
				tool.Enabled = false
				table.insert(frozen, tool)
			end
		end
	end
	if equipped then table.insert(frozen, equipped) end
	-- 봇 태거: Backpack 이 없고 Tool(PushTool)을 캐릭터 직속으로 들고 있다.
	-- FindFirstChildOfClass 는 하나만 잡으므로 나머지도 전수 봉인.
	for _, tool in ipairs(taggerCharacter:GetChildren()) do
		if tool:IsA("Tool") and tool.Enabled and tool ~= equipped then
			tool.Enabled = false
			table.insert(frozen, tool)
		end
	end

	-- duration 후 복구
	-- [FREEZE-OUTLIVES-TOOL] 해제 예정 시각을 남겨 scheduleToolDestroy 가 이보다
	--   먼저 Tool 을 파괴하지 않도록 한다(파괴되면 아래 스레드가 죽어 해제가 유실됨).
	freezeReleaseAt = math.max(freezeReleaseAt, tick() + FREEZE_DURATION)
	task.delay(FREEZE_DURATION, function()
		if taggerPlayer then
			taggerPlayer:SetAttribute("Frozen", nil)
		end
		if taggerCharacter and taggerCharacter.Parent then
			taggerCharacter:SetAttribute("Frozen", nil)   -- 봇 태거 행동 재개
		end
		-- WalkSpeed 복구 (캐릭터가 아직 살아있고 Humanoid 유효한 경우만)
		if humanoid and humanoid.Parent and oldWalkSpeed then
			humanoid.WalkSpeed = oldWalkSpeed
		end
		for _, tool in ipairs(frozen) do
			if tool and tool.Parent then
				tool.Enabled = true
			end
		end
	end)
end

-- ─── 화살 발사 ─────────────────────────────────────────────
local lastFireTime = 0

local function fireArrow(player, mouseHitPos, power)
	-- power: 0~1 차지 정도 (클라이언트 입력, 서버에서도 클램프)
	power = math.clamp(tonumber(power) or 1, 0, 1)

	-- 쿨다운
	local now = tick()
	if now - lastFireTime < FIRE_COOLDOWN then return end

	-- 충전 검사
	local charges = Tool:GetAttribute("Charges") or 0
	if charges <= 0 then return end

	-- 플레이어/캐릭터 검증
	local character = Tool.Parent
	if not character or not character:FindFirstChildOfClass("Humanoid") then return end
	local owner = Players:GetPlayerFromCharacter(character)
	if owner ~= player then return end  -- 소유자만 발사 가능

	-- 발사 위치/방향
	local startPos = Handle.Position
	local direction = (mouseHitPos - startPos)

	-- power 비례 사거리 계산
	local maxRange = ARROW_RANGE_MIN + (ARROW_RANGE - ARROW_RANGE_MIN) * power
	-- Penetrating sniper: range is set by CHARGE (maxRange), NOT by cursor distance.
	-- Cursor only provides the aim direction; arrow flies/detects up to maxRange
	-- along that direction even if the cursor ray hit near geometry (stairs/wall).
	local distance = maxRange
	direction = direction.Unit

	lastFireTime = now
	Tool:SetAttribute("Charges", charges - 1)
	-- [CONSUMABLE-ONUSE] 발사 확정 지점(쿨다운·잔탄 가드 통과 후).
	--   2발 중 1발만 써도 '사용'이다. MarkConsumableUsed 는 라운드당 1회만 유효하므로
	--   두 발 다 쏴도 인벤에서는 1개만 빠진다.
	if _G.MarkConsumableUsed then _G.MarkConsumableUsed(player, "Ice Bow") end

	-- 발사 사운드 (만렙 차지면 더 강하게)
	local fireSound = Handle:FindFirstChild("Fire")
	if fireSound then
		local sfx = fireSound:Clone()
		sfx.Parent = Handle
		sfx.PlaybackSpeed = 0.85 + power * 0.4  -- power 낮으면 둔탁, 높으면 날카로움
		sfx:Play()
		game:GetService("Debris"):AddItem(sfx, 2)
	end

	-- 저격 봉인기 판정: 벽/계단/아이템 완전 관통, 태거만 대상, 관대한 히트박스
	-- 조준 방향(direction)에서 각 태거까지의 "수직 거리"가 HIT_RADIUS 이내면 명중
	local HIT_RADIUS = 12          -- 조준선에서 이 반경 내 태거면 명중 (관대)
	local hitPos, hitPart
	local bestParam = math.huge     -- 가장 가까운(먼저 맞는) 태거 선택

	local function testTargetChar(ch)
		local hrp = ch:FindFirstChild("HumanoidRootPart")
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum and hum.Health > 0) then
			return
		end
		local toTarget = hrp.Position - startPos
		local along = toTarget:Dot(direction)       -- 조준 방향 투영 거리
		local closest = startPos + direction * math.max(along, 0)
		local perp = (hrp.Position - closest).Magnitude
		if along > 0 and along <= distance then
			if perp <= HIT_RADIUS and along < bestParam then
				bestParam = along
				hitPart = hrp
				hitPos = hrp.Position
			end
		end
	end

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= owner and other.Character and isTaggerCharacter(other.Character) then
			testTargetChar(other.Character)
		end
	end
	-- NPC 태거(Noob)도 대상
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model:FindFirstChild("HumanoidRootPart") and isTaggerCharacter(model) then
			testTargetChar(model)
		end
	end

	-- 명중한 태거 없으면 화살은 최대 사거리까지 날아가 사라짐
	if not hitPos then
		hitPos = startPos + direction * distance
	end

	-- 화살 인스턴스 (Model: 외곽 얼음 + 내부 화살)
	-- 컨셉: 반투명 얼음 큐브가 진짜 화살을 감싸고 비행
	local arrowModel = Instance.new("Model")
	arrowModel.Name = "IceArrow"

	-- 1) 외곽 얼음 큐브 (반투명, 안의 화살이 비침)
	local iceShell = Instance.new("Part")
	iceShell.Name = "IceShell"
	iceShell.Size = Vector3.new(0.9, 0.9, 6)
	iceShell.Material = Enum.Material.Glass
	iceShell.Color = Color3.fromRGB(180, 230, 255)
	iceShell.Transparency = 0.5   -- 0.15 → 0.5: 더 투명, 안 화살이 잘 보이도록
	iceShell.Reflectance = 0.3
	iceShell.CanCollide = false
	iceShell.Anchored = true
	iceShell.Parent = arrowModel

	-- 2) 내부 화살대 (나무, 갈색)
	local shaft = Instance.new("Part")
	shaft.Name = "ArrowShaft"
	shaft.Size = Vector3.new(0.15, 0.15, 4.5)
	shaft.Material = Enum.Material.Wood
	shaft.Color = Color3.fromRGB(110, 75, 50)
	shaft.CanCollide = false
	shaft.Anchored = true
	shaft.Parent = arrowModel

	-- 3) 화살촉 (앞쪽, 금속)
	local tip = Instance.new("Part")
	tip.Name = "ArrowTip"
	tip.Size = Vector3.new(0.3, 0.3, 0.6)
	tip.Material = Enum.Material.Metal
	tip.Color = Color3.fromRGB(200, 200, 210)
	tip.Reflectance = 0.25
	tip.CanCollide = false
	tip.Anchored = true
	tip.Parent = arrowModel

	-- 4) 깃털 (뒤쪽 양옆, 흰색 두 개)
	local fletchL = Instance.new("Part")
	fletchL.Name = "FletchingL"
	fletchL.Size = Vector3.new(0.05, 0.5, 0.7)
	fletchL.Material = Enum.Material.SmoothPlastic
	fletchL.Color = Color3.fromRGB(225, 230, 240)
	fletchL.CanCollide = false
	fletchL.Anchored = true
	fletchL.Parent = arrowModel

	local fletchR = Instance.new("Part")
	fletchR.Name = "FletchingR"
	fletchR.Size = Vector3.new(0.05, 0.5, 0.7)
	fletchR.Material = Enum.Material.SmoothPlastic
	fletchR.Color = Color3.fromRGB(225, 230, 240)
	fletchR.CanCollide = false
	fletchR.Anchored = true
	fletchR.Parent = arrowModel

	-- PrimaryPart 설정 (PivotTo 기준 — 이게 있어야 Model 단위 이동 가능)
	arrowModel.PrimaryPart = iceShell

	-- 초기 상대 위치 (원점 기준, -Z가 화살 forward 방향)
	-- iceShell 중심 (0,0,0), 길이 6 → 앞 끝 z=-3, 뒤 끝 z=+3
	iceShell.CFrame = CFrame.new()
	shaft.CFrame   = CFrame.new()                       -- iceShell과 동일 중심
	tip.CFrame     = CFrame.new(0, 0, -2.55)            -- shaft 앞쪽 끝 위치
	fletchL.CFrame = CFrame.new(0.18, 0, 1.95)          -- shaft 뒤쪽 왼쪽
	fletchR.CFrame = CFrame.new(-0.18, 0, 1.95)         -- shaft 뒤쪽 오른쪽

	-- 외곽 빛 (iceShell에 부착)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(140, 220, 255)
	light.Brightness = 2
	light.Range = 8
	light.Parent = iceShell

	-- 1) 눈송이 — 흰색 작은 입자, 사방으로 흩어짐
	local snow = Instance.new("ParticleEmitter")
	snow.Name = "Snowflakes"
	snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	snow.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	snow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	snow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	snow.Lifetime = NumberRange.new(0.6, 1.2)
	snow.Rate = 40
	snow.Speed = NumberRange.new(1, 3)
	snow.SpreadAngle = Vector2.new(180, 180)
	snow.Acceleration = Vector3.new(0, -2, 0)
	snow.LightEmission = 0.4
	snow.Rotation = NumberRange.new(0, 360)
	snow.RotSpeed = NumberRange.new(-60, 60)
	snow.Parent = iceShell

	-- 2) 얼음 글로우 — 푸른빛, 화살 본체에 밀착
	local glow = Instance.new("ParticleEmitter")
	glow.Name = "IceGlow"
	glow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glow.Color = ColorSequence.new(Color3.fromRGB(140, 220, 255))
	glow.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	glow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	glow.Lifetime = NumberRange.new(0.3, 0.5)
	glow.Rate = 80
	glow.Speed = NumberRange.new(0, 0.5)
	glow.SpreadAngle = Vector2.new(360, 360)
	glow.LightEmission = 1
	glow.Parent = iceShell

	-- 3) 비행 트레일 — 화살 뒤로 짧은 자국
	local trail = Instance.new("ParticleEmitter")
	trail.Name = "IceTrail"
	trail.Texture = "rbxasset://textures/particles/smoke_main.dds"
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 240, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 200, 240)),
	})
	trail.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = NumberRange.new(0.15, 0.25)
	trail.Rate = 120
	trail.Speed = NumberRange.new(0, 0)
	trail.LightEmission = 0.6
	trail.Parent = iceShell

	arrowModel.Parent = workspace
	Debris:AddItem(arrowModel, 3)

	-- 비행 애니메이션 (Model 전체를 PivotTo로 한 번에 이동)
	local travelTime = (hitPos - startPos).Magnitude / ARROW_SPEED
	travelTime = math.clamp(travelTime, 0.05, 0.6)
	local startTime = tick()
	-- 첫 위치 (시작 지점, 목표 방향)
	arrowModel:PivotTo(CFrame.new(startPos, hitPos))
	local conn
	conn = game:GetService("RunService").Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / travelTime, 1)
		if arrowModel.Parent then
			arrowModel:PivotTo(CFrame.new(startPos:Lerp(hitPos, alpha), hitPos))
		end
		if alpha >= 1 then
			conn:Disconnect()
			-- 도달 시 처리
			if not arrowModel.Parent then return end

			-- 박힘 효과 (최종 위치 고정)
			arrowModel:PivotTo(CFrame.new(hitPos, hitPos + direction))

			-- 🏹 이번 발사의 명중 여부. ⚠️ 반드시 local — 없으면 전역이 되어
			--    이전 발사 결과가 다음 발사에 새고, 화살이 동시에 여러 발 날면 서로 덮어쓴다.
			local hitResult = false

			-- 명중 판정: Tagger인가?
			if hitPart then
				local character = hitPart.Parent
				if character and character:IsA("Accessory") then
					character = character.Parent
				end
				if character and isTaggerCharacter(character) then
					-- Tagger 명중!
					-- 🛡️ [2026-09-02] CC 면역이면 '막혔다'는 연출로 갈라진다.
					--   [왜] 면역 중에도 얼음 오라·냉기 파편이 그대로 나가서, 붉은 면역
					--     보호막과 색이 겹쳐 상태를 못 읽었다. 게다가 화면엔 "HIT!" 가 떠
					--     러너는 걸린 줄 안다 — 실제로는 아무 효과가 없는데도.
					--   [해결] 여기서 한 번에 갈라 얼음 연출을 통째로 건너뛴다.
					--     화살이 맞은 건 사실이므로 사운드는 남기되, 문구로 결과를 알린다.
					local ccBlocked = (_G.IsCcImmune and _G.IsCcImmune(character)) or false

					-- 명중 사운드 (얼음 깨지는 효과)
					local hitSfx = Instance.new("Sound")
					hitSfx.SoundId = "rbxassetid://9113163332"
					hitSfx.Volume = ccBlocked and 0.7 or 1.5   -- 막혔으면 둔탁하게
					hitSfx.RollOffMaxDistance = 80
					hitSfx.RollOffMinDistance = 10
					hitSfx.Parent = iceShell
					hitSfx:Play()
					Debris:AddItem(hitSfx, 4)

					-- 1) Tagger 아이템 봉인 (면역이면 내부에서 return 한다)
					local taggerPlayer = Players:GetPlayerFromCharacter(character)
					freezeTaggerTools(character, taggerPlayer)

					-- 1-b) 명중 시각화: 태거를 감싸는 얼음 오라 + 냉기 파편.
					--      기존엔 사운드만 있어 "맞았는지" 판단이 어려웠다(특히 봇 상대).
					--      서버에서 캐릭터에 직접 붙여 모든 클라이언트에 복제되게 한다.
					--   ⚠️ 면역이면 만들지 않는다. 얼지 않았는데 얼음이 씌워지면 거짓 정보다.
					task.spawn(function()
						if ccBlocked then return end
						local hrpT = character:FindFirstChild("HumanoidRootPart")
						if not hrpT then return end

						local aura = Instance.new("Part")
						aura.Name = "IceFreezeAura"
						aura.Shape = Enum.PartType.Ball
						aura.Size = Vector3.new(7, 7, 7)
						aura.Material = Enum.Material.Glass
						aura.Color = Color3.fromRGB(150, 220, 255)
						aura.Transparency = 0.55
						aura.Reflectance = 0.35
						aura.CanCollide = false
						aura.Massless = true
						aura.CastShadow = false
						aura.CFrame = hrpT.CFrame
						aura.Parent = character

						local weld = Instance.new("WeldConstraint")
						weld.Part0 = hrpT
						weld.Part1 = aura
						weld.Parent = aura

						local pe = Instance.new("ParticleEmitter")
						pe.Color = ColorSequence.new(Color3.fromRGB(190, 240, 255))
						pe.Size = NumberSequence.new(1.2)
						pe.Lifetime = NumberRange.new(0.5, 1.0)
						pe.Speed = NumberRange.new(8, 16)
						pe.SpreadAngle = Vector2.new(180, 180)
						pe.Rate = 12
						pe.LightEmission = 0.4
						pe.Parent = aura
						pe:Emit(60)

						local light = Instance.new("PointLight")
						light.Color = Color3.fromRGB(150, 220, 255)
						light.Brightness = 2
						light.Range = 14
						light.Parent = aura

						task.delay(FREEZE_DURATION - 0.4, function()
							if not aura.Parent then return end
							pe.Rate = 0
							pe:Emit(30)
							local TS = game:GetService("TweenService")
							TS:Create(aura, TweenInfo.new(0.4), {Transparency = 1, Size = aura.Size * 1.4}):Play()
							TS:Create(light, TweenInfo.new(0.4), {Brightness = 0}):Play()
						end)
						Debris:AddItem(aura, FREEZE_DURATION + 1)
					end)

					-- 2) Tagger 클라이언트로 화면 효과 신호
					--   ⚠️ 면역이면 얼지 않았으므로 화면 효과도 보내지 않는다.
					if taggerPlayer and not ccBlocked then
						TaggerFreezeEffect:FireClient(taggerPlayer, FREEZE_DURATION)
					end

					-- 🛡️ 결과를 세 갈래로 알린다: 명중 / 면역으로 막힘 / 빗나감.
					hitResult = ccBlocked and "immune" or true
				end
			end

			-- 🏹 [SHOT-FEEDBACK] 사수에게 결과를 알린다.
			--   [이유] 아이스 보우는 원거리 무기인데, 멀리서 쏘면 명중 여부를 알 방법이 없었다.
			--          명중 사운드는 화살이 박힌 '그 자리'에서 나므로 거리가 멀면 안 들리고,
			--          얼음 오라도 태거 주변에만 생겨 사수 화면에서는 확인이 어렵다.
			--   ⚠️ 여기는 도달 처리(alpha>=1)의 공통 종료 지점이라 명중/빗나감 양쪽 다 지난다.
			--      명중 분기 안에서만 보내면 빗나감을 영영 알릴 수 없다.
			if owner then
				ShotResultRemote:FireClient(owner, hitResult)
			end
		end
	end)
end

RM.OnServerEvent:Connect(function(player, mouseHitPos, power)
	if typeof(mouseHitPos) ~= "Vector3" then return end
	fireArrow(player, mouseHitPos, power)
end)

print("✅ Ice Bow Server ready (2 charges, tagger-freeze on hit)")
