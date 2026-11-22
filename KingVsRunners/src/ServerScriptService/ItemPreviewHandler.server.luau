-- 태거 아이템 프리뷰 폴더 생성 (클라 로컬 청사진용)
-- 이전 방식: 요청마다 workspace에 청사진 생성 → MeshPart 복제 지연으로 클라 WaitForChild 타임아웃 버그.
-- 현재 방식: boot 시 ReplicatedStorage.TaggerItemPreviews에 템플릿을 clone 해두고,
--            클라(TaggerUIScript)가 로컬에서 청사진을 빌드한다. 서버 왕복/복제 레이스 없음.
-- CrownPreviews 처럼 런타임 생성이라 Ctrl+S 불필요 (F5마다 재생성).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local taggerItems = ServerStorage:WaitForChild("TaggerItem")

-- 기존 폴더 정리 후 재생성
local existing = ReplicatedStorage:FindFirstChild("TaggerItemPreviews")
if existing then existing:Destroy() end

local previews = Instance.new("Folder")
previews.Name = "TaggerItemPreviews"

local count = 0
local skipped = {}
for _, itemTemplate in ipairs(taggerItems:GetChildren()) do
	local actual = itemTemplate

	-- Folder 타입은 안의 BasePart/Model 을 실체로 사용 (기존 서버 청사진 unwrap 로직과 동일)
	if itemTemplate:IsA("Folder") then
		actual = nil
		for _, child in ipairs(itemTemplate:GetChildren()) do
			if child:IsA("BasePart") or child:IsA("Model") then
				actual = child
				break
			end
		end
	end

	if actual and (actual:IsA("BasePart") or actual:IsA("Model")) then
		local clone = actual:Clone()
		clone.Name = itemTemplate.Name   -- 클라는 TaggerItem 자식 이름으로 조회하므로 원래 이름 유지
		-- 프리뷰는 시각용 → 사운드 제거 (Playing 사운드가 ReplicatedStorage에서 2D 전역 재생되는 버그 방지)
		for _, s in ipairs(clone:GetDescendants()) do
			if s:IsA("Sound") then s:Destroy() end
		end
		-- 배럴 프리뷰: 세로 원통을 옆으로 눕혀서 표시 (인벤/청사진 공용)
		if (itemTemplate.Name == "Wooden Barrel" or itemTemplate.Name == "CrusaderBarrel" or itemTemplate.Name == "OilDrum") and clone:IsA("Model") and clone.PrimaryPart then
			clone:PivotTo(clone:GetPivot() * CFrame.Angles(0, 0, math.rad(90)))
		end
		clone.Parent = previews
		count = count + 1
	else
		table.insert(skipped, itemTemplate.Name)
	end
end

previews.Parent = ReplicatedStorage

print("[TaggerPreviews] ReplicatedStorage.TaggerItemPreviews 생성:", count, "종")
if #skipped > 0 then
	print("[TaggerPreviews] 스킵됨(BasePart/Model 아님):", table.concat(skipped, ", "))
end

-- ── RareChest 프리뷰 (배틀패스 Box 티어 프리뷰용 — 클라 뷰포트에서 클론) ──
-- 클라는 ServerStorage 접근 불가 → RS에 복제해둠. 런타임 생성이라 Ctrl+S 불필요.
local rareChestT = ServerStorage:FindFirstChild("RareChest")
if rareChestT then
	local old = ReplicatedStorage:FindFirstChild("RareChestPreview")
	if old then old:Destroy() end
	local c = rareChestT:Clone()
	c.Name = "RareChestPreview"
	for _, s in ipairs(c:GetDescendants()) do
		if s:IsA("Sound") then s:Destroy() end
	end
	c.Parent = ReplicatedStorage
	print("[Preview] RareChestPreview 생성")
else
	warn("[Preview] ServerStorage.RareChest 없음")
end

-- ── Item Chest 프리뷰 (Basic 박스 컷신용 — 일반 파밍 상자) ──
local itemChestT = ServerStorage:FindFirstChild("Item Chest")
if itemChestT then
	local old = ReplicatedStorage:FindFirstChild("ItemChestPreview")
	if old then old:Destroy() end
	local c = itemChestT:Clone()
	c.Name = "ItemChestPreview"
	for _, s in ipairs(c:GetDescendants()) do
		if s:IsA("Sound") then s:Destroy() end
		if s:IsA("BasePart") then s.Anchored = true; s.CanCollide = false end
	end
	c.Parent = ReplicatedStorage
	print("[Preview] ItemChestPreview 생성")
else
	warn("[Preview] ServerStorage.Item Chest 없음")
end

-- ── CosmeticBox 프리뷰 (코스메틱 박스 컷신용) ──
--   ⚠️ 로벅스샵 진열대(_RobuxBoxShelf)의 모델을 재사용한다. 원본은 워크스페이스 배치용이라
--      클라가 직접 못 쓴다 → ReplicatedStorage 로 복제해야 한다.
--      예전엔 일반 상자에 색만 입혔는데(RareSkinRewardCard:483) 형태가 같아 구분이 안 됐다.
local shelf = ServerStorage:FindFirstChild("_RobuxBoxShelf")
local cosBoxT = shelf and shelf:FindFirstChild("CosmeticBox", true)
if cosBoxT then
	local old = ReplicatedStorage:FindFirstChild("CosmeticBoxPreview")
	if old then old:Destroy() end
	local c = cosBoxT:Clone()
	c.Name = "CosmeticBoxPreview"
	for _, s in ipairs(c:GetDescendants()) do
		if s:IsA("Sound") then s:Destroy() end
		if s:IsA("BasePart") then s.Anchored = true; s.CanCollide = false end
	end
	if not c.PrimaryPart then
		local p = c:FindFirstChildWhichIsA("BasePart", true)
		if p then c.PrimaryPart = p end
	end
	c.Parent = ReplicatedStorage
	print("[Preview] CosmeticBoxPreview 생성")
else
	warn("[Preview] _RobuxBoxShelf.CosmeticBox 없음")
end

-- ── MysteryBox 프리뷰 (Rare+/Epic+ 박스 회전 컷신용) ──
local mysteryBoxT = ServerStorage:FindFirstChild("MysteryBox")
if mysteryBoxT then
	local old = ReplicatedStorage:FindFirstChild("MysteryBoxPreview")
	if old then old:Destroy() end
	local c = mysteryBoxT:Clone()
	c.Name = "MysteryBoxPreview"
	for _, s in ipairs(c:GetDescendants()) do
		if s:IsA("Sound") then s:Destroy() end
		if s:IsA("BasePart") then s.Anchored = true; s.CanCollide = false end
	end
	if not c.PrimaryPart then
		local p = c:FindFirstChildWhichIsA("BasePart", true)
		if p then c.PrimaryPart = p end
	end
	c.Parent = ReplicatedStorage
	print("[Preview] MysteryBoxPreview 생성")
else
	warn("[Preview] ServerStorage.MysteryBox 없음")
end
