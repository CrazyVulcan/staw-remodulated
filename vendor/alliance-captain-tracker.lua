;(function()
    local A={}
    STA2E.AllianceCaptain=A
    function A.progress(value)
        if type(value)~="table" or (value.version~=nil and value.version~=2) then return nil,"Invalid Alliance captain tracker." end
        if value.name~=nil and (type(value.name)~="string" or #value.name>400) then return nil,"Invalid captain name." end
        local state={version=2,name=value.name or ""}
        for track,maximum in pairs({Elite=6,Skill=14,Crew=10,Weapon=10,Tech=10}) do
            local n=value[track]
            if n==nil then n=0 end
            if type(n)~="number" or n~=n or n<0 or n>maximum or n~=math.floor(n) then return nil,"Invalid "..track.." XP." end
            state[track]=n
        end
        local choices={None=true,Crew=true,Weapon=true,Tech=true}
        for _,field in ipairs({"ExpansionOne","ExpansionTwo"}) do
            local choice=value[field]
            if choice==nil then choice="None" end
            if type(choice)~="string" or not choices[choice] then return nil,"Invalid captain expansion slot." end
            state[field]=choice
        end
        return state
    end
    function A.pendingState(data,color,transaction,progress)
        local state=progress and assert(A.progress(progress)) or decode(data.LuaScriptState) or {version=2}
        state.memory={schemaVersion=1,role="pending",transaction=transaction}
        local player=Player[color]
        if not progress or state.name=="" then state.name=player and player.steam_name and player.steam_name~="" and player.steam_name or "Alliance Captain" end
        data.Nickname=state.name
        return JSON.encode(state)
    end
    function A.apply(s,entry,snapshot)
        if type(snapshot)~="table" then return false end
        local name=tostring(snapshot.name or "")
        local skill=tonumber(snapshot.skill)
        if not skill or skill~=skill then return false end
        skill=math.max(2,math.min(9,math.floor(skill)))
        local xp=math.max(0,math.floor(tonumber(snapshot.xp) or 0))
        local old=s.allianceCaptain
        if old and old.guid==entry.guid and old.name==name and old.skill==skill and old.xp==xp then return false end
        if old and old.guid==entry.guid and old.skill~=skill then s.skillOverride=nil end
        s.allianceCaptain={guid=entry.guid,cardId=entry.cardId,name=name,skill=skill,xp=xp}
        return true
    end
    function A.syncCaptain(s)
        for _,entry in ipairs(s.upgrades or {}) do
            local card=CATALOG[entry.cardId]
            if card and card.type=="captain" then
                if not card.interactiveCaptain then return false end
                local object=obj(entry.guid)
                if not object then return false end
                local ok,snapshot=pcall(function() return object.call("STA2E_CaptainSnapshot") end)
                return ok and A.apply(s,entry,snapshot) or false
            end
        end
        return false
    end
    function A.syncShipName(s)
        local card=obj(s.cardGUID)
        if not card then return false end
        local actual=tostring(card.getName() or "")
        if s.observedShipCardName==nil then s.observedShipCardName=actual;return false end
        if actual==s.observedShipCardName then return false end
        s.observedShipCardName=actual
        local cleaned=actual:match("^%s*(.-)%s*$")
        local name=cleaned~="" and cleaned or importedShipName(CATALOG[s.definitionId])
        if name==s.name then return false end
        s.name=name
        return true
    end
    function A.scan()
        for _,s in pairs(STA2E.ships or {}) do
            local shipChanged=A.syncShipName(s)
            local captainChanged=A.syncCaptain(s)
            if shipChanged or captainChanged then refresh(s) end
        end
    end
    function STA2E_AllianceCaptainChanged(params)
        local object=params and params.object
        local m=metadata(object)
        local s=m and STA2E.ships[m.instanceId]
        if not s or m.role~="upgrade" or m.cardGUID~=s.cardGUID then return end
        for _,entry in ipairs(s.upgrades or {}) do
            local card=CATALOG[entry.cardId]
            if entry.guid==object.getGUID() and card and card.interactiveCaptain then
                if A.apply(s,entry,params.snapshot) then refresh(s) end
                return
            end
        end
    end
    local previousUpdate=onUpdate
    local nextCheck=0
    function onUpdate()
        if previousUpdate then previousUpdate() end
        if not STA2E.ready or STA2E.loading or STA2E.reconciling or Time.time<nextCheck then return end
        nextCheck=Time.time+0.5
        A.scan()
    end
    local previousReconcile=STA2E_Reconcile
    function STA2E_Reconcile()
        previousReconcile()
        A.scan()
    end
    local previousSave=onSave
    function onSave()
        if STA2E.ready and not STA2E.loading then A.scan() end
        return previousSave()
    end
end)()
