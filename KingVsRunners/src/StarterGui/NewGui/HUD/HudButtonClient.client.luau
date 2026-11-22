local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hudGui  = script.Parent
local canvas  = hudGui:WaitForChild("Canvas")
local currency = canvas:WaitForChild("Currency")

-- 코인 패널 우측 + 버튼 → 로벅스샵 COIN PACKS 섹션으로 이동
task.spawn(function()
	local gold = currency:WaitForChild("Gold", 10)
	local add  = gold and gold:WaitForChild("Add", 10)
	if not add then return end
	add.Active = true
	add.AutoButtonColor = true
	add.MouseButton1Click:Connect(function()
		if _G.openRobuxStore then
			_G.openRobuxStore("coins")
		else
			warn("[HUD] openRobuxStore 없음 — RobuxStoreClient 로드 확인 필요")
		end
	end)
end)
local buttons = canvas:WaitForChild("Buttons")
local invenBtn  = buttons:WaitForChild("InvenButton")
local effectBtn = buttons:FindFirstChild("Emote_killeffect_Button")

-- 화면 가장자리까지 사용 (자동 인셋 무시 — 더 좌측 끝에 붙음)
pcall(function() hudGui.ScreenInsets = Enum.ScreenInsets.None end)

-- ── 디바이스별 HUD 레이아웃 (공통 모듈) ───────────────────────
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Scaler = require(ReplicatedStorage:WaitForChild("ResponsiveScaler"))

local HUD_LAYOUT = {
	Mobile = {  -- 현재 마음에 드는 배치 (동결 — 절대 건드리지 않음)
		LEFT_X = 15, CURRENCY_Y = 120, BUTTONS_Y = 165,
		CELL_SIZE = 60, CELL_PAD = 8, MIN_SCALE = 0.7,
		MAX_COLS = 2,                                   -- 3열
		BUTTONS_SIZE = UDim2.new(0, 128, 0, 128),       -- 3×2 수용
		CURRENCY_WIDTH = nil,                           -- nil = 원본 Scale 너비 유지
		BANNER_W = 128, BANNER_COMPACT = true, BANNER_GAP = 8,          -- HUD 광고 배너 (모바일: 버튼폭 compact)
	},
	PC = {  -- 예시처럼: 코인+버튼 같은 열 정렬, 버튼 3열 그리드
		-- [LEFT-HUD-POS] 2026-08-21: 130/194 → 250/314.
		--   로블록스 PC 클라이언트에서 기본 채팅창(좌측 상단, 하단 y≈366)과 겹쳤다.
		--   Studio 는 뷰포트가 작고 채팅이 축소돼 있어 재현되지 않았다.
		--   ⚠️ Mobile 값은 "동결"이라 건드리지 않는다(위 주석 참조).
		LEFT_X = 24, CURRENCY_Y = 250, BUTTONS_Y = 314,
		CELL_SIZE = 72, CELL_PAD = 8, MIN_SCALE = 0.85,  -- 셀 80→72 (약간 축소)
		MAX_COLS = 2,                                   -- 3열 (6개 → 3×2)
		-- 3열 콘텐츠 너비 = 72*3 + 8*2 = 232 / 높이 = 72*2 + 8 = 152
		BUTTONS_SIZE = UDim2.new(0, 152, 0, 152),       -- 3열×2행 수용
		CURRENCY_WIDTH = 232,                           -- 코인 패널 = 그리드 콘텐츠 너비 (열 정렬)
		CURRENCY_HEIGHT = 50,                           -- 코인 패널 높이 56→50 (약간 축소)
		BANNER_W = 280, BANNER_COMPACT = false, BANNER_GAP = 48,         -- HUD 광고 배너 (PC: 넓은 가로 카드)
	},
}
local cfg = HUD_LAYOUT[Scaler.device()]

-- ── 좌측 HUD 정렬 (Currency 위, Buttons 그 아래, X 좌표 통일) ──
currency.AnchorPoint = Vector2.new(0, 0)
currency.Position    = UDim2.new(0, cfg.LEFT_X, 0, cfg.CURRENCY_Y)

-- PC: 코인 패널 너비를 버튼 그리드와 동일하게 (Offset 고정)
if cfg.CURRENCY_WIDTH then
	currency.Size = UDim2.new(0, cfg.CURRENCY_WIDTH, 0, cfg.CURRENCY_HEIGHT or 56)
end

-- Currency UIScale 제거 (원본 크기 사용)
local currencyScale = currency:FindFirstChildOfClass("UIScale")
if currencyScale then
	currencyScale.Scale = 1
end

buttons.AnchorPoint  = Vector2.new(0, 0)
buttons.Position     = UDim2.new(0, cfg.LEFT_X, 0, cfg.BUTTONS_Y)
buttons.Size         = cfg.BUTTONS_SIZE

-- 6개 HUD 버튼 크기 (UIGridLayout 의 셀 사이즈 강제)
local gridLayout = buttons:FindFirstChildOfClass("UIGridLayout")
if gridLayout then
	gridLayout.CellSize              = UDim2.new(0, cfg.CELL_SIZE, 0, cfg.CELL_SIZE)
	gridLayout.CellPadding           = UDim2.new(0, cfg.CELL_PAD, 0, cfg.CELL_PAD)
	gridLayout.FillDirectionMaxCells = cfg.MAX_COLS
