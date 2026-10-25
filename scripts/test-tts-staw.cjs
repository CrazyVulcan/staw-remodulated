// Run the established regression suites against the exact packaged Global and objects.
// Fengari mocks TTS; live multiplayer, rendering and physics still need playtesting.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const dir=path.resolve(__dirname,'../tests/tts-staw'),release=path.resolve(__dirname,'../tts/staw');
const {manifest,save}=require('./build-tts-staw.cjs').assemble();
const {push,read,cfunction,execute,results,lua,lauxlib,lualib,to_luastring,to_jsstring}=require('../tests/tts-staw/harness.cjs');
const readTest=file=>fs.readFileSync(path.join(dir,file),'utf8');
const syntax=[];
function compile(code,name){
  const L=lauxlib.luaL_newstate();
  const status=lauxlib.luaL_loadbuffer(L,to_luastring(code.replace(/!=/g,'~=')),null,to_luastring('@'+name));
  syntax.push({name,pass:status===lua.LUA_OK,error:status===lua.LUA_OK?null:to_jsstring(lua.lua_tostring(L,-1))});
  lua.lua_close(L);
}
function walk(value,name='$'){
  if(!value||typeof value!=='object')return;
  if(typeof value.LuaScript==='string'&&value.LuaScript.trim()){
    compile(value.LuaScript,name);
    for(const match of value.LuaScript.matchAll(/\b([A-Z][A-Z0-9_]*SCRIPT)\s*=\s*\[(=*)\[([\s\S]*?)\]\2\]/g))compile(match[3],name+':'+match[1]);
  }
  for(const[key,child]of Object.entries(value))if(child&&typeof child==='object')walk(child,name+'.'+key);
}
// Read the package separately: source/package drift must fail before any behavior test.
assert.deepEqual(save,JSON.parse(fs.readFileSync(path.join(release,manifest.file),'utf8')));
walk(save);
const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
cfunction(L,'_jsonDecode',state=>{push(state,JSON.parse(read(state,1)));return 1;});
cfunction(L,'_jsonEncode',state=>{push(state,JSON.stringify(read(state,1)));return 1;});
cfunction(L,'_auditRecord',state=>{results.tests.push({name:read(state,1),pass:read(state,2),detail:read(state,3)});return 0;});
cfunction(L,'_auditLog',state=>{results.logs.push(read(state,1));return 0;});
cfunction(L,'_missionScriptSource',state=>{
  const name=read(state,1);assert(['hull-counter.lua','mission-controller.lua'].includes(name));
  push(state,readTest('fixtures/'+name));return 1;
});
cfunction(L,'_book3ControllerSource',state=>{const id=read(state,1);push(state,save.ObjectStates.find(o=>o.GMNotes?.split('|')[0]==='STA2E_MISSION_CONTROLLER'&&o.GMNotes.split('|')[1]===id)?.LuaScript);return 1;});
cfunction(L,'_playtestDiceSource',state=>{push(state,save.ObjectStates.find(o=>o.GUID==='5084a4').LuaScript);return 1;});
cfunction(L,'_returnedObjectSource',state=>{push(state,save.ObjectStates.find(o=>o.GUID===read(state,1))?.LuaScript);return 1;});
try{
  execute(L,readTest('mock-tts.lua'),'mock-tts.lua');
  execute(L,save.LuaScript,'packaged Global.lua');
  execute(L,require('../tests/tts-staw/retired-dice.cjs'),'retired dice dashboard tests');
  if(process.argv.includes('--focus-base')){
    execute(L,readTest('mission-tests.lua').split('test("Mission definitions')[0],'extended object mocks');
    execute(L,'onLoad("");_drain(20000)','startup');
    execute(L,readTest('base-arcs-echo-tests.lua'),'base-arcs-echo-tests.lua');
  }else for(const name of ['global-tests.lua','core-regression-tests.lua','extra-regression-tests.lua','mission-tests.lua','colors-tests.lua','cards-tests.lua','startup-tests.lua','release-tests.lua','hotfix-tests.lua','book2-tests.lua','based-ships-tests.lua','book3-tests.lua','controller-tests.lua','maneuver-tests.lua','hover-tests.lua','captain-tests.lua','playtest-tests.lua','followup-tests.lua','anticipation-tests.lua','base-arcs-echo-tests.lua'])execute(L,readTest(name),name);
}catch(error){results.tests.push({name:'Harness execution',pass:false,detail:error.message});}
lua.lua_close(L);
const output=path.resolve(__dirname,'../test-results');fs.mkdirSync(output,{recursive:true});
fs.writeFileSync(path.join(output,'tts-staw.json'),JSON.stringify({...results,syntax},null,2)+'\n');
const failures=[...syntax,...results.tests].filter(result=>!result.pass);
console.log(`Packaged Lua compilation: ${syntax.filter(r=>r.pass).length}/${syntax.length}`);
console.log(`STAW behavior: ${results.tests.filter(r=>r.pass).length}/${results.tests.length}`);
for(const failure of failures)console.error(failure);
if(failures.length)process.exitCode=1;
