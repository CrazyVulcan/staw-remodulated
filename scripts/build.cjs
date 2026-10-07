const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..');
const m5=fs.readFileSync(path.join(root,'src/m5.html'),'utf8');
fs.writeFileSync(path.join(root,'m5.html'),m5.replace('href="m5.css"','href="src/m5.css"').replace("assetBase:''","assetBase:'public'").replace('src="m5-core.js"','src="src/m5-core.js"').replace('src="m5-app.js"','src="src/m5-app.js"'));
// Build only copies known public files. Editable catalogs are never regenerated here.
fs.rmSync(path.join(root,'dist'),{recursive:true,force:true});
fs.cpSync(path.join(root,'public'),path.join(root,'dist'),{recursive:true});
fs.cpSync(path.join(root,'src'),path.join(root,'dist'),{recursive:true});
console.log('Static site built in dist/');
