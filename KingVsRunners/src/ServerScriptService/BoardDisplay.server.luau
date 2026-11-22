--[[
	BoardDisplay — 로비 물리 리더보드 4종을 LeaderboardService 데이터로 갱신.

	대상: Workspace 직속 모델 중 Attribute "LeaderboardId" 를 가진 것.
	      (LB_KingWins / LB_Tyrant / LB_RunnerWins / LB_Kingslayer)

	원래 에셋의 TimePlayedClass 를 대체한다. 차이점:
	  · 보드마다 서로 다른 OrderedDataStore 를 읽는다 (에셋은 전역 1개 고정이었음)
	  · 스코어 업데이트를 하지 않는다 — 기록은 RoundSystem.endRound 가 단독 담당
	  · 시즌 구분은 SeasonConfig 를 따른다 (배틀패스와 공유)

	DataStore 부하: 보드 4개 × (갱신주기 1회). GetSortedAsync 는 읽기라 쿼터가 넉넉하지만
	주기를 짧게 잡을 이유가 없어 기본 120초. 라운드가 3분 안팎이라 라운드당 1~2회 갱신된다.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeasonConfig = require(ReplicatedStorage:WaitForChild("SeasonConfig"))
local LeaderboardService = require(game:GetService("ServerScriptService"):WaitForChild("LeaderboardService"))

-- ⚠️ [BOARD-INTERVAL] 120 → 60.
--    라운드 종료 즉시 갱신을 제거했으므로(RoundSystem) 주기가 유일한 갱신 경로다.
--    GetSortedAsync 는 Ordered List 한도가 작다(솔로 5+2=7회/분, 8명 5+16=21회/분).
--    보드 4종 × 60초 = 분당 4회라 한도 안에 안전하게 들어간다.
--    ⚠️ 이보다 더 줄이면(예: 30초) 8회/분이 되어 솔로 한도(7)를 넘는다.
local UPDATE_INTERVAL = 60     -- 보드 갱신 주기(초)
local TOP_N           = 10
local BLANK_PHOTO     = "rbxassetid://2319523583"   -- 에셋 기본 실루엣 아이콘

-- 값 표시 포맷: 1234 -> "1.2K"
local function fmt(v)
	v = tonumber(v) or 0
	if v >= 1000000 then return string.format("%.1fM", v/1000000) end
	if v >= 1000 then return string.format("%.1fK", v/1000) end
	return tostring(v)
end

-- ── 이름/썸네일 캐시 (서버 전역) ─────────────────────────────
local nameCache, thumbCache = {}, {}

local function getName(userId)
	if nameCache[userId] then return nameCache[userId] end
	local ok, res = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local v = ok and res or "Unknown"
	nameCache[userId] = v
	return v
end

local function getThumb(userId)
	if thumbCache[userId] then return thumbCache[userId] end
	local ok, res = pcall(function()
		return Players:GetUserThumbnailAsync(userId,
			Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	local v = ok and res or BLANK_PHOTO
	thumbCache[userId] = v
	return v
end

-- ── 보드 1개 갱신 ────────────────────────────────────────────
local function clearBoard(gui)
	for _, folderName in ipairs({"Names", "Score", "Photos"}) do
		local f = gui:FindFirstChild(folderName)
		if f then
			for _, item in ipairs(f:GetChildren()) do item.Visible = false end
		end
	end
end

local function renderBoard(model)
	local boardId = model:GetAttribute("LeaderboardId")
	local sb = model:FindFirstChild("ScoreBlock")
	if not sb then return end
	local gui      = sb:FindFirstChild("Leaderboard")
	local noData   = sb:FindFirstChild("NoDataFound")
	if not gui then return end

	local rows = LeaderboardService.getTop(boardId, TOP_N)

	-- 조회 실패(nil)와 기록 없음(빈 배열)을 구분: 실패 시 기존 표시를 유지해 깜빡임 방지
	if rows == nil then
		warn(string.format("[BoardDisplay] %s 조회 실패 — 이전 표시 유지", tostring(boardId)))
		return
	end

	local hasData = #rows > 0
	gui.Enabled = hasData
	if noData then
		noData.Enabled = not hasData
		-- ⚠️ NoDataFound 의 SurfaceGui 를 켜도 내부 라벨(Warning)이 Visible=false 로
		--    저장돼 있어 "빈 판"만 보였다. 기록이 없을 때 clearBoard 가 Leaderboard 쪽
		--    라벨을 전부 숨기므로, 결과적으로 보드에 아무것도 안 그려졌다.
		--    → 켜고 끌 때 내부 라벨 가시성도 함께 맞춘다(파일 저장값에 의존하지 않게).
		for _, x in ipairs(noData:GetDescendants()) do
			if x:IsA("TextLabel") or x:IsA("ImageLabel") then x.Visible = not hasData end
		end
	end
	if not hasData then
		clearBoard(gui)
		return
	end

	clearBoard(gui)
	local names  = gui:FindFirstChild("Names")
	local scores = gui:FindFirstChild("Score")
	local photos = gui:FindFirstChild("Photos")

	for rank, entry in ipairs(rows) do
		local nl = names  and names:FindFirstChild("Name"..rank)
		local sl = scores and scores:FindFirstChild("Score"..rank)
		local pl = photos and photos:FindFirstChild("Photo"..rank)

		local uid = entry.userId
		-- 스튜디오 테스트 플레이어는 음수 UserId 를 받는다
		local displayName = (uid and uid > 0) and getName(uid) or "Studio Tester"

		if nl then nl.Text = displayName; nl.Visible = true end
		if sl then sl.Text = fmt(entry.value); sl.Visible = true end
		if pl then
			pl.Image = (uid and uid > 0) and getThumb(uid) or BLANK_PHOTO
			pl.Visible = true
		end

		-- 1위는 받침대 아바타에도 반영 (아바타를 쓰는 보드만)
		if rank == 1 then
			local fpa = model:FindFirstChild("First Place Avatar")
			-- 🚦 [2026-09-06] 1위가 그대로면 아바타를 다시 적용하지 않는다.
			--   [왜] 60초마다 renderBoard 가 돌면서 같은 uid 로 SetRigHumanoidDescription 을
			--     반복 호출했다. 아바타 적용은 액세서리·메시·텍스처를 로드하는 무거운 작업이라,
			--     바뀐 게 없는데 치를 이유가 없다.
			--   ⚠️ 이 가드는 지연의 원인이 아바타든 아니든 옳다 — 같은 값을 다시 쓰는 건 낭비다.
			--     원인 확정은 위 ⏱️ 계측 로그로 따로 한다.
			--   ⚠️ 보드별로 따로 기억한다. 보드가 4개고 1위가 각각 다르다.
			--   ⚠️ return 을 쓰면 안 된다. 여기는 순위 루프 안이라 함수 전체가 끊겨
			--     2위 이하가 렌더링되지 않는다(작성 중 실제로 넣었다가 잡았다).
			--     조건으로 감싸서 '아바타 적용만' 건너뛴다.
			local lastKey = boardId and ("_lastAvatarUid_" .. tostring(boardId))
			local avatarChanged = not (lastKey and model:GetAttribute(lastKey) == uid)
			if avatarChanged and lastKey then model:SetAttribute(lastKey, uid) end

			local rigModule = fpa and fpa:FindFirstChild("PlayAnimationInRig")
			if avatarChanged and rigModule then
				task.spawn(function()
					local ok, mod = pcall(require, rigModule)
					if not ok then
						warn(string.format("[BoardDisplay] %s 아바타 모듈 로드 실패: %s", tostring(boardId), tostring(mod)))
						return
					end
					if not (mod and mod.SetRigHumanoidDescription) then
						warn(string.format("[BoardDisplay] %s 아바타 모듈에 SetRigHumanoidDescription 없음", tostring(boardId)))
						return
					end
					-- ⏱️ [진단 2026-09-06] 아바타 적용 비용 측정.
					--   [왜] 17:19:55 에 서버 573ms / 클라 574ms 지연이 아바타 적용 두 줄
					--     사이에 정확히 끼어 있었다. 다만 17:20:58 의 적용에서는 지연이 없어
					--     '항상 원인'은 아니다 — 추측 대신 실제 소요를 남긴다.
					--   ⚠️ 원인 확정 후 삭제할 것.
					local t0 = os.clock()
					local ok2, err2 = pcall(function()
						mod.SetRigHumanoidDescription(uid > 0 and uid or 1)
					end)
					local costMs = (os.clock() - t0) * 1000
					if costMs > 100 then
						warn(string.format("⏱️ [BoardDisplay] %s 아바타 적용 %.0fms — 서버 지연 용의자",
							tostring(boardId), costMs))
					end
					if ok2 then
						print(string.format("👑 [BoardDisplay] %s 1위 아바타 적용: %s (%d)", tostring(boardId), displayName, uid))
					else
						warn(string.format("[BoardDisplay] %s 아바타 적용 실패: %s", tostring(boardId), tostring(err2)))
					end
				end)
			end
		end
	end
end

-- ── 시즌 표기 ────────────────────────────────────────────────
local function setSeasonLabel(model)
	local ubt = model:FindFirstChild("UpdateBoardTimer")
	local tl = ubt and ubt:FindFirstChild("Timer") and ubt.Timer:FindFirstChild("TextLabel")
	if tl then
		tl.Text = string.upper(SeasonConfig.id())   -- "SEASON1"
	end
end

-- ── 부팅 ─────────────────────────────────────────────────────
local boards = {}
for _, obj in ipairs(workspace:GetChildren()) do
	if obj:GetAttribute("LeaderboardId") then
		table.insert(boards, obj)
		setSeasonLabel(obj)
	end
end

print(string.format("📊 BoardDisplay 시작 — 보드 %d개 (%s, 갱신 %ds)",
	#boards, SeasonConfig.id(), UPDATE_INTERVAL))

if #boards > 0 then
	task.spawn(function()
		while true do
			for _, model in ipairs(boards) do
				if model.Parent then
					local ok, err = pcall(renderBoard, model)
					if not ok then
						warn("[BoardDisplay] "..tostring(model:GetAttribute("LeaderboardId")).." 렌더 오류: "..tostring(err))
					end
				end
				task.wait(0.5)   -- 보드 간 간격 — DataStore 요청이 한꺼번에 몰리지 않게
			end
			task.wait(UPDATE_INTERVAL)
		end
	end)
end
