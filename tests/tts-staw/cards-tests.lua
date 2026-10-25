-- Focused behavioral checks against the actual patched MEMBER_SCRIPT.
-- Run after the packaged Global in the existing mocked-TTS Lua harness.
local function cardTestEnvironment()
    local object={buttons={},clears=0,creates=0,script_state=""}
    object.clearButtons=function() object.clears=object.clears+1;object.buttons={} end
    object.createButton=function(button) object.creates=object.creates+1;object.buttons[#object.buttons+1]=button end
    object.setLock=function(value) object.locked=value end
    local calls={}
    local env={self=object,JSON=JSON,Wait={frames=function() end},
        Global={call=function(name,args) calls[#calls+1]={name=name,args=args} end}}
    setmetatable(env,{__index=_G})
    local chunk,message=load(MEMBER_SCRIPT,"patched-member-script","t",env)
    assert(chunk,message);chunk()
    return env,object,calls
end

local function frontShipButtons(object,dialOpen,aiEnabled)
    local labels={"DEPLOY",dialOpen and "CLOSE DIAL" or "OPEN DIAL","ACTIONS",
        aiEnabled and "AI CONTROL: ON" or "AI CONTROL: OFF","SHIP CONTROLS"}
    assert(#object.buttons==5,"ship card should have five front controls")
    for index,button in ipairs(object.buttons) do
        assert(button.label==labels[index],"unexpected ship control label")
        assert(button.position[2]>0,"ship control exists on the back face")
        assert(button.rotation[3]==0,"ship control is rotated onto the back face")
        assert(button.function_owner==object,"ship callback owner changed")
    end
end

test("Ship card controls occupy only the physical front and retain callbacks",function()
    local env,object,calls=cardTestEnvironment()
    env.onLoad(JSON.encode({role="card",instanceId="card-polish",state={dialOpen=false},ai={enabled=false}}))
    frontShipButtons(object,false,false)
    for _,button in ipairs(object.buttons) do env[button.click_function](object,"Blue") end
    local commands={"deploy","open_dial","toggle_actions","ai_toggle","ship_settings"}
    assert(#calls==5)
    for index,event in ipairs(calls) do
        assert(event.name=="STA2E_Command" and event.args.command==commands[index] and event.args.color=="Blue")
    end
    env.memory.state.dialOpen=true;env.memory.ai.enabled=true;env.STA2E_SetMemory(env.memory)
    frontShipButtons(object,true,true)
end)

test("Front card controls retain redraw caching and saved component identity",function()
    local env,object=cardTestEnvironment()
    env.STA2E_SetMemory({role="card",instanceId="front-cache",state={dialOpen=false}})
    local original=object.buttons[1]
    for index=1,100 do
        env.STA2E_SetMemory({role="card",instanceId="front-cache",name="Ship "..index,state={dialOpen=false}})
        env.STA2E_SetDisplay({status="planning",guideRange=index%4})
    end
    assert(object.buttons[1]==original and object.clears==1 and object.creates==5,"equivalent updates redraw controls")
    assert(JSON.decode(object.script_state).name=="Ship 100","memory persistence changed")
end)

test("Upgrade and fleet MANAGE buttons are opaque on both card faces",function()
    for _,role in ipairs({"upgrade","fleetCard"}) do
        local env,object,calls=cardTestEnvironment()
        env.STA2E_SetMemory({role=role,cardId="C001"})
        assert(#object.buttons==2,"flipped upgrade management became inaccessible")
        for _,button in ipairs(object.buttons) do
            assert(button.label=="MANAGE" and button.color[4]==1,"upgrade background is translucent")
            assert(button.font_color[1]==1 and button.font_color[2]==1 and button.font_color[3]==1,"upgrade text contrast changed")
            env[button.click_function](object,"Blue")
        end
        assert(calls[1].name=="STA2E_ManageCard" and calls[2].name=="STA2E_ManageCard")
    end
end)

test("Card polish preserves base ARC/CLEAR controls and concealed maneuver UI",function()
    local env,object=cardTestEnvironment()
    env.STA2E_SetMemory({role="base"})
    assert(#object.buttons==3 and object.buttons[1].label=="ARC")
    env.STA2E_SetDisplay({guideArc=true})
    assert(#object.buttons==3 and object.buttons[1].label=="CLEAR")
    env.STA2E_SetMemory({role="baseModel"})
    assert(#object.buttons==3 and object.buttons[1].label=="CLEAR")
    env.STA2E_SetMemory({role="dial"})
    assert(#object.buttons==0,"private maneuver selection leaked onto physical buttons")
end)

test("Upgrade management overlay has an opaque background and readable commands",function()
    _reset()
    local card=_object("opaque-upgrade",{schemaVersion=1,role="upgrade",cardId="C001"})
    STA2E_ManageCard({object=card,color="Blue"});_drain()
    local panel=_xml:match('<Panel id="manageBlue".-</Panel>')
    assert(panel and panel:find('color="#102432FF"',1,true),"upgrade overlay is translucent")
    for _,text in ipairs({"CARD COMMANDS","+ TIME","+ DISABLE","DISCARD / FLIP","ACTION","REMINDER TOKEN"}) do
        assert(panel:find(text,1,true),"missing readable upgrade command: "..text)
    end
    assert(panel:find('textColor="#FFFFFF"',1,true),"upgrade button text lost its contrast")
    STA2E_ManageAction(Player.Blue,"","actions")
    assert(_messages[#_messages].message=="This card is not associated with a ship.","missing unassociated-card warning")
end)
