--[[
  Chainlog guide: follow one chain with TomTom's arrow.

  Pick a chain with its "Lead" button, or one quest with the track arrow
  on its row (one thing at a time). Chainlog then keeps one waypoint on
  the next thing to do and moves it by itself as you play:

    quest you can take      -> its quest giver
    quest in your log       -> the nearest place to do its objectives
                               (the mob, the item's dropper, the object,
                               the area to explore)
    objectives complete     -> where you turn it in
    turned in               -> the next step of the chain

  Without TomTom the game's own map pin is used. Targets inside a dungeon
  point at the dungeon's entrance. The chain is remembered across sessions.

  /chainlog stop   stop leading
  /chainlog next   say what the next step is
]]

local _, ns = ...
local T = ns.T
local C = ns.Core

local G = {}
ns.Guide = G

local P = "|cffe8a33aChainlog|r "

G.chain = nil   -- list of quest IDs being followed
G.handle = nil  -- current waypoint
G.lastKey = nil -- what the waypoint points at, to avoid resetting it

local function DB()
	return ns.DB and ns.DB() or {}
end

------------------------------------------------------------------------
-- What to do next (pure apart from Core reads; tests/core_test.lua)
------------------------------------------------------------------------

-- Returns a step { action, quest, where, need } or nil when the chain is done.
--   action: "turnin" | "do" | "take" | "level" | "blocked"
function G.NextStep(chain, here)
	if type(chain) ~= "table" then
		return nil
	end
	-- 1. anything ready to hand in
	for _, id in ipairs(chain) do
		if C.Status(id) == "ready" then
			return { action = "turnin", quest = id, where = C.Ender(id) }
		end
	end
	-- 2. the first step not done, in chain order
	local blocked
	for _, id in ipairs(chain) do
		local st, need = C.Status(id)
		if st == "active" then
			local spot = C.ObjectiveSpot(id, here)
			if spot then
				return { action = "do", quest = id, where = { kind = "spot", name = spot.name or C.Name(id), area = spot.area, x = spot.x, y = spot.y } }
			end
			-- nothing to hunt (deliver, talk to someone): head for the turn-in
			return { action = "turnin", quest = id, where = C.Ender(id) }
		elseif st == "available" then
			return { action = "take", quest = id, where = C.Giver(id) }
		elseif st == "level" then
			return { action = "level", quest = id, need = need, where = C.Giver(id) }
		elseif st == "locked" and not blocked then
			blocked = id
		end
	end
	if blocked then
		return { action = "blocked", quest = blocked }
	end
	return nil
end

-- Short line for chat and the arrow title.
function G.Describe(step)
	if not step then
		return T("Chain finished!")
	end
	local name = C.Name(step.quest)
	if step.action == "take" then
		return string.format(T("Take: %s"), name)
	elseif step.action == "do" then
		return string.format(T("Do: %s"), name) .. (step.where and step.where.name and (" - " .. step.where.name) or "")
	elseif step.action == "turnin" then
		return string.format(T("Turn in: %s"), name)
	elseif step.action == "level" then
		return string.format(T("%s opens at level %d"), name, step.need or 0)
	end
	return string.format(T("%s: an earlier step is missing"), name)
end

------------------------------------------------------------------------
-- Following
------------------------------------------------------------------------

local function Clear()
	if G.handle then
		C.RemoveWaypoint(G.handle)
	end
	G.handle, G.lastKey = nil, nil
end

local function KeyOf(step, leg)
	if not step then
		return "done"
	end
	local w = step.where
	local key = string.format("%s:%s:%s:%s:%s", step.action, step.quest, w and w.area or "", w and w.x or "", w and w.y or "")
	if leg then
		key = key .. string.format(":%s:%s", leg.mode, ns.Route.PlaceName(leg.to))
	end
	return key
end

-- The fastest way there (flights, zeppelins, boats) when it beats running
-- straight. Returns the route and the leg to show now, or nil.
local function RouteFor(step)
	if not (step and step.where and step.action ~= "level" and ns.Route) then
		return nil
	end
	local ok, route = pcall(ns.Route.To, step.where)
	if not ok or not route or #route.legs < 2 then
		return nil
	end
	local leg, i = ns.Route.Current(route)
	if not leg or i == #route.legs then
		return nil -- only the last run is left: the plain arrow does it
	end
	return route, leg, i
end

local function OnTaxi()
	return UnitOnTaxi and UnitOnTaxi("player") and true or false
end

