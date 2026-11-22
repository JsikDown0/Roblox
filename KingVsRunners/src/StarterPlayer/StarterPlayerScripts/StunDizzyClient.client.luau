-- StunDizzyClient
-- 만화풍 "헤롱헤롱" 스턴 이펙트: 스턴 동안 머리 위에 별들이 타원형 링으로 회전.
--
-- 이유: 애니메이션을 각 클라에서 로컬로 돌려야 전원에게 부드럽게 보임
--       (RevivalFlagEmitClient 와 동일한 브로드캐스트 패턴).
-- 흐름:
--   서버 → StunDizzyEffect:FireAllClients(victimChar, duration)
--   클라 → victim 머리 위 BillboardGui 생성 후 RenderStepped로 별 회전, duration 후 제거

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local event = ReplicatedStorage:WaitForChild("StunDizzyEffect")

-- ── 튜닝 ────────────────────────────────────────────────
local STAR_COUNT  = 5
local SPIN_SPEED  = 2.6                       -- 회전 속도(rad/s)
local CENTER      = Vector2.new(0.5, 0.42)    -- 링 중심(빌보드 내 스케일)
local RADIUS_X    = 0.40                       -- 타원 가로 반경
local RADIUS_Y    = 0.14                       -- 타원 세로 반경(납작 = 머리 두른 느낌)
local STAR_COLOR  = Color3.fromRGB(255, 214, 51)
local STROKE_COL  = Color3.fromRGB(120, 70, 0)
local BILLBOARD_STUDS = 4                       -- 빌보드 크기(stud)
local HEAD_OFFSET = 2.2                          -- 머리 위 높이(stud)

-- 캐릭터별 활성 이펙트: char -> { gui, conn, stopAt }
local active = {}

local function getHead(char)
    return char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChildWhichIsA("BasePart")
end

local function stop(char)
    local a = active[char]
    if not a then return end
    active[char] = nil
    if a.conn then a.conn:Disconnect() end
    if a.gui then a.gui:Destroy() end
end

local function start(char, duration)
    local head = getHead(char)
    if not head then return end

    -- 이미 떠 있으면 시간만 연장하고 재사용
    if active[char] then
        active[char].stopAt = math.max(active[char].stopAt, os.clock() + duration)
        return
    end

    local gui = Instance.new("BillboardGui")
    gui.Name = "DizzyStars"
    gui.Adornee = head
    gui.Size = UDim2.fromScale(BILLBOARD_STUDS, BILLBOARD_STUDS)
    gui.StudsOffsetWorldSpace = Vector3.new(0, HEAD_OFFSET, 0)
    gui.AlwaysOnTop = true
    gui.LightInfluence = 0
    gui.ResetOnSpawn = false
    gui.Parent = head

    local stars = {}
    for i = 1, STAR_COUNT do
        local lbl = Instance.new("TextLabel")
        lbl.Name = "Star" .. i
        lbl.BackgroundTransparency = 1
        lbl.AnchorPoint = Vector2.new(0.5, 0.5)
        lbl.Size = UDim2.fromScale(0.30, 0.30)
        lbl.Font = Enum.Font.FredokaOne
        lbl.Text = "★"
        lbl.TextColor3 = STAR_COLOR
        lbl.TextScaled = true
        lbl.Parent = gui

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Color = STROKE_COL
        stroke.Parent = lbl

        stars[i] = { lbl = lbl, stroke = stroke }
    end

    local a = { gui = gui, stopAt = os.clock() + duration }
    active[char] = a

    local t = 0
    a.conn = RunService.RenderStepped:Connect(function(dt)
        if os.clock() >= a.stopAt or not head.Parent or not gui.Parent then
            stop(char)
            return
        end
        t = t + dt
        local base = t * SPIN_SPEED
        for i, s in ipairs(stars) do
            local ang = base + (i - 1) * (2 * math.pi / STAR_COUNT)
            local sn = math.sin(ang)        -- +1 = 앞(아래), -1 = 뒤(위)
            local x = CENTER.X + RADIUS_X * math.cos(ang)
            local y = CENTER.Y + RADIUS_Y * sn
            s.lbl.Position = UDim2.fromScale(x, y)
            -- 깊이감: 앞쪽 별은 크고 선명, 뒤쪽 별은 작고 흐릿
            local depth = (sn + 1) / 2       -- 0(뒤)~1(앞)
            local scale = 0.22 + 0.16 * depth
            s.lbl.Size = UDim2.fromScale(scale, scale)
            local tr = 0.45 * (1 - depth)
            s.lbl.TextTransparency = tr
            s.stroke.Transparency = tr
            s.lbl.ZIndex = math.floor(depth * 10) + 1
        end
    end)
end

event.OnClientEvent:Connect(function(char, duration)
    if typeof(char) ~= "Instance" then return end
    duration = tonumber(duration) or 0.5
    start(char, duration)
end)

print("✅ StunDizzyClient 활성화 (머리 위 별 링)")
