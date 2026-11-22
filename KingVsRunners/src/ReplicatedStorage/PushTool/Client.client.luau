-- PushTool Client
-- 입력 처리 + 애니메이션 + 쿨다운 인디케이터.
--   좌클릭/탭   = 푸시 (밀치기)        — 하단 중앙 쿨다운 바
--   그랩 버튼/E = 그랩 (끌어와 스턴)   — 우측 원형 버튼 + 쿨다운 오버레이
-- 데미지/넉백/스턴/끌기는 모두 서버에서 처리.

local Players          = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tool   = script.Parent
local Remote = Tool:WaitForChild("Remote")

local localPlayer = Players.LocalPlayer
local swingTrack  = nil
local grabTrack   = nil
local inputConn   = nil
local inputEndedConn = nil

-- ── 푸시 쿨다운 상태 ────────────────────────────────────
local cooldownEndTime = 0      -- 입력 잠금이 끝나는 os.clock() (스윙 락 + 실쿨다운 공용)
local cooldownTotal   = 1
local cooldownIsReal  = false  -- 명중 후 "진짜 쿨다운"일 때만 바 표시
local readyFlashUntil = 0
local blockedFlashUntil = 0    -- 쿨다운 중 푸시 시도 시 "아직 쿨다운" 경고 표시 종료 os.clock()
local cdConn          = nil

-- ── 그랩 쿨다운 상태 ────────────────────────────────────
-- ⚠️ [전방 선언 2026-09-11] updateGrabHud 는 아래 '장착/해제' 블록에서 정의하는데
--   startCooldownLoop 의 RenderStepped 루프가 그보다 앞에서 호출한다.
--   Lua 의 local function 은 정의 지점 이후에만 보이므로, 선언이 없으면
--   "attempt to call a nil value" 가 매 프레임 터진다(초당 60줄).
--   ⚠️ CaptureSystem 이 setCaptureFx 로 같은 사고를 냈고 그 주석이 남아 있다.
--     새 함수를 루프에 얹을 때는 정의 위치를 먼저 확인할 것.
local updateGrabHud
local grabCdEnd   = 0
-- 🖐️ [2026-09-11] 광역 그랩 전용 상태.
--   ⚠️ 위 grabCdEnd 는 이름과 달리 '차징(강타) 쿨' 표시에 재사용되고 있다.
--     그랩이 폐기된 뒤 남은 변수를 강타가 물려받은 것 — grabBtn·GRAB_START_SOUND 와 같은 형태다.
--     그랩이 부활하면서 한 변수를 두 스킬이 쓰면 표시가 서로를 덮으므로 전용 변수를 세운다.
--   ⚠️ 옛 이름을 바꾸지 않았다. 소비처가 여러 곳이라 개명은 별건으로 할 것.
local realGrabCdEnd  = 0   -- 광역 그랩 쿨 종료 시각
local realGrabCdTotal = 15 -- 쿨 총량(서버 GrabCooldown 이 갱신). 오버레이 비율 계산용
                           -- 🔻 [2026-09-21] 20 → 15. 서버 GRAB_COOLDOWN 과 같은 값을 유지한다.
                           --   첫 GrabCooldown 수신 전까지만 쓰이는 폴백이지만, 서버 값을 바꿀 때
                           --   여기를 잊으면 그 한 판의 오버레이 비율이 조용히 어긋난다.
local grabWindupEnd  = 0   -- 경고 종료 시각 (UI 표시용)
-- ⏱️ [2026-09-20] 이번 경고의 총 길이. 게이지 비율의 분모다.
--   [왜] 예전엔 updateGrabHud 가 1.5 를 하드코딩했다. 서버 GRAB_WINDUP 을 바꾸면
--     게이지만 옛 길이로 차서 UI 가 거짓말을 한다(그 줄 주석이 이미 경고하고 있었다).
--   → GrabBegin 이 서버 값으로 갱신한다. 폴백은 서버 현재값과 같은 1.0.
local grabWindupTotal = 1.0
local grabCdTotal = 1
local grabFreezeId = 0   -- 마지막 포즈 freeze 예약 가드

-- ── 그랩 홀드-조준 미리보기 (태거 본인만 보임, 클라 생성) ──
-- ※ 아래 3개는 서버 PushTool.Server 의 GRAB_MAX_RANGE / GRAB_HAND_HEIGHT / GRAB_HAND_START_FWD 와 일치시켜야 정확함
local GRAB_PREVIEW_RANGE  = 50
local GRAB_PREVIEW_HEIGHT = 1.2
local GRAB_PREVIEW_FWD    = 2
local GRAB_PREVIEW_MARK_RADIUS = 4   -- 끝점 마커 러너 감지 반경 (서버 GRAB_HAND_RADIUS와 맞춤)

-- ✋ 차징 상태(클라 표시용). 실제 판정은 서버가 한다.
-- ⚠️ updateCooldownUI 가 이 값을 읽으므로 그보다 먼저 선언해야 한다.
-- ⚠️ 버튼을 누른 시각. 이 직후의 InputBegan 은 '버튼 클릭'이므로
--    기본 슬랩(attemptPush)이 함께 나가면 안 된다.
--    실측: 버튼 클릭 시 슬랩이 먼저 나가 canSwing=false 가 되고,
--    차징이 시작만 되고 발동하지 못했다.
local btnPressedAt   = 0
local chargeTrack    = nil
local chargeFreezeConn = nil

-- ═══════════════════════════════════════════════════════════
-- ✨ 차징 이펙트
--
-- ⚠️ 템플릿은 ReplicatedStorage.PushChargeFx.Stage1~3 에 있다.
--    Folder 속성: HandColor / LightBrightness / LightRange / LightColor
--    자식: SparkAtt(Attachment) + Swirl(Part)
--
-- ⚠️ 원본 Handle 의 색·재질을 저장했다가 복원한다. 스킨을 쓰는
--    유저가 있으므로 그냥 흰색으로 되돌리면 스킨이 날아간다.
-- ═══════════════════════════════════════════════════════════
-- ⚠️ 로드 시점에 한 번만 조회하면 그때 없을 경우 영영 nil 이 된다.
local function getFxBank()
    return ReplicatedStorage:FindFirstChild("PushChargeFx")
end
local fxActive = nil          -- { swirl, sparkAtt, light, wristAtt }
local savedHandLook = nil     -- { color, material, texture }

local function clearChargeFx()
    if not fxActive then return end
    -- ⚠️ 파티클을 즉시 지우면 이미 떠 있는 입자까지 사라져 뚝 끊긴다.
    --    Enabled 를 끄고 잠시 뒤 제거해 자연스럽게 잦아들게 한다.
    for _, inst in ipairs({ fxActive.swirl, fxActive.sparkAtt }) do
        if inst and inst.Parent then
            for _, d in ipairs(inst:GetDescendants()) do
                if d:IsA("ParticleEmitter") then d.Enabled = false end
            end
        end
    end
    if fxActive.light and fxActive.light.Parent then fxActive.light.Enabled = false end

    local a = fxActive
    fxActive = nil
    task.delay(1.2, function()
        if a.swirl and a.swirl.Parent then a.swirl:Destroy() end
        if a.sparkAtt and a.sparkAtt.Parent then a.sparkAtt:Destroy() end
        if a.wristAtt and a.wristAtt.Parent then a.wristAtt:Destroy() end
    end)

    -- 손 원래 모습 복원
    local handle = Tool:FindFirstChild("Handle")
    if handle and savedHandLook then
        handle.Color = savedHandLook.color
        handle.Material = savedHandLook.material
        if handle:IsA("MeshPart") and savedHandLook.texture then
            handle.TextureID = savedHandLook.texture
        end
    end
    savedHandLook = nil
end

local function playChargeFx(stage)
    clearChargeFx()
    local FX_BANK = getFxBank()
    if not FX_BANK then
        warn("[ChargeFx] PushChargeFx 템플릿 없음")
        return
    end
    local tpl = FX_BANK:FindFirstChild("Stage" .. tostring(stage or 1))
    -- 🔇 [로그 정리 2026-08-26] 위 "[ChargeFx] 단계" 와 한 세트. 같이 되살릴 것.
    -- print("[ChargeFx] 템플릿 " .. tostring(tpl and tpl.Name or "없음"))
    if not tpl then return end
    local handle = Tool:FindFirstChild("Handle")
    if not handle then return end

    -- 원래 모습 저장
    savedHandLook = {
        color = handle.Color,
        material = handle.Material,
        texture = handle:IsA("MeshPart") and handle.TextureID or nil,
    }

    -- 🌟 손 발광
    -- ⚠️ 스킨을 쓰는 유저의 색이 사라지지 않게, 차징 중에만 덮고
    --    clearChargeFx 에서 원래 색·재질·텍스처를 되돌린다.
    --    (상시 표시(손목 오라)는 2026-08-25 제거됨 — 차징 중에만 색이 보인다)
    local hc = tpl:GetAttribute("HandColor")
    if hc then handle.Color = hc end
    handle.Material = Enum.Material.Neon
    if handle:IsA("MeshPart") then handle.TextureID = "" end

    -- 💡 손목 조명
    local wrist = Instance.new("Attachment")
    wrist.Name = "_ChargeWrist"
    local ratio = tpl:GetAttribute("WristOffsetRatio") or -0.32
    wrist.Position = Vector3.new(0, handle.Size.Y * ratio, 0)
    wrist.Parent = handle

    local light = Instance.new("PointLight")
    light.Color = tpl:GetAttribute("LightColor") or hc or Color3.new(1,1,1)
    light.Brightness = tpl:GetAttribute("LightBrightness") or 3
    light.Range = tpl:GetAttribute("LightRange") or 15
    light.Parent = wrist

    -- ✨ 스파크
    -- 💥 [2026-08-25] 시작 버스트 추가.
    --   [왜] Rate 만으로는 2초 차징이 밋밋해 "모으기 시작했다"가 안 읽혔다.
    --   Emit 으로 시작 순간에 한 번 터뜨려야 눈에 들어온다.
    --   단계가 오를수록 더 크게 터진다(Rate 차등과 같은 방향).
    local BURST_BASE = { Sparks = 45, MiniSparks = 40 }
    local burstMult = 1 + (math.clamp(stage or 1, 1, 3) - 1) * 0.5   -- 1 / 1.5 / 2
    local function burst(root)
        if not root then return end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("ParticleEmitter") then
                d.Enabled = true
                d:Emit(math.floor((BURST_BASE[d.Name] or 22) * burstMult))
            end
        end
    end

    local sa = tpl:FindFirstChild("SparkAtt")
    local sparkClone
    if sa then
        sparkClone = sa:Clone()
        sparkClone.Name = "_ChargeSpark"
        -- ⚠️ 템플릿 SparkAtt 의 Position 은 (0,0,0) = Handle 메시의 기하학적
        --   중심이다. Handle 이 4.14×5.49×1.54 라 중심은 주먹이 아니라
        --   메시 한가운데다 → 스파크가 손에서 안 나오는 것처럼 보였다.
        --   손목 조명(WristOffsetRatio)과 같은 방식으로 튜닝 손잡이를 둔다.
        sparkClone.Position = Vector3.new(0, handle.Size.Y * (tpl:GetAttribute("SparkOffsetRatio") or 0), 0)
        sparkClone.Parent = handle
        for _, d in ipairs(sparkClone:GetDescendants()) do
            if d:IsA("ParticleEmitter") then d.Enabled = true end
        end
        burst(sparkClone)
    end

    -- 🌀 회오리 — Handle 에 Attachment 로 직접 붙인다.
    -- ⚠️ [수정 2026-08-25] 중간 Part + WeldConstraint 방식 폐기.
    --   [문제] 템플릿 Swirl 은 0.001 짜리 투명 Part 고, 그 안의 crash2
    --   Attachment 가 실제 이펙트를 들고 있었다. 코드는 그 Part 를
    --   handle.CFrame 에 놓고 용접했는데, 물리 객체를 한 단계 거치므로
    --   부모가 되기 전 한 프레임 흔들리거나 미세하게 어긋났다
    --   (실측: "이펙트 위치가 안 맞는 느낌").
    --   [해결] crash2 는 이미 Attachment 다. Handle 에 직접 붙이면
    --   물리 없이 완벽히 따라간다. Part 도 용접도 필요 없다.
    local swirlClone
    local sw = tpl:FindFirstChild("Swirl")
    local crashAtt = sw and sw:FindFirstChildOfClass("Attachment")
    if crashAtt then
        swirlClone = crashAtt:Clone()
        swirlClone.Name = "_ChargeSwirl"
        -- 위치 튜닝: 템플릿 속성으로 조절한다(코드 수정 없이 스튜디오에서).
        swirlClone.Position = Vector3.new(0, handle.Size.Y * (tpl:GetAttribute("SwirlOffsetRatio") or 0), 0)
        swirlClone.Parent = handle
        for _, d in ipairs(swirlClone:GetDescendants()) do
            if d:IsA("ParticleEmitter") then d.Enabled = true end
        end
        burst(swirlClone)
    end

    fxActive = { swirl = swirlClone, sparkAtt = sparkClone,
                 light = light, wristAtt = wrist }
