-- EmoteData: 이미지 이모트 단일 정의 (EffectSystem / EmotionServer / ShopSystem 공유)
--   imageId = 머리 위에 띄울 스티커 이미지(rbxassetid). 비어있으면 icon(이모지) 폴백.
--   free = true → 구매 없이 기본 보유(상점 미노출, 인벤에서 바로 장착 가능).
--   ⚠ Decal로 올렸는데 인게임에서 안 뜨면, Decal ID가 아니라 Image(Texture) ID로 바꿔야 함.
return {
	{ id = "emote_8bit",          name = "8-Bit GG",       imageId = "rbxassetid://95324123859000",  icon = "🎮", rarity = "Normal" },
	{ id = "emote_angry",         name = "Angry",          imageId = "rbxassetid://122335322062785", icon = "😡", rarity = "Normal", free = true },
	{ id = "emote_caught",        name = "Caught",         imageId = "rbxassetid://122314747301123", icon = "✊", rarity = "Normal" },
	{ id = "emote_crying",        name = "Crying",         imageId = "rbxassetid://120676248829342", icon = "😢", rarity = "Normal", free = true },
	{ id = "emote_default",       name = "Newbie",         imageId = "rbxassetid://119019006009828", icon = "🙂", rarity = "Normal", free = true },
	{ id = "emote_expressionless",name = "Expressionless", imageId = "rbxassetid://124731970298525", icon = "😑", rarity = "Normal" },
	{ id = "emote_fire_gg",       name = "Fire GG",        imageId = "rbxassetid://93454128722466",  icon = "🔥", rarity = "Normal" },
	{ id = "emote_king",          name = "King",           imageId = "rbxassetid://118491022652753", icon = "👑", rarity = "Normal" },
	{ id = "emote_smile",         name = "Smile",          imageId = "rbxassetid://71368328621311",  icon = "😄", rarity = "Normal", free = true },
	{ id = "emote_surprised",     name = "Surprised",      imageId = "rbxassetid://104854712620087", icon = "😮", rarity = "Normal", free = true },
	{ id = "emote_teasing",       name = "Teasing",        imageId = "rbxassetid://91181215595040",  icon = "😝", rarity = "Normal" },
	{ id = "emote_too_slow",      name = "Too Slow",       imageId = "rbxassetid://117737766154503", icon = "🐌", rarity = "Normal" },
	{ id = "emote_chick",       name = "Chick",          imageId = "rbxassetid://96219391262744",  icon = utf8.char(0x1F424), rarity = "Normal", free = false },
	{ id = "emote_focus",       name = "Focused",        imageId = "rbxassetid://114803214249969", icon = utf8.char(0x1F3AF), rarity = "Normal", free = false },
	{ id = "emote_frozen",      name = "Frozen",         imageId = "rbxassetid://125951457581214", icon = utf8.char(0x1F9CA), rarity = "Normal", free = false },
	{ id = "emote_fury",        name = "Furious",        imageId = "rbxassetid://98830773047023",  icon = utf8.char(0x1F4A2), rarity = "Normal", free = false },
	{ id = "emote_good",        name = "Nice!",          imageId = "rbxassetid://87780333753105",  icon = utf8.char(0x1F44D), rarity = "Normal", free = false },
	{ id = "emote_royal",       name = "Royal",          imageId = "rbxassetid://92394887921763",  icon = utf8.char(0x1F60C), rarity = "Normal", free = false },
	{ id = "emote_shy",         name = "Shy",            imageId = "rbxassetid://130103420545580", icon = utf8.char(0x263A),  rarity = "Normal", free = false },
	{ id = "emote_donut_tube",    name = "Donut Tube",     imageId = "rbxassetid://86886948456897",  icon = utf8.char(0x1F369), rarity = "Epic", free = false, passExclusive = true },
	{ id = "emote_coconut_smile", name = "Coconut Smile",  imageId = "rbxassetid://81178726118141",  icon = utf8.char(0x1F965), rarity = "Epic", free = false, passExclusive = true },
	{ id = "emote_beach",         name = "Beach",          imageId = "rbxassetid://112844986822281", icon = utf8.char(0x1F3D6), rarity = "Epic", free = false, passExclusive = true },
}
