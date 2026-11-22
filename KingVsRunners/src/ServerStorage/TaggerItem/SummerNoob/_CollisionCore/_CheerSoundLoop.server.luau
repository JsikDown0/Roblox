-- SummerNoob 환호 사운드: splash처럼 반복하되 주기를 길게 (가끔 "예후~" 터짐)
local sound = script.Parent:FindFirstChild("_CheerSound")
if not sound then return end

-- 간격 설정 (사운드 길이 3.66초 + 충분한 쉼)
local MIN_GAP = 8    -- 최소 간격(초)
local MAX_GAP = 12   -- 최대 간격(초)
local FIRST_DELAY = 1.5  -- 스폰 후 첫 환호까지 살짝 대기
local START_AT = 0.5  -- 앞부분 빈 구간 건너뛰고 0.5초부터 재생

task.wait(FIRST_DELAY)
while script.Parent and script.Parent.Parent do
    sound.TimePosition = START_AT  -- 0.5초 지점부터 시작
    sound:Play()
    -- 실제 재생 길이(전체 - 시작점)만큼 + 랜덤 쉼
    local playLen = math.max(0, sound.TimeLength - START_AT)
    local gap = playLen + math.random(MIN_GAP, MAX_GAP)
    task.wait(gap)
end