end
local attackTrack    = nil
local chargeStartAt  = 0
local chargeDuration = 2.0
local aiming      = false
local previewLine = nil
local previewEnd  = nil

-- 그랩 중 백팩 잠금(무기 스왑 차단) — 건틀릿 패턴. 안전망 ID로 영구 잠금 방지.
local grabBackpackLockId = 0
local function setBackpack(enabled)
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
    end)
end

-- ── 조준 미리보기 선/끝점 (클라 생성 → 본인만 보임) ──────
local function clearPreview()
    if previewLine then previewLine:Destroy(); previewLine = nil end
    if previewEnd  then previewEnd:Destroy();  previewEnd  = nil end
end

local function ensurePreview()
    if previewLine and previewLine.Parent and previewEnd and previewEnd.Parent then return end
    clearPreview()
    previewLine = Instance.new("Part")
    previewLine.Name = "_GrabAimLine"
    previewLine.Anchored = true
    previewLine.CanCollide = false
    previewLine.CanQuery = false
    previewLine.CanTouch = false
    previewLine.Massless = true
    previewLine.Material = Enum.Material.Neon
    previewLine.Color = Color3.fromRGB(255, 90, 90)
    previewLine.Transparency = 0.45
    previewLine.Size = Vector3.new(0.5, 0.5, GRAB_PREVIEW_RANGE)
    previewLine.Parent = Workspace

    previewEnd = Instance.new("Part")
    previewEnd.Name = "_GrabAimEnd"
    previewEnd.Shape = Enum.PartType.Ball
    previewEnd.Anchored = true
    previewEnd.CanCollide = false
    previewEnd.CanQuery = false
    previewEnd.CanTouch = false
    previewEnd.Massless = true
    previewEnd.Material = Enum.Material.Neon
    previewEnd.Color = Color3.fromRGB(255, 70, 70)   -- 기본: 빨강 (사거리 내 러너 없음)
    previewEnd.Transparency = 0.15
    previewEnd.Size = Vector3.new(2.4, 2.4, 2.4)
    previewEnd.Parent = Workspace
end

-- 비행 경로(태거 앞 origin → 최대 사거리) 위에 유효 러너(살아있고 Tagger 아닌 캐릭터)가 있는지
local function runnerOnPath(origin, forward)
    local mid = origin + forward * (GRAB_PREVIEW_RANGE / 2)
    local boxCFrame = CFrame.lookAt(mid, mid + forward)
    local boxSize = Vector3.new(GRAB_PREVIEW_MARK_RADIUS * 2, GRAB_PREVIEW_MARK_RADIUS * 2, GRAB_PREVIEW_RANGE)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    if previewLine then table.insert(ignore, previewLine) end
    if previewEnd  then table.insert(ignore, previewEnd)  end
    if localPlayer.Character then table.insert(ignore, localPlayer.Character) end
    params.FilterDescendantsInstances = ignore
    local parts = Workspace:GetPartBoundsInBox(boxCFrame, boxSize, params)
    local seen = {}
    for _, part in ipairs(parts) do
        local m = part:FindFirstAncestorOfClass("Model")
        if m and not seen[m] then
            seen[m] = true
            local hum = m:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local plr = Players:GetPlayerFromCharacter(m)
                if not (plr and plr:GetAttribute("Role") == "Tagger") then
                    return true
                end
            end
        end
    end
    return false
end

local function updatePreview()
    if not previewLine or not previewEnd then return end
    local char = localPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local cam  = Workspace.CurrentCamera
    if not hrp or not cam then return end
    local lv = cam.CFrame.LookVector
    local forward = Vector3.new(lv.X, 0, lv.Z)
    if forward.Magnitude < 0.001 then forward = hrp.CFrame.LookVector end
    forward = forward.Unit
    local origin = hrp.Position + forward * GRAB_PREVIEW_FWD + Vector3.new(0, GRAB_PREVIEW_HEIGHT, 0)
    local mid    = origin + forward * (GRAB_PREVIEW_RANGE / 2)
    local endPos = origin + forward * GRAB_PREVIEW_RANGE
    previewLine.CFrame  = CFrame.lookAt(mid, mid + forward)
    previewEnd.Position = endPos
    -- 경로 어디든 러너가 닿으면 주황, 없으면 빨강
    if runnerOnPath(origin, forward) then
        previewEnd.Color = Color3.fromRGB(255, 170, 90)
    else
        previewEnd.Color = Color3.fromRGB(255, 70, 70)
    end
end

-- ── 푸시 쿨다운 바 UI ───────────────────────────────────
local cooldownGui, cooldownFrame, cooldownFill, cooldownLabel
-- ── 그랩 버튼 UI ────────────────────────────────────────
local grabGui, grabBtn, grabCdOverlay

local function buildCooldownUI()
    if cooldownGui and cooldownGui.Parent then return end

    cooldownGui = Instance.new("ScreenGui")
    cooldownGui.Name = "PushCooldownGui"
    cooldownGui.ResetOnSpawn = false
    cooldownGui.IgnoreGuiInset = true
    cooldownGui.DisplayOrder = 8
    cooldownGui.Parent = localPlayer:WaitForChild("PlayerGui")

    cooldownFrame = Instance.new("Frame")
    cooldownFrame.Name = "Bar"
    cooldownFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    cooldownFrame.Position = UDim2.new(0.5, 0, 0.8, 0)
    cooldownFrame.Size = UDim2.new(0, 230, 0, 30)
    cooldownFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
    cooldownFrame.BackgroundTransparency = 0.25
    cooldownFrame.BorderSizePixel = 0
    cooldownFrame.Visible = false
    cooldownFrame.Parent = cooldownGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = cooldownFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 0, 0)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.4
    stroke.Parent = cooldownFrame

    cooldownFill = Instance.new("Frame")
    cooldownFill.Name = "Fill"
    cooldownFill.AnchorPoint = Vector2.new(0, 0.5)
    cooldownFill.Position = UDim2.new(0, 0, 0.5, 0)
    cooldownFill.Size = UDim2.new(1, 0, 1, 0)
    cooldownFill.BackgroundColor3 = Color3.fromRGB(220, 80, 80)
    cooldownFill.BorderSizePixel = 0
    cooldownFill.Parent = cooldownFrame

    local fcorner = Instance.new("UICorner")
    fcorner.CornerRadius = UDim.new(0, 8)
    fcorner.Parent = cooldownFill

    cooldownLabel = Instance.new("TextLabel")
    cooldownLabel.Size = UDim2.new(1, 0, 1, 0)
    cooldownLabel.BackgroundTransparency = 1
    cooldownLabel.Text = ""
    cooldownLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    cooldownLabel.TextScaled = true
    cooldownLabel.Font = Enum.Font.GothamBold
    cooldownLabel.TextStrokeTransparency = 0.4
    cooldownLabel.ZIndex = 2
    cooldownLabel.Parent = cooldownFrame

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 5)
    pad.PaddingBottom = UDim.new(0, 5)
    pad.Parent = cooldownLabel
end

