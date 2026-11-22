-- RunnerDiveServer — 산데비스탄 i-frame을 서버 권위로 관리
-- 클라이언트가 SetAttribute 한 값은 서버로 복제되지 않으므로(복제는 서버→클라 단방향),
-- 클라가 RemoteEvent로 "대시했음"을 통보 → 서버가 player.Invincible 을 설정/해제.
-- ItemDamageSystem 등 서버 킬판정은 이 서버측 Invincible 속성을 읽음.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MAX_IFRAME = 3.0   -- 보안: 클라가 보낸 지속시간 상한 (조작 방지)

-- ── 공유 헬퍼: 모든 킬 시스템이 킬 직전에 호출 ──
-- 캐릭터가 현재 무적(i-frame) 상태면 true. 플레이어 없는 NPC/nil은 false.
-- 사용법:  if _G.isInvincible(char) then return end   -- 또는 continue
_G.isInvincible = function(character)
	if not character then return false end
	local plr = Players:GetPlayerFromCharacter(character)
	return plr ~= nil and plr:GetAttribute("Invincible") == true
end

-- RemoteEvent 준비 (없으면 생성)
local remote = ReplicatedStorage:FindFirstChild("RunnerDiveRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "RunnerDiveRemote"
	remote.Parent = ReplicatedStorage
end

-- 📡 잔상 브로드캐스트 전용 채널. 입력용(remote)과 분리한다 —
--    remote 는 클라→서버 요청이고 이건 서버→전체 알림이라 방향과 신뢰 경계가 다르다.
local dashFxRemote = ReplicatedStorage:FindFirstChild("RunnerDiveFxRemote")
if not dashFxRemote then
	dashFxRemote = Instance.new("RemoteEvent")
	dashFxRemote.Name = "RunnerDiveFxRemote"
	dashFxRemote.Parent = ReplicatedStorage
end

-- 플레이어별 토큰: 겹치는 i-frame 타이머 무효화용
local activeToken = {}

remote.OnServerEvent:Connect(function(player, duration)
	-- 러너만 허용
	if player:GetAttribute("Role") ~= "Runner" then return end

	duration = tonumber(duration) or 0
	if duration <= 0 then return end
	duration = math.min(duration, MAX_IFRAME)

	player:SetAttribute("Invincible", true)

	-- 📡 [DASH-BROADCAST] 대시 사실을 모든 클라에 알린다.
	--   [이유] 잔상은 RunnerDive(LocalScript)가 workspace 에 직접 파트를 만드는 방식이라
	--          '본인 화면에만' 보였다. 대시 스킨은 상점에서 파는 상품인데 남이 못 보면
	--          구매 동기가 없고, 태거도 러너가 대시를 썼는지(=6초 쿨 시작) 읽을 수 없다.
	--   ⚠️ 색은 실어 보내지 않는다. 각 클라가 player:GetAttribute("DashSkin") 을 직접 읽어
	--      DASH_SKIN_SPECIAL / DashData 로 색을 계산한다. 페이로드도 줄고 값도 어긋나지 않는다.
	--   ⚠️ 본인에게도 간다. 수신부에서 LocalPlayer 는 걸러야 잔상이 두 겹으로 그려지지 않는다.
	dashFxRemote:FireAllClients(player, duration)

	local token = {}
	activeToken[player] = token

	task.delay(duration, function()
		-- 그 사이 새 대시가 또 들어왔으면(토큰 교체) 이 타이머는 무효
		if activeToken[player] == token then
			player:SetAttribute("Invincible", false)
			activeToken[player] = nil
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	activeToken[player] = nil
end)

print("✅ RunnerDiveServer 준비! (i-frame 서버 권위 관리 + _G.isInvincible 헬퍼 노출, MAX_IFRAME:", MAX_IFRAME, "s )")
