-- Minimal API doubles. Does not simulate Unity physics, network, or rendering.
JSON={decode=_jsonDecode,encode=_jsonEncode}
-- Lua 5.2/MoonSharp exposes atan2; Lua 5.3 moved it into two-argument atan.
math.atan2=math.atan2 or function(y,x)return math.atan(y,x)end
Time={time=0}
_objects={}; _waits={}; _messages={}; _xml=""; _spawned=0; _hudWrites=0
function print(...) local a={...};for i,v in ipairs(a) do a[i]=tostring(v) end;_auditLog(table.concat(a," ")) end
function broadcastToColor(message,color) table.insert(_messages,{message=message,color=color}) end
function broadcastToAll(message) table.insert(_messages,{message=message}) end
function getObjectFromGUID(guid) return _objects[guid] end
function getObjects() local out={};for _,o in pairs(_objects) do if not o._destroyed then table.insert(out,o) end end;return out end
getAllObjects=getObjects
function _vector(v) return {x=v.x or v[1] or 0,y=v.y or v[2] or 0,z=v.z or v[3] or 0} end
Vector=setmetatable({},{__call=function(_,...) local a={...};return _vector(type(a[1])=="table" and a[1] or a) end})
Color=setmetatable({},{__call=function(_,v) return v end})
UI={setXml=function(xml) _xml=xml;_hudWrites=_hudWrites+1 end,getXml=function() return _xml end,setAttribute=function() end}
Wait={}
local seq=0
local function schedule(fn,delay) seq=seq+1;table.insert(_waits,{fn=fn,time=Time.time+delay,seq=seq});return seq end
function Wait.frames(fn,frames) return schedule(fn,(frames or 1)/60) end
function Wait.time(fn,seconds) return schedule(fn,seconds or 0) end
function Wait.condition(fn,condition,timeout,timeoutfn)
    local start=Time.time
    local function poll()
        if condition() then fn()
        elseif timeout and Time.time-start>timeout then if timeoutfn then timeoutfn() end
        else Wait.frames(poll,1) end
    end
    return Wait.frames(poll,1)
end
function _drain(maximum)
    local steps=0
    while #_waits>0 do
        steps=steps+1;assert(steps<=(maximum or 2000),"mock Wait callback limit")
        table.sort(_waits,function(a,b)return a.time==b.time and a.seq<b.seq or a.time<b.time end)
        local job=table.remove(_waits,1);Time.time=job.time;job.fn()
    end
    return steps
end
function _object(guid,memory,position)
    local o={guid=guid,_memory=memory,_position=_vector(position or {0,1,0}),_rotation=_vector({0,0,0}),_buttons={},_inputs={},_name=guid,_notes="",_xml="",tag="Generic",resting=true,isSmoothMoving=false}
    o.getGUID=function()return guid end
    o.getTable=function(key)return key=="memory" and o._memory or nil end
    o.setTable=function(key,value)if key=="memory" then o._memory=value end end
    o.call=function(name,value)if name=="STA2E_SetMemory" then o._memory=value elseif name=="STA2E_SetDisplay" then o._display=value end end
    o.getPosition=function()return _vector(o._position) end
    o.setPosition=function(p)o._position=_vector(p) end
    o.setPositionSmooth=o.setPosition
    o.getRotation=function()return _vector(o._rotation) end
    o.setRotation=function(r)o._rotation=_vector(r) end
    o.setRotationSmooth=o.setRotation
    o.getScale=function()return _vector({1,1,1}) end
    o.setScale=function()end
    o.flip=function()o._flipped=not o._flipped end
    o.getBounds=function()return {center=o.getPosition(),size={x=2.8,y=0.2,z=2.8}} end
    o.getBoundsNormalized=o.getBounds
    o.getVisualBoundsNormalized=o.getBounds
    o.getName=function()return o._name end
    o.setName=function(v)o._name=v end
    o.getGMNotes=function()return o._notes end
    o.setGMNotes=function(v)o._notes=v end
    o.getDescription=function()return "" end
    o.setDescription=function()end
    o.setLock=function(v)o.locked=v end
    o.getLock=function()return o.locked or false end
    o.highlightOn=function()end; o.highlightOff=function()end
    o.setVectorLines=function(lines)o._lines=lines end
    o.getVectorLines=function()return o._lines or {} end
    o.getObjects=function()return o._contents or {} end
    o.getTags=function()return o._tags or {} end
    o.hasTag=function(tag)for _,t in ipairs(o._tags or {})do if t==tag then return true end end;return false end
    o.clearButtons=function()o._buttons={} end
    o.createButton=function(b)table.insert(o._buttons,b) end
    o.editButton=function()end
    o.createInput=function(b)table.insert(o._inputs,b) end
    o.clearInputs=function()o._inputs={} end
    o.getButtons=function()return o._buttons end
    o.getInputs=function()return o._inputs end
    o.getValue=function()return o._value or 1 end
    o.getRotationValue=function()return o._rotationValue or "Hit" end
    o.getRotationValues=function()return {} end
    o.setValue=function(v)o._value=v end
    o.randomize=function()o.resting=false end
    o.roll=o.randomize
    o.destruct=function()o._destroyed=true;_objects[guid]=nil end
    o.UI={setXml=function(xml)o._xml=xml end,getXml=function()return o._xml end,setAttribute=function()end}
    _objects[guid]=o;return o
