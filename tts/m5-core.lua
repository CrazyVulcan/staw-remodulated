-- M5 AI vertical slice 0.1.
-- Appended after round-ux.lua and neutral-tools.lua so it can reuse the
-- authoritative ship records, current movement evaluator, and physical-card factory.

STA2E.M5 = STA2E.M5 or {}
local M5=STA2E.M5
M5.VERSION=1
M5.TIMING={
    PLANNING_START="planning_start", MANEUVER_SELECTED="maneuver_selected",
    MANEUVER_REVEALED="maneuver_revealed", AFTER_MOVE="after_move", ACTION_STEP="action_step",
    COMBAT_START="combat_start", ATTACK_DECLARE="attack_declare", ATTACK_ROLL="attack_roll",
    ATTACK_MODIFY="attack_modify", DEFENSE_ROLL="defense_roll", DEFENSE_MODIFY="defense_modify",
    ATTACK_RESOLVED="attack_resolved", END_PHASE="end_phase",
}

M5.SHIP_PROFILES={
    neghvar={
        id="neghvar", shipCardId="S193", name="I.K.S. Negh'var", faction="Klingon",
        class="Negh'var Class", baseCaptainSkill=4, baseThreat=6, slotCapacity=4,
        attack=6, agility=1, hull=7, shields=3,
        actionTree={
            {id="clear_aux",label="Clear Auxiliary Power",condition="has_aux",action="CLEAR_AUX"},
            {id="target_lock",label="Acquire Target Lock",condition="has_target",action="TL"},
            {id="battlestations",label="Battle Stations",condition="always",action="BS"},
            {id="evade",label="Evade",condition="always",action="EVA"},
        },
    },
}

-- Focused Barrage is a provisional adaptation of the discussed timing window,
-- not a verified transcription of an original 2024 card. Hunter's
-- Algorithm proves that signed negative CS is first-class and beneficial for
-- an activation-oriented routine; it is intentionally small for this slice.
M5.PROGRAMS={
    focused_barrage={
        id="focused_barrage",name="Focused Barrage",faction="Klingon",
        csModifier=3,threat=3,slots=2,classes={"Negh'var Class","Vor'cha Class"},
        timing=M5.TIMING.ATTACK_DECLARE,
        text="When declaring a primary attack, choose that defender as the fleet focus and add 1 attack die.",
    },
    hunters_algorithm={
        id="hunters_algorithm",name="Hunter's Algorithm",faction="Klingon",
        csModifier=-2,threat=1,slots=1,classes={"Negh'var Class","K'Vort Class","B'Rel Class"},
        timing=M5.TIMING.AFTER_MOVE,
        text="After moving, prefer Target Lock when a legal enemy is available. The -2 CS helps this ship activate earlier.",
    },
}

M5.Events={listeners={},sequence=0}
function M5.Events.on(window,id,priority,handler)
    if type(window)~="string" or type(id)~="string" or type(handler)~="function" then return false end
    M5.Events.sequence=M5.Events.sequence+1
    M5.Events.listeners[window]=M5.Events.listeners[window] or {}
    table.insert(M5.Events.listeners[window],{id=id,priority=priority or 100,sequence=M5.Events.sequence,handler=handler})
    table.sort(M5.Events.listeners[window],function(a,b)
        if a.priority~=b.priority then return a.priority<b.priority end
        return a.sequence<b.sequence
    end)
    return true
end
function M5.Events.off(window,id)
    local source=M5.Events.listeners[window] or {};local kept={}
    for _,listener in ipairs(source) do if listener.id~=id then table.insert(kept,listener) end end
    M5.Events.listeners[window]=kept
end
function M5.Events.emit(window,context)
    context=context or {};context.window=window;context.round=STA2E.game and STA2E.game.round or 0
    for _,listener in ipairs(M5.Events.listeners[window] or {}) do
        local ok,err=pcall(listener.handler,context)
        if not ok then context.errors=context.errors or {};table.insert(context.errors,listener.id..": "..tostring(err)) end
        if context.cancelled then break end
    end
    return context
