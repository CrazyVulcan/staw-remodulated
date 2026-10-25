test("Release has no dice tool or dashboard even with stale open-pool flags",function()
    _reset();local ship=_ship('no-dice-tools','Blue')
    ship.state.toolsPage='home';ship.state.dialOpen=true
    STA2E_Command({object=_objects[ship.cardGUID],color='Blue',command='tool_home'})
    _drain()
    assert(not _objects[ship.refs.dial]._xml:find('tool_dice',1,true))
    STA2E.diceOpen.Blue=true
    assert(STA2E_DicePanel()=='')
    STA2E_Command({object=_objects[ship.cardGUID],color='Blue',command='tool_dice'})
    assert(not STA2E.diceSource.Blue)
end)

test("Retired dice hooks neither record physical dice nor start watchers",function()
    _reset()
    local die=_object('retired-die');die.type='Custom_Dice';die.setName('Attack die')
    die.getRotationValue=function()return 'Hit'end
    local zone=_object('d1ce01');zone._contents={die}
    onObjectEnterScriptingZone(zone,die)
    STA2E_DieRolled({object=die})
    STA2E.DiceManager.beginRoll(die,'Blue')
    assert(not next(STA2E.DiceManager.watching) and not next(STA2E.DiceManager.byGuid))
    assert(not next(STA2E.dice) and not die.locked)
end)

test("Old saved dice dashboard state is ignored by release startup",function()
    _reset()
    local saved=JSON.encode({schemaVersion=1,game={round=4,phase='combat',nextId=100,fleets={}},
        dice={Blue={order={'absent-die'},dice={['absent-die']={guid='absent-die',kind='attack'}}}},
        diceOpen={Blue=true},diceSource={Blue='old-ship'}})
    onLoad(saved);_drain(20000)
    assert(STA2E.ready and STA2E.game.round==4 and STA2E.game.phase=='combat')
    assert(not next(STA2E.dice) and not next(STA2E.diceOpen) and not next(STA2E.diceSource))
    assert(STA2E_DicePanel()=='' and not _xml:find('dicePanel',1,true))
end)
