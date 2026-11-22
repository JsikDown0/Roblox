-- SpectateServer
-- 관전 시스템 서버 측.
-- 클라이언트의 GetSpectateTargets 요청에 응답한다.
-- 관전 대상 목록 = RoundSystem._G.GetSpectateTargets() (태거 먼저, 러너들, NPC 더미)
-- 권한: 요청자가 "라운드에 살아서 참여 중"이면 관전 불가 (자기 캐릭터 조작 보호).
--
-- 엔트리 형식 (RoundSystem 에서 생성):
--   플레이어 → { kind="player", userId, name, isTagger }
--   NPC     → { kind="npc", model=<이름>, name, isTagger=false }
-- 클라이언트가 kind 에 따라 캐릭터를 찾는다.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local getTargetsFn = ReplicatedStorage:WaitForChild("GetSpectateTargets")

getTargetsFn.OnServerInvoke = function(requester)
	-- 권한 체크: 살아서 플레이 중인 사람은 관전 불가
	if _G.IsPlayingAlive and _G.IsPlayingAlive(requester) then
		return { allowed = false, targets = {} }
	end

	-- 관전 대상 조회 (RoundSystem 에서 완성된 엔트리 배열 반환)
	local targets = {}
	if _G.GetSpectateTargets then
		local entries = _G.GetSpectateTargets()
		for _, entry in ipairs(entries) do
			-- 요청자 본인은 제외 (player kind 이고 userId 일치 시)
			local isSelf = (entry.kind == "player" and entry.userId == requester.UserId)
			if not isSelf then
				table.insert(targets, entry)
			end
		end
	end

	return { allowed = true, targets = targets }
end

print("✅ SpectateServer 준비 완료")
