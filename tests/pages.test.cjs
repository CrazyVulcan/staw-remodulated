const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),http=require('http'),p=require('path');
const root=p.resolve(__dirname,'..');
const read=file=>fs.readFileSync(p.join(root,file),'utf8');

test('Root GitHub Pages entry point uses existing app with public asset paths',async()=>{
 const html=read('index.html'),css=read('style.css'),utopia=read('public/vendor/utopia.js');
 for(const file of ['index.html','style.css','src/core.js','src/rules.js','src/app.js','public/css/font-staw.css','public/vendor/jquery.js','public/data/card-costs.json']){
  assert.ok(fs.existsSync(p.join(root,file)),file);
 }
 assert.match(read('src/app.js'),/data-maneuver/);
 assert.match(html,/window\.RemodulatedConfig=\{assetBase:'public'\}/);
 assert.match(html,/data-asset-path="data\/card-costs\.json"/);
 assert.match(html,/href="public\/css\/font-staw\.css"/);
 assert.match(html,/src="src\/app\.js"/);
 assert.doesNotMatch(html,/id="cost-editor"/);
 assert.match(utopia,/remodulatedAssetPath\("data\/data\.json"\)/);
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
  assert.match(await fetchText('/'),/public\/css\/font-staw\.css/);
  for(const path of ['/style.css','/src/app.js','/public/data/data.json','/public/data/card-costs.json','/public/data/maneuver-cards.json','/public/cards/ship/ship-S415.webp','/public/cards/captain/captain-Cap039.webp']){
   assert.equal(await fetchStatus(path),200,path);
  }
 }finally{
  await new Promise(resolve=>server.close(resolve));
 }
});
