-- Website-owned fleet construction. TTS consumes IDs and recomputes totals;
-- imported JSON cannot install executable effects or override profile values.
local function profileById(id)
    for _,p in ipairs(M5.CATALOG.ships or {}) do if p.id==id then return p end end
end
local function installCatalog()
    for _,p in ipairs(M5.CATALOG.ships or {}) do
        local original=CATALOG[p.physicalShipId]
        if original then
            local card=copy(original);card.id=p.id;card.name="M5 "..p.name;card.cost=p.baseThreat;card.m5Profile=p.profileId
            CATALOG[p.id]=card;CATALOG_ORDINAL[p.id]=CATALOG_ORDINAL[p.physicalShipId]
            SHIP_DEFINITIONS[p.id]=SHIP_DEFINITIONS[p.physicalShipId]
        end
        for _,program in ipairs(M5.CATALOG.programs or {}) do
            if original then
                CATALOG[program.id]={id=program.id,name=program.name,type="m5-program",cost=program.threat,
                    cardImage=original.cardBack,cardBack=original.cardBack,m5Program=true}
            end
        end
    end
end
local priorReconcile=STA2E_Reconcile
function STA2E_Reconcile()
    installCatalog()
    return priorReconcile()
end
local originalCardData=cardData
cardData=function(card)
    if card and card.m5Program then return programCardData(M5.PROGRAMS[card.id],M5.SHIP_PROFILES.neghvar) end
    return originalCardData(card)
end

local function validateM5(fleet)
    local isM5=fleet and fleet.source and fleet.source.kind=="remodulated-m5"
    local anyM5=false
    if type(fleet)~="table" or not array(fleet.ships) then return nil end
    for _,ship in ipairs(fleet.ships) do if type(ship)=="table" and profileById(ship.shipCardId) then anyM5=true end end
    if not isM5 and not anyM5 then return nil end
    if not isM5 or fleet.source.m5Version~=1 then return "Use an M5 version 1 JSON export from staw-remodulated." end
    if type(fleet.fleetId)~="string" or not fleet.fleetId:match('^m5%-[%w%-]+$') or #fleet.fleetId>83 then return "Invalid M5 fleet identity." end
    if #fleet.ships<1 or #fleet.ships>3 then return "Provide 1–3 M5 ships, one per row." end
    if not array(fleet.resources or {}) or #(fleet.resources or {})>0 then return "Normal resources are not supported in M5 fleets." end
    for _,ship in ipairs(fleet.ships) do
        if type(ship)~="table" then return "Invalid M5 ship." end
        local p=profileById(ship.shipCardId)
        if not p or not array(ship.cards) then return "Unknown M5 ship or invalid program list." end
        local programs,seen={},{}
        for _,entry in ipairs(ship.cards) do
            if type(entry)~="table" or not M5.PROGRAMS[entry.cardId] then return "Unknown M5 program." end
            if seen[entry.cardId] or entry.hidden then return "Duplicate or hidden M5 programs are not supported." end
            seen[entry.cardId]=true;table.insert(programs,entry.cardId)
        end
        local profile,err=M5.profile({profileId=p.profileId,programs=programs})
        if not profile then return err end
    end
end
local originalReview=reviewFleet
reviewFleet=function(fleet)
    local err=validateM5(fleet);if err then return nil,err end
    return originalReview(fleet)
