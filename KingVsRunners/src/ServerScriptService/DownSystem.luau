-- DownSystem
-- 러너 다운 상태 관리 모듈
-- 다운된 러너는 10초 동안 기어다닐 수 있고, 발사체에 무적이며,
-- 시간이 만료되면 사망 처리됨.
-- 부활 시스템은 추후 추가 예정.
--
-- 사용법:
--   local DownSystem = require(game.ServerScriptService.DownSystem)
--   DownSystem.triggerDown(character)  -- 다운 시작
--   DownSystem.isDowned(character)     -- 다운 상태 확인
--   DownSystem.clearDown(character)    -- 다운 해제 (부활 시 사용 예정)

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DownSystem = {}

-- SosSystem 연동 (다운 종료 시 SOS 자동 정리)
-- 지연 require로 순환 참조 방지 (SosSystem 초기화 후 사용)
local SosSystem = nil
local function getSosSystem()
    if not SosSystem then
        local ok, mod = pcall(require, game.ServerScriptService:WaitForChild("SosSystem", 5))
        if ok then SosSystem = mod end
    end
    return SosSystem
end

-- ── 설정 ────────────────────────────────────────────────
local DOWN_DURATION       = 10     -- 다운 지속 시간 (초)
local DOWN_WALKSPEED_MULT = 0.25   -- 일반 이동의 25% (느린 기어가기)
local DEFAULT_WALKSPEED   = 16     -- Roblox 기본 WalkSpeed

-- ── 다운 자세 애니메이션 (서버 재생) ─────────────────────
-- ⚠️ 반드시 서버에서 재생해야 한다.
--    이전에는 DownClient(로컬)가 KeyframeSequenceProvider:RegisterKeyframeSequence 로
--    임시 애니메이션을 만들어 재생했는데, 그 임시 에셋은 해당 클라이언트에만 존재해
--    다른 플레이어에게 복제되지 않았다. 반면 Animate 스크립트 비활성화는 인스턴스
--    속성이라 전파되어서, "남의 화면에서만 T포즈"가 되는 버그가 있었다.
--    (Studio 솔로 테스트에는 관찰자가 없어 한 번도 드러나지 않았음)
--    서버 Animator 로 재생하면 모든 클라이언트에 자동 복제된다.
local DOWN_ANIM_IDS = {
    R15 = { Idle = "rbxassetid://139314696142315", Walk = "rbxassetid://122123776991115" },
    R6  = { Idle = "rbxassetid://103837025248844", Walk = "rbxassetid://125507346849648" },
}
-- 위 ID 들의 숫자만 모은 집합 (INTRUDER 워처에서 클라 재생분 제외용)
local DOWN_ANIM_ID_SET = {}
for _, set in pairs(DOWN_ANIM_IDS) do
	for _, id in pairs(set) do
		local n = tostring(id):match("(%d+)")
		if n then DOWN_ANIM_ID_SET[n] = true end
	end
end
local MOVE_EPSILON = 0.1   -- 이 이상 움직이면 Walk 로 전환
local BLEND_TIME   = 0.15  -- Idle <-> Walk 가중치 전환 시간

-- ── 상태 ────────────────────────────────────────────────
local downedCharacters = {}  -- character -> downInfo

-- ── 이벤트 ──────────────────────────────────────────────
local downStateEvent = ReplicatedStorage:WaitForChild("DownStateChanged")

-- ─────────────────────────────────────────────────────────────
-- 다운 자세 애니메이션 시작 (서버 재생 → 전 클라이언트 복제)
-- Idle/Walk 두 트랙을 동시에 재생하고 이동 여부로 가중치를 섞는다.
-- 반환: { idle=track, walk=track, conn=RBXScriptConnection, animate=Script? }
-- ─────────────────────────────────────────────────────────────
local RunService = game:GetService("RunService")

