-- WeaponUICleanupClient — 라운드 경계 무기 UI/잔재 강제 정리 (영속)
-- 배경: 라운드 종료 시 서버가 UnequipTools와 Tool:Destroy()를 같은 프레임에 실행하면,
-- 툴 자식 LocalScript(ChargeClient 등)는 Unequipped/Destroying 콜백을 실행할 기회를
-- 얻기 전에 툴과 함께 파괴된다. → 툴 내부 정리 코드는 이 경로에서 절대 실행되지 않음.
-- 해결: 툴 생명주기와 무관한 이 영속 스크립트가 intermission마다 무조건 청소한다.
-- (DragonEntranceClient의 라운드 리셋과 같은 패턴)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- 무기 스킬 gui 이름들 (각 무기 클라 스크립트가 PlayerGui에 만드는 것)
-- ⚠️ PushTool 은 GUI 를 두 개 만든다 — PushCooldownGui(푸시 바) + PushGrabGui(그랩 버튼).
--    쿨다운 바만 목록에 있어 그랩 버튼이 라운드 종료 후에도 화면에 남아 있었다.
--    둘 다 ResetOnSpawn=false 라 리스폰으로도 안 지워진다(실측).
local WEAPON_GUIS = { "HammerSlamGui", "GauntletDashGui", "HammerSpinGui",
                      "PushCooldownGui", "PushGrabGui", "KatanaCounterGui" }
-- workspace에 남는 조준/경로 잔재 파트 이름들 (클라 로컬 생성물)
local RESIDUE_PARTS = { "_SlamAimPreview", "_GauntletDashPathSeg", "_GrabAimLine", "_GrabAimEnd" }

-- 🖐️ [2026-09-14] SkillBarGui.SkillBar 안에 무기가 꽂아 넣는 슬롯 이름들.
--   ⚠️ 위 WEAPON_GUIS 와 다른 목록이다. 저건 PlayerGui 직속 ScreenGui 를 지우고,
--     이건 KEEP_OPEN 인 SkillBarGui **안쪽**을 청소한다. 컨테이너는 남겨야 한다.
--   ⚠️ DiveSlot(러너 대시)은 StarterGui 소유라 여기 넣으면 안 된다 — 라운드와 무관하게 상시다.
local SKILLBAR_SLOTS = { "GrabSlot" }

local function cleanup(reason)
	-- ① 인벤토리(백팩 UI) 복구 — 스킬 중 종료로 꺼진 채 잔존하면 인벤이 영영 사라짐
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)
	-- ② 무기 스킬 gui 제거 (스킬 아이콘·"착지 지점" 문구 잔재)
	local pg = player:FindFirstChild("PlayerGui")
	if pg then
		for _, name in ipairs(WEAPON_GUIS) do
			local g = pg:FindFirstChild(name)
			if g then g:Destroy() end
		end
	end
	-- ③ 조준/경로 잔재 파트 제거 (클라 로컬 파트라 여기서 지워야 함)
	for _, d in ipairs(workspace:GetChildren()) do
		for _, name in ipairs(RESIDUE_PARTS) do
			if d.Name == name then d:Destroy() break end
		end
	end
	-- ④ 🖐️ [2026-09-14] SkillBar 안의 무기 슬롯 잔재 제거.
	--   [증상] 라운드가 끝나도 로비에 Q(광역 그랩) 버튼이 남았다(실측 09-14 스크린샷).
	--   [왜 ②로 안 잡히나] ② 는 PlayerGui 직속 ScreenGui 를 지운다. 그런데 이 슬롯은
	--     SkillBarGui **안쪽**에 들어 있고, SkillBarGui 는 KEEP_OPEN 화이트리스트라
	--     정리 대상에서 통째로 빠진다. 컨테이너는 남기고 안의 슬롯만 걷어내야 한다.
	--   [근본 원인] 슬롯을 만드는 PushTool.Client 는 **툴 안의 LocalScript** 라
	--     라운드 종료 시 툴과 함께 죽는다. 자기 정리 코드(grabSlot:Destroy)에 도달하지 못해
	--     만든 쪽은 사라지고 만든 물건만 남는다.
	--     ⚠️ 08-21 에 "무기가 없는 로비에 강타 버튼이 잔존"한 것과 같은 계열이다.
	--        그때는 GUI 통째였고 지금은 그 안의 슬롯 하나다.
	--   ⚠️ DiveSlot(러너 대시)은 StarterGui 소유라 건드리면 안 된다. 이름으로 고른다.
	if pg then
		local bar = pg:FindFirstChild("SkillBarGui")
		bar = bar and bar:FindFirstChild("SkillBar")
		if bar then
			local removed = 0
			for _, slot in ipairs(bar:GetChildren()) do
				for _, name in ipairs(SKILLBAR_SLOTS) do
					if slot.Name == name then slot:Destroy() removed = removed + 1 break end
				end
			end
			if removed > 0 then
				print("🖐️ [WeaponUICleanup] SkillBar 슬롯 잔재 " .. removed .. "개 제거")
			end
		end
	end
	print("🧼 [WeaponUICleanup] 정리 완료 (" .. reason .. ")")
