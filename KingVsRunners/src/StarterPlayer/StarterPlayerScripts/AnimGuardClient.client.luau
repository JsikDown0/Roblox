-- ═══════════════════════════════════════════════════════════════
-- 🧊 AnimGuardClient — 라운드 종료 시 '얼린 애니메이션' 해제 (툴 독립)
--
-- [왜 별도 스크립트인가 — 5세션 만에 찾은 원인]
--   PushTool.Client 는 툴 안에 있는 LocalScript 다. 라운드가 끝나면 서버가
--   PushTool 을 제거하고, 그러면 그 LocalScript 도 함께 사라진다.
--   즉 "툴이 사라질 때 정리한다" 는 코드가 정작 그 순간 실행될 주체를 잃는다.
--
--   그런데 AnimationTrack 은 Humanoid.Animator 에 붙어 있고, Animator 는
--   '캐릭터' 소유다. 툴이 죽어도 트랙은 살아남는다.
--   → AdjustSpeed(0) 으로 얼린 트랙이 아무도 멈춰주지 않아 그 자세로 굳는다.
--
--   실측(2026-08-27):
--     [FREEZEDIAG:phase=intermission+3.0s] PushTool=없음
--       73582353792070[p=Action4, spd=0.00, w=1.00]   ← 굳은 트랙
--     같은 시간대에 [ANIMDIAG] 로그가 하나도 없음 = unfreezeAllTracks 미실행.
--
--   다섯 번의 수정(attackTrack 추가 / 안전망 / RoundPhase 감시)이 전부
--   '이미 죽은 스크립트 안' 에 있었다. 코드가 틀린 게 아니라 실행되지 않았다.
--
-- ⚠️ Core / Idle / Movement 우선순위는 절대 건드리지 않는다.
--   그것까지 멈추면 T포즈가 된다(ANIM-SWEEP 에서 겪은 사고와 같은 유형).
--   실측 로그에서 Idle(p=Idle)과 걷기(p=Core)는 정상 재생 중이었다 — 살려야 한다.
-- ⚠️ AdjustSpeed(1) 을 먼저 하고 Stop 한다. 속도 0 인 트랙은 Stop 의 페이드가
--   진행되지 않아 마지막 프레임 자세가 그대로 남는다.
-- ⚠️ PushTool.Client 의 정리 코드는 남겨둔다. 툴이 살아 있는 경로(장착 해제 등)
--   에서는 그쪽이 더 빨리 반응한다. 이 스크립트는 '툴이 없을 때' 를 메운다.
-- ═══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

-- 멈출 우선순위. Action 계열만.
local STOP_PRIORITY = {
	[Enum.AnimationPriority.Action]  = true,
	[Enum.AnimationPriority.Action2] = true,
	[Enum.AnimationPriority.Action3] = true,
	[Enum.AnimationPriority.Action4] = true,
}

local DIAG = false  -- 🔬 라운드마다 warn 을 찍어 로그 노이즈가 크다. 필요할 때만 true.
--   [2026-09-13] false 로. 09-13 판에서 4회 전부 "Action 트랙 0개 해제" 였다 —
--   해제할 트랙이 없는 상태만 찍히고 있어 지금은 정보가 0이다.
--   ⚠️ 자세 굳음이 재발하면 다시 true. 그때 볼 것은 '0개'가 아닌 줄이다.
                    --    ⚠️ 로그만 끄고 Action 트랙 해제 동작은 그대로 돈다.

-- 🧭 [2026-09-06] AutoRotate 복원. 애니메이션과 같은 이유로 여기에 있다.
--   [증상] 해머 스핀 중 라운드가 끝나면 캐릭터가 옆을 본 채 걷는다.
--     앞으로 가는데 몸이 안 돌아가니 "포즈가 굳었다"처럼 보인다.
--   [원인] HammerLow 의 SpinClient 가 회전 연출을 위해 AutoRotate=false 로 두고,
--     Heartbeat 종료 또는 Tool.Unequipped 에서 되돌린다. 그런데 라운드가 끝나면
--     서버가 툴을 지우고 그 LocalScript 가 함께 죽는다 — 복원 코드가 실행될
--     주체를 잃는다. 이 파일 헤더가 설명하는 바로 그 함정이다.
--   [왜 서버가 아니라 여기인가] AutoRotate 는 클라가 자기 캐릭터에 세운 값이다.
--     서버에서 true 를 써도 클라 쪽 값을 확실히 덮지 못한다 — 애니 트랙과 같은 부류다.
--     실제로 RoundSystem 에 서버 복구를 넣었는데도 증상이 남았다.
--   ⚠️ SpinClient 자체의 백팩 안전망(Tool.Destroying)에는 AutoRotate 가 빠져 있었다.
--     거기에 더해도 되지만, 툴이 파괴되는 순간 지연 콜백은 실행되지 않는다 —
--     툴 밖에서 하는 이 방식이 확실하다.
local function restoreAutoRotate(hum)
	if hum and not hum.AutoRotate then
		hum.AutoRotate = true
		if DIAG then warn("[AnimGuard] AutoRotate 복원") end
	end
end

local function unfreeze(tag)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	restoreAutoRotate(hum)
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return end

	local stopped = {}
	for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
		if STOP_PRIORITY[tr.Priority] then
			local id = tr.Animation and tr.Animation.AnimationId or "?"
			stopped[#stopped + 1] = id:gsub("rbxassetid://", "")
			pcall(function()
				tr:AdjustSpeed(1)   -- 얼린 트랙은 속도를 되돌려야 Stop 이 먹는다
				tr:Stop(0)
			end)
		end
	end
	-- ⚠️ 0개일 때도 찍는다. "해제할 게 없었다"도 중요한 증거다 —
	--   트랙이 안 잡혔다는 뜻이고, 그러면 굳는 원인이 애니가 아니라는 신호다.
	if DIAG then
		warn(("[AnimGuard:%s] Action 트랙 %d개 해제 | %s"):format(
			tag, #stopped, table.concat(stopped, " ")))
	end
end

-- 라운드 밖으로 나갈 때만. stage1/stage2 로 '들어갈' 때 풀면 정상 스윙이 끊긴다.
ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(function()
	local ph = ReplicatedStorage:GetAttribute("RoundPhase")
	if ph == "stage1" or ph == "stage2" then return end
	unfreeze("phase=" .. tostring(ph))
	-- ⚠️ 지연 재시도 2회. 라운드 종료 순간엔 툴 제거·캐릭터 이동이 겹쳐
	--   그 사이 새 트랙이 시작될 수 있다(예: 이동 중 재생된 스윙).
	task.delay(0.5, function() unfreeze("phase+0.5s") end)
	task.delay(2.0, function() unfreeze("phase+2.0s") end)
end)

-- 캐릭터가 새로 생기면 이전 상태가 남아 있지 않게 한 번 훑는다.
player.CharacterAdded:Connect(function()
	task.wait(0.3)
	unfreeze("spawn")
end)

-- 수동 확인용
player.Chatted:Connect(function(msg)
	if msg:lower():sub(1, 6) == "/adiag" then unfreeze("manual") end
end)

print("🧊 AnimGuardClient 활성화 (툴 독립 — 라운드 종료 시 Action 트랙 해제)")
