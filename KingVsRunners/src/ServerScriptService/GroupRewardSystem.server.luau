-- 그룹 가입 보상 시스템 v2 (Group Rewards Pad 기반)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ⚙️ 설정
local GROUP_ID = 183448200
local POPUP_COOLDOWN = 3

-- RemoteEvent
local showPopupEvent = ReplicatedStorage:FindFirstChild("ShowGroupPopup")
if not showPopupEvent then
    showPopupEvent = Instance.new("RemoteEvent")
    showPopupEvent.Name = "ShowGroupPopup"
    showPopupEvent.Parent = ReplicatedStorage
end

local giveRewardEvent = ReplicatedStorage:FindFirstChild("GiveGroupReward")
if not giveRewardEvent then
    giveRewardEvent = Instance.new("RemoteEvent")
    giveRewardEvent.Name = "GiveGroupReward"
    giveRewardEvent.Parent = ReplicatedStorage
end

-- Group Rewards Pad 가져오기
local pad = game.Workspace:WaitForChild("Group Rewards"):WaitForChild("Pad")

-- 상태 추적
local rewardedPlayers = {}
local popupCooldowns = {}
local playersOnPad   = {}
local touchCounts    = {}
-- 🔴 [2026-09-19] '이미 받음' 안내를 패드 진입당 1회만 띄우기 위한 표식.
--   루프가 0.5초마다 도므로 이게 없으면 서 있는 내내 토스트가 쏟아진다.
--   패드에서 내려가면 지운다(TouchEnded) — 다시 올라오면 다시 알려준다.
local claimedNotified = {}

-- 그룹 가입 여부
local function isInGroup(player)
    local ok, result = pcall(function() return player:IsInGroup(GROUP_ID) end)
    return ok and result
end

-- 🔴 [2026-09-19] 캐시를 타지 않는 권위 검사.
--   [증상] 가입 성공 직후 보상이 '한 차례 늦게' 들어왔다(부계정 실측).
--   [원인] player:IsInGroup 은 **서버 세션 캐시**다. 가입 직후 물으면 false 로
--     굳어 있어서, 아래 재검사 루프가 10초를 다 쓰고 포기한다. 그 뒤 캐시가
--     풀리면 패드 메인 루프가 뒤늦게 잡아 지급한다 = '한 차례 늦음'.
--     더 나쁜 건 그 사이 '재접속하라' 안내가 먼저 나가서 안내와 결과가
--     서로 모순된다는 점이다. 늦는 것보다 거짓말하는 쪽이 문제다.
--   [해결] GroupService:GetGroupsAsync(userId) 는 웹을 직접 묻는다 — 캐시가 없다.
--     실측 반환: { {Id=number, Name=string, Rank=number, Role=string, ...}, ... }
--   🔴 웹 호출이라 요청 비용이 있다. **패드 메인 루프(0.5초 주기)에서는 절대 쓰지 말 것.**
--     여기는 버튼 클릭으로만 도달하므로 호출 빈도가 사람 손 속도로 묶인다.
--   ⚠️ 캐시가 이미 true 면 웹을 안 부른다 — 빠른 경로를 먼저 둔다.
--   ⚠️ 이 함수는 소비처(joinCheckEvent 핸들러)보다 반드시 위에 있어야 한다.
local GroupService = game:GetService("GroupService")
local function isInGroupFresh(player)
    if isInGroup(player) then return true end
    local ok, groups = pcall(function()
        return GroupService:GetGroupsAsync(player.UserId)
    end)
    if not ok then
        warn("[GroupReward] GetGroupsAsync 실패:", groups)
        return false
    end
    if type(groups) ~= "table" then return false end
    for _, g in ipairs(groups) do
        if g.Id == GROUP_ID then return true end
    end
    return false
end

-- 보상 지급
-- [GROUP-PERSIST] 수령 여부를 프로필에 영구 기록한다.
--   ⚠️ rewardedPlayers(메모리)만 쓰면 재접속마다 초기화되어
--      ItemNoob 은 사라지고 코인 300 은 무한히 받을 수 있었다(실측 2026-08-22).
--   ⚠️ 프로필이 아직 로드 전이면 지급을 미룬다. 여기서 그냥 주면 기록이 안 남아
--      같은 무한 지급이 재현된다.
local function alreadyClaimed(player)
    if rewardedPlayers[player.UserId] then return true end
    local d = _G.DataService and _G.DataService.get(player)
    return d ~= nil and d.GroupRewardClaimed == true
end