end

-- ────────────────────────────────────────────────────────────────
-- 라운드 시작 시 메타 UI 강제 닫기
--   라운드 도중에 상점·인벤토리를 열어 로드아웃을 바꾸는 걸 막는다.
--   ⚠️ 이건 편의 처리이고 실제 차단은 서버(LoadoutManager.isRoundActive)가 한다.
--   유지할 UI 만 화이트리스트로 두고 나머지를 닫는다 — 이름을 하나씩 나열하면
--   새 UI 가 추가될 때 누락되기 때문.
-- ────────────────────────────────────────────────────────────────
local KEEP_OPEN = {   -- 라운드 중에도 필요한 UI
	HUD = true, KillLogGui = true, SkillBarGui = true, EmotionBarGui = true,
	SpectateGui = true, TaggerItemUI = true, RoundResultGui = true,
	GameUI = true, SosButtonGui = true, SosMarkers = true,
	ReviveChanceGui = true, ReviveRescueInfoGui = true, RevivePromptGui = true,
	GroupRewardGui = true, MapVoteGui = true,
	-- ⚠️ [TOUCH-GUI] 로블록스 기본 터치 조작(조이스틱·점프 버튼) 컨테이너.
	--    이게 빠져 있어 라운드 시작 시 closeMetaUIs 가 조이스틱을 통째로 껐다
	--    (실측 2026-08-21 모바일: 라운드 시작하면 고정 조이스틱이 사라짐).
	--    DynamicThumbstick 시절엔 생성 시점이 늦어 우연히 안 걸렸을 뿐, 잠재 버그였다.
	TouchGui = true, ControlFrame = true, TouchControlFrame = true,
	-- ⚠️ [WEAPON-SKILL-GUI] 무기 스킬 버튼 GUI 들.
	--    각 무기 스크립트가 Equipped/Unequipped 로 자체 관리하므로 여기서 건드리면 안 된다.
	--    빠져 있으면 라운드 시작에 닫혔다가 restoreMetaUIs 가 인터미션에 다시 켜서
	--    무기가 없는 로비에도 스킬 버튼이 남는다 (실측 2026-08-21: 강타 버튼이 로비에 잔존).
	ClassicLungeGui = true, KatanaCounterGui = true,
	HammerSpinGui = true, HammerSlamGui = true, GauntletDashGui = true,
	-- ⚠️ [REWARD-CUTSCENE] 보상 상자 컷신 / 카드.
	--    라운드 시작이 연출 도중에 걸리면 화면에서 사라진다
	--    (실측 2026-08-21: Day 7 수령 직후 라운드 시작 → 상자가 안 열림).
	--    ※ 보상 자체는 서버에서 이미 지급됐다(grantRandomSkin 이 속성+프로필에 기록).
	--       사라지는 건 연출뿐이지만, 뭘 받았는지 모르게 되므로 유지한다.
	RareSkinRewardCardGui = true, BoxCutsceneGui = true,
	QuestClaimToast = true,
}

