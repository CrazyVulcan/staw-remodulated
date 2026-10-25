local geometry=STA2E.MeasurementGeometry
local function pointBoundary(bearing,yaw)
    local a=math.rad(bearing+(yaw or 0));local p={x=-10*math.sin(a),z=-10*math.cos(a)}
    return {center=p,points={p},yaw=0,footprint={}}
end
test("Station arc includes all three primary sectors at multiple headings",function()
    for _,yaw in ipairs({0,45,90,180,270}) do
        local attacker={center={x=0,z=0},yaw=yaw,footprint={}}
        for _,angle in ipairs({0,44,120,164,240,284}) do
            assert(geometry.validateArc(attacker,pointBoundary(angle,yaw),'three-primary-90').primary,"Missing sector "..angle.." at heading "..yaw)
        end
    end
end)
test("Station arc preserves the three gaps between sectors",function()
    local attacker={center={x=0,z=0},yaw=0,footprint={}}
    for _,angle in ipairs({46,60,74,166,180,194,286,300,314}) do
        assert(not geometry.validateArc(attacker,pointBoundary(angle),'three-primary-90').primary,"Gap incorrectly in arc: "..angle)
    end
end)
test("Station guide draws three distinct sectors",function()
    _reset();local s=_ship('station-lines','Blue','S075');s.state.guideArc=true
    STA2E_DrawShipGuides(s)
    local lines=_objects[s.refs.base]._lines
    assert(#lines==9,"Expected three range contours per sector, got "..#lines)
    local directions={}
    for _,line in ipairs(lines) do local p=line.points[2];directions[string.format('%.2f,%.2f',p[1],p[3])]=true end
    local n=0;for _ in pairs(directions)do n=n+1 end;assert(n==9)
end)
local function guide(params)assert(STA2E_LegacyGuide(params),'Guide rejected')end
test("Legacy guide bridge implements every supported mode",function()
    _reset();local base=_object('legacy-modes')
    for _,mode in ipairs({'range1','range2','range3','range123','front90','rear90','front180','ai','all'})do
        guide({guid=base.guid,owner='modes',mode=mode});assert(#base._lines>0,mode)
        for _,line in ipairs(base._lines)do assert(#line.points>=2)end
    end
    assert(not STA2E_LegacyGuide({guid=base.guid,mode='invalid'}))
    assert(not STA2E_LegacyGuide({guid='absent',mode='range1'}))
    assert(not STA2E_LegacyGuide(false))
end)
test("Legacy overlays preserve existing lines and clear by owner",function()
    _reset();local base=_object('legacy-owners');local baseline={points={{0,0,0},{1,0,0}},color={1,1,1}}
    base._lines={baseline};base.locked=true;base.createButton({label='original'})
    guide({guid=base.guid,owner='a',mode='range1'});assert(#base._lines==2)
    guide({guid=base.guid,owner='b',mode='range2'});assert(#base._lines==3)
    guide({guid=base.guid,owner='a',mode='clear'});assert(#base._lines==2)
    guide({guid=base.guid,owner='b',mode='clear'});assert(#base._lines==1 and base._lines[1]==baseline)
    assert(base.locked and #base._buttons==1)
end)
test("Legacy overlays follow modern guide redraw without restoring stale lines",function()
    _reset();local s=_ship('legacy-modern');local base=_objects[s.refs.base]
    guide({guid=base.guid,owner='helper-modern',mode='range1'});assert(#base._lines==1)
    s.state.guideArc=true;STA2E_DrawShipGuides(s);local arcs=#base._lines;assert(arcs>1)
    s.state.guideRange=2;STA2E_DrawShipGuides(s);local count=#base._lines;assert(count==arcs+2)
    guide({guid=base.guid,owner='helper-modern',mode='clear'});assert(#base._lines==count-1)
    s.state.guideRange=0;s.state.guideArc=false;STA2E_DrawShipGuides(s);assert(#base._lines==0)
end)
test("Destroying one legacy helper clears only its own overlay",function()
    _reset();local base=_object('legacy-delete-base');local helper=_object('legacy-delete-helper')
    guide({guid=base.guid,owner=helper.guid,mode='range1'});guide({guid=base.guid,owner='other',mode='range2'})
    helper.destruct();onObjectDestroy(helper);assert(#base._lines==1)
    guide({guid=base.guid,owner='other',mode='clear'});assert(#base._lines==0)
end)
test("Echo previews preserve helper overlays and cancellation restores current guides",function()
    _reset();local s=_ship('echo-overlay');local base=_objects[s.refs.base]
    guide({guid=base.guid,owner='echo-helper',mode='range1'})
    STA2E_StartSensorEcho({color='Blue',instanceId=s.instanceId,sourceType='ship'})
    STA2E_SensorEchoAction(Player.Blue,'','echo_Blue_side_Left')
    STA2E_SensorEchoAction(Player.Blue,'','echo_Blue_template_STRAIGHT_1')
    local candidates=STA2E.sensorEcho.Blue.candidates;assert(#base._lines==#candidates+1)
    guide({guid=base.guid,owner='echo-helper',mode='clear'});assert(#base._lines==#candidates)
    guide({guid=base.guid,owner='echo-helper',mode='range2'})
    STA2E_SensorEchoAction(Player.Blue,'','echo_Blue_cancel');assert(#base._lines==1)
    guide({guid=base.guid,owner='echo-helper',mode='clear'});assert(#base._lines==0)
end)
local function m5Ship(id,cards)
    local s=_ship(id);STA2E_M5Attach(s,{shipCardId='M5S001',cards=cards or {}});return s
end
local function targets()
    _reset();local s=m5Ship('focus-attacker');local near=_ship('near','Red');local far=_ship('far','Red')
    _objects[near.refs.base].setPosition({0,1,-5});_objects[far.refs.base].setPosition({0,1,-10})
    STA2E.game.m5={fleetFocus={},fleetFocusRound={}}
    return s,near,far
end
test("M5 focus overrides nearest target only in its recorded round",function()
    local s,near,far=targets();assert(STA2E.M5.selectTarget(s,true)==near)
    STA2E.game.m5.fleetFocus.Blue=far.instanceId;STA2E.game.m5.fleetFocusRound.Blue=1
    assert(STA2E.M5.selectTarget(s,true)==far)
    STA2E.game.round=2;assert(STA2E.M5.selectTarget(s,true)==near)
end)
test("M5 focus cannot bypass range, arc, side, or destroyed state",function()
    local s,near,far=targets();STA2E.game.m5.fleetFocus.Blue=far.instanceId;STA2E.game.m5.fleetFocusRound.Blue=1
    for _,pos in ipairs({{0,1,-40},{0,1,10}})do _objects[far.refs.base].setPosition(pos);assert(STA2E.M5.selectTarget(s,true)==near)end
    _objects[far.refs.base].setPosition({0,1,-10});far.combat={destroyed=true};assert(STA2E.M5.selectTarget(s,true)==near)
    far.combat=nil;far.side=s.side;assert(STA2E.M5.selectTarget(s,true)==near)
end)
test("Focused Barrage records target and round at declaration",function()
    local s,near=targets();s.m5.programs={'focused_barrage'}
    local context=STA2E.M5.Events.emit(STA2E.M5.TIMING.ATTACK_DECLARE,{attacker=s,defender=near,weapon='primary',attackDice=6})
    assert(context.attackDice==7 and STA2E.game.m5.fleetFocus.Blue==near.instanceId and STA2E.game.m5.fleetFocusRound.Blue==1)
end)
test("M5 exported combat runner orders descending signed captain skill",function()
    _reset();STA2E.game.phase='combat';local order={}
    for id,skill in pairs({low=-2,middle=4,high=7})do local s=m5Ship(id);s.m5.finalCaptainSkill=skill end
    local original=STA2E.M5.primaryAttack
    STA2E.M5.primaryAttack=function(s)table.insert(order,s.instanceId);s.state.fired=true;return {}end
    local ok,err=pcall(function()for _=1,3 do STA2E.M5.run('Blue')end end);STA2E.M5.primaryAttack=original
    assert(ok,err);assert(table.concat(order,',')=='high,middle,low',table.concat(order,','))
end)
test("M5 defender retains custom profile stats",function()
    _reset();local s=m5Ship('m5-attacker');local d=m5Ship('m5-defender');d.owner='Red';d.side='allied'
    local original,random=STA2E.M5.selectTarget,math.random
    STA2E.M5.selectTarget=function()return d,{range=2}end;math.random=function()return 8 end
    local ok,result=pcall(STA2E.M5.primaryAttack,s);STA2E.M5.selectTarget=original;math.random=random
    assert(ok,result);assert(d.combat.maxHull==7 and d.combat.agility==1 and d.combat.maxShields==3)
end)
test("M5 rejects unknown defender stats before dice or attack effects",function()
    _reset();local s=m5Ship('unknown-attacker',{{cardId='focused_barrage'}});local d=_ship('unknown-defender','Red','UNKNOWN')
    local original,random=STA2E.M5.selectTarget,math.random;local rolls=0
    STA2E.M5.selectTarget=function()return d,{range=2}end;math.random=function()rolls=rolls+1;return 1 end
    local ok,result,err=pcall(STA2E.M5.primaryAttack,s);STA2E.M5.selectTarget=original;math.random=random
    assert(ok,result);assert(not result and err and err:find('No verified combat stats',1,true))
    assert(rolls==0 and not s.state.fired and not d.combat and not (STA2E.game.m5 and STA2E.game.m5.fleetFocus.Blue))
end)
test("Bundled combat stats include every ordinary ship and exact station stats",function()
    local n=0;for _,stats in pairs(SHIP_COMBAT_STATS)do n=n+1;assert(stats.hull>0 and stats.agility>=0 and stats.shields>=0)end
    assert(n==396,'Expected 396 ships, got '..n)
    assert(SHIP_COMBAT_STATS.S075.hull==8 and SHIP_COMBAT_STATS.S075.shields==8 and SHIP_COMBAT_STATS.S075.agility==0)
    assert(SHIP_COMBAT_STATS.S184.shields==7)
end)
test("HUD batching retains the latest state and schedules the next update",function()
    _reset();local s=_ship('hud-latest');STA2E_SidebarClick(Player.Blue,'','skill_up_hud-latest');STA2E_SidebarClick(Player.Blue,'','skill_up_hud-latest')
    assert(_hudWrites==0);_drain();assert(_hudWrites==1 and s.skillOverride==2 and #_xml>0)
    STA2E_SidebarClick(Player.Blue,'','skill_up_hud-latest');_drain();assert(_hudWrites==2 and s.skillOverride==3)
end)