local function giveReward(player)
    if rewardedPlayers[player.UserId] then return end
    local d = _G.DataService and _G.DataService.get(player)
    if not d then
        print("👥 프로필 미로드 — 그룹 보상 보류:", player.Name)
        return
    end
    if d.GroupRewardClaimed then
        -- 이미 받은 계정: 코인은 다시 주지 않고 아이템 소유만 복원한다.
        player:SetAttribute("HasItemNoob", true)
        rewardedPlayers[player.UserId] = true
        return
    end
    d.GroupRewardClaimed = true
    player:SetAttribute("HasItemNoob", true)
    rewardedPlayers[player.UserId] = true
    -- 300코인 지급 (최초 1회)
    if _G.CoinSystem then
        _G.CoinSystem.addCoins(player, 300)
        print("💰 그룹 보상 코인 지급: +300 ->", player.Name)
    end
    giveRewardEvent:FireClient(player)
    print("🎁 그룹 보상 지급 (ItemNoob + 300코인):", player.Name)
end

-- Pad 터치 감지
pad.Touched:Connect(function(hit)
    local player = Players:GetPlayerFromCharacter(hit.Parent)
    if not player then return end
    local uid = player.UserId
    touchCounts[uid] = (touchCounts[uid] or 0) + 1
    if not playersOnPad[uid] then
        playersOnPad[uid] = true
        print("👟 Pad 진입:", player.Name)
    end
end)

pad.TouchEnded:Connect(function(hit)
    local player = Players:GetPlayerFromCharacter(hit.Parent)
    if not player then return end
    local uid = player.UserId
    touchCounts[uid] = math.max((touchCounts[uid] or 1) - 1, 0)
    task.delay(0.1, function()
        if (touchCounts[uid] or 0) <= 0 then
            touchCounts[uid] = 0
            playersOnPad[uid] = false
            claimedNotified[uid] = nil   -- 다시 올라오면 다시 안내
            print("🚶 Pad 이탈:", player.Name)
        end
    end)
end)

-- 메인 루프
task.spawn(function()
    while true do
        task.wait(0.5)
        local now = tick()
        for _, player in ipairs(Players:GetPlayers()) do
            local uid = player.UserId
            if not playersOnPad[uid] then continue end
            -- 🔴 [2026-09-19] 수령 완료자에게 침묵하지 않는다.
            --   [왜] 전엔 그냥 continue 라, 이미 받은 사람이 패드에 올라서면 아무 일도
            --     안 일어났다. 유저 입장에서 '고장'과 '정상'이 같은 모양이다.
            if alreadyClaimed(player) then
                if not claimedNotified[uid] then
                    claimedNotified[uid] = true
                    giveRewardEvent:FireClient(player, "👥  Group reward already claimed — thanks for joining!")
                end
                continue
            end
            if isInGroup(player) then
                giveReward(player)
            else
                local last = popupCooldowns[uid] or 0
                if (now - last) >= POPUP_COOLDOWN then
                    popupCooldowns[uid] = now
                    showPopupEvent:FireClient(player)
                    print("📢 그룹 미가입 팝업:", player.Name)
                end
            end
        end
    end
end)

-- [GROUP-JOIN] 클라가 '가입 완료'를 알리면 즉시 재검사한다.
--   ⚠️ 패드 위 여부를 보지 않는다. 가입 창을 띄운 사이 이동했을 수 있고,
--      그 조건(playersOnPad) 때문에 보상이 안 나오는 것이 원래 증상이었다.
--   ⚠️ 신뢰 판정은 서버가 한다 — 클라 신호는 '다시 확인해달라'는 요청일 뿐,
--      실제 가입 여부는 isInGroup(서버 API)으로 검증하므로 위조해도 소용없다.
--   ⚠️ 그룹 멤버십은 캐시 때문에 즉시 반영되지 않을 수 있어 몇 번 재시도한다.
local joinCheckEvent = ReplicatedStorage:FindFirstChild("GroupJoinCheck")
if joinCheckEvent then
    joinCheckEvent.OnServerEvent:Connect(function(player)
        -- 🔴 [2026-09-19] 요청에 침묵하지 않는다. 클라가 '확인해달라'고 보냈는데
        --   아무 응답이 없으면 버튼이 먹통인 것과 구분되지 않는다.
        if alreadyClaimed(player) then
            giveRewardEvent:FireClient(player, "👥  You've already claimed this reward.")
            return
        end
        task.spawn(function()
            -- 🔴 [2026-09-19] 5회×2초(10초) → 3회×1.5초(4.5초).
            --   권위 검사라 보통 첫 판에 붙는다. 남긴 2회는 가입 직후 웹 반영
            --   지연에 대한 여유지, 캐시 만료를 기다리는 시간이 아니다.
            for _ = 1, 3 do
                if not player.Parent then return end
                if rewardedPlayers[player.UserId] then return end
                if isInGroupFresh(player) then
                    giveReward(player)
                    return
                end
                task.wait(1.5)
            end
            print("👥 그룹 가입 확인 실패:", player.Name)
            -- 🔴 여기까지 왔으면 캐시 문제가 아니라 실제로 미가입이거나 웹 호출이
            --   실패한 것이다. '재접속하라'고 하지 않는다 — 재접속은 캐시 해법이라
            --   이 경로에선 틀린 안내가 된다.
            giveRewardEvent:FireClient(player, "⏳  We couldn't confirm your membership. Step on the pad again in a moment.")
        end)
    end)
