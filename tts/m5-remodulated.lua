-- Integration with the user's October 4 Remodulated save.
-- Call the actual current navigation evaluator, including target acquisition,
-- intent, center approach, terrain avoidance, and public-position snapshots.
function M5.chooseManeuver(s)
    if not complete(s) then return nil,"Deploy the M5 ship first." end
    s.ai=s.ai or {};s.ai.enabled=true;s.ai.intent=s.ai.intent or "engage"
    s.side=s.side or "enemy"
    aiEvaluate(s)
    local plan=s.ai.plan
    if not plan then return nil,s.ai.message end
    return {key=plan.key,target=plan.targetId,range=plan.range,reason=s.ai.message}
end

function M5.selectTarget(s,requireArc)
    local candidates={}
    for _,target in pairs(STA2E.ships) do
        if target~=s and aiSide(s)~=aiSide(target) and not (target.combat and target.combat.destroyed) then
            local measure=MeasurementGeometry.measure(s,target)
            if measure and measure.range>=1 and measure.range<=3 and (not requireArc or measure.arcs.primary) then
                table.insert(candidates,{ship=target,range=measure.range,distance=measure.baseEdgeDistance})
            end
        end
    end
    table.sort(candidates,function(a,b)
        if a.distance~=b.distance then return a.distance<b.distance end
        return a.ship.instanceId<b.ship.instanceId
    end)
    return candidates[1] and candidates[1].ship or nil,candidates[1]
end

-- Existing movement already calls this hook. Use one action path for M5;
-- other AI ships retain their existing action evaluation.
local originalAfterMove=STA2E_AI_AfterMove
function STA2E_AI_AfterMove(s,key)
    if not isControlled(s) then return originalAfterMove(s,key) end
    M5.Events.emit(M5.TIMING.AFTER_MOVE,{ship=s,key=key})
    M5.runActionTree(s)
    s.ai.plan=nil
end

-- Remove the older refresh-based after-move hook: this save supplies an exact
-- movement completion callback, including terrain and movement cancellation.
refresh=previousRefresh

local originalM5Run=M5.run
function M5.run(color)
    if next(STA2E.pendingMoves) then return "Wait for movement to finish." end
    for _,s in pairs(STA2E.ships) do
        if isControlled(s) then
            s.ai=s.ai or {intent="engage"};s.ai.enabled=true;s.side=s.side or "enemy"
        end
    end
    return originalM5Run(color)
end