local function startDownAnimation(character, humanoid)
    -- 플레이어 캐릭터는 네트워크 소유자가 클라라서 DownClient 가 자기 트랙을 직접 재생한다.
    -- 서버까지 재생하면 다운 직후 1초 동안 같은 애니가 2벌 겹친다(실측: 클라에 트랙 4개).
    -- Animate 끄기·기존 트랙 정리·진단은 플레이어에게도 그대로 필요하므로 재생만 건너뛴다.
    -- NPC 는 서버가 소유하므로 종전대로 서버가 재생한다.
    local isPlayer = Players:GetPlayerFromCharacter(character) ~= nil
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    -- 기본 Animate 비활성화 (걷기 애니가 다운 자세를 덮어쓰지 않게).
    -- 서버에서 끄면 모든 클라이언트에 전파된다.
    local animateScript = character:FindFirstChild("Animate")
    if animateScript then animateScript.Disabled = true end

    -- 진행 중이던 트랙 정리
    for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
        pcall(function() t:Stop(0) end)
    end

    local set = (humanoid.RigType == Enum.HumanoidRigType.R15)
        and DOWN_ANIM_IDS.R15 or DOWN_ANIM_IDS.R6

    local function load(id, name)
        local anim = Instance.new("Animation")
        anim.AnimationId = id
        local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
        if not ok or not track then
            warn(string.format("[DownSystem] %s 애니메이션 로드 실패 (%s): %s", name, id, tostring(track)))
            return nil
        end
        track.Priority = Enum.AnimationPriority.Action4
        track.Looped = true
        return track
    end

    local idleTrack = load(set.Idle, "Idle")
    local walkTrack = load(set.Walk, "Walk")


    -- 둘 다 실패하면 Animate 를 되돌려 T포즈를 막는다 (최소한 기본 모션은 나오게)
    if not idleTrack and not walkTrack then
        if animateScript then animateScript.Disabled = false end
        warn("[DownSystem] 다운 애니메이션 전부 실패 — 기본 Animate 복구")
        return nil
    end

    if not isPlayer then
    	if idleTrack then idleTrack:Play(0.2, 1.0) end
    	if walkTrack then walkTrack:Play(0.2, 0.0) end
    end

    -- 이벤트 기반 침입 감시: 0.5초 폴링은 짧은 애니(툴 스윙 등)를 놓친다.
    -- 다운 중 제3의 트랙이 재생되는 '순간'을 잡는다.
    do
    	local watchConn
    	local stopped = 0
    	watchConn = animator.AnimationPlayed:Connect(function(track)
    		if track == idleTrack or track == walkTrack then return end
    		-- 플레이어는 클라가 자기 다운 트랙을 재생하고 그게 서버로 복제된다.
    		-- 객체가 달라 위 동일성 비교로는 안 걸리므로 애니 ID 로 제외한다.
    		local rawId = (track.Animation and track.Animation.AnimationId) or ""
    		local nid = tostring(rawId):match("(%d+)")
    		if nid and DOWN_ANIM_ID_SET[nid] then return end
                -- Core / Idle / Movement = 기본 Animate 계열. 다운 중엔 존재하면 안 된다.
                -- 서버에서 Animate.Disabled=true 를 걸어도 클라(LocalScript)까지 복제 지연이 있어,
                -- 그 틈에 시작된 트랙은 기존 정리 루프(다운 시작 시점 스냅샷)가 못 잡는다.
                -- Action4 는 '키를 잡은 관절'만 이기므로 남은 Core 트랙이 비쳐 나와 자세가 깨진다.
                if stopped < 12 then
                	local p = track.Priority
                	if p == Enum.AnimationPriority.Core
                		or p == Enum.AnimationPriority.Idle
                		or p == Enum.AnimationPriority.Movement then
                		stopped = stopped + 1
                		task.defer(function() pcall(function() track:Stop(0) end) end)
                	end
                end
    	end)
    	task.delay(15, function()
    		if watchConn then watchConn:Disconnect(); watchConn = nil end
    	end)
    end

    local conn = RunService.Heartbeat:Connect(function()
        if not (humanoid and humanoid.Parent) then return end
        local moving = humanoid.MoveDirection.Magnitude > MOVE_EPSILON
        if walkTrack then walkTrack:AdjustWeight(moving and 1.0 or 0.0, BLEND_TIME) end
        if idleTrack then idleTrack:AdjustWeight(moving and 0.0 or 1.0, BLEND_TIME) end
    end)

    -- ⚠️ 진단 2: 다운 지속 시간 전체를 감시한다.
    --   1.5초까지는 정상이었으므로(실측), 그 이후 또는 상태 전이에서 깨질 가능성이 크다.
    --   Humanoid 상태 변화(점프/낙하)도 함께 본다 — "점프 시 기본 모션이 튀어나온다"는 제보와 연결.

    return { idle = idleTrack, walk = walkTrack, conn = conn, animate = animateScript }
end

-- 다운 자세 애니메이션 정지 + 기본 Animate 복구
local function stopDownAnimation(animState, fadeTime)
	if not animState then return end
	-- 사망 시엔 0 을 넘긴다. 0.2 초 페이드 동안 다운 자세가 남아
	-- 죽는 연출이 늦어 보였다(NPC 애니 도입 후 드러남).
	local fade = fadeTime or 0.2
    if animState.conn then animState.conn:Disconnect() end
    if animState.idle then pcall(function() animState.idle:Stop(fade) end) end
    if animState.walk then pcall(function() animState.walk:Stop(fade) end) end
    if animState.animate and animState.animate.Parent then
        animState.animate.Disabled = false
    end
end

-- ─────────────────────────────────────────────────────────────
-- 다운 상태 확인
-- ─────────────────────────────────────────────────────────────
function DownSystem.isDowned(character)
    return downedCharacters[character] ~= nil
end

