-- ResetGuardClient: 라운드 중(stage1/stage2)엔 리셋 버튼 차단, 인터미션엔 허용.
-- 목적: 러너가 리셋으로 다운 창(취약+부활 기회)·victim 컷씬(관 등)을 스킵하는 것 방지.
--       + 태거 자폭 방지. 인터미션엔 허용해 지오메트리 끼임 탈출 가능.
-- 참고: 킬 크레딧은 서버가 Role 폴백(GetKiller)으로 처리해 리셋에 안전. 이건 클라 QoL 방어선.
local StarterGui       = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local phaseEvent  = ReplicatedStorage:WaitForChild("RoundPhaseEvent")   -- ("intermission" | "stage1")
local stage2Event = ReplicatedStorage:WaitForChild("Stage2Started")     -- FireAllClients (2단계 진입)

-- SetCore는 CoreGui 준비 전 호출 시 에러 → 성공할 때까지 재시도
local function setReset(enabled)
	for _ = 1, 15 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", enabled)
		end)
		if ok then return end
		task.wait(0.2)
	end
end

phaseEvent.OnClientEvent:Connect(function(phase)
	if phase == "stage1" then
		setReset(false)        -- 라운드 시작 → 차단
	elseif phase == "intermission" then
		setReset(true)         -- 대기 시간 → 허용 (끼임 탈출)
	end
end)

stage2Event.OnClientEvent:Connect(function()
	setReset(false)            -- 2단계도 라운드 진행 중 → 계속 차단
end)

-- 초기 상태: 로비/인터미션이므로 허용
setReset(true)

print("✅ ResetGuardClient 활성화 (라운드 중 리셋 차단)")
