--[[
  Chainlog marks: two small helpers while you run a dungeon.

  1. Quest mobs on nameplates. In a dungeon where you have quests, every
     mob you still need gets a small icon above its nameplate: a skull to
     kill it, a bag when it drops an item your quest needs. The icon goes
     away when that objective is done. Enemy nameplates must be on (V).
     The game's nameplates are never changed: the icon is our own frame.

  2. Quest lines in mob tooltips. When a mob's tooltip lists the quest
     progress of everyone in your group, your own line is shown in gold
     with an arrow, so you find it at a glance. A finished objective
     (2/2) turns green, and so does the quest's title when all its
     objectives there are finished.

  Items lying on the ground (crates, chests) cannot be marked: the game
  gives addons neither their position nor a frame for them.

  /chainlog marks   quest mob icons on or off
]]

local _, ns = ...
local T = ns.T
local C = ns.Core

local MK = {}
ns.Marks = MK

MK.ICON = {
	kill = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
	loot = "Interface\\GossipFrame\\VendorGossipIcon",
}

local function Safe(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a = pcall(fn, ...)
	if not ok or (issecretvalue and issecretvalue(a)) then
		return nil
	end
	return a
end

local function DB()
	local d = ns.DB and ns.DB() or {}
	if d.marks == nil then
		d.marks = true
	end
	return d
end

-- npcID from a creature GUID ("Creature-0-...-<npc>-<spawn>")
function MK.NpcID(guid)
	if type(guid) ~= "string" then
		return nil
	end
	local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind == "Creature" or kind == "Vehicle" then
		return tonumber(npc)
	end
	return nil
end

------------------------------------------------------------------------
-- Nameplate icons
------------------------------------------------------------------------

MK.needed = {} -- npcID -> "kill" | "loot"
local icons = {} -- plate -> our frame

function MK.Rebuild()
	MK.needed = {}
	local d = DB().marks and C.CurrentDungeon()
	local chains = d and ns.Window and ns.Window.ChainsFor and ns.Window.ChainsFor(d)
	if d and chains then
		MK.needed = C.NeededMobs(d, chains)
	end
	MK.PaintAll()
end

local function Icon(plate)
	local f = icons[plate]
	if not f then
		f = CreateFrame("Frame", nil, plate)
		f:SetSize(22, 22)
		f:SetPoint("BOTTOM", plate, "TOP", 0, -4)
		f.glow = f:CreateTexture(nil, "BACKGROUND")
		f.glow:SetPoint("CENTER")
		f.glow:SetSize(38, 38)
		f.glow:SetTexture("Interface\\Cooldown\\star4")
		f.glow:SetBlendMode("ADD")
		f.glow:SetVertexColor(1, 0.82, 0.2)
		f.tex = f:CreateTexture(nil, "ARTWORK")
		f.tex:SetAllPoints()
		icons[plate] = f
	end
	return f
end

function MK.Paint(plate, unit)
	if type(plate) ~= "table" then
		return
	end
	local kind = MK.needed[MK.NpcID(Safe(UnitGUID, unit)) or -1]
	if kind and not Safe(UnitIsDead, unit) then
		local f = Icon(plate)
		f.tex:SetTexture(MK.ICON[kind] or MK.ICON.kill)
		f:Show()
	elseif icons[plate] then
		icons[plate]:Hide()
	end
end

function MK.PaintAll()
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		return
	end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	if not ok or type(plates) ~= "table" then
		return
	end
	for _, plate in ipairs(plates) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if type(unit) == "string" then
			MK.Paint(plate, unit)
		end
	end
end

------------------------------------------------------------------------
-- Your line in tooltips
------------------------------------------------------------------------

MK.MARK = "|cffffd100» "
MK.DONE = "|cff40ff40"

local function Plain(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Is this an objective line that is finished (2/2, 10/10)?
function MK.Finished(plain)
	local a, b = plain:match("(%d+)/(%d+)")
	a, b = tonumber(a), tonumber(b)
	return a and b and b > 0 and a >= b or false
end

-- Quest lines in a mob's tooltip (written by Questie and the like), from
-- the second line on:
--   your own progress line (in a group): gold with an arrow
--   a finished objective (2/2): green
--   a quest title ([33] Name) whose objectives below are all finished: green
-- Returns how many lines changed; lines already changed are left alone.
function MK.HighlightTooltip(tip)
	local me = Safe(UnitName, "player")
	if not (tip and tip.NumLines) then
		return 0
	end
	local name = tip.GetName and tip:GetName()
	local n, changed = Safe(tip.NumLines, tip) or 0, 0
	local fonts, texts = {}, {}
	for i = 2, n do
		local fs = name and _G[name .. "TextLeft" .. i]
		local text = fs and Safe(fs.GetText, fs)
		if type(text) == "string" then
			fonts[i], texts[i] = fs, text
		end
	end
	-- objectives first
	for i = 2, n do
		local text = texts[i]
		if text and not text:find(MK.MARK, 1, true) and text:sub(1, #MK.DONE) ~= MK.DONE then
			local plain = Plain(text)
			local done = plain:find("%d+/%d+") and MK.Finished(plain)
			local mine = type(me) == "string" and text:find(me, 1, true)
				and (plain:find("%d+/%d+") or plain:find(me .. ":", 1, true))
			if mine then
				fonts[i]:SetText((done and (MK.DONE .. "» ") or MK.MARK) .. plain .. "|r")
				changed = changed + 1
			elseif done then
				fonts[i]:SetText(MK.DONE .. plain .. "|r")
				changed = changed + 1
			end
		end
	end
	-- then quest titles: green when every objective under them is finished
	for i = 2, n do
		local text = texts[i]
		if text and text:sub(1, #MK.DONE) ~= MK.DONE then
			local plain = Plain(text)
			if plain:find("^%s*%[%d+%+?%]") then
				local objectives, finished = 0, 0
				for j = i + 1, n do
					local p = texts[j] and Plain(texts[j])
					if not p or p:find("^%s*%[%d+%+?%]") or not p:find("%d+/%d+") then
						break
					end
					objectives = objectives + 1
					if MK.Finished(p) then
						finished = finished + 1
					end
				end
				if objectives > 0 and finished == objectives then
					fonts[i]:SetText(MK.DONE .. plain .. "|r")
					changed = changed + 1
				end
			end
		end
	end
	return changed
end

if GameTooltip and hooksecurefunc then
	-- after every Show: the quest addon adds its lines first, then shows
	hooksecurefunc(GameTooltip, "Show", function(tip)
		if Safe(tip.GetUnit, tip) then
			MK.HighlightTooltip(tip)
		end
	end)
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local queued = false
ev:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
			MK.Paint(Safe(C_NamePlate.GetNamePlateForUnit, unit), unit)
		end
		return
	end
	if queued then
		return
	end
	queued = true
	local function Run()
		queued = false
		MK.Rebuild()
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(1, Run)
	else
		Run()
	end
end)
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "NAME_PLATE_UNIT_ADDED" }) do
	pcall(ev.RegisterEvent, ev, e)
end

function MK.Toggle()
	local d = DB()
	d.marks = not d.marks
	print("|cffe8a33aChainlog|r " .. T("quest mob icons:") .. " " .. (d.marks and T("on") or T("off")))
	MK.Rebuild()
end
