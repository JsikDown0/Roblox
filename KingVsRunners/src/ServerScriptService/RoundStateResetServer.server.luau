-- RoundStateResetServer — 로비로 돌아갈 때 캐릭터 상태를 무조건 되돌린다.
--
-- [왜 endRound 안전망으로 부족한가] 실측(2026-09-06):
--   18:02:49.665  라운드 종료 → endRound 안전망이 WalkSpeed 8→16 복구 ✅
--   18:02:58.748  스핀 재사용 → 16→8 (툴이 아직 남아 있었다)
--   복구 없음 → 로비에서 이속 8 로 굳음
--   endRound 는 이미 지나갔고, 그 뒤 로비 진입까지 복구를 돌릴 계기가 없었다.
--
-- [무엇이 다른가] 이 스크립트는 '라운드가 끝나는 순간'이 아니라
--   '로비 상태가 되는 순간'을 본다. 종료와 로비 사이에 무슨 일이 있었든 마지막에 한 번 쓸어준다.
--   ⚠️ HammerScript 에 라운드 밖 시작 차단을 넣었지만, 그건 해머 하나에만 적용된다.
--     같은 창을 통과하는 스킬이 또 생기면 여기서 잡힌다 — 목록이 아니라 결과를 보장하는 방식.
--
-- ⚠️ 값을 '스냅샷'하지 않고 기본값으로 되돌린다. 스냅샷은 이미 오염된 값을 저장할 위험이 있다
--   (감속된 8 을 '원래 값'으로 기억하는 사고). 로비에는 버프가 없어야 정상이다.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_WALKSPEED = 16
local DEFAULT_JUMPPOWER = 50
local DEFAULT_JUMPHEIGHT = 7.2   -- StarterPlayer.CharacterJumpHeight 실측값 (2026-09-13)
local DIAG = false  -- ⚠️ [2026-09-08] 방향 굳음 원인 확정되어 끔.
-- [무엇이 원인이었나] 서버가 아니라 클라였다. 캐릭터 네트워크 오너가 클라이언트라
--   서버가 AutoRotate/CFrame 을 써도 다음 프레임에 덮어써진다. 서버 로그는
--   AutoRotate=true / 기울기 0 으로 '정상' 을 보고했지만 화면은 틀어져 있었다.
--   실제 수정은 WeaponUICleanupClient 의 클라측 복구 + SpinClient 의 툴 소멸 감지.
-- ⚠️ 재발하면 이걸 true 로 켜기 전에 클라 로그("클라 방향 복구")부터 봐라 —
--   그쪽이 AutoRotate 의 진짜 값을 보여준다.

