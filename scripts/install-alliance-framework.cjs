const fs=require('fs');
const path=require('path');

const root=path.resolve(__dirname,'..');
const savePath=path.resolve(process.argv[2]||'');
if(!process.argv[2]||!fs.existsSync(savePath))throw Error('Pass the current TTS save path.');
const save=JSON.parse(fs.readFileSync(savePath,'utf8'));
if(typeof save.LuaScript!=='string')throw Error('The save has no Global LuaScript.');
const canonical=fs.readFileSync(path.join(root,'vendor','tts-importer-source.lua'),'utf8');
const chipScript=fs.readFileSync(path.join(root,'vendor','alliance-a1m1-chip.lua'),'utf8');
const missionStartTokenImage='https://steamusercontent-a.akamaihd.net/ugc/15124136587514081326/767C98EB6EB818EEFE4DB2043199556D1CFD5A01/';
const moduleStart=canonical.indexOf('-- Alliance mission framework.');
const moduleEnd=canonical.indexOf('local phaseReconcile=STA2E_Reconcile',moduleStart);
if(moduleStart<0||moduleEnd<0)throw Error('Could not extract the canonical Alliance controller.');
const allianceModule=canonical.slice(moduleStart,moduleEnd);
let lua=save.LuaScript;

// Keep the save's runtime card catalog aligned with the builder. This updates
// corrected WebP fronts and paired backs without replacing the rest of Global.
{
  const canonicalCatalogStart=canonical.indexOf('CATALOG_DATA = JSON.decode(');
  const canonicalCatalogEnd=canonical.indexOf('\nSHIP_DATA =',canonicalCatalogStart);
  const catalogStart=lua.indexOf('CATALOG_DATA = JSON.decode(');
  const catalogEnd=lua.indexOf('\nSHIP_DATA =',catalogStart);
  if(canonicalCatalogStart<0||canonicalCatalogEnd<0||catalogStart<0||catalogEnd<0)throw Error('Could not synchronize the TTS card catalog header.');
  lua=lua.slice(0,catalogStart)+canonical.slice(canonicalCatalogStart,canonicalCatalogEnd)+lua.slice(catalogEnd);

  const canonicalJobsStart=canonical.indexOf('local startupJobs = {');
  const canonicalJobsEnd=canonical.indexOf('\nSTANDARD_BASE =',canonicalJobsStart);
  const jobsStart=lua.indexOf('local startupJobs = {');
  const jobsEnd=lua.indexOf('\nSTANDARD_BASE =',jobsStart);
  if(canonicalJobsStart<0||canonicalJobsEnd<0||jobsStart<0||jobsEnd<0)throw Error('Could not synchronize the TTS card catalog batches.');
  lua=lua.slice(0,jobsStart)+canonical.slice(canonicalJobsStart,canonicalJobsEnd)+lua.slice(jobsEnd);
}

function replaceOne(before,after,label){
  if(lua.includes(after))return;
  const count=lua.split(before).length-1;
  if(count!==1)throw Error(`Expected one ${label} insertion point; found ${count}.`);
  lua=lua.replace(before,()=>after);
}
function replaceWhenPresent(before,after){if(lua.includes(before))lua=lua.replace(before,()=>after);}

if(!lua.includes('local function defaultXmlAttribute(markup,tag,attribute,value)')){
  const xmlEnd='local function xml(text)\n    return tostring(text or ""):gsub("&", "&amp;"):gsub(\'"\', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;")\nend';
  const safeAttributes=`${xmlEnd}
local function defaultXmlAttribute(markup,tag,attribute,value)
    local needle="<"..tag.." ";local output={};local cursor=1
    while true do
        local first,last=markup:find(needle,cursor,true)
        if not first then table.insert(output,markup:sub(cursor));break end
        table.insert(output,markup:sub(cursor,first-1))
        local close=markup:find(">",last+1,true)
        if not close then table.insert(output,markup:sub(first));break end
        local node=markup:sub(first,close)
        if not node:find(" "..attribute.."=",1,true) then node=needle..attribute..'="'..value..'" '..node:sub(#needle+1) end
        table.insert(output,node);cursor=close+1
    end
    return table.concat(output)
end`;
  replaceOne(xmlEnd,safeAttributes,'safe XML attribute helper');
}

const playerBlockStart=canonical.indexOf('local PLAYER_COLORS=');
const playerBlockEnd=canonical.indexOf('\nlocal function nextId',playerBlockStart);
if(playerBlockStart<0||playerBlockEnd<0)throw Error('Could not extract the canonical fleet-player configuration.');
const playerBlock=canonical.slice(playerBlockStart,playerBlockEnd);
{
  const configured=lua.indexOf('local PLAYER_COLORS=');
  const legacy=lua.indexOf('local function own(color)');
  const start=configured>=0?configured:legacy;
  const end=lua.indexOf('\nlocal function nextId',start);
  if(start<0||end<0)throw Error('Could not find the fleet-player configuration to update.');
  lua=lua.slice(0,start)+playerBlock+lua.slice(end);
}
const visibilityStart=canonical.indexOf('local function publicVisibility(owner)');
const visibilityEnd=canonical.indexOf('\nlocal function render',visibilityStart);
if(visibilityStart<0||visibilityEnd<0)throw Error('Could not extract the canonical private-visibility helper.');
{
  const start=lua.indexOf('local function publicVisibility(owner)');
  const end=lua.indexOf('\nlocal function render',start);
  if(start<0||end<0)throw Error('Could not find the private-visibility helper to update.');
  lua=lua.slice(0,start)+canonical.slice(visibilityStart,visibilityEnd)+lua.slice(end);
}
replaceWhenPresent(
  '        local markup=table.concat(private):gsub(\'<Text \', \'<Text color="#FFFFFF" \')\n        -- Highlighted labels already specify a color; avoid duplicate XML attributes.\n        markup=markup:gsub(\'<Text color="#FFFFFF" ([^>]-) color="([^"]+)"\', \'<Text %1 color="%2"\')\n        markup=markup:gsub(\'<Button \', \'<Button textColor="#FFFFFF" \')',
  '        local markup=table.concat(private)\n        markup=defaultXmlAttribute(markup,"Text","color","#FFFFFF")\n        markup=defaultXmlAttribute(markup,"Button","textColor","#FFFFFF")');
if(lua.includes('markup:gsub(\'<Text color="#FFFFFF" ([^>]-)'))throw Error('Could not remove the complex dashboard XML pattern.');

const playerTextureStart=canonical.indexOf('local PLAYER_BASE_TEXTURES=');
const playerTextureEnd=canonical.indexOf('\nlocal ALLIANCE_AI_BASE_TEXTURES=',playerTextureStart);
if(playerTextureStart<0||playerTextureEnd<0)throw Error('Could not extract the canonical player base textures.');
{
  const start=lua.indexOf('local PLAYER_BASE_TEXTURES=');
  const end=lua.indexOf('\nlocal ALLIANCE_AI_BASE_TEXTURES=',start);
  if(start<0||end<0)throw Error('Could not find the player base textures to update.');
  lua=lua.slice(0,start)+canonical.slice(playerTextureStart,playerTextureEnd)+lua.slice(end);
}
const aiBaseStart=canonical.indexOf('local ALLIANCE_AI_BASE_TEXTURES=');
const aiBaseEnd=canonical.indexOf('\nlocal function deploy',aiBaseStart);
if(aiBaseStart<0||aiBaseEnd<0)throw Error('Could not extract the canonical Alliance AI base textures.');
const aiBaseBlock=canonical.slice(aiBaseStart,aiBaseEnd);
{
  const tableStart=lua.indexOf('local ALLIANCE_AI_BASE_TEXTURES=');
  const functionStart=lua.indexOf('local function STA2E_BaseTexture(');
  const start=tableStart>=0?tableStart:functionStart;
  const end=lua.indexOf('\nlocal function deploy',functionStart+'local function STA2E_BaseTexture('.length);
  if(start<0||end<0)throw Error('Could not find the base texture selector to update.');
  lua=lua.slice(0,start)+aiBaseBlock+'\n'+lua.slice(end+1);
}
lua=lua.split('STA2E_BaseTexture(s.owner,class.arc,large)').join('STA2E_BaseTexture(s.owner,class.arc,large,s.ai~=nil)');
lua=lua.split('STA2E_BaseTexture(s.owner,class.arc,isLargeBase)').join('STA2E_BaseTexture(s.owner,class.arc,isLargeBase,s.ai~=nil)');
if((lua.match(/local ALLIANCE_AI_BASE_TEXTURES=/g)||[]).length!==1)throw Error('Could not install one Alliance AI base texture set.');
if(!lua.includes('STA2E_BaseTexture(s.owner,class.arc,large,s.ai~=nil)')&&!lua.includes('STA2E_BaseTexture(s.owner,class.arc,isLargeBase,s.ai~=nil)'))throw Error('Could not route AI deployment through the white base selector.');
replaceWhenPresent(
  'local dialTransform=playerSideTransform(s.owner,p,{side=4.2,up=0.3})',
  'local dialTransform=playerSideTransform(s.owner,p,{side=6.0,forward=0.1,up=0.3})');
