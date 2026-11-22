-- DamagePopupServer — _G.ShowDamage 노출
--
-- [쓰는 법] _G.ShowDamage(player, dmg, worldPos, crit)
--   player  : 공격자 Player (숫자는 때린 사람에게만 보인다 — 기존 3종과 같은 규약)
--   dmg     : 표시할 값. CC 환산이 필요하면 _G.DisplayDamage 를 먼저 통과시킬 것.
--   worldPos: 타격 지점 (Hit.Position 등)
--   crit    : 강타/스킬이면 true → 금색 + 크게
--
-- ⚠️ 봇(Player 없음)이 때린 경우엔 조용히 무시한다. FireClient 는 Player 가 필요하다.
-- ⚠️ 이 파일은 표시 전용이다. 데미지 판정에는 절대 관여하지 않는다 —
--   표시와 판정이 한 곳에 섞이면 "숫자를 고치다 데미지가 바뀌는" 사고가 난다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ev = ReplicatedStorage:WaitForChild("DamagePopupEvent")

_G.ShowDamage = function(player, dmg, worldPos, crit)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	if not worldPos then return end
	ev:FireClient(player, dmg or 0, worldPos, crit and true or false)
end

print("🔢 DamagePopupServer 준비 (_G.ShowDamage)")
