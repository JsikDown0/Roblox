-- MechHUD (ModuleScript, MechClient 의 자식) — 10-30 MechClient 에서 떼어 냄(Script.Source 20만 자 한도 — MechPoses 머리 주석)
--   옛 MechClient 202~357줄(makeHUD) 그대로. 바깥 이름은 player 하나뿐 → 여기서 LocalPlayer 로 직접
--   MechClient: local makeHUD = require(script.MechHUD).make → 예전과 같이 makeHUD() 로 부름
local player = game:GetService("Players").LocalPlayer
-- ================= HUD =================
local function makeHUD()
	local g = Instance.new("ScreenGui")
	g.Name = "MechHUD"; g.ResetOnSpawn = false; g.IgnoreGuiInset = true; g.DisplayOrder = 5
	local W = Color3.fromRGB(235, 240, 245)
	local function frame(parent, size, pos, color, anchor)
		local f = Instance.new("Frame")
		f.Size = size; f.Position = pos; f.BackgroundColor3 = color; f.BorderSizePixel = 0
		f.AnchorPoint = anchor or Vector2.new(0.5, 0.5); f.Parent = parent
		return f
	end
	frame(g, UDim2.fromOffset(4, 4), UDim2.fromScale(0.5, 0.5), W)
	-- 조준선 4갈래: 벌어진 정도 = 실제 탄 퍼짐(카메라 단계가 매 프레임 옮김)
	local chU = frame(g, UDim2.fromOffset(2, 10), UDim2.new(0.5, 0, 0.5, -14), W)
	local chD = frame(g, UDim2.fromOffset(2, 10), UDim2.new(0.5, 0, 0.5, 14), W)
	local chL = frame(g, UDim2.fromOffset(10, 2), UDim2.new(0.5, -14, 0.5, 0), W)
	local chR = frame(g, UDim2.fromOffset(10, 2), UDim2.new(0.5, 14, 0.5, 0), W)
	-- 10-27 HUD 재배치(메카 브레이크식, 유저 "HUD만 작업하자"): 가운데 카메라라 기체가 화면 아래 가운데를 차지한다.
	--   옛 막대·무장 글자(화면 아래 가운데)는 기체 다리·허리 위에 겹쳐 흰 기체 위 흰 글자가 안 읽혔음(유저 녹화 13:24).
	--   → HP·BOOST = 조준점을 감싸는 호(왼쪽 HP · 오른쪽 BOOST, 아래에서 위로 참) · 무장 = 조준점 오른쪽 세로 목록 · 조작 안내 = 왼쪽 아래.
	--   [MB 팔콘 영상 실측: 호 반지름 ≈ 화면 높이 0.24, 왼쪽 131~175° / 오른쪽 5~49°]. 링 = 화면 높이 기준 정사각(SizeConstraint RelativeYY)
-- 10-27 14:06 HUD = C안 "모니터 모서리"(유저 "메카 브레이크랑 넘 비슷해" → 시안 A/B/C 중 C). 원형 링(MB 실루엣)을 버리고
	--   화면 가운데를 사각 모니터 테 네 모서리로 감쌈 · 양옆 눈금 · 안쪽 작은 십자 4 · HP/BOOST = 모니터 아래 모서리를 따라 가는 블록 막대(바깥에서 안쪽으로 참)
	--   · 무장 = 오른쪽 테 바깥 세로 목록. 배치 원칙(조준점 가까이 · 기체 안 가림)은 그대로, 겉모양만 우리 것(콕핏 모니터 → 출격·탑승 연출로 이어 갈 테).
	--   옛 원형 링 = ServerStorage._HudC_before_20261027. 단위 = 화면 높이(정사각 판 SizeConstraint RelativeYY, 가운데 0.5). 선 두께 2px 고정
