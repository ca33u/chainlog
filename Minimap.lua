--[[
  Chainlog: round button on the minimap ring, like the other addon buttons.

  Left click:  open Chainlog
  Drag:        move it around the minimap
  /chainlog minimap   show or hide the button
]]

local _, ns = ...
local T = ns.T

local M = {}
ns.Minimap = M

local ICON = "Interface\\AddOns\\Chainlog\\Media\\minimap"

local function IsSecret(v)
	return issecretvalue and issecretvalue(v) and true or false
end

local function Num(v)
	return type(v) == "number" and not IsSecret(v) and v or nil
end

local btn

local function Place()
	if not btn then
		return
	end
	local db = ChainlogDB
	if not db or db.minimap == false or not Minimap then
		btn:Hide()
		return
	end
	local ok, mx, my = pcall(Minimap.GetCenter, Minimap)
	local okW, width = pcall(Minimap.GetWidth, Minimap)
	mx, my, width = ok and Num(mx), ok and Num(my), okW and Num(width)
	if not mx or not my or not width or width < 20 then
		btn:Hide()
		return
	end
	local okS, ms = pcall(Minimap.GetEffectiveScale, Minimap)
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	ms, us = okS and Num(ms), okU and Num(us)
	local a = math.rad(db.minimapAngle or 170)
	local r = width / 2 + 8
	local x, y = mx + math.cos(a) * r, my + math.sin(a) * r
	if ms and us and ms > 0 and us > 0 then
		x, y = x * ms / us, y * ms / us
	end
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	btn:Show()
end

local function Create()
	if btn or not Minimap then
		return
	end
	btn = CreateFrame("Button", "ChainlogMinimapButton", UIParent)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(40)
	btn:SetClampedToScreen(true)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if icon.SetMask then
		pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
	end

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	local dragging = false
	btn:SetScript("OnClick", function(_, button)
		if dragging then
			return
		end
		if button == "RightButton" then
			ns.Window.Open("log")
		else
			ns.Window.Toggle()
		end
	end)
	btn:SetScript("OnDragStart", function(self)
		dragging = true
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			mx, my, px, py, scale = Num(mx), Num(my), Num(px), Num(py), Num(scale)
			if mx and my and px and py and scale and scale > 0 and ChainlogDB then
				ChainlogDB.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
				Place()
			end
		end)
	end)
	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		C_Timer.After(0, function()
			dragging = false
		end)
	end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("|cffe8a33aChainlog|r")
		GameTooltip:AddLine(T("Left-click: open Chainlog"), 0.8, 0.8, 0.8)
		GameTooltip:AddLine(T("Drag: move the button"), 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	Place()
end

function M.Toggle()
	ChainlogDB = ChainlogDB or {}
	ChainlogDB.minimap = ChainlogDB.minimap == false
	Create()
	Place()
	print("|cffe8a33aChainlog|r " .. T("minimap button:") .. " " .. (ChainlogDB.minimap and T("on") or T("off")))
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function()
	ChainlogDB = ChainlogDB or {}
	if ChainlogDB.minimap == nil then
		ChainlogDB.minimap = true
	end
	Create()
	Place()
	if C_Timer and C_Timer.After then
		C_Timer.After(1, Place)
	end
end)
frame:RegisterEvent("PLAYER_LOGIN")
pcall(frame.RegisterEvent, frame, "DISPLAY_SIZE_CHANGED")
pcall(frame.RegisterEvent, frame, "UI_SCALE_CHANGED")
