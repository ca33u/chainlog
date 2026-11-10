--[[
  Chainlog core: quest data, dungeon index, chains and quest status.

  Quest data is read at run time from QuestieDB's public API
  (LibQuestieDB.Quest/Npc/Object/Item.Get and LibQuestieDB.Support). Chainlog
  ships no quest data of its own.

  A "chain" is every quest connected to a dungeon quest through
  prerequisites (preQuestSingle / preQuestGroup), lead-ins (breadcrumbs) and
  follow-ups (childQuests / nextQuestInChain), limited to quests your race
  and class can take. Each chain is listed in the order you do it.

  All reads are guarded: a missing field or an API change gives empty
  results instead of Lua errors.
]]

local ADDON_NAME, ns = ...
ns = ns or {}
local T = ns.T or function(text)
	return text
end

local C = {}
ns.Core = C

local MAX_DEPTH = 25 -- how far a chain is followed in each direction

------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------

local function IsSecret(v)
	return issecretvalue and issecretvalue(v) and true or false
end

local function Call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if not ok or IsSecret(a) then
		return nil
	end
	return a, b, c
end

------------------------------------------------------------------------
-- Data source (QuestieDB). Tests replace C.source.
------------------------------------------------------------------------

local function Entity(name)
	local lib = _G.LibQuestieDB
	return type(lib) == "table" and type(lib[name]) == "table" and lib[name] or nil
end

local function Getter(name)
	return function(id, key)
		local e = Entity(name)
		return e and Call(e.Get, id, key) or nil
	end
end

local zoneSupport -- LibQuestieDB.Support "ZoneDB" module, or false

local function ZoneSupport()
	if zoneSupport == nil then
		zoneSupport = false
		local lib = _G.LibQuestieDB
		local support = type(lib) == "table" and lib.Support
		if type(support) == "table" then
			local z = Call(support.Get, "ZoneDB")
			if type(z) == "table" and type(z.private) == "table" then
				zoneSupport = z.private
			end
		end
	end
	return zoneSupport or nil
end

-- "return {...}" strings are loaded once.
local function LoadTable(value)
	if type(value) == "table" then
		return value
	end
	if type(value) == "string" and type(loadstring or load) == "function" then
		local fn = (loadstring or load)(value)
		local ok, t = pcall(fn or function() end)
		if ok and type(t) == "table" then
			return t
		end
	end
	return nil
end

local areaMap -- areaId -> uiMapID

C.source = {
	quest = Getter("Quest"),
	npc = Getter("Npc"),
	object = Getter("Object"),
	item = Getter("Item"),
	available = function()
		return Entity("Quest") ~= nil
	end,
	allQuestIds = function()
		local e = Entity("Quest")
		return e and Call(e.GetAllIds) or {}
	end,
	dungeons = function()
		local z = ZoneSupport()
		return z and LoadTable(z.dungeons) or {}
	end,
	uiMap = function(areaId)
		if areaMap == nil then
			areaMap = {}
			local z = ZoneSupport()
			if z then
				for _, key in ipairs({ "areaIdToUiMapId", "areaIdToUiMapIdOverride" }) do
					local t = LoadTable(z[key])
					if t then
						for k, v in pairs(t) do
							areaMap[k] = v
						end
					end
				end
			end
		end
		local m = areaMap[areaId]
		return (m and m > 0) and m or nil
	end,
	areaName = function(areaId)
		local name = C_Map and Call(C_Map.GetAreaInfo, areaId)
		return type(name) == "string" and name ~= "" and name or nil
	end,
}

local function Q(id, key)
	return C.source.quest(id, key)
end

------------------------------------------------------------------------
-- Player (tests replace C.player)
------------------------------------------------------------------------

local function IsDone(id)
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		return Call(C_QuestLog.IsQuestFlaggedCompleted, id) == true
	end
	return Call(IsQuestFlaggedCompleted, id) == true
end

local function InLog(id)
	if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		local i = Call(C_QuestLog.GetLogIndexForQuestID, id)
		return type(i) == "number" and i > 0
	end
	return false
end

local function IsComplete(id)
	return C_QuestLog and Call(C_QuestLog.IsComplete, id) == true or false
end

C.player = {
	level = function()
		return Call(UnitLevel, "player") or 1
	end,
	race = function()
		local _, _, id = Call(UnitRace, "player")
		return id
	end,
	class = function()
		local _, _, id = Call(UnitClass, "player")
		return id
	end,
	done = IsDone,
	inLog = InLog,
	complete = IsComplete,
}

