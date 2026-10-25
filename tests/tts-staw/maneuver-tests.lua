local movement=STA2E.Movement
local newMoves={{"FAL1","TL1","TL1",180},{"FAR1","TR1","TR1",-180},{"IRL1","TL1","TR1",0},{"IRR1","TR1","TL1",0}}
local function close(actual,expected) assert(math.abs(actual-expected)<0.00002,tostring(actual).." instead of "..tostring(expected)) end
local function sameHeading(actual,expected) close((actual-expected+180)%360-180,0) end
local function expectedFinish(start,entry,half)
    local first=movement.pose(start,MOVE_DEFS[entry[2]],1)
    local old=movement.pose(first,MOVE_DEFS[entry[3]],1)
    local jointHeading=math.rad(first.yaw)
    -- Independent oracle: the old result minus ONE entire base at the join.
    return {x=old.x+2*half*math.sin(jointHeading),z=old.z+2*half*math.cos(jointHeading),yaw=old.yaw}
end

test("Connected turns remove exactly one base length at the join for both hands",function()
    for _,entry in ipairs(newMoves) do
        for _,half in ipairs({0.65,0.8,1.4}) do
            for _,yaw in ipairs({0,90,237}) do
                local start={x=5.7,z=-8.3,yaw=yaw}
                local expected=expectedFinish(start,entry,half)
                local actual=movement.pose(start,MOVE_DEFS[entry[1]],1,half)
                close(actual.x,expected.x);close(actual.z,expected.z);sameHeading(actual.yaw,expected.yaw)
                sameHeading(actual.yaw,yaw+entry[4])
            end
        end
    end
end)

test("Connected template paths keep the base centered at the shared join without teleporting",function()
    for _,entry in ipairs(newMoves) do
        local start={x=-4,z=9,yaw=33};local half=0.8;local move=MOVE_DEFS[entry[1]]
        local first=movement.pose(start,MOVE_DEFS[entry[2]],1)
        local expected={x=first.x+half*math.sin(math.rad(first.yaw)),z=first.z+half*math.cos(math.rad(first.yaw)),yaw=first.yaw}
        local middle=movement.pose(start,move,0.5,half)
        close(middle.x,expected.x);close(middle.z,expected.z);sameHeading(middle.yaw,expected.yaw)
        local atStart=movement.pose(start,move,0,half)
        close(atStart.x,start.x);close(atStart.z,start.z);sameHeading(atStart.yaw,start.yaw)
        for _,t in ipairs({0.25,0.5,0.75,1}) do
            local a=movement.pose(start,move,t-0.000001,half)
            local b=movement.pose(start,move,t,half)
            assert(math.abs(b.x-a.x)<0.0001 and math.abs(b.z-a.z)<0.0001)
            assert(math.abs(b.yaw-a.yaw)<0.001,"Facing jumped on the connected template")
        end
    end
end)

