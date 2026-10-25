(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.RemodulatedRules=api;})(typeof window==='object'?window:globalThis,function(){
 const INTERNAL_HELPERS=new Set(['crew:C426','question:Q030']);
 const TRAITS=[{
  id:'lower-decks',label:'Lower Decks',matches:card=>card?.type==='crew'&&/\(\s*Lower Decks\s*\)/i.test(String(card.text||''))
 }];
 function key(card){return (card?.catalogType||card?.type)+':'+card?.id;}
 function traits(card){return TRAITS.filter(rule=>rule.matches(card)).map(rule=>rule.id);}
 function hasTrait(card,id){return traits(card).includes(id);}
 function isInternalHelper(card){return INTERNAL_HELPERS.has(key(card))||/NOT A REAL CARD/i.test(String(card?.text||''));}
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
 return {TRAITS,traits,hasTrait,isInternalHelper,applyCatalogSlots,enhanceEquippedCard,capabilityLabels};
});