replaceWhenPresent(
  'local dialTransform=playerSideTransform(s.owner,p,{side=-6.0,forward=0.1,up=0.3})',
  'local dialTransform=playerSideTransform(s.owner,p,{side=6.0,forward=0.1,up=0.3})');
replaceWhenPresent(
  'local referenceTransform=playerSideTransform(s.owner,p,{side=4.2,forward=3.4,up=0.15})',
  'local referenceTransform=playerSideTransform(s.owner,p,{side=3.15,up=0.15})');
replaceWhenPresent(
  'local referenceTransform=playerSideTransform(s.owner,p,{side=-3.15,up=0.15})',
  'local referenceTransform=playerSideTransform(s.owner,p,{side=3.15,up=0.15})');
replaceWhenPresent(
  'Nickname=s.name.." Dial",Description=s.definitionId,Transform={posX=0,posY=1.5,posZ=0,rotX=0,rotY=180,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},ColorDiffuse={r=1,g=1,b=1},Locked=true',
  'Nickname=s.name.." Dial",Description=s.definitionId,Transform={posX=0,posY=1.5,posZ=0,rotX=0,rotY=180,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},ColorDiffuse={r=1,g=1,b=1},Locked=false');
replaceWhenPresent(
  'Nickname=s.name.." Maneuver Reference",Description=reference.name,Transform={posX=0,posY=1.2,posZ=0,rotX=0,rotY=0,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},ColorDiffuse={r=1,g=1,b=1},Locked=true',
  'Nickname=s.name.." Maneuver Reference",Description=reference.name,Transform={posX=0,posY=1.2,posZ=0,rotX=0,rotY=0,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},ColorDiffuse={r=1,g=1,b=1},Locked=false');
if(!lua.includes('local dialTransform=playerSideTransform(s.owner,p,{side=6.0,forward=0.1,up=0.3})'))throw Error('Could not install the card-relative dial position.');
if(!lua.includes('local referenceTransform=playerSideTransform(s.owner,p,{side=3.15,up=0.15})'))throw Error('Could not install the card-relative maneuver-reference position.');
if(!lua.includes('Nickname=s.name.." Dial",Description=s.definitionId,Transform={posX=0,posY=1.5,posZ=0,rotX=0,rotY=180,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},ColorDiffuse={r=1,g=1,b=1},Locked=false'))throw Error('Could not unlock spawned maneuver dials.');
if(!lua.includes('Nickname=s.name.." Maneuver Reference",Description=reference.name,Transform={posX=0,posY=1.2,posZ=0,rotX=0,rotY=0,rotZ=0,scaleX=1,scaleY=1,scaleZ=1},ColorDiffuse={r=1,g=1,b=1},Locked=false'))throw Error('Could not unlock spawned maneuver references.');

const actionChoiceStart=canonical.indexOf('local ACTION_KEYS=');
const actionChoiceEnd=canonical.indexOf('\nlocal function dialFor',actionChoiceStart);
if(actionChoiceStart<0||actionChoiceEnd<0)throw Error('Could not extract the canonical action choices.');
{
  const start=lua.indexOf('local ACTION_KEYS=');
  const end=lua.indexOf('\nlocal function dialFor',start);
  if(start<0||end<0)throw Error('Could not find the ship action choices to update.');
  lua=lua.slice(0,start)+canonical.slice(actionChoiceStart,actionChoiceEnd)+lua.slice(end);
}
lua=lua.split('for i,key in ipairs((s.capabilities and s.capabilities.actions) or {}) do table.insert(private,dialButton("action_"..key,key,((i-1)%2==0 and -115 or 115),210-math.floor((i-1)/2)*62,"#284A66")) end')
  .join('for i,key in ipairs(actionChoices(s)) do table.insert(private,dialButton("action_"..key,key,((i-1)%2==0 and -115 or 115),210-math.floor((i-1)/2)*62,"#284A66")) end');
lua=lua.split('dialButton("undo","UNDO MOVEMENT",-115,55,"#526777")').join('dialButton("undo","UNDO MOVEMENT",-115,-65,"#526777")');
lua=lua.split('dialButton("undo","UNDO MOVEMENT",-115,-5,"#526777")').join('dialButton("undo","UNDO MOVEMENT",-115,-65,"#526777")');
lua=lua.split('dialButton("finish","SKIP / FINISH",115,55,"#863B3B")').join('dialButton("finish","SKIP / FINISH",115,-65,"#863B3B")');
lua=lua.split('dialButton("finish","SKIP / FINISH",115,-5,"#863B3B")').join('dialButton("finish","SKIP / FINISH",115,-65,"#863B3B")');

const cardManagerStart=canonical.indexOf('local drawShipGuides');
const cardManagerEnd=canonical.indexOf('\nfunction hud()',cardManagerStart);
if(cardManagerStart<0||cardManagerEnd<0)throw Error('Could not extract the canonical upgrade-card manager.');
{
  const declarationStart=lua.indexOf('local drawShipGuides');
  const legacyStart=lua.indexOf('local function managedObject(color)');
  const start=declarationStart>=0?declarationStart:legacyStart;
  const end=lua.indexOf('\nfunction hud()',start);
  if(start<0||end<0)throw Error('Could not find the upgrade-card manager to update.');
  lua=lua.slice(0,start)+canonical.slice(cardManagerStart,cardManagerEnd)+lua.slice(end);
}
lua=lua.replace('local function drawShipGuides(s)','drawShipGuides=function(s)');
if(!lua.includes('rectAlignment="LowerCenter" offsetXY="0 28"')||!lua.includes('manage_action_')||!lua.includes('reminderCardFace(source,cardId)'))throw Error('Could not install the bottom-center upgrade-card manager.');
if(!lua.includes('for i,key in ipairs(actionChoices(s)) do'))throw Error('Could not add Sensor Echo to the shared ship action menu.');
if(!lua.includes('local ALL_ACTION_CHOICES={"EVA","BS","TL","SCN","CLK","REG","ECHO"}'))throw Error('Could not install the complete shared action list.');
if(!lua.includes('dialButton("undo","UNDO MOVEMENT",-115,-65,"#526777")'))throw Error('Could not clear the expanded dial action menu footer.');

const actionTokenStart=canonical.indexOf('local ACTION_BAGS=');
const actionTokenEnd=canonical.indexOf('\nfunction STA2E_Command(params)',actionTokenStart);
if(actionTokenStart<0||actionTokenEnd<0)throw Error('Could not extract the canonical action-token placement.');
{
  const start=lua.indexOf('local ACTION_BAGS=');
  const end=lua.indexOf('\nfunction STA2E_Command(params)',start);
  if(start<0||end<0)throw Error('Could not find the action-token placement to update.');
  lua=lua.slice(0,start)+canonical.slice(actionTokenStart,actionTokenEnd)+lua.slice(end);
}

