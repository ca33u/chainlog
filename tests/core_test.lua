-- Run: lua tests/core_test.lua (from the repo root)
dofile("tests/stubs.lua")
LoadFile("Locale.lua")
LoadFile("Core.lua")
local C = NS.Core

-- A made-up world: dungeon 100 (alt area 101), quests:
--  1 lead-in -> 2 (breadcrumb)
--  2 -> 3 (child) ; 3 is the dungeon quest (zone 100)
--  4 dungeon quest on the alt area, needs 5 OR 6 (6 is Alliance only)
--  7 Alliance-only dungeon quest
--  8 unrelated quest in another zone
local QUESTS = {
	[1] = { name = "Lead In", questLevel = 20, requiredLevel = 18, breadcrumbForQuestId = 2, startedBy = { { 50 } } },
	[2] = { name = "Prep", questLevel = 22, requiredLevel = 20, breadcrumbs = { 1 }, childQuests = { 3 }, startedBy = { { 51 } }, finishedBy = { { 51 } },
		objectives = { [3] = { { 901 } } } },
	[3] = { name = "Into The Dungeon", questLevel = 25, requiredLevel = 22, zoneOrSort = 100, preQuestSingle = { 2 }, startedBy = { { 51 } }, finishedBy = { { 50 } },
		objectives = { [1] = { { 60 } } } },
	[4] = { name = "Alt Area Quest", questLevel = 26, requiredLevel = 24, zoneOrSort = 101, preQuestSingle = { 5, 6 }, startedBy = { nil, nil, { 900 } } },
	[5] = { name = "Horde Prep", questLevel = 24, requiredLevel = 20, requiredRaces = 178 },
	[6] = { name = "Alliance Prep", questLevel = 24, requiredLevel = 20, requiredRaces = 77 },
	[7] = { name = "Alliance Dungeon", questLevel = 25, zoneOrSort = 100, requiredRaces = 77 },
	[8] = { name = "Elsewhere", questLevel = 10, zoneOrSort = 12 },
}
local NPCS = {
	[50] = { name = "Scout", spawns = { [130] = { { 40.5, 50.5 } } } },
	[51] = { name = "Elder", spawns = { [100] = { { 1, 1 } }, [130] = { { 44, 41 } } } },
	[60] = { name = "Boss", spawns = { [100] = { { 50, 50 } } } },
	[61] = { name = "Wolf", spawns = { [130] = { { 10, 10 }, { 80, 80 } } } },
}
local ITEMS = { [900] = { name = "Strange Map", npcDrops = { 60 } }, [901] = { name = "Wolf Pelt", npcDrops = { 61 } } }
local ids = {}
for id in pairs(QUESTS) do ids[#ids + 1] = id end
table.sort(ids)
local function G(t) return function(id, key) local r = t[id]; return r and r[key] end end
C.source.quest, C.source.npc, C.source.item = G(QUESTS), G(NPCS), G(ITEMS)
C.source.object = function() return nil end
C.source.allQuestIds = function() return ids end
C.source.dungeons = function()
	return { [100] = { "Test Hold", { 101 }, 130, { { 130, 60, 70 } } }, [2597] = { "Battleground", nil, 36, {} } }
end
C.source.areaName = function(a) return ({ [130] = "Silverpine" })[a] end
C.source.uiMap = function(a) return a == 130 and 21 or nil end

local done, log, level = {}, {}, 23
C.player = {
	level = function() return level end, race = function() return 5 end, class = function() return 2 end,
	done = function(id) return done[id] or false end, inLog = function(id) return log[id] or false end,
	complete = function() return false end,
}

Check(C.HasBit(178, 5), "undead bit set in Horde mask")
Check(not C.HasBit(77, 5), "undead bit not in Alliance mask")
Check(C.HasBit(8589934770, 5), "wide masks work")
Check(C.HasBit(nil, 5) and C.HasBit(0, 5), "no mask: anyone")

local idx = C.Build()
Check(#idx.dungeons == 1 and idx.dungeons[1].name == "Test Hold", "one dungeon; battleground skipped")
local d = idx.dungeons[1]
Check(#d.quests == 3, "alt area quests count for the dungeon (3, 4, 7)")
Check(C.DungeonOf(4) == d, "quest on the alt area maps to the dungeon")

local chains = C.DungeonChains(d)
Check(#chains == 2, "two chains (Alliance quests left out)")
local main = chains[1]
Check(main[1] == 1 and main[2] == 2 and main[3] == 3, "chain in order: lead-in, prep, dungeon quest")
local other = chains[2]
Check(other[1] == 5 and other[2] == 4 and #other == 2, "alt chain: Horde prep then the quest")

Check(C.Status(2) == "available", "prep available")
Check(C.Status(3) == "locked", "dungeon quest locked before prep")
Check(C.Status(4) == "locked", "needs Horde prep (Alliance alternative ignored)")
done[2] = true
Check(C.Status(3) == "available", "dungeon quest opens after prep")
Check(C.Status(1) == "skip", "lead-in not needed once its target is done")
level = 19
Check(select(1, C.Status(3)) == "level" and select(2, C.Status(3)) == 22, "too low level")
level = 23
log[3] = true
Check(C.Status(3) == "active", "in log")

local g = C.Giver(2)
Check(g and g.area == 130 and g.x == 44, "giver outside the dungeon preferred")
Check(C.FormatWhere(g) == "Elder - Silverpine (44, 41)", "where text")
local item = C.Giver(4)
Check(item and item.kind == "item" and item.inside and item.dungeon == "Test Hold", "item starter dropped inside the dungeon")
Check(C.FormatWhere(item):find("Strange Map", 1, true) ~= nil, "item starter text")

local chain, pos = C.ChainOf(2)
Check(#chain == 3 and pos == 2, "chain of a middle step")
Check(C.IsLinked(3) and C.IsLinked(2) and not C.IsLinked(8), "linked quests")

-- waypoint inside the dungeon points at the entrance
local got
TomTom = { AddWaypoint = function(_, map, x, y) got = { map, x, y } end }
Check(C.Waypoint(item, "x") and got[1] == 21 and math.abs(got[2] - 0.6) < 1e-9, "waypoint to the dungeon entrance via TomTom")
Check(C.Waypoint(g, "y") and math.abs(got[2] - 0.44) < 1e-9, "waypoint to the giver")

-- abandon warning
LoadFile("Util.lua")
LoadFile("Window.lua")
LoadFile("Abandon.lua")
local lines = NS.Abandon.Lines(2)
Check(lines and lines[1]:find("Step 2 of 3", 1, true) ~= nil, "warning names the step")
local joined = table.concat(lines or {}, "|")
Check(joined:find("Into The Dungeon", 1, true) ~= nil, "warning lists the next step")
Check(joined:find("Silverpine", 1, true) ~= nil, "warning says where to take it again")
Check(NS.Abandon.Lines(8) == nil, "no warning for a lone quest")
Check(NS.Abandon.Lines(3) ~= nil and table.concat(NS.Abandon.Lines(3)):find("Test Hold", 1, true) ~= nil, "dungeon quest warning")

-- the hook fires on SetAbandonQuest
ChainlogDB = { warn = true }
C_QuestLog = {
	SetAbandonQuest = function() end,
	GetAbandonQuest = function() return 2 end,
}
LoadFile("Abandon.lua")
local okHook = pcall(C_QuestLog.SetAbandonQuest)
Check(okHook, "abandon hook runs")

-- window smoke: open, build the index synchronously, render both tabs
LibQuestieDB = { Quest = {} } -- marks the source as available
C.source.available = function() return true end
local W = NS.Window
local okOpen, err = pcall(W.Open, "dungeons")
Check(okOpen, "window opens " .. tostring(err or ""))
Check(pcall(W.Refresh), "refresh while building")
Check(pcall(W.BuildNow), "index builds")
local okD, errD = pcall(W.Refresh)
Check(okD, "dungeons tab renders " .. tostring(errD or ""))
C.LogQuests = function() return { 2, 8 } end
local okL, errL = pcall(W.Open, "log")
Check(okL, "my quests tab renders " .. tostring(errL or ""))
Check(W.selected == 2, "my quests: the chain quest is selected, the lone one is left out")

-- objective spots: nearest on the current map, else the most common zone
local spots = C.ObjectiveSpots(2)
Check(#spots == 2 and spots[1].name:find("Wolf Pelt", 1, true) ~= nil, "item objective: where it drops")
local near = C.ObjectiveSpot(2, { map = 21, x = 75, y = 75 })
Check(near and near.x == 80, "nearest spot on your map")
Check(C.ObjectiveSpot(2, { map = 99 }).area == 130, "elsewhere: the zone with the spots")

-- guide: follow the chain 1 -> 2 -> 3
LoadFile("Guide.lua")
local Gd = NS.Guide
local added, removed = {}, 0
TomTom = {
	AddWaypoint = function(_, map, x, y, opts) local uid = { map, x, y, title = opts.title, crazy = opts.crazy }; added[#added + 1] = uid; return uid end,
	RemoveWaypoint = function() removed = removed + 1 end,
}
done, log = {}, {}
level = 23
local okStart = pcall(Gd.Start, 2)
Check(okStart and Gd.chain and #Gd.chain == 3, "start leading the chain of a middle step")
Check(Gd.step and Gd.step.action == "take" and Gd.step.quest == 1, "first: take the lead-in")
Check(#added == 1 and added[1].crazy == true and math.abs(added[1][2] - 0.405) < 1e-9, "arrow to the lead-in giver")
done[1] = true
Gd.Update()
Check(Gd.step.action == "take" and Gd.step.quest == 2 and removed == 1, "lead-in done: arrow moves to the next giver")
log[2] = true
C.player.complete = function() return false end
Gd.Update()
Check(Gd.step.action == "do" and Gd.step.where and Gd.step.where.name:find("Wolf", 1, true), "in log: arrow to the objective")
local before = #added
Gd.Update()
Check(#added == before, "same target: the waypoint is not reset")
C.player.complete = function(id) return id == 2 end
Gd.Update()
Check(Gd.step.action == "turnin" and Gd.step.where.name == "Elder", "objectives done: arrow to the turn-in")
log[2] = nil; done[2] = true
C.player.complete = function() return false end
Gd.Update()
Check(Gd.step.action == "take" and Gd.step.quest == 3, "turned in: next step")
log[3] = true
Gd.Update()
local last = added[#added]
Check(Gd.step.action == "do" and last[1] == 21 and math.abs(last[2] - 0.6) < 1e-9, "objective inside the dungeon: arrow to the entrance")
log[3] = nil; done[3] = true
Gd.Update()
Check(Gd.chain == nil and ChainlogDB.guide == nil, "chain finished: guide stops")
Check(Gd.Describe(nil) == "Chain finished!", "finished text")
Gd.Start(3)
Check(Gd.chain == nil or Gd.step == nil, "an already finished chain stops at once")
-- dungeon targets and the tracker
LoadFile("Tracker.lua")
local TRK = NS.Tracker
done, log = { [1] = true, [2] = true }, { [3] = true }
C.player.complete = function() return false end
local objs = { { text = "Boss slain: 0/1", finished = false } }
C.player.objectives = function(id) return id == 3 and objs or nil end
d = C.index.dungeons[1] -- the window rebuilt the index above
local tg = C.DungeonTargets(d, C.DungeonChains(d))
Check(#tg == 1 and tg[1].kind == "kill" and tg[1].name == "Boss", "inside: kill the boss for the active quest")
Check(not C.TargetDone(tg[1]), "boss not done yet")
objs[1].finished = true
Check(C.TargetDone(tg[1]), "boss ticked off from the quest log line")
GetInstanceInfo = function() return "Test Hold", "party", 1, "", 5, 0, false, 9999 end
Check(C.CurrentDungeon() == d, "current dungeon found by name")
objs[1].finished = false
local tl, left = TRK.Collect(d, C.DungeonChains(d))
Check(#tl == 1 and left == 1, "tracker lists the boss")
log[3] = nil; done[3] = true
tl, left = TRK.Collect(d, C.DungeonChains(d))
Check(#tl == 1 and left == 0 and tl[1].done, "quest turned in: the line stays, ticked")
Check(pcall(TRK.Refresh), "tracker panel renders")
GetInstanceInfo = function() return "Elsewhere", "none" end
Check(C.CurrentDungeon() == nil, "outside: no dungeon")

QUESTS[9] = { name = "Deliver", questLevel = 20, finishedBy = { { 51 } }, childQuests = { 10 } }
QUESTS[10] = { name = "After", questLevel = 21, preQuestSingle = { 9 }, startedBy = { { 51 } } }
log[9] = true
local st = Gd.NextStep({ 9, 10 })
Check(st.action == "turnin" and st.where and st.where.name == "Elder", "no objective spots: head for the turn-in")
Report("core_test")
