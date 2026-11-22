-- DownedBotSystem
-- 항상 다운 상태인 테스트용 봇.
-- 주기적으로 SOS 신호를 보내서 SOS UI / 화살표 / 사운드 / 화면 마커 테스트에 사용.
-- 게임 디자인 검증용이라 실제 게임 흐름과는 분리됨 — AI/충돌/굴리기 등 일반 NPC 기능 없음.
--
-- 채팅 명령어:
--   /downedbot       → 봇 활성화 (또는 재활성화)
--   /downedbot off   → 봇 제거

local Players = game:GetService("Players")

local DownSystem = require(game.ServerScriptService:WaitForChild("DownSystem"))
local SosSystem  = require(game.ServerScriptService:WaitForChild("SosSystem"))

-- ── 설정 ────────────────────────────────────────────────
local BOT_NAME           = "DownedBot"
local SOS_INTERVAL       = 8     -- 몇 초마다 SOS 발신할지
local DOWN_REFRESH_DELAY = 1     -- 사망 후 몇 초 뒤 부활시킬지

-- 위치: 통로 중간 (taggerbase 지면 Y=138 위 3 stud)
-- 라인 X=717은 test_launcher와 같은 통나무 굴러오는 라인
-- (테스트용으로 살짝 옆으로 빼고 싶으면 X를 715 정도로 변경 권장)
local DEFAULT_POSITION   = Vector3.new(717, 141, -650)

-- ── 상태 ────────────────────────────────────────────────
local botRunning = false
local botCharacter = nil
local sosLoopThread = nil
local watchThread = nil
local startBotInternal  -- forward declaration (watchDeath 안에서 호출하기 위함)

-- ─────────────────────────────────────────────────────────────
-- Noob 모델 복제 → DownedBot 생성
-- ─────────────────────────────────────────────────────────────
local function findSourceNoob()
    for _, child in ipairs(workspace:GetChildren()) do
        if child.Name == "Noob" and child:FindFirstChild("HumanoidRootPart") then
            return child
        end
    end
    return nil
end

local function createBot()
    -- 기존 봇 제거
    local existing = workspace:FindFirstChild(BOT_NAME)
    if existing then existing:Destroy() end

    local source = findSourceNoob()
    if not source then
        warn("[DownedBotSystem] 복제할 Noob 원본 없음")
        return nil
    end

    local bot = source:Clone()
    bot.Name = BOT_NAME
    bot.Parent = workspace

    -- 식별용 노란 Highlight (러너지만 다운 상태)
    local hl = Instance.new("Highlight")
    hl.Name = "BotHighlight"
    hl.FillColor = Color3.fromRGB(255, 255, 100)
    hl.FillTransparency = 0.85
    hl.OutlineColor = Color3.fromRGB(255, 255, 100)
    hl.OutlineTransparency = 0.3
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = bot

    -- 안전한 배치: HRP를 잠시 Anchor 시켜 정확히 원하는 위치에 고정
    local hrp = bot:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.Anchored = true
        bot:PivotTo(CFrame.new(DEFAULT_POSITION))
        -- 속도/관성 제거 (복제된 모델이 가질 수 있는 잔여 운동량 클리어)
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end

    return bot
end

-- ─────────────────────────────────────────────────────────────
-- 봇을 다운 상태로 만들기
-- DownSystem.triggerDown은 일반적으로 ItemDamageSystem이 호출하지만,
-- 직접 호출해도 동일하게 작동 (다운 처리, 애니메이션, 타이머 모두).
-- ─────────────────────────────────────────────────────────────
local function makeDowned(bot)
    if not bot then return false end
    local hum = bot:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return DownSystem.triggerDown(bot)
end

-- ─────────────────────────────────────────────────────────────
-- 사망 감시: 다운 타이머 만료 시 자동 부활시켜 영구 다운 유지
-- ─────────────────────────────────────────────────────────────
local function watchDeath(bot)
    local hum = bot:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local conn
    conn = hum.Died:Connect(function()
        if conn then conn:Disconnect() end
        if not botRunning then return end

        print("[DownedBotSystem] 봇 사망 → 부활 예약 (", DOWN_REFRESH_DELAY, "초 후)")
        task.delay(DOWN_REFRESH_DELAY, function()
            if not botRunning then return end
            -- 새 봇 생성 (모델 자체를 새로 만들어서 깨끗한 상태 보장)
            startBotInternal()
        end)
    end)
