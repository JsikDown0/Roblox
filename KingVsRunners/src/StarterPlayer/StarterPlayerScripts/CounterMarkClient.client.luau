-- CounterMarkClient : 카타나 카운터 자세 표식 (킹 화면 전용)
--
-- [왜] 카운터 자세는 서버 애니로 보이긴 하지만, 2단계 전장은 불기둥·이펙트가 많고
--   러너가 뭉쳐 있어 "누가 자세 중인지"가 안 읽힌다. 킹이 실제로 하는 판단은
--   "지금 때려도 되나 / 누굴 피해야 하나" 라서 위치 정보가 있는 월드 표식이 맞다.
--
-- ⚠️ 킹에게만 그린다. DurabilityHitClient 가 같은 이유로 이미 그렇게 한다
--   ("전원에게 띄우면 다수 흡수 시 화면이 표식으로 덮인다").
--   실측 2026-09-14: 세 봇이 1ms 안에 동시 카운터한 판이 있었다.
--   러너 본인은 자기 버튼·자세로 이미 안다.
--
-- [신호] 캐릭터 속성 "KatanaCounter". KatanaSword2 가 WalkSpeedManager 의 flags 로
--   켜고 끈다 — 감속과 같은 source 라 해제가 한 곳으로 묶여 있고,
--   COUNTER_HOLD_TIME 만료가 이중 안전망이다.
--   ⚠️ 이벤트가 아니라 속성을 본다. 캐릭터가 라운드마다 갈려도 현재 값을 바로 읽고
--     연결 해제를 관리할 필요가 없다(TaggerHpDisplay 가 같은 이유로 속성을 쓴다).
--
-- [자리] HP바와 같은 층(3.8)을 쓰고, 뜨는 동안 HP바를 잠깐 숨긴다.
--   [왜 겹쳐도 되나] 축 규칙에서 카운터는 "지금 중요한가"이고 1.5초만 뜬다.
--     그 순간에는 HP 잔량보다 카운터가 더 중요하므로 자리를 받는 게 맞다.
--   [왜 위로 안 올리나] 층을 쌓으면(5.6) 시선이 분산되고, 크기가 층 간격에 묶인다.
--     같은 자리를 쓰면 크게 만들어도 위를 안 밀고 "이 순간은 이 정보가 전부"가 된다.
--   ⚠️ 애초에 RunnerHpBar 도 상시가 아니다 — "맞았을 때만 나타나고 잠시 뒤 사라진다"
--     (BotHealthBarSystem:19). 둘 다 일시 표시라 실제 충돌 빈도는 낮다.
--
-- [색] 진영색 규칙을 따른다. 러너 청(80,170,255) 계열.
--   ⚠️ 빨강은 킹 진영색, 금색은 VIP·과금 축이라 쓰면 안 된다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer

local ATTR       = "KatanaCounter"
local MARK_NAME  = "_CounterMark"
local HPBAR_NAME = "RunnerHpBar"          -- BotHealthBarSystem:77 과 같은 이름
local Y_OFFSET   = 3.8                    -- RunnerHpBar 와 같은 층
local COLOR      = Color3.fromRGB(120, 200, 255)
local STROKE     = Color3.fromRGB(20, 60, 110)
local MAX_DIST   = 300

-- ⚠️ Scale(스터드) 단위. 픽셀 고정은 거리와 무관하게 같은 픽셀이라 원거리에서
--   주변 대비 거대해진다(TaggerHpDisplay:30 이 같은 이유로 기각한 방식).
--   PC 에서 작아 보인다는 실측(09-14)에 따라 3.2×1.1 → 5.0×1.6.
local MARK_SIZE  = UDim2.fromScale(5.0, 1.6)

-- 우리가 숨긴 HP바만 되돌린다.
--   ⚠️ 무조건 Enabled = true 로 밀면 다른 이유로 숨겨진 바까지 켜버린다.
--     약한참조라 캐릭터가 사라지면 자동 정리된다.
local hiddenBars = setmetatable({}, { __mode = "k" })

local function isTagger()
	return localPlayer:GetAttribute("Role") == "Tagger"
end

-- ⚠️ 이름으로 컨테이너를 직접 훑어 중복을 막는다. 지역 변수로 들고 있으면
--   캐릭터 재생성 때 고아가 남는다 — 2026-09-13 Q버튼 복제가 그 형태였다.
local function ensureMark(head)
	local old = head:FindFirstChild(MARK_NAME)
	if old then return old end

	local gui = Instance.new("BillboardGui")
	gui.Name = MARK_NAME
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = MAX_DIST
	gui.Size = MARK_SIZE
	gui.StudsOffset = Vector3.new(0, Y_OFFSET, 0)
	gui.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Text"
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.Text = "⚔ COUNTER"
	lbl.TextColor3 = COLOR
	lbl.TextStrokeTransparency = 0
	lbl.TextStrokeColor3 = STROKE
	lbl.Parent = gui
	return gui
end

-- 상주 스윕. "속성이 켜진 놈만 표식이 있고, 그때만 HP바가 숨는다"를 매 프레임 보장한다.
--   ⚠️ 속성 변경 이벤트로 하지 않는 이유: 자세가 여럿에게 동시에 붙고 캐릭터가
--     라운드마다 갈린다. 연결을 걸면 해제 시점을 또 관리해야 하고 그게 새는 지점이다.
--     스윕은 결과를 보장한다 — 오늘 WalkSpeedManager 만료와 같은 형태.
--   ⚠️ HP바 숨김은 **로컬 변경**이다. 서버가 나중에 Enabled 를 다시 쓰면 덮인다.
--     BotHealthBarSystem 은 생성·표시 시점에만 건드리므로 지금은 문제없다.
RunService.Heartbeat:Connect(function()
	local tagger = isTagger()
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") then
			local head = model:FindFirstChild("Head")
			if head then
				local want = tagger and (model:GetAttribute(ATTR) == true)
				local mark = head:FindFirstChild(MARK_NAME)
				local bar  = head:FindFirstChild(HPBAR_NAME)

				if want then
					if not mark then ensureMark(head) end
					-- HP바 양보: 지금 켜져 있는 것만 우리가 숨겼다고 기록한다.
					if bar and bar.Enabled then
						bar.Enabled = false
						hiddenBars[model] = true
					end
				else
					if mark then mark:Destroy() end
					if hiddenBars[model] then
						hiddenBars[model] = nil
						if bar then bar.Enabled = true end
					end
				end
			end
		end
	end
end)
