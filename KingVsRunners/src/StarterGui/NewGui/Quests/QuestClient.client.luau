-- ════════════════════════════════════════════════════════════════
-- QuestClient  (StarterGui/NewGui/Quests / LocalScript)
-- ────────────────────────────────────────────────────────────────
-- 퀘스트 UI를 서버 데이터(QuestSystem)에 바인딩.
--  · 창(Canvas.Main)이 열릴 때 QuestDataEvent로 스냅샷 요청
--  · Daily / Weekly 탭 2개 생성 + 클릭 전환
--  · 선택된 탭의 퀘스트들을 TaskTemplate 복제로 렌더 (진행바 + Claim 버튼)
--  · Claim 클릭 → QuestClaimEvent 발신
--  · QuestUpdateEvent 구독 → 실시간 갱신
--  · 리셋까지 남은 시간 표시 (DescLabel 활용)
-- ════════════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local ConfettiEffect    = require(ReplicatedStorage:WaitForChild("ConfettiEffect"))

local player = Players.LocalPlayer

local screenGui = script.Parent
local main      = screenGui:WaitForChild("Canvas"):WaitForChild("Main")
local list      = main:WaitForChild("List")
local details   = main:WaitForChild("Details")
local tabTemplate  = list:WaitForChild("TabTemplate")
local titleLabel   = details:WaitForChild("TitleLabel")
local descLabel    = details:WaitForChild("DescLabel")
local tasksFrame   = details:WaitForChild("Tasks")
local taskTemplate = tasksFrame:WaitForChild("TaskTemplate")

-- 완주 보상 패널 (좌측 하단)
local completionPanel = main:WaitForChild("CompletionPanel")
local panelTitle    = completionPanel:WaitForChild("PanelTitle")
local panelProgress = completionPanel:WaitForChild("PanelProgress")
local panelClaim    = completionPanel:WaitForChild("PanelClaim")
local panelReward   = completionPanel:WaitForChild("RewardText")

-- 리모트
local dataEvent   = ReplicatedStorage:WaitForChild("QuestDataEvent")    -- RemoteFunction
local updateEvent = ReplicatedStorage:WaitForChild("QuestUpdateEvent")  -- RemoteEvent
local claimEvent  = ReplicatedStorage:WaitForChild("QuestClaimEvent")   -- RemoteEvent

-- ── 상태 ─────────────────────────────────────────────────────────
local currentSnapshot = nil
local selectedTab = "daily"   -- "daily" | "weekly"
local tabButtons = {}         -- ["daily"]=btn, ["weekly"]=btn

-- forward declaration (탭 핸들러가 render를 참조하므로 미리 선언)
local render

-- 색상
local COLOR_FILL_INCOMPLETE = Color3.fromRGB(90, 200, 90)
local COLOR_FILL_COMPLETE   = Color3.fromRGB(255, 190, 50)
local COLOR_CLAIM_READY     = Color3.fromRGB(95, 190, 70)
local COLOR_CLAIM_DONE      = Color3.fromRGB(110, 110, 120)
local COLOR_CLAIM_LOCKED    = Color3.fromRGB(70, 70, 80)

-- ════════════════════════════════════════════════════════════════
-- 탭 버튼 텍스트 헬퍼: 상태 프레임(Active/Inactive)의 라벨 설정
-- ════════════════════════════════════════════════════════════════
local function setTabContent(btn, titleText)
    for _, stateName in ipairs({"Active", "Inactive"}) do
        local frame = btn:FindFirstChild(stateName)
        if frame then
            -- 라벨 수집 후 위치로 구분: 위쪽(Y 작음)=제목, 아래쪽=진행수(미사용)
            local labels = {}
            for _, lbl in ipairs(frame:GetChildren()) do
                if lbl:IsA("TextLabel") then
                    table.insert(labels, lbl)
                end
            end
            table.sort(labels, function(a, b)
                return a.Position.Y.Scale < b.Position.Y.Scale
            end)
            if labels[1] then labels[1].Text = titleText end  -- 제목
            if labels[2] then labels[2].Text = "" end          -- 진행수 칸 비움
        end
    end