-- ─────────────────────────────────────────────────────────────
-- 캐릭터 부위 충돌 끄기 (발사체 통과시키기)
-- HumanoidRootPart는 이미 CanCollide=false라 건드리지 않음.
-- Torso/UpperTorso/LowerTorso 등 메인 충돌 부위만 끔.
-- 부활 시 복구를 위해 원본 값을 저장.
-- ─────────────────────────────────────────────────────────────
-- 다운 전용 콜리전 그룹: 지형/캐릭터 충돌은 기존 그대로, TaggerItems(굴러오는 아이템)와만 통과.
-- (과거 CanCollide=false 전체 해제는 지면 인식이 깨져 실패 → 그룹 "관계"만 선택 차단하는 방식)
local downedGroupReady = false
local function ensureDownedGroup()
    if downedGroupReady then return end
    downedGroupReady = true
    local PhysicsService = game:GetService("PhysicsService")
    pcall(function() PhysicsService:RegisterCollisionGroup("DownedRunner") end)
    pcall(function()
        -- 기준 그룹(RunnerCharacter)의 관계를 전 그룹에 복사
        for _, g in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
            local collidable = PhysicsService:CollisionGroupsAreCollidable("RunnerCharacter", g.name)
            PhysicsService:CollisionGroupSetCollidable("DownedRunner", g.name, collidable)
        end
        -- 핵심: 태거 아이템은 다운된 몸을 통과 (밀려 내려가기 방지)
        PhysicsService:CollisionGroupSetCollidable("DownedRunner", "TaggerItems", false)
    end)
end

local function setCharacterCollision(character)
    ensureDownedGroup()
    local snapshot = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            snapshot[part] = part.CollisionGroup
            pcall(function() part.CollisionGroup = "DownedRunner" end)
        end
    end
    return snapshot
end

local function restoreCharacterCollision(character, snapshot)
    if not snapshot then return end
    for part, originalGroup in pairs(snapshot) do
        if part and part.Parent then
            pcall(function() part.CollisionGroup = originalGroup end)
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- 다운 트리거
-- 즉사 대신 호출되어 다운 상태로 전환
-- ─────────────────────────────────────────────────────────────
-- 다운 시 관성을 죽일 아이템 (소문자 비교).
--   여기 없는 아이템은 맞는 순간의 관성이 그대로 남는다.
local NO_PUSH_ITEMS = {
	["wood log"] = true,
}

