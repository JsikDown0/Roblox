local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player   = Players.LocalPlayer
local event    = ReplicatedStorage:WaitForChild("EmotionEvent")
local getEquippedEmotes  = ReplicatedStorage:WaitForChild("GetEquippedEmotes")
local emoteEquipChanged  = ReplicatedStorage:WaitForChild("EmoteEquipChanged")

local COOLDOWN = 2
local lastUsed = 0
local isOpen   = true

local gui       = script.Parent
local bar       = gui:WaitForChild("EmoteBar")
local toggleBtn = bar:WaitForChild("ToggleBtn")
local divider   = bar:WaitForChild("Divider")
local guriBtn   = bar:WaitForChild("Btn7")  -- guri: 항상 고정

bar.ClipsDescendants = true

-- 화면 가장자리까지 사용 (자동 인셋 무시 — 더 좌측 끝에 붙음)
-- 안전영역 기준을 TaggerItemUI/HUD와 통일 (DeviceSafeInsets).
-- 과거엔 None으로 화면 끝까지 썼는데, 그러면 좌표 원점이 달라져 태거 아이템 리스트와
-- 같은 (1,-10)을 써도 47px 어긋남(실측). 노치·둥근모서리 잘림 위험도 있어 통일.
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
-- 인벤(UnifiedInven DO=10)·로드아웃 프리뷰(DO=12)보다 위로.
-- 아래 있으면 인벤 열었을 때 이모트 바가 패널 뒤로 깔려 안 보임.
gui.DisplayOrder = 13

-- ── 반응형 스케일 + 위치 (디바이스별, 공통 모듈) ──────────────
local Scaler = require(ReplicatedStorage:WaitForChild("ResponsiveScaler"))
Scaler.applyEdge(gui, bar, {
	baseW = 1280, baseH = 720,
	anchor = Vector2.new(0, 1),  -- 좌하단 (우측 KING ITEMS와 안 겹치게 좌측 끝으로)
	Mobile = { pos = UDim2.new(0, 20, 1, -200), minScale = 0.55 },
	PC     = { pos = UDim2.new(0, 20, 1, -200), minScale = 0.55 },  -- ← PC용. 자유 조정
})

-- 모바일도 PC와 동일하게 좌하단 유지 (위 applyEdge의 Mobile pos 사용).
-- 과거엔 여기서 우측으로 덮어썼음 — 조이스틱과 겹친다는 이유. 겹치면 31줄 Mobile pos의
-- Y(-200)를 더 키워 위로 올릴 것. (좌우를 바꾸는 대신 높이로 회피)

-- ── 로드아웃 세트 표시용 상자 ──────────────────────────────────
-- 인벤(로드아웃 패널)이 열릴 때만 켜서 "이모트도 로드아웃에 함께 저장됨"을 시각화.
-- bar의 자식으로 두는 게 핵심: 위치·크기·UIScale을 자동으로 따라가므로
-- 별도 GUI를 나란히 놓을 때 생기는 정렬 어긋남이 원천적으로 없음.
local BOX_PAD     = 5
local BOX_LABEL_H = 12
local loadoutBox = Instance.new("Frame")
loadoutBox.Name = "LoadoutBox"
loadoutBox.Position = UDim2.new(0, -BOX_PAD, 0, -BOX_PAD - BOX_LABEL_H)
loadoutBox.Size     = UDim2.new(1, BOX_PAD * 2, 1, BOX_PAD * 2 + BOX_LABEL_H)
loadoutBox.BackgroundColor3 = Color3.fromRGB(16, 19, 28)   -- 로드아웃 패널 섹션과 동일
loadoutBox.BackgroundTransparency = 0.08
loadoutBox.BorderSizePixel = 0
loadoutBox.ZIndex = 0                                       -- 이모트 바 뒤에 깔림
loadoutBox.Visible = false
-- ⚠ bar의 자식으로 두면 안 됨: bar에 UIListLayout이 있어서 상자가 리스트 항목으로
-- 배치돼 버튼 옆에 나란히 놓임. 같은 ScreenGui의 형제로 두고 위치·크기를 미러링한다.
-- (같은 GUI라 UIScale은 여전히 공유 → 정렬 어긋남 없음)
loadoutBox.Parent = bar.Parent
Instance.new("UICorner", loadoutBox).CornerRadius = UDim.new(0, 10)
do
	local st = Instance.new("UIStroke", loadoutBox)
	st.Color = Color3.fromRGB(70, 130, 210)   -- RUNNER SET 섹션과 같은 파랑
	st.Thickness = 1.5
