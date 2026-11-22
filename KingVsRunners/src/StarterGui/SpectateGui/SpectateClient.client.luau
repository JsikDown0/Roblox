-- SpectateClient
-- 관전 시스템 클라이언트.
--   - 돋보기 버튼: 관전 모드 토글
--   - 관전 대상: 서버에서 받은 목록 (태거 먼저, 살아있는 러너들. 죽은 사람 제외, 다운 포함)
--   - 화살표: 대상 순회 (태거 → 러너들 → 다시 태거로 순환)
--   - 카메라: 대상 캐릭터의 3인칭 뒤쪽 시야
--   - 권한: 라운드에 살아서 참여 중이면 관전 불가 (서버가 판정)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local gui         = script.Parent
local spectateBtn = gui:WaitForChild("SpectateButton")
local overlay     = gui:WaitForChild("SpectateOverlay")
local topBar      = overlay:WaitForChild("TopBar")
local targetName  = topBar:WaitForChild("TargetName")
local roleLabel   = topBar:WaitForChild("RoleLabel")
local prevBtn     = overlay:WaitForChild("PrevButton")
local nextBtn     = overlay:WaitForChild("NextButton")
local exitBtn     = overlay:WaitForChild("ExitButton")

local getTargetsFn = ReplicatedStorage:WaitForChild("GetSpectateTargets")

-- ── 카메라 설정 ──────────────────────────────────────────────
local CAM_DISTANCE = 12    -- 대상 뒤쪽 거리 (studs)
local CAM_HEIGHT   = 4     -- 대상 위쪽 높이
local CAM_LERP     = 0.15  -- 카메라 추적 부드러움 (0~1, 클수록 빠름)

-- ── 상태 ─────────────────────────────────────────────────────
local spectating   = false
local targets      = {}    -- { {userId, name, isTagger}, ... }
local currentIndex = 1
-- ⚠️ [2026-08-30] BindToRenderStep 은 반환값이 없다(nil).
--   예전엔 그 결과를 renderConn 에 담아 해제 조건(if renderConn then)으로 썼는데,
--   항상 nil 이라 해제가 단 한 번도 실행되지 않았다. 렌더스텝이 영구히 물려 있었다.
--   콜백 첫 줄의 `if not spectating then return end` 가 막아줘서 증상이 안 보였을 뿐이다.
--   → 바인딩 여부는 불리언으로 따로 기록하고, 해제는 이름으로 한다.
local CAM_BIND     = "SpectateCam"
local camBound     = false

