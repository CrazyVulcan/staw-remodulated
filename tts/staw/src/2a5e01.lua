-- Standard two-player setup guides. This controller owns its own vector lines;
-- the playmat, ship arcs/ranges, and Alliance mission guides are never edited.
local BOARD_GUID="ae9c49"
local PLAY_AREA_HALF=18.1 -- visible mat perimeter, reduced from 18.8
local active=false
local loadGeneration=0
local RED={0.95,0.20,0.18}
local BLUE={0.12,0.62,1.0}
local GOLD={1.0,0.78,0.16}

local function component(v,key,index,default)
    return tonumber(v and (v[key] or v[index])) or default
end

local function boardFrame()
    local board=getObjectFromGUID(BOARD_GUID)
    if not board then return nil end
    local p,r,s=board.getPosition(),board.getRotation(),board.getScale()
    -- Match the visible play surface; keep the 4/8-inch insets in world units.
    -- TTS world units are inches; Range 1 is 3.94 because it represents 10 cm.
    return {x=component(p,"x",1,0),y=Global.call("STA2E_GuidePlane"),
        z=component(p,"z",3,0),yaw=component(r,"y",2,90)-90,
        -- Book/frame x follows the model's local z axis at its normal 90 yaw.
        halfX=PLAY_AREA_HALF*math.abs(component(s,"z",3,1.89))/1.89,
        halfZ=PLAY_AREA_HALF*math.abs(component(s,"x",1,1.89))/1.89}
end

local function worldPoint(frame,x,z)
    local angle=math.rad(frame.yaw)
    return {x=frame.x+x*math.cos(angle)+z*math.sin(angle),y=frame.y,
        z=frame.z-x*math.sin(angle)+z*math.cos(angle)}
end

local function polygon(frame,points,color)
    local result={points={},color=color,thickness=0.06}
    for _,point in ipairs(points) do
        local localPoint=self.positionToLocal(worldPoint(frame,point[1],point[2]))
        result.points[#result.points+1]={localPoint.x or localPoint[1],localPoint.y or localPoint[2],localPoint.z or localPoint[3]}
    end
    return result
end

local function drawGuides()
    local frame=boardFrame()
    if not frame or frame.halfX<=8 or frame.halfZ<=8 then return false end
    local x,z=frame.halfX,frame.halfZ
    self.setVectorLines({
        polygon(frame,{{-x,-z},{x,-z},{x,-z+4},{-x,-z+4},{-x,-z}},RED),
        polygon(frame,{{-x,z},{x,z},{x,z-4},{-x,z-4},{-x,z}},BLUE),
        polygon(frame,{{-x+8,-z+8},{x-8,-z+8},{x-8,z-8},{-x+8,z-8},{-x+8,-z+8}},GOLD)
    })
    return true
end

local function redrawButton()
    self.editButton({index=1,label=active and "HIDE SETUP LINES" or "2 PLAYER SETUP",
        color=active and {0.25,0.41,0.23,1} or {0.13,0.32,0.47,1}})
end

function noAction() end

function clearSetup()
    active=false
    loadGeneration=loadGeneration+1
    self.setVectorLines({})
    redrawButton()
end

function toggleSetup(_,color)
    if active then clearSetup();return end
    if drawGuides() then
        active=true
        redrawButton()
    elseif type(color)=="string" and color~="" then
        broadcastToColor("Standard setup needs the playmat on the table at its normal size.",color,{1,0.65,0.2})
    end
end

function onObjectDrop(_,object)
    if not active or not object or not object.getGUID then return end
    if object==self or object.getGUID()==BOARD_GUID then drawGuides() end
end

function onLoad(saved)
    local ok,state=pcall(JSON.decode,saved or "")
    active=ok and type(state)=="table" and state.active==true or false
    loadGeneration=loadGeneration+1
    local generation=loadGeneration
    self.setLock(true)
    self.setVectorLines({})
    self.clearButtons()
    self.createButton({click_function="noAction",function_owner=self,label="STANDARD ATTACK WING",
        position={0,1.05,-0.70},scale={0.5,0.5,0.5},width=0,height=0,font_size=105,font_color={1,1,1},tooltip="Two-player setup guides"})
    self.createButton({click_function="toggleSetup",function_owner=self,label="2 PLAYER SETUP",
        position={0,1.05,-0.15},scale={0.5,0.5,0.5},width=1220,height=330,font_size=130,
        color={0.13,0.32,0.47,1},font_color={1,1,1},tooltip="Show or hide two 4-inch deployment zones and the obstacle area 8 inches inside every edge."})
    self.createButton({click_function="clearSetup",function_owner=self,label="CLEAR LINES",
        position={0,1.05,0.40},scale={0.5,0.5,0.5},width=1220,height=270,font_size=110,
        color={0.45,0.18,0.16,1},font_color={1,1,1},tooltip="Remove only this tool's setup lines."})
    self.createButton({click_function="noAction",function_owner=self,label='4" DEPLOYMENT  /  8" OBSTACLES',
        position={0,1.05,0.83},scale={0.5,0.5,0.5},width=0,height=0,font_size=65,font_color=GOLD,tooltip="Red and blue zones: deployment. Gold boundary: obstacle placement area."})
    redrawButton()
    if active then
        local function restore(attempt)
            if not active or generation~=loadGeneration then return end
            if not drawGuides() and attempt<4 then Wait.frames(function()restore(attempt+1)end,30) end
        end
        Wait.frames(function()restore(1)end,3)
    end
end

function onSave()
    return JSON.encode({active=active})
end
