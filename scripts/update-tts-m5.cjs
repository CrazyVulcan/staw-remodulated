const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
function update(save){
  let script=save.LuaScript;
  assert.equal(typeof script,'string','Save has no Global Lua');
  assert(!script.includes('STA2E.M5 ='),'Use the original Remodulated save, without an earlier M5 patch.');
  for(const hook of ['local function aiEvaluate(s)','local function aiSide(s)','function STA2E_AI_AfterMove(s,key)','function MeasurementGeometry.measure','local function executeMove(s,color,manualKey)'])assert(script.includes(hook),'Unsupported save: missing '+hook);
  const tracker=script.split('\n').find(line=>line.includes('if s.ai then table.insert(parts,')&&line.includes('activate_ai_'));
  const instance=script.split('\n').find(line=>line.includes('shipInstances[i]={schemaVersion=1'));
  assert(tracker&&instance,'Unsupported tracker/importer. No output written.');
  script=script.replace(tracker,'        if s.m5 and s.m5.controlled then table.insert(parts,STA2E_M5TrackerButton(s,y))\n        else\n'+tracker+'\n        end');
  script=script.replace(instance,instance+'\n        STA2E_M5Attach(shipInstances[i],ship)');
  const read=name=>fs.readFileSync(path.join(root,'tts',name),'utf8');
  const catalog=fs.readFileSync(path.join(root,'public/data/m5-catalog.json'),'utf8');
  script+='\n;(function()\n'+read('m5-core.lua')+'\nM5.CATALOG=JSON.decode([====['+catalog+']====])\n'+read('m5-remodulated.lua')+'\n'+read('m5-tracker.lua')+'\nend)()\n';
  return {...save,SaveName:save.SaveName+' — M5 Tracker',LuaScript:script};
}
if(require.main===module){
  const [input,output]=process.argv.slice(2);
  if(!input||!output)throw Error('Usage: node scripts/update-tts-m5.cjs "original-save.json" "new-M5-save.json"');
  assert.notEqual(path.resolve(input),path.resolve(output),'Choose a separate output save.');
  const result=update(JSON.parse(fs.readFileSync(input,'utf8')));
  // Refuse replacement of any existing save, including a previous output.
  fs.writeFileSync(output,JSON.stringify(result,null,2),{flag:'wx'});
  console.log('Created '+output+'; original save unchanged.');
}
module.exports={update};
