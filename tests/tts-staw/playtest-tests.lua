local P=STA2E_Playtest
local function setupAI(id,position)
 local s=_ship(id,"Red","S301");s.side="enemy";s.ai={enabled=true,intent="engage"}
 s.state.dialOpen=true;_objects[s.refs.base].setPosition(position or {0,1,0})
 return s
end
local function cmd(s,command,color)
 STA2E_Command({object=_objects[s.cardGUID],command=command,color=color or "Red"})
end
test("Playtest AI selects distant living opponents and excludes friendlies and destroyed ships",function()
 _reset();local s=setupAI("enemy");local friendly=setupAI("friendly",{0,1,-5})
 local dead=_ship("dead","Blue");dead.combat={destroyed=true};_objects[dead.refs.base].setPosition({0,1,-7})
 local player=_ship("player","Red");player.side="allied";_objects[player.refs.base].setPosition({0,1,-40})
 local selected=assert(P.selectTarget(s));assert(selected.target==player)
 cmd(s,"ai_evaluate");assert(s.ai.plan and s.ai.plan.targetId==player.instanceId and not s.ai.plan.centerTarget)
 assert(s.ai.message:find("closing into weapon range",1,true))
end)
test("Playtest AI waits without a deployed opponent instead of executing a center plan",function()
 _reset();local s=setupAI("alone");STA2E.game.phase="activation"
 cmd(s,"ai_evaluate");assert(not s.ai.plan and s.ai.message:find("No living opponent",1,true))
 cmd(s,"ai_execute");assert(not STA2E.pendingMoves[s.instanceId] and s.state.status=="planning")
end)
test("Playtest target selection prioritizes usable proximity over a distant forward zone",function()
 _reset();local s=setupAI("selector")
 local near=_ship("near","Blue");_objects[near.refs.base].setPosition({6,1,0})
 local far=_ship("far","Green");_objects[far.refs.base].setPosition({0,1,-30})
 assert(P.selectTarget(s).target==near)
end)
test("AI no longer sees a destroyed target as a valid cached execution",function()
 _reset();local s=setupAI("invalidate");local t=_ship("opponent","Blue");_objects[t.refs.base].setPosition({0,1,-12})
 STA2E.game.phase="activation";cmd(s,"ai_evaluate");assert(s.ai.plan)
 t.combat={destroyed=true};cmd(s,"ai_execute");assert(not s.ai.plan and not STA2E.pendingMoves[s.instanceId])
end)
test("Automatic tactics use concrete reasons while distance overrides are explicit",function()
 _reset();local s=setupAI("tactics");local t=_ship("opponent","Blue");_objects[t.refs.base].setPosition({0,1,-10})
 cmd(s,"ai_evaluate");assert(s.ai.intent=="engage" and s.ai.message:find("Auto:",1,true))
 local markup=_objects[s.refs.dial]._xml
 assert(not markup:find('>ENGAGE<',1,true) and not markup:find('>CHASE<',1,true) and not markup:find('>ESCAPE<',1,true))
 cmd(s,"tactic_escape");cmd(s,"ai_evaluate");assert(s.ai.intent=="escape" and s.ai.message:find("Manual tactic",1,true))
 cmd(s,"tactic_auto");cmd(s,"ai_evaluate");assert(s.ai.intent=="engage" and not s.ai.tacticOverride)
end)
test("ACT AI and the AI dial choose the same current target and maneuver",function()
 _reset();local s=setupAI("samepath");local t=_ship("opponent","Blue");_objects[t.refs.base].setPosition({0,1,-12})
 STA2E.game.phase="activation";cmd(s,"ai_evaluate");local key=s.ai.plan.key
 STA2E_AllianceActivateAI({instanceId=s.instanceId,color="Blue"})
 assert(s.state.maneuver==key and s.ai.lastDecision.targetId==t.instanceId)
 _drain();assert(s.aiActivatedRound==1)
end)
test("Explicit movement contact prevents an AI action and red maneuvers retain existing Aux",function()
 _reset();local s=setupAI("contact");s.state.lastMoveBlocked=true;s.state.status="complete"
 STA2E_AI_AfterMove(s,"S1");assert(s.state.status=="complete" and s.ai.lastAction.key=="SKIP")
 s.state.lastMoveBlocked=false;s.state.status="action"
 local token=_object("aux");token.setGMNotes("STA2E_SHIP_TOKEN|"..s.instanceId.."|AUX")
 STA2E_AI_AfterMove(s,"CA3");assert(not token._destroyed and s.state.aiSkipAction)
end)
test("AI removal of existing Aux consumes its action rather than spawning another token",function()
 _reset();local s=setupAI("aux-action");s.state.status="action"
 local token=_object("aux");token.setGMNotes("STA2E_SHIP_TOKEN|"..s.instanceId.."|AUX")
 token.getData=function()return {Name="BlockSquare"}end
 STA2E_AI_AfterMove(s,"S1");assert(token._destroyed and s.state.action=="CLEAR_AUX" and s.state.status=="complete")
end)
test("AI does not choose Target Lock or Regenerate without valid range or known damage",function()
 _reset();local s=setupAI("actions");local t=_ship("far");_objects[t.refs.base].setPosition({0,1,-40})
 s.capabilities.actions={"TL","REG"};_object("57c840");_object("0afb47")
 assert(STA2E_AllianceChooseAction({ship=s})==nil)
end)
test("Board risk follows translated rotated and scaled active maps",function()
 _reset();STA2E.game.alliance={active=true,missionObjects={frame={x=100,z=-50,yaw=90,halfX=12,halfZ=20}}}
 assert(P.edgeRisk({x=100,z=-50,yaw=90},{x=1,z=1})==0)
 assert(P.edgeRisk({x=100,z=-36,yaw=90},{x=1,z=1})>100)
end)
test("Repeated dial toggles preserve position and rotation from every physical entry point",function()
 _reset();local s=_ship("dial","Blue");local d=_objects[s.refs.dial]
 d.setPosition({9,2,11});d.setRotation({0,37,0})
 for _,object in ipairs({_objects[s.cardGUID],_objects[s.refs.base],d}) do
  for i=1,4 do STA2E_Command({object=object,color="Blue",command="open_dial"}) end
 end
 assert(d.getPosition().x==9 and d.getPosition().y==2 and d.getPosition().z==11 and d.getRotation().y==37)
end)
test("Cooperative dial visibility and card management include teammates while ordinary opponents stay restricted",function()
 _reset();local s=_ship("coop","Blue");s.side="allied"
 local upgrade=_object("upgrade",{schemaVersion=1,instanceId=s.instanceId,cardGUID=s.cardGUID,role="upgrade"})
 assert(not P.canManage(s,"Green"))
 STA2E.game.alliance={active=true};assert(P.canManage(s,"Green"))
 STA2E_ManageCard({object=upgrade,color="Green"});assert(STA2E.manageCard.Green==upgrade.guid)
 cmd(s,"open_dial","Green");local markup=_objects[s.refs.dial]._xml
 assert(markup:find('visibility="Blue|Red|Green|Purple|Orange|Yellow|Black"',1,true))
 STA2E.game.alliance.active=false;assert(not P.canManage(s,"Green"))
end)
test("Ownership transfer updates linked component metadata without changing allegiance",function()
 _reset();local s=_ship("transfer","Blue");s.side="allied"
 local base=_objects[s.refs.base];base.getCustomObject=function()return {}end;base.setCustomObject=function(v)base._custom=v end;base.reload=function()return base end
 cmd(s,"owner_Green","Blue")
 assert(s.owner=="Green" and s.side=="allied")
 for _,role in ipairs({"base","model","dial","reference"}) do assert(_objects[s.refs[role]].getTable("memory").owner=="Green") end
 assert(_objects[s.cardGUID].getTable("memory").owner=="Green")
end)
test("Ownership changes require control and cannot run during movement",function()
 _reset();local s=_ship("permission","Blue");cmd(s,"owner_Red","Green");assert(s.owner=="Blue")
 STA2E.pendingMoves[s.instanceId]=true;cmd(s,"owner_Red","Blue");assert(s.owner=="Blue")
end)
test("Remove ship works after base loss and deletes linked pieces only after confirmation",function()
 _reset();local s=_ship("remove","Blue");local unrelated=_object("unrelated")
 _objects[s.refs.base].destruct();s.refs.base=nil
 local token=_object("shield");token.setGMNotes("STA2E_ALLIANCE_SHIELD|"..s.instanceId)
 cmd(s,"remove_ship","Blue");assert(STA2E.ships[s.instanceId])
 cmd(s,"remove_ship","Blue");assert(not STA2E.ships[s.instanceId] and not _objects[s.cardGUID] and not _objects[s.refs.model] and not _objects[token.guid] and _objects.unrelated==unrelated)
end)
test("Range measurement and AI sector tools do not consume actions or change maneuvers",function()
 _reset();local s=_ship("range","Blue");local t=_ship("other","Red");_objects[t.refs.base].setPosition({0,1,-8})
 s.state.maneuver="S2";s.state.status="action"
 cmd(s,"quick_range","Blue");assert(s.state.guideRange==3 and s.state.maneuver=="S2" and s.state.status=="action")
 cmd(s,"quick_ai_arcs","Blue");assert(s.state.aiSectors and #_objects[s.refs.base]._lines>0)
 cmd(s,"quick_ai_arcs","Blue");assert(not s.state.aiSectors)
 cmd(s,"ship_settings","Blue");assert(_objects[s.refs.dial]._xml:find("OWNERSHIP",1,true)==nil and _objects[s.refs.dial]._xml:find("Owner:",1,true))
end)
test("AI shared tool pages remain available instead of being overwritten by the AI dashboard",function()
 _reset();local s=setupAI("ai-tools");cmd(s,"tool_arcs")
 local markup=_objects[s.refs.dial]._xml;assert(markup:find('id="tool_measure"',1,true))
 cmd(s,"ship_settings");assert(_objects[s.refs.dial]._xml:find('id="tactic_auto"',1,true))
end)
test("Measurements produce a persistent per-player status that can be dismissed",function()
 _reset();P.notice={};local s=_ship("source");local t=_ship("target","Red");_objects[t.refs.base].setPosition({0,1,-8})
 cmd(s,"quick_range","Blue");_drain();assert(P.notice.Blue and _xml:find('playtest_notice_Blue',1,true))
 Time.time=Time.time+60;hud();_drain();assert(_xml:find('playtest_notice_Blue',1,true))
 STA2E_PlaytestCloseNotice(Player.Blue,"","notice_Blue");_drain();assert(not P.notice.Blue)
end)
test("Ship control settings survive card-memory and Global save reload",function()
 _reset();local s=setupAI("saved");cmd(s,"tactic_escape");cmd(s,"owner_Green");s.state.basePlaneY=1.15
 cmd(s,"open_dial");local saved=onSave();onLoad(saved);_drain()
 local restored=assert(STA2E.ships.saved)
 assert(restored.owner=="Green" and restored.side=="enemy" and restored.ai.tacticOverride=="escape" and restored.state.basePlaneY==nil)
end)
test("Moving a friendly blocker after PLAN invalidates the route before execution",function()
 _reset();local s=setupAI("route");local t=_ship("player");_objects[t.refs.base].setPosition({0,1,-12})
 local blocker=setupAI("blocker",{12,1,12});STA2E.game.phase="activation"
 cmd(s,"ai_evaluate");assert(s.ai.plan);_objects[blocker.refs.base].setPosition({0,1,-5})
 cmd(s,"ai_execute");assert(not s.ai.plan and not STA2E.pendingMoves[s.instanceId] and s.ai.message:find("Board positions changed",1,true))
end)
test("Automatic distance opening uses recorded hull and shields without guessing physical damage",function()
 _reset();local s=setupAI("hurt");local t=_ship("player");_objects[t.refs.base].setPosition({0,1,-9})
 s.combat={hull=1,maxHull=6,shields=0};cmd(s,"ai_evaluate");assert(s.ai.intent=="escape")
 s.combat={hull=6,maxHull=6,shields=0};cmd(s,"ai_evaluate");assert(s.ai.intent=="engage")
end)
test("Target Lock uses the actual Target Lock bag and records the chosen opponent",function()
 _reset();local s=setupAI("lock");local t=_ship("player");_objects[t.refs.base].setPosition({0,1,-10})
 s.capabilities.actions={"TL"};s.state.status="action"
 local count=0;local bag=_object("57c840")
 bag.takeObject=function(params)count=count+1;local token=_object("lock-token");params.callback_function(token);return token end
 local wrong=_object("1649f4");wrong.takeObject=function()error("Excelsior model bag used as Target Lock")end
 STA2E_AI_AfterMove(s,"S1")
 assert(count==1 and s.state.action=="TL" and s.state.targetLockId==t.instanceId and s.ai.lastAction.targetId==t.instanceId)
end)
test("Tactical decisions do not read or change a player's concealed maneuver",function()
 _reset();local s=setupAI("public");local t=_ship("secret");_objects[t.refs.base].setPosition({0,1,-9})
 t.state.maneuver="TL1";cmd(s,"ai_evaluate");local key=s.ai.plan.key
 t.state.maneuver="TR3";cmd(s,"ai_evaluate");assert(s.ai.plan.key==key and t.state.maneuver=="TR3")
end)
test("Printed-speed manual movement layout places speed 1 below speed 6",function()
 _reset();local s=setupAI("manual");cmd(s,"tool_moves")
 local markup=_objects[s.refs.dial]._xml
 local six=assert(markup:match('id="tool_move_S6".-position="[%d.-]+ ([%d.-]+)'))
 local one=assert(markup:match('id="tool_move_S1".-position="[%d.-]+ ([%d.-]+)'))
 assert(tonumber(one)<tonumber(six))
end)
test("Physical AI card has action symbols and identifies its selected target",function()
 _reset();local s=setupAI("icons");local t=_ship("player");_objects[t.refs.base].setPosition({0,1,-9})
 cmd(s,"ai_evaluate");local markup=_objects[s.cardGUID]._xml
 assert(markup:find("◇ Evade",1,true) and markup:find("⊕ Target Lock",1,true) and markup:find("Target: player",1,true))
end)
test("Rolling box cancels asynchronous dice from an obsolete roll",function()
 _reset();local tray=_object("tray");local env=setmetatable({self=tray},{__index=_G});env._G=env
 assert(load(_playtestDiceSource(),"dice-box-late","t",env))();env.onLoad("")
 local callbacks={};local bag=_object("00e112");bag.takeObject=function(params)callbacks[#callbacks+1]=params.callback_function end
 env.attack(nil,"Blue");env.clear()
 for i,callback in ipairs(callbacks)do local die=_object("late-"..i);callback(die);assert(die._destroyed)end
 assert(#env.memory.dice==0)
end)
