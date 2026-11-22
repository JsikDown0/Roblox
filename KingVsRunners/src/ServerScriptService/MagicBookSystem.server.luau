-- ═══════════════════════════════════════════════════════════════
-- 📖 마법책 (map2 수성 무기)
--
-- [왜 map1 과 다른 물건인가] 두 맵이 "스킨만 다른" 상태였다. 같은 곡사포를
--   양쪽에 두면 사막 테마가 겉치레로만 남는다.
--   → map2 는 마법책 3개. 역할은 같지만 형태·연출이 다르다.
--
-- [왜 마석이 아니라 책인가] 마석은 map2 의 많은 장식(오벨리스크·태양 심볼·
--   횃불)에 묻혀 "쓸 수 있는 것"으로 안 읽힌다.
--   → 책은 공중에 뜬 채 회전한다. 움직이는 것은 장식이 아니라는 신호다.
--
-- [왜 책에서 불꽃이 나가나] 태양에서만 떨어지면 "내가 쐈다"가 안 느껴진다.
--   책 → 하늘 → 착탄 순으로 이어져야 인과가 읽힌다.
--
-- ⚠️ 조작은 곡사포와 동일하다(ProximityPrompt + E 홀드). 맵이 바뀌어도
--    배울 게 없어야 한다.
-- ═══════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- ── 튜닝 ───────────────────────────────────────────────────────
local USE_RANGE     = 14
local CHARGE_TIME   = 2.0
local COOLDOWN      = 6.0
-- ⏳ [2026-08-29] 봇 전용 예고 시간(초). CannonSystem.BOT_TELEGRAPH 와 같은 값·같은 이유.
--   유저의 홀드 차징(CHARGE_TIME 2.0)이 하던 예고를 봇에게도 준다.
--   ⚠️ 곡사포와 값을 맞춰 둔다. 한쪽만 바꾸면 두 기물의 리듬이 어긋난다.
local BOT_TELEGRAPH = 1.4
-- 🎯 [2026-08-27] 반경 44 → 38. 회피 가능성 확보.
--   [왜] 중앙에 선 러너가 Q대시로 완벽히 빠져나올 수 있어야 한다는 기준을 세웠다.
--     실측 계산(BURST 80×0.5s / 탈진 6×1.0s / 걷기 16, 예고 1.55s):
--       달리기만        20.0 stud  — 대시 없이는 반경 44 를 절대 못 벗어남
--       즉시 대시(반응0.3) 44.5 stud  — 44 대비 0.5 차이, 사실상 운
--       즉시 대시(반응0.5) 43.3 stud  — 피격
--       막판 대시(최적)   48.8~52.0  — 살지만, 붉게 점멸하는데 대시를 참는 플레이가 전제
--     즉 44 는 "반응 0.3초 + 최적 타이밍" 을 동시에 요구해 실질 회피 불가였다.
--   [38 의 근거] 즉시 대시 상한 44.5 대비 6.5 stud 여유 → 반응 0.5초까지 커버된다.
--   ⚠️ 이 값은 책 배치와 한 짝이다. 책 3개 간격이 75 라 지름 76(=38×2)이 겨우 맞물린다.
--     더 낮추면 원 사이에 틈이 생겨 "그 라인만 타면 안 맞는" 위치 암기 게임이 된다.
--     더 줄이려면 반경만 만지지 말고 책 간격도 같이 좁힐 것.
--   ⚠️ 곡사포(34)는 안 건드린다. 반경 34 / 예고 1.1s 는 어떤 플레이로도 탈출 가능해
--     이미 기준을 만족한다. 값이 다른 건 대포 4대 / 책 3개의 개수 차이다.
local BLAST_RADIUS  = 38      -- ⚠️ 3개로 성벽 폭을 덮는 값(지름 76 ≈ 책 간격 75)
-- 🛢️ [2026-08-27] 판정은 '구'가 아니라 '원기둥'이다.
--   [증상] 경고원 안인데 안 맞거나, 원 밖으로 보이는데 맞았다.
--   [원인] 경고원(CannonWarnClient)은 한 높이에 놓인 평평한 원반인데
--     판정은 3D 거리였다. map2 는 반경 44 안 지면 기복이 45~112 stud 라
--     원반이 지형을 뚫고 지나가고, 높이차가 3D 거리를 부풀려 원 안이 죽었다.
--     (실측: 원 가장자리에 29stud 높이차 → 3D 53 → 반경 44 초과로 미적중)
--   [해결] 수평거리로만 반경을 재고, 높이는 별도 밴드로 자른다.
--     "바닥에 그려진 원 안 + 그 근처 높이면 맞는다" — 표시와 규칙이 일치한다.
--   ⚠️ 35 의 근거는 실측이다. 걸을 수 있는 지면은 map2 −17~+29 / map1 −14~+20 이라
--     전부 포함되고, 성벽 위(+95)와 태거베이스 내부(−70)는 빠진다.
--   ⚠️ 밴드를 없애면 안 된다. 책 타깃(X 725)이 taggerbase2(X 711~861) 위에 걸쳐 있어,
--     높이를 안 보면 성 내부·아래까지 관통한다("베이스는 푸시툴로만" 원칙 위반).
--   ⚠️ CannonSystem 에 같은 처리가 있다. 곡사포는 이 무기의 스킨이라 판정이 같아야 한다.
local BLAST_HEIGHT  = 35      -- 착탄점 기준 위아래 유효 높이(stud)
local BLAST_DAMAGE  = 38
local BLAST_FALLOFF = 0.75
local FLIGHT_TIME   = 1.2
local WARN_BLINK_AT = 0.45
local RISE_TIME     = 0.35    -- 책에서 하늘로 올라가는 시간

