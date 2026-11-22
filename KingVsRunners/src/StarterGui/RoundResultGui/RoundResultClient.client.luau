local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player   = Players.LocalPlayer
local gui      = script.Parent
local panel    = gui:WaitForChild("Panel")
local scroll   = panel:WaitForChild("PlayerList")
local header   = panel:WaitForChild("Header")
local title    = header:WaitForChild("ResultTitle")
local closeBtn = panel:WaitForChild("CloseBtn")
local roundResultEvent = ReplicatedStorage:WaitForChild("RoundResultEvent")

pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)

local Scaler = require(ReplicatedStorage:WaitForChild("ResponsiveScaler"))
Scaler.applyPanel(panel, {
	baseW = 580, baseH = 460,
	Mobile = { frac = 0.85, minScale = 0.55 },
	PC     = { frac = 0.85, minScale = 0.55 },
})

-- ── 헤더: 타이틀 + 서브타이틀(맥락 한 줄) ──
title.TextScaled = false
title.TextSize   = 24
title.Size       = UDim2.new(1, 0, 0, 36)
title.Position   = UDim2.new(0, 0, 0, 6)

local subtitle = header:FindFirstChild("ResultSubtitle")
if not subtitle then
	subtitle = Instance.new("TextLabel")
	subtitle.Name = "ResultSubtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, -24, 0, 16)
	subtitle.Position = UDim2.new(0, 12, 0, 40)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 13
	subtitle.TextColor3 = Color3.fromRGB(205, 205, 220)
	subtitle.TextTruncate = Enum.TextTruncate.AtEnd
	subtitle.ZIndex = 2
	subtitle.Parent = header
end

-- ═══════════════════════════════════════════════════════════════
-- 🎉 결과 연출
--
-- [왜] 예전 결과창은 카드가 부드럽게 나타나는 게 전부였다. 사운드도 파티클도
--      화면 효과도 없어서 "보고서를 받는 느낌"이었고, 이겼다는 감각이 없었다.
-- ⚠️ 정보 전달은 이미 충분하다. 여기서 더할 것은 '감각'이지 텍스트가 아니다.
-- ═══════════════════════════════════════════════════════════════
local SoundService = game:GetService("SoundService")

-- ⚠️ 전용 승리음이 아직 없어 고급 상자 개봉음을 빌려 쓴다.
--    "좋은 일이 일어났다"는 톤이 이미 이 게임에서 검증된 소리다.
--    ElevenLabs 로 전용 음을 만들면 이 ID 만 갈아끼우면 된다.
local SFX_WIN  = "rbxassetid://100791117505114"
local SFX_LOSE = "rbxassetid://116841971399984"

local function playResultSfx(win)
    local s = Instance.new("Sound")
    s.SoundId = win and SFX_WIN or SFX_LOSE
    s.Volume = win and 2.5 or 1.2   -- 패배는 조용히. 실패를 크게 울리면 불쾌하다
    s.PlaybackSpeed = win and 1.0 or 0.82  -- 패배는 낮은 톤
    s.Parent = SoundService
    s:Play()
    game:GetService("Debris"):AddItem(s, 6)
end

-- 타이틀 임팩트: 크게 들어왔다가 제자리로 (Back easing)
-- ⚠️ TextScaled 를 쓰는 라벨이면 Size 트윈이 안 먹는다. Rotation + TextTransparency 로 대신한다.
local function punchTitle(win)
    if not title then return end
    title.Rotation = win and -6 or 0
    title.TextTransparency = 1
    local info = TweenInfo.new(win and 0.45 or 0.6,
        Enum.EasingStyle.Back, Enum.EasingDirection.Out)
    TweenService:Create(title, info, {
        Rotation = 0,
        TextTransparency = 0,
    }):Play()
end

-- 승리 시 화면 가장자리 금색 발광 (짧게)
local function flashScreen(win)
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    local old = pg:FindFirstChild("_ResultFlash")
    if old then old:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name = "_ResultFlash"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 90   -- 결과 패널보다 뒤
    sg.Parent = pg

    local f = Instance.new("Frame")
    f.Size = UDim2.fromScale(1, 1)
    f.BackgroundColor3 = win and Color3.fromRGB(255, 205, 70)
                             or Color3.fromRGB(20, 25, 40)
    f.BackgroundTransparency = win and 0.55 or 0.4
    f.BorderSizePixel = 0
    f.Parent = sg

    TweenService:Create(f, TweenInfo.new(win and 0.7 or 0.9), {
        BackgroundTransparency = 1,
    }):Play()
    game:GetService("Debris"):AddItem(sg, 1.5)
end

