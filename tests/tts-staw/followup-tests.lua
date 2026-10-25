local P,F=STA2E_Playtest,STA2E_Playtest.follow
local function ship(id)
 local s=_ship(id,"Blue","S274");s.deployedOnce=false
 local m=_objects[s.refs.model];m.hidden={"Grey"}
 m.getInvisibleTo=function()return m.hidden end;m.setInvisibleTo=function(v)m.hidden=v end
 return s,_objects[s.refs.base],m
end
test("Model follow waits for the base's final settled pose and never moves the base",function()
 _reset();local s,b,m=ship("settle");local writes=0
 b.setPosition=function()writes=writes+1 end
 b.held_by_color="Blue";b.resting=false
 onObjectPickUp("Blue",b);assert(m.getPosition().y>b.getPosition().y+10 and m.locked and s.state.modelFollowPending)
 Wait.frames(function()b.held_by_color=nil;b._position={x=4,y=4,z=5};onObjectDrop("Blue",b)end,2)
 Wait.frames(function()b._position={x=6,y=2,z=8}end,7)
 Wait.frames(function()b._position={x=7,y=1.37,z=9};b._rotation={x=0,y=43,z=0};b.resting=true end,15)
 _drain()
 local p=m.getPosition();assert(writes==0 and p.x==7 and p.z==9)
 assert(math.abs(p.y-(1.37+SHIP_DEFINITIONS.S274.model.offsetY))<0.00001 and m.getRotation().y==43)
 assert(not s.state.modelFollowPending and #m.hidden==1 and m.hidden[1]=="Grey")
end)
test("Repeated pickup and drop do not run competing follow jobs or restore an old drop position",function()
 _reset();local s,b,m=ship("repeat")
 b.resting=true;onObjectPickUp("Blue",b);local job=F.jobs[s.instanceId]
 onObjectDrop("Blue",b);onObjectPickUp("Blue",b);assert(F.jobs[s.instanceId]==job)
 b._position={x=14,y=2.1,z=-4};onObjectDrop("Blue",b);_drain()
 assert(m.getPosition().x==14 and m.getPosition().z==-4 and b.getPosition().y==2.1 and not F.jobs[s.instanceId])
end)
test("Saving while a base is held restores the parked miniature after reload",function()
 _reset();local s,b,m=ship("parked-save");b.held_by_color="Blue"
 onObjectPickUp("Blue",b);local saved=onSave()
 b.held_by_color=nil;b.resting=true;b._position={x=5,y=1.3,z=11}
 onLoad(saved);_drain(20000)
 local restored=assert(STA2E.ships[s.instanceId]);assert(not restored.state.modelFollowPending)
 assert(m.getPosition().x==5 and m.getPosition().z==11 and m.getPosition().y>-100)
end)
test("Integrated base-models remain a single physical object without a park or follow job",function()
 _reset();local s,b=ship("integrated");s.refs.model=s.refs.base
 b._memory.role="baseModel";local before=b.getPosition()
 STA2E_FollowModel(s);assert(not F.jobs[s.instanceId] and b.getPosition().y==before.y)
end)
test("New scripted deployments and undo finish with the miniature at the settled base",function()
 _reset();local s,b,m=ship("scripted-follow")
 s.state.status="revealed";s.state.maneuver="S1"
 STA2E.game.phase="activation";STA2E_Command({object=_objects[s.cardGUID],color="Blue",command="move"});_drain()
 assert(math.abs(m.getPosition().x-b.getPosition().x)<0.00001 and not s.state.modelFollowPending)
 STA2E_Command({object=_objects[s.cardGUID],color="Blue",command="undo"});_drain()
 assert(math.abs(m.getPosition().z-b.getPosition().z)<0.00001 and not s.state.modelFollowPending)
end)
test("Modern, legacy and tall-object guides share the mat's surface height",function()
 _reset();local board=_object("ae9c49",nil,{0,0.53,0})
 board.getVisualBoundsNormalized=function()return {center={x=0,y=1,z=0},size={x=36.2,y=.10,z=36.2}}end
 assert(math.abs(P.guidePlane()-1.065)<.00001)
 local s,b=ship("flat-guide");b._position={x=0,y=4,z=0}
 b.getScale=function()return {x=2,y=3,z=4}end
 b.positionToLocal=function(v)return {x=v.x/2,y=(v.y-4)/3,z=v.z/4}end
 s.state.guideRange=3;STA2E_DrawShipGuides(s)
 for _,line in ipairs(b._lines)do for _,point in ipairs(line.points)do assert(math.abs(4+point[2]*3-P.guidePlane())<.00001)end end
 local tall=_object("tall",nil,{0,9,0})
 tall.getScale=function()return {x=1,y=2,z=1}end
 tall.positionToLocal=function(v)return {x=v.x,y=(v.y-9)/2,z=v.z}end
 STA2E_LegacyGuide({guid=tall.guid,owner="test",mode="ai"})
 for _,line in ipairs(tall._lines)do for _,point in ipairs(line.points)do assert(math.abs(9+point[2]*2-P.guidePlane())<.00001)end end
end)
test("Generic class references use a real generic ship card and never register an extra fleet ship",function()
 _reset();local s=ship("generic")
 local id,class=F.generic(s);assert(id and class=="Galaxy Class")
 local route;for _,candidate in ipairs(STA2E_GENERIC_REFERENCES.generic)do if candidate.id==id then route=candidate end end
 assert(route and route.class==class)
 local originalSpawn=spawnObjectData;local referenceValue
 spawnObjectData=function(params)
  if params.data and params.data.Nickname and params.data.Nickname:find("Generic Ship Reference",1,true) then referenceValue=params.data.Value end
  return originalSpawn(params)
 end
 F.ensureReference(s);F.ensureReference(s);_drain()
 spawnObjectData=originalSpawn;assert(referenceValue==0,"A reference card must not add fleet points")
 local ref=assert(_objects[s.refs.classReference]);local memory=ref.getTable("memory")
 assert(memory.role=="classReference" and memory.referenceId==id and memory.instanceId==s.instanceId)
 assert(ref.getName():find("Generic Ship Reference",1,true));local count=0;for _ in pairs(STA2E.ships)do count=count+1 end;assert(count==1)
 local guid=ref.guid;F.ensureReference(s);_drain();assert(s.refs.classReference==guid)
end)
test("Deploy Repair recreates a missing generic class reference and removal cleans it up",function()
 _reset();local s=ship("generic-repair");F.ensureReference(s);_drain()
 local original=s.refs.classReference;_objects[original].destruct();s.refs.classReference=nil
 STA2E_Command({object=_objects[s.cardGUID],color="Blue",command="deploy"});_drain()
 assert(s.refs.classReference~=original and _objects[s.refs.classReference])
 local guid=s.refs.classReference
 STA2E_Command({object=_objects[s.cardGUID],color="Blue",command="remove_ship"})
 STA2E_Command({object=_objects[s.cardGUID],color="Blue",command="remove_ship"});assert(not _objects[guid])
end)
test("Class-reference callbacks cancel safely when their ship is removed before spawning finishes",function()
 _reset();local s=ship("generic-late");F.ensureReference(s)
 _objects[s.cardGUID].destruct();STA2E.ships[s.instanceId]=nil;_drain()
 for _,o in pairs(_objects)do local m=o.getTable("memory");assert(not (m and m.role=="classReference" and m.instanceId==s.instanceId and not o._destroyed))end
end)
local function boxEnvironment()
 local box=_object("box",nil,{-29,1.4,.24})
 local scale={x=.257746518,y=.8591551,z=.7130987};local yaw=math.rad(270)
 box.getScale=function()return scale end
 box.getBoundsNormalized=function()return {offset={x=0,y=0,z=0},size={x=36.72*scale.x,y=1.11*scale.y,z=9.7308*scale.z}}end
 box.positionToWorld=function(v)
  local x,z=(v.x or v[1])*scale.x,(v.z or v[3])*scale.z
  return {x=-29+x*math.cos(yaw)+z*math.sin(yaw),y=1.4+(v.y or v[2])*scale.y,z=.24-x*math.sin(yaw)+z*math.cos(yaw)}
 end
 local env=setmetatable({self=box},{__index=_G});env._G=env
 assert(load(_playtestDiceSource(),"refined-dice-box","t",env))();env.onLoad("")
 return box,env,scale
end
test("Dice controls retain separate world-space button rectangles on the user's non-uniform box",function()
 _reset();local box,env,scale=boxEnvironment();assert(#box._buttons==6)
 local rectangles={}
 for _,b in ipairs(box._buttons)do
  local x,z=b.position[1]*scale.x,b.position[3]*scale.z
  local w=b.width/500*b.scale[1]*scale.x;local h=b.height/500*b.scale[3]*scale.z
  assert(math.abs(x)+w/2<18*scale.x and math.abs(z)+h/2<4.5*scale.z)
  assert(math.abs(b.position[2]*scale.y-(-.15*scale.y+.025))<.00001,"Button is not above the tray floor")
  for _,r in ipairs(rectangles)do assert(math.abs(x-r.x)>(w+r.w)/2 or math.abs(z-r.z)>(h+r.h)/2,"Overlapping dice buttons")end
  rectangles[#rectangles+1]={x=x,z=z,w=w,h=h}
 end
 local export={width=36.72*scale.x,depth=9.7308*scale.z,innerWidth=36*scale.x,innerDepth=9*scale.z,buttons={}}
 for i,r in ipairs(rectangles)do export.buttons[i]={label=box._buttons[i].label,x=r.x,z=r.z,width=r.w,height=r.h}end
 _auditLog("BOX_LAYOUT|"..JSON.encode(export))
end)
test("Dice spawn inside the moved and rotated user's box rather than a fixed world-space grid",function()
 _reset();local box,env=boxEnvironment();local positions={}
 local bag=_object("00e112");bag.takeObject=function(params)
  local die=_object("box-die-"..(#positions+1),nil,params.position);positions[#positions+1]=params.position
  params.callback_function(die);return die
 end
 for i=1,9 do env.more()end;env.attack(nil,"Blue");_drain();assert(#positions==12)
 for _,p in ipairs(positions)do assert(math.abs(p.x+29)<4.5*.7130987 and math.abs(p.z-.24)<18*.257746518 and p.y>1.4)end
 local unrelated=_object("unrelated-die");local saved=env.onSave();env.onLoad(saved);assert(env.memory.count==12)
 env.clear();assert(_objects[unrelated.guid]);for i=1,12 do assert(not _objects["box-die-"..i])end
end)
test("Two-player helper draws its lines on the shared guide plane",function()
 _reset();local board=_object("ae9c49",nil,{0,.53,0})
 board.getScale=function()return {x=1.89,y=1.87,z=1.89}end
 board.getRotation=function()return {x=0,y=90,z=0}end
 board.getVisualBoundsNormalized=function()return {center={x=0,y=1,z=0},size={x=36.2,y=.10,z=36.2}}end
 local helper=_object("2a5e01",nil,{-22,-.38,0})
 local env=setmetatable({self=helper},{__index=_G});env._G=env
 assert(load(_returnedObjectSource("2a5e01"),"standard-helper","t",env))();env.onLoad("");env.toggleSetup(nil,"Blue")
 assert(#helper._lines==3)
 for _,line in ipairs(helper._lines)do for _,p in ipairs(line.points)do assert(math.abs(p[2]+helper.getPosition().y-P.guidePlane())<.00001)end end
end)
