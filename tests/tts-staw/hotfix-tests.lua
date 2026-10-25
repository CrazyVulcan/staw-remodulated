-- Reproduce the numeric-zero-key trigger with an explicit encoder policy.
-- This is a targeted simulation, not TTS's actual JSON implementation.
local function guardNumericKeys(value, seen)
    if type(value)~='table' then return end
    seen=seen or {};if seen[value]then return end;seen[value]=true
    for key, child in pairs(value)do
        assert(not(type(key)=='number' and key<=0), 'TTS JSON numeric-object-key conversion trigger: '..tostring(key))
        guardNumericKeys(child,seen)
    end
end

local function withKeyPolicy(fn)
    local original=JSON.encode
    JSON.encode=function(value,...)guardNumericKeys(value);return original(value,...)end
    local ok,err=pcall(fn)
    JSON.encode=original
    assert(ok,tostring(err))
end

test('JSON regression policy detects nested zero keys and permits string keys',function()
    withKeyPolicy(function()
        local ok,err=pcall(JSON.encode,{objective={platformsByInfluence={[0]=4,[1]=3,[2]=2}}})
        assert(not ok and tostring(err):find('numeric-object-key conversion trigger',1,true))
        assert(JSON.decode(JSON.encode({objective={platformsByInfluence={['0']=4,['1']=3,['2']=2}}})).objective.platformsByInfluence['0']==4)
    end)
end)

test('Every mission definition serializes without numeric zero keys',function()
    withKeyPolicy(function()
        for id,definition in pairs(STA2E_MISSION_DEFINITIONS)do
            assert(JSON.decode(JSON.encode(definition)).id==id)
        end
    end)
end)

for influence=0,2 do
    test('Act III setup and save/reload pass numeric-key policy at Influence '..influence,function()
        withKeyPolicy(function()
            _reset()
            local board=_object('ae9c49',nil,{0,0.53,0});board.setRotation({0,90,0})
            board.getScale=function()return {x=1.89,y=1.87,z=1.89}end
            local bag=_object('df60bd',nil,{60,1,60})
            bag.takeObject=function(params)
                return spawnObjectData({data={Name='Custom_Token',Nickname='Shield'},position=params.position,callback_function=params.callback_function})
            end
            local result=STA2E_MissionStart({id='A3M1',playerCount=2,influence=influence,color='Blue'})
            assert(result.ok,result.error);_drain(20000)
            local state=assert(STA2E.game.alliance)
            assert(state.missionObjects.setupComplete and #state.missionObjects.errors==0)
            assert(#STA2E.MissionObjects.hulls(state)==4-influence)
            local runId=state.runId
            local saved=onSave();_waits={};onLoad(saved);_drain(20000)
            state=assert(STA2E.game.alliance)
            assert(STA2E.ready and state.runId==runId and state.missionId=='A3M1')
            assert(state.influence==influence and state.settings.influence==influence and state.playerCount==2)
            assert(state.missionObjects.setupComplete and not STA2E_MissionStatus({id='A3M1'}).pending)
            local count=0
            for _,row in ipairs(STA2E.MissionObjects.hulls(state))do
                assert(_objects[row.guid] and not _objects[row.guid]._destroyed)
                count=count+1
            end
            assert(count==4-influence,'live platforms after reload')
            assert(state.definition.objective.platformsByInfluence[tostring(influence)]==4-influence)
            assert(type(onSave())=='string')
        end)
    end)
end
