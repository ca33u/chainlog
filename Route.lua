--[[
  Chainlog route: the fastest way to the next place, not just a straight
  arrow.

  The world is a small graph: you, the place, your flight points, and the
  zeppelins and boats. Running is possible between any two points on one
  continent, flying between two flight points you know, a ship between its
  two docks. The fastest path wins (Dijkstra). A flight is only suggested
  when it saves at least a minute over running.

  Roads, mountains and water are not known to addons, so a "run" leg is a
  straight line: TomTom's arrow points along it as before.

  Your flight points: the game only lists them at a flight master. Chainlog
  remembers them (per character) every time you open the flight map.

  Times are estimates: run at your current speed, fly at about 30 yards a
  second with a detour, a ship takes about three and a half minutes with
  the wait.
]]

local _, ns = ...
local T = ns.T
local C = ns.Core

local RT = {}
ns.Route = RT

RT.RUN = 7          -- yards per second on foot
RT.FLY = 30         -- taxi speed, yards per second
RT.FLY_DETOUR = 1.3 -- taxi paths bend through other flight points
RT.FLY_EXTRA = 20   -- talk to the master, take off, land
RT.SHIP = 210       -- crossing plus the average wait at the dock
RT.MIN_SAVING = 60  -- a detour must save at least this many seconds
RT.NEAR = 40        -- yards: "you are there"

-- Zeppelins and boats: { kind, faction, dockA, dockB }; dock = { area, x, y, name }.
RT.TRANSPORTS = {
	{ "zeppelin", "H", { 14, 50.8, 13.2, "Orgrimmar" }, { 85, 61.3, 58.9, "Undercity" } },
	{ "zeppelin", "H", { 14, 50.6, 12.6, "Orgrimmar" }, { 33, 31.5, 29.7, "Grom'gol" } },
	{ "zeppelin", "H", { 85, 61.9, 59.0, "Undercity" }, { 33, 31.5, 29.9, "Grom'gol" } },
	{ "boat", "AH", { 17, 63.7, 38.6, "Ratchet" }, { 33, 25.9, 73.1, "Booty Bay" } },
	{ "boat", "A", { 11, 4.6, 57.1, "Menethil Harbor" }, { 15, 71.6, 56.4, "Theramore" } },
	{ "boat", "A", { 11, 4.8, 63.6, "Menethil Harbor" }, { 148, 32.4, 43.8, "Auberdine" } },
	{ "boat", "A", { 148, 33.2, 40.2, "Auberdine" }, { 141, 54.9, 96.8, "Rut'theran Village" } },
}

------------------------------------------------------------------------
-- Planner (pure: tests/core_test.lua)
------------------------------------------------------------------------

