local function seatColor(color,seat)
    local r,g,b=color[1],color[2],color[3]
    if seat=='Blue'then return b>g and g>r
    elseif seat=='Red'then return r>g and r>b
    elseif seat=='Green'then return g>r and g>b
    elseif seat=='Purple'then return b>r and r>g
    elseif seat=='Orange'then return r>g and g>b
    elseif seat=='Yellow'then return r>=g and g>b
    elseif seat=='White'then return r==g and g==b end
end
local function allLinesMatch(object,seat)
    local lines=object.getVectorLines()
    assert(#lines>0,'no guides for '..seat)
    for _,line in ipairs(lines)do
        assert(seatColor(line.color,seat),'wrong line color for '..seat..': '..JSON.encode(line.color))
    end
end

test("Modern arcs and all range bands follow each of the six ship owners",function()
    for _,seat in ipairs({'Blue','Red','Green','Purple','Orange','Yellow'})do
        _reset();local ship=_ship('seat-guide-'..seat,seat)
        ship.state.guideArc=true;ship.state.guideRange=3
        STA2E_DrawShipGuides(ship)
        allLinesMatch(_objects[ship.refs.base],seat)
        assert(#_objects[ship.refs.base].getVectorLines()>3,'arc contours missing')
    end
end)

test("Nor station sectors retain the owner's color on every contour",function()
    _reset();local ship=_ship('purple-nor','Purple','S075')
    ship.state.guideArc=true;ship.state.guideRange=3
    STA2E_DrawShipGuides(ship)
    assert(#_objects[ship.refs.base].getVectorLines()==12)
    allLinesMatch(_objects[ship.refs.base],'Purple')
end)

test("Legacy ranges and arcs use the target ship owner rather than helper identity",function()
    _reset();local ship=_ship('legacy-green','Green');local base=_objects[ship.refs.base]
    for _,mode in ipairs({'range1','range2','range3','range123','front90','rear90','front180','ai','all'})do
        assert(STA2E_LegacyGuide({guid=base.guid,owner='Purple-helper-guid',mode=mode}))
        allLinesMatch(base,'Green')
        assert(STA2E_LegacyGuide({guid=base.guid,owner='Purple-helper-guid',mode='clear'}))
    end
end)

test("Legacy guides honor unmanaged object ownership and use neutral unowned lines",function()
    _reset()
    local yellow=_object('yellow-unmanaged',{owner='Yellow',role='base'})
    assert(STA2E_LegacyGuide({guid=yellow.guid,owner='Red-helper',mode='range123'}))
    allLinesMatch(yellow,'Yellow')
    local neutral=_object('neutral-unmanaged')
    assert(STA2E_LegacyGuide({guid=neutral.guid,owner='Blue-helper',mode='front90'}))
    allLinesMatch(neutral,'White')
end)

local function trackerRow(id)
    local first=assert(_xml:find('<Button id="focus_'..id..'"',1,true),'tracker row missing: '..id)
    local last=assert(_xml:find('</Button>',first,true))
    return _xml:sub(first,last+8)
end
test("M5 and Alliance tracker rows stay white with readable text including manual Hunt orders",function()
    _reset()
    local m5=_ship('style-m5','Red');STA2E_M5Attach(m5,{shipCardId='M5S001',cards={}})
    local alliance=_ship('style-alliance','Blue');alliance.ai={enabled=true};alliance.side='enemy'
    local hunt=_ship('style-hunt','White');hunt.ai={enabled=false,manualMissionOrders=true};hunt.side='enemy'
    local human=_ship('style-human','Green')
    hud();_drain()
    for _,ship in ipairs({m5,alliance,hunt})do
        local row=trackerRow(ship.instanceId)
        assert(row:find('color="#FFFFFF"',1,true) and row:find('textColor="#18202B"',1,true))
    end
    assert(not trackerRow(human.instanceId):find('color="#FFFFFF"',1,true),'human row lost its owner color')
    STA2E.game.phase='combat';alliance.state.fired=true;human.state.fired=true
    hud();_drain()
    assert(trackerRow(alliance.instanceId):find('color="#FFFFFF"',1,true))
    assert(trackerRow(alliance.instanceId):find('/F]',1,true),'AI fired marker missing')
    assert(trackerRow(human.instanceId):find('color="#48515D"',1,true),'human fired-state styling changed')
end)
