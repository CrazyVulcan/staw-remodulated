-- Controls belong to the supplied dice-box mesh. Normalize their scale so a
-- non-uniformly scaled or rotated box does not stretch or overlap the buttons.
memory={count=3,dice={}}
local epoch=0
local layout
local function geometry()
 local b=self.getBoundsNormalized();local s=self.getScale();local p=self.getPosition()
 local sx,sy,sz=math.max(0.001,math.abs(s.x)),math.max(0.001,math.abs(s.y)),math.max(0.001,math.abs(s.z))
 local offset=b.offset or {x=0,y=0,z=0}
 local cy=(offset.y or ((b.center and b.center.y or p.y)-p.y))
 return {w=math.max(2,b.size.x-0.5),d=math.max(2,b.size.z-0.5),
  cx=(offset.x or 0)/sx,cz=(offset.z or 0)/sz,
  -- The supplied tray's cached mesh spans Y -0.555..0.555; its inner floor
  -- is Y -0.15. Use that proportion, then lift the controls 0.025 world units.
  y=(cy-b.size.y*(0.15/1.11)+0.025)/sy,sx=sx,sy=sy,sz=sz}
end
function redraw()
 self.clearButtons();layout=geometry();local a=layout
 local h=math.min(0.56,a.d*0.12)
 local function b(fn,label,x,z,w,height)
  self.createButton({function_owner=self,click_function=fn,label=label,
   position={a.cx+x/a.sx,a.y,a.cz+z/a.sz},rotation={0,0,0},scale={1/a.sx,1/a.sy,1/a.sz},
   width=math.floor(w*500),height=math.floor((height or h)*500),font_size=math.floor(h*210),
   color={0.12,0.28,0.42,1},font_color={1,1,1}})
 end
 b("less","−",-a.w*0.35,-a.d*0.34,a.w*0.16)
 b("noop",tostring(memory.count).." DICE",0,-a.d*0.34,a.w*0.42)
 b("more","+",a.w*0.35,-a.d*0.34,a.w*0.16)
 b("attack","ROLL ATTACK",-a.w*0.25,a.d*0.23,a.w*0.44)
 b("defense","ROLL DEFENSE",a.w*0.25,a.d*0.23,a.w*0.44)
 b("clear","CLEAR",0,a.d*0.42,a.w*0.38,h*0.8)
end
function onLoad(saved)
 local ok,v=pcall(JSON.decode,saved or "")
 if ok and type(v)=="table" then memory=v end
 memory.count=math.max(1,math.min(12,tonumber(memory.count) or 3));memory.dice=memory.dice or {}
 redraw()
end
function onSave()return JSON.encode(memory)end
function noop()end
function less()memory.count=math.max(1,memory.count-1);redraw()end
function more()memory.count=math.min(12,memory.count+1);redraw()end
function clear()
 epoch=epoch+1
 for _,guid in ipairs(memory.dice)do local die=getObjectFromGUID(guid);if die and die.getGMNotes()=="STA2E_ROLLER|"..self.getGUID() then die.destruct()end end
 memory.dice={}
end
local function roll(guid,color)
 local bag=getObjectFromGUID(guid)
 if not bag then broadcastToColor("This dice supply is missing.",color,{1,0.5,0.3});return end
 clear();local ticket=epoch;local a=geometry()
 local columns=math.min(6,math.max(2,math.floor(a.w/0.8)))
 local rows=math.ceil(memory.count/columns)
 for i=1,memory.count do
  local x=(((i-1)%columns)-(math.min(columns,memory.count)-1)/2)*(a.w*0.70/columns)
  local z=(math.floor((i-1)/columns)-(rows-1)/2)*(a.d*0.32/math.max(1,rows))
  local localPoint={x=a.cx+x/a.sx,y=a.y+1.8/a.sy,z=a.cz+z/a.sz}
  local position=self.positionToWorld(localPoint)
  bag.takeObject({position=position,rotation={math.random(0,359),math.random(0,359),math.random(0,359)},callback_function=function(die)
   if not die then return end
   if ticket~=epoch then die.destruct();return end
   die.setGMNotes("STA2E_ROLLER|"..self.getGUID());memory.dice[#memory.dice+1]=die.getGUID()
   Wait.frames(function()if ticket==epoch and getObjectFromGUID(die.getGUID())then die.randomize()end end,2)
  end})
 end
end
function attack(_,color)roll("00e112",color)end
function defense(_,color)roll("fd1d2b",color)end
function onObjectDrop(_,object)if object==self then redraw()end end
