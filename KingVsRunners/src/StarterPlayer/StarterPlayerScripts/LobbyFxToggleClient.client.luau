--[[
	LobbyFxToggleClient — 라운드 참여 중에는 로비 이펙트를 꺼서 성능을 확보한다.

	끄는 대상: LobbyCliffFalls(폭포, PE 72 + Beam 81) / ANGEL SET2(로비 건물) 등
	           로비에만 존재하는 파티클·빔. 맵 이펙트는 건드리지 않는다.

	켜고 끄는 기준 — "지금 이 플레이어가 로비를 보고 있는가":
	  · Role 속성이 있고(라운드 배정됨) 아직 탈락하지 않았으면  → 끔 (맵에 있음)
	  · Role 이 없거나 / Eliminated / 관전 중이면                → 켬 (로비로 돌아옴)

	⚠️ 클라이언트에서만 처리한다. 서버가 Enabled 를 만지면 전 플레이어에게 전파되어
	   로비에 남은 사람의 화면까지 꺼진다.
	⚠️ Enabled=false 는 이미 방출된 파티클을 지우지 않고 신규 방출만 멈춘다.
	   즉시 정리하려면 Clear() 를 함께 호출한다.
]]

local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- 로비 전용 이펙트가 들어있는 최상위 오브젝트 이름
local LOBBY_FX_ROOTS = {
	"LobbyCliffFalls",   -- 폭포 (가장 큼)
	"ANGEL SET2",        -- 로비 건물 장식
	"Floating Lobby",    -- 섬/발판 계열
	"Lantern",
	"Group Rewards",
	"shop",              -- 상점 전시물: DragonFire 불꽃, SakuraBlade 벚꽃, 리바이벌 깃발
	"ShopNPC",
}

local tracked = {}     -- { [instance] = true }  원래 Enabled 였던 것만 기록
local isOff = false

local function collect()
	tracked = {}
	for _, name in ipairs(LOBBY_FX_ROOTS) do
		local root = workspace:FindFirstChild(name)
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				-- ⚠️ Fire/Smoke 도 포함해야 한다. 상점 전시 DragonFireSword 의 불꽃은
				--    ParticleEmitter 가 아니라 Fire 클래스라 기존 조건으로는 안 잡혔다.
				if (d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail")
					or d:IsA("Fire") or d:IsA("Smoke")) and d.Enabled then
					tracked[d] = true
				end
			end
		end
	end
	local n = 0
	for _ in pairs(tracked) do n += 1 end
	return n
end

local function setLobbyFx(on)
	if on == (not isOff) then return end   -- 이미 그 상태
	isOff = not on

	if not on then
		-- 끄기 직전에 목록을 새로 수집 (맵 스왑 등으로 구성이 바뀌었을 수 있음)
		collect()
	end

	local n = 0
	for inst in pairs(tracked) do
		if inst.Parent then
			inst.Enabled = on
			if not on and inst:IsA("ParticleEmitter") then
				inst:Clear()   -- 이미 떠 있는 입자도 즉시 제거
			end
			n += 1
		else
			tracked[inst] = nil
		end
	end
	print(string.format("🌊 [LobbyFX] 로비 이펙트 %s (%d개)", on and "ON" or "OFF", n))
end

-- 로비를 보고 있는가?
-- ⚠️ 판단 기준은 Role 하나다.
--    탈락(Eliminated)해도 라운드가 끝날 때까지 맵에 남아 관전하므로
--    (로비 복귀는 endRound 의 teleportPlayer(lobbySpawn) 시점 = Role 해제와 같은 타이밍)
--    Eliminated 로 켜면 "맵을 보는 중인데 로비 이펙트 ON" 이 되어 성능 이득이 사라진다.
local function shouldShowLobby()
	return player:GetAttribute("Role") == nil
end

local function refresh()
	setLobbyFx(shouldShowLobby())
end

player:GetAttributeChangedSignal("Role"):Connect(refresh)

-- 초기 1회 (맵/로비 로딩 후)
task.spawn(function()
	task.wait(3)
	print("🌊 [LobbyFX] 대상 수집: "..collect().."개")
	refresh()
end)
