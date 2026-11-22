local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = script.Parent

local popup = gui:WaitForChild("GroupPopup")
local rewardNotif = gui:WaitForChild("RewardNotif")
local joinBtn = popup:WaitForChild("JoinGroupBtn")
local closeBtn = popup:WaitForChild("CloseBtn")

local showPopupEvent = ReplicatedStorage:WaitForChild("ShowGroupPopup")
local giveRewardEvent = ReplicatedStorage:WaitForChild("GiveGroupReward")

local GROUP_ID = 183448200

-- 모바일 노치/펀치홀 자동 회피
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)

-- 모바일 대응 UIScale
local Camera = workspace.CurrentCamera
local uiScale = gui:FindFirstChildWhichIsA("UIScale")
if not uiScale then
	uiScale = Instance.new("UIScale")
	uiScale.Parent = gui
end
local BASE_W, BASE_H = 1280, 720
local function updateScale()
	local vp = Camera.ViewportSize
	local s = math.min((vp.X * 0.85) / BASE_W, (vp.Y * 0.85) / BASE_H, 1)
	uiScale.Scale = math.max(s, 0.55)  -- 모바일 작은 화면 보호 (최소 55%)
end
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
updateScale()

-- 항상 정중앙 고정
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position    = UDim2.new(0.5, 0, 0.5, 0)
rewardNotif.AnchorPoint = Vector2.new(0.5, 0.5)
rewardNotif.Position    = UDim2.new(0.5, 0, 0.5, 0)

local function setChildrenTransparency(frame, transparency)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("TextLabel") then
			child.TextTransparency = transparency
		elseif child:IsA("TextButton") then
			child.TextTransparency = transparency
			child.BackgroundTransparency = transparency
		end
	end
end

