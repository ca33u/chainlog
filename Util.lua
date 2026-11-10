--[[
  Chainlog: website link. The game cannot open web pages, so a click shows
  the address in a small window, selected and ready for Cmd+C / Ctrl+C.
]]

local _, ns = ...
local T = ns.T

local copy

function ns.ShowCopy(url)
	if not copy then
		copy = CreateFrame("Frame", "ChainlogCopyDialog", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
		copy:SetSize(330, 104)
		copy:SetPoint("CENTER", 0, 120)
		copy:SetFrameStrata("FULLSCREEN_DIALOG")
		copy:SetToplevel(true)
		copy:EnableMouse(true)
		if copy.SetBackdrop then
			copy:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 },
			})
		end
		local hint = copy:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		hint:SetPoint("TOP", 0, -22)
		hint:SetText(T("Press Cmd+C (Ctrl+C) to copy the address"))
		local eb = CreateFrame("EditBox", nil, copy, "InputBoxTemplate")
		eb:SetSize(250, 22)
		eb:SetPoint("TOP", 0, -44)
		eb:SetAutoFocus(true)
		eb:SetJustifyH("CENTER")
		eb:SetScript("OnEscapePressed", function() copy:Hide() end)
		eb:SetScript("OnEnterPressed", function() copy:Hide() end)
		eb:SetScript("OnTextChanged", function(self, user)
			if user then
				self:SetText(copy.url or "")
				self:HighlightText()
			end
		end)
		eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
		copy.eb = eb
		local x = CreateFrame("Button", nil, copy, "UIPanelCloseButton")
		x:SetPoint("TOPRIGHT", -5, -5)
		local done = CreateFrame("Button", nil, copy, "UIPanelButtonTemplate")
		done:SetSize(90, 20)
		done:SetPoint("BOTTOM", 0, 16)
		done:SetText(OKAY or "OK")
		done:SetScript("OnClick", function() copy:Hide() end)
		if UISpecialFrames then
			table.insert(UISpecialFrames, "ChainlogCopyDialog")
		end
	end
	copy.url = url
	copy.eb:SetText(url)
	copy:Show()
	copy.eb:SetFocus()
	copy.eb:HighlightText()
end

function ns.Link(parent, text, url)
	local b = CreateFrame("Button", nil, parent)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("LEFT")
	b.text:SetText(text)
	b.text:SetTextColor(0.5, 0.83, 1)
	local w = b.text:GetStringWidth()
	b:SetSize((type(w) == "number" and w > 0 and w or 60) + 2, 14)
	b:SetScript("OnEnter", function(self)
		b.text:SetTextColor(0.75, 0.92, 1)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(url)
			GameTooltip:AddLine(T("Click to copy the address"), 0.8, 0.8, 0.8)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function()
		b.text:SetTextColor(0.5, 0.83, 1)
		if GameTooltip then GameTooltip:Hide() end
	end)
	b:SetScript("OnClick", function() ns.ShowCopy(url) end)
	return b
end
