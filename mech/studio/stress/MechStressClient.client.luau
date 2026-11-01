-- MechStressClient (LocalScript → StarterPlayer.StarterPlayerScripts)
-- 화면 왼쪽 위: 지금 FPS · 1% 저점 · 메모리 · 핑 · 서버 FPS + 버튼(−2 / +2 / 걷기 / 사격 / 조준 / 자동 측정 / 중심 다시)
-- 자동 측정: 기체 0 → 2 → 4 → 6 → 8 → 10 → 12 대, 단계마다 4초 안정 + 10초 측정 → 출력 창에 표 출력(그대로 복사해서 보내 주세요)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local STAGES = { 0, 2, 4, 6, 8, 10, 12 }
local WARMUP, MEASURE = 4, 10

local player = Players.LocalPlayer
local cmd = ReplicatedStorage:WaitForChild("MechStressCmd")
local folder = workspace:WaitForChild("StressMechs")

-- 프레임마다 실제로 쓴 시간(60 FPS 상한과 상관없음). 속성이 없는 버전이면 -1
local function statMs(name)
	local ok, v = pcall(function() return Stats[name] end)
	if ok and type(v) == "number" then return v end
	return -1
end

-- ---------- 프레임 기록 ----------
local recent = {}          -- 최근 1초 dt(화면 표시용)
local recording = nil      -- 자동 측정 중 dt 목록
local cpuRec, gpuRec = nil, nil
RunService.RenderStepped:Connect(function(dt)
	table.insert(recent, dt)
	if recording then
		table.insert(recording, dt)
		table.insert(cpuRec, statMs("RenderCPUFrameTime"))
		table.insert(gpuRec, statMs("RenderGPUFrameTime"))
	end
end)
local function mean(list)
	if not list or #list == 0 then return -1 end
	local s = 0
	for _, v in ipairs(list) do s += v end
	return s / #list
end