end
local originalLayout=fleetLayout
fleetLayout=function(fleet)
    if not (fleet.source and fleet.source.kind=="remodulated-m5") then return originalLayout(fleet) end
    local rows={}
    for index,ship in ipairs(fleet.ships) do
        local entries={{cardId=ship.shipCardId,role="ship"}}
        for _,entry in ipairs(ship.cards) do table.insert(entries,entry) end
        table.insert(rows,{used=#entries,groups={{entries=entries,shipIndex=index,start=1}}})
    end
    return rows
end
function STA2E_M5Attach(s,input)
    local p=profileById(input.shipCardId);if not p then return end
    local programs={};for _,entry in ipairs(input.cards) do table.insert(programs,entry.cardId) end
    local profile=assert(M5.profile({profileId=p.profileId,programs=programs}))
    s.m5={controlled=true,shipId=p.id,profileId=p.profileId,faction=profile.faction,class=profile.class,
        baseCaptainSkill=profile.baseCaptainSkill,finalCaptainSkill=profile.captainSkill,
        baseThreat=profile.baseThreat,threat=profile.threat,slotCapacity=profile.slotCapacity,slotsUsed=profile.slotsUsed,
        programs=programs,actionTree=copy(profile.actionTree)}
    s.ai={enabled=true,intent="engage"};s.side="enemy"
end

function STA2E_M5TrackerButton(s,y)
    local phase=STA2E.game.phase;local label="M5"
    if phase=="planning" then label="PLAN"
    elseif phase=="activation" then label=(s.state.status=="complete" or s.state.status=="action") and "DONE" or "ACT M5"
    elseif phase=="combat" then label=s.state.fired and "FIRED" or "ATTACK" end
    return '<Button id="m5_step_'..xml(s.instanceId)..'" onClick="STA2E_SidebarClick" position="215 '..y..' 0" width="68" height="38" fontSize="12" color="#2B7651" textColor="#FFFFFF">'..label..'</Button>'
end
function STA2E_M5TrackerStep(s,player)
    if not isControlled(s) or not player then return end
    if not player.host and player.color~="Black" and player.color~=s.owner then tell(player.color,"Only the owner or host can run this M5 ship.");return end
    if next(STA2E.pendingMoves) or next(STA2E.imports) or next(STA2E.pending) then tell(player.color,"Wait for spawning or movement to finish.");return end
    if not complete(s) then tell(player.color,"Deploy / Repair this ship first.");return end
    if s.combat and s.combat.destroyed then tell(player.color,"This ship is destroyed.");return end
    local phase=STA2E.game.phase
    if phase=="planning" then
        local result,err=M5.planShip(s);tell(player.color,result and "M5 maneuver planned." or err)
    elseif phase=="activation" then
        if s.state.status=="complete" or s.state.status=="action" then tell(player.color,"This ship already activated.");return end
        local choice,err=M5.planShip(s);if not choice then tell(player.color,err);return end
        s.state.status="revealed";s.state.revealedOriginal=s.state.maneuver;s.state.aiSkipAction=nil
        M5.Events.emit(M5.TIMING.MANEUVER_REVEALED,{ship=s,maneuver=s.state.maneuver})
        executeMove(s,s.owner)
    elseif phase=="combat" then
        if s.state.fired then tell(player.color,"This ship already attacked.");return end
        local result,err=M5.primaryAttack(s)
        if not result then tell(player.color,err) end
    else tell(player.color,"M5 controls are available during Planning, Activation and Combat.") end
    refresh(s)
end
local priorSidebarClick=STA2E_SidebarClick
function STA2E_SidebarClick(player,value,id)
    local instance=id and (id:match('^m5_step_(.+)$') or id:match('^activate_ai_(.+)$'))
    if instance and isControlled(STA2E.ships[instance]) then return STA2E_M5TrackerStep(STA2E.ships[instance],player) end
    return priorSidebarClick(player,value,id)
end
-- All M5 turn execution lives in the tracker. Normal ship tools remain usable.
local priorCommand=STA2E_Command
function STA2E_Command(params)
    local s=shipFor(params.object)
    if isControlled(s) and ({ai_execute=true,move=true,ai_evaluate=true,ai_toggle=true})[params.command] then
        tell(params.color,"Use this M5 ship's tracker row to plan, activate or attack.");return
    end
    return priorCommand(params)
end
local priorRender=render
render=function(s)
    priorRender(s)
    if isControlled(s) then
        local dial=member(s,"dial")
        if dial and s.state.dialOpen then
            dial.UI.setXml('<Panel width="700" height="200" position="0 0 -120" rotation="0 0 180" scale="0.4 0.4 1" color="#102432F5"><Text text="M5 · Use the ship tracker to plan, activate and attack" width="670" height="180" fontSize="25" color="#FFD86B"/></Panel>')
        end
    end
end
