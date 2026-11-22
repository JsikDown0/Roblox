-- SandWindController — map2 사막 랜덤 모래바람 (C안)
-- 미세(플레이 무영향) + 랜덤 출현: 45~120초 간격으로 8~15초 재생, 페이드 인/아웃.
-- 이 Script는 map2 폴더 소속 → 맵이 workspace에 있을 때만 실행되고
-- 라운드 스왑으로 ServerStorage에 들어가면 자동 정지 (map1 라운드 무영향).

local folder = script.Parent:WaitForChild("SandWind")

local RATE_MAX = 8       -- 재생 시 이미터 rate (미세 톤)
local FADE = 1.5         -- 페이드 인/아웃 시간
local GAP_MIN, GAP_MAX = 45, 120   -- 출현 간격
local DUR_MIN, DUR_MAX = 8, 15     -- 지속 시간

local emitters = {}
for _, d in ipairs(folder:GetDescendants()) do
	if d:IsA("ParticleEmitter") then emitters[#emitters + 1] = d end
end
if #emitters == 0 then return end

local rng = Random.new()

local function setRate(r)
	for _, e in ipairs(emitters) do e.Rate = r end
end

local function fadeTo(target, dur)
	local start = emitters[1].Rate
	local t0 = os.clock()
	while os.clock() - t0 < dur do
		local a = (os.clock() - t0) / dur
		setRate(start + (target - start) * a)
		task.wait(0.1)
	end
	setRate(target)
end

setRate(0)
task.wait(rng:NextNumber(10, 25))  -- 첫 출현은 라운드 초반 이후
while true do
	fadeTo(RATE_MAX, FADE)
	task.wait(rng:NextNumber(DUR_MIN, DUR_MAX))
	fadeTo(0, FADE)
	task.wait(rng:NextNumber(GAP_MIN, GAP_MAX))
end
