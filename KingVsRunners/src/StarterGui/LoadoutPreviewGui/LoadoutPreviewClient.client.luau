-- Loadout Preview (독립 화면) — 인벤 열릴 때 표시. 장착 세트를 Item/Weapon/EFFECT 그룹으로.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = script.Parent  -- LoadoutPreviewGui (ScreenGui)
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets end)
gui.DisplayOrder = 12   -- 인벤(UnifiedInven DO=10) 위로 (프리셋 버튼 안 가리게)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling   -- ZIndex 0 절차적 아이콘이 슬롯 배경에 안 가리게

-- ── 크기 상수(튜닝 지점) ──────────────────────────────────────
local SLOT_SIZE = 52
local SLOT_PAD  = 6
local SECTION_H = 32 + SLOT_SIZE + 8 + 12 + SLOT_SIZE + 8   -- 진영 섹션 높이(2단)
local LABEL_C   = Color3.fromRGB(150, 160, 180)   -- 그룹 라벨
local EFFECT_C  = Color3.fromRGB(105, 112, 128)   -- EFFECT 라벨(회색톤 = 성능 아님)

-- ── 셸 ───────────────────────────────────────────────────────
local BASE_W = 320
local BASE_H = 42 + SECTION_H + 8 + SECTION_H + 12

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0, 0.5)
root.Position = UDim2.new(0, 20, 0.5, 0)
root.Size = UDim2.fromOffset(BASE_W, BASE_H)
root.BackgroundColor3 = Color3.fromRGB(20, 23, 34)
root.BackgroundTransparency = 0.08
root.BorderSizePixel = 0
root.Parent = gui
Instance.new("UICorner", root).CornerRadius = UDim.new(0, 14)
local stroke = Instance.new("UIStroke", root)
stroke.Color = Color3.fromRGB(60, 70, 95)
stroke.Thickness = 1.5

-- 모바일 스케일
local camera = workspace.CurrentCamera
local uiScale = Instance.new("UIScale", root)
local function applyScale()
    uiScale.Scale = math.clamp(camera.ViewportSize.Y / 720, 0.6, 1)
end
applyScale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)

-- 타이틀
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 28)
title.Position = UDim2.new(0, 12, 0, 8)
title.BackgroundTransparency = 1
title.Text = "LOADOUT"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextScaled = true
title.Parent = root
Instance.new("UITextSizeConstraint", title).MaxTextSize = 22

-- ── 그룹 컨테이너 빌더 ────────────────────────────────────────
local function groupGrid(parent, x, y, cols)
    local w = cols * SLOT_SIZE + (cols - 1) * SLOT_PAD
    local c = Instance.new("Frame")
    c.Size = UDim2.fromOffset(w, SLOT_SIZE)
    c.Position = UDim2.fromOffset(x, y)
    c.BackgroundTransparency = 1
    c.Parent = parent
    local g = Instance.new("UIGridLayout")
    g.CellSize = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE)
    g.CellPadding = UDim2.fromOffset(SLOT_PAD, SLOT_PAD)
    g.SortOrder = Enum.SortOrder.LayoutOrder
    g.Parent = c
    return c
end

