const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..');
const types={'.html':'text/html','.js':'text/javascript','.css':'text/css','.json':'application/json'};
(async()=>{
  const server=http.createServer((req,res)=>{
    const rel=new URL(req.url,'http://localhost').pathname.slice(1)||'index.html';const file=path.resolve(root,rel);
    if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}
    res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream'});fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  let browser;
  try{
    browser=await chromium.launch({channel:'msedge',headless:true});
    const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    await page.goto('http://127.0.0.1:'+server.address().port+'/m5.html');
    await page.waitForFunction(()=>document.getElementById('m5-total').textContent.includes('Threat'));
    await page.locator('#m5-add').click();
    await page.locator('[data-program="focused_barrage"]').check();
    await page.locator('[data-program="hunters_algorithm"]').check();
    assert.match(await page.locator('.m5-ship').textContent(),/CS 5/);
    assert.match(await page.locator('#m5-total').textContent(),/10 \/ 30/);
    await page.locator('#m5-export').click();
    const exported=await page.locator('#m5-json').inputValue();const payload=JSON.parse(exported);
    assert.equal(payload.ships[0].shipCardId,'M5S001');assert.equal(payload.ships[0].cards.length,2);
    await page.locator('#m5-close').click();
    await page.reload();await page.waitForSelector('.m5-ship');assert.match(await page.locator('.m5-ship').textContent(),/CS 5/);
    await page.locator('#m5-import').click();await page.locator('#m5-json').fill(exported.replace('M5S001','M5S999'));await page.locator('#m5-apply').click();
    assert.match(await page.locator('#m5-dialog-status').textContent(),/Unknown M5 ship/);
    await page.locator('#m5-close').click();assert.equal(await page.locator('.m5-ship').count(),1);
    await page.locator('#m5-add').click();await page.locator('#m5-add').click();assert.equal(await page.locator('#m5-add').isDisabled(),true);
    await page.locator('[data-remove="2"]').click();assert.equal(await page.locator('.m5-ship').count(),2);
    fs.mkdirSync(path.join(root,'test-results'),{recursive:true});
    await page.evaluate(()=>window.scrollTo(0,0));
    await page.screenshot({path:path.join(root,'test-results/m5-desktop.png'),fullPage:true});
    await page.setViewportSize({width:390,height:844});
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'mobile overflow');
    await page.screenshot({path:path.join(root,'test-results/m5-mobile.png'),fullPage:true});
    assert.deepEqual(errors,[]);
    console.log('M5 browser QA passed: build, signed CS, export, persistence, invalid import rollback, multiple hulls, mobile layout.');
  }finally{if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