-- 라운드 시작 때 내가 끈 UI 목록. 인터미션에 이것만 되돌린다.
--   ⚠️ '전부 켜기'로 복구하면 원래 꺼져 있던 UI(GauntletCustomGui 등)까지 켜진다.
local closedByMe = {}

-- 라운드 시작에 내가 닫은 UI 의 '이름' 집합.
--   ⚠️ ChildAdded 감시가 이걸 기준으로 삼는다. KEEP_OPEN 화이트리스트만 보고 막으면
--      라운드 중 늦게 생성되는 게임플레이 UI 까지 꺼버린다
--      (실측 2026-08-20: FirePressureCountdownGui·GameAnnounceUI 가 차단돼
--       불기둥 카운트다운이 안 보였다).
--      되살아난 것만 막으려면 "원래 열려 있다가 내가 닫은 것"으로 좁혀야 한다.
local closedNames = {}

-- 현재 라운드 단계. 라운드 중에 새로 뜨는 UI 를 막으려면 이 상태가 필요하다.
--   ⚠️ 이벤트만 믿으면 안 된다 — 이미 발사된 stage1 을 놓칠 수 있어
--      서버가 남긴 속성(RoundPhase)을 초기값으로 읽고 변화도 함께 추적한다.
local currentPhase = ReplicatedStorage:GetAttribute("RoundPhase") or "intermission"
local function inRound()
	return currentPhase == "stage1" or currentPhase == "stage2"
end

--   isRoundStart=true  : 목록을 새로 만든다(라운드 시작)
--   isRoundStart=false : 기존 목록에 덧붙인다(라운드 중 새로 뜬 UI 차단)
--     ⚠️ 이때 목록을 비우면 앞서 닫아둔 UI 가 복구 대상에서 빠져 영영 안 열린다.
-- [ROUND-UI-KEEP] 라운드가 시작돼도 열려 있던 메타 UI 는 그대로 둔다.
--   ⚠️ 예전엔 라운드 시작 시 전부 강제로 닫았다. 그런데 상자깡·퀘스트 수령·상점 구경
--      도중에 끌려가면 보던 게 통째로 사라져 불편했다(실측 2026-08-21 솔로).
--   ⚠️ 원래 닫던 목적은 '라운드 중 로드아웃 변경 차단'이었다. 그건 인벤 쪽에서
--      따로 막아야 할 문제이지, 모든 UI 를 닫을 이유는 아니다.
--   새 동작: 라운드 시작 시엔 아무것도 닫지 않는다. 유저가 직접 닫으면 그 이름을
--      기억해(closedNames) 라운드가 끝날 때까지 재출현을 막는다.
--      → 계속 보고 싶은 사람은 열어두면 되고, 닫은 사람은 방해받지 않는다.
local function closeMetaUIs(isRoundStart)
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	if isRoundStart then
		-- 라운드 시작: 목록만 비우고 닫지는 않는다.
		closedByMe = {} ; closedNames = {}
		print("[WeaponUICleanup] 라운드 시작 — 열린 UI 유지(닫으면 그때부터 차단)")
		return
	end
	local n = 0
	for _, gui in ipairs(pg:GetDescendants()) do
		-- 라운드 중 재훑기: '유저가 닫았던 이름'만 대상.
		-- 전수로 끄면 라운드 중 생성되는 게임플레이 UI 까지 꺼진다.
		if gui:IsA("ScreenGui") and not KEEP_OPEN[gui.Name] and gui.Enabled
		   and closedNames[gui.Name] then
			gui.Enabled = false
			closedByMe[#closedByMe + 1] = gui
			n = n + 1
		end
	end
	-- isRoundStart 는 위에서 이미 반환했으므로 여기 도달하지 않는다.
	if n > 0 then
		print("[WeaponUICleanup] 닫아둔 UI " .. n .. "개 재차단")
	end
end

-- ⚠️ [RESPAWN-REVIVE] ResetOnSpawn=true 인 ScreenGui(Quests·Rewards·Settings 등)는
--    리스폰 때 파괴되고 StarterGui 에서 Enabled=true 인 새 인스턴스로 복제된다.
--    closedByMe 가 든 건 파괴된 옛 인스턴스라 아무도 새것을 닫지 않는다.
--    (실측 2026-08-20: 13개 닫고 7개만 복구 — 6개가 파괴·재생성됨)
--    리스폰 타이밍이 라운드 시작 전후 어디든 잡히도록 ChildAdded 로 감시한다.
-- [ROUND-UI-KEEP] 라운드 중 유저가 직접 닫은 UI 를 기억한다.
--   ⚠️ 이게 없으면 closedNames 가 영영 비어 있어 재차단이 걸리지 않는다.
--      (라운드 시작 시 강제로 닫지 않게 바뀌면서 채우는 주체가 사라졌다)
--   Enabled=false 로 바뀌는 순간을 잡아 이름만 기록한다. 되돌리진 않는다.
local function watchUserClose()
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	local hooked = {}
	local function hook(gui)
		if hooked[gui] then return end
		if not gui:IsA("ScreenGui") then return end
		if KEEP_OPEN[gui.Name] then return end
		hooked[gui] = true
		gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if inRound() and not gui.Enabled then
				closedNames[gui.Name] = true
			end
		end)
	end
	for _, g in ipairs(pg:GetChildren()) do hook(g) end
	pg.ChildAdded:Connect(hook)
