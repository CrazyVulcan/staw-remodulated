local function setup()
    _reset()
    local board=_object('ae9c49',nil,{0,0.53,0});board.setRotation({0,90,0})
    board.getScale=function()return {x=1.89,y=1.87,z=1.89}end
    local bag=_object('df60bd',nil,{60,1,60})
    bag.takeObject=function(p)return spawnObjectData({data={Name='Custom_Token',Nickname='Shield'},position=p.position,callback_function=p.callback_function})end
end
local cases={
 {id='A2M3',kind='runabout',count=3,hull=2},
 {id='A4M1',kind='freighter',count=12,hull=3},
 {id='A6M2',kind='tenthFleet',count=6,hull=4}}

local function checkCase(c,s)
    local n=0
    for _,row in ipairs(s.missionObjects.objects)do
        if row.kind==c.kind then
            n=n+1
            local base=assert(_objects[row.guid]);local data=assert(base._spawnData)
            assert(data.Name=='Custom_Model' and data.CustomMesh.MeshURL==STANDARD_BASE.CustomMesh.MeshURL)
            assert(math.abs(data.Transform.scaleX-1.174999)<0.00001 and math.abs(data.Transform.scaleZ-1.174999)<0.00001)
            assert(#base.getAttachments()==1,'missing/duplicate attached model')
            local attachment=base.getAttachments()[1]
            assert(attachment.data.Name=='Custom_Model' and attachment.data.CustomMesh.MeshURL~=STANDARD_BASE.CustomMesh.MeshURL)
            assert(attachment.name:find('Model',1,true))
            assert(attachment.position.x==base.getPosition().x and attachment.position.z==base.getPosition().z)
            assert(attachment.rotation.y==base.getRotation().y)
            assert(base._objectiveScript and base._objectiveScript.getHull().maxHull==c.hull)
            assert(base._buttons[2].width==133 and base._buttons[2].height==113)
            assert(base._buttons[4].label=='MOVE' and base._buttons[4].position[3]<0)
            assert(base._buttons[5].label=='ARC')
            assert(base._buttons[1].position[3]==0.95,'counter overlaps model centre')
        end
    end
    assert(n==c.count,c.id..' base count '..n)
    for _,o in ipairs(getAllObjects())do assert(not o.getGMNotes():find('|scenarioModel|',1,true),'loose model after setup')end
end

for _,c in ipairs(cases)do
 test('Standard based and attached mission ships '..c.id,function()
    setup();local r=STA2E_MissionStart({id=c.id,playerCount=6,influence=1});assert(r.ok,r.error);_drain(30000)
    local s=STA2E.game.alliance;assert(s.missionObjects.setupComplete)
    checkCase(c,s)
    local saved=onSave();_waits={};onLoad(saved);_drain(30000)
    s=STA2E.game.alliance;assert(s.missionObjects.setupComplete);checkCase(c,s)
    STA2E_Reconcile();checkCase(c,s)
    assert(STA2E_MissionReset({id=c.id}).ok);_drain(30000)
    for _,o in ipairs(getAllObjects())do assert(not o.getGMNotes():find('STA2E_MISSION_OBJECT|',1,true))end
 end)
end

test('Rules notecard spawns below fleet staging cards and dials',function()
    setup();assert(STA2E_MissionStart({id='A6M2',playerCount=2}).ok);_drain(30000)
    local rules
    for _,row in ipairs(STA2E.game.alliance.missionObjects.objects)do if row.kind=='rules' then rules=_objects[row.guid]end end
    assert(rules and rules.getPosition().z<-28)
    assert(math.abs(rules.getPosition().z-(-12.5))>15)
end)

for _,c in ipairs(cases) do
 test('Scenario move and arc controls '..c.id,function()
    setup();assert(STA2E_MissionStart({id=c.id,playerCount=2}).ok);_drain(30000)
    local base
    for _,row in ipairs(STA2E.game.alliance.missionObjects.objects) do if row.kind==c.kind then base=_objects[row.guid];break end end
    assert(base);local env=base._objectiveScript
    -- Give movement a clear area and verify the physical button callbacks.
    base.setPosition({100,1,100});base.setRotation({0,0,0})
    env.scenarioToggleMove();assert(base._buttons[4].label=='CLOSE')
    assert(#base._buttons==(c.kind=='freighter' and 9 or 15))
    local key=c.kind=='runabout' and 'S1' or 'S2'
    assert(not STA2E_ScenarioMove({guid=base.getGUID(),key='S5'}),'illegal scenario move accepted')
    env['scenarioMove_'..key](nil,'Blue')
    assert(not STA2E_ScenarioMove({guid=base.getGUID(),key=key}),'overlapping move accepted')
    _drain(30000)
    local expected=c.kind=='runabout' and 3.10 or 4.60
    assert(math.abs(base.getPosition().z-(100-expected))<0.001,'incorrect movement endpoint')
    assert(base._buttons[4].label=='MOVE' and #base.getAttachments()==1)
    env.scenarioToggleArc();assert(#base.getVectorLines()>0 and base._buttons[5].label=='CLEAR')
    env.scenarioToggleArc();assert(#base.getVectorLines()==0 and base._buttons[5].label=='ARC')
    env.setHull({hull=0,silent=true})
    assert(not STA2E_ScenarioMove({guid=base.getGUID(),key=key}),'destroyed objective moved')
 end)
end

test('Interrupted attached ship setup recovers missing model once',function()
    setup();assert(STA2E_MissionStart({id='A6M2',playerCount=2}).ok)
    local s=STA2E.game.alliance;assert(s.missionObjects.pending>0)
    local removed
    for _,row in ipairs(s.missionObjects.objects)do if row.kind=='scenarioModel' then removed=row.guid;_objects[removed].destruct();break end end
    assert(removed)
    local saved=onSave();_waits={};onLoad(saved);_drain(30000)
    s=STA2E.game.alliance
    assert(s.missionObjects.setupComplete,table.concat(s.missionObjects.errors,';'))
    local count=0
    for _,row in ipairs(s.missionObjects.objects)do if row.kind=='tenthFleet' then
        count=count+1;assert(#_objects[row.guid].getAttachments()==1)
    end end
    assert(count==2)
    for _,o in ipairs(getAllObjects())do assert(not o.getGMNotes():find('|scenarioModel|',1,true))end
end)

test('Reset during base/model spawning cancels all late models',function()
    setup();assert(STA2E_MissionStart({id='A4M1',playerCount=6}).ok)
    assert(STA2E_MissionReset({id='A4M1'}).ok);_drain(30000)
    for _,o in ipairs(getAllObjects())do assert(not o.getGMNotes():find('STA2E_MISSION_OBJECT|',1,true))end
end)
