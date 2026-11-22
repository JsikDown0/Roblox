-- WeaponAnimPrewarm : 서버측 무기 애니메이션 캐시 예열
--
-- [이유] 클라는 AssetPreloadClient 가 예열하지만 **서버는 안 한다.**
--   서버가 처음 LoadAnimation 하면 AnimationTrack.Length 가 ~0.4초간 0 으로 읽힌다
--   (FrostDragonPrewarm:4 주석에 이미 기록된 관측이다).
--   길이 0 인 트랙에 Play() 를 걸면 아무 일도 안 일어나고, 그대로 끝난다.
--
-- [증상 2026-09-14] 봇 카타나 카운터에서 칼날 발광과 효과음은 나오는데 자세 애니만 안 나왔다.
--   enterCounter 는 LoadAnimation 직후 바로 Play 한다 — 서버가 그 에셋을 처음 만나는 순간이면
--   길이가 아직 0 이라 재생이 통째로 누락된다. 발광·사운드는 그 블록 밖이라 정상이었다.
--   ⚠️ 봇 전용이 아니다. 유저도 서버측 트랙이 같은 경로를 탄다.
--   ⚠️ 진단 중 "CounterAnim 은 R15 전용" 이라는 오진이 있었다. Length 로 리그 호환을 판정하면
--     안 된다 — 그건 '다운로드가 끝났나'를 반영한다. 예열 후 R6 에서 정상 길이가 나왔다.
--
-- [왜 전수인가] 이름 목록으로 고르면 새 무기가 추가될 때마다 샌다.
--   ServerStorage 의 Animation 인스턴스를 전부 훑어 AnimationId 로 중복 제거한다.
--   무기를 늘려도 이 파일은 안 고쳐도 된다 — "이름 목록보다 결과 보장".
--
-- [형태] FrostDragonPrewarm 의 선례를 따르되 한 가지만 다르다:
--   거기서는 애니 하나마다 순차로 기다린다(2개라 문제없다). 여기는 27개라
--   **전부 LoadAnimation 한 뒤 한 번만 대기**한다. 순차로 하면 부팅이 초 단위로 늘어난다.
--
-- ⚠️ FrostDragonPrewarm 과 대상이 겹친다(TaggerItem 의 FlapAnim/EndAnim).
--   중복 예열은 무해하지만, 그쪽을 지울지는 별도 판단이다. 지금은 둘 다 둔다 —
--   FrostDragon 은 '마지막 포즈 고정'이라는 자기만의 타이밍 요구가 있다.
-- ⚠️ 예열은 캐시만 데운다. 애니가 리그와 안 맞아 안 나오는 경우는 이걸로 안 풀린다.
--   그때는 Length 가 예열 후에도 0 으로 남으므로 아래 warn 에 찍힌다 — 판별에 쓸 것.

local ServerStorage = game:GetService("ServerStorage")

local SCAN_FOLDERS = { "RunnerItem", "TaggerItem" }
local WAIT_LIMIT   = 6      -- 전체 대기 상한(초)
local POLL         = 0.05

task.spawn(function()
	-- 1) 고유 AnimationId 수집
	local ids, order = {}, {}
	for _, name in ipairs(SCAN_FOLDERS) do
		local root = ServerStorage:FindFirstChild(name)
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("Animation") and d.AnimationId ~= "" and not ids[d.AnimationId] then
					ids[d.AnimationId] = d.Name
					order[#order + 1] = d.AnimationId
				end
			end
		end
	end
	if #order == 0 then
		warn("[AnimPrewarm] 예열할 애니가 없다 — SCAN_FOLDERS 확인")
		return
	end

	-- 2) 더미 Animator 에 전부 로드 (한 번에)
	local holder = Instance.new("Model")
	holder.Name = "_WeaponAnimPrewarm"
	local ac = Instance.new("AnimationController")
	local an = Instance.new("Animator")
	an.Parent = ac
	ac.Parent = holder
	holder.Parent = workspace

	local tracks = {}
	local failed = 0
	for _, id in ipairs(order) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		anim.Parent = holder
		local ok, track = pcall(function() return an:LoadAnimation(anim) end)
		if ok and track then
			tracks[id] = track
		else
			failed = failed + 1
			warn(string.format("[AnimPrewarm] LoadAnimation 실패: %s (%s)", ids[id], id))
		end
	end

	-- 3) 전부 Length 가 잡힐 때까지 한 번만 대기
	local t0 = os.clock()
	while os.clock() - t0 < WAIT_LIMIT do
		local pending = 0
		for _, track in pairs(tracks) do
			if track.Length <= 0 then pending = pending + 1 end
		end
		if pending == 0 then break end
		task.wait(POLL)
	end

	-- 4) 결과 보고. ⚠️ 여기 남는 0 은 '캐시 문제가 아닌' 애니다 — 리그 불일치·삭제된 에셋 등.
	local warm, cold = 0, {}
	for id, track in pairs(tracks) do
		if track.Length > 0 then
			warm = warm + 1
		else
			cold[#cold + 1] = string.format("%s(%s)", ids[id], id)
		end
	end
	holder:Destroy()

	print(string.format("🎞️ [AnimPrewarm] 서버 무기 애니 예열 %d/%d (%.2fs)%s",
		warm, #order, os.clock() - t0, failed > 0 and (" / 로드실패 " .. failed) or ""))
	if #cold > 0 then
		warn("[AnimPrewarm] ⚠️ 예열 후에도 길이 0 — 캐시 문제가 아니다: " .. table.concat(cold, ", "))
	end
end)