end

local function watchNewGuis()
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	pg.ChildAdded:Connect(function(gui)
		if not inRound() then return end
		if not gui:IsA("ScreenGui") then return end
		if KEEP_OPEN[gui.Name] then return end
		-- ★ 라운드 시작에 내가 닫았던 이름만 재차단한다.
		--   이 조건이 없으면 라운드 중 새로 생기는 게임플레이 UI 까지 꺼진다.
		if not closedNames[gui.Name] then return end
		-- 복제 직후엔 Enabled 가 아직 확정 전일 수 있어 한 프레임 양보한다
		task.defer(function()
			if inRound() and gui.Parent and gui.Enabled then
				gui.Enabled = false
				closedByMe[#closedByMe + 1] = gui
				print("[WeaponUICleanup] 리스폰으로 되살아난 UI 재차단: " .. gui.Name)
			end
		end)
	end)
end
watchNewGuis()
watchUserClose()   -- [ROUND-UI-KEEP] 유저가 닫은 UI 를 기억해 재출현을 막는다

-- 인터미션 복구. 각 UI 스크립트는 Enabled 를 건드리지 않고 내부 Frame.Visible 만
-- 토글하므로, Enabled=false 로 두면 서버가 '열기'를 보내도 화면에 안 뜬다.
-- ⚠️ [WEAPON-GUI-CLEANUP] 무기 스킬 GUI 는 인터미션에 '파괴'한다.
--    각 무기의 FXClient 가 Tool.Destroying 으로 스스로 정리하게 해뒀지만,
--    툴이 파괴되면 그 안의 LocalScript 도 함께 죽어 핸들러가 실행될 기회가 없다.
--    그래서 GUI 가 PlayerGui 에 남아 로비에서도 쿨다운까지 표시됐다(실측 2026-08-22).
--    → 툴 밖에서 도는 이 스크립트가 확실하게 지운다.
--    ⚠️ ResetOnSpawn=true 도 있지만 라운드 종료 시 리스폰이 없으면 소용없다.
--    ⚠️ 라운드 중에는 절대 지우면 안 된다 — 인터미션에만 호출할 것.
local WEAPON_SKILL_GUIS = {
	"ClassicLungeGui", "KatanaCounterGui",
	"HammerSpinGui", "HammerSlamGui", "GauntletDashGui",
	-- ⚠️ [2026-09-07] 넷이 빠져 있었다. 실측으로 전수 확인한 목록이다.
	--    무기 8종이 만드는 GUI 를 grep(gui.Name =) 으로 뽑아 대조했다.
	"ClassicSwordFXGui", "DiamondComboGui", "DragonFireFXGui", "SakuraStackGui",
	-- ⚠️ [2026-09-08] King 도구(PushTool)의 GUI 둘. 훈련장 KING 탭에서 지급된다.
	--   위 GUI_OF_TOOL 에도 같은 이름이 들어간다 — 두 목록은 담당이 다르다:
	--     · 이 목록      = 라운드 경계 일괄 청소 (툴 없이 GUI 만 남은 상태를 잡는다)
	--     · GUI_OF_TOOL = 툴 소멸 감시 (교체 순간의 잔재를 잡는다)
	--   한쪽만 넣으면 다른 경우가 새므로 반드시 짝으로 유지한다.
	"PushCooldownGui", "PushGrabGui",
}
local function destroyWeaponSkillGuis()
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	local n = 0
	for _, nm in ipairs(WEAPON_SKILL_GUIS) do
		for _, g in ipairs(pg:GetChildren()) do
			if g.Name == nm then g:Destroy() ; n = n + 1 end
		end
	end
	if n > 0 then print("[WeaponUICleanup] 무기 스킬 GUI " .. n .. "개 제거") end
end

-- ⚠️ [2026-09-07] 무기 '교체' 시점의 잔재 (실측 버그)
--   증상: 새 무기를 받으면 이전 무기의 스킬 아이콘이 1개 남아 새 것과 겹친다.
--         2단계 진입(Stage2TriggerSystem 지급)과 로비 무기 체험 양쪽에서 재현.
--   원인: 위 destroyWeaponSkillGuis 는 phase == "intermission" 에서만 불린다(아래 참조).
--         교체는 phase 변화 없이 일어나므로 아무도 청소하지 않았다.
--         툴이 Destroy 되면 그 안의 LocalScript 도 죽어 자체 정리가 실행될 기회가 없다
--         (이 파일 상단 주석이 라운드 종료에 대해 이미 지적한 것과 같은 구조).
--   해결: 목록을 늘리는 대신 '툴이 사라지는 순간'을 직접 본다.
--         무기가 9번째로 늘어도 이 코드는 안 고쳐도 된다.
--   ⚠️ 이름 목록은 그대로 둔다 — 라운드 경계의 일괄 청소는 여전히 이름으로 돈다.
--      (툴 없이 GUI 만 남은 상태는 소멸 감시로는 못 잡는다)
local GUI_OF_TOOL = {
	ClassicSword      = { "ClassicSwordFXGui", "ClassicLungeGui" },
	DiamondBladeSword = { "DiamondComboGui" },
	DragonFireSword   = { "DragonFireFXGui" },
	KatanaSword2      = { "KatanaCounterGui" },
	SakuraBlade       = { "SakuraStackGui" },
	HammerLow         = { "HammerSpinGui" },
	HammerHigh        = { "HammerSlamGui" },
	Gauntlet          = { "GauntletDashGui" },
	-- ⚠️ [2026-09-08] King 도구. 훈련장 KING 탭에서 지급된다.
	--   [증상] 라운드에 끌려간 뒤에도 F 손바닥 버튼이 남았다(1단계 러너인데 태거 UI).
	--   [원인] 이 목록에 없어서 watchTool 의 `if not GUI_OF_TOOL[tool.Name] then return end`
	--     에 걸려 감시 대상조차 되지 못했다.
	--   [이름 출처] PushTool.Client 가 만드는 ScreenGui 두 개 — 실측으로 확인한 값이다.
	--     PushCooldownGui(610행) / PushGrabGui(723행, F 홀드 버튼)
	--   ⚠️ 실전 2단계에서도 태거는 PushTool 을 쓴다. 거기서는 라운드가 끝나야 회수되므로
	--     이 항목이 그 정리까지 함께 담당한다 — 훈련장 전용이 아니다.
	PushTool          = { "PushCooldownGui", "PushGrabGui" },
}

local function destroyGuisFor(toolName)
	local list = GUI_OF_TOOL[toolName]
	if not list then return end
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	local n = 0
	for _, nm in ipairs(list) do
		for _, g in ipairs(pg:GetChildren()) do
			if g.Name == nm then g:Destroy() ; n = n + 1 end
		end
	end
	if n > 0 then
		print("[WeaponUICleanup] " .. toolName .. " 잔재 GUI " .. n .. "개 제거 (교체)")
	end

	-- ⚠️ [2026-09-07] GUI 만으로는 부족하다. 스킬 애니메이션도 툴과 함께 끊긴다.
	--   실측 증상: 라운드 종료 직전(또는 야드 이탈 직전) 스킬을 쓰면 로비에서 애니가
	--   계속 재생된다. 툴 안 스크립트가 Stop() 을 부를 기회를 잃기 때문.
	--   AnimGuardClient 는 RoundPhase 변경 시점에만 돌아서 이 경로를 못 잡는다
	--   (로비 안에서 일어나는 교체·회수는 phase 가 안 바뀐다).
	-- ⚠️ 우선순위가 아니라 '무기 스킬이 쓰는 트랙'만 끈다. Core/Idle/Movement 를 끄면
	--   기본 이동 애니까지 죽는다 — AnimGuardClient 가 같은 이유로 ID 로 제외한다.
	-- ⚠️ [2026-09-07 추가] 이걸로 못 잡는 스킬이 있다.
	--   HammerLow 스핀은 AnimationTrack 을 아예 안 쓴다. RenderStepped 에서
	--   hrp.CFrame 을 직접 돌린다(SpinClient:134). 그래서 여기 검색은 0개가 나오고,
	--   증상('뒤로 달림')은 서버의 _G.ResetCharacterState 가 방향을 펴서 잡는다.
	--   → 0개가 "정상"이 아니라 "이 경로로는 안 보인다"는 뜻이다. 로그로 구분해 둔다.
	local char = player.Character
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator then
		local stopped, playing = 0, 0
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			playing = playing + 1
			local pr = track.Priority
			if pr == Enum.AnimationPriority.Action
			or pr == Enum.AnimationPriority.Action2
			or pr == Enum.AnimationPriority.Action3
			or pr == Enum.AnimationPriority.Action4 then
				track:Stop(0.1)
				stopped = stopped + 1
			end
		end
		if stopped > 0 then
			print("[WeaponUICleanup] " .. toolName .. " Action 트랙 " .. stopped .. "개 해제")
		elseif playing > 0 then
			print("[WeaponUICleanup] " .. toolName .. " 재생 트랙 " .. playing ..
			      "개 (전부 Action 아님 — 해제 대상 없음)")
		end
	end

	-- ⚠️ [2026-09-07] 캐릭터 방향 복구는 '클라에서' 해야 한다.
	--   서버(RoundStateResetServer)가 AutoRotate=true 와 CFrame 을 써도 화면은 안 고쳐졌다.
	--   실측 19:33:29.672 — 서버는 AutoRotate=true / look(0,0,-1) / 기울기 0 으로 '정상'을
	--   보고하는데 플레이어 화면은 여전히 틀어져 있었다.
	--   [왜] 캐릭터의 네트워크 오너가 클라이언트다. 클라가 건 AutoRotate=false 는 서버로
	--   복제되지 않고, 서버가 쓴 CFrame 은 다음 프레임에 클라가 덮어쓴다.
	--   → 서버 로그의 "정상" 은 서버 범위 안에서만 참이다.
	-- [무엇을 하나] AutoRotate 를 클라에서 되돌리고, 카메라가 보는 쪽으로 한 번 정렬한다.
	--   한 번만 펴 주면 그 다음은 AutoRotate 가 이동 방향으로 알아서 맞춘다.
	if hum then
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local beforeAuto = hum.AutoRotate
		local beforeLook = hrp and hrp.CFrame.LookVector or Vector3.zero
		hum.AutoRotate = true
		local cam = workspace.CurrentCamera
		if hrp and cam then
			local cd   = cam.CFrame.LookVector
			local flat = Vector3.new(cd.X, 0, cd.Z)
			if flat.Magnitude > 0.001 then
				hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit)
			end
			hrp.AssemblyAngularVelocity = Vector3.zero
			-- ⚠️ [2026-09-08] 이동 무버·잔류 속도도 클라에서 지운다.
			--   [증상] 건틀렛 돌진을 야드 밖으로 쓰면 돌진이 영구히 이어졌다.
			--     야드 이탈 → 툴 회수 → GauntletScript 사망 → finishDash 미호출.
			--   [왜 서버만으론 부족한가] 위 주석과 같은 이유다 — 네트워크 오너가 클라라
			--     서버가 지운 속도를 다음 프레임에 클라가 덮어쓴다.
			--     실제로 방향 굳음도 이 자리에서 고쳐야 잡혔다.
			--   ⚠️ 이름 목록으로 거르지 않는다. 캐릭터에 붙은 이동 무버를 전부 지운다 —
			--     새 스킬이 생겨도 자동으로 커버된다.
			hrp.AssemblyLinearVelocity = Vector3.zero
			for _, d in ipairs(char:GetDescendants()) do
				if d:IsA("LinearVelocity") or d:IsA("BodyVelocity")
				   or d:IsA("VectorForce") or d:IsA("BodyForce") then
					d:Destroy()
				end
			end
						--   무기 4종(ClassicSword · DragonFireSword · HammerHigh · Gauntlet)이
			--   장착 중 RightHand.Transparency = 1 로 손을 숨기고 Unequipped 에서 되돌린다.
			--   툴이 Destroy 되면 그 복원이 실행되지 않아 팔이 사라진 채 남는다.
			--   ⚠️ 서버(RoundStateResetServer)에도 같은 처리가 있지만 그건 로비 전환·
			--     무기 회수 때만 돈다. '무기 교체'는 여기서만 잡힌다 — 짝으로 유지할 것.
