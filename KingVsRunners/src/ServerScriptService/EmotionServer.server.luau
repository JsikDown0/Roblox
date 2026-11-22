-- EmotionServer
-- 이모트 표시. 두 종류:
--   (1) 이미지 이모트  → 머리 위에 스티커 이미지만 둥둥 (흰 말풍선/꼬리 없음, 포크나이트 방식)
--   (2) 이모지 이모트  → 흰 둥근 말풍선 + 이모지 텍스트 (레거시 폴백)
-- 바(EmotionBarClient)는 이미지 이모트의 경우 emote id를 보내고, 서버가 EmoteData에서 imageId를 찾아 띄움.
-- __GURI__ 는 특별 고정 버튼(이미지).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local event = ReplicatedStorage:WaitForChild("EmotionEvent")

local DISPLAY_TIME = 3   -- 표시 시간(초)
local COOLDOWN = 2       -- 최소 사용 간격(초)
local GURI_IMAGE = "rbxassetid://109811485953893"
-- 🔼 [2026-08-27] 5.5 → 7.0. 러너 내구도 게이지와 겹침 제거.
--   [증상] 이모지가 내구도 게이지와 지지직거렸다.
--   [왜 ZIndex 로 못 푸나] ZIndex 는 '같은 BillboardGui 안' 에서만 순서를 정한다.
--     별개 BillboardGui 둘이 AlwaysOnTop=true 면 깊이 테스트가 꺼져 그리는 순서가
--     불안정해진다 — 어느 쪽도 앞이라고 정할 근거가 없다.
--     (BillboardGui 에는 ZIndex 속성 자체가 없다. 대입하면 런타임 에러)
--   [해결] 겹침 자체를 없앤다. 태거가 3.5→6.5 로 같은 문제를 푼 것과 같은 방법.
--   [계산] 내구도 게이지: 중심 4.9 + 높이 18px(≈0.47stud) → 상단 5.14
--          이모지: 96px(≈2.53stud) → 반높이 1.26
--          5.14 + 1.26 + 여유 0.5 ≈ 6.9  → 7.0
--   ⚠️ DurabilitySystem 의 StudsOffset(4.9)이나 BAR 높이를 바꾸면 여기도 다시 계산할 것.
--   ⚠️ 96px 은 bb.Size 다. 이모지 크기를 키우면 반높이가 늘어 다시 겹친다.
-- ⚠️ [2026-08-27] 아래 두 상수는 더 이상 쓰이지 않는다(말풍선이 가로축으로 이동).
--   지우지 않는 이유: 5.5 → 7.0 까지 올렸다가 "라운드 알림급 높이" 가 되어
--   가로 배치로 방향을 바꾼 이력이 남아 있어야, 다음에 또 세로로 올리려 하지 않는다.
--   ⚠️ 새 코드에서 쓰지 말 것. 세로 공간은 이미 포화다.
local HEAD_OFFSET = 7.0   -- (사용 안 함 · 이력 보존)        -- 머리 위 기본 오프셋(러너). 3 → 5.5 (2026-08-23)
--   ⚠️ 러너 머리 위에는 상시 표시물이 쌓여 있다. 이모트가 3 이었을 때
--      96px 짜리 말풍선이 그것들을 통째로 가렸다.
--        5.5  이모트        (일시, 3~4초)
--        4.4  부활 방패 배지 (일시, 2초)
--        3.9  내구도 게이지  (상시)
--   ⚠️ 상시 표시(게이지)를 올리지 말고 일시 표시(이모트)를 올린다.
--      게이지는 14px 라 높이 올릴수록 안 보이고, 교전 중 가려지면
--      "몇 대 더 버티나"를 판단할 수 없게 된다.
--   ⚠️ 태거는 HEAD_OFFSET_TAGGER(6.5) 를 따로 쓴다(왕관+HP바). 내구도 게이지도
--      안 붙으므로 여기 값과 무관하다.
-- ⚠️ 태거 오프셋: 왕관 + HP바 위로 "충분히" 띄워야 한다.
--   기존 4.7 은 HP바(TaggerHpDisplay, Y+3.5)와 간격이 1.2 뿐이었다.
--   BillboardGui 크기는 픽셀 단위라 화면에선 겹치는데, 둘 다 AlwaysOnTop=false 여서
--   3D 깊이로 정렬된다 → 깊이가 거의 같아 카메라가 조금만 움직여도 앞뒤가 뒤바뀌며 깜빡였다.
--   (HP바의 AlwaysOnTop=false 는 "벽 너머 위치 노출 방지"라는 의도된 설계라 유지)
--   → 이모지를 올려 겹침 자체를 없앤다. 이모지 높이 96px ≈ 2.5스터드 이므로 3.0 여유.
-- ⚠️ 태거는 내구도 게이지가 안 붙고 왕관+HP바(3.5)만 있다. 6.5 로 이미 3.0 여유가 있어
--   그대로 둔다. 러너(7.0)보다 낮은 게 정상이다 — 가릴 대상이 더 낮기 때문.
local HEAD_OFFSET_TAGGER = 6.5