local function grpLabel(parent, text, x, y, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromOffset(120, 11)
    l.Position = UDim2.fromOffset(x, y)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color
    l.Font = Enum.Font.GothamBold
    l.TextSize = 10
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
end

-- 진영 섹션: ITEM(4) 윗단 / WEAPON(1) │ EFFECT(3) 아랫단. 3 컨테이너 반환.
local function makeFactionSection(name, factionLabel, yPos, accent)
    local sec = Instance.new("Frame")
    sec.Name = name
    sec.Size = UDim2.new(1, -24, 0, SECTION_H)
    sec.Position = UDim2.new(0, 12, 0, yPos)
    sec.BackgroundColor3 = Color3.fromRGB(16, 19, 28)
    sec.BorderSizePixel = 0
    sec.Parent = root
    Instance.new("UICorner", sec).CornerRadius = UDim.new(0, 8)
    local s = Instance.new("UIStroke", sec); s.Color = accent; s.Thickness = 1.5

    local fl = Instance.new("TextLabel")
    fl.Size = UDim2.new(1, -20, 0, 13); fl.Position = UDim2.new(0, 10, 0, 5)
    fl.BackgroundTransparency = 1; fl.Text = factionLabel
    fl.TextColor3 = Color3.fromRGB(165, 175, 195); fl.Font = Enum.Font.GothamBold
    fl.TextSize = 12; fl.TextXAlignment = Enum.TextXAlignment.Left; fl.Parent = sec

    -- 윗단: ITEM
    grpLabel(sec, "ITEM", 10, 20, LABEL_C)
    local items = groupGrid(sec, 8, 32, 4)

    -- 아랫단: WEAPON │ EFFECT
    local t2 = 32 + SLOT_SIZE + 8
    grpLabel(sec, "WEAPON", 10, t2, LABEL_C)
    local weapon = groupGrid(sec, 8, t2 + 12, 1)

    local divX = 8 + SLOT_SIZE + 9
    local div = Instance.new("Frame")
    div.Size = UDim2.fromOffset(1, SLOT_SIZE)
    div.Position = UDim2.fromOffset(divX, t2 + 12)
    div.BackgroundColor3 = Color3.fromRGB(52, 58, 74)
    div.BorderSizePixel = 0; div.Parent = sec

    grpLabel(sec, "EFFECT", divX + 8, t2, EFFECT_C)
    local effects = groupGrid(sec, divX + 8, t2 + 12, 3)

    return { items = items, weapon = weapon, effects = effects }
end
local taggerSec = makeFactionSection("TaggerSection", "KING SET", 42, Color3.fromRGB(210, 80, 80))
local runnerSec = makeFactionSection("RunnerSection", "RUNNER SET", 42 + SECTION_H + 8, Color3.fromRGB(70, 130, 210))

-- ── 데이터 ────────────────────────────────────────────────────
local getPlayerLoadout = ReplicatedStorage:WaitForChild("GetPlayerLoadout")
local getRunnerLd      = ReplicatedStorage:WaitForChild("GetRunnerLoadout")
local getEffectData    = ReplicatedStorage:WaitForChild("GetEffectData")

-- ⚠️ 인벤(UnifiedInvenClient.RARITY_BORDER)과 반드시 같은 색이어야 한다.
--    2026-08-23 실측: 여기 Rare 가 파랑(70,140,230)이었는데 인벤은 초록(80,200,90)이라
--    같은 아이템(bear_trap)이 두 화면에서 다른 등급처럼 보였다.
--    ⚠️ 한쪽만 고치면 다시 어긋난다. 등급 색을 바꿀 땐 양쪽을 같이.
local RARITY_COLOR = {
    Normal    = Color3.fromRGB(210, 210, 210),
    Rare      = Color3.fromRGB(80, 200, 90),
    Epic      = Color3.fromRGB(170, 95, 240),
    Legendary = Color3.fromRGB(255, 180, 30),
}

-- 🏅 [버그수정 2026-09-05] 러너 무기 등급을 WeaponData 에서 읽는다.
--   [증상] LOADOUT 패널의 러너 WEAPON 슬롯이 무기와 무관하게 늘 보라색(Epic)이었다.
--     인벤 카드는 카타나를 Legendary(금색)로 표시하는데 여기만 달랐다.
--   [원인] 아래 renderSlots 호출이 rarity = "Epic" 을 하드코딩하고 있었다.
--     색 테이블(RARITY_COLOR)은 인벤과 맞춰뒀지만 넘기는 '값'이 가짜였다.
--     ⚠️ 141행 주석이 "한쪽만 고치면 어긋난다"고 경고한 것과 같은 종류의 실패다 —
--       그때는 색을 맞췄고, 이번엔 등급값 자체가 어긋나 있었다.
--   [해결] ReplicatedStorage.WeaponData 가 유일한 출처다(인벤도 이걸 쓴다).
--     여기서 파생시키면 무기가 추가돼도 자동으로 맞는다.
--   ⚠️ WeaponData 는 배열이라 id 로 선형 탐색한다. 8개뿐이라 캐시 없이도 충분하다.
--   ⚠️ require 실패해도 UI 가 죽으면 안 된다 → pcall + Normal 폴백.
local WEAPON_RARITY = {}
do
    local ok, wd = pcall(require, ReplicatedStorage:WaitForChild("WeaponData", 5))
    if ok and type(wd) == "table" then
        for _, e in ipairs(wd) do
            if type(e) == "table" and e.id then WEAPON_RARITY[e.id] = e.rarity end
        end
    else
        warn("[LoadoutPreview] WeaponData 로드 실패 — 무기 등급이 전부 Normal 로 보인다")
    end
end

local PERM_MAP = {   -- 서버 PERMANENT_SKU 미러. 소유 시 ∞    -- 🗑️ [2026-08-29] ODM/Ice Bow 영구 SKU 제거로 비었다.
    --   ⚠️ 서버(LoadoutManager.PERMANENT_SKU)와 한 짝이다. 한쪽만 채우면
    --     "인벤엔 ∞ 인데 라운드에선 차감" 같은 불일치가 생긴다.
}

local function equippedOf(list)
    for _, e in ipairs(list or {}) do
        if e.equipped then return e end
    end
    return nil
end

local function effectDesc(e)
    if not e then return { filled = false } end
    -- 🖼️ [2026-08-27] imgScale/imgOffX/imgOffY 를 함께 담는다.
    --   [증상] 킬이펙트 배지 크기가 제각각이었다(Rainbow 너무 큼 / Sword Rain 너무 작음).
    --   [원인] 서버(EffectSystem:279~283)는 이 값들을 보내주는데 여기서 버리고 있었다.
    --     그래서 로드아웃만 고정 1.5 + 예외 하드코딩으로 버텨왔고, 배지가 늘 때마다 어긋났다.
    --   ⚠️ 인벤·상점은 같은 값을 이미 쓴다(UnifiedInvenClient _sc / ShopClient item.imgScale).
    --     세 UI 가 같은 소스를 보게 되므로, 이제 BadgeTuner(B키)로 한 번 맞추면 전부 맞는다.
    return { filled = true, id = e.id, imageId = tostring(e.imageId or ""), icon = tostring(e.icon or ""),
             name = e.name or "?", rarity = e.rarity or "Normal",
             imgScale = e.imgScale, imgOffX = e.imgOffX, imgOffY = e.imgOffY }
end

-- 로드아웃 아이템(최대 4) → 디스크립터 4개(빈 슬롯 포함). 이미지는 icon 필드.
local function itemDescs(data)
    local out = {}
    if data then
        local meta = {}
        for _, it in ipairs(data.allItems or {}) do meta[it.name] = it end
        local i = 0
        for _, nm in ipairs(data.loadout or {}) do
            i += 1
            if i > 4 then break end
            local it = meta[nm]
            if it then
                -- 태거 아이템(배럴 등)은 TaggerItemPreviews, 러너는 RunnerItemPreviews
                local _tp = ReplicatedStorage:FindFirstChild("TaggerItemPreviews")
                local _vpf = (_tp and _tp:FindFirstChild(it.name)) and "TaggerItemPreviews" or "RunnerItemPreviews"
                local d = { filled = true, imageId = tostring(it.icon or ""), name = it.displayName or it.name, rarity = it.rarity or "Normal", vpFolder = _vpf, vpKey = it.name }
                if it.consumable then
                    local permId = PERM_MAP[it.name]
                    if permId and player:GetAttribute("OwnedItem_" .. permId) then
                        d.badge = "∞"
                    else
                        local n = tonumber((data.consumables or {})[it.name]) or 0
                        d.badge = "x" .. n
                        d.dim = (n <= 0)
                    end
                end
                out[i] = d
            else
                out[i] = { filled = false }
            end
        end
    end
    for j = 1, 4 do out[j] = out[j] or { filled = false } end
    return out
end

-- ── 3D 뷰포트 아이콘 (ShopClient buildThumbnail 재활용) ─────────
local function makeViewport(parent, folderName, key)
    if not folderName or not key or key == "" then return false end
    local pf = ReplicatedStorage:FindFirstChild(folderName)
    local src = pf and pf:FindFirstChild(key)
    if not src then return false end
    local vp = Instance.new("ViewportFrame")
    vp.Name = "_ItemVP"                     -- PreviewTuner(P키)가 잡는 이름
    vp:SetAttribute("PreviewId", key)
    vp.Size = UDim2.new(1, -6, 1, -6)
    vp.Position = UDim2.new(0, 3, 0, 3)
    vp.BackgroundTransparency = 1
    vp.LightColor = Color3.fromRGB(255, 240, 220)
    vp.LightDirection = Vector3.new(-1, -2, -1)
    vp.Ambient = src:GetAttribute("Ambient") or Color3.fromRGB(140, 140, 150)
    vp.Parent = parent
    local m = src:Clone()
    -- 프리뷰 모델을 뷰포트 원점으로 이동 (배럴 등이 월드 y=50에 있어 카메라 프레이밍 어긋나는 것 방지)
    if m:IsA("Model") then
        if not m.PrimaryPart then
            m.PrimaryPart = m:FindFirstChildWhichIsA("BasePart", true)
        end
        local pivot = m:GetPivot()
        m:PivotTo(pivot - pivot.Position)  -- 위치만 원점으로, 회전은 유지 (크라운/푸시툴 각도 보존)
    elseif m:IsA("BasePart") then
        m.CFrame = m.CFrame - m.CFrame.Position  -- 위치만 원점, 회전 유지
    end
    for _, p in ipairs(m:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = true; p.CastShadow = false end
    end
    m.Parent = vp
    local cam = Instance.new("Camera")
    cam.FieldOfView = 50
    vp.CurrentCamera = cam
    cam.Parent = vp
    local cf, sz
    if m:IsA("Model") then
        cf, sz = m:GetBoundingBox()
    else
        cf, sz = m.CFrame, m.Size   -- single MeshPart/BasePart: bbox = CFrame + Size
    end
    local md = math.max(sz.X, sz.Y, sz.Z, 0.1)
    -- PreviewTuner 공식과 동일: target = center + pan*maxDim (월드), dist = maxDim*distMul
    local distMul = src:GetAttribute("DistMul") or 1.4
    local dv      = src:GetAttribute("CameraDirection") or Vector3.new(0.7, 0.5, 0.7)
    local pan     = src:GetAttribute("CameraOffset") or Vector3.new(0, 0, 0)
    local tgt = cf.Position + pan * md
    cam.CFrame = CFrame.new(tgt + dv * (md * distMul), tgt)
    -- PreviewTuner 초기값 (현재 프레이밍부터 시작)
    vp:SetAttribute("_tuneDist", distMul)
    vp:SetAttribute("_tuneDir", dv)
    vp:SetAttribute("_tuneTarget", pan)
    return true
end
_G.LP_makeViewport = makeViewport   -- 상점 코스메틱 3D 썸네일 재활용용

local function makeSlot(desc)
    local slot = Instance.new("Frame")   -- 크기는 UIGridLayout이 지정
    slot.BackgroundColor3 = desc.filled and Color3.fromRGB(28, 32, 44) or Color3.fromRGB(19, 21, 29)
    slot.BorderSizePixel = 0
    Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 7)
    local st = Instance.new("UIStroke", slot)
    st.Color = desc.filled and (RARITY_COLOR[desc.rarity] or RARITY_COLOR.Normal) or Color3.fromRGB(45, 50, 64)
    st.Thickness = 1.5
    if desc.filled then
        if desc.imageId ~= "" then
            local img = Instance.new("ImageLabel")
            if desc.bigIcon then
                -- 🌈 [2026-08-27] 고정 1.5 + 예외 하드코딩 → 서버가 보내준 값(desc.imgScale) 읽기.
                --   [증상] Rainbow Kill 이 로드아웃에서 비정상적으로 컸다.
                --     실측: imgScale 이 0.9 인데 여기서 1.5 를 강제해 1.67배 확대됐다.
                --   [왜 예외를 더 넣지 않았나] 이미 Sword Rain(4.11)이 예외로 박혀 있었고
                --     Rainbow 가 두 번째다. 실제 값은 0.9~4.11 로 4.5배 범위라
                --     고정값 하나에 예외를 붙이는 방식은 배지가 늘 때마다 재발한다.
                --   [해결] 인벤·상점과 같은 소스를 읽는다. 서버가 EffectSystem 에서
                --     imgScale·imgOffX·imgOffY 를 단일 정의하고, GetEffectData 응답에
                --     그대로 실려 온다(ShopSystem 396행이 같은 값을 상점에 실어주는 것과 같은 경로).
                --   ⚠️ _G.KILL_EFFECTS 로 폴백하지 않는다 — 그건 서버 전역이라
                --     LocalScript 에서는 언제나 nil 이다(죽은 코드가 된다).
                --   ⚠️ 1.5 폴백은 남긴다. 값이 없는 배지를 0 으로 만들면 아예 안 보인다.
                local sc = tonumber(desc.imgScale) or 1.5
                local ox = tonumber(desc.imgOffX) or 0
                local oy = tonumber(desc.imgOffY) or 0
                img.AnchorPoint = Vector2.new(0.5, 0.5)
                img.Position = UDim2.new(0.5 + ox, 0, 0.5 + oy, 0)
                img.Size = UDim2.new(sc, 0, sc, 0)
            else
                img.Size = UDim2.new(1, -6, 1, -6)
                img.Position = UDim2.new(0, 3, 0, 3)
            end
            img.BackgroundTransparency = 1
            img.ScaleType = Enum.ScaleType.Fit
            img.Image = "rbxassetid://" .. (desc.imageId:gsub("rbxassetid://", ""))
            img.Parent = slot
        elseif makeViewport(slot, desc.vpFolder, desc.vpKey) then
            -- 3D 뷰포트
        elseif desc.procKind == "dash" and _G.LP_makeDashIcon and _G.LP_makeDashIcon(slot, desc.id) then
            -- 대시 절차적 썸네일
        elseif desc.procKind == "trail" and _G.LP_makeTrailRibbon and _G.LP_makeTrailRibbon(slot, desc.id) then
            -- 트레일 절차적 썸네일
        else
            local t = Instance.new("TextLabel")
            t.Size = UDim2.fromScale(1, 1)
            t.BackgroundTransparency = 1
            t.Font = Enum.Font.GothamBold
            t.TextScaled = true
            t.Parent = slot
            if desc.icon and desc.icon ~= "" then
                t.Text = desc.icon
                t.TextColor3 = Color3.fromRGB(255, 255, 255)
                Instance.new("UITextSizeConstraint", t).MaxTextSize = desc.bigIcon and 52 or 30
            else
                t.Text = (desc.name or "?"):sub(1, 3)
                t.TextColor3 = Color3.fromRGB(205, 214, 228)
                Instance.new("UITextSizeConstraint", t).MaxTextSize = 15
            end
        end

        if desc.dim then
            local ov = Instance.new("Frame")
            ov.Size = UDim2.fromScale(1, 1)
            ov.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            ov.BackgroundTransparency = 0.55
            ov.BorderSizePixel = 0
            ov.ZIndex = 5
            Instance.new("UICorner", ov).CornerRadius = UDim.new(0, 7)
            ov.Parent = slot
        end

        -- 🛒 상점 점프 버튼.
        -- ⚠️ 예전엔 이 블록이 `if desc.dim then` 안에 있어 x0 소모품에만 걸렸다.
        --    이제 shopHint 가 있는 모든 슬롯에 건다(빈 슬롯 포함 — 아래 filled 밖에서 처리).
        if desc.shopHint then
            local jump = Instance.new("TextButton")
            jump.Name = "ShopJump"
            jump.Size = UDim2.fromScale(1, 1)
            jump.BackgroundTransparency = 1
            jump.Text = ""
            jump.AutoButtonColor = false
            jump.ZIndex = 7
            jump.Parent = slot
            jump.MouseButton1Click:Connect(function()
                if not _G.OpenShopToItem then return end
                local h = desc.shopHint
                -- 인벤 위에 상점이 겹쳐 열린다(닫지 않음)
                _G.OpenShopToItem(desc.name, h.sub, h.tab)
            end)
        end
        if desc.badge then
            local b = Instance.new("TextLabel")
            b.Size = UDim2.new(0, 24, 0, 15)
            b.Position = UDim2.new(1, -25, 0, 1)
            b.BackgroundColor3 = desc.dim and Color3.fromRGB(190, 75, 60) or Color3.fromRGB(30, 34, 46)
            b.BackgroundTransparency = 0.1
            b.Text = desc.badge
            b.TextColor3 = Color3.fromRGB(240, 242, 248)
            b.Font = Enum.Font.GothamBold
            b.TextScaled = true
            b.ZIndex = 6
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
            Instance.new("UITextSizeConstraint", b).MaxTextSize = 11
            b.Parent = slot
        end
    end
    return slot
end

-- 🛒 [2026-08-27] 슬롯 클릭 → 상점의 해당 탭·칩으로 점프.
--   [왜] 예전엔 x0 소모품(desc.dim)에만 점프가 걸려 있었다. "이 자리에 뭘 넣지?" 는
--     모든 슬롯에서 생기는 질문인데, 답을 찾으려면 상점을 열고 탭을 직접 찾아가야 했다.
--   [형태] hint = { tab = 상점 카테고리, sub = 칩 키 }.
--     상점 카테고리 문자열은 "runner"/"tagger"/"skin" 그대로다(재배치 때 안 바꿨다).
--     "skin" = 공용 탭(Universal) — faction 없는 effect/emote/trail 이 여기 있다.
--   ⚠️ sub 키는 ShopClient.SUB_LABEL 의 키와 정확히 같아야 한다. 라벨(표시명)이 아니다.
--     라벨은 2026-08-27 에 KING ITEM→ITEM COLOR 식으로 바뀌었지만 키는 그대로다.
--   ⚠️ 이름이 안 맞아도 탭·칩 이동은 이미 끝난 상태다(OpenShopToItem 이 그 순서로 동작).
--     빈 슬롯도 name 이 nil 일 뿐 이동은 되므로, 그대로 "뭘 살지 둘러보기"가 된다.
local function renderSlots(container, list, hint)
    for _, c in ipairs(container:GetChildren()) do
        if not c:IsA("UIGridLayout") then c:Destroy() end
    end
    for i, desc in ipairs(list) do
        -- 개별 desc 에 이미 힌트가 있으면 그것을 우선(EFFECT 그룹은 슬롯마다 다르다)
        if hint and not desc.shopHint then desc.shopHint = hint end
        local s = makeSlot(desc)
        s.LayoutOrder = i
        s.Parent = container
    end
end

local function refreshSets()
    -- 🛒 슬롯 → 상점 탭·칩 대응표.
    --   sub 은 ShopClient.SUB_LABEL 의 '키' 다(표시 라벨 아님).
    --   ⚠️ King WEAPON(King Fist)은 무기 자체가 판매 대상이 아니다 — 기본 지급이고
    --      색만 판다. 그래서 ic_tagger_weapon(FIST COLOR) 칩으로 보낸다.
    --   ⚠️ tab 은 상점 카테고리 문자열이다. "skin" = 공용(Universal) 탭 —
    --      2026-08-27 재배치에서 라벨만 바꾸고 카테고리 키는 그대로 뒀다.
    local H_KING_ITEM   = { tab = "tagger", sub = "item" }
    local H_KING_FIST   = { tab = "tagger", sub = "ic_tagger_weapon" }
    local H_CROWN       = { tab = "tagger", sub = "crown" }
    local H_RUNNER_ITEM = { tab = "runner", sub = "item" }
    local H_RUNNER_WPN  = { tab = "runner", sub = "weapon" }
    local H_DASH        = { tab = "runner", sub = "dash" }
    local H_TRAIL       = { tab = "skin",   sub = "trail" }
    local H_KILL        = { tab = "skin",   sub = "effect" }

    -- 트레일은 역할 공용 코스메틱이라 태거·러너 양쪽 EFFECT 에 같은 슬롯을 노출한다.
    -- (플레이어 속성 TrailSkin 하나를 공유하므로 두 섹션이 항상 같은 값을 보여준다)
    local trailDesc = effectDesc(equippedOf(getEffectData:InvokeServer("trailSkin")))
    trailDesc.procKind = "trail"
    trailDesc.shopHint = H_TRAIL

    -- 태거: ITEM(4) / WEAPON(PushTool) / EFFECT(크라운·트레일·킬이펙트)
    renderSlots(taggerSec.items, itemDescs(getPlayerLoadout:InvokeServer()), H_KING_ITEM)
    renderSlots(taggerSec.weapon, {
        -- ⚠️ PushTool 은 WeaponData 에 없다(상점 카탈로그가 아니라 태거 기본 지급품).
        --   그래서 여기만 등급을 직접 적는다 — 아래 러너 무기와 달리 하드코딩이 정당하다.
        --   ⚠️ 언젠가 PushTool 이 WeaponData 에 편입되면 이 줄도 WEAPON_RARITY 로 바꿀 것.
        { filled = true, imageId = "", name = "Push Tool", rarity = "Rare", vpFolder = "RunnerItemPreviews", vpKey = "PushTool" },
    }, H_KING_FIST)
    local crown = equippedOf(getEffectData:InvokeServer("crownSkin"))
    local crownDesc = effectDesc(crown)
    crownDesc.shopHint = H_CROWN
    if crown and crown.skinKey then crownDesc.vpFolder = "CrownPreviews"; crownDesc.vpKey = crown.skinKey end
    local killDesc = effectDesc(equippedOf(getEffectData:InvokeServer("killEffect")))
    killDesc.bigIcon = true
    killDesc.shopHint = H_KILL
    renderSlots(taggerSec.effects, {
        crownDesc,
        trailDesc,
        killDesc,
    })

    -- 러너: ITEM(4) / WEAPON(EquippedWeapon) / EFFECT(대시·트레일·킬이펙트)
    renderSlots(runnerSec.items, itemDescs(getRunnerLd:InvokeServer()), H_RUNNER_ITEM)
    local eqW = player:GetAttribute("EquippedWeapon")
    renderSlots(runnerSec.weapon, {
        (eqW and eqW ~= "")
            and { filled = true, imageId = "", name = tostring(eqW), rarity = WEAPON_RARITY[tostring(eqW)] or "Normal", vpFolder = "RunnerItemPreviews", vpKey = tostring(eqW) }
            or { filled = false },
    }, H_RUNNER_WPN)
    local dashDesc = effectDesc(equippedOf(getEffectData:InvokeServer("dashSkin")))
    dashDesc.procKind = "dash"
    dashDesc.shopHint = H_DASH
    local killDescR = effectDesc(equippedOf(getEffectData:InvokeServer("killEffect")))
    killDescR.bigIcon = true
    killDescR.shopHint = H_KILL
    renderSlots(runnerSec.effects, {
        dashDesc,
        trailDesc,
        killDescR,
    })

    print("[LoadoutPreview] 세트 렌더 (Item/Weapon/EFFECT 그룹)")
end

-- ── 실시간 갱신 훅 ────────────────────────────────────────────
_G.LoadoutPreviewRefresh = function()
    if not gui.Enabled then return end
    task.spawn(function()
        task.wait(0.1)
        refreshSets()
    end)
end

-- ── 이모트 바 겹침 회피 ───────────────────────────────────────
-- ── 프리셋 번호 버튼 (우측) ───────────────────────────────────
local getPresetsFn   = ReplicatedStorage:WaitForChild("GetPresets", 10)
local switchPresetE  = ReplicatedStorage:WaitForChild("SwitchPreset", 10)
local presetChangedE = ReplicatedStorage:WaitForChild("PresetChanged", 10)

local PRESET_BTN = 34
local presetBar = Instance.new("Frame")
presetBar.Name = "PresetBar"
presetBar.AnchorPoint = Vector2.new(0, 0)
presetBar.Position = UDim2.new(1, 8, 0, 42)
presetBar.Size = UDim2.fromOffset(PRESET_BTN, 10)
presetBar.AutomaticSize = Enum.AutomaticSize.Y
presetBar.BackgroundTransparency = 1
presetBar.Parent = root
do
	local l = Instance.new("UIListLayout", presetBar)
	l.FillDirection = Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, 6)
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
end