end
function STA2E_M5Emit(params) return M5.Events.emit(params.window,params.context or {}) end

local function contains(values,value)
    for _,candidate in ipairs(values or {}) do if candidate==value then return true end end
    return false
end
local function signed(value)
    value=tonumber(value) or 0
    return value>=0 and ("+"..tostring(value)) or tostring(value)
end
local function selectedPrograms(build)
    local result={}
    for _,id in ipairs(build.programs or {}) do if M5.PROGRAMS[id] then table.insert(result,id) end end
    return result
end
function M5.profile(build)
    build=build or {};local base=M5.SHIP_PROFILES[build.profileId or "neghvar"]
    if not base then return nil,"Unknown M5 ship profile." end
    local result=copy(base);result.programs=selectedPrograms(build)
    result.captainSkill=result.baseCaptainSkill;result.threat=result.baseThreat;result.slotsUsed=0
    for _,id in ipairs(result.programs) do
        local program=M5.PROGRAMS[id]
        if program.faction~=result.faction or not contains(program.classes,result.class) then
            return nil,program.name.." cannot be installed on "..result.class.."."
        end
        result.captainSkill=result.captainSkill+(tonumber(program.csModifier) or 0)
        result.threat=result.threat+(tonumber(program.threat) or 0)
        result.slotsUsed=result.slotsUsed+(tonumber(program.slots) or 0)
    end
    if result.slotsUsed>result.slotCapacity then return nil,"M5 slots exceed this ship's capacity." end
    return result
end
function M5.validateBuild(build) return M5.profile(build) end

local function m5State()
    STA2E.game.m5=STA2E.game.m5 or {builds={},fleetFocus={}}
    STA2E.game.m5.builds=STA2E.game.m5.builds or {}
    STA2E.game.m5.fleetFocus=STA2E.game.m5.fleetFocus or {}
    return STA2E.game.m5
end
local function buildFor(color)
    local state=m5State()
    state.builds[color]=state.builds[color] or {profileId="neghvar",programs={"focused_barrage","hunters_algorithm"}}
    return state.builds[color]
end
local function isControlled(s) return s and s.m5 and s.m5.controlled==true end
function STA2E_M5SetController(params)
    local s=params and params.instanceId and STA2E.ships[params.instanceId]
    if not s then return {ok=false,error="Unknown ship instance."} end
    s.m5=s.m5 or {};s.m5.controlled=params.controlled~=false
    refresh(s);return {ok=true}
end

-- Feed M5's signed skill into the existing Activation/Combat sort. It changes
-- timing only; every M5 ship uses the same tactical evaluator.
local previousSkillFor=skillFor
skillFor=function(s)
    if isControlled(s) and s.m5.finalCaptainSkill~=nil then return s.m5.finalCaptainSkill end
    return previousSkillFor(s)
end

local function programInstalled(s,id) return isControlled(s) and contains(s.m5.programs,id) end
M5.Events.on(M5.TIMING.ATTACK_DECLARE,"program.focused_barrage",20,function(context)
    local s=context.attacker
    if not programInstalled(s,"focused_barrage") or context.weapon~="primary" then return end
    context.attackDice=(context.attackDice or 0)+1
    local state=m5State();state.fleetFocus[s.owner]=context.defender and context.defender.instanceId or nil
    context.effects=context.effects or {};table.insert(context.effects,"Focused Barrage +1 attack die")
end)
M5.Events.on(M5.TIMING.AFTER_MOVE,"program.hunters_algorithm",20,function(context)
    local s=context.ship
    if programInstalled(s,"hunters_algorithm") then s.m5.preferredAction="TL" end
end)

local function basePose(s)
    local base=member(s,"base")
    if not base then return nil end
    local p,r=base.getPosition(),base.getRotation()
    return {x=p.x,z=p.z,yaw=r.y,object=base}
