-- 👊 PushToolDebug — 푸시툴 즉시 지급 + 장착
-- ⚠️ 릴리즈 전 삭제 대상.
--
-- [왜] 차징 애니 홀드·연출 검증에 매번 2단계까지 기다리면 라운드당 3분이 든다.
--   검증 대상은 애니/연출뿐이고 HP 재산정·점령·곡사포는 무관하므로
--   Stage2 트리거 전체를 재현하지 않고 툴만 손에 쥐여준다.
--
-- ⚠️ TestCommands 에도 같은 /push 가 있으나(1672행) 그 스크립트는 Disabled 다.
--   켜면 2200줄이 통째로 활성화되고 릴리즈 때 되돌리는 걸 잊기 쉬워,
--   필요한 것만 떼어 독립시킨다.
--
-- ⚠️ 스킨은 적용하지 않는다. 연출 검증용이라 기본 글러브가 오히려 낫다
--   (차징 FX 가 HandColor 로 손 색을 덮으므로 스킨색과 섞이면 판단이 흐려진다).
--   스킨까지 보려면 TestCommands 의 /push 를 쓸 것.

local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ⚠️ 다른 디버그 시스템과 동일한 판별 방식.
local DEV_IDS = {
	[9228200642] = true,   -- melonberrystrong
}
local function isDev(player)
	if RunService:IsStudio() then return true end
	return DEV_IDS[player.UserId] == true
end

local function findTool(player)
	local ch = player.Character
	local bp = player:FindFirstChild("Backpack")
	return (ch and ch:FindFirstChild("PushTool"))
		or (bp and bp:FindFirstChild("PushTool"))
end

local function givePush(player)
	local tmpl = RS:FindFirstChild("PushTool")
	if not tmpl then
		warn("👊 [PushDebug] ReplicatedStorage.PushTool 템플릿 없음")
		return
	end
	local ch  = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local bp  = player:FindFirstChild("Backpack")
	if not (ch and hum and bp) then
		warn("👊 [PushDebug] 캐릭터/Humanoid/Backpack 없음 — 리스폰 후 다시 시도")
		return
	end

	-- 중복 지급 방지: 기존 것은 버리고 새로 준다(수정한 스크립트가 반영되도록).
	local old = findTool(player)
	if old then old:Destroy() end

	local tool = tmpl:Clone()
	tool.Parent = bp

	-- ⚠️ Backpack 에만 넣으면 안 된다.
	--   PushTool.Client 는 Tool.Equipped 에서 애니(ChargeR6/R15, Attack)를
	--   로드하고 스킬 버튼 UI 를 만든다. 장착까지 해야 검증이 가능하다.
	task.wait(0.15)
	local ok = pcall(function() hum:EquipTool(tool) end)
	print(string.format("👊 [PushDebug] %s 푸시툴 지급%s",
		player.Name, ok and " + 장착" or " (장착 실패 — 백팩에 있음)"))
end

local function removePush(player)
	local t = findTool(player)
	if t then
		t:Destroy()
		print("👊 [PushDebug] " .. player.Name .. " 푸시툴 회수")
	else
		print("👊 [PushDebug] 들고 있는 푸시툴 없음")
	end
end

-- 🖐️ [TEST 2026-09-11] 광역 그랩 검증용 — 표적 배치.
--   [왜] 그랩의 최대 위험은 물리다(여러 캐릭터 동시 이동 — 봇 넉백 솟구침과 같은 계열).
--     로비에는 끌어올 대상이 없어서 검증이 안 된다.
--   ⚠️ 로비 더미는 isValidTarget 의 LobbyDummy 분기를 이미 통과한다 — 별도 처리 불필요.
--   ⚠️ 그랩 자체에는 라운드 가드가 없다(로비 훈련장에서 정상 사용). 이 커맨드는
--     '우회 스위치'가 아니라 단순 표적 배치다. 릴리즈 때 이것만 지우면 된다.
local function grabTest(player)
    local ch = player.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not hrp then
        warn("🖐️ [GrabTest] 캐릭터 없음")
        return
    end

    -- 더미를 킹 앞 25 stud 에 옆으로 벌려 세운다.
    --   ⚠️ 한 점에 모으면 그랩이 아니라 '이미 뭉친 상태'를 테스트하게 된다.
    --     실전은 흩어진 러너를 끌어오는 것이므로 벌려 놓는 게 맞다.
    local look = hrp.CFrame.LookVector
    local fwd = Vector3.new(look.X, 0, look.Z).Unit
    local right = Vector3.new(-fwd.Z, 0, fwd.X)
    local n = 0
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m.Name:match("^LobbyTrainingDummy") then
            local r = m:FindFirstChild("HumanoidRootPart")
            if r then
                n = n + 1
                local off = (n - 2.5) * 9           -- -13.5 / -4.5 / +4.5 / +13.5
                local dest = hrp.Position + fwd * 25 + right * off
                r.AssemblyLinearVelocity = Vector3.zero
                r.CFrame = CFrame.new(dest + Vector3.new(0, 3, 0), hrp.Position)
            end
        end
    end
    print(string.format("🖐️ [GrabTest] 더미 %d체 배치 (앞 25 stud, 간격 9) — Q 로 끌어와 볼 것", n))
end

