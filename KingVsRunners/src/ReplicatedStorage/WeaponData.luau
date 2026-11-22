-- 러너 2단계 근접 무기 단일 소스 (UnifiedInven + ShopSystem 공유).
-- modelName = RunnerItemPreviews 키(=id).
--
-- 📝 [2026-08-29] short/desc 를 실측 기반으로 채웠다. 영문 표기.
--   [원칙] 숫자를 쓰지 않는다. 밸런스 값은 자주 바뀌는데 카드 문구가 따라가지 못하면
--     "설명과 실제가 다르다"가 되어 더 나쁘다. '무엇을 하는 무기인가'만 적는다.
--   [원칙] short 는 한 줄 태그(카드 목록용), desc 는 한두 문장(상세용).
--   [원칙] 각 무기의 '넉백 대응 방식'이 곧 정체성이다 — 킹의 모든 공격에 넉백이
--     달려 있어, 밀려남을 어떻게 다루느냐가 무기를 가른다.
return {
	-- 🔢 [정렬 2026-09-09] 배열 순서 = 등급 오름차순 (Normal → Rare → Epic → Legendary).
	--   [왜] 인벤(UnifiedInvenClient:579)이 이 배열을 그대로 ipairs 로 그린다.
	--     정렬 코드가 없어서 여기 순서가 곧 화면 순서였고, 등급이 뒤죽박죽으로 보였다.
	--   ⚠️ 이 배열을 순회하는 곳이 넷이다 — 순서를 바꾸면 전부 같이 바뀐다:
	--       UnifiedInvenClient  인벤 Weapon 탭 카드 순서
	--       ShopSystem:172      상점 runner 카테고리 편입 순서
	--       WeaponTrialClient   무기 체험장 진열 순서
	--       WeaponTrialSystem   화이트리스트 (순서 무관)
	--     넷 다 같은 순서가 되는 게 의도다. 한 곳만 정렬하면 UI 마다 순서가 어긋난다.
	--   ⚠️ 새 무기를 추가할 때 등급 자리에 끼워 넣을 것. 끝에 붙이면 정렬이 깨진다.
	--   ⚠️ 같은 등급 안의 순서는 기존 배열 순서를 유지했다(특별한 기준 없음).

	-- ── Normal ──
	{ id = "ClassicSword",      name = "Classic Sword", rarity = "Normal", modelName = "ClassicSword",
	  short = "Balanced starter",
	  desc = "Reliable all-rounder with a short lunge dash. The lunge closes the gap right after you get knocked back, so you rarely lose your rhythm." },

	{ id = "HammerLow",         name = "Hammer",         rarity = "Normal",   modelName = "HammerLow",
	  short = "Heavy spin",
	  desc = "Slow, weighty swings plus a spinning sweep that keeps hitting. Pin the King against a wall and the spin lands every tick." },

	-- ── Rare ──
	-- 🔥 [표기 변경 2026-09-12] "Dragon Fire" → "Fire Blade".
	--   [왜] 이 게임에서 드래곤은 킹·환경 쪽 소재다(FrostDragon 태거 아이템 /
	--     DragonEntrance 맵 연출). 러너 무기에 붙어 있으면 진영 소재가 섞인다.
	--   ⚠️ id·modelName 은 그대로 둔다. 저장 데이터(로드아웃)와 스크립트 참조가
	--     전부 이 문자열을 쓰므로 바꾸면 기존 유저의 장착이 깨진다.
	--     표기는 name 하나만 본다 — 그게 이 구조가 id/name 을 나눠둔 이유다.
	{ id = "DragonFireSword",   name = "Fire Blade",     rarity = "Rare",   modelName = "DragonFireSword",
	  short = "Stack and burn",
	  desc = "Every hit stacks burning embers on the King. Fill the stack to set off a blast. Stacks linger, so you can keep building after being pushed away." },

	-- 🏅 [등급조정 2026-09-09] Epic → Rare.
	--   [근거는 성능이 아니라 복잡도다] 실측 8.7 은 Rare 목표(8~9)에 들어가지만,
	--     그 값은 봇 출격(Sally) 수정 '전' 이라 지금 재면 달라질 수 있다.
	--     ⚠️ 숫자를 근거로 쓰지 말 것 — 재측정 후 11 대가 나와도 이 배치는 유지한다.
	--   [실제 근거] 셋 중 메커니즘이 가장 단순하다.
	--     Sakura      때리면 빨라진다 (조건 없음)
	--     HammerHigh  도약 내려찍기 — 빗나가면 무방비 (리스크·리턴)
	--     DiamondBlade 표식 순회 (각도·순서)
	--     Rare 는 ClassicSword 다음에 잡는 '두 번째 무기' 자리라 단순한 쪽이 맞다.
	--   [부수 효과] Rare 가 DragonFire 1종뿐이던 게 2종이 되고 2-2-2-2 로 고르게 된다.
	--   ⚠️ 재평가 미완: 이속 +20% 는 원래 "점령 승리 경로의 자원"으로 정당화된 값인데,
	--     2026-09-05 에 점령 승리가 폐지되면서 근거가 사라졌다. 아직 안 봤다.
	--   ⚠️ 되돌릴 값: rarity = "Epic" (그리고 Epic 블록으로 위치 이동)
	{ id = "SakuraBlade",       name = "Sakura Blade",   rarity = "Rare",   modelName = "SakuraBlade",
	  short = "Keep the tempo",
	  desc = "Landing hits stacks attack speed and movement speed on yourself. Stop swinging and the stacks fade, so stay on the offensive." },

	-- ── Epic ──
	{ id = "DiamondBladeSword", name = "Diamond Blade",  rarity = "Epic",   modelName = "DiamondBladeSword",
	  short = "Strike the marks",
	  desc = "Marks appear around the King. Hit both from the right angles to detonate them. Rewards footwork over raw damage." },

	{ id = "HammerHigh",        name = "Flame Hammer",   rarity = "Epic",   modelName = "HammerHigh",
	  short = "Leap and slam",
	  desc = "Leap to your target and slam down, launching the King into the air. Miss and you are left wide open." },

	-- ── Legendary ──
	{ id = "KatanaSword2",      name = "Katana",         rarity = "Legendary",   modelName = "KatanaSword2",
	  short = "Counter the knockback",
	  desc = "Hold a counter stance to negate the King's next push and stun him instead. You cannot swing while braced, so read the timing." },

	{ id = "Gauntlet",          name = "Gauntlet",       rarity = "Legendary",   modelName = "Gauntlet",
	  short = "Charge and slam",
	  desc = "Charge a dash, then chase the King down for a second hit. Slamming him into a wall hits far harder, but crashing into it yourself leaves you stunned." },
}
