-- DragonAnimDriver : 날갯짓 루프(Looped=true) → FrostEnding 시 엔딩 애니로 크로스페이드
--
-- [설계]
--   * FlapAnim: Looped=true → 경계에서 트랙이 죽지 않음 (rest pose 버그 원천 소멸)
--   * EndAnim : Looped=false. 끝나면 트랙이 종료되며 포즈가 rest로 튕김(=제자리 복귀처럼 보임).
--               → Play() 직후부터 매 프레임 감시하여 끝 직전 AdjustSpeed(0)으로 포즈 고정.
--   [주의] Length 대기 루프는 수백 ms 걸릴 수 있음. 고정 타이머를 그 뒤에 걸면 지각함.
--          반드시 Play() 직후 감시를 시작할 것.
local dragon = script.Parent
local FLAP_SPEED  = 3.0    -- 날갯짓 속도 (원본 3.33s/사이클 → 약 1.1s)
local END_SPEED   = 1.0    -- 엔딩 재생 속도 (낮추면 이륙이 느긋해짐)
local FADE        = 0.3    -- 크로스페이드 시간
local HOLD_MARGIN = 0.10   -- 엔딩 끝 이만큼 전에 정지 (클라 복제 여유)

local ac = dragon:WaitForChild("AnimationController")
local animator = ac:WaitForChild("Animator")
local flapAnim = dragon:WaitForChild("FlapAnim")
local endAnim  = dragon:WaitForChild("EndAnim")

local flap = animator:LoadAnimation(flapAnim)
flap.Looped = true
flap.Priority = Enum.AnimationPriority.Idle
flap:Play(0.2)
flap:AdjustSpeed(FLAP_SPEED)

local ending = false
dragon:GetAttributeChangedSignal("FrostEnding"):Connect(function()
	if not dragon:GetAttribute("FrostEnding") or ending then return end
	ending = true

	local fin = animator:LoadAnimation(endAnim)
	fin.Looped = false
	fin.Priority = Enum.AnimationPriority.Action
	fin:Play(FADE)
	fin:AdjustSpeed(END_SPEED)
	flap:Stop(FADE)
	local playStart = os.clock()

	local held = false
	local function hold(why)
		if held then return end
		held = true
		fin:AdjustSpeed(0)
		print(string.format("[DragonAnim] 포즈 고정 (%s) t=%.2f", why, fin.TimePosition))
	end

	-- ★ Play() 직후 즉시 감시 시작 (Length 대기와 병렬 — 지각 방지)
	task.spawn(function()
		while not held do
			local L = fin.Length
			if L > 0 and fin.TimePosition >= L - HOLD_MARGIN then hold("끝 직전"); break end
			if not fin.IsPlaying then break end
			task.wait()
		end
	end)
	-- 안전장치: 그래도 끝나버리면 마지막 포즈로 되잡기
	fin.Stopped:Connect(function()
		if held then return end
		warn("[DragonAnim] 엔딩 트랙 종료 감지 → 마지막 포즈 복원")
		held = true
		fin:Play(0)
		fin.TimePosition = math.max(0, fin.Length - 0.02)
		fin:AdjustSpeed(0)
	end)

	-- 길이 확보(로그/페이드 타이밍용)
	local t0 = os.clock()
	while fin.Length <= 0 and os.clock() - t0 < 3 do task.wait(0.05) end
	local len = fin.Length
	local dur = len / math.max(END_SPEED, 0.01)
	print(string.format("[DragonAnim] 엔딩 재생 (length=%.2fs, speed=%.1fx → %.2fs)", len, END_SPEED, dur))

	-- 이륙 다 보여준 뒤 페이드 신호 (Play 시점 기준으로 보정)
	local elapsed = os.clock() - playStart
	task.delay(math.max(0, dur - elapsed + 0.05), function()
		dragon:SetAttribute("FrostEndingDone", true)
	end)
end)

print(string.format("[DragonAnim] 날갯짓 루프 시작 (speed=%.1fx)", FLAP_SPEED))
