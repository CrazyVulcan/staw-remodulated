const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),http=require('http'),p=require('path');
const root=p.resolve(__dirname,'..');
const read=file=>fs.readFileSync(p.join(root,file),'utf8');

test('Landing page links to isolated STAW and M5 builders using one shared engine',async()=>{
 const html=read('index.html'),staw=read('staw/index.html'),m5=read('m5/index.html'),css=read('style.css'),utopia=read('public/vendor/utopia.js');
 for(const file of ['index.html','landing.css','staw/index.html','m5/index.html','style.css','src/core.js','src/rules.js','src/app.js','public/css/font-staw.css','public/vendor/jquery.js','public/data/card-costs.json','public/data/m5/data.json','public/data/m5/card-costs.json','public/data/m5/tts-routes.json','public/m5/klingon/klingon-ships-v3.2.png','public/m5/klingon/klingon-deck-v3.2.png','public/m5/klingon/klingon-deck-back.png']){
  assert.ok(fs.existsSync(p.join(root,file)),file);
 }
 assert.match(read('src/app.js'),/data-maneuver/);
 assert.match(html,/href="staw\/"/);assert.match(html,/href="m5\/"/);
 assert.match(staw,/gameId:'staw'/);assert.match(m5,/gameId:'m5'/);
 assert.match(staw,/storagePrefix:'staw-remodulated'/);assert.match(m5,/storagePrefix:'m5-remodulated'/);
 assert.match(m5,/catalogBase:'data\/m5'/);assert.match(m5,/catalogFile:'data\/m5\/data\.json'/);
 assert.match(staw,/src="\.\.\/src\/app\.js"/);assert.match(m5,/src="\.\.\/src\/app\.js"/);
 assert.doesNotMatch(staw,/id="cost-editor"/);
 assert.match(utopia,/RemodulatedConfig\.catalogFile/);
 const m5Data=JSON.parse(read('public/data/m5/data.json')),m5Routes=JSON.parse(read('public/data/m5/tts-routes.json'));
 assert.equal(m5Data.ships.length,6);assert.equal(m5Data.upgrades.length,26);assert.equal(Object.keys(m5Routes).length,32);
 assert.ok(m5Data.ships.every(ship=>ship.upgrades.every(slot=>slot==='m5')));
 assert.match(css,/url\('public\/fonts\/Swiss1\.ttf'\)/);
 assert.match(css,/url\('src\/favicon\.svg'\)/);
 const server=http.createServer((req,res)=>{
  const pathname=new URL(req.url,'http://127.0.0.1').pathname;
  const rel=pathname==='/'?'index.html':pathname.replace(/^\/+/,'');
  const file=p.join(root,rel);
  if(!file.startsWith(root+p.sep)&&file!==p.join(root,'index.html')){res.writeHead(403);return res.end();}
  if(!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);return res.end();}
  res.writeHead(200);fs.createReadStream(file).pipe(res);
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const {port}=server.address();
 const fetchText=path=>new Promise((resolve,reject)=>http.get({host:'127.0.0.1',port,path},res=>{let body='';res.setEncoding('utf8');res.on('data',chunk=>body+=chunk);res.on('end',()=>res.statusCode===200?resolve(body):reject(Error(path+' -> '+res.statusCode)));}).on('error',reject));
 const fetchStatus=path=>new Promise((resolve,reject)=>http.get({host:'127.0.0.1',port,path},res=>{res.resume();res.on('end',()=>resolve(res.statusCode));}).on('error',reject));
 try{
  assert.match(await fetchText('/'),/Launch STAW builder/);
  assert.match(await fetchText('/staw/index.html'),/gameId:'staw'/);
  assert.match(await fetchText('/m5/index.html'),/gameId:'m5'/);
  for(const path of ['/landing.css','/style.css','/src/app.js','/public/data/data.json','/public/data/card-costs.json','/public/data/maneuver-cards.json','/public/data/m5/data.json','/public/data/m5/card-costs.json','/public/data/m5/tts-routes.json','/public/m5/klingon/klingon-ships-v3.2.png','/public/m5/klingon/klingon-deck-v3.2.png','/public/m5/klingon/klingon-deck-back.png','/public/cards/ship/ship-S415.webp','/public/cards/captain/captain-Cap039.webp','/public/models/contentious-effect-token.obj']){
   assert.equal(await fetchStatus(path),200,path);
  }
 }finally{
  await new Promise(resolve=>server.close(resolve));
 }
});
