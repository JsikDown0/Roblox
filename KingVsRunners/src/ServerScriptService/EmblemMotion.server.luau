--[[
	EmblemMotion — 리더보드 받침대 위 엠블럼(이모지 판)에 회전 + 부유 모션 부여.

	대상: 이름이 "FuryEmblem" 이거나 Attribute "EmblemMotion" = true 인 앵커드 Part.
	아바타 Rig가 애니메이션으로 살아있는 것과 달리 판은 정적이라 존재감이 죽는다.
	Y축 회전으로 앞뒤 양면을 번갈아 보여주고, 사인파 부유로 "떠 있음"을 명확히 한다.

	성능: Heartbeat 1개에서 전체 엠블럼을 일괄 갱신(엠블럼당 루프를 만들지 않음).
	      대상이 0개면 연결 자체를 끊는다.
]]

local RunService = game:GetService("RunService")

local SPIN_SPEED  = 0.6    -- 초당 회전(라디안). 약 34도/초 → 한 바퀴 10.5초
local FLOAT_AMP   = 0.45   -- 부유 진폭(스터드)
local FLOAT_SPEED = 1.4    -- 부유 주기 계수

local emblems = {}

local function collect()
	emblems = {}
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart")
		and (obj.Name == "FuryEmblem" or obj:GetAttribute("EmblemMotion") == true) then
			-- 기준 CFrame 확보: 최초 1회 저장해두고 이후엔 이걸 기준으로만 변형
			if not obj:GetAttribute("_BaseCF_X") then
				obj:SetAttribute("_BaseCF_X", obj.CFrame.X)
				obj:SetAttribute("_BaseCF_Y", obj.CFrame.Y)
				obj:SetAttribute("_BaseCF_Z", obj.CFrame.Z)
			end
			obj.Anchored = true
			table.insert(emblems, obj)
		end
	end
	return #emblems
end

local n = collect()
print(string.format("✨ EmblemMotion 시작 — 대상 %d개 (회전 %.1f rad/s, 부유 ±%.2f)",
	n, SPIN_SPEED, FLOAT_AMP))

if n > 0 then
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		for i = #emblems, 1, -1 do
			local e = emblems[i]
			if not e.Parent then
				table.remove(emblems, i)
			else
				local bx = e:GetAttribute("_BaseCF_X")
				local by = e:GetAttribute("_BaseCF_Y")
				local bz = e:GetAttribute("_BaseCF_Z")
				-- 엠블럼마다 위상을 어긋나게 해 여러 개일 때 동기화된 느낌 방지
				local phase = (i - 1) * 1.1
				local y = by + math.sin((t + phase) * FLOAT_SPEED) * FLOAT_AMP
				e.CFrame = CFrame.new(bx, y, bz) * CFrame.Angles(0, t * SPIN_SPEED, 0)
			end
		end
	end)
end