local lastInfo   -- 마지막 GetPresets 결과 (낙관적 재렌더용)
local presetBtns = {}
local function renderPresetBar(info)
	for _, b in ipairs(presetBtns) do b:Destroy() end
	presetBtns = {}
	if type(info) ~= "table" or type(info.slots) ~= "table" then return end
	lastInfo = info
	for i, slot in ipairs(info.slots) do
		local isActive = (i == info.active)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.fromOffset(PRESET_BTN, PRESET_BTN)
		btn.LayoutOrder = i
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 16
		btn.AutoButtonColor = false
		if not slot.unlocked then
			btn.Text = "🔒"
			btn.TextColor3 = Color3.fromRGB(150, 155, 170)
			btn.BackgroundColor3 = Color3.fromRGB(24, 27, 38)
		else
			btn.Text = tostring(i)
			btn.TextColor3 = isActive and Color3.fromRGB(22, 24, 32) or Color3.fromRGB(210, 216, 228)
			btn.BackgroundColor3 = isActive and Color3.fromRGB(255, 210, 90) or Color3.fromRGB(30, 34, 46)
		end
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
		local st = Instance.new("UIStroke", btn)
		st.Color = isActive and Color3.fromRGB(255, 210, 90) or Color3.fromRGB(55, 62, 80)
		st.Thickness = 1.5
		btn.Parent = presetBar
		btn.MouseButton1Click:Connect(function()
			if not slot.unlocked then
				-- VIP 잠금 슬롯: 게임패스 구매 유도 (서버 VIP_PASS_ID와 일치)
				pcall(function()
					game:GetService("MarketplaceService"):PromptGamePassPurchase(player, 1906860989)
				end)
				return
			end
			if isActive then return end
			if switchPresetE then switchPresetE:FireServer(i) end
			if lastInfo then lastInfo.active = i; renderPresetBar(lastInfo) end
		end)
		presetBtns[i] = btn
	end
