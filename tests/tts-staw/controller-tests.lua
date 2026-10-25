test('Book III packaged controller callbacks and selectors persist and reach runtime',function()
    for _,id in ipairs({'A7M1','A7M2','A7M3','A8M1','A8M2','A9M1','A9M2'})do
        _reset();local o=_object('book3-controller');local calls={}
        local bridge={call=function(name,args)
            calls[#calls+1]={name=name,args=args}
            return {ok=true,id=id,runId='test-run',round=0,phase='setup',waveText='Ready',status='Ready'}
        end}
        local function environment(saved)
            local env=setmetatable({self=o,Global=bridge},{__index=_G});env._G=env
            assert(load(_book3ControllerSource(id),'@packaged-'..id,'t',env))();env.onLoad(saved or '')
            for _,b in ipairs(o._buttons)do assert(type(env[b.click_function])=='function',id..': '..b.click_function)end
            return env
        end
        local env=environment();env.choosePlayers();env.chooseDifficulty();env.choosePenumbra();env.chooseSupplyRun();env.chooseDogsRound();env.chooseAsteroid()
        if id=='A9M1' or id=='A9M2' then env.chooseEscort1();env.chooseEscort2();env.chooseEscort2()end
        local saved=env.onSave();env.onDestroy();env=environment(saved)
        assert(env.onSave()==saved,'selector persistence '..id)
        env.startMission(nil,'Blue');local args=calls[#calls].args
        assert(calls[#calls].name=='STA2E_MissionStart' and args.id==id and args.playerCount==3 and args.difficulty=='adjusted')
        assert(args.priorResults.penumbra and args.priorResults.supplyRun and args.priorResults.dogsRound==8)
        if id=='A9M1' or id=='A9M2'then assert(args.escortFactions[1]=='federation' and args.escortFactions[2]=='klingon')end
        for callback,name in pairs({advancePhase='STA2E_MissionAdvance',retryWaves='STA2E_MissionRetry',finishMission='STA2E_MissionFinish',resetMission='STA2E_MissionReset'})do
            env[callback](nil,'Blue');assert(calls[#calls].name==name and calls[#calls].args.id==id)
        end
        local action=({A7M1='battleshipDestroyed',A8M1='facilityRevealed',A9M1='defect',A9M2='bombardment'})[id]
        if action then env[action](nil,'Blue');args=calls[#calls].args;assert(calls[#calls].name=='STA2E_Book3Event' and args.runId=='test-run' and args.action==action and args.asteroid==2)end
        env.onDestroy();_waits={}
    end
end)
