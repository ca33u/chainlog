--[[
  Chainlog window: dungeons on the left, their quest chains on the right.

    Dungeons tab   every dungeon with quests for your race and class,
                   level range and how many of its quests you have done.
    My quests tab  the quests in your log that belong to a chain, with the
                   whole chain around them.

  Each quest row: status icon, [level] name, and on the second line where
  to pick it up (or turn it in). Click a row to put a waypoint there
  (TomTom when installed, the game's own map pin otherwise).

  Status icons:
    green tick        done
    yellow ?          in your log, ready to turn in
    grey ?            in your log
    yellow !          you can take it now
    grey !            you can take it at a higher level
    lock              finish the earlier step first
]]

local ADDON_NAME, ns = ...
local T = ns.T
local C = ns.Core

local UI = {}
ns.Window = UI

local W, H = 800, 540
local PAD = 20
local LEFT_W = 250
local ROW_H = 32
local HEAD_H = 22
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

local function DB()
	if type(ChainlogDB) ~= "table" then
		ChainlogDB = {}
	end
	local d = ChainlogDB
	if d.hideDone == nil then d.hideDone = false end
	if d.allLevels == nil then d.allLevels = false end
	if d.warn == nil then d.warn = true end
	if d.tab == nil then d.tab = "dungeons" end
	return d
end
ns.DB = DB

------------------------------------------------------------------------
-- Index build, spread over frames so the game never stutters
------------------------------------------------------------------------

local building, built = nil, false
local chainsByArea = {} -- area -> chains

local function Finish()
	built = true
	building = nil
	if UI.frame and UI.frame:IsShown() then
		UI.Refresh()
	end
end

function UI.EnsureIndex()
	if built or building then
		return built
	end
	if not C.source.available() then
		return false
	end
	building = coroutine.create(function()
		C.Build(coroutine.yield, 150)
		for _, d in ipairs(C.index.dungeons) do
			chainsByArea[d.area] = C.DungeonChains(d)
			coroutine.yield()
		end
	end)
	return false
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function()
	if not building then
		return
	end
	local ok, err = coroutine.resume(building)
	if not ok then
		building = nil
		print("|cffe8a33aChainlog|r index error: " .. tostring(err))
		return
	end
	if coroutine.status(building) == "dead" then
		Finish()
	end
end)

-- Builds everything right now (tests).
function UI.BuildNow()
	C.Build()
	for _, d in ipairs(C.index.dungeons) do
		chainsByArea[d.area] = C.DungeonChains(d)
	end
	building = nil
	Finish()
end

-- Chains of a dungeon (after the index is built).
function UI.ChainsFor(d)
	return d and chainsByArea[d.area] or nil
end

function UI.IsBuilt()
	return built
end

------------------------------------------------------------------------
-- Look
------------------------------------------------------------------------

local ICON = {
	done = "Interface\\RaidFrame\\ReadyCheck-Ready",
	ready = "Interface\\GossipFrame\\ActiveQuestIcon",
	active = "Interface\\GossipFrame\\IncompleteQuestIcon",
	available = "Interface\\GossipFrame\\AvailableQuestIcon",
	level = "Interface\\GossipFrame\\AvailableQuestIcon",
	locked = "Interface\\Buttons\\LockButton-Locked-Up",
	skip = "Interface\\Buttons\\UI-MinusButton-Up",
}

-- Quest difficulty colour, like the quest log.
local function LevelColor(level)
	local me = C.player.level() or 1
	if type(level) ~= "number" then
		return 0.9, 0.9, 0.9
	end
	local diff = level - me
	if diff >= 5 then
		return 1, 0.1, 0.1
	elseif diff >= 3 then
		return 1, 0.5, 0.25
	elseif diff >= -2 then
		return 1, 0.82, 0
	elseif diff >= -8 then
		return 0.25, 0.75, 0.25
	end
	return 0.6, 0.6, 0.6
end

local function Hex(r, g, b)
	return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------

local win