end

local function refreshPresetBar()
	if not getPresetsFn then return end
	task.spawn(function()
		local ok, info = pcall(function() return getPresetsFn:InvokeServer() end)
		if ok then renderPresetBar(info) end
	end)
end

if presetChangedE then
	presetChangedE.OnClientEvent:Connect(function()
		refreshPresetBar()
		if _G.LoadoutPreviewRefresh then _G.LoadoutPreviewRefresh() end
	end)
end

local EMOTE_NUDGE = 120
local emoteBar, emoteBaseY
local emoteNudged = false
task.spawn(function()
    local pg = player:WaitForChild("PlayerGui")
    local ebg = pg:WaitForChild("EmotionBarGui", 10)
    emoteBar = ebg and ebg:WaitForChild("EmoteBar", 10)
end)
local function nudgeEmote(down)
    -- 위치 결정은 EmotionBarClient가 단독 소유(모바일: 플레이=태거리스트 아래 / 인벤=좌측 컬럼).
    -- 여기서 Position을 같이 건드리면 두 스크립트가 같은 속성을 다투므로 신호만 전달.
    if _G.EmoteLoadoutBox then _G.EmoteLoadoutBox(down) end
    -- 인벤 열림 동안 Settings/관전 숨김 (인벤 X 버튼과 겹침)
    _G.HudInvenOpen = down and true or false
    if _G.syncHudRightBtns then _G.syncHudRightBtns() end
