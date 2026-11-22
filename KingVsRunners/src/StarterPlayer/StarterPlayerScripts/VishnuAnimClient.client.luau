-- Vishnu(Ascendant) 클라 애니 정리: VishnuAura 속성 감지 시 로컬 Animate 중지 + 기본 애니 트랙 정지.
-- (서버가 꺼도 클라 Animate가 로컬로 계속 재생을 재시작하는 핑퐁 문제 해결 — 클라에서 직접 처리)
local Players = game:GetService("Players")
local plr = Players.LocalPlayer

local function hook(char)
	local function onAura()
		local hum = char:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		local animate = char:FindFirstChild("Animate")
		if char:GetAttribute("VishnuAura") then
			if animate then animate.Disabled = true end
			-- 기본(걷기/달리기 등) 트랙 정지 — 부양 애니(104124357238880)는 유지
			if animator then
				task.spawn(function()
					for i = 1, 20 do
						if not char:GetAttribute("VishnuAura") then break end
						for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
							local id = t.Animation and t.Animation.AnimationId or ""
							if not string.find(id, "104124357238880") then t:Stop(0.1) end
						end
						task.wait(0.05)
					end
				end)
			end
		else
			-- 다운 중에는 Animate 소유권이 DownSystem/DownClient 에 있다.
			-- 여기서 조건 없이 되살리면 기본 달리기/걷기 애니가 다운 자세를 덮어쓴다.
			-- (다운이 풀릴 때 DownClient.endDown 이 VishnuAura 를 확인하고 복구해준다)
			if animate and not char:GetAttribute("Downed") then
				animate.Disabled = false
			end
		end
	end
	char:GetAttributeChangedSignal("VishnuAura"):Connect(onAura)
	onAura()   -- 초기 상태 반영 (스폰 시 이미 켜져있을 수 있음)
end

if plr.Character then hook(plr.Character) end
plr.CharacterAdded:Connect(hook)
