const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),p=require('path');
const root=p.resolve(__dirname,'..'),read=f=>JSON.parse(fs.readFileSync(p.join(root,f),'utf8')),core=require('../src/core.js'),sharp=require('sharp');
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
 assert.match(routes['flagship:R004i'].face,/1760312207262782202\/3ED3D22943040B54B6A96E20B77D8F7EE038F62A/);
 const flagshipFaces=new Set(Object.values(routes).filter(route=>route.type==='flagship').map(route=>route.face));
 const fleetCaptainFaces=new Set(Object.values(routes).filter(route=>route.type==='fleet-captain').map(route=>route.face));
 assert.equal([...flagshipFaces].some(face=>fleetCaptainFaces.has(face)),false);
 const importer=fs.readFileSync(p.join(root,'scripts/import-resource-cards.cjs'),'utf8');
 assert.match(importer,/const suffix=card\.type==='flagship'\?'Flagship':'Fleet Captain'/);
 assert.doesNotMatch(importer,/replace\(\/\\bfleet captain\\b\|\\bflagship\\b\/g/);
 const installer=fs.readFileSync(p.join(root,'scripts/install-alliance-framework.cjs'),'utf8');
 assert.match(installer,/Could not synchronize the TTS card catalog header/);
 assert.match(installer,/Could not synchronize the TTS card catalog batches/);
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
 assert.match(lua,/12536278486705869606\/DBCDCF7E3C34993A0355D1351AB364DCC3991A2C/);
 assert.match(lua,/DiffuseURL=reminderImage/);
 assert.match(lua,/Spawn reminder token/);
 assert.match(lua,/id="reminder"[^>]*>REMINDER TOKEN/);
 assert.ok(fs.existsSync(p.join(root,'public/models/contentious-effect-token.obj')));
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
test('Fleet imports use all six v7 staging hands and place shields beside ship cards',()=>{
 const lua=fs.readFileSync(p.join(root,'vendor/tts-importer-source.lua'),'utf8');
 assert.match(lua,/local PLAYER_COLORS=\{"Blue","Red","Green","Purple","Orange","Yellow"\}/);
 assert.match(lua,/local FLEET_STAGING_BOARD_GUID="3b5e31"/);
 for(const [color,guid] of Object.entries({Blue:'14a077',Red:'7e36ee',Green:'52a30b',Purple:'a418ef',Orange:'657947',Yellow:'7e86d6'})){
  assert.match(lua,new RegExp(`${color}="${guid}"`));
 }
 assert.match(lua,/shieldCount=tonumber\(root\.shields\) or 0/);
 assert.match(lua,/local function spawnFleetShields\(s\)/);
 assert.match(lua,/local function importedShipName\(card\)/);
 assert.match(lua,/if name:match\(" Starship\$"\) and className~="" then return className end/);
 assert.match(lua,/name=importedShipName\(root\)/);
 assert.match(lua,/STA2E\.ships\[s\.instanceId\]=s;commit\(s\);spawnFleetShields\(s\);deploy\(s\);refresh\(s\)/);
 assert.match(lua,/Fleet cards spawned; ships, dials, and maneuver references are deploying\./);
 assert.match(lua,/local target=playerSideTransform\(s\.owner,object\.getPosition\(\),\{forward=4\.8,up=0\.25\}\)/);
 assert.match(lua,/s\.spawnRotation=target\.facing or target\.rotation\[2\]/);
 assert.match(lua,/local spacing,rowSpacing=2\.45,8\.5/);
 assert.match(lua,/local rowForward=\(rowIndex-\(#layout\+1\)\/2\)\*rowSpacing/);
 assert.match(lua,/local reverseGroup=not group\.standalone/);
 assert.match(lua,/local slot=reverseGroup and \(finalSlot-j\+1\) or \(group\.start\+j-1\)/);
 assert.match(lua,/local fanDirection=reverseGroup and -1 or 1/);
 assert.doesNotMatch(lua,/local z=handPosition\.z/);
 assert.match(lua,/return board\.getPosition\(\),board\.getRotation\(\)\.y/);
 assert.match(lua,/local dialTransform=playerSideTransform\(s\.owner,p,\{side=6\.0,forward=0\.1,up=0\.3\}\)/);
 assert.match(lua,/local referenceTransform=playerSideTransform\(s\.owner,p,\{side=3\.15,up=0\.15\}\)/);
 assert.match(lua,/Nickname=s\.name\.\." Dial".*?Locked=false/s);
 assert.match(lua,/Nickname=s\.name\.\." Maneuver Reference".*?Locked=false/s);
});
test('Upgrade cards use a bottom-center command and shared action menu',()=>{
 const lua=fs.readFileSync(p.join(root,'vendor/tts-importer-source.lua'),'utf8');
 assert.match(lua,/rectAlignment="LowerCenter" offsetXY="0 28" width="720" height="355"/);
 assert.doesNotMatch(lua,/id="time_remove"/);
 assert.doesNotMatch(lua,/id="disable_remove"/);
 for(const id of ['time_add','disable_add','arcs','clear','discard','close','actions','reminder'])assert.match(lua,new RegExp(`id="${id}"`));
 assert.match(lua,/id="range_'\.\.n\.\.'"/);
 assert.match(lua,/local ALL_ACTION_CHOICES=\{"EVA","BS","TL","SCN","CLK","REG","ECHO"\}/);
 assert.match(lua,/local function actionChoices\(s\)/);
 assert.match(lua,/for _,key in ipairs\(ALL_ACTION_CHOICES\) do table\.insert\(actions,key\) end/);
 assert.match(lua,/for i,key in ipairs\(actionChoices\(s\)\) do table\.insert\(private,dialButton\("action_"/);
 assert.match(lua,/dialButton\("undo","UNDO MOVEMENT",-115,-65/);
 assert.match(lua,/id="manage_action_'\.\.key/);
 assert.match(lua,/STA2E_Command\(\{object=root,color=player\.color,command="action_"\.\.action\}\)/);
 assert.match(lua,/drawShipGuides\(s\);refresh\(s\);return/);
 assert.match(lua,/local BUILDER_CARD_ROOT="https:\/\/crazyvulcan\.github\.io\/staw-remodulated\/public\/cards\/"/);
 assert.match(lua,/local function reminderCardFace\(source,cardId\)/);
 assert.match(lua,/return BUILDER_CARD_ROOT\.\.cardType\.\."\/"\.\.cardType\.\."-"\.\.id\.\."\.webp"/);
 assert.match(lua,/local reminderImage=reminderCardFace\(source,cardId\)/);
 const reminderBlock=lua.slice(lua.indexOf('function STA2E_SpawnReminder'),lua.indexOf('\nlocal function managePanel'));
 assert.doesNotMatch(reminderBlock,/source\.cardImage/);
 assert.match(lua,/DiffuseURL=reminderImage/);
 assert.match(lua,/scaleX=0\.375,scaleY=0\.375,scaleZ=0\.375/);
 assert.match(lua,/ColliderURL=""/);
});
test('Ship token tools split adjacent and card destinations and Echo gains 3 Straight',()=>{
 const lua=fs.readFileSync(p.join(root,'vendor/tts-importer-source.lua'),'utf8');
 assert.match(lua,/local SHIP_ADJACENT_TOKENS=\{EVA=true,TL=true,BS=true,SCN=true,CLK=true,REG=true,AUX=true\}/);
 assert.match(lua,/local SHIP_ADJACENT_CHOICES=\{/);
 assert.match(lua,/local SHIP_CARD_CHOICES=\{/);
 assert.match(lua,/SHIP-ADJACENT TOKENS/);
 assert.match(lua,/SHIP CARD TOKENS/);
 assert.match(lua,/if SHIP_ADJACENT_TOKENS\[key\] then/);
 assert.match(lua,/local card=obj\(s\.cardGUID\)/);
 assert.match(lua,/s\.state\.spawnedCardTokens/);
 assert.match(lua,/target=\{p\.x\+dx,p\.y\+0\.55,p\.z\+dz\}/);
 const installer=fs.readFileSync(p.join(root,'scripts/install-alliance-framework.cjs'),'utf8');
 assert.match(installer,/id=\"STRAIGHT_3\",label=\"3 Straight\",distance=6\.15/);
});
test('Green, Orange, and Purple player bases use their supplied arc textures',()=>{
 const lua=fs.readFileSync(p.join(root,'vendor/tts-importer-source.lua'),'utf8');
 const expected={
  Green:['4815CBBA576D86F4A45E55B1DE5C7A1E94C949B4','83B21D84F0110158C051DBA41ECB56A5DBF95DA6','A2953C0EFA50C9CC338410AE4AD6C6487663B0B7','F6FCA99BBF83DAD7A6036B5C8E90C6A58D385BA6','1651475D1B387D39EE900A4C0C68744DA90670CB'],
  Orange:['B61A78BAD1BA985095AC7858FDB67ADF600D16BB','E0A930D5496F290E6B46AA4D25FF5CABAE1FE06A','71794AE6A74C9FD819D465AC6E9724E8D3008122','41996730C1203B01DDD606E42AC364A77BC90B92','2CAA703C16B6810F068E3949A01C038D0F569FBF'],
  Purple:['3DEE96BF1AC0BFC35DE0951C07FF4897BE46A9A9','BF9176017FB6AA0E01E594261AE70EA87220BB11','B08B6ABC784EEC369D104A64B7D7455DA457E3D3','2A775D6A8B9AC05F675FC72C432E041ABCDD1D09','4AEFBD2CFD91C163421B9E14CD13AA2942F155E7'],
 };
 for(const [color,hashes] of Object.entries(expected)){
  assert.match(lua,new RegExp(`${color}=\\{`));
  for(const hash of hashes)assert.match(lua,new RegExp(hash));
 }
 assert.match(lua,/if set and set\[arc\] then return set\[arc\] end/);
 assert.match(lua,/if arc=="360" then return BORG_BASE_TEXTURES\[owner\] end/);
});
test('Ship tracker rows use each seated player color',()=>{
 const lua=fs.readFileSync(p.join(root,'vendor/tts-importer-source.lua'),'utf8');
 assert.match(lua,/local TRACKER_PLAYER_COLORS=\{Blue="#[0-9A-F]+",Red="#[0-9A-F]+",Green="#[0-9A-F]+",Purple="#[0-9A-F]+",Orange="#[0-9A-F]+",Yellow="#[0-9A-F]+"\}/);
 assert.match(lua,/local TRACKER_OWNER_ORDER=\{Blue=1,Red=2,Green=3,Purple=4,Orange=5,Yellow=6\}/);
 assert.match(lua,/local function trackerBefore\(a,b\)/);
 assert.match(lua,/while j>=1 and trackerBefore\(entry,ordered\[j\]\) do/);
 assert.match(lua,/initiativeOrder=s\.owner==initiative and 1 or 0/);
 assert.doesNotMatch(lua,/table\.sort\(ships,function/);
 assert.match(lua,/local shade=s\.ai and "#5C4678" or \(TRACKER_PLAYER_COLORS\[s\.owner\] or "#48515D"\)/);
});
test('Phase button right-click returns to the previous phase',()=>{
 const lua=fs.readFileSync(p.join(root,'vendor/tts-importer-source.lua'),'utf8');
 assert.match(lua,/tooltip="Left-click: advance \| Right-click: previous phase"/);
 assert.match(lua,/function STA2E_PhaseUI\(player,value\)/);
 assert.match(lua,/local reverse=tostring\(value\)=="-2"/);
 assert.match(lua,/if g\.phase=="activation" then g\.phase="planning"/);
 assert.match(lua,/elseif g\.phase=="combat" then g\.phase="activation"/);
 assert.match(lua,/elseif g\.phase=="end" then g\.phase="combat"/);
 assert.match(lua,/if \(tonumber\(g\.round\) or 0\)>1 then g\.round=g\.round-1;g\.phase="end"/);
 assert.match(lua,/else g\.round=0;g\.phase="setup" end/);
 assert.match(lua,/oldPhaseUI\(player,value\)/);
 assert.match(lua,/phaseAdvance\(player,value\)/);
 const installer=fs.readFileSync(p.join(root,'scripts/install-alliance-framework.cjs'),'utf8');
 assert.match(installer,/return aiOldPhase\(player,value\)/);
});
test('Global startup leaves a client sync window and uses small catalog batches',()=>{
 const lua=fs.readFileSync(p.join(root,'vendor/tts-importer-source.lua'),'utf8');
 assert.match(lua,/local last=math\.min\(cardIndex\+39,#cards\)/);
 assert.match(lua,/Wait\.time\(step,6\)/);
 assert.doesNotMatch(lua,/cardIndex\+149/);
 assert.doesNotMatch(lua,/Wait\.frames\(step,10\)/);
});
test('Alliance missions use the supplied start token and reusable ship-card catalog',()=>{
 const lua=fs.readFileSync(p.join(root,'vendor/tts-importer-source.lua'),'utf8');
 const chip=fs.readFileSync(p.join(root,'vendor/alliance-a1m1-chip.lua'),'utf8');
 const installer=fs.readFileSync(p.join(root,'scripts/install-alliance-framework.cjs'),'utf8');
 const catalog=JSON.parse(fs.readFileSync(p.join(root,'vendor/alliance-ship-cards.json'),'utf8'));
 assert.equal(Object.keys(catalog.cards).length,32);
 assert.equal(new Set(Object.values(catalog.cards).map(card=>card.className)).size,5);
 assert.ok(Object.values(catalog.cards).every(card=>/^https:\/\//.test(card.classImage)&&/^https:\/\//.test(card.profileImage)));
 const embedded=JSON.parse(lua.match(/local ALLIANCE_SHIP_CARD_DATA=JSON\.decode\(\[===\[(.*?)\]===\]\)/s)[1]);
 assert.deepEqual(embedded,catalog);
 assert.equal(catalog.sheet.face,'https://steamusercontent-a.akamaihd.net/ugc/12941386263067143059/558C4A1E301B9AA11C5119D7B8B0462FE943C635/');
 assert.equal(catalog.sheet.back,'https://steamusercontent-a.akamaihd.net/ugc/12020036739026850548/1952CEDF8FBF6FAE69330AE3D62030A0CE562749/');
 assert.match(lua,/local function allianceDrawShipCard\(state,className,fallbackId\)/);
 assert.match(lua,/local cardAsset,cardId=allianceDrawShipCard\(state,className,profile\.cardId\)/);
 assert.match(lua,/CardID=deckId\*100\+sheetIndex/);
 assert.match(lua,/NumWidth=sheetWidth,NumHeight=sheetHeight/);
 assert.match(lua,/UniqueBack=sheet\.uniqueBack~=false/);
 assert.match(lua,/local isAdvanced=spec\.profile=="advanced" or profile\.advanced==true/);
 assert.match(lua,/if not isAdvanced then card\.flip\(\) end/);
 assert.match(lua,/allianceCardFaceDown=not isAdvanced/);
 assert.match(lua,/for _,z in ipairs\(\{-12\.5,4\.0,20\.5\}\) do/);
 assert.match(lua,/for _,x in ipairs\(\{23\.0,30\.5,38\.0,45\.5\}\) do/);
 assert.match(chip,/generic=\{cardId="285600"/);
 assert.match(chip,/advanced=\{cardId="325000"/);
 assert.equal((chip.match(/scale=0\.25/g)||[]).length,2);
 assert.match(chip,/label="2 PLAYERS"/);
 assert.match(chip,/width=820,height=300,font_size=135/);
 const token='https://steamusercontent-a.akamaihd.net/ugc/15124136587514081326/767C98EB6EB818EEFE4DB2043199556D1CFD5A01/';
 assert.ok(chip.includes(token));assert.ok(installer.includes(token));
});
test('Alliance ship cards are packed into full-card 10x7 TTS sheets',async()=>{
 const catalog=read('vendor/alliance-ship-cards.json');
 assert.deepEqual([catalog.sheet.width,catalog.sheet.height],[10,7]);
 assert.equal(catalog.sheet.uniqueBack,true);
 assert.deepEqual(Object.values(catalog.cards).map(card=>card.sheetIndex).sort((a,b)=>a-b),Array.from({length:32},(_,index)=>index));
 for(const file of ['public/cards/alliance/alliance-ship-cards.webp','public/cards/alliance/alliance-ship-backs.webp']){
  assert.ok(fs.existsSync(p.join(root,file)),file);
  const metadata=await sharp(p.join(root,file)).metadata();
  assert.deepEqual([metadata.width,metadata.height,metadata.format],[4000,3920,'webp']);
 }
});
