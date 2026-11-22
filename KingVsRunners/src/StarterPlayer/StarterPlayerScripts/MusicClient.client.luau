-- ════════════════════════════════════════════════════════════════
-- MusicClient  (StarterPlayerScripts / LocalScript)
-- ────────────────────────────────────────────────────────────────
-- 상황별 배경음악 매니저.
--  · RoundPhaseEvent("intermission"/"stage1") + Stage2Started 구독
--  · 내 생존상태(Role/Eliminated)와 조합해 적절한 BGM 선택
--  · 죽음/제외 시 로비 BGM (관전 느낌)
--  · crossfade로 부드럽게 전환
--  · _G.MusicEnabled (설정 토글) 연동
--
-- [음악 결정 규칙]
--   인터미션              → 로비
--   라운드 중 + 생존 + 1단계 → 1단계
--   라운드 중 + 생존 + 2단계 → 2단계
--   라운드 중 + 죽음/제외    → 로비 (관전)
-- ════════════════════════════════════════════════════════════════

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ── 음원 ID ──────────────────────────────────────────────────────
local TRACKS = {
    lobby  = "rbxassetid://118762225644778",  -- 로비/관전
    stage1 = "rbxassetid://126199584198103",  -- 라운드 1단계
    stage2 = "rbxassetid://73374900108244",   -- 2단계 진입
}

local TARGET_VOLUME = 0.5    -- 기본 음량
local FADE_TIME = 1.0        -- crossfade 시간(초)

-- ── SoundGroup ───────────────────────────────────────────────────
local musicGroup = SoundService:FindFirstChild("MusicGroup")
if not musicGroup then
    musicGroup = Instance.new("SoundGroup")
    musicGroup.Name = "MusicGroup"
    musicGroup.Volume = 1
    musicGroup.Parent = SoundService
end

-- ── 각 트랙용 Sound 객체 미리 생성 (루프 재생) ──────────────────
local sounds = {}
for key, id in pairs(TRACKS) do
    local s = Instance.new("Sound")
    s.Name = "Music_" .. key
    s.SoundId = id
    s.Looped = true
    s.Volume = 0          -- 시작은 무음, 필요 시 페이드 인
    s.SoundGroup = musicGroup
    s.Parent = SoundService
    sounds[key] = s
end

-- ── 상태 ─────────────────────────────────────────────────────────
local currentPhase = "intermission"  -- "intermission" | "stage1" | "stage2"
local phaseStartServerTime = os.time()  -- 현재 단계 곡이 서버에서 시작된 시각
local serverTimeOffset = 0              -- (서버 os.time) - (클라 os.time) 보정값
local currentTrackKey = nil           -- 지금 재생 중인 트랙 키
local activeTweens = {}

-- 설정 토글: _G.MusicEnabled (없으면 기본 ON)
local function musicEnabled()
    if _G.MusicEnabled == nil then return true end
    return _G.MusicEnabled
end

-- ── 페이드 헬퍼 ──────────────────────────────────────────────────
local function fadeTo(sound, targetVol, time)
    if activeTweens[sound] then
        activeTweens[sound]:Cancel()
        activeTweens[sound] = nil
    end
    -- 페이드 인이면 재생 보장 (멈춰 있던 트랙도 다시 켬)
    if targetVol > 0 and not sound.IsPlaying then
        sound:Play()
    end
    local tw = TweenService:Create(sound,
        TweenInfo.new(time, Enum.EasingStyle.Linear),
        { Volume = targetVol })
    activeTweens[sound] = tw
    tw:Play()
    -- 0으로 페이드된 경우에만, 이 tween이 정상 완료됐을 때 정지
    if targetVol <= 0 then
        task.spawn(function()
            tw.Completed:Wait()
            -- 이 tween이 여전히 최신이고 음량이 0이면 정지
            if activeTweens[sound] == tw and sound.Volume <= 0.01 then
                sound:Stop()
                activeTweens[sound] = nil
            end
        end)
    end
end

-- ── 특정 트랙으로 전환 (crossfade) ──────────────────────────────
-- seekTime: 지정 시 그 시간대(초)부터 재생 (관전 시 라운드 곡 동기화용)
local function playTrack(key, seekTime)
    if currentTrackKey == key then
        -- 이미 같은 트랙 — 음량만 토글 상태에 맞춤 (seek은 안 함: 이미 재생 중)
        local s = sounds[key]
        if s then fadeTo(s, musicEnabled() and TARGET_VOLUME or 0, FADE_TIME) end
        return
    end

    -- 이전 트랙 페이드 아웃
    if currentTrackKey and sounds[currentTrackKey] then
        fadeTo(sounds[currentTrackKey], 0, FADE_TIME)
    end

    currentTrackKey = key
    local s = sounds[key]
    if not s then return end

    if not s.IsPlaying then s:Play() end
    -- 지정 시간대부터 재생 (루프 길이 안에서)
    if seekTime and s.TimeLength and s.TimeLength > 0 then
        s.TimePosition = seekTime % s.TimeLength
    end
    fadeTo(s, musicEnabled() and TARGET_VOLUME or 0, FADE_TIME)