-- id → imageId 조회 (EmoteData 단일 소스). 클라가 임의 이미지를 못 띄우게 화이트리스트 역할도 겸함.
local IMG_BY_ID = {}
do
	local ok, EmoteData = pcall(require, ReplicatedStorage:WaitForChild("EmoteData"))
	if ok and type(EmoteData) == "table" then
		for _, e in ipairs(EmoteData) do
			if e.id and e.imageId and e.imageId ~= "" then
				IMG_BY_ID[e.id] = e.imageId
			end
		end
	end
end

local lastUsed = {}  -- [player] = tick()

-- 💬 [2026-08-27] 만화 말풍선 — 이미지·텍스트 공용.
--
-- [왜 합쳤나] 예전엔 이미지 이모트는 '맨 스티커', 텍스트 이모지는 '말풍선' 으로
--   생김새가 달랐다. 같은 기능인데 두 벌이라 한쪽만 고쳐지는 사고가 반복됐다
--   (실측 2026-08-27: 말풍선 코드는 멀쩡한데 이미지 경로만 깨져 있었다).
--
-- [왜 왼쪽인가] 머리 위 세로 공간이 이미 포화다 — 이름표·HP바·내구도 게이지·
--   왕관·부활 배지·트랩 배지가 전부 그 자리를 노린다. 하나를 올리면 다음 UI 가
--   또 밀리고, 실제로 5.5 → 7.0 으로 올렸더니 "라운드 알림급 위치" 가 됐다.
--   → 가로축으로 빼면 세로 경쟁에서 완전히 빠진다. 만화 말풍선 문법과도 맞는다.
--
-- ⚠️ 말풍선은 이미지 한 장이다(아래 BUBBLE_IMAGE). 꼬리가 이미 그려져 있으므로
--   꼬리를 코드로 만들지 않는다.

-- 💬 말풍선 — 단일 이미지 방식.
--
-- ⚠️ [2026-08-27] Frame 조합(본체+테두리+회전 마름모 2장, 인스턴스 7개) → 이미지 1장.
--   [왜 바꿨나] 도형 하나를 코드로 흉내 내느라 이음새·ZIndex 3층·√2 컨테이너 계산을
--     픽셀 단위로 맞춰야 했고, 그 과정에서 세 번 틀렸다(꼬리 잘림 / 떨어져 보임 /
--     테두리가 마름모 전체에 그려짐). 이미지는 그 전부가 사라진다.
--   ⚠️ 대가: 색·꼬리 방향을 바꾸려면 이미지를 다시 뽑아야 한다.
--     지금은 왼쪽 배치 전용이다(꼬리가 오른쪽 아래를 향함).
--
-- ⚠️ 경합(내구도 게이지와 지지직)은 '그리는 방식' 이 아니라 '위치' 문제였다.
--   게이지는 머리 위(Y 4.9), 말풍선은 머리 왼쪽(X -3.0) — 축이 달라 겹치지 않는다.
--   ⚠️ StudsOffset 을 세로로 되돌리면 그 문제가 그대로 재발한다.

