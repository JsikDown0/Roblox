-- ════════════════════════════════════════════════════════════════
-- QuestBoot  (ServerScriptService / Script)
-- ────────────────────────────────────────────────────────────────
-- QuestSystem 모듈을 활성화하는 부트 스크립트.
--  · 플레이어 입장/퇴장 시 퀘스트 데이터 로드/저장
--  · 클라이언트의 데이터 조회(QuestDataEvent) 응답
--  · 클라이언트의 보상 수령(QuestClaimEvent) 처리
--  · 주기적 자동 저장 + 리셋 검사
--  · 전역 노출(_G.QuestSystem)로 다른 서버 스크립트에서 진행도 추가 가능
-- ════════════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local QuestSystem = require(ServerScriptService:WaitForChild("QuestSystem"))

-- 다른 서버 스크립트(RoundSystem, ReviveSystem 등)에서 호출할 수 있도록 전역 노출
_G.QuestSystem = QuestSystem

print("📜 QuestBoot 시작!")

-- ── 입장: 데이터 로드 후 클라이언트로 최초 push ──────────────────
Players.PlayerAdded:Connect(function(player)
    QuestSystem.load(player)
    -- 클라이언트 UI가 늦게 붙을 수 있으니 약간 지연 후 한 번 push
    task.delay(2, function()
        if player and player.Parent then
            QuestSystem.pushToClient(player)
        end
    end)
end)

-- 부트 시점에 이미 들어와 있는 플레이어 처리 (스튜디오 재실행 등)
for _, player in ipairs(Players:GetPlayers()) do
    if not player:GetAttribute("_QuestLoaded") then
        QuestSystem.load(player)
        player:SetAttribute("_QuestLoaded", true)
    end
end

-- ── 퇴장: 저장 후 메모리 해제 ───────────────────────────────────
Players.PlayerRemoving:Connect(function(player)
    QuestSystem.unload(player)
end)

-- 서버 종료 시 전원 저장
game:BindToClose(function()
    for _, player in ipairs(Players:GetPlayers()) do
        QuestSystem.save(player)
    end
end)

-- ── 클라이언트 데이터 조회 (UI가 열릴 때 호출) ──────────────────
local dataEvent = ReplicatedStorage:WaitForChild("QuestDataEvent")
dataEvent.OnServerInvoke = function(player)
    return QuestSystem.getSnapshot(player)
end

-- ── 클라이언트 보상 수령 요청 ───────────────────────────────────
local claimEvent = ReplicatedStorage:WaitForChild("QuestClaimEvent")
-- [CLAIM-FEEDBACK] 수령 결과 알림에 재사용. QuestSystem.pushToClient 와 같은 리모트다.
local updateEvent = ReplicatedStorage:WaitForChild("QuestUpdateEvent")
claimEvent.OnServerEvent:Connect(function(player, questId)
    if type(questId) ~= "string" then return end
    local ok, reason, info
    -- "completion:daily" / "completion:weekly" → 완주 보너스 수령
    local category = questId:match("^completion:(%a+)$")
    if category then
        ok, reason, info = QuestSystem.claimCompletion(player, category)
    else
        ok, reason, info = QuestSystem.claim(player, questId)
    end
    if not ok then
        print(string.format("⚠️ 보상 수령 거절 (%s): %s", tostring(reason), player.Name))
        return
    end
    -- [CLAIM-FEEDBACK] 무엇을 받았는지 클라에 알린다.
    --   ⚠️ 새 리모트를 만들지 않고 기존 QuestUpdateEvent 를 재사용한다.
    --      첫 인자로 종류를 구분하므로 기존 스냅샷 수신부와 충돌하지 않는다.
    --   ⚠️ pushToClient(스냅샷 갱신)가 먼저 나간 뒤에 보내야 UI 가 갱신된 상태에서 뜬다.
    if info then
        updateEvent:FireClient(player, "claimed", info)
    end
end)

-- ── 주기적 자동 저장 + 리셋 검사 (60초마다) ─────────────────────
task.spawn(function()
    while true do
        task.wait(60)
        for _, player in ipairs(Players:GetPlayers()) do
            -- getSnapshot 내부에서 checkReset 수행됨 → push로 리셋도 반영
            QuestSystem.pushToClient(player)
            QuestSystem.save(player)
        end
    end
end)

print("✅ QuestBoot 준비 완료!")
