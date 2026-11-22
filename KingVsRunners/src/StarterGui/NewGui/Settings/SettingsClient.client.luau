-- ════════════════════════════════════════════════════════════════
-- SettingsClient  (StarterGui/NewGui/Settings / LocalScript)
-- ────────────────────────────────────────────────────────────────
-- 설정 UI 바인딩. 현재 항목:
--   · Background Music (ON/OFF) → _G.MusicEnabled 연동
-- 토글은 On/Off 두 프레임의 Visible로 상태 표시 (스위치 형태).
-- ════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local player  = Players.LocalPlayer

local screenGui = script.Parent
local main      = screenGui:WaitForChild("Canvas"):WaitForChild("Main")
local list      = main:WaitForChild("List")

-- ── 토글 상태 적용 헬퍼 ──────────────────────────────────────────
-- toggle: On/Off 프레임을 가진 Frame
local function setToggleVisual(toggle, isOn)
    local on  = toggle:FindFirstChild("On")
    local off = toggle:FindFirstChild("Off")
    if on then on.Visible = isOn end
    if off then off.Visible = not isOn end
end

-- ── 토글에 클릭 감지 버튼 부착 ───────────────────────────────────
local function hookToggle(toggle, getState, setState)
    -- Frame이라 클릭 못 받음 → 투명 TextButton 오버레이
    local hit = toggle:FindFirstChild("_ClickHit")
    if not hit then
        hit = Instance.new("TextButton")
        hit.Name = "_ClickHit"
        hit.Size = UDim2.fromScale(1, 1)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.ZIndex = 20
        hit.Parent = toggle
    end
    hit.MouseButton1Click:Connect(function()
        local newState = not getState()
        setState(newState)
        setToggleVisual(toggle, newState)
    end)
end

-- ── Background Music 설정 ────────────────────────────────────────
-- _G.MusicEnabled를 단일 소스로 사용 (MusicClient가 이 값을 읽음)
local function musicEnabled()
    if _G.MusicEnabled == nil then return true end
    return _G.MusicEnabled
end
local function setMusicEnabled(v)
    _G.MusicEnabled = v
    -- 클라이언트 속성으로도 저장 (다른 스크립트 참조/추후 영구저장용)
    player:SetAttribute("Setting_MusicEnabled", v)
end

-- 초기값: 기본 ON (이미 켜져 있으면 유지)
if _G.MusicEnabled == nil then _G.MusicEnabled = true end

local bgmItem = list:WaitForChild("Setting_BackgroundMusic")
local bgmToggle = bgmItem:WaitForChild("Main"):WaitForChild("Toggle")

-- 시각 초기화 + 클릭 연결
setToggleVisual(bgmToggle, musicEnabled())
hookToggle(bgmToggle, musicEnabled, setMusicEnabled)

-- ── Visibility Markers 설정 ──────────────────────────────────────
-- _G.MarkersEnabled를 단일 소스로 사용 (마커 클라이언트들이 이 값을 읽음).
-- 게임플레이엔 영향 없는 순수 시각 옵션(가시성 선/초상화/아이템 선 표시 여부).
local function markersEnabled()
    if _G.MarkersEnabled == nil then return true end
    return _G.MarkersEnabled
end
local function setMarkersEnabled(v)
    _G.MarkersEnabled = v
    player:SetAttribute("Setting_MarkersEnabled", v)
end

-- 초기값: 기본 ON
if _G.MarkersEnabled == nil then _G.MarkersEnabled = true end

local markersItem = list:WaitForChild("Setting_Markers")
local markersToggle = markersItem:WaitForChild("Main"):WaitForChild("Toggle")
setToggleVisual(markersToggle, markersEnabled())
hookToggle(markersToggle, markersEnabled, setMarkersEnabled)

-- ── X(닫기) 버튼 ─────────────────────────────────────────────────
local closeButton = main:FindFirstChild("Close")
if closeButton then
    closeButton.MouseButton1Click:Connect(function()
        main.Visible = false
    end)
end

print("⚙️ SettingsClient 활성화 (Background Music 토글)")
