local G,P=STA2E.MeasurementGeometry,STA2E_Playtest
local function near(a,b)assert(math.abs(a-b)<.00001,tostring(a).." ~= "..tostring(b))end
local function pair(id)
 local s=_ship(id,"Blue","S274")
 local b,m=_objects[s.refs.base],_objects[s.refs.model]
 m.getInvisibleTo=function()return m._hidden or {}end;m.setInvisibleTo=function(v)m._hidden=v end
 return s,b,m
end
local function bounds(b,x,z,ox,oz)
 b.getBoundsNormalized=function()return {size={x=x,y=.2,z=z},offset={x=ox or 0,y=0,z=oz or 0}}end
end

test("Measurement boundaries rotate the collider center instead of using the model pivot",function()
 _reset();local s,b=pair("offset-boundary");bounds(b,4,6,.5,.75)
 b._position={x=10,y=1,z=20};b._rotation={x=0,y=90,z=0}
 local a=G.boundary(s);near(a.center.x,10.75);near(a.center.z,19.5)
 near(a.points[1].x,7.75);near(a.points[1].z,21.5)
 local t,tb=pair("offset-target");bounds(tb,4,6);tb._position={x=20.25,y=1,z=19.5};tb._rotation={x=0,y=90,z=0}
 local measure=G.measure(s,t);near(measure.baseEdgeDistance,3.5);assert(measure.range==1)
end)

test("Predicted AI footprints preserve the offset through a changed heading",function()
 _reset();local s,b=pair("offset-prediction");bounds(b,4,6,.5,.75);b._rotation={x=0,y=90,z=0}
 local future=P.project(G.boundary(s),{x=0,z=0,yaw=180})
 near(future.center.x,-.5);near(future.center.z,-.75)
 b._position={x=0,y=1,z=0};b._rotation={x=0,y=180,z=0};local actual=G.boundary(s)
 for i,p in ipairs(future.points)do near(p.x,actual.points[i].x);near(p.z,actual.points[i].z)end
end)

test("Modern and legacy arc lines use the same offset base with independent X and Z scale",function()
 _reset();local s,b=pair("offset-guides");bounds(b,4,8,.6,1.2)
 b.getScale=function()return {x=2,y=1,z=4}end
 s.state.guideArc=true;STA2E_DrawShipGuides(s)
 local first=b._lines[1].points[1];near(first[1]*2,-1.4);near(first[3]*4,-2.8)
 local modernX,modernZ=first[1],first[3]
 s.state.guideArc=false;STA2E_DrawShipGuides(s)
 STA2E_LegacyGuide({guid=b.guid,owner="offset-test",mode="front90"})
 first=b._lines[1].points[1];near(first[1],modernX);near(first[3],modernZ)
 STA2E_LegacyGuide({guid=b.guid,owner="offset-test",mode="ai"})
 first=b._lines[4].points[1];near(first[1]*2,-1.4);near(first[3]*4,-2.8)
end)

test("A 180-degree arc includes the forward half beside the base, with its origin at the center",function()
 _reset();local s=pair("arc-180");local a=G.boundary(s)
 local front={center={x=4,z=-.5},points={{x=4,z=-.5}},yaw=0,footprint={}}
 local behind={center={x=4,z=.5},points={{x=4,z=.5}},yaw=0,footprint={}}
 assert(G.validateArc(a,front,"180").primary)
 assert(not G.validateArc(a,front,"90").primary)
 assert(not G.validateArc(a,behind,"180").primary)
end)

test("Echo bank landing centers are invariant to a different pivot on the same physical base",function()
 _reset();local s,b=pair("echo-offset");bounds(b,2.8,2.8)
 b._position={x=0,y=1,z=0}
 local session={instanceId=s.instanceId,side="Left",template="BANK_1_FORWARD"}
 local centered=STA2E.SensorEchoController.calculate(session)
 bounds(b,2.8,2.8,.3,1.1);b._position={x=-.3,y=1,z=-1.1}
 local shifted=STA2E.SensorEchoController.calculate(session)
 local k=math.sqrt(.5)
 for i,c in ipairs(shifted)do near(c.x+.3*k+1.1*k,centered[i].x);near(c.z-.3*k+1.1*k,centered[i].z)end
end)

test("A manual base placement without pickup or drop events still restores the miniature after settling",function()
 _reset();local s,b,m=pair("missed-event");local writes=0;b.setPosition=function()writes=writes+1 end
 b._position={x=9,y=1.4,z=-6};b.resting=false;P.follow.scan()
 Wait.frames(function()b._position={x=11,y=1.2,z=-8};b._rotation={x=0,y=83,z=0};b.resting=true end,10)
 _drain();assert(writes==0);near(m.getPosition().x,11);near(m.getPosition().z,-8);near(m.getRotation().y,83)
 near(m.getPosition().y,1.2+SHIP_DEFINITIONS.S274.model.offsetY)
end)

