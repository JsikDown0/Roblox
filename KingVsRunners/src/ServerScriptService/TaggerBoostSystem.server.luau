-- TaggerBoostSystem: 유료 "Tagger Priority" 토큰.
-- 토큰 보유 시 태거 선택 가중치 ×MULT (RoundSystem이 _G.TaggerBoost로 조회).
-- 태거로 뽑히면 토큰 1개 소모 -> "될 때까지 지속". 영속(DataStore).
-- 하드 개런티(pity 임계)는 부스트와 무관 -> 무료 유저 순번 보장 유지.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("TaggerBoost_v1")

local BOOST_MULT = 3

local tokens = {}   -- uid -> count

local function loadTokens(player)
	local n = 0
	local ok, saved = pcall(function() return store:GetAsync("tb_" .. player.UserId) end)
	if ok and type(saved) == "number" then n = saved end
	tokens[player.UserId] = n
end

local function saveTokens(player)
	local uid = player.UserId
	if tokens[uid] == nil then return end
	do
		local ok, err = pcall(function() store:SetAsync("tb_" .. uid, tokens[uid]) end)
		if not ok and _G.ReportSaveFailure then _G.ReportSaveFailure("TaggerBoost_v1", err) end
	end
end

_G.TaggerBoost = {
	MULT = BOOST_MULT,
	get = function(player) return tokens[player.UserId] or 0 end,
	hasBoost = function(player) return (tokens[player.UserId] or 0) > 0 end,
	grant = function(player, n)
		tokens[player.UserId] = (tokens[player.UserId] or 0) + (n or 1)
		saveTokens(player)
		print("[TaggerBoost] grant +" .. (n or 1) .. " -> " .. player.Name .. " (total " .. tokens[player.UserId] .. ")")
	end,
	consume = function(player)
		local uid = player.UserId
		if (tokens[uid] or 0) > 0 then
			tokens[uid] = tokens[uid] - 1
			saveTokens(player)
			print("[TaggerBoost] consume -> " .. player.Name .. " (left " .. tokens[uid] .. ")")
			return true
		end
		return false
	end,
}

Players.PlayerAdded:Connect(loadTokens)
Players.PlayerRemoving:Connect(saveTokens)
for _, p in ipairs(Players:GetPlayers()) do loadTokens(p) end

print("TaggerBoostSystem ready (boost x" .. BOOST_MULT .. ")")
