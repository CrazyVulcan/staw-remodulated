(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.RemodulatedRules=api;})(typeof window==='object'?window:globalThis,function(){
 const INTERNAL_HELPERS=new Set(['crew:C426','question:Q030']);
 // Verified Alliance app copies. Retain their IDs for imports and saved fleets;
 // only suppress a library entry when its regular card is also available.
 const AP_DUPLICATES=Object.freeze({
  AP1001:'C359',AP1002:'C360',AP1003:'C361',AP1005:'C362',
  AP1006:'E200',AP1007:'E201',AP1008:'E199',AP1009:'E202',AP1010:'E203',
  AP1011:'T254',AP1012:'T256',AP1013:'T255',AP1014:'T253',AP1015:'T257',AP1016:'T258',AP1017:'T259',
  AP1018:'W204',AP1020:'W203',AP1021:'W205',AP1022:'W201',AP1023:'W207',AP1024:'W202',
  AP2001:'E216',AP2002:'E217',AP2003:'C391',AP2004:'T281'
 });
 const TRAITS=[{
  id:'lower-decks',label:'Lower Decks',matches:card=>card?.type==='crew'&&/\(\s*Lower Decks\s*\)/i.test(String(card.text||''))
 }];
 function key(card){return (card?.catalogType||card?.type)+':'+card?.id;}
 function traits(card){return TRAITS.filter(rule=>rule.matches(card)).map(rule=>rule.id);}
 function hasTrait(card,id){return traits(card).includes(id);}
 function isInternalHelper(card){return INTERNAL_HELPERS.has(key(card))||/NOT A REAL CARD/i.test(String(card?.text||''));}
 function libraryCards(cards){
  const byKey=new Map(cards.map(card=>[key(card),card]));
  return cards.filter(card=>{
   if(isInternalHelper(card))return false;
   const original=byKey.get((card.catalogType||card.type)+':'+AP_DUPLICATES[card.id]);
   return !original||original.name!==card.name;
  });
 }
 function applyCatalogSlots(card){
  for(const [index,definition]of (card.additionalUpgradeSlots||[]).entries()){
   card.upgradeSlots=card.upgradeSlots||[];
   if(!card.upgradeSlots.some(slot=>slot._additionalSlot===index))card.upgradeSlots.push({
    ...definition,type:[...definition.type],source:card.name,_additionalSlot:index
   });
  }
  return card;
 }
 function enhanceEquippedCard(card,parentSlot){
  if(!card||parentSlot?._sharedRule||!hasTrait(card,'lower-decks'))return card;
  const types=Array.isArray(parentSlot?.type)?parentSlot.type:[];
  if(!types.includes('crew'))return card;
  card.upgradeSlots=card.upgradeSlots||[];
  if(!card.upgradeSlots.some(slot=>slot._sharedRule==='lower-decks'))card.upgradeSlots.push({
   type:['crew'],rules:'Shares this crew slot',source:'Lower Decks',_sharedRule:'lower-decks',
   canEquip:upgrade=>hasTrait(upgrade,'lower-decks')
  });
  return card;
 }
 function capabilityLabels(card){
  const labels=traits(card).map(id=>TRAITS.find(rule=>rule.id===id).label);
  const added=(card?.upgradeSlots||[]).filter(slot=>!slot._sharedRule);
  if(added.length)labels.push('Adds '+added.length+' slot'+(added.length===1?'':'s'));
  return labels;
 }
 return {TRAITS,traits,hasTrait,isInternalHelper,applyCatalogSlots,enhanceEquippedCard,capabilityLabels,AP_DUPLICATES,libraryCards};
});
