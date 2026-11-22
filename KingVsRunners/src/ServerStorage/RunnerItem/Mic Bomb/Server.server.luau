-- Mic Bomb Server (최소화: 비행/폭발은 영속 스크립트 MicBombSystem 이 담당)
-- Tool 스크립트는 던지기 요청만 검증 후 _G.launchMicBomb 호출 → 즉시 자폭.
-- (비행 Heartbeat가 MicBombSystem 소유라 Tool 파괴와 무관하게 끝까지 날아감)

local tool = script.Parent
local RM   = tool:WaitForChild("RemoteEvent")

local thrown = false  -- 일회용 가드

RM.OnServerEvent:Connect(function(player, targetPos)
	if thrown then return end
	if tool.Parent ~= player.Character then return end
	if typeof(targetPos) ~= "Vector3" then return end
	local char = player.Character
	if not char then return end
	thrown = true
	-- [CONSUMABLE-ONUSE] 투척 확정 지점. thrown·Tool소유·targetPos 가드 통과 후.
	if _G.MarkConsumableUsed then _G.MarkConsumableUsed(player, "Mic Bomb") end

	if _G.launchMicBomb then
		_G.launchMicBomb(player, char, targetPos)
	else
		warn("⚠️ Mic Bomb: _G.launchMicBomb 없음 (MicBombSystem 로드 확인)")
	end

	-- 비행은 MicBombSystem에서 돌아가므로 Tool은 바로 제거해도 안전
	if tool then tool:Destroy() end
end)

print("✅ Mic Bomb Server ready (→ _G.launchMicBomb, 비행은 MicBombSystem)")
