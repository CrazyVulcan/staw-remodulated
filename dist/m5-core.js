(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.M5Fleet=api;})(typeof window==='object'?window:globalThis,function(){
  'use strict';
  function shipTotals(ship,catalog){
    const profile=catalog.ships.find(p=>p.id===ship.shipCardId);
    if(!profile||!/^M5S\d{3}$/.test(ship.shipCardId))throw Error('Unknown M5 ship: '+ship.shipCardId);
    if(!Array.isArray(ship.cards))throw Error('Installed programs must be a list.');
    const seen=new Set();let cs=profile.baseCaptainSkill,threat=profile.baseThreat,slots=0;
    for(const card of ship.cards){
      const program=catalog.programs.find(p=>p.id===card?.cardId);
      if(!program)throw Error('Unknown M5 program: '+card?.cardId);
      if(seen.has(program.id))throw Error('Duplicate program: '+program.name);
      if(card.hidden)throw Error('M5 programs cannot be hidden.');
      if(program.faction!==profile.faction||!program.classes.includes(profile.class))throw Error(program.name+' is restricted to '+program.faction+' '+program.classes.join(' / '));
      seen.add(program.id);cs+=program.csModifier;threat+=program.threat;slots+=program.slots;
    }
    if(slots>profile.slotCapacity)throw Error('M5 slots exceeded for '+profile.name);
    return {profile,cs,threat,slots,capacity:profile.slotCapacity};
  }
  function validate(fleet,catalog,{allowEmpty=false}={}){
    if(!fleet||fleet.schemaVersion!==2||fleet.source?.kind!=='remodulated-m5'||fleet.source?.m5Version!==1)throw Error('Expected an M5 fleet export, version 1.');
    if(typeof fleet.fleetId!=='string'||!/^m5-[a-zA-Z0-9-]{1,80}$/.test(fleet.fleetId))throw Error('Invalid M5 fleet identity.');
    if(!Array.isArray(fleet.ships)||(!allowEmpty&&!fleet.ships.length)||fleet.ships.length>3)throw Error('Use one to three M5 ships; each ship has its own TTS row.');
    if(fleet.resources!==undefined&&(!Array.isArray(fleet.resources)||fleet.resources.length!==0))throw Error('M5 fleets do not support normal resources.');
    if(!Number.isInteger(fleet.threatLimit)||fleet.threatLimit<1||fleet.threatLimit>9999)throw Error('Threat limit must be 1–9999.');
    const ships=fleet.ships.map(s=>shipTotals(s,catalog));
    const threat=ships.reduce((n,s)=>n+s.threat,0);
    return {ships,threat,remaining:fleet.threatLimit-threat};
  }
  function serialize(fleet,catalog){validate(fleet,catalog);return JSON.stringify(fleet,null,2);}
  function parse(text,catalog){const fleet=JSON.parse(text);validate(fleet,catalog);return fleet;}
  return {shipTotals,validate,serialize,parse};
});