end
do
	local bl = Instance.new("TextLabel")
	bl.Size = UDim2.new(1, -20, 0, 13)
	bl.Position = UDim2.new(0, 10, 0, 5)
	bl.BackgroundTransparency = 1
	bl.Text = "EMOTE SET"
	bl.TextColor3 = Color3.fromRGB(165, 175, 195)
	bl.Font = Enum.Font.GothamBold
	bl.TextSize = 12
	bl.TextXAlignment = Enum.TextXAlignment.Left
	bl.ZIndex = 1
	bl.Parent = loadoutBox
end
-- (_G.EmoteLoadoutBox 정의는 applyEmotePlacement 선언 이후로 이동 — 아래 참조)

-- ── 배치 (인벤 상태에 따라 전환) ──────────────────────────────
-- 모바일은 두 요구가 서로 다른 순간에 발생함:
--   · 플레이 중(인벤 닫힘) → 조이스틱·점프·스킬 버튼을 피해야 함 = 하단 중앙
--   · 편집 중(인벤 열림)   → 로드아웃 패널과 같은 열이어야 "같이 저장됨"이 읽힘 = 좌측
-- PC는 조이스틱이 없으므로 항상 좌측 유지.
-- 좌측 X는 20/s 역보정: 로드아웃 패널은 UIScale이 root에 걸려 Position(20)이 절대값인 반면,
-- 이 GUI는 UIScale이 ScreenGui에 걸려 Position도 축소되기 때문.
local PANEL_LEFT   = 20
local BASE_Y       = -200   -- 좌측 배치 기본 높이
local NUDGE_OPEN   = 195    -- (폴백 전용) 패널을 못 찾았을 때만 사용
local PANEL_GAP    = 6      -- 로드아웃 패널 하단 ↔ EMOTE SET 박스 상단 간격(px)
-- 태거 아이템 리스트(TaggerItemUI.ItemList) 바로 아래에 붙이기 위한 값.
-- ItemList: AnchorPoint(1,0.5), Position(1,-10)(0.5,0), Size 200x400.
-- TaggerItemUI도 동일한 UIScale 공식(1280x720 기준, 최소 0.55)을 ScreenGui에 걸어서
-- offset 단위가 그대로 통용됨 → 역보정 불필요.
local LIST_RIGHT   = 10     -- ItemList 우측 여백
local LIST_HALF_H  = 200    -- ItemList 높이 400의 절반
local LIST_GAP     = 8
local MOBILE_LEFT_X = 20    -- 좌측 여백
local MOBILE_MID_Y  = -60   -- 화면 세로 중앙 기준 오프셋(조이스틱 위)
local LOBBY_BOTTOM_Y = -200  -- 로비: 화면 하단에서 위로(점프 버튼 회피)
-- 모바일 플레이 중 이모트 바의 상단 오프셋(px).
-- Settings/Spectate(상단 ~120) 아래, SkillBar·점프버튼(하단) 위의 빈 구간.
local invOpen = false

-- 이 GUI의 좌표 원점 기준점. AbsolutePosition을 로컬 오프셋으로 환산할 때 사용.
local originRef = Instance.new("Frame")
originRef.Name = "OriginRef"
originRef.Size = UDim2.fromOffset(0, 0)
originRef.Position = UDim2.fromOffset(0, 0)
originRef.BackgroundTransparency = 1
originRef.Visible = false
originRef.Parent = bar.Parent

-- 라운드 진행 중인지 판정 (클라이언트).
-- HudButtonClient 가 라운드 중 좌측 HUD(Currency)를 숨기므로 그 상태를 신호로 쓴다.
-- 같은 판단을 두 번 구현하면 어긋나므로 결과만 읽는다.
local function isInRound()
	-- ⚠️ HUD 는 PlayerGui 최상위가 아니라 PlayerGui.NewGui.HUD 에 있다.
	--    (StarterGui.NewGui 폴더째로 복사되기 때문)
	--    최상위만 찾으면 항상 nil → isInRound() 가 늘 false → 라운드에도 로비 위치였다.
	local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then return false end
	local currency = pg:FindFirstChild("Currency", true)   -- 재귀 검색
	if not currency then return false end
	return not currency.Visible