local function Dist(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

-- start, goal: { cont, x, y } in world yards.
-- opts.flights: { { cont, x, y, name, id } } flight points you can use
-- opts.ships:   { { kind, a = point, b = point } } with points like above
-- opts.run:     your speed
-- Returns { legs = { { mode = "run"|"fly"|"zeppelin"|"boat", from, to, time, yards } },
--           time, direct } or nil when the goal cannot be reached.
-- direct: running time in a straight line (nil across continents).
function RT.Plan(start, goal, opts)
	if not (start and goal and start.cont and goal.cont) then
		return nil
	end
	opts = opts or {}
	local run = opts.run or RT.RUN
	local nodes = { start, goal }
	local fly, ship = {}, {}
	for _, f in ipairs(opts.flights or {}) do
		nodes[#nodes + 1] = f
		fly[#nodes] = true
	end
	for _, s in ipairs(opts.ships or {}) do
		nodes[#nodes + 1] = s.a
		local ia = #nodes
		nodes[#nodes + 1] = s.b
		ship[ia] = { to = #nodes, kind = s.kind }
		ship[#nodes] = { to = ia, kind = s.kind }
	end
	-- Dijkstra over a complete graph (a few dozen nodes)
	local n = #nodes
	local best, prev, mode, done = {}, {}, {}, {}
	best[1] = 0
	while true do
		local u, bu
		for i = 1, n do
			if not done[i] and best[i] and (not bu or best[i] < bu) then
				u, bu = i, best[i]
			end
		end
		if not u or u == 2 then
			break
		end
		done[u] = true
		local a = nodes[u]
		local function Relax(v, cost, how)
			if not done[v] and (not best[v] or bu + cost < best[v]) then
				best[v], prev[v], mode[v] = bu + cost, u, how
			end
		end
		for v = 1, n do
			local b = nodes[v]
			if v ~= u and b.cont == a.cont then
				Relax(v, Dist(a, b) / run, "run")
				if fly[u] and fly[v] then
					Relax(v, Dist(a, b) * RT.FLY_DETOUR / RT.FLY + RT.FLY_EXTRA, "fly")
				end
			end
		end
		if ship[u] then
			Relax(ship[u].to, RT.SHIP, ship[u].kind)
		end
	end
	if not best[2] then
		return nil
	end
	local legs = {}
	local v = 2
	while v ~= 1 do
		local u = prev[v]
		local m = mode[v]
		table.insert(legs, 1, { mode = m, from = nodes[u], to = nodes[v],
			yards = nodes[u].cont == nodes[v].cont and Dist(nodes[u], nodes[v]) or nil,
			time = best[v] - best[u] })
		v = u
	end
	local direct = start.cont == goal.cont and Dist(start, goal) / run or nil
	-- a detour that barely helps is not worth the hassle
	if direct and (#legs > 1) and direct - best[2] < RT.MIN_SAVING then
		legs = { { mode = "run", from = start, to = goal, yards = Dist(start, goal), time = direct } }
		return { legs = legs, time = direct, direct = direct }
	end
	return { legs = legs, time = best[2], direct = direct }
end

-- The leg to act on now: skips a run you have already finished (you
-- stand at the flight master or the dock).
function RT.Current(route)
	if not route then
		return nil
	end
	for i, leg in ipairs(route.legs) do
		if not (leg.mode == "run" and leg.yards and leg.yards < RT.NEAR and i < #route.legs) then
			return leg, i
		end
	end
	return nil
end

------------------------------------------------------------------------
-- Words
------------------------------------------------------------------------

local function Minutes(sec)
	return math.max(1, math.floor((sec or 0) / 60 + 0.5))
end

function RT.PlaceName(p)
	return p and (p.name or (p.area and C.source.areaName(p.area))) or "?"
end

-- One leg as a short instruction.
function RT.Say(leg, last)
	if not leg then
		return ""
	end
	local to = RT.PlaceName(leg.to)
	if leg.mode == "fly" then
		return string.format(T("Fly to %s"), to)
	elseif leg.mode == "zeppelin" then
		return string.format(T("Zeppelin to %s"), to)
	elseif leg.mode == "boat" then
		return string.format(T("Boat to %s"), to)
	end
	if last then
		return string.format(T("Run to the place (%d yd)"), math.floor((leg.yards or 0) + 0.5))
	end
	if leg.to.flight then
		return string.format(T("Run to the flight master: %s"), to)
	end
	return string.format(T("Run to the dock: %s"), to)
end

-- The leg after leg i that is worth naming (short runs are skipped),
-- and whether it is the last one.
function RT.NextLeg(route, i)
	if not route then
		return nil
	end
	for j = (i or 0) + 1, #route.legs do
		local leg = route.legs[j]
		if not (leg.mode == "run" and leg.yards and leg.yards < RT.NEAR and j < #route.legs) then
			return leg, j == #route.legs
		end
	end
	return nil
end

-- What comes after the current step, as the end of a sentence.
function RT.Then(leg, last)
	if not leg then
		return ""
	end
	local to = RT.PlaceName(leg.to)
	if leg.mode == "fly" then
		return string.format(T("then fly to %s"), to)
	elseif leg.mode == "zeppelin" then
		return string.format(T("then the zeppelin to %s"), to)
	elseif leg.mode == "boat" then
		return string.format(T("then the boat to %s"), to)
	elseif last then
		return string.format(T("then run %d yd"), math.floor((leg.yards or 0) + 0.5))
	elseif leg.to.flight then
		return string.format(T("then run to the flight master: %s"), to)
	end
	return string.format(T("then run to the dock: %s"), to)
end

-- Arrow title: this step and the next one, then the quest on a new line.
function RT.Title(route, i, say, quest)
	local nextLeg, last = RT.NextLeg(route, i)
	local head = say
	if nextLeg then
		head = head .. ", " .. RT.Then(nextLeg, last)
	end
	return head .. "\n" .. (quest or "")
end

-- Lines for a tooltip; nil when a straight run is the best.
function RT.Lines(route)
	if not route or #route.legs < 2 then
		return nil
	end
	local out = {}
	for i, leg in ipairs(route.legs) do
		if not (leg.mode == "run" and leg.yards and leg.yards < RT.NEAR and i < #route.legs) then
			out[#out + 1] = (#out + 1) .. ". " .. RT.Say(leg, i == #route.legs)
		end
	end
	if route.direct then
		out[#out + 1] = string.format(T("About %d min instead of %d on foot"), Minutes(route.time), Minutes(route.direct))
	else
		out[#out + 1] = string.format(T("About %d min"), Minutes(route.time))
	end
	return out
end

------------------------------------------------------------------------
-- Game side: positions, your flight points
------------------------------------------------------------------------

local function Secret(v)
	return issecretvalue and issecretvalue(v) and true or false
end

-- World position (yards) of a point on a uiMap (x, y 0-100).
function RT.WorldOf(map, x, y)
	if not (map and x and y and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
		return nil
	end
	local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
	if not ok or type(cont) ~= "number" or Secret(cont) or not pos then
		return nil
	end
	local okXY, wx, wy = pcall(pos.GetXY, pos)
	if not okXY or type(wx) ~= "number" or Secret(wx) then
		return nil
	end
	return { cont = cont, x = wx, y = wy }
end

function RT.WorldOfArea(area, x, y)
	local map = C.source.uiMap(area)
	return map and RT.WorldOf(map, x, y) or nil
end

local function CharKey()
	local name = UnitName and UnitName("player")
	local realm = GetRealmName and GetRealmName()
	if type(name) ~= "string" or Secret(name) then
		return nil
	end
	return name .. "-" .. (type(realm) == "string" and realm or "")
end

-- npcID -> true for the flight points this character knows.
function RT.Known()
	local db = ns.DB and ns.DB()
	local key = CharKey()
	if not (db and key) then
		return {}
	end
	db.flights = type(db.flights) == "table" and db.flights or {}
	db.flights[key] = type(db.flights[key]) == "table" and db.flights[key] or {}
	return db.flights[key]
end

local function MyFaction()
	return C.player.faction and C.player.faction() or nil
end

local function Usable(faction)
	local me = MyFaction()
	return faction == "AH" or not me or faction == me
end

-- Flight points as planner nodes (cached: positions never move).
local flightNodes
local function AllFlights()
	if flightNodes then
		return flightNodes
	end
	local list = {}
	for _, f in ipairs(ns.FLIGHTS or {}) do
		local w = RT.WorldOfArea(f[3], f[4], f[5])
		if w then
			w.id, w.faction, w.area, w.flight = f[1], f[2], f[3], true
			w.pin = { C.source.uiMap(f[3]), f[4], f[5] }
			list[#list + 1] = w
		end
	end
	if #list > 0 then
		flightNodes = list
	end
	return list
end

local shipNodes
local function AllShips()
	if shipNodes then
		return shipNodes
	end
	local list = {}
	for _, s in ipairs(RT.TRANSPORTS) do
		local a = RT.WorldOfArea(s[3][1], s[3][2], s[3][3])
		local b = RT.WorldOfArea(s[4][1], s[4][2], s[4][3])
		if a and b then
			a.name, a.area, b.name, b.area = T(s[3][4]), s[3][1], T(s[4][4]), s[4][1]
			a.pin = { C.source.uiMap(s[3][1]), s[3][2], s[3][3] }
			b.pin = { C.source.uiMap(s[4][1]), s[4][2], s[4][3] }
			list[#list + 1] = { kind = s[1], faction = s[2], a = a, b = b }
		end
	end
	if #list > 0 then
		shipNodes = list
	end
	return list
end

function RT.RunSpeed()
	if GetUnitSpeed then
		local ok, _, run = pcall(GetUnitSpeed, "player")
		if ok and type(run) == "number" and not Secret(run) and run > RT.RUN then
			return run
		end
	end
	return RT.RUN
end

function RT.KnownCount()
	local n = 0
	for _ in pairs(RT.Known()) do
		n = n + 1
	end
	return n
end

-- Route from where you stand to the place `w` (a Chainlog "where").
function RT.To(w)
	local map, x, y = C.MapPoint(w)
	if not map then
		return nil
	end
	local here = C.Here()
	if not (here and here.map and here.x) then
		return nil
	end
	local start = RT.WorldOf(here.map, here.x, here.y)
	local goal = RT.WorldOf(map, x, y)
	if not (start and goal) then
		return nil
	end
	goal.name = w.name
	goal.pin = { map, x, y }
	local known = RT.Known()
	local flights = {}
	for _, f in ipairs(AllFlights()) do
		if known[f.id] and Usable(f.faction) then
			flights[#flights + 1] = f
		end
	end
	local ships = {}
	for _, s in ipairs(AllShips()) do
		if Usable(s.faction) then
			ships[#ships + 1] = s
		end
	end
	local route = RT.Plan(start, goal, { flights = flights, ships = ships, run = RT.RunSpeed() })
	return route
end

-- The point (uiMap, x, y) a leg leads to, for the arrow.
function RT.MapOf(leg)
	local pin = leg and leg.to and leg.to.pin
	if pin and pin[1] then
		return pin[1], pin[2], pin[3]
	end
	return nil
end

------------------------------------------------------------------------
-- Learning your flight points at the flight master
------------------------------------------------------------------------

local function NpcIdOf(unit)
	local guid = UnitGUID and UnitGUID(unit)
	if type(guid) ~= "string" or Secret(guid) then
		return nil
	end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	return (kind == "Creature") and tonumber(id) or nil
end

-- The continent map you are on (taxi node positions are on it).
local function ContinentMap()
	if GetTaxiMapID then
		local ok, m = pcall(GetTaxiMapID)
		if ok and type(m) == "number" and m > 0 then
			return m
		end
	end
	local here = C.Here()
	local map = here and here.map
	for _ = 1, 6 do
		if not map then
			return nil
		end
		local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
		if not info then
			return nil
		end
		if info.mapType == 2 then -- Enum.UIMapType.Continent
			return map
		end
		map = info.parentMapID
	end
	return nil
end

-- Positions (0-1 on `map`) of the flight points the map shows as yours.
local function TaxiPoints(map)
	local out = {}
	if C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and map then
		local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, map)
		if ok and type(nodes) == "table" then
			for _, n in ipairs(nodes) do
				-- state 0 = you are here, 1 = you can fly there
				if type(n) == "table" and (n.state == 0 or n.state == 1) and n.position then
					local okXY, x, y = pcall(n.position.GetXY, n.position)
					if okXY and type(x) == "number" then
						out[#out + 1] = { x, y }
					end
				end
			end
		end
	end
	if #out == 0 and NumTaxiNodes and TaxiNodeGetType and TaxiNodePosition then
		local ok, count = pcall(NumTaxiNodes)
		for i = 1, (ok and type(count) == "number") and count or 0 do
			local okT, kind = pcall(TaxiNodeGetType, i)
			if okT and (kind == "CURRENT" or kind == "REACHABLE") then
				local okP, x, y = pcall(TaxiNodePosition, i)
				if okP and type(x) == "number" then
					out[#out + 1] = { x, y }
				end
			end
		end
	end
	return out
end

-- Marks the flight master nearest to a point (0-1 on `map`) as known.
local function LearnAt(known, map, x, y)
	local w = RT.WorldOf(map, x * 100, y * 100)
	if not w then
		return
	end
	local best, bestD
	for _, f in ipairs(AllFlights()) do
		if f.cont == w.cont and Usable(f.faction) then
			local d = Dist(f, w)
			if not bestD or d < bestD then
				best, bestD = f, d
			end
		end
	end
	if best and bestD < 250 then
		known[best.id] = true
	end
end

local function Learned(before, quiet)
	local after = RT.KnownCount()
	if after ~= before then
		if not quiet then
			print("|cffe8a33aChainlog|r " .. string.format(T("knows %d of your flight points now: routes can use them."), after))
		end
		if ns.Guide and ns.Guide.Replan then
			ns.Guide.Replan()
		end
	end
end

function RT.LearnFromTaxiMap()
	local known = RT.Known()
	local before = RT.KnownCount()
	local here = NpcIdOf("npc")
	if here then
		for _, f in ipairs(ns.FLIGHTS or {}) do
			if f[1] == here then
				known[here] = true
			end
		end
	end
	local map = ContinentMap()
	for _, p in ipairs(TaxiPoints(map)) do
		LearnAt(known, map, p[1], p[2])
	end
	Learned(before)
end

-- The world map knows your flight points on every continent, so they can
-- be learned without visiting a flight master. Only nodes the game marks
-- as discovered count (isUndiscovered == false); a client without that
-- field teaches nothing here.
RT.CONTINENT_MAPS = { 1414, 1415, 12, 13 } -- Kalimdor, Eastern Kingdoms (classic and modern ids)

function RT.LearnFromWorldMap(quiet)
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap and C_Map and C_Map.GetMapInfo) then
		return
	end
	local known = RT.Known()
	local before = RT.KnownCount()
	local seen = {}
	for _, map in ipairs(RT.CONTINENT_MAPS) do
		local okI, info = pcall(C_Map.GetMapInfo, map)
		if okI and type(info) == "table" and info.mapType == 2 and not seen[info.name or map] then
			seen[info.name or map] = true
			local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, map)
			for _, n in ipairs(ok and type(nodes) == "table" and nodes or {}) do
				if type(n) == "table" and n.isUndiscovered == false and n.position then
					local okXY, x, y = pcall(n.position.GetXY, n.position)
					if okXY and type(x) == "number" then
						LearnAt(known, map, x, y)
					end
				end
			end
		end
	end
	Learned(before, quiet)
end

-- Flight points you know on a continent (0 Eastern Kingdoms, 1 Kalimdor).
function RT.KnownOn(cont)
	local n = 0
	local known = RT.Known()
	for _, f in ipairs(AllFlights()) do
		if f.cont == cont and known[f.id] then
			n = n + 1
		end
	end
	return n
end

-- The continent of a far goal on your own continent where Chainlog knows
-- none of your flight points (so the route can only be on foot), or nil.
function RT.MissingFlights(w)
	local map, x, y = C.MapPoint(w)
	local here = C.Here()
	if not (map and here and here.map and here.x) then
		return nil
	end
	local start = RT.WorldOf(here.map, here.x, here.y)
	local goal = RT.WorldOf(map, x, y)
	if not (start and goal) or start.cont ~= goal.cont or Dist(start, goal) < 1500 then
		return nil
	end
	if RT.KnownOn(start.cont) > 0 then
		return nil
	end
	return start.cont
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
	if event == "TAXIMAP_OPENED" then
		pcall(RT.LearnFromTaxiMap)
	elseif C_Timer and C_Timer.After then
		C_Timer.After(5, function()
			pcall(RT.LearnFromWorldMap, true)
		end)
	end
end)
pcall(ev.RegisterEvent, ev, "TAXIMAP_OPENED")
pcall(ev.RegisterEvent, ev, "PLAYER_LOGIN")
pcall(ev.RegisterEvent, ev, "UI_INFO_MESSAGE") -- "new flight path discovered" and the like