end

-- 탭 선택 상태 시각 반영
local function refreshTabVisual()
    for key, btn in pairs(tabButtons) do
        local isSel = (key == selectedTab)
        local active   = btn:FindFirstChild("Active")
        local inactive = btn:FindFirstChild("Inactive")
        if active   then active.Visible   = isSel end
        if inactive then inactive.Visible = not isSel end
    end
end

-- ════════════════════════════════════════════════════════════════
-- 탭 생성 (최초 1회)
-- ════════════════════════════════════════════════════════════════
local function buildTabs()
    if next(tabButtons) ~= nil then return end  -- 이미 생성됨

    local defs = {
        { key = "daily",  title = "Daily",  order = 1 },
        { key = "weekly", title = "Weekly", order = 2 },
    }
    for _, d in ipairs(defs) do
        local btn = tabTemplate:Clone()
        btn.Name = "Tab_" .. d.key
        btn.LayoutOrder = d.order
        btn.Visible = true
        setTabContent(btn, d.title)
        btn.Parent = list

        btn.MouseButton1Click:Connect(function()
            if selectedTab ~= d.key then
                selectedTab = d.key
                refreshTabVisual()
                render()
            end
        end)

        -- [TAB-BADGE] 탭에도 느낌표. 위클리는 탭을 눌러야 보여서
        --   수령 가능한 게 있어도 인지가 안 됐다(실측 2026-08-21: 개발자도 못 알아챔).
        local tb = Instance.new("TextLabel")
        tb.Name = "_TabBadge"
        tb.AnchorPoint = Vector2.new(1, 0.5)
        tb.Position = UDim2.new(1, -10, 0.5, 0)
        tb.Size = UDim2.fromOffset(24, 24)
        tb.BackgroundColor3 = Color3.fromRGB(235, 50, 50)
        tb.Text = "!"
        tb.Font = Enum.Font.GothamBlack
        tb.TextSize = 18
        tb.TextColor3 = Color3.fromRGB(255, 255, 255)
        tb.ZIndex = 20
        tb.Active = false
        tb.Selectable = false
        tb.Visible = false
        tb.Parent = btn
        Instance.new("UICorner", tb).CornerRadius = UDim.new(1, 0)
        local tbs = Instance.new("UIStroke", tb)
        tbs.Color = Color3.fromRGB(255, 255, 255) ; tbs.Thickness = 2
        -- ⚠️ UIStroke 기본값(ContextualStroke)은 텍스트에도 적용된다.
        --    흰 글자 + 흰 테두리 → ! 가 뭉개져 안 보인다(실측 2026-08-21).
        tbs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

        tabButtons[d.key] = btn
    end
    refreshTabVisual()
end

-- [TAB-BADGE] 카테고리별 수령 가능 여부로 탭 배지를 갱신한다.
--   HudButtonClient 의 questHasClaimable 과 같은 판정이지만 카테고리 단위다.
local function refreshTabBadges(snap)
    if type(snap) ~= "table" then return end
    for _, key in ipairs({ "daily", "weekly" }) do
        local btn = tabButtons[key]
        local badge = btn and btn:FindFirstChild("_TabBadge")
        if badge then
            local cat = snap[key]
            local has = false
            if type(cat) == "table" then
                for _, qq in ipairs(cat.quests or {}) do
                    if qq.complete and not qq.claimed then has = true break end
                end
                if not has and cat.allClaimed and not cat.bonusClaimed then has = true end
            end
            badge.Visible = has
        end
    end
end

