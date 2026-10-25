const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const dir=path.resolve(__dirname,'../tts/staw');
const hash=value=>crypto.createHash('sha256').update(value).digest('hex');
function assemble(){
  const manifest=JSON.parse(fs.readFileSync(path.join(dir,'release.json'),'utf8'));
  const save=JSON.parse(fs.readFileSync(path.join(dir,manifest.file),'utf8'));
  save.LuaScript=manifest.globalSources.map(file=>fs.readFileSync(path.join(dir,file),'utf8')).join('\n');
  for(const [guid,file]of Object.entries(manifest.objectScripts)){
    const object=save.ObjectStates.find(object=>object.GUID===guid);assert(object,'Missing scripted object '+guid);
    object.LuaScript=fs.readFileSync(path.join(dir,file),'utf8');
  }
  const layout=structuredClone(save.ObjectStates);for(const object of layout)delete object.LuaScript;
  assert.equal(layout.length,manifest.objects);
  assert.equal(hash(JSON.stringify(layout)),manifest.layoutSHA256,'Physical table layout changed; review the release manifest before rebuilding.');
  return {manifest,save,content:JSON.stringify(save,null,2)+'\n'};
}
if(require.main===module){
  const {manifest,save,content}=assemble(),file=path.join(dir,manifest.file);
  if(process.argv.includes('--check')){
    assert.deepEqual(save,JSON.parse(fs.readFileSync(file,'utf8')),'Packaged scripts differ from their editable sources. Run npm run build:tts.');
    assert.equal(hash(fs.readFileSync(file)),manifest.sha256,'Release checksum differs from manifest.');
    console.log('STAW release matches editable sources, layout and checksum.');
  }else{
    fs.writeFileSync(file,content);manifest.sha256=hash(content);
    fs.writeFileSync(path.join(dir,'release.json'),JSON.stringify(manifest,null,2)+'\n');
    console.log('Built '+manifest.file+'; '+manifest.objects+' physical objects preserved.');
  }
}
module.exports={assemble};
