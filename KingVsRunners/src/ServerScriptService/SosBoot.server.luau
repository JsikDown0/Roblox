-- SosBoot
-- SosSystem 모듈을 게임 시작 시점에 즉시 require하여 활성화시키는 부트 스크립트.
-- (ModuleScript는 require 되어야 실행되는데, DownSystem은 다운 발생 시점에야 require 하므로
--  그 전에 클라이언트 SOS 요청이 들어오면 무시됨. 이 부트로 시작 시점에 미리 활성화.)

require(game.ServerScriptService:WaitForChild("SosSystem"))
print("🆘 SosBoot: SosSystem require 완료")