end

-- ── 반응형 UIScale (모듈에 위임, HUD 아이콘 가독성 우선) ──────
-- ⚠️ 이 ScreenGui 에는 MobileScaled 태그를 붙이지 말 것.
--    MobileUIScaler 가 같은 UIScale 을 minScale 0.55 로 덮어쓴다.
--    ResponsiveScaler.getOrMakeScale 은 FindFirstChildOfClass 로 기존 UIScale 을
--    그대로 재사용하므로 두 시스템이 하나의 객체를 두고 다툰다.
--    둘 다 ViewportSize 변경에 연결돼 있어 나중에 발동한 쪽이 이긴다 → 판마다 결과가 달라짐.
--    실측(2026-08): 0.70(정상) / 0.55(찌그러짐)가 번갈아 적용됐고,
--      0.55 에서 currency(Y 8~33.7)와 buttons(Y 32.75~)가 겹쳤다.
--    MIN_SCALE 0.7 은 CURRENCY_Y=120 / BUTTONS_Y=165 와 한 세트로 설계된 값이다.
Scaler.applyEdge(hudGui, nil, {
	baseW = 1280, baseH = 720,
	Mobile = { minScale = cfg.MIN_SCALE },
	PC     = { minScale = cfg.MIN_SCALE },
})

local function findBtnByText(text)
    for _, btn in ipairs(buttons:GetChildren()) do
        if btn:IsA("ImageButton") then
            local m  = btn:FindFirstChild("Main")
            local tl = m and m:FindFirstChild("TextLabel")
            if tl and tl.Text == text then return btn end
        end
    end
end
local indexBtn    = findBtnByText("Index")
local teleportBtn = findBtnByText("Teleport")
local settingsBtn = findBtnByText("Settings")
local questsBtn   = findBtnByText("Quests")
local rewardsBtn  = findBtnByText("Rewards")

local function toggleGui(guiName)
    local newGui = playerGui:FindFirstChild("NewGui")
    local gui    = newGui and newGui:FindFirstChild(guiName) or playerGui:FindFirstChild(guiName)
    if not gui then return end
    if not gui.Enabled then gui.Enabled = true end
    local canvas = gui:FindFirstChild("Canvas")
    if not canvas then return end
    local target = canvas:FindFirstChild("Main") or canvas
    target.Visible = not target.Visible
end

-- ── UnifiedInven 열기/닫기 토글 ──────────────────────────────
local function openUnified(startTabId)
    local newGui = playerGui:FindFirstChild("NewGui")
    local uni    = newGui and newGui:FindFirstChild("UnifiedInven")
    if not uni then return end
    local uniCanvas = uni:FindFirstChild("Canvas")

    if uniCanvas and uniCanvas.Visible then
        if _G.closeUnifiedInven then _G.closeUnifiedInven()
        else uniCanvas.Visible = false end
    else
        if _G.openUnifiedInven then _G.openUnifiedInven(startTabId)
        elseif uniCanvas then uniCanvas.Visible = true end
    end
end

-- InvenButton → Tagger 탭으로
invenBtn.MouseButton1Click:Connect(function() openUnified("Tagger") end)

-- EffectButton → KillEffect 탭으로
if effectBtn then
    effectBtn.MouseButton1Click:Connect(function() openUnified("KillEffect") end)
end

if indexBtn    then indexBtn.MouseButton1Click:Connect(function()    toggleGui("Index")    end) end
if teleportBtn then teleportBtn.MouseButton1Click:Connect(function() toggleGui("Teleport") end) end
if settingsBtn then settingsBtn.MouseButton1Click:Connect(function() toggleGui("Settings") end) end
if questsBtn   then questsBtn.MouseButton1Click:Connect(function()   toggleGui("Quests")   end) end
if rewardsBtn  then rewardsBtn.MouseButton1Click:Connect(function()  toggleGui("Rewards")  end) end

-- ════════════════════════════════════════════════════════════════
-- [CLAIM-BADGE] 수령 가능한 보상이 있으면 버튼에 느낌표를 띄운다.
--   ⚠️ 서버에 새 리모트를 만들지 않는다. 두 시스템이 이미 스냅샷을 push 하므로
--      그걸 구독해서 클라에서 판정한다.
--        QuestUpdateEvent  → 퀘스트 스냅샷 (complete && not claimed 가 하나라도 있으면)
--        DailyRewardUpdate → 출석 스냅샷 (canClaim)
--   ⚠️ QuestUpdateEvent 는 수령 알림("claimed" 문자열)도 실어 나른다. 테이블일 때만 처리.
-- ════════════════════════════════════════════════════════════════
local _MakeClaimBadge   -- [BADGE-SCOPE] 아래 do 블록 안의 makeBadge 를 밖에서도 쓰기 위한 핸들