test("Joined Full About and Impulse Roll use actual base length, animate, and undo as one maneuver",function()
    for _,entry in ipairs(newMoves) do
        for _,half in ipairs({0.8,1.4}) do
            for _,yaw in ipairs({0,90,237}) do
                _reset();local ship=_ship("joined-"..entry[1]);local base=_objects[ship.refs.base]
                base.getBoundsNormalized=function() return {size={x=half*2,y=0.2,z=half*2}} end
                base.setPosition({7,1,-6});base.setRotation({0,yaw,0});base.setLock(true)
                ship.state={status="locked",maneuver="S2",dialOpen=true,toolsPage="moves",toolsMovePage=2}
                local expected=expectedFinish({x=7,z=-6,yaw=yaw},entry,half)
                local positions={};local setPosition=base.setPosition
                base.setPosition=function(p) positions[#positions+1]=_vector(p);setPosition(p) end
                STA2E_Command({object=_objects[ship.cardGUID],color="Blue",command="tool_move_"..entry[1]});_drain()
                close(base.getPosition().x,expected.x);close(base.getPosition().z,expected.z)
                sameHeading(base.getRotation().y,expected.yaw)
                assert(#positions==60 and base.getLock() and not STA2E.pendingMoves[ship.instanceId])
                assert(ship.state.status=="locked" and ship.state.maneuver=="S2")
                STA2E_Command({object=_objects[ship.cardGUID],color="Blue",command="tool_undo"});_drain()
                close(base.getPosition().x,7);close(base.getPosition().z,-6);sameHeading(base.getRotation().y,yaw)
                assert(ship.state.status=="locked" and ship.state.maneuver=="S2" and ship.state.toolsPage=="moves")
            end
        end
    end
end)

test("Joined template collision backtracking uses the same no-gap curve as animation",function()
    for _,entry in ipairs(newMoves) do
        local start={x=0,z=0,yaw=41};local move=MOVE_DEFS[entry[1]];local shape={x=0.2,z=0.3}
        local ending=expectedFinish(start,entry,shape.z)
        local blocker={pose={x=ending.x,z=ending.z,yaw=17},shape={x=0.15,z=0.15},reason="ship"}
        local stop,reason=movement.latestLegal(start,move,shape,{blocker})
        assert(stop>0.5 and stop<1 and reason=="ship")
        assert(not movement.overlaps(movement.pose(start,move,stop,shape.z),shape,blocker.pose,blocker.shape))
    end
end)

test("Full About and Impulse Roll joined endpoints have no second base allowance",function()
    local start={x=0,z=0,yaw=0};local half=0.8
    -- Speed-one center offsets are 2.1; a 1.6-unit base removes 1.6 laterally.
    local expected={FAL1={2.6,0},FAR1={-2.6,0},IRL1={2.6,-4.2},IRR1={-2.6,-4.2}}
    for key,point in pairs(expected) do
        local actual=movement.pose(start,MOVE_DEFS[key],1,half)
        close(actual.x,point[1]);close(actual.z,point[2])
    end
end)

test("Grouped maneuver pages show every template exactly once and retain hover tooltips",function()
    _reset();local ship=_ship("grouped-moves");ship.state.dialOpen=true
    local seen={}
    local names={"STANDARD FLIGHT","SPECIAL FLIGHT","EVASIVE","BORG","STATION / ROTATION"}
    for page=1,5 do
        ship.state.toolsMovePage=page
        STA2E_Command({object=_objects[ship.cardGUID],color="Blue",command="tool_moves"})
        -- Opening the menu deliberately starts on page one; navigation selects later pages.
        for _=2,page do STA2E_Command({object=_objects[ship.cardGUID],color="Blue",command="tool_next"}) end
        _drain()
        local markup=_objects[ship.refs.dial]._xml
        assert(markup:find(names[page],1,true))
        for tag in markup:gmatch('<Button[^>]+>') do
            local key=tag:match('id="tool_move_([^"]+)"')
            if key then
                assert(MOVE_DEFS[key] and not seen[key],"Missing or duplicate "..key)
                assert(tag:find('onMouseEnter="STA2E_DialHoverEnter"',1,true),"Hover callback missing for "..key)
                seen[key]=true
            end
        end
        if page==2 then
            assert(markup:find('tool_move_FAL1',1,true))
            assert(markup:find('tool_move_IRR1',1,true))
        end
    end
    for key in pairs(MOVE_DEFS) do assert(seen[key],"Unreachable maneuver "..key) end
end)

test("New moves are available in the modifier without changing printed ship dials",function()
    for _,entry in ipairs(newMoves) do
        _reset();local ship=_ship("modified-"..entry[1]);ship.state.status="revealed";ship.state.maneuver="S1"
        STA2E.modifyShip.Blue=ship.instanceId
        STA2E_ModifyChoice(Player.Blue,"","modify_"..entry[1]);_drain()
        assert(ship.state.maneuver==entry[1])
    end
end)
