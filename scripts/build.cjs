const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..');
// Build only copies known public files. Editable catalogs are never regenerated here.
const dist=path.resolve(root,'dist');
if(path.dirname(dist)!==root||path.basename(dist)!=='dist')throw Error('Build output is outside the builder directory.');
fs.rmSync(dist,{recursive:true,force:true});
fs.cpSync(path.join(root,'public'),path.join(root,'dist'),{recursive:true});
fs.cpSync(path.join(root,'src'),path.join(root,'dist'),{recursive:true});
const write=(target,source,transform=value=>value)=>{fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,transform(fs.readFileSync(source,'utf8')));};
const flatten=value=>value.replaceAll('public/','').replaceAll('src/','');
const route=value=>value.replaceAll('../public/','../').replaceAll('../src/','../').replace("assetBase:'../public'","assetBase:'..'");
write(path.join(root,'dist','index.html'),path.join(root,'index.html'),flatten);
write(path.join(root,'dist','style.css'),path.join(root,'style.css'),flatten);
write(path.join(root,'dist','landing.css'),path.join(root,'landing.css'),flatten);
for(const game of ['staw','m5'])write(path.join(root,'dist',game,'index.html'),path.join(root,game,'index.html'),route);
console.log('Static site built in dist/');