local function summarize(list)
	if #list == 0 then return 0, 0, 0 end
	local sum = 0
	for _, d in ipairs(list) do sum += d end
	local sorted = table.clone(list)
	table.sort(sorted)
	local p99 = sorted[math.max(1, math.ceil(#sorted * 0.99))]
	return #list / sum, 1 / p99, sum / #list * 1000   -- 평균 FPS, 1% 저점 FPS, 평균 프레임 ms
end

local function memMB() return math.floor(Stats:GetTotalMemoryUsageMb()) end
local function pingMS() return math.floor(player:GetNetworkPing() * 1000) end

-- ---------- 화면 ----------
local gui = Instance.new("ScreenGui")
gui.Name = "MechStressGui"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Position = UDim2.fromOffset(10, 10); panel.Size = UDim2.fromOffset(330, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.fromRGB(15, 16, 22); panel.BackgroundTransparency = 0.25
panel.Parent = gui
local pad = Instance.new("UIPadding"); pad.PaddingTop = UDim.new(0, 8); pad.PaddingBottom = UDim.new(0, 8)
pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8); pad.Parent = panel
local list = Instance.new("UIListLayout"); list.Padding = UDim.new(0, 6); list.SortOrder = Enum.SortOrder.LayoutOrder; list.Parent = panel

local info = Instance.new("TextLabel")
info.LayoutOrder = 1; info.Size = UDim2.new(1, 0, 0, 0); info.AutomaticSize = Enum.AutomaticSize.Y
info.BackgroundTransparency = 1; info.TextColor3 = Color3.new(1, 1, 1); info.Font = Enum.Font.Code
info.TextSize = 14; info.TextXAlignment = Enum.TextXAlignment.Left; info.TextYAlignment = Enum.TextYAlignment.Top
info.TextWrapped = true; info.Text = "MechStress"; info.Parent = panel

local row = Instance.new("Frame")
row.LayoutOrder = 2; row.Size = UDim2.new(1, 0, 0, 0); row.AutomaticSize = Enum.AutomaticSize.Y
row.BackgroundTransparency = 1; row.Parent = panel
local grid = Instance.new("UIGridLayout"); grid.CellSize = UDim2.fromOffset(100, 36); grid.CellPadding = UDim2.fromOffset(5, 5)
grid.SortOrder = Enum.SortOrder.LayoutOrder; grid.Parent = row

local function button(text, order, onClick)
	local b = Instance.new("TextButton")
	b.LayoutOrder = order; b.Text = text; b.TextSize = 15; b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1); b.BackgroundColor3 = Color3.fromRGB(55, 60, 75); b.AutoButtonColor = true
	b.Parent = row
	b.Activated:Connect(onClick)
	return b
end

local busy = false
local function count() return folder:GetAttribute("Count") or #folder:GetChildren() end

button("−2", 1, function() if not busy then cmd:FireServer("setCount", count() - 2) end end)
button("+2", 2, function() if not busy then cmd:FireServer("setCount", count() + 2) end end)
local bWalk = button("걷기", 3, function() cmd:FireServer("flag", "Walk") end)
local bFire = button("사격", 4, function() cmd:FireServer("flag", "Fire") end)
local bAim = button("조준", 5, function() cmd:FireServer("flag", "Aim") end)
button("중심 다시", 6, function() if not busy then cmd:FireServer("recenter") end end)
local bAuto

local function flagColor(b, on) b.BackgroundColor3 = on and Color3.fromRGB(40, 140, 90) or Color3.fromRGB(55, 60, 75) end

local function platform()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then return "모바일" end
	return "PC"
end

-- ---------- 자동 측정 ----------
local results = {}
local function runAuto()
	if busy then return end
	busy = true; bAuto.Text = "측정 중…"
	results = {}
	local flags = ("걷기=%s 사격=%s 조준=%s"):format(tostring(folder:GetAttribute("Walk")), tostring(folder:GetAttribute("Fire")), tostring(folder:GetAttribute("Aim")))
	for _, n in ipairs(STAGES) do
		cmd:FireServer("setCount", n)
		local t0 = os.clock()
		while count() ~= n and os.clock() - t0 < 5 do task.wait(0.1) end
		task.wait(WARMUP)
		cpuRec, gpuRec = {}, {}
		recording = {}
		task.wait(MEASURE)
		local rec = recording; recording = nil
		local avg, low, ms = summarize(rec)
		local r = { n = count(), avg = avg, low = low, ms = ms, cpu = mean(cpuRec), gpu = mean(gpuRec), mem = memMB(), srv = folder:GetAttribute("ServerFPS") or 0, ping = pingMS() }
		table.insert(results, r)
		print(("[MechStress] 기체 %2d | FPS 평균 %5.1f · 1%%저점 %5.1f · %5.1fms | CPU %5.2fms · GPU %5.2fms | 메모리 %dMB | 서버 %4.1f | 핑 %dms"):format(r.n, r.avg, r.low, r.ms, r.cpu, r.gpu, r.mem, r.srv, r.ping))
	end
	local lines = { ("===== MechStress 결과 (%s · %s · 단계마다 %ds 측정) ====="):format(platform(), flags, MEASURE),
		"기체 | FPS평균 | 1%저점 | 프레임ms | CPUms | GPUms | 메모리MB | 서버FPS | 핑ms" }
	for _, r in ipairs(results) do
		table.insert(lines, ("%4d | %7.1f | %6.1f | %8.1f | %5.2f | %5.2f | %8d | %7.1f | %4d"):format(r.n, r.avg, r.low, r.ms, r.cpu, r.gpu, r.mem, r.srv, r.ping))
	end
	table.insert(lines, "=====")
	print(table.concat(lines, string.char(10)))
	busy = false; bAuto.Text = "자동 측정"
end
bAuto = button("자동 측정", 7, function() task.spawn(runAuto) end)

-- ---------- 화면 갱신(0.5초) ----------
task.spawn(function()
	while true do
		task.wait(0.5)
		local window = recent; recent = {}
		local avg, low = summarize(window)
		local lastLine = ""
		if #results > 0 then
			local r = results[#results]
			lastLine = ("\n마지막 단계: %d대 · %.1f / %.1f FPS"):format(r.n, r.avg, r.low)
		end
		info.Text = ("기체 %d대 · %s%s\nFPS %.1f (저점 %.1f) · CPU %.2fms · GPU %.2fms\n메모리 %dMB · 핑 %dms · 서버 %.1f%s"):format(
			count(), platform(), busy and " · 자동 측정 중" or "",
			avg, low, statMs("RenderCPUFrameTime"), statMs("RenderGPUFrameTime"), memMB(), pingMS(), folder:GetAttribute("ServerFPS") or 0, lastLine)
		flagColor(bWalk, folder:GetAttribute("Walk")); flagColor(bFire, folder:GetAttribute("Fire")); flagColor(bAim, folder:GetAttribute("Aim"))
	end
end)