-- 닫기
local function hideResult()
	TweenService:Create(panel, TweenInfo.new(0.25), {BackgroundTransparency = 1}):Play()
	task.delay(0.25, function() panel.Visible = false end)
end
closeBtn.MouseButton1Click:Connect(hideResult)

-- ── 플레이어 카드 (겹침 없는 2행 레이아웃) ──
local CARD_H = 78

local function createCard(stat, index)
	local isMe     = (stat.userId == player.UserId)
	local isTagger = (stat.role == "Tagger")

	local card = Instance.new("Frame")
	card.Name = "Card_" .. index
	card.Size = UDim2.new(1, 0, 0, CARD_H)
	card.BackgroundColor3 = isMe and Color3.fromRGB(46, 34, 74) or Color3.fromRGB(30, 24, 48)
	card.BorderSizePixel = 0
	card.LayoutOrder = index
	card.Parent = scroll
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	if isMe then
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(255, 205, 90)
		st.Thickness = 1.5
		st.Parent = card
	end

	-- 좌측 역할 색 바 (알약형)
	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 4, 1, -18)
	accent.Position = UDim2.new(0, 8, 0, 9)
	accent.BackgroundColor3 = isTagger and Color3.fromRGB(235, 90, 90) or Color3.fromRGB(90, 165, 255)
	accent.BorderSizePixel = 0
	accent.Parent = card
	Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)

	-- 아바타 썸네일
	-- ⚠️ 텍스트만 있으면 누가 누군지 한눈에 안 들어온다(실측 2026-08-23: "잘 안 읽힌다").
	--    얼굴이 있으면 목록에서 자기를 즉시 찾을 수 있다.
	-- ⚠️ GetUserThumbnailAsync 는 yield 한다. 카드 생성 흐름을 막지 않게 spawn 으로 뺀다.
	local av = Instance.new("ImageLabel")
	av.Name = "Avatar"
	av.Size = UDim2.new(0, 52, 0, 52)
	av.Position = UDim2.new(0, 20, 0, 13)
	av.BackgroundColor3 = Color3.fromRGB(22, 18, 30)
	av.BorderSizePixel = 0
	av.Parent = card
	Instance.new("UICorner", av).CornerRadius = UDim.new(1, 0)

	if isMe then
		local avs = Instance.new("UIStroke", av)
		avs.Color = Color3.fromRGB(255, 205, 90)
		avs.Thickness = 2
	end

	if stat.userId then
		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(stat.userId,
					Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and url and av.Parent then av.Image = url end
		end)
	end

	-- 1행: 순위 뱃지
	-- ⚠️ 예전엔 "🏃 Runner" 역할 배지였는데, 이제 이 목록에는 러너만 들어온다.
	--    전원이 같은 글자를 다는 건 공간 낭비이므로 순위(#1, #2...)로 바꾼다.
	--    코인 내림차순 정렬이라 순위가 곧 기여도 서열이다.
	local roleBadge = Instance.new("Frame")
	roleBadge.Size = UDim2.new(0, 40, 0, 24)
	roleBadge.Position = UDim2.new(0, 82, 0, 13)
	roleBadge.BackgroundColor3 = (index == 1) and Color3.fromRGB(210, 165, 40)
	                                          or Color3.fromRGB(45, 110, 210)
	roleBadge.BorderSizePixel = 0
	roleBadge.Parent = card
	Instance.new("UICorner", roleBadge).CornerRadius = UDim.new(0, 6)

	local roleText = Instance.new("TextLabel")
	roleText.Size = UDim2.new(1, 0, 1, 0)
	roleText.BackgroundTransparency = 1
	roleText.Text = "#" .. index
	roleText.TextColor3 = Color3.fromRGB(255, 255, 255)
	roleText.TextSize = 13
	roleText.Font = Enum.Font.GothamBold
	roleText.Parent = roleBadge

	-- 1행: 이름 (아바타 + 순위뱃지 오른쪽)
	-- ⚠️ 좌표 지도: accent 8~12 / 아바타 20~72 / 순위뱃지 82~122 / 이름 132~
	--    하나를 옮기면 뒤 요소도 같이 밀어야 겹치지 않는다.
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -262, 0, 24)
	nameLabel.Position = UDim2.new(0, 132, 0, 13)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = (isMe and "⭐ " or "") .. stat.name
	nameLabel.TextColor3 = isMe and Color3.fromRGB(255, 222, 110) or Color3.fromRGB(228, 228, 235)
	nameLabel.TextSize = 17
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	-- 2행: 상태 (별도 행 — 겹침 없음)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -270, 0, 20)
	statusLabel.Position = UDim2.new(0, 82, 0, 46)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextSize = 13
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	if isTagger then
		-- AI 러너 처치는 Kills(리더보드 집계)에 포함되지 않는다.
		-- 그대로 두면 "코인은 받았는데 Kills 가 0" 으로 보여 버그로 오해되므로 별도 병기.
		local ai = stat.aiKills or 0
		statusLabel.Text = "💀 Kills: " .. (stat.kills or 0) .. (ai > 0 and ("  (+" .. ai .. " bots)") or "")
		statusLabel.TextColor3 = Color3.fromRGB(255, 140, 140)
	elseif stat.kingslayer then
		-- 태거에게 막타를 넣은 러너 — 생존 여부보다 우선 표시 (라운드 MVP 성격)
		statusLabel.Text = "👑 Kingslayer!"
		statusLabel.TextColor3 = Color3.fromRGB(255, 215, 90)
	else
		statusLabel.Text = stat.survived and "✅ Survived" or "💀 Eliminated"
		statusLabel.TextColor3 = stat.survived and Color3.fromRGB(120, 225, 120) or Color3.fromRGB(215, 110, 110)
	end
	statusLabel.Parent = card

	-- 우측 코인 뱃지
	local coinBadge = Instance.new("Frame")
	coinBadge.Size = UDim2.new(0, 112, 0, 50)
	coinBadge.Position = UDim2.new(1, -124, 0.5, -25)
	coinBadge.BackgroundColor3 = Color3.fromRGB(60, 50, 90)
	coinBadge.BorderSizePixel = 0
	coinBadge.Parent = card
	Instance.new("UICorner", coinBadge).CornerRadius = UDim.new(0, 10)

	local coinGrad = Instance.new("UIGradient")
	coinGrad.Color = stat.won
		and ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(255,195,55)), ColorSequenceKeypoint.new(1, Color3.fromRGB(185,105,0))})
		or  ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(92,74,134)), ColorSequenceKeypoint.new(1, Color3.fromRGB(52,42,82))})
	coinGrad.Rotation = 90
	coinGrad.Parent = coinBadge

	local coinTop = Instance.new("TextLabel")
	coinTop.Size = UDim2.new(1, 0, stat.won and 0.56 or 1, 0)
	coinTop.BackgroundTransparency = 1
	coinTop.Text = "💰 +" .. (stat.coins or 0)
	coinTop.TextColor3 = Color3.fromRGB(255, 248, 190)
	coinTop.TextSize = 17
	coinTop.Font = Enum.Font.GothamBold
	coinTop.Parent = coinBadge

	if stat.won then
		local coinBot = Instance.new("TextLabel")
		coinBot.Size = UDim2.new(1, 0, 0.44, 0)
		coinBot.Position = UDim2.new(0, 0, 0.56, 0)
		coinBot.BackgroundTransparency = 1
		coinBot.Text = "🏆 Win!"
		coinBot.TextColor3 = Color3.fromRGB(255, 235, 140)
		coinBot.TextSize = 12
		coinBot.Font = Enum.Font.GothamBold
		coinBot.Parent = coinBadge
	end
