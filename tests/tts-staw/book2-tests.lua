-- Exercise the exact packaged Global under the established TTS API harness.
local function setup()
    _reset()
    local board=_object('ae9c49',nil,{0,0.53,0});board.setRotation({0,90,0})
    board.getScale=function()return {x=1.89,y=1.87,z=1.89}end
    local bag=_object('df60bd',nil,{60,1,60})
    bag.takeObject=function(params)
        return spawnObjectData({data={Name='Custom_Token',Nickname='Shield'},position=params.position,callback_function=params.callback_function})
    end
    return board
end
local function start(id,p,d,i)
    local result=STA2E_MissionStart({id=id,playerCount=p,difficulty=d,influence=i or 0,color='Blue'})
    assert(result.ok,result.error);_drain(30000)
    return STA2E.game.alliance
end
local function clearLanes(s)
    for id in pairs(s.shipRecords)do
        local ship=STA2E.ships[id];local base=ship and ship.refs and _objects[ship.refs.base]
        if base then base.setPosition({0,1.3,-2})end
    end
end
local expected={
 A4M1={{5,7,9,12,13},{5,7,9,12,13}}, A4M2={{4,7,9,11,14},{5,8,11,13,17}},
 A5M1={{3,3,4,5,6},{3,4,5,6,8}}, A5M2={{6,9,12,14,17},{7,11,14,17,21}},
 A5M3={{5,7,10,12,15},{5,8,11,13,17}}, A6M1={{5,8,10,13,16},{6,9,12,16,20}},
 A6M2={{6,8,11,13,16},{6,8,11,13,16}}
}
local stats={ASR={1,3,2,"Jem'Hadar Attack Ship"},ASE={4,3,2,"Jem'Hadar Attack Ship"},
 GR={2,4,3,'Cardassian Galor Class'},GE={5,4,3,'Cardassian Galor Class'},
 BCR={5,6,4,"Jem'Hadar Battle Cruiser"},BCE={7,6,4,"Jem'Hadar Battle Cruiser"}}

