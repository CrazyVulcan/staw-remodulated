-- Run after global-tests.lua with the same Global and mock TTS environment.
-- Covers repaired failure paths beyond the original audit reproductions.
local coreDieSequence=0
local function coreDie()
    _reset();coreDieSequence=coreDieSequence+1
    STA2E.DiceManager.byGuid={};STA2E.DiceManager.watching={}
    local die=_object("core-die-"..coreDieSequence)
    die.type="Custom_Dice";die._tags={"STA2E_ATTACK_DIE"};die._value=3
    local zone=_object("d1ce01");zone._contents={die}
    return die,zone
end

test("Malformed ordinary and development fleet structures return clean errors",function()
    local values={
        {schemaVersion=2,ships={false}},
        {schemaVersion=2,ships={{shipCardId="S193",cards=false}}},
        {schemaVersion=2,ships={{shipCardId="S193",cards={{cardId={}}}}}},
        {schemaVersion=2,ships={{shipCardId="S193"}},resources=1},
        {schemaVersion=2,ships={{shipCardId="S193"}},resources={1}},
        {schemaVersion=2,ships={{shipCardId="S193"}},source=1},
        {schemaVersion=2,ships={{shipCardId="S193"}},fleetId={}},
        {schemaVersion=1,ships={1}},
        {schemaVersion=1,ships={{shipCardId="S193",upgradeIds=false}}},
        {schemaVersion=1,ships={{shipCardId="S193",upgradeIds={1}}}},
    }
    for i,fleet in ipairs(values) do
        _reset();STA2E_FleetText(Player.Blue,JSON.encode(fleet));STA2E_FleetPreview(Player.Blue)
        assert(not STA2E.fleetPlans.Blue and STA2E.fleetStatus.Blue:find("Cannot spawn",1,true),"malformed case "..i.." accepted")
    end
    for _,fleet in ipairs({false,7,"wrong type"}) do
        assert(not STA2E_ImportFleet({color="Blue",fleet=fleet}).ok)
    end
end)

test("All station definitions keep a usable profile",function()
    for _,id in ipairs({"S073","S075","S184","S185"}) do
        local ship=assert(SHIP_DEFINITIONS[id]);assert(ship.profile and SHIP_DATA.classes[ship.profile],id)
    end
end)

test("Dice edits and rerolls are blocked while awaiting",function()
    local die,zone=coreDie();die.resting=false;onObjectEnterScriptingZone(zone,die)
    STA2E.dice.Blue.dice[die.guid].selected=true
    for _,action in ipairs({"set_hit","reroll","reroll_blanks","spend_bs","finalize","toggle_"..die.guid}) do
        STA2E_DiceAction(Player.Blue,"","dice_Blue_"..action)
        assert(STA2E.dice.Blue.dice[die.guid].awaiting and not STA2E.dice.Blue.finalized)
    end
    die.resting=true;_drain();assert(STA2E.dice.Blue.dice[die.guid].result=="Hit")
end)

