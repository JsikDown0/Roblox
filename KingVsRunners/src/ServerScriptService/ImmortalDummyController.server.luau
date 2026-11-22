-- ImmortalDummyController
-- 데미지 테스트용 불사신 더미.
-- workspace의 ImmortalDummy 속성을 가진 모델을 감시한다.
-- 다운(Downed 속성 true) 상태가 되면 RECOVER_DELAY 초 뒤 자동 회복:
--   DownSystem.clearDown 으로 다운 해제 + 체력/물리 상태 풀 복구.
-- 다운을 거치지 않고 즉사하는 경로(킬이펙트 등)도 Humanoid.Died로 잡아 복구.
-- 테스트 전용. 정식 빌드 전 제거할 것.

local Players = game:GetService("Players")
local DownSystem = require(game.ServerScriptService:WaitForChild("DownSystem"))

local RECOVER_DELAY = 2  -- 다운/사망 후 회복까지 대기(초)

local watched = {}  -- [model] = true (중복 연결 방지)
local recovering = {}  -- [model] = true (회복 처리 진행 중)

local function fullRestore(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	-- 다운 상태면 먼저 정식 해제 (물리/충돌/자세 복구 포함)
	if DownSystem.isDowned(model) then
		DownSystem.clearDown(model)
	end
	-- 혹시 PlatformStand/속도가 남아 있으면 정리
	hum.PlatformStand = false
	hum.Sit = false
	-- 체력 복구. Health=0 으로 죽어 있었다면 ChangeState로 되살림
	if hum.Health <= 0 then
		hum.Health = hum.MaxHealth
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
	else
		hum.Health = hum.MaxHealth
	end
	hum.WalkSpeed = 16
	hum.JumpPower = 50
	recovering[model] = nil
	print("♻️ [ImmortalDummy] 회복:", model.Name)
end

local function scheduleRecover(model)
	if recovering[model] then return end
	recovering[model] = true
	print("⏳ [ImmortalDummy] 다운 감지 →", RECOVER_DELAY, "초 후 회복:", model.Name)
	task.delay(RECOVER_DELAY, function()
		if model and model.Parent then
			fullRestore(model)
		else
			recovering[model] = nil
		end
	end)
end

local function watch(model)
	if watched[model] then return end
	watched[model] = true

	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- 1) 다운 진입 감지 (Downed 속성 nil → true)
	model:GetAttributeChangedSignal("Downed"):Connect(function()
		if model:GetAttribute("Downed") then
			scheduleRecover(model)
		end
	end)

	-- 2) 다운 없이 즉사하는 경로 안전망
	hum.Died:Connect(function()
		scheduleRecover(model)
	end)

	-- 3) ⚠️ [2026-09-08] 로비 훈련 더미는 '죽기 전에' 되살린다.
	--   [왜] DownSystem.triggerDown 이 LobbyDummy 를 거르면서 다운 경로가 끊겼다.
	--     그러면 Died 만 남는데, 죽는 순간 킬 이펙트·시체 연출이 한 번은 돈다.
	--     훈련장에서 매번 그게 나오면 산만하고, 실측상 회복 직후 다시 죽는
	--     루프에 갇히기도 했다(12:08:16~24, 2초 간격 "데미지 500" 반복).
	--   [해결] HP 가 문턱 아래로 내려가면 즉시 만피로 되돌린다. 죽지 않으니
	--     Died 도, 시체 연출도, 루프도 없다.
	--   ⚠️ HP 가 줄어드는 것 자체는 그대로 둔다 — 데미지 확인이 훈련의 목적이다.
	--     되돌리는 건 '0 에 닿기 직전' 뿐이다.
	if model:GetAttribute("LobbyDummy") then
		hum.HealthChanged:Connect(function(h)
			if h > 0 and h <= hum.MaxHealth * 0.05 then
				hum.Health = hum.MaxHealth
				print(string.format("♻️ [ImmortalDummy] %s 만피 복구 (HP %.0f 도달)", model.Name, h))
			end
		end)
	end

	print("👁️ [ImmortalDummy] 감시 시작:", model.Name)
end

-- 현재 존재하는 불사신 더미 등록
for _, m in ipairs(workspace:GetChildren()) do
	if m:IsA("Model") and m:GetAttribute("ImmortalDummy") then
		watch(m)
	end
end

-- 이후 추가되는 것도 등록 (복제/재생성 대응)
workspace.ChildAdded:Connect(function(m)
	if m:IsA("Model") and m:GetAttribute("ImmortalDummy") then
		task.wait(0.1)  -- 자식 로드 대기
		watch(m)
	end
end)

print("✅ ImmortalDummyController 활성화 (회복 지연:", RECOVER_DELAY, "초)")
