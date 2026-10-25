-- Focused tests for patch_startup.py using the release's mocked TTS API.
-- These verify scheduling/state, not Unity compilation, network or asset loads.
local function startupTick()
    assert(#_waits>0,"startup stopped scheduling callbacks")
    table.sort(_waits,function(a,b)return a.time==b.time and a.seq<b.seq or a.time<b.time end)
    local job=table.remove(_waits,1);Time.time=job.time;job.fn()
end
local function startupSave(round)
    STA2E.game.round=round or 1
    return JSON.encode({schemaVersion=1,game=STA2E.game})
end

test("Startup serializes world reconciliation and coalesces ship renders",function()
    _reset()
    for i=1,4 do _ship("serial-"..i,"Blue") end
    local saved=startupSave(4)
    onLoad(saved)
    assert(not STA2E.ready and STA2E.loading,"startup exposed controls immediately")
    local steps=0
    while not STA2E.ready do
        steps=steps+1;assert(steps<3000,"startup failed to finish")
        local before={}
        for _,key in ipairs({"objects","registered","linked","normalized","rendered"}) do before[key]=(STA2E.startupStats or {})[key] or 0 end
        startupTick()
        for key,value in pairs(before) do
            assert(((STA2E.startupStats or {})[key] or 0)-value<=1,"multiple "..key.." processed in one callback")
        end
    end
    _drain()
    assert(not STA2E.loading and not STA2E.reconciling and STA2E.startupStage=="complete")
    assert(STA2E.startupStats.objects==20 and STA2E.startupStats.registered==4)
    assert(STA2E.startupStats.linked==4 and STA2E.startupStats.rendered==4,"duplicate or missing ship renders")
    assert(STA2E.startupStats.cards==#CATALOG_DATA.cards)
    assert(CATALOG.M5S001 and SHIP_DEFINITIONS.M5S001,"final M5 reconcile wrapper was bypassed")
    assert(STA2E.game.round==4)
end)

test("Reload supersedes a partially completed startup queue",function()
    _reset();_ship("reload-serial","Blue")
    onLoad(startupSave(2));local oldEpoch=STA2E.startupEpoch
    for i=1,8 do startupTick() end
    assert(not STA2E.ready)
    onLoad(startupSave(7))
    assert(STA2E.startupEpoch==oldEpoch+1)
    _drain(5000)
    assert(STA2E.ready and not STA2E.loading and STA2E.game.round==7)
    assert(STA2E.startupStats.rendered==1 and STA2E.startupStats.registered==1)
    assert(STA2E.startupStats.cards==#CATALOG_DATA.cards,"stale startup changed the new catalog")
end)

test("Startup failure remains guarded and a subsequent reload recovers",function()
    _reset()
    local original=STA2E_Reconcile
    STA2E_Reconcile=function()error("intentional startup failure")end
    onLoad(startupSave(3));_drain(5000)
    assert(not STA2E.ready and STA2E.loading and STA2E.startupStage=="failed")
    assert(not STA2E.startupThread and not STA2E.startupRegistering)
    STA2E_Reconcile=original
    onLoad(startupSave(9));_drain(5000)
    assert(STA2E.ready and not STA2E.loading and STA2E.game.round==9)
end)

test("Ordinary reconcile stays synchronous after serial startup",function()
    _reset();_ship("ordinary-reconcile","Blue")
    local ok,err=pcall(STA2E_Reconcile)
    assert(ok,tostring(err))
    assert(not STA2E.reconciling and STA2E.ships["ordinary-reconcile"])
    assert(pcall(function()STA2E_StartupYield("outside")end),"yield helper suspended an ordinary callback")
end)