-- ⚠️ [2026-08-27] 데칼 ID 가 아니라 '텍스처 ID' 를 써야 한다.
--   로블록스는 데칼을 업로드하면 두 개의 ID 를 만든다:
--     121813960622798 = 데칼 에셋(AssetTypeId 13) — Image 속성에 넣으면 안 뜬다
--     103948077910387  = 그 안의 실제 텍스처 ← ImageLabel.Image 에 쓰는 값
--   ⚠️ 확인 방법: InsertService:LoadAsset(데칼ID) → 안의 Decal.Texture 를 읽는다.
--     또는 MarketplaceService:GetProductInfo 의 AssetTypeId 가 13 이면 데칼이다.
local BUBBLE_IMAGE = "rbxassetid://103948077910387"

-- ⚠️ [2026-08-27] 96 → 120. 이미지 방식으로 바꾸며 이모지가 작아졌다.
--   [왜] 이미지에는 꼬리·테두리 여백이 포함돼 있어, 같은 BUBBLE_PX 라도
--     '본체' 가 차지하는 실제 넓이는 Frame 방식보다 작다.
--     실측: 96 x 0.52 = 50px (이전 Frame 방식은 84 x 0.82 = 69px)
--   ⚠️ 아래 CONTENT_SCALE 과 한 세트다. 하나만 바꾸면 이모지가 말풍선을 넘치거나
--     너무 작아진다. 반드시 튜너(V키)로 둘을 같이 보며 맞출 것.
local BUBBLE_PX       = 190     -- 말풍선 이미지 한 변 — ⚠️ 단위는 '스터드'다. 아래 참조
-- 📏 [2026-08-28] BillboardGui.Size 를 Offset(px) → Scale(스터드) 로 바꿨다.
--   [증상] 이모지 크기가 카메라 줌에 따라 들쭉날쭉했다. 줌아웃하면 캐릭터를
--     통째로 감쌀 만큼 커 보이고, 줌인하면 정상으로 보였다(실측 스크린샷 2장).
--   [원인] BillboardGui.Size 는 Scale=스터드(월드), Offset=픽셀(화면 고정)이다.
--     Offset 만 쓰면 거리와 무관하게 화면상 크기가 고정되므로, 캐릭터만 작아지는
--     줌아웃에서 상대적으로 거대해진다. 위치(StudsOffset)는 스터드인데 크기만
--     픽셀이라 둘의 단위가 어긋나 있었던 것.
--   [환산] 기존 주석의 기준(96px ≈ 2.53스터드 → 약 38px/스터드)으로 190px ≈ 5.0스터드.
--   ⚠️ 트레이드오프: 이제 멀리서 보면 같이 작아진다. 그게 "캐릭터 대비 항상 같은 크기"의
--     대가다. 원거리 가독성이 문제면 Scale 에 작은 Offset 을 더한 하이브리드
--     (UDim2.new(S, minPx, S, minPx))로 최소 크기를 깔 수 있다 — 지우지 말고 그쪽으로.
--   ⚠️ BubbleTunerClient(V키) 미리보기도 같은 식으로 맞춰야 한다. 한쪽만 바꾸면
--     튜너로 맞춘 값이 실제와 달라진다.
local BUBBLE_STUDS    = 5.0
local BUBBLE_OFFSET_X = -3.0   -- 머리 기준 왼쪽(-X)
local BUBBLE_OFFSET_Y = 2.2    -- 살짝 위

-- 내용물(이모지)이 들어갈 영역. 이미지 안에서 '본체' 가 차지하는 비율에 맞춘다.
-- ⚠️ 이미지는 아래·오른쪽에 꼬리 여백이 있으므로, 내용물을 정중앙에 두면
--   꼬리 쪽으로 치우쳐 보인다. 중심을 살짝 왼쪽·위로 당긴다.
local CONTENT_SCALE = 0.62     -- 컨테이너 대비 내용물 크기
local CONTENT_CX    = 0.44     -- 내용물 중심 X (0.5 = 정중앙)
local CONTENT_CY    = 0.42     -- 내용물 중심 Y

