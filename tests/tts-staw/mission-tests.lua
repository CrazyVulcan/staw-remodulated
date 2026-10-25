-- Mission behavior tests use the exact Global source serialized into the save.
-- Physics, remote assets, and TTS rendering are outside this offline harness.
local oldObject=_object
function _object(...)
    local o=oldObject(...)
    o._description=""
    o.setColorTint=function(value)o._tint=value end
    o.getColorTint=function()return o._tint or {1,1,1} end
    o.setDescription=function(value)o._description=value end
    o.getDescription=function()return o._description end
    o.positionToLocal=function(v)
        local p=_vector(v);return {x=p.x-o._position.x,y=p.y-o._position.y,z=p.z-o._position.z}
    end
    o.positionToWorld=function(v)
        local p=_vector(v);return {x=p.x+o._position.x,y=p.y+o._position.y,z=p.z+o._position.z}
    end
    o.getCustomObject=function()return {} end
    o.setCustomObject=function(v)o._custom=v end
    o.reload=function()return o end
    o._attachments={}
    o.getAttachments=function()return o._attachments end
    o.addAttachment=function(child)
        o._attachments[#o._attachments+1]={guid=child.getGUID(),name=child.getName(),
            data=child._spawnData,position=child.getPosition(),rotation=child.getRotation()}
        child.destruct()
    end
    o.getVar=function(key)return o._vars and o._vars[key] end
    o.editButton=function(b)
        local target=o._buttons[b.index+1]
        if target then for k,v in pairs(b)do target[k]=v end end
    end
    return o
end
Wait.stop=Wait.stop or function()end

local function scriptEnvironment(source,object,global)
    local env=setmetatable({self=object,Global=global or Global},{__index=_G})
    env._G=env
    assert(load(source,"@isolated-mission-object","t",env))()
    return env
end

test("Mission definitions preserve all printed cumulative wave counts",function()
    local expected={A1M1={4,6,8,10,11},A2M1={4,5,7,9,10},A2M2={3,5,6,8,9},
        A2M3={3,5,6,8,9},A2M4={4,6,8,10,12},A3M1={4,7,8,11,12}}
    local n=0
    for id,totals in pairs(expected)do
        local d=assert(STA2E_MISSION_DEFINITIONS[id]);n=n+1
        for players=2,6 do
            local count=0
            for _,f in ipairs(d.formations)do count=count+f.counts[players] end
            assert(count==totals[players-1],id.." at "..players.." players: "..count)
        end
    end
    assert(n==6)
end)

test("Part I enemy profiles retain exactly two shields",function()
    for id,d in pairs(STA2E_MISSION_DEFINITIONS)do
        if not d.book2 then
            assert(d.profiles.generic.shields==2,id)
            assert(d.profiles.advanced.shields==2,id)
        end
    end
end)

test("Finale has no search orders or hidden objective tokens",function()
    local d=STA2E_MISSION_DEFINITIONS.A3M1
    assert(d.geometry.noHiddenMissionTokens and d.objective.noHiddenMissionTokens)
    assert(d.objective.escapeRound==5 and d.objective.escapeFormationId=="beta")
    for _,f in ipairs(d.formations)do assert(f.orders=="Attack",f.name)end
end)

