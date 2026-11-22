-- VIPNametag: VIP 플레이어 머리 위 이름을 금색으로 표시.
-- 기본 이름 숨김(NameDisplayDistance=0) + 골드 BillboardGui (서버 생성 -> 전 클라 복제).
-- IsVIP 속성(PresetManager 세팅)으로 판정. 스폰/토글에 반응.
local Players = game:GetService("Players")

local GOLD = Color3.fromRGB(255, 215, 0)
local DEFAULT_NAME_DIST = 100   -- 비VIP 기본 이름 거리 (Roblox 기본값)

-- [NAMETAG-RACE] VIP 판정이 확정되기 전 기본 닉네임이 잠깐 뜨는 문제.
--   IsVIP 는 PresetManager 가 DataStore 로드 후 비동기로 세팅한다.
--   접속 직후나 리스폰 직후에는 아직 nil 이라, 예전 코드는
--   "VIP 아님"으로 단정하고 기본 닉네임을 명시적으로 켰다(NameDisplayDistance=100).
--   그 뒤 IsVIP=true 가 들어오면 골드 태그가 생기므로, 그 사이 구간에서
--   VIP 유저에게 기본 닉네임이 잠깐 노출된다.
--   ⚠️ 기본 닉네임은 BillboardGui 가 아니라 Humanoid 속성으로 CoreGui 가 그린다.
--      워크스페이스 GUI 를 훑는 진단에는 절대 안 잡히니 주의.
--   ⚠️ 이 수정은 "닉네임 위 검은 자국"의 원인으로 의심해 넣었으나, 진범은
--      아래 TEXTSIZE-FIX(TextScaled 8px 축소)였다. 이 건은 별개의 실제 결함이라 유지.
--   해결: VIP 여부가 확정되기 전에는 아무 것도 켜지 않고 숨긴 채로 둔다.
--         확정된 뒤에만 켜거나 골드 태그를 붙인다.
local function vipState(player)
    local v = player:GetAttribute("IsVIP")
    if v == nil then return nil end        -- 아직 로드 전 — 판단 보류
    return v == true
end

local function applyNametag(player)
	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not head or not hum then return end

	local old = head:FindFirstChild("VIPNametag")
	if old then old:Destroy() end

	local isVip = vipState(player)

	if isVip == nil then
		-- 아직 모름: 기본 닉네임을 켜지 않는다. 켜뒀다가 VIP 로 판명되면 겹친다.
		hum.NameDisplayDistance = 0
		return
	end

	if not isVip then
		hum.NameDisplayDistance = DEFAULT_NAME_DIST   -- 기본 이름 복원
		return
	end

	-- VIP: 기본 이름 숨기고 골드 네임태그
	hum.NameDisplayDistance = 0

	local bb = Instance.new("BillboardGui")
	bb.Name = "VIPNametag"
	-- [TEXTSIZE-FIX] 폭을 넓힌다.
	--   실측 2026-08-20: 200×26 박스에 16글자를 TextScaled 로 밀어넣으니
	--   폰트가 8px 까지 줄어들었다(TextBounds=198×25 로 폭을 꽉 채움).
	--   8px GothamBold 는 글리프가 뭉개지고 검은 외곽선만 남아
	--   "닉네임 위 검은 바코드"처럼 보였다.
	--   ⚠️ UITextSizeConstraint 는 상한만 정한다 — MaxTextSize 로는 축소를 못 막는다.
	--      아래 MinTextSize 와 짝으로 걸어야 한다.
	bb.Size = UDim2.new(0, 320, 0, 32)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 100
	bb.Adornee = head
	bb.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = player.DisplayName
	lbl.TextColor3 = GOLD
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	-- [TEXTSIZE-FIX] TextScaled 는 TextWrapped 를 자동으로 켠다(실측 Wrapped=true).
	--   MinTextSize 하한에 걸린 긴 닉네임이 두 줄로 접혀 박스 밖으로 잘리므로
	--   한 줄 유지로 강제한다. 넘치면 잘리되 글자 모양은 살아있다.
	lbl.TextWrapped = false
	lbl.TextStrokeTransparency = 0.4
	lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lbl.Parent = bb

	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = 20
	-- [TEXTSIZE-FIX] 하한을 건다. 이게 없으면 긴 닉네임에서 폰트가 한없이 줄어
	--   글자가 뭉개진다. 14px 아래로는 안 내려가고, 대신 폭이 모자라면
	--   TextWrapped 로 줄바꿈되거나 잘린다 — 뭉개지는 것보다 낫다.
	c.MinTextSize = 16
	c.Parent = lbl
end

local function hookPlayer(player)
	player.CharacterAdded:Connect(function(char)
		-- [NAMETAG-RACE] 새 Humanoid 는 NameDisplayDistance 가 기본값(100)으로 시작한다.
		--   아래 task.wait(0.3) 동안 VIP 유저에게 기본 닉네임이 잠깐 노출된다.
		--   → 기다리기 전에 먼저 숨긴다. 비VIP 면 applyNametag 가 곧바로 되돌린다.
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 3)
		if hum then hum.NameDisplayDistance = 0 end

		task.wait(0.3)   -- 캐릭터/속성 준비 대기
		applyNametag(player)
	end)
	player:GetAttributeChangedSignal("IsVIP"):Connect(function()
		applyNametag(player)
	end)
	if player.Character then applyNametag(player) end
end

Players.PlayerAdded:Connect(hookPlayer)
for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end

print("VIPNametag ready")
