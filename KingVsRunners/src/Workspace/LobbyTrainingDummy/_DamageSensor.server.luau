-- _DamageSensor: 태거 더미가 받는 데미지를 추적 (디버그용)
-- Humanoid 체력 변화를 감지해, 매 타격의 데미지량/시각/간격/누적을 콘솔에 출력.
-- 한 스윙에 여러 번 들어가는지(중복 타격) 바로 확인 가능.

local dummy = script.Parent
local hum = dummy:WaitForChild("Humanoid")

local lastHealth = hum.Health
local lastHitClock = nil
local hitCount = 0
local totalDamage = 0

print(string.format("🩺 [DamageSensor] 시작 — 더미 HP: %d / %d", hum.Health, hum.MaxHealth))

hum.HealthChanged:Connect(function(newHealth)
	local delta = newHealth - lastHealth
	lastHealth = newHealth

	-- 데미지(감소)만 추적. 회복(증가)은 별도 표시.
	if delta < 0 then
		local dmg = -delta
		hitCount += 1
		totalDamage += dmg
		local now = os.clock()
		local gapStr = "첫 타격"
		if lastHitClock then
			gapStr = string.format("이전 타격 +%.3fs", now - lastHitClock)
		end
		lastHitClock = now
		warn(string.format("🗡️ [DamageSensor] %s #%d  데미지: %.1f  → HP: %.0f/%.0f  | 누적: %.1f  | %s",
			dummy.Name, hitCount, dmg, math.floor(newHealth), hum.MaxHealth, totalDamage, gapStr))
	elseif delta > 0 then
		print(string.format("💚 [DamageSensor] 회복 +%d → HP: %d/%d", delta, math.floor(newHealth), hum.MaxHealth))
	end
end)

hum.Died:Connect(function()
	warn(string.format("💀 [DamageSensor] 더미 사망 — 총 %d회 타격, 누적 데미지 %.1f", hitCount, totalDamage))
end)
