-- Minimal WoW API stand-ins for running Chainlog outside the game.
local total, fails = 0, 0
function Check(cond, msg)
	total = total + 1
	if cond then
		print("ok    " .. msg)
	else
		fails = fails + 1
		print("FAIL  " .. msg)
	end
end
function Report(name)
	print(string.format("%s: %d checks, %d failed", name, total, fails))
	os.exit(fails == 0 and 0 or 1)
end

local function Obj(extra)
	local o = extra or {}
	local scripts = {}
	o.SetScript = function(self, k, fn) scripts[k] = fn end
	o.GetScript = function(self, k) return scripts[k] end
	o.IsShown = function(self) return self._shown or false end
	o.IsVisible = o.IsShown
	o.Show = function(self) self._shown = true; if scripts.OnShow then scripts.OnShow(self) end end
	o.Hide = function(self) self._shown = false end
	o.SetShown = function(self, v) if v then self:Show() else self:Hide() end end
	o.GetStringWidth = function() return 50 end
	o.GetStringHeight = function() return 40 end
	o.GetWidth = function() return 300 end
	o.GetChecked = function() return false end
	o.CreateTexture = function() return Obj() end
	o.CreateFontString = function() return Obj() end
	-- methods (Capitalized) are no-ops; plain fields stay nil like in the game
	return setmetatable(o, { __index = function(_, k)
		if type(k) == "string" and k:match("^%u") then
			return function() end
		end
	end })
end
StubObj = Obj
function CreateFrame() return Obj() end
UIParent = Obj()
Minimap = Obj()
GameTooltip = Obj()
UISpecialFrames = {}
SlashCmdList = {}
function GetTime() return 1000 end
function GetLocale() return "enUS" end
function hooksecurefunc(t, k, fn)
	local old = t[k]
	t[k] = function(...) local a, b, c = old(...); fn(...); return a, b, c end
end
C_Timer = { After = function(_, fn) end }

-- Loads one addon file with the shared namespace.
NS = {}
function LoadFile(path)
	local chunk = assert(loadfile(path))
	chunk("Chainlog", NS)
end
