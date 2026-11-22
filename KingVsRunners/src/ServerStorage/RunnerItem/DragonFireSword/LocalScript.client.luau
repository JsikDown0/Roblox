--Made by Stickmasterluke


local sp=script.Parent

originalgrip=CFrame.new(0,-1.8,0)
currentgrip=originalgrip

swingspeed=1

debris=game:GetService("Debris")
enabled=true

function waitfor(parent,name)
	while true do
		local child=parent:FindFirstChild(name)
		if child~=nil then
			return child
		end
		wait()
	end
end

waitfor(sp,"Handle")

function onButton1Down(mouse)
	if not enabled then
		return
	end
	enabled=false
	mouse.Icon="rbxasset://textures\\GunWaitCursor.png"
	wait(.75)
	mouse.Icon="rbxasset://textures\\GunCursor.png"
	enabled=true
end

function swordUp()
	currentgrip=originalgrip
end

function swordOut()
	currentgrip=originalgrip*CFrame.Angles(math.pi/4,.4,0)
end

function spinsword(spintime)
	delay(0,function()
		local startspin=tick()
		local endspin=startspin+spintime
		while tick()<endspin do
			sp.Grip=currentgrip*CFrame.Angles(math.pi*2*((tick()-startspin)/spintime),0,0)
			wait()
		end
		sp.Grip=currentgrip
	end)
end

sp.Equipped:connect(function(mouse)
	equipped=true
	local currentlast=lastequipped
	if mouse==nil then
		print("Mouse not found")
		return 
	end
	mouse.Icon="rbxasset://textures\\GunCursor.png"
	mouse.Button1Down:connect(function()
		onButton1Down(mouse)
	end)
	mouse.KeyDown:connect(function(key)
		key=string.lower(key)
		if key=="l" or key=="t" or key=="g" then
			local h=sp.Parent:FindFirstChild("Humanoid")
			if h~=nil then

			end
		end
	end)
	local h=sp.Parent:FindFirstChild("Humanoid")
	local t=sp.Parent:FindFirstChild("Torso")
	if t and h then
		local equipanim=sp:FindFirstChild("Equip")
		if equipanim~=nil then
			local EquipAnim=h:LoadAnimation(equipanim)
			if EquipAnim and h.Health>0 then
				EquipAnim:Play(nil,nil,equipspeed)
			end
		end
		local holdanim=sp:FindFirstChild("Hold")
		if holdanim~=nil then
			if HoldAnim then
				HoldAnim:Stop()
			end
			HoldAnim=h:LoadAnimation(holdanim)
			if HoldAnim and h.Health>0 then
				HoldAnim:Play()
			end
		end
	end
end)

sp.Unequipped:connect(function()
	equipped=false
	if HoldAnim then
		HoldAnim:Stop()
	end
end)

function lunge()
	local t=sp.Parent:FindFirstChild("Torso")
	local h=sp.Parent:FindFirstChild("Humanoid")
	if t and h and equipped then
		local target=h.TargetPoint
		local direction=(target-t.Position)*Vector3.new(1,0,1)
		if direction.magnitude>.01 then
			direction=direction.unit
			local newBV=Instance.new("BodyVelocity")
			newBV.P=10^5
			newBV.maxForce=Vector3.new(newBV.P,0,newBV.P)
			newBV.velocity=direction*30
			debris:AddItem(newBV,1)
			newBV.Parent=t
			t.CFrame=CFrame.new(t.Position,target*Vector3.new(1,0,1)+Vector3.new(0,t.Position.Y,0))
			local sound=sp.Handle:FindFirstChild("FlashSound")
			if sound then
				sound:Play()
			end
			wait(.2)
			if newBV~=nil then
				newBV:remove()
			end
		end
	end
end

waitfor(sp,"RunAnim")

-- 스윙 애니메이션 재생.
-- (1) R15는 "Torso"가 없으므로 Torso 의존 제거 → Humanoid만 있으면 재생.
-- (2) 원본 일부 ID(SwingFast 계열 86...)는 이 게임에서 재생 불가(Length=0)였음 →
--     재생 확인된 ID(74...)로 코드에서 대체. 인스턴스 ID 변경은 롤백되므로 코드에서 강제.
-- (3) Priority=Action 강제 → 걷기/서기 애니메이션에 묻히지 않고 위에 덮어쓰게.
local WORKING_ANIM = {
	["http://www.roblox.com/Asset?ID=86313418"] = "rbxassetid://74894663", -- LeftSwingFast → LeftSlash
	["http://www.roblox.com/Asset?ID=86313260"] = "rbxassetid://74813494", -- RightSwingFast → RightSlash
}

sp.RunAnim.Changed:connect(function()
	local h = sp.Parent:FindFirstChild("Humanoid")
	local anim = sp:FindFirstChild(sp.RunAnim.Value)
	if anim and h and h.Health > 0 then
		-- 막힌 ID면 재생되는 ID로 대체
		local replacement = WORKING_ANIM[anim.AnimationId]
		if replacement then
			anim.AnimationId = replacement
		end
		local animator = h:FindFirstChildOfClass("Animator")
		local track
		if animator then
			track = animator:LoadAnimation(anim)
		else
			track = h:LoadAnimation(anim)
		end
		track.Priority = Enum.AnimationPriority.Action  -- 걷기/서기 위에 덮어쓰기
		track:Play(0.1, 1, 1/swingspeed)
		local sound = sp.Handle:FindFirstChild("FlashSound")
		if sound then
			sound:Play()
		end
	end
end)


function tagHumanoid(humanoid,player)
	for i,v in ipairs(humanoid:GetChildren()) do
		if v.Name=="creator" then
			v:remove()
		end
	end
	local creator_tag=Instance.new("ObjectValue")
	creator_tag.Value=player
	creator_tag.Name="creator"
	creator_tag.Parent=humanoid
	debris:AddItem(creator_tag,1)
end