do
	local RS = game:GetService("ReplicatedStorage")

	local function makeBadge(btn)
		if not btn then return nil end
		local existing = btn:FindFirstChild("_ClaimBadge")
		if existing then return existing end
		local b = Instance.new("TextLabel")
		b.Name = "_ClaimBadge"
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.fromScale(1.06, -0.10)
		-- ⚠️ 예전엔 fromScale(0.42) + RelativeYY 였는데, HUD 버튼이 작아 20px 도 안 됐다.
		--    거기에 TextScaled 까지 겹쳐 글자가 뭉개졌다(실측 2026-08-21).
		--    → 고정 크기(offset)로 최소 가독 크기를 보장한다.
		b.Size = UDim2.fromOffset(28, 28)
		b.BackgroundColor3 = Color3.fromRGB(235, 50, 50)
		b.Text = "!"
		b.Font = Enum.Font.GothamBlack
		-- TextScaled 대신 고정 TextSize. 원 안에 안정적으로 들어간다.
		b.TextScaled = false
		b.TextSize = 22
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.ZIndex = 20
		b.Visible = false
		-- ⚠️ 버튼 위에 얹히므로 입력을 가로채지 않게 명시한다.
		b.Active = false
		b.Selectable = false
		-- ⚠️ 부모 버튼이 ClipsDescendants 면 배지가 잘린다. 배지가 버튼 밖으로
		--    살짝 나가는 배치라 반드시 꺼야 한다(실측 2026-08-21: 원만 보이고 ! 안 보임).
		if btn:IsA("GuiObject") then btn.ClipsDescendants = false end
		b.Parent = btn
		Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
		local st = Instance.new("UIStroke", b)
		st.Color = Color3.fromRGB(255, 255, 255) ; st.Thickness = 2
		-- ⚠️ UIStroke 는 기본(ContextualStroke)에서 '텍스트'에도 적용된다.
		--    흰 글자에 흰 테두리가 겹쳐 ! 가 뭉개져 안 보였다.
		--    Border 로 지정해 배경 테두리에만 적용한다.
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		-- 시선을 끄는 맥박
		task.spawn(function()
			local TS = game:GetService("TweenService")
			local sc = Instance.new("UIScale", b)
			while b.Parent do
				if b.Visible then
					TS:Create(sc, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { Scale = 1.18 }):Play()
					task.wait(0.5)
					TS:Create(sc, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
					task.wait(0.5)
				else
					task.wait(0.4)
				end
			end
		end)
		return b
	end

	-- ⚠️ [BADGE-SCOPE] makeBadge 는 이 do…end 안의 지역 함수라 블록 밖에서 못 쓴다.
	--    배틀패스 배지(아래쪽)가 이걸 호출했다가 nil 참조로 스크립트가 멈춰
	--    그 뒤의 bpBar 클릭 연결이 아예 실행되지 않았다(실측 2026-08-22).
	--    → 모듈 상단 변수에 담아 블록 밖에서도 쓸 수 있게 한다.
	_MakeClaimBadge = makeBadge

	local questBadge  = makeBadge(questsBtn)
	local rewardBadge = makeBadge(rewardsBtn)

	-- 퀘스트: 수령 대기 중인 항목이 하나라도 있는가
	local function questHasClaimable(snap)
		if type(snap) ~= "table" then return false end
		for _, key in ipairs({ "daily", "weekly" }) do
			local cat = snap[key]
			if type(cat) == "table" then
				for _, q in ipairs(cat.quests or {}) do
					if q.complete and not q.claimed then return true end
				end
				if cat.allClaimed and not cat.bonusClaimed then return true end
			end
		end
		return false
	end

	local questEv = RS:FindFirstChild("QuestUpdateEvent")
	if questEv and questBadge then
		questEv.OnClientEvent:Connect(function(snap)
			-- 수령 알림(문자열)은 무시 — 스냅샷만 판정에 쓴다
			if type(snap) ~= "table" then return end
			questBadge.Visible = questHasClaimable(snap)
		end)
		-- 최초 1회는 직접 조회 (push 를 기다리면 늦다)
		task.spawn(function()
			local fn = RS:FindFirstChild("QuestDataEvent")
			if not fn then return end
			local ok, snap = pcall(function() return fn:InvokeServer() end)
			if ok then questBadge.Visible = questHasClaimable(snap) end
		end)
	end

	local rewardEv = RS:FindFirstChild("DailyRewardUpdate")
	if rewardEv and rewardBadge then
		rewardEv.OnClientEvent:Connect(function(snap)
			if type(snap) ~= "table" then return end
			rewardBadge.Visible = snap.canClaim == true
		end)
		-- 최초 1회 직접 조회. push 를 기다리면 접속 직후에 배지가 안 뜬다.
		task.spawn(function()
			local fn = RS:FindFirstChild("DailyRewardData")
			if not fn then return end
			local ok, snap = pcall(function() return fn:InvokeServer() end)
			if ok and type(snap) == "table" then
				rewardBadge.Visible = snap.canClaim == true
			end
		end)
	end
end

-- ── Settings → 관전(Spectate) 옆으로 이동 + 그 자리에 Shop 버튼(→코인샵) 추가 ──
-- 동결 HUD 그리드는 Settings↔Shop 1:1 교체라 셀 개수·배치 보존. Settings는 그리드 밖(우하단)으로.
if settingsBtn then
	-- 1) Shop 버튼 = Settings 클론 (동일 스타일), 아이콘/라벨만 교체
	local shopBtn = settingsBtn:Clone()
	shopBtn.Name = "ShopButton"
	shopBtn.LayoutOrder = 2   -- Inventory(1) 다음 = 우상단 슬롯
	local sMain  = shopBtn:FindFirstChild("Main")
	local sIcon  = sMain and sMain:FindFirstChild("Glow")   -- Main.Glow = 아이콘 이미지
	local sLabel = sMain and sMain:FindFirstChildWhichIsA("TextLabel", true)
	if sIcon then sIcon.Image = "rbxassetid://18469563575" end  -- 쇼핑 아이콘
	if sLabel then sLabel.Text = "Shop" end
	shopBtn.Parent = buttons
	shopBtn.MouseButton1Click:Connect(function()
		if _G.openCoinShop then _G.openCoinShop() else warn("[HUD] _G.openCoinShop 없음 (ShopClient 미로드?)") end
	end)

	-- 2) 그리드 순서 고정 (Inventory=1, Shop=2, Quests=3, Rewards=4)
	if invenBtn  then invenBtn.LayoutOrder  = 1 end
	if questsBtn then questsBtn.LayoutOrder = 3 end
	if rewardsBtn then rewardsBtn.LayoutOrder = 4 end

	-- 3) Settings를 관전(Spectate) 버튼 바로 왼쪽에, 동일 크기(56)로 이동
	-- SpectateGui로 옮겨야 관전과 같은 좌표계·스케일 → 크기·정렬 정확히 일치
	settingsBtn.LayoutOrder = 99
	task.spawn(function()
		local specGui = playerGui:WaitForChild("SpectateGui", 10)
		settingsBtn.AnchorPoint = Vector2.new(1, 0)
		settingsBtn.Parent = specGui or canvas

		-- 관전(Spectate) 버튼도 Settings처럼 박스+텍스트 입히기 (아이콘만 있어 이질적)
		local specBtn = specGui and specGui:FindFirstChild("SpectateButton")
		if specBtn then
			specBtn.AnchorPoint = Vector2.new(1, 0)
		end

		-- 우측 버튼(Settings/관전): 좌측 HUD 버튼과 동일 크기·여백·간격으로 통일
		-- 라운드 중(_G.HudRoundActive)에는 관전을 숨기고 Settings가 우측 끝자리를 차지
		local function syncRightBtns()
			local us = hudGui:FindFirstChildOfClass("UIScale")
			local sc = (us and us.Scale or 1)
			local size = cfg.CELL_SIZE * sc   -- 좌측 셀과 동일 크기
			local edge = cfg.LEFT_X   * sc    -- 좌우 가장자리 여백 대칭
			local gap  = cfg.CELL_PAD * sc    -- 좌측 그리드 간격과 동일
			-- 우측 버튼 상단 여백(스케일 전 기준). 작을수록 화면 최상단에 붙음.
			-- 좌측 그리드(BUTTONS_Y)와 분리 — 우측 상단은 비어 있어 끝까지 올릴 수 있음.
			-- 라운드 중엔 KING ITEMS(TaggerItemUI.ItemList)가 우측에 내려와 Settings 라벨을
			-- 가리므로 그때만 더 위로 붙인다.
			-- [SETTINGS-POS] 대각선 아래로 이동 (2026-08-21).
			--   ⚠️ 라운드 중 값(ROUND)은 KING ITEMS(TaggerItemUI.ItemList)를 피하려고
			--      일부러 위로 붙인 것이라 크게 내리면 다시 가려진다. 로비보다 적게 내린다.
			--   X 도 RIGHT_NUDGE_X 만큼 안쪽으로 당겨 화면 모서리에서 띄운다.
			local RIGHT_TOP_Y       = 64   -- 40 → 64
			local RIGHT_TOP_Y_ROUND = 20   -- 8 → 20
			local RIGHT_NUDGE_X     = 16
			local topY = (_G.HudRoundActive and RIGHT_TOP_Y_ROUND or RIGHT_TOP_Y) * sc
			settingsBtn.Size = UDim2.fromOffset(size, size)
			if specBtn then specBtn.Size = UDim2.fromOffset(size, size) end
			-- 인벤(로드아웃) 열림 중엔 둘 다 숨김.
			-- 인벤 닫기 X 버튼과 겹치고(실측: 세로 6px·가로 19px), X 버튼이 상단 12px
			-- 지점이라 그 위로 피할 공간도 없음. 인벤 보는 동안엔 불필요한 버튼이기도 함.
			if _G.HudInvenOpen then
				settingsBtn.Visible = false
				if specBtn then specBtn.Visible = false end
				return
			end
			settingsBtn.Visible = true
			if _G.HudRoundActive then
				-- 라운드 진행 중: 관전 숨김 + Settings를 우측 끝으로 이동
				settingsBtn.Position = UDim2.new(1, -(edge + RIGHT_NUDGE_X), 0, topY)
				if specBtn then specBtn.Visible = false end
			else
				-- 대기/관전/탈락: 둘 다 표시 (Settings 좌 · 관전 우)
				settingsBtn.Position = UDim2.new(1, -(edge + RIGHT_NUDGE_X + size + gap), 0, topY)
				if specBtn then
					specBtn.Visible = true
					specBtn.Position = UDim2.new(1, -(edge + RIGHT_NUDGE_X), 0, topY)
				end
			end
		end
		_G.syncHudRightBtns = syncRightBtns   -- refreshHudVisibility에서 호출
		syncRightBtns()
		task.defer(syncRightBtns)
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(syncRightBtns)
		if specBtn and not specBtn:FindFirstChild("_SkinMain") then
			local specIcon = specBtn:FindFirstChild("Icon")
			local iconImg = specIcon and specIcon.Image or ""
			-- Settings의 외곽 Glow + Main 박스 복제 → 관전 버튼에 입힘
			local og = settingsBtn:FindFirstChild("Glow")
			if og then
				local g = og:Clone(); g.Name = "_SkinGlow"; g.Parent = specBtn
			end
			local mb = settingsBtn:FindFirstChild("Main")
			if mb then
				local m = mb:Clone(); m.Name = "_SkinMain"; m.Parent = specBtn
				local mi = m:FindFirstChild("Glow")                    -- 아이콘 자리
				if mi then mi.Image = iconImg end                      -- 관전 돋보기 아이콘 유지
				local ml = m:FindFirstChildWhichIsA("TextLabel", true)
				if ml then ml.Text = "Spectate" end
			end
			-- 원래 bare Icon 숨김 (스킨 Main이 아이콘 제공)
			if specIcon then specIcon.Visible = false end
		end
	end)
	print("[HUD] Settings 이동 + Shop 버튼 추가 완료")
