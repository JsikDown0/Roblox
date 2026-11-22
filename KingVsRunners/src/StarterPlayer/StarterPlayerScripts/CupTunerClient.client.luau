-- CupTunerClient: 손에 든 컵(Speed Potion 스킨) 회전을 실시간 튜닝.
-- 사용법: 컵 스킨 장착 후(/potionskin Cup) T 키로 튜너 ON/OFF.
--   ON 상태에서: I/K = X축 ±, J/L = Y축 ±, U/O = Z축 ±  (Shift = 5도씩, 기본 15도)
--   B = [TUNE-OUT] 현재 회전값 출력  |  N = 0으로 리셋
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local plr = Players.LocalPlayer
-- 🔒 [출시] dev/스튜디오 전용 게이트 (플레이어 실수 방지, 되돌리기=이 줄 삭제)
if not game:GetService("RunService"):IsStudio() and plr.UserId ~= 9228200642 then return end

local tuning = false
local STEP = math.rad(15)
local SMALL = math.rad(5)

-- 손에 든 컵 CupBody 파트 찾기 (캐릭터 안, IsBody 속성)
local function findCup()
	local char = plr.Character
	if not char then return nil end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("IsBody") and d.Name == "CupBody" then
			return d
		end
	end
	return nil
end

-- 컵을 Handle 기준 상대 회전시키기 (weld 유지된 채 회전 오프셋 적용)
-- weld는 상대위치 고정이므로, weld 재생성 없이 회전하려면 파트 CFrame을 직접 돌리고
-- WeldConstraint를 재적용해야 함. 간단히: 기존 weld 제거 → 회전 → 새 weld.
local function rotateCup(cup, axisCF)
	local handle = nil
	-- weld 찾아서 Part0(handle) 확보
	for _, c in ipairs(cup:GetChildren()) do
		if c:IsA("WeldConstraint") and c.Part0 then handle = c.Part0; c:Destroy() end
	end
	if not handle then
		-- 이미 weld 없으면 부모 툴 Handle 추정
		handle = cup.Parent and cup.Parent:FindFirstChild("Handle")
	end
	-- 현재 handle 기준 상대 CFrame에 축 회전 곱하기
	local rel = handle.CFrame:ToObjectSpace(cup.CFrame)
	rel = rel * axisCF
	cup.CFrame = handle.CFrame * rel
	-- weld 재생성
	local wc = Instance.new("WeldConstraint")
	wc.Part0 = handle
	wc.Part1 = cup
	wc.Parent = cup
end

local function printTune(cup)
	local handle
	for _, c in ipairs(cup:GetChildren()) do
		if c:IsA("WeldConstraint") and c.Part0 then handle = c.Part0 end
	end
	if not handle then print("[Cup] handle 못 찾음"); return end
	local rel = handle.CFrame:ToObjectSpace(cup.CFrame)
	local rx, ry, rz = rel:ToOrientation()
	print(string.format("[TUNE-OUT] Cup | rot=(%.1f, %.1f, %.1f) deg  → CupBody.CFrame = CFrame.Angles(math.rad(%.1f), math.rad(%.1f), math.rad(%.1f))",
		math.deg(rx), math.deg(ry), math.deg(rz), math.deg(rx), math.deg(ry), math.deg(rz)))
end

UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	local key = input.KeyCode
	if key == Enum.KeyCode.T then
		tuning = not tuning
		print("🥤 [CupTuner] " .. (tuning and "ON — I/K=X J/L=Y U/O=Z, B=출력, N=리셋 (Shift=미세)" or "OFF"))
		return
	end
	if not tuning then return end
	local cup = findCup()
	if not cup then print("[CupTuner] 손에 컵 없음 (/potionskin Cup 먼저)"); return end
	local step = UIS:IsKeyDown(Enum.KeyCode.LeftShift) and SMALL or STEP
	local map = {
		[Enum.KeyCode.I] = CFrame.Angles(step,0,0),
		[Enum.KeyCode.K] = CFrame.Angles(-step,0,0),
		[Enum.KeyCode.J] = CFrame.Angles(0,step,0),
		[Enum.KeyCode.L] = CFrame.Angles(0,-step,0),
		[Enum.KeyCode.U] = CFrame.Angles(0,0,step),
		[Enum.KeyCode.O] = CFrame.Angles(0,0,-step),
	}
	if map[key] then
		rotateCup(cup, map[key])
	elseif key == Enum.KeyCode.B then
		printTune(cup)
	elseif key == Enum.KeyCode.N then
		-- 리셋: handle 기준 상대회전 0
		local handle
		for _, c in ipairs(cup:GetChildren()) do
			if c:IsA("WeldConstraint") and c.Part0 then handle = c.Part0; c:Destroy() end
		end
		if handle then
			local rel = handle.CFrame:ToObjectSpace(cup.CFrame)
			cup.CFrame = handle.CFrame * CFrame.new(rel.Position)
			local wc = Instance.new("WeldConstraint"); wc.Part0=handle; wc.Part1=cup; wc.Parent=cup
			print("[CupTuner] 회전 리셋")
		end
	end
end)

print("🥤 CupTunerClient 준비 — T 키로 튜너 토글")
