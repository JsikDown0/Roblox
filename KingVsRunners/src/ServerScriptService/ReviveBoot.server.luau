-- ReviveBoot
-- ReviveSystem 모듈을 게임 시작 시점에 즉시 require하여 활성화시키는 부트 스크립트.
-- (SosBoot와 동일 패턴 — ModuleScript는 require 되어야 실행되므로)

require(game.ServerScriptService:WaitForChild("ReviveSystem"))
print("🩹 ReviveBoot: ReviveSystem require 완료")
