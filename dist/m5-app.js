(async function(){
  'use strict';
  const $=id=>document.getElementById(id),storageKey='remodulated-m5-v1';
  const esc=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const signed=n=>n>=0?'+'+n:String(n);
  let catalog,fleet;
  const fresh=()=>({schemaVersion:2,source:{kind:'remodulated-m5',m5Version:1},fleetId:'m5-'+crypto.randomUUID(),name:'M5 patrol',threatLimit:30,ships:[],resources:[]});
  function status(message){$('m5-status').textContent=message;}
  function render(){
    const totals=M5Fleet.validate(fleet,catalog,{allowEmpty:true});
    $('m5-name').value=fleet.name||'';$('m5-limit').value=fleet.threatLimit;
    $('m5-total').textContent=totals.threat+' / '+fleet.threatLimit+' Threat · '+(totals.remaining>=0?totals.remaining+' available':-totals.remaining+' over limit');
    $('m5-add').disabled=fleet.ships.length>=3;
    $('m5-export').disabled=$('m5-save').disabled=!fleet.ships.length;
    $('m5-ships').innerHTML=totals.ships.map((total,index)=>`<article class="m5-ship"><header><h3>${esc(total.profile.name)} · ${esc(total.profile.id)}</h3><button data-remove="${index}" aria-label="Remove ship ${index+1}">Remove ship</button></header><p>${esc(total.profile.faction)} · ${esc(total.profile.class)}</p><p>Base CS ${total.profile.baseCaptainSkill} → <strong>CS ${total.cs}</strong> · <strong>${total.threat} Threat</strong> · <strong>${total.slots}/${total.capacity} slots</strong></p><div class="m5-programs">${catalog.programs.map(program=>`<label class="m5-program"><input type="checkbox" data-ship="${index}" data-program="${esc(program.id)}" ${fleet.ships[index].cards.some(c=>c.cardId===program.id)?'checked':''}> <strong>${esc(program.name)}</strong><p>CS ${signed(program.csModifier)} · +${program.threat} Threat · ${program.slots} slot${program.slots===1?'':'s'}</p><p>${esc(program.text)}</p><small>Restrictions: ${esc(program.faction)} · ${esc(program.classes.join(' / '))}</small><small>${esc(program.status)}</small></label>`).join('')}</div></article>`).join('')||'<p class="empty">Add a Neg’Var to start your M5 fleet.</p>';
    try{localStorage.setItem(storageKey,JSON.stringify(fleet));}catch{status('Browser storage unavailable. Use Save to keep this fleet.');}
  }
  function change(edit){const draft=structuredClone(fleet);try{edit(draft);M5Fleet.validate(draft,catalog,{allowEmpty:true});fleet=draft;status('');render();}catch(error){status(error.message);render();}}
  try{
    const base=window.RemodulatedConfig?.assetBase||'';
    const response=await fetch((base?base+'/':'')+'data/m5-catalog.json');if(!response.ok)throw Error('M5 catalog could not be loaded.');catalog=await response.json();
    fleet=fresh();try{const saved=localStorage.getItem(storageKey);if(saved){const value=JSON.parse(saved);M5Fleet.validate(value,catalog,{allowEmpty:true});fleet=value;}}catch{status('The saved M5 fleet could not be read. Import a downloaded fleet to recover it.');}
    $('m5-add').onclick=()=>change(d=>d.ships.push({shipCardId:'M5S001',cards:[]}));
    $('m5-name').onchange=e=>change(d=>d.name=e.target.value.slice(0,100));
    $('m5-limit').onchange=e=>change(d=>d.threatLimit=Number(e.target.value));
    $('m5-ships').onchange=e=>{if(e.target.dataset.program)change(d=>{const s=d.ships[Number(e.target.dataset.ship)],id=e.target.dataset.program;if(e.target.checked)s.cards.push({cardId:id,role:'m5-program'});else s.cards=s.cards.filter(c=>c.cardId!==id);});};
    $('m5-ships').onclick=e=>{if(e.target.dataset.remove!==undefined)change(d=>d.ships.splice(Number(e.target.dataset.remove),1));};
    $('m5-new').onclick=()=>{if(fleet.ships.length&&!confirm('Start a new M5 fleet? Save this fleet first if you want to keep it.'))return;fleet=fresh();render();};
    function dialog(mode){const importing=mode==='import';$('m5-dialog-title').textContent=importing?'Import M5 fleet':'TTS export';$('m5-dialog-help').textContent=importing?'Paste a saved M5 fleet. Your current fleet is replaced only after validation.':'Copy this fleet into Fleet Setup in the updated M5 TTS save. Each ship and its programs spawn as a physical row.';$('m5-json').value=importing?'':M5Fleet.serialize(fleet,catalog);$('m5-json').readOnly=!importing;$('m5-apply').hidden=!importing;$('m5-copy').hidden=importing;$('m5-dialog-status').textContent='';$('m5-dialog').showModal();}
    $('m5-import').onclick=()=>dialog('import');$('m5-export').onclick=()=>dialog('export');$('m5-close').onclick=()=>$('m5-dialog').close();
    $('m5-apply').onclick=()=>{try{const candidate=M5Fleet.parse($('m5-json').value,catalog);fleet=candidate;render();$('m5-dialog').close();status('M5 fleet imported.');}catch(error){$('m5-dialog-status').textContent=error.message;}};
    $('m5-copy').onclick=async()=>{try{await navigator.clipboard.writeText($('m5-json').value);$('m5-dialog-status').textContent='Copied. Paste into TTS Fleet Setup.';}catch{$('m5-json').select();$('m5-dialog-status').textContent='Select and copy the text manually.';}};
    $('m5-save').onclick=()=>{const url=URL.createObjectURL(new Blob([M5Fleet.serialize(fleet,catalog)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='m5-fleet.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
    render();
  }catch(error){status(error.message);for(const id of ['m5-add','m5-export','m5-save','m5-import','m5-new'])$(id).disabled=true;}
})();
