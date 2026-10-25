const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {update}=require('../scripts/update-tts-m5.cjs');
const M5=require('../src/m5-core.js'),catalog=require('../public/data/m5-catalog.json');
test('M5 updater refuses unsupported or already patched saves',()=>{
  assert.throws(()=>update({LuaScript:'',SaveName:'empty'}),/Unsupported/);
  assert.throws(()=>update({LuaScript:'STA2E.M5 = {}',SaveName:'already'}),/earlier M5/);
});
test('Website export imports through the real Remodulated Lua and tracker', {skip:!process.env.STAW_M5_SAVE},()=>{
  const {lua,lauxlib,lualib,to_luastring,to_jsstring}=require('fengari');
  const original=JSON.parse(fs.readFileSync(process.env.STAW_M5_SAVE,'utf8')),save=update(original);
  assert.deepEqual(save.ObjectStates,original.ObjectStates);assert.equal(save.LuaScriptState,original.LuaScriptState);
  assert(!save.LuaScript.includes('M5 BUILDER'));assert(!save.LuaScript.includes('RUN M5'));
  const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
  function push(v){lua.lua_checkstack(L,8);if(v==null)lua.lua_pushnil(L);else if(typeof v==='string')lua.lua_pushstring(L,to_luastring(v));else if(typeof v==='number')lua.lua_pushnumber(L,v);else if(typeof v==='boolean')lua.lua_pushboolean(L,v);else{lua.lua_newtable(L);for(const[k,x]of Object.entries(v)){push(Array.isArray(v)?Number(k)+1:k);push(x);lua.lua_settable(L,-3);}}}
  function read(i){lua.lua_checkstack(L,8);const t=lua.lua_type(L,i);if(t===lua.LUA_TNIL)return null;if(t===lua.LUA_TSTRING)return to_jsstring(lua.lua_tostring(L,i));if(t===lua.LUA_TNUMBER)return lua.lua_tonumber(L,i);if(t===lua.LUA_TBOOLEAN)return lua.lua_toboolean(L,i);assert.equal(t,lua.LUA_TTABLE);const a=lua.lua_absindex(L,i),out={};lua.lua_pushnil(L);while(lua.lua_next(L,a)){out[read(-2)]=read(-1);lua.lua_pop(L,1);}const keys=Object.keys(out);return keys.length&&keys.every((k,n)=>String(n+1)===k)?Object.values(out):out;}
  lua.lua_newtable(L);lua.lua_pushjsfunction(L,()=>{try{push(JSON.parse(to_jsstring(lua.lua_tostring(L,1))));return 1;}catch(e){push(e.message);return lua.lua_error(L);}});lua.lua_setfield(L,-2,to_luastring('decode'));
  lua.lua_pushjsfunction(L,()=>{push(JSON.stringify(read(1)));return 1;});lua.lua_setfield(L,-2,to_luastring('encode'));lua.lua_setglobal(L,to_luastring('JSON'));
  const fleet={schemaVersion:2,source:{kind:'remodulated-m5',m5Version:1},fleetId:'m5-roundtrip',threatLimit:30,ships:[{shipCardId:'M5S001',cards:[{cardId:'focused_barrage'},{cardId:'hunters_algorithm'}]},{shipCardId:'M5S001',cards:[]}],resources:[]};
  push(M5.serialize(fleet,catalog));lua.lua_setglobal(L,to_luastring('EXPORT_JSON'));
  const probe=`
-- Resolve the actual embedded catalog startup batches, without TTS delays.
for _,job in ipairs(startupJobs or {}) do
 local values=JSON.decode(job.json)
 for key,value in pairs(values) do job.target[job.offset>=0 and (job.offset+key) or key]=value end
end
CATALOG={};CATALOG_ORDINAL={}
for i,card in ipairs(CATALOG_DATA.cards) do
 local asset=card.assetSheet and CATALOG_DATA.assetSheets[card.assetSheet]
 if asset then card.cardImage=asset.cardImage;card.cardBack=asset.cardBack;card.sheet=card.sheet or {};card.sheet.width=asset.width;card.sheet.height=asset.height;card.sheet.uniqueBack=asset.uniqueBack end
 if card.publishedFace then card.cardImage=card.publishedFace;card.sheet=nil end
 CATALOG[card.id]=card;CATALOG_ORDINAL[card.id]=i
end
STA2E.game={phase='setup',round=0,nextId=100,fleets={}};STA2E.ships={};STA2E.ready=true
local objects,callbacks={},{}
getAllObjects=function()return{}end;getObjectFromGUID=function(id)return objects[id]end
UI={setXml=function()end};Wait={frames=function()end,time=function()end}
broadcastToColor=function()end;broadcastToAll=function()end
hud=function()end;render=function()end;sync=function()end
STA2E_Reconcile()
assert(CATALOG.M5S001 and SHIP_DEFINITIONS.M5S001,'M5 deployment definition installed')
local parsed,err=parseFleet(EXPORT_JSON);assert(parsed,err)
local review,err=reviewFleet(parsed);assert(review,err);assert(review.rows==2,'one ship per row')
assert(review.cost==16,'website and TTS threat agree')
local bad=JSON.decode(EXPORT_JSON);bad.ships[1].cards[1].cardId='C001';assert(not reviewFleet(bad),'normal upgrades rejected')
bad=JSON.decode(EXPORT_JSON);bad.source.m5Version=2;assert(not reviewFleet(bad),'unknown schema version rejected')
bad=JSON.decode(EXPORT_JSON);bad.ships[1].cards[3]={cardId='focused_barrage'};assert(not reviewFleet(bad),'duplicates rejected')
local plain=parseFleet('S193');assert(reviewFleet(plain),'normal import still valid')
fleetStagingLane=function()return{x=0,y=1,z=0},0 end
playerSideTransform=function(color,origin,offset)return{position={origin.x+(offset.side or 0),origin.y+(offset.up or 0),origin.z+(offset.forward or 0)},facing=0,rotation={0,0,0}}end
spawnFleetShields=function()end;deploy=function()end
local serial=0
spawnObjectData=function(params)
 serial=serial+1;local guid='test-'..serial
 local o={getGUID=function()return guid end,getPosition=function()return{x=params.position[1],y=params.position[2],z=params.position[3]}end}
 o.call=function(name,value)o.memory=value end;o.destruct=function()objects[guid]=nil end
 objects[guid]=o;table.insert(callbacks,function()params.callback_function(o)end);return o
end
assert(STA2E_ImportFleet({color='Red',fleet=parsed}).ok)
assert(not STA2E_ImportFleet({color='Red',fleet=parsed}).ok,'pending import deduplication')
for i=#callbacks,1,-1 do callbacks[i]() end
local ids=STA2E.game.fleets['Red:m5-roundtrip'];assert(#ids==2)
local ship=STA2E.ships[ids[1]]
assert(ship.definitionId=='M5S001' and ship.m5.finalCaptainSkill==5 and ship.m5.slotsUsed==3)
assert(#ship.upgrades==2 and ship.upgrades[1].cardId=='focused_barrage','program order survives reversed callbacks')
assert(objects[ship.cardGUID].memory.m5.finalCaptainSkill==5,'authoritative card persistence')
assert(not STA2E_ImportFleet({color='Red',fleet=parsed}).ok,'completed import deduplication')
local persisted=JSON.decode(JSON.encode(objects[ship.cardGUID].memory));assert(persisted.m5.programs[2]=='hunters_algorithm')
objects[ship.upgrades[1].guid]=nil;assert(ship.m5.programs[1]=='focused_barrage','physical program deletion does not change installed state')
complete=function()return true end
local plans,moves,attacks=0,0,0
STA2E.M5.planShip=function(s)plans=plans+1;s.state.maneuver='S1';s.state.status='ready';return{key='S1'}end
executeMove=function(s)moves=moves+1;s.state.status='complete'end
STA2E.M5.primaryAttack=function(s)attacks=attacks+1;s.state.fired=true;return{}end
STA2E.game.phase='activation'
STA2E_M5TrackerStep(ship,{color='Blue'});assert(moves==0,'ownership guard')
STA2E_M5TrackerStep(ship,{color='Red'});STA2E_M5TrackerStep(ship,{color='Red'});assert(moves==1,'one activation')
STA2E.game.phase='combat'
STA2E_M5TrackerStep(ship,{color='Red'});STA2E_M5TrackerStep(ship,{color='Red'});assert(attacks==1,'one attack')
assert(STA2E_M5TrackerButton(ship,0):find('FIRED'),'tracker state')
`;
  const code=save.LuaScript+'\n;(function()\n'+probe+'\nend)()';
  if(lauxlib.luaL_loadbuffer(L,to_luastring(code),null,to_luastring('M5 integration'))!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
  if(lua.lua_pcall(L,0,0,0)!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
});