local function onChat(player, msg)
	if not isDev(player) then return end
	local m = msg:lower():match("^%s*(.-)%s*$")   -- 앞뒤 공백 제거

	-- 🔀 [2026-09-11] `/push` 를 여기서 처리하지 않는다.
	--   [왜] 이 스크립트가 만들어진 이유는 "TestCommands 가 Disabled 라서"였는데(헤더 주석),
	--     지금 TestCommands 는 살아 있고 /push 를 스킨까지 입혀 처리한다.
	--     둘 다 발화하면 이쪽이 나중에 돌면서 기존 툴을 Destroy 해 **스킨이 지워졌다.**
	--     (비슈누만 남던 건 그게 툴 스킨이 아니라 캐릭터 VishnuAura 속성이라서다)
	--   [지금] /push = TestCommands (스킨 포함) / /pushplain = 여기 (기본 글러브)
	--   ⚠️ 기본 글러브가 필요한 경우: 차징 FX 가 손 색을 덮으므로 스킨색과 섞이면
	--     연출 판단이 흐려진다(헤더 주석 참조).
	if m == "/pushplain" then
		givePush(player)
	elseif m == "/push off" then
		removePush(player)
	elseif m == "/grab" then
		grabTest(player)
	elseif m == "/hero" then
		-- 🤖 [TEST 2026-09-12] 히어로봇 무기 진단 토글.
		--   DragonFireSword 의 봇 타격 경로가 서버에 흔적을 안 남겨서 붙였다.
		--   ⚠️ 릴리즈 전 삭제. 무기 스크립트의 _G.HeroWeaponDiag 분기와 한 짝이다.
		_G.HeroWeaponDiag = not _G.HeroWeaponDiag
		print("🔥 [HeroDiag] " .. (_G.HeroWeaponDiag and "ON — 히어로 타격 로그 출력" or "OFF"))
	elseif m == "/ws" then
		-- 🏃 [TEST 2026-09-12] 지금 누가 이동속도를 걸고 있나.
		--   [읽는 법] base 14 × [HammerSlam=0.00] = 0.0 (실제 0.0)
		--     실제값이 계산값과 다르면 = 관리자를 안 거치는 시스템이 덮어썼다.
		--   ⚠️ 릴리즈 전 삭제.
		local ch = player.Character
		print("🏃 [WS] " .. player.Name .. ": " ..
			((_G.WalkSpeed and _G.WalkSpeed.debug(ch)) or "WalkSpeedManager 없음"))
		for _, mdl in ipairs(workspace:GetChildren()) do
			if mdl:IsA("Model") and mdl:GetAttribute("HeroRunner") then
				print("   " .. mdl.Name .. ": " .. (_G.WalkSpeed and _G.WalkSpeed.debug(mdl) or "-"))
			end
		end
	elseif m:match("^/hw%f[%s\0]") or m:match("^/heroweapon%f[%s\0]") then
		-- ⚠️ [2026-09-12 수정] 예전 조건 `m:sub(1,7) == "/hw"` 는 영원히 거짓이었다.
		--   7글자를 잘라 3글자와 비교했다("/hw katana" → "/hw kat" ≠ "/hw").
		--   커맨드가 한 번도 안 먹었고, 로그도 안 남아 원인이 안 보였다.
		--   %f[%s\0] = 공백 또는 문자열 끝 — "/hwfoo" 같은 건 안 걸린다.
		-- 🗡️ [TEST 2026-09-12] 히어로 무기 강제 지정. 랜덤을 덮어쓴다.
		--   [왜] 특정 무기의 봇 동작을 검증하려면 그 무기가 나올 때까지 판을 돌려야 했다.
		--     6종 중 4개를 뽑으니 원하는 무기가 안 나오는 판이 흔하다.
		--   [쓰기] /hw katana   /hw high   /hw low   /hw fire   /hw sakura   /hw classic
		--          /hw off      → 랜덤으로 복귀
		--   ⚠️ 릴리즈 전 삭제. Stage2TriggerSystem 의 _G.ForceHeroWeapon 분기와 한 짝이다.
		local arg = m:match("^/%a+%s+(%S+)")
		local ALIAS = {
			katana = "KatanaSword2",  kat = "KatanaSword2",
			high   = "HammerHigh",    hh  = "HammerHigh",
			low    = "HammerLow",     hl  = "HammerLow",
			fire   = "DragonFireSword", df = "DragonFireSword",
			sakura = "SakuraBlade",   sk  = "SakuraBlade",
			classic = "ClassicSword", cs  = "ClassicSword",
		}
		if not arg or arg == "off" or arg == "random" then
			_G.ForceHeroWeapon = nil
			print("🗡️ [HeroWeapon] 랜덤으로 복귀")
		else
			local pick = ALIAS[arg] or arg   -- m 이 이미 lower 를 거쳤다
			local pool = game:GetService("ServerStorage"):FindFirstChild("RunnerItem")
			if pool and pool:FindFirstChild(pick) then
				_G.ForceHeroWeapon = pick
				print("🗡️ [HeroWeapon] 강제: " .. pick .. " (다음 2단계부터 전원 이 무기)")
			else
				warn("🗡️ [HeroWeapon] 없는 무기: " .. tostring(pick)
					.. "  |  katana / high / low / fire / sakura / classic / off")
			end
		end
	elseif m == "/pushhelp" then
		print("👊 [PushDebug] /push (TestCommands·스킨 포함) · /pushplain (기본 글러브) · /push off (회수) · /grab (그랩 표적 배치)")
	end
end

local function hook(player)
	player.Chatted:Connect(function(msg) onChat(player, msg) end)
end
for _, p in ipairs(Players:GetPlayers()) do hook(p) end
Players.PlayerAdded:Connect(hook)

print("👊 PushToolDebug 준비 (/pushplain, /push off, /grab) — ⚠️ 릴리즈 전 삭제")