end

-- ── 👑 상단 KING 영역 ─────────────────────────────────────────
-- ⚠️ 태거는 카드 목록에 넣지 않는다. 1 vs N 게임인데 같은 크기로 한 줄씩 세우면
--    태거가 러너 사이에 묻혀 비대칭이 드러나지 않는다.
-- ⚠️ 봇 태거(솔로 모드)일 때는 stats 에 태거가 없다. 그 경우도 영역이 비지 않게
--    "KING (BOT)" 으로 채운다 — 빈 상자가 남으면 버그처럼 보인다.
local kingSection = panel:WaitForChild("KingSection")

local function fillKingSection(taggerStat, winner)
	-- 기존 내용 정리 (라벨과 테두리는 남긴다)
	for _, c in ipairs(kingSection:GetChildren()) do
		if c:IsA("GuiObject") and c.Name ~= "SectionLabel" then c:Destroy() end
	end

	local kingWon = (winner == "Tagger")
	local stroke = kingSection:FindFirstChild("KingStroke")
	if stroke then
		stroke.Color = kingWon and Color3.fromRGB(255, 205, 90) or Color3.fromRGB(120, 100, 110)
	end
	kingSection.BackgroundColor3 = kingWon
		and Color3.fromRGB(56, 42, 24) or Color3.fromRGB(34, 28, 34)

	-- 아바타
	local av = Instance.new("ImageLabel")
	av.Name = "Avatar"
	av.Size = UDim2.new(0, 62, 0, 62)
	av.Position = UDim2.new(0, 16, 0, 32)
	av.BackgroundColor3 = Color3.fromRGB(22, 18, 30)
	av.BorderSizePixel = 0
	av.Parent = kingSection
	Instance.new("UICorner", av).CornerRadius = UDim.new(1, 0)

	if taggerStat and taggerStat.userId then
		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(taggerStat.userId,
					Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and url and av.Parent then av.Image = url end
		end)
	else
		-- 봇 태거(솔로 모드)에는 실제 유저가 없다. 전용 초상을 쓴다.
		-- ⚠️ 업로드한 111476077461663 은 Decal 이라 ImageLabel 에 직접 넣으면 안 뜬다.
		--    InsertService 로 뽑은 내부 Image ID 를 쓴다.
		av.Image = "rbxassetid://103459617970841"
	end

	-- 이름
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0, 260, 0, 30)
	nameLbl.Position = UDim2.new(0, 90, 0, 34)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 22
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.TextColor3 = kingWon and Color3.fromRGB(255, 225, 150)
	                              or Color3.fromRGB(190, 185, 195)
	nameLbl.Text = taggerStat and taggerStat.name or "KING (BOT)"
	nameLbl.Parent = kingSection

	-- 성과 (처치 수)
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(0, 300, 0, 20)
	sub.Position = UDim2.new(0, 90, 0, 64)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 14
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = Color3.fromRGB(190, 185, 200)
	if taggerStat then
		local k = (taggerStat.kills or 0) + (taggerStat.aiKills or 0)
		sub.Text = string.format("%d eliminated  ·  %d coins", k, taggerStat.coins or 0)
	else
		sub.Text = "Controlled by AI"
	end
	sub.Parent = kingSection

	-- 우측 결과 도장
	local stamp = Instance.new("TextLabel")
	stamp.Size = UDim2.new(0, 130, 0, 34)
	stamp.Position = UDim2.new(1, -146, 0, 46)
	stamp.BackgroundColor3 = kingWon and Color3.fromRGB(255, 195, 70)
	                                  or Color3.fromRGB(58, 52, 62)
	stamp.BorderSizePixel = 0
	stamp.Font = Enum.Font.GothamBold
	stamp.TextSize = 16
	stamp.TextColor3 = kingWon and Color3.fromRGB(50, 34, 10)
	                            or Color3.fromRGB(170, 168, 180)
	stamp.Text = kingWon and "DEFENDED" or "FALLEN"
	stamp.Parent = kingSection
	Instance.new("UICorner", stamp).CornerRadius = UDim.new(0, 8)