test("Hull counter buttons clamp, notify, and survive reload",function()
    _reset()
    local notifications={}
    local o=_object('hull-counter')
    local source=_missionScriptSource('hull-counter.lua')
    local bridge={call=function(name,event)assert(name=='STA2E_MissionHullChanged');notifications[#notifications+1]=event end}
    local env=scriptEnvironment(source,o,bridge)
    env.onLoad(JSON.encode({hull=8,maxHull=8,kind='listening',missionId='A2M4',runId='counter-test'}))
    assert(#o._buttons==3 and env.getHull().hull==8)
    env.hullMinus();assert(env.getHull().hull==7 and #notifications==1)
    for i=1,20 do env.hullMinus()end
    assert(env.getHull().hull==0 and not o._destroyed)
    assert(o._description:find('DESTROYED',1,true))
    env.hullPlus();assert(env.getHull().hull==1)
    local saved=env.onSave()
    local reloaded=scriptEnvironment(source,o,bridge);reloaded.onLoad(saved)
    assert(reloaded.getHull().hull==1 and reloaded.getHull().runId=='counter-test')
    for i=1,20 do reloaded.hullPlus()end
    assert(reloaded.getHull().hull==8)
end)

test("All six mission objects expose functioning setup and tracker callbacks",function()
    _reset()
    local ids={'A1M1','A2M1','A2M2','A2M3','A2M4','A3M1'}
    local source=_missionScriptSource('mission-controller.lua')
    for _,id in ipairs(ids)do
        local calls={};local o=_object('controller-'..id)
        local bridge={call=function(name,args)
            calls[#calls+1]={name=name,args=args}
            return {ok=true,round=0,phase='setup',waveText='0 waves',status='Ready'}
        end}
        local code=source:gsub('__MISSION_ID__',id):gsub('__MISSION_NAME__',STA2E_MISSION_DEFINITIONS[id].name)
        local env=scriptEnvironment(code,o,bridge);env.onLoad('')
        for _,b in ipairs(o._buttons)do assert(type(env[b.click_function])=='function',id..':'..b.click_function)end
        env.startMission(nil,'Blue');assert(calls[#calls].name=='STA2E_MissionStart')
        assert(calls[#calls].args.id==id and calls[#calls].args.playerCount==2)
        env.advancePhase(nil,'Blue');assert(calls[#calls].name=='STA2E_MissionAdvance')
        env.retryWaves(nil,'Blue');assert(calls[#calls].name=='STA2E_MissionRetry')
        env.finishMission(nil,'Blue');assert(calls[#calls].name=='STA2E_MissionFinish')
        env.resetMission(nil,'Blue');assert(calls[#calls].name=='STA2E_MissionReset')
        local before=JSON.decode(env.onSave()).players
        env.choosePlayers();assert(JSON.decode(env.onSave()).players==before+1)
        if id=='A3M1'then env.chooseInfluence();assert(JSON.decode(env.onSave()).influence==1)end
        env.onDestroy()
    end
    -- Drop mock repeating-poll jobs. Production Wait.time supports -1 repetitions.
    _waits={}
end)

local missionSpawn=spawnObjectData
function spawnObjectData(params)
    local request={};for k,v in pairs(params)do request[k]=v end
    local callback=params.callback_function
    request.callback_function=function(o)
        o._spawnData=params.data
        if params.data and type(params.data.LuaScript)=='string' and params.data.LuaScript:find('local hullMemory=',1,true) then
            local env=scriptEnvironment(params.data.LuaScript,o)
            env.onLoad(params.data.LuaScriptState or '')
            local oldCall=o.call
            o.call=function(name,args)if env[name]then return env[name](args)else return oldCall(name,args)end end
            o._objectiveScript=env
        end
        if callback then callback(o)end
    end
    return missionSpawn(request)
end

local function missionTable()
    _reset()
    local board=_object('ae9c49',nil,{0,0.53,0});board.setRotation({0,90,0})
    board.getScale=function()return {x=1.89,y=1.87,z=1.89}end
    local bag=_object('df60bd',nil,{60,1,60})
    bag.takeObject=function(params)
        return spawnObjectData({data={Name='Custom_Token',Nickname='Shield'},position=params.position,callback_function=params.callback_function})
    end
    return board
end

local function start(id,players,influence)
    local result=STA2E_MissionStart({id=id,playerCount=players or 2,influence=influence or 0,color='Blue'})
    assert(result.ok,result.error);_drain(20000)
    return assert(STA2E.game.alliance)
end

local function countOwnedShields(s,id)
    local count=0
    for _,o in ipairs(getAllObjects())do if o.getGMNotes()=='STA2E_ALLIANCE_SHIELD|'..id then count=count+1 end end
    return count
end

local function deployThrough(s,lastRound)
    for round=1,lastRound do
        STA2E.game.round=round;STA2E.game.phase='planning'
        STA2E_AllianceProcessRound();_drain(20000)
        -- Simulate prior formations moving away from entry points. This is not
        -- a movement/physics test; it permits all scheduled waves to arrive.
        for id in pairs(s.shipRecords)do
            local ship=STA2E.ships[id]
            local base=ship and ship.refs and _objects[ship.refs.base]
            if base then base.setPosition({0,1.3,0})end
        end
    end
end

test("Six real mission setups spawn their expected scenario pieces",function()
    local ids={'A1M1','A2M1','A2M2','A2M3','A2M4','A3M1'}
    for _,id in ipairs(ids)do
        missionTable();local s=start(id,2)
        assert(s.missionObjects.setupComplete,id..': scene incomplete')
        assert(#s.missionObjects.errors==0,id)
        local kinds={}
        for _,o in ipairs(s.missionObjects.objects)do kinds[o.kind]=(kinds[o.kind]or 0)+1 end
        assert(kinds.guide==1,id)
        if id=='A1M1'then assert(kinds.sensorSite==2)
        elseif id=='A2M1'then assert(kinds.planet==1 and kinds.surveyTeam==3)
        elseif id=='A2M2'then assert(kinds.searchToken==5)
        elseif id=='A2M3'then assert(kinds.runabout==1 and kinds.planet==1)
        elseif id=='A2M4'then assert(kinds.listeningPost==2)
        elseif id=='A3M1'then assert(kinds.weaponPlatform==4 and not kinds.searchToken and not s.escapeEdge)end
        for enemyId,record in pairs(s.shipRecords)do
            assert(record.cardCreated and record.shieldsComplete,id..': incomplete enemy')
            assert(countOwnedShields(s,enemyId)==2,id..': physical shield count')
        end
    end
end)

test("Mission setup uses odd-player runabout counts and Influence platform counts",function()
    for players=2,6 do
        missionTable();local s=start('A2M3',players)
        local n=0;for _,o in ipairs(s.missionObjects.objects)do if o.kind=='runabout'then n=n+1 end end
        assert(n==math.ceil(players/2),'runabouts at '..players)
    end
    for influence=0,2 do
        missionTable();local s=start('A3M1',2,influence)
        assert(#STA2E.MissionObjects.hulls(s)==4-influence)
    end
end)

test("Duplicate start, wrong controller, and repeated wave retry are safe",function()
    missionTable();local human=_ship('retained-human','Blue');human.refs.base=nil
    local s=start('A1M1',4);local initial=#s.spawnedShips
    assert(not STA2E_MissionStart({id='A2M1',playerCount=2}).ok)
    assert(not STA2E_MissionReset({id='A2M1'}).ok)
    for i=1,5 do assert(STA2E_MissionRetry({id='A1M1'}).ok)end
    _drain(20000);assert(#s.spawnedShips==initial)
    assert(STA2E_MissionReset({id='A1M1'}).ok);_drain(20000)
    assert(STA2E.ships['retained-human'] and _objects['retained-human-card'])
    for _,o in ipairs(getAllObjects())do assert(not o.getGMNotes():find('STA2E_MISSION_OBJECT|',1,true))end
end)

test("Reset during asynchronous setup cancels late cards, tokens, and shields",function()
    missionTable();local human=_ship('pending-human','Blue');human.refs.base=nil
    assert(STA2E_MissionStart({id='A2M1',playerCount=6}).ok)
    assert(STA2E_MissionReset({id='A2M1'}).ok)
    _drain(20000)
    assert(not STA2E.game.alliance and STA2E.ships['pending-human'])
    for _,o in ipairs(getAllObjects())do
        assert(not o.getGMNotes():find('STA2E_MISSION_OBJECT|',1,true))
        assert(not o.getGMNotes():find('STA2E_ALLIANCE_SHIELD|',1,true))
    end
end)

test("Finale initial bearings are distinct and Beta opens its own edge in Planning",function()
    missionTable();local s=start('A3M1',6)
    STA2E.game.phase='planning';STA2E.game.round=1;STA2E_AllianceProcessRound();_drain(20000)
    local bearings={}
    for _,id in ipairs({'wing1','wing2','alpha'})do
        local w=s.waves[id];assert(w.spawned,id..': '..tostring(w.error))
        assert(not bearings[w.bearing],'duplicate initial bearing');bearings[w.bearing]=true
    end
    assert(not s.escapeEdge)
    STA2E.game.round=5;STA2E_AllianceProcessRound();_drain(20000)
    assert(s.waves.beta.spawned and s.escapeEdge==s.waves.beta.edge)
    assert(s.missionObjects.escapeEdge==s.escapeEdge and STA2E.game.phase=='planning')
    local before=#s.spawnedShips
    STA2E_AllianceProcessRound();STA2E_MissionRetry({id='A3M1'});_drain(20000)
    assert(#s.spawnedShips==before)
end)

test("Listening Posts score any survivor, require 6 hull for bonuses, and retain R10 checkpoint",function()
    missionTable();local s=start('A2M4',2)
    assert(not STA2E_MissionFinish({id='A2M4'}).ok,'premature Listening victory')
    local hulls=STA2E.MissionObjects.hulls(s)
    _objects[hulls[1].guid].call('setHull',{hull=6})
    _objects[hulls[2].guid].call('setHull',{hull=0})
    deployThrough(s,10)
    STA2E.game.round=10;STA2E.game.phase='end';STA2E_PhaseUI(Player.Blue)
    assert(s.round10Score and s.round10Score.success and s.round10Score.objectiveXP==2)
    assert(s.active and not s.finished)
    _objects[hulls[1].guid].call('setHull',{hull=5})
    STA2E.game.round=12;STA2E.game.phase='end';STA2E_PhaseUI(Player.Blue)
    assert(s.finished and s.result.objectiveXP==2)
end)

test("Listening clears all scheduled waves early as victory with current hull XP",function()
    missionTable();local s=start('A2M4',2);deployThrough(s,7)
    local hulls=STA2E.MissionObjects.hulls(s)
    _objects[hulls[1].guid].call('setHull',{hull=5})
    _objects[hulls[2].guid].call('setHull',{hull=0})
    local cards={}
    for id in pairs(s.shipRecords)do local ship=STA2E.ships[id];cards[#cards+1]=_objects[ship.cardGUID]end
    for _,card in ipairs(cards)do onObjectDestroy(card);card.destruct()end
    _drain(20000)
    assert(s.finished and s.result.outcome=='success' and s.result.objectiveXP==1)
end)

test("Stable mission save/reload retains enemy waves, two shields, and hull controls",function()
    missionTable();local s=start('A2M4',3)
    local hulls=STA2E.MissionObjects.hulls(s)
    _objects[hulls[1].guid].call('setHull',{hull=4})
    local before=#s.spawnedShips;local run=s.runId
    local saved=onSave();onLoad(saved);_drain(20000)
    local restored=STA2E.game.alliance
    assert(STA2E.ready and restored and restored.runId==run)
    assert(#restored.spawnedShips==before and restored.waves.alpha.spawned)
    assert(STA2E.MissionObjects.hulls(restored)[1].hull==4)
    for id in pairs(restored.shipRecords)do assert(countOwnedShields(restored,id)==2)end
    assert(not STA2E_MissionStatus({id='A2M4'}).pending)
    deployThrough(restored,7)
    assert(#restored.spawnedShips==6,'later three-player waves lost their counts after reload')
end)

test("Interrupted scene reload restores a missing pending platform without duplicating hull rows",function()
    missionTable()
    assert(STA2E_MissionStart({id='A3M1',playerCount=2}).ok)
    local s=STA2E.game.alliance
    assert(s.missionObjects.pending>0)
    local hulls=STA2E.MissionObjects.hulls(s)
    assert(#hulls==4)
    local removed=hulls[1].guid
    _objects[removed].destruct()
    local saved=onSave()
    _waits={} -- Loading TTS discards callbacks from the old Lua instance.
    onLoad(saved);_drain(20000)
    local restored=STA2E.game.alliance
    assert(restored.missionObjects.setupComplete and restored.missionObjects.pending==0)
    local result=STA2E.MissionObjects.hulls(restored)
    assert(#result==4,'extra hull row after interrupted scene reload')
    for _,row in ipairs(result)do assert(row.guid~=removed and _objects[row.guid])end
    local count=0
    for _,row in ipairs(restored.missionObjects.objects)do if row.kind=='weaponPlatform'then count=count+1 end end
    assert(count==4)
end)

test("Interrupted enemy card reload removes the orphan card before safe wave retry",function()
    missionTable()
    assert(STA2E_MissionStart({id='A1M1',playerCount=2}).ok)
    local pending={}
    for _,record in pairs(STA2E.game.alliance.shipRecords)do
        assert(not record.cardCreated and record.pendingCardGUID)
        pending[#pending+1]=record.pendingCardGUID
    end
    assert(#pending==2)
    local saved=onSave();_waits={}
    onLoad(saved);_drain(20000)
    for _,guid in ipairs(pending)do assert(not _objects[guid],'orphan pending card')end
    assert(STA2E_MissionRetry({id='A1M1'}).ok);_drain(20000)
    local restored=STA2E.game.alliance
    local alive=0
    for id,record in pairs(restored.shipRecords)do
        if not record.cancelled then
            alive=alive+1;assert(record.cardCreated and record.shieldsComplete)
            assert(countOwnedShields(restored,id)==2)
        end
    end
    assert(alive==2 and restored.waves.wing1.spawned and restored.waves.wing2.spawned,
        'alive='..alive..' waves='..JSON.encode(restored.waves))
    local before=#restored.spawnedShips
    STA2E_MissionRetry({id='A1M1'});_drain(20000)
    assert(#restored.spawnedShips==before)
end)

test("Blocked fixed-bearing formations retry once after the obstruction is moved",function()
    missionTable()
    local human=_ship('blocking-human','Blue')
    _objects[human.refs.base].setPosition({-18.8/3,1.3,17.25})
    local s=start('A1M1',2)
    assert(not s.waves.wing1.spawned and s.waves.wing2.spawned)
    assert(#s.spawnedShips==1)
    _objects[human.refs.base].setPosition({0,1.3,0})
    assert(STA2E_MissionRetry({id='A1M1'}).ok);_drain(20000)
    assert(s.waves.wing1.spawned and #s.spawnedShips==2)
    STA2E_MissionRetry({id='A1M1'});_drain(20000)
    assert(#s.spawnedShips==2 and STA2E.ships['blocking-human'])
end)