local function Build()
	win = CreateFrame("Frame", "ChainlogWindow", UIParent, BACKDROP)
	UI.frame = win
	win:SetSize(W, H)
	win:SetPoint("CENTER", 0, 40)
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	if win.SetBackdrop then
		win:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		win:SetBackdropColor(1, 1, 1, 0.95)
	end
	win:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "ChainlogWindow")
	end

	local plate = win:CreateTexture(nil, "ARTWORK")
	plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	plate:SetSize(256, 64)
	plate:SetPoint("TOP", 0, 12)
	local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", plate, "TOP", 0, -14)
	title:SetText("Chainlog")

	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -5, -5)

	-- tabs
	UI.tabs = {}
	local x = PAD
	for _, t in ipairs({ { "dungeons", T("Dungeons") }, { "log", T("My quests") } }) do
		local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
		b:SetSize(120, 22)
		b:SetPoint("TOPLEFT", x, -30)
		b:SetText(t[2])
		b:SetScript("OnClick", function()
			DB().tab = t[1]
			UI.selected = nil
			UI.Refresh()
		end)
		UI.tabs[t[1]] = b
		x = x + 124
	end

	-- filters
	local function Check(key, label, xOff)
		local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
		cb:SetSize(22, 22)
		cb:SetPoint("TOPRIGHT", xOff, -30)
		local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("RIGHT", cb, "LEFT", -2, 0)
		fs:SetText(label)
		cb:SetScript("OnClick", function(self)
			DB()[key] = self:GetChecked() and true or false
			UI.Refresh()
		end)
		return cb
	end
	UI.hideDone = Check("hideDone", T("Hide completed"), -PAD)
	UI.allLevels = Check("allLevels", T("Show all levels"), -PAD - 150)

	-- left list
	UI.left = CreateFrame("ScrollFrame", "ChainlogLeftScroll", win, "UIPanelScrollFrameTemplate")
	UI.left:SetPoint("TOPLEFT", PAD, -62)
	UI.left:SetPoint("BOTTOMLEFT", PAD, 38)
	UI.left:SetWidth(LEFT_W - 26)
	UI.leftContent = CreateFrame("Frame", nil, UI.left)
	UI.leftContent:SetSize(LEFT_W - 26, 10)
	UI.left:SetScrollChild(UI.leftContent)

	local sep = win:CreateTexture(nil, "ARTWORK")
	sep:SetColorTexture(1, 0.82, 0, 0.18)
	sep:SetWidth(1)
	sep:SetPoint("TOPLEFT", PAD + LEFT_W, -62)
	sep:SetPoint("BOTTOMLEFT", PAD + LEFT_W, 38)

	-- right pane
	UI.right = CreateFrame("ScrollFrame", "ChainlogRightScroll", win, "UIPanelScrollFrameTemplate")
	UI.right:SetPoint("TOPLEFT", PAD + LEFT_W + 10, -62)
	UI.right:SetPoint("BOTTOMRIGHT", -PAD - 24, 38)
	UI.rightContent = CreateFrame("Frame", nil, UI.right)
	UI.rightContent:SetSize(W - LEFT_W - 2 * PAD - 40, 10)
	UI.right:SetScrollChild(UI.rightContent)

	UI.message = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	UI.message:SetPoint("CENTER", UI.right, "CENTER", 0, 0)
	UI.message:SetWidth(W - LEFT_W - 2 * PAD - 60)

	-- footer
	local footer = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	footer:SetPoint("BOTTOMLEFT", PAD, 18)
	local ver = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)
	local okV, v = pcall(ver or function() end, ADDON_NAME, "Version")
	footer:SetText(string.format("Chainlog %s  ·  %s addicted  ·  MIT  · ", okV and v or "", T("by")))
	local link = ns.Link and ns.Link(win, "addicted.sh", "https://addicted.sh")
	if link then
		link:SetPoint("LEFT", footer, "RIGHT", 2, 0)
	end
	UI.legend = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	UI.legend:SetPoint("BOTTOMRIGHT", -PAD, 18)
	UI.legend:SetText(T("Click: show on the map  ·  Shift-click: quest log"))

	win:SetScript("OnShow", function()
		UI.EnsureIndex()
		UI.Refresh()
	end)
end

------------------------------------------------------------------------
-- Pools
------------------------------------------------------------------------

local leftButtons, rows, heads = {}, {}, {}
local LeadButton

local function LeftButton(i)
	local b = leftButtons[i]
	if not b then
		b = CreateFrame("Button", nil, UI.leftContent)
		b:SetSize(LEFT_W - 30, 22)
		b.hl = b:CreateTexture(nil, "BACKGROUND")
		b.hl:SetAllPoints()
		b.hl:SetColorTexture(1, 0.82, 0, 0.12)
		b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.name:SetPoint("LEFT", 4, 0)
		b.name:SetPoint("RIGHT", -64, 0)
		b.name:SetJustifyH("LEFT")
		b.name:SetWordWrap(false)
		b.info = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		b.info:SetPoint("RIGHT", -4, 0)
		b.info:SetJustifyH("RIGHT")
		local over = b:CreateTexture(nil, "HIGHLIGHT")
		over:SetAllPoints()
		over:SetColorTexture(1, 1, 1, 0.06)
		leftButtons[i] = b
	end
	return b
