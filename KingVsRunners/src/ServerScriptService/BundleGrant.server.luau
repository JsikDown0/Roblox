-- BundleGrant: 게임패스 기반 묶음 상품 지급 (Frost Lord Bundle / King Starter / Runner Starter)
--
-- 왜 게임패스인가:
--   개발자상품은 중복 구매가 가능해 유저가 같은 값을 두 번 결제할 수 있고, 로블록스는 환불 API가 없음.
--   패스는 로블록스가 1인 1개를 강제하고 소유권을 영구 보관 → 우리가 추적할 필요 없음.
--   ⚠ 반대로 "반복 구매가 정상"인 상품(Collector Pack = 박스 5개)은 개발자상품이어야 하며
--     BattlePassSystem.ProcessReceipt가 담당한다. 여기 넣지 말 것.
--
-- 2경로 지급 (Roblox 공식 패스 가이드):
--   1) 조인 시 : UserOwnsGamePassAsync  (기존 소유자 / 웹에서 산 사람)
--   2) 세션 중 : PromptGamePassPurchaseFinished  (지금 막 산 사람)
--   ⚠ UserOwnsGamePassAsync는 세션 캐시라 조인 때 false를 읽으면 그 세션 내내 false. 재폴링 금지.
--
-- 멱등성: 지급이 전부 "소유 플래그 세팅"이라 몇 번 불려도 결과가 같음 → 실패해도 다음 조인에 자동 복구.
--   ⚠ 예외: 소모품(consumables)은 부를 때마다 수량이 늘어남 = 멱등이 아님.
--     그래서 소모품이 든 팩은 "이미 지급했는지" 표시를 남겨 1회만 준다.

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

-- 지급 경로가 3갈래 (아이템 종류별로 소유권 저장소가 다름)
--   permanents : OwnedItem_ 계열 → LoadoutManager.ownedPermanents 에 지속 (GrantOwnedPermanent)
--   skins      : Has_ 계열 → DataService.Skins 에 지속 (SkinManager.restoreSkins가 조인 시 복원)
--   consumables: playerConsumables + Consumable_ 어트리뷰트 (ShopSystem 345줄과 동일하게 둘 다 필요)
local PACKS = {
	{
		name = "Frost Lord Bundle",
		pass = 1918658457,
		permanents = { "frost_dragon", "dash_ice", "trail_ice", "kill_effect_ice", "emote_frozen" },
		skins      = { "Has_FrozenSword" },
	},
	{
		name = "King Starter Pack",
		pass = 1919324786,
		permanents = { "demon_spear", "crown_crimson", "kill_effect_fire" },
		skins      = { "Has_RainbowFist" },
	},
	{
		name = "Runner Starter Pack",
		pass = 1918070832,
		permanents = { "trail_shadow", "dash_spectral" },
		skins      = { "Has_RainbowCycleSword" },
		-- 소모품은 멱등이 아니므로 1회만 지급 (아래 grantedAttr 가드)
		consumables = {
			{ id = "speed_boost", name = "Speed Potion", count = 3 },
			{ id = "wood_shield", name = "Wood Shield",  count = 3 },
			{ id = "revival_flag", name = "RevivalFlag", count = 1 },
		},
	},
}

local function grantPack(player, pack, reason)
	if not _G.GrantOwnedPermanent then
		warn("[Pack] GrantOwnedPermanent 없음 - LoadoutManager 미로드?")
		return false
	end

	local allOk = true

	for _, id in ipairs(pack.permanents or {}) do
		-- GrantOwnedPermanent는 LoadoutManager 데이터 로드까지 내부 대기하고,
		-- 실패 시 false 리턴 (로드 전 저장 = 기존 데이터 소실이라 막아둠).
		if not _G.GrantOwnedPermanent(player, id) then
			warn("[Pack] 지급 실패:", player.Name, pack.name, id, "- 다음 조인에 재시도됨")
			allOk = false
		end
	end

	-- 스킨은 별도 저장소. 프로필 로드까지 대기해야 영속됨.
	if pack.skins and #pack.skins > 0 then
		local d = _G.DataService and _G.DataService.waitForData(player, 20)
		if d and type(d.Skins) == "table" then
			for _, attr in ipairs(pack.skins) do
				player:SetAttribute(attr, true)
				d.Skins[attr] = true
			end
		else
			warn("[Pack] DataService 프로필 미로드 - 스킨 지급 보류:", player.Name, pack.name)
			allOk = false
		end
	end

	-- 소모품: 부를 때마다 누적되므로(멱등 X) 이미 줬으면 건너뜀.
	-- OwnedItem_ 네임스페이스를 재활용해 LoadoutManager가 DataStore에 지속시킴.
	if pack.consumables and allOk then
		local flag = "starterconsum_" .. pack.pass
		if player:GetAttribute("OwnedItem_" .. flag) then
			-- 이미 지급됨 (재접속 등) → 조용히 통과
		elseif _G.AddConsumable then
			for _, c in ipairs(pack.consumables) do
				for _ = 1, c.count do
					_G.AddConsumable(player, c.name)   -- 1개씩만 올림 → count만큼 반복
				end
				local cur = player:GetAttribute("Consumable_" .. c.id) or 0
				player:SetAttribute("Consumable_" .. c.id, cur + c.count)   -- UI 표시용(ShopSystem과 동일)
			end
			_G.GrantOwnedPermanent(player, flag)   -- 지급 완료 표시(영속)
		else
			warn("[Pack] AddConsumable 없음 - 소모품 지급 보류:", player.Name)
			allOk = false
		end
	end

	if allOk then
		print("[Pack] " .. pack.name .. " 지급 완료 ->", player.Name, "(" .. reason .. ")")
	end
	return allOk
end

-- 경로 1: 조인 시 (기존 소유자 + 웹 구매자)
local function onPlayerAdded(player)
	for _, pack in ipairs(PACKS) do
		task.spawn(function()
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pack.pass)
			end)
			if not ok then
				warn("[Pack] UserOwnsGamePassAsync 실패:", player.Name, pack.name, tostring(owns))
				return
			end
			if owns then grantPack(player, pack, "join") end
		end)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerAdded, player)
end)

-- 경로 2: 세션 중 구매 (캐시 우회 - 재폴링으로는 절대 못 잡음)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	if not purchased then return end
	for _, pack in ipairs(PACKS) do
		if pack.pass == passId then
			task.spawn(grantPack, player, pack, "purchase")
			return
		end
	end
end)

print("[Pack] BundleGrant ready (" .. #PACKS .. " packs)")
