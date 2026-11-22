
   
  




function onTouched(part) 
local h = part.Parent:findFirstChild("Humanoid") 
if h~=nil then 
h.Health = h.Health -100 


end 
end 

-- 데미지 효과 제거: Touched 연결 차단 (grapple 용도라 칼날 데미지 불필요)