end

-- ── HUD 광고 배너 (프로모 캐러셀 compact, 버튼 그리드 바로 아래) ──
local PromoCarousel = require(ReplicatedStorage:WaitForChild("PromoCarousel"))
local promoBanner
do
	local compact = cfg.BANNER_COMPACT ~= false
	local bw = cfg.BANNER_W or cfg.BUTTONS_SIZE.X.Offset   -- 배너 폭 (디바이스별)
	local bh = compact and 56 or 84                        -- 배너 높이 (모바일 얇게)
	local desiredBy = cfg.BUTTONS_Y + cfg.BUTTONS_SIZE.Y.Offset + (cfg.BANNER_GAP or 8)  -- 버튼 그리드 아래(기본 위치)
	promoBanner = PromoCarousel.makeCarousel(canvas, {
		promos = PromoCarousel.PROMOS,
		compact = compact,
		height = bh,
		size = UDim2.new(0, bw, 0, bh),
		position = UDim2.new(0, cfg.LEFT_X, 0, desiredBy),
		autoSec = 4,
		onClick = function()
			if _G.openRobuxStore then _G.openRobuxStore() else warn("[HUD] _G.openRobuxStore 없음") end
		end,
	})
	promoBanner.Name = "PromoBanner"
end

-- ── 상단 배틀패스 진행 바 (라운드 타이머 아래, 탭 → 배틀패스) ──
local bpBar
do
	local NAVY_CARD = Color3.fromRGB(26, 34, 54)
	local GREEN     = Color3.fromRGB(47, 180, 87)
	local BLUE      = Color3.fromRGB(75, 159, 255)
	local TEXT_MAIN = Color3.fromRGB(234, 240, 255)

	bpBar = Instance.new("TextButton")
	bpBar.Name = "BattlePassBar"
	bpBar.AnchorPoint = Vector2.new(0.5, 0)
	bpBar.Position = UDim2.new(0.5, 0, 0, 82)   -- 상단중앙, 타이머 아래 (스샷 보고 Y 조정)
	bpBar.Size = UDim2.fromOffset(290, 46)   -- 2줄(티어 + 남은기간) 수용을 위해 38→46
	bpBar.BackgroundColor3 = NAVY_CARD
	bpBar.AutoButtonColor = true
	bpBar.Text = ""
	bpBar.Parent = canvas
	Instance.new("UICorner", bpBar).CornerRadius = UDim.new(0, 12)
	local st = Instance.new("UIStroke"); st.Color = BLUE; st.Thickness = 1; st.Transparency = 0.4; st.Parent = bpBar

	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0, 0.5)
	lbl.Position = UDim2.new(0, 14, 0.5, -6)   -- 하단 날짜줄 공간만큼 살짝 위로
	lbl.Size = UDim2.new(0.6, -14, 0, 20)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = "BATTLE PASS  ·  Tier 5"
	lbl.TextColor3 = TEXT_MAIN
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextScaled = true
	lbl.Parent = bpBar
	local lc = Instance.new("UITextSizeConstraint"); lc.MaxTextSize = 14; lc.Parent = lbl

	-- 시즌 남은 기간: 하단 중앙에 한 줄로.
	-- (패널 안까지 들어가야만 마감을 알 수 있으면 "예고 없이 끝났다"는 배신감으로 이어짐)
	local expLbl = Instance.new("TextLabel")
	expLbl.Name = "ExpiryLabel"
	expLbl.AnchorPoint = Vector2.new(0.5, 1)
	expLbl.Position = UDim2.new(0.5, 0, 1, -4)
	expLbl.Size = UDim2.new(1, -20, 0, 13)
	expLbl.BackgroundTransparency = 1
	expLbl.Font = Enum.Font.GothamMedium
	expLbl.Text = ""
	expLbl.TextColor3 = Color3.fromRGB(255, 200, 90)
	expLbl.TextXAlignment = Enum.TextXAlignment.Center
	expLbl.TextScaled = true
	expLbl.Parent = bpBar
	local ec = Instance.new("UITextSizeConstraint"); ec.MaxTextSize = 11; ec.Parent = expLbl

	local barBg = Instance.new("Frame")
	barBg.AnchorPoint = Vector2.new(1, 0.5)
	barBg.Position = UDim2.new(1, -14, 0.5, -6)   -- 티어 텍스트와 같은 높이 (하단 날짜줄 공간 확보)
	barBg.Size = UDim2.new(0.34, 0, 0, 10)
	barBg.BackgroundColor3 = Color3.fromRGB(14, 22, 38)
	barBg.BorderSizePixel = 0
	barBg.Parent = bpBar
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0.64, 0, 1, 0)   -- 더미 64%
	fill.BackgroundColor3 = GREEN
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	-- live: read BP_Tier / BP_XP so the entry bar matches actual progress
	local BP_XP_PER_TIER = 800
	local bpPlr = game:GetService("Players").LocalPlayer
	-- ⚠️ WaitForChild 를 타임아웃 없이 쓰면 SeasonConfig 복제가 늦을 때 여기서 스크립트가
	--    멈춰 뒤쪽 refreshHudVisibility() 초기 호출까지 도달하지 못한다.
	--    → 배틀패스 바가 처음에 안 보이다가 Role 변경 등으로 갱신될 때서야 나타남 (2026-08 실측).
	--    바 생성/표시를 막지 않도록 논블로킹으로 가져오고, 없으면 기간 표시만 생략한다.
	local SeasonCfg = nil
	task.spawn(function()
		local mod = game:GetService("ReplicatedStorage"):WaitForChild("SeasonConfig", 10)
		if mod then
			local ok, res = pcall(require, mod)
			if ok then SeasonCfg = res end
		end
		if not SeasonCfg then warn("[HUD] SeasonConfig 로드 실패 — 배틀패스 기간 표시 생략") end
	end)
	local function updateBpBar()
		local tier = math.clamp(bpPlr:GetAttribute("BP_Tier") or 1, 1, 30)
		local xp = bpPlr:GetAttribute("BP_XP") or 0
		-- ⚠️ 게이지는 "현재 티어 안의 진행도"(xp % 800)다. 전체 진행도가 아니다.
		--    만렙(30)에 도달하면 티어는 고정인데 XP 는 계속 쌓여 게이지만 0~100%를
		--    반복해 "왜 안 오르지?"로 보인다 → 만렙이면 꽉 채우고 MAX 로 표기.
		if tier >= 30 then
			lbl.Text = "BATTLE PASS  ·  MAX"
			fill.Size = UDim2.new(1, 0, 1, 0)
		else
			lbl.Text = "BATTLE PASS  ·  Tier " .. tier
			fill.Size = UDim2.new(math.clamp((xp % BP_XP_PER_TIER) / BP_XP_PER_TIER, 0, 1), 0, 1, 0)
		end
	end
	-- 남은 기간 갱신: 60초 주기. 3일 이하로 남으면 붉은색 경고.
	local function updateExpiry()
		if not SeasonCfg then expLbl.Text = "" return end   -- 아직 로드 전이면 빈 줄 유지
		local left = SeasonCfg.secondsLeft()
		expLbl.Text = (left > 0) and ("Ends in " .. SeasonCfg.timeLeftText()) or "SEASON ENDED"
		expLbl.TextColor3 = (left <= 0) and Color3.fromRGB(255, 110, 110)
			or (left <= 3 * 86400) and Color3.fromRGB(255, 130, 110)
			or Color3.fromRGB(255, 200, 90)
	end
	updateBpBar()
	updateExpiry()
	task.spawn(function()
		-- 초기엔 SeasonCfg 로드를 기다려야 하므로 짧게, 이후엔 60초 주기
		for _ = 1, 20 do
			task.wait(0.5)
			if SeasonCfg then updateExpiry() break end
		end
		while bpBar.Parent do
			task.wait(60)
			updateExpiry()
		end
	end)
	bpPlr:GetAttributeChangedSignal("BP_Tier"):Connect(updateBpBar)
	bpPlr:GetAttributeChangedSignal("BP_XP"):Connect(updateBpBar)


	-- ⚠️ 상단 중앙 모달이 뜨는 동안에는 배틀패스 바를 숨긴다.
	--    대상: 킹 선정 발표(SlotFrame) + 맵 투표(MapVoteGui.VoteFrame).
	--    맵 투표는 Y 0.42 중앙 정렬 + 헤더가 위로 30 튀어나와, 1136×640 기준
	--    헤더 상단이 Y 99 라 배틀패스 바(82~128)와 29px 겹쳤다(실측).
	--    ⚠️ 바를 아래로 내리는 건 역효과다 — 투표 UI 가 더 아래에 있어 겹침이 커진다.
	--       위로 올리자니 라운드 타이머(30~110)와 투표 헤더(99~) 사이에 46px 자리가 없다.
	--       → 겹치는 동안 숨기는 것이 유일한 해결.
	--    두 조건을 하나의 상태로 합친다. 따로 두면 서로 Visible 을 덮어쓴다.
	--
	-- ⚠️ [BPBAR-OWNER] 여기에 '라운드 중 숨김'까지 합쳤다.
	--    예전엔 refreshHudVisibility(519행)가 라운드 조건으로 bpBar.Visible 을 끄고,
	--    이 apply() 가 슬롯·투표 조건만 보고 다시 켜서 서로 덮어썼다.
	--    두 주인이 같은 속성을 다투면 나중에 실행된 쪽이 이겨 판마다 결과가 달라진다
	--    (실측 2026-08-20: 태거로 라운드 진행 중인데 배틀패스 바가 남아 있었음).
	--    → 소유자를 이 apply() 하나로 통일하고, 라운드 상태는 _G.HudRoundActive 로 받는다.
	--      (그 값은 refreshHudVisibility 가 521행에서 갱신한다)
	task.spawn(function()
		local pg = bpPlr:WaitForChild("PlayerGui", 10)
		if not pg then return end

		local hideBySlot, hideByVote = false, false
		local function apply()
			-- _G.HudRoundActive = "라운드 진행 중 + 내가 살아서 참여 중"
			bpBar.Visible = not (hideBySlot or hideByVote or _G.HudRoundActive)
		end
		-- refreshHudVisibility 쪽에서 라운드 상태가 바뀔 때 다시 부를 수 있도록 노출
		_G.applyBpBarVisibility = apply
		-- 초기 1회 적용. apply() 는 아래 bindSlot/bindVote 안에서만 불리는데,
		-- 그 GUI 가 아직 없거나 영영 안 뜨는 경우 한 번도 실행되지 않는다.
		-- 이 task.spawn 은 WaitForChild 로 지연되므로, 그 사이에 지나간
		-- refreshHudVisibility 의 결과(_G.HudRoundActive)를 여기서 따라잡는다.
		apply()

		-- 킹 선정 발표
		local function bindSlot(gameGui)
			local slot = gameGui:WaitForChild("SlotFrame", 10)
			if not slot then return end
			local function sync()
				hideBySlot = slot.Visible
				apply()
			end
			slot:GetPropertyChangedSignal("Visible"):Connect(sync)
			sync()
		end

		-- 맵 투표: VoteFrame 은 화면 밖(Y -300/-1000)으로 밀어 감추므로
		-- Visible 이 아니라 실제 화면 안에 있는지로 판단한다.
		local function bindVote(voteGui)
			local vf = voteGui:WaitForChild("VoteFrame", 10)
			if not vf then return end
			local function sync()
				local onScreen = vf.Visible and vf.AbsolutePosition.Y > -200
				hideByVote = onScreen
				apply()
			end
			vf:GetPropertyChangedSignal("Position"):Connect(sync)
			vf:GetPropertyChangedSignal("Visible"):Connect(sync)
			sync()
		end

		local existing = pg:FindFirstChild("GameAnnounceUI") or pg:FindFirstChild("GameUI")
		if existing then bindSlot(existing) end
		local mv = pg:FindFirstChild("MapVoteGui")
		if mv then bindVote(mv) end
		pg.ChildAdded:Connect(function(c)
			if c.Name == "GameAnnounceUI" or c.Name == "GameUI" then
				task.wait(0.2); bindSlot(c)
			elseif c.Name == "MapVoteGui" then
				task.wait(0.2); bindVote(c)
			end
		end)
	end)

	-- ── 배틀패스: 현재 티어 이하에 미수령 보상이 있으면 배지 ──
	--   ⚠️ bpBar 가 생성된 뒤여야 한다. 위쪽(퀘스트/출석 배지 블록)에 두면 아직 nil 이다.
	--   ⚠️ 퀘스트/출석과 달리 push 이벤트가 없어 BattlePassClaim("state")로 직접 조회한다.
	--      매초 폴링은 서버 부하이므로 20초 주기로 둔다.
	--   ⚠️ 프리미엄 미보유자에게 prem 미수령을 알리면 "받을 수 없는데 알림"이 된다.
	--      free 트랙만 판정한다.
	do
		local RS2 = game:GetService("ReplicatedStorage")
		local bpBadge = _MakeClaimBadge and _MakeClaimBadge(bpBar) or nil
		if bpBadge then
			local function refreshBP()
				local fn = RS2:FindFirstChild("BattlePassClaim")
				if not fn then return end
				local ok, st = pcall(function() return fn:InvokeServer("state") end)
				if not (ok and type(st) == "table") then return end
				local tier = tonumber(st.tier) or 1
				local cf = st.claimedFree or {}
				local has = false
				for t = 1, math.min(tier, 30) do
					if not cf[t] then has = true break end
				end
				bpBadge.Visible = has
			end
			task.spawn(function()
				task.wait(3)          -- 프로필 로드 대기
				while bpBar and bpBar.Parent do
					pcall(refreshBP)
					task.wait(20)
				end
			end)
			_G.RefreshBattlePassBadge = refreshBP   -- 수령 직후 즉시 갱신용
		end
	end

	bpBar.MouseButton1Click:Connect(function()
		if _G.openBattlePass then _G.openBattlePass() else warn("[HUD] _G.openBattlePass 없음 (BattlePassClient 미로드?)") end
	end)