-- ════════════════════════════════════════════════════════════════
-- 퀘스트 줄 렌더
-- ════════════════════════════════════════════════════════════════
local function renderTasks(catData)
    -- 기존 줄 제거 (템플릿/레이아웃 제외)
    for _, c in ipairs(tasksFrame:GetChildren()) do
        if c:IsA("Frame") and c.Name == "QuestRow" then
            c:Destroy()
        end
    end
    if not catData then return end

    for i, q in ipairs(catData.quests) do
        local row = taskTemplate:Clone()
        row.Name = "QuestRow"
        row.LayoutOrder = i
        row.Visible = true

        local qName = row:FindFirstChild("QName")
        local qDesc = row:FindFirstChild("QDesc")
        local qProg = row:FindFirstChild("QProgress")
        local barBG = row:FindFirstChild("BarBG")
        local barFill = barBG and barBG:FindFirstChild("BarFill")
        local claimBtn = row:FindFirstChild("ClaimButton")

        if qName then qName.Text = q.title end
        if qDesc then
            qDesc.Text = q.desc or ""
            -- [REWARD-BADGE] 보상 배지(0.60~0.83)와 겹치지 않게 폭을 줄인다.
            --   원본 0.78 → 0.55. QDesc 는 TextScaled 라 글자가 작아질 뿐 잘리지 않는다.
            --   ⚠️ 보상이 없는 퀘스트는 원래 폭을 유지한다.
            qDesc.Size = UDim2.new(q.reward and 0.50 or 0.78, 0, qDesc.Size.Y.Scale, 0)
        end
        if qProg then qProg.Text = string.format("%d/%d", q.progress, q.goal) end

        -- [REWARD-BADGE] 보상 표기. 서버가 스냅샷에 reward 를 담아 보낸다(QuestSystem:416).
        --   기존엔 제목·설명·진행도만 있어 Claim 을 눌러도 뭘 받는지 알 수 없었다.
        --   코인 아이콘은 HUD 의 것을 재사용해 일관성을 맞춘다.
        if q.reward then
            local badge = Instance.new("Frame")
            badge.Name = "RewardBadge"
            -- ⚠️ 템플릿의 다른 요소가 전부 scale 기반이라 여기도 scale 로 맞춘다.
            --    offset 을 쓰면 해상도가 바뀔 때 혼자 어긋난다.
            --    실측 배치: QName 0.03~0.58 / QProgress 0.58~0.80 / ClaimButton 0.84~0.99
            --               BarBG 0.03~0.83(하단) / QDesc 0.03~0.81(중단)
            --    → 빈 곳은 QProgress 아래·진행바 오른쪽. 그 구간(0.60~0.83)에 둔다.
            badge.AnchorPoint = Vector2.new(1, 0)
            badge.Position = UDim2.fromScale(0.83, 0.36)
            badge.Size = UDim2.fromScale(0.28, 0.26)
            badge.BackgroundTransparency = 1
            badge.Parent = row

            local lay = Instance.new("UIListLayout", badge)
            lay.FillDirection = Enum.FillDirection.Horizontal
            lay.HorizontalAlignment = Enum.HorizontalAlignment.Right
            lay.VerticalAlignment = Enum.VerticalAlignment.Center
            lay.Padding = UDim.new(0.03, 0)
            lay.SortOrder = Enum.SortOrder.LayoutOrder

            local order = 0
            local function addPart(imageId, text, tint)
                order = order + 1
                if imageId then
                    local ic = Instance.new("ImageLabel")
                    ic.LayoutOrder = order
                    ic.BackgroundTransparency = 1
                    ic.Size = UDim2.fromScale(0.18, 1)
                    ic.SizeConstraint = Enum.SizeConstraint.RelativeYY
                    ic.Image = imageId
                    ic.ScaleType = Enum.ScaleType.Fit
                    ic.Parent = badge
                    order = order + 1
                end
                local tl = Instance.new("TextLabel")
                tl.LayoutOrder = order
                tl.BackgroundTransparency = 1
                tl.Size = UDim2.fromScale(imageId and 0.74 or 0.95, 1)
                tl.Font = Enum.Font.GothamBold
                tl.TextScaled = true
                tl.TextXAlignment = Enum.TextXAlignment.Left
                tl.TextColor3 = tint or Color3.fromRGB(255, 216, 96)
                tl.TextStrokeTransparency = 0.5
                tl.Text = text
                tl.Parent = badge
            end

            if q.reward.coins and q.reward.coins > 0 then
                -- HUD.Canvas.Currency.Gold.Icon 과 동일한 에셋
                -- ⚠️ 아이콘만으로는 작아서 무엇인지 안 읽힌다(실측 2026-08-21).
                --    "Coins" 단위를 함께 적어 상자 개수 등으로 오해되지 않게 한다.
                addPart("rbxassetid://109002720549611", q.reward.coins .. " Coins")
            end
            if q.reward.spins and q.reward.spins > 0 then
                addPart(nil, "x" .. q.reward.spins .. " Spin", Color3.fromRGB(140, 220, 255))
            end
            if q.reward.box then
                local boxName = (q.reward.box == "skin") and "Skin Box"
                    or (q.reward.box == "killeffect") and "Effect Box" or "Box"
                addPart(nil, boxName, Color3.fromRGB(200, 160, 255))
            end
        end

        -- 진행바 채움 비율
        local ratio = (q.goal > 0) and math.clamp(q.progress / q.goal, 0, 1) or 0
        if barFill then
            barFill.Size = UDim2.fromScale(ratio, 1)
            barFill.BackgroundColor3 = q.complete and COLOR_FILL_COMPLETE or COLOR_FILL_INCOMPLETE
        end

        -- Claim 버튼 상태
        if claimBtn then
            if q.claimed then
                claimBtn.Text = "Done"
                claimBtn.BackgroundColor3 = COLOR_CLAIM_DONE
                claimBtn.AutoButtonColor = false
                claimBtn.Active = false
            elseif q.complete then
                claimBtn.Text = "Claim"
                claimBtn.BackgroundColor3 = COLOR_CLAIM_READY
                claimBtn.AutoButtonColor = true
                claimBtn.Active = true
            else
                claimBtn.Text = "Locked"
                claimBtn.BackgroundColor3 = COLOR_CLAIM_LOCKED
                claimBtn.AutoButtonColor = false
                claimBtn.Active = false
            end

            local questId = q.id
            claimBtn.MouseButton1Click:Connect(function()
                -- 달성 + 미수령일 때만 의미 있음 (서버가 최종 검증)
                if q.complete and not q.claimed then
                    claimEvent:FireServer(questId)
                    ConfettiEffect.play()   -- 퀘스트 수령 축하
                end
            end)
        end

        row.Parent = tasksFrame
    end