-- 🔊 [2026-08-29] 마법책 전용 사운드로 교체. 이전엔 곡사포 것을 그대로 썼다.
--   [왜] 둘 다 2단계 고정 기물이라 같은 자리에서 발동한다. 소리가 같으면
--     러너가 무엇이 오는지 귀로 구분할 수 없다.
--   ⚠️ 볼륨은 SfxGroupBinder 가 SFXGroup 으로 묶어 일괄 조절한다. 여기선 상대값만 잡는다.
local SFX_FIRE   = "rbxassetid://115361160519930"   -- 시전
local SFX_IMPACT = "rbxassetid://140491618332570"   -- 착탄
-- 🔔 경고음은 베어트랩(TrapSystem.SND_WARNING)과 공유한다.
--   [왜] 이미 "위험이 온다"는 의미로 학습된 소리다. 새 소리를 만들면
--     유저가 다시 배워야 하고, 경고는 즉시 알아들어야 하는 정보다.
--   ⚠️ map1 곡사포도 같은 소리를 쓴다(CannonSystem). 세 곳이 한 소리를 공유하므로
--     바꿀 거면 셋을 같이 볼 것.
local SFX_WARN   = "rbxassetid://16903690359"
local VOL_FIRE, VOL_IMPACT = 0.7, 2.2
local VOL_WARN   = 1.0
local RANGE_FIRE, RANGE_IMPACT = 120, 320
local RANGE_WARN = 200

-- 부유 연출
local FLOAT_AMP   = 1.2       -- 위아래 진폭
local FLOAT_SPEED = 1.6
local SPIN_SPEED  = 22        -- 초당 회전(도)

local function ensureRemote(name)
    local e = ReplicatedStorage:FindFirstChild(name)
    if not e then
        e = Instance.new("RemoteEvent")
        e.Name = name
        e.Parent = ReplicatedStorage
    end
    return e
end
local stateEvent = ensureRemote("CannonState")   -- 곡사포와 공유 (클라 표시 재사용)
local warnEvent  = ensureRemote("CannonWarn")

local books = {}   -- [model] = { cooldownUntil }
-- 🤖 [2026-08-29] 책별 시전 함수. 봇 킹이 프롬프트 없이 쓰기 위한 통로.
--   ⚠️ 약한 참조 — 책은 성문 붕괴 때 Destroy 된다.
local bookCastFns = setmetatable({}, { __mode = "k" })

-- 🗺️ [ACTIVEMAP-BOOKS 2026-08-27] 활성 맵의 책만 반환한다.
--   [증상] map1 라운드인데 "📖 2단계 — 마법책 사용 가능" 이 뜨고 책은 안 보였다.
--   [원인] workspace 전체를 훑어서, 비활성 맵(map2)에 있는 책 3개를 항상 반환했다.
--     map1 에는 MagicBook 이 하나도 없는데 시스템은 "3개 있다"고 믿은 것.
--   ⚠️ CaptureSystem 이 2026-08-23 에 같은 실패를 겪었다("항상 map1 존이 반환됐다").
--     해결도 같다 — RoundSystem 이 SetCurrentMap 으로 알려주는 활성 맵에서만 찾는다.
--   ⚠️ 활성 맵에 책이 없으면 빈 목록을 돌려준다. 그게 정상이다(map1 은 곡사포만 쓴다).
--     책이 없으면 사용 가능 안내도 뜨지 않아야 하므로, 호출부에서 #list 를 볼 것.
local activeMapFolder = nil
do
	local ev = game:GetService("ReplicatedStorage"):FindFirstChild("SetCurrentMap")
	if ev and ev:IsA("BindableEvent") then
		ev.Event:Connect(function(folder) activeMapFolder = folder end)
	end
end

