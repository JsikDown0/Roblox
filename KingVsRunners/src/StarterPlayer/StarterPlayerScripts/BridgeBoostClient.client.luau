-- BridgeBoostClient — 로비 다리 무빙워크
--
-- ═══ 왜 이 방식인가 ═══
-- [원본을 안 쓴 이유] 툴박스 Speed Pad 의 스크립트는 이렇게 생겼다:
--     human.WalkSpeed = 40 ; wait(3.5) ; human.WalkSpeed = 16
--   이건 이 프로젝트에서 하루 종일 잡은 버그의 교과서적 형태다.
--     · 3.5초 뒤 '무조건' 16 으로 덮어쓴다 — 그 사이 다운(4)·해머스핀(8)이면 그걸 지운다
--     · Touched 는 밟고 있는 동안 연타된다 → wait 이 중첩되고 마지막 하나가 강제 복원
--     · 밟고 바로 라운드에 끌려가면 맵에서 속도 40 으로 시작한다
--   → 원본은 ServerStorage 로 치웠다. 참고용으로만 남긴다.
--
-- [핵심 원칙] '되돌릴 상태를 만들지 않는다.'
--   WalkSpeed 를 건드리지 않고, 매 프레임 "지금 패드 위인가" 를 다시 묻는다.
--   패드를 벗어나면 아무 일도 안 한다 — 복원 코드가 없으니 복원 실패도 없다.
--   라운드에 끌려가도 그 순간 패드 밖이므로 자동으로 끝난다.
--   ("제외 목록보다 결과 보장" 과 같은 형태)
--
-- [왜 클라인가] 캐릭터의 네트워크 오너가 클라이언트다. 서버에서 속도를 써도
--   다음 프레임에 클라가 덮어쓴다 — 오늘 방향 굳음 버그에서 실측으로 확인했다.
--
-- ⚠️ AssemblyLinearVelocity 에 '더하지' 않는다. 매 프레임 더하면 가속이 누적돼 튕겨나간다.
--   목표 속도에 부족한 만큼만 채운다(속도 상한이 저절로 생긴다).

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local BOOST_SPEED = 50     -- 패드 위 목표 이동 속도 (기본 16 의 약 3배)
-- ⚠️ [2026-09-08] 34 → 50 상향.
--   [왕복 시간은 거의 안 준다] 다리가 43.5 스터드뿐이라 34 로도 1.28초면 건넌다.
--     34 → 왕복 17.1초 / 50 → 16.3초 / 80 → 15.7초. 나머지는 다리 밖 구간이 먹는다.
--     올리는 이유는 시간이 아니라 '미끄러지는 체감' 이다.
--   ⚠️ 상한이 있다. 패드는 다리 끝(X 192.5)에서 끝나고 야드 입구는 X 209 — 여유 16.5.
--     55 이상이면 이탈 후 관성으로 그 여유를 넘어 야드까지 튕겨 들어간다.
--     50 이 실질 상한선이다. 더 올리려면 패드를 다리 끝에서 더 일찍 끊어야 한다.
local PAD_HEIGHT  = 6      -- 패드 윗면에서 이 높이 안에 있어야 인정 (점프 중엔 끊김)
local FOLDER_NAME = "BridgeBoost"

local pads = nil

local function collectPads()
	local folder = workspace:FindFirstChild(FOLDER_NAME)
	if not folder then return nil end
	local list = {}
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") and p:GetAttribute("BoostDir") then
			local half = p.Size / 2
			table.insert(list, {
				part = p,
				dir  = p:GetAttribute("BoostDir"),
				minX = p.Position.X - half.X, maxX = p.Position.X + half.X,
				minZ = p.Position.Z - half.Z, maxZ = p.Position.Z + half.Z,
				topY = p.Position.Y + half.Y,
			})
		end
	end
	return #list > 0 and list or nil
end

-- ⚠️ 라운드 중에는 돌지 않는다. 로비 전용 장치가 맵에서 살아 있을 이유가 없다.
local function isLobby()
	local phase = ReplicatedStorage:GetAttribute("RoundPhase")
	return phase == nil or phase == "intermission"
end

-- 🔴 [버그수정 2026-09-20] 단계 게이트를 제거한다.
--   [증상] 스튜디오에선 되는데 라이브에서 패드가 작동하지 않는다(라이브 제보).
--   [원인] 위 isLobby() 는 '내가 로비에 있나'가 아니라 '지금 인터미션인가'를 묻는다.
--     그런데 라이브에서 로비에 있는 사람은 **대부분 라운드 중**이다 —
--     죽어서 관전 중이거나, 라운드 도중에 접속해 다음 판을 기다리는 중이다.
--     그 상태에선 RoundPhase 가 stage1/stage2 라 이 함수가 통째로 조기 종료됐다.
--     스튜디오에선 보통 인터미션에 테스트하니 항상 통과해 증상이 안 보였다.
--   [왜 가드가 불필요한가] 주석이 걱정한 "밟고 라운드에 끌려가면 속도 40으로 시작"은
--     **옛 툴박스 스크립트** 얘기다. 이 구현은 WalkSpeed 를 안 건드리고 패드 위에 있는
--     프레임에만 속도를 채우므로, 끌려가는 순간 패드 밖이 되어 저절로 끝난다.
--     그게 이 파일 상단의 '되돌릴 상태를 만들지 않는다' 원칙이다.
--   [위치 판정이 곧 로비 판정이다] 패드는 Y≈302 이고 맵 언덕은 Y 1~138 이다.
--     좌표가 겹칠 수 없으므로 단계를 볼 이유가 없다.
--   ⚠️ 같은 뿌리의 버그가 같은 날 하나 더 있었다 — FirePressureSystem 이 '맵 위인가' 대신
--     X 좌표만 보고 로비를 태웠다. **로비 시스템은 상태(phase)가 아니라 위치로 판단할 것.**
--   🔴 [되돌리는 법] 아래 한 줄을 되살린다: if not isLobby() then return end
RunService.Heartbeat:Connect(function()

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return end

	pads = pads or collectPads()
	if not pads then return end

	local p = hrp.Position
	for _, pad in ipairs(pads) do
		if p.X >= pad.minX and p.X <= pad.maxX
		   and p.Z >= pad.minZ and p.Z <= pad.maxZ
		   and p.Y >= pad.topY - 1 and p.Y <= pad.topY + PAD_HEIGHT then

			-- 목표 속도에 '부족한 만큼만' 채운다. 더하기가 아니라서 누적되지 않는다.
			local v = hrp.AssemblyLinearVelocity
			local along = v.X * pad.dir              -- 진행 방향 성분
			if along < BOOST_SPEED then
				hrp.AssemblyLinearVelocity =
					Vector3.new(pad.dir * BOOST_SPEED, v.Y, v.Z)
			end
			return   -- 패드 하나만 적용
		end
	end
end)

-- 패드가 나중에 생기거나 바뀌면 목록을 다시 만든다
do
	local folder = workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		folder.ChildAdded:Connect(function() pads = nil end)
		folder.ChildRemoved:Connect(function() pads = nil end)
	else
		workspace.ChildAdded:Connect(function(c)
			if c.Name == FOLDER_NAME then pads = nil end
		end)
	end
end

print("🛼 BridgeBoostClient 활성화 (다리 무빙워크 — WalkSpeed 미사용)")
