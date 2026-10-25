const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const root=path.resolve(__dirname,'..');
const moduleSource=fs.readFileSync(path.join(root,'vendor/alliance-captain-tracker.lua'),'utf8');
const catalog=JSON.parse(fs.readFileSync(path.join(root,'vendor/tts-catalog.json'),'utf8'));
const captains=catalog.cards.filter(c=>c.interactiveCaptain);
assert.equal(captains.length,3);
function patch(lua){
  lua=lua.replace(/\r\n/g,'\n');
  if(lua.includes('-- ALLIANCE_INTERACTIVE_CAPTAINS_20261013'))throw Error('Captain integration is already installed.');
  function once(a,b){assert.equal(lua.split(a).length,2,'Expected unique patch: '+a.slice(0,90));lua=lua.replace(a,b);}
  once('local function cardData(card)\n','local function cardData(card)\n    if card and card.interactiveCaptain then return copy(card.objectData) end\n');
  once('data.GUID=nil;data.States=nil;data.LuaScript=MEMBER_SCRIPT;data.XmlUI=""','data.GUID=nil;data.States=nil\n        if not card.interactiveCaptain then data.LuaScript=MEMBER_SCRIPT;data.XmlUI="" end');
  once('data.LuaScriptState=JSON.encode({schemaVersion=1,role="pending",transaction=key})','data.LuaScriptState=card.interactiveCaptain and STA2E.AllianceCaptain.pendingState(data,color,key) or JSON.encode({schemaVersion=1,role="pending",transaction=key})');
  once('STA2E.ships[s.instanceId]=s;commit(s);spawnFleetShields(s);deploy(s);refresh(s)','STA2E.ships[s.instanceId]=s;STA2E.AllianceCaptain.syncShipName(s);STA2E.AllianceCaptain.syncCaptain(s);commit(s);spawnFleetShields(s);deploy(s);refresh(s)');
  const captainStart=lua.indexOf('local function captainFor(s)');
  const captainEnd=lua.indexOf('\nlocal function skillFor(s)',captainStart);
  assert(captainStart>=0&&captainEnd>captainStart);
  lua=lua.slice(0,captainStart)+`local function captainFor(s)
    for _,entry in ipairs(s.upgrades or {}) do
        local card=CATALOG[entry.cardId]
        if card and card.type=="captain" then
            local live=card.interactiveCaptain and s.allianceCaptain
            if live and live.guid==entry.guid then
                return {id=card.id,type="captain",name=live.name~="" and live.name or card.name,skill=live.skill}
            end
            return card
        end
    end
    return nil
end
`+lua.slice(captainEnd);
  // Add the three verified object routes to the existing catalog chunks.
  const pattern=/\{target=CATALOG_DATA\["cards"\],offset=(\d+),json=\[===\[([\s\S]*?)\]===\]\}/g;
  const chunks=[...lua.matchAll(pattern)];assert(chunks.length>0);
  const last=chunks.at(-1),cards=JSON.parse(last[2]);
  for(const card of captains)assert(!chunks.some(chunk=>JSON.parse(chunk[2]).some(existing=>existing.id===card.id)),'Captain route already exists');
  lua=lua.slice(0,last.index)+`{target=CATALOG_DATA["cards"],offset=${last[1]},json=[===[${JSON.stringify(cards.concat(captains))}]===]}`+lua.slice(last.index+last[0].length);
  return lua+'\n-- ALLIANCE_INTERACTIVE_CAPTAINS_20261013\n'+moduleSource;
}
module.exports=patch;
if(require.main===module){const target=process.argv[2];if(!target)throw Error('Supply a Lua file to install captain support.');fs.writeFileSync(target,patch(fs.readFileSync(target,'utf8')));console.log('Installed Alliance captain objects and tracker name synchronization.');}