local function buildGrabButton()
    if grabGui and grabGui.Parent then return end

    grabGui = Instance.new("ScreenGui")
    grabGui.Name = "PushGrabGui"
    grabGui.ResetOnSpawn = false
    grabGui.IgnoreGuiInset = true
    grabGui.DisplayOrder = 9
    grabGui.Enabled = false
    grabGui.Parent = localPlayer:WaitForChild("PlayerGui")

    grabBtn = Instance.new("TextButton")
    grabBtn.Name = "GrabButton"
    grabBtn.AnchorPoint = Vector2.new(1, 1)
    grabBtn.Size = UDim2.new(0, 100, 0, 100)   -- 임시값. 아래 syncSkillBtnPos 가 디바이스별로 덮어쓴다(Mobile 120 / PC 150)
    grabBtn.BackgroundColor3 = Color3.fromRGB(70, 45, 90)
    -- ⚠️ [GRAB-ICON-CONTRAST] 버튼 배경은 '투명'이어야 한다.
    --    실측(2026-08-23): 여기가 0.1(거의 불투명 보라)이었는데 아이콘 이미지도 보라 계열이라
    --    보라 위에 보라가 되어 손 모양 윤곽이 뭉갰다. 쿨다운과 무관하게 평상시에도 흐릿했다.
    --    잘 보이는 강타 버튼(ClassicSword.FXClient)은 버튼을 투명으로 두고 아이콘 쪽에
    --    어두운 배경(30,30,35)을 줘서 대비를 만든다. 같은 구조로 맞춘다.
    grabBtn.BackgroundTransparency = 1
    grabBtn.AutoButtonColor = true
    -- ⚠️ [GRAB-ICON] 텍스트 대신 아이콘. 강타/대시 버튼과 톤을 맞춘 것으로,
    --    저연령층이 그랩의 존재를 인지하지 못한다는 실측(2026-08-22)이 배경이다.
    --    쿨다운 중에는 갱신 코드가 숫자를 넣으므로 평시엔 Text 를 비운다.
    grabBtn.Text = ""
    grabBtn.TextScaled = true
    grabBtn.Font = Enum.Font.GothamBold
    grabBtn.TextColor3 = Color3.fromRGB(240, 230, 255)
    grabBtn.Active = true
    grabBtn.ZIndex = 4          -- 아이콘(2)·오버레이(3) 위에 쿨다운 숫자가 오도록
    grabBtn.Parent = grabGui

    -- 아이콘. ⚠️ Decal ID 를 ImageLabel 에 그대로 넣으면 안 그려진다.
    --   업로드하면 Roblox 가 Decal 로 감싸므로, 항상 내부 Image ID 를 추출해야 한다.
    --   추출: InsertService:LoadAsset(decalId) → 자식 Decal 의 .Texture
    --   [2026-08-28] 강화 슬랩 아이콘 교체
    --     Decal 113479182513623 → Image 127344251289225 (검정 배경판, 옆 대시 아이콘 톤에 맞춤)
    --     이전: Decal 79530690579461 → Image 109694174051624 (보라 배경 — 스킬바에서 혼자 튐)
    --     그 이전: 86289296972585 (구 '푸시' 시절)
    local grabIcon = Instance.new("ImageLabel")
    grabIcon.Name = "Icon"
    -- 🎨 [2026-08-28] 대비용 어두운 판을 없앤다(투명 1).
    --   [증상] 아이콘 주변에 회색 여백이 보였다.
    --   [원인] 이 배경판(30,30,35)이었다. 예전 아이콘은 배경이 투명한 PNG 라
    --     빈 곳마다 판이 그대로 비쳤다. 이미지가 아니라 판이 문제였던 것.
    --   [지금] 새 아이콘은 보라 배경이 가장자리까지 꽉 찬 풀블리드라 판이 필요 없다.
    --   ⚠️ 배경이 비치는 이미지로 다시 바꾼다면 투명도를 되돌리지 말고,
    --     '이미지를 풀블리드로 다시 뽑는' 쪽이 맞다. 판을 켜면 여백이 다시 생긴다.
    grabIcon.BackgroundTransparency = 1
    grabIcon.AnchorPoint = Vector2.new(0.5, 0.5)
    grabIcon.Position = UDim2.fromScale(0.5, 0.5)
    -- ⚠️ 높이에 +12 를 더해 아래 UIPadding(상하 6+6)을 상쇄한다. 패딩은 쿨다운 숫자가
    --    버튼 높이에 꽉 차지 않게 하려고 있는 것이라 유지해야 하는데, 그대로 두면
    --    아이콘까지 눌려 원 안에 작게 뜬다.
    --    ⚠️ 좌우 패딩은 없으므로 폭에는 보정이 필요 없다(실측 확인).
    grabIcon.Size = UDim2.new(1, 0, 1, 12)
    -- ⚠️ ScaleType 은 기본(Stretch) 을 유지한다. Fit 으로 바꾸면 정사각 이미지가
    --    원 안에서 축소돼 다시 여백이 생긴다 — 여백 제거와 정반대 결과다.
    grabIcon.Image = "rbxassetid://127344251289225"

    -- ⚠️ [2026-08-25] '꾹 눌러야 한다'는 안내.
    --    한 번 누르면 나가는 다른 스킬과 구분이 안 돼 곤란했다.
    local holdHint = Instance.new("TextLabel")
    holdHint.Name = "HoldHint"
    holdHint.Size = UDim2.new(1, 0, 0, 16)
    holdHint.Position = UDim2.new(0, 0, 1, -14)
    holdHint.BackgroundTransparency = 1
    holdHint.Font = Enum.Font.GothamBold
    holdHint.TextScaled = true
    holdHint.Text = "HOLD"
    holdHint.TextColor3 = Color3.fromRGB(255, 235, 150)
    holdHint.TextStrokeTransparency = 0.3
    holdHint.ZIndex = 10
    holdHint.Parent = grabBtn
    -- ⚠️ ScaleType 은 기본(Stretch). Fit 이면 정사각 이미지가 축소돼 버튼 안에서 작아진다.
    grabIcon.ZIndex = 2
    grabIcon.Active = false
    grabIcon.Parent = grabBtn
    -- ⚠️ 반경 0.5 = 완전 원형. UICorner 는 ImageLabel 의 '이미지'까지 라운딩하므로
    --    이 값이 버튼(0.5)과 어긋나면 원형 버튼 위에 각진 사각 이미지가 겹쳐 보인다.
    --    이전 값 0.18 이 정확히 그 상태였다.
    local gic = Instance.new("UICorner", grabIcon); gic.CornerRadius = UDim.new(0.5, 0)

    -- ⌨️ [2026-08-27] 키 힌트 "F".
    --   [왜] 러너 스킬 아이콘엔 전부 F 힌트가 있는데 태거 그랩만 없었다.
    --     조준 키를 E→F 로 옮긴 김에 표기도 러너 쪽 규약에 맞춘다.
    --   ⚠️ 스타일·위치·표시조건은 러너 무기(Gauntlet/Hammer/Katana/ClassicSword)의
    --     KeyHint 와 동일하게 유지할 것. 하나만 달라지면 "다른 기능"으로 읽힌다.
    --   ⚠️ ZIndex 만 러너(4)와 다르게 11 이다 — 여기선 아이콘 2 / 버튼 4 / HoldHint 10 이
    --     이미 쌓여 있어, 4 로 두면 쿨다운 숫자와 같은 층이 된다.
    do
        local hint = Instance.new("TextLabel")
        hint.Name = "KeyHint"
        hint.Text = "F"
        hint.AnchorPoint = Vector2.new(1, 0)
        hint.Position = UDim2.new(0.96, 0, 0.04, 0)
        hint.Size = UDim2.new(0.32, 0, 0.32, 0)
        hint.BackgroundColor3 = Color3.fromRGB(15, 20, 31)
        hint.BackgroundTransparency = 0.2
        hint.BorderSizePixel = 0
        hint.TextColor3 = Color3.new(1, 1, 1)
        hint.Font = Enum.Font.GothamBlack
        hint.TextScaled = true
        hint.ZIndex = 11
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = hint
        local s = Instance.new("UIStroke")
        s.Thickness = 1.5; s.Color = Color3.fromRGB(255, 190, 60); s.Parent = hint
        hint.Parent = grabBtn
        -- 키보드 입력 가능할 때만 표시 (러너 KeyHint · DiveSlotClient 와 동일 규칙)
        local _uis = game:GetService("UserInputService")
        local function updateHintVisibility()
            hint.Visible = not (_uis.TouchEnabled and not _uis.KeyboardEnabled)
        end
        updateHintVisibility()
        _uis:GetPropertyChangedSignal("KeyboardEnabled"):Connect(updateHintVisibility)
        _uis:GetPropertyChangedSignal("TouchEnabled"):Connect(updateHintVisibility)
    end

    -- 디바이스별 스킬 버튼 위치 (Q 슬롯 SKILLBAR_POS 바로 위 · 핫스왑 대응)
    local _Scaler = require(game:GetService("ReplicatedStorage"):WaitForChild("ResponsiveScaler"))
    -- Q 슬롯과 동일한 UIScale (좌표계 일치용 · 필수)
    _Scaler.applyEdge(grabGui, nil, {
        baseW = 1280, baseH = 720,
        Mobile = { minScale = 0.55 },
        PC     = { minScale = 0.55 },
    })
    -- ⚠️ [GRAB-SLOT] 러너의 무기 스킬 버튼(강타)과 '같은 자리'를 쓴다.
    --    아래 값은 ClassicSword.FXClient 의 SKILLBTN_POS / SKILLBTN_SIZE 와 동일해야 한다.
    --    좌표계가 일치하는 것도 확인됨: 양쪽 다 applyEdge(baseW 1280, baseH 720,
    --    minScale 0.55) + AnchorPoint(1,1) 이라 같은 숫자가 같은 지점을 가리킨다.
    --    ⚠️ 한쪽만 고치면 두 스킬 버튼의 자리가 어긋난다. 바꿀 땐 반드시 양쪽을 같이.
    --
    --    [이력] 이전 값은 Mobile(1,-36,1,-218) / PC(1,-160,1,-20) 이었다. 모바일 쪽은
    --    대시 슬롯(DiveSlot)과 완전히 같은 좌표였는데, 태거는 Q 슬롯이 숨겨지니 그 자리를
    --    재활용한 것이었다. 겹치지는 않았지만 러너의 스킬 자리와 달라서, 역할이 바뀌면
    --    같은 종류의 버튼을 다른 곳에서 찾아야 했다.
    local SKILLBTN_POS  = {
        Mobile = UDim2.new(1, -187, 1, -128),
        PC     = UDim2.new(1, -365, 1, -170),
    }
    local SKILLBTN_SIZE = { Mobile = 120, PC = 150 }
    local function syncSkillBtnPos()
        local dev = _Scaler.device()
        local sz  = SKILLBTN_SIZE[dev] or SKILLBTN_SIZE.PC
        grabBtn.Size = UDim2.fromOffset(sz, sz)
        grabBtn.Position = SKILLBTN_POS[dev] or SKILLBTN_POS.PC
    end
    syncSkillBtnPos()
    local _UIS = game:GetService("UserInputService")
    _UIS:GetPropertyChangedSignal("KeyboardEnabled"):Connect(syncSkillBtnPos)
    _UIS:GetPropertyChangedSignal("TouchEnabled"):Connect(syncSkillBtnPos)

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = grabBtn

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(180, 120, 240)
    stroke.Thickness = 3
    stroke.Parent = grabBtn

    -- 쿨다운 오버레이(위에서 덮어 내려오며, 남은 시간만큼 가림)
    grabCdOverlay = Instance.new("Frame")
    grabCdOverlay.Name = "CdOverlay"
    grabCdOverlay.AnchorPoint = Vector2.new(0.5, 0)
    grabCdOverlay.Position = UDim2.new(0.5, 0, 0, 0)
    grabCdOverlay.Size = UDim2.new(1, 0, 0, 0)
    grabCdOverlay.BackgroundColor3 = Color3.fromRGB(15, 10, 20)
    grabCdOverlay.BackgroundTransparency = 0.35
    grabCdOverlay.BorderSizePixel = 0
    -- ⚠️ [GRAB-ICON] ZIndex 순서: 아이콘(2) < 쿨다운 오버레이(3) < 버튼 텍스트(4)
    --    오버레이가 버튼 텍스트와 같은 3 이면 쿨다운 숫자가 가려질 수 있다.
    grabCdOverlay.ZIndex = 3
    grabCdOverlay.Parent = grabBtn
    local ocorner = Instance.new("UICorner")
    ocorner.CornerRadius = UDim.new(0.5, 0)
    ocorner.Parent = grabCdOverlay

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 6)
    pad.Parent = grabBtn

    -- 홀드: 누르면 조준 미리보기 시작, 떼면 발사(전역 InputEnded가 release 처리)
    grabBtn.MouseButton1Down:Connect(function()
        startAiming()
    end)
    -- ⚠️ [수정] MouseButton1Up 제거.
    --    실측: 꾹 눌러도 0.6초마다 Up 이 발동해 차징이 끊겼다.
    --    이제 서버가 CHARGE_TIME 후 자동 발동하므로 뗄 필요가 없다.
    --    취소는 UserInputService.InputEnded 가 담당한다.
    -- ⚠️ [수정] MouseLeave 제거. 버튼을 누르는 순간 커서가 조금만
    --    움직여도 발동해서 0초 차징으로 즉시 취소됐다.
    --    버튼 밖에서 떼는 경우는 UserInputService.InputEnded 가 잡는다.
