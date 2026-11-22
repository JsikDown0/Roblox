-- 첫 스폰 시 텍스처/사운드 로딩 지연(흰 공, 무음)을 막기 위해 에셋 미리 로드
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

task.spawn(function()
    local FF3 = "rbxassetid://14005262616"  -- [진단] ForceField3 텍스처
    local toPreload = {}
    local ff3Found = false

    -- 텍스처: 실제 인스턴스를 넘겨야 디코드까지 확실히 프리로드됨
    local folder = ReplicatedStorage:WaitForChild("PreloadAssets", 10)
    if folder then
        folder:WaitForChild("KillEffectTextures", 10)  -- 서버가 킬이펙트 텍스처 채울 때까지 대기
        for _, d in ipairs(folder:GetDescendants()) do
            if d:IsA("Texture") or d:IsA("Decal") or d:IsA("ImageLabel")
                or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
                table.insert(toPreload, d)
                local id = d:IsA("ImageLabel") and d.Image or d.Texture
                if id == FF3 then ff3Found = true end
            end
        end
    end

    -- 사운드 등 ID 기반 에셋
    table.insert(toPreload, "rbxassetid://112698874460325") -- DemonFlameStone 사운드

    -- Frost Dragon 애니 (첫 스폰 때 클라가 rest pose로 굳는 문제 방지 — 필수)
    local FD_ANIMS = {
        ["rbxassetid://76023260643161"] = "FrostDragon 날갯짓",
        ["rbxassetid://77887657065146"] = "FrostDragon 엔딩",
    }
    for id in pairs(FD_ANIMS) do
        local a = Instance.new("Animation")
        a.AnimationId = id
        table.insert(toPreload, a)
    end

    -- 방패 방어 스파크(RiotShield) 텍스처 프리로드 — 첫 방어 시 스파크 팝인 방지
    local sparkFx = ReplicatedStorage:FindFirstChild("ShieldSparkFx")
    if sparkFx then
        for _, d in ipairs(sparkFx:GetDescendants()) do
            if d:IsA("ParticleEmitter") then table.insert(toPreload, d) end
        end
    end

    -- 이지스(Aegis) 골드 버스트 텍스처 프리로드 (ShieldBlockEmitClient 인라인 사용)
    table.insert(toPreload, "rbxassetid://17086063752")
    table.insert(toPreload, "rbxassetid://17086075673")

    -- ── 러너 소모품 사운드 — 프리뷰에는 없어 첫 사용 때 히치가 난다.
    --   ⚠️ 아래 프리뷰 폴더 프리로드는 '메시·텍스처'만 커버한다.
    --      Gas Grenade 는 사운드 4종(Explode/Fuse/Impact/Swing)이 실물에만 있어
    --      첫 투척 시 버벅였다(실측 2026-08-21).
    --   ⚠️ ServerStorage 는 클라가 못 읽으므로 ID 를 직접 나열한다.
    --      새 소모품에 사운드를 추가하면 여기도 갱신할 것.
    --   ⚠️ 전수 조사 결과 미프리로드 고유 사운드가 39개였다(2026-08-21).
    --      전부 넣으면 첫 진입이 느려지므로(현재 로딩 5.8초) 빈도 높은 것만 담는다:
    --        · 곰덫 2종 — 15개 스킨이 공유, 태거가 매 라운드 사용
    --        · 러너 소모품 — 스타터킷으로 전원 보유
    --      2단계 무기·스킨 변형 사운드는 제외(등장 시점이 늦거나 소유자 한정).
    for _, id in ipairs({
        -- 러너 소모품
        "rbxassetid://1265561710",  -- Gas Grenade: Explode / Dist
        "rbxassetid://138931042",   -- Gas Grenade: Fuse
        "rbxassetid://214755079",   -- Gas Grenade: Impact
        "rbxassetid://231425197",   -- Gas Grenade: Swing
        "rbxassetid://16211041",    -- Ice Bow: Fire
        "rbxassetid://89343281",    -- Ice Bow: Hit
        "rbxassetid://9119623080",  -- ODM Gear
        -- 태거 곰덫 (15개 스킨 공유 — 매 라운드 등장)
        "rbxassetid://138259748",   -- BearTrap: Bang
        "rbxassetid://513153251",   -- BearTrap: Ow
        -- 굴리기 3종은 기본 지급이라 매 라운드 등장. 배럴 메시 2종은 프리뷰 커버에서 빠져 있었다.
        "rbxassetid://119740614762290",  -- Wooden Barrel: Body
        "rbxassetid://113965249014596",  -- Wooden Barrel: Rings
    }) do
        table.insert(toPreload, id)
    end

    -- ── 태거/러너 아이템 프리뷰 — 첫 소환 히치 방지 (실물과 메시·텍스처 공유)
    for _, folderName in ipairs({"TaggerItemPreviews", "RunnerItemPreviews"}) do
        local pf = ReplicatedStorage:WaitForChild(folderName, 5)
        if pf then
            local added = 0
            for _, d in ipairs(pf:GetDescendants()) do
                if d:IsA("MeshPart") or d:IsA("SpecialMesh") or d:IsA("Decal")
                    or d:IsA("Texture") or d:IsA("ParticleEmitter") or d:IsA("Sound") then
                    table.insert(toPreload, d)
                    added += 1
                end
            end
            print("[Preload] " .. folderName .. " 수집:", added)
        end
    end

    -- ── 스켈레톤 드래곤 — 첫 작동 히치 방지: 사운드 + 메시 + 화염 파티클
    table.insert(toPreload, "rbxassetid://78381988783824")   -- 드래곤 비행음
    table.insert(toPreload, "rbxassetid://132960610285205")  -- 드래곤 화염음
    local dragon = workspace:FindFirstChild("skeleton dragon", true)
    if dragon then
        local dAdded = 0
        for _, d in ipairs(dragon:GetDescendants()) do
            if d:IsA("MeshPart") or d:IsA("SpecialMesh") or d:IsA("ParticleEmitter") or d:IsA("Beam") then
                table.insert(toPreload, d)
                dAdded += 1
            end
        end
        print("[Preload] skeleton dragon 수집:", dAdded)
    end

    -- ── 픽업 상자 — 첫 E키 획득 시 히치 방지
    -- ⚠️ 상자 템플릿은 ServerStorage 에만 있어 클라이언트가 접근할 수 없다.
    --    다행히 ItemPreviewHandler 가 부트 시 RS 에 프리뷰를 복제해둔다
    --    (RareChestPreview / ItemChestPreview / MysteryBoxPreview — 같은 이유의 기존 장치).
    --    런타임 생성이므로 WaitForChild 로 대기해야 한다.
    -- ⚠️ 상자 본체보다 "획득 연출"이 더 무겁다. RareSkinRewardCard 가 에셋 13개를
    --    참조하는데, 첫 획득 순간에 그걸 한꺼번에 로드하면서 렉이 걸린다(실측 체감).
    local chestAdded = 0
    for _, previewName in ipairs({"RareChestPreview", "ItemChestPreview", "MysteryBoxPreview"}) do
        local pf = ReplicatedStorage:WaitForChild(previewName, 5)
        if pf then
            for _, d in ipairs(pf:GetDescendants()) do
                if d:IsA("MeshPart") or d:IsA("SpecialMesh") or d:IsA("Decal")
                    or d:IsA("Texture") or d:IsA("ParticleEmitter") then
                    table.insert(toPreload, d)
                    chestAdded += 1
                end
            end
        else
            warn("[Preload] " .. previewName .. " 없음 — 해당 상자 메시 프리로드 생략")
        end
    end
    -- 획득 연출(RareSkinRewardCard)이 쓰는 아이콘·사운드 — ID 직접 지정
    local REWARD_ASSETS = {
        "rbxassetid://75422951",           -- 개봉 사운드
        "rbxassetid://547900945",
        "rbxassetid://6032245879",
        "rbxassetid://8451174579",
        "rbxassetid://8482764467",
        "rbxassetid://10357952493",
        "rbxassetid://10598374841",
        "rbxassetid://12681289795",
        "rbxassetid://12994153008",
        "rbxassetid://13278756202",
        "rbxassetid://102162470318254",
        "rbxassetid://105841275801305",
        "rbxassetid://127362823754161",
    }
    for _, id in ipairs(REWARD_ASSETS) do
        table.insert(toPreload, id)
        chestAdded += 1
    end
    print("[Preload] 픽업 상자·보상 연출 수집:", chestAdded)

    -- ── 게임플레이 중 첫 사용 히치 방지 (UI 아이콘보다 우선순위 높음)
    -- 기준: "플레이 도중 처음 발동하는 것"만 넣는다. UI 아이콘은 로딩이 늦어도
    -- 화면이 잠깐 비는 정도지만, 스킬·음악은 히치가 조작 손실로 이어진다.
    local GAMEPLAY_ASSETS = {
        -- RunnerDive: 대시 스킬 (사운드 + 애니 + 파티클)
        "rbxassetid://111623265887880",  -- Sandevistan 사운드
        "rbxassetid://86265615635745",   -- 배기 애니
        "rbxassetid://87796474809920",   -- 수박 파티클
        "rbxassetid://85698671947685",   -- 얼음 파티클
        -- MusicClient: 페이즈 전환 시 처음 로드되면 전환이 끊긴다
        "rbxassetid://118762225644778",  -- 로비/관전
        "rbxassetid://126199584198103",  -- 라운드 1단계
        "rbxassetid://73374900108244",   -- 2단계 진입
    }
    for _, id in ipairs(GAMEPLAY_ASSETS) do
        table.insert(toPreload, id)
    end
    -- 애니메이션은 Animation 인스턴스로 넘겨야 확실히 프리로드된다
    local DIVE_ANIM = Instance.new("Animation")
    DIVE_ANIM.AnimationId = "rbxassetid://86265615635745"
    table.insert(toPreload, DIVE_ANIM)
    print("[Preload] 게임플레이 에셋 수집:", #GAMEPLAY_ASSETS + 1)

    -- ── 매 라운드 반복 발동하는 것 (첫 발생 히치가 자주 체감됨)
    -- ⚠️ 판단 기준: "라운드마다 여러 번 일어나는가".
    --    킬이펙트(13종+)나 스킨(11종)처럼 "유저가 고른 1종만 쓰이는" 것은 넣지 않는다.
    --    전부 프리로드하면 첫 입장 로딩만 길어지고 대부분은 안 쓰인다.
    local FREQUENT_ASSETS = {

        -- 💬 이모지 말풍선 배경 (EmotionServer.BUBBLE_IMAGE)
        --   ⚠️ 안 넣으면 첫 출력에서 '이모지가 먼저 뜨고 말풍선이 나중에' 뜬다.
        --     이미지 두 장이 같은 프레임에 그려져야 하나의 도형으로 읽힌다(실측 2026-08-27).
        --   ⚠️ 이건 '텍스처 ID' 다. 데칼 ID(121813960622798)를 넣으면 프리로드가
        --     엉뚱한 걸 받아 실제 표시에는 도움이 안 된다.
        --   ⚠️ EmotionServer 의 BUBBLE_IMAGE 를 바꾸면 여기도 같이 바꿀 것.
        "rbxassetid://103948077910387",
        -- DownSystem: 러너가 쓰러질 때마다 (애니 + 사운드)
        "rbxassetid://139314696142315",
        "rbxassetid://122123776991115",
        "rbxassetid://103837025248844",
        "rbxassetid://125507346849648",
        -- BarricadeSystem: 벽 타격/파괴음 — 라운드마다 수십 회
        "rbxassetid://138453047962067",
        "rbxassetid://127860004094478",
        "rbxassetid://84981346209739",
        -- SpeedPotion: 러너가 라운드마다 마시는 소모품. 첫 사용 때 히치가 체감됐다.
        --   ⚠️ 이 ID 는 SpeedPotionClient 에 하드코딩되어 있다. 그쪽을 바꾸면 여기도 같이.
        "rbxassetid://92235360782852",

        -- ── 아래는 2026-08-23 전수 점검으로 추가 ──────────────────
        -- 판단 기준은 위와 동일: "라운드마다 여러 번 / 모든 플레이어에게" 발동하는가.
        -- ⚠️ 상점에서 사야 나오는 아이템(폭탄·에너지볼·곰덫·마이크밤·쓰나미·톡스박스)은
        --    일부러 뺐다. 모든 판에 등장하지 않는데 전부 넣으면 안 쓰는 유저의 첫
        --    로딩만 길어진다. 킬이펙트를 제외한 것과 같은 논리다.

        -- ClassicSword: 2단계 기본 지급 무기. 전원이 수십 번 휘두른다.
        "rbxassetid://133329036243942",   -- 평타
        "rbxassetid://126383299163284",   -- 강타

        -- FirePressureSystem: 매 라운드 고정 발동하는 환경 압박
        "rbxassetid://257528237",

        -- 부활 / SOS: 이번 리스크 완화로 발생 빈도가 올라갈 예정
        "rbxassetid://133794907160143",
        "rbxassetid://133835353564397",   -- 부활 보호막 생성음
        "rbxassetid://140558322031646",   -- SOS

        -- PickupSystem: 라운드당 최대 5개 + 8초마다 보충 → 개봉음이 자주 난다
        "rbxassetid://100791117505114",   -- 고급 상자
        "rbxassetid://116841971399984",   -- 일반 상자

        -- PushTool: 태거 그랩 버튼 아이콘. 장착 즉시 화면에 뜬다
        "rbxassetid://86289296972585",

        -- DurabilitySystem: 내구도 소모음. 러너 전원이 기본 1칸을 갖고 있어
        --   라운드마다 여러 번 울린다.
        "rbxassetid://117793859307433",

        -- 승패 감상 화면 스팅어. 라운드 종료마다 반드시 울린다.
        --   ⚠️ 첫 라운드에서 늦게 나오면 2초짜리 연출과 어긋나므로 반드시 등록.
        "rbxassetid://122312432289909",   -- 승리
        "rbxassetid://134829851656557",   -- 패배

        -- 감상 화면 배경 텍스처(광선·발광). 같은 이유로 미리 받아둔다.
        "rbxassetid://8451174579",

        -- 결과창 봇 태거 초상. 솔로 모드에서 매 라운드 노출된다.
        --   ⚠️ 업로드 원본(111476077461663)은 Decal 이라 여기 넣으면 안 된다.
        --      InsertService 로 뽑은 실제 Image ID 를 등록한다.
        "rbxassetid://103459617970841",

        -- 곡사포 사운드. 2단계마다 여러 번 울린다.
        --   ⚠️ 첫 발사가 늦으면 착탄 예고원과 소리가 어긋나 어색해진다.
        "rbxassetid://73341075974025",    -- 발사
        "rbxassetid://107141645486762",   -- 착탄

        -- 태거 기본 로드아웃(stone / Wood Log / Wooden Barrel) 소환·명중음
        "rbxassetid://133303251833176",
        "rbxassetid://101688098876378",
        "rbxassetid://101897300177252",
        "rbxassetid://105916582425420",   -- ItemNoob 명중음(nom-nom-nom)
    }
    for _, id in ipairs(FREQUENT_ASSETS) do
        table.insert(toPreload, id)
    end
    print("[Preload] 반복 발동 에셋 수집:", #FREQUENT_ASSETS)

    print("[Preload] 목록", #toPreload, "개 / ForceField3 텍스처 포함:", ff3Found)

    -- [LoadingScreen 연동] 진행률·완료 신호를 속성으로 발행
    local RS = game:GetService("ReplicatedStorage")
    local totalAssets = math.max(#toPreload, 1)
    local loadedCount = 0
    RS:SetAttribute("PreloadProgress", 0)

    local t0 = os.clock()
    local ok, err = pcall(function()
        ContentProvider:PreloadAsync(toPreload, function(assetId, status)
            loadedCount += 1
            RS:SetAttribute("PreloadProgress", math.min(loadedCount / totalAssets, 1))
            if assetId == FF3 then
                print("[Preload] ForceField3 로드 상태:", tostring(status))
            elseif FD_ANIMS[assetId] then
                print("[Preload] " .. FD_ANIMS[assetId] .. " 로드 상태:", tostring(status))
            end
        end)
    end)
    print(string.format("[Preload] 완료 (%.2fs) ok=%s%s", os.clock() - t0, tostring(ok), ok and "" or (" err=" .. tostring(err))))
    RS:SetAttribute("PreloadProgress", 1)
    -- PreloadDone은 메시 워밍업까지 끝난 뒤(스크립트 말미)에 발행


    -- ── 파티클 워밍업 (EMP) — Crimson Fang 카운터 참격에 사용되므로 필수.
    -- 첫 방출 시 텍스처 디코드 지연이 생겨 이펙트가 늦게 뜨는 걸 막는다.
    -- 대상은 ReplicatedStorage.empfieldfx (클라 접근 가능 위치).
    local WARMUP_EMP = true
    local emp = ReplicatedStorage:FindFirstChild("empfieldfx")
    if WARMUP_EMP and emp then
        local RunService = game:GetService("RunService")
        local cam = workspace.CurrentCamera
        local warm = emp:Clone()
        warm.Name = "_EmpWarmup"
        if warm:IsA("BasePart") then
            warm.Anchored = true
            warm.CanCollide = false
        end
        -- ⚠ 워밍업은 "화면에 실제로 렌더돼야" 텍스처가 디코드됨.
        --   완전히 시야 밖으로 빼면 워밍업이 무의미해져 첫 EMP가 다시 늦어진다.
        --   → 프러스텀 안에 두되 파티클을 아주 작게 만들어 눈에 안 띄게 처리.
        for _, e in ipairs(warm:GetDescendants()) do
            if e:IsA("ParticleEmitter") then
                e.Size = NumberSequence.new(0.05)
            end
        end
        warm.Parent = workspace
        local function place()
            if cam and warm.Parent and warm:IsA("BasePart") then
                warm.CFrame = cam.CFrame * CFrame.new(0, -8, -60)  -- 카메라 앞 60stud, 아래 8 (프러스텀 하단 구석)
            end
        end
        -- 실제 방출 1회 + 충분히 오래 렌더 (디코드는 횟수가 아니라 시간 문제)
        place()
        for _, e in ipairs(warm:GetDescendants()) do
            if e:IsA("ParticleEmitter") then
                e.Enabled = true
                e:Emit(5)
            end
        end
        local HOLD = 0.6  -- 디코드 여유(초). 부족하면 늘리면 됨
        local t0 = os.clock()
        while os.clock() - t0 < HOLD do
            place()
            RunService.RenderStepped:Wait()
        end
        warm:Destroy()
        print("[Preload] empfieldfx 워밍업 완료")
    end

    -- ── 파티클 워밍업 (불기둥) ────────────────────────────────
    -- ⚠️ 이건 에셋 다운로드 문제가 아니다. 텍스처(257528237)는 이미 프리로드에 있다.
    --    FirePressureSystem 이 기둥 18개에 이미터 여러 종을 '런타임에 생성'하는데,
    --    첫 방출에서 GPU 파이프라인이 준비되며 프레임이 툭 끊긴다(실측 체감).
    --    → 로딩 중에 같은 파라미터로 한 번 방출해 미리 데운다.
    -- ⚠️ 불기둥은 서버가 만드는 구조라 원본을 복제할 수 없다. 대신 같은 텍스처/크기대의
    --    이미터를 즉석에서 만들어 방출한다. 데워지는 것은 '그 텍스처의 렌더 경로'다.
    do
        local RunService = game:GetService("RunService")
        local cam = workspace.CurrentCamera
        if cam then
            local part = Instance.new("Part")
            part.Name = "_FireWarm"
            part.Size = Vector3.new(1, 1, 1)
            part.Transparency = 1
            part.Anchored = true
            part.CanCollide = false
            part.CanQuery = false
            part.CanTouch = false
            part.CastShadow = false
            part.CFrame = cam.CFrame * CFrame.new(0, -8, -60)
            part.Parent = workspace

            -- FirePressureSystem 의 Fire 이미터와 같은 계열 설정
            local pe = Instance.new("ParticleEmitter")
            pe.Texture = "rbxassetid://257528237"
            pe.Size = NumberSequence.new(10)
            pe.Transparency = NumberSequence.new(0.5)
            pe.Lifetime = NumberRange.new(0.4, 0.6)
            pe.Rate = 0
            pe.Speed = NumberRange.new(10, 20)
            pe.Parent = part

            -- 동적 광원도 함께 데운다(기둥에 PointLight 가 붙는다)
            local pl = Instance.new("PointLight")
            pl.Brightness = 0.05
            pl.Range = 6
            pl.Parent = part

            pe:Emit(12)

            -- 드래곤에 붙은 'Pillar of fire' 파티클도 같은 순간에 처음 켜진다.
            -- ⚠️ 실물을 복제하지 않고 Emit 만 시킨다. 드래곤은 맵에 상주하는 모델이라
            --    복제하면 21개 파트가 화면에 튀어나온다. 원본 이미터를 그 자리에서
            --    한 번 방출시키는 것만으로 렌더 경로가 데워진다.
            for _, mapFolder in ipairs(workspace:GetChildren()) do
                local dr = mapFolder:FindFirstChild("skeleton dragon")
                local pf = dr and dr:FindFirstChild("Pillar of fire")
                if pf then
                    for _, e in ipairs(pf:GetDescendants()) do
                        if e:IsA("ParticleEmitter") then
                            pcall(function() e:Emit(3) end)
                        end
                    end
                end
            end

            local t0 = os.clock()
            while os.clock() - t0 < 0.6 do
                part.CFrame = cam.CFrame * CFrame.new(0, -8, -60)
                RunService.RenderStepped:Wait()
            end
            part:Destroy()
            print("[Preload] 불기둥 파티클 워밍업 완료")
        end
    end

    -- ── 파티클 워밍업 (방패 스파크) — 첫 방어 스파크 GPU 디코드 보장(EMP와 동일 이유)
    local sparkFolder = ReplicatedStorage:FindFirstChild("ShieldSparkFx")
    if sparkFolder then
        local RunService = game:GetService("RunService")
        local cam = workspace.CurrentCamera
        local warm = Instance.new("Part")
        warm.Name = "_SparkWarmup"
        warm.Size = Vector3.new(0.2, 0.2, 0.2)
        warm.Transparency = 1
        warm.Anchored = true
        warm.CanCollide = false
        warm.CanQuery = false
        warm.CanTouch = false
        local att = Instance.new("Attachment")
        att.Parent = warm
        for _, src in ipairs(sparkFolder:GetChildren()) do
            if src:IsA("ParticleEmitter") then
                local e = src:Clone()
                e.Size = NumberSequence.new(0.05)  -- 눈에 안 띄게
                e.Enabled = false
                e.Rate = 0
                e.Parent = att
            end
        end
        warm.Parent = workspace
        local function placeSpark()
            if cam and warm.Parent then
                warm.CFrame = cam.CFrame * CFrame.new(0, -8, -60)  -- 프러스텀 하단 구석
            end
        end
        placeSpark()
        for _, e in ipairs(warm:GetDescendants()) do
            if e:IsA("ParticleEmitter") then e:Emit(5) end
        end
        local HOLD_S = 0.6
        local tS = os.clock()
        while os.clock() - tS < HOLD_S do
            placeSpark()
            RunService.RenderStepped:Wait()
        end
        warm:Destroy()
        print("[Preload] 방패 스파크 워밍업 완료")
    end

    -- ── 아이템 메시 렌더 워밍업 — 첫 소환 프레임 히치 방지 (로딩화면이 가려줌)
    do
        local RunSvc = game:GetService("RunService")
        local cam = workspace.CurrentCamera
        local tp = ReplicatedStorage:FindFirstChild("TaggerItemPreviews")
        local warmNames = {"stone", "Wood Log", "Wooden Barrel", "Spear"}
        local clones = {}
        if cam and tp then
            for i, nm in ipairs(warmNames) do
                local src = tp:FindFirstChild(nm)
                if src then
                    local c = src:Clone()
                    local pivot = cam.CFrame * CFrame.new((i - 2.5) * 4, -2, -12)
                    if c:IsA("Model") then
                        for _, d in ipairs(c:GetDescendants()) do
                            if d:IsA("BasePart") then
                                d.Anchored = true; d.CanCollide = false; d.CastShadow = false
                                d.Transparency = math.max(d.Transparency, 0.9)
                            end
                        end
                        c:PivotTo(pivot)
                    elseif c:IsA("BasePart") then
                        c.Anchored = true; c.CanCollide = false; c.CastShadow = false
                        c.Transparency = math.max(c.Transparency, 0.9)
                        c.CFrame = pivot
                    end
                    c.Parent = workspace
                    table.insert(clones, c)
                end
            end
            for _ = 1, 6 do RunSvc.RenderStepped:Wait() end
            for _, c in ipairs(clones) do c:Destroy() end
            print("[Preload] 아이템 메시 워밍업 완료:", #clones, "개")
        end

        -- 🛡️ 우든 실드 워밍업.
        -- ⚠️ 이건 PreloadAsync 로 못 잡는다. 실드에는 Sound/Texture 가 하나도 없고
        --    비용의 정체가 UnionOperation 지오메트리라, ID 를 목록에 넣어봐야 소용없다.
        --    → 위 아이템 메시와 같은 방식으로 '한 번 렌더'해서 준비시킨다.
        -- ⚠️ 설치 시 1.5배로 확대되므로(WoodShieldClient.SHIELD_SCALE) 같은 배율로 데운다.
        --    확대된 지오메트리가 실제로 그려질 형태다.
        do
            local tmpl = ReplicatedStorage:FindFirstChild("ItemTemplates")
            tmpl = tmpl and tmpl:FindFirstChild("wood Shield")
            if cam and tmpl then
                local c = tmpl:Clone()
                if c:IsA("Model") then
                    pcall(function() c:ScaleTo(1.5) end)
                    for _, d in ipairs(c:GetDescendants()) do
                        if d:IsA("BasePart") then
                            d.Anchored = true; d.CanCollide = false; d.CastShadow = false
                            d.Transparency = math.max(d.Transparency, 0.9)
                        end
                    end
                    c:PivotTo(cam.CFrame * CFrame.new(0, -2, -14))
                end
                c.Parent = workspace
                for _ = 1, 6 do RunSvc.RenderStepped:Wait() end
                c:Destroy()
                print("[Preload] 우든 실드 워밍업 완료")
            end
        end
    end

    RS:SetAttribute("PreloadDone", true)
end)
