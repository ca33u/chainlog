--[[
  Chainlog marks: two small helpers while you run a dungeon.

  1. Quest mobs on nameplates. In a dungeon where you have quests, every
     mob you still need gets a small icon above its nameplate: a skull to
     kill it, a bag when it drops an item your quest needs. The icon goes
     away when that objective is done. Enemy nameplates must be on (V).
     The game's nameplates are never changed: the icon is our own frame.

  2. You in quest tooltips. When a mob's tooltip lists the quest progress
     of everyone in your group, your own line is shown in gold with an
     arrow, so you find it at a glance.

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

-- Gold and an arrow on the tooltip lines that are about you (a line with
-- your name and a count like 3/6), not on the first line (the mob's name).
function MK.HighlightTooltip(tip)
	local me = Safe(UnitName, "player")
	if type(me) ~= "string" or not (tip and tip.NumLines) then
		return 0
	end
	local name = tip.GetName and tip:GetName()
	local n, changed = Safe(tip.NumLines, tip) or 0, 0
	for i = 2, n do
		local fs = name and _G[name .. "TextLeft" .. i]
		local text = fs and Safe(fs.GetText, fs)
		if type(text) == "string" and text:find(me, 1, true) and not text:find(MK.MARK, 1, true) then
			local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			if plain:find("%d+/%d+") or plain:find(me .. ":", 1, true) then
				fs:SetText(MK.MARK .. plain .. "|r")
				changed = changed + 1
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
