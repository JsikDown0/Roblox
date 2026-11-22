-- SfxGroupBinder — 모든 효과음을 하나의 SoundGroup 으로 묶는다 (클라이언트)
--
-- 🔊 [2026-08-28] 도입 배경
--   [증상] SFX 전체 음량을 한 번에 줄일 방법이 없었다. 설정에 슬라이더를 넣으려 해도
--     붙일 대상이 아예 없다.
--   [실측] 배치된 Sound 197개 중 SoundGroup 이 지정된 것이 0개(0%).
--     존재하는 그룹은 MusicGroup 하나뿐이고 거기에도 아무 SFX 가 연결돼 있지 않았다.
--   [해결] SFXGroup 을 만들고, '그룹이 없는' Sound 를 자동으로 여기에 붙인다.
--
-- ⚠️ Volume = 1.0 으로 시작한다. SoundGroup 볼륨은 개별 Sound.Volume 에 '곱해지므로'
--    1.0 은 무변화다. 즉 이 스크립트를 넣어도 지금 들리는 소리는 하나도 안 바뀐다.
--    실제 음량 변경은 _G.SetSfxVolume 을 부르는 쪽(설정 UI)이 담당한다.
--
-- ⚠️ 왜 45개 스크립트를 고치지 않고 자동 부착인가
--    사운드 생성 지점이 45개 스크립트 86곳에 흩어져 있다. 전부 고치면 회귀 위험이 크고,
--    앞으로 사운드를 추가할 때마다 또 빠뜨린다(이번 세션에만 "같은 규칙이 두 곳에 있으면
--    한쪽만 고쳐진다" 패턴이 다섯 번 나왔다). 여기서 한 번에 잡으면 신규 사운드도
--    자동으로 포함된다.
--
-- ⚠️ 이미 그룹이 있는 Sound 는 절대 건드리지 않는다.
--    MusicClient 의 MusicGroup, LoadingScreenClient 의 LoadingSfxGroup 이 그렇다.
--    각자 볼륨 정책(음악 0.5, 로딩음 컴프레서+EQ)이 있으므로 뺏어오면 그 설계가 깨진다.
--    ⚠️ 경합 없음: 두 스크립트 모두 Parent 대입 '전에' SoundGroup 을 세팅하므로,
--       DescendantAdded 가 불릴 시점엔 이미 그룹이 박혀 있다.

local Players       = game:GetService("Players")
local SoundService  = game:GetService("SoundService")
local player        = Players.LocalPlayer

local GROUP_NAME  = "SFXGroup"
local START_VOLUME = 1.0   -- ⚠️ 1.0 = 무변화. 도입 시점에 소리가 바뀌면 안 된다.

-- ── 그룹 확보 ────────────────────────────────────────────────
-- ⚠️ FindFirstChild 로 먼저 찾는다. Instance.new 만 하면 리스폰·재실행마다 그룹이
--    쌓여서, 나중에 만든 것에만 볼륨이 걸리고 소리는 예전 그룹으로 나가는 상태가 된다.
--    (MusicClient 가 같은 이유로 FindFirstChild 를 쓴다. LoadingScreenClient 는
--     안 써서 매번 새로 만드는데, 그건 로딩음 1개 전용이라 문제가 안 될 뿐이다)
local sfxGroup = SoundService:FindFirstChild(GROUP_NAME)
if not sfxGroup or not sfxGroup:IsA("SoundGroup") then
	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = GROUP_NAME
	sfxGroup.Volume = START_VOLUME
	sfxGroup.Parent = SoundService
end

-- ── 부착 ────────────────────────────────────────────────────
local bound = 0

local function bind(inst)
	if not inst:IsA("Sound") then return end
	-- ⚠️ 이 nil 검사가 이 스크립트의 안전장치 전부다. 지우면 음악·로딩음까지 빨아들인다.
	if inst.SoundGroup ~= nil then return end
	inst.SoundGroup = sfxGroup
	bound += 1
end

-- ── 감시 대상 ────────────────────────────────────────────────
-- workspace      : 맵·아이템·캐릭터에 붙는 사운드 (대부분)
-- SoundService   : 2D 전역 사운드
-- LocalPlayer    : Backpack 의 도구(PushTool 의 Boom/Smack 등), PlayerGui
--
-- ⚠️ [성능] DescendantAdded 콜백은 파트가 추가될 때마다 불리지만 하는 일은 IsA 하나뿐이다.
--    프드 얼음이 한 번에 ~140파트를 만들어도 IsA 140회 = 무시할 수준.
--    여기에 무거운 로직을 추가하지 말 것 — 그 순간 핫패스가 된다.
local roots = { workspace, SoundService, player }

for _, root in ipairs(roots) do
	for _, d in ipairs(root:GetDescendants()) do
		bind(d)
	end
	root.DescendantAdded:Connect(bind)
end

-- ── 음량 API (설정 UI 가 쓴다) ───────────────────────────────
-- ⚠️ 값은 여기서 저장하지 않는다. 저장·복원은 설정 시스템의 책임이다.
--    부팅 시 저장값을 SetSfxVolume 으로 한 번 불러주면 된다.
local function setSfxVolume(v)
	if type(v) ~= "number" then return end
	sfxGroup.Volume = math.clamp(v, 0, 1)
end

_G.SetSfxVolume = setSfxVolume
_G.GetSfxVolume = function() return sfxGroup.Volume end
_G.GetSfxGroup  = function() return sfxGroup end

print(string.format("🔊 SfxGroupBinder 준비 — %s 에 %d개 부착 (Volume %.2f = 무변화)",
	GROUP_NAME, bound, sfxGroup.Volume))