end

local function applyEmotePlacement()
	local us = gui:FindFirstChildOfClass("UIScale") or bar.Parent:FindFirstChildOfClass("UIScale")
	local s = (us and us.Scale) or 1
	if s <= 0 then s = 1 end
	-- ⚠️ [ROUND-ANCHOR] 라운드 중에는 플랫폼과 무관하게 '좌측 세로중앙' 하나로 고정한다.
	--    예전엔 배치 분기가 4가지(모바일 라운드/로비, PC 패널추종/하단)라 상황이 바뀔 때마다
	--    앵커까지 (0,0.5)→(1,1)→(0,0)→(0,1) 로 달라져 바가 화면 반대편으로 날아갔다.
	--    ReviveClient 가 이 바를 추종하므로 그 불안정이 그대로 전파돼
	--    "이모트-리바이브 겹침"이 세션마다 재발했다(실측 2026-08-22).
	--    → 기준이 안 움직이면 추종이 실패할 여지 자체가 사라진다.
	--    ⚠️ 로비는 메타 UI(로드아웃 패널)와의 관계가 있어 기존 분기를 유지한다.
	if isInRound() and not invOpen then
		bar.AnchorPoint = Vector2.new(0, 0.5)
		bar.Position = UDim2.new(0, MOBILE_LEFT_X, 0.5, MOBILE_MID_Y)
		return
	end

	if Scaler.isMobile() and not invOpen then
		if isInRound() then
			-- 라운드 중: 우측은 태거 아이템 리스트(ItemList)가 세로로 길게 차지해 쓸 수 없다.
			-- 좌측 중앙은 HUD 가 숨겨져 비어 있으므로 그리로 보낸다.
			bar.AnchorPoint = Vector2.new(0, 0.5)
			bar.Position = UDim2.new(0, MOBILE_LEFT_X, 0.5, MOBILE_MID_Y)
		else
			-- 로비: 우측. 화면 하단 기준으로 점프 버튼 위에 올린다.
			-- ⚠️ 기존 Y = 0.5H + 208 은 화면이 클수록 아래로 내려가 점프 버튼과 겹쳤다
			--    (640 에서 52px, 720 에서 68px 겹침 — 실측).
			--    하단 기준(anchor 1,1) + 고정 오프셋이면 해상도와 무관하게 항상 버튼 위다.
			bar.AnchorPoint = Vector2.new(1, 1)
			bar.Position = UDim2.new(1, -LIST_RIGHT, 1, LOBBY_BOTTOM_Y)
		end
		return
	end
	-- 인벤 열림(또는 PC): 로드아웃 패널 "바로 아래"에 붙인다.
	-- ⚠ 화면 하단 기준(anchor 1)으로 두면 안 됨 — 패널은 화면 중앙 기준이라
	--    화면이 커질수록 둘 사이가 벌어짐(아이패드에서 이모트만 아래로 떨어지던 원인).
	--    패널의 실제 렌더 위치를 읽어 따라가면 기기와 무관하게 항상 붙는다.
	local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	local lpg = pg and pg:FindFirstChild("LoadoutPreviewGui")
	local root = lpg and (lpg:FindFirstChild("Root", true) or lpg:FindFirstChild("root", true))
	bar.AnchorPoint = Vector2.new(0, 0)
	if root and root:IsA("GuiObject") and root.AbsoluteSize.Y > 0 then
		local panelBottom = root.AbsolutePosition.Y + root.AbsoluteSize.Y
		local originY = originRef.AbsolutePosition.Y
		local topAbs = panelBottom + PANEL_GAP + (BOX_PAD + BOX_LABEL_H) * s
		bar.Position = UDim2.new(0, (PANEL_LEFT / s) + BOX_PAD, 0, (topAbs - originY) / s)
	else
		-- 패널을 못 찾으면 종전 방식으로 폴백
		bar.AnchorPoint = Vector2.new(0, 1)
		bar.Position = UDim2.new(0, (PANEL_LEFT / s) + BOX_PAD, 1, BASE_Y + NUDGE_OPEN)
	end
end

