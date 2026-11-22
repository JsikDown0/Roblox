-- ItemPhysicsWarmup — 태거 아이템의 서버 물리/충돌 지오메트리 예열
--
-- [증상] 그 세션에서 '처음' 로그·배럴이 굴러올 때 서버 596ms / 클라 610ms 가 동시에 튀었다.
--   두 번째부터는 조용했다 — 콜드 스타트의 전형이다.
-- [왜 기존 워밍업으로 안 잡혔나] AssetPreloadClient 의 '아이템 메시 워밍업'은
--   ① 클라에서만 돌고 ② CanCollide=false 로 렌더만 데운다.
--   그런데 굴러가는 물체의 물리는 서버가 계산하고, Wood Log·Wooden Barrel 은
--   CollisionFidelity=Hull 이라 충돌 지오메트리를 따로 만들어야 한다.
--   렌더를 데워도 그 비용은 그대로 남는다.
-- [무엇을 하나] 실제 스폰과 같은 인스턴스를 잠깐 물리에 태웠다가 지운다.
--   ⚠️ Anchored=false 여야 물리 솔버가 실제로 형상을 쓴다. 앵커하면 의미가 없다.
--   ⚠️ 맵 아래 먼 곳에서 한다. 라운드 전이라 아무도 없지만, 혹시 보여도 곤란하다.
--   ⚠️ 서버 부팅 중이라 이 비용은 로딩화면에 가려진다 — 그게 이 스크립트의 목적이다.

local ServerStorage = game:GetService("ServerStorage")

local WARM = { "Wood Log", "Wooden Barrel", "stone", "ItemNoob" }
-- ⚠️ workspace.FallenPartsDestroyHeight(-500)보다 위여야 한다.
--   아래에 두면 파트가 생성 즉시 삭제돼 물리를 한 스텝도 안 타고,
--   스크립트는 "예열 완료"만 찍는다 — 아무 일도 안 하는 예열이 된다.
--   맵 최저점이 Y=-372 이므로 -420 은 맵과도 겹치지 않는다.
local WARM_POS = Vector3.new(0, -420, 0)
local HOLD = 0.35                           -- 물리 스텝을 몇 번 태울 시간

task.spawn(function()
	local ti = ServerStorage:FindFirstChild("TaggerItem")
	if not ti then
		warn("[PhysWarm] ServerStorage.TaggerItem 없음 — 예열 생략")
		return
	end
	local t0 = os.clock()
	local made, folder = 0, Instance.new("Folder")
	folder.Name = "_PhysWarm"
	folder.Parent = workspace

	for i, nm in ipairs(WARM) do
		local tpl = ti:FindFirstChild(nm)
		if tpl then
			local c = tpl:Clone()
			-- 실제 스폰과 같은 조건: 물리를 태워야 Hull 지오메트리가 생성된다.
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = false
					d.CanCollide = true
					d.CanQuery = false
					d.CanTouch = false      -- Touched 훅이 도는 걸 막는다
				end
			end
			if c:IsA("BasePart") then
				c.Anchored = false; c.CanCollide = true
				c.CanQuery = false; c.CanTouch = false
			end
			c.Parent = folder
			pcall(function() c:PivotTo(CFrame.new(WARM_POS + Vector3.new(i * 20, 0, 0))) end)
			made = made + 1
		end
	end

	task.wait(HOLD)
	-- ⚠️ 실제로 물리를 탔는지 확인한다. 낙하로 인해 위치가 변했으면 시뮬레이션이 돈 것이다.
	--   변화가 없으면 삭제됐거나 앵커된 것이므로 예열이 무효다.
	local alive, moved = 0, 0
	for _, c in ipairs(folder:GetChildren()) do
		alive = alive + 1
		local ok, p = pcall(function() return c:GetPivot().Position end)
		if ok and p.Y < WARM_POS.Y - 0.5 then moved = moved + 1 end
	end
	if alive == 0 then
		warn("⚠️ [PhysWarm] 예열본이 전부 사라졌다 — FallenPartsDestroyHeight 확인 필요")
	elseif moved == 0 then
		warn("⚠️ [PhysWarm] 예열본이 낙하하지 않았다 — 물리를 안 탔을 수 있다")
	end
	folder:Destroy()
	print(string.format("🔥 [PhysWarm] 서버 물리 예열 %d종 (낙하확인 %d/%d) / %.0fms",
		made, moved, alive, (os.clock() - t0) * 1000))
end)