test("Dropping the miniature by hand realigns it without moving its base",function()
 _reset();local s,b,m=pair("model-drop");b._position={x=7,y=1.3,z=8};local writes=0;b.setPosition=function()writes=writes+1 end
 m._position={x=-9,y=5,z=12};m.held_by_color="Blue";P.follow.scan();assert(not P.follow.jobs[s.instanceId])
 m.held_by_color=nil;onObjectDrop("Blue",m);_drain()
 near(m.getPosition().x,7);near(m.getPosition().z,8);assert(writes==0 and m.locked)
end)

test("An interrupted long drag is recovered after release even when its drop event is missed",function()
 _reset();local s,b,m=pair("long-drag");b.held_by_color="Blue";onObjectPickUp("Blue",b)
 Wait.time(function()
  assert(m.getPosition().y==-1000);b.held_by_color=nil;b._position={x=18,y=1.2,z=12};b.resting=true;P.follow.scan()
 end,31)
 _drain();near(m.getPosition().x,18);near(m.getPosition().z,12);assert(not s.state.modelFollowPending)
end)

test("A linked cloak token opens the full Echo GUI, including reverse bank and Back placement",function()
 _reset();local s,b=pair("cloak-gui");local token=_object("linked-cloak")
 token.setGMNotes("STA2E_SHIP_TOKEN|"..s.instanceId.."|CLK")
 STA2E_CloakEcho({source=token,color="Blue"});_drain();assert(_xml:find("echo_Blue_side_Left",1,true))
 STA2E_SensorEchoAction(Player.Blue,"","echo_Blue_side_Left")
 STA2E_SensorEchoAction(Player.Blue,"","echo_Blue_template_BANK_1_REVERSE")
 local session=assert(STA2E.sensorEcho.Blue);assert(#session.candidates==3 and session.candidates[3].name=="Back")
 local expected=session.candidates[3]
 STA2E_SensorEchoAction(Player.Blue,"","echo_Blue_commit_3");_drain()
 near(b.getPosition().x,expected.x);near(b.getPosition().z,expected.z);assert(s.undo and not STA2E.sensorEcho.Blue)
end)

test("Manual cloak tokens resolve one nearby friendly base and reject ambiguous or unauthorized ships",function()
 _reset();local a,ab=pair("cloak-near-a");local b,bb=pair("cloak-near-b")
 ab._position={x=-1.5,y=1,z=0};bb._position={x=1.5,y=1,z=0}
 local token=_object("manual-cloak",nil,{0,1,0});STA2E.sensorEcho.Blue=nil
 STA2E_CloakEcho({source=token,color="Blue"});assert(not STA2E.sensorEcho.Blue)
 token._position={x=-1.5,y=1,z=0};STA2E_CloakEcho({source=token,color="Blue"});assert(STA2E.sensorEcho.Blue.instanceId==a.instanceId)
 token.setGMNotes("STA2E_SHIP_TOKEN|"..a.instanceId.."|CLK");STA2E.sensorEcho.Red=nil
 STA2E_CloakEcho({source=token,color="Red"});assert(not STA2E.sensorEcho.Red)
end)

test("Either cloak face launches Echo directly and script repair reloads an older token only once",function()
 _reset();local s=pair("cloak-script");local token=_object("cloak-script-token");token.setGMNotes("STA2E_SHIP_TOKEN|"..s.instanceId.."|CLK")
 local source,reloads="",0;local env=setmetatable({self=token},{__index=_G});env._G=env
 token.getLuaScript=function()return source end;token.setLuaScript=function(code)source=code end
 token.call=function(name,args)if env[name] then return env[name](args)end end
 token.reload=function()reloads=reloads+1;assert(load(source,"@cloak-token","t",env))();env.onLoad();return token end
 STA2E_InstallCloakEcho(token);_drain();assert(reloads==1 and #token._buttons==2)
 env.STA2E_Echo(nil,"Blue");assert(STA2E.sensorEcho.Blue.instanceId==s.instanceId)
 STA2E_InstallCloakEcho(token);_drain();assert(reloads==1)
end)

test("The cloak action installs Echo on a token that came from an older bag",function()
 _reset();local s=pair("cloak-spawn");local token=_object("spawned-cloak");local installed
 token.getLuaScript=function()return "old cloak script" end;token.setLuaScript=function(code)installed=code end;token.reload=function()return token end
 local bag=_object("8d45a9");bag.takeObject=function(params)params.callback_function(token);return token end
 s.state.status="action";STA2E.game.phase="activation"
 STA2E_Command({object=_objects[s.cardGUID],color="Blue",command="action_CLK"});_drain()
 assert(installed==CLOAK_TOKEN_SCRIPT and token.getGMNotes()=="STA2E_SHIP_TOKEN|"..s.instanceId.."|CLK")
end)