-- Recompute the next step and move the waypoint if it changed.
function G.Update(announce)
	if not G.chain then
		return
	end
	if OnTaxi() and G.step then
		return G.step -- in the air: replan after landing
	end
	local step = G.NextStep(G.chain)
	-- keep the objective spot steady while you work on the same quest here
	if step and step.action == "do" and G.step and G.step.action == "do"
		and G.step.quest == step.quest and G.step.where and not G.zoneChanged then
		step.where = G.step.where
	end
	G.zoneChanged = false
	local route, leg, legIndex = RouteFor(step)
	local key = KeyOf(step, leg)
	if key == G.lastKey and not announce then
		return step
	end
	local changed = key ~= G.lastKey
	Clear()
	G.lastKey = key
	G.step = step
	G.route = route
	if not step then
		print(P .. (G.single and string.format(T("%s: done, tracking off."), C.Name(G.root)) or T("Chain finished!")))
		G.Stop(true)
		return nil
	end
	local text = G.Describe(step)
	local where = step.where and C.FormatWhere(step.where)
	if leg then
		-- the arrow goes to the flight master or the dock first
		local map, x, y = ns.Route.MapOf(leg)
		local say = ns.Route.Say(leg, false)
		if leg.mode == "fly" then
			-- standing at the master: the arrow points at where you land
			say = say .. " (" .. T("talk to the flight master") .. ")"
		elseif leg.mode ~= "run" then
			say = say .. " (" .. T("wait for it at the dock") .. ")"
		end
		local ok, handle = false, nil
		if map then
			ok, handle = C.WaypointAt(map, x, y, ns.Route.Title(route, legIndex, say, text), true)
		end
		if ok then
			G.handle = handle
		end
	elseif step.where and step.action ~= "level" then
		local ok, handle = C.Waypoint(step.where, text, true)
		if ok then
			G.handle = handle
		end
	end
	if changed or announce then
		print(P .. "|cffffd100>|r " .. text .. (where and step.action ~= "do" and ("  |cffaaaaaa" .. where .. "|r") or ""))
		-- far away on foot because no flight point here is known yet: say so once
		local cont = not leg and step.where and ns.Route and ns.Route.MissingFlights and ns.Route.MissingFlights(step.where)
		G.hinted = G.hinted or {}
		if cont and not G.hinted[cont] then
			G.hinted[cont] = true
			print(P .. "|cffffd100" .. T("Chainlog does not know your flight points on this continent yet: open any flight master's map here once, and the route will use them.") .. "|r")
		end
		if leg then
			print(P .. "|cffffd100" .. T("Fastest way:") .. "|r " .. table.concat(ns.Route.Lines(route) or {}, "  "))
		end
	end
	if ns.Window and ns.Window.Refresh then
		ns.Window.Refresh()
	end
	return step
end

-- Start following the chain that contains `id`.
function G.Start(id)
	local chain = C.ChainOf(id)
	G.chain = chain
	G.root = chain[#chain]
	G.single = false
	DB().guide = G.root
	DB().guideSingle = nil
	G.lastKey = nil
	print(P .. string.format(T("Leading: %s"), C.Name(G.root)))
	return G.Update(true)
end

-- Track one quest: the navigation follows it alone (giver, objectives,
-- turn-in). Only one thing is tracked at a time: tracking another quest
-- (or leading a chain) replaces it; tracking it again turns it off.
function G.Track(id)
	if G.IsTracked(id) then
		G.Stop()
		return nil
	end
	G.chain, G.root, G.single = { id }, id, true
	DB().guide, DB().guideSingle = id, true
	G.lastKey = nil
	print(P .. string.format(T("Tracking: %s"), C.Name(id)))
	return G.Update(true)
end

-- Position changed a lot (landed, crossed a zone): check the route again.
function G.Replan()
	if G.chain then
		G.Update(false)
	end
end

function G.IsTracked(id)
	return G.single and G.root == id or false
end

function G.Stop(quiet)
	Clear()
	G.chain, G.root, G.step, G.single = nil, nil, nil, false
	DB().guide, DB().guideSingle = nil, nil
	if not quiet then
		print(P .. T("Stopped leading."))
	end
	if ns.Window and ns.Window.Refresh then
		ns.Window.Refresh()
	end
end

-- Is this chain (list of IDs) the one being led?
function G.IsLeading(chain)
	if not (G.chain and chain) then
		return false
	end
	for _, id in ipairs(chain) do
		if id == G.root then
			return true
		end
	end
	return false
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local queued = false
local function Queue(delay)
	if queued or not G.chain then
		return
	end
	queued = true
	local function Run()
		queued = false
		G.Update(false)
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(delay or 0.5, Run)
	else
		Run()
	end
end

ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		-- resume the chain from last session once the game has settled
		local root = DB().guide
		if type(root) == "number" and C_Timer and C_Timer.After then
			C_Timer.After(8, function()
				if C.source.available() then
					G.single = DB().guideSingle and true or false
					G.chain = G.single and { root } or C.ChainOf(root)
					G.root = root
					G.Update(true)
				end
			end)
		end
		return
	end
	if event == "PLAYER_CONTROL_GAINED" or event == "TAXIMAP_CLOSED" then
		Queue(1) -- landed, or left the flight master
		return
	end
	if event == "ZONE_CHANGED_NEW_AREA" then
		G.zoneChanged = true
		Queue(2) -- objectives: pick the spot nearest on the new map
	else
		Queue(0.5)
	end
end)
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_GAINED", "TAXIMAP_CLOSED" }) do
	pcall(ev.RegisterEvent, ev, e)
end

-- While a route with a flight or a ship is up, check every few seconds
-- whether you reached the flight master or the dock.
local tick = 0
ev:SetScript("OnUpdate", function(_, elapsed)
	tick = tick + (elapsed or 0)
	if tick < 3 then
		return
	end
	tick = 0
	if G.chain and G.route then
		G.Update(false)
	end
end)
