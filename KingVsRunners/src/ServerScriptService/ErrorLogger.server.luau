-- ErrorLogger
-- 서버에서 발생한 런타임 오류를 콘솔에 모아 출력한다.
--
-- 설계 의도:
--  · 저장·전송을 하지 않는다. DataStore 쓰기는 한도가 있어(이미 큐 경고가 나는 상태)
--    오류가 연쇄로 터지면 정작 중요한 플레이어 데이터 저장이 밀린다.
--  · 평시 비용 0 — ScriptContext.Error 는 오류가 났을 때만 발화한다.
--  · 같은 오류 반복은 묶어서 센다. 한 프레임에 수백 번 나는 경우가 있어
--    그대로 찍으면 콘솔이 도배되고 정작 다른 오류가 묻힌다.
--
-- 출시 후 개선 여지: 안정화되면 60초 버퍼 + DataStore 기록을 추가.

local ScriptContext = game:GetService("ScriptContext")

local REPEAT_WINDOW = 30      -- 같은 오류를 묶는 시간(초)
local SUMMARY_EVERY = 120     -- 누적 요약 출력 주기(초)

local seen  = {}   -- [key] = { count, firstAt, lastAt, script, message }
local total = 0

ScriptContext.Error:Connect(function(message, stackTrace, scriptInstance)
    total += 1
    local where = scriptInstance and scriptInstance:GetFullName() or "(unknown)"
    -- 메시지에서 줄번호까지 포함해 키를 만들면 같은 지점의 반복을 정확히 묶는다
    local key = where .. "|" .. tostring(message)
    local now = os.clock()

    local e = seen[key]
    if e then
        e.count += 1
        -- 반복 억제: 창 안에서는 다시 찍지 않는다
        if now - e.lastAt < REPEAT_WINDOW then
            e.lastAt = now
            return
        end
        e.lastAt = now
        warn(string.format("[Error x%d] %s | 위치: %s", e.count, tostring(message), where))
        return
    end

    seen[key] = { count = 1, firstAt = now, lastAt = now, script = where, message = message }
    warn(string.format("[Error] %s | 위치: %s | 스택: %s",
        tostring(message), where, tostring(stackTrace):sub(1, 250)))
end)

-- 누적 요약: 어떤 오류가 가장 자주 나는지 한눈에
task.spawn(function()
    while true do
        task.wait(SUMMARY_EVERY)
        if total > 0 then
            local list = {}
            for _, e in pairs(seen) do list[#list + 1] = e end
            table.sort(list, function(a, b) return a.count > b.count end)
            print(string.format("── [ErrorLogger] 누적 %d건 / 고유 %d종 ──", total, #list))
            for i = 1, math.min(#list, 5) do
                local e = list[i]
                print(string.format("   %d회  %s  (%s)",
                    e.count, tostring(e.message):sub(1, 70), e.script))
            end
        end
    end
end)

print("✅ ErrorLogger 활성화 (콘솔 전용, 저장 없음)")