end
function spawnObjectData(params)
    _spawned=_spawned+1
    local o=_object("mock-".._spawned,nil,params.position or {0,1,0})
    local data=params.data or {};o._name=data.Nickname or data.Name or o.guid
    if data.LuaScriptState and data.LuaScriptState~="" then o._memory=JSON.decode(data.LuaScriptState) end
    if params.rotation then o.setRotation(params.rotation) end
    if params.callback_function then Wait.frames(function()params.callback_function(o) end,1) end
    return o
end
function spawnObjectJSON(params)params.data=JSON.decode(params.json);return spawnObjectData(params) end
function spawnObject(params)return spawnObjectData(params) end
Player=setmetatable({},{__index=function(t,k)local p={color=k,host=k=="Black",lookAt=function()end,getHandTransform=function()return {position={0,1,0},rotation={0,0,0}} end};rawset(t,k,p);return p end})
Global={call=function(name,args)return _G[name](args) end}
Physics={cast=function()return {} end}
function _ship(id,owner,definitionId)
    local s={schemaVersion=1,instanceId=id,cardGUID=id.."-card",role="card",owner=owner or "Blue",definitionId=definitionId or "S193",name=id,refs={},upgrades={},state={status="planning"},capabilities={actions={"EVA","BS","TL","CLK","ECHO"}},conflicts={}}
    _object(s.cardGUID,s)
    for _,role in ipairs({"base","model","dial","reference"}) do
        local guid=id.."-"..role;s.refs[role]=guid
        _object(guid,{schemaVersion=1,instanceId=id,cardGUID=s.cardGUID,role=role})
    end
    STA2E.ships[id]=s;return s
end
function _reset()
    _objects={};_waits={};_messages={};_xml="";_hudWrites=0
    STA2E.hudEpoch=(STA2E.hudEpoch or 0)+1;STA2E.hudScheduled=nil
    STA2E.ships={};STA2E.pending={};STA2E.imports={};STA2E.pendingMoves={};STA2E.ready=true;STA2E.loading=false;STA2E.reconciling=false
    STA2E.game={phase="planning",round=1,nextId=100,fleets={},initiative="Blue"}
    STA2E.manageCard={};STA2E.dice={};STA2E.diceOpen={};STA2E.diceSource={};STA2E.sensorEcho={}
    STA2E.fleetText={};STA2E.fleetStatus={};STA2E.fleetPlans={};STA2E.fleetColor=nil
end
function test(name,fn)
    local ok,detail=pcall(fn)
    _auditRecord(name,ok,ok and (type(detail)=="string" and detail or "") or tostring(detail))
end
