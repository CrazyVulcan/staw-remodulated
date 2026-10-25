-- Template: replace the two placeholders when embedding in a mission object.
local MISSION_ID="__MISSION_ID__"
local MISSION_NAME="__MISSION_NAME__"
local maxRound=MISSION_ID=="A2M4" and 12 or (MISSION_ID=="A3M1" and 11 or 10)
local players=2
local influence=0
local round=0
local phase="Not started"
local waveText="No waves deployed"
local lastStatus="Choose players, then start this mission."
local pollHandle=nil
local buttonIndex={}

local function wrapped(value,width,maxLines)
    local lines,line={},""
    for word in tostring(value):gmatch("%S+") do
        if line~="" and #line+#word+1>width then
            lines[#lines+1]=line
            line=word
        else
            line=line=="" and word or line.." "..word
        end
    end
    if line~="" then lines[#lines+1]=line end
    if #lines>maxLines then
        while #lines>maxLines do table.remove(lines) end
        lines[maxLines]=lines[maxLines].."..."
    end
    return table.concat(lines,"\n")
end

local function integer(value,minimum,maximum,default)
    local n=tonumber(value)
    if not n then return default end
    return math.max(minimum,math.min(maximum,math.floor(n)))
end

local function message(text,color,isError)
    if type(color)=="string" and color~="" then
        broadcastToColor(text,color,isError and {1,0.35,0.25} or {0.6,0.9,1})
    end
end

local function redraw()
    if not buttonIndex.title then return end
    self.editButton({index=buttonIndex.title,label=wrapped(MISSION_NAME,32,2),tooltip=MISSION_NAME})
    self.editButton({index=buttonIndex.players,label=players.." PLAYERS"})
    if buttonIndex.influence then self.editButton({index=buttonIndex.influence,label="INFLUENCE "..influence}) end
    self.editButton({index=buttonIndex.round,label="ROUND "..tostring(round).." / "..maxRound.."  |  "..tostring(phase)})
    self.editButton({index=buttonIndex.waves,label=wrapped(waveText,48,2),tooltip=tostring(waveText)})
    self.editButton({index=buttonIndex.status,label=wrapped(lastStatus,55,3),tooltip=tostring(lastStatus)})
end

local function applyResponse(result,color,quiet)
    if type(result)~="table" then
        if not quiet then
            lastStatus="Mission runtime returned no response."
            message(lastStatus,color,true)
        end
        redraw()
        return false
    end
    if result.ok==false or result.error then
        lastStatus=tostring(result.error or result.status or "Mission operation failed.")
        if not quiet then message(lastStatus,color,true) end
        redraw()
        return false
    end
    if result.round~=nil then round=result.round end
    if result.phase~=nil then phase=result.phase end
    if result.waveText~=nil then waveText=result.waveText end
    if result.status~=nil then lastStatus=result.status end
    redraw()
    return true
end

local function callRuntime(name,params,color,quiet)
    local ok,result=pcall(function() return Global.call(name,params) end)
    if not ok then
        lastStatus="Runtime error: "..tostring(result)
        if not quiet then message(lastStatus,color,true) end
        redraw()
        return false
    end
    return applyResponse(result,color,quiet)
end

function noAction() end

function choosePlayers()
    players=players+1
    if players>6 then players=2 end
    redraw()
end

function chooseInfluence()
    if MISSION_ID~="A3M1" then return end
    influence=(influence+1)%3
    redraw()
end

function startMission(_,color)
    callRuntime("STA2E_MissionStart",{id=MISSION_ID,playerCount=players,influence=influence,controllerGUID=self.getGUID()},color,false)
end

function advancePhase(_,color)
    callRuntime("STA2E_MissionAdvance",{id=MISSION_ID,color=color},color,false)
end

function retryWaves(_,color)
    callRuntime("STA2E_MissionRetry",{id=MISSION_ID},color,false)
end

function finishMission(_,color)
    callRuntime("STA2E_MissionFinish",{id=MISSION_ID,color=color},color,false)
end

function resetMission(_,color)
    callRuntime("STA2E_MissionReset",{id=MISSION_ID,color=color},color,false)
end

function refreshStatus()
    callRuntime("STA2E_MissionStatus",{id=MISSION_ID},nil,true)
end

-- Optional push callback; polling remains available if Global does not use it.
function onMissionStateChanged(result)
    if type(result)=="table" and (result.id==nil or result.id==MISSION_ID) then applyResponse(result,nil,true) end
end

local function button(key,callback,label,x,z,width,height,fontSize,color,tooltip)
    local existing=self.getButtons() or {}
    buttonIndex[key]=#existing
    self.createButton({click_function=callback,function_owner=self,label=label,
        position={x,0.22,z},rotation={0,0,0},width=width,height=height,font_size=fontSize,
        color=color or {0.13,0.23,0.32,0.98},font_color={1,1,1},tooltip=tooltip or ""})
end

function onLoad(saved)
    local ok,state=pcall(JSON.decode,saved or "")
    if ok and type(state)=="table" then
        players=integer(state.players,2,6,2)
        influence=integer(state.influence,0,2,0)
        lastStatus=type(state.lastStatus)=="string" and state.lastStatus or lastStatus
    end
    self.setLock(true)
    self.clearButtons()
    buttonIndex={}
    button("title","noAction",MISSION_NAME,0,-1.65,0,0,105,nil,"Standalone mission setup and wave controller")
    button("players","choosePlayers","",MISSION_ID=="A3M1" and -0.82 or 0,-1.08,760,265,125,nil,"Cycles 2-6 players for the next setup. Solo play uses two ships and 2-player setup.")
    if MISSION_ID=="A3M1" then
        button("influence","chooseInfluence","",0.82,-1.08,760,265,115,{0.35,0.24,0.12,0.98},"Cycles 0-2 Influence for the next finale setup.")
    end
    button("start","startMission","START",-1.05,-0.53,680,280,125,{0.18,0.46,0.28,0.98},"Build this mission's objects and setup formations.")
    button("advance","advancePhase","NEXT PHASE",0.85,-0.53,1000,280,120,{0.16,0.36,0.55,0.98},"Advance Planning, Activation, Combat, then End phase. Follow the shown phase when resolving manual rules.")
    button("retry","retryWaves","RETRY WAVES",-0.88,0.02,900,260,105,{0.33,0.28,0.12,0.98},"Retry scheduled ships that could not be spawned. Already spawned ships are not duplicated.")
    button("finish","finishMission","FINISH",0.96,0.02,650,260,115,{0.33,0.22,0.40,0.98},"End this mission after manually resolving its objectives and XP.")
    button("reset","resetMission","RESET MISSION",0,0.57,1250,260,110,{0.47,0.19,0.16,0.98},"Reset this mission's runtime and generated mission objects.")
    button("round","noAction","",0,1.10,0,0,110)
    button("waves","noAction","",0,1.48,0,0,75)
    button("status","noAction","",0,1.95,0,0,65)
    redraw()
    refreshStatus()
    if pollHandle then Wait.stop(pollHandle) end
    pollHandle=Wait.time(refreshStatus,2,-1)
end

function onSave()
    return JSON.encode({players=players,influence=influence,lastStatus=lastStatus})
end

function onDestroy()
    if pollHandle then Wait.stop(pollHandle) end
end
