const fs=require('fs'),p=require('path');
const root=p.resolve(__dirname,'..'),source=p.join(root,'vendor/utopia/data');
const read=f=>JSON.parse(fs.readFileSync(p.join(root,f),'utf8'));
const write=(f,v)=>{fs.mkdirSync(p.dirname(p.join(root,f)),{recursive:true});fs.writeFileSync(p.join(root,f),JSON.stringify(v,null,2)+'\n');};
const groups=['ships','captains','admirals','ambassadors','upgrades','starship_construction','resources','others'];
const data={sets:require(p.join(source,'sets.js')),shipClasses:require(p.join(source,'ship_classes.js'))};
const tts=read('vendor/tts-catalog.json'),ttsBy=new Map(tts.cards.map(c=>[c.id,c]));
const cards=[],aliases={},merges=[],conflicts=[],suppressedAlliance=[],keys=new Map();
for(const group of groups){data[group]=[];for(const raw of require(p.join(source,group+'.js'))){
  if(raw.type==='copy'){data[group].push(raw);continue;}
  const ids=(Array.isArray(raw.id)?raw.id:[raw.id]).map(String);
  // Alliance-only duplicates are useful in the Alliance app, but cannot be
  // spawned by this mod. Keep Alliance cards that have an actual TTS route.
  if(raw.alliance===true&&!ids.some(id=>ttsBy.has(id))){suppressedAlliance.push({id:raw.id,type:raw.type,name:raw.name,reason:'Alliance-only record has no card in the supplied TTS catalog'});continue;}
  const canonical=raw.name==='Borg Tractor Beam Token (BTBT)'?'rule_borg_tractor_beam':ids.map(id=>ttsBy.get(id)?.canonicalCardId).find(Boolean)||ids.find(id=>!/[a-z]$/.test(id))||ids[0];
  const card=JSON.parse(JSON.stringify({...raw,id:canonical}));
  const key=card.type+':'+canonical;
  for(const id of ids){if(raw.name!=='Borg Tractor Beam Token (BTBT)')aliases[card.type+':'+id]=key;}
  aliases[card.type+':'+String(raw.id)]=key;
  if(keys.has(key)){
    const previous=keys.get(key);
    const comparable=c=>JSON.stringify(Object.fromEntries(Object.entries(c).filter(([k])=>!['set','image','aliases'].includes(k))));
    if(comparable(previous)!==comparable(card)){conflicts.push({key,first:previous.name,second:card.name});continue;}
    previous.set=[...new Set([...(previous.set||[]),...(card.set||[])])];
    merges.push({key,name:card.name,reason:'Equivalent card; merged expansion membership'});continue;
  }
  keys.set(key,card);data[group].push(card);cards.push(card);
}}
if(conflicts.length)throw new Error('Unresolved duplicate definitions: '+JSON.stringify(conflicts));
const routes={},missing=[],mismatches=[];
const previousRoutes=fs.existsSync(p.join(root,'public/data/tts-routes.json'))?read('public/data/tts-routes.json'):{};
const name=s=>s.toLowerCase().replace(/[^a-z0-9]/g,'');
for(const c of cards){
  const key=c.type+':'+c.id;
  const t=ttsBy.get(c.id);
  if(!t){missing.push({id:c.id,type:c.type,name:c.name,reason:'No card in supplied TTS catalog'});continue;}
  if(t.type!==c.type||name(t.name)!==name(c.name)){mismatches.push({id:c.id,utopia:{type:c.type,name:c.name},tts:{type:t.type,name:t.name}});continue;}
  const sheet=t.assetSheet?tts.assetSheets[t.assetSheet]:null;
  const face=sheet?.cardImage||t.cardImage,back=sheet?.cardBack||t.cardBack;
  if(!face||!back){missing.push({id:c.id,type:c.type,name:c.name,reason:'Missing front or back image'});continue;}
  const width=sheet?.width||t.sheet?.width||1,height=sheet?.height||t.sheet?.height||1,index=(t.sheet?.ttsCardId||0)%100;
  if(index>=width*height)throw new Error('Sheet index outside image: '+key);
  routes[key]={id:t.id,type:t.type,name:t.name,face,back,width,height,index,ttsCardId:t.sheet?.ttsCardId||null,assetSheet:t.assetSheet||null,...(t.objectKind?{objectKind:t.objectKind}:{}),...(t.objectScale?{objectScale:t.objectScale}:{})};
  const old=previousRoutes[key];if(old?.localImage&&old.face===face&&old.width===width&&old.height===height&&old.index===index){routes[key].localImage=old.localImage;routes[key].aspect=old.aspect;}
}
// Name disagreements are never silently exported. Keep evidence for human review.
const costsPath=p.join(root,'public/data/card-costs.json');
const previous=fs.existsSync(costsPath)?new Map(read('public/data/card-costs.json').map(c=>[c.type+':'+c.id,c])):new Map();
const costs=cards.map(c=>({id:c.id,name:c.name,type:c.type,cost:previous.has(c.type+':'+c.id)?previous.get(c.type+':'+c.id).cost:typeof c.cost==='number'?c.cost:null,spudsCost:previous.get(c.type+':'+c.id)?.spudsCost??null})).sort((a,b)=>a.id.localeCompare(b.id,undefined,{numeric:true}));
aliases['question:T053']='tech:T053';aliases['question:T057']='tech:T057';
write('public/data/data.json',data);write('public/data/aliases.json',aliases);write('public/data/tts-routes.json',routes);write('public/data/card-costs.json',costs);
write('public/data/reference-data.json',{rulings:require(p.join(source,'rulings.js')),missionSets:require(p.join(source,'missionSets.js')),missions:require(p.join(source,'missions.js'))});
write('public/data/id-audit.json',{sourceCommit:'478c9779ec901d2bae2a60d1aec625dcace0f148',cards:cards.length,ttsRoutes:Object.keys(routes).length,merges,mismatches,missing,suppressedAlliance,corrections:[{from:'token:rule_specialzation',to:'token:rule_borg_tractor_beam',name:'Borg Tractor Beam Token (BTBT)',reason:'Upstream assigns the same ID to two different reference cards; the specialization reference keeps its existing ID.'},{ids:['T053','T057'],reason:'Keep original tech catalog identities even when Utopia evaluates multi-slot question-card rules.'},{id:'Cap039',name:'Jonathan Archer',reason:'The supplied sheet cell contains Mr. Spock; use the recovered original one-card TTS object and its correct Jonathan Archer face.'}],aliases:Object.entries(aliases).filter(([a,b])=>a!==b)});
console.log(JSON.stringify({cards:cards.length,routes:Object.keys(routes).length,merges:merges.length,mismatches:mismatches.length,missing:missing.length,suppressedAlliance:suppressedAlliance.length}));