local function resetOne(plr)
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	local before = hum.WalkSpeed
	hum.WalkSpeed  = DEFAULT_WALKSPEED
	hum.JumpPower  = DEFAULT_JUMPPOWER
	-- ⚠️ [2026-09-13] JumpHeight 복구 추가. 이 게임은 UseJumpPower = false 라
	--   위의 JumpPower 대입은 점프에 아무 효과가 없다(실측: 두 속성은 연동되지 않는다).
	--   즉 이 안전망은 지금까지 점프를 한 번도 복구한 적이 없다. 드러나지 않았던 건
	--   JumpHeight 를 0 으로 만드는 시스템이 없었기 때문이고, 오늘 카타나·해머가
	--   실제로 0 을 쓰기 시작했다. JumpPower 줄은 UseJumpPower 가 켜질 경우 대비로 남긴다.
	hum.JumpHeight = DEFAULT_JUMPHEIGHT
	hum.AutoRotate = true
	hum.PlatformStand = false
	char:SetAttribute("Stunned", nil)
	-- ⚠️ [2026-09-13] HammerStunned 가 Humanoid → Character 로 옮겨오면서 이 그물에 들어왔다.
	--   예전엔 Humanoid 속성이라 여기가 닿지 못했고 정리 경로가 0곳이었다.
	char:SetAttribute("HammerStunned", nil)

	-- 👑 [2026-09-15] 킹 몸집 강화 원복.
	--   [증상] 라운드가 끝나도 로비에서 커진 채로 남았다(실측 09-15, ×2.50 도달 판).
	--   [원인] 원복을 RoundSystem 의 **다음 라운드 시작**에만 걸었다. 그 사이의
	--     인터미션·로비 구간이 통째로 비어 있었다.
	--   [왜 여기인가] 이 스크립트가 "로비 진입 시 캐릭터 상태 복구" 담당이고,
	--     WalkSpeed·JumpHeight·PlatformStand 가 이미 같은 이유로 여기 있다.
	--   ⚠️ RoundSystem 쪽 원복은 **지우지 않는다.** 여기 도달하지 못하는 경로
	--     (사망 상태로 라운드 종료 등)가 있으면 그쪽이 받는다 — 이중 그물.
	--   ⚠️ R15 는 normalizeAllPlayers 가 스케일 Value 를 1 로 되돌리지만 그건
	--     다음 라운드 시작이다. 여기서 양쪽 리그를 다 처리해야 로비가 깨끗하다.
	do
		local applied = char:GetAttribute("_KingScaleApplied")
		-- 👑 왕관은 리그와 무관하게 직접 곱했으므로, 리그와 무관하게 직접 되돌린다.
		local cs = char:GetAttribute("_KingCrownScale")
		local crown = char:FindFirstChild("TaggerCrown")
		if crown and cs and cs > 1.001 then
			for _, p in ipairs(crown:GetDescendants()) do
				if p:IsA("BasePart") then p.Size = p.Size / cs end
			end
		end
		char:SetAttribute("_KingCrownScale", nil)

		-- 👑 머리 위 UI 높이도 되돌린다. 안 되돌리면 다음 라운드에 HP 바가 공중에 뜬다.
		--   ⚠️ 원본 값은 확대할 때 _BaseStudsY 속성에 적어뒀다.
		local headPart = char:FindFirstChild("Head")
		if headPart then
			for _, guiName in ipairs({"TaggerHpDisplay", "CcImmuneGui"}) do
				local g = headPart:FindFirstChild(guiName)
				if g and g:IsA("BillboardGui") then
					local base = g:GetAttribute("_BaseStudsY")
					if base then
						g.StudsOffset = Vector3.new(0, base, 0)
						g:SetAttribute("_BaseStudsY", nil)
					end
				end
			end
		end
		if hum.RigType == Enum.HumanoidRigType.R15 then
			for _, n in ipairs({"BodyDepthScale","BodyWidthScale","BodyHeightScale","HeadScale"}) do
				local v = hum:FindFirstChild(n)
				if v then v.Value = 1 end
			end
		elseif applied and applied > 1.001 then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				local step = 1 / applied
				local origin = root.Position
				local snap = {}
				for _, p in ipairs(char:GetDescendants()) do
					if p:IsA("BasePart") then snap[#snap + 1] = { p, p.CFrame } end
				end
				for _, e in ipairs(snap) do
					local p, cf = e[1], e[2]
					p.Size = p.Size * step
					local rel = cf.Position - origin
					p.CFrame = CFrame.new(origin + rel * step) * (cf - cf.Position)
				end
				print(string.format("👑 [KingScale] 로비 원복 ×%.2f → ×1.00 (%s)", applied, plr.Name))
			end
		end
		char:SetAttribute("_KingScaleApplied", nil)
		char:SetAttribute("KingScale", nil)
	end

	-- ⚠️ [2026-09-07] 몸이 돌아간 채로 굳는 문제.
	--   실측: HammerLow 스핀 중 라운드에 끌려가면 캐릭터가 '뒤로 달린다'.
	--   원인은 애니메이션이 아니라 CFrame 이다 — SpinClient:123 이
	--     hum.AutoRotate = false 로 끄고
	--     hrp.CFrame = hrp.CFrame * CFrame.Angles(0, rad(24), 0) 을 매 프레임 돌린다.
	--   툴이 파괴되면 그 루프가 끊겨 '돌다 만 각도'가 그대로 남는다.
	--   AutoRotate=true 로 되돌려도 엔진은 이동 방향으로 다시 정렬해주지 않는다.
	--   ⚠️ 그래서 Action 트랙 검색은 0개가 나온다. 재생 중인 트랙이 애초에 없다.
	--     (WeaponUICleanupClient 의 우선순위 기반 해제로는 이 증상을 못 잡는다)
	-- [무엇을 하나] 기울기만 제거하고 바라보는 방향은 유지한다.
	--   회전각을 0 으로 강제하면 스폰 직후 엉뚱한 쪽을 보게 된다.
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local look = hrp.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		-- ⚠️ [2026-09-07 진단] 무조건 찍는다.
		--   이전 판에서 이 함수가 불렸는지조차 구분이 안 됐다 — WalkSpeed 가 이미 16 이면
		--   아래 조건부 로그가 안 찍혀서, '안 불림' 과 '불렸지만 변화 없음' 이 같아 보였다.
		--   ⚠️ 원인 확정되면 DIAG 를 false 로.
		if DIAG then
			warn(string.format(
				"🔎 [RoundReset] %s | WS %.1f | AutoRotate=%s | look(%.2f, %.2f, %.2f) | 기울기=%.3f",
				plr.Name, before, tostring(hum.AutoRotate),
				look.X, look.Y, look.Z, math.abs(look.Y)))
		end
		if flat.Magnitude > 0.001 then
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat.Unit)
		end
		-- 회전 잔류 속도까지 지운다. 남아 있으면 복구 직후 다시 돈다.
		hrp.AssemblyAngularVelocity = Vector3.zero
	end

	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Anchored then d.Anchored = false end
	end

	-- ⚠️ [2026-09-08] 이동 무버와 잔류 속도를 정리한다.
	--   [증상] 건틀렛 돌진을 야드 밖으로 쓰면 돌진이 영구히 이어졌다.
	--     야드 이탈 판정 → 툴 회수 → GauntletScript 가 통째로 죽어 finishDash 가
	--     못 불린다. 라운드 납치 때와 같은 구조인데, 그때는 WalkSpeed 만 굳었고
	--     여기서는 '미는 힘' 이 남는다.
	--   [왜 위 코드로 안 잡혔나] resetOne 은 WalkSpeed·AutoRotate·PlatformStand 와
	--     '회전' 속도만 되돌린다. 건틀렛은 LinearVelocity 무버로 밀고, 그 무버는
	--     캐릭터에 붙어 있어 툴이 사라져도 계속 남는다 — 별개 채널이다.
	--   [결과 보장 방식] 무기 이름 목록으로 거르지 않는다. 캐릭터에 붙은 이동 무버를
	--     전부 지우고 속도를 0 으로 만든다. 새 스킬이 생겨도 자동으로 커버된다.
	--   ⚠️ 로비에는 이동 무버가 있어야 할 이유가 없다. 라운드 중에는 이 함수가
	--     안 돌므로(RoundPhase 로비 전환 · 체험 무기 회수에서만 호출) 실전에 영향 없다.
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("LinearVelocity") or d:IsA("BodyVelocity")
		   or d:IsA("VectorForce") or d:IsA("BodyForce")
		   or d:IsA("AlignPosition") or d:IsA("BodyPosition") then
			d:Destroy()
		end
	end
	-- ⚠️ hrp 를 다시 잡는다. 위의 local hrp(100행)는 다른 블록 소속이라
	--   여기서 유효하다고 가정하면 안 된다 — nil 이면 조용히 안 돈다.
	local root = char:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end

	-- ✨ [2026-09-08] 무기가 캐릭터에 남긴 이펙트를 걷어낸다.
	--   사쿠라 오라는 '서버' 가 캐릭터 팔다리에 붙인다. 클라에서 지워도 서버 사본이 남아
	--   다시 복제되므로 여기서도 지워야 한다.
	--   ⚠️ 생성 쪽(SakuraBlade.SwordScript.attachOne)이 이름을 붙여준다.
	for _, d in ipairs(char:GetDescendants()) do
		if d.Name == "_WeaponFx_SakuraAura" then d:Destroy() end
	end

	-- 🖐️ [2026-09-08] 숨겨진 손을 되돌린다.
	--   [증상] 건틀렛·푸시툴을 쓰고 나면 오른팔이 사라진 채로 남는다.
	--   [원인] 무기 4종(ClassicSword · DragonFireSword · HammerHigh · Gauntlet)이
	--     장착 중 손끝이 비쳐 보이는 걸 막으려고 RightHand.Transparency = 1 로 숨긴다.
	--     복원은 Tool.Unequipped 안에 있는데, 툴이 Destroy 되면 그 이벤트가 오지 않거나
	--     스크립트가 이미 죽어서 실행되지 않는다 — 오늘 반복해서 본 구조다.
	--   [왜 여기서 고치나] 무기마다 고치면 4곳이고, 5번째 무기가 생기면 또 샌다.
	--     "제외 목록보다 결과 보장" — 로비로 돌아온 캐릭터는 몸이 다 보여야 한다.
	--   ⚠️ 액세서리·의상은 건드리지 않는다. R15 기본 파츠 이름만 훑는다.
	--   ⚠️ 라운드 중에는 이 함수가 안 돈다(로비 전환·체험 무기 회수에서만 호출).
	for _, nm in ipairs({
		"RightHand", "LeftHand", "Right Arm", "Left Arm",
		"RightLowerArm", "LeftLowerArm", "RightUpperArm", "LeftUpperArm",
	}) do
		local p = char:FindFirstChild(nm)
		if p and p:IsA("BasePart") and p.Transparency > 0 then
			p.Transparency = 0
		end
	end
	if math.abs(before - DEFAULT_WALKSPEED) > 0.01 then
		warn(string.format("🧹 [RoundReset] %s WalkSpeed %.1f → %.1f (로비 복귀)",
			plr.Name, before, DEFAULT_WALKSPEED))
	end