end

-- ─────────────────────────────────────────────────────────────
-- SOS 주기 발신 루프
-- ─────────────────────────────────────────────────────────────
local function startSosLoop(bot)
    if sosLoopThread then task.cancel(sosLoopThread) end
    sosLoopThread = task.spawn(function()
        -- 첫 SOS는 다운 직후 즉시 발신 (사용자가 빨리 확인할 수 있게)
        task.wait(0.5)
        while botRunning and bot and bot.Parent do
            if bot:GetAttribute("Downed") then
                SosSystem.forceActivateSos(bot)
            end
            task.wait(SOS_INTERVAL)
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- 봇 시작 (내부) — forward declaration 된 변수에 함수 할당
-- ─────────────────────────────────────────────────────────────
startBotInternal = function()
    botCharacter = createBot()
    if not botCharacter then return end

    -- 짧게 대기 (안정화)
    task.wait(0.2)
    if not (botCharacter and botCharacter.Parent) then return end

    -- Anchor 해제 직전 → 다운 적용 (다운이 적용되면 발사체 통과 등 다운 처리 시작)
    -- 다운된 휴머노이드는 WalkSpeed=4로 거의 정지. 잔여 낙하 거리도 0 stud라 안전.
    local hrp = botCharacter:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.Anchored = false
    end

    local downed = makeDowned(botCharacter)
    if not downed then
        warn("[DownedBotSystem] 다운 적용 실패")
        return
    end

    print("[DownedBotSystem] 봇 다운 적용 완료 →", hrp and hrp.Position or "?")

    watchDeath(botCharacter)
    startSosLoop(botCharacter)
end

-- ─────────────────────────────────────────────────────────────
-- 외부 인터페이스: 시작 / 정지
-- ─────────────────────────────────────────────────────────────
local function startBot()
    if botRunning then
        -- 이미 실행 중이면 재시작
        local existing = workspace:FindFirstChild(BOT_NAME)
        if existing then existing:Destroy() end
    end
    botRunning = true
    startBotInternal()
end

local function stopBot()
    botRunning = false
    if sosLoopThread then
        task.cancel(sosLoopThread)
        sosLoopThread = nil
    end
    local existing = workspace:FindFirstChild(BOT_NAME)
    if existing then
        SosSystem.clearSos(existing)
        existing:Destroy()
    end
    print("[DownedBotSystem] 봇 정지")
end

-- ─────────────────────────────────────────────────────────────
-- 채팅 명령어 처리
-- ─────────────────────────────────────────────────────────────
local isDev = require(game:GetService("ServerScriptService"):WaitForChild("DevAuth")).isDev

local function onChatted(player, message)
    if not isDev(player) then return end   -- 🔒 개발자 전용
    local lower = message:lower()
    if lower == "/downedbot" or lower == "/downedbot on" then
        print("[DownedBotSystem]", player.Name, "이 봇 호출")
        startBot()
    elseif lower == "/downedbot off" then
        stopBot()

    -- ── [DOWNLOCK-TEST] 솔로 검증용 자가 다운/부활 ──────────────────
    --   다운 중 인벤 잠금(DownSystem 의 lockedTools)은 부활이 있어야 복구까지 볼 수 있는데,
    --   솔로 플레이에선 살려줄 사람이 없어 검증이 막힌다.
    --   /down 으로 스스로 눕고 /revive 로 일어나서 잠금→복구 왕복을 확인한다.
    --   isDev 가드 안이라 일반 유저에겐 노출되지 않는다.
    elseif lower == "/down" then
        local char = player.Character
        if not char then
            warn("[DownTest] 캐릭터 없음")
            return
        end
        if DownSystem.isDowned(char) then
            print("[DownTest] 이미 다운 상태")
            return
        end
        DownSystem.triggerDown(char, "TestCommand")
        print("🩸 [DownTest]", player.Name, "→ 자가 다운")

    elseif lower == "/revive" then
        local char = player.Character
        if not char then
            warn("[DownTest] 캐릭터 없음")
            return
        end
        if not DownSystem.isDowned(char) then
            print("[DownTest] 다운 상태가 아님 — 부활할 게 없음")
            return
        end
        -- clearDown 이 사망 타이머 취소 + 상태 복구 + 잠갔던 툴 복구까지 담당한다
        DownSystem.clearDown(char)
        print("✨ [DownTest]", player.Name, "→ 자가 부활")

    elseif lower == "/toolstate" then
        -- 잠금/복구가 실제로 어떤 상태인지 눈으로 확인용.
        -- 특히 "원래 꺼져 있던 툴까지 켜지지 않았는지"를 보는 게 핵심이다.
        local char = player.Character
        local bp   = player:FindFirstChildOfClass("Backpack")
        print(string.format("🔧 [DownTest] %s Downed=%s", player.Name,
            tostring(char and DownSystem.isDowned(char))))
        for _, loc in ipairs({ char, bp }) do
            if loc then
                for _, t in ipairs(loc:GetChildren()) do
                    if t:IsA("Tool") then
                        print(string.format("    %-14s Enabled=%s  (%s)", t.Name, tostring(t.Enabled), loc.ClassName))
                    end
                end
            end
        end

    -- [BP-DEBUG] 배틀패스 티어를 되돌리고 수령 기록을 비운다.
    --   만렙이면 '받을 게 없어' 배지·수령 테스트가 안 되므로 필요하다.
    --   /bptier 5  → 티어 5 (XP = 4×800) + 수령 기록 초기화 → 1~5 미수령 상태
    elseif lower:match("^/bptier") then
        local t = tonumber(lower:match("^/bptier%s+(%d+)$")) or 5
        local bp = _G.BattlePass
        if bp and bp.debugSetTier then
            local tier, xp = bp.debugSetTier(player, t)
            print(string.format("🧪 [BP] %s → 티어 %d (XP %d), 수령기록 초기화",
                player.Name, tier, xp))
        else
            warn("[BP] _G.BattlePass.debugSetTier 없음")
        end

    -- [UNOWN-DEBUG] 소유 상태를 '일시적으로' 지운다. 미보유 유저 관점 검증용.
    --   /unown            → 현재 보유 중인 태거 아이템 목록 출력
    --   /unown tox_box    → 그 아이템만 미보유 처리
    --   /unown all        → 태거 아이템 전부 미보유 처리
    --   /unown restore    → 되돌리기
    --
    --   ⚠️ 안전성: OwnedItem_ 속성만 건드린다. 저장되는 실제 데이터는
    --      LoadoutManager 의 playerOwnedPermanents 테이블이고 속성은 그 캐시일 뿐이라,
    --      여기서 지워도 DataStore 에는 영향이 없다. 재접속하면 loadPlayerData 가 복원한다.
    --   ⚠️ 그래도 restore 를 제공한다. 재접속 없이 되돌리려면 필요하고,
    --      "지웠다가 복구를 못 하는" 상태를 남기지 않기 위해서다.
    elseif lower:match("^/unown") then
        local arg = message:match("^/unown%s+(%S+)$")
        local ok, FR = pcall(function()
            return require(game:GetService("ReplicatedStorage"):WaitForChild("FreeRotation"))
        end)

        -- 태거 아이템의 shopId 목록 (LoadoutManager.ALL_ITEMS 기준)
        local SHOP_IDS = {
            Spear = "spear", Demonspear = "demon_spear", bear_trap = "bear_trap",
            tox_box = "tox_box", tsunami = "tsunami", tnt = "tnt",
            BlackHole = "black_hole", EnergyBall = "energy_ball",
        }

        if arg == "restore" then
            local saved = player:GetAttribute("_UnownBackup")
            if type(saved) == "string" and saved ~= "" then
                local n = 0
                for id in saved:gmatch("[^,]+") do
                    player:SetAttribute("OwnedItem_" .. id, true)
                    n = n + 1
                end
                player:SetAttribute("_UnownBackup", nil)
                print(("🔓 [Unown] 복구 %d종 — 인벤을 다시 열면 반영됨"):format(n))
            else
                print("🔓 [Unown] 복구할 백업 없음 (재접속해도 자동 복원됨)")
            end

        elseif arg == nil then
            local have = {}
            for nm, id in pairs(SHOP_IDS) do
                if player:GetAttribute("OwnedItem_" .. id) then
                    table.insert(have, ("%s(%s)"):format(nm, id))
                end
            end
            table.sort(have)
            print(("🔓 [Unown] 보유 중 %d종: %s"):format(#have,
                #have > 0 and table.concat(have, ", ") or "(없음)"))
            if ok and FR then
                print(("🆓 오늘 무료: %s"):format(table.concat(FR.todayItems(), ", ")))
            end

        else
            -- 지우기 전에 원래 상태를 백업(restore 용). 이미 백업이 있으면 덮지 않는다.
            local removed = {}
            local targets = {}
            if arg == "all" then
                for _, id in pairs(SHOP_IDS) do table.insert(targets, id) end
            else
                targets = { SHOP_IDS[arg] or arg }
            end
            for _, id in ipairs(targets) do
                if player:GetAttribute("OwnedItem_" .. id) then
                    player:SetAttribute("OwnedItem_" .. id, nil)
                    table.insert(removed, id)
                end
            end
            if #removed > 0 then
                local prev = player:GetAttribute("_UnownBackup")
                local merged = (type(prev) == "string" and prev ~= "")
                    and (prev .. "," .. table.concat(removed, ","))
                    or table.concat(removed, ",")
                player:SetAttribute("_UnownBackup", merged)
                print(("🔓 [Unown] 미보유 처리 %d종: %s"):format(#removed, table.concat(removed, ", ")))
                print("   → 인벤을 다시 열어야 반영됨. /unown restore 로 복구.")
            else
                print(("🔓 [Unown] 대상 없음: %s (이미 미보유이거나 이름 오타)"):format(tostring(arg)))
            end
        end

    -- [ROTATION-DEBUG] 무료 로테이션 검증용. 하루 기다리지 않고 날짜를 옮긴다.
    --   /rot        → 오늘 개방 목록 출력
    --   /rot 3      → 3일 뒤로 이동 (누적 아님, 절대 오프셋)
    --   /rot 0      → 원래대로
    --   ⚠️ ReplicatedStorage 속성이라 클라도 같이 바뀐다(표시와 판정이 함께 이동).
    elseif lower:match("^/rot") then
        local RS = game:GetService("ReplicatedStorage")
        local n = tonumber(lower:match("^/rot%s+(%-?%d+)$"))
        if n then
            RS:SetAttribute("FreeRotDayShift", n)
            print(("🆓 [Rotation] 날짜 오프셋 → %+d일"):format(n))
        end
        local ok, FR = pcall(function() return require(RS:WaitForChild("FreeRotation")) end)
        if ok and FR then
            print(("🆓 [Rotation] 오늘 무료 (%s 남음): %s"):format(
                FR.formatRemaining(), table.concat(FR.todayItems(), ", ")))
        else
            warn("[Rotation] FreeRotation 모듈 로드 실패")
        end

    -- [DURABILITY-DEBUG] 내구도 검증용.
    --   /armor      → 1칸으로 리셋 (기본값)
    --   /armor 3    → 3칸 (게이지 칸 분할 확인용. 밸런스상 과한 값)
    --   /armor 0    → 제거
    --   ⚠️ 라운드 시작 시 자동으로 기본 1칸이 지급되므로, 이 커맨드는 그 위에 덮어쓴다.
    elseif lower:match("^/armor") then
        local n = tonumber(lower:match("^/armor%s+(%d+)$"))
        if n == nil then n = 1 end
        local char = player.Character
        if not char then
            warn("[Durability] 캐릭터 없음")
        elseif not _G.DurabilitySystem then
            warn("[Durability] DurabilitySystem 미로드")
        elseif n <= 0 then
            _G.DurabilitySystem.clear(char)
            print("🛡️ [Durability] 제거:", player.Name)
        else
            _G.DurabilitySystem.reset(char, n)
            print(string.format("🛡️ [Durability] %s → %d칸", player.Name, n))
        end

    -- [NEWBIE-DEBUG] 신규 유저 경험 검증용. RoundsPlayed 를 되돌린다.
    --   이 값에 걸리는 것: 스타터킷, 대시 힌트 2종, 킹 난이도 hard 배제.
    --   ⚠️ hard 배제 때문에 그랩 힌트를 못 보는 문제는 /kingtier hard 로 우회한다.
    --      pickTier 는 forcedTier 를 먼저 반환하므로(TaggerBotSystem:121) 신규 보호를 건너뛴다.
    --      즉 "/newbie → /kingtier hard" 순서로 쓰면 신규 상태 + 그랩이 나오는 킹이 된다.
    elseif lower:match("^/newbie") then
        local n = tonumber(lower:match("^/newbie%s+(%d+)$")) or 0
        local d = _G.DataService and _G.DataService.get(player)
        if d then
            d.RoundsPlayed = n
            player:SetAttribute("RoundsPlayed", n)
            print(string.format("🧪 [Newbie] %s RoundsPlayed = %d (힌트·스타터킷·hard배제 재활성)",
                player.Name, n))
        else
            warn("[Newbie] 프로필 미로드")
        end

    -- [QUEST-DEBUG] 퀘스트/출석 검증 커맨드.
    --   /qreset [daily|weekly]    진행도·수령 상태 전부 0
    --   /qdone  [daily|weekly]    전부 목표 달성(수령 전) → Claim 버튼 검증
    --   /rreset                   출석 보상 오늘 수령 기록 삭제 → 다시 수령 가능
    --   ⚠️ 원인 확정 후 이 블록과 QuestSystem.debug* 를 함께 제거할 것.
    elseif lower:match("^/qreset") then
        local cat = lower:match("^/qreset%s+(%a+)$")
        if cat ~= "daily" and cat ~= "weekly" then cat = nil end
        local qsys = _G.QuestSystem
        if qsys and qsys.debugReset then
            local ok = qsys.debugReset(player, cat)
            print("🧪 [QuestDebug] reset " .. (cat or "all") .. " → " .. tostring(ok))
        else
            warn("[QuestDebug] _G.QuestSystem.debugReset 없음")
        end

    elseif lower:match("^/qdone") then
        local cat = lower:match("^/qdone%s+(%a+)$")
        if cat ~= "daily" and cat ~= "weekly" then cat = nil end
        local qsys = _G.QuestSystem
        if qsys and qsys.debugComplete then
            local ok = qsys.debugComplete(player, cat)
            print("🧪 [QuestDebug] complete " .. (cat or "all") .. " → " .. tostring(ok))
        else
            warn("[QuestDebug] _G.QuestSystem.debugComplete 없음")
        end

    elseif lower == "/rreset" then
        -- 출석: 오늘 수령 기록만 지운다. Day 진행도는 유지 → 특정 Day 반복 검증 가능
        local drs = _G.DailyRewardSystem
        if drs and drs.debugResetClaim then
            local ok = drs.debugResetClaim(player)
            print("🧪 [RewardDebug] 오늘 수령 기록 삭제 → " .. tostring(ok))
        else
            warn("[RewardDebug] _G.DailyRewardSystem.debugResetClaim 없음")
        end

    elseif lower:match("^/rday%s+%d+$") then
        -- 특정 Day 로 점프. Day 2/7 같은 마일스톤(스킨 박스)을 바로 검증한다.
        local d = tonumber(lower:match("^/rday%s+(%d+)$"))
        local drs = _G.DailyRewardSystem
        if drs and drs.debugSetDay then
            local ok = drs.debugSetDay(player, d)
            print("🧪 [RewardDebug] Day " .. tostring(d) .. " 로 이동 → " .. tostring(ok))
        else
            warn("[RewardDebug] _G.DailyRewardSystem.debugSetDay 없음")
        end

    -- [RESETKIT] 스타터킷 재지급 테스트용.
    --   ⚠️ Studio 명령 바는 기본이 '클라이언트' 컨텍스트라 _G.DataService 가 nil 이다.
    --      (실측 2026-08-21: attempt to index nil with 'get')
    --      채팅 커맨드는 서버 스크립트에서 처리되므로 컨텍스트 문제가 없다.
    elseif lower == "/resetkit" then
        local d = _G.DataService and _G.DataService.get(player)
        if not d then
            warn("[ResetKit] 프로필 미로드 — 잠시 후 다시 시도")
            return
        end
        d.StarterKitGiven = false
        -- 이미 받은 소모품은 그대로 둔다(중복 지급되어 수량이 늘어남 — 테스트 목적상 무해).
        print("🎁 [ResetKit] " .. player.Name .. " StarterKitGiven=false → 인벤을 다시 열면 재지급")
    end
end

Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(msg) onChatted(player, msg) end)
end)
for _, player in ipairs(Players:GetPlayers()) do
    player.Chatted:Connect(function(msg) onChatted(player, msg) end)
end

print("✅ DownedBotSystem 활성화 (/downedbot 으로 호출, /downedbot off 로 제거)")
