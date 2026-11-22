-- RevivalFlag Server
-- 부활 깃발 — 1회 사용 소모품.
--
-- 효과 (Tool.Activated 시):
--   1. 사용자 위치에 깃발 모델 설치 (시각)
--   2. 시작 시점 *스냅샷*으로 범위 안의 다운자들 식별 (이후 입출입 무관)
--   3. 각 스냅샷 다운자에게 데스 타이머 정지 (자연사 막음)
--   4. 7초 후 자동 부활 (DownSystem.clearDown)
--   5. 깃발 모델 제거 + Tool 소모

local ServerStorage   = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace       = game:GetService("Workspace")
local Debris          = game:GetService("Debris")
local ServerScriptService = game:GetService("ServerScriptService")
local Players         = game:GetService("Players")

-- DownSystem 모듈 가져오기
local DownSystem = require(ServerScriptService:WaitForChild("DownSystem"))

-- 파티클 즉시 Emit 신호 (클라이언트에서 Emit 호출해야 보임)
local emitEvent = ReplicatedStorage:WaitForChild("RevivalFlagEmit")

-- ── 설정 ────────────────────────────────────────────────
-- ⚠️ [2026-08-27] EFFECT_DURATION 은 더 이상 실행 코드에서 쓰이지 않는다.
--   깃발 지속은 REVIVE_DELAY + 0.5 로, 부활 지연은 REVIVE_DELAY 로 계산한다.
--   지우지 않는 이유: 값의 이력(원래 7초였다)이 사라지면 왜 3이 됐는지 추적이 끊긴다.
--   ⚠️ 새 코드에서 이 상수를 쓰지 말 것. 쓰면 부활 시점과 다시 어긋난다.
local EFFECT_DURATION   = 7         -- (사용 안 함 · 이력 보존용) 옛 깃발 지속 = 옛 자동 부활 시간
local EFFECT_RADIUS     = 25        -- 효과 범위 (stud)
local FLAG_TEMPLATE_PATH = "revival flag"  -- workspace 안 깃발 모델 이름

local Tool = script.Parent
local Handle = Tool:WaitForChild("Handle")

-- 한 번 사용한 깃발은 이중 발동 방지
local used = false