local mon = Instance.new("Frame")
	mon.Name = "Monitor"; mon.BackgroundTransparency = 1; mon.AnchorPoint = Vector2.new(0.5, 0.5)
	mon.Position = UDim2.fromScale(0.5, 0.5); mon.Size = UDim2.fromScale(1, 1); mon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	mon.Parent = g
	-- 테 크기(14:16 "넓혀 보고 싶어" · 14:22 "커스텀 — 축소·확장·아예 닫기(HP·부스트 같은 필수 정보는 남김)"):
	--   플레이어 속성 HudFrame = 1~4 단계(반너비 0.40 / 0.47 / 0.55 / 0.62, 기본 4) · HudFrameOff = 테 끔(모서리·눈금·십자만 숨기고
	--   HP·BOOST 막대·무장 목록·조준선은 1단계 자리에 남김). [ / ] / H 로 바꾸면 HUD 를 다시 만듦(입력 처리). 저장소가 없어 이 세션만 기억.
	--   반너비는 화면 가로를 넘지 않게 min(단계값, 가로/세로 ÷ 2 − 0.04) · 반높이 = 0.27 → 0.36 을 반너비에 비례
	local FRAME_MX = { 0.40, 0.47, 0.55, 0.62 }
	local off = player:GetAttribute("HudFrameOff") == true
	local stepN = off and 1 or math.clamp(player:GetAttribute("HudFrame") or 4, 1, 4)
	local vp = workspace.CurrentCamera.ViewportSize
	local aspect = vp.X / math.max(1, vp.Y)
	local MX = math.min(FRAME_MX[stepN], aspect / 2 - 0.04)
	local MY, DIM = 0.27 + (MX - 0.40) * 0.09 / 0.22, Color3.fromRGB(25, 27, 32)   -- 반높이(화면 높이 단위)
	local function P(x, y) return UDim2.fromScale(0.5 + x, 0.5 + y) end
	local function hl(x0, x1, y, transp)   -- 가로선
		local f = frame(mon, UDim2.new(math.abs(x1 - x0), 0, 0, 2), P((x0 + x1) / 2, y), W); f.BackgroundTransparency = transp
	end
	local function vl(x, y0, y1, transp)   -- 세로선
		local f = frame(mon, UDim2.new(0, 2, math.abs(y1 - y0), 0), P(x, (y0 + y1) / 2), W); f.BackgroundTransparency = transp
	end
	if not off then
		-- 네 모서리: ㄱ자 두 변 + 꺾이는 곳은 45° 짧은 사선(둥근 모서리 느낌)
		local CL, CC = 0.07 + (MX - 0.40) * 0.02 / 0.22, 0.02
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				local x, y = sx * MX, sy * MY
				vl(x, y - sy * CL, y - sy * CC, 0.35)
				hl(x - sx * CL, x - sx * CC, y, 0.35)
				local d = frame(mon, UDim2.new(CC * 1.414, 0, 0, 2), P(x - sx * CC / 2, y - sy * CC / 2), W)
				d.Rotation = (sx * sy > 0) and -45 or 45; d.BackgroundTransparency = 0.35
			end
		end
		-- 양옆 눈금(테에서 안쪽으로, 가운데 기준 4칸마다 길게) — 모서리 선 아래·위까지
		local half = math.floor((MY - 0.12) / 0.04 + 0.5)
		for k = -half, half do
			local ln = (k % 4 == 0) and 0.02 or 0.01
			for _, sx in ipairs({ -1, 1 }) do hl(sx * MX, sx * (MX - ln), k * 0.04, (k % 4 == 0) and 0.3 or 0.5) end
		end
		-- 안쪽 작은 십자 4(모니터 화면 표식)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				local a1 = frame(mon, UDim2.fromOffset(12, 2), P(sx * 0.49 * MX, sy * 0.47 * MY), W); a1.BackgroundTransparency = 0.55
				local a2 = frame(mon, UDim2.fromOffset(2, 12), P(sx * 0.49 * MX, sy * 0.47 * MY), W); a2.BackgroundTransparency = 0.55
			end
		end
	end
	-- 아래 모서리 블록 막대: 바깥 끝에서 안쪽으로 참(줄면 안쪽 칸부터 꺼짐). 안쪽 끝은 기체 팔·총(±0.13) 바깥 0.18 보다 안으로 안 옴
	local NB = 10
	local function bar(sx, color, label)
		local x0, x1 = sx * (MX - 0.03), sx * math.max(0.18, MX - 0.27)
		local w = math.abs(x1 - x0) / NB
		local blocks = {}
		for i = 0, NB - 1 do
			local f = frame(mon, UDim2.new(w, -3, 0.0125, 0), P(x0 + (x1 - x0) * (i + 0.5) / NB, MY), DIM); f.BackgroundTransparency = 0.45
			blocks[i + 1] = f
		end
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1; t.Font = Enum.Font.GothamBold; t.TextSize = 13; t.TextColor3 = W; t.TextStrokeTransparency = 0.6
		t.Size = UDim2.fromOffset(110, 16); t.Text = label
		t.AnchorPoint = Vector2.new(sx < 0 and 0 or 1, 0.5); t.Position = P(x0, MY - 0.035)
		t.TextXAlignment = sx < 0 and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
		t.Parent = mon
		local shown = -1
		return function(frac)   -- 켠 칸 수가 바뀔 때만 칠함
			local n = math.clamp(math.ceil(frac * NB - 1e-6), 0, NB)
			if n == shown then return end
			shown = n
			for i, f in ipairs(blocks) do
				f.BackgroundColor3 = (i <= n) and color or DIM
				f.BackgroundTransparency = (i <= n) and 0.05 or 0.45
			end
		end, t
	end
	local setHP, hpText = bar(-1, Color3.fromRGB(255, 120, 24), "HP")
	local setEN = bar(1, Color3.fromRGB(90, 230, 255), "BOOST")
	-- 10-30 궁극기 공용 게이지(CFG.Ult, 모든 기체): BOOST 막대 바로 밑 얇은 막대(바깥에서 안쪽으로 참) · 보라(HP 주황·BOOST 청록과 다른 색 = 다른 정보)
	--   글자: 차는 중 "ULT 64%" · 다 참 "ULT READY  [X]"(깜빡) · 쓰는 중 "ULT 4.2"(남은 초, 막대도 줄어듦) · 궁극기 없는 기체 = 회색 "ULT"(게이지만 참)
	local ULTC = Color3.fromRGB(190, 120, 255)
	local ux0, ux1 = MX - 0.03, math.max(0.18, MX - 0.27)
	local uw = math.abs(ux1 - ux0) / NB
	local ublocks = {}
	for i = 0, NB - 1 do
		local f = frame(mon, UDim2.new(uw, -3, 0.007, 0), P(ux0 + (ux1 - ux0) * (i + 0.5) / NB, MY + 0.024), DIM); f.BackgroundTransparency = 0.45
		ublocks[i + 1] = f
	end
	local ut = Instance.new("TextLabel")
	ut.BackgroundTransparency = 1; ut.Font = Enum.Font.GothamBold; ut.TextSize = 13; ut.TextColor3 = W; ut.TextStrokeTransparency = 0.6
	ut.Size = UDim2.fromOffset(160, 16); ut.Text = "ULT"; ut.RichText = true
	ut.AnchorPoint = Vector2.new(1, 0.5); ut.Position = P(ux0, MY + 0.05); ut.TextXAlignment = Enum.TextXAlignment.Right
	ut.Parent = mon
	local uShown, uText = -1, nil
	local function setULT(frac, text, lit)
		local n = math.clamp(math.ceil(frac * NB - 1e-6), 0, NB)
		local key = n * 2 + (lit and 1 or 0)
		if key ~= uShown then
			uShown = key
			for i, f in ipairs(ublocks) do
				f.BackgroundColor3 = (i <= n) and ULTC or DIM
				f.BackgroundTransparency = (i <= n) and (lit and 0 or 0.2) or 0.45
			end
		end
		if text ~= uText then uText = text; ut.Text = text end
	end
	-- 무장 표시: 테 오른쪽 바깥에 자리(260px + 여유)가 있으면 바깥 왼쪽 정렬, 없으면 테 안쪽 오른쪽 정렬. 지금 든 무기만 흰색 굵게
	local wl = Instance.new("TextLabel")
	wl.BackgroundTransparency = 1; wl.Size = UDim2.fromOffset(260, 110)
	wl.Font = Enum.Font.GothamMedium; wl.TextSize = 15; wl.RichText = true; wl.TextColor3 = W; wl.TextStrokeTransparency = 0.6
	wl.TextYAlignment = Enum.TextYAlignment.Top; wl.LineHeight = 1.35
	if (aspect / 2 - MX) * vp.Y >= 290 then
		wl.AnchorPoint = Vector2.new(0, 0); wl.Position = UDim2.new(0.5 + MX, 16, 0.5 - 0.04, 0); wl.TextXAlignment = Enum.TextXAlignment.Left
	else
		wl.AnchorPoint = Vector2.new(1, 0); wl.Position = UDim2.fromScale(0.5 + MX - 0.04, 0.5 - 0.04); wl.TextXAlignment = Enum.TextXAlignment.Right
	end
	wl.Text = '<font color="#FFFFFF"><b>1 라이플</b></font>' .. string.char(10) .. '<font color="#8A93A0">2 빔사벨</font>'
	wl.Parent = mon
	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1; hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.new(0, 16, 1, -12); hint.Size = UDim2.new(0.42, 0, 0, 36)
	hint.TextXAlignment = Enum.TextXAlignment.Left; hint.TextYAlignment = Enum.TextYAlignment.Bottom; hint.TextWrapped = true
	hint.Font = Enum.Font.GothamMedium; hint.TextSize = 12; hint.TextColor3 = W; hint.TextTransparency = 0.35; hint.TextStrokeTransparency = 0.8
	hint.Text = "클릭 사격   ·   우클릭 줌   ·   Shift / Q 부스트(누르고 있으면 지속)   ·   Space 점프   ·   F 하차"
	hint.Text = hint.Text .. "   ·   R 빔사벨   ·   V 주먹"
	hint.Text = hint.Text .. "   ·   1 / 2 무장 교체   ·   E 재장전   ·   G 미사일(한 번)"
	hint.Text = hint.Text .. "   ·   [ / ] 모니터 테 크기   ·   H 테 끄기"
	hint.Parent = g
	g.Parent = player:WaitForChild("PlayerGui")
	-- (미사일 록온 마름모는 10-25 13:15 조준 사격으로 바꾸며 없앰 — 미사일도 라이플 조준점 하나로 쏜다)
	return { gui = g, setHP = setHP, hpText = hpText, setEN = setEN, setULT = setULT, wl = wl, ch = { chU, chD, chL, chR } }
end

return { make = makeHUD }
