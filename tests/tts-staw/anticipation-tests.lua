local P,A=STA2E_Playtest,STA2E_Playtest.anticipation
local function scenario(x,z,yaw,actorSkill,targetSkill)
 _reset();local actor=_ship("predictor","Red","S301")
 actor.ai={enabled=true,intent="engage"};actor.side="enemy";actor.skillOverride=actorSkill or 1;actor.state.dialOpen=true
 local target=_ship("later-target","Blue","S274");target.side="allied";target.skillOverride=targetSkill or 4
 _objects[target.refs.base].setPosition({x or 0,1,z or -12});_objects[target.refs.base].setRotation({0,yaw or 0,0})
 STA2E.game.phase="activation";return actor,target
end
local function plan(actor)
 STA2E_Command({object=_objects[actor.cardGUID],color=actor.owner,command="ai_evaluate"})
 return assert(actor.ai.plan,actor.ai.message)
end
test("Lower-skill AI forecasts several printed legal moves for a later-activating target",function()
 local s,t=scenario(0,-14,0);local p=plan(s)
 assert(p.anticipation.mode=="possible-later-moves" and p.anticipation.samples>3)
 assert(p.anticipation.targetSkill==4 and p.anticipation.actorSkill==1 and p.anticipation.mean.z<-14)
 assert(s.ai.message:find("Anticipating later movement",1,true) and p.anticipation.coverage>=0 and p.anticipation.coverage<=1.000001)
 local f=assert(A.forecast(s,t));local printed={}
 for _,move in ipairs(SHIP_DATA.classes[SHIP_DEFINITIONS.S274.profile].dial)do printed[move.key]=true end
 local count=0;for _,option in ipairs(f.options)do assert(printed[option.key] and MOVE_DEFS[option.key] and option.weight>0);count=count+1 end
 assert(count==p.anticipation.samples)
end)
test("Already-activated or lower-skill targets use their actual positions",function()
 local s,t=scenario(0,-12,180);t.state.status="complete"
 assert(plan(s).anticipation.mode=="current-position")
 t.state.status="action";assert(plan(s).anticipation.mode=="current-position")
 t.state.status="locked";s.skillOverride=6;assert(plan(s).anticipation.mode=="current-position")
 STA2E.game.phase="combat";s.skillOverride=1;assert(plan(s).anticipation.mode=="current-position")
end)
test("Equal-skill anticipation respects public initiative rather than guessing the hidden dial",function()
 local s,t=scenario(0,-12,0,3,3)
 STA2E.game.initiative="Red";assert(A.movesLater(s,t))
 STA2E.game.initiative="Blue";assert(not A.movesLater(s,t))
end)
test("Changing a later target's concealed maneuver cannot change the forecast or chosen AI maneuver",function()
 local s,t=scenario(5,-13,90)
 t.state.status="locked";t.state.maneuver="S1";local first=plan(s)
 local key,mean,coverage=first.key,first.anticipation.mean,first.anticipation.coverage
 t.state.maneuver="TR3";local second=plan(s)
 assert(second.key==key and second.anticipation.mean.x==mean.x and second.anticipation.mean.z==mean.z and math.abs(second.anticipation.coverage-coverage)<.000001)
 -- A trap also detects accidental reads of absent concealed-dial fields.
 t.state.maneuver=nil;setmetatable(t.state,{__index=function(_,k)if k=="maneuver" then error("Read a private target dial")end end})
 assert(plan(s).anticipation.mode=="possible-later-moves")
end)
test("Forecast weighting uses a previously completed public move without treating it as the next dial",function()
 local s,t=scenario(0,-14,0);STA2E.game.round=3
 local baseline=A.forecast(s,t);local before
 for _,option in ipairs(baseline.options)do if option.key=="S2" then before=option.weight end end
 assert(before)
 t.state.publicNavigation={round=2,key="S2",start={x=0,z=-8,yaw=0},finish={x=0,z=-14,yaw=0}}
 local forecast=A.forecast(s,t);assert(forecast.historyKey=="S2")
 for _,option in ipairs(forecast.options)do if option.key=="S2" then assert(option.weight>before)end end
 assert(#forecast.options>3)
end)
test("A completed maneuver is recorded publicly and Undo restores the previous movement history",function()
 _reset();local s=_ship("history","Blue","S274");STA2E.game.phase="activation";STA2E.game.round=2
 s.state.status="revealed";s.state.maneuver="S1";s.state.publicNavigation={round=1,key="S2"}
 STA2E_Command({object=_objects[s.cardGUID],color="Blue",command="move"});_drain()
 local public=assert(s.state.publicNavigation)
 assert(public.round==2 and public.key=="S1" and public.start and public.finish)
 assert(A.hasMoved(s))
 STA2E_Command({object=_objects[s.cardGUID],color="Blue",command="undo"});_drain()
 assert(s.state.publicNavigation.round==1 and s.state.publicNavigation.key=="S2" and not A.hasMoved(s))
end)
test("Completing a stationary target's activation invalidates an earlier forecast even without a position change",function()
 local s,t=scenario(0,-14,0);plan(s);t.state.status="complete"
 STA2E_Command({object=_objects[s.cardGUID],color="Red",command="ai_execute"})
 assert(not s.ai.plan and not STA2E.pendingMoves[s.instanceId])
end)
test("Changing skill after PLAN invalidates its anticipated move order",function()
 local s,t=scenario(0,-14,0);plan(s);t.skillOverride=0
 STA2E_Command({object=_objects[s.cardGUID],color="Red",command="ai_execute"})
 assert(not s.ai.plan and not STA2E.pendingMoves[s.instanceId])
end)
test("Public movement history and anticipated-plan summaries survive save and reload",function()
 local s,t=scenario(0,-14,0)
 t.state.publicNavigation={round=0,key="S2",start={x=0,z=-6,yaw=0},finish={x=0,z=-14,yaw=0}}
 plan(s);STA2E_Command({object=_objects[s.cardGUID],color="Red",command="open_dial"})
 local saved=onSave();onLoad(saved);_drain(20000)
 local actor=assert(STA2E.ships.predictor);local target=assert(STA2E.ships["later-target"])
 assert(target.state.publicNavigation.key=="S2" and actor.ai.plan.anticipation.samples>3)
end)
test("Intercept planning considers multiple future firing solutions for closing and crossing targets",function()
 local rows={};local changed=0
 for _,case in ipairs({{0,-10,180},{0,-16,180},{5,-12,90},{-5,-12,270},{0,-20,0}})do
  local s,t=scenario(case[1],case[2],case[3])
  t.state.status="complete";local current=plan(s).key
  t.state.status="locked";local anticipated=plan(s)
  if current~=anticipated.key then changed=changed+1 end
  rows[#rows+1]={x=case[1],z=case[2],yaw=case[3],current=current,anticipated=anticipated.key,
   sampleCount=anticipated.anticipation.samples,coverage=anticipated.anticipation.coverage,mean=anticipated.anticipation.mean}
 end
 assert(changed>=1,"Anticipation did not change any tested intercept maneuver")
 _auditLog("ANTICIPATION_CASES|"..JSON.encode(rows))
end)