const tokenChoiceStart=canonical.indexOf('local SHIP_ADJACENT_CHOICES=');
const tokenChoiceEnd=canonical.indexOf('\nlocal function normalizeDialPhase',tokenChoiceStart);
if(tokenChoiceStart<0||tokenChoiceEnd<0)throw Error('Could not extract the split token choices.');
{
  const configured=lua.indexOf('local SHIP_ADJACENT_CHOICES=');
  const legacy=lua.indexOf('local TOKEN_CHOICES=');
  const start=configured>=0?configured:legacy;
  const end=lua.indexOf('\nlocal function normalizeDialPhase',start);
  if(start<0||end<0)throw Error('Could not find the token choices to update.');
  lua=lua.slice(0,start)+canonical.slice(tokenChoiceStart,tokenChoiceEnd)+lua.slice(end);
}
{
  const canonicalStart=canonical.indexOf('    if page=="tokens" then');
  const canonicalEnd=canonical.indexOf('    elseif page=="moves" then',canonicalStart);
  const start=lua.indexOf('    if page=="tokens" then');
  const end=lua.indexOf('    elseif page=="moves" then',start);
  if(canonicalStart<0||canonicalEnd<0||start<0||end<0)throw Error('Could not update the split token-menu layout.');
  lua=lua.slice(0,start)+canonical.slice(canonicalStart,canonicalEnd)+lua.slice(end);
}
const straightThree='    {id="STRAIGHT_3",label="3 Straight",distance=6.15,bias=0,orientation="forward"},';
if(!lua.includes(straightThree)){
  const echoAnchor='    {id="STRAIGHT_2",label="2 Straight",distance=4.60,bias=0,orientation="forward"},';
  if(!lua.includes(echoAnchor))throw Error('Could not find the Sensor Echo template list.');
  lua=lua.replace(echoAnchor,straightThree+'\n'+echoAnchor);
}
if(!lua.includes('local SHIP_ADJACENT_TOKENS={EVA=true,TL=true,BS=true,SCN=true,CLK=true,REG=true,AUX=true}')||!lua.includes('local SHIP_CARD_CHOICES='))throw Error('Could not install split action-token destinations.');
if(!lua.includes(straightThree))throw Error('Could not add the 3 Straight Sensor Echo template.');

const rangeHelperStart=canonical.indexOf('local function edgeRoundedRange(');
const rangeHelperEnd=canonical.indexOf('\nlocal function arcRangeBand',rangeHelperStart);
if(rangeHelperStart<0||rangeHelperEnd<0)throw Error('Could not extract the canonical rounded range helper.');
const roundedRange=canonical.slice(rangeHelperStart,rangeHelperEnd);
{
  const starts=[
    lua.indexOf('local function roundedRange('),
    lua.indexOf('local function squaredRange('),
    lua.indexOf('local function edgeRoundedRange('),
  ].filter(index=>index>=0);
  const start=starts.length?Math.min(...starts):-1;
  const candidates=[
    lua.indexOf('\nlocal function arcLines',start),
    lua.indexOf('\nlocal function arcProjection',start),
    lua.indexOf('\nlocal function arcRangeBand',start),
    lua.indexOf('\nlocal function drawShipGuides',start),
    lua.indexOf('\ndrawShipGuides=function',start),
  ].filter(index=>index>=0);
  if(start<0||!candidates.length)throw Error('Could not find the range helper to update.');
  const end=Math.min(...candidates);
  lua=lua.slice(0,start)+roundedRange+'\n'+lua.slice(end+1);
}
lua=lua.split('roundedRange(').join('edgeRoundedRange(');
lua=lua.split('squaredRange(').join('edgeRoundedRange(');
replaceWhenPresent('local ARC_LINE_THICKNESS=0.034','local ARC_LINE_THICKNESS=0.05');