test("Dice timeout removes unresolved entry and unlocks physical die",function()
    local die,zone=coreDie();die.resting=false;onObjectEnterScriptingZone(zone,die);_drain()
    assert(#STA2E.dice.Blue.order==0 and not next(STA2E.dice.Blue.rolling) and not die.locked)
    assert(not STA2E.DiceManager.byGuid[die.guid])
end)

test("New roll reopens a previously closed dice panel",function()
    local die,zone=coreDie();onObjectEnterScriptingZone(zone,die);_drain()
    STA2E_DiceAction(Player.Blue,"","dice_Blue_close")
    STA2E_DieRolled({object=die});_drain()
    assert(STA2E.diceOpen.Blue and STA2E_DicePanel():find('id="dicePanelBlue"',1,true))
end)

test("Clear followed immediately by same die roll ignores old watcher",function()
    local die,zone=coreDie();die.resting=false;onObjectEnterScriptingZone(zone,die)
    STA2E_DiceAction(Player.Blue,"","dice_Blue_clear")
    onObjectEnterScriptingZone(zone,die);die.resting=true;die._value=1;_drain()
    assert(#STA2E.dice.Blue.order==1 and STA2E.dice.Blue.dice[die.guid].result=="Crit")
    assert(not next(STA2E.dice.Blue.rolling))
end)

test("Physical die cannot remain recorded in two player pools",function()
    local die,zone=coreDie();onObjectEnterScriptingZone(zone,die);_drain()
    local redZone=_object("d1ce02");redZone._contents={die};zone._contents={}
    onObjectEnterScriptingZone(redZone,die);_drain()
    assert(#STA2E.dice.Blue.order==0 and #STA2E.dice.Red.order==1)
end)

test("Finalized logical dice and explicit closed visibility survive reload",function()
    local die,zone=coreDie();onObjectEnterScriptingZone(zone,die);_drain()
    STA2E.diceSource.Blue="source-ship"
    STA2E_DiceAction(Player.Blue,"","dice_Blue_finalize")
    STA2E_DiceAction(Player.Blue,"","dice_Blue_close")
    local saved=onSave();die._value=1;onLoad(saved);_drain()
    assert(STA2E.dice.Blue.finalized and STA2E.dice.Blue.dice[die.guid].result=="Hit" and die.locked)
    assert(STA2E.diceOpen.Blue==false and STA2E.diceSource.Blue=="source-ship")
end)

test("Reload resumes an unresolved roll and captures settled value",function()
    local die,zone=coreDie();die.resting=false;onObjectEnterScriptingZone(zone,die)
    local saved=onSave();onLoad(saved);die.resting=true;die._value=1;_drain()
    assert(STA2E.dice.Blue.dice[die.guid].result=="Crit" and not next(STA2E.dice.Blue.rolling) and die.locked)
end)

test("Deleted settled die is removed from dashboard and save state",function()
    local die,zone=coreDie();onObjectEnterScriptingZone(zone,die);_drain()
    die.destruct();onObjectDestroy(die);_drain()
    assert(#STA2E.dice.Blue.order==0 and not STA2E.DiceManager.byGuid[die.guid])
end)

test("Reload prunes missing physical dice",function()
    local die,zone=coreDie();onObjectEnterScriptingZone(zone,die);_drain()
    local saved=onSave();die.destruct();onLoad(saved);_drain()
    assert(#STA2E.dice.Blue.order==0 and not STA2E.DiceManager.byGuid[die.guid])
end)

local function echoPreview()
    _reset();local s=_ship("core-echo")
    STA2E_StartSensorEcho({color="Blue",instanceId=s.instanceId,sourceType="ship"})
    STA2E_SensorEchoAction(Player.Blue,"","echo_Blue_side_Left")
    STA2E_SensorEchoAction(Player.Blue,"","echo_Blue_template_STRAIGHT_1")
    assert(STA2E.sensorEcho.Blue.source and STA2E.sensorEcho.Blue.candidates[2].legal)
    return s,_objects[s.refs.base],STA2E.sensorEcho.Blue
end

test("Sensor Echo cancels a preview after source movement",function()
    local s,base=echoPreview();base.setPosition({0.5,1,0})
    STA2E_SensorEchoAction(Player.Blue,"","echo_Blue_commit_2")
    assert(not STA2E.sensorEcho.Blue and base.getPosition().x==0.5 and not s.undo)
end)

test("Sensor Echo rechecks newly blocking ships before commit",function()
    local s,base,session=echoPreview();local candidate=session.candidates[2]
    local blocker=_ship("echo-blocking-ship","Red")
    _objects[blocker.refs.base].setPosition({candidate.x,1,candidate.z})
    STA2E_SensorEchoAction(Player.Blue,"","echo_Blue_commit_2")
    assert(base.getPosition().x==0 and not s.undo and STA2E.sensorEcho.Blue)
    assert(not STA2E.sensorEcho.Blue.candidates[2].legal)
end)

test("Sensor Echo rechecks newly blocking terrain before commit",function()
    local s,base,session=echoPreview();local candidate=session.candidates[2]
    local blocker=_object("echo-terrain",nil,{candidate.x,1,candidate.z});blocker._tags={"Obstacle"}
    STA2E_SensorEchoAction(Player.Blue,"","echo_Blue_commit_2")
    assert(base.getPosition().x==0 and not s.undo and not STA2E.sensorEcho.Blue.candidates[2].legal)
end)

test("Sensor Echo commits an unchanged legal preview and records Undo",function()
    local s,base,session=echoPreview();local candidate=session.candidates[2]
    STA2E_SensorEchoAction(Player.Blue,"","echo_Blue_commit_2")
    assert(not STA2E.sensorEcho.Blue and s.undo and math.abs(base.getPosition().x-candidate.x)<0.001)
end)