-- 팝업 열기 (스케일 인 애니메이션)
local function showPopup()
	popup.Visible = true
	popup.BackgroundTransparency = 1
	popup.Size = UDim2.new(0, 360, 0, 220)
	setChildrenTransparency(popup, 1)

	TweenService:Create(popup, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
		Size = UDim2.new(0, 420, 0, 260),
	}):Play()

	for _, child in ipairs(popup:GetChildren()) do
		if child:IsA("TextLabel") then
			TweenService:Create(child, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		elseif child:IsA("TextButton") then
			TweenService:Create(child, TweenInfo.new(0.3), {
				TextTransparency = 0,
				BackgroundTransparency = 0,
			}):Play()
		end
	end
end

-- 팝업 닫기
local function closePopup()
	TweenService:Create(popup, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	setChildrenTransparency(popup, 1)
	task.delay(0.2, function() popup.Visible = false end)
end

-- 보상 알림
local function showRewardNotif(msg)
	local textLabel = rewardNotif:FindFirstChild("TextLabel")
	if textLabel then
		textLabel.Text = msg or "🎁  ItemNoob & Coins delivered!"
		textLabel.TextTransparency = 1
	end

	rewardNotif.Visible = true
	rewardNotif.BackgroundTransparency = 1

	TweenService:Create(rewardNotif, TweenInfo.new(0.3), { BackgroundTransparency = 0 }):Play()
	if textLabel then
		TweenService:Create(textLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	end

	task.delay(3, function()
		TweenService:Create(rewardNotif, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		if textLabel then
			TweenService:Create(textLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
		task.delay(0.4, function() rewardNotif.Visible = false end)
	end)
end

-- 🔴 [2026-09-19] 가입 버튼 전면 교체.
--   [증상] 부계정 실측 — 패드에서 'join group' 을 눌러도 아무 일도 안 일어났다.
--     보상도 안 나오고 에러도 없어서, 받은 건지 만 건지조차 알 수 없었다.
--   [원인] SocialService:PromptGroupJoin 은 **존재하지 않는 API** 다.
--     실측: SocialService 에 PromptGroupJoin / PromptGroupJoinCompleted 둘 다 없음.
--     08-27 수정은 '이벤트가 없다'까지만 밝히고 '메서드는 있다'를 전제했다.
--     그 호출이 pcall 에 싸여 있어 에러가 통째로 삼켜졌다 — 아래 주석이
--     "pcall 이 에러를 삼켜서 진짜 이유가 안 보였다" 고 경고한 그 함정을
--     같은 줄에서 다시 밟은 것이다.
--   [해결] GroupService:PromptJoinAsync(groupId) — 클라 전용 공식 API.
--     유저가 선택할 때까지 yield 한 뒤 Enum.GroupMembershipStatus 를 돌려준다:
--       Joined(1) / JoinRequestPending(2) / AlreadyMember(3) / None(0)
--   🔴 [무반응 금지] 어떤 분기로 빠지든 화면에 한 줄은 뜬다.
--     침묵은 유저에게 '보상을 받은 건지 버그인지' 구분이 안 되는 최악의 상태다.
--   ⚠️ yield 하므로 task.spawn 안에서 부른다. 안 그러면 클릭 동안 UI 가 멎는다.
local joining = false
joinBtn.MouseButton1Click:Connect(function()
	closePopup()
	if GROUP_ID == 0 then return end
	if joining then return end   -- yield 중 중복 클릭 방지
	joining = true
	task.spawn(function()
		local GroupService = game:GetService("GroupService")
		local ok, result = pcall(function()
			return GroupService:PromptJoinAsync(GROUP_ID)
		end)
		joining = false

		local checkEvent = ReplicatedStorage:FindFirstChild("GroupJoinCheck")
		if not ok then
			warn("[GroupReward] PromptJoinAsync 실패:", result)
			showRewardNotif("⚠️  Couldn't open the join window. Join from the game page.")
			return
		end

		if result == Enum.GroupMembershipStatus.Joined then
			showRewardNotif("✅  Joined! Claiming your reward...")
			if checkEvent then checkEvent:FireServer() end
			-- ⚠️ IsInGroup 은 캐시돼 서버가 즉시 못 볼 수 있다. 서버가 5회 재시도하고
			--   아래 폴링이 한 번 더 받쳐준다 — 둘 다 남겨둔다.
			if _G.GroupRewardStartPolling then _G.GroupRewardStartPolling() end
		elseif result == Enum.GroupMembershipStatus.AlreadyMember then
			showRewardNotif("👥  Already a member — checking your reward...")
			if checkEvent then checkEvent:FireServer() end
		elseif result == Enum.GroupMembershipStatus.JoinRequestPending then
			showRewardNotif("⏳  Request sent. Come back once it's approved.")
		else
			showRewardNotif("Join the group anytime to claim your reward.")
		end
	end)
end)
-- [GROUP-JOIN] 가입 감지 → 서버에 재검사 요청
--
-- ⚠️ [2026-08-27] SocialService.PromptGroupJoinCompleted 는 '존재하지 않는 이벤트' 다.
-- 🔴 [2026-09-19 정정] 아래 문단의 "PromptGroupJoin 은 창만 띄우고 끝난다" 는 **틀렸다**.
--   그 메서드 자체가 존재하지 않는다(실측). 이벤트만 없는 게 아니라 메서드도 없다.
--   이 문장을 사실로 믿은 탓에 '클릭해도 무반응' 이 한 달 살아남았다.
--   지금 쓰는 건 GroupService:PromptJoinAsync — 위 버튼 핸들러 참조.
--   아래 폴링은 지우지 않는다. IsInGroup 캐시 지연에 대한 예비 경로로 계속 쓴다.
--   [증상] "[GroupReward] PromptGroupJoinCompleted 연결 실패" 가 매번 찍히고
--     가입해도 보상이 안 나왔다.
--   [원인] SocialService 에 있는 건 PromptInviteRequested 뿐이다. 그룹 가입 '완료'
--     를 알려주는 이벤트는 API 에 없다 — PromptGroupJoin 은 창만 띄우고 끝난다.
--     pcall 이 에러를 삼켜서 "연결 실패" 만 남고 진짜 이유가 안 보였다.
--   [해결] 이벤트 대신 '폴링' 한다. 가입 창을 띄운 뒤 잠깐 동안 주기적으로
--     소속 여부를 확인하고, 가입이 확인되면 서버에 알린다.
--   ⚠️ IsInGroup 은 캐시된다. 가입 직후 바로 물으면 false 가 나올 수 있어
--     여러 번 확인해야 한다(그래서 폴링이 필요하다).
--   ⚠️ 무한 폴링 금지. 창을 닫고 가입 안 하는 경우가 대부분이라
--     제한 시간을 두고 멈춘다.
do
	local checkEvent = ReplicatedStorage:FindFirstChild("GroupJoinCheck")

	local POLL_INTERVAL = 2      -- 확인 주기(초)
	local POLL_DURATION = 60     -- 이 시간 뒤 포기
	local polling = false

	local function startJoinPolling()
		if polling then return end
		if GROUP_ID == 0 then return end
		-- 이미 가입돼 있으면 폴링할 필요가 없다
		local already = false
		pcall(function() already = player:IsInGroup(GROUP_ID) end)
		if already then return end

		polling = true
		task.spawn(function()
			local deadline = os.clock() + POLL_DURATION
			while os.clock() < deadline do
				task.wait(POLL_INTERVAL)
				local joined = false
				local ok = pcall(function() joined = player:IsInGroup(GROUP_ID) end)
				if ok and joined then
					print("[GroupReward] 그룹 가입 확인 → 서버에 보상 요청")
					if checkEvent then checkEvent:FireServer() end
					break
				end
			end
			polling = false
		end)
	end

	-- 가입 창을 띄우는 그 순간부터 폴링을 시작한다.
	_G.GroupRewardStartPolling = startJoinPolling
end

closeBtn.MouseButton1Click:Connect(function()
	closePopup()
end)

showPopupEvent.OnClientEvent:Connect(function()
	showPopup()
end)

giveRewardEvent.OnClientEvent:Connect(function(msg)
	closePopup()
	showRewardNotif(msg)
end)

print("✅ GroupRewardClient ready!")