end

-- ── 표시/숨김: 인벤 열림 미러링 ──────────────────────────────
gui.Enabled = false
-- 인벤 Canvas 의 Visible 을 따라 로드아웃 패널을 열고 닫는다.
-- ⚠️ Canvas 가 파괴되면(예: ResetOnSpawn 으로 인벤이 재생성) 이 연결이 죽은 인스턴스를
--    가리키게 되어, 인벤은 사라졌는데 로드아웃만 화면에 남는 분리 버그가 생긴다.
--    (2026-08 실측: 인벤을 켠 채 사망 → 리스폰 시 재현)
--    UnifiedInven.ResetOnSpawn=false 로 근본 차단했지만, 어떤 이유로든 참조가 끊겼을 때를
--    대비해 재연결 루프를 둔다.
local function bindToInvenCanvas()
    local playerGui = player:WaitForChild("PlayerGui")
    local newGui = playerGui:WaitForChild("NewGui", 10)
    local uni = newGui and newGui:WaitForChild("UnifiedInven", 10)
    local canvas = uni and uni:WaitForChild("Canvas", 10)
    if not canvas then
        warn("[LoadoutPreview] UnifiedInven.Canvas 못 찾음 — 표시 트리거 미연결")
        return nil
    end
    local function sync()
        gui.Enabled = canvas.Visible
        nudgeEmote(canvas.Visible)
        if canvas.Visible then task.spawn(refreshSets); refreshPresetBar() end
    end
    canvas:GetPropertyChangedSignal("Visible"):Connect(sync)
    sync()
    return canvas
end

task.spawn(function()
    local canvas = bindToInvenCanvas()
    -- Canvas 가 사라지면 패널을 즉시 닫고 새 Canvas 에 다시 연결
    while true do
        task.wait(1)
        if not (canvas and canvas.Parent) then
            if gui.Enabled then
                gui.Enabled = false
                warn("[LoadoutPreview] Canvas 소실 감지 — 패널 닫고 재연결 시도")
            end
            canvas = bindToInvenCanvas()
        end
    end
end)

print("✅ LoadoutPreviewClient 준비! (Item/Weapon/EFFECT 그룹)")