-- ✨ [2026-09-08] 무기가 남긴 시각 이펙트를 걷어낸다.
			--   [증상] 다이아 표식(유리판·보석)·사쿠라 오라(꽃가루)가 무기를 바꿔도 남았다.
			--   [원인] 두 무기 모두 정리를 Tool.Unequipped 에만 걸어뒀다. 툴이 Destroy 되면
			--     그 이벤트가 안 온다. Destroying/AncestryChanged 로 자체 정리를 시도했지만
			--     Destroy() 가 툴 안 스크립트를 즉시 정지시켜 그 핸들러도 안 돌았다(실측).
			--   [해결] 생성 시점에 이름을 붙이고 밖에서 그 이름으로 걷어낸다.
			--     "생성할 때 표식만 켜면 소비처를 안 고쳐도 된다" 의 적용이다.
			--   ⚠️ 표식은 workspace 직속, 오라는 캐릭터 팔다리 — 두 곳을 모두 훑는다.
			for _, d in ipairs(workspace:GetChildren()) do
				if d.Name == "_WeaponFx_DiamondMark" then d:Destroy() end
			end
			for _, d in ipairs(char:GetDescendants()) do
				if d.Name == "_WeaponFx_SakuraAura" then d:Destroy() end
			end
						for _, nm in ipairs({
				"RightHand", "LeftHand", "Right Arm", "Left Arm",
				"RightLowerArm", "LeftLowerArm", "RightUpperArm", "LeftUpperArm",
			}) do
				local p = char:FindFirstChild(nm)
				if p and p:IsA("BasePart") and p.Transparency > 0 then
					p.Transparency = 0
				end
			end
		end
		print(string.format(
			"[WeaponUICleanup] %s 클라 방향 복구 | AutoRotate %s → true | look(%.2f, %.2f, %.2f) → (%.2f, %.2f, %.2f)",
			toolName, tostring(beforeAuto),
			beforeLook.X, beforeLook.Y, beforeLook.Z,
			hrp and hrp.CFrame.LookVector.X or 0,
			hrp and hrp.CFrame.LookVector.Y or 0,
			hrp and hrp.CFrame.LookVector.Z or 0))
	end
