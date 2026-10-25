local function setup()
    _reset()
    local board=_object('ae9c49',nil,{0,0.53,0});board.setRotation({0,90,0})
    board.getScale=function()return {x=1.89,y=1.87,z=1.89}end
    local bag=_object('df60bd',nil,{60,1,60})
    bag.takeObject=function(p)return spawnObjectData({data={Name='Custom_Token',Nickname='Shield'},position=p.position,callback_function=p.callback_function})end
end
local function start(id,p,d,prior,factions)
    local result=STA2E_MissionStart({id=id,playerCount=p,difficulty=d or 'normal',priorResults=prior or {},escortFactions=factions,color='Blue'})
    assert(result.ok,result.error);_drain(30000)
    return STA2E.game.alliance
end
local function clearLanes(s)
    for id in pairs(s.shipRecords) do local ship=STA2E.ships[id];local base=ship and ship.refs and _objects[ship.refs.base]
        if base then base.setPosition({100,1.3,100})end end
end
local expected={
    A7M1={{5,7,9,11,13},{5,7,9,11,13}},A7M2={{4,6,8,10,12},{5,7,10,12,15}},
    A7M3={{4,6,8,10,12},{5,7,10,12,15}},A8M1={{5,7,10,12,15},{6,9,12,15,18}},
    A8M2={{5,7,10,12,15},{6,9,12,15,18}},A9M1={{8,12,16,20,24},{8,12,16,20,24}},
    A9M2={{6,8,12,14,18},{7,10,14,17,21}}
}
test('Book III all 70 cumulative wave totals match independent printed counts',function()
    for id,counts in pairs(expected) do for p=2,6 do for mode,d in ipairs({'normal','adjusted'}) do
        local prepared=STA2E_Book2Prepare(STA2E_MISSION_DEFINITIONS[id],p,d);local count=0
        for _,row in ipairs(prepared.formations) do count=count+#row.slotProfiles end
        assert(count==counts[mode][p-1],id..' '..p..' '..d..' '..count)
    end end end
end)

for _,diff in ipairs({'normal','adjusted'}) do for _,p in ipairs({2,6}) do for _,id in ipairs({'A7M1','A7M2','A7M3','A8M1','A8M2','A9M1','A9M2'}) do
    test('Book III actual setup/waves '..id..' '..p..'p '..diff,function()
        setup();local s=start(id,p,diff)
        assert(s.missionObjects.setupComplete,table.concat(s.missionObjects.errors,';'))
        if id=='A8M1' then
            STA2E.game.round=1;STA2E.game.phase='combat'
            assert(STA2E_Book3Event({id=id,action='facilityRevealed',asteroid=1}).ok);_drain(30000)
        end
        for round=0,8 do clearLanes(s);STA2E.game.round=round;STA2E.game.phase='planning';STA2E_AllianceProcessRound();_drain(30000)
            local r=STA2E_MissionRetry({id=id});assert(r.ok,r.error);_drain(30000) end
        local count=0
        for _,wave in pairs(s.waves)do assert(wave.spawned,wave.name..': '..tostring(wave.error))end
        for enemy,record in pairs(s.shipRecords)do if not record.cancelled then
            count=count+1;local ship=assert(STA2E.ships[enemy]);local profile=s.definition.profiles[ship.aiProfile]
            assert(ship.skillOverride==profile.skill)
            assert(ship.combat.maxHull==profile.hull and ship.combat.hull==profile.hull)
            assert(ship.combat.maxShields==profile.shields)
            local shields=0;for _,o in ipairs(getAllObjects())do if o.getGMNotes()=='STA2E_ALLIANCE_SHIELD|'..enemy then shields=shields+1 end end
            assert(shields==profile.shields,ship.aiProfile..' physical shields '..shields)
            assert(SHIP_DEFINITIONS[ship.definitionId].class==profile.className)
        end end
        assert(count==expected[id][diff=='normal' and 1 or 2][p-1],id..' actual '..count)
        STA2E_MissionRetry({id=id});_drain(30000)
        local after=0;for _,r in pairs(s.shipRecords)do if not r.cancelled then after=after+1 end end
        assert(count==after,'Retry duplicates')
    end)
end end end

