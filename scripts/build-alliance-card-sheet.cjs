const fs=require('fs');
const path=require('path');
const sharp=require('sharp');

const root=path.resolve(__dirname,'..');
const catalog=JSON.parse(fs.readFileSync(path.join(root,'vendor','alliance-ship-cards.json'),'utf8'));
const cards=Object.values(catalog.cards).sort((a,b)=>a.sheetIndex-b.sheetIndex);
const columns=catalog.sheet.width,rows=catalog.sheet.height;
if(cards.length>columns*rows)throw Error(`Sheet is ${columns}x${rows}, but catalog has ${cards.length} cards.`);
// 400x560 retains the standard 5:7 card ratio while keeping a 10x7 sheet
// within TTS's practical 4096px texture limit. A small gutter ensures the
// complete card edge remains visible in every sliced slot.
const slotWidth=400,slotHeight=560,cardWidth=390,cardHeight=550,gutter=5;
async function load(url){
  const response=await fetch(url);
  if(!response.ok)throw Error(`${response.status} loading ${url}`);
  return Buffer.from(await response.arrayBuffer());
}
async function sheet(field,output){
  const unique=new Map();
  for(const card of cards)if(!unique.has(card[field]))unique.set(card[field],load(card[field]));
  await Promise.all(unique.values());
  const composites=[];
  for(const card of cards){
    const input=await unique.get(card[field]);
    const cardImage=await sharp(input).resize(cardWidth,cardHeight,{fit:'contain',background:{r:0,g:0,b:0,alpha:1}}).png().toBuffer();
    // Flatten each card into its own complete grid cell before assembling the
    // sheet. This guarantees that no source image can bleed into an adjacent
    // TTS slice and leaves a visible five-pixel border around the full card.
    const slot=await sharp({create:{width:slotWidth,height:slotHeight,channels:3,background:{r:0,g:0,b:0}}})
      .composite([{input:cardImage,left:gutter,top:gutter}]).png().toBuffer();
    composites.push({input:slot,left:(card.sheetIndex%columns)*slotWidth,top:Math.floor(card.sheetIndex/columns)*slotHeight});
  }
  await sharp({create:{width:columns*slotWidth,height:rows*slotHeight,channels:3,background:{r:0,g:0,b:0}}})
    .composite(composites).webp({quality:95}).toFile(output);
}
(async()=>{
  const outputDir=path.join(root,'public','cards','alliance');
  fs.mkdirSync(outputDir,{recursive:true});
  await sheet('profileImage',path.join(outputDir,'alliance-ship-cards.webp'));
  await sheet('classImage',path.join(outputDir,'alliance-ship-backs.webp'));
  console.log(`Built ${columns}x${rows} Alliance face and back sheets with ${cards.length} full-card slots.`);
})().catch(error=>{console.error(error);process.exitCode=1;});