end

-- 리셋까지 남은 시간 문자열
local function formatTimeLeft(catData, lengthSec, serverNow)
    if not catData or not catData.lastReset then return "" end
    local elapsed = (serverNow or os.time()) - catData.lastReset
    local remaining = math.max(0, lengthSec - elapsed)
    local h = math.floor(remaining / 3600)
    local m = math.floor((remaining % 3600) / 60)
    if h >= 24 then
        local d = math.floor(h / 24)
        return string.format("Resets in: %dd %dh", d, h % 24)
    end
    return string.format("Resets in: %dh %dm", h, m)
end

-- ════════════════════════════════════════════════════════════════
-- 완주 보상 패널 갱신
-- ════════════════════════════════════════════════════════════════
local COLOR_PANEL_READY  = Color3.fromRGB(95, 190, 70)
local COLOR_PANEL_DONE   = Color3.fromRGB(110, 110, 120)
local COLOR_PANEL_LOCKED = Color3.fromRGB(70, 70, 80)

local function renderCompletionPanel(catData)
    if not catData then return end
    local claimed = catData.claimedCount or 0
    local total   = catData.total or 0

    panelTitle.Text = (selectedTab == "daily")
        and "Complete All Dailies" or "Complete All Weeklies"
    panelProgress.Text = string.format("%d/%d completed", claimed, total)

    -- 보상 내용 텍스트 (서버가 준 bonusReward 기반)
    local br = catData.bonusReward
    if br then
        local lines = {}
        if br.coins and br.coins > 0 then
            table.insert(lines, string.format("+%d Coins", br.coins))
        end
        if br.spins and br.spins > 0 then
            table.insert(lines, string.format("+%d Spins", br.spins))
        end
        if br.box then
            local boxName = (br.box == "skin") and "Skin Box"
                or (br.box == "killeffect") and "Kill Effect Box"
                or "Box"
            table.insert(lines, "+1 " .. boxName)
        end
        panelReward.Text = table.concat(lines, string.char(10))
    end

    if catData.bonusClaimed then
        panelClaim.Text = "Done"
        panelClaim.BackgroundColor3 = COLOR_PANEL_DONE
        panelClaim.AutoButtonColor = false
        panelClaim.Active = false
    elseif catData.allClaimed then
        panelClaim.Text = "Claim"
        panelClaim.BackgroundColor3 = COLOR_PANEL_READY
        panelClaim.AutoButtonColor = true
        panelClaim.Active = true
    else
        panelClaim.Text = "Locked"
        panelClaim.BackgroundColor3 = COLOR_PANEL_LOCKED
        panelClaim.AutoButtonColor = false
        panelClaim.Active = false
    end