end

local function updateCooldownUI()
    -- 🗑️ [2026-09-11] 강타 홀드 차징 진행률(%) 표시 제거.
    --   [왜 필요 없나] 2026-08-25 에 '홀드 차징 → 자동 발동'으로 바뀌었다.
    --     지금은 누르는 순간 발동이 확정되므로 %가 알려줄 정보가 없고,
    --     오히려 "더 누르면 더 강해지나?"로 오해를 만든다. 홀드 시절의 잔재다.
    --   ⚠️ 그리고 grabBtn.Text 에 쓰고 있었다 — 그 버튼은 이제 Q 광역 그랩 소유다.
    --     지우지 않으면 그랩 쿨 숫자를 강타 진행률이 매 프레임 덮어쓴다.
    --   [남기는 것] chargeStartAt 자체는 재진입 방지에 쓰이므로 건드리지 않는다
    --     (attemptPush 의 "진행 중 다시 누르면 애니가 0프레임부터" 가드).
    if not cooldownFrame then return end
    local now = os.clock()
    local remaining = cooldownEndTime - now

    if now < blockedFlashUntil and remaining > 0 then
        -- 쿨다운 중 푸시 시도 → 적색 점멸로 경고 (스윙 락 중에도 강제 표시)
        cooldownFrame.Visible = true
        local frac = math.clamp(remaining / math.max(cooldownTotal, 0.01), 0, 1)
        cooldownFill.Size = UDim2.new(frac, 0, 1, 0)
        local pulse = (math.sin(now * 40) + 1) * 0.5
        cooldownFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(255, 195, 195), pulse)
        cooldownLabel.Text = string.format("ON COOLDOWN  %.1fs", remaining)
    elseif cooldownIsReal and remaining > 0 then
        cooldownFrame.Visible = true
        local frac = math.clamp(remaining / cooldownTotal, 0, 1)
        cooldownFill.Size = UDim2.new(frac, 0, 1, 0)
        cooldownFill.BackgroundColor3 = Color3.fromRGB(220, 80, 80):Lerp(Color3.fromRGB(90, 200, 90), 1 - frac)
        cooldownLabel.Text = string.format("PUSH  %.1fs", remaining)
    elseif now < readyFlashUntil then
        cooldownFrame.Visible = true
        cooldownFill.Size = UDim2.new(1, 0, 1, 0)
        cooldownFill.BackgroundColor3 = Color3.fromRGB(90, 200, 90)
        cooldownLabel.Text = "✅ READY!"
    else
        cooldownFrame.Visible = false
    end
end

local function updateGrabButton()
    if not grabBtn then return end
    local remaining = grabCdEnd - os.clock()
    if remaining > 0 then
        local frac = math.clamp(remaining / grabCdTotal, 0, 1)
        grabCdOverlay.Size = UDim2.new(1, 0, frac, 0)
        grabBtn.Text = string.format("%.1f", remaining)
        grabBtn.AutoButtonColor = false
    else
        grabCdOverlay.Size = UDim2.new(1, 0, 0, 0)
        grabBtn.Text = ""          -- [GRAB-ICON] 준비 완료 = 아이콘만 보이게
        grabBtn.AutoButtonColor = true
    end
end

local function startCooldownLoop()
    buildCooldownUI()
    if cdConn then cdConn:Disconnect() end
    cdConn = RunService.RenderStepped:Connect(function()
        local now = os.clock()
        if cooldownIsReal and (cooldownEndTime - now) <= 0 then
            cooldownIsReal = false
            readyFlashUntil = now + 0.6
        end
        updateCooldownUI()
        -- 🔁 [복구 2026-09-11] F 강타 버튼의 쿨 표시.
        --   [사고] Q 그랩을 붙이면서 updateGrabButton() 을 루프에서 끊었는데,
        --     그게 grabBtn(=실제로는 F 강타 버튼)의 쿨 오버레이·숫자를 그리던 유일한
        --     경로였다. "훈련장에서 F 쿨타임이 표기되지 않는다"가 그 결과다.
        --   ⚠️ grabBtn 은 이름만 grab 이고 소유자는 강타다. Q 는 별도 슬롯(GrabSlot)을 쓰므로
        --     이제 둘이 안 겹친다 — 되살려도 안전하다.
        updateGrabButton()
        updateGrabHud()
        if aiming then updatePreview() end
    end)
end

-- ✋ 차징 시작 시각(클라 표시용). 실제 판정은 서버가 한다.

local function stopCooldownLoop()
    if cdConn then cdConn:Disconnect(); cdConn = nil end
    if cooldownFrame then cooldownFrame.Visible = false end
end

-- ── 입력: 푸시 ──────────────────────────────────────────
local function attemptPush()
    if os.clock() < cooldownEndTime then
        -- 쿨다운 중 시도 → 남은 시간 경고 표시 (서버 요청 없이 클라에서 처리)
        blockedFlashUntil = os.clock() + 0.35
        return
    end
    local camera = Workspace.CurrentCamera
    local aimDir = camera and camera.CFrame.LookVector or nil
    Remote:FireServer("Push", aimDir)
end

-- ── 입력: 그랩 (홀드 조준 → 떼면 발사) ──────────────────
-- ✋ [재설계 2026-08-25] 그랩 → 차징 슬랩
--    버튼을 누르고 있으면 차징, 놓으면 발동. 곡사포·마법책과 같은 문법이다.
function attemptGrab()
    -- (구 그랩) 더 이상 쓰이지 않는다
end

