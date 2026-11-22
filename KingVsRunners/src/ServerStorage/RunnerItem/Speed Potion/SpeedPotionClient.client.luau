-- Speed Potion Client Script
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local player   = Players.LocalPlayer
local tool     = script.Parent
local useEvent = ReplicatedStorage:WaitForChild("SpeedPotionUse")

local BOOST_DURATION = 5
local used           = false

-- ── 사운드 미리 생성 (Play 지연 없애기) ────────────────────────
local sound = Instance.new("Sound")
sound.SoundId             = tool:GetAttribute("PotionSoundId") or "rbxassetid://92235360782852"
sound.Volume              = 1
sound.RollOffMaxDistance  = 40
sound.Parent              = tool.Handle

-- ── 오라 파티클 생성 함수 ───────────────────────────────────────
local function spawnAura(character)
    -- 파티클 붙일 위치들 (상·중·하 커버)
    local attachPoints = {
        {part = "HumanoidRootPart", offset = Vector3.new(0,  1.2, 0)},
        {part = "HumanoidRootPart", offset = Vector3.new(0, -1.0, 0)},
        {part = "HumanoidRootPart", offset = Vector3.new(0,  0.0, 0)},
    }

    local attachments = {}

    -- skin-driven fx color: tool attribute PotionFxColor (Color3). nil = default cyan.
    local FX = script.Parent:GetAttribute("PotionFxColor")
    local windSeq, sparkleSeq
    if typeof(FX) == "Color3" then
        local function lighten(c, f) return c:Lerp(Color3.new(1, 1, 1), f) end
        windSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,   lighten(FX, 0.15)),
            ColorSequenceKeypoint.new(0.3, lighten(FX, 0.35)),
            ColorSequenceKeypoint.new(0.7, FX),
            ColorSequenceKeypoint.new(1,   lighten(FX, 0.25)),
        })
        sparkleSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0, lighten(FX, 0.5)),
            ColorSequenceKeypoint.new(1, FX),
        })
    else
        windSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0,   Color3.fromRGB(0,   255, 230)),
            ColorSequenceKeypoint.new(0.3, Color3.fromRGB(100, 255, 245)),
            ColorSequenceKeypoint.new(0.7, Color3.fromRGB(0,   200, 220)),
            ColorSequenceKeypoint.new(1,   Color3.fromRGB(50,  240, 255)),
        })
        sparkleSeq = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 255, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(0,   200, 220)),
        })
    end

    for _, info in ipairs(attachPoints) do
        local basePart = character:FindFirstChild(info.part)
        if not basePart then continue end

        local att = Instance.new("Attachment")
        att.Position = info.offset
        att.Parent   = basePart
        table.insert(attachments, att)

        -- 메인 바람 파티클
        local wind = Instance.new("ParticleEmitter")
        wind.Color = windSeq
        wind.LightEmission  = 0.85
        wind.LightInfluence = 0.15
        wind.Transparency   = NumberSequence.new({
            NumberSequenceKeypoint.new(0,   0.0),
            NumberSequenceKeypoint.new(0.4, 0.3),
            NumberSequenceKeypoint.new(0.85,0.75),
            NumberSequenceKeypoint.new(1,   1.0),
        })
        wind.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0,   0.5),
            NumberSequenceKeypoint.new(0.3, 1.2),
            NumberSequenceKeypoint.new(0.7, 0.9),
            NumberSequenceKeypoint.new(1,   0.0),
        })
        wind.Speed        = NumberRange.new(6, 14)
        wind.Rate         = 90
        wind.Lifetime     = NumberRange.new(0.7, 1.6)
        wind.Rotation     = NumberRange.new(0, 360)
        wind.RotSpeed     = NumberRange.new(-200, 200)
        wind.SpreadAngle  = Vector2.new(80, 80)
        wind.Parent       = att

        -- 커피 원두 파티클 (컵 스킨일 때만: BeanFxId 속성)
        local beanId = script.Parent:GetAttribute("BeanFxId")
        if beanId then
            local bean = Instance.new("ParticleEmitter")
            bean.Texture = beanId
            bean.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
            bean.LightEmission = 0
            bean.LightInfluence = 1
            bean.Size = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.35),
                NumberSequenceKeypoint.new(1, 0.28),
            })
            bean.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.75, 0),
                NumberSequenceKeypoint.new(1, 1),
            })
            bean.Rotation = NumberRange.new(-180, 180)
            bean.RotSpeed = NumberRange.new(-120, 120)
            bean.Speed = NumberRange.new(6, 10)
            bean.SpreadAngle = Vector2.new(60, 60)
            bean.Lifetime = NumberRange.new(0.6, 0.9)
            bean.Acceleration = Vector3.new(0, -14, 0)  -- 중력으로 흩뿌려 떨어짐
            bean.Rate = 14  -- 드문드문 튀는 느낌 (wind는 90)
            bean.Parent = att
        end

        -- 반짝이는 작은 파티클 (별빛 느낌)
        local sparkle = Instance.new("ParticleEmitter")
        sparkle.Color = sparkleSeq
        sparkle.LightEmission  = 1.0
        sparkle.LightInfluence = 0.0
        sparkle.Transparency   = NumberSequence.new({
            NumberSequenceKeypoint.new(0,   0.0),
            NumberSequenceKeypoint.new(0.6, 0.4),
            NumberSequenceKeypoint.new(1,   1.0),
        })
        sparkle.Size = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.15),
            NumberSequenceKeypoint.new(0.5, 0.3),
            NumberSequenceKeypoint.new(1, 0.0),
        })
        sparkle.Speed       = NumberRange.new(2, 8)
        sparkle.Rate        = 35
        sparkle.Lifetime    = NumberRange.new(0.4, 1.0)
        sparkle.SpreadAngle = Vector2.new(180, 180)
        sparkle.Parent      = att
    end

    -- 지속시간 후 파티클 비활성화 → 잔상 사라지면 제거
    task.delay(BOOST_DURATION, function()
        for _, att in ipairs(attachments) do
            if att and att.Parent then
                for _, emitter in ipairs(att:GetChildren()) do
                    if emitter:IsA("ParticleEmitter") then
                        emitter.Enabled = false
                    end
                end
            end
        end
        task.delay(1.8, function()
            for _, att in ipairs(attachments) do
                if att and att.Parent then att:Destroy() end
            end
        end)
    end)
end

-- ── 액체 페이드아웃 ─────────────────────────────────────────────
local function fadeLiquid()
    local liquid = tool:FindFirstChild("liquid")
    if not liquid then return end
    task.spawn(function()
        while liquid and liquid.Parent and liquid.Transparency < 1 do
            liquid.Transparency += 0.06
            task.wait(0.07)
        end
    end)
end

-- ── Activated ──────────────────────────────────────────────────
tool.Activated:Connect(function()
    if used then return end
    used = true

    -- 사운드 즉시 재생 (미리 생성됐으므로 딜레이 없음)
    sound.SoundId = tool:GetAttribute("PotionSoundId") or sound.SoundId  -- skin-driven; attr may replicate after init
    sound:Play()

    -- 서버에 속도 부스트 요청 + 툴 제거 요청
    useEvent:FireServer()

    -- 오라 이펙트
    local character = player.Character
    if character then
        spawnAura(character)
    end

    -- 액체 페이드
    fadeLiquid()

    -- 부스트 지속시간 후 Tool 제거 (클라이언트 선처리)
    task.delay(BOOST_DURATION + 0.1, function()
        if tool and tool.Parent then
            tool:Destroy()
        end
    end)
end)
