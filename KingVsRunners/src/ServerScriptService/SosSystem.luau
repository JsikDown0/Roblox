-- SosSystem
-- 다운된 러너의 구조 신호(SOS) 관리 모듈
--
-- 작동 흐름:
--   다운된 러너가 Q 누르거나 SOS 버튼 클릭
--     → 클라이언트가 SosRequestEvent 발신
--     → 서버 검증 (다운 상태 + 쿨다운 + 중복 방지)
--     → 통과 시 SosStateChanged 로 모든 클라이언트에 SOS 활성화 전파
--     → 다운 종료(부활/사망) 시 자동 정리
--
-- 인터페이스:
--   SosSystem.isSosActive(character)  -- SOS 활성 상태 확인
--   SosSystem.getActiveSosTargets()   -- 현재 SOS 활성된 모든 캐릭터 목록
--   SosSystem.clearSos(character)     -- SOS 강제 해제 (다운 종료 시 호출)

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SosSystem = {}

-- ── 설정 ────────────────────────────────────────────────
local SOS_COOLDOWN = 3   -- 발신 쿨다운 (초)
local SOS_DURATION = 5   -- SOS 활성 지속 시간 (초). 종료 후 재발신 필요

-- ── 상태 ────────────────────────────────────────────────
-- character -> { sentTime = tick() }
local activeSos = {}
-- character -> tick() of last attempt (쿨다운 추적)
local lastAttempt = {}

-- ── 이벤트 ──────────────────────────────────────────────
local stateEvent   = ReplicatedStorage:WaitForChild("SosStateChanged")
local requestEvent = ReplicatedStorage:WaitForChild("SosRequestEvent")

-- ─────────────────────────────────────────────────────────────
-- API
-- ─────────────────────────────────────────────────────────────
function SosSystem.isSosActive(character)
    return activeSos[character] ~= nil
end

function SosSystem.getActiveSosTargets()
    local targets = {}
    for char, _ in pairs(activeSos) do
        if char and char.Parent then
            table.insert(targets, char)
        end
    end
    return targets
end

function SosSystem.clearSos(character)
    if not activeSos[character] then return end
    -- 자동 종료 타이머 취소 (수동/외부 정리 시 누수 방지)
    if activeSos[character].timer then
        task.cancel(activeSos[character].timer)
    end
    activeSos[character] = nil
    stateEvent:FireAllClients("sos_cleared", character)
    print("🆘 SOS 해제:", character.Name)
end

-- ─────────────────────────────────────────────────────────────
-- NPC용 직접 SOS 활성화 (Player 객체 없이 작동)
-- 테스트용 봇이나 자동 NPC에게 사용. 일반 플레이어 검증/쿨다운 없이 바로 활성화.
-- 다운 상태 검증은 호출자 책임.
-- ─────────────────────────────────────────────────────────────
function SosSystem.forceActivateSos(character)
    if not character or not character.Parent then return end
    if activeSos[character] then return end

    local timerHandle
    timerHandle = task.delay(SOS_DURATION, function()
        local entry = activeSos[character]
        if entry and entry.timer == timerHandle then
            activeSos[character] = nil
            stateEvent:FireAllClients("sos_cleared", character)
            print("🆘 SOS 자동 종료 (NPC):", character.Name)
        end
    end)

    activeSos[character] = { sentTime = tick(), timer = timerHandle }
    stateEvent:FireAllClients("sos_activated", character)
    print("🆘 SOS 활성화 (NPC):", character.Name)
end

-- ─────────────────────────────────────────────────────────────
-- SOS 활성화 시도 (클라이언트 요청 처리)
-- ─────────────────────────────────────────────────────────────
local function tryActivateSos(player)
    local character = player.Character
    if not character then return end

    -- 다운 상태 검증 (Downed 속성 = DownSystem이 설정)
    if not character:GetAttribute("Downed") then
        return  -- 다운 아닌 사람의 요청 무시
    end

    -- 이미 SOS 활성 상태면 무시 (자동 종료 후 재발신 가능)
    if activeSos[character] then
        return
    end

    -- 쿨다운 체크 (마지막 발신 시도로부터 SOS_COOLDOWN초 지나야 재발신 가능)
    local now = tick()
    if lastAttempt[character] and (now - lastAttempt[character]) < SOS_COOLDOWN then
        return
    end
    lastAttempt[character] = now

    -- SOS 활성화 + 자동 종료 타이머 등록
    -- 활성 상태가 SOS_DURATION초 동안 유지된 후 자동으로 sos_cleared 발신.
    -- 다운자가 살고 싶으면 타이머 만료 후 다시 Q/클릭으로 재발신해야 함.
    local timerHandle
    timerHandle = task.delay(SOS_DURATION, function()
        -- 타이머 만료 시점에 여전히 같은 SOS 세션이 활성 상태면 종료
        local entry = activeSos[character]
        if entry and entry.timer == timerHandle then
            activeSos[character] = nil
            stateEvent:FireAllClients("sos_cleared", character)
            print("🆘 SOS 자동 종료:", character.Name)
        end
    end)

    activeSos[character] = { sentTime = now, timer = timerHandle }
    stateEvent:FireAllClients("sos_activated", character)

    -- 쿨다운 종료 시점에 클라이언트에 알림 (버튼 활성화 복귀용)
    -- 다운자 본인에게만 발신
    local owner = Players:GetPlayerFromCharacter(character)
    if owner then
        task.delay(SOS_COOLDOWN, function()
            -- 쿨다운 종료 시점에 다운자가 여전히 존재하고 같은 lastAttempt 유지 중이면 알림
            if lastAttempt[character] == now then
                stateEvent:FireClient(owner, "cooldown_ended")
            end
        end)
    end

    print("🆘 SOS 활성화:", character.Name, "(", SOS_DURATION, "초간)")
end

requestEvent.OnServerEvent:Connect(tryActivateSos)

-- ─────────────────────────────────────────────────────────────
-- 캐릭터 사망/이탈 시 자동 정리
-- (DownSystem이 부활/사망 시 명시적으로 clearSos를 호출하지만,
--  외부 사망 등 예외 상황 대비 폴백)
-- ─────────────────────────────────────────────────────────────
local function watchCharacter(character)
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then
        hum = character:WaitForChild("Humanoid", 5)
    end
    if not hum then return end

    hum.Died:Connect(function()
        SosSystem.clearSos(character)
    end)
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(watchCharacter)
end)
for _, player in ipairs(Players:GetPlayers()) do
    if player.Character then watchCharacter(player.Character) end
    player.CharacterAdded:Connect(watchCharacter)
end

print("✅ SosSystem 활성화 (쿨다운:", SOS_COOLDOWN, "초)")

return SosSystem