function startAiming()
    -- ⚠️ [2026-08-25] 쿨 중이면 아무것도 하지 않는다.
    --   [문제] 예전엔 클라가 쿨을 안 보고 이펙트·애니를 재생했다.
    --   서버 beginCharge 는 canCharge 가 false 면 조용히 return 하므로,
    --   화면에는 차징이 시작된 듯 보이는데 발동이 안 됐다.
    --   (실측: 쿨 7초인데 1.4~2.7초 간격으로 차징 연출만 반복)
    if grabCdEnd and os.clock() < grabCdEnd then
        return
    end

    btnPressedAt = os.clock()

    -- 🚧 [측정 2026-08-25] 남은 관문을 '연출보다 먼저' 통과시킨다.
    --   [실측] 차징 시도 8회 중 3회가 연출만 나오고 서버로 가지 않았다.
    --   ([ChargeFx] 는 찍혔는데 2.62초 뒤 [Duel] 결과가 없음)
    --   13.337 / 17.418 = 기본 슬랩 쿨 중, 20.202 = 이미 차징 중.
    --   관문이 연출 뒤에 있어 "모션은 나오는데 쿨도 데미지도 없다" 가 됐다.
    --   → 관문을 전부 앞으로. 이 아래로 내려오면 반드시 ChargeBegin 이 나간다.
    --
    -- ⚠️ [B안 2026-08-25] 차징은 '기본 슬랩 쿨' 을 보지 않는다.
    --   [왜] 서버 beginCharge 는 canSwing/cooldownUntil 을 아예 안 본다
    --        ("차징은 자기 쿨만 본다" — Server 459행). 클라만 혼자 막고 있었다.
    --        실측 로그에서 씹힌 차징 3회 중 2회가 이 불일치 때문이었다.
    --   [남기는 것] 스윙 모션 중(cooldownIsReal == false, SWING_LOCK 0.55s)에는
    --        여전히 막는다. 안 그러면 스윙 애니와 차징 자세가 겹친다.
    --   [안 건드리는 것] '차징 중 평타 차단' 은 별개 장치다
    --        (아래 onInputBegan 의 aiming 검사 + Server 1057행 charging 검사).
    if not cooldownIsReal and os.clock() < cooldownEndTime then
        blockedFlashUntil = os.clock() + 0.35
        return
    end
    -- 🧊 [2026-09-11] 차징 쿨 가드. 없으면 애니만 나가고 서버가 조용히 거부해
    --   "손 뻗은 자세로 굳는다"가 된다(실측: [Charge] 거부: 차징 쿨 0.2s 남음).
    --   [이력] 2026-08-25 에 '기본 슬랩 쿨' 가드를 걷어내면서(서버가 그걸 안 보므로)
    --     차징 자기 쿨 가드까지 같이 빠졌다. 서버 beginCharge 는 canCharge 를 본다.
    --   ⚠️ grabCdEnd 는 이름과 달리 '차징 쿨'이다(ChargeCooldown 이 세팅). 그랩 쿨은 realGrabCdEnd.
    if os.clock() < grabCdEnd then
        blockedFlashUntil = os.clock() + 0.35
        return
    end
    if aiming then return end
    -- ⚠️ [2026-08-25] 버튼을 떼도 차징은 계속된다(서버가 2초 뒤 자동 발동).
    --   그래서 aiming 만으로는 재진입을 못 막는다. 진행 중 다시 누르면
    --   차징 애니가 0프레임부터 재생돼 방금 살린 '모은 자세'가 도로 풀린다.
    --   chargeStartAt 은 ChargeFired / ChargeCancel 에서 0 이 되고,
    --   서버가 응답을 안 줘도 시간이 지나면 스스로 풀린다(브릭 방지).
    if chargeStartAt > 0 and (os.clock() - chargeStartAt) < (chargeDuration + 0.5) then
        return
    end

    aiming = true
    chargeStartAt = os.clock()

    -- ✨ 차징 이펙트. 단계는 1단계 킬 수에 따라 서버가 정한다.
    -- ⚠️ KillEffectSystem.updateChargeStage 가 PushChargeStage 속성을 세운다.
    local myChar = Tool.Parent
    local stage = (myChar and myChar:GetAttribute("PushChargeStage")) or 1
    -- 🔇 [로그 정리 2026-08-26] 차징마다 2줄씩 찍혔다(단계 + 템플릿).
    --   단계 선택은 검증 완료. 필요하면 아래 두 print 를 되살릴 것.
    --   ⚠️ 서버의 [Charge] 발동 로그는 남아 있어 차징 발생 자체는 여전히 추적된다.
    -- print("[ChargeFx] 단계 " .. tostring(stage))
    playChargeFx(stage)

    -- 🔒 차징 중임을 버튼에 표시한다.
    --    카타나 카운터처럼 "지금은 이 동작만 진행 중"을 알려,
    --    다른 조작을 시도하지 않게 한다.
    if grabBtn then
        local st = grabBtn:FindFirstChildOfClass("UIStroke")
        if not st then
            st = Instance.new("UIStroke")
            st.Thickness = 3
            st.Parent = grabBtn
        end
        st.Color = Color3.fromRGB(255, 235, 150)
        st.Transparency = 0
    end
    -- ✋ 차징 자세. 전용 애니(ChargeR6/R15)가 '차징 시점까지'를 담고 있다.
    -- ⚠️ 애니가 끝나면 로블록스가 자동으로 원래 자세로 되돌린다.
    --    '모은 자세'를 유지하려면 마지막 프레임에서 AdjustSpeed(0) 으로
    --    얼려야 한다(건틀릿과 같은 기법).
    -- ⚠️ Length 는 로드 직후 0 일 수 있으므로 매 프레임 확인한다.
    if chargeTrack then
        if chargeFreezeConn then chargeFreezeConn:Disconnect(); chargeFreezeConn = nil end
        chargeTrack:Stop(0)
        chargeTrack:Play(0.1)
        chargeTrack:AdjustSpeed(1)

        chargeFreezeConn = RunService.RenderStepped:Connect(function()
            -- ⚠️ [2026-08-25] 'not aiming' 조건 제거.
            --   [왜] 예전엔 유저가 버튼을 꾹 눌러 차징했다. 지금은 서버가
            --   2초 뒤 자동 발동하므로 손을 떼도 차징은 계속된다.
            --   그런데 stopAiming 이 aiming=false 로 만들면서 이 루프가
            --   마지막 프레임에 닿기 전에 끊겼다 → 애니가 끝까지 재생되고
            --   로블록스가 기본 자세로 되돌려 '모은 자세'가 안 남았다.
            --   (실측: 스킬 아이콘을 계속 누르고 있을 때만 홀드됨)
            --   해제는 ChargeFired / ChargeCancel / 사망·해제 경로가 담당한다.
            --   이 루프는 얼리는 즉시 스스로 끊으므로 남지 않는다.
            if not chargeTrack or not chargeTrack.IsPlaying then
                if chargeFreezeConn then chargeFreezeConn:Disconnect(); chargeFreezeConn = nil end
                return
            end
            local len = chargeTrack.Length
            if len > 0 and chargeTrack.TimePosition >= len - 0.05 then
                -- 마지막 프레임에서 정지 → 손을 뗄 때까지 그 자세 유지
                chargeTrack:AdjustSpeed(0)
                chargeTrack.TimePosition = len - 0.01
                if chargeFreezeConn then chargeFreezeConn:Disconnect(); chargeFreezeConn = nil end
            end
        end)
    end
    Remote:FireServer("ChargeBegin")
end

function stopAiming(fire)
    if not aiming then return end
    aiming = false
    clearPreview()
    -- ⚠️ [수정] ChargeRelease 를 보내지 않는다.
    --    서버가 CHARGE_TIME 후 자동 발동하는데, 뗄 때 취소 신호를 보내면
    --    2초를 채우기 전에 무효화된다(실측: 0.6초마다 Up 발동).
    --    취소가 필요하면 나중에 '이동 시 취소' 같은 명확한 조건으로 넣는다.
end

