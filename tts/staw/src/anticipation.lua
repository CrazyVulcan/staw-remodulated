-- Skill-aware interception using only public movement options and completed
-- movement history. Player state.maneuver and locked dial selections are never read.
;(function()
local P=STA2E_Playtest
local A={context=nil}
P.anticipation=A
function A.hasMoved(s)
 local state=s.state or {}
 return state.status=="action" or state.status=="complete"
  or (state.publicNavigation and state.publicNavigation.round==STA2E.game.round) or false
end
function A.movesLater(actor,target)
 if not actor or not target then return false,"no target" end
 if STA2E.game.phase~="activation" and STA2E.game.phase~="planning" then return false,"outside maneuver planning" end
 if A.hasMoved(target) then return false,"target already activated" end
 if STA2E.pendingMoves[target.instanceId] then return false,"target is currently moving" end
 local a,t=skillFor(actor),skillFor(target)
 if t>a then return true,"higher-skill target moves later" end
 if t==a and actor.owner~=target.owner and STA2E.game.initiative==actor.owner then return true,"initiative puts the AI first" end
 return false,"target moves before the AI or order is unresolved"
end
function STA2E_RecordPublicMove(s,key,start,finish)
 s.state.publicNavigation={round=STA2E.game.round,key=key,start=copy(start),finish=copy(finish)}
end
local function projectedMeasure(actorBoundary,targetBoundary)
 local nearest=MeasurementGeometry.nearestPoints(actorBoundary,targetBoundary)
 return {attackerBoundary=actorBoundary,targetBoundary=targetBoundary,baseEdgeDistance=nearest.distance,
  centerDistance=math.sqrt((actorBoundary.center.x-targetBoundary.center.x)^2+(actorBoundary.center.z-targetBoundary.center.z)^2),
  nearest=nearest,range=nearest.distance<=.02 and 0 or math.ceil(nearest.distance/RANGE_SEGMENT)}
end
function A.forecast(actor,target)
 local actorBase,targetBase=member(actor,"base"),member(target,"base")
 if not actorBase or not targetBase then return nil end
 local actorBoundary,targetBoundary=MeasurementGeometry.boundary(actor),MeasurementGeometry.boundary(target)
 if not actorBoundary or not targetBoundary then return nil end
 local p,r=targetBase.getPosition(),targetBase.getRotation()
 local start={x=p.x,z=p.z,yaw=r.y};local shape=baseShape(targetBase)
 local terrain=terrainSnapshot(targetBase);local blockers={}
 for _,item in ipairs(terrain) do if item.kind=="planet" then blockers[#blockers+1]={pose=item.pose,shape=item.shape,reason="planet"} end end
 for id,other in pairs(STA2E.ships) do
  if id~=actor.instanceId and id~=target.instanceId and A.hasMoved(other) and member(other,"base") and not (other.combat and other.combat.destroyed) then
   local base=member(other,"base");local q,rotation=base.getPosition(),base.getRotation()
   blockers[#blockers+1]={pose={x=q.x,z=q.z,yaw=rotation.y},shape=baseShape(base),reason="ship"}
  end
 end
 local history=target.state and target.state.publicNavigation
 local historicalKey=history and type(history.round)=="number" and history.round<STA2E.game.round and history.key or nil
 local options,total={},0
 for _,entry in ipairs(dialFor(target)) do
  local move=MOVE_DEFS[entry.key]
  if move then
   local stop=latestLegal(start,move,shape,blockers)
   local finish=pose(start,move,stop,shape.z)
   local prefix,speed=entry.key:match("^([A-Z]+)(%d+)$");speed=tonumber(speed) or 0
   local weight=({S=1.6,BL=1.2,BR=1.2,TL=.85,TR=.85,CA=.35,R=.4})[prefix] or .45
   weight=weight*(({[0]=.7,[1]=1,[2]=1.35,[3]=1.15})[speed] or .65)
   if entry.difficulty=="red" then weight=weight*.35 elseif entry.difficulty=="green" then weight=weight*1.1 end
   if entry.key==historicalKey then weight=weight*2 end
   local hits=movementTerrainHits(start,move,stop,shape,terrain)
   if #hits>0 then weight=weight*.25 end
   if P.edgeRisk(finish,shape)>50 then weight=weight*.08 end
   options[#options+1]={key=entry.key,move=move,weight=weight,finish=finish,boundary=P.project(targetBoundary,finish)}
   total=total+weight
  end
 end
 if #options==0 or total<=0 then return nil end
 local center={x=0,z=0};local yawX,yawZ=0,0
 for _,option in ipairs(options) do
  option.weight=option.weight/total
  center.x=center.x+option.finish.x*option.weight;center.z=center.z+option.finish.z*option.weight
  yawX=yawX+math.sin(math.rad(option.finish.yaw))*option.weight;yawZ=yawZ+math.cos(math.rad(option.finish.yaw))*option.weight
 end
 local seed=P.project(targetBoundary,{x=center.x,z=center.z,yaw=math.deg(math.atan2(yawX,yawZ))})
 return {targetId=target.instanceId,actorId=actor.instanceId,targetBoundary=targetBoundary,actorBoundary=actorBoundary,
  start=start,shape=shape,blockers=blockers,options=options,mean=center,historyKey=historicalKey,
  measure=projectedMeasure(actorBoundary,seed),scores={}}
end
-- Use the mean only to seed the old steering table. Final maneuver evaluation
-- scores every possible future footprint, not an imaginary mean-position ship.
local selectNow=P.selectTarget
P.selectTarget=function(s)
 local selected=selectNow(s);local context=A.context
 if context and context.actor==s and selected and selected.target.instanceId==context.forecast.targetId then
  selected.presentMeasure=selected.measure;selected.measure=context.forecast.measure;selected.projected=true
  selected.zone=AllianceAI.zone(selected.measure.attackerBoundary,selected.measure.targetBoundary.center)
 end
 return selected
end
function A.futureBoundary(forecast,option,actorFinish,actorShape)
 if not overlaps(option.finish,forecast.shape,actorFinish,actorShape) then return option.boundary end
 local blockers={}
 for _,blocker in ipairs(forecast.blockers) do blockers[#blockers+1]=blocker end
 blockers[#blockers+1]={pose=actorFinish,shape=actorShape,reason="ship"}
 local stop=latestLegal(forecast.start,option.move,forecast.shape,blockers)
 return P.project(forecast.targetBoundary,pose(forecast.start,option.move,stop,forecast.shape.z))
end
local scoreNow=P.moveScore
function A.score(actor,entry,snapshot,finish,stop,forecast)
 local projectedActor=P.project(snapshot.boundary,finish)
 local class=definition(actor.definitionId);local profile=class and class.arc or "90"
 local expected,coverage=0,0;local scored={}
 for _,option in ipairs(forecast.options) do
  local boundary=A.futureBoundary(forecast,option,finish,snapshot.shape)
  local score=scoreNow(actor,entry,snapshot,finish,boundary,stop)
  expected=expected+option.weight*score
  local distance=MeasurementGeometry.nearestPoints(projectedActor,boundary).distance
  local arcs=MeasurementGeometry.validateArc(projectedActor,boundary,profile)
  if distance>.02 and distance<=RANGE_SEGMENT*3 and (arcs.primary or arcs.rear or arcs.secondary) then coverage=coverage+option.weight end
  scored[#scored+1]={score=score,weight=option.weight}
 end
 table.sort(scored,function(a,b)return a.score>b.score end)
 local remaining,worst=.25,0
 for _,item in ipairs(scored) do
  local used=math.min(remaining,item.weight);worst=worst+used*item.score;remaining=remaining-used
  if remaining<.000001 then break end
 end
 local result=expected*.8+(worst/.25)*.2
 coverage=math.max(0,math.min(1,coverage))
 forecast.scores[entry.key]={score=result,expected=expected,coverage=coverage}
 return result
end
P.moveScore=function(s,entry,snapshot,finish,targetBoundary,stop)
 local context=A.context
 if context and context.actor==s then return A.score(s,entry,snapshot,finish,stop,context.forecast) end
 return scoreNow(s,entry,snapshot,finish,targetBoundary,stop)
end
local evaluateNow=aiEvaluate
aiEvaluate=function(s)
 local selected=selectNow(s)
 local later,reason=A.movesLater(s,selected and selected.target)
 local forecast=later and selected and A.forecast(s,selected.target) or nil
 local previous=A.context
 A.context=forecast and {actor=s,forecast=forecast} or nil
 local ok,errorMessage=pcall(evaluateNow,s)
 A.context=previous
 if not ok then error(errorMessage) end
 if not s.ai.plan then return end
 if forecast then
  local metric=forecast.scores[s.ai.plan.key]
  local summary={mode="possible-later-moves",targetId=forecast.targetId,actorSkill=skillFor(s),targetSkill=skillFor(selected.target),
   samples=#forecast.options,mean=forecast.mean,historyKey=forecast.historyKey,coverage=metric and metric.coverage or 0,reason=reason}
  s.ai.plan.anticipation=summary
  s.ai.lastDecision.anticipation=copy(summary)
  s.ai.message=s.ai.message.."\nAnticipating later movement (skill "..summary.actorSkill.." → "..summary.targetSkill.."): "..
   summary.samples.." possible maneuvers; "..math.floor(summary.coverage*100+.5).."% weighted firing coverage."
 else
  local summary={mode="current-position",reason=reason}
  s.ai.plan.anticipation=summary
  if s.ai.lastDecision then s.ai.lastDecision.anticipation=copy(summary) end
 end
end
-- Public activation progress and skill changes can invalidate a forecast even
-- when a base remains in the same place (Stop / blocked moves, skill edits).
local environmentNow=P.environment
P.environment=function()
 local rows={environmentNow()}
 for id,s in pairs(STA2E.ships) do
  rows[#rows+1]=id.."|skill="..tostring(skillFor(s)).."|moved="..tostring(A.hasMoved(s)).."|status="..tostring(s.state and s.state.status)
 end
 rows[#rows+1]="phase="..tostring(STA2E.game.phase).."|round="..tostring(STA2E.game.round).."|initiative="..tostring(STA2E.game.initiative)
 table.sort(rows);return table.concat(rows,";")
end
end)()