end

-- Claim 버튼은 1회만 연결 (selectedTab을 클릭 시점에 읽음)
panelClaim.MouseButton1Click:Connect(function()
    if not currentSnapshot then return end
    local catData = currentSnapshot[selectedTab]
    if catData and catData.allClaimed and not catData.bonusClaimed then
        claimEvent:FireServer("completion:" .. selectedTab)
        ConfettiEffect.play()   -- 전체 완료 보너스 수령 축하
    end
end)

-- ════════════════════════════════════════════════════════════════
-- 전체 렌더
-- ════════════════════════════════════════════════════════════════
render = function()
    if not currentSnapshot then return end
    local catData = currentSnapshot[selectedTab]

    titleLabel.Text = (selectedTab == "daily") and "Daily Quests" or "Weekly Quests"

    local length = (selectedTab == "daily")
        and currentSnapshot.dayLength or currentSnapshot.weekLength
    descLabel.Text = formatTimeLeft(catData, length, currentSnapshot.serverNow)

    renderTasks(catData)
    renderCompletionPanel(catData)
end

-- ════════════════════════════════════════════════════════════════
-- 데이터 요청
-- ════════════════════════════════════════════════════════════════
local function requestData()
    local ok, snap = pcall(function()
        return dataEvent:InvokeServer()
    end)
    if ok and snap then
        currentSnapshot = snap
        buildTabs()
        render()
        refreshTabBadges(snap)
    end
end