const arcHelperStart=canonical.indexOf('local function arcRangeBand(');
const arcHelperEnd=canonical.indexOf('\ndrawShipGuides=function',arcHelperStart);
if(arcHelperStart<0||arcHelperEnd<0)throw Error('Could not extract the canonical curved arc helper.');
const arcProjection=canonical.slice(arcHelperStart,arcHelperEnd);
{
  const oldStart=lua.indexOf('local function arcLines(');
  const curvedStart=lua.indexOf('local function arcRangeBand(');
  const currentStart=lua.indexOf('local function arcProjection(');
  const starts=[oldStart,curvedStart,currentStart].filter(index=>index>=0);
  const start=starts.length?Math.min(...starts):-1;
  const drawFunction=lua.indexOf('\nlocal function drawShipGuides',start);
  const drawAssignment=lua.indexOf('\ndrawShipGuides=function',start);
  const ends=[drawFunction,drawAssignment].filter(index=>index>=0);
  const end=ends.length?Math.min(...ends):-1;
  if(start<0)throw Error('Could not find an arc helper to update.');
  if(end<0)throw Error('Could not find the end of the old arc helper.');
  lua=lua.slice(0,start)+arcProjection+'\n'+lua.slice(end+1);
}
{
  const start=lua.indexOf('        if state.guideArc then');
  const marker='\n        end\n    end\n    base.setVectorLines';
  const end=lua.indexOf(marker,start);
  if(start<0||end<0)throw Error('Could not find the old arc rendering block.');
  const block=`        if state.guideArc then
            local class=definition(s.definitionId)
            local profile=class and class.arc or "90"
            local ranges={}
            for n=1,3 do ranges[n]=n*RANGE_SEGMENT/((sx+sz)/2) end
            local function addArc(half,center,originHalfWidth,originForwardOffset)
                for _,line in ipairs(arcProjection(half,center,ranges,y,bandColor,hx,hz,originHalfWidth,originForwardOffset)) do table.insert(lines,line) end
            end
            if profile=="360" then
                for n=1,3 do table.insert(lines,edgeRoundedRange(hx,hz,ranges[n],y,bandColor[n])) end
            else
                if profile:match("^180") then addArc(90,0,nil,0) else addArc(45,0) end
                if profile:find("rear90",1,true) then addArc(45,180) end
                -- The 30-degree secondary arc is centered on the ship and its
                -- boundary rays converge at the base center, not its front edge.
                if profile:find("second30",1,true) then addArc(15,0,0,0) end
            end
        end`;
  const closing='\n        end';
  lua=lua.slice(0,start)+block+lua.slice(end+closing.length);
}
if(lua.includes('local function squaredRange(')||lua.includes('local function roundedRange('))throw Error('Could not remove an obsolete range helper.');
if((lua.match(/local function edgeRoundedRange\(/g)||[]).length!==1)throw Error('Could not install one edge-rounded range helper.');
if(lua.includes('local function arcLines('))throw Error('Could not remove the duplicated arc range bands.');
if(!lua.includes('local function arcRangeBand(halfAngle,rear,distance,y,hx,hz,originWidth,originZ)'))throw Error('Could not install edge-measured curved range bands.');
if(!lua.includes('local function arcProjection(halfAngle,center,ranges,y,colors,hx,hz,originHalfWidth,originForwardOffset)'))throw Error('Could not install clean arc projections.');

const fleetImportStart=canonical.indexOf('local FLEET_SHIELD_BAG_GUID=');
const fleetImportEnd=canonical.indexOf('\nfunction STA2E_FleetSpawn',fleetImportStart);
if(fleetImportStart<0||fleetImportEnd<0)throw Error('Could not extract the canonical fleet staging importer.');
{
  const helperStart=lua.indexOf('local FLEET_SHIELD_BAG_GUID=');
  const legacyStart=lua.indexOf('function STA2E_ImportFleet(');
  const start=helperStart>=0?helperStart:legacyStart;
  const end=lua.indexOf('\nfunction STA2E_FleetSpawn',start);
  if(start<0||end<0)throw Error('Could not find the fleet importer to update.');
  lua=lua.slice(0,start)+canonical.slice(fleetImportStart,fleetImportEnd)+lua.slice(end);
}
lua=lua.split('for _,color in ipairs({"Blue","Red"}) do').join('for _,color in ipairs(PLAYER_COLORS) do');
lua=lua.split('Only a seated Red or Blue player may advance the phase.').join('Only a seated fleet player may advance the phase.');
lua=lua.split('Sit in Blue or Red to set up a fleet.').join('Sit in a fleet color to set up a fleet.');
lua=lua.split('<Button id="advance" onClick="STA2E_PhaseUI" position="-108 -17 0" width="205" height="30" fontSize="15">ADVANCE PHASE</Button>')
  .join('<Button id="advance" onClick="STA2E_PhaseUI" tooltip="Left-click: advance | Right-click: previous phase" position="-108 -17 0" width="205" height="30" fontSize="15">ADVANCE PHASE</Button>');
lua=lua.split('function STA2E_PhaseUI(player)').join('function STA2E_PhaseUI(player,value)');
lua=lua.split('oldPhaseUI(player)').join('oldPhaseUI(player,value)');
lua=lua.split('phaseAdvance(player)').join('phaseAdvance(player,value)');
lua=lua.split('return aiOldPhase(player)').join('return aiOldPhase(player,value)');
{
  const phaseStart=lua.indexOf('function STA2E_PhaseUI(player,value)');
  const phaseEnd=lua.indexOf('\nfunction STA2E_PhaseFromDial',phaseStart);
  if(phaseStart<0||phaseEnd<0)throw Error('Could not find the primary phase handler.');
  const phaseSection=lua.slice(phaseStart,phaseEnd);
  if(!phaseSection.includes('local reverse=tostring(value)=="-2"')){
    const gameLine='    local g=STA2E.game';
    const reversePhase=`${gameLine}
    local reverse=tostring(value)=="-2"
    if reverse then
        phaseConfirm={}
        if next(STA2E.pending) or next(STA2E.imports) then tell(player.color,"Wait for spawning to finish.");return end
        if g.phase=="activation" then g.phase="planning"
        elseif g.phase=="combat" then g.phase="activation"
        elseif g.phase=="end" then g.phase="combat"
        elseif g.phase=="planning" then
            if (tonumber(g.round) or 0)>1 then g.round=g.round-1;g.phase="end"
            else g.round=0;g.phase="setup" end
        else tell(player.color,"Setup is the first phase; there is no previous phase.");return end
        for _,s in pairs(STA2E.ships) do refresh(s) end
        hud();return
    end`;
    if(!phaseSection.includes(gameLine))throw Error('Could not find the phase state line.');
    const updated=phaseSection.replace(gameLine,reversePhase);
    lua=lua.slice(0,phaseStart)+updated+lua.slice(phaseEnd);
  }
}
if(!lua.includes('local reverse=tostring(value)=="-2"')||!lua.includes('phaseAdvance(player,value)'))throw Error('Could not install right-click previous-phase handling.');
if(lua.includes('local aiOldPhase=STA2E_PhaseUI')&&!lua.includes('return aiOldPhase(player,value)'))throw Error('AI phase guard did not forward the mouse button value.');
lua=lua.split('local last=math.min(cardIndex+149,#cards)').join('local last=math.min(cardIndex+39,#cards)');
lua=lua.split('Wait.frames(step,10)').join('Wait.time(step,6)');
if(!lua.includes('local last=math.min(cardIndex+39,#cards)')||!lua.includes('Wait.time(step,6)'))throw Error('Could not install join-safe startup throttling.');
if(!lua.includes('name=importedShipName(root)')||!lua.includes('spawnFleetShields(s);deploy(s);refresh(s)'))throw Error('Could not install automatic fleet deployment and class-based generic ship names.');

replaceWhenPresent(
  'rotation={0,role=="dial" and 180 or (sign==1 and 0 or 180),0}',
  'rotation={0,role=="dial" and 180 or (s.spawnRotation or (sign==1 and 0 or 180)),0}');
replaceWhenPresent(
  'local rotation=role=="dial" and dialTransform.rotation or role=="reference" and referenceTransform.rotation or {0,(sign==1 and 0 or 180),0}',
  'local rotation=role=="dial" and dialTransform.rotation or role=="reference" and referenceTransform.rotation or {0,(s.spawnRotation or (sign==1 and 0 or 180)),0}');
if(!lua.includes('s.spawnRotation or (sign==1 and 0 or 180)'))throw Error('Could not install Alliance deployment rotation support.');
replaceWhenPresent(
  'if a.owner~=b.owner then return a.owner==initiative end',
  'if a.owner~=b.owner then\n            if phase=="activation" then return a.owner~=initiative end\n            return a.owner==initiative\n        end');
const stableOwnerSort=`if a.owner~=b.owner then
            local aInitiative=a.owner==initiative;local bInitiative=b.owner==initiative
            if aInitiative~=bInitiative then
                if phase=="activation" then return not aInitiative end
                return aInitiative
            end
            local aOrder=TRACKER_OWNER_ORDER[a.owner] or 99
            local bOrder=TRACKER_OWNER_ORDER[b.owner] or 99
            if aOrder~=bOrder then return aOrder<bOrder end
            return tostring(a.owner)<tostring(b.owner)
        end
        return tostring(a.instanceId)<tostring(b.instanceId)`;
replaceWhenPresent(
  'if a.owner~=b.owner then\n            if phase=="activation" then return a.owner~=initiative end\n            return a.owner==initiative\n        end\n        return a.instanceId<b.instanceId',
  stableOwnerSort);
replaceWhenPresent(
  'if a.owner~=b.owner then\n            -- Equal-skill timing is phase-specific: the initiative player places\n            -- and attacks first, but activates second.\n            if phase=="activation" then return a.owner~=initiative end\n            return a.owner==initiative\n        end\n        return a.instanceId<b.instanceId',
  stableOwnerSort);
replaceWhenPresent('width="380" height="\'..(95+math.max(#ships,1)*46)',
  'width="500" height="\'..(95+math.max(#ships,1)*46)');
replaceWhenPresent('width="380" height="\'..(130+math.max(#ships,1)*46)',
  'width="500" height="\'..(130+math.max(#ships,1)*46)');
const trackerPalette='local TRACKER_PLAYER_COLORS={Blue="#285779",Red="#713839",Green="#2F6A45",Purple="#62427A",Orange="#A45D24",Yellow="#8A741F"}';
if(!lua.includes(trackerPalette)){
  const sidebarAt=lua.indexOf('local function sidebar()');
  if(sidebarAt<0)throw Error('Could not find the tracker sidebar for the player-color palette.');
  lua=lua.slice(0,sidebarAt)+trackerPalette+'\n'+lua.slice(sidebarAt);
}
const trackerOwnerOrder='local TRACKER_OWNER_ORDER={Blue=1,Red=2,Green=3,Purple=4,Orange=5,Yellow=6}';
if(!lua.includes(trackerOwnerOrder))lua=lua.replace(trackerPalette,trackerPalette+'\n'+trackerOwnerOrder);
if(!lua.includes('local aOrder=TRACKER_OWNER_ORDER[a.owner] or 99')&&!lua.includes('local function trackerBefore(a,b)'))throw Error('Could not install stable multi-owner tracker ordering.');
const comparatorTrackerSort=`table.sort(ships,function(a,b)
        local x,y=skillFor(a),skillFor(b)
        if x~=y then return phase=="combat" and x>y or (phase~="combat" and x<y) end
        local initiative=STA2E.game.initiative or "Blue"
        ${stableOwnerSort}
    end)`;
const safeTrackerSort=`local initiative=STA2E.game.initiative or "Blue"
    local ordered={}
    for ordinal,s in ipairs(ships) do
        local skill=tonumber(skillFor(s)) or 0;if skill~=skill then skill=0 end
        local initiativeOrder
        if phase=="activation" then initiativeOrder=s.owner==initiative and 1 or 0
        else initiativeOrder=s.owner==initiative and 0 or 1 end
        table.insert(ordered,{ship=s,skillOrder=phase=="combat" and -skill or skill,
            initiativeOrder=initiativeOrder,ownerOrder=TRACKER_OWNER_ORDER[s.owner] or 99,
            instanceId=tostring(s.instanceId or ""),ordinal=ordinal})
    end
    local function trackerBefore(a,b)
        if a.skillOrder~=b.skillOrder then return a.skillOrder<b.skillOrder end
        if a.initiativeOrder~=b.initiativeOrder then return a.initiativeOrder<b.initiativeOrder end
        if a.ownerOrder~=b.ownerOrder then return a.ownerOrder<b.ownerOrder end
        if a.instanceId~=b.instanceId then return a.instanceId<b.instanceId end
        return a.ordinal<b.ordinal
    end
    for i=2,#ordered do
        local entry=ordered[i];local j=i-1
        while j>=1 and trackerBefore(entry,ordered[j]) do ordered[j+1]=ordered[j];j=j-1 end
        ordered[j+1]=entry
    end
    ships={};for _,entry in ipairs(ordered) do table.insert(ships,entry.ship) end`;
replaceWhenPresent(comparatorTrackerSort,safeTrackerSort);
if(!lua.includes('local function trackerBefore(a,b)')||lua.includes('table.sort(ships,function'))throw Error('Could not install comparator-free tracker ordering.');
replaceWhenPresent(
  'local shade=s.owner=="Red" and "#713839" or "#285779"',
  'local shade=s.ai and "#5C4678" or (TRACKER_PLAYER_COLORS[s.owner] or "#48515D")');
replaceWhenPresent(
  'local shade=s.ai and "#5C4678" or (s.owner=="Red" and "#713839" or "#285779")',
  'local shade=s.ai and "#5C4678" or (TRACKER_PLAYER_COLORS[s.owner] or "#48515D")');
if(!lua.includes('local shade=s.ai and "#5C4678" or (TRACKER_PLAYER_COLORS[s.owner] or "#48515D")'))throw Error('Could not install six-player tracker row colors.');
replaceOne(
  "table.insert(parts,'<Button id=\"focus_'..xml(s.instanceId)..'\" onClick=\"STA2E_SidebarClick\" position=\"-40 '..y..' 0\" width=\"265\" height=\"38\" fontSize=\"14\" color=\"'..shade..'\" textColor=\"#FFFFFF\">'..xml(tostring(skillFor(s))..' | '..name..' | '..s.name..' ['..marker..']')..'</Button>')",
  "local rowName=s.ai and (\"AI · \"..s.name) or (name..\" | \"..s.name)\n        table.insert(parts,'<Button id=\"focus_'..xml(s.instanceId)..'\" onClick=\"STA2E_SidebarClick\" position=\"-40 '..y..' 0\" width=\"265\" height=\"38\" fontSize=\"14\" color=\"'..shade..'\" textColor=\"#FFFFFF\">'..xml(tostring(skillFor(s))..' | '..rowName..' ['..marker..']')..'</Button>')",
  'AI row label');
replaceOne(
  "table.insert(parts,'<Button id=\"fire_'..xml(s.instanceId)..'\" onClick=\"STA2E_SidebarClick\" position=\"166 '..y..' 0\" width=\"27\" height=\"38\" fontSize=\"14\">F</Button>')",
  "table.insert(parts,'<Button id=\"fire_'..xml(s.instanceId)..'\" onClick=\"STA2E_SidebarClick\" position=\"166 '..y..' 0\" width=\"27\" height=\"38\" fontSize=\"14\">F</Button>')\n        if s.ai then table.insert(parts,'<Button id=\"activate_ai_'..xml(s.instanceId)..'\" onClick=\"STA2E_SidebarClick\" position=\"222 '..y..' 0\" width=\"78\" height=\"38\" fontSize=\"12\" color=\"#2B7651\" textColor=\"#FFFFFF\">ACT AI</Button>') end",
  'AI activation button');
replaceOne(
  "    local action,actionId=id and id:match('^(skill_down)_(.+)$')",
  "    local aiId=id and id:match('^activate_ai_(.+)$')\n    if aiId then STA2E_AllianceActivateAI({instanceId=aiId,color=player and player.color});return end\n    local action,actionId=id and id:match('^(skill_down)_(.+)$')",
  'AI tracker handler');

if(lua.includes('-- Alliance mission framework.')){
  const start=lua.indexOf('-- Alliance mission framework.');
  const end=lua.indexOf('local phaseReconcile=STA2E_Reconcile',start);
  if(end<0)throw Error('Existing Alliance controller has no end marker.');
  lua=lua.slice(0,start)+allianceModule+lua.slice(end);
}else{
  const insertion=lua.lastIndexOf('local phaseReconcile=STA2E_Reconcile');
  if(insertion<0)throw Error('Could not find the Alliance controller insertion point.');
  lua=lua.slice(0,insertion)+allianceModule+lua.slice(insertion);
}
if(!lua.includes('if STA2E.game.phase=="planning" then STA2E_AllianceProcessRound() end')){
  const phaseStart=lua.indexOf('local phaseAdvance=STA2E_PhaseUI');
  const nextSection=Math.min(...[lua.indexOf('\n-- Physical dice',phaseStart),lua.indexOf('\nfunction onLoad(saved)',phaseStart)].filter(i=>i>=0));
  const phaseEnd=lua.lastIndexOf('\nend',nextSection);
  if(phaseStart<0||phaseEnd<0)throw Error('Could not find the final phase wrapper.');
  lua=lua.slice(0,phaseEnd)+'\n    if STA2E.game.phase=="planning" then STA2E_AllianceProcessRound() end'+lua.slice(phaseEnd);
}
if(!lua.includes('STA2E.loading=false\n            STA2E_AllianceProcessRound()')){
  const loadNeedle='            STA2E_Reconcile()\n            STA2E.loading=false\n            hud()';
  const loadAt=lua.lastIndexOf(loadNeedle);
  if(loadAt<0)throw Error('Could not find the final load event hook.');
  const replacement='            STA2E_Reconcile()\n            STA2E.loading=false\n            STA2E_AllianceProcessRound()\n            hud()';
  lua=lua.slice(0,loadAt)+replacement+lua.slice(loadAt+loadNeedle.length);
}

// AI Prototype v0.4 integration: lead higher-skill targets and evaluate the
// physical maneuver path before accepting the chart's preferred maneuver.
if(lua.includes('local AllianceAI={version="0.4"')){
  replaceWhenPresent(
    'function AllianceAI.vectorHand(aiBoundary,targetBoundary)\n -- Toward the target\'s course line, not its current position. Project the AI\n -- center onto that line; no hidden maneuver or target speed is consulted.\n local a=math.rad(targetBoundary.yaw)\n local fx,fz=-math.sin(a),-math.cos(a)\n local dx,dz=aiBoundary.center.x-targetBoundary.center.x,aiBoundary.center.z-targetBoundary.center.z\n local along=dx*fx+dz*fz\n local point={x=targetBoundary.center.x+along*fx,z=targetBoundary.center.z+along*fz}\n local x=worldToLocal(aiBoundary,point)\n if math.abs(x)<0.02 then return nil end\n return x>0 and "R" or "L"\nend',
    'function AllianceAI.vectorHand(aiBoundary,targetBoundary,previousHand)\n -- Choose by the target\'s signed bearing from the AI ship. A small dead zone\n -- retains the prior hand so nearly aligned ships do not alternate left/right.\n local x=worldToLocal(aiBoundary,targetBoundary.center)\n local halfWidth=(aiBoundary.footprint and aiBoundary.footprint.halfWidth) or 1.4\n local deadZone=math.max(0.18,halfWidth*0.12)\n if math.abs(x)<=deadZone then return previousHand end\n return x>0 and "R" or "L"\nend');
  replaceWhenPresent(
    ' -- v0.3: mirror left/right only at the AI chart-to-dial lookup.\n hand=hand and (hand=="L" and "R" or "L")',
    ' -- Maneuver keys already use pilot-facing left/right; no extra mirror is needed.');
  replaceWhenPresent(
    ' local toward=s.ai.hand\n if not toward then\n  if found.centerTarget then\n   -- Center has no course vector: turn toward its bearing. Symmetric alignment\n   -- uses a fixed side only if the table needs a directional maneuver.\n   local x=worldToLocal(m.attackerBoundary,m.targetBoundary.center)\n   toward=x>0 and "R" or "L"\n  else toward=AllianceAI.vectorHand(m.attackerBoundary,m.targetBoundary) end\n end',
    ' local toward=s.ai.hand\n if not toward then\n  local marker=string.byte(tostring(s.instanceId or s.name or "AI"),-1) or 0\n  local stableHand=s.ai.lastHand or (marker%2==0 and "L" or "R")\n  toward=AllianceAI.vectorHand(m.attackerBoundary,m.targetBoundary,stableHand)\n end\n if toward then s.ai.lastHand=toward end');
  replaceWhenPresent(
    ' local aspect,group\n if found.centerTarget then aspect,group="Approaching / Front","front"\n else aspect,group=AllianceAI.aspect(m.targetBoundary,m.attackerBoundary.center) end',
    ' -- Steering is AI-centric: target facing does not change the maneuver row.\n local aspect=found.centerTarget and "Board Center" or "Direct Approach"\n local group="front"');
  if(lua.includes('hand=hand and (hand=="L" and "R" or "L")'))throw Error('Could not remove the obsolete AI left/right mirror.');
  if(!lua.includes('local x=worldToLocal(aiBoundary,targetBoundary.center)'))throw Error('Could not install direct-bearing AI steering.');
  if(!lua.includes('local stableHand=s.ai.lastHand'))throw Error('Could not install stable AI steering hand.');
  if(!lua.includes('local aspect=found.centerTarget and "Board Center" or "Direct Approach"'))throw Error('Could not install simplified AI approach logic.');
  const aiHelpers=`local AI_TARGET_LEAD=3.0
local function aiProjectedMeasure(s,target,measure)
 if not measure or skillFor(target)<=skillFor(s) then return measure,false end
 local source=measure.targetBoundary
 local projected={center={x=source.center.x,z=source.center.z},yaw=source.yaw or 0,points={}}
 local yaw=math.rad(projected.yaw or 0)
 local dx,dz=-math.sin(yaw)*AI_TARGET_LEAD,-math.cos(yaw)*AI_TARGET_LEAD
 projected.center={x=projected.center.x+dx,z=projected.center.z+dz}
 projected.points={}
 for _,point in ipairs(measure.targetBoundary.points or {}) do table.insert(projected.points,{x=point.x+dx,z=point.z+dz}) end
 local nearest=MeasurementGeometry.nearestPoints(measure.attackerBoundary,projected)
 return {range=math.max(1,math.min(3,math.ceil(nearest.distance/RANGE_SEGMENT))),baseEdgeDistance=nearest.distance,
  attackerBoundary=measure.attackerBoundary,targetBoundary=projected,nearest=nearest},true
end
local function aiAngleDistance(a,b) return math.abs(((a-b+180)%360)-180) end
local function aiAssessMove(s,entry,targetBoundary,preferredKey)
 local base=member(s,"base");local move=entry and MOVE_DEFS[entry.key]
 if not base or not move then return nil end
 local p,r=base.getPosition(),base.getRotation();local start={x=p.x,z=p.z,yaw=r.y};local shape=baseShape(base)
 local blockers={};local terrain=terrainSnapshot(base)
 for id,other in pairs(STA2E.ships) do if id~=s.instanceId then
  local otherBase=member(other,"base");if otherBase then local op,orr=otherBase.getPosition(),otherBase.getRotation()
   table.insert(blockers,{pose={x=op.x,z=op.z,yaw=orr.y},shape=baseShape(otherBase),reason="ship"}) end end end
 for _,item in ipairs(terrain) do if item.kind=="planet" then table.insert(blockers,{pose=item.pose,shape=item.shape,reason="planet"}) end end
 local stop,stopReason=latestLegal(start,move,shape,blockers);local finish=pose(start,move,stop)
 local hits=movementTerrainHits(start,move,stop,shape,terrain);local hazards={};local penalty=0
 if stopReason=="planet" then penalty=penalty+100;table.insert(hazards,"planet landing")
 elseif stop<0.999 then penalty=penalty+7+(1-stop)*18;table.insert(hazards,"ship bump") end
 for _,hit in ipairs(hits) do
  local cost=hit.kind=="minefield" and 18 or 11
  if hit.finalOverlap then cost=cost+7 end
  penalty=penalty+cost;table.insert(hazards,hit.label)
 end
 local board=AllianceAI.boardCenter or {x=0,z=0};local edge=math.max(math.abs(finish.x-board.x),math.abs(finish.z-board.z))
 if edge>18 then penalty=penalty+80+(edge-18)*20;table.insert(hazards,"battlefield edge")
 elseif edge>16.5 then penalty=penalty+12+(edge-16.5)*4;table.insert(hazards,"battlefield edge") end
 local target=targetBoundary.center;local dx,dz=target.x-finish.x,target.z-finish.z
 local distance=math.sqrt(dx*dx+dz*dz);local desired=math.deg(math.atan2(-dx,-dz))
 if s.ai.intent=="escape" then desired=desired+180 end
 local startBoundary=MeasurementGeometry.boundary(s)
 if startBoundary then
  local targetX=worldToLocal(startBoundary,target);local finishX=worldToLocal(startBoundary,{x=finish.x,z=finish.z})
  if s.ai.intent=="escape" then targetX=-targetX end
  if math.abs(targetX)>0.25 and finishX*targetX<0 then penalty=penalty+16;table.insert(hazards,"wrong-way veer") end
 end
 local tactical=(s.ai.intent=="escape" and -distance or distance)+aiAngleDistance(finish.yaw,desired)*0.06
 local preference=entry.key==preferredKey and 0 or 3.5
 return {entry=entry,score=tactical+preference+penalty,penalty=penalty,hazards=hazards,stop=stop}
end
local function aiObstacleChoice(s,preferred,targetBoundary)
 local choices={}
 for _,candidate in ipairs(dialFor(s)) do
  if MOVE_DEFS[candidate.key] then local result=aiAssessMove(s,candidate,targetBoundary,preferred.key);if result then table.insert(choices,result) end end
 end
 table.sort(choices,function(a,b) if math.abs(a.score-b.score)>0.0001 then return a.score<b.score end return a.entry.key<b.entry.key end)
 local selected=choices[1];if not selected then return preferred,nil end
 local preferredResult
 for _,choice in ipairs(choices) do if choice.entry.key==preferred.key then preferredResult=choice;break end end
 if preferredResult and preferredResult.penalty<=0 then return preferred,nil end
 local note
 if selected.entry.key~=preferred.key then
  note="avoids "..table.concat((preferredResult and preferredResult.hazards) or {},", ")
 elseif selected.penalty>0 then note="accepts "..table.concat(selected.hazards,", ").." as the better route" end
 return selected.entry,note
end
`;
  if(!lua.includes('local AI_TARGET_LEAD=3.0')){
    const selectAt=lua.indexOf('local function aiSelect(s)',lua.indexOf('local AllianceAI={version="0.4"'));
    if(selectAt<0)throw Error('Could not find the AI target selector.');
    lua=lua.slice(0,selectAt)+aiHelpers+lua.slice(selectAt);
  }
  replaceWhenPresent(
    ' local target=targetBoundary.center;local dx,dz=target.x-finish.x,target.z-finish.z\n local distance=math.sqrt(dx*dx+dz*dz);local desired=math.deg(math.atan2(-dx,-dz))\n if s.ai.intent=="escape" then desired=desired+180 end\n local tactical=(s.ai.intent=="escape" and -distance or distance)+aiAngleDistance(finish.yaw,desired)*0.025\n local preference=entry.key==preferredKey and 0 or 2.5\n return {entry=entry,score=tactical+preference+penalty,penalty=penalty,hazards=hazards,stop=stop}',
    ' local board=AllianceAI.boardCenter or {x=0,z=0};local edge=math.max(math.abs(finish.x-board.x),math.abs(finish.z-board.z))\n if edge>18 then penalty=penalty+80+(edge-18)*20;table.insert(hazards,"battlefield edge")\n elseif edge>16.5 then penalty=penalty+12+(edge-16.5)*4;table.insert(hazards,"battlefield edge") end\n local target=targetBoundary.center;local dx,dz=target.x-finish.x,target.z-finish.z\n local distance=math.sqrt(dx*dx+dz*dz);local desired=math.deg(math.atan2(-dx,-dz))\n if s.ai.intent=="escape" then desired=desired+180 end\n local startBoundary=MeasurementGeometry.boundary(s)\n if startBoundary then\n  local targetX=worldToLocal(startBoundary,target);local finishX=worldToLocal(startBoundary,{x=finish.x,z=finish.z})\n  if s.ai.intent=="escape" then targetX=-targetX end\n  if math.abs(targetX)>0.25 and finishX*targetX<0 then penalty=penalty+16;table.insert(hazards,"wrong-way veer") end\n end\n local tactical=(s.ai.intent=="escape" and -distance or distance)+aiAngleDistance(finish.yaw,desired)*0.06\n local preference=entry.key==preferredKey and 0 or 3.5\n return {entry=entry,score=tactical+preference+penalty,penalty=penalty,hazards=hazards,stop=stop}');
  if(!lua.includes('if math.abs(targetX)>0.25 and finishX*targetX<0 then penalty=penalty+16;table.insert(hazards,"wrong-way veer") end'))throw Error('Could not install geometric toward/away preservation.');
  if(!lua.includes('table.insert(hazards,"battlefield edge")'))throw Error('Could not install AI battlefield-edge avoidance.');
  replaceWhenPresent(
    ' local projected=copy(measure.targetBoundary)\n local yaw=math.rad(projected.yaw or 0)',
    ' local source=measure.targetBoundary\n local projected={center={x=source.center.x,z=source.center.z},yaw=source.yaw or 0,points={}}\n local yaw=math.rad(projected.yaw or 0)');
  if(lua.includes('local projected=copy(measure.targetBoundary)'))throw Error('Could not remove userdata from the projected target copy.');
  if(!lua.includes('local AI_ACQUISITION_DISTANCE=24.0')){
    const selectAt=lua.indexOf('local function aiSelect(s)',lua.indexOf('local AllianceAI={version="0.4"'));
    if(selectAt<0)throw Error('Could not find the AI target selector for acquisition range.');
    lua=lua.slice(0,selectAt)+'local AI_ACQUISITION_DISTANCE=24.0\n'+lua.slice(selectAt);
  }
  replaceWhenPresent(
    '   local measure=MeasurementGeometry.measure(s,target)\n   if measure and measure.range<=3 then\n    table.insert(found,{target=target,measure=measure,zone=AllianceAI.zone(measure.attackerBoundary,measure.targetBoundary.center)})\n   end',
    '   local measure=MeasurementGeometry.measure(s,target)\n   if measure and measure.baseEdgeDistance<=AI_ACQUISITION_DISTANCE then\n    local projected,lead=aiProjectedMeasure(s,target,measure)\n    table.insert(found,{target=target,measure=projected,projected=lead,zone=AllianceAI.zone(projected.attackerBoundary,projected.targetBoundary.center)})\n   end');
  replaceWhenPresent(
    '   local measure=MeasurementGeometry.measure(s,target)\n   if measure and measure.range<=3 then\n    local projected,lead=aiProjectedMeasure(s,target,measure)',
    '   local measure=MeasurementGeometry.measure(s,target)\n   if measure and measure.baseEdgeDistance<=AI_ACQUISITION_DISTANCE then\n    local projected,lead=aiProjectedMeasure(s,target,measure)');
  replaceWhenPresent(
    ' local entry,fallback=AllianceAI.resolve(dialFor(s),instruction,hand)\n if not entry then s.ai.plan=nil;s.ai.message="Manual decision: "..fallback;return end\n s.ai.plan={key=entry.key,targetId=found.target.instanceId,centerTarget=found.centerTarget or false,center=found.centerTarget and copy(AllianceAI.boardCenter) or nil,zone=found.zone,range=range,aspect=aspect,instruction=copy(instruction),hand=hand,fallback=fallback,round=STA2E.game.round,intent=s.ai.intent,source=aiSnapshot(s),target=not found.centerTarget and aiSnapshot(found.target) or nil}\n s.ai.message=found.target.name.." | Zone "..found.zone.." | Range "..range.." | "..aspect.."\\n"..string.upper(s.ai.intent)..": "..instruction.speed.." "..instruction.family.." "..(instruction.direction or "").." → "..maneuverLabel(s,entry.key)..(fallback and " (fallback)" or "")',
    ' local entry,fallback=AllianceAI.resolve(dialFor(s),instruction,hand)\n if not entry then s.ai.plan=nil;s.ai.message="Manual decision: "..fallback;return end\n local avoidance;entry,avoidance=aiObstacleChoice(s,entry,m.targetBoundary)\n s.ai.plan={key=entry.key,targetId=found.target.instanceId,centerTarget=found.centerTarget or false,center=found.centerTarget and copy(AllianceAI.boardCenter) or nil,zone=found.zone,range=range,aspect=aspect,instruction=copy(instruction),hand=hand,fallback=fallback,projected=found.projected or false,avoidance=avoidance,round=STA2E.game.round,intent=s.ai.intent,source=aiSnapshot(s),target=not found.centerTarget and aiSnapshot(found.target) or nil}\n s.ai.message=found.target.name..(found.projected and " | Lead +3" or "").." | Zone "..found.zone.." | Range "..range.." | "..aspect.."\\n"..string.upper(s.ai.intent)..": "..instruction.speed.." "..instruction.family.." "..(instruction.direction or "").." → "..maneuverLabel(s,entry.key)..(fallback and " (fallback)" or "")..(avoidance and " · "..avoidance or "")');
  if(!lua.includes('local avoidance;entry,avoidance=aiObstacleChoice'))throw Error('Could not install AI obstacle selection.');
  if(!lua.includes('local projected,lead=aiProjectedMeasure'))throw Error('Could not install AI target projection.');
  replaceWhenPresent(
    ' local range=math.max(1,m.range)\n local instruction=AllianceAI.behavior[found.zone][range][group][s.ai.intent]',
    ' local actualRange=math.max(1,m.range)\n local range=math.min(3,actualRange)\n local instruction=AllianceAI.behavior[found.zone][range][group][s.ai.intent]');
  replaceWhenPresent('zone=found.zone,range=range,aspect=aspect','zone=found.zone,range=actualRange,tacticalRange=range,aspect=aspect');
  replaceWhenPresent('" | Range "..range.." | "..aspect','" | Range "..actualRange.." | "..aspect');
  if(!lua.includes('measure.baseEdgeDistance<=AI_ACQUISITION_DISTANCE'))throw Error('Could not install the 24-inch AI acquisition range.');
  if(!lua.includes('local range=math.min(3,actualRange)'))throw Error('Could not clamp long-range targets to the approach behavior band.');

  const actionHelpers=`AllianceAI.actionEvaluators=AllianceAI.actionEvaluators or {}
function AllianceAI.registerActionEvaluator(key,evaluator) AllianceAI.actionEvaluators[key]=evaluator end
local function aiHasToken(s,key)
 for _,object in ipairs(getAllObjects()) do if object.getGMNotes()=="STA2E_SHIP_TOKEN|"..s.instanceId.."|"..key then return true end end
 return false
end
local function aiActionContext(s)
 local selected=aiSelect(s);local target=selected and selected.target or nil
 local measure=target and MeasurementGeometry.measure(s,target) or nil
 local enemyIn12=target and measure and measure.baseEdgeDistance<=12.0 or false
 local attack=measure and measure.range<=3 and (measure.arcs.primary or measure.arcs.rear or measure.arcs.secondary) or false
 local threats=0
 for id,enemy in pairs(STA2E.ships) do if id~=s.instanceId and aiSide(enemy)~=aiSide(s) then
  local incoming=MeasurementGeometry.measure(enemy,s)
  if incoming and incoming.range<=3 and (incoming.arcs.primary or incoming.arcs.rear or incoming.arcs.secondary) then threats=threats+1 end
 end end
 local cloaked=target and (target.state and target.state.action=="CLK" or aiHasToken(target,"CLK")) or false
 return {target=target,measure=measure,enemyIn12=enemyIn12,meaningfulAttack=attack,threats=threats,cloakedTarget=cloaked,
  higherSkill=target and skillFor(target)>skillFor(s) or false,intent=s.ai.intent or "engage"}
end
AllianceAI.registerActionEvaluator("BS",function(s,c)
 if not c.target then return nil end
 local score=70+(c.meaningfulAttack and 15 or 0)+(c.measure and c.measure.range==1 and 10 or 0)+math.min(c.threats,2)*3
 return score,"attack and defense flexibility"
end)
AllianceAI.registerActionEvaluator("TL",function(s,c)
 if not c.target or not c.enemyIn12 or aiHasToken(s,"TL") then return nil end
 local score=78+((c.measure and c.measure.range>=2) and 10 or 0)+(c.meaningfulAttack and 4 or 0)
 return score,"target available at Range "..tostring(c.measure and c.measure.range or "?")
end)
AllianceAI.registerActionEvaluator("EVA",function(s,c)
 if aiHasToken(s,"EVA") then return nil end
 local score=45+c.threats*12+(c.intent=="escape" and 15 or 0)+(c.higherSkill and 10 or 0)
 return score,c.threats>0 and (tostring(c.threats).." incoming firing solution(s)") or "defensive fallback"
end)
AllianceAI.registerActionEvaluator("SCN",function(s,c)
 if aiHasToken(s,"SCN") then return nil end
 if not c.enemyIn12 then return 38,"no enemy within 12; sensor sweep" end
 return 35+(c.cloakedTarget and 55 or 0)+(c.meaningfulAttack and 5 or 0),c.cloakedTarget and "target is cloaked" or "target acquisition support"
end)
AllianceAI.registerActionEvaluator("CLK",function(s,c)
 if aiHasToken(s,"CLK") then return nil end
 return 50+c.threats*10,"reduce incoming threat"
end)
AllianceAI.registerActionEvaluator("REG",function(s,c)
 if aiHasToken(s,"REG") then return nil end
 return 25,"regeneration available; damage state is manual"
end)
function STA2E_AllianceChooseAction(params)
 local s=params and params.ship;if not s or not (s.ai and s.ai.enabled) then return nil end
 local context=aiActionContext(s);local candidates={}
 for _,key in ipairs((s.capabilities and s.capabilities.actions) or {}) do
  local evaluator=AllianceAI.actionEvaluators[key]
  if evaluator and (key=="ECHO" or obj(ACTION_BAGS[key])) then
   local score,reason=evaluator(s,context)
   if score then table.insert(candidates,{key=key,score=score,reason=reason}) end
  end
 end
 table.sort(candidates,function(a,b) if a.score~=b.score then return a.score>b.score end return a.key<b.key end)
 local selected=candidates[1]
 if selected then selected.target=context.target;selected.context=context end
 return selected
end
`;
  if(!lua.includes('AllianceAI.actionEvaluators=AllianceAI.actionEvaluators or {}')){
    const afterMoveAt=lua.indexOf('function STA2E_AI_AfterMove(s,key)',lua.indexOf('local AllianceAI={version="0.4"'));
    if(afterMoveAt<0)throw Error('Could not find the AI post-move hook.');
    lua=lua.slice(0,afterMoveAt)+actionHelpers+lua.slice(afterMoveAt);
  }
  replaceWhenPresent(
    ' local measure=target and MeasurementGeometry.measure(s,target) or nil\n local attack=measure and measure.range<=3',
    ' local measure=target and MeasurementGeometry.measure(s,target) or nil\n local enemyIn12=target and measure and measure.baseEdgeDistance<=12.0 or false\n local attack=measure and measure.range<=3');
  replaceWhenPresent(
    'return {target=target,measure=measure,meaningfulAttack=attack,threats=threats,cloakedTarget=cloaked,',
    'return {target=target,measure=measure,enemyIn12=enemyIn12,meaningfulAttack=attack,threats=threats,cloakedTarget=cloaked,');
  replaceWhenPresent(
    'if not c.target or aiHasToken(s,"TL") then return nil end',
    'if not c.target or not c.enemyIn12 or aiHasToken(s,"TL") then return nil end');
  replaceWhenPresent(
    'AllianceAI.registerActionEvaluator("SCN",function(s,c)\n if not c.target or aiHasToken(s,"SCN") then return nil end\n return 35+(c.cloakedTarget and 55 or 0)+(c.meaningfulAttack and 5 or 0),c.cloakedTarget and "target is cloaked" or "target acquisition support"\nend)',
    'AllianceAI.registerActionEvaluator("SCN",function(s,c)\n if aiHasToken(s,"SCN") then return nil end\n if not c.enemyIn12 then return 38,"no enemy within 12; sensor sweep" end\n return 35+(c.cloakedTarget and 55 or 0)+(c.meaningfulAttack and 5 or 0),c.cloakedTarget and "target is cloaked" or "target acquisition support"\nend)');
  if(!lua.includes('local enemyIn12=target and measure and measure.baseEdgeDistance<=12.0 or false'))throw Error('Could not install the AI 12-inch action-target check.');
  if(!lua.includes('if not c.target or not c.enemyIn12 or aiHasToken(s,"TL") then return nil end'))throw Error('Could not restrict AI Target Lock to a real nearby enemy.');
  if(!lua.includes('if not c.enemyIn12 then return 38,"no enemy within 12; sensor sweep" end'))throw Error('Could not install the no-target Scan fallback.');
  replaceWhenPresent(
    'function STA2E_AI_AfterMove(s,key)\n if not (s.ai and s.ai.enabled) then return end\n local entry=maneuver(s,key)\n if entry and entry.difficulty=="red" then\n  local tokens=aiAuxTokens(s)\n  if tokens[1] then\n   if s.undo then s.undo.aiRemovedAux=tokens[1].getData() end\n   tokens[1].destruct()\n  end\n  s.state.aiSkipAction=true;s.state.status="complete"\n  broadcastToAll("[AI] "..s.name..": red maneuver; "..(#tokens>0 and "removed 1 Aux" or "no Aux to remove").."; normal action skipped.",{1,0.7,0.3})\n end\n s.ai.plan=nil\nend',
    'function STA2E_AI_AfterMove(s,key)\n if not (s.ai and s.ai.enabled) then return end\n local entry=maneuver(s,key)\n if entry and entry.difficulty=="red" then\n  local tokens=aiAuxTokens(s)\n  if tokens[1] then\n   if s.undo then s.undo.aiRemovedAux=tokens[1].getData() end\n   tokens[1].destruct()\n  end\n  s.state.aiSkipAction=true;s.state.status="complete";s.ai.plan=nil\n  broadcastToAll("[AI] "..s.name..": red maneuver; "..(#tokens>0 and "removed 1 Aux" or "no Aux to remove").."; normal action skipped.",{1,0.7,0.3})\n  return\n end\n local choice=STA2E_AllianceChooseAction({ship=s})\n if choice then\n  spawnActionToken(s,choice.key);s.state.action=choice.key;s.state.status="complete"\n  s.ai.lastAction={key=choice.key,score=choice.score,reason=choice.reason,round=STA2E.game.round}\n  broadcastToAll("[AI] "..s.name.." action: "..choice.key.." - "..choice.reason..".",{0.75,0.85,1})\n else\n  broadcastToAll("[AI] "..s.name..": no useful automatic action; use the dial for manual or card-granted actions.",{1,0.75,0.35})\n end\n s.ai.plan=nil\nend');
  if(!lua.includes('local choice=STA2E_AllianceChooseAction({ship=s})'))throw Error('Could not install automatic AI action selection.');
}
save.LuaScript=lua;

function walk(objects,callback){for(const object of objects||[]){if(callback(object))return object;const nested=walk(object.ContainedObjects,callback);if(nested)return nested;if(object.States){const state=walk(Object.values(object.States),callback);if(state)return state}}}
let chip=walk(save.ObjectStates,o=>o.GUID==='a1c1f1');
if(!chip){
  const template=walk(save.ObjectStates,o=>o.GUID==='0da48d')||walk(save.ObjectStates,o=>o.Name==='Custom_Token');
  if(!template)throw Error('No custom token is available as a mission-chip template.');
  chip=JSON.parse(JSON.stringify(template));
  chip.GUID='a1c1f1';
  save.ObjectStates.push(chip);
}
chip.Name='Custom_Token';
chip.Nickname='Alliance Act I — A Simple Patrol';
chip.Description='Choose 2–6 players and Regular/Advanced, then start the mission.';
chip.Transform={posX:68,posY:1.2,posZ:31,rotX:0,rotY:180,rotZ:0,scaleX:2.2,scaleY:1,scaleZ:2.2};
chip.Locked=true;chip.LuaScript=chipScript;chip.LuaScriptState='';chip.XmlUI='';chip.ContainedObjects=[];delete chip.States;
chip.CustomImage={ImageURL:missionStartTokenImage,ImageSecondaryURL:'',ImageScalar:1,WidthScale:0,CustomToken:{Thickness:0.1,MergeDistancePixels:15,StandUp:false,Stackable:false}};

const backup=savePath+'.pre-alliance-framework.bak';
if(!fs.existsSync(backup))fs.copyFileSync(savePath,backup);
fs.writeFileSync(savePath,JSON.stringify(save,null,2));
console.log(`Installed Alliance framework and A1M1 chip in ${savePath}`);
console.log(`Backup: ${backup}`);