-- 박스는 bar를 감싸되 앵커 방향에 따라 패딩 부호가 달라짐.
-- (좌하단 (0,1) / 우상단 (1,0) 두 배치를 모두 지원)
local function syncLoadoutBox()
	local a = bar.AnchorPoint
	loadoutBox.AnchorPoint = a
	local dx = (a.X == 1) and BOX_PAD or -BOX_PAD
	local dy = (a.Y == 1) and BOX_PAD or -(BOX_PAD + BOX_LABEL_H)
	loadoutBox.Position = bar.Position + UDim2.fromOffset(dx, dy)
	loadoutBox.Size     = bar.Size     + UDim2.fromOffset(BOX_PAD * 2, BOX_PAD * 2 + BOX_LABEL_H)
end

applyEmotePlacement()
syncLoadoutBox()

-- ⚠️ [PANEL-FOLLOW] LoadoutPreviewGui.Root 의 크기·위치 변화를 구독한다.
--    계산식(157~165행)은 정상이지만 '언제 다시 계산하는가'가 부족했다:
--      기존 트리거 = 뷰포트 변경 / 라운드 전환(0.5초 폴링) / 인벤 토글
--      → Root 가 커지거나 내용이 바뀌면 이모트 바가 그 자리에 남는다.
--    ReviveClient 가 이모트 바를 따라가므로 이 지연이 REVIVE 까지 전파된다.
--    ⚠️ Root 는 런타임 생성이라 처음엔 없을 수 있다 → 생길 때까지 기다렸다 건다.
task.spawn(function()
	local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then return end
	local hooked = false
	local function hook()
		if hooked then return true end
		local lpg = pg:FindFirstChild("LoadoutPreviewGui")
		local root = lpg and (lpg:FindFirstChild("Root", true) or lpg:FindFirstChild("root", true))
		if not (root and root:IsA("GuiObject")) then return false end
		hooked = true
		local function refresh() task.defer(applyEmotePlacement) end
		root:GetPropertyChangedSignal("AbsolutePosition"):Connect(refresh)
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
		root:GetPropertyChangedSignal("Visible"):Connect(refresh)
		return true
	end
	for _ = 1, 40 do
		if hook() then return end
		task.wait(0.25)
	end
end)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
	task.defer(applyEmotePlacement)
end)

-- 라운드 시작/종료 시 위치를 다시 계산한다.
-- ⚠️ Currency.Visible 에 이벤트를 연결하는 방식은 못 쓴다.
--    HUD 는 ResetOnSpawn=true 라 재스폰마다 새 인스턴스로 교체되는데,
--    EmotionBarGui 는 ResetOnSpawn=false 라 살아남는다.
--    → 연결이 죽은 인스턴스에 남아 라운드 전환을 못 알아채고 로비 위치에 머물렀다(실측).
--    주기 확인은 인스턴스가 교체돼도 항상 현재 상태를 읽는다. 0.5초 간격이면 부담 없다.
task.spawn(function()
	local lastInRound = nil
	while true do
		task.wait(0.5)
		local now = isInRound()
		if now ~= lastInRound then
			lastInRound = now
			applyEmotePlacement()
		end
	end
end)
bar:GetPropertyChangedSignal("Position"):Connect(syncLoadoutBox)
bar:GetPropertyChangedSignal("Size"):Connect(syncLoadoutBox)
bar:GetPropertyChangedSignal("AnchorPoint"):Connect(syncLoadoutBox)


-- 박스 표시와 배치 전환을 함께 처리 (위치 결정은 이 스크립트가 단독 소유).
_G.EmoteLoadoutBox = function(show)
	invOpen = show and true or false
	loadoutBox.Visible = invOpen
	applyEmotePlacement()
end

local SIZE_CLOSED = UDim2.new(0, 56,  0, 68)

local TWEEN_INFO   = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_TOGGLE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local currentEmotes = {}  -- { {id, icon}, ... }

local function calcOpenWidth(count)
	-- ToggleBtn(44) + Divider(2) + spacing×2(12) + emoteBtn×count + guriBtn(44) + padding(12)
	return 114 + (count + 1) * 50
end