end

-- ⚠️ [2026-09-07] 무기가 '라운드 밖에서' 사라지는 경로가 생겨 노출한다.
--   실측: 로비 훈련장에서 HammerLow 스핀 중(WalkSpeed 8) 야드를 벗어나 툴이 회수되면
--         SpinClient 가 툴과 함께 죽어 8 이 그대로 굳었다.
--         18:29:56.558  16.0 → 8.0  En=false   (스핀 시작)
--         18:29:57.034  야드 이탈 → 회수        (복구 로그 없음)
--   이 경로는 RoundPhase 가 안 바뀌므로 아래 리스너가 영영 안 돈다.
--   → 무기를 지우는 쪽이 지우기 '직전'에 이걸 부른다.
--   ⚠️ 새 복구 함수를 만들지 않는다. 같은 규칙이 두 곳에 있으면 한쪽만 고쳐진다.
_G.ResetCharacterState = function(plr)
	pcall(resetOne, plr)
end

ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(function()
	local ph = ReplicatedStorage:GetAttribute("RoundPhase")
	if ph == "stage1" or ph == "stage2" then return end
	for _, plr in ipairs(Players:GetPlayers()) do
		pcall(resetOne, plr)
	end
	-- ⚠️ 지연 재시도 1회. 로비 진입 직전에 걸린 감속이 이 프레임 뒤에 적용될 수 있다.
	task.delay(1.0, function()
		for _, plr in ipairs(Players:GetPlayers()) do
			pcall(resetOne, plr)
		end
	end)
end)

print("🧹 RoundStateResetServer 준비 (로비 진입 시 캐릭터 상태 복구)")
