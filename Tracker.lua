--[[
  Chainlog tracker: a small checklist while you are inside a dungeon.

  When you enter a dungeon where you have quests, a panel lists what those
  quests need in there: bosses and mobs to kill, items to loot (and from
  whom), objects to use, people to talk to. Lines are ticked off as the
  quest log reports them done. The panel can be dragged; it hides when you
  leave the dungeon.

  The game gives addons no position inside dungeons, so this is a list,
  not an arrow.

  /chainlog tracker   turn the dungeon checklist on or off
]]

local _, ns = ...
local T = ns.T
local C = ns.Core

local TR = {}
ns.Tracker = TR

local WIDTH = 270
local LINE = 30
local MAX_LINES = 14
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

TR.ICON = {
	kill = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
	loot = "Interface\\GossipFrame\\VendorGossipIcon",
	use = "Interface\\GossipFrame\\BinderGossipIcon",
	talk = "Interface\\GossipFrame\\GossipGossipIcon",
	done = "Interface\\RaidFrame\\ReadyCheck-Ready",
}

local function DB()
	local d = ns.DB and ns.DB() or {}
	if d.tracker == nil then
		d.tracker = true
	end
	return d
end

-- Text for one target: "Archmage Arugal: Head of Arugal"
function TR.Label(t)
	local name = t.name or "?"
	if t.item and t.item ~= name then
		name = name .. ": |cffffffff" .. t.item .. "|r"
	end
	local have, need = C.TargetProgress(t)
	if need and need > 1 then
		local col = have >= need and "|cff20ff20" or "|cffffd100"
		name = name .. "  " .. col .. have .. "/" .. need .. "|r"
	end
	if t.many then
		name = name .. " |cffaaaaaa(" .. T("from mobs in the dungeon") .. ")|r"
	end
	return name
end

function TR.For(t)
	local names = {}
	for _, q in ipairs(t.quests) do
		names[#names + 1] = C.Name(q)
	end
	return table.concat(names, ", ")
end

------------------------------------------------------------------------
-- Session list: targets stay on the list (ticked) after they are done
------------------------------------------------------------------------

TR.area = nil
TR.seen = {}   -- key -> target
TR.order = {}  -- keys in first-seen order

function TR.Collect(d, chains)
	if TR.area ~= d.area then
		TR.area, TR.seen, TR.order = d.area, {}, {}
	end
	local now = {}
	for _, t in ipairs(C.DungeonTargets(d, chains)) do
		now[t.key] = true
		if not TR.seen[t.key] then
			TR.order[#TR.order + 1] = t.key
		end
		TR.seen[t.key] = t
		t.done = C.TargetDone(t)
	end
	-- gone from the list: its quest moved on, so it is done
	local list, left = {}, 0
	for _, key in ipairs(TR.order) do
		local t = TR.seen[key]
		if not now[key] then
			t.done = true
		end
		if not t.done then
			left = left + 1
		end
		list[#list + 1] = t
	end
	table.sort(list, function(a, b)
		if a.done ~= b.done then
			return not a.done
		end
		if a.order ~= b.order then
			return a.order < b.order
		end
		return (a.name or "") < (b.name or "")
	end)
	return list, left
end

------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------

local panel, lines

local function Build()
	panel = CreateFrame("Frame", "ChainlogTracker", UIParent, BACKDROP)
	panel:SetSize(WIDTH, 40)
	panel:SetFrameStrata("MEDIUM")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint(1)
		DB().trackerPos = { point, x, y }
	end)
	if panel.SetBackdrop then
		panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		panel:SetBackdropColor(0.05, 0.05, 0.07, 0.72)
		panel:SetBackdropBorderColor(0, 0, 0, 0.9)
	end
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.title:SetPoint("TOPLEFT", 8, -6)
	panel.title:SetPoint("RIGHT", -40, 0)
	panel.title:SetJustifyH("LEFT")
	panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.count:SetPoint("TOPRIGHT", -8, -6)
	lines = {}
	for i = 1, MAX_LINES do
		local l = CreateFrame("Frame", nil, panel)
		l:SetSize(WIDTH - 12, LINE)
		l:SetPoint("TOPLEFT", 6, -20 - (i - 1) * LINE)
		l.icon = l:CreateTexture(nil, "ARTWORK")
		l.icon:SetSize(14, 14)
		l.icon:SetPoint("TOPLEFT", 0, -2)
		l.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.text:SetPoint("TOPLEFT", 18, -2)
		l.text:SetPoint("RIGHT", 0, 0)
		l.text:SetJustifyH("LEFT")
		l.text:SetWordWrap(false)
		l.sub = l:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		l.sub:SetPoint("TOPLEFT", 18, -15)
		l.sub:SetPoint("RIGHT", 0, 0)
		l.sub:SetJustifyH("LEFT")
		l.sub:SetWordWrap(false)
		l:Hide()
		lines[i] = l
	end
	local pos = DB().trackerPos
	panel:ClearAllPoints()
	if type(pos) == "table" and pos[1] then
		panel:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0)
	else
		panel:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
	end
	panel:Hide()
end

function TR.Refresh()
	local d = DB().tracker and C.CurrentDungeon()
	local chains = d and ns.Window and ns.Window.ChainsFor and ns.Window.ChainsFor(d)
	if not (d and chains) then
		if panel then
			panel:Hide()
		end
		return
	end
	local list, left = TR.Collect(d, chains)
	if #list == 0 then
		if panel then
			panel:Hide()
		end
		return
	end
	if not panel then
		Build()
	end
	panel.title:SetText("|cffe8a33aChainlog|r  " .. d.name)
	panel.count:SetText(string.format("%d/%d", #list - left, #list))
	local shown = math.min(#list, MAX_LINES)
	for i = 1, MAX_LINES do
		local l, t = lines[i], list[i]
		if i <= shown then
			l.icon:SetTexture(t.done and TR.ICON.done or TR.ICON[t.kind] or TR.ICON.kill)
			l.text:SetText(TR.Label(t))
			l.sub:SetText(TR.For(t))
			l:SetAlpha(t.done and 0.45 or 1)
			l:Show()
		else
			l:Hide()
		end
	end
	panel:SetHeight(24 + shown * LINE)
	panel:Show()
end

function TR.Toggle()
	local d = DB()
	d.tracker = not d.tracker
	print("|cffe8a33aChainlog|r " .. T("dungeon checklist:") .. " " .. (d.tracker and T("on") or T("off")))
	TR.Refresh()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local queued = false
ev:SetScript("OnEvent", function()
	if queued then
		return
	end
	queued = true
	local function Run()
		queued = false
		if ns.Window and ns.Window.EnsureIndex and not ns.Window.IsBuilt() then
			ns.Window.EnsureIndex()
			if C_Timer and C_Timer.After then
				C_Timer.After(2, TR.Refresh)
			end
			return
		end
		TR.Refresh()
	end
	if C_Timer and C_Timer.After then
		C_Timer.After(0.5, Run)
	else
		Run()
	end
end)
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED" }) do
	pcall(ev.RegisterEvent, ev, e)
end