-- 말풍선 껍데기 생성 → (billboard, bg) 반환. 내용물은 호출부가 bg 에 넣는다.
local function makeBubble(head)
	local bb = Instance.new("BillboardGui")
	bb.Name = "EmotionBubble"
	bb.Size = UDim2.fromScale(BUBBLE_STUDS, BUBBLE_STUDS)   -- ⚠️ Scale=스터드. 위 주석 참조
	-- ⚠️ StudsOffset 은 카메라 기준으로 보정된다. X 를 주면 화면상 왼쪽 —
	--    캐릭터가 어느 방향을 보든 일정하다.
	bb.StudsOffset = Vector3.new(BUBBLE_OFFSET_X, BUBBLE_OFFSET_Y, 0)
	-- ⚠️ BillboardGui 에는 ZIndex 속성이 없다. 대입하면 런타임 에러가 나고
	--    그 줄에서 함수가 죽어 이모지가 통째로 안 만들어진다(실측 2026-08-27).
	bb.AlwaysOnTop = true
	bb.ResetOnSpawn = false
	bb.LightInfluence = 0
	bb.Parent = head

	local bg = Instance.new("ImageLabel")
	bg.Name = "Bubble"
	bg.ZIndex = 20
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundTransparency = 1
	bg.Image = BUBBLE_IMAGE
	bg.ScaleType = Enum.ScaleType.Fit   -- 비율 유지. Stretch 면 꼬리가 찌그러진다
	bg.Parent = bb

	return bb, bg
end

-- 이미지 이모트
local function showImage(head, imageId, _offsetY)
	local bb, bg = makeBubble(head)

	local img = Instance.new("ImageLabel")
	img.ZIndex = 21
	img.Size = UDim2.new(CONTENT_SCALE, 0, CONTENT_SCALE, 0)
	img.Position = UDim2.new(CONTENT_CX, 0, CONTENT_CY, 0)
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.BackgroundTransparency = 1
	img.Image = imageId
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = bg

	Debris:AddItem(bb, DISPLAY_TIME)
end

-- 텍스트 이모지 (이미지가 없는 항목의 폴백)
local function showEmoji(head, emojiText, _offsetY)
	local bb, bg = makeBubble(head)

	local label = Instance.new("TextLabel")
	label.ZIndex = 21
	label.Size = UDim2.new(CONTENT_SCALE, 0, CONTENT_SCALE, 0)
	label.Position = UDim2.new(CONTENT_CX, 0, CONTENT_CY, 0)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Text = emojiText
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bg

	Debris:AddItem(bb, DISPLAY_TIME)
end

event.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "string" or #payload == 0 or #payload > 64 then return end

	local now = tick()
	if lastUsed[player] and now - lastUsed[player] < COOLDOWN then return end
	lastUsed[player] = now

	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end

	-- 기존 말풍선 제거
	local existing = head:FindFirstChild("EmotionBubble")
	if existing then existing:Destroy() end

	-- ⚠️ [2026-08-27] 세로 오프셋 계산 제거. 말풍선이 머리 '옆'(가로축)으로 나가면서
	--   태거/러너 구분이 필요 없어졌다. 머리 위 UI 와 아예 경쟁하지 않는다.

	-- 이미지 이모트 우선 (id 조회 → 화이트리스트), 그다음 guri, 마지막에 이모지 텍스트
	local imageId = IMG_BY_ID[payload]
	if payload == "__GURI__" then
		imageId = GURI_IMAGE
	end

	if imageId then
		showImage(head, imageId)
	else
		showEmoji(head, payload)
	end
end)

-- 플레이어 퇴장 시 쿨다운 정리
game.Players.PlayerRemoving:Connect(function(player)
	lastUsed[player] = nil
end)

print("✅ EmotionServer 준비! (이미지 이모트 + 이모지 폴백)")