local function findBooks()
	local list = {}
	-- 1순위: 활성 맵 (정확)
	if activeMapFolder and activeMapFolder.Parent then
		for _, d in ipairs(activeMapFolder:GetChildren()) do
			if d:IsA("Model") and d.Name == "MagicBook" then list[#list + 1] = d end
		end
		return list
	end
	-- 2순위: 책을 가진 맵이 '하나뿐' 이면 그것 (맵 스왑이 켜진 경우)
	local byMap = {}
	for _, mapFolder in ipairs(workspace:GetChildren()) do
		if mapFolder:IsA("Folder") or mapFolder:IsA("Model") then
			local found = {}
			for _, d in ipairs(mapFolder:GetChildren()) do
				if d:IsA("Model") and d.Name == "MagicBook" then found[#found + 1] = d end
			end
			if #found > 0 then byMap[#byMap + 1] = found end
		end
	end
	if #byMap == 1 then return byMap[1] end
	if #byMap > 1 then
		warn("[MagicBook] 책을 가진 맵이 " .. #byMap .. "개 — 활성 맵을 특정하지 못했다")
		return byMap[1]
	end
	return list
end

local function getCore(b) return b.PrimaryPart end

local function getTarget(book)
    local tx = book:GetAttribute("TargetX")
    local tz = book:GetAttribute("TargetZ")
    if not tx or not tz then return nil end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { book }
    local hit = workspace:Raycast(Vector3.new(tx, 400, tz), Vector3.new(0, -500, 0), params)
    local y = hit and hit.Position.Y or 130
    return Vector3.new(tx, y, tz)
end

local function setGlow(book, on)
    local core = getCore(book)
    if not core then return end
    for _, d in ipairs(core:GetDescendants()) do
        if d:IsA("ParticleEmitter") then d.Rate = on and 400 or 150 end
    end
    for _, d in ipairs(book:GetDescendants()) do
        if d:IsA("ParticleEmitter") then d.Rate = on and 400 or 150 end
    end
end

local function playAt(pos, id, volume, range)
    local p = Instance.new("Part")
    p.Anchored = true ; p.CanCollide = false ; p.CanQuery = false
    p.CanTouch = false ; p.Transparency = 1
    p.Size = Vector3.new(1, 1, 1)
    p.CFrame = CFrame.new(pos)
    p.Parent = workspace
    local snd = Instance.new("Sound")
    snd.SoundId = id ; snd.Volume = volume
    snd.RollOffMaxDistance = range
    snd.RollOffMode = Enum.RollOffMode.InverseTapered
    snd.Parent = p
    snd:Play()
    Debris:AddItem(p, 6)
end

-- ── 착탄 ───────────────────────────────────────────────────────
local function damageAt(pos)
    -- 🏰 [2026-08-28] 마법책은 '공성 방어' 무기다 — 태거 베이스 면역을 두지 않는다.
    --   ⚠️ 여기에 isInTaggerBase / _G.IsCharInTaggerBase 를 추가하지 말 것.
    --     "다른 태거 아이템엔 다 있는데 여기만 없다"고 보이지만 의도된 예외다.
    --   [근거] 착탄점이 애초에 베이스 안이다. 실측 2026-08-28:
    --     · 마법책 TargetX = 725, 착탄 지면이 map2 castle.taggerbase2 (Y 129.9) 로 찍힌다
    --     · 2단계 러너는 성문(X≈731)을 때리므로 역시 베이스 위에 서 있다
    --     → 면역을 걸면 모든 착탄이 무효가 되어 무기가 통째로 죽는다.
    --   [왜 다른 아이템은 면역이 있나] 프드·폭탄·에너지볼·데몬스피어는 '들판에 던지는'
    --     아이템이라, 베이스까지 반경이 닿는 게 사고다. 마법책·곡사포는 반대로
    --     베이스(성문 앞)를 때리는 게 존재 이유다. 규칙이 아니라 역할이 다르다.
    --   ⚠️ CannonSystem 에 같은 주석이 있다. 곡사포는 이 무기의 스킨이므로
    --     한쪽만 바꾸면 반드시 갈라진다.
    local function hurt(char)
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end
        if char:GetAttribute("Downed") then return end
        -- 수평거리로 반경 판정 + 높이는 밴드로 컷 (원기둥). 상수 선언부 주석 참조.
        local off = hrp.Position - pos
        local d = Vector2.new(off.X, off.Z).Magnitude
        if d <= BLAST_RADIUS and math.abs(off.Y) <= BLAST_HEIGHT then
            local dmg = BLAST_DAMAGE * (1 - (d / BLAST_RADIUS) * BLAST_FALLOFF)
            hum:TakeDamage(dmg)
            -- 🚧 [진단 2026-08-26] 데미지 출처 추적.
            --   [왜] 마법책은 발사·명중을 아무것도 안 남겨서, 러너가 어디서
            --   맞고 죽었는지 로그로 재구성할 수 없었다. 실제로 푸시툴 딜만
            --   합산하고 나머지를 불기둥으로 오인하는 일이 있었다.
            --   [Duel] 과 같은 형식으로 맞춰 한 판의 딜을 전부 추적 가능하게 한다.
            warn(string.format("[MagicBook] 명중 → %s (dmg %.1f / 거리 %.0f)",
                char.Name, dmg, d))
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr:GetAttribute("Role") == "Runner" and plr.Character then hurt(plr.Character) end
    end
    for _, mdl in ipairs(workspace:GetChildren()) do
        if mdl:IsA("Model") and mdl.Name:match("^AIRunner") then hurt(mdl) end
    end
end

local function detonate(pos)
    local fx = Instance.new("Explosion")
    fx.Position = pos
    fx.BlastRadius = BLAST_RADIUS
    fx.BlastPressure = 0
    fx.DestroyJointRadiusPercent = 0
    fx.ExplosionType = Enum.ExplosionType.NoCraters
    fx.Parent = workspace
    Debris:AddItem(fx, 3)
    playAt(pos, SFX_IMPACT, VOL_IMPACT, RANGE_IMPACT)
    damageAt(pos)
end

-- 📖 책의 불꽃에서 불덩이가 솟아 포물선을 그리며 목표로 낙하
--
-- ⚠️ 시작점은 반드시 책의 불꽃(core)이다. 다른 데서 나오면 "책이 쐈다"가 안 읽힌다.
--
-- ⚠️ [2026-08-27] 예전엔 "수직 상승(RISE_TIME) → 하늘에서 수평 이동" 2단계였다.
--   [왜 바꿨나] 궤적이 두 토막이라 눈으로 쫓아도 착탄점을 예측할 수 없었다.
--     러너가 피할 단서가 바닥 원 '하나뿐' 이라, 원이 부정확하면 회피가 성립하지 않았다.
--   [지금] 한 번의 포물선. 솟는 느낌은 발사각으로 유지한다.
--   ⚠️ 총 비행시간은 RISE_TIME + FLIGHT_TIME 그대로다. 경고원이 이 합으로 점멸
--     타이밍을 맞추므로(아래 warnEvent), 한쪽만 바꾸면 예고와 착탄이 어긋난다.
--
-- ⚠️ ARC_HEIGHT 는 발사각을 결정한다. 책→목표 수평거리가 55 stud 로 짧아서
--   호를 높일수록 수직에 가까워지고 횡이동 단서가 사라진다(실측):
--     95 → 82°(거의 수직)  /  45 → 74°  /  25 → 61°(던진 느낌)
--   곡사포와 구분되어야 하므로 너무 낮추지 말 것 — 책은 '높이 치솟는 호' 다.
local ARC_HEIGHT = 45

local function castFlame(book, targetPos)
    local core = getCore(book)
    if not core then return end
    local startPos = core.Position

    warnEvent:FireAllClients(targetPos, RISE_TIME + FLIGHT_TIME, BLAST_RADIUS, WARN_BLINK_AT)
    playAt(startPos, SFX_FIRE, VOL_FIRE, RANGE_FIRE)
    -- 🔔 경고음은 '착탄 지점'에서 낸다. 시전 지점(책)에서 내면 어디로 떨어지는지
    --    귀로 알 수 없다 — 경고의 목적은 위치 전달이다.
    --    ⚠️ 시각 경고 원(warnEvent)과 같은 좌표를 쓴다. 둘이 어긋나면 더 헷갈린다.
    playAt(targetPos, SFX_WARN, VOL_WARN, RANGE_WARN)

    local orb = Instance.new("Part")
    orb.Name = "_FlameOrb"
    orb.Shape = Enum.PartType.Ball
    orb.Size = Vector3.new(4, 4, 4)
    orb.Color = Color3.fromRGB(255, 150, 40)
    orb.Material = Enum.Material.Neon
    orb.Anchored = true
    orb.CanCollide = false
    orb.CanQuery = false
    orb.CFrame = CFrame.new(startPos)
    orb.Parent = workspace
    Debris:AddItem(orb, RISE_TIME + FLIGHT_TIME + 1)

    -- 마법책의 파티클을 그대로 가져다 붙인다 (연출 재활용)
    for _, d in ipairs(book:GetDescendants()) do
        if d:IsA("ParticleEmitter") then
            local c = d:Clone()
            c.Rate = 300
            c.Parent = orb
            break
        end
    end
    local lt = Instance.new("PointLight")
    lt.Color = Color3.fromRGB(255, 160, 60)
    lt.Range = 26 ; lt.Brightness = 3
    lt.Parent = orb

    task.spawn(function()
        -- 책 → 목표, 한 번의 포물선. 최고점은 두 점을 잇는 직선 기준 ARC_HEIGHT.
        --   4a(1-a) 는 a=0/1 에서 0, a=0.5 에서 1 인 포물선 계수다.
        local FLY = RISE_TIME + FLIGHT_TIME
        local t0 = os.clock()
        while true do
            local a = math.min((os.clock() - t0) / FLY, 1)
            if not orb.Parent then return end
            local flat = startPos:Lerp(targetPos, a)
            orb.CFrame = CFrame.new(flat + Vector3.new(0, ARC_HEIGHT * 4 * a * (1 - a), 0))
            if a >= 1 then break end
            RunService.Heartbeat:Wait()
        end
        orb:Destroy()
        detonate(targetPos)
    end)
end

-- ── 프롬프트 ───────────────────────────────────────────────────
local attachPrompt
function attachPrompt(book)
    local core = getCore(book)
    if not core then return end
    local old = core:FindFirstChildOfClass("ProximityPrompt")
    if old then old:Destroy() end

    local p = Instance.new("ProximityPrompt")
    p.Name = "CannonPrompt"      -- ⚠️ CannonPromptFilter 가 이 이름으로 러너에게 숨긴다
    p.ActionText = "시전"
    p.ObjectText = "마법책"
    p.KeyboardKeyCode = Enum.KeyCode.E
    p.HoldDuration = CHARGE_TIME
    p.MaxActivationDistance = USE_RANGE
    p.RequiresLineOfSight = false
    p.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
    p.Parent = core

    p.PromptButtonHoldBegan:Connect(function(player)
        if player:GetAttribute("Role") ~= "Tagger" then return end
        setGlow(book, true)
        book:SetAttribute("CannonCharging", true)
        stateEvent:FireClient(player, "charging", CHARGE_TIME, getTarget(book))
    end)

    p.PromptButtonHoldEnded:Connect(function(player)
        setGlow(book, false)
        book:SetAttribute("CannonCharging", nil)
        stateEvent:FireClient(player, "cancel")
    end)

    -- 발사 본체. 프롬프트(유저)와 봇이 함께 쓴다.
    -- 🤖 [2026-08-29] CannonSystem.doFire 와 같은 구조다. 한쪽만 고치지 말 것.
    --   봇 킹은 Player 인스턴스가 아니라 pseudoPlayer 테이블이라
    --   ProximityPrompt.Triggered 를 탈 수 없다.
    -- ⏳ botTelegraph=true 면 글로우를 먼저 켜고 BOT_TELEGRAPH 뒤에 시전한다.
    --   유저의 홀드 차징이 하던 예고 역할을 대신한다(곡사포와 동일한 이유).
    local function doCast(player, botTelegraph)
        local st = books[book]
        if st and os.clock() < (st.cooldownUntil or 0) then
            if player and typeof(player) == "Instance" and player:IsA("Player") then
                stateEvent:FireClient(player, "cooldown", st.cooldownUntil - os.clock())
            end
            return false
        end

        local target = getTarget(book)
        if not target then return false end

        books[book] = books[book] or {}
        books[book].cooldownUntil = os.clock() + COOLDOWN + (botTelegraph and BOT_TELEGRAPH or 0)
        book:SetAttribute("CannonReadyAt", os.time() + COOLDOWN)
        p.Enabled = false

        local function cast()
            if not book.Parent then return end
            setGlow(book, false)
            -- ⚠️ 표적을 다시 읽는다. 예고를 보고 피한 러너가 실제로 살아남아야 한다.
            castFlame(book, getTarget(book) or target)
            task.delay(COOLDOWN, function()
                if book and book.Parent then
                    book:SetAttribute("CannonReadyAt", nil)
                    p.Enabled = true
                end
            end)
        end

        if botTelegraph then
            setGlow(book, true)   -- 예고: 책이 빛난다
            task.delay(BOT_TELEGRAPH, cast)
        else
            cast()
        end
        return true
    end
    bookCastFns[book] = doCast

    p.Triggered:Connect(function(player)
        if player:GetAttribute("Role") ~= "Tagger" then return end
        local char = player.Character
        if not char or char:GetAttribute("Downed") then return end
        doCast(player)
    end)
end

-- ── 2단계 전용 표시 ────────────────────────────────────────────
local DIM_TRANSPARENCY = 0.7

local function setBookVisible(book, on)
    -- 🔍 [2026-08-27 정정] 1단계에도 '반투명으로 보인다'. 완전히 숨기지 않는다.
    --   [왜] 곡사포(CannonSystem.setCannonVisible)가 이미 그렇게 한다 —
    --     1단계 내내 DIM_TRANSPARENCY 로 흐릿하게 보이다가 2단계에 또렷해진다.
    --     아예 안 보이다 튀어나오면 "갑툭튀" 가 되어 러너가 대비할 수 없다.
    --   ⚠️ 앞서 한 번 완전 숨김(Transparency=1)으로 바꿨다가 되돌렸다.
    --     그때 노린 건 '불꽃이 1단계에 보이는 것' 이었는데, 그건 파트가 아니라
    --     ParticleEmitter 문제였다. 파트는 곡사포와 같이 반투명을 유지한다.
    for _, d in ipairs(book:GetDescendants()) do
        if d:IsA("BasePart") then
            local orig = d:GetAttribute("_BookOrigTransparency")
            if orig == nil then
                orig = d.Transparency
                d:SetAttribute("_BookOrigTransparency", orig)
            end
            -- ⚠️ 원래 투명(1)한 파트는 그대로 둔다 — Handle(프롬프트 앵커),
            --    Part(이미터 부모)는 보이면 안 되는 보조 파트다.
            if orig >= 1 then
                d.Transparency = orig
            else
                d.Transparency = on and orig or DIM_TRANSPARENCY
            end
        elseif d:IsA("ParticleEmitter") then
            -- 🔥 불꽃은 2단계에만. 파트는 흐릿하게 보이더라도 이펙트가 돌면
            --    "이미 작동 중" 으로 읽혀 혼란스럽다.
            d.Enabled = on
        elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
            -- ⚠️ 조명도 이펙트와 함께. 파트를 흐리게 해도 빛은 그대로 남아 바닥이 물든다.
            d.Enabled = on
        end
    end

    -- 🚫 [2026-08-27 복구] 2단계에만 사용 가능. 프롬프트를 함께 토글한다.
    --   [증상] 1단계에서 반투명하게 보이는데 E 를 눌러 '사용' 까지 됐다.
    --   [원인] setBookVisible 을 다시 쓰면서 원래 있던 프롬프트 제어 줄을 날렸다.
    --     파트 투명도만 바꾸고 ProximityPrompt 는 계속 켜져 있었던 것.
    --   ⚠️ CannonSystem.setCannonVisible 도 같은 자리에서 p.Enabled = on 을 한다.
    --     "보이는 것" 과 "쓸 수 있는 것" 은 반드시 같은 함수에서 같이 토글할 것 —
    --     따로 두면 이번처럼 한쪽만 빠진다.
    local core = getCore(book)
    local p = core and core:FindFirstChild("CannonPrompt")
    if p then p.Enabled = on end

end

local function setAllVisible(on)
    for _, b in ipairs(findBooks()) do setBookVisible(b, on) end
end

-- ═══════════════════════════════════════════════════════════
-- 📖 성문 파괴 시 마법책도 함께 무너진다. BarricadeSystem 이 호출한다.
--
-- ⚠️ [버그 수정 2026-08-26] 이 훅이 누락돼 있었다.
--   마법책은 곡사포와 같은 무기이고 스킨만 다르다. 그런데 성문 붕괴
--   훅(_G.CannonOnGateDestroyed)이 곡사포에만 걸려 있어서,
--   성문이 무너진 뒤에도 마법책만 살아남아 계속 발사됐다.
--   (실측 10:14 판: 성문 붕괴 10:14:06 → AIRunner_9 이 10:14:23 까지
--    푸시툴로 61.2 만 맞고 죽음. 나머지 38.8 ≈ BLAST_DAMAGE 38.)
--   → 곡사포는 사라지는데 마법책은 남는 비대칭이 밸런스를 조용히 흔들었다.
--
-- ⚠️ 데미지는 주지 않는다. 태거가 자기 포대 폭발에 죽으면 이상하다.
--   (CannonSystem.destroyCannons 와 같은 규약)
-- ═══════════════════════════════════════════════════════════
-- 💾 [2026-08-27] 원본 백업/복원 — 성문과 함께 파괴되므로 복원 자료가 필요하다.
--   [증상] 첫 판에서 성문이 무너지면 마법책이 영구 소멸해, 두 번째 판부터 안 보였다.
--   [원인] destroyBooks 가 b:Destroy() 만 하고 복원이 없었다.
--     CannonSystem 은 backupCannons/restoreCannons 로 이미 같은 문제를 풀고 있다
--     — 마법책이 그 패턴을 따라가지 못했다(2026-08-26 파괴 훅만 추가된 상태).
--   ⚠️ 부팅 시 1회 백업하고, 라운드 시작마다 복원한다.
--     복원을 '라운드 시작' 에 두는 이유: 파괴 시점에 되살리면 폭발 연출과 겹친다.
local ServerStorage = game:GetService("ServerStorage")
local bookBackups = {}   -- { clone = Model, parent = Instance, cframe = CFrame }

local function backupBooks()
	local folder = ServerStorage:FindFirstChild("_MagicBookBackups")
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "_MagicBookBackups"
	folder.Parent = ServerStorage

	bookBackups = {}
	for _, b in ipairs(findBooks()) do
		local clone = b:Clone()
		clone.Parent = folder
		bookBackups[#bookBackups + 1] = {
			clone  = clone,
			parent = b.Parent,
			cframe = b:GetPivot(),
		}
	end
	print(("💾 [MagicBook] 원본 백업 %d개"):format(#bookBackups))
end

local function restoreBooks()
	if #bookBackups == 0 then return end
	-- 이미 살아 있으면 복원하지 않는다(중복 생성 방지).
	-- 🐛 [버그수정 2026-09-09] 가드를 '활성 맵'이 아니라 '복원 대상 부모'로 옮긴다.
	--   [증상] 사용자 제보 — "레디 상태가 아닌데 E 차징만 하면 무한 발사".
	--   [실측] 라운드마다 책이 3개씩 늘었다:
	--       23:52 map2 라운드  사용 가능 3개
	--       23:55 map1 라운드  ♻️ 복원 3개   ← map1 엔 책이 없어 가드가 뚫림
	--       23:56 map1        ♻️ 복원 3개
	--       23:59 map1        ♻️ 복원 3개
	--       00:01 map2 라운드  사용 가능 12개  (3 + 3×3)
	--   [원인] findBooks() 는 ACTIVEMAP-BOOKS(2026-08-27) 이후 '활성 맵'만 본다.
	--     그런데 복원은 e.parent, 즉 '원래 맵'으로 넣는다. 두 기준이 다르다.
	--     map1 라운드에서 findBooks() 가 0 을 반환 → 가드 통과 → 클론은 map2 에 쌓인다.
	--   [무한 발사가 되는 이유] 쿨(COOLDOWN 6.0)은 책 '개별'로 관리된다(books[book]).
	--     12권이면 서로 다른 책이 번갈아 발사돼 실효 간격이 6/12 = 0.5초가 된다.
	--     실측 명중 간격 2.6~3.0초가 이것과 맞는다(9권 기준).
	--   [해결] 복원 대상 부모에 이미 책이 있으면 그 항목만 건너뛴다.
	--     맵 단위로 판정하므로 어느 맵에서 라운드를 돌든 누적되지 않는다.
	--   ⚠️ CannonSystem.restoreCannons 도 같은 구조인지 확인할 것 —
	--     "둘은 한 짝이다"(523행 주석). 곡사포는 복원 로그가 항상 '4대'라 아직 미확인.
	--   ⚠️ 판정은 루프 '전에' 끝낸다. 3권이 같은 부모라, 루프 안에서 매번 검사하면
	--     첫 권을 넣는 순간 부모에 책이 생겨 나머지 2권이 스킵된다(복원 1개).
	local function parentHasBook(parent)
		for _, d in ipairs(parent:GetChildren()) do
			if d:IsA("Model") and d.Name == "MagicBook" then return true end
		end
		return false
	end
	local skipParent = {}   -- [parent] = true 면 이미 살아 있으므로 복원 안 함
	for _, e in ipairs(bookBackups) do
		if e.parent and e.parent.Parent and skipParent[e.parent] == nil then
			skipParent[e.parent] = parentHasBook(e.parent)
		end
	end
	local n = 0
	for _, e in ipairs(bookBackups) do
		if e.parent and e.parent.Parent and not skipParent[e.parent] then
			local c = e.clone:Clone()
			c:PivotTo(e.cframe)
			c.Parent = e.parent
			-- 🔌 [2026-08-27] 프롬프트를 다시 건다.
			--   [증상] 성문 붕괴로 책이 파괴된 '다음' 라운드에서, E 홀드 게이지는
			--     차오르는데 발사가 안 됐다.
			--     (실측 00:57:30 복원 → 00:58 라운드 명중 0건. 복원 전 두 판은 정상)
			--   [원인] attachPrompt 는 부팅 루프(506행)에서 한 번만 돈다. 복원본은
			--     클론이라 ProximityPrompt '인스턴스' 는 딸려오지만
			--     PromptButtonHoldBegan 서버 '연결' 은 복제되지 않는다.
			--     → UI 는 멀쩡한데 듣는 쪽이 없어 아무 일도 일어나지 않는다.
			--   ⚠️ 키 바인딩(E) 충돌이 아니다. 충돌이면 게이지 자체가 안 찬다.
			--   ⚠️ CannonSystem.restoreCannons(281행)는 이미 같은 처리를 한다.
			--     둘은 한 짝이다 — 한쪽만 고치면 다시 어긋난다.
			attachPrompt(c)
			-- ⚠️ attachPrompt 는 프롬프트를 새로 만들고 Enabled 기본값은 true 다.
			--   여기서 끄지 않으면 1단계부터 시전이 가능해진다(348행 주석의 그 버그).
			--   2단계 감시 루프가 때가 되면 켜준다.
			setBookVisible(c, false)
			c:SetAttribute("CannonReadyAt", nil)
			c:SetAttribute("CannonCharging", nil)
			n = n + 1
		end
	end
	if n > 0 then print(("♻️ [MagicBook] 복원 %d개"):format(n)) end
end

local function destroyBooks()
    local list = findBooks()
    if #list == 0 then return end
    for _, b in ipairs(list) do
        local core = getCore(b)
        local pos = core and core.Position or b:GetPivot().Position
        local fx = Instance.new("Explosion")
        fx.Position = pos
        fx.BlastRadius = 18
        fx.BlastPressure = 0
        fx.DestroyJointRadiusPercent = 0
        fx.ExplosionType = Enum.ExplosionType.NoCraters
        fx.Parent = workspace
        Debris:AddItem(fx, 3)
        b:Destroy()
    end
    print(string.format("📖 [MagicBook] 성문 붕괴와 함께 %d개 파괴", #list))

    -- ⚠️ [버그 수정 2026-08-26] 조준 원 정리 (CannonSystem 과 같은 사유).
    --   마법책은 곡사포와 CannonState 채널을 공유하므로 같은 신호를 쓴다.
    stateEvent:FireAllClients("cancel")
end

-- 💾 부팅 시 원본 백업. findBooks 가 활성 맵만 보므로, 맵 전환 후에도 한 번 더 뜬다.
task.defer(function()
	task.wait(2)   -- 맵 배치·SetCurrentMap 이후
	backupBooks()
end)

_G.MagicBookOnGateDestroyed = destroyBooks

task.spawn(function()
    local last = nil
    while true do
        task.wait(0.4)
        local ph = ReplicatedStorage:GetAttribute("RoundPhase")
        if ph ~= last then
            last = ph
            -- ♻️ 라운드가 시작되면 먼저 복원한다(지난 라운드에 파괴됐다면 되살린다).
            --   ⚠️ setAllVisible 보다 앞이어야 한다 — 없는 책은 숨길 수도 없다.
            if ph == "stage1" or ph == "stage2" then restoreBooks() end
            setAllVisible(ph == "stage2")
            if ph == "stage2" then
                -- ⚠️ [2026-08-27] 책이 실제로 있을 때만 알린다.
                --   map1 에는 MagicBook 이 없다. 예전엔 workspace 전체를 훑어 map2 의 책을
                --   잡았기 때문에 map1 라운드에서도 "사용 가능" 이 떴고, 정작 화면엔
                --   아무것도 없었다(실측 2회).
                local n = #findBooks()
                if n > 0 then
                    print("📖 [MagicBook] 2단계 — 마법책 사용 가능 (" .. n .. "개)")
                else
                    print("📖 [MagicBook] 이 맵에는 마법책 없음 — 비활성")
                end
            end
        end
    end
end)

-- ── 부유 연출 ──────────────────────────────────────────────────
-- ⚠️ 이게 "장식이 아니다"를 알리는 핵심이다. 움직이지 않으면
--    map2 의 많은 장식(오벨리스크·태양 심볼)과 구분되지 않는다.
-- ⚠️ Heartbeat 로 30fps 갱신. 매 프레임 돌 필요가 없다.
task.spawn(function()
    local acc = 0
    RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < 0.033 then return end
        acc = 0
        local t = os.clock()
        for _, b in ipairs(findBooks()) do
            local core = getCore(b)
            local baseY = b:GetAttribute("FloatBaseY")
            if core and baseY then
                local y = baseY + math.sin(t * FLOAT_SPEED) * FLOAT_AMP
                b:PivotTo(CFrame.new(core.Position.X, y, core.Position.Z)
                    * CFrame.Angles(0, math.rad(t * SPIN_SPEED % 360), 0))
            end
        end
    end)
end)

task.defer(function()
    local list = findBooks()
    for _, b in ipairs(list) do
        attachPrompt(b)
        setBookVisible(b, false)
        b:SetAttribute("CannonReadyAt", nil)
        b:SetAttribute("CannonCharging", nil)
    end
    print(string.format("📖 MagicBookSystem 준비 (%d개, 반경 %d)", #list, BLAST_RADIUS))
end)

-- 🤖 [2026-08-29] 봇 킹용 시전 진입점. _G.FireCannonForBot 과 같은 구조다.
--   ⚠️ 이 맵에 책이 없으면 0 을 돌려준다(map1 은 책이 없다 — "이 맵에는 마법책 없음" 로그).
--     봇 AI 는 반환값이 0 이어도 정상으로 취급해야 한다.
--   ⚠️ [2026-08-29 수정] 곡사포와 같은 이유로 '한 번에 하나만' 시전한다.
--     전부 돌면 3개가 동시 착탄해 회피가 불가능해진다. 무작위 선택으로
--     표적이 한 곳에 고정되는 것도 막는다. 한쪽만 고치지 말 것.
_G.CastMagicBookForBot = function()
    local ready = {}
    for _, b in ipairs(findBooks()) do
        local fn = bookCastFns[b]
        if fn and b.Parent and b:GetAttribute("CannonReadyAt") == nil then
            ready[#ready + 1] = fn
        end
    end
    if #ready == 0 then return 0 end
    local pick = ready[math.random(1, #ready)]
    return pick(nil, true) and 1 or 0   -- ⏳ botTelegraph=true (예고 후 시전)
end
