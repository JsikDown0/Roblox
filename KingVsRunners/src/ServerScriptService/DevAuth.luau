-- DevAuth: 테스트/개발자 커맨드 인증 (단일 화이트리스트)
-- 프로덕션에선 DEV_IDS만 허용. Studio(플레이테스트)에선 전원 허용(테스트 편의).
-- 실패 시 fail-closed: isDev가 false면 커맨드 차단.
local RunService = game:GetService("RunService")

local DevAuth = {}

DevAuth.DEV_IDS = {
	[9228200642] = true,   -- melonberrystrong (개발자)
}

function DevAuth.isDev(plr)
	return (plr ~= nil and DevAuth.DEV_IDS[plr.UserId] == true) or RunService:IsStudio()
end

return DevAuth
