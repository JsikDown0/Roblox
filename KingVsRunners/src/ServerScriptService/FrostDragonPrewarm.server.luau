-- FrostDragonPrewarm : 서버측 애니메이션 캐시 예열
--
-- [이유] 클라는 AssetPreloadClient가 예열하지만 서버는 안 함.
--   서버가 처음 LoadAnimation 하면 AnimationTrack.Length 가 ~0.4초간 0 으로 읽힘.
--   그 사이 엔딩 애니가 이미 재생돼서 DragonAnimDriver의 '마지막 포즈 고정'이 지각 →
--   트랙이 끝나며 rest pose 로 튕김(= 이륙 후 제자리 복귀). 첫 스폰에서만 발생했음.
-- [해결] 부팅 시 더미 Animator 로 두 애니를 미리 로드해 Length 가 잡힐 때까지 대기 → 캐시 warm.
local ServerStorage = game:GetService("ServerStorage")

task.spawn(function()
	local tpl = ServerStorage:WaitForChild("TaggerItem", 30):WaitForChild("Frost Dragon", 30)
	if not tpl then warn("[FrostPrewarm] 템플릿 없음") return end

	local holder = Instance.new("Model")
	holder.Name = "_FrostAnimPrewarm"
	local ac = Instance.new("AnimationController")
	local an = Instance.new("Animator")
	an.Parent = ac
	ac.Parent = holder
	holder.Parent = workspace

	for _, nm in ipairs({"FlapAnim", "EndAnim"}) do
		local src = tpl:FindFirstChild(nm)
		if src then
			local anim = Instance.new("Animation")
			anim.AnimationId = src.AnimationId
			anim.Parent = holder
			local ok, track = pcall(function() return an:LoadAnimation(anim) end)
			if ok and track then
				local t0 = os.clock()
				while track.Length <= 0 and os.clock() - t0 < 5 do task.wait(0.05) end
				print(string.format("[FrostPrewarm] %s length=%.2fs (대기 %.2fs)", nm, track.Length, os.clock() - t0))
			else
				warn("[FrostPrewarm] LoadAnimation 실패: " .. nm)
			end
		end
	end

	holder:Destroy()
	print("[FrostPrewarm] 서버 애니 캐시 예열 완료")
end)