-- 서버 push 구독 (라운드 후 진행 갱신, 수령 결과 등)
-- [CLAIM-FEEDBACK] 수령 결과 토스트.
--   ⚠️ 화면 중앙 상단에 띄운다. 퀘스트 창이 열려 있어도 가리지 않는 위치.
local function showClaimToast(info)
	if not info then return end
	local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "QuestClaimToast"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	gui.Parent = pg

	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, 0.10)
	card.Size = UDim2.fromScale(0.30, 0.10)
	card.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
	card.BackgroundTransparency = 0.08
	card.Parent = gui
	Instance.new("UICorner", card).CornerRadius = UDim.new(0.16, 0)
	local st = Instance.new("UIStroke", card)
	st.Color = Color3.fromRGB(255, 216, 96) ; st.Thickness = 2

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.04, 0.08)
	title.Size = UDim2.fromScale(0.92, 0.36)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "Claimed: " .. tostring(info.title or "Quest")
	title.Parent = card

	-- 보상 줄 (아이콘 + 값)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(0.04, 0.50)
	row.Size = UDim2.fromScale(0.92, 0.40)
	row.Parent = card
	local lay = Instance.new("UIListLayout", row)
	lay.FillDirection = Enum.FillDirection.Horizontal
	lay.VerticalAlignment = Enum.VerticalAlignment.Center
	lay.Padding = UDim.new(0.02, 0)
	lay.SortOrder = Enum.SortOrder.LayoutOrder

	local ord = 0
	local function part(imageId, text, tint)
		ord = ord + 1
		if imageId then
			local ic = Instance.new("ImageLabel")
			ic.LayoutOrder = ord ; ic.BackgroundTransparency = 1
			ic.Size = UDim2.fromScale(1, 1)
			ic.SizeConstraint = Enum.SizeConstraint.RelativeYY
			ic.Image = imageId ; ic.ScaleType = Enum.ScaleType.Fit
			ic.Parent = row
			ord = ord + 1
		end
		local tl = Instance.new("TextLabel")
		tl.LayoutOrder = ord ; tl.BackgroundTransparency = 1
		tl.Size = UDim2.fromScale(0.42, 1)
		tl.Font = Enum.Font.GothamBold ; tl.TextScaled = true
		tl.TextXAlignment = Enum.TextXAlignment.Left
		tl.TextColor3 = tint or Color3.fromRGB(255, 216, 96)
		tl.Text = text
		tl.Parent = row
	end

	local r = info.reward or {}
	if r.coins and r.coins > 0 then
		part("rbxassetid://109002720549611", "+" .. r.coins .. " Coins")
	end
	if r.spins and r.spins > 0 then
		part(nil, "+" .. r.spins .. " Spin", Color3.fromRGB(140, 220, 255))
	end
	if r.box then
		local bn = (r.box == "skin") and "Skin Box"
			or (r.box == "killeffect") and "Effect Box" or "Box"
		part(nil, bn, Color3.fromRGB(200, 160, 255))
	end

	-- 등장/퇴장 애니
	local TweenService = game:GetService("TweenService")
	card.Position = UDim2.fromScale(0.5, 0.04)
	local sc = Instance.new("UIScale", card) ; sc.Scale = 0.85
	TweenService:Create(card, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.10) }):Play()
	TweenService:Create(sc, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
	task.delay(2.4, function()
		TweenService:Create(card, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(sc, TweenInfo.new(0.25), { Scale = 0.9 }):Play()
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			elseif d:IsA("ImageLabel") then
				TweenService:Create(d, TweenInfo.new(0.25), { ImageTransparency = 1 }):Play()
			elseif d:IsA("UIStroke") then
				TweenService:Create(d, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			end
		end
		task.wait(0.3)
		gui:Destroy()
	end)
end

updateEvent.OnClientEvent:Connect(function(snap, info)
	-- [CLAIM-FEEDBACK] 첫 인자가 문자열이면 스냅샷이 아니라 수령 알림이다.
	--   pushToClient 는 FireClient(player, snapshot) 로 테이블을 보낸다.
	if snap == "claimed" then
		showClaimToast(info)
		return
	end
    if snap then
        currentSnapshot = snap
        -- 창이 닫혀 있어도 미리 갱신해 둠 (첫 열기 시 즉시 표시)
        buildTabs()
        render()
        refreshTabBadges(snap)
    end
end)

-- 창 열림 감지 → 최신 데이터 요청
main:GetPropertyChangedSignal("Visible"):Connect(function()
    if main.Visible then
        requestData()
    end
end)

-- 시작 시 미리 데이터를 받아 탭·내용까지 빌드해 둠
-- (첫 클릭 시 빈 화면처럼 보이는 문제 방지 — 열기 전에 이미 렌더 완료)
task.spawn(function()
    -- 서버가 응답 가능할 때까지 몇 차례 시도
    for attempt = 1, 10 do
        local ok, snap = pcall(function()
            return dataEvent:InvokeServer()
        end)
        if ok and snap then
            currentSnapshot = snap
            buildTabs()
            render()
            refreshTabBadges(snap)
            break
        end
        task.wait(0.5)
    end
end)

-- ── X(닫기) 버튼 연결 ────────────────────────────────────────────
-- toggleGui와 동일하게 Canvas.Main.Visible 토글로 닫음
local closeButton = main:FindFirstChild("Close")
if closeButton then
    closeButton.MouseButton1Click:Connect(function()
        main.Visible = false
    end)
    print("✅ Quests 닫기(X) 버튼 연결됨")
else
    warn("⚠️ Close 버튼을 찾지 못함")
end

print("✅ QuestClient 활성화")
