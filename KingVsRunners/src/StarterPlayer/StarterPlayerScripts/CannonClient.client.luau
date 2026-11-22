-- 🎯 곡사포 클라 — 착탄 예정 원 표시만 담당
--
-- ⚠️ [2026-08-24] 조작은 ProximityPrompt 가 전담한다.
--    · 로블록스 기본 UI 라 유저가 이미 안다 (픽업 상자와 같은 조작)
--    · HoldDuration 진행 게이지를 엔진이 그려준다
--    · 모바일 터치 버튼도 엔진이 만들어준다
--    → 이 스크립트는 키 입력을 처리하지 않는다. 서버가 보내는
--      "지금 이 좌표를 조준 중" 신호에 맞춰 바닥 원만 그린다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local stateEvent = ReplicatedStorage:WaitForChild("CannonState")

local aiming = false
local targetPos = nil
local aimStart = 0
local CHARGE_TIME = 2.0

local ring
local function showRing(pos)
    if not ring then
        ring = Instance.new("Part")
        ring.Name = "_CannonAim"
        ring.Shape = Enum.PartType.Cylinder
        -- ⚠️ 서버 BLAST_RADIUS(34) × 2. 표시와 실제가 어긋나면
        --    "원 밖인데 맞았다"가 되어 불신이 생긴다.
        ring.Size = Vector3.new(0.4, 68, 68)
        ring.Anchored = true
        ring.CanCollide = false
        ring.CanQuery = false
        ring.CanTouch = false
        ring.CastShadow = false
        ring.Material = Enum.Material.Neon
        ring.Color = Color3.fromRGB(255, 180, 60)
        ring.Transparency = 0.55
        ring.Parent = workspace
    end
    -- ⚠️ Cylinder 는 X 가 두께다. 바닥에 눕히려면 Z 로 90도.
    ring.CFrame = CFrame.new(pos.X, pos.Y + 0.3, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
end

local function hideRing()
    if ring then ring:Destroy() ; ring = nil end
end

RunService.RenderStepped:Connect(function()
    if not aiming or not targetPos then return end
    showRing(targetPos)
    if not ring then return end
    local p = math.clamp((os.clock() - aimStart) / CHARGE_TIME, 0, 1)
    if p >= 1 then
        ring.Color = Color3.fromRGB(255, 200, 70)
        ring.Transparency = 0.25 + math.sin(os.clock() * 8) * 0.12
    else
        ring.Color = Color3.fromRGB(255, 140, 60):Lerp(Color3.fromRGB(255, 200, 70), p)
        ring.Transparency = 0.72 - p * 0.32
    end
end)

stateEvent.OnClientEvent:Connect(function(kind, value, pos)
    if kind == "charging" then
        aiming = true
        aimStart = os.clock()
        targetPos = pos
        if value then CHARGE_TIME = value end
    elseif kind == "cancel" or kind == "fired" then
        aiming = false
        hideRing()
    elseif kind == "cooldown" then
        aiming = false
        hideRing()
    end
end)

player.CharacterAdded:Connect(function()
    aiming = false
    hideRing()
end)
