local players=2
local difficulty="regular"

local MISSION={
    id="A1M1",
    name="Alliance Act I — A Simple Patrol",
    startTokenImage="https://steamusercontent-a.akamaihd.net/ugc/15124136587514081326/767C98EB6EB818EEFE4DB2043199556D1CFD5A01/",
    mapImage="https://i.imgur.com/3U3F7Y5.png",
    asteroidCount=6,
    asteroidZoneSize=18.8,
    asteroidMinDistance=6.25,
    asteroidImage="https://i.imgur.com/ZY0cmma.png",
    missionBook={url="https://steamusercontent-a.akamaihd.net/ugc/2027235400877448693/4F5A363E686CDB0237BD57885CE820D2FD9CF558/"},
    objectives={
        {name="Odd Mission Token",image="https://steamusercontent-a.akamaihd.net/ugc/1696156843858188507/14C2AA1C8ECC251B68C83F98356D50F3A7CDD27F/",offset={10.15,1,-10.15},scale=0.25},
        {name="Even Mission Token",image="https://steamusercontent-a.akamaihd.net/ugc/1696156843858194629/7F967A885772CB4EBCB3E478731A68C149E09630/",offset={10.15,1,10.15},scale=0.25},
    },
    profiles={
        generic={cardId="285600",className="Jem'Hadar Attack Ship",definitionId="S301",skill=1,shields=3,
            description="Alliance Generic profile · Skill 1 · 3 Shields"},
        advanced={cardId="325000",className="Jem'Hadar Attack Ship",definitionId="S301",skill=4,shields=3,
            description="Alliance Advanced profile · Skill 4 · 3 Shields. Resolve the printed advanced ability manually."},
    },
    setup={
        [2]={
            {profile="generic",position={-6.05,1.3,17.43},rotation=0},
            {profile="generic",position={6.04,1.3,17.42},rotation=0},
        },
        [3]={
            {profile="generic",position={-7.44,1.3,17.38},rotation=0},
            {profile="generic",position={-4.68,1.3,17.40},rotation=0},
            {profile="generic",position={6.04,1.3,17.42},rotation=0},
        },
        [4]={
            {profile="generic",position={-7.44,1.3,17.38},rotation=0},
            {profile="generic",position={-4.68,1.3,17.40},rotation=0},
            {profile="generic",position={4.68,1.3,17.43},rotation=0},
            {profile="generic",position={7.44,1.3,17.46},rotation=0},
        },
        [5]={
            {profile="generic",position={-7.44,1.3,17.38},rotation=0},
            {profile="generic",position={-4.68,1.3,17.40},rotation=0},
            {profile="generic",position={4.68,1.3,17.43},rotation=0},
            {profile="generic",position={7.44,1.3,17.46},rotation=0},
        },
        [6]={
            {profile="generic",position={-7.44,1.3,17.38},rotation=0},
            {profile="generic",position={-4.68,1.3,17.40},rotation=0},
            {profile="generic",position={4.68,1.3,17.43},rotation=0},
            {profile="generic",position={7.44,1.3,17.46},rotation=0},
        },
    },
    -- Counts are transcribed from the original A Simple Patrol deployment helpers.
    events={
        {round=2,profile="generic",counts={[5]=1,[6]=2}},
        {round=3,profile="advanced",counts={[2]=1,[3]=1,[4]=2,[5]=2,[6]=2}},
        {round=6,profile="generic",counts={[2]=1,[3]=2,[4]=2,[5]=3,[6]=3}},
    },
}

local function redraw()
    self.editButton({index=0,label=players.." PLAYERS"})
    self.editButton({index=1,label=string.upper(difficulty)})
end

function choosePlayers()
    players=players%6+1
    if players<2 then players=2 end
    redraw()
end

function chooseDifficulty()
    difficulty=difficulty=="regular" and "advanced" or "regular"
    redraw()
end

function startMission(_,color)
    local result=Global.call("STA2E_AllianceStart",{definition=MISSION,playerCount=players,difficulty=difficulty})
    if not result or not result.ok then
        broadcastToColor((result and result.error) or "Alliance mission could not start.",color,{1,0.35,0.25})
    end
end

function onLoad(saved)
    local ok,state=pcall(JSON.decode,saved or "")
    if ok and type(state)=="table" then players=tonumber(state.players) or players;difficulty=state.difficulty or difficulty end
    self.setLock(true)
    self.createButton({click_function="choosePlayers",function_owner=self,label="2 PLAYERS",position={-0.82,0.18,0.08},rotation={0,0,0},width=820,height=300,font_size=135,color={0.12,0.25,0.36,0.95},font_color={1,1,1}})
    self.createButton({click_function="chooseDifficulty",function_owner=self,label="REGULAR",position={0.82,0.18,0.08},rotation={0,0,0},width=820,height=300,font_size=135,color={0.35,0.25,0.12,0.95},font_color={1,1,1}})
    self.createButton({click_function="startMission",function_owner=self,label="START MISSION",position={0,0.18,-0.62},rotation={0,0,0},width=1500,height=320,font_size=160,color={0.18,0.48,0.30,0.98},font_color={1,1,1}})
    redraw()
end

function onSave() return JSON.encode({players=players,difficulty=difficulty}) end
