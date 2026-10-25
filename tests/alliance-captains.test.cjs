const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),p=require('path');
const root=p.resolve(__dirname,'..'),core=require('../src/core.js');
const rules=require('../src/rules.js');
const read=name=>JSON.parse(fs.readFileSync(p.join(root,name),'utf8'));
test('Captain XP state stays bounded, derives skill, and remains separate from fleet cost',()=>{
 const state=core.captainProgress({version:2,name:"Captain T'Pol",Elite:6,Skill:14,Crew:10,Weapon:10,Tech:10,ExpansionOne:'Crew',ExpansionTwo:'Tech'});
 assert.deepEqual(core.captainSummary(state),{xp:50,skill:9});
 assert.deepEqual(core.captainSummary(),{xp:0,skill:2});
 for(const edit of [s=>s.Skill=15,s=>s.Elite=-1,s=>s.Crew=1.5,s=>s.Tech='3',s=>s.version=3,s=>s.ExpansionOne='Borg',s=>s.name='x'.repeat(101)]){
  const invalid={...state};edit(invalid);assert.throws(()=>core.captainProgress(invalid));
 }
 const data=read('public/data/data.json'),routes=read('public/data/tts-routes.json');
 const captain={...data.captains.find(c=>c.id==='AC0001'),allianceCaptain:state};
 const live={ships:[{...data.ships.find(s=>s.id==='S274'),captain}]};
 const saved=core.withCaptainProgress(live,{ships:[{id:'ship:S274',captain:{id:'captain:AC0001'}}]});
 const by=Object.fromEntries([live.ships[0],captain].map(card=>[core.key(card),card]));
 assert.deepEqual(core.canonicalize(saved,{},by).ships[0].captain.allianceCaptain,state);
 assert.deepEqual(JSON.parse(core.ttsExport(live,routes,'json')).ships[0].cards[0].allianceCaptain,state);
 assert.equal(captain.cost,0);assert.equal(live.ships[0].cost,26);
 assert.match(core.ttsExport(live,routes),/^S274\nAC0001\n/);
 const bad={ships:[{id:'ship:S274',allianceCaptain:state}]};assert.throws(()=>core.canonicalize(bad,{},by),/requires an Alliance captain/);
});
test('Federation, Klingon, and Romulan Alliance captains export exact interactive object IDs',()=>{
 const data=read('public/data/data.json'),routes=read('public/data/tts-routes.json'),catalog=read('vendor/tts-catalog.json');
 const ships=data.ships,objects=read('vendor/alliance-captain-objects.json');
 for(const [id,faction]of [['AC0001','federation'],['AC0009','klingon'],['AC0017','romulan']]){
  const card=data.captains.find(card=>card.id===id),route=routes['captain:'+id],original=catalog.cards.find(card=>card.id===id);
  assert.equal(card.type,'captain');assert.equal(card.interactiveCaptain,true);assert.deepEqual(card.factions,[faction]);assert.equal(card.cost,0);assert.equal(card.skill,2);assert.equal(card.unique,false);
  assert.equal(card.talents,3);assert.deepEqual(card.additionalUpgradeSlots,[{type:['tech','weapon','crew']},{type:['tech','weapon','crew']}]);
  assert.equal(route.objectKind,'alliance-captain');assert.ok(route.aspect>1.5&&route.aspect<1.7);assert.ok(fs.existsSync(p.join(root,'public',route.localImage)));
  assert.equal(objects[id].Name,'Custom_Tile');assert.equal(objects[id].CustomImage.ImageURL,original.cardImage);assert.match(objects[id].LuaScript,/STA2E_CaptainSnapshot/);assert.match(objects[id].XmlUI,/onEndEdit="nameUpdate"/);
  const fleet={ships:[{...ships.find(ship=>ship.id==='S274'),captain:card}]};
  const exported=JSON.parse(core.ttsExport(fleet,routes,'json'));assert.equal(exported.ships[0].cards[0].cardId,id);assert.match(core.ttsExport(fleet,routes),new RegExp('\n'+id+'\n'));
 }
});

test('Alliance flexible slots append after the Talent slots and retain independent occupants',()=>{
 const data=read('public/data/data.json');
 for(const definition of data.captains.filter(card=>card.interactiveCaptain)){
  const captain={...definition,upgradeSlots:Array.from({length:definition.talents},()=>({type:['talent']}))};
  const existing={id:'AP1006',type:'talent'};captain.upgradeSlots[0].occupant=existing;
  rules.applyCatalogSlots(captain);rules.applyCatalogSlots(captain);
  assert.equal(captain.upgradeSlots.length,5);assert.equal(captain.upgradeSlots[0].occupant,existing);
  assert.deepEqual(captain.upgradeSlots.map(slot=>slot.type),[['talent'],['talent'],['talent'],['tech','weapon','crew'],['tech','weapon','crew']]);
  captain.upgradeSlots[3].occupant={id:'AP1014',type:'tech'};
  assert.equal(captain.upgradeSlots[4].occupant,undefined);assert.notEqual(captain.upgradeSlots[3].type,captain.upgradeSlots[4].type);
 }
});

test('Legacy Alliance AP upgrades retain exact TTS routes, including AP1014',()=>{
 const data=read('public/data/data.json'),routes=read('public/data/tts-routes.json'),catalog=read('vendor/tts-catalog.json');
 const upgrades=data.upgrades.filter(card=>/^AP\d+$/.test(card.id));assert.ok(upgrades.length>=26);
 for(const card of upgrades){
  const route=routes[core.key(card)],original=catalog.cards.find(entry=>entry.id===card.id);
  assert.ok(route,card.id+' is missing its TTS route');assert.equal(route.type,card.type);assert.equal(route.name,card.name);
  assert.equal(route.index,original.sheet.ttsCardId%100);assert.ok(route.face);assert.ok(route.back);
  const fleet={ships:[{...data.ships.find(ship=>ship.id==='S274'),captain:{...data.captains.find(captain=>captain.id==='AC0001'),upgradeSlots:[{type:[card.type],occupant:card}]}}]};
  assert.equal(JSON.parse(core.ttsExport(fleet,routes,'json')).ships[0].cards[1].cardId,card.id);
 }
 assert.equal(routes['tech:AP1014'].name,'Reinforced Shielding');assert.equal(routes['tech:AP1014'].index,19);
});

test('Previously saved cost profiles gain the three captain defaults without losing overrides',()=>{
 const data=read('public/data/data.json'),current=read('public/data/card-costs.json');
 const by=Object.fromEntries(Object.entries(data).filter(([key])=>!['sets','shipClasses'].includes(key)).flatMap(([,group])=>group).filter(card=>card.id).map(card=>[core.key(card),card]));
 const old=current.filter(row=>!['AC0001','AC0009','AC0017'].includes(row.id)).map(row=>({...row}));
 old.find(row=>row.id==='S274').spudsCost=17;
 const merged=core.migrateCosts(old,current,by);
 assert.equal(merged.length,current.length);assert.equal(merged.find(row=>row.id==='S274').spudsCost,17);
 for(const id of ['AC0001','AC0009','AC0017'])assert.equal(merged.find(row=>row.id===id).cost,0);
 assert.throws(()=>core.migrateCosts(old.filter(row=>row.id!=='S274'),current,by),/incomplete/);
 assert.throws(()=>core.migrateCosts([...old,{id:'UNKNOWN',type:'captain',cost:0,spudsCost:null}],current,by),/Unknown/);
});
