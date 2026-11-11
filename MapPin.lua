--[[
  Chainlog map pin: "show me where" for a quest.

  Clicking a quest in the window opens the world map on the right zone with
  a Chainlog pin on the spot (yellow "!" for where to pick it up, "?" for
  where to turn it in), next to the waypoint. Shift-click opens the quest
  in your quest log instead, when you have it.
]]

local _, ns = ...
local T = ns.T
local C = ns.Core

local MP = {}
ns.MapPin = MP

MP.ICON = {
	take = "Interface\\GossipFrame\\AvailableQuestIcon",
	turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
}

MP.target = nil -- { map, x, y, title, kind }

local pin

local function Canvas()
	return WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
end

local function CanvasScale()
	local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
	if type(sc) == "table" and sc.GetCanvasScale then
		local ok, s = pcall(sc.GetCanvasScale, sc)
		if ok and type(s) == "number" and s > 0 then
			return s
		end
	end
	return 1
end

local function Build(canvas)
	pin = CreateFrame("Frame", "ChainlogMapPin", canvas)
	pin:SetSize(26, 26)
	pin:SetFrameStrata("HIGH")
	pin.glow = pin:CreateTexture(nil, "BACKGROUND")
	pin.glow:SetPoint("CENTER")
	pin.glow:SetSize(44, 44)
	pin.glow:SetTexture("Interface\\Cooldown\\star4")
	pin.glow:SetBlendMode("ADD")
	pin.glow:SetVertexColor(1, 0.82, 0.2)
	pin.icon = pin:CreateTexture(nil, "ARTWORK")
	pin.icon:SetAllPoints()
	pin:EnableMouse(true)
	pin:SetScript("OnEnter", function(self)
		if not MP.target then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(MP.target.title or "", 1, 0.82, 0)
		if MP.target.where then
			GameTooltip:AddLine(MP.target.where, 1, 1, 1, true)
		end
		GameTooltip:AddLine("Chainlog", 0.91, 0.64, 0.23)
		GameTooltip:Show()
	end)
	pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local t = 0
	pin:SetScript("OnUpdate", function(_, elapsed)
		t = t + (elapsed or 0)
		pin.glow:SetAlpha(0.45 + 0.35 * math.sin(t * 4))
	end)
	pin:Hide()
end

-- Places the pin when the map shows the target's zone.
function MP.Refresh()
	local canvas = Canvas()
	if not canvas then
		return
	end
	if not pin then
		Build(canvas)
	end
	local tg = MP.target
	local shown = tg and WorldMapFrame:IsShown() and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() == tg.map
	if not shown then
		pin:Hide()
		return
	end
	local cs = CanvasScale()
	pin:SetScale(1 / cs)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", canvas, "TOPLEFT", tg.x / 100 * canvas:GetWidth() * cs, -tg.y / 100 * canvas:GetHeight() * cs)
	pin.icon:SetTexture(MP.ICON[tg.kind] or MP.ICON.take)
	pin:Show()
end

local hooked = false
local function Hook()
	if hooked or not WorldMapFrame then
		return
	end
	hooked = true
	if WorldMapFrame.OnMapChanged then
		hooksecurefunc(WorldMapFrame, "OnMapChanged", MP.Refresh)
	end
	WorldMapFrame:HookScript("OnShow", MP.Refresh)
	local scale, wait = nil, 0
	WorldMapFrame:HookScript("OnUpdate", function(_, elapsed)
		wait = wait - (elapsed or 0)
		if wait > 0 then
			return
		end
		wait = 0.25
		local s = CanvasScale()
		if s ~= scale then
			scale = s
			MP.Refresh()
		end
	end)
end

-- Opens the world map on the place `w` with the pin.
-- kind: "take" or "turnin". Returns true when the map could be opened.
function MP.Show(w, title, kind)
	local map, x, y = C.MapPoint(w)
	if not map then
		return false
	end
	local okW, where = pcall(C.FormatWhere, w)
	MP.target = { map = map, x = x, y = y, title = title, kind = kind, where = okW and where or nil }
	Hook()
	local ok = false
	if OpenWorldMap then
		ok = pcall(OpenWorldMap, map)
	end
	if not ok and WorldMapFrame then
		ok = pcall(function()
			if not WorldMapFrame:IsShown() then
				ShowUIPanel(WorldMapFrame)
			end
			WorldMapFrame:SetMapID(map)
		end)
	end
	pcall(MP.Refresh)
	return ok
end

-- Opens a quest you have in your quest log. Returns true on success.
function MP.OpenQuest(id)
	if QuestMapFrame_OpenToQuestDetails then
		if pcall(QuestMapFrame_OpenToQuestDetails, id) then
			return true
		end
	end
	local index
	if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		local ok, i = pcall(C_QuestLog.GetLogIndexForQuestID, id)
		index = ok and i or nil
	end
	if not index and GetQuestLogIndexByID then
		local ok, i = pcall(GetQuestLogIndexByID, id)
		index = ok and i or nil
	end
	if not index or index == 0 then
		return false
	end
	return pcall(function()
		if QuestLogFrame then
			ShowUIPanel(QuestLogFrame)
		end
		if QuestLog_SetSelection then
			QuestLog_SetSelection(index)
		end
		if QuestLog_Update then
			QuestLog_Update()
		end
	end) and true or false
end