-- ── 깃발 시각 모델 생성 ─────────────────────────────────
-- workspace["revival flag"] 폴더의 *모든 자식*을 복제하여 *효과 위치*에 설치.
-- 폴더 자식: AnimatedFlag (Model, 폴+천) + "flag effect" (Part, 파티클+PointLight).
-- 두 자식을 임시 Model 하나로 묶어서 위치 처리(PivotTo, GetBoundingBox) 편하게.
local function spawnFlagModel(position, tiltCF, skinName)
    tiltCF = tiltCF or CFrame.new()  -- 폴백: 기울기 없음
    local palmMode = (skinName == "PalmTree")
    local templateFolder = ReplicatedStorage:FindFirstChild(FLAG_TEMPLATE_PATH)
    if not templateFolder then
        warn("[RevivalFlag] " .. FLAG_TEMPLATE_PATH .. " 원본 폴더 못 찾음")
        return nil
    end

    -- 임시 Model로 wrap (Folder는 PivotTo 안 되니 Model로 묶음)
    local clone = Instance.new("Model")
    clone.Name = "RevivalFlagEffect"

    -- 폴더 안의 모든 자식 (AnimatedFlag + flag effect 등) 복제
    for _, child in ipairs(templateFolder:GetChildren()) do
        local c = child:Clone()
        c.Parent = clone
    end

    -- 원본 Animate 스크립트는 클론에서 재시작이 불안정함 (원인 불명).
    -- 안정적인 펄럭임을 위해 *원본 Animate 제거*하고 *자체 루프*로 직접 구현.
    -- AnimatedFlag.Animate가 자식의 자식이라 재귀 검색.
    local origAnimate = clone:FindFirstChild("Animate", true)
    if origAnimate then origAnimate:Destroy() end

    -- 모든 파트 anchored + non-collide (시각만)
    for _, desc in ipairs(clone:GetDescendants()) do
        if desc:IsA("BasePart") then
            desc.Anchored = true
            desc.CanCollide = false
            desc.CanQuery = false
            desc.CanTouch = false
        end
    end

    -- Flag(천) 메시파트 1~16 수집 + 모두 *처음엔 보이게* 리셋
    -- 재귀 검색 (clone.AnimatedFlag.Flag 경로)
    local flagFolder = clone:FindFirstChild("Flag", true)
    local frames = {}  -- [번호] = MeshPart
    if flagFolder then
        for _, c in ipairs(flagFolder:GetChildren()) do
            local n = tonumber(c.Name)
            if c:IsA("MeshPart") and n then
                c.Transparency = 1  -- 일단 모두 숨김 (루프가 곧 하나씩 표시)
                frames[n] = c
            end
        end
    end

    -- PrimaryPart 설정 (PivotTo용)
    local primary = nil
    for _, desc in ipairs(clone:GetDescendants()) do
        if desc:IsA("BasePart") then primary = desc; clone.PrimaryPart = primary; break end
    end

    clone.Parent = Workspace

    -- 모델 크기 축소 (원본 깃발 27.65 stud → 약 14 stud로, 캐릭터 2-3배 정도)
    -- ScaleTo는 모든 BasePart Size + 상대 위치를 비례 조정. Parent된 후 호출 권장.
    -- 위치 계산(PivotTo, GetBoundingBox) 전에 적용해야 정확한 바운딩박스 기반 보정 가능.
    clone:ScaleTo(0.5)

    if primary then
        -- 1단계: 일단 발 위치에 배치
        clone:PivotTo(CFrame.new(position))

        -- 2단계: 모델 바닥이 *발 위치(땅)*에 오도록 위로 올림.
        --   PivotTo는 모델의 *피벗*을 지정 위치에 두는데, 보통 피벗 = 모델 중심.
        --   즉 모델의 절반이 땅 아래로 묻혀버림 (축소 후 약 7 stud 매몰).
        --   해결: GetBoundingBox로 현재 바닥 Y 계산 후, 차이만큼 위로 보정.
        local cf, size = clone:GetBoundingBox()
        local currentBottom = cf.Position.Y - size.Y / 2
        local raise = position.Y - currentBottom
        if math.abs(raise) > 0.01 then
            clone:PivotTo(clone:GetPivot() + Vector3.new(0, raise, 0))
        end

        -- 3단계: 바닥 중심을 회전축으로 *지형 기울기* 적용.
        --   현재 피벗에서 *바닥(groundY)*까지의 수직 거리를 height로 잡고,
        --   그 height만큼 위로 올린 위치를 새 피벗으로 설정.
        --   CFrame.new(groundCenter) * tiltCF * CFrame.new(0, height, 0)는
        --   "groundCenter에서 기울인 후 그 기울인 축으로 height만큼 위로"를 의미.
        local pivot = clone:GetPivot()
        local height = pivot.Position.Y - position.Y
        local groundCenter = Vector3.new(pivot.Position.X, position.Y, pivot.Position.Z)
        clone:PivotTo(CFrame.new(groundCenter) * tiltCF * CFrame.new(0, height, 0))
    end

    -- palm tree skin: hide the flag cloth/pole, stand a palm tree, drop coconuts after 0.5s
    if palmMode then
        local animFlag = clone:FindFirstChild("AnimatedFlag")
        if animFlag then
            for _, d in ipairs(animFlag:GetDescendants()) do
                if d:IsA("BasePart") then d.Transparency = 1 end
            end
        end
        -- recolor the revive burst to light blue for the palm theme
        local fx = clone:FindFirstChild("flag effect")
        if fx then
            local lightBlue = ColorSequence.new(Color3.fromRGB(170, 225, 255), Color3.fromRGB(90, 175, 245))
            for _, d in ipairs(fx:GetDescendants()) do
                if d:IsA("ParticleEmitter") then
                    d.Color = lightBlue
                elseif d:IsA("PointLight") then
                    d.Color = Color3.fromRGB(130, 200, 255)
                end
            end
        end
        local palmTpl = game:GetService("ServerStorage"):FindFirstChild("PalmTreeStatic")
        if palmTpl then
            local palm = palmTpl:Clone()
            palm.Name = "PalmSkinTree"
            palm.Parent = clone
            palm:ScaleTo(0.35)
            palm:PivotTo(CFrame.new(position))
            local pcf, psz = palm:GetBoundingBox()
            local praise = position.Y - (pcf.Position.Y - psz.Y / 2)
            palm:PivotTo(palm:GetPivot() + Vector3.new(0, praise, 0))
            local ppivot = palm:GetPivot()
            local pheight = ppivot.Position.Y - position.Y
            local pground = Vector3.new(ppivot.Position.X, position.Y, ppivot.Position.Z)
            palm:PivotTo(CFrame.new(pground) * tiltCF * CFrame.new(0, pheight, 0))

            -- coconut drop after 0.5s
            task.delay(0.5, function()
                if not palm.Parent then return end
                local cf2, sz2 = palm:GetBoundingBox()
                local canopy = cf2.Position + Vector3.new(0, sz2.Y * 0.3, 0)
                for _ = 1, 5 do
                    local coco = Instance.new("Part")
                    coco.Shape = Enum.PartType.Ball
                    coco.Size = Vector3.new(1.4, 1.4, 1.4)
                    coco.Color = Color3.fromRGB(120, 78, 44)
                    coco.Material = Enum.Material.Wood
                    coco.CanCollide = false
                    coco.Position = canopy + Vector3.new(math.random(-30, 30) / 10, math.random(0, 15) / 10, math.random(-30, 30) / 10)
                    coco.AssemblyLinearVelocity = Vector3.new(math.random(-20, 20) / 10, 0, math.random(-20, 20) / 10)
                    coco.Parent = Workspace
                    Debris:AddItem(coco, 4)
                end
            end)
        end
    end

    -- ── 자체 펄럭임 루프 ──────────────────────────────────
    -- 매 0.04초마다 다음 프레임을 보이게(나머지 숨김) → 펄럭임 애니메이션.
    -- 깃발 모델이 destroy되면 clone.Parent == nil이 되어 자연 종료.
    if next(frames) and not palmMode then
        task.spawn(function()
            local i = 1
            while clone.Parent do
                -- 모두 숨김
                for _, mp in pairs(frames) do
                    mp.Transparency = 1
                end
                -- 현재 프레임만 보임
                local current = frames[i]
                if current then current.Transparency = 0 end
                i = (i % 16) + 1
                task.wait(0.04)
            end
        end)
    end

    -- ── 효과 범위 시각화 (빨강 원 둘레) ───────────────────
    -- 12 stud 반경 원의 *둘레만* 표시 (속은 비어있음).
    -- Roblox에는 native ring 도형이 없어 32개 짧은 세그먼트로 폴리곤 근사.
    -- 깃발 clone의 자식이라 깃발 destroy 시 자동 함께 사라짐.
    -- ScaleTo의 영향을 받지 않도록 *축소 처리 후*에 추가.
    local RING_SEGMENTS  = 32     -- 세그먼트 개수 (많을수록 부드러움)
    local RING_THICKNESS = 0.4    -- 원 두께 (방사상)
    local RING_HEIGHT    = 0.4    -- 원 높이 (수직)

    local ringFolder = Instance.new("Folder")
    ringFolder.Name = "RangeIndicator"
    ringFolder.Parent = clone

    -- 각 세그먼트의 호 길이 = 2 * R * sin(π/N) (현 길이)
    local segLen = 2 * EFFECT_RADIUS * math.sin(math.pi / RING_SEGMENTS)

    for i = 0, RING_SEGMENTS - 1 do
        local angle = (i / RING_SEGMENTS) * math.pi * 2
        local x = math.cos(angle) * EFFECT_RADIUS
        local z = math.sin(angle) * EFFECT_RADIUS

        -- 각 세그먼트의 *로컬* CFrame (기울기 없는 평면 기준):
        --   위치: 원 중심에서 (x, 0.05, z)
        --   X축: 접선 방향 (-sin θ, 0, cos θ)
        --   Y축: 로컬 위쪽
        local localPos = Vector3.new(x, 0.05, z)
        local localTangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
        local localUp = Vector3.new(0, 1, 0)
        local localCF = CFrame.fromMatrix(localPos, localTangent, localUp)

        -- 월드 변환: 원 중심 이동 → 지형 기울기 적용 → 로컬 변환
        local segCF = CFrame.new(position) * tiltCF * localCF

        local seg = Instance.new("Part")
        seg.Shape = Enum.PartType.Block
        seg.Size = Vector3.new(segLen, RING_HEIGHT, RING_THICKNESS)
        seg.CFrame = segCF
        seg.Color = Color3.fromRGB(255, 50, 50)
        seg.Material = Enum.Material.Neon
        seg.Transparency = 0.3
        seg.Anchored = true
        seg.CanCollide = false
        seg.CanQuery = false
        seg.CanTouch = false
        seg.Parent = ringFolder
    end

    return clone
