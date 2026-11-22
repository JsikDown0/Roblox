-- LightingDirector — 맵별 라이팅 무드 프리셋 (골드/블루 컬러 체계의 '빛' 구현)
-- lobby: 밝은 오후(중립·화사) / map1: 청명한 낮(블루 강조) / map2: 사막 골든아워(골드+블루 보색)
-- 사용: _G.SetLightingPreset("lobby"|"map1"|"map2") — RoundSystem이 맵 스왑/인터미션에서 호출.
-- 전환은 TweenService로 3초 페이드 (급변 없이 무드가 스며들게).

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

local PRESETS = {
	lobby = {
		-- 천사 테마 로비는 흰 표면(SmoothPlastic·구름·대리석) 비중이 커서
		-- 빛이 서로 반사돼 실제보다 훨씬 밝게 보인다 → 맵보다 낮게 잡아야 균형이 맞음.
		lighting = {
			ClockTime = 14.2,
			Brightness = 1.6,
			ExposureCompensation = -0.35,
			OutdoorAmbient = Color3.fromRGB(84, 96, 114),
			Ambient = Color3.fromRGB(58, 68, 82),
		},
		atmosphere = {
			Density = 0.18,
			Color = Color3.fromRGB(196, 210, 224),
			Decay = Color3.fromRGB(106, 112, 125),
			Haze = 0.4,
			Glare = 0.02,
		},
	},
	map1 = {
		-- 청명한 낮: 블루 강조 (러너의 색) — 쨍한 초원 전장
		lighting = {
			ClockTime = 12.6,
			Brightness = 3.1,
			OutdoorAmbient = Color3.fromRGB(118, 138, 168),
			Ambient = Color3.fromRGB(92, 106, 128),
		},
		atmosphere = {
			Density = 0.14,
			Color = Color3.fromRGB(199, 214, 235),
			Decay = Color3.fromRGB(100, 110, 130),
			Haze = 0.25,
			Glare = 0.08,
		},
	},
	map2 = {
		-- 사막 골든아워: 골드 광원 + 블루 하늘 보색 — 시그니처 무드
		lighting = {
			ClockTime = 16.4,
			Brightness = 2.7,
			OutdoorAmbient = Color3.fromRGB(158, 138, 108),
			Ambient = Color3.fromRGB(120, 104, 84),
		},
		atmosphere = {
			Density = 0.26,
			Color = Color3.fromRGB(226, 196, 152),
			Decay = Color3.fromRGB(150, 108, 70),
			Haze = 1.1,
			Glare = 0.28,
		},
	},
}

local TWEEN = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local currentPreset = nil

local function apply(name)
	local p = PRESETS[name]
	if not p then
		warn("[LightingDirector] 알 수 없는 프리셋:", name)
		return
	end
	if currentPreset == name then return end
	currentPreset = name
	TweenService:Create(Lighting, TWEEN, p.lighting):Play()
	if atmosphere then
		TweenService:Create(atmosphere, TWEEN, p.atmosphere):Play()
	end
	print("💡 [Lighting] 프리셋 →", name)
end

_G.SetLightingPreset = apply

-- 부팅 시 로비 무드
task.wait(1)
apply("lobby")