end

local function Head(i)
	local h = heads[i]
	if not h then
		h = CreateFrame("Button", nil, UI.rightContent)
		h:SetHeight(HEAD_H)
		h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		h.text:SetPoint("LEFT", 0, 0)
		h.text:SetJustifyH("LEFT")
		h.right = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		h.right:SetPoint("RIGHT", 0, 0)
		h.line = h:CreateTexture(nil, "ARTWORK")
		h.line:SetColorTexture(1, 0.82, 0, 0.18)
		h.line:SetHeight(1)
		h.line:SetPoint("BOTTOMLEFT", 0, 1)
		h.line:SetPoint("BOTTOMRIGHT", 0, 1)
		heads[i] = h
	end
	return h
end

-- "Lead" / "Stop" button on a chain heading.
LeadButton = function(h, chain, leading)
	if not h.lead then
		h.lead = CreateFrame("Button", nil, h, "UIPanelButtonTemplate")
		h.lead:SetSize(74, 18)
		h.lead:SetPoint("RIGHT", h.right, "LEFT", -8, 0)
	end
	h.lead:SetText(leading and T("Stop") or T("Lead"))
	h.lead:SetScript("OnClick", function()
		if not ns.Guide then
			return
		end
		if leading then
			ns.Guide.Stop()
		else
			ns.Guide.Start(chain[#chain])
		end
	end)
	h.lead:SetScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(leading and T("Stop leading") or T("Lead me through this chain"), 1, 0.82, 0)
			if not leading then
				GameTooltip:AddLine(T("TomTom's arrow (or the map pin) moves to the next quest giver, objective and turn-in by itself."), 0.9, 0.9, 0.9, true)
			end
			GameTooltip:Show()
		end
	end)
	h.lead:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	h.lead:Show()
end

local function ShowTip(row)
	if not (GameTooltip and row.quest) then
		return
	end
	local id = row.quest
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(C.Name(id), 1, 0.82, 0)
	for _, line in ipairs(C.Objectives(id)) do
		if type(line) == "string" then
			GameTooltip:AddLine(line, 1, 1, 1, true)
		end
	end
	local g = C.FormatWhere(C.Giver(id))
	if g then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(T("Quest giver") .. ": " .. g, 0.8, 0.8, 0.8, true)
	end
	local st = C.Status(id)
	local place, kind = C.NextPlace(id)
	if kind == "do" then
		local d = C.FormatWhere(place)
		if d then
			GameTooltip:AddLine(T("Go to") .. ": " .. d, 1, 0.82, 0, true)
		end
	end
	local e = C.FormatWhere(C.Ender(id))
	if e then
		GameTooltip:AddLine(T("Turn in") .. ": " .. e, 0.8, 0.8, 0.8, true)
	end
	local p = C.Prereqs(id)
	local need = {}
	for _, x in ipairs(p.all) do
		if C.ForMe(x) then need[#need + 1] = C.Name(x) end
	end
	for _, x in ipairs(p.any) do
		if C.ForMe(x) then need[#need + 1] = C.Name(x) end
	end
	if #need > 0 then
		GameTooltip:AddLine(T("Requires") .. ": " .. table.concat(need, ", "), 1, 0.6, 0.4, true)
	end
	local nexts = {}
	for _, x in ipairs(C.Next(id)) do
		if C.ForMe(x) then nexts[#nexts + 1] = C.Name(x) end
	end
	if #nexts > 0 then
		GameTooltip:AddLine(T("Leads to") .. ": " .. table.concat(nexts, ", "), 0.5, 0.83, 1, true)
	end
	GameTooltip:AddLine(" ")
	if st == "active" or st == "ready" then
		GameTooltip:AddLine(T("Click: open in your quest log"), 0.5, 0.5, 0.5)
		GameTooltip:AddLine(T(kind == "do" and "Shift-click: show where to do it on the map" or "Shift-click: show where to turn it in on the map"), 0.5, 0.5, 0.5)
	else
		GameTooltip:AddLine(T("Click: show the quest giver on the map"), 0.5, 0.5, 0.5)
	end
	GameTooltip:Show()
end

local function Row(i)
	local r = rows[i]
	if not r then
		r = CreateFrame("Button", nil, UI.rightContent)
		r:SetHeight(ROW_H)
		r.mark = r:CreateTexture(nil, "BACKGROUND")
		r.mark:SetAllPoints()
		r.mark:SetColorTexture(1, 0.82, 0, 0.1)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(16, 16)
		r.icon:SetPoint("TOPLEFT", 2, -2)
		r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		r.name:SetPoint("TOPLEFT", 24, -3)
		r.name:SetPoint("RIGHT", -112, 0)
		r.name:SetJustifyH("LEFT")
		r.name:SetWordWrap(false)
		-- track: show this quest in the navigation (one at a time)
		r.track = CreateFrame("Button", nil, r)
		r.track:SetSize(18, 18)
		r.track:SetPoint("TOPRIGHT", -2, -1)
		r.track.tex = r.track:CreateTexture(nil, "ARTWORK")
		r.track.tex:SetAllPoints()
		r.track.tex:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
		r.track:RegisterForClicks("LeftButtonUp")
		r.track:SetScript("OnClick", function(self)
			local q = self:GetParent().quest
			if q and ns.Guide then
				ns.Guide.Track(q)
			end
		end)
		r.track:SetScript("OnEnter", function(self)
			local q = self:GetParent().quest
			if GameTooltip and q then
				local on = ns.Guide and ns.Guide.IsTracked(q)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(on and T("Stop tracking") or T("Track in navigation"), 1, 0.82, 0)
				GameTooltip:AddLine(T("The arrow and the map pin follow this quest: giver, objectives, turn-in. One quest at a time."), 0.9, 0.9, 0.9, true)
				GameTooltip:Show()
			end
		end)
		r.track:SetScript("OnLeave", function()
			if GameTooltip then GameTooltip:Hide() end
		end)
		r.state = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		r.state:SetPoint("TOPRIGHT", -24, -4)
		r.state:SetJustifyH("RIGHT")
		r.where = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		r.where:SetPoint("TOPLEFT", 24, -18)
		r.where:SetPoint("RIGHT", -2, 0)
		r.where:SetJustifyH("LEFT")
		r.where:SetWordWrap(false)
		local over = r:CreateTexture(nil, "HIGHLIGHT")
		over:SetAllPoints()
		over:SetColorTexture(1, 1, 1, 0.06)
		r:SetScript("OnEnter", ShowTip)
		r:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)
		r:SetScript("OnClick", function(self)
			if not self.quest then
				return
			end
			local st = C.Status(self.quest)
			local mine = st == "active" or st == "ready"
			-- in your log: open it there (Shift-click: where to go, on the map)
			local shift = IsShiftKeyDown and IsShiftKeyDown()
			if mine and not shift and ns.MapPin.OpenQuest(self.quest) then
				return
			end
			local w, kind = C.NextPlace(self.quest)
			local name = C.Name(self.quest)
			if ns.MapPin.Show(w, name, kind) then
				print("|cffe8a33aChainlog|r " .. string.format(T("On the map: %s"), C.FormatWhere(w) or ""))
			else
				print("|cffe8a33aChainlog|r " .. (w and (C.FormatWhere(w) or "") or T("No location known for this quest")))
			end
		end)
		rows[i] = r
	end
	r.track:Hide()
	return r
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

local STATE_TEXT = {
	done = "done",
	ready = "ready to turn in",
	active = "in log",
	available = "available",
	locked = "locked: finish the previous step",
	skip = "not needed any more",
}

local function PaintRow(r, id, highlight)
	local st, need = C.Status(id)
	r.quest = id
	r.icon:SetTexture(ICON[st] or ICON.available)
	if r.icon.SetDesaturated then
		r.icon:SetDesaturated(st == "level" or st == "active" or st == "skip")
	end
	local lvl = C.Level(id)
	local lr, lg, lb = LevelColor(lvl)
	local name = C.Name(id)
	if st == "done" or st == "skip" then
		r.name:SetText(string.format("|cff808080[%s] %s|r", lvl or "?", name))
	elseif st == "locked" then
		r.name:SetText(string.format("%s[%s]|r |cffaaaaaa%s|r", Hex(lr, lg, lb), lvl or "?", name))
	else
		r.name:SetText(string.format("%s[%s] %s|r", Hex(lr, lg, lb), lvl or "?", name))
	end
	if st == "level" then
		r.state:SetText(string.format(T("needs level %d"), need or 0))
	elseif st == "available" and C.IsLeadIn(id) then
		r.state:SetText(T("optional lead-in"))
	else
		r.state:SetText(T(STATE_TEXT[st] or ""))
	end
	local w
	if st == "active" or st == "ready" then
		local place, kind = C.NextPlace(id)
		local e = C.FormatWhere(place)
		w = e and (T(kind == "do" and "Go to" or "Turn in") .. ": " .. e) or ""
	elseif st == "done" then
		w = ""
	else
		local g = C.FormatWhere(C.Giver(id))
		w = g and (T("Quest giver") .. ": " .. g) or ""
	end
	r.where:SetText(w)
	local on = ns.Guide and ns.Guide.IsTracked(id)
	r.track.tex:SetDesaturated(not on)
	r.track.tex:SetAlpha(on and 1 or 0.35)
	r.track:SetShown(on or (st ~= "done" and st ~= "skip"))
	r.mark:SetShown(highlight == id)
	r:SetAlpha((st == "done" or st == "skip") and 0.7 or 1)
	r:Show()
end

-- chains: list of lists of quest IDs. Returns the content height.
local function RenderChains(header, chains, highlight)
	local content = UI.rightContent
	local width = content:GetWidth()
	for _, r in ipairs(rows) do r:Hide() end
	for _, h in ipairs(heads) do h:Hide() end
	local y, ri, hi = 0, 0, 0
	local hide = DB().hideDone

	if header then
		hi = hi + 1
		local h = Head(hi)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", 0, -y)
		h:SetWidth(width)
		h.text:SetText(header.title)
		h.right:SetText(header.right or "")
		h:SetScript("OnClick", header.onClick)
		if h.lead then h.lead:Hide() end
		h:Show()
		y = y + HEAD_H
		if header.sub then
			hi = hi + 1
			local s = Head(hi)
			s:ClearAllPoints()
			s:SetPoint("TOPLEFT", 0, -y)
			s:SetWidth(width)
			s.text:SetText("|cff7fd4ff" .. header.sub .. "|r")
			s.right:SetText("")
			s.line:Hide()
			if s.lead then s.lead:Hide() end
			s:SetScript("OnClick", header.onSubClick)
			s:Show()
			y = y + HEAD_H
		end
		y = y + 6
	end

	-- inside the dungeon: what your quests need there
	local function DrawTargets()
	local targets = header and header.targets
	if targets and #targets > 0 then
		hi = hi + 1
		local h = Head(hi)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", 0, -y)
		h:SetWidth(width)
		h.text:SetText("|cffe8a33a" .. T("Inside: what your quests need") .. "|r")
		h.right:SetText("")
		h.line:Show()
		h:SetScript("OnClick", nil)
		if h.lead then h.lead:Hide() end
		h:Show()
		y = y + HEAD_H
		local TR = ns.Tracker
		for _, t in ipairs(targets) do
			ri = ri + 1
			local r = Row(ri)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", 8, -y)
			r:SetWidth(width - 8)
			r.quest = nil
			local doneT = C.TargetDone(t)
			r.icon:SetTexture(doneT and TR.ICON.done or TR.ICON[t.kind] or TR.ICON.kill)
			if r.icon.SetDesaturated then r.icon:SetDesaturated(false) end
			r.name:SetText(TR.Label(t))
			r.state:SetText(T(t.kind == "talk" and "talk" or t.kind == "kill" and "kill" or t.kind == "use" and "use" or "loot"))
			r.where:SetText(T("for") .. ": " .. TR.For(t))
			r.mark:Hide()
			r:SetAlpha(doneT and 0.5 or 1)
			r:Show()
			y = y + ROW_H
		end
		y = y + 8
	end
	end

	local function DrawChain(chain)
		local list = {}
		local doneCount = 0
		for _, id in ipairs(chain) do
			local st = C.Status(id)
			if st == "done" then
				doneCount = doneCount + 1
			end
			if not (hide and (st == "done" or st == "skip")) then
				list[#list + 1] = id
			end
		end
		if #list > 0 then
			if #chain > 1 or UI.forceChainHead then
				hi = hi + 1
				local h = Head(hi)
				h:ClearAllPoints()
				h:SetPoint("TOPLEFT", 0, -y)
				h:SetWidth(width)
				local leading = ns.Guide and ns.Guide.IsLeading(chain)
				h.text:SetText((leading and "|TInterface\\Minimap\\MiniMap-QuestArrow:14|t " or "") .. "|cffe8a33a" .. T("chain") .. ":|r " .. C.Name(chain[#chain]))
				h.right:SetText(string.format("%d/%d", doneCount, #chain))
				h.line:Show()
				h:SetScript("OnClick", nil)
				LeadButton(h, chain, leading)
				h:Show()
				y = y + HEAD_H
			end
			for _, id in ipairs(list) do
				ri = ri + 1
				local r = Row(ri)
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", #chain > 1 and 8 or 0, -y)
				r:SetWidth(width - (#chain > 1 and 8 or 0))
				PaintRow(r, id, highlight)
				y = y + ROW_H
			end
			y = y + 8
		end
	end

	-- Order: chains with something still to do first (to take, in progress,
	-- ready), then what your quests need inside the dungeon, then chains you
	-- have finished.
	local open, finished = {}, {}
	for _, chain in ipairs(chains) do
		local all = true
		for _, id in ipairs(chain) do
			local st = C.Status(id)
			if st ~= "done" and st ~= "skip" then
				all = false
				break
			end
		end
		if all then
			finished[#finished + 1] = chain
		else
			open[#open + 1] = chain
		end
	end
	-- among the open ones: something to turn in or do first, then quests to
	-- take, then ones that wait for a level or an earlier step
	local RANK = { ready = 1, active = 2, available = 3, level = 4, locked = 5 }
	local function Best(chain)
		local best = 9
		for _, id in ipairs(chain) do
			best = math.min(best, RANK[C.Status(id)] or 9)
		end
		return best
	end
	for i, chain in ipairs(open) do
		open[i] = { chain = chain, best = Best(chain), i = i }
	end
	table.sort(open, function(a, b)
		if a.best ~= b.best then
			return a.best < b.best
		end
		return a.i < b.i
	end)
	for _, e in ipairs(open) do
		DrawChain(e.chain)
	end
	DrawTargets()
	for _, chain in ipairs(finished) do
		DrawChain(chain)
	end
	content:SetHeight(math.max(y, 10))
	return y
end

-- The dungeon as a plan: numbered steps, each quest once, and under a
-- quest you do inside, what it needs there (kill, loot, use).
UI.PLAN_TITLE = {
	before = "Before you go in",
	inside = "In the dungeon",
	turnin = "After: turn in",
	later = "Later",
	done = "Done",
}
UI.TARGET_VERB = { kill = "Kill", loot = "Loot", use = "Use", talk = "Talk to" }

local function RenderPlan(header, plan, highlight)
	local content = UI.rightContent
	local width = content:GetWidth()
	for _, r in ipairs(rows) do r:Hide() end
	for _, h in ipairs(heads) do h:Hide() end
	local y, ri, hi = 0, 0, 0
	local TR = ns.Tracker

	local function Heading(text, right, sub)
		hi = hi + 1
		local h = Head(hi)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", 0, -y)
		h:SetWidth(width)
		h.text:SetText(text)
		h.right:SetText(right or "")
		h.line:SetShown(not sub)
		h:SetScript("OnClick", nil)
		if h.lead then h.lead:Hide() end
		h:Show()
		y = y + HEAD_H
		return h
	end

	if header then
		local h = Heading(header.title, header.right)
		h:SetScript("OnClick", header.onClick)
		if header.sub then
			local s = Heading("|cff7fd4ff" .. header.sub .. "|r", nil, true)
			s:SetScript("OnClick", header.onSubClick)
		end
		y = y + 6
	end

	local n = 0
	for _, section in ipairs(plan) do
		if not (section.key == "done" and DB().hideDone) then
			local title = T(UI.PLAN_TITLE[section.key])
			if section.key ~= "later" and section.key ~= "done" then
				n = n + 1
				title = n .. ". " .. title
			end
			Heading("|cffe8a33a" .. title .. "|r")
			for _, item in ipairs(section.items) do
				ri = ri + 1
				local r = Row(ri)
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", 8, -y)
				r:SetWidth(width - 8)
				PaintRow(r, item.quest, highlight)
				y = y + ROW_H
				for _, t in ipairs(item.targets) do
					ri = ri + 1
					local tr = Row(ri)
					tr:ClearAllPoints()
					tr:SetPoint("TOPLEFT", 30, -y)
					tr:SetWidth(width - 30)
					tr.quest = nil
					local doneT = C.TargetDone(t)
					tr.icon:SetTexture(doneT and TR.ICON.done or TR.ICON[t.kind] or TR.ICON.kill)
					if tr.icon.SetDesaturated then tr.icon:SetDesaturated(false) end
					tr.name:SetText(TR.Label(t))
					tr.state:SetText("")
					tr.where:SetText(T(UI.TARGET_VERB[t.kind] or "Loot"))
					tr.mark:Hide()
					tr:SetAlpha(doneT and 0.5 or 1)
					tr:Show()
					y = y + ROW_H
				end
			end
			y = y + 8
		end
	end
	content:SetHeight(math.max(y, 10))
	return y
end
UI.RenderPlan = RenderPlan

local function DungeonCounts(d)
	local done, total = 0, 0
	for _, chain in ipairs(chainsByArea[d.area] or {}) do
		for _, id in ipairs(chain) do
			total = total + 1
			if C.player.done(id) then
				done = done + 1
			end
		end
	end
	return done, total
end

local function VisibleDungeons()
	local me = C.player.level() or 1
	local out = {}
	for _, d in ipairs(C.index and C.index.dungeons or {}) do
		local chains = chainsByArea[d.area]
		if chains and #chains > 0 then
			local fits = DB().allLevels or (d.max >= me - 3 and d.min <= me + 10)
			if fits then
				out[#out + 1] = d
			end
		end
	end
	return out
end

local function RenderDungeons()
	local list = VisibleDungeons()
	local me = C.player.level() or 1
	-- default: the dungeon that fits your level best
	if not UI.selected or not chainsByArea[UI.selected] then
		local best, bestDist
		for _, d in ipairs(list) do
			local mid = (d.min + d.max) / 2
			local dist = math.abs(mid - me)
			if not bestDist or dist < bestDist then
				best, bestDist = d, dist
			end
		end
		UI.selected = best and best.area or nil
	end
	for _, b in ipairs(leftButtons) do b:Hide() end
	for i, d in ipairs(list) do
		local b = LeftButton(i)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 0, -(i - 1) * 23)
		local r, g, bl = LevelColor((d.min + d.max) / 2)
		b.name:SetText(Hex(r, g, bl) .. d.name .. "|r")
		local done, total = DungeonCounts(d)
		b.info:SetText(string.format("%d-%d  |cffffffff%d/%d|r", d.min, d.max, done, total))
		b.hl:SetShown(UI.selected == d.area)
		b:SetScript("OnClick", function()
			UI.selected = d.area
			UI.right:SetVerticalScroll(0)
			UI.Refresh()
		end)
		b:Show()
	end
	UI.leftContent:SetHeight(math.max(#list * 23, 10))

	local d = UI.selected and C.index.byArea[UI.selected]
	if not d then
		RenderChains(nil, {})
		UI.message:SetText(T("No dungeon quests for your faction and class here."))
		return
	end
	UI.message:SetText("")
	local header = { title = d.name .. (d.raid and " (raid)" or ""), right = string.format("%d-%d", d.min, d.max) }
	local e = d.entrances[1]
	if type(e) == "table" and e[1] then
		local zone = C.AreaName(e[1]) or "?"
		header.sub = string.format("%s: %s (%.0f, %.0f)", T("Entrance"), zone, e[2] or 0, e[3] or 0)
		header.onSubClick = function()
			local spot = { area = e[1], x = e[2], y = e[3] }
			if C.Waypoint(spot, d.name) then
				print("|cffe8a33aChainlog|r " .. string.format(T("Waypoint set: %s"), d.name .. " - " .. zone))
			end
		end
	end
	if ns.Tracker then
		RenderPlan(header, C.DungeonPlan(d, chainsByArea[d.area]))
	else
		RenderChains(header, chainsByArea[d.area])
	end
end

local function RenderLog()
	local items = {}
	for _, id in ipairs(C.LogQuests()) do
		local chain, pos = C.ChainOf(id)
		local d = C.DungeonOf(id)
		if #chain > 1 or d then
			items[#items + 1] = { id = id, chain = chain, pos = pos, dungeon = d }
		end
	end
	table.sort(items, function(a, b)
		return (C.Level(a.id) or 0) < (C.Level(b.id) or 0)
	end)
	local found = false
	for _, it in ipairs(items) do
		if it.id == UI.selected then
			found = true
		end
	end
	if not found then
		UI.selected = items[1] and items[1].id or nil
	end
	for _, b in ipairs(leftButtons) do b:Hide() end
	for i, it in ipairs(items) do
		local b = LeftButton(i)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", 0, -(i - 1) * 23)
		local r, g, bl = LevelColor(C.Level(it.id))
		b.name:SetText(Hex(r, g, bl) .. C.Name(it.id) .. "|r")
		b.info:SetText(#it.chain > 1 and string.format(T("step %d/%d"), it.pos, #it.chain) or (it.dungeon and it.dungeon.name:sub(1, 10) or ""))
		b.hl:SetShown(UI.selected == it.id)
		b:SetScript("OnClick", function()
			UI.selected = it.id
			UI.right:SetVerticalScroll(0)
			UI.Refresh()
		end)
		b:Show()
	end
	UI.leftContent:SetHeight(math.max(#items * 23, 10))
	if not UI.selected then
		RenderChains(nil, {})
		UI.message:SetText(T("None of your quests belong to a chain."))
		return
	end
	UI.message:SetText("")
	local chain = C.ChainOf(UI.selected)
	local d = C.DungeonOf(UI.selected)
	UI.forceChainHead = true
	RenderChains({ title = C.Name(UI.selected), right = d and d.name or "" }, { chain }, UI.selected)
	UI.forceChainHead = false
end

function UI.Refresh()
	if not (win and win:IsShown()) then
		return
	end
	local db = DB()
	UI.hideDone:SetChecked(db.hideDone)
	UI.allLevels:SetChecked(db.allLevels)
	UI.allLevels:SetShown(db.tab == "dungeons")
	for key, b in pairs(UI.tabs) do
		if key == db.tab then
			b:LockHighlight()
		else
			b:UnlockHighlight()
		end
	end
	local G = ns.Guide
	if G and G.chain then
		UI.legend:SetText("|TInterface\\Minimap\\MiniMap-QuestArrow:12|t |cffffd100" .. G.Describe(G.step) .. "|r")
	else
		UI.legend:SetText(T("Click: show on the map  ·  Shift-click: quest log"))
	end
	if not C.source.available() then
		for _, b in ipairs(leftButtons) do b:Hide() end
		RenderChains(nil, {})
		UI.message:SetText(T("QuestieDB is not loaded: Chainlog needs it for quest data."))
		return
	end
	if not built then
		UI.EnsureIndex()
		for _, b in ipairs(leftButtons) do b:Hide() end
		RenderChains(nil, {})
		UI.message:SetText(T("Building the quest index..."))
		return
	end
	if db.tab == "log" then
		RenderLog()
	else
		RenderDungeons()
	end
end

function UI.Toggle()
	if not win then
		Build()
	end
	if win:IsShown() then
		win:Hide()
	else
		win:Show()
	end
end

function UI.Open(tab)
	if not win then
		Build()
	end
	if tab then
		DB().tab = tab
		UI.selected = nil
	end
	win:Show()
	UI.Refresh()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local ev = CreateFrame("Frame")
local pending = false
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		DB()
		-- build in the background a little after login
		if C_Timer and C_Timer.After then
			C_Timer.After(6, UI.EnsureIndex)
		end
		return
	end
	-- quest progress changed: redraw once on the next frame
	if win and win:IsShown() and not pending then
		pending = true
		if C_Timer and C_Timer.After then
			C_Timer.After(0.2, function()
				pending = false
				UI.Refresh()
			end)
		else
			pending = false
			UI.Refresh()
		end
	end
end)
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_LEVEL_UP" }) do
	pcall(ev.RegisterEvent, ev, e)
end

------------------------------------------------------------------------
-- Slash
------------------------------------------------------------------------

SLASH_CHAINLOG1 = "/chainlog"
SLASH_CHAINLOG2 = "/chains"
SlashCmdList = SlashCmdList or {}
SlashCmdList.CHAINLOG = function(msg)
	local cmd = string.lower(msg or ""):match("^(%S+)") or ""
	local P = "|cffe8a33aChainlog|r "
	if cmd == "log" or cmd == "quests" then
		UI.Open("log")
	elseif cmd == "warn" then
		DB().warn = not DB().warn
		print(P .. T("abandon warning:") .. " " .. (DB().warn and T("on") or T("off")))
	elseif cmd == "tracker" then
		if ns.Tracker then ns.Tracker.Toggle() end
	elseif cmd == "marks" then
		if ns.Marks then ns.Marks.Toggle() end
	elseif cmd == "stop" then
		if ns.Guide then ns.Guide.Stop() end
	elseif cmd == "next" then
		if ns.Guide and ns.Guide.chain then
			ns.Guide.Update(true)
		else
			print(P .. T("Not leading any chain. Press Lead on a chain in /chainlog."))
		end
	elseif cmd == "minimap" then
		if ns.Minimap and ns.Minimap.Toggle then
			ns.Minimap.Toggle()
		end
	elseif cmd == "help" then
		print(P .. "by addicted · |cff7fd4ffaddicted.sh|r")
		print("  /chainlog          " .. T("Dungeons"))
		print("  /chainlog log      " .. T("My quests"))
		print("  /chainlog next     " .. T("Lead me through this chain"))
		print("  /chainlog stop     " .. T("Stop leading"))
		print("  /chainlog tracker  " .. T("dungeon checklist:"))
		print("  /chainlog marks  " .. T("quest mob icons:"))
		print("  /chainlog warn     " .. T("abandon warning:"))
		print("  /chainlog minimap  " .. T("minimap button:"))
	else
		UI.Toggle()
	end
end

function Chainlog_OnAddonCompartmentClick()
	UI.Toggle()
end
