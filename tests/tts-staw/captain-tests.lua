local ids={"AC0001","AC0009","AC0017"}
local function attachBoard(object,data,saved)
    object.clearContextMenu=function() end
    object.addContextMenuItem=function() end
    object._xml=data.XmlUI
    local attributes={}
    object.UI.setAttribute=function(id,key,value) attributes[id]=attributes[id] or {};attributes[id][key]=value end
    local env=setmetatable({self=object},{__index=_G});env._G=env
    local chunk,error=load(data.LuaScript,"alliance-captain-"..object.guid,"t",env)
    assert(chunk,error);chunk()
    object.getTable=function(key) return key=="memory" and env.memory or nil end
    object.call=function(name,args) if env[name] then return env[name](args) end end
    env.onLoad(saved or data.LuaScriptState)
    return env,attributes
end
local function captainShip(id,cardId)
    _reset();local ship=_ship(id,"Blue","S274")
    local board=_object(id.."-captain")
    ship.upgrades={{cardId=cardId,guid=board.guid,index=1}}
    local data=assert(CATALOG[cardId].objectData)
    local state=JSON.decode(data.LuaScriptState)
    state.name="Captain Test";state.memory={schemaVersion=1,role="upgrade",instanceId=ship.instanceId,cardGUID=ship.cardGUID,cardId=cardId}
    local env,attributes=attachBoard(board,data,JSON.encode(state))
    return ship,board,env,attributes
end

test("Three Alliance captain routes retain the supplied tile, artwork, XML, and interactive script",function()
    for _,id in ipairs(ids) do
        local card=assert(CATALOG[id]);local data=assert(card.objectData)
        assert(card.type=="captain" and card.interactiveCaptain and card.skill==2)
        assert(data.Name=="Custom_Tile" and data.CustomImage.ImageURL==card.cardImage)
        assert(data.XmlUI:find('onEndEdit="nameUpdate"',1,true))
        assert(data.XmlUI:find('onClick="SkillUp"',1,true))
        local ship,board,env=captainShip("art-"..id,id)
        assert(env.STA2E_CaptainSnapshot().skill==2)
    end
end)

test("Every captain track calculates XP, clamps to the printed track, and preserves expansion choices",function()
    for _,id in ipairs(ids) do
        local ship,board,env,attributes=captainShip("xp-"..id,id)
        env.SkillUp();env.SkillUp();env.CrewUp();env.WeaponUp();env.TechUp();env.EliteUp()
        assert(env.totalPoints==6 and attributes.Cost.text=="6" and board.value==6)
        assert(ship.allianceCaptain.skill==3 and ship.allianceCaptain.xp==6)
        env.option1Selected(nil,"Weapon");env.option2Selected(nil,"Tech")
        for _=1,40 do env.SkillUp();env.CrewUp() end
        assert(env.SkillPoints==14 and env.CrewPoints==10 and env.STA2E_CaptainSnapshot().skill==9)
        for _=1,40 do env.SkillDown();env.CrewDown() end
        assert(env.SkillPoints==0 and env.CrewPoints==0 and env.STA2E_CaptainSnapshot().skill==2)
        local saved=JSON.decode(env.onSave())
        assert(saved.ExpansionOne=="Weapon" and saved.ExpansionTwo=="Tech")
    end
end)

test("Captain input name and skill update the associated tracker row without renaming its ship",function()
    local ship,board,env=captainShip("captain-live","AC0001")
    local originalName=ship.name
    env.nameUpdate(Player.Blue,'T\'Pol & <Captain>');env.SkillUp();env.SkillUp();_drain()
    assert(ship.name==originalName and ship.allianceCaptain.name=='T\'Pol & <Captain>')
    assert(ship.allianceCaptain.skill==3)
    assert(_xml:find("T'Pol &amp; &lt;Captain&gt;",1,true) and _xml:find(ship.name,1,true))
    ship.skillOverride=7;env.nameUpdate(Player.Blue,"Captain Renamed")
    assert(ship.skillOverride==7,"A name-only edit removed a temporary skill override")
    env.SkillUp();env.SkillUp()
    assert(ship.skillOverride==nil,"A captain skill edit left the tracker using the old override")
end)

test("Captain state and ship association survive independent board save and reload",function()
    local ship,board,env=captainShip("captain-reload","AC0017")
    env.nameUpdate(Player.Blue,"Commander Ael");env.SkillUp();env.SkillUp();env.SkillUp();env.SkillUp();env.CrewUp();env.option1Selected(nil,"Crew")
    local saved=env.onSave()
    ship.allianceCaptain=nil
    local reloaded=attachBoard(board,CATALOG.AC0017.objectData,saved)
    assert(reloaded.SkillPoints==4 and reloaded.CrewPoints==1 and reloaded.ExpansionOne=="Crew")
    assert(reloaded.memory.instanceId==ship.instanceId and reloaded.memory.cardGUID==ship.cardGUID)
    assert(ship.allianceCaptain.name=="Commander Ael" and ship.allianceCaptain.skill==4 and ship.allianceCaptain.xp==5)
end)

