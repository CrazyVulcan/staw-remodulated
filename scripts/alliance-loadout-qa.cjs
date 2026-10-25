const assert=require('node:assert/strict'),fs=require('fs'),p=require('path');
const {chromium}=require('playwright');
(async()=>{
 const out=process.env.STAW_QA_OUTPUT||p.resolve(__dirname,'../../output/alliance-loadouts-2026-10-13');fs.mkdirSync(out,{recursive:true});
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[],fixtures=[];
  page.on('pageerror',error=>errors.push(error.message));
  await page.goto('http://127.0.0.1:4173/staw/');await page.waitForFunction(()=>!!window.STAW);
  for(const id of ['AC0001','AC0009','AC0017']){
   await page.evaluate(id=>STAW.loadText('S274\n'+id),id);
   assert.deepEqual(await page.evaluate(()=>STAW.fleet.ships[0].captain.upgradeSlots.map(slot=>slot.type)),[['talent'],['talent'],['talent'],['tech','weapon','crew'],['tech','weapon','crew']]);
   // Use the visible slot controls, including compatibility filtering in the library.
   await page.selectOption('#faction','');await page.selectOption('#set','');
   for(const [index,card]of [[0,'talent:AP1007'],[1,'talent:AP1008'],[2,'talent:AP1010'],[3,'tech:AP1011'],[4,'weapon:AP1018']]){
    await page.locator('[data-slot="'+index+'"]').click();await page.locator('#search').fill(card.split(':')[1]);
    await page.locator('[data-add="'+card+'"]').click();
    assert.equal(await page.evaluate(index=>STAW.fleet.ships[0].captain.upgradeSlots[index].occupant?.id,index),card.split(':')[1]);
   }
   assert.equal(await page.evaluate(()=>STAW.equip('talent:AP1006')),false,'A fourth Talent must not fit');
   const saved=await page.evaluate(()=>JSON.stringify(STAW.saveObject())),text=await page.evaluate(()=>STAW.exportFleet('text')),json=await page.evaluate(()=>STAW.exportFleet('json'));
   assert.deepEqual(JSON.parse(json).ships[0].cards.map(card=>card.cardId),[id,'AP1007','AP1008','AP1010','AP1011','AP1018']);
   await page.evaluate(saved=>STAW.loadText(saved),saved);assert.equal(await page.evaluate(()=>JSON.stringify(STAW.saveObject())),saved);
   await page.reload();await page.waitForFunction(()=>!!window.STAW);assert.equal(await page.evaluate(()=>STAW.exportFleet('text')),text);
   await page.evaluate(()=>STAW.changePointMode('spuds'));assert.equal(await page.evaluate(()=>STAW.exportFleet('text')),text);
   await page.evaluate(()=>STAW.changePointMode('standard'));
   fixtures.push({name:id+' full loadout',text,json});
  }
  // All six type combinations are legal in the two captain slots.
  const options={tech:['AP1011','AP1012'],weapon:['AP1018','AP1024'],crew:['C441','C005']};
  for(const id of ['AC0001','AC0009','AC0017'])for(const pair of [['tech','tech'],['weapon','weapon'],['crew','crew'],['tech','weapon'],['tech','crew'],['weapon','crew']]){
   await page.evaluate(id=>STAW.loadText('S274\n'+id),id);
   for(const [offset,type]of pair.entries()){
    const card=options[type][offset];await page.locator('[data-slot="'+(3+offset)+'"]').click();await page.locator('#search').fill(card);
    await page.locator('[data-add="'+type+':'+card+'"]').click();
    assert.equal(await page.evaluate(index=>STAW.fleet.ships[0].captain.upgradeSlots[index].occupant?.id,3+offset),card);
   }
   const saved=await page.evaluate(()=>JSON.stringify(STAW.saveObject()));await page.evaluate(saved=>STAW.loadText(saved),saved);
   assert.deepEqual(await page.evaluate(()=>STAW.fleet.ships[0].captain.upgradeSlots.slice(3).map(slot=>slot.occupant.type)),pair);
  }
  await page.evaluate(()=>STAW.loadText('S274\nAC0001'));
  await page.locator('[data-slot="3"]').click();await page.locator('#search').fill('AP1014');
  await page.locator('[data-add="tech:AP1014"]').click();
  assert.equal(await page.evaluate(()=>STAW.fleet.ships[0].captain.upgradeSlots[3].occupant.id),'AP1014');
  assert.equal(await page.evaluate(()=>STAW.equip('tech:AP1014')),false,'One-per-ship still applies');
  const saved=await page.evaluate(()=>JSON.stringify(STAW.saveObject()));await page.evaluate(saved=>STAW.loadText(saved),saved);
  await page.locator('#export').click();assert.match(await page.locator('#export-text').inputValue(),/\nAP1014\n/);await page.locator('#close-modal').click();
  fixtures.push({name:'AP1014 captain slot',text:await page.evaluate(()=>STAW.exportFleet('text')),json:await page.evaluate(()=>STAW.exportFleet('json'))});
  // A previously saved single Talent retains slot 0 when the new slots become available.
  await page.evaluate(()=>STAW.loadText(JSON.stringify({ships:[{id:'ship:S274',captain:{id:'captain:AC0001',upgradeSlots:[{id:'talent:AP1007'}]}}]})));
  assert.equal(await page.evaluate(()=>STAW.fleet.ships[0].captain.upgradeSlots[0].occupant.id),'AP1007');
  assert.equal(await page.evaluate(()=>STAW.fleet.ships[0].captain.upgradeSlots.length),5);
  await page.evaluate(()=>STAW.loadText('S274\nAC0001'));await page.selectOption('#type','tech');await page.locator('#search').fill('AP1014');
  await page.screenshot({path:p.join(out,'captain-slots-desktop.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  await page.screenshot({path:p.join(out,'captain-slots-mobile.png'),fullPage:true});
  fs.writeFileSync(p.join(out,'fleet-fixtures.json'),JSON.stringify(fixtures,null,2)+'\n');assert.deepEqual(errors,[]);
  console.log('Alliance loadouts passed: all three captains, 3 Talents, 18 flexible-slot combinations, AP1014, slot limits, persistence, old saves, point modes, exports, and mobile layout.');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