end
local function distance(a,b)
    local dx,dz=b.x-a.x,b.z-a.z
    return math.sqrt(dx*dx+dz*dz)
end
local function forwardDot(poseValue,target)
    local dx,dz=target.x-poseValue.x,target.z-poseValue.z;local length=math.sqrt(dx*dx+dz*dz)
    if length<0.001 then return 1 end
    local heading=math.rad(poseValue.yaw)
    return ((-math.sin(heading))*dx+(-math.cos(heading))*dz)/length
end
local function enemies(s,requireArc)
    local origin=basePose(s);local result={}
    if not origin then return result end
    for _,candidate in pairs(STA2E.ships) do
        if candidate.instanceId~=s.instanceId and candidate.owner~=s.owner then
            local target=basePose(candidate)
            if target then
                local range=distance(origin,target);local dot=forwardDot(origin,target)
                if range<=18.0 and (not requireArc or dot>=0.7071) then
                    table.insert(result,{ship=candidate,range=range,dot=dot})
                end
            end
        end
    end
    table.sort(result,function(a,b)
        local focus=m5State().fleetFocus[s.owner]
        if (a.ship.instanceId==focus)~=(b.ship.instanceId==focus) then return a.ship.instanceId==focus end
        local ah=a.ship.combat and a.ship.combat.hull or 99
        local bh=b.ship.combat and b.ship.combat.hull or 99
        if ah~=bh then return ah<bh end
        return a.range<b.range
    end)
    return result
end
function M5.selectTarget(s,requireArc)
    local list=enemies(s,requireArc)
    return list[1] and list[1].ship or nil,list[1]
end

-- Uses the newer Remodulated candidate-pose evaluator. The printed 2024 chart
-- is not consulted. Collision truncation remains owned by executeMove().
function M5.chooseManeuver(s)
    local start=basePose(s);if not start then return nil,"Deploy the M5 ship first." end
    local target=M5.selectTarget(s,false);local targetPose=target and basePose(target) or {x=0,z=0,yaw=0}
    local best=nil
    for _,entry in ipairs(dialFor(s) or {}) do
        local move=MOVE_DEFS[entry.key]
        if move then
            local finish=STA2E.Movement.pose(start,move,1)
            local range=distance(finish,targetPose);local dot=forwardDot(finish,targetPose)
            local desired=range>=5 and range<=11 and 32 or -math.abs(range-8)*3
            local arc=dot>=0.7071 and 45 or dot*18
            local close=distance(start,targetPose)>12 and (distance(start,targetPose)-range)*2 or 0
            local edge=math.max(0,math.abs(finish.x)-34)*20+math.max(0,math.abs(finish.z)-34)*20
            local difficulty=entry.difficulty=="red" and -8 or (entry.difficulty=="green" and 3 or 0)
            if s.state and s.state.auxiliary and entry.difficulty=="green" then difficulty=difficulty+12 end
            local score=desired+arc+close+difficulty-edge
            if not best or score>best.score or (score==best.score and entry.key<best.key) then
                best={key=entry.key,score=score,range=range,dot=dot,target=target and target.instanceId or nil}
            end
        end
    end
    if not best then return nil,"No supported maneuver exists on this dial." end
    return best
end
function M5.planShip(s)
    if not isControlled(s) then return nil,"Ship is not M5 controlled." end
    local choice,err=M5.chooseManeuver(s);if not choice then return nil,err end
    s.state=s.state or {};s.state.maneuver=choice.key;s.state.status="ready"
    s.m5.navigationTarget=choice.target;s.m5.intent=choice
    M5.Events.emit(M5.TIMING.MANEUVER_SELECTED,{ship=s,choice=choice})
    refresh(s);return choice
end