------------------------------------------------------------------------
-- Pure helpers
------------------------------------------------------------------------

-- Is bit (n-1) set in mask? Masks can be wider than 32 bits, so no bit library.
function C.HasBit(mask, n)
	if type(mask) ~= "number" or mask == 0 then
		return true -- no restriction
	end
	if type(n) ~= "number" or n < 1 then
		return true
	end
	return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end

-- Can this character take the quest at all (race and class)?
function C.ForMe(id)
	if Q(id, "name") == nil then
		return false
	end
	return C.HasBit(Q(id, "requiredRaces"), C.player.race())
		and C.HasBit(Q(id, "requiredClasses"), C.player.class())
end

local function List(v)
	return type(v) == "table" and v or {}
end

------------------------------------------------------------------------
-- Dungeons
------------------------------------------------------------------------

-- Level ranges for the classic dungeons and raids (area ID -> min, max, raid).
-- Others (Forever's additions) take their range from their quests.
C.LEVELS = {
	[2437] = { 13, 18 }, [718] = { 17, 24 }, [1581] = { 17, 26 }, [209] = { 22, 30 },
	[719] = { 24, 32 }, [717] = { 24, 32 }, [721] = { 29, 38 }, [491] = { 29, 38 },
	[796] = { 34, 45 }, [722] = { 37, 46 }, [1337] = { 41, 51 }, [1176] = { 44, 54 },
	[2100] = { 46, 55 }, [1477] = { 50, 60 }, [1584] = { 52, 60 }, [2557] = { 55, 60 },
	[1583] = { 55, 60 }, [2057] = { 58, 60 }, [2017] = { 58, 60 },
	[1977] = { 60, 60, true }, [2159] = { 60, 60, true }, [2717] = { 60, 60, true },
	[2677] = { 60, 60, true }, [3428] = { 60, 60, true }, [3429] = { 60, 60, true },
	[3456] = { 60, 60, true },
}
-- Not dungeons: battlegrounds, cities, the tram.
C.SKIP = { [2257] = true, [2597] = true, [2917] = true, [2918] = true, [3277] = true, [3358] = true }

C.index = nil -- built by C.Build

-- Builds the dungeon list and assigns quests to dungeons. When `step` is
-- given it is called every `step` quests (the window uses it to yield).
function C.Build(yield, step)
	local dungeons, byArea = {}, {}
	for areaId, d in pairs(C.source.dungeons()) do
		if type(areaId) == "number" and type(d) == "table" and not C.SKIP[areaId] then
			local entry = {
				area = areaId,
				name = (type(d[1]) == "string" and d[1]) or C.source.areaName(areaId) or tostring(areaId),
				parent = d[3],
				entrances = List(d[4]),
				quests = {},
			}
			local lv = C.LEVELS[areaId]
			if lv then
				entry.min, entry.max, entry.raid = lv[1], lv[2], lv[3] or false
			end
			dungeons[#dungeons + 1] = entry
			byArea[areaId] = entry
			for _, alt in ipairs(List(d[2])) do
				byArea[alt] = byArea[alt] or entry
			end
		end
	end
	local ids = C.source.allQuestIds() or {}
	for n, id in ipairs(ids) do
		local z = Q(id, "zoneOrSort")
		local d = type(z) == "number" and byArea[z]
		if d then
			d.quests[#d.quests + 1] = id
		end
		if yield and step and n % step == 0 then
			yield()
		end
	end
	local kept = {}
	for _, d in ipairs(dungeons) do
		if #d.quests > 0 then
			if not d.min then
				local lo, hi
				for _, id in ipairs(d.quests) do
					local l = Q(id, "questLevel")
					if type(l) == "number" and l > 0 then
						lo = lo and math.min(lo, l) or l
						hi = hi and math.max(hi, l) or l
					end
				end
				d.min, d.max = lo or 0, hi or 0
			end
			kept[#kept + 1] = d
		end
	end
	table.sort(kept, function(a, b)
		if (a.raid or false) ~= (b.raid or false) then
			return not a.raid
		end
		if a.min ~= b.min then
			return a.min < b.min
		end
		return a.name < b.name
	end)
	C.index = { dungeons = kept, byArea = byArea }
	return C.index
end

function C.DungeonOf(id)
	if not C.index then
		return nil
	end
	local z = Q(id, "zoneOrSort")
	return type(z) == "number" and C.index.byArea[z] or nil
end

------------------------------------------------------------------------
-- Chains
------------------------------------------------------------------------

-- Prerequisites: { all = {...}, any = {...} }
function C.Prereqs(id)
	return { all = List(Q(id, "preQuestGroup")), any = List(Q(id, "preQuestSingle")) }
end

-- Quests that this one leads to.
function C.Next(id)
	local out, seen = {}, {}
	for _, c in ipairs(List(Q(id, "childQuests"))) do
		if not seen[c] then
			seen[c] = true
			out[#out + 1] = c
		end
	end
	local n = Q(id, "nextQuestInChain")
	if type(n) == "number" and n > 0 and not seen[n] then
		out[#out + 1] = n
	end
	return out
end

-- Every quest connected to `roots`, for this character. Returns the set.
function C.Component(roots)
	local set, queue = {}, {}
	for _, id in ipairs(roots) do
		if C.ForMe(id) then
			set[id] = 0
			queue[#queue + 1] = id
		end
	end
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head = head + 1
		local depth = set[id]
		if depth < MAX_DEPTH then
			local p = C.Prereqs(id)
			local links = {}
			for _, x in ipairs(p.all) do links[#links + 1] = x end
			for _, x in ipairs(p.any) do links[#links + 1] = x end
			for _, x in ipairs(List(Q(id, "breadcrumbs"))) do links[#links + 1] = x end
			local b = Q(id, "breadcrumbForQuestId")
			if type(b) == "number" and b > 0 then links[#links + 1] = b end
			for _, x in ipairs(C.Next(id)) do links[#links + 1] = x end
			for _, x in ipairs(links) do
				if type(x) == "number" and x > 0 and set[x] == nil and C.ForMe(x) then
					set[x] = depth + 1
					queue[#queue + 1] = x
				end
			end
		end
	end
	return set
end

-- Splits a set of quests into connected groups and orders each group so
-- every prerequisite comes before the quests that need it.
function C.Chains(set)
	local ids = {}
	for id in pairs(set) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	-- edges inside the set: before -> after
	local after, before = {}, {}
	local function Edge(a, b)
		if set[a] and set[b] and a ~= b then
			after[a] = after[a] or {}
			after[a][b] = true
			before[b] = before[b] or {}
			before[b][a] = true
		end
	end
	for _, id in ipairs(ids) do
		local p = C.Prereqs(id)
		for _, x in ipairs(p.all) do Edge(x, id) end
		for _, x in ipairs(p.any) do Edge(x, id) end
		for _, x in ipairs(List(Q(id, "breadcrumbs"))) do Edge(x, id) end
		local b = Q(id, "breadcrumbForQuestId")
		if type(b) == "number" then Edge(id, b) end
		for _, x in ipairs(C.Next(id)) do Edge(id, x) end
	end
	-- connected groups
	local group, groups = {}, {}
	for _, id in ipairs(ids) do
		if not group[id] then
			local g = {}
			local stack = { id }
			group[id] = g
			while #stack > 0 do
				local x = table.remove(stack)
				g[#g + 1] = x
				for _, links in ipairs({ after[x] or {}, before[x] or {} }) do
					for y in pairs(links) do
						if not group[y] then
							group[y] = g
							stack[#stack + 1] = y
						end
					end
				end
			end
			groups[#groups + 1] = g
		end
	end
	-- order each group (Kahn; ties by level, then name)
	local function Lvl(id)
		local l = Q(id, "questLevel")
		return type(l) == "number" and l or 0
	end
	local function Less(a, b)
		if Lvl(a) ~= Lvl(b) then
			return Lvl(a) < Lvl(b)
		end
		return (Q(a, "name") or "") < (Q(b, "name") or "")
	end
	local chains = {}
	for _, g in ipairs(groups) do
		local indeg, inGroup = {}, {}
		for _, id in ipairs(g) do
			inGroup[id] = true
		end
		for _, id in ipairs(g) do
			local n = 0
			for y in pairs(before[id] or {}) do
				if inGroup[y] then
					n = n + 1
				end
			end
			indeg[id] = n
		end
		local ready, order = {}, {}
		for _, id in ipairs(g) do
			if indeg[id] == 0 then
				ready[#ready + 1] = id
			end
		end
		while #ready > 0 do
			table.sort(ready, function(a, b)
				return Less(b, a)
			end)
			local id = table.remove(ready)
			order[#order + 1] = id
			for y in pairs(after[id] or {}) do
				if inGroup[y] then
					indeg[y] = indeg[y] - 1
					if indeg[y] == 0 then
						ready[#ready + 1] = y
					end
				end
			end
		end
		-- a cycle in the data: append what is left
		if #order < #g then
			local placed = {}
			for _, id in ipairs(order) do placed[id] = true end
			local rest = {}
			for _, id in ipairs(g) do
				if not placed[id] then rest[#rest + 1] = id end
			end
			table.sort(rest, Less)
			for _, id in ipairs(rest) do order[#order + 1] = id end
		end
		chains[#chains + 1] = order
	end
	table.sort(chains, function(a, b)
		return Less(a[#a], b[#b])
	end)
	return chains
end

-- Chains for one dungeon (the dungeon's own quests plus everything linked).
function C.DungeonChains(d)
	return C.Chains(C.Component(d.quests))
end

-- The chain a quest belongs to, and its position in it.
function C.ChainOf(id)
	local chains = C.Chains(C.Component({ id }))
	for _, chain in ipairs(chains) do
		for i, x in ipairs(chain) do
			if x == id then
				return chain, i
			end
		end
	end
	return { id }, 1
end

------------------------------------------------------------------------
-- Status
------------------------------------------------------------------------

-- "done", "ready", "active", "available", "level", "locked", "skip"
function C.Status(id)
	local P = C.player
	if P.done(id) then
		return "done"
	end
	if P.inLog(id) then
		return P.complete(id) and "ready" or "active"
	end
	-- a lead-in is pointless once its target is taken or done
	local target = Q(id, "breadcrumbForQuestId")
	if type(target) == "number" and target > 0 and (P.done(target) or P.inLog(target)) then
		return "skip"
	end
	local p = C.Prereqs(id)
	for _, x in ipairs(p.all) do
		if C.ForMe(x) and not P.done(x) then
			return "locked"
		end
	end
	if #p.any > 0 then
		local any, relevant = false, false
		for _, x in ipairs(p.any) do
			if C.ForMe(x) then
				relevant = true
				if P.done(x) then
					any = true
					break
				end
			end
		end
		if relevant and not any then
			return "locked"
		end
	end
	local need = Q(id, "requiredLevel")
	if type(need) == "number" and need > (P.level() or 1) then
		return "level", need
	end
	return "available"
end

------------------------------------------------------------------------
-- Where: quest givers and turn-ins
------------------------------------------------------------------------

local function IsDungeonArea(area)
	return C.index and C.index.byArea[area] ~= nil
end

-- Picks one spawn: outside dungeons first, the zone with most spawns wins.
local function BestSpawn(spawns)
	if type(spawns) ~= "table" then
		return nil
	end
	local best, bestScore
	for area, list in pairs(spawns) do
		if type(area) == "number" and type(list) == "table" and type(list[1]) == "table" then
			local score = #list + (IsDungeonArea(area) and 0 or 1000)
			if not bestScore or score > bestScore then
				best, bestScore = { area = area, x = list[1][1], y = list[1][2] }, score
			end
		end
	end
	return best
end

-- { kind = "npc"|"object"|"item", name, area, x, y, inside, dungeon } or nil
local function Locate(kind, id)
	local getter = C.source[kind]
	local name = getter(id, "name")
	if not name then
		return nil
	end
	local spot = BestSpawn(getter(id, "spawns"))
	local out = { kind = kind, id = id, name = name }
	if spot then
		out.area, out.x, out.y = spot.area, spot.x, spot.y
		local d = C.index and C.index.byArea[spot.area]
		if d then
			out.inside, out.dungeon = true, d.name
		end
	end
	return out
end

local function Who(field, id)
	local by = Q(id, field)
	if type(by) ~= "table" then
		return nil
	end
	for _, npc in ipairs(List(by[1])) do
		local w = Locate("npc", npc)
		if w then
			return w
		end
	end
	for _, obj in ipairs(List(by[2])) do
		local w = Locate("object", obj)
		if w then
			return w
		end
	end
	for _, item in ipairs(List(by[3])) do
		local name = C.source.item(item, "name")
		if name then
			local w = { kind = "item", id = item, name = name }
			-- where it drops: the first dropping creature's spot
			for _, npc in ipairs(List(C.source.item(item, "npcDrops"))) do
				local at = Locate("npc", npc)
				if at then
					w.from, w.area, w.x, w.y, w.inside, w.dungeon = at.name, at.area, at.x, at.y, at.inside, at.dungeon
					break
				end
			end
			return w
		end
	end
	return nil
end

function C.Giver(id)
	return Who("startedBy", id)
end

function C.Ender(id)
	return Who("finishedBy", id)
end

------------------------------------------------------------------------
-- Where to do a quest's objectives
------------------------------------------------------------------------

-- Where the player is: { map = uiMapID, x = 0-100, y = 0-100 } or nil.
function C.Here()
	if not (C_Map and C_Map.GetBestMapForUnit) then
		return nil
	end
	local map = Call(C_Map.GetBestMapForUnit, "player")
	if type(map) ~= "number" then
		return nil
	end
	local pos = Call(C_Map.GetPlayerMapPosition, map, "player")
	if type(pos) ~= "table" and type(pos) ~= "userdata" then
		return { map = map }
	end
	local ok, x, y = pcall(pos.GetXY, pos)
	if not ok or type(x) ~= "number" or IsSecret(x) then
		return { map = map }
	end
	return { map = map, x = x * 100, y = y * 100 }
end

-- Candidate spots { area, x, y, name } for one spawn table.
local function AddSpots(out, spawns, name)
	if type(spawns) ~= "table" then
		return
	end
	for area, list in pairs(spawns) do
		if type(area) == "number" and type(list) == "table" then
			for k, p in ipairs(list) do
				if type(p) == "table" and type(p[1]) == "number" and p[1] > 0 then
					out[#out + 1] = { area = area, x = p[1], y = p[2], name = name }
				end
				if k >= 40 then
					break -- enough to pick from
				end
			end
		end
	end
end

-- Every place an objective of the quest can be done.
function C.ObjectiveSpots(id)
	local out = {}
	local o = Q(id, "objectives")
	if type(o) == "table" then
		for _, e in ipairs(List(o[1])) do -- creatures
			if type(e) == "table" and e[1] then
				AddSpots(out, C.source.npc(e[1], "spawns"), C.source.npc(e[1], "name"))
			end
		end
		for _, e in ipairs(List(o[2])) do -- objects
			if type(e) == "table" and e[1] then
				AddSpots(out, C.source.object(e[1], "spawns"), C.source.object(e[1], "name"))
			end
		end
		for _, e in ipairs(List(o[3])) do -- items: where they drop
			if type(e) == "table" and e[1] then
				local item = C.source.item(e[1], "name")
				for k, npc in ipairs(List(C.source.item(e[1], "npcDrops"))) do
					AddSpots(out, C.source.npc(npc, "spawns"), (C.source.npc(npc, "name") or "?") .. (item and (" (" .. item .. ")") or ""))
					if k >= 6 then break end
				end
				for k, obj in ipairs(List(C.source.item(e[1], "objectDrops"))) do
					AddSpots(out, C.source.object(obj, "spawns"), (C.source.object(obj, "name") or "?") .. (item and (" (" .. item .. ")") or ""))
					if k >= 6 then break end
				end
			end
		end
		for _, e in ipairs(List(o[5])) do -- kill credit: { {npcIds}, creditId, text }
			if type(e) == "table" then
				for _, npc in ipairs(List(e[1])) do
					AddSpots(out, C.source.npc(npc, "spawns"), C.source.npc(npc, "name"))
				end
			end
		end
	end
	local trig = Q(id, "triggerEnd") -- { text, { [area] = {{x,y}} } }
	if type(trig) == "table" then
		AddSpots(out, trig[2], type(trig[1]) == "string" and trig[1] or nil)
	end
	return out
end

-- The objective spot to head for: nearest one on the map you are on,
-- otherwise the one outside dungeons in the zone with the most spots.
function C.ObjectiveSpot(id, here)
	local spots = C.ObjectiveSpots(id)
	if #spots == 0 then
		return nil
	end
	here = here or C.Here()
	if here and here.map then
		local best, bestD
		for _, s in ipairs(spots) do
			if C.source.uiMap(s.area) == here.map then
				local d = here.x and ((s.x - here.x) ^ 2 + (s.y - here.y) ^ 2) or 0
				if not bestD or d < bestD then
					best, bestD = s, d
				end
			end
		end
		if best then
			return best
		end
	end
	local count = {}
	for _, s in ipairs(spots) do
		count[s.area] = (count[s.area] or 0) + 1
	end
	local best, bestScore
	for _, s in ipairs(spots) do
		local score = count[s.area] + ((C.index and C.index.byArea[s.area]) and 0 or 1000)
		if not bestScore or score > bestScore then
			best, bestScore = s, score
		end
	end
	return best
end

function C.AreaName(area)
	if type(area) ~= "number" then
		return nil
	end
	local d = C.index and C.index.byArea[area]
	return C.source.areaName(area) or (d and d.name) or nil
end

-- "Name - Zone (12.3, 45.6)"
function C.FormatWhere(w)
	if not w then
		return nil
	end
	local name = w.name
	if w.kind == "item" then
		name = T("Starts from item") .. " [" .. w.name .. "]" .. (w.from and (" - " .. w.from) or "")
	end
	local where = ""
	if w.area then
		local zone = C.AreaName(w.area) or "?"
		if w.inside then
			zone = (w.dungeon or zone) .. ", " .. T("inside the dungeon")
		end
		if type(w.x) == "number" and type(w.y) == "number" and w.x > 0 then
			where = string.format(" - %s (%.0f, %.0f)", zone, w.x, w.y)
		else
			where = " - " .. zone
		end
	end
	return name .. where
end

------------------------------------------------------------------------
-- Waypoints
------------------------------------------------------------------------

-- Sets a map waypoint (TomTom when installed, the game's own pin otherwise).
-- `arrow`: also point TomTom's arrow at it (quietly). Returns ok and a
-- handle for C.RemoveWaypoint.
function C.Waypoint(w, title, arrow)
	if not (w and w.area and type(w.x) == "number" and type(w.y) == "number") then
		return false
	end
	local area = w.area
	-- inside a dungeon: point at its entrance instead
	local d = C.index and C.index.byArea[area]
	local x, y = w.x, w.y
	if d and d.entrances[1] then
		local e = d.entrances[1]
		area, x, y = e[1], e[2], e[3]
	end
	local map = C.source.uiMap(area)
	if not map then
		return false
	end
	local tomtom = _G.TomTom
	if type(tomtom) == "table" and type(tomtom.AddWaypoint) == "function" then
		local ok, uid = pcall(tomtom.AddWaypoint, tomtom, map, x / 100, y / 100,
			{ title = title, from = "Chainlog", persistent = false, crazy = arrow or nil, silent = arrow or nil })
		if ok then
			return true, uid
		end
	end
	if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
		local ok = pcall(function()
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
			if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
				C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			end
		end)
		return ok, ok and "game" or nil
	end
	return false
end

function C.RemoveWaypoint(handle)
	if handle == "game" then
		if C_Map and C_Map.ClearUserWaypoint then
			pcall(C_Map.ClearUserWaypoint)
		end
	elseif type(handle) == "table" then
		local tomtom = _G.TomTom
		if type(tomtom) == "table" and type(tomtom.RemoveWaypoint) == "function" then
			pcall(tomtom.RemoveWaypoint, tomtom, handle)
		end
	end
end

------------------------------------------------------------------------
-- Quest log
------------------------------------------------------------------------

-- Quest IDs in the log.
function C.LogQuests()
	local out = {}
	if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then
		return out
	end
	local n = Call(C_QuestLog.GetNumQuestLogEntries) or 0
	for i = 1, n do
		local info = Call(C_QuestLog.GetInfo, i)
		if type(info) == "table" and not info.isHeader then
			local id = info.questID
			if type(id) == "number" and not IsSecret(id) and id > 0 then
				out[#out + 1] = id
			end
		end
	end
	return out
end

-- Is this quest part of a chain worth warning about?
function C.IsLinked(id)
	if C.DungeonOf(id) then
		return true
	end
	local chain = C.ChainOf(id)
	return #chain > 1
end

-- An optional lead-in ("breadcrumb") to another quest.
function C.IsLeadIn(id)
	local b = Q(id, "breadcrumbForQuestId")
	return type(b) == "number" and b > 0
end

function C.Name(id)
	return Q(id, "name") or ("#" .. tostring(id))
end

function C.Level(id)
	local l = Q(id, "questLevel")
	return type(l) == "number" and l or nil
end

function C.Objectives(id)
	return List(Q(id, "objectivesText"))
end

return C