end

-- ── 내 생존/참여 상태 판단 ───────────────────────────────────────
-- 라운드 중 죽음/제외 = 관전 = 로비 음악
local function isSpectating()
    -- Eliminated 속성이 true면 탈락(관전)
    if player:GetAttribute("Eliminated") then return true end
    -- Role이 없으면 라운드에 참여 안 함 (제외)
    local role = player:GetAttribute("Role")
    if role == nil or role == "" then return true end
    return false
end

-- ── 현재 상태에 맞는 음악 결정 ──────────────────────────────────
-- 현재 곡만 페이드 아웃하고 새 곡은 틀지 않음 (죽은 직후 무음 구간용)
local function fadeOutCurrent()
    if currentTrackKey and sounds[currentTrackKey] then
        fadeTo(sounds[currentTrackKey], 0, FADE_TIME)
    end
    currentTrackKey = nil
end

-- 캐릭터가 살아있는지 (리스폰 완료 여부)
local function isCharacterAlive()
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

local function isSpectatingMode()
    return player:GetAttribute("Spectating") == true
end

-- 현재 라운드 단계 곡의 경과 시간(초) 계산
local function currentStageElapsed()
    -- 서버 시각 기준 경과 = (보정된 현재 클라 시각) - 단계 시작 서버 시각
    local nowServer = os.time() + serverTimeOffset
    return math.max(0, nowServer - phaseStartServerTime)
end

local function updateMusic()
    if currentPhase == "intermission" then
        playTrack("lobby")
        return
    end

    -- 라운드 중
    if isSpectatingMode() then
        -- 관전 중 → 현재 단계 곡을 진행 중인 시간대부터 재생
        local key = (currentPhase == "stage2") and "stage2" or "stage1"
        playTrack(key, currentStageElapsed())
        return
    end

    if isSpectating() then
        -- 죽음/제외 + 관전 아님 → 로비(관전 종료 상태). 리스폰 후에만 재생.
        if isCharacterAlive() then
            playTrack("lobby")
        else
            fadeOutCurrent()  -- 죽은 직후: 무음 대기
        end
        return
    end

    -- 살아서 플레이 중
    if currentPhase == "stage2" then
        playTrack("stage2")
    else
        playTrack("stage1")
    end
end

-- ── 이벤트 구독 ──────────────────────────────────────────────────
local phaseEvent = ReplicatedStorage:WaitForChild("RoundPhaseEvent")
phaseEvent.OnClientEvent:Connect(function(phase, serverStartTime)
    currentPhase = phase
    if serverStartTime then
        phaseStartServerTime = serverStartTime
        serverTimeOffset = serverStartTime - os.time()  -- 서버-클라 시각차 보정
    end
    updateMusic()
end)

local stage2Event = ReplicatedStorage:WaitForChild("Stage2Started")
stage2Event.OnClientEvent:Connect(function(_reachedName, serverStartTime)
    currentPhase = "stage2"
    if serverStartTime then
        phaseStartServerTime = serverStartTime
        serverTimeOffset = serverStartTime - os.time()
    end
    updateMusic()
end)

-- 생존 상태 변화 감지 (죽으면 관전 음악으로)
-- 죽는 순간 Eliminated/Role이 거의 동시에 바뀔 수 있어 디바운스로 한 번만 처리
local pendingUpdate = false
local function debouncedUpdate()
    if pendingUpdate then return end
    pendingUpdate = true
    task.defer(function()
        pendingUpdate = false
        updateMusic()
    end)
end
player:GetAttributeChangedSignal("Eliminated"):Connect(debouncedUpdate)
player:GetAttributeChangedSignal("Role"):Connect(debouncedUpdate)
player:GetAttributeChangedSignal("Spectating"):Connect(debouncedUpdate)

-- 리스폰 감지: 캐릭터가 다시 생기면 음악 갱신 (죽은 뒤 로비곡은 이때부터)
player.CharacterAdded:Connect(function(char)
    -- Humanoid가 준비될 때까지 잠깐 기다린 뒤 갱신
    char:WaitForChild("Humanoid", 5)
    task.wait(0.3)
    debouncedUpdate()
end)

-- 설정 토글이 바뀔 때 음량 즉시 반영하도록 폴링 (가벼움)
task.spawn(function()
    local lastEnabled = musicEnabled()
    while true do
        task.wait(0.3)
        local now = musicEnabled()
        if now ~= lastEnabled then
            lastEnabled = now
            if currentTrackKey and sounds[currentTrackKey] then
                fadeTo(sounds[currentTrackKey], now and TARGET_VOLUME or 0, 0.4)
            end
        end
    end
end)

-- 시작: 로비 음악
updateMusic()

print("🎵 MusicClient 활성화 (lobby/stage1/stage2)")