local function setOpen(open)
	isOpen = open
	local w = open and calcOpenWidth(#currentEmotes) or 56
	TweenService:Create(bar, TWEEN_INFO, {Size = UDim2.new(0, w, 0, 68)}):Play()
	toggleBtn.BackgroundColor3 = open
		and Color3.fromRGB(80, 80, 80)
		or  Color3.fromRGB(60, 60, 100)
end

-- ── 이모티콘 버튼 클릭 공통 처리 ────────────────────────────
local function fireEmote(emoji)
	local now = tick()
	if now - lastUsed < COOLDOWN then return end
	lastUsed = now
	event:FireServer(emoji)
end

-- ── 동적 버튼 플래시 효과 ────────────────────────────────────
local function flashBtn(btn)
	local orig = btn.BackgroundColor3
	btn.BackgroundColor3 = Color3.fromRGB(100, 100, 200)
	task.delay(0.15, function()
		if btn and btn.Parent then
			btn.BackgroundColor3 = orig
		end
	end)
end

-- ── 바 동적 재구성 ────────────────────────────────────────────
local function rebuildBar(equippedList)
	currentEmotes = equippedList or {}

	-- 기존 동적 버튼(Btn1~Btn6) 제거
	for _, child in ipairs(bar:GetChildren()) do
		if child.Name:match("^Btn%d+$") and child ~= guriBtn then
			child:Destroy()
		end
	end

	-- 장착된 이모트 버튼 생성 (LayoutOrder 2~7)
	for i, emoteData in ipairs(currentEmotes) do
		local btn = Instance.new("TextButton")
		btn.Name              = "Btn" .. i
		btn.Size              = UDim2.new(0, 44, 0, 44)
		btn.BackgroundColor3  = Color3.fromRGB(50, 50, 50)
		btn.BackgroundTransparency = 0.3
		btn.TextScaled        = true   -- 버튼 크기에 꽉 차게
		btn.Font              = Enum.Font.GothamBold
		btn.LayoutOrder       = i + 1
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0.2, 0)
		btn.Parent = bar

		local hasImage = (emoteData.imageId ~= nil and emoteData.imageId ~= "")
		local payload
		if hasImage then
			btn.Text = ""
			local img = Instance.new("ImageLabel")
			img.Size = UDim2.new(1, -4, 1, -4)
			img.Position = UDim2.new(0, 2, 0, 2)
			img.BackgroundTransparency = 1
			img.Image = emoteData.imageId
			img.ScaleType = Enum.ScaleType.Fit
			img.Parent = btn
			payload = emoteData.id          -- 서버가 id→imageId 조회
		else
			btn.Text = emoteData.icon
			payload = emoteData.icon        -- 레거시 이모지
		end

		btn.MouseButton1Click:Connect(function()
			flashBtn(btn)
			fireEmote(payload)
		end)
	end

	-- guri 버튼 LayoutOrder: 항상 마지막
	guriBtn.LayoutOrder = #currentEmotes + 2

	-- 열린 상태면 바 크기 업데이트
	if isOpen then
		local w = calcOpenWidth(#currentEmotes)
		TweenService:Create(bar, TWEEN_INFO, {Size = UDim2.new(0, w, 0, 68)}):Play()
	end
end

-- ── guri 버튼 연결 (항상 고정) ───────────────────────────────
guriBtn.MouseButton1Click:Connect(function()
	flashBtn(guriBtn)
	fireEmote("__GURI__")
end)

-- ── 토글 버튼 ────────────────────────────────────────────────
toggleBtn.MouseButton1Click:Connect(function()
	setOpen(not isOpen)
end)

-- 키보드 B 토글 (F는 무기 스킬 통일키로 이관)
toggleBtn.Text = "B"   -- 인스턴스 속성 대신 스크립트에서 지정(Ctrl+S 없이 유지)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.B then
		setOpen(not isOpen)
	end
end)

-- ── 서버에서 장착 변경 알림 수신 ─────────────────────────────
emoteEquipChanged.OnClientEvent:Connect(function(equippedList)
	rebuildBar(equippedList)
end)

-- ── 초기 상태 로드 ────────────────────────────────────────────
task.spawn(function()
	local equippedList = getEquippedEmotes:InvokeServer()
	rebuildBar(equippedList or {})
	-- 초기 바 크기 설정
	local w = isOpen and calcOpenWidth(#currentEmotes) or 56
	bar.Size = UDim2.new(0, w, 0, 68)
end)

print("✅ EmotionBarClient 준비! (동적 이모트 바)")