end

-- ── 효과 발동 ───────────────────────────────────────────
local function activateFlag(user)
    if used then return end
    used = true

    local userChar = user.Character or user.CharacterAdded:Wait()
    local userRoot = userChar:FindFirstChild("HumanoidRootPart") or userChar:FindFirstChild("Torso")
    if not userRoot then
        used = false
        return
    end

    -- 깃발은 사용자 발치(약간 앞)에 설치.
    -- HRP는 캐릭터 허리 부근 → 발까지 약 3 stud 아래.
    -- 추가 0.5 stud 더 내려서 *살짝 박힌 듯* 자연스러운 모습.
    -- 사용자 위치에서 *지면을 향해 raycast*하여 정확한 지면 위치 + 기울기 얻기.
    -- Wood Shield의 지형 적응 패턴 차용 (WoodShieldClient L134~162 참고).
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {userChar}
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local rayResult = workspace:Raycast(
        userRoot.Position,
        Vector3.new(0, -80, 0),
        rayParams
    )

    -- 지면 위치 (raycast 실패 시 폴백: HRP에서 3.5 stud 아래)
    local groundPos = rayResult and rayResult.Position
        or (userRoot.Position - Vector3.new(0, userRoot.Size.Y / 2 + 2.5, 0))
    local terrainNormal = rayResult and rayResult.Normal or Vector3.new(0, 1, 0)

    -- worldY → terrainNormal 회전 CFrame (지형 기울기)
    local worldY = Vector3.new(0, 1, 0)
    local cross = worldY:Cross(terrainNormal)
    local tiltCF
    if cross.Magnitude > 0.001 then
        tiltCF = CFrame.fromAxisAngle(cross.Unit,
            math.acos(math.clamp(worldY:Dot(terrainNormal), -1, 1)))
    else
        tiltCF = CFrame.new()  -- 평지면 회전 없음
    end

    local eqSkin = _G.getEquippedSkin and _G.getEquippedSkin(user, "RevivalFlag") or nil
    local flagModel = spawnFlagModel(groundPos, tiltCF, eqSkin)

    -- ⚠️ 중요: 이 스크립트의 부모를 Tool에서 깃발 모델로 이동.
    -- 이유: Tool:Destroy() 호출 시 스크립트도 함께 파괴되어
    --       아래의 task.delay 콜백들이 모두 자동 취소되는 문제가 있음.
    --       스크립트를 깃발 모델로 옮기면, Tool 파괴와 무관하게
    --       깃발 모델 수명 동안 (7.5초) 스크립트가 살아있어 콜백이 정상 실행됨.
    if flagModel then
        script.Parent = flagModel
    end

    -- 설치 사운드 — 단일 재생.
    -- SoundService에 추가하여 2D 사운드 (모든 클라가 동일 볼륨으로 들음).
    do
        local SoundService = game:GetService("SoundService")
        local snd = Instance.new("Sound")
        snd.SoundId = "rbxassetid://106419036434633"
        snd.Volume = 1
        snd.Parent = SoundService
        snd:Play()
        -- 재생 끝나면 자동 정리
        snd.Ended:Once(function() snd:Destroy() end)
        -- 안전망: 10초 후 강제 정리 (Ended가 실패하는 케이스 대비)
        Debris:AddItem(snd, 10)
    end

    -- 클라이언트에 파티클 즉시 Emit 신호 발신.
    -- ParticleEmitter:Emit()은 *클라이언트에서 호출해야만* 그 클라에 보이므로,
    -- 서버는 신호만 보내고 각 클라가 자기 화면에서 Emit 호출 → 모든 클라가 폭발 봄.
    -- 살짝 지연(replication 보장) 후 flag effect Part 참조와 함께 발신.
    if flagModel then
        local flagEffectPart = flagModel:FindFirstChild("flag effect")
        if flagEffectPart then
            -- 약간의 지연으로 클라이언트에 모델이 replicate된 후 Emit 보장
            task.delay(0.1, function()
                if flagEffectPart and flagEffectPart.Parent then
                    emitEvent:FireAllClients(flagEffectPart)
                end
            end)
        end
    end

    -- 시작 시점 스냅샷: 범위 안의 다운자 모두 식별
    local affectedDowned = {}
    for _, char in ipairs(Workspace:GetChildren()) do
        if char:IsA("Model") and char ~= userChar then
            local hum = char:FindFirstChildOfClass("Humanoid")
            local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
            if hum and hum.Health > 0 and hrp and char:GetAttribute("Downed") then
                local dist = (hrp.Position - userRoot.Position).Magnitude
                if dist <= EFFECT_RADIUS then
                    table.insert(affectedDowned, char)
                end
            end
        end
    end

    print(string.format("🚩 [RevivalFlag] %s 사용 — 범위 내 다운자 %d명 영향",
        user.Name, #affectedDowned))

    -- 각 다운자에게: 데스 타이머 정지 + REVIVE_DELAY 후 자동 부활
    -- ⚠️ [2026-08-27] 지연 7 → 3, 그리고 부활 무적 부여.
    --   [왜 지연이 있나] 광역 자동 부활이라 대가가 필요하다는 설계다(수동 부활은
    --     1.5초 홀드 + 구조자가 제자리에 묶임 — 깃발은 그게 없다).
    --   [왜 7 → 3] 다운 지속이 10초인데 7초를 기다리면 대가가 아니라 사실상 무효였다.
    --     3초면 "즉시는 아니지만 확실히 산다"가 성립한다.
    --   [왜 무적] 일반 부활은 INVUL_DURATION(2초) 무적이 붙는데 깃발은 자체 경로로
    --     clearDown 만 불러 맨몸으로 일어났다. 살아나자마자 다시 쓰러지면 깃발을 쓴
    --     의미가 없다. ReviveSystem.grantInvul 로 같은 무적을 준다.
    --   ⚠️ 무적 구현이 속성+토큰+구체+배지+해제예약 한 덩어리라 흉내 내지 말 것.
    --   [3 의 근거] 일반 부활(ReviveSystem.REVIVE_DURATION)이 1.5초 홀드다.
    --     광역 자동이라는 이점의 대가로 그 2배를 지연으로 준다.
    --     ⚠️ ReviveSystem 의 홀드 시간을 바꾸면 여기도 같이 볼 것(2배 관계 유지).
    local REVIVE_DELAY = 3
    for i, downedChar in ipairs(affectedDowned) do
        -- 자연사 막기
        DownSystem.cancelDeathTimer(downedChar)
        downedChar:SetAttribute("RevivalFlagActive", true)
        print(string.format("  ↳ %s: 데스 타이머 정지, %d초 후 자동 부활", downedChar.Name, REVIVE_DELAY))

        local isFirst = (i == 1)   -- 소리는 한 번만 (여러 명 동시 부활 시 겹침 방지)
        task.delay(REVIVE_DELAY, function()
            if not downedChar.Parent then return end  -- 사라짐
            local stillDowned = downedChar:GetAttribute("Downed")
            local hum2 = downedChar:FindFirstChildOfClass("Humanoid")
            if stillDowned and hum2 and hum2.Health > 0 then
                DownSystem.clearDown(downedChar)
                -- 🛡️ 일반 부활과 동일한 무적. clearDown 뒤에 부른다
                --    (다운 중에 걸면 clearDown 이 상태를 되돌리며 지울 수 있다).
                local ok, RV = pcall(require, game:GetService("ServerScriptService"):WaitForChild("ReviveSystem"))
                if ok and RV and RV.grantInvul then
                    RV.grantInvul(downedChar, isFirst)
                end
                print(string.format("  ✨ %s 자동 부활 완료 (무적 부여)", downedChar.Name))
            else
                print(string.format("  ⚠️ %s 부활 실패 (이미 사망/회복)", downedChar.Name))
            end
            downedChar:SetAttribute("RevivalFlagActive", nil)
        end)
    end

    -- 깃발 시각 모델 제거 (효과 끝 후 + 약간의 페이드 여유)
    -- 🚩 [2026-08-27] 깃발 지속을 부활 시점에 맞춘다(EFFECT_DURATION 7 → REVIVE_DELAY 기준).
    --   [왜] 부활 대상은 '사용 순간'의 범위 내 다운자로 확정된다(affectedDowned 스냅샷).
    --     즉 3초에 부활이 끝나면 그 뒤 깃발은 아무 기능이 없다.
    --     그런데 7초까지 서 있어서 "여기 오면 살려준다"로 읽혔다 — 나중에 다운된 러너가
    --     깃발 쪽으로 기어가거나, 동료가 "저기 깃발 있으니 괜찮겠지" 하고 구조를 포기한다.
    --     기능이 끝난 물건이 화면에 남아 있으면 그건 UI 가 거짓말하는 것과 같다.
    --   ⚠️ EFFECT_DURATION(7) 자체는 지우지 않았다. 다른 곳에서 참조할 수 있어서다.
    --     여기서만 부활 시점 기준으로 계산한다.
    --   +0.5 는 페이드 여유(부활 연출이 끝나는 걸 보고 사라지게).
    if flagModel then
        Debris:AddItem(flagModel, REVIVE_DELAY + 0.5)
    end

    -- Tool 소모 (즉시 제거)
    task.wait(0.1)
    Tool:Destroy()
end

-- ── 입력 처리 ───────────────────────────────────────────
Tool.Activated:Connect(function()
    local user = Players:GetPlayerFromCharacter(Tool.Parent)
    if user then
        activateFlag(user)
        -- [CONSUMABLE-ONUSE] 발동 확정 지점. user 가 nil 이면 아무 일도 안 일어난다.
        if _G.MarkConsumableUsed then _G.MarkConsumableUsed(user, "RevivalFlag") end
    end
end)

print("✅ RevivalFlag Server 활성화 (범위:", EFFECT_RADIUS, ", 부활 지연: 3초 / 깃발 지속: 3.5초)")
