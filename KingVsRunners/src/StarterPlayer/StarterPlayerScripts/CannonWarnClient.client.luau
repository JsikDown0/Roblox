-- 🔔 곡사포 착탄 예고 (전원에게 보임)
--
-- ⚠️ 이게 이 무기의 존재 근거다. 아이템 소환 확장이 기각된 이유가
--    "예고 없이 머리 위에 생겨서 죽는다"였으므로, 러너가 반드시 미리 봐야 한다.
-- ⚠️ 태거의 조준원(CannonClient)은 태거만 본다. 이건 별개로 전원에게 간다.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local warnEvent = ReplicatedStorage:WaitForChild("CannonWarn")

warnEvent.OnClientEvent:Connect(function(pos, flightTime, radius, blinkAt)
    if typeof(pos) ~= "Vector3" then return end
    flightTime = flightTime or 1.1
    radius = radius or 14
    blinkAt = blinkAt or 0.45

    -- 바닥 원
    local ring = Instance.new("Part")
    ring.Name = "_CannonWarn"
    ring.Shape = Enum.PartType.Cylinder
    ring.Size = Vector3.new(0.4, radius * 2, radius * 2)
    ring.Anchored = true
    ring.CanCollide = false
    ring.CanQuery = false
    ring.CanTouch = false
    ring.CastShadow = false
    ring.Material = Enum.Material.Neon
    ring.Color = Color3.fromRGB(255, 160, 50)
    ring.Transparency = 0.55
    -- ⚠️ Cylinder 는 X 축이 두께다. 바닥에 눕히려면 Z 로 90도 돌린다.
    ring.CFrame = CFrame.new(pos.X, pos.Y + 0.3, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
    ring.Parent = workspace

    local t0 = os.clock()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if not ring.Parent then conn:Disconnect() return end
        local el = os.clock() - t0
        local left = flightTime - el

        if left <= blinkAt then
            -- 착탄 임박: 붉게 빠르게 점멸
            ring.Color = Color3.fromRGB(255, 45, 30)
            ring.Transparency = 0.2 + math.abs(math.sin(el * 26)) * 0.35
        else
            -- 접근 중: 서서히 진해진다
            local p = math.clamp(el / math.max(flightTime - blinkAt, 0.01), 0, 1)
            ring.Color = Color3.fromRGB(255, 160, 50):Lerp(Color3.fromRGB(255, 90, 40), p)
            ring.Transparency = 0.6 - p * 0.25
        end

        if el >= flightTime then
            conn:Disconnect()
            ring:Destroy()
        end
    end)

    Debris:AddItem(ring, flightTime + 0.5)
end)
