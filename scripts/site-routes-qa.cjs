// Exercise the generated site under a Pages-style repository URL prefix.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {chromium}=require('playwright'),root=path.resolve(__dirname,'../dist'),prefix='/preview/';
const types={'.html':'text/html','.js':'text/javascript','.json':'application/json','.css':'text/css','.svg':'image/svg+xml','.webp':'image/webp','.png':'image/png','.ttf':'font/ttf'};
(async()=>{
  const server=http.createServer((req,res)=>{
    const url=new URL(req.url,'http://localhost');
    if(!url.pathname.startsWith(prefix)){res.writeHead(404);return res.end();}
    let rel=decodeURIComponent(url.pathname.slice(prefix.length));if(!rel||rel.endsWith('/'))rel+='index.html';
    const file=path.resolve(root,rel);
    if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);return res.end();}
    res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream'});fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  let browser;
  try{
    browser=await chromium.launch({channel:process.env.STAW_BROWSER_CHANNEL||'msedge',headless:true});
    const page=await browser.newPage(),errors=[];
    page.on('pageerror',error=>errors.push(error.message));
    page.on('response',response=>{if(response.status()>=400)errors.push(response.status()+' '+response.url());});
    const base='http://127.0.0.1:'+server.address().port+prefix;
    await page.goto(base);await page.getByRole('link',{name:'Launch STAW builder'}).click();
    await page.waitForFunction(()=>!!window.STAW);
    await page.getByRole('link',{name:'M5 tracker fleets'}).click();
    await page.waitForFunction(()=>document.getElementById('m5-total').textContent.includes('Threat'));
    await page.locator('#m5-add').click();await page.locator('#m5-export').click();
    assert.equal(JSON.parse(await page.locator('#m5-json').inputValue()).source.kind,'remodulated-m5');
    await page.locator('#m5-close').click();await page.getByRole('link',{name:'Klingon V3.2 references'}).click();
    await page.waitForFunction(()=>!!window.M5);
    assert.equal(await page.evaluate(()=>M5.cards.length),32);assert(await page.locator('#export').isDisabled());
    await page.setViewportSize({width:390,height:844});
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'reference page mobile overflow');
    await page.goto(base);await page.getByRole('link',{name:'Launch M5 tracker builder'}).click();
    await page.waitForFunction(()=>document.getElementById('m5-total').textContent.includes('Threat'));
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'tracker mobile overflow');
    assert.deepEqual(errors,[]);
    console.log('Built site passed: landing → STAW → M5 tracker → card references, valid export, asset paths, repository prefix and mobile widths.');
  }finally{if(browser)await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