else
    warn("[GroupReward] GroupJoinCheck 리모트 없음")
end

-- [GROUP-PERSIST] 접속 시 이미 받은 계정의 소유를 복원한다.
--   ⚠️ 이게 없으면 프로필엔 기록이 있는데 HasItemNoob 속성이 없어
--      ItemNoob 이 인벤에서 잠긴 채로 보이고, 패드를 다시 밟아야 풀린다.
--   ⚠️ 속성은 세션마다 새로 세워야 한다 — 프로필과 달리 자동 복원되지 않는다.
local function restoreOwnership(player)
    task.spawn(function()
        local d = _G.DataService and _G.DataService.waitForData
            and _G.DataService.waitForData(player, 20)
        if d and d.GroupRewardClaimed then
            player:SetAttribute("HasItemNoob", true)
            rewardedPlayers[player.UserId] = true
            print("👥 그룹 보상 소유 복원:", player.Name)
        end
    end)
end
Players.PlayerAdded:Connect(restoreOwnership)
for _, p in ipairs(Players:GetPlayers()) do restoreOwnership(p) end

-- 플레이어 퇴장 정리
Players.PlayerRemoving:Connect(function(player)
    local uid = player.UserId
    rewardedPlayers[uid] = nil
    popupCooldowns[uid]  = nil
    playersOnPad[uid]    = nil
    touchCounts[uid]     = nil
    claimedNotified[uid] = nil
end)

print("✅ GroupRewardSystem 시작!")

-- ═══════════════════════════════════════════════════════════════
-- 🔧 [GROUPDEBUG 2026-08-27] 그룹 보상 테스트 커맨드 (dev 전용)
--
-- [왜 필요한가] 그룹 소유주·기존 가입자는 PromptGroupJoin 창이 아예 안 뜬다.
--   그래서 "가입 → 감지 → 지급" 흐름을 실제로 밟아볼 수가 없다.
--   ⚠️ 실측 2026-08-27: 소유주 계정으로는 이 기능을 한 번도 검증하지 못했다.
--
-- [커맨드]
--   /greset  — 수령 기록 삭제(메모리 + 프로필). 다시 받을 수 있는 상태로.
--   /gcheck  — 지금 상태 출력(가입 여부 / 수령 여부 / 프로필 로드 여부).
--   /gclaim  — 가입 감지 경로를 강제 실행(클라 폴링 없이 서버 지급 로직만 시험).
--
-- ⚠️ isDev 가드 필수. 이 커맨드는 코인 300 을 반복 지급할 수 있다.
-- ⚠️ 릴리즈 전 이 블록을 삭제할 것.
-- ═══════════════════════════════════════════════════════════════
do
	local DEV_IDS = { [9228200642] = true }
	local function isDev(p)
		return DEV_IDS[p.UserId] or game:GetService("RunService"):IsStudio()
	end

	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(msg)
			if not isDev(player) then return end
			local cmd = msg:lower()

			if cmd == "/greset" then
				rewardedPlayers[player.UserId] = nil
				local d = _G.DataService and _G.DataService.get(player)
				if d then
					d.GroupRewardClaimed = nil
					print("🔧 [GroupReward] 수령 기록 삭제:", player.Name, "(프로필 + 메모리)")
				else
					print("🔧 [GroupReward] 메모리만 삭제 — 프로필 미로드:", player.Name)
				end
				player:SetAttribute("HasItemNoob", nil)

			elseif cmd == "/gcheck" then
				local d = _G.DataService and _G.DataService.get(player)
				print(string.format(
					"🔧 [GroupReward] %s | 그룹가입=%s | 수령=%s | 프로필=%s | HasItemNoob=%s",
					player.Name,
					tostring(isInGroup(player)),
					tostring(alreadyClaimed(player)),
					d and "로드됨" or "미로드",
					tostring(player:GetAttribute("HasItemNoob"))))

			elseif cmd == "/gclaim" then
				-- 클라이언트 폴링을 건너뛰고 서버 지급 경로를 직접 태운다.
				-- ⚠️ isInGroup 검사는 그대로 통과시킨다 — 그걸 빼면 실제와 다른 경로가 된다.
				if not isInGroup(player) then
					print("🔧 [GroupReward] 그룹 미가입 — 지급 안 함:", player.Name)
					return
				end
				if alreadyClaimed(player) then
					print("🔧 [GroupReward] 이미 수령함. /greset 먼저:", player.Name)
					return
				end
				giveReward(player)
				print("🔧 [GroupReward] 강제 지급 실행:", player.Name)
			end
		end)
	end)
	print("🔧 [GroupReward] 디버그 커맨드 활성화 (/greset /gcheck /gclaim)")
end
print("  GROUP_ID:", GROUP_ID)
print("  팝업 쿨타임:", POPUP_COOLDOWN, "초")
