const assert=require('node:assert/strict'),path=require('node:path'),fs=require('node:fs');
const {chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({channel:process.env.STAW_BROWSER_CHANNEL||'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  await page.goto(process.env.STAW_QA_URL||'http://127.0.0.1:4173/staw/');await page.waitForFunction(()=>!!window.STAW);
  const options=await page.locator('#set option').allTextContents();assert.equal(options.filter(s=>s==='Alliance').length,1);assert(!options.some(s=>/^Part (I|II|III)$/.test(s)));
  await page.selectOption('#set','alliance');
  for(const [type,name,id]of [['crew','Commander','C362'],['crew','Engineering Officer','C391'],['tech','Reinforced Shielding','T253']]){
   await page.selectOption('#type',type);await page.locator('#search').fill(name);
   assert.equal(await page.locator('[data-add="'+type+':'+id+'"]').count(),1);
   assert.equal(await page.locator('.catalog-entry [data-add*="AP"]').count(),0,'Duplicate AP row is still visible');
  }
  await page.evaluate(()=>STAW.loadText('S274\nAC0001\nAP1005'));
  const legacy=await page.evaluate(()=>JSON.stringify(STAW.saveObject()));
  await page.evaluate(saved=>STAW.loadText(saved),legacy);
  assert.equal(await page.evaluate(()=>STAW.exportFleet('text').includes('\nAP1005\n')),true,'Legacy AP ID was changed');
  assert.equal(await page.locator('.fleet-card code').filter({hasText:'AP1005'}).count(),1,'Legacy AP card is missing from its fleet');
  for(const set of ['80000','80001','80002','80003']){
   const card=await page.evaluate(set=>STAW.cards.find(c=>(c.set||[]).includes(set)&&c.type==='ship')?.id||STAW.cards.find(c=>(c.set||[]).includes(set))?.id,set);
   assert(card,'Alliance source '+set+' has no cards');await page.selectOption('#type','');await page.locator('#search').fill(card);assert(await page.locator('.catalog-entry').count()>0,'Alliance filter omitted '+set);
  }
  await page.locator('#search').fill('');
  for(const id of ['AC0001','AC0009','AC0017']){
   await page.evaluate(id=>STAW.loadText('S274\n'+id),id);
   const originalCost=await page.locator('#total').textContent();
   assert.equal(await page.locator('.captain-tracker').count(),1);
   await page.getByLabel('Captain name for ship 1',{exact:true}).fill("Captain T'Pol & <Test>");await page.getByLabel('Captain name for ship 1',{exact:true}).press('Tab');
   await page.locator('#captain-0-Skill').fill('8');await page.locator('#captain-0-Skill').press('Tab');
   await page.getByRole('button',{name:'Increase Talent XP for ship 1',exact:true}).click();
   await page.getByRole('button',{name:'Increase Crew XP for ship 1',exact:true}).click();
   await page.getByLabel('Expansion slot 1 for ship 1',{exact:true}).selectOption('Crew');
   await page.getByLabel('Expansion slot 2 for ship 1',{exact:true}).selectOption('Tech');
   assert.match(await page.locator('.captain-summary').textContent(),/10 XP spent.*Captain Skill 6/);assert.equal(await page.locator('#total').textContent(),originalCost);
   assert.equal(await page.evaluate(()=>STAW.fleet.ships[0].captain.skill),6);
   const saved=await page.evaluate(()=>JSON.stringify(STAW.saveObject())),json=await page.evaluate(()=>STAW.exportFleet('json'));
   assert.equal(JSON.parse(json).ships[0].cards[0].allianceCaptain.name,"Captain T'Pol & <Test>");
   await page.evaluate(saved=>STAW.loadText(saved),saved);assert.equal(await page.evaluate(()=>JSON.stringify(STAW.saveObject())),saved);
   await page.reload();await page.waitForFunction(()=>!!window.STAW);assert.equal(await page.evaluate(()=>STAW.exportFleet('json')),json);
   await page.selectOption('#point-mode','spuds');assert.equal(await page.evaluate(()=>STAW.exportFleet('json')),json);
   await page.locator('#export').click();assert.equal(await page.locator('#export-text').inputValue(),json);assert.match(await page.locator('#export-ids').textContent(),/no XP/);await page.locator('#close-modal').click();
   await page.evaluate(json=>STAW.loadText(json),json);assert.equal(await page.evaluate(()=>STAW.exportFleet('json')),json);
   await page.evaluate(()=>{const before=JSON.stringify(STAW.saveObject());const bad=JSON.parse(STAW.exportFleet('json'));bad.ships[0].cards[0].allianceCaptain.Skill=100;let failed=false;try{STAW.loadText(JSON.stringify(bad));}catch{failed=true;}if(!failed||JSON.stringify(STAW.saveObject())!==before)throw Error('Invalid import changed the fleet');try{STAW.loadText('S274\nUNKNOWN')}catch{}if(JSON.stringify(STAW.saveObject())!==before)throw Error('Failed ID import lost XP');});
   await page.locator('#captain-0-Elite').fill('6');await page.locator('#captain-0-Elite').press('Tab');assert(await page.getByRole('button',{name:'Increase Talent XP for ship 1',exact:true}).isDisabled());
  }
  // Multiple copies keep distinct progress even after ship ordering changes.
  await page.evaluate(()=>{const a=JSON.parse(STAW.exportFleet('json'));a.ships[0].shipCardId='S273';a.ships.push(structuredClone(a.ships[0]));a.ships[1].cards[0].allianceCaptain.name='Second Captain';a.ships[1].cards[0].allianceCaptain.Skill=2;STAW.loadText(JSON.stringify(a));});
  await page.locator('[data-move="1"][data-dir="-1"]').click();
  assert.equal(await page.getByLabel('Captain name for ship 1',{exact:true}).inputValue(),'Second Captain');assert.equal(await page.locator('#captain-0-Skill').inputValue(),'2');
  await page.locator('[data-remove-ship="1"]').click();
  const out=path.resolve(__dirname,'../test-results');fs.mkdirSync(out,{recursive:true});
  await page.locator('.captain-tracker').scrollIntoViewIfNeeded();await page.screenshot({path:path.join(out,'captain-tracker-desktop.png')});
  await page.setViewportSize({width:390,height:844});await page.locator('.captain-tracker').scrollIntoViewIfNeeded();assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:path.join(out,'captain-tracker-mobile.png')});
  await page.evaluate(()=>STAW.loadText('S274\nCap049'));assert.equal(await page.locator('.captain-tracker').count(),0);
  assert.deepEqual(errors,[]);
  console.log('Captain trackers passed: all factions, XP/skill, bounds, names, slots, save/reload, JSON round-trip, rollback, duplicate captains, ship ordering and mobile layout; one Alliance expansion.');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