local function hasAction(s,key) return contains(s.capabilities and s.capabilities.actions,key) end
function M5.runActionTree(s)
    if not isControlled(s) or not s.state or s.state.status~="action" then return nil end
    local target=M5.selectTarget(s,false);local chosen=nil
    for _,node in ipairs(s.m5.actionTree or {}) do
        local valid=node.condition=="always" or (node.condition=="has_aux" and s.state.auxiliary) or (node.condition=="has_target" and target~=nil)
        if valid and (node.action=="CLEAR_AUX" or hasAction(s,node.action)) then chosen=node.action;break end
    end
    if s.m5.preferredAction and target and hasAction(s,s.m5.preferredAction) then chosen=s.m5.preferredAction end
    M5.Events.emit(M5.TIMING.ACTION_STEP,{ship=s,target=target,action=chosen})
    if chosen=="CLEAR_AUX" then s.state.auxiliary=false;s.state.action="CLEAR_AUX";s.state.status="complete";refresh(s)
    elseif chosen then STA2E_Command({object=obj(s.cardGUID),color=s.owner,command="action_"..chosen})
    else s.state.status="complete";refresh(s) end
    s.m5.preferredAction=nil
    return chosen
end

local previousRefresh=refresh
refresh=function(s)
    previousRefresh(s)
    if isControlled(s) and s.state and s.state.status=="action" and not s.state.m5ActionPending then
        s.state.m5ActionPending=true;commit(s)
        Wait.frames(function()
            if STA2E.ships[s.instanceId] and s.state and s.state.status=="action" then
                s.state.m5ActionPending=nil
                M5.Events.emit(M5.TIMING.AFTER_MOVE,{ship=s,target=M5.selectTarget(s,false)})
                M5.runActionTree(s)
            end
        end,1)
    end
end

local function ensureCombat(s)
    local catalog=CATALOG[s.definitionId] or {}
    if not s.combat then
        local profile=isControlled(s) and M5.SHIP_PROFILES[s.m5.profileId] or nil
        s.combat={hull=profile and profile.hull or 4,maxHull=profile and profile.hull or 4,
            shields=profile and profile.shields or tonumber(catalog.shields) or 0,
            maxShields=profile and profile.shields or tonumber(catalog.shields) or 0,
            agility=profile and profile.agility or 2,destroyed=false}
    end
    return s.combat
end
local function attackDie()
    local face=math.random(1,8)
    if face<=3 then return "hit" elseif face==4 then return "critical" elseif face<=6 then return "battlestations" else return "blank" end
end
local function defenseDie()
    local face=math.random(1,8)
    if face<=3 then return "evade" elseif face<=5 then return "battlestations" else return "blank" end
end
local function count(values,key)local n=0;for _,value in ipairs(values) do if value==key then n=n+1 end end;return n end
function M5.primaryAttack(s)
    if not isControlled(s) then return nil,"Ship is not M5 controlled." end
    local defender,geometry=M5.selectTarget(s,true)
    if not defender then return nil,"No enemy is in primary arc at Range 1-3." end
    local profile=M5.SHIP_PROFILES[s.m5.profileId];local context={attacker=s,defender=defender,weapon="primary",attackDice=profile.attack,range=geometry.range,effects={}}
    M5.Events.emit(M5.TIMING.ATTACK_DECLARE,context)
    context.attackResults={};for _=1,context.attackDice do table.insert(context.attackResults,attackDie()) end
    M5.Events.emit(M5.TIMING.ATTACK_ROLL,context)
    if s.state and s.state.action=="BS" then
        for i,value in ipairs(context.attackResults) do if value=="battlestations" then context.attackResults[i]="hit" end end
    end
    M5.Events.emit(M5.TIMING.ATTACK_MODIFY,context)
    local defense=ensureCombat(defender);context.defenseResults={}
    for _=1,defense.agility do table.insert(context.defenseResults,defenseDie()) end
    M5.Events.emit(M5.TIMING.DEFENSE_ROLL,context)
    if defender.state and defender.state.action=="EVA" then table.insert(context.defenseResults,"evade") end
    M5.Events.emit(M5.TIMING.DEFENSE_MODIFY,context)
    local hits=count(context.attackResults,"hit")+count(context.attackResults,"critical")
    local evades=count(context.defenseResults,"evade")
    local damage=math.max(0,hits-evades);local shields=math.min(defense.shields,damage)
    defense.shields=defense.shields-shields;defense.hull=defense.hull-(damage-shields)
    defense.destroyed=defense.hull<=0;context.hits=hits;context.evades=evades;context.damage=damage
    s.state.fired=true;s.m5.combatTarget=defender.instanceId
    M5.Events.emit(M5.TIMING.ATTACK_RESOLVED,context)
    refresh(s);refresh(defender)
    broadcastToAll(s.name.." attacks "..defender.name.." with its primary weapon: "..hits.." hit/critical, "..evades.." evade, "..damage.." damage.",{0.90,0.72,0.30})
    return context