local function onInputBegan(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch then
        -- ⚠️ [2026-08-25] 차징 중에는 기본 슬랩을 막는다.
        --   [왜] 카타나 카운터처럼 '자세에 들어가면 그 동작만 수행'해야
        --   오조작이 없다. 예전엔 차징 중 좌클릭이 슬랩으로 나가
        --   무엇이 발동할지 예측할 수 없었다.
        if aiming then return end
        if os.clock() - btnPressedAt < 0.15 then return end
        attemptPush()
    -- ⌨️ [2026-08-27] 조준 키 E → F.
    --   [왜] E 가 태거 안에서 겹쳤다. 마법책·곡사포가 ProximityPrompt(E)를 쓰는데
    --     2단계에 PushTool 을 든 채로 책 앞에 서면 같은 키가 두 동작을 노린다.
    --   [왜 하필 F] 러너 무기 스킬이 전부 F 다 — ClassicSword 런지 / Katana 카운터 /
    --     HammerLow 스핀 / HammerHigh 차지 / Gauntlet 대시. "스킬은 F" 로 통일한다.
    --   ⚠️ E 는 상호작용(부활 홀드·픽업 프롬프트·마법책/곡사포)이 쓰는 자리로 남긴다.
    --   ⚠️ 아래 onInputEnded 의 해제 키와 한 짝이다. 한쪽만 바꾸면 조준이 안 풀린다.
    elseif input.KeyCode == Enum.KeyCode.F then
        startAiming()
    -- 🖐️ [2026-09-11] Q = 광역 그랩. 폐기됐던 그랩 버튼(PushGrabGui)이 그대로 살아난다.
    --   [키 정책] F = 스킬(강타·러너 웨폰) / E = 상호작용(부활·픽업·마법책) / Q = 진영 특수기.
    --     러너 Q 는 대시(RunnerDive), 태거 Q 는 그랩 — 역할이 배타적이라 겹치지 않는다.
    --   ⚠️ Q 는 이제 세 갈래다. 하나를 건드리면 나머지를 같이 볼 것:
    --       Q + Downed      → SosClient (다운일 때만. `if not char:GetAttribute("Downed") then return end`)
    --       Q + 러너 평상시 → RunnerDive 대시
    --       Q + 태거        → 여기
    --     셋 다 조건이 배타적이라 한 키를 공유해도 충돌하지 않는다.
    --   ⚠️ 차징 중에는 막는다. 서버 beginGrab 도 같은 가드를 갖고 있지만,
    --     클라에서 먼저 걸러야 "눌렀는데 아무 반응 없음"이 안 생긴다.
    elseif input.KeyCode == Enum.KeyCode.Q then
        if aiming then return end
        if os.clock() < realGrabCdEnd then return end
        Remote:FireServer("Grab")
    end
end

-- release: 조준 중일 때 손/터치/F를 떼면 발사 (버튼 밖에서 떼도 잡힘)
local function onInputEnded(input)
    if not aiming then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
       or input.UserInputType == Enum.UserInputType.Touch
       or input.KeyCode == Enum.KeyCode.F then
        stopAiming(true)
    end
end

-- ── 애니메이션 로드 ─────────────────────────────────────
local function loadAnimation()
    local char = Tool.Parent
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local animator = hum:FindFirstChildOfClass("Animator") or hum

    local swingAnim = Tool:FindFirstChild("Swing")
    if swingAnim then
        swingTrack = animator:LoadAnimation(swingAnim)
        swingTrack.Priority = Enum.AnimationPriority.Action
        swingTrack.Looped = false
    end

    local grabAnim = Tool:FindFirstChild("Grab")
    if grabAnim then
        grabTrack = animator:LoadAnimation(grabAnim)
        grabTrack.Priority = Enum.AnimationPriority.Action
        grabTrack.Looped = false
    end

    -- ✋ [2026-08-25] 리그별 전용 애니.
    -- ⚠️ R15 애니를 R6 캐릭터에 재생하면 리타게팅이 어긋나 자세가 깨진다.
    --    로블록스는 유저 아바타 설정에 따라 R6/R15 가 모두 들어오므로
    --    캐릭터의 RigType 을 보고 골라 쓴다.
    local isR6 = (hum.RigType == Enum.HumanoidRigType.R6)
    local chargeName = isR6 and "ChargeR6" or "ChargeR15"
    local attackName = isR6 and "AttackR6" or "AttackR15"

    local cObj = Tool:FindFirstChild(chargeName)
    if cObj then
        local okC, tr = pcall(function() return animator:LoadAnimation(cObj) end)
        if okC then
            chargeTrack = tr
            chargeTrack.Priority = Enum.AnimationPriority.Action4
            chargeTrack.Looped = false
        end
    end
    local aObj = Tool:FindFirstChild(attackName)
    if aObj then
        local okA, tr = pcall(function() return animator:LoadAnimation(aObj) end)
        if okA then
            attackTrack = tr
            attackTrack.Priority = Enum.AnimationPriority.Action4
            attackTrack.Looped = false
        end
    end
end

-- ── 서버 신호 처리 ──────────────────────────────────────
Remote.OnClientEvent:Connect(function(action, value, extra)
    if action == "PlaySwing" then
        -- ⚠️ 차징 슬랩(extra=true)은 느리고 무겁게 재생해 강타임을 보여준다.
        -- ⚠️ 차징 슬랩은 ChargeFired 에서 전용 공격 애니를 이미 재생했다.
        --    여기서 스윙까지 틀면 두 애니가 겹쳐 자세가 깨진다.
        if swingTrack and not extra then
            swingTrack:Play(0.1, 1, 5)
        elseif extra and not attackTrack and swingTrack then
            swingTrack:Play(0.05, 2.5, 0.7)   -- 전용 애니가 없을 때만 폴백
        end
        if typeof(value) == "number" then
            cooldownEndTime = os.clock() + value
            cooldownTotal   = value
            cooldownIsReal  = false
        end
    elseif action == "Cooldown" then
        if typeof(value) == "number" then
            cooldownEndTime = os.clock() + value
            cooldownTotal   = math.max(value, 0.01)
            cooldownIsReal  = true
        end
    elseif action == "ChargeBegin" then
        -- ✋ 서버가 차징을 받아들였다. value = CHARGE_TIME
        chargeStartAt = os.clock()
        chargeDuration = value or 2.0

    elseif action == "ChargeCooldown" then
        -- ✋ 차징 전용 쿨. 기본 슬랩 쿨과 별개로 표시한다.
        if typeof(value) == "number" then
            grabCdEnd = os.clock() + value
        end

    -- 🖐️ [2026-09-11] 광역 그랩 신호 4종.
    --   ⚠️ grabCdEnd 는 원래 '차징 쿨' 표시에 재사용되고 있었다(바로 위 분기).
    --     그랩이 부활하면서 같은 변수를 두 스킬이 쓰면 표시가 서로를 덮는다.
    --     → 그랩은 전용 변수(realGrabCdEnd)를 쓴다. 위 분기는 건드리지 않는다.
    elseif action == "StopGrab" then
        -- ✋ [2026-09-11] 그랩 애니 해제. PlayGrab 이 마지막 프레임에서 AdjustSpeed(0) 으로
        --   얼리는데, 옛 그랩은 '손이 돌아올 때' 풀었다. 그 경로가 사라져서 팔을 뻗은 채
        --   굳어 있었다(실측 22:05 판).
        --   ⚠️ freeze 예약도 무효화해야 한다. 안 그러면 Stop 직후 예약이 깨어나 다시 언다.
        grabFreezeId = grabFreezeId + 1
        if grabTrack then
            grabTrack:AdjustSpeed(1)
            grabTrack:Stop(0.15)
        end

    elseif action == "GrabBegin" then
        -- ⏳ 예열 시작. value = GRAB_WINDUP
        -- ⚠️ 폴백 2.0 은 서버 GRAB_WINDUP 과 맞은 적이 없다(서버는 1.5였다가 1.0).
        --   value 가 오면 그걸 쓰고, 총량도 같이 세워 게이지 분모를 맞춘다.
        local w = (typeof(value) == "number" and value > 0) and value or 1.0
        grabWindupTotal = w
        grabWindupEnd = os.clock() + w
    elseif action == "GrabCooldown" then
        if typeof(value) == "number" then
            realGrabCdEnd = os.clock() + value
            -- ⚠️ 총량을 서버에서 받아 저장한다. 20 으로 하드코딩하면 쿨을 바꿀 때마다
            --   오버레이가 어긋난다(테스트로 1 초로 내렸을 때 아예 안 보였다).
            realGrabCdTotal = math.max(value, 0.01)
        end
    elseif action == "GrabReady" then
        realGrabCdEnd = 0
    elseif action == "GrabLocked" then
        -- 서버가 잠갔다. 정확한 시각은 GrabCooldown 이 따로 알려준다.
        if realGrabCdEnd <= os.clock() then realGrabCdEnd = os.clock() + 0.1 end

    elseif action == "ChargeFired" then
        -- ✋ 차징 발동. 차징 자세를 끊고 전용 공격 애니로 넘어간다.
        aiming = false
        chargeStartAt = 0
        if chargeFreezeConn then chargeFreezeConn:Disconnect(); chargeFreezeConn = nil end
        -- ⚠️ 얼려둔 속도를 되돌리고 정지. 안 그러면 다음 차징이 멈춘 채 시작된다.
        if chargeTrack then chargeTrack:AdjustSpeed(1); chargeTrack:Stop(0.08) end
        -- 🔓 차징 표시 해제
        if grabBtn then
            local _st = grabBtn:FindFirstChildOfClass("UIStroke")
            if _st then _st.Transparency = 1 end
        end
        clearChargeFx()
        -- ⚠️ 전용 공격 애니가 있으면 그걸 쓴다. 없으면 기본 스윙으로 폴백.
        if attackTrack then
            attackTrack:Stop(0)
            attackTrack:Play(0.05)
        end
        if grabBtn then grabBtn.Text = "" end

    elseif action == "ChargeCancel" then
        -- ✋ 취소됐다
        -- 🔬 [진단 2026-09-11] 서버 [ChargeDiag/S] 와 한 짝. 원인 확정 후 둘 다 삭제.
        --   트랙이 nil 인지 / Stop 이 먹었는지를 가른다. 0.3초 뒤 재확인이 핵심이다 —
        --   Stop 을 불렀는데도 playing=true 로 남으면 애니 레이어 쪽 문제다.
        do
            local t = chargeTrack
            print(string.format("[ChargeDiag/C] 수신 | track=%s playing=%s speed=%.2f pos=%.2f/%.2f",
                t and "O" or "nil",
                t and tostring(t.IsPlaying) or "-",
                t and t.Speed or -1,
                t and t.TimePosition or -1,
                t and t.Length or -1))
            task.delay(0.3, function()
                if t then
                    print(string.format("[ChargeDiag/C] +0.3s | playing=%s speed=%.2f pos=%.2f",
                        tostring(t.IsPlaying), t.Speed, t.TimePosition))
                end
            end)
        end
        aiming = false
        chargeStartAt = 0
        if chargeFreezeConn then chargeFreezeConn:Disconnect(); chargeFreezeConn = nil end
        if chargeTrack then chargeTrack:AdjustSpeed(1); chargeTrack:Stop(0.2) end
        -- 🔓 차징 표시 해제
        if grabBtn then
            local _st = grabBtn:FindFirstChildOfClass("UIStroke")
            if _st then _st.Transparency = 1 end
        end
        clearChargeFx()
        -- ⚠️ [2026-09-11] `grabBtn.Text = ""` 제거. 그 버튼은 이제 Q 그랩 소유라
        --   여기서 비우면 그랩 쿨 숫자가 지워진다. 강타는 자기 UI(cooldownFrame)만 쓴다.
        clearPreview()

    elseif action == "Ready" then
        cooldownEndTime = 0
        cooldownIsReal  = false
    elseif action == "PlayGrab" then
        -- ✋ [2026-09-11] 예열 길이에 맞춰 배속을 계산한다.
        --   [실측] Grab 애니 길이 = 0.500s, 예열 = 2.0s.
        --     원래 속도로 재생하면 0.5초에 다 뻗고 남은 1.5초를 굳은 채 보낸다
        --     ("손만 뻗고 멈춘다"의 정체. freeze 는 버그가 아니라 옛 그랩의 의도였다 —
        --      손이 날아가 있는 동안 자세를 유지하려던 것).
        --   [지금] value = 예열 시간. speed = 길이 / 예열 → 2.0초에 걸쳐 천천히 뻗는다.
        --   ⚠️ Length 는 로드 직후 0 이다. 0 이면 배속을 못 구하므로 1.0 으로 둔다.
        if grabTrack then
            grabFreezeId = grabFreezeId + 1   -- 옛 freeze 예약 무효화
            local windup = (typeof(value) == "number" and value > 0) and value or 2.0
            local len = grabTrack.Length
            local speed = (len and len > 0) and (len / windup) or 1.0
            grabTrack:Stop(0)
            grabTrack:Play(0.1)
            grabTrack:AdjustSpeed(speed)
        end
        if typeof(value) == "number" then
            grabCdEnd   = os.clock() + value
            grabCdTotal = math.max(value, 0.01)
        end
        -- 그랩 중 백팩 잠금(무기 스왑 차단) + 안전망: GrabEnd를 놓쳐도 일정 시간 뒤 무조건 해제
        setBackpack(false)
        grabBackpackLockId = grabBackpackLockId + 1
        local myBpLock = grabBackpackLockId
        task.delay(1.5, function()
            if myBpLock == grabBackpackLockId then setBackpack(true) end
        end)
    elseif action == "GrabEnd" then
        -- 손이 돌아옴 → freeze 해제 + 애니 마무리(경직 해제) + 백팩 잠금 해제
        grabFreezeId = grabFreezeId + 1
        grabBackpackLockId = grabBackpackLockId + 1  -- 안전망 타이머 무효화
        setBackpack(true)
        if grabTrack then
            grabTrack:AdjustSpeed(1)
            grabTrack:Stop(0.15)
        end
    elseif action == "GrabCooldown" then
        if typeof(value) == "number" then
            grabCdEnd   = os.clock() + value
            grabCdTotal = math.max(value, 0.01)
        end
    end
end)

-- 🖐️ [2026-09-11] 그랩 전용 스킬 슬롯 — 러너 Q(대시)와 같은 규격·같은 컨테이너.
--   ⚠️ [정정 1] 처음에 grabBtn 에 얹었는데 그건 F 강타 버튼이다("[GRAB-SLOT] 러너의
--     무기 스킬 버튼(강타)과 같은 자리"). 한 버튼에 두 스킬이 겹쳤다.
--   ⚠️ [정정 2] 그다음엔 별도 ScreenGui 를 150×150 으로 띄웠는데, 대시는 80×80 이고
--     StarterGui.SkillBarGui.SkillBar (UIListLayout) 안에 들어 있다. 규격도 컨테이너도
--     달라서 크고 어긋나 보였다.
--   [지금] SkillBar 안에 DiveSlot 과 같은 80×80 슬롯으로 넣는다.
--     ⚠️ UIListLayout 이 배치를 맡으므로 Position 을 직접 주지 않는다.
--       리스트가 자동 정렬하니 스킬이 늘어도 좌표를 다시 안 잡아도 된다.
--     ⚠️ 실측 규격(대시와 동일): 슬롯 80×80 · 아이콘 Size(1,1) ScaleType Fit ·
--       KeyHint 0.32×0.32 Pos(0.96,0.04) Anchor(1,0).
--       한쪽만 바꾸면 두 스킬 버튼이 어긋난다. 바꿀 땐 DiveSlot 과 같이 볼 것.
local GRAB_ICON = "rbxassetid://86289296972585"   -- ⚠️ 데칼 124081112440323 의 '실제 이미지 ID'.
                                                  --   [실측] 데칼 ID 를 그대로 넣으면 안 뜬다(AssetTypeId 13).
                                                  --   InsertService:LoadAsset → Decal.Texture 로 꺼낸 값이다.
                                                  --   ⚠️ 다음 아이콘도 같은 변환이 필요하다. 데칼 ID 를 그대로 쓰지 말 것.

local grabSlot  = nil   -- 슬롯 프레임
local grabBadge = nil   -- Q 배지
local grabGauge = nil   -- 예열 게이지
local grabNum   = nil   -- 쿨 숫자

local function buildGrabHud()
    -- 이 스크립트 인스턴스가 이미 만든 슬롯이 살아 있으면 그대로 쓴다.
    if grabSlot and grabSlot.Parent then return end

    local pg = localPlayer:WaitForChild("PlayerGui")
    local bar = pg:WaitForChild("SkillBarGui", 5)
    bar = bar and bar:FindFirstChild("SkillBar")
    if not bar then
        warn("🖐️ [GrabHud] SkillBarGui.SkillBar 없음 — 슬롯을 못 만든다")
        return
    end

    -- 🧹 [2026-09-13] 이전 라운드가 남긴 고아 슬롯 제거.
    --   [증상] Q 버튼이 라운드마다 하나씩 늘었다(실측 2026-09-13 스크린샷: F 1개 / Q 2개).
    --   [원인] 위 가드는 `grabSlot`(이 스크립트의 지역 변수)만 본다. 그런데
    --     PushTool.Client 는 **툴 안의 LocalScript** 라 라운드마다 툴과 함께 죽고
    --     새 인스턴스로 다시 뜬다. 새 인스턴스의 grabSlot 은 nil 이므로 가드가 늘 통과한다.
    --     반면 SkillBar 는 StarterGui → PlayerGui 라 **라운드를 넘어 살아남는다**
    --     (WeaponUICleanupClient 의 KEEP_OPEN 화이트리스트에도 있다).
    --     즉 만든 쪽은 죽고 만든 물건만 남는다 — 아래 1288행 정리 코드는 툴이 파괴될 때
    --     도달하지 못한다. task.delay 가 호출자 혈통과 함께 회수되는 것과 같은 계열이다.
    --   [형태] 지역 변수 대신 **컨테이너를 직접 훑는다.** 고아가 몇 개 쌓였든 한 번에 치운다.
    --     UIListLayout 이 배치를 맡으므로 지우면 남은 슬롯이 알아서 재정렬된다.
    --   ⚠️ DiveSlot(러너 대시)은 건드리지 않는다. 이름으로 GrabSlot 만 고른다.
    for _, old in ipairs(bar:GetChildren()) do
        if old.Name == "GrabSlot" then
            pcall(function() old:Destroy() end)
        end
    end

    grabSlot = Instance.new("Frame")
    grabSlot.Name = "GrabSlot"
    -- ⚠️ [2026-09-11] 80 → 120. 대시 슬롯(80)과 맞췄더니 F 강타(150) 대비 너무 작았다.
    --   러너도 F 150 / Q 80 이라 원래 차이가 있지만, 태거 Q 는 핵심 신규 스킬이라
    --   그 격차가 더 눈에 띈다. 150 보다는 작게 둬서 위계는 남긴다.
    grabSlot.Size = UDim2.new(0, 120, 0, 120)
    grabSlot.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    grabSlot.BackgroundTransparency = 0.15
    grabSlot.BorderSizePixel = 0
    -- ⚠️ 아이콘 확대분을 잘라내려면 필수. 아래 icon 주석 참조.
    grabSlot.ClipsDescendants = true
    grabSlot.LayoutOrder = 2                     -- 대시(1) 다음
    grabSlot.Parent = bar
    Instance.new("UICorner", grabSlot).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke")
    -- 🎨 [2026-09-11] 태거 진영색(크림슨). TaggerHpDisplay 의 fillC 와 같은 값이다.
    --   ⚠️ 러너 웨폰 스킬 테두리는 아직 무기별 하드코딩이라 제각각이다
    --     (ClassicSword 금색 / Gauntlet 파랑 — 등급색도 진영색도 아님).
    --     B-1 사이드그레이드 작업에서 청색으로 통일할 것. 그래야 금색 = VIP 가 성립한다.
    stroke.Color = Color3.fromRGB(178, 34, 62)
    stroke.Thickness = 1.5
    stroke.Parent = grabSlot

    local icon = Instance.new("ImageButton")
    icon.Name = "IconButton"
    -- ⚠️ [2026-09-11] 여백 제거. ScaleType.Fit 을 써도 공백이 남는 건 이미지 자체에
    --   투명 여백이 들어 있기 때문이다(정사각 이미지 + 정사각 프레임이라 Fit/Crop 이 같다).
    --   → 슬롯보다 크게 그려서 여백을 프레임 밖으로 밀어내고 ClipsDescendants 로 자른다.
    --   1.2 = 가장자리 약 8% 씩 잘라냄. (1.35 는 손 모양이 상해서 낮췄다)
    icon.Size = UDim2.fromScale(1.2, 1.2)
    icon.Position = UDim2.fromScale(-0.1, -0.1)
    icon.BackgroundTransparency = 1
    icon.Image = GRAB_ICON
    icon.ScaleType = Enum.ScaleType.Fit
    icon.ZIndex = 2
    icon.Parent = grabSlot

    -- 쿨 오버레이 (아래에서 차오르는 어두운 막)
    local cdOverlay = Instance.new("Frame")
    cdOverlay.Name = "CooldownOverlay"
    cdOverlay.AnchorPoint = Vector2.new(0, 1)
    cdOverlay.Position = UDim2.fromScale(0, 1)
    cdOverlay.Size = UDim2.new(1, 0, 0, 0)
    cdOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    cdOverlay.BackgroundTransparency = 0.45
    cdOverlay.BorderSizePixel = 0
    cdOverlay.ZIndex = 3
    cdOverlay.Parent = grabSlot

    grabNum = Instance.new("TextLabel")
    grabNum.Name = "CooldownText"
    grabNum.Size = UDim2.fromScale(1, 1)
    grabNum.BackgroundTransparency = 1
    grabNum.Text = ""
    grabNum.TextColor3 = Color3.fromRGB(255, 255, 255)
    grabNum.TextScaled = true
    grabNum.Font = Enum.Font.GothamBold
    grabNum.TextStrokeTransparency = 0.3
    grabNum.ZIndex = 5
    grabNum.Parent = grabSlot

    grabBadge = Instance.new("TextLabel")
    grabBadge.Name = "KeyHint"
    grabBadge.AnchorPoint = Vector2.new(1, 0)
    grabBadge.Position = UDim2.fromScale(0.96, 0.04)   -- ⚠️ 대시와 동일
    grabBadge.Size = UDim2.fromScale(0.32, 0.32)
    grabBadge.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    grabBadge.BackgroundTransparency = 0.1
    grabBadge.Text = "Q"
    grabBadge.TextColor3 = Color3.fromRGB(255, 210, 120)
    grabBadge.TextScaled = true
    grabBadge.Font = Enum.Font.GothamBold
    grabBadge.ZIndex = 6
    grabBadge.Parent = grabSlot
    Instance.new("UICorner", grabBadge).CornerRadius = UDim.new(0, 5)

    -- 예열 게이지 (슬롯 하단)
    local gaugeBg = Instance.new("Frame")
    gaugeBg.Name = "WindupBg"
    gaugeBg.AnchorPoint = Vector2.new(0.5, 1)
    gaugeBg.Position = UDim2.new(0.5, 0, 1, -5)
    gaugeBg.Size = UDim2.new(0.82, 0, 0, 7)
    gaugeBg.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    gaugeBg.BackgroundTransparency = 0.15
    gaugeBg.BorderSizePixel = 0
    gaugeBg.Visible = false
    gaugeBg.ZIndex = 6
    gaugeBg.Parent = grabSlot
    Instance.new("UICorner", gaugeBg).CornerRadius = UDim.new(0, 4)

    grabGauge = Instance.new("Frame")
    grabGauge.Name = "WindupFill"
    grabGauge.Size = UDim2.fromScale(0, 1)
    grabGauge.BackgroundColor3 = Color3.fromRGB(255, 120, 150)
    grabGauge.BorderSizePixel = 0
    grabGauge.ZIndex = 7
    grabGauge.Parent = gaugeBg
    Instance.new("UICorner", grabGauge).CornerRadius = UDim.new(0, 4)

    icon.MouseButton1Click:Connect(function()
        if aiming then return end
        if os.clock() < realGrabCdEnd then return end
        Remote:FireServer("Grab")
    end)
end

-- 매 프레임 갱신. ⚠️ 별도 루프를 만들지 않고 기존 쿨다운 루프에 얹는다.
--   ⚠️ local 을 다시 쓰지 않는다 — 위에서 전방 선언했다. 여기서 local 을 붙이면
--     새 지역변수가 만들어져 루프가 보는 건 여전히 nil 이다.
function updateGrabHud()
    if not grabSlot or not grabSlot.Parent then return end
    local now = os.clock()
    local gaugeBg = grabGauge and grabGauge.Parent
    local cdOverlay = grabSlot:FindFirstChild("CooldownOverlay")

    if now < grabWindupEnd then
        -- 경고 중: 게이지가 찬다. 숫자는 감춘다.
        -- ⚠️ 분모는 GrabBegin 이 서버에서 받은 값이다. 하드코딩하지 말 것 —
        --   예전엔 1.5 가 박혀 있어 서버만 바꾸면 게이지가 어긋났다(2026-09-20 제거).
        local left = grabWindupEnd - now
        local ratio = math.clamp(1 - (left / math.max(grabWindupTotal, 0.01)), 0, 1)
        if gaugeBg then gaugeBg.Visible = true end
        grabGauge.Size = UDim2.fromScale(ratio, 1)
        grabNum.Text = ""
        if cdOverlay then cdOverlay.Size = UDim2.new(1, 0, 0, 0) end
        grabBadge.TextColor3 = Color3.fromRGB(255, 120, 150)   -- 시전 중 = 붉게
    else
        if gaugeBg then gaugeBg.Visible = false end
        if now < realGrabCdEnd then
            local frac = math.clamp((realGrabCdEnd - now) / realGrabCdTotal, 0, 1)
            grabNum.Text = string.format("%.0f", math.ceil(realGrabCdEnd - now))
            if cdOverlay then cdOverlay.Size = UDim2.new(1, 0, frac, 0) end
            grabBadge.TextColor3 = Color3.fromRGB(120, 120, 130)   -- 쿨 = 흐리게
        else
            grabNum.Text = ""
            if cdOverlay then cdOverlay.Size = UDim2.new(1, 0, 0, 0) end
            grabBadge.TextColor3 = Color3.fromRGB(255, 210, 120)   -- 준비 = 금색
        end
    end
end

-- ── 장착/해제 ───────────────────────────────────────────
Tool.Equipped:Connect(function()
    loadAnimation()
    startCooldownLoop()
    buildGrabButton()
    buildGrabHud()   -- 🖐️ Q 배지·예열 게이지·쿨 숫자 (grabBtn 이 만들어진 뒤여야 한다)
    if grabGui then grabGui.Enabled = true end
    if inputConn then inputConn:Disconnect() end
    inputConn = UserInputService.InputBegan:Connect(onInputBegan)
    if inputEndedConn then inputEndedConn:Disconnect() end
    inputEndedConn = UserInputService.InputEnded:Connect(onInputEnded)
end)

Tool.Unequipped:Connect(function()
    -- ⚠️ 장착 해제 시 이펙트가 남으면 손 색이 흰색으로 굳는다.
    clearChargeFx()
    if inputConn then
        inputConn:Disconnect()
        inputConn = nil
    end
    if inputEndedConn then
        inputEndedConn:Disconnect()
        inputEndedConn = nil
    end
    stopAiming(false)   -- 조준 중이었으면 미리보기 정리(발사 안 함)
    -- ⚠️ 차징 애니는 AdjustSpeed(0) 으로 얼려둔 상태다.
    --    속도를 되돌리고 멈추지 않으면 그 자세로 굳는다.
    --    (실측: 강화 슬랩 차징 중 라운드가 끝나면 포즈가 남았다)
    if chargeFreezeConn then chargeFreezeConn:Disconnect(); chargeFreezeConn = nil end
    if chargeTrack then chargeTrack:AdjustSpeed(1); chargeTrack:Stop(0) end
    if swingTrack then swingTrack:Stop() end
    -- ⚠️ [버그 수정 2026-08-26] grabTrack 도 AdjustSpeed(0) 으로 얼리는 트랙이다(896행).
    --   여기서 속도를 안 되돌리고 Stop 만 부르면 던진 포즈가 그대로 굳는다.
    --   (아래 unfreezeAllTracks 와 같은 처리 — 새 트랙 추가 시 양쪽 다 볼 것)
    grabFreezeId = grabFreezeId + 1   -- 예약된 freeze task 무효화
    if grabTrack then grabTrack:AdjustSpeed(1); grabTrack:Stop(0) end
    stopCooldownLoop()
    if grabGui then grabGui.Enabled = false end
    -- 🖐️ [2026-09-11] 그랩 슬롯 제거. SkillBar 는 러너와 공유하는 컨테이너라
    --   안 지우면 러너로 바뀌어도 그랩 아이콘이 남는다.
    if grabSlot then
        pcall(function() grabSlot:Destroy() end)
        grabSlot, grabBadge, grabGauge, grabNum = nil, nil, nil, nil
    end
    grabBackpackLockId = grabBackpackLockId + 1  -- 예약 무효화
    setBackpack(true)                            -- 해제 시 백팩 잠금 안전 복원
end)

print("✅ PushTool Client 활성화 (푸시 바 + 그랩 버튼/F + 허공 무쿨)")

-- ─── 백팩 UI 복구 안전망 (스킬 중 라운드 종료 대응) ───
-- ⚠️ 전방 선언. 아래 Destroying 콜백이 이 이름을 참조하는데, local 은 선언 이후에만
--    보이므로 미리 선언해두지 않으면 콜백이 nil 을 캡처한다.
local unfreezeAllTracks
-- PushTool가 차징/시전 중 백팩을 끄는데, 스킬 중 툴이 파괴/회수되면 복구 코드가
-- 실행 안 돼 백팩이 꺼진 채 잔존 → 다음 라운드 무기 장착 불가. 다단계로 확실히 켠다.
local function _restoreBackpack()
	pcall(function() setBackpack(true) end)
end
Tool.Destroying:Connect(function()
	_restoreBackpack()
	task.delay(0.6, _restoreBackpack)
	task.delay(1.8, _restoreBackpack)
	-- ⚠️ [2026-08-26] 파괴 시에도 얼린 애니를 푼다.
	--   라운드 종료로 툴이 통째로 제거되면 Unequipped 가 안 올 수 있다.
	--   (unfreezeAllTracks 는 아래에 선언 — Destroying 은 런타임에만 발화하므로 안전)
	if unfreezeAllTracks then unfreezeAllTracks() end
end)
Tool.Unequipped:Connect(function()
    -- ⚠️ 장착 해제 시 이펙트가 남으면 손 색이 흰색으로 굳는다.
    clearChargeFx()
	task.delay(0.1, _restoreBackpack)  -- 정상 해제 시에도 안전 복구 (스킬 안 켜졌으면 무해)
end)


-- ⚠️ 라운드 종료 시 PushTool 이 통째로 제거되면 Unequipped 가 오지 않을 수 있다.
--    그때도 얼린 애니를 반드시 풀어준다. 안 그러면 캐릭터가 그 자세로 굳는다.
-- 🧊 [2026-08-26] 얼린 애니 트랙 일괄 해제.
--
-- [왜 함수로 뽑았나] 이 툴은 두 트랙을 AdjustSpeed(0) 으로 얼린다:
--     · chargeTrack (719행) — 차징 자세 유지
--     · grabTrack   (896행) — 던진 포즈 유지
--   그런데 정리 경로가 넷이고(Unequipped / AncestryChanged / Died / Destroying)
--   각자 따로 해제 코드를 갖고 있어, grabTrack 이 전부에서 누락돼 있었다.
--   → 라운드 종료 시 그랩/슬랩 시전 중이면 포즈가 굳었다(재발 관측 2026-08-26).
--
-- ⚠️ 속도를 1 로 되돌린 뒤 Stop 해야 한다. 속도 0 인 트랙은 Stop 의
--   페이드아웃이 진행되지 않아 마지막 프레임 자세가 그대로 남는다.
-- ⚠️ 새로 얼리는 트랙을 추가하면 반드시 여기에도 추가할 것.
--   네 경로가 이 함수 하나만 부르므로, 여기만 고치면 전부 반영된다.
-- ⚠️ [2026-08-27 실측] 이 함수만으로는 부족하다.
--   라운드 종료 시 서버가 PushTool 을 제거하면 이 LocalScript 도 함께 사라져,
--   Destroying / AncestryChanged 가 발화해도 정리가 끝까지 못 간다.
--   그런데 AnimationTrack 은 Humanoid.Animator(캐릭터 소유)에 살아남아
--   spd=0 인 채로 굳는다(실측: PushTool=없음 + Action4 트랙 잔존).
--   → 툴 밖의 StarterPlayerScripts.AnimGuardClient 가 그 경우를 메운다.
--   ⚠️ 이 함수는 '툴이 살아 있는 경로'(장착 해제 등)에서 더 빨리 반응하므로 유지한다.
function unfreezeAllTracks()
    if chargeFreezeConn then chargeFreezeConn:Disconnect(); chargeFreezeConn = nil end
    grabFreezeId = grabFreezeId + 1   -- 예약된 freeze task 무효화
    if chargeTrack then
        pcall(function() chargeTrack:AdjustSpeed(1); chargeTrack:Stop(0) end)
    end
    if grabTrack then
        pcall(function() grabTrack:AdjustSpeed(1); grabTrack:Stop(0) end)
    end
    if swingTrack then
        pcall(function() swingTrack:AdjustSpeed(1); swingTrack:Stop(0) end)
    end
    -- ⚠️ [2026-08-27] attackTrack 누락으로 재발. 강화 슬랩 자세로 굳었다.
    --   [왜 이게 제일 나쁜가] attackTrack 은 Priority = Action4 다. 우선순위가
    --   최상단이라 이게 안 멈추면 Idle·Walk 가 이겨낼 수 없고, 로비로 돌아가도
    --   그 자세 그대로 남는다(chargeTrack 도 Action4 라 같은 이유로 목록에 있다).
    --   [이력] grabTrack 이 같은 이유로 2026-08-26 에 누락됐다가 추가됐다.
    --   같은 사고가 트랙만 바꿔 반복된 것 — 새 트랙을 만들 때 이 목록을 안 봤다.
    if attackTrack then
        pcall(function() attackTrack:AdjustSpeed(1); attackTrack:Stop(0) end)
    end
    -- 🛡️ [2026-08-27] 최종 안전망: 이름을 몰라도 Animator 의 Action 이상 트랙을 전부 끈다.
    --   [왜] 위 목록은 트랙을 추가할 때마다 사람이 갱신해야 하고, 실제로 두 번 놓쳤다.
    --     목록은 유지하되(의도가 드러나므로), 빠뜨려도 굳지는 않게 한 겹 더 둔다.
    --   ⚠️ Core·Idle·Movement 우선순위는 건드리지 않는다. 그것까지 끄면 T포즈가 된다
    --     (ANIM-SWEEP 에서 겪은 사고와 같은 유형).
    pcall(function()
        local char = Tool.Parent
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if not animator then return end
        for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
            local p = tr.Priority
            if p == Enum.AnimationPriority.Action or p == Enum.AnimationPriority.Action2
               or p == Enum.AnimationPriority.Action3 or p == Enum.AnimationPriority.Action4 then
                tr:AdjustSpeed(1)
                tr:Stop(0)
            end
        end
    end)
end

-- 🏁 [PUSHTOOL-ROUNDEND 2026-08-27] 라운드 상태를 직접 듣는다.
--   [왜] 기존 정리 경로 넷(Destroying / AncestryChanged / Died / Unequipped)은
--     전부 '툴이 사라지거나 캐릭터가 죽는' 것을 전제한다. 그런데 라운드가
--     타임아웃이나 점령으로 끝나면 캐릭터는 로비로 '이동'만 하고 툴도 남을 수 있다.
--     그 경로에선 넷 다 발화하지 않아 자세가 그대로 굳는다.
--   ⚠️ RoundPhase 속성은 ReplicatedStorage 에 있다(HUD 가 리스폰마다 재시작해도
--     이벤트를 놓치지 않으려고 만든 그 장치). 이벤트가 아니라 속성이라 늦게 붙어도 읽힌다.
--   ⚠️ stage1/stage2 로 '들어갈' 때는 풀지 않는다. 전투 중에 자세를 끊으면
--     정상 스윙이 취소된다. 라운드 밖(intermission/nil)으로 나갈 때만 푼다.
do
    local RS = game:GetService("ReplicatedStorage")
    RS:GetAttributeChangedSignal("RoundPhase"):Connect(function()
        local ph = RS:GetAttribute("RoundPhase")
        if ph == "stage1" or ph == "stage2" then return end
        if unfreezeAllTracks then unfreezeAllTracks() end
        clearChargeFx()
    end)
end

Tool.AncestryChanged:Connect(function(_, parent)
    if parent then return end
    unfreezeAllTracks()
    clearChargeFx()
end)

-- ⚠️ 캐릭터가 죽거나 리스폰될 때도 정리한다.
do
    local char = Tool.Parent
    if char and char:FindFirstChildOfClass("Humanoid") then
        local hum = char:FindFirstChildOfClass("Humanoid")
        hum.Died:Connect(function()
            unfreezeAllTracks()
            clearChargeFx()
        end)
    end
end
