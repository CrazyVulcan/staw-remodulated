const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'..');
const input=path.resolve(process.argv[2]||'');
if(!process.argv[2]||!fs.existsSync(input))throw Error('Pass Alliance Ship Cards.json.');
const saved=JSON.parse(fs.readFileSync(input,'utf8'));
const cards=[];
function walk(objects){
  for(const object of objects||[]){
    if(object.Name==='CardCustom'&&object.CardID!==undefined){
      const decks=Object.values(object.CustomDeck||{});
      if(decks.length!==1)throw Error(`Card ${object.CardID} must contain exactly one custom deck definition.`);
      const deck=decks[0];
      if(!deck.FaceURL||!deck.BackURL)throw Error(`Card ${object.CardID} is missing a face or back image.`);
      cards.push({id:String(object.CardID),className:object.Nickname||'Alliance Ship',classImage:deck.FaceURL,profileImage:deck.BackURL});
    }
    walk(object.ContainedObjects);
    if(object.States)walk(Object.values(object.States));
  }
}
walk(saved.ObjectStates);
cards.sort((a,b)=>Number(a.id)-Number(b.id));
if(cards.length!==32)throw Error(`Expected 32 Alliance ship cards; found ${cards.length}.`);
if(new Set(cards.map(card=>card.id)).size!==cards.length)throw Error('Alliance ship card IDs must be unique.');
cards.forEach((card,index)=>card.sheetIndex=index);
const document={schemaVersion:1,source:path.basename(input),sheet:{
  face:'https://steamusercontent-a.akamaihd.net/ugc/12941386263067143059/558C4A1E301B9AA11C5119D7B8B0462FE943C635/',
  back:'https://steamusercontent-a.akamaihd.net/ugc/12020036739026850548/1952CEDF8FBF6FAE69330AE3D62030A0CE562749/',
  width:10,height:7,uniqueBack:true,
},cards:Object.fromEntries(cards.map(card=>[card.id,card]))};
fs.writeFileSync(path.join(root,'vendor','alliance-ship-cards.json'),JSON.stringify(document,null,2)+'\n');

const luaPath=path.join(root,'vendor','tts-importer-source.lua');
let lua=fs.readFileSync(luaPath,'utf8');
const prefix='local ALLIANCE_SHIP_CARD_DATA=JSON.decode([===[';
const suffix=']===])';
const start=lua.indexOf(prefix);
const end=lua.indexOf(suffix,start+prefix.length);
if(start<0||end<0)throw Error('Could not find the Alliance ship-card catalog marker in the TTS source.');
lua=lua.slice(0,start+prefix.length)+JSON.stringify(document)+lua.slice(end);
fs.writeFileSync(luaPath,lua);
console.log(`Imported ${cards.length} Alliance ship cards.`);