end

local function orderedControlled(phase)
    local result={};for _,s in pairs(STA2E.ships) do if isControlled(s) then table.insert(result,s) end end
    table.sort(result,function(a,b)
        local x,y=skillFor(a),skillFor(b)
        if x~=y then return phase=="combat" and x>y or x<y end
        return a.instanceId<b.instanceId
    end)
    return result
end
function M5.run(color)
    local phase=STA2E.game.phase
    if phase=="planning" then
        M5.Events.emit(M5.TIMING.PLANNING_START,{color=color})
        local planned=0;for _,s in ipairs(orderedControlled(phase)) do if not s.state.maneuver then local choice=M5.planShip(s);if choice then planned=planned+1 end end end
        return "M5 planned "..planned.." ship(s)."
    elseif phase=="activation" then
        for _,s in ipairs(orderedControlled(phase)) do
            if s.state.status=="planning" then M5.planShip(s) end
            if s.state.status=="ready" then
                s.state.status="revealed";s.state.revealedOriginal=s.state.maneuver
                M5.Events.emit(M5.TIMING.MANEUVER_REVEALED,{ship=s,maneuver=s.state.maneuver})
                refresh(s);executeMove(s,s.owner);return "M5 activated "..s.name.."."
            end
        end
        return "All M5 ships have activated."
    elseif phase=="combat" then
        M5.Events.emit(M5.TIMING.COMBAT_START,{color=color})
        for _,s in ipairs(orderedControlled(phase)) do
            if not s.state.fired then local result,err=M5.primaryAttack(s);if result then return "M5 resolved "..s.name.."'s attack." else s.state.fired=true;refresh(s);return s.name..": "..err end end
        end
        return "All M5 ships have attacked."
    else
        M5.Events.emit(M5.TIMING.END_PHASE,{color=color});return "M5 end-phase events resolved."
    end
end

local function programCardData(program,profile)
    local back=CATALOG[profile.shipCardId] and CATALOG[profile.shipCardId].cardBack or "https://i.imgur.com/21bhPTi.jpg"
    return {Name="Custom_Tile",Transform={posX=0,posY=1.2,posZ=0,rotX=0,rotY=180,rotZ=0,scaleX=1.45,scaleY=1,scaleZ=1.0},
        Nickname="M5 · "..program.name,Description="M5 PROGRAM\nCS "..signed(program.csModifier).." · Threat +"..program.threat.." · Slots "..program.slots.."\n"..program.text,
        GMNotes="M5_PROGRAM:"..program.id,ColorDiffuse={r=0.22,g=0.26,b=0.30},Locked=false,Grid=true,Snap=true,Hands=true,
        CustomImage={ImageURL=back,ImageSecondaryURL="",ImageScalar=1,WidthScale=0,CustomTile={Type=0,Thickness=0.1,Stackable=false,Stretch=true}},LuaScript="",LuaScriptState="",XmlUI=""}
end
