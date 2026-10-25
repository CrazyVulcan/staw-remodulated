-- Reusable Alliance objective hull counter. Zero hull keeps the token on the
-- table, with its controls available for correcting damage or repairing an undo.
local hullMemory={hull=8,maxHull=8,kind="objective",missionId="",runId="",label="Objective"}

local function hullClamp(value,maximum)
    return math.max(0,math.min(maximum,math.floor(tonumber(value) or maximum)))
end

function getHull()
    return {guid=self.getGUID(),hull=hullMemory.hull,maxHull=hullMemory.maxHull,
        kind=hullMemory.kind,missionId=hullMemory.missionId,runId=hullMemory.runId,
        label=hullMemory.label,index=hullMemory.index,destroyed=hullMemory.hull==0}
end

local function hullDraw()
    self.clearButtons()
    local dead=hullMemory.hull==0
    self.setColorTint(dead and {0.38,0.38,0.38} or {1,1,1})
    self.setDescription((hullMemory.rules or "").."\nHull: "..hullMemory.hull.." / "..hullMemory.maxHull..
        (dead and "\nDESTROYED. Token retained; + can correct damage." or "\nUse - for damage and + to correct or restore hull."))
    self.createButton({function_owner=self,click_function="hullNoop",
        label=(dead and "DESTROYED\n" or "HULL\n")..hullMemory.hull.." / "..hullMemory.maxHull,
        position={0,0.23,0},rotation={0,0,0},width=0,height=0,font_size=175,
        font_color=dead and {1,0.35,0.25} or {1,1,1},tooltip="Current hull / maximum hull"})
    self.createButton({function_owner=self,click_function="hullMinus",label="-",
        position={-0.72,0.24,0.72},rotation={0,0,0},width=400,height=340,font_size=260,
        color={0.56,0.14,0.10,0.96},font_color={1,1,1},tooltip="Remove 1 hull (minimum 0)"})
    self.createButton({function_owner=self,click_function="hullPlus",label="+",
        position={0.72,0.24,0.72},rotation={0,0,0},width=400,height=340,font_size=260,
        color={0.10,0.40,0.22,0.96},font_color={1,1,1},tooltip="Restore 1 hull (maximum "..hullMemory.maxHull..")"})
end

function hullNoop() end

function setHull(params)
    local request=type(params)=="table" and params or {hull=params}
    local previous=hullMemory.hull
    if request.maxHull then hullMemory.maxHull=math.max(1,math.floor(tonumber(request.maxHull) or hullMemory.maxHull)) end
    hullMemory.hull=hullClamp(request.hull,hullMemory.maxHull)
    hullDraw()
    local event=getHull()
    if not request.silent and hullMemory.hull~=previous then
        -- Global validates both runId and missionId, so an old token cannot
        -- alter the results of a later mission after a reset or reload.
        pcall(function() Global.call("STA2E_MissionHullChanged",event) end)
    end
    return event
end

function hullMinus() return setHull({hull=hullMemory.hull-1}) end
function hullPlus() return setHull({hull=hullMemory.hull+1}) end

function onLoad(saved)
    if saved and saved~="" then
        local ok,decoded=pcall(JSON.decode,saved)
        if ok and type(decoded)=="table" then
            for key,value in pairs(decoded) do hullMemory[key]=value end
        end
    end
    hullMemory.maxHull=math.max(1,math.floor(tonumber(hullMemory.maxHull) or 8))
    hullMemory.hull=hullClamp(hullMemory.hull,hullMemory.maxHull)
    self.setLock(true)
    hullDraw()
end

function onSave() return JSON.encode(hullMemory) end