end

-- 툴이 백팩/캐릭터에서 사라지면 그 무기의 GUI 를 지운다.
--   ⚠️ AncestryChanged 를 쓴다. Destroying 은 툴 내부 스크립트와 같은 운명이라
--      늦거나 아예 안 온다. 여기는 툴 밖이므로 안전하다.
--   ⚠️ 한 프레임 양보한다 — 교체는 '이전 것 제거 → 새 것 추가' 순인데, 같은 프레임에
--      지우면 새 툴이 막 만든 GUI 를 지울 위험이 있다. defer 후 툴 존재를 재확인한다.
-- ⚠️ [2026-09-07] 중복 연결 방지.
--   hookContainer 가 세 경로로 불린다 — 초기 1회 / CharacterAdded / ChildAdded(Backpack).
--   Backpack 은 리스폰마다 새로 생겨서 뒤의 둘이 같은 툴을 또 잡았고,
--   실측상 정리가 3번씩 돌았다(로그 3연속 + CFrame 3회 대입).
--   결과는 멱등이라 무해했지만 낭비이고 로그가 읽기 어려워진다.
local watched = setmetatable({}, {__mode = "k"})   -- 툴이 사라지면 자동 정리

local function watchTool(tool)
	if not tool:IsA("Tool") then return end
	if not GUI_OF_TOOL[tool.Name] then return end
	if watched[tool] then return end
	watched[tool] = true
	local name = tool.Name
	tool.AncestryChanged:Connect(function(_, parent)
		if parent then return end   -- 아직 어딘가에 붙어 있다 (장착/해제 이동)
		task.defer(function()
			-- 같은 이름의 툴이 다시 들어와 있으면 그건 새 무기다. 건드리지 않는다.
			local char = player.Character
			local bp   = player:FindFirstChildOfClass("Backpack")
			if (char and char:FindFirstChild(name)) or (bp and bp:FindFirstChild(name)) then
				return
			end
			destroyGuisFor(name)
		end)
	end)