function DownSystem.triggerDown(character, sourceName)
    if not character or not character.Parent then return false end
    if downedCharacters[character] then return false end  -- 이미 다운

    -- ⚠️ [2026-09-08] 로비 훈련 더미는 다운되지 않는다.
    --   [증상] 더미를 죽이면 킬 로그가 뜨고 코인이 지급됐다. 훈련 표적을 잡은 것이
    --     라운드 처치로 집계되면 로그도 보상도 의미를 잃는다.
    --   [추가 증상] ImmortalDummy 가 회복시키면 다시 죽고 또 회복하는 루프에 갇혔다
    --     (실측 12:08:16~24, 2초 간격으로 "데미지 500" 이 반복).
    --   [왜 여기인가] triggerDown 이 다운·사망·킬로그·코인의 공통 진입점이다.
    --     KillLogClient / CoinSystem 을 각각 고치면 세 곳이 되고 한쪽만 고쳐진다.
    --   ⚠️ 더미는 HP 가 줄어드는 것까지는 그대로다 — 데미지 확인이 훈련의 목적이다.
    --     ImmortalDummyController 가 HP 0 을 감지해 회복시키는 경로는 살아 있다.
    if character:GetAttribute("LobbyDummy") then return false end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end

    -- 🔬 [K측정 2026-09-04] 2단계 다운 시각 기록. 킹의 실효 처치 페이스(K).
    --   ⚠️ '사망'이 아니라 '다운'이다. 러너의 DPS 가 사라지는 건 이 시점이고,
    --     킹 생존시간 `T = HP / 받는DPS` 에 들어가는 것도 이 값이다.
    --     사망은 10초 뒤라 전멸 카운트에만 쓰인다(killDowned 쪽에서 따로 센다).
    --   ⚠️ 여기 두는 이유 — 위 두 가드(중복 다운 / 이미 사망)를 통과한 뒤라야
    --     1다운 = 1기록이 보장된다. 함수 진입부에 두면 거부된 호출까지 세게 된다.
    if _G.RoundObs and (_G.RoundObs.stage2At or 0) > 0 then
        _G.RoundObs.s2Downs = _G.RoundObs.s2Downs or {}
        table.insert(_G.RoundObs.s2Downs, {
            t   = os.clock() - _G.RoundObs.stage2At,
            bot = (Players:GetPlayerFromCharacter(character) == nil),
            src = tostring(sourceName or ""),
        })
    end

    -- 🛡️ [ARMOR] 아머 가드는 여기 두면 안 된다 (2026-08-23 실패 기록).
    --   이 함수의 false 반환은 "다운을 취소했다"가 아니라 "이미 다운/사망 상태다"라는
    --   뜻이고, 호출부(ItemDamageSystem:272)가 그걸 보고 폴백 즉사(TakeDamage)를 돌린다.
    --   그래서 여기서 흡수하고 false 를 돌려줬더니 아머가 오히려 러너를 죽였다
    --   (아머 없으면 다운 → 부활 기회, 아머 있으면 즉사).
    --   → 가드는 ItemDamageSystem.processHit 진입부의 무적 체크 옆으로 옮겼다.

    local player = Players:GetPlayerFromCharacter(character)

    -- 다운 정보 기록
    -- WalkSpeed는 부스트(SpeedPotion) 효과 중 다운되면 부스트값으로 백업되는 걸 방지하기 위해
    -- DEFAULT_WALKSPEED를 고정 복원값으로 사용. 다른 부스트 시스템이 추가돼도 안전.
    local downInfo = {
        startTime          = tick(),
        humanoid           = humanoid,
        originalJumpPower  = humanoid.JumpPower,
        originalAutoRotate = humanoid.AutoRotate,
        collisionSnapshot  = nil,
        timer              = nil,
    }
    downedCharacters[character] = downInfo

    -- 캐릭터 속성 (다른 시스템이 참조 가능)
    character:SetAttribute("Downed", true)
    -- 남은 시간 표시용. 클라(SosClient)가 이 값을 읽어 카운트다운을 그린다.
    -- 이벤트가 아니라 속성이라 늦게 들어온/재시작된 클라도 현재 상태를 그대로 읽는다.
    character:SetAttribute("DownEndAt", workspace:GetServerTimeNow() + DOWN_DURATION)

    -- 무장해제: 다운 중 무기 스킬(대시/궁/카운터 등) 사용 원천 차단.
    -- Tool을 손에서 떼고, 다운 동안 재장착 시도도 즉시 해제한다.
    -- 🤖 [2026-09-12] 봇은 예외 — UnequipTools 를 쓰면 무기가 영영 사라진다.
    --   [실측] 히어로봇이 다운→부활하면 갈퀴와 파이어소드가 둘 다 손에서 소멸했다.
    --   [원인] UnequipTools 는 Tool 을 Backpack 으로 옮긴다. 플레이어는 Backpack 이
    --     있어서 복구되지만, 봇은 Player 가 없어 Backpack 자체가 없다 → 갈 곳이 없다.
    --   [해결] 봇은 벗기지 않고 아래 [DOWNLOCK] 의 Enabled=false 만으로 막는다.
    --     무장해제의 목적이 "스킬 사용 차단"이고 그건 Enabled=false 로 이미 달성된다.
    --   ⚠️ 봇에게도 ChildAdded 감시는 안 건다. 벗기지 않으니 재장착 자체가 없다.
    local isBot = (Players:GetPlayerFromCharacter(character) == nil)
    if not isBot then
        pcall(function() humanoid:UnequipTools() end)
        downInfo.toolBlockConn = character.ChildAdded:Connect(function(c)
            if c:IsA("Tool") then
                task.defer(function()
                    if character:GetAttribute("Downed") then
                        pcall(function() humanoid:UnequipTools() end)
                    end
                end)
            end
        end)
    end

    -- [DOWNLOCK] 다운 중 아이템 사용 원천 차단.
    --   위 UnequipTools + ChildAdded 감시만으로는 새는 창이 있다:
    --   백팩에서 다시 꺼내는 순간과 task.defer 로 해제되는 시점 사이에
    --   Tool.Activated 가 이미 나가버린다(실측: 다운 중 Decoy Wand / ODM Gear 발동).
    --   Enabled=false 는 Activated 자체를 막으므로 그 창이 사라진다.
    --
    --   ⚠️ 복구할 때 '전부 켜기'는 금지. ODM Gear 는 발사 후 스스로 Enabled=false 로
    --      잠기는 구간이 있어, 원래 꺼져 있던 것까지 살아난다.
    --      → 내가 끈 것만 기록해두고 clearDown 에서 그것만 되돌린다.
    downInfo.lockedTools = {}
    do
        local function lockTool(t)
            if t:IsA("Tool") and t.Enabled then
                t.Enabled = false
                table.insert(downInfo.lockedTools, t)
            end
        end
        for _, t in ipairs(character:GetChildren()) do lockTool(t) end
        local plr = Players:GetPlayerFromCharacter(character)
        local bp  = plr and plr:FindFirstChildOfClass("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do lockTool(t) end
            -- 다운 중에 새로 들어온 툴도 잠근다
            downInfo.toolAddConn = bp.ChildAdded:Connect(function(t)
                if character:GetAttribute("Downed") then lockTool(t) end
            end)
        end
    end

    -- 이동 제한
    humanoid.WalkSpeed = DEFAULT_WALKSPEED * DOWN_WALKSPEED_MULT
    humanoid.JumpPower = 0  -- 점프 차단

    -- 발사체 통과(시각적): 사용 안 함.
    --   CanCollide=false 로 모든 Part 충돌을 끄면 캐릭터가 바닥과 충돌 안 함 →
    --   Roblox 휴머노이드가 "공중에 떠있는 상태"로 인식하여 WalkSpeed/이동 작동 불가.
    --   대신 ItemDamageSystem.processHit 에서 isDowned 체크로 데미지 무적 처리됨.
    --   시각적으로 통나무가 다운자에 부딪혀 튕기는 것은 부수적 어색함으로 수용.
    downInfo.collisionSnapshot = setCharacterCollision(character)

    -- 통나무는 '넓은 범위'가 강점이므로 다운 시 관성을 죽여 그 자리에 눕힌다.
    --   실측(2026-08): 통나무는 다운된 러너와 충돌하지 않는다(hit=false). 밀림의 정체는
    --   맞는 순간(다운 전) 받은 관성 + 지형 경사였고, 그래서 165 stud ~ 2 stud 로 들쭉날쭉했다.
    if sourceName and NO_PUSH_ITEMS[tostring(sourceName):lower()] then
    	local hrp0 = character:FindFirstChild("HumanoidRootPart")
    	if hrp0 then
    		-- 한 번만 0으로 두면 다음 물리 틱에 경사로 다시 가속되므로 짧게 반복한다.
    		task.spawn(function()
    			for _ = 1, 12 do
    				if not (hrp0.Parent and character:GetAttribute("Downed")) then return end
    				local vy = hrp0.AssemblyLinearVelocity.Y
    				hrp0.AssemblyLinearVelocity = Vector3.new(0, math.min(0, vy), 0)
    				hrp0.AssemblyAngularVelocity = Vector3.zero
    				task.wait(0.05)
    			end
    		end)
    	end
    end
    -- 클라이언트에 알림
    if player then
        downStateEvent:FireClient(player, "downed", DOWN_DURATION)
    end
    -- 다른 클라이언트도 알림 (타인의 다운 시각화 위함)
    downStateEvent:FireAllClients("character_downed", character)

    -- NPC인 경우 서버에서 직접 자세 처리 (DownClient는 LocalPlayer만 처리하므로)
    -- PlatformStand로 쓰러진 자세 만들기 + 위치 약간 떨어뜨림.
    -- NPC 도 애니메이션 우선. 실패하면 기존 PlatformStand 방식으로 폴백한다.
    --   startDownAnimation 은 humanoid.RigType 을 보고 R15/R6 를 알아서 고른다.
    --   애니가 안 붙는데 PlatformStand 까지 빼면 '멀쩡히 서 있는 러너'가 되어
    --   지금보다 나빠지므로, nil 이 오면 반드시 원래 방식으로 되돌린다.
    if not player then
    	local npcAnim = startDownAnimation(character, humanoid)
    	if npcAnim then
    		downInfo.animState = npcAnim
    	else
    		warn("[DownSystem] NPC 다운 애니 실패 → PlatformStand 폴백: " .. character.Name)
    		humanoid.PlatformStand = true
    		humanoid.Sit = false
    		downInfo.npcPlatformStand = true
    	end
    else
        -- 플레이어: 서버에서 다운 자세 애니메이션 재생 → 전 클라이언트에 복제됨.
        -- (DownClient 는 카메라/사운드/타이머 UI 등 로컬 연출만 담당)
        downInfo.animState = startDownAnimation(character, humanoid)
    end

    -- 타이머
    downInfo.timer = task.delay(DOWN_DURATION, function()
        if downedCharacters[character] then
            DownSystem.killDowned(character)
        end
    end)

    print("🩸 다운:", character.Name, "(", DOWN_DURATION, "초)")
    return true
end

-- ─────────────────────────────────────────────────────────────
-- 다운 → 사망 (타이머 만료)
-- ─────────────────────────────────────────────────────────────
function DownSystem.killDowned(character)
    local downInfo = downedCharacters[character]
    if downInfo and downInfo.toolBlockConn then downInfo.toolBlockConn:Disconnect() downInfo.toolBlockConn = nil end
    -- [DOWNLOCK] 사망 경로에서도 연결 해제. 여기선 툴 Enabled 복구를 하지 않는다 —
    --   캐릭터가 사라지고 리스폰 시 백팩이 새로 채워지므로 되돌릴 대상이 없다.
    if downInfo and downInfo.toolAddConn then downInfo.toolAddConn:Disconnect() downInfo.toolAddConn = nil end
    if not downInfo then return end

    -- 🔬 [K측정 2026-09-04] 2단계 사망 카운트. 전멸 승리 판정의 분자다.
    --   ⚠️ 다운 카운트와 별개로 센다. 다운은 러너 DPS 가 사라지는 시점(킹 생존시간 T),
    --     사망은 전멸까지 남은 수가 줄어드는 시점 — 둘 사이에 10초 간격이 있고
    --     그 10초 동안은 "무력화됐지만 아직 전멸이 아닌" 상태다.
    if _G.RoundObs and (_G.RoundObs.stage2At or 0) > 0 then
        _G.RoundObs.s2Deaths = (_G.RoundObs.s2Deaths or 0) + 1
    end

    -- ☠️ [2026-08-27] '의도된 사망' 표식.
    --   [왜] ItemDamageSystem.attachRunnerDownOnZero 가 러너의 HP 0 을 가로채 다운으로
    --     바꾼다. 그런데 이 함수는 Downed 속성을 '먼저 지우고' 그 다음에 Health=0 을 준다.
    --     그 순간 훅이 보기엔 "다운도 아닌데 HP 가 0" 이라 정상 피해로 읽고 다시 다운시킨다.
    --     → 다운 10초 → 사망 → 같은 밀리초에 재다운 → 무한 불사 (실측 2026-08-27 로그).
    --   [해결] 여기서 표식을 세우고, 훅이 이 표식을 보면 개입하지 않는다.
    --   ⚠️ downInfo 확인 '뒤'에 세워야 한다. 조기 반환에 걸린 채 표식만 남으면
    --     그 캐릭터는 영원히 다운되지 못한다(반대 방향 버그).
    --   ⚠️ 되돌리지 않는다 — 이 함수는 항상 사망으로 끝나고, 리스폰하면 새 캐릭터라
    --     속성이 처음부터 없다. 부활(clearDown)에서도 지워 이중 안전.
    character:SetAttribute("_DyingFromDown", true)

    -- 처형: 블리드아웃 순간, 태거 victim-제어 이펙트가 있으면 아직 살아있는 몸에 발동 → 사망 위임
    if _G.ExecuteKillEffect and _G.ExecuteKillEffect(character) then
        stopDownAnimation(downInfo.animState, 0)   -- 사망: 즉시 정지(래그돌로 바로 넘어가게)
        restoreCharacterCollision(character, downInfo.collisionSnapshot)
        downedCharacters[character] = nil
        if character and character.Parent then
        	character:SetAttribute("Downed", nil)
        	character:SetAttribute("DownEndAt", nil)
        end
        local sos = getSosSystem()
        if sos then sos.clearSos(character) end
        print("💀 처형 이펙트 발동 (다운→처형):", character.Name)
        return
    end

    stopDownAnimation(downInfo.animState, 0)   -- 사망: 즉시 정지(래그돌로 바로 넘어가게)
    restoreCharacterCollision(character, downInfo.collisionSnapshot)
    downedCharacters[character] = nil
    if character and character.Parent then
        character:SetAttribute("Downed", nil)
        character:SetAttribute("DownEndAt", nil)
    end

    -- SOS 신호 정리
    local sos = getSosSystem()
    if sos then sos.clearSos(character) end

    -- 충돌 복구 (시체로서 굴러가지 않도록)
    -- → 사실 죽을 거니까 굳이 복구 안 해도 됨

    -- Health=0으로 사망 처리. Humanoid.Died가 자동 발생하여
    -- KillEffectSystem 등 기존 사망 처리 시스템이 작동함.
    if downInfo.humanoid and downInfo.humanoid.Parent then
        downInfo.humanoid.WalkSpeed = 0
        downInfo.humanoid.JumpPower = 0
        -- 사망 시 즉시 무너뜨린다.
        --   다운 애니(Action4)가 자세를 붙잡고 있어 Health=0 만으로는 화면에서 안 쓰러진다.
        --   PlatformStand 시절엔 이미 물리로 누워 있어 안 보이던 차이(NPC 애니 도입 후 드러남).
        --   ⚠️ 여기는 연출형 킬 이펙트가 아닌 '일반 사망' 경로다.
        --     위쪽 _G.ExecuteKillEffect 분기에서 true 면 이미 return 했고,
        --     그 6종(ice/water/coffin/tornado/portal/punch)은 freezeCharacter 로
        --     시체를 직접 소유하므로 여기서 물리를 건드리면 연출이 깨진다.
        downInfo.humanoid.PlatformStand = true
        downInfo.humanoid.Health    = 0
    end
    -- 관절을 명시적으로 끊는다.
    --   BreakJointsOnDeath=true 인데도 자동 파괴가 안 되는 경우가 있다.
    --   실측(2026-08): 사망 +1.0초에도 motor=6 / vel=0 / 트랙 0개 —
    --   애니는 멈췄는데 관절이 남아 마지막 다운 포즈가 그대로 굳었다.
    --   NPC 는 Animate 스크립트가 없어 새 포즈를 덮어쓸 주체가 없기 때문.
    --   (넉백 중 사망한 개체는 motor=0 으로 정상 파괴돼 간헐적으로 보였다)
    --   ⚠️ 플레이어는 제외 — 기본 사망 처리가 이미 정상 동작하므로 건드리지 않는다.
    if not Players:GetPlayerFromCharacter(character) then
    	pcall(function() character:BreakJoints() end)
    end

    local player = Players:GetPlayerFromCharacter(character)
    if player then
        downStateEvent:FireClient(player, "died")
    end
    downStateEvent:FireAllClients("character_died", character)

    print("💀 다운 → 사망:", character.Name)
end

-- ─────────────────────────────────────────────────────────────
-- 데스 타이머 정지 (자연사 막기)
-- 부활 깃발 같은 시스템이 *효과 지속 동안* 자연사를 차단하는 용도.
-- 불꽃벽 같은 외부 데미지로는 여전히 죽을 수 있음 (의도된 동작).
-- 이미 정지된 상태에 다시 호출해도 안전 (멱등성).
-- ─────────────────────────────────────────────────────────────
function DownSystem.cancelDeathTimer(character)
    local downInfo = downedCharacters[character]
    if not downInfo then return false end
    if downInfo.timer then
        task.cancel(downInfo.timer)
        downInfo.timer = nil
    end
    return true
end

-- ─────────────────────────────────────────────────────────────
-- 다운 해제 (부활 시 호출 예정)
-- 부활 시스템 도입 시 이 함수 호출
-- ─────────────────────────────────────────────────────────────
function DownSystem.clearDown(character, reviveRatio)
    local downInfo = downedCharacters[character]
    -- ☠️ 부활했으면 '의도된 사망' 표식을 지운다.
    --   killDowned 가 조기 반환하거나 처형 이펙트가 중간에 끊긴 경우 표식이 남을 수 있고,
    --   그대로 두면 이 캐릭터는 이후 HP 0 에서 다운되지 못하고 즉사한다.
    character:SetAttribute("_DyingFromDown", nil)

    -- 💚 [REVIVE-HEAL 2026-08-27] 부활 시 HP 회복.
    --   [왜] 원인에 따라 부활 후 HP 가 달랐다:
    --     · 태거 아이템 다운 → 아이템은 HP 를 안 깎으므로 풀피로 일어남
    --     · 체력 소진 다운   → ItemDamageSystem 훅이 Health=1 로 살려둔 상태라
    --                          일어서자마자 어떤 피해든 한 방에 다시 다운
    --     같은 '다운'인데 결과가 달라 러너가 예측할 수 없다.
    --   [해결] 원인 불문 같은 비율로 회복. 이 '이유 불문'이 핵심이다 —
    --     원인별 차등은 위 예측 불가 문제를 되살리므로 다시 제안하지 말 것.
    --   ⚠️ 체력 소진 다운은 B 패치(2026-08-27, HP 0 → 다운)로 새로 생긴 경로다.
    --     그 전엔 즉사라 이 상황이 없었다.
    --
    -- ⚖️ [재조정 2026-09-05] 100% → 50%.
    --   [왜] 태거 입장에서 파급력이 과했다. 킹 슬랩 7 / 쿨 1.0s 기준 —
    --     풀피 부활은 슬랩 15타(약 15초)를 통째로 되돌린다.
    --     실측 2단계 평균 K(킹이 러너 하나를 눕히는 시간)가 3.5~15.6초였으니
    --     부활 한 번이 킹의 작업 전체를 무효화하는 셈이었다.
    --   [50% 인 이유] 8타(약 8초)로 절반만 되돌린다. 부활은 여전히 인원을
    --     되살리지만, 되살아난 러너가 곧바로 온전한 전력이 되지는 않는다.
    --   ⚠️ 러너에게는 상시 회복 수단이 없다(전수 확인함). 즉 50% 부활은
    --     "남은 판 내내 반피"를 뜻한다 — 이것이 의도된 대가다.
    --     회복 아이템이 생기면 이 값의 의미가 달라지므로 함께 재검토할 것.
    --   ⚠️ 러너 쪽 비용은 그대로다: 홀드 1.5초 + 판당 1회 + 부활자 무방비.
    --   ⚠️ 되돌릴 값은 1.0.
    --
    -- 🧹 [2026-09-05] 호출처가 셋이라 비율을 인자로 받는다.
    --   · ReviveSystem(팀원 부활) → 인자 없음 = 0.5. 이게 위 밸런스 결정의 대상이다.
    --   · RoundSystem(라운드 종료 정리) → 1.0 을 넘긴다.
    --     ⚠️ 그쪽 주석대로 "로비 이동은 리스폰이 아니라 캐릭터가 유지"된다.
    --       여기서 반피로 두면 다운된 채 라운드가 끝난 러너만 로비에서 반피로 서 있고,
    --       그 상태가 다음 라운드까지 이어진다 — 밸런스가 아니라 잔재 버그다.
    --   · TestCommands(더미 초기화) → 1.0. 테스트 기준선이 흔들리면 안 된다.
    local REVIVE_HP_RATIO = reviveRatio or 0.5
    do
        local hum = character:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            hum.Health = hum.MaxHealth * REVIVE_HP_RATIO
        end
    end    if not downInfo then return end

    if downInfo.timer then
        task.cancel(downInfo.timer)
    end
    if downInfo.toolBlockConn then downInfo.toolBlockConn:Disconnect() downInfo.toolBlockConn = nil end
    -- [DOWNLOCK] 잠갔던 툴 복구 — 내가 끈 것만. 전부 켜면 원래 잠겨 있던 툴까지 살아난다.
    if downInfo.toolAddConn then downInfo.toolAddConn:Disconnect() downInfo.toolAddConn = nil end
    if downInfo.lockedTools then
        for _, t in ipairs(downInfo.lockedTools) do
            if t and t.Parent then t.Enabled = true end
        end
        downInfo.lockedTools = nil
    end

    downedCharacters[character] = nil
    if character and character.Parent then
        character:SetAttribute("Downed", nil)
        character:SetAttribute("DownEndAt", nil)
    end

    -- SOS 신호 정리
    local sos = getSosSystem()
    if sos then sos.clearSos(character) end

    -- 원래 상태 복구.
    -- ⚠️ [REVIVE-BOOST] 예전엔 DEFAULT_WALKSPEED(16) 고정 복원이었다.
    --    "부스트 잔존 차단"이 목적이었으나, 반대 부작용이 있었다:
    --    스피드 포션이 아직 남아 있는데도 16으로 덮여 포션 효과가 사라졌다
    --    (실측 2026-08-22: 포션 중 다운 → 부활하면 남은 시간 동안 손해).
    --    → SpeedBoost 속성을 더해 라이브 재계산한다. 포션이 없으면 0이라 16 그대로다.
    --    ⚠️ RunnerDive.groundSpeed() 와 같은 공식이다. 한쪽만 바꾸면 어긋난다.
    --    ⚠️ '잔존 차단'은 여전히 유효하다 — 속성이 만료되면 0이 되므로
    --       부스트가 끝난 뒤에는 자동으로 16이 된다.
    if downInfo.humanoid and downInfo.humanoid.Parent then
        local boost = character:GetAttribute("SpeedBoost") or 0
        downInfo.humanoid.WalkSpeed  = DEFAULT_WALKSPEED + boost
        downInfo.humanoid.JumpPower  = downInfo.originalJumpPower
        downInfo.humanoid.AutoRotate = downInfo.originalAutoRotate
        -- 🩹 [버그수정 2026-09-01] PlatformStand 무조건 복구 (NPC 조건 제거).
        --   [증상] 강타에 맞고 다운되면, 다운이 풀린 뒤에도 로비에서 자세가 굳었다.
        --     진단 로그: endDown 정상 완주 / Animate.Disabled=false / 다운 트랙 정리 완료 /
        --     기본 idle 재생 중(w1.00) — 그런데 PlatformStand=true 만 계속 남아 있었다.
        --     애니는 도는데 Humanoid 가 안 서니 늘어진 몸으로 보인 것이다.
        --   [원인] PushTool.Server:555 의 래그돌 해제가 `not Downed` 로 가드돼 있다.
        --     다운 중 PlatformStand 를 풀면 다운 연출이 깨지므로 맞는 가드지만,
        --     다운이 끝난 뒤 대신 풀어주는 쪽이 없었다. 여기가 그 자리다.
        --     (실측 18:08:13 — 강타 래그돌 0.4초와 다운이 2 ms 차로 겹쳤다)
        --   ⚠️ NPC 조건을 붙이면 안 된다. 플레이어는 npcPlatformStand 가 nil 이라
        --     예전 코드에선 이 분기 자체를 못 탔다. 그게 버그의 전부였다.
        --   ⚠️ 라운드 종료 전용 문제가 아니다. 팀원 부활(ReviveSystem → clearDown)도
        --     같은 경로라, 강타 맞고 다운된 러너를 살려주면 똑같이 굳었다.
        --     솔로 봇전에선 부활이 안 나서 여태 안 드러났을 뿐이다.
        --   ⚠️ 다른 PlatformStand 소유자(건틀릿/푸시툴 그랩)는 자체 복구가 무조건 실행되므로
        --     여기서 false 로 덮어도 충돌하지 않는다.
        downInfo.humanoid.PlatformStand = false
    end
    stopDownAnimation(downInfo.animState)   -- 부활: 다운 자세 해제 + 기본 Animate 복구
    restoreCharacterCollision(character, downInfo.collisionSnapshot)

    local player = Players:GetPlayerFromCharacter(character)
    if player then
        downStateEvent:FireClient(player, "revived")
    end
    downStateEvent:FireAllClients("character_revived", character)

    print("✨ 다운 해제:", character.Name)
end

-- ─────────────────────────────────────────────────────────────
-- 캐릭터 사망 시 정리 (다른 원인으로 죽었을 때)
-- 예: 라운드 종료 강제 사망, FirePressure 등
-- ─────────────────────────────────────────────────────────────
local function watchCharacter(character)
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum then
        hum = character:WaitForChild("Humanoid", 5)
    end
    if not hum then return end

    hum.Died:Connect(function()
        local downInfo = downedCharacters[character]
        if downInfo then
            if downInfo.timer then
                task.cancel(downInfo.timer)
            end
            downedCharacters[character] = nil
            print("🧹 다운 캐릭터 정리 (외부 사망):", character.Name)
        end
    end)
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(watchCharacter)
end)
-- 이미 접속 중인 플레이어 처리
for _, player in ipairs(Players:GetPlayers()) do
    if player.Character then
        watchCharacter(player.Character)
    end
    player.CharacterAdded:Connect(watchCharacter)
