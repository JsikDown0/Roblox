-- VIPChatTag: VIP 발신자의 채팅에 [VIP] 태그 + 골드 네임.
-- 서버가 VIP 플레이어에 IsVIP 속성을 세팅(PresetManager) → 여기서 발신자 판정.
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")

local GOLD = "#FFD700"

TextChatService.OnIncomingMessage = function(message)
	local props = Instance.new("TextChatMessageProperties")
	local src = message.TextSource
	if src then
		local player = Players:GetPlayerByUserId(src.UserId)
		if player and player:GetAttribute("IsVIP") then
			-- 기존 PrefixText(보통 "이름")를 [VIP] + 골드색으로 감쌈
			props.PrefixText = string.format("<font color='%s'>[VIP] %s</font>", GOLD, message.PrefixText)
		end
	end
	return props
end
