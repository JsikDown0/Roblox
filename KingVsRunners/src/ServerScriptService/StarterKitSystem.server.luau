-- StarterKitSystem — 소모품 맛보기 지급 (계정당 1회)
--   목적: "모르면 안 산다"를 푸는 장치. 9종을 2개씩 줘서 직접 써보게 한다.
--   지급 시점: 인벤토리를 처음 열었을 때 (클라가 StarterKitOpened 로 알림)
--     ⚠️ 접속 즉시 주지 않는 이유 — 인벤을 안 열면 받은 줄도 모르고,
--        연출(상자 열기)을 볼 수 없어 인지가 안 된다.
--   ⚠️ 지급 여부는 서버가 판정한다. 클라 신호만 믿으면 반복 호출로 무한 지급된다.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local openedEvent = ReplicatedStorage:WaitForChild("StarterKitOpened")
local rewardEvent = ReplicatedStorage:FindFirstChild("RareSkinReward")

-- 지급 목록: LoadoutManager 의 consumable = true 9종과 일치해야 한다.
--   ⚠️ 새 소모품을 추가하면 여기도 갱신할 것. 자동 동기화가 아니다.
local KIT = {
	"Speed Potion", "Wood Shield", "RevivalFlag",
	"Gas Grenade", "ODM Gear",
	-- 🗑️ [2026-08-29] "GrappleHook" 제거 (ODM 하위호환). 9종 → 8종.
	--   ⚠️ RareSkinRewardCard 의 "9 Runner Items" 문구도 함께 고쳤다.
	"Ice Bow", "Mic Bomb", "Decoy Wand",
}
local PER_ITEM = 2

-- 동시 호출 방어(같은 프레임에 두 번 들어오는 경우)
local granting = {}

local function grant(player)
	if granting[player] then return end
	granting[player] = true

	local ok = pcall(function()
		local d = _G.DataService and _G.DataService.get(player)
		if not d then
			-- 프로필 미로드 — 조용히 넘어간다. 다음 인벤 오픈에 다시 시도된다.
			return
		end
		if d.StarterKitGiven then return end

		if not _G.AddConsumable then
			warn("[StarterKit] _G.AddConsumable 없음 — 지급 중단")
			return
		end

		local total = 0
		for _, itemName in ipairs(KIT) do
			for _ = 1, PER_ITEM do
				_G.AddConsumable(player, itemName)
			end
			total = total + PER_ITEM
		end

		-- ⚠️ 플래그는 지급이 끝난 뒤에 세운다. 앞에 두면 중간 실패 시 영영 못 받는다.
		d.StarterKitGiven = true
		print(string.format("🎁 [StarterKit] %s granted %d types x%d = %d items",
			player.Name, #KIT, PER_ITEM, total))

		-- 연출: 기존 상자 열기 컷신 재사용 (RareSkinRewardCard 의 fromBox 경로)
		if rewardEvent then
			rewardEvent:FireClient(player, {
				fromBox   = true,
				kind      = "cosmetic",
				-- header 가 있으면 RareSkinRewardCard 가 그걸 우선 쓴다.
				header    = "RUNNER STARTER KIT!",
				display   = string.format("%d Runner Items · x%d Each", #KIT, PER_ITEM),
				rarity    = "Epic",
				-- itemGrid 가 있으면 카드가 단일 아이콘 대신 3열 격자로 썸네일을 그린다.
				--   값은 ReplicatedStorage.RunnerItemPreviews 의 모델명과 맞아야 한다.
				itemGrid  = KIT,
				itemCount = PER_ITEM,
			})
		end
	end)

	if not ok then warn("[StarterKit] 지급 중 오류") end
	granting[player] = nil
end

openedEvent.OnServerEvent:Connect(function(player)
	grant(player)
end)

Players.PlayerRemoving:Connect(function(player)
	granting[player] = nil
end)

print("🎁 StarterKitSystem ready — " .. #KIT .. " consumables x" .. PER_ITEM .. " (once per account)")