test("Renaming a ship card updates the tracker and persists without overwriting captain identity",function()
    local ship,board,env=captainShip("ship-rename","AC0009")
    STA2E.AllianceCaptain.scan();_drain()
    _objects[ship.cardGUID].setName("I.K.S. Courage & Honor")
    STA2E.AllianceCaptain.scan();_drain()
    assert(ship.name=="I.K.S. Courage & Honor" and ship.allianceCaptain.name=="Captain Test")
    assert(_objects[ship.cardGUID]._memory.name==ship.name)
    assert(_xml:find("I.K.S. Courage &amp; Honor",1,true))
    local savedName=ship.name;STA2E_Reconcile();_drain()
    assert(STA2E.ships[ship.instanceId].name==savedName)
end)

test("Unchanged name scans do not redraw the HUD or rewrite ship state",function()
    local ship,board,env=captainShip("name-cache","AC0001")
    STA2E.AllianceCaptain.scan();_drain();local before=_hudWrites
    for _=1,30 do STA2E.AllianceCaptain.scan() end
    _drain();assert(_hudWrites==before)
end)

test("The live update callback detects ship-card renames with a half-second scan limit",function()
    local ship,board,env=captainShip("live-name-poll","AC0001")
    _drain()
    Time.time=Time.time+1;onUpdate();_drain()
    _objects[ship.cardGUID].setName("U.S.S. Pathfinder")
    Time.time=Time.time+1;onUpdate();_drain()
    assert(ship.name=="U.S.S. Pathfinder")
    _objects[ship.cardGUID].setName("U.S.S. Voyager")
    Time.time=Time.time+0.1;onUpdate()
    assert(ship.name=="U.S.S. Pathfinder","Name polling ignored its time limit")
    Time.time=Time.time+0.6;onUpdate();_drain()
    assert(ship.name=="U.S.S. Voyager")
end)

test("Captain notifications cannot update another ship or a card outside the imported upgrades",function()
    local ship,board,env=captainShip("captain-owner","AC0001")
    local other=_ship("captain-other","Red")
    STA2E_AllianceCaptainChanged({object=board,snapshot={name="Valid",skill=4,xp=4}})
    assert(ship.allianceCaptain.name=="Valid" and not other.allianceCaptain)
    env.memory.instanceId=other.instanceId;env.memory.cardGUID=other.cardGUID
    STA2E_AllianceCaptainChanged({object=board,snapshot={name="Wrong Ship",skill=9,xp=14}})
    assert(not other.allianceCaptain)
end)

test("Fleet import spawns the scripted captain object and attaches it to the correct ship",function()
    for _,id in ipairs(ids) do
        _reset();_object("3b5e31",nil,{0,1,0})
        Player.Blue.steam_name="Player Example"
        local originalSpawn=spawnObjectData;local board,boardEnv,spawnedData
        spawnObjectData=function(params)
            local object=originalSpawn(params)
            if params.data and params.data.LuaScript and params.data.LuaScript:find("STA2E_CaptainSnapshot",1,true) then
                spawnedData=params.data;board=object;boardEnv=attachBoard(object,params.data)
            end
            return object
        end
        local ok,error=pcall(function()
            local result=STA2E_ImportFleet({color="Blue",fleet={schemaVersion=2,fleetId="captain-import-"..id,ships={{shipCardId="S274",cards={{cardId=id,role="captain"}}}}}})
            assert(result.ok,result.error);_drain()
            assert(board and boardEnv and spawnedData.Name=="Custom_Tile")
            assert(spawnedData.XmlUI:find('onEndEdit="nameUpdate"',1,true),"Import erased the XP-card XML")
            assert(boardEnv.memory.role=="upgrade" and boardEnv.memory.cardId==id)
            local ship=assert(STA2E.ships[boardEnv.memory.instanceId])
            assert(boardEnv.memory.cardGUID==ship.cardGUID and ship.allianceCaptain.guid==board.guid)
            assert(ship.allianceCaptain.name=="Player Example")
            boardEnv.nameUpdate(Player.Blue,"Imported Captain");boardEnv.SkillUp();boardEnv.SkillUp();_drain()
            assert(ship.allianceCaptain.name=="Imported Captain" and ship.allianceCaptain.skill==3)
        end)
        spawnObjectData=originalSpawn;assert(ok,tostring(error))
    end
end)
