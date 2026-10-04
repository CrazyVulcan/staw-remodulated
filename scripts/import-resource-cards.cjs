const fs=require('fs'),p=require('path');

const root=p.resolve(__dirname,'..'),savePath=process.argv[2];
if(!savePath)throw Error('Usage: node scripts/import-resource-cards.cjs "path-to-legacy-save.json"');

const save=JSON.parse(fs.readFileSync(savePath,'utf8'));
const data=JSON.parse(fs.readFileSync(p.join(root,'public/data/data.json'),'utf8'));
const catalogPath=p.join(root,'vendor/tts-catalog.json');
const catalog=JSON.parse(fs.readFileSync(catalogPath,'utf8'));
const wanted=[...data.resources,...data.others.filter(card=>card.type==='flagship'||card.type==='fleet-captain')];
const objects=[];

function walk(value){
 if(!value||typeof value!=='object')return;
 if(value.Name)objects.push(value);
 for(const field of ['ObjectStates','ContainedObjects'])for(const child of value[field]||[])walk(child);
 if(value.States)for(const child of Object.values(value.States))walk(child);
}
walk(save);

const normalize=value=>String(value||'').toLowerCase().replace(/[^a-z0-9]/g,'');
function sourceFor(card){
 const exact=objects.filter(object=>String(object.Description||'').trim()===card.id);
 if(card.type==='resource')return exact.find(object=>object.CardID&&object.CustomDeck)||null;
 const tiles=objects.filter(object=>object.Name==='Custom_Tile'&&object.CustomImage);
 const suffix=card.type==='flagship'?'Flagship':'Fleet Captain';
 const expectedName=normalize(card.name+' '+suffix);
 return tiles.find(object=>normalize(object.Nickname)===expectedName)||exact.find(object=>object.Name==='Custom_Tile')||null;
}

const assetUrl=value=>String(value||'').replace(/^http:/,'https:').replace('https://cloud-3.steamusercontent.com/','https://steamusercontent-a.akamaihd.net/');

const imported=[],missing=[];
for(const card of wanted){
 // These two records select an attached physical card; they are not spawned.
 if(card.type==='resource'&&(card.id==='R004'||card.id==='R010'))continue;
 const object=sourceFor(card);
 if(!object){missing.push({type:card.type,id:card.id,name:card.name});continue;}
 const record={type:card.type,id:card.id,name:card.name,cost:card.cost};
 if(object.CardID&&object.CustomDeck){
  const [deckKey,deck]=Object.entries(object.CustomDeck)[0];
  const assetKey='legacy-resource-'+deckKey;
  catalog.assetSheets[assetKey]={cardImage:assetUrl(deck.FaceURL),cardBack:assetUrl(deck.BackURL),width:deck.NumWidth,height:deck.NumHeight,uniqueBack:deck.UniqueBack===true};
  record.sheet={ttsCardId:object.CardID};record.assetSheet=assetKey;
 }else if(object.Name==='Custom_Tile'&&object.CustomImage){
  record.cardImage=assetUrl(object.CustomImage.ImageURL);
  record.cardBack=assetUrl(object.CustomImage.ImageSecondaryURL);
  record.objectKind='tile';
  record.objectScale={x:object.Transform?.scaleX||1,y:object.Transform?.scaleY||1,z:object.Transform?.scaleZ||1};
 }
 imported.push(record);
}

const importedKeys=new Set(imported.map(card=>card.type+':'+card.id));
catalog.cards=catalog.cards.filter(card=>!importedKeys.has(card.type+':'+card.id)).concat(imported)
 .sort((a,b)=>a.type.localeCompare(b.type)||a.id.localeCompare(b.id,undefined,{numeric:true}));
fs.writeFileSync(catalogPath,JSON.stringify(catalog,null,2)+'\n');
console.log(JSON.stringify({imported:imported.length,missing},null,2));