-- ── 대상 캐릭터 찾기 ─────────────────────────────────────────
local function getTargetCharacter(entry)
	if not entry then return nil end
	local char
	if entry.kind == "npc" then
		-- NPC: workspace 에서 모델 이름으로 찾기
		char = workspace:FindFirstChild(entry.model)
	else
		-- 플레이어: UserId 로 찾기
		local plr = Players:GetPlayerByUserId(entry.userId)
		if not plr then return nil end
		char = plr.Character
	end
	if not char then return nil end
	local hum = char:FindFirstChildWhichIsA("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	-- 카메라 기준 파트: R15 는 HumanoidRootPart, R6 더미는 Torso 등 다양함.
	-- 여러 후보를 순서대로 시도 (HumanoidRootPart → Humanoid.RootPart → Torso → UpperTorso).
	local rootPart = char:FindFirstChild("HumanoidRootPart")
		or hum.RootPart
		or char:FindFirstChild("Torso")
		or char:FindFirstChild("UpperTorso")
	if not rootPart then return nil end
	return char, rootPart
end

-- ── 상단 정보 갱신 ───────────────────────────────────────────
local function updateInfo()
	local entry = targets[currentIndex]
	if not entry then return end
	targetName.Text = entry.name
	if entry.isTagger then
		roleLabel.Text = "🔴 King"
		roleLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
	else
		roleLabel.Text = "🔵 Runner  (" .. currentIndex .. "/" .. #targets .. ")"
		roleLabel.TextColor3 = Color3.fromRGB(120, 180, 255)
	end
end

-- ── 카메라 추적 (매 프레임) ──────────────────────────────────
local function startCameraTracking()
	if camBound then RunService:UnbindFromRenderStep(CAM_BIND) end
	camBound = true
	RunService:BindToRenderStep(CAM_BIND, Enum.RenderPriority.Camera.Value + 1, function()
		if not spectating then return end
		-- ⚠️ 카메라는 매 프레임 새로 읽는다. 예전엔 바깥에서 한 번만 캡처했는데,
		--   관전 중 리스폰으로 CurrentCamera 가 교체되면 사라진 카메라에 계속 쓰게 된다.
		local camera = workspace.CurrentCamera
		if not camera then return end
		local entry = targets[currentIndex]
		local char, hrp = getTargetCharacter(entry)
		if not char then
			-- 현재 대상이 사라짐(사망/퇴장) → 다음 대상으로 자동 전환
			advanceToValid(1)
			return
		end
		camera.CameraType = Enum.CameraType.Scriptable
		-- 대상 뒤쪽 + 위쪽에서 바라보는 3인칭 시점
		local lookVector = hrp.CFrame.LookVector
		local targetPos  = hrp.Position
		local camPos = targetPos - lookVector * CAM_DISTANCE + Vector3.new(0, CAM_HEIGHT, 0)
		local goalCF = CFrame.lookAt(camPos, targetPos + Vector3.new(0, 2, 0))
		camera.CFrame = camera.CFrame:Lerp(goalCF, CAM_LERP)
	end)
end

-- ── 유효한 다음/이전 대상으로 이동 ───────────────────────────
-- dir = +1 (다음) 또는 -1 (이전). 죽어서 사라진 대상은 건너뜀.
function advanceToValid(dir)
	if #targets == 0 then stopSpectate(); return end
	local tried = 0
	repeat
		currentIndex = currentIndex + dir
		if currentIndex > #targets then currentIndex = 1 end
		if currentIndex < 1 then currentIndex = #targets end
		tried = tried + 1
		local char = getTargetCharacter(targets[currentIndex])
		if char then
			updateInfo()
			return
		end
	until tried >= #targets
	-- 유효한 대상이 하나도 없으면 목록 새로고침 시도
	refreshTargets(function(ok)
		if not ok or #targets == 0 then stopSpectate() end
	end)
end

-- ── 서버에서 대상 목록 새로고침 ──────────────────────────────
function refreshTargets(callback)
	local ok, result = pcall(function()
		return getTargetsFn:InvokeServer()
	end)
	if not ok or not result then
		if callback then callback(false) end
		return
	end
	if not result.allowed then
		if callback then callback(false, "notAllowed") end
		return
	end
	targets = result.targets or {}
	if callback then callback(true) end
end

-- ── 관전 시작 ────────────────────────────────────────────────
function startSpectate()
	refreshTargets(function(ok, reason)
		if not ok then
			if reason == "notAllowed" then
				-- 살아서 플레이 중 → 관전 불가 (조용히 무시하거나 안내)
				spectateBtn:SetAttribute("flash", true)
			end
			return
		end
		if #targets == 0 then return end  -- 관전할 대상 없음

		spectating = true
		localPlayer:SetAttribute("Spectating", true)  -- 음악: 관전 중 라운드 곡 재생용
		currentIndex = 1  -- 항상 첫 번째(태거)부터 시작
		overlay.Visible = true
		updateInfo()
		startCameraTracking()
	end)
end

-- ── 관전 종료 ────────────────────────────────────────────────
function stopSpectate()
	spectating = false
	localPlayer:SetAttribute("Spectating", false)  -- 음악: 관전 종료 → 로비 곡으로
	overlay.Visible = false
	if camBound then
		RunService:UnbindFromRenderStep(CAM_BIND)
		camBound = false
	end

	-- 카메라 원복 (본인 캐릭터로)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local char = localPlayer.Character
	local hum  = char and char:FindFirstChildWhichIsA("Humanoid")
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")

	-- ⚠️ 순서 주의: 대상을 먼저 본인으로 되돌린 뒤 Custom 으로 넘긴다.
	--   반대로 하면 Custom 이 켜지는 프레임에 subject 가 아직 관전 대상이라 화면이 한 번 튄다.
	if hum then camera.CameraSubject = hum end
	camera.CameraType = Enum.CameraType.Custom

	-- 🎥 [2026-08-30] 복귀 시점 초기화.
	--   [증상] 관전을 끄면 카메라가 엉뚱한 각도(대개 바닥을 내려다보는 자세)로 돌아왔다.
	--   [원인] 기본 카메라는 Custom 으로 재개될 때 '현재 카메라 CFrame'에서 각도를 역산한다.
	--     관전 카메라는 대상을 CAM_HEIGHT 만큼 위에서 내려다보고 있었으므로,
	--     그 아래를 향한 피치가 그대로 승계됐다. CameraType 만 되돌려선 안 고쳐진다.
	--   [해결] 캐릭터 뒤 수평 시점으로 CFrame 을 직접 세워 각도를 리셋한다.
	--   ⚠️ 캐릭터가 없으면(사망 중 관전 종료) 건너뛴다. 리스폰 때 카메라가 새로 잡힌다.
	if hrp then
		local look = hrp.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = (flat.Magnitude > 0.01) and flat.Unit or Vector3.new(0, 0, -1)
		local focus = hrp.Position + Vector3.new(0, 2, 0)
		camera.CFrame = CFrame.lookAt(focus - flat * 12, focus)
	end
end

-- ── 버튼 연결 ────────────────────────────────────────────────
spectateBtn.MouseButton1Click:Connect(function()
	if spectating then
		stopSpectate()
	else
		startSpectate()
	end
end)

nextBtn.MouseButton1Click:Connect(function()
	if spectating then advanceToValid(1) end
end)

prevBtn.MouseButton1Click:Connect(function()
	if spectating then advanceToValid(-1) end
end)

exitBtn.MouseButton1Click:Connect(function()
	stopSpectate()
end)

-- 본인이 리스폰하면 관전 강제 종료 (라운드 재참여 등)
localPlayer.CharacterAdded:Connect(function()
	if spectating then stopSpectate() end
end)

print("✅ SpectateClient 준비 완료")