test('Book III new stats, Benzar shield scaling, Glinn and excluded setup bearings',function()
    assert(SHIP_COMBAT_STATS.S288.attack==6)
    for p=2,6 do
        local d=STA2E_Book2Prepare(STA2E_MISSION_DEFINITIONS.A7M1,p,'normal');d=assert(STA2E_Book3Prepare(d,{},p))
        assert(d.profiles.BSR.skill==7 and d.profiles.BSE.skill==9 and d.profiles.BSR.hull==7 and d.profiles.BSR.shields==2*p)
        assert(d.profiles.BR.skill==5 and d.profiles.BE.skill==8 and d.profiles.BR.hull==4 and d.profiles.BR.shields==3)
        setup();local s=start('A7M2',p)
        for _,row in pairs(s.waves)do if row.round==0 then assert(row.bearing~=1 and row.bearing~=6)end end
        local normal=STA2E_Book2Prepare(STA2E_MISSION_DEFINITIONS.A7M3,p,'normal')
        assert(#normal.formations[5].slotProfiles==math.floor(p/2))
    end
end)

test('Book III prior results apply hull damage to setup AND reinforcements',function()
    setup();local s=start('A9M1',4,'normal',{penumbra=true,supplyRun=true,dogsRound=8})
    for round=1,3 do clearLanes(s);STA2E.game.round=round;STA2E.game.phase='planning';STA2E_AllianceProcessRound();_drain(30000)end
    for id in pairs(s.shipRecords)do local ship=STA2E.ships[id]
        if ship.name:find("Jem'Hadar",1,true)then assert(ship.combat.hull==ship.combat.maxHull-1)
        else assert(ship.combat.hull==ship.combat.maxHull)end end
    assert(s.settings.book3.penumbra and s.book3.supplyRun)
    local saved=onSave();_waits={};onLoad(saved);_drain(30000);s=STA2E.game.alliance
    for id in pairs(s.shipRecords)do local ship=STA2E.ships[id];if ship.name:find("Jem'Hadar",1,true)then assert(ship.combat.hull==ship.combat.maxHull-1)end end
end)

test('Book III defection preserves AI and targets hostile AI instead of players',function()
    setup();local s=start('A9M1',2,'normal',{supplyRun=true});clearLanes(s)
    STA2E.game.round=2;STA2E.game.phase='planning';STA2E_AllianceProcessRound();_drain(30000)
    local galor,dominion
    for id in pairs(s.shipRecords)do local ship=STA2E.ships[id]
        if ship.aiProfile=='GE' then galor=ship elseif ship.aiProfile=='ASR' then dominion=ship end end
    assert(galor and dominion)
    local human=_ship('book3-human','Blue','S193');human.side='allied'
    _objects[human.refs.base].setPosition({0,1,-1})
    _objects[galor.refs.base].setPosition({0,1,0});_objects[galor.refs.base].setRotation({0,0,0})
    _objects[dominion.refs.base].setPosition({0,1,-10});_objects[dominion.refs.base].setRotation({0,180,0})
    galor.ai.plan={targetId=human.instanceId};dominion.ai.plan={targetId=human.instanceId}
    STA2E.game.round=3;STA2E_AllianceProcessRound();assert(galor.side=='enemy')
    STA2E.game.round=4;STA2E_AllianceProcessRound();_drain(30000)
    assert(galor.side=='allied' and galor.ai.enabled and not galor.ai.manualMissionOrders and not galor.ai.plan)
    STA2E_Command({object=_objects[galor.cardGUID],color='Red',command='ai_evaluate'})
    assert(galor.ai.plan and galor.ai.plan.targetId==dominion.instanceId,galor.ai.message)
    _objects[human.refs.base].setPosition({0,1,10})
    STA2E_Command({object=_objects[dominion.cardGUID],color='Red',command='ai_evaluate'})
    assert(dominion.ai.plan and dominion.ai.plan.targetId==galor.instanceId,dominion.ai.message)
    local saved=onSave();_waits={};onLoad(saved);_drain(30000)
    galor=STA2E.ships[galor.instanceId];assert(galor.side=='allied' and galor.ai.enabled)
    setup();s=start('A9M1',2);clearLanes(s);STA2E.game.round=4;STA2E.game.phase='planning';STA2E_AllianceProcessRound();assert(not s.book3.defected)
    STA2E.game.round=5;STA2E_AllianceProcessRound();assert(s.book3.defected)
end)

test('Book III facility event schedules next round at furthest bearing and is idempotent',function()
    setup();local s=start('A8M1',4);STA2E.game.round=3;STA2E.game.phase='combat'
    assert(not STA2E_Book3Event({id='A8M1',action='facilityRevealed',asteroid=7}).ok)
    local r=STA2E_Book3Event({id='A8M1',action='facilityRevealed',asteroid=3});assert(r.ok,r.error);_drain(30000)
    assert(s.book3.facilityIndex==3 and s.definition.formations[6].round==4 and not s.waves.wave6.spawned)
    local hulls=STA2E.MissionObjects.hulls(s);local n=0
    for _,row in ipairs(hulls)do if row.kind=='facility'then n=n+1;assert(row.hull==8)end end;assert(n==1)
    assert(not STA2E_Book3Event({id='A8M1',action='facilityRevealed',asteroid=4}).ok)
    clearLanes(s);STA2E.game.round=4;STA2E.game.phase='planning';STA2E_AllianceProcessRound();_drain(30000)
    clearLanes(s);STA2E_MissionRetry({id='A8M1'});_drain(30000)
    assert(s.waves.wave6.spawned and s.waves.wave6.bearing==s.book3.facilityBearing,s.waves.wave6.error)
    local saved=onSave();_waits={};onLoad(saved);_drain(30000);assert(STA2E.game.alliance.book3.facilityIndex==3)
end)

test('Book III Benzar event cancels undeployed waves and persists Withdraw',function()
    setup();local s=start('A7M1',2)
    assert(STA2E_Book3Event({id='A7M1',action='battleshipDestroyed'}).ok)
    assert(s.waves.wave5.cancelled)
    clearLanes(s);STA2E.game.round=4;STA2E.game.phase='planning';STA2E_AllianceProcessRound();_drain(30000)
    assert(#s.waves.wave5.slots==0)
    local saved=onSave();_waits={};onLoad(saved);_drain(30000);s=STA2E.game.alliance
    for id in pairs(s.shipRecords)do local ship=STA2E.ships[id];if ship.aiProfile~='BSR' then assert(ship.missionOrders=='Withdraw' and not ship.ai.enabled)end end
    assert(not STA2E_Book3Event({id='A7M1',action='battleshipDestroyed'}).ok)
end)

test('Book III population formula, physical token synchronization and no fixed finale deadline',function()
    for p=2,6 do for _,success in ipairs({false,true})do for _,round in ipairs({7,8,9})do
        local d=STA2E_Book2Prepare(STA2E_MISSION_DEFINITIONS.A9M2,p,'normal')
        d=assert(STA2E_Book3Prepare(d,{priorResults={supplyRun=success,dogsRound=round}},p))
        assert(d.book3Settings.population==3*p+(success and 2 or 0)-(round==8 and 1 or round==9 and 2 or 0))
    end end end
    setup();local s=start('A9M2',4,'normal',{supplyRun=true,dogsRound=8});assert(s.book3.population==13)
    local function physical()local n=0;for _,o in ipairs(getAllObjects())do if o.getGMNotes():find('|population|',1,true)then n=n+1 end end;return n end
    assert(physical()==13)
    assert(STA2E_Book3Event({id='A9M2',action='populationMinus'}).ok);_drain(30000);assert(physical()==12)
    assert(STA2E_Book3Event({id='A9M2',action='populationPlus'}).ok);_drain(30000);assert(physical()==13)
    for round=1,6 do clearLanes(s);STA2E.game.round=round;STA2E.game.phase='planning';STA2E_AllianceProcessRound();_drain(30000)
        clearLanes(s);STA2E_MissionRetry({id='A9M2'});_drain(30000)end
    STA2E.game.round=12;STA2E.game.phase='end';STA2E_PhaseUI(Player.Blue);_drain(30000)
    assert(not s.deadlineReached and STA2E.game.round==13,STA2E_MissionStatus({id='A9M2'}).status)
end)

test('Book III bombardment includes Round 1, one loss per crit, duplicate guard and reload',function()
    setup();local s=start('A9M2',2)
    assert(not STA2E_Book3Event({id='A9M2',action='bombardment'}).ok)
    STA2E.game.round=1;STA2E.game.phase='planning';STA2E_AllianceProcessRound()
    local random=math.random;math.random=function(a,b)return 4 end
    local r=STA2E_Book3Event({id='A9M2',action='bombardment'});math.random=random;assert(r.ok,r.error);_drain(30000)
    assert(s.book3.lastBombardment.dice==3 and s.book3.lastBombardment.loss==3 and s.book3.population==3)
    assert(not STA2E_Book3Event({id='A9M2',action='bombardment'}).ok)
    local saved=onSave();_waits={};onLoad(saved);_drain(30000);s=STA2E.game.alliance
    assert(s.book3.population==3 and not STA2E_Book3Event({id='A9M2',action='bombardment'}).ok)
    for _,row in ipairs(STA2E.MissionObjects.hulls(s))do if row.kind=='weaponPlatform'then _objects[row.guid]._objectiveScript.setHull({hull=0,silent=true})end end
    STA2E.game.round=2;math.random=function(a,b)return 4 end
    r=STA2E_Book3Event({id='A9M2',action='bombardment'});math.random=random;assert(r.ok,r.error);_drain(30000)
    assert(s.book3.lastBombardment.dice==1 and s.book3.population==2)
end)

test('Book III faction escorts are standard bases with actual attached models and separate hull',function()
    setup();local s=start('A9M1',3,'normal',{}, {'federation','klingon','romulan'})
    local n=0;local types={}
    for _,row in ipairs(s.missionObjects.objects)do if row.kind=='escortShip'then
        n=n+1;local o=assert(_objects[row.guid]);assert(o._spawnData.CustomMesh.MeshURL==STANDARD_BASE.CustomMesh.MeshURL)
        assert(#o.getAttachments()==1);local a=o.getAttachments()[1]
        types[a.data.CustomMesh.MeshURL]=true;assert(o._objectiveScript.getHull().hull==5)
        assert(#o._buttons==3,'Escort should use formation movement, not a freighter movement menu')
    end end
    assert(n==3);local meshes=0;for _ in pairs(types)do meshes=meshes+1 end;assert(meshes==3)
    local saved=onSave();_waits={};onLoad(saved);_drain(30000)
    for _,row in ipairs(STA2E.game.alliance.missionObjects.objects)do if row.kind=='escortShip'then assert(#_objects[row.guid].getAttachments()==1)end end
end)

test('Book III unique Battleship loadouts in finale and scene piece counts at every player count',function()
    for p=2,6 do
        setup();local s=start('A9M2',p);local cards={};local count=0;local platforms=0
        for id in pairs(s.shipRecords)do local ship=STA2E.ships[id];if ship.aiProfile=='BSE'then assert(not cards[ship.allianceCardId]);cards[ship.allianceCardId]=true;count=count+1 end end
        assert(count==math.floor(p/2))
        for _,row in ipairs(s.missionObjects.objects)do if row.kind=='weaponPlatform'then platforms=platforms+1;assert(row.maxHull==8)end end;assert(platforms==p)
        setup();s=start('A7M2',p);platforms=0;local controls=0
        for _,row in ipairs(s.missionObjects.objects)do if row.kind=='weaponPlatform'then platforms=platforms+1;assert(row.maxHull==4)elseif row.kind=='controlPlatform'then controls=controls+1 end end
        assert(platforms==2*p and controls==2)
        setup();s=start('A8M2',p);assert(#s.missionObjects.contactPool==p)
        local twelve=0;for _,n in ipairs(s.missionObjects.contactPool)do if n==12 then twelve=twelve+1 end end;assert(twelve==1)
    end
end)

test('Book III reset owns late event callbacks and keeps player fleet',function()
    setup();local human=_ship('book3-reset-human','Blue');human.refs.base=nil
    local s=start('A8M1',2);STA2E.game.round=1;STA2E.game.phase='combat'
    assert(STA2E_Book3Event({id='A8M1',action='facilityRevealed',asteroid=1}).ok)
    assert(STA2E_MissionReset({id='A8M1'}).ok);_drain(30000)
    assert(STA2E.ships['book3-reset-human'])
    for _,o in ipairs(getAllObjects())do assert(not o.getGMNotes():find('STA2E_MISSION_OBJECT|',1,true))end
    assert(not STA2E_Book3Event({id='A8M1',runId=s.runId,action='facilityRevealed',asteroid=2}).ok)
end)

test('Book III invalid prior settings leave the save session untouched',function()
    setup();local r=STA2E_MissionStart({id='A9M2',priorResults={dogsRound=10}});assert(not r.ok and not STA2E.game.alliance)
    r=STA2E_MissionStart({id='A9M1',escortFactions={'borg'}});assert(not r.ok and not STA2E.game.alliance)
end)

test('Book III agreed map geometry, planet supply storage and asteroid counts',function()
    for _,id in ipairs({'A7M1','A7M3','A8M2','A9M1','A9M2'})do
        setup();local s=start(id,6);local r=s.missionObjects
        assert(#r.layoutWarnings==0,id..': '..table.concat(r.layoutWarnings,'; '))
        assert(r.asteroidCount==s.definition.geometry.asteroidCount,id..' asteroid count')
        if id=='A7M1'then
            assert(s.definition.formations[1].sites[1].rotation==315)
            assert(s.definition.formations[1].sites[1].u==0 and s.definition.formations[1].sites[1].v==0)
        elseif id=='A7M3'then
            local planet;local supplies={};local depot
            for _,row in ipairs(r.objects)do
                if row.kind=='planet'then planet=_objects[row.guid].getPosition()
                elseif row.kind=='raidSupply'then supplies[#supplies+1]=_objects[row.guid].getPosition()
                elseif row.kind=='supplyDepot'then depot=_objects[row.guid].getPosition()end
            end
            assert(#supplies==12 and planet and depot)
            for _,p in ipairs(supplies)do assert((p.x-planet.x)^2+(p.z-planet.z)^2<5,JSON.encode({supply=p,planet=planet}))end
            assert((depot.x-planet.x)^2+(depot.z-planet.z)^2>25)
        elseif id=='A9M2'then assert(r.anchors[2].edge=='left' and r.geometry.bearings[2].v<0)end
    end
end)
