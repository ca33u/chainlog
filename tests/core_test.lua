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
	[2] = { name = "Prep", questLevel = 22, requiredLevel = 20, breadcrumbs = { 1 }, childQuests = { 3 }, startedBy = { { 51 } }, finishedBy = { { 51 } } },
	[3] = { name = "Into The Dungeon", questLevel = 25, requiredLevel = 22, zoneOrSort = 100, preQuestSingle = { 2 }, startedBy = { { 51 } } },
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
}
local ITEMS = { [900] = { name = "Strange Map", npcDrops = { 60 } } }
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
Report("core_test")