end


-- ── 코인 UI 연동 ──────────────────────────────────────────────
local updateCoinEvent = ReplicatedStorage:WaitForChild("UpdateCoinEvent")
local getCoinEvent    = ReplicatedStorage:WaitForChild("GetCoinEvent")

local goldLabel = hudGui:FindFirstChild("Canvas")
    and hudGui.Canvas:FindFirstChild("Currency")
    and hudGui.Canvas.Currency:FindFirstChild("Gold")
    and hudGui.Canvas.Currency.Gold:FindFirstChild("TextLabel")

local function formatCoins(amount)
    return "$" .. string.format("%d", amount):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function updateCoinDisplay(amount)
    if goldLabel then goldLabel.Text = formatCoins(amount) end
end

-- 초기값 로드
local current = getCoinEvent:InvokeServer()
if current then updateCoinDisplay(current) end

-- 실시간 업데이트
updateCoinEvent.OnClientEvent:Connect(function(amount)
    updateCoinDisplay(amount)
end)

-- ── 라운드 중 HUD 숨김 ───────────────────────────────────────────
-- 라운드에 실제 참여(살아서 플레이) 중일 때만 좌측 HUD(골드+버튼)를 숨김.
-- 인터미션 / 죽음·관전 / 라운드 미참여 시엔 표시.
-- (음악 시스템과 동일한 판단 기준)
do
    local phaseEvent = ReplicatedStorage:FindFirstChild("RoundPhaseEvent")
    local stage2Event = ReplicatedStorage:FindFirstChild("Stage2Started")

    -- ⚠️ 이 스크립트는 HUD(ResetOnSpawn=true) 소속이라 리스폰마다 재시작된다.
    --    라운드 시작 텔레포트로 리스폰이 나면 이미 발사된 stage1 이벤트를 놓친다.
    --    (실측: ROUND START 0.4초 뒤 재시작 → phase 가 intermission 으로 굳음)
    --    → 이벤트에만 의존하지 않고 서버가 남긴 현재 단계를 직접 읽는다.
    local currentPhase = ReplicatedStorage:GetAttribute("RoundPhase") or "intermission"

    -- 관전/미참여 판단
    local function isSpectatingOrOut()
        if player:GetAttribute("Spectating") == true then return true end
        if player:GetAttribute("Eliminated") then return true end
        local role = player:GetAttribute("Role")
        if role == nil or role == "" then return true end
        return false
    end

    local function refreshHudVisibility()
        -- 라운드 진행 중(stage1/stage2) + 실제 참여(생존) → 숨김
        local inRound = (currentPhase == "stage1" or currentPhase == "stage2")
        local hide = inRound and (not isSpectatingOrOut())
        local show = not hide
        currency.Visible = show
        buttons.Visible = show
        if promoBanner then promoBanner.Visible = show end
        -- 우측 버튼: 라운드 중이면 관전 숨김 + Settings를 우측 끝으로
        _G.HudRoundActive = hide
        -- [BPBAR-OWNER] 배틀패스 바는 직접 만지지 않는다.
        --   슬롯·투표 겹침 회피 로직(407행 apply)과 소유권을 다투면 서로 덮어쓴다.
        --   _G.HudRoundActive 를 먼저 갱신한 뒤 그쪽에 위임한다 — 순서가 중요하다.
        --   apply 가 아직 준비 전(WaitForChild 대기)이면 그쪽이 생성 직후 스스로 적용한다.
        if _G.applyBpBarVisibility then pcall(_G.applyBpBarVisibility) end
        if _G.syncHudRightBtns then _G.syncHudRightBtns() end
    end

    if phaseEvent then
        phaseEvent.OnClientEvent:Connect(function(phase)
            currentPhase = phase
            refreshHudVisibility()
        end)
    end
    if stage2Event then
        stage2Event.OnClientEvent:Connect(function()
            currentPhase = "stage2"
            refreshHudVisibility()
        end)
    end

    -- 생존/관전 상태 변화 시 갱신 (죽으면 다시 보이게)
    -- 이벤트를 놓쳐도 상태 변화로 따라잡는다 (재시작 대비 이중 안전장치)
    ReplicatedStorage:GetAttributeChangedSignal("RoundPhase"):Connect(function()
    	currentPhase = ReplicatedStorage:GetAttribute("RoundPhase") or "intermission"
    	refreshHudVisibility()
    end)
    player:GetAttributeChangedSignal("Eliminated"):Connect(refreshHudVisibility)
    player:GetAttributeChangedSignal("Role"):Connect(refreshHudVisibility)
    player:GetAttributeChangedSignal("Spectating"):Connect(refreshHudVisibility)

    refreshHudVisibility()  -- 시작 시 1회 적용
end

print("✅ HudButtonClient 준비! (UnifiedInven 통합)")