test('Book II all 70 player/difficulty combinations match printed wave totals',function()
    for id,counts in pairs(expected) do
        for players=2,6 do for mode,diff in ipairs({'normal','adjusted'}) do
            local d=STA2E_Book2Prepare(STA2E_MISSION_DEFINITIONS[id],players,diff)
            local count=0
            for _,row in ipairs(d.formations) do
                count=count+#row.slotProfiles
                for _,key in ipairs(row.slotProfiles) do assert(stats[key],key) end
                if row.hardOnly and diff=='normal' then assert(#row.slotProfiles==0)end
            end
            assert(count==counts[mode][players-1],id..' '..players..' '..diff..': '..count)
        end end
    end
end)

for _,diff in ipairs({'normal','adjusted'}) do
 for _,players in ipairs({2,6}) do
  for _,id in ipairs({'A4M1','A4M2','A5M1','A5M2','A5M3','A6M1','A6M2'}) do
   test('Book II real deployment '..id..' '..players..'p '..diff,function()
    setup();local s=start(id,players,diff)
    assert(s.missionObjects.setupComplete,table.concat(s.missionObjects.errors,';'))
    assert(#s.missionObjects.errors==0)
    for round=0,8 do
        clearLanes(s);STA2E.game.round=round;STA2E.game.phase='planning';STA2E_AllianceProcessRound();_drain(30000)
        local retry=STA2E_MissionRetry({id=id});assert(retry.ok,retry.error);_drain(30000)
    end
    local count=0
    for _,wave in pairs(s.waves)do assert(wave.spawned,wave.name..': '..tostring(wave.error))end
    for enemy,record in pairs(s.shipRecords)do
        if not record.cancelled then
            count=count+1
            local ship=assert(STA2E.ships[enemy]);local e=assert(stats[ship.aiProfile])
            assert(SHIP_DEFINITIONS[ship.definitionId].class==e[4],ship.definitionId..' wrong model class')
            assert(ship.skillOverride==e[1])
            assert(ship.combat.maxHull==e[2] and ship.combat.hull==e[2])
            assert(ship.combat.maxShields==e[3] and ship.combat.shields==e[3])
            assert(record.shieldsComplete)
            local shields=0
            for _,o in ipairs(getAllObjects())do if o.getGMNotes()=='STA2E_ALLIANCE_SHIELD|'..enemy then shields=shields+1 end end
            assert(shields==e[3],ship.aiProfile..' physical shields '..shields)
            if ship.missionOrders~='Attack' then assert(not ship.ai.enabled)end
        end
    end
    assert(count==expected[id][diff=='normal' and 1 or 2][players-1],id..' actual count '..count)
    local before=count;STA2E_MissionRetry({id=id});_drain(30000)
    local after=0;for _,r in pairs(s.shipRecords)do if not r.cancelled then after=after+1 end end
    assert(after==before,'Retry duplicated ships')
   end)
  end
 end
end

test('Book II adjusted settings and mixed profiles persist through reload',function()
    setup();local s=start('A5M2',4,'adjusted');clearLanes(s)
    STA2E.game.round=6;STA2E.game.phase='planning';STA2E_AllianceProcessRound();_drain(30000)
    local runId=s.runId;local saved=onSave();_waits={};onLoad(saved);_drain(30000)
    s=STA2E.game.alliance
    assert(STA2E.ready and s.runId==runId and s.difficulty=='adjusted' and s.settings.difficulty=='adjusted')
    assert(s.missionObjects.setupComplete and not STA2E_MissionStatus().pending)
    local seen={};for id in pairs(s.shipRecords)do local ship=STA2E.ships[id];seen[ship.aiProfile]=true end
    assert(seen.BCE and seen.GE and seen.ASE)
end)

test('Book II scene counts, shipyard power pool and Influence hulls',function()
    local yards={2,3,4,5,6};local docked={3,5,6,7,9};local mines={5,7,10,12,15};local pool={4,6,8,10,12}
    for p=2,6 do
        setup();local s=start('A5M1',p,'normal');local kinds={}
        for _,o in ipairs(s.missionObjects.objects)do kinds[o.kind]=(kinds[o.kind]or 0)+1 end
        assert(kinds.shipyard==yards[p-1] and kinds.dockedAS==docked[p-1])
        assert(kinds.powerUpToken==pool[p-1] and #s.missionObjects.powerUpPool==pool[p-1])
        setup();s=start('A4M2',p,'normal');local n=0
        for _,o in ipairs(s.missionObjects.objects)do if o.kind=='mine' then n=n+1 end end
        assert(n==mines[p-1])
        for influence=0,2 do
            setup();s=start('A6M2',p,'normal',influence);local n=0
            for _,o in ipairs(STA2E.MissionObjects.hulls(s))do
                if o.kind=='tenthFleet'then n=n+1;assert(o.maxHull==3+influence)end
            end
            assert(n==p)
        end
    end
end)

test('Book II reset owns only mission pieces, including late callbacks',function()
    setup();local human=_ship('book2-human','Blue');human.refs.base=nil
    local result=STA2E_MissionStart({id='A5M1',playerCount=6,difficulty='adjusted'})
    assert(result.ok,result.error);assert(STA2E_MissionReset({id='A5M1'}).ok);_drain(30000)
    assert(STA2E.ships['book2-human'])
    for _,o in ipairs(getAllObjects())do assert(not o.getGMNotes():find('STA2E_MISSION_OBJECT|',1,true))end
    assert(not STA2E.game.alliance)
end)

test('Part I rejects adjusted mode until its own tables are implemented',function()
    setup();local r=STA2E_MissionStart({id='A1M1',playerCount=2,difficulty='adjusted'})
    assert(not r.ok and not STA2E.game.alliance)
end)

test('Book II movable hull counter is interactive and survives object reload',function()
    setup();local s=start('A6M2',2,'normal',2)
    local miranda
    for _,row in ipairs(s.missionObjects.objects)do if row.kind=='tenthFleet' then miranda=_objects[row.guid];break end end
    assert(miranda and miranda._objectiveScript)
    local env=miranda._objectiveScript
    assert(env.getHull().hull==5)
    env.hullMinus();assert(env.getHull().hull==4)
    local saved=env.onSave();env.onLoad(saved);assert(env.getHull().hull==4)
    assert(env.getHull().runId==s.runId)
    for i=1,10 do env.hullMinus()end
    assert(env.getHull().hull==0 and not miranda._destroyed)
    env.hullPlus();assert(env.getHull().hull==1)
end)
