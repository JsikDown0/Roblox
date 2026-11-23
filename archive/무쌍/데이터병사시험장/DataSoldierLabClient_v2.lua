--[[ DataSoldierLabClient v2 (7바이트: id·x·z·편 — 높이 없음) (2026-11-10) — 데이터 병사 1단계 클라: 받기 · 풀기만 (화면 표시 없음)
  workspace 속성 DataSoldierLab 이 0 이나 없으면 아무것도 안 한다. 5초마다 한 줄.
]]
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local LAB = workspace:GetAttribute("DataSoldierLab")
if not LAB or LAB == 0 then return end

local snap = RS:WaitForChild("DataSoldierSnap", 30)
if not snap then warn("[데이터병사C] DataSoldierSnap 없음"); return end

local px, py, pz, pt = {}, {}, {}, {}
local bytes, packets, decodeSum, seen = 0, 0, 0, {}
snap.OnClientEvent:Connect(function(b)
	local t0 = os.clock()
	local n = buffer.len(b) // 7
	local off = 0
	for _ = 1, n do
		local id = buffer.readu16(b, off)
		px[id] = buffer.readi16(b, off + 2) / 4
		pz[id] = buffer.readi16(b, off + 4) / 4
		pt[id] = buffer.readu8(b, off + 6)
		seen[id] = true
		off += 7
	end
	decodeSum += os.clock() - t0
	bytes += buffer.len(b); packets += 1
end)

local frames, dtSum, over33 = 0, 0, 0
RunService.RenderStepped:Connect(function(dt)
	frames += 1; dtSum += dt
	if dt > 0.033 then over33 += 1 end
end)

while true do
	task.wait(5)
	local u = 0 for _ in pairs(seen) do u += 1 end
	print(("[데이터병사C] %s | 받은 병사 %d | 수신 %.1fkbps 패킷/초 %.1f | 풀기 %.2fms/초 | 화면 프레임 평균 %.1fms · 33ms넘음 %d"):format(
		tostring(workspace:GetAttribute("DataSoldierPhase") or "-"), u, bytes * 8 / 1000 / 5, packets / 5,
		decodeSum * 1000 / 5, frames > 0 and dtSum / frames * 1000 or 0, over33))
	bytes, packets, decodeSum, seen, frames, dtSum, over33 = 0, 0, 0, {}, 0, 0, 0
end