end

-- ── 결과 수신 ──
-- ⚠️ 결과창은 서버 이벤트를 직접 받는다.
--    승패 감상 화면(VictoryScreenClient)은 별도 신호(VictoryScreenEvent)로
--    로비 이동 '전에' 이미 재생되므로, 여기서 지연시킬 필요가 없다.
roundResultEvent.OnClientEvent:Connect(function(winner, stats, voided, endReason, hazardKill)
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end

	-- 타이틀 + 서브타이틀
	-- ⚠️ [핵심] 승패는 '나 기준'으로 먼저 말해야 한다.
	--    예전엔 winner 만 보고 "King Wins!" 를 띄웠는데, 러너인 내가 그걸 보면
	--    내 역할과 대조해서 "아 내가 졌구나"를 한 번 더 생각해야 했다.
	--    그 한 박자가 "내가 이겼다는 느낌이 없다"의 원인이다.
	--    → VICTORY / DEFEAT 를 먼저, 누가 이겼는지는 부제로 내린다.
	--
	-- ⚠️ [실패 기록 2026-08-23] 처음엔 player:GetAttribute("Role") 로 내 역할을 읽었는데
	--    항상 nil 이었다. endRound 안에서 Role 제거(1553행)가 결과 전송(1701행)보다
	--    먼저 실행되기 때문이다. 그 결과 전원이 관전자로 판정되어 연출이 통째로 스킵됐다.
	--    → stats 에 담겨 오는 내 기록에서 role 을 읽는다. 서버가 라운드 중 값을 담아
	--       보내므로 제거 순서와 무관하다.
	local myRole = nil
	for _, s in ipairs(stats or {}) do
		if s.userId == player.UserId then myRole = s.role break end
	end
	-- 폴백: stats 에 없으면(관전 입장 등) 속성이라도 본다
	if myRole == nil then myRole = player:GetAttribute("Role") end

	local iWon = (not voided) and myRole ~= nil and (
		(winner == "Tagger" and myRole == "Tagger") or
		(winner == "Runner" and myRole == "Runner")
	)
	local isSpectator = (myRole == nil)

	if voided then
		title.Text = "ROUND CANCELLED"
		title.TextColor3 = Color3.fromRGB(255, 170, 70)
		subtitle.Text = "The King fled the match — no winner this round"
	elseif isSpectator then
		-- 관전자에겐 나 기준이 없으니 기존처럼 승자를 말한다
		title.Text = (winner == "Tagger") and "KING WINS" or "RUNNERS WIN"
		title.TextColor3 = (winner == "Tagger")
			and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(120, 255, 120)
		subtitle.Text = (winner == "Tagger") and "All runners were eliminated"
			or (hazardKill and "The advancing wall took him" or "The runners prevailed")
	elseif iWon then
		title.Text = "VICTORY"
		title.TextColor3 = Color3.fromRGB(255, 215, 80)
		-- ⚠️ 같은 승리라도 '어떻게' 이겼는지에 따라 체감이 다르다.
		--    사유별로 갈라줘야 그 판이 기억에 남는다.
		if myRole == "Tagger" then
			subtitle.Text = (endReason == "timeout")
				and "You held out to the very end"
				or  "You defended the throne"
		else
			if endReason == "capture" then
				subtitle.Text = "The throne is yours"
			elseif endReason == "tagger_slain" or endReason == "bot_slain" then
				-- 🌊 [2026-09-01] 환경(밀려오는 벽)이 막타면 문구를 갈라준다.
				--   [왜] 실제로는 벽이 마무리했는데 "You brought down the King" 이 뜨면
				--     "이게 내 승리가 맞나?" 라는 애매함만 남는다(실측 12:14 판: 러너 96% / 벽 4%).
				--   [왜 'wall' 인가] map1 물벽 / map2 불꽃벽이고 맵이 늘면 또 는다.
				--     요소마다 문구를 만들면 유지가 안 되므로 공통어인 '밀려오는 벽'으로 묶는다.
				--   ⚠️ 승패는 그대로다. 러너 승리이고 보상도 동일하다 — 표현만 바꾼다.
				subtitle.Text = hazardKill
					and "The advancing wall took him"
					or  "You brought down the King"
			else
				subtitle.Text = "You survived the King's reign"
			end
		end
	else
		title.Text = "DEFEAT"
		title.TextColor3 = Color3.fromRGB(150, 160, 180)
		if myRole == "Tagger" then
			subtitle.Text = (endReason == "capture") and "The throne was taken"
				or (hazardKill and "The advancing wall took you" or "The King has fallen")
		else
			subtitle.Text = "The King stood his ground"
		end
	end

	-- 🎉 감각 연출. 텍스트가 아니라 소리·움직임·빛으로 결과를 먼저 전달한다.
	-- ⚠️ 관전자와 무효 라운드는 승패가 없으므로 조용히 넘어간다.
	--    아무 일도 안 일어난 판에 팡파르를 울리면 오히려 혼란스럽다.
	-- ⚠️ 사운드·플래시는 앞선 감상 화면(VictoryScreenClient)이 이미 담당한다.
	--    여기서 또 울리면 2초 사이에 같은 소리가 두 번 나고 화면도 두 번 번쩍인다.
	--    결과창은 '보고서' 역할이므로 타이틀 등장 정도만 남긴다.
	punchTitle(iWon and not voided and not isSpectator)

	local taggers, runners = {}, {}
	for _, s in ipairs(stats) do
		if s.role == "Tagger" then table.insert(taggers, s)
		else table.insert(runners, s) end
	end
	table.sort(runners, function(a, b) return (a.coins or 0) > (b.coins or 0) end)

	-- 👑 태거는 카드가 아니라 전용 상단 영역에 크게 그린다.
	-- ⚠️ 이 게임은 1 vs N 이다. 예전엔 전원을 같은 크기 카드로 한 줄씩 세워서
	--    태거가 러너 사이에 묻혔고, 비대칭이라는 정체성이 화면에 드러나지 않았다.
	--    → 위쪽에 KING 하나, 아래쪽에 RUNNERS 목록으로 나눈다.
	fillKingSection(taggers[1], winner)

	local totalH, idx, PAD = 0, 1, 8
	for _, s in ipairs(runners) do createCard(s, idx); totalH = totalH + CARD_H + PAD; idx = idx + 1 end
	scroll.CanvasSize = UDim2.new(0, 0, 0, totalH + 4)

	panel.Visible = true
	panel.BackgroundTransparency = 1
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), {BackgroundTransparency = 0}):Play()
end)

print("✅ RoundResultClient 준비! (리메이크: 2행 카드 + 서브타이틀 + void)")