end

print("✅ DownSystem 활성화! (지속:", DOWN_DURATION, "초, 속도:", DOWN_WALKSPEED_MULT * 100, "%)")

-- ☠️ [2026-08-27] 다운자 처형을 외부(PushTool)에서 부를 수 있게 노출.
--   [왜 래핑하나] killDowned 는 타이머 만료(자연사) 경로에서만 불리던 내부 함수다.
--     외부에서 직접 부르면 "다운이 아닌 캐릭터"나 "이미 죽은 캐릭터"에도 돌 수 있어,
--     여기서 가드를 씌워 전용 진입점으로 만든다.
--   ⚠️ killDowned 는 킬이펙트 위임·애니 정지·콜리전 복구를 전부 담당한다.
--     PushTool 에서 Health = 0 만 쓰면 그 정리들이 통째로 빠진다.
--   반환: 실제로 처형했으면 true. 호출부(PushTool)가 false 면 폴백을 탄다.
_G.KillDownedRunner = function(character, killer)
    if not character or not character.Parent then return false end
    if not downedCharacters[character] then return false end   -- 다운 상태가 아니면 거부
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    -- 처형자 기록 — RoundSystem 의 킬 집계가 creator 태그로 가해자를 식별한다.
    if killer then
        local old = hum:FindFirstChild("creator")
        if old then old:Destroy() end
        local c = Instance.new("ObjectValue")
        c.Name = "creator"
        c.Value = killer
        c.Parent = hum
        game:GetService("Debris"):AddItem(c, 2)
    end
    DownSystem.killDowned(character)
    return true
end

return DownSystem
