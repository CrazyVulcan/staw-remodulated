const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),p=require('path');
const root=p.resolve(__dirname,'..'),read=f=>JSON.parse(fs.readFileSync(p.join(root,f),'utf8')),core=require('../src/core.js');
const data=read('public/data/data.json'),costs=read('public/data/card-costs.json'),routes=read('public/data/tts-routes.json'),aliases=read('public/data/aliases.json'),audit=read('public/data/id-audit.json'),maneuverCards=read('public/data/maneuver-cards.json'),rules=require('../src/rules.js');
const cards=Object.entries(data).filter(([k])=>!['sets','shipClasses'].includes(k)).flatMap(([,v])=>v).filter(c=>c.id&&c.type!=='copy'),by=Object.fromEntries(cards.map(c=>[core.key(c),c]));
test('Every converted record has a scalar, globally unique ID and one cost row',()=>{
 assert.equal(cards.length,2296);assert.equal(new Set(cards.map(c=>c.id)).size,cards.length);
 assert.equal(new Set(cards.map(core.key)).size,cards.length);assert.equal(costs.length,cards.length);
 core.validateCosts(costs,by);assert.equal(audit.mismatches.length,0);
});
test('Array IDs and duplicates have unambiguous aliases',()=>{
 assert.equal(aliases['tech:T311,T311a'],'tech:T311');assert.equal(aliases['question:Q036a'],'question:Q036');
 assert.equal(cards.filter(c=>c.id==='S199').length,1);assert.ok(by['token:rule_borg_tractor_beam']);
 assert.equal(by['token:rule_specialzation'].name,'Specialization Cards (SCS)');
});
test('Alliance-only cards without a loadable TTS route are suppressed',()=>{
 assert.equal(audit.suppressedAlliance.length,77);
 assert.equal(cards.filter(c=>c.alliance&&!routes[core.key(c)]).length,0);
 assert.equal(by['captain:AC0001'],undefined);
 assert.ok(by['crew:AP1001']);assert.ok(routes['crew:AP1001']);
});
test('Every TTS route matches its original catalog identity and a local image',()=>{
 const catalog=read('vendor/tts-catalog.json');const original=new Map(catalog.cards.map(c=>[c.id,c]));
 assert.equal(Object.keys(routes).length,2194);
 for(const [k,r]of Object.entries(routes)){assert.equal(r.id,by[k].id);assert.equal(r.type,by[k].type);assert.equal(r.name,original.get(r.id).name);assert.ok(r.index>=0&&r.index<r.width*r.height);assert.match(r.localImage,new RegExp('^cards/'+r.type+'/'));assert.ok(fs.existsSync(p.join(root,'public',r.localImage)),k);}
 const folders=fs.readdirSync(p.join(root,'public/cards'),{withFileTypes:true});
 assert.ok(folders.every(entry=>entry.isDirectory()));
 for(const folder of folders)assert.ok(fs.readdirSync(p.join(root,'public/cards',folder.name)).length<1000,folder.name);
 const archer=routes['captain:Cap039'];
 assert.equal(archer.face,'https://steamusercontent-a.akamaihd.net/ugc/5957769823492690291/F030E1F37A5E337701846EA0715FAF058205ECD3/');
 assert.equal(archer.back,'https://i.imgur.com/21bhPTi.jpg');
 assert.equal(archer.ttsCardId,316300);assert.equal(archer.width,1);assert.equal(archer.height,1);assert.equal(archer.index,0);
 assert.equal(archer.displayFallback,undefined);assert.equal(archer.assetSheet,null);
 assert.ok(fs.existsSync(p.join(root,'public',archer.localImage)));
});
test('Saved fleets normalize legacy aliases without dropping unknown IDs',()=>{
 const saved={ships:[{id:'ship:S274',upgrades:[{id:'tech:T311a'}]}]};
 const actual=core.canonicalize(saved,aliases,by);assert.equal(actual.ships[0].upgrades[0].id,'tech:T311');
 assert.throws(()=>core.canonicalize({ships:[{id:'ship:DOES_NOT_EXIST'}]},aliases,by),/Unknown/);
 assert.throws(()=>core.canonicalize({ships:[{id:'crew:C441'}]},aliases,by),/must be a ship/);
});
test('TTS text and JSON preserve groups, roles, canonical IDs, and repeated generic upgrades',()=>{
 const ship={...by['ship:S274'],captain:by['captain:Cap049'],upgrades:[{occupant:by['crew:C441']},{occupant:by['weapon:W204']},{occupant:by['weapon:W204']}]};
 const f={ships:[ship,{...by['ship:S001']}]},out=JSON.parse(core.ttsExport(f,routes,'json'));
 assert.deepEqual(out.ships[0].cards.map(c=>c.cardId),['Cap049','C441','W204','W204']);
 assert.equal(out.ships[1].shipCardId,'S001');assert.equal(out.schemaVersion,2);assert.ok(core.ttsExport(f,routes).startsWith('S274\nCap049\n'));
});
test('Face-down generated slots are tagged and exported with the TTS hidden marker',()=>{
 const quark={...by['crew:C114'],upgradeSlots:[{type:['tech','weapon'],faceDown:true,occupant:by['tech:T001']}]};
 const ship={...by['ship:S274'],upgrades:[{occupant:quark}]},fleet={ships:[ship]};
 const entries=core.walkEntries(ship);assert.equal(entries.find(e=>e.card.id==='T001').hidden,true);assert.equal(entries.find(e=>e.card.id==='C114').hidden,false);
 assert.match(core.ttsExport(fleet,routes),/\nC114\n#T001\n/);
 const payload=JSON.parse(core.ttsExport(fleet,routes,'json'));assert.equal(payload.ships[0].cards[1].hidden,true);assert.equal(payload.ships[0].cards[0].hidden,undefined);
});
test('No partial exports, unknown routing, or overflow beyond TTS layout limits',()=>{
 assert.throws(()=>core.ttsExport({ships:[by['ship:S199']]},routes),/no verified route/);
 assert.throws(()=>core.ttsExport({ships:[]},routes),/at least one/);
 const huge={...by['ship:S274'],upgrades:Array.from({length:14},()=>({occupant:by['weapon:W204']}))};
 assert.throws(()=>core.ttsExport({ships:[huge]},routes),/14-card/);
 assert.throws(()=>core.ttsExport({ships:Array.from({length:16},()=>({...by['ship:S274']}))},routes),/three rows/);
});
test('Cost validation accepts zero and rejects duplicate, negative, and unknown overrides',()=>{
 assert.equal(core.validateCosts([{id:'S274',type:'ship',cost:26,spudsCost:0}],by)[0].spudsCost,0);
 assert.throws(()=>core.validateCosts([{id:'S274',type:'ship',cost:26,spudsCost:-1}],by),/Invalid/);
 assert.throws(()=>core.validateCosts([costs[0],costs[0]],by),/Duplicate/);
});
test('Lower Decks uses a shared crew position without the Utopia helper card',()=>{
 const lower={type:'crew',id:'C414',name:'Ahni Jetal',text:'<b>(Lower Decks)</b>'},other={type:'crew',id:'C001',text:'Regular crew'},slot={type:['crew']};
 rules.enhanceEquippedCard(lower,slot);assert.equal(lower.upgradeSlots.length,1);assert.equal(lower.upgradeSlots[0]._sharedRule,'lower-decks');
 assert.equal(lower.upgradeSlots[0].canEquip({...lower}),true);assert.equal(lower.upgradeSlots[0].canEquip(other),false);
 rules.enhanceEquippedCard(lower,slot);assert.equal(lower.upgradeSlots.length,1);assert.equal(rules.isInternalHelper({type:'crew',id:'C426'}),true);assert.equal(rules.isInternalHelper({type:'question',id:'Q030'}),true);
});
test('Resource selectors stay virtual while their chosen Flagship and Fleet Captain cards export',()=>{
 const flagship=by['flagship:R004e'],captain=by['fleet-captain:R010g'];
 assert.ok(flagship);assert.ok(captain);assert.equal(routes['flagship:R004e'].objectKind,'tile');assert.equal(routes['fleet-captain:R010g'].objectKind,'tile');assert.equal(routes['flagship:R004e'].objectScale.x,1.87760186);
 const ship={...by['ship:S274'],resource:flagship,upgrades:[{occupant:captain}]};
 const fleet={ships:[ship],resource:by['resource:R004']},payload=JSON.parse(core.ttsExport(fleet,routes,'json'));
 assert.deepEqual(payload.resources,[]);assert.deepEqual(payload.ships[0].cards.map(card=>card.cardId),['R004e','R010g']);
 assert.equal(core.isVirtual(by['resource:R004']),true);assert.equal(core.isVirtual(by['resource:R010']),true);
});
test('Voyager discount helper stays hidden from TTS while its equipped card exports',()=>{
 const helper={...by['question:Q030'],upgradeSlots:[{type:['tech'],occupant:by['tech:T001']}]};
 const ship={...by['ship:S274'],upgrades:[{occupant:helper}]},payload=JSON.parse(core.ttsExport({ships:[ship]},routes,'json'));
 assert.deepEqual(payload.ships[0].cards.map(card=>card.cardId),['T001']);
});
test('Maneuver references cover every builder class with a card image or class grid',()=>{
 const classNames=new Set(data.ships.map(ship=>ship.class));
 assert.deepEqual(new Set(Object.keys(maneuverCards.classes)),classNames);
 assert.ok(Object.values(maneuverCards.classes).every(entry=>entry.maneuvers||entry.cards.length));
 assert.ok(Object.values(maneuverCards.classes).filter(entry=>entry.cards.length).length>=79);
 const galaxy=maneuverCards.classes['Galaxy Class (MU)'];
 assert.ok(galaxy.cards.some(card=>card.sourceShipId==='S108'));
 assert.ok(galaxy.cards.every(card=>/^https:\/\//.test(card.sourceFace)));
 for(const entry of Object.values(maneuverCards.classes))for(const card of entry.cards)assert.ok(fs.existsSync(p.join(root,'public',card.image)),card.image);
});
test('TTS deploy uses published card fronts, circular dials, and maneuver reference tiles',()=>{
 const lua=fs.readFileSync(p.join(root,'vendor/tts-importer-source.lua'),'utf8');
 assert.match(lua,/https:\/\/crazyvulcan\.github\.io\/staw-remodulated\/public\/cards\/resource\/resource-R028\.webp/);
 assert.match(lua,/card\.cardImage=card\.publishedFace/);
 assert.match(lua,/if not card\.dualSided then card\.cardBack=CATALOG_DATA\.genericCardBack end/);
 assert.match(lua,/"genericCardBack":"https:\/\/i\.imgur\.com\/21bhPTi\.jpg"/);
 const deployed=[...lua.matchAll(/\{target=CATALOG_DATA\["cards"\],offset=\d+,json=\[===\[(.*?)\]===\]\}/gs)].flatMap(match=>JSON.parse(match[1]));
 const deployedBy=new Map(deployed.map(card=>[card.id,card]));
 for(const route of Object.values(routes))assert.match(deployedBy.get(route.id).publishedFace,new RegExp('/public/'+route.localImage.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'$'));
 assert.equal(deployed.filter(card=>card.dualSided).length,16);
 assert.equal(deployedBy.get('R004e').dualSided,true);
 assert.equal(deployedBy.get('Cap039').dualSided,false);
 assert.match(lua,/CustomTile=\{Type=2,Thickness=0\.12/);
 assert.match(lua,/role=="reference"/);
 assert.match(lua,/https:\/\/crazyvulcan\.github\.io\/staw-remodulated\/public\/maneuvers\//);
 assert.match(lua,/target=SHIP_DATA\["ships"\]/);
 assert.match(lua,/target=SHIP_DATA\["classes"\]/);
 const physical=JSON.parse(lua.match(/SHIP_DATA = JSON\.decode\(\[===\[(.*?)\]===\]\)/s)[1]);
 for(const match of lua.matchAll(/\{target=SHIP_DATA\["(ships|classes)"\],offset=-1,json=\[===\[(.*?)\]===\]}/gs))Object.assign(physical[match[1]],JSON.parse(match[2]));
 assert.equal(Object.keys(physical.ships).length,390);assert.equal(Object.keys(physical.classes).length,82);
 assert.ok(Object.values(physical.ships).every(ship=>ship.model&&physical.classes[ship.profile]));
});
test('Bump resolution converges to base-edge contact without a clearance gap',()=>{
 const lua=fs.readFileSync(p.join(root,'vendor/tts-importer-source.lua'),'utf8');
 assert.match(lua,/math\.abs\(dx\*ux\+dz\*uz\)>=extent\(ashape,yawA,ux,uz\)\+extent\(bshape,yawB,ux,uz\) then return false/);
 assert.doesNotMatch(lua,/extent\(bshape,yawB,ux,uz\)\+0\.02 then return false/);
});