end

local function hookContainer(container)
	if not container then return end
	for _, d in ipairs(container:GetChildren()) do watchTool(d) end
	container.ChildAdded:Connect(watchTool)
end

hookContainer(player:FindFirstChildOfClass("Backpack"))
player.CharacterAdded:Connect(function(char)
	hookContainer(char)
	task.defer(function() hookContainer(player:FindFirstChildOfClass("Backpack")) end)
end)
if player.Character then hookContainer(player.Character) end
player.ChildAdded:Connect(function(c)
	if c:IsA("Backpack") then hookContainer(c) end
end)

local function restoreMetaUIs()
	local n = 0
	for _, gui in ipairs(closedByMe) do
		if gui and gui.Parent then
			gui.Enabled = true
			n = n + 1
		end
	end
	closedByMe = {}
	if n > 0 then print("[WeaponUICleanup] 인터미션 — 메타 UI " .. n .. "개 복구") end
end
-- 라운드 경계(인터미션)마다 무조건 정리
local phaseEvent = ReplicatedStorage:WaitForChild("RoundPhaseEvent")
phaseEvent.OnClientEvent:Connect(function(phase)
	currentPhase = phase
	if phase == "intermission" then
		cleanup("intermission")
		restoreMetaUIs()
		destroyWeaponSkillGuis()
	elseif phase == "stage1" or phase == "stage2" then
		closeMetaUIs(true)
	end
end)

-- 이벤트를 놓쳐도 서버가 남긴 속성으로 따라잡는다(HUD 와 같은 이중 안전장치).
ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(function()
	currentPhase = ReplicatedStorage:GetAttribute("RoundPhase") or "intermission"
end)

-- 리스폰 시에도 안전 정리 (백팩 복구 등)
player.CharacterAdded:Connect(function()
	task.wait(0.5)
	cleanup("respawn")
	-- [RESPAWN-REVIVE] 라운드 중 리스폰이면 되살아난 메타 UI 를 다시 닫는다.
	--   ChildAdded 감시로도 잡히지만, 감시 연결 전에 복제된 것까지 확실히 훑는다.
	if inRound() then closeMetaUIs(false) end
end)


print("🧼 WeaponUICleanupClient 활성화 (라운드 경계 무기 UI 강제 정리)")
