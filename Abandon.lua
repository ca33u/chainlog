--[[
  Chainlog: warning before you abandon a chain quest.

  When the game asks "Abandon <quest>?", Chainlog checks the quest. If it is
  a dungeon quest or a step of a chain, a small panel appears above the
  game's question with what you would lose and where to pick it up again.
  Chainlog never touches the game's own dialog: it only listens to
  C_QuestLog.SetAbandonQuest (a post-hook) and shows its own frame.

  /chainlog warn   turn the warning on or off
]]

local _, ns = ...
local T = ns.T
local C = ns.Core

local A = {}
ns.Abandon = A

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local SHOW_FOR = 20 -- seconds

-- The warning lines for a quest, or nil when it is not part of anything.
-- Pure apart from Core reads (tests/abandon_test.lua).
function A.Lines(id)
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	local lines = {}
	local chain, pos = C.ChainOf(id)
	local d = C.DungeonOf(id)
	if #chain > 1 then
		lines[#lines + 1] = string.format(T("Step %d of %d in a chain that leads to: %s"), pos, #chain, C.Name(chain[#chain]))
	end
	if d then
		lines[#lines + 1] = string.format(T("Dungeon quest: %s"), d.name)
	end
	if #lines == 0 then
		return nil
	end
	local later = {}
	for i = pos + 1, #chain do
		later[#later + 1] = C.Name(chain[i])
		if #later >= 3 then
			if #chain > i then
				later[#later + 1] = "..."
			end
			break
		end
	end
	if #later > 0 then
		lines[#lines + 1] = string.format(T("Abandoning it locks the next steps: %s"), table.concat(later, ", "))
	end
	local where = C.FormatWhere(C.Giver(id))
	if where then
		lines[#lines + 1] = string.format(T("To take it again: %s"), where)
	end
	if pos > 1 then
		lines[#lines + 1] = T("Abandoning keeps the earlier steps done, but this one must be picked up again.")
	end
	return lines
end

local panel, hideAt

local function Build()
	panel = CreateFrame("Frame", "ChainlogAbandonWarning", UIParent, BACKDROP)
	panel:SetSize(440, 100)
	panel:SetPoint("TOP", UIParent, "TOP", 0, -40)
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetToplevel(true)
	panel:EnableMouse(true)
	if panel.SetBackdrop then
		panel:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end
	panel.icon = panel:CreateTexture(nil, "ARTWORK")
	panel.icon:SetSize(28, 28)
	panel.icon:SetPoint("TOPLEFT", 18, -18)
	panel.icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.title:SetPoint("TOPLEFT", 54, -20)
	panel.title:SetPoint("RIGHT", -20, 0)
	panel.title:SetJustifyH("LEFT")
	panel.body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.body:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -6)
	panel.body:SetPoint("RIGHT", -20, 0)
	panel.body:SetJustifyH("LEFT")
	panel.body:SetSpacing(3)
	local ok = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	ok:SetSize(110, 20)
	ok:SetPoint("BOTTOMRIGHT", -18, 16)
	ok:SetText(T("OK"))
	ok:SetScript("OnClick", function() panel:Hide() end)
	panel:SetScript("OnUpdate", function(self)
		if hideAt and GetTime() > hideAt then
			self:Hide()
		end
	end)
	panel:Hide()
end

function A.Show(id)
	if not (ns.DB and ns.DB().warn) then
		return
	end
	if not (ns.Window and ns.Window.IsBuilt and ns.Window.IsBuilt()) then
		-- dungeon lookups need the index; chains work without it
		if ns.Window and ns.Window.EnsureIndex then
			ns.Window.EnsureIndex()
		end
	end
	local ok, lines = pcall(A.Lines, id)
	if not ok or not lines then
		return
	end
	if not panel then
		Build()
	end
	panel.title:SetText(T("Chain quest") .. ": |cffffd100" .. C.Name(id) .. "|r")
	panel.body:SetText(table.concat(lines, "\n"))
	local h = panel.body:GetStringHeight()
	panel:SetHeight(84 + ((type(h) == "number" and h) or 40))
	hideAt = GetTime() + SHOW_FOR
	panel:Show()
end

function A.Hide()
	if panel then
		panel:Hide()
	end
end

-- Post-hook: runs after the game stored which quest is being abandoned.
if C_QuestLog and type(C_QuestLog.SetAbandonQuest) == "function" and hooksecurefunc then
	hooksecurefunc(C_QuestLog, "SetAbandonQuest", function()
		local id = C_QuestLog.GetAbandonQuest and select(2, pcall(C_QuestLog.GetAbandonQuest))
		if type(id) == "number" and not (issecretvalue and issecretvalue(id)) then
			A.Show(id)
		end
	end)
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", A.Hide)
pcall(ev.RegisterEvent, ev, "QUEST_REMOVED")
