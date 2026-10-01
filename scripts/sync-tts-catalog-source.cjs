const fs=require('fs'),p=require('path');
const root=p.resolve(__dirname,'..');
const catalog=JSON.parse(fs.readFileSync(p.join(root,'vendor/tts-catalog.json'),'utf8'));
const routes=JSON.parse(fs.readFileSync(p.join(root,'public/data/tts-routes.json'),'utf8'));
const data=JSON.parse(fs.readFileSync(p.join(root,'public/data/data.json'),'utf8'));
const maneuverCards=JSON.parse(fs.readFileSync(p.join(root,'public/data/maneuver-cards.json'),'utf8'));
const publicRoot='https://crazyvulcan.github.io/staw-remodulated/public/';
const target=p.join(root,'vendor/tts-importer-source.lua');
let lua=fs.readFileSync(target,'utf8');
const routeById=new Map(Object.values(routes).map(route=>[route.id,route]));
const dualSided=new Set(catalog.dualSidedCardIds||[]);
const cards=catalog.cards.map(card=>{
 const route=routeById.get(card.id);
 if(!route?.localImage)return card;
 const local=p.join(root,'public',route.localImage);
 if(!fs.existsSync(local))throw Error('Missing published card front: '+route.localImage);
 return {...card,publishedFace:publicRoot+route.localImage.replaceAll('\\','/'),dualSided:dualSided.has(card.id)};
});
const maneuverReferences={};
for(const ship of data.ships){
 const classEntry=maneuverCards.classes[ship.class],available=classEntry&&classEntry.cards||[];
 const card=available.find(candidate=>candidate.sourceShipId===ship.id)||available[0];
 if(!card)continue;
 const local=p.join(root,'public',card.image);
 if(!fs.existsSync(local))throw Error('Missing maneuver reference: '+card.image);
 maneuverReferences[ship.id]={name:card.name,image:publicRoot+card.image.replaceAll('\\','/'),back:card.back};
}
const header={...catalog,cards:[],publishedRoot:publicRoot,maneuverReferences};
lua=lua.replace(/CATALOG_DATA = JSON\.decode\(\[===\[[^\r\n]*\]===\]\)/,'CATALOG_DATA = JSON.decode([===['+JSON.stringify(header)+']===])');
const size=1100,jobs=[];
for(let offset=0;offset<cards.length;offset+=size){
 const chunk=cards.slice(offset,offset+size);
 jobs.push('{target=CATALOG_DATA["cards"],offset='+offset+',json=[===['+JSON.stringify(chunk)+']===]}');
}
const start=lua.indexOf('local startupJobs = {');
const standard=lua.indexOf('STANDARD_BASE =',start);
const end=lua.lastIndexOf('}',standard);
if(start<0||standard<0||end<start)throw Error('Could not locate startupJobs in TTS importer source.');
const physicalJobs=lua.slice(start,standard).split(/\r?\n/)
 .map(line=>line.trim().replace(/,$/,''))
 .filter(line=>line.startsWith('{target=SHIP_DATA["ships"]')||line.startsWith('{target=SHIP_DATA["classes"]'));
if(!physicalJobs.length)throw Error('Refusing to sync without the physical ship/class startup jobs.');
lua=lua.slice(0,start)+'local startupJobs = {\n'+jobs.concat(physicalJobs).join(',\n')+'\n}\n'+lua.slice(standard);
fs.writeFileSync(target,lua);
console.log('Synced '+cards.length+' TTS catalog cards and '+Object.keys(maneuverReferences).length+' ship maneuver references; preserved '+physicalJobs.length+' physical-definition chunks.');
