-- Strict mock of the WoW: Forever API surface (started for Rep Planner, so the character window and
-- Reputation tab are here too); tlmock.lua adds the maps, waypoints and world map Trainer Locator uses.
-- Methods that aren't defined here raise "attempt to call" errors, so an API typo can't pass.
local DIR = ...

local function class(parent)
	local c = {}
	c.__index = c
	if parent then setmetatable(c, { __index = parent }) end
	return c
end

MOCK = {
	events = {}, now = 1000, epoch = 1790000000, chat = {}, secrets = {},
	factions = {},         -- [factionID] = { name, value, isHeader, isHeaderWithRep, watched }
	order = {},            -- faction IDs as the Reputation tab lists them
	selected = 0,          -- index in order
	quests = {},           -- quest log: { questID, complete, isHeader }
	done = {},             -- [questID] = true
	items = {},            -- [itemID] = count
	instance = nil,        -- { mapID, name, kind }
	zoneName = "Elwynn Forest",
	dead = false,
	side = "Alliance", classID = 8, raceID = 1, sex = 3,
	secretIdentity = false,
	editMode = false,
	level = 60,
	sounds = {},
	missingFiles = {},     -- texture files this client doesn't have
}

-- The atlases WoW: Forever has that the planner may use, with their sizes
MOCK.ATLASES = {}
for line in io.lines(DIR .. "/test/atlases.txt") do
	local name, w, h = line:match("^(%S+)%s+(%d+)%s+(%d+)$")
	if name and not line:find("^#") then MOCK.ATLASES[name] = { tonumber(w), tonumber(h) } end
end

local KNOWN_EVENTS = {}
for line in io.lines(DIR .. "/test/events.txt") do KNOWN_EVENTS[line] = true end

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

---------------------------------------------------------------- secrets
function MOCK.Secret()
	local p = newproxy(true)
	local mt = getmetatable(p)
	local function boom() error("attempt to use a secret value") end
	mt.__index, mt.__concat, mt.__tostring, mt.__lt, mt.__le = boom, boom, boom, boom, boom
	mt.__add, mt.__sub, mt.__mul, mt.__div, mt.__unm = boom, boom, boom, boom, boom
	MOCK.secrets[p] = true
	return p
end
function issecretvalue(v) return MOCK.secrets[v] == true end

---------------------------------------------------------------- regions
local Region = class()
local POINTS = { TOPLEFT = 1, TOPRIGHT = 1, BOTTOMLEFT = 1, BOTTOMRIGHT = 1, TOP = 1, BOTTOM = 1, LEFT = 1, RIGHT = 1, CENTER = 1 }
function Region:SetPoint(point, a, b, c, d)
	assert(POINTS[point], "bad anchor point " .. tostring(point))
	local rel, relPoint, x, y
	if type(a) == "table" then
		rel, relPoint, x, y = a, b, c, d
	elseif type(a) == "number" then
		rel, relPoint, x, y = self._parent, point, a, b
	else
		rel, relPoint, x, y = self._parent, a or point, b, c
	end
	relPoint = relPoint or point
	x, y = x or 0, y or 0
	assert(type(rel) == "table" and rel._kind, "SetPoint needs a region to anchor to")
	assert(POINTS[relPoint], "bad relative point " .. tostring(relPoint))
	assert(finite(x) and finite(y), "SetPoint offset isn't a finite number")
	self._points = self._points or {}
	for i = #self._points, 1, -1 do
		if self._points[i][1] == point then table.remove(self._points, i) end
	end
	table.insert(self._points, { point, rel, relPoint, x, y })
end
function Region:GetPoint(i)
	local p = self._points and self._points[i or 1]
	if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Region:SetAllPoints(rel) self._points = { { "TOPLEFT", rel or self._parent, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel or self._parent, "BOTTOMRIGHT", 0, 0 } } end
function Region:ClearAllPoints() self._points = {} end
function Region:SetWidth(w)
	assert(finite(w) and w >= 0, "bad width " .. tostring(w))
	local changed = w ~= self._w
	self._w = w
	if changed and self._Fire then self:_Fire("OnSizeChanged", self._w, self._h) end
end
function Region:SetHeight(h)
	assert(finite(h) and h >= 0, "bad height " .. tostring(h))
	local changed = h ~= self._h
	self._h = h
	if changed and self._Fire then self:_Fire("OnSizeChanged", self._w, self._h) end
end
function Region:SetSize(w, h) self:SetWidth(w); self:SetHeight(h) end
function Region:GetWidth() return self._w or 0 end
function Region:GetHeight() return self._h or 0 end
function Region:Show()
	local was = self._shown
	self._shown = true
	if not was and self._Fire then self:_Fire("OnShow") end
end
function Region:Hide()
	local was = self._shown
	self._shown = false
	if was and self._Fire then self:_Fire("OnHide") end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self._shown == true end
function Region:IsVisible()
	local r = self
	while r do
		if not r._shown then return false end
		r = r._parent
	end
	return true
end
function Region:GetParent() return self._parent end
function Region:SetAlpha(a) assert(finite(a) and a >= 0 and a <= 1, "bad alpha"); self._alpha = a end
function Region:GetAlpha() return self._alpha or 1 end

local Texture = class(Region)
-- Returns whether the file exists, as the game's does
function Texture:SetTexture(file)
	assert(type(file) == "string" or type(file) == "number", "SetTexture wants a file")
	self._file, self._atlas, self._coords = file, nil, nil
	return not MOCK.missingFiles[file]
end
function Texture:GetTexture() return self._file or self._atlas end
-- Only atlases WoW: Forever has (atlases.txt); useAtlasSize sizes the texture like the game
function Texture:SetAtlas(atlas, useAtlasSize)
	local size = MOCK.ATLASES[atlas]
	assert(size, "no atlas called " .. tostring(atlas) .. " (tools/test/atlases.txt)")
	assert(useAtlasSize == nil or type(useAtlasSize) == "boolean", "SetAtlas: useAtlasSize is a boolean")
	self._atlas, self._file, self._coords, self._useAtlasSize = atlas, nil, nil, useAtlasSize
	if useAtlasSize then self:SetSize(size[1], size[2]) end
	return true
end
function Texture:GetAtlas() return self._atlas end
function Texture:SetTexCoord(...)
	local n = select("#", ...)
	assert(n == 4 or n == 8, "SetTexCoord takes 4 or 8 numbers")
	for i = 1, n do assert(finite((select(i, ...))), "SetTexCoord wants numbers") end
	self._coords = { ... }
end
function Texture:SetBlendMode(mode)
	assert(({ DISABLE = 1, BLEND = 1, ALPHAKEY = 1, ADD = 1, MOD = 1 })[mode], "bad blend mode " .. tostring(mode))
	self._blend = mode
end
function Texture:SetDesaturated(v) assert(type(v) == "boolean", "SetDesaturated wants a boolean"); self._desaturated = v end
function Texture:SetHorizTile(v) self._htile = v end
function Texture:SetVertTile(v) self._vtile = v end
function Texture:SetColorTexture(r, g, b, a)
	for _, v in ipairs({ r, g, b, a or 1 }) do assert(finite(v) and v >= 0 and v <= 1, "SetColorTexture out of range: " .. tostring(v)) end
	self._color = { r, g, b, a or 1 }
end
function Texture:SetVertexColor(r, g, b, a) self._vcolor = { r, g, b, a } end

local FontString = class(Region)
function FontString:SetText(t)
	assert(t == nil or type(t) == "string" or type(t) == "number", "SetText needs a string, got " .. type(t))
	self._text = t and tostring(t) or ""
end
function FontString:GetText() return self._text end
function FontString:SetTextColor(r, g, b, a)
	for _, v in ipairs({ r, g, b, a or 1 }) do assert(finite(v) and v >= 0 and v <= 1, "SetTextColor out of range: " .. tostring(v)) end
	self._color = { r, g, b }
end
function FontString:SetJustifyH(j) assert(j == "LEFT" or j == "RIGHT" or j == "CENTER"); self._justify = j end
function FontString:SetJustifyV(j) assert(j == "TOP" or j == "MIDDLE" or j == "BOTTOM") end
function FontString:SetWordWrap(v) assert(type(v) == "boolean"); self._wrap = v end
function FontString:SetSpacing(n) assert(finite(n)); self._spacing = n end
-- Plain text without colour codes, for measuring and for the tests
function MOCK.Plain(s)
	s = s or ""
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return s
end
-- Rough height: 12px a line, wrapping at about 5.5px a character when a width is set. preview.py
-- sets MOCK.Measure to measure with the game's font instead.
function FontString:GetStringHeight()
	if MOCK.Measure then return (select(2, MOCK.Measure(self._font, self._text or "", self._wrap ~= false and self._w or 0, self._spacing or 0))) end
	local text = MOCK.Plain(self._text)
	if text == "" then return 0 end
	local lines = 0
	local perLine = self._w and self._w > 0 and math.floor(self._w / 5.5) or 10000
	for line in (text .. "\n"):gmatch("(.-)\n") do
		lines = lines + math.max(1, math.ceil(#line / perLine))
	end
	return lines * 12 + (lines - 1) * (self._spacing or 0)
end
function FontString:GetStringWidth()
	if MOCK.Measure then return (MOCK.Measure(self._font, self._text or "", 0, 0)) end
	return #MOCK.Plain(self._text) * 5.5
end

---------------------------------------------------------------- frames
local SCRIPTS = {
	OnEvent = 1, OnShow = 1, OnHide = 1, OnEnter = 1, OnLeave = 1, OnSizeChanged = 1, OnUpdate = 1, OnClick = 1,
	OnMouseUp = 1, OnMouseDown = 1, OnDragStart = 1, OnDragStop = 1, OnMouseWheel = 1, OnVerticalScroll = 1,
	OnScrollRangeChanged = 1, OnValueChanged = 1,
	OnTextChanged = 1, OnEditFocusGained = 1, OnEditFocusLost = 1, OnEscapePressed = 1, OnEnterPressed = 1,
}
local Frame = class(Region)
function Frame:SetScript(name, fn)
	assert(SCRIPTS[name], "no script " .. tostring(name))
	assert(fn == nil or type(fn) == "function")
	if name == "OnClick" then assert(self._kind == "Button" or self._kind == "CheckButton", "only buttons have OnClick") end
	if name:find("^OnText") or name:find("Focus") or name:find("Pressed$") then assert(self._kind == "EditBox", name .. " is an edit box script") end
	self._scripts = self._scripts or {}
	self._scripts[name] = fn
end
function Frame:GetScript(name) return self._scripts and self._scripts[name] end
function Frame:HookScript(name, fn)
	assert(SCRIPTS[name], "no script " .. tostring(name))
	assert(type(fn) == "function", "HookScript needs a function")
	self._hooks = self._hooks or {}
	self._hooks[name] = self._hooks[name] or {}
	table.insert(self._hooks[name], fn)
end
function Frame:_Fire(name, ...)
	local handler = self._scripts and self._scripts[name]
	if handler then handler(self, ...) end
	for _, fn in ipairs(self._hooks and self._hooks[name] or {}) do fn(self, ...) end
end
function Frame:RegisterEvent(e)
	if not KNOWN_EVENTS[e] then error('Frame:RegisterEvent(): Attempt to register unknown event "' .. tostring(e) .. '"') end
	MOCK.events[e] = MOCK.events[e] or {}
	MOCK.events[e][self] = true
end
function Frame:UnregisterEvent(e) if MOCK.events[e] then MOCK.events[e][self] = nil end end
function Frame:CreateTexture(name, layer)
	assert(name == nil, "named textures aren't mocked")
	assert(({ BACKGROUND = 1, BORDER = 1, ARTWORK = 1, OVERLAY = 1, HIGHLIGHT = 1 })[layer], "bad layer " .. tostring(layer))
	local t = setmetatable({ _parent = self, _shown = true, _kind = "Texture", _layer = layer }, Texture)
	self._textures = self._textures or {}
	table.insert(self._textures, t)
	return t
end
local FONTS = { GameFontNormal = 1, GameFontNormalSmall = 1, GameFontNormalLarge = 1, GameFontHighlight = 1,
	GameFontHighlightSmall = 1, GameFontDisable = 1, GameFontDisableSmall = 1, GameFontNormalLeft = 1, GameFontNormalMed3 = 1 }
MOCK.FONTS = FONTS
function Frame:CreateFontString(name, layer, template)
	assert(name == nil, "named font strings aren't mocked")
	assert(({ BACKGROUND = 1, BORDER = 1, ARTWORK = 1, OVERLAY = 1 })[layer], "bad layer " .. tostring(layer))
	assert(FONTS[template], "unknown font template " .. tostring(template))
	local fs = setmetatable({ _parent = self, _shown = true, _kind = "FontString", _text = "", _font = template }, FontString)
	self._fontstrings = self._fontstrings or {}
	table.insert(self._fontstrings, fs)
	return fs
end
function Frame:SetToplevel(on) self._toplevel = on end
function Frame:SetFrameStrata(s) assert(({ BACKGROUND = 1, LOW = 1, MEDIUM = 1, HIGH = 1, DIALOG = 1, FULLSCREEN = 1, TOOLTIP = 1 })[s]); self._strata = s end
function Frame:SetFrameLevel(l) assert(finite(l)); self._level = l end
function Frame:GetFrameLevel() return self._level or 1 end
function Frame:SetClampedToScreen(v) assert(type(v) == "boolean") end
function Frame:SetMovable(v) assert(type(v) == "boolean"); self._movable = v end
function Frame:EnableMouse(v) assert(type(v) == "boolean") end
function Frame:RegisterForDrag(...) end
function Frame:StartMoving() assert(self._movable, "StartMoving on a frame that isn't movable") end
function Frame:StopMovingOrSizing() self._sizing = nil end
function Frame:SetResizable(v) assert(type(v) == "boolean"); self._resizable = v end
function Frame:SetResizeBounds(minW, minH, maxW, maxH)
	assert(finite(minW) and finite(minH) and finite(maxW) and finite(maxH) and minW <= maxW and minH <= maxH)
	self._bounds = { minW, minH, maxW, maxH }
end
function Frame:StartSizing(point)
	assert(self._resizable, "StartSizing on a frame that isn't resizable")
	assert(POINTS[point], "bad sizing point")
	self._sizing = point
end
function Frame:SetUserPlaced(v) assert(type(v) == "boolean"); self._userPlaced = v end
function Frame:SetScale(s) assert(finite(s) and s > 0, "bad scale"); self._scale = s end
function Frame:GetScale() return self._scale or 1 end
function Frame:GetEffectiveScale()
	local scale, f = (MOCK.uiScale or 1), self
	while f do
		scale = scale * (f._scale or 1)
		f = f._parent
	end
	return scale
end
function Frame:IsProtected() return false, false end
function Frame:IsMouseOver() return false end
-- BackdropTemplate
local function RequireBackdrop(self) assert(self._templates and self._templates.BackdropTemplate, "SetBackdrop without BackdropTemplate") end
function Frame:SetBackdrop(b) RequireBackdrop(self); assert(type(b) == "table"); self._backdrop = b end
function Frame:SetBackdropColor(r, g, b, a) RequireBackdrop(self); for _, v in ipairs({ r, g, b, a or 1 }) do assert(finite(v) and v >= 0 and v <= 1) end; self._bg = { r, g, b, a or 1 } end
function Frame:SetBackdropBorderColor(r, g, b, a) RequireBackdrop(self); for _, v in ipairs({ r, g, b, a or 1 }) do assert(finite(v) and v >= 0 and v <= 1) end; self._border = { r, g, b, a or 1 } end

local Button = class(Frame)
function Button:RegisterForClicks(...) end
-- A button's state textures are regions of their own, filling the button
local function StateTexture(self, key, layer, file)
	assert(type(file) == "string", "state textures here are files")
	local t = self[key]
	if not t then
		t = self:CreateTexture(nil, layer)
		t:SetAllPoints()
		self[key] = t
	end
	t:SetTexture(file)
	return t
end
function Button:SetNormalTexture(file) self._normal = StateTexture(self, "_normalTexture", "ARTWORK", file) end
function Button:SetHighlightTexture(file) self._highlight = StateTexture(self, "_highlightTexture", "HIGHLIGHT", file) end
function Button:SetPushedTexture(file)
	self._pushed = StateTexture(self, "_pushedTexture", "ARTWORK", file)
	self._pushed:Hide()
end
function Button:Click(button) self:_Fire("OnClick", button or "LeftButton", false) end
function Button:SetText(text)
	assert(text == nil or type(text) == "string", "Button:SetText wants a string")
	if not self._fontString then
		self._fontString = self:CreateFontString(nil, "OVERLAY", self._normalFont or "GameFontNormal")
		self._fontString:SetPoint("CENTER")
	end
	self._fontString:SetText(text)
end
function Button:GetText() return self._fontString and self._fontString:GetText() end
function Button:GetFontString() return self._fontString end
local function FontObject(font)
	assert(type(font) == "string" and FONTS[font] or (type(font) == "table" and font._fontName), "unknown font object " .. tostring(font))
	return type(font) == "table" and font._fontName or font
end
function Button:SetNormalFontObject(font) self._normalFont = FontObject(font); if self._fontString then self._fontString._font = self._normalFont end end
function Button:SetHighlightFontObject(font) self._highlightFont = FontObject(font) end
function Button:SetDisabledFontObject(font) self._disabledFont = FontObject(font) end
function Button:LockHighlight() self._highlightLocked = true end
function Button:UnlockHighlight() self._highlightLocked = false end
function Button:IsEnabled() return self._disabled ~= true end
function Button:SetEnabled(on) self._disabled = not on end
function Button:Enable() self._disabled = false end
function Button:Disable() self._disabled = true end

local StatusBar = class(Frame)
function StatusBar:SetStatusBarTexture(t) self._tex = t end
function StatusBar:SetStatusBarColor(r, g, b, a) for _, v in ipairs({ r, g, b, a or 1 }) do assert(finite(v) and v >= 0 and v <= 1) end; self._barColor = { r, g, b, a or 1 } end
function StatusBar:SetMinMaxValues(lo, hi) assert(finite(lo) and finite(hi) and lo <= hi, "bad min/max"); self._min, self._max = lo, hi end
function StatusBar:SetValue(v)
	assert(finite(v), "bad value")
	assert(self._min and v >= self._min - 1e-9 and v <= self._max + 1e-9, "StatusBar value outside its range: " .. v)
	self._value = v
end
function StatusBar:GetValue() return self._value end

local ScrollFrame = class(Frame)
function ScrollFrame:SetScrollChild(f) self._child = f end
function ScrollFrame:GetScrollChild() return self._child end
function ScrollFrame:UpdateScrollChildRect() end
function ScrollFrame:GetVerticalScrollRange()
	local h = MOCK.RegionHeight and MOCK.RegionHeight(self) or self:GetHeight()
	return math.max(0, (self._child and self._child:GetHeight() or 0) - h)
end
function ScrollFrame:GetVerticalScroll() return self._scroll or 0 end
function ScrollFrame:SetVerticalScroll(v)
	assert(finite(v) and v >= 0, "bad scroll offset")
	self._scroll = v
	self:_Fire("OnVerticalScroll", v)
end


-- EditBox: text, focus, and the scripts a typed character runs
local EditBox = class(Frame)
function EditBox:SetText(t) assert(type(t) == "string", "EditBox:SetText wants a string"); self._text = t; self:_Fire("OnTextChanged", false) end
function EditBox:GetText() return self._text or "" end
function EditBox:SetAutoFocus(v) assert(type(v) == "boolean") end
function EditBox:HasFocus() return self._focus == true end
function EditBox:SetFocus() self._focus = true end
function EditBox:ClearFocus() self._focus = false end
function EditBox:SetTextInsets() end
function EditBox:SetMaxLetters(n) assert(finite(n)) end
-- what typing does: the text changes as the player's input
function EditBox:MockType(t) self._text = t; self:_Fire("OnTextChanged", true) end

-- CheckButton: a click flips it before OnClick runs, as in the game
local CheckButton = class(Button)
function CheckButton:SetChecked(v) assert(v == nil or type(v) == "boolean", "SetChecked wants a boolean"); self._checked = v and true or false end
function CheckButton:GetChecked() return self._checked == true end
function CheckButton:Click(button)
	self._checked = not self._checked
	self:_Fire("OnClick", button or "LeftButton", false)
end
MOCK.frames = {}
local DropdownButton = class(Button)
local KINDS = { Frame = Frame, Button = Button, StatusBar = StatusBar, ScrollFrame = ScrollFrame, DropdownButton = DropdownButton,
	EditBox = EditBox, CheckButton = CheckButton }
-- Blizzard templates, from templates.lua: [name] = { kinds = { Frame = true, ... }, build = function(frame) }
MOCK.TEMPLATES = {}
function CreateFrame(kind, name, parent, template)
	local mt = KINDS[kind]
	assert(mt, "CreateFrame kind " .. tostring(kind))
	assert(parent == nil or (type(parent) == "table" and parent._kind), "CreateFrame parent isn't a frame")
	if type(name) == "string" and name:find("^%$parent") then name = (parent and parent._name or "") .. name:sub(8) end
	local f = setmetatable({ _parent = parent, _shown = true, _name = name, _kind = kind }, mt)
	if name then _G[name] = f end
	table.insert(MOCK.frames, f)
	if template then
		f._templates = {}
		for t in template:gmatch("[^,%s]+") do
			local spec = MOCK.TEMPLATES[t]
			assert(spec, "template " .. t .. " isn't mocked (or doesn't exist)")
			assert(not spec.kinds or spec.kinds[kind], t .. " isn't a template for a " .. kind)
			f._templates[t] = true
			if spec.build then spec.build(f, name) end
		end
	end
	return f
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)

-- The minimap, as Blizzard_Minimap builds it on Forever: a 198 x 198 round map near the top right.
-- GetCenter and GetCursorPosition are in screen units; the cursor's are scaled by the UI scale.
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetSize(198, 198)
MOCK.minimapCenter = { 1800, 950 }
MOCK.uiScale = 1
MOCK.cursor = { 0, 0 }
function Minimap:GetCenter() return MOCK.minimapCenter[1], MOCK.minimapCenter[2] end
function GetCursorPosition() return MOCK.cursor[1] * MOCK.uiScale, MOCK.cursor[2] * MOCK.uiScale end
UISpecialFrames = {}
function tinsert(t, v) table.insert(t, v) end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function hooksecurefunc(obj, name, fn)
	if type(obj) == "string" then obj, name, fn = _G, obj, name end
	local orig = obj[name]
	assert(type(orig) == "function", "hooksecurefunc: " .. tostring(name) .. " isn't a function")
	obj[name] = function(...)
		local r = { orig(...) }
		fn(...)
		return unpack(r)
	end
end

---------------------------------------------------------------- tooltip
local Tooltip = class(Region)
GameTooltip = setmetatable({ _kind = "GameTooltip", _shown = false, _lines = {}, _colors = {} }, Tooltip)
function Tooltip:SetOwner(owner, anchor)
	assert(owner and owner._kind, "SetOwner needs a frame")
	assert(({ ANCHOR_RIGHT = 1, ANCHOR_LEFT = 1, ANCHOR_TOP = 1, ANCHOR_BOTTOM = 1, ANCHOR_CURSOR = 1, ANCHOR_NONE = 1 })[anchor], "bad anchor " .. tostring(anchor))
	self._owner, self._anchor, self._lines, self._colors, self._rows, self._shown = owner, anchor, {}, {}, {}, false
end
local function colorOK(...) for _, v in ipairs({ ... }) do assert(finite(v) and v >= 0 and v <= 1, "tooltip colour out of range: " .. tostring(v)) end end
function Tooltip:SetText(text, r, g, b)
	assert(type(text) == "string", "SetText needs a string")
	colorOK(r or 1, g or 1, b or 1)
	self._lines, self._colors = { text }, { { r or 1, g or 1, b or 1 } }
	self._rows = { { left = text, lc = { r or 1, g or 1, b or 1 } } }
end
function Tooltip:AddLine(text, r, g, b, wrap)
	assert(type(text) == "string", "AddLine needs a string, got " .. type(text))
	colorOK(r or 1, g or 1, b or 1)
	assert(wrap == nil or type(wrap) == "boolean")
	table.insert(self._lines, text)
	table.insert(self._colors, { r or 1, g or 1, b or 1 })
	table.insert(self._rows, { left = text, lc = { r or 1, g or 1, b or 1 }, wrap = wrap })
end
function Tooltip:AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)
	assert(type(l) == "string" and type(r) == "string", "AddDoubleLine needs two strings")
	colorOK(lr or 1, lg or 1, lb or 1, rr or 1, rg or 1, rb or 1)
	table.insert(self._lines, l .. " || " .. r)
	table.insert(self._colors, { lr or 1, lg or 1, lb or 1, rr or 1, rg or 1, rb or 1 })
	table.insert(self._rows, { left = l, right = r, lc = { lr or 1, lg or 1, lb or 1 }, rc = { rr or 1, rg or 1, rb or 1 } })
end
function Tooltip:NumLines() return #self._lines end
function MOCK.TooltipText() return MOCK.Plain(table.concat(GameTooltip._lines, "\n")) end

---------------------------------------------------------------- Blizzard globals
-- WoW: Forever's FACTION_RED/ORANGE/YELLOW/GREEN_COLOR
local RED, ORANGE, YELLOW, GREEN = { r = 0.8, g = 0.3, b = 0.22 }, { r = 0.75, g = 0.27, b = 0 }, { r = 0.9, g = 0.7, b = 0 }, { r = 0, g = 0.6, b = 0.1 }
FACTION_BAR_COLORS = { RED, RED, ORANGE, YELLOW, GREEN, GREEN, GREEN, GREEN }
local LABELS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
for i, l in ipairs(LABELS) do _G["FACTION_STANDING_LABEL" .. i] = l end
function GetText(key, gender)
	assert(not issecretvalue(gender), "GetText with a secret gender")
	return _G[key]
end
UNKNOWN = "Unknown"
function BreakUpLargeNumbers(n)
	assert(type(n) == "number" and n % 1 == 0, "BreakUpLargeNumbers wants a whole number, got " .. tostring(n))
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (n < 0 and "-" or "") .. out
end
function GetTime() return MOCK.now end
function time() return MOCK.epoch + MOCK.now end
bit = {
	band = function(a, b) local r, m = 0, 1; while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + m end; a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2 end; return r end,
	lshift = function(a, n) return a * 2 ^ n end,
}

function UnitFactionGroup(u) assert(u == "player"); return MOCK.side, MOCK.side end
function UnitClass(u) assert(u == "player"); if MOCK.secretIdentity then return MOCK.Secret(), MOCK.Secret(), MOCK.Secret() end; return "Mage", "MAGE", MOCK.classID end
function UnitRace(u) assert(u == "player"); if MOCK.secretIdentity then return MOCK.Secret(), MOCK.Secret(), MOCK.Secret() end; return "Human", "Human", MOCK.raceID end
function UnitSex(u) assert(u == "player"); if MOCK.secretIdentity then return MOCK.Secret() end; return MOCK.sex end
function UnitIsDeadOrGhost(u) assert(u == "player"); return MOCK.dead end
function UnitLevel(u) assert(u == "player"); return MOCK.level end
function SetCursor(cursor) assert(cursor == nil or type(cursor) == "string"); MOCK.cursor = cursor end
SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 839, IG_CHARACTER_INFO_CLOSE = 840, IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
	IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
function PlaySound(id)
	local known = false
	for _, v in pairs(SOUNDKIT) do if v == id then known = true end end
	assert(known, "PlaySound wants a SOUNDKIT id")
	table.insert(MOCK.sounds, id)
end
function IsInInstance()
	if MOCK.instance then return true, MOCK.instance.kind end
	return false, "none"
end
function GetInstanceInfo()
	local i = MOCK.instance
	if i then return i.name, i.kind, 1, "Normal", 5, 0, false, i.mapID, 5, nil end
	return MOCK.zoneName, "none", 0, "", 0, 0, false, 0, 0, nil
end

C_Map = {
	GetBestMapForUnit = function(u) assert(u == "player"); return 1429 end,
	GetMapInfo = function(id) assert(type(id) == "number"); return { mapID = id, name = MOCK.zoneName, mapType = 3 } end,
	GetAreaInfo = function(id) assert(type(id) == "number"); return nil end,
}

C_Item = {
	GetItemCount = function(id, bank)
		assert(type(id) == "number", "GetItemCount wants an item ID")
		assert(bank == true, "counts should include the bank")
		return MOCK.items[id] or 0
	end,
	GetItemNameByID = function(id) assert(type(id) == "number"); return nil end,
}

C_QuestLog = {
	GetNumQuestLogEntries = function() return #MOCK.quests, #MOCK.quests end,
	GetInfo = function(i)
		local q = MOCK.quests[i]
		if not q then return nil end
		return { title = "q", questLogIndex = i, questID = q.isHeader and 0 or q[1], isHeader = q.isHeader == true, isHidden = false,
			isTask = false, level = 60 }
	end,
	IsComplete = function(id)
		assert(type(id) == "number" and id > 0)
		for _, q in ipairs(MOCK.quests) do if q[1] == id then return q[2] == true end end
		return false
	end,
	IsQuestFlaggedCompleted = function(id) assert(type(id) == "number"); return MOCK.done[id] == true end,
}

local function FactionData(id)
	local f = MOCK.factions[id]
	if not f then return nil end
	local value = f.value
	local reaction = 1
	local starts = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000 }
	for r = 8, 1, -1 do if value >= starts[r] then reaction = r; break end end
	local nextT = reaction < 8 and starts[reaction + 1] or 43000
	return { factionID = id, name = f.name, description = "", reaction = reaction, currentReactionThreshold = starts[reaction],
		nextReactionThreshold = nextT, currentStanding = value, atWarWith = false, canToggleAtWar = true, isChild = false,
		isHeader = f.isHeader == true, isHeaderWithRep = f.isHeaderWithRep == true, isCollapsed = false,
		isWatched = MOCK.watched == id, hasBonusRepGain = false, canSetInactive = true, isAccountWide = false }
end
MOCK.FactionData = FactionData
C_Reputation = {
	GetFactionDataByID = function(id) assert(type(id) == "number", "GetFactionDataByID wants a number"); return FactionData(id) end,
	GetFactionDataByIndex = function(i) assert(type(i) == "number"); local id = MOCK.order[i]; return id and FactionData(id) end,
	GetNumFactions = function() return #MOCK.order end,
	GetSelectedFaction = function() return MOCK.selected end,
	SetSelectedFaction = function(i) MOCK.selected = i end,
	GetWatchedFactionData = function() return MOCK.watched and FactionData(MOCK.watched) or nil end,
}

---------------------------------------------------------------- event registry, scroll box
EventRegistry = { _cb = {} }
function EventRegistry:RegisterCallback(event, fn, owner)
	assert(type(event) == "string" and type(fn) == "function" and owner ~= nil)
	self._cb[event] = self._cb[event] or {}
	self._cb[event][owner] = fn
end
function EventRegistry:TriggerEvent(event, ...)
	for owner, fn in pairs(self._cb[event] or {}) do fn(owner, ...) end
end

local ScrollBox = class(Frame)
function ScrollBox:ForEachFrame(fn) for _, fr in ipairs(self._frames) do if fn(fr, fr.elementData) then return end end end
function ScrollBox:RegisterCallback(event, fn, owner)
	assert(event == "OnAcquiredFrame" or event == "OnInitializedFrame")
	assert(owner ~= nil, "callbacks need an owner")
	self._cbs = self._cbs or {}
	self._cbs[event] = { fn = fn, owner = owner }
end
ScrollBoxListMixin = { Event = { OnAcquiredFrame = "OnAcquiredFrame", OnInitializedFrame = "OnInitializedFrame" } }
ScrollUtil = {
	AddAcquiredFrameCallback = function(scrollBox, callback, owner, iterateExisting)
		-- like Blizzard's: existing frames get (frame, elementData), new ones (owner, frame, elementData, new)
		if iterateExisting then scrollBox:ForEachFrame(callback) end
		scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, function(o, fr, data, new) callback(o, fr, data, new) end, owner)
	end,
}

---------------------------------------------------------------- the character window
function MOCK.BuildCharacterFrame()
	CharacterFrame = CreateFrame("Frame", "CharacterFrame", UIParent)
	CharacterFrame:SetSize(631, 484)
	CharacterFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	CharacterFrame:Hide()
	CharacterFrame.rightPaneCollapsed = false
	function CharacterFrame:SetRightPaneCollapsed(collapsed)
		self.rightPaneCollapsed = collapsed
		self:SetWidth(collapsed and 398 or 631)
	end
	CharacterFrameLeftPaneHost = CreateFrame("Frame", "CharacterFrameLeftPaneHost", CharacterFrame)
	CharacterFrameLeftPaneHost:SetSize(398, 464)
	CharacterFrameLeftPaneHost:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, -20)
	local tabs = CreateFrame("Frame", "CharacterFrameModeTabs", CharacterFrame)
	tabs:SetSize(64, 384)
	tabs:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 0, -30)
	-- Camelot's side tabs: SidePanelTabButtonMixin sizes them from the common-sidetab art
	for i = 1, 6 do
		local tab = CreateFrame("Frame", "CharacterFrameModeTab" .. i, tabs)
		tab:SetSize(55, 55)
		tab:SetPoint("TOPLEFT", tabs, "TOPLEFT", 0, -(i - 1) * 57)
	end
	ReputationFrame = CreateFrame("Frame", "ReputationFrame", CharacterFrame)
	ReputationFrame:SetAllPoints(CharacterFrame)
	ReputationFrame:Hide()
	ReputationFrame.ScrollBox = setmetatable({ _parent = ReputationFrame, _shown = true, _kind = "Frame", _frames = {} }, ScrollBox)
	for _ = 1, 6 do MOCK.NewReputationRow() end
end

-- A row the way ReputationEntryTemplate builds it: its own OnEnter only changes the bar text
function MOCK.NewReputationRow()
	local row = CreateFrame("Button", nil, ReputationFrame.ScrollBox)
	row:SetScript("OnEnter", function() end)
	row:SetScript("OnLeave", function() end)
	row:SetScript("OnClick", function(self)
		C_Reputation.SetSelectedFaction(self.factionIndex or 0)
		EventRegistry:TriggerEvent("ReputationFrame.NewFactionSelected")
	end)
	table.insert(ReputationFrame.ScrollBox._frames, row)
	return row
end

-- What ReputationFrameMixin:Update does to the rows it shows
function MOCK.FillReputationRows()
	-- the scroll box acquires more rows when there are more factions to show
	local box = ReputationFrame.ScrollBox
	local cb = box._cbs and box._cbs.OnAcquiredFrame
	while #box._frames < math.min(#MOCK.order, 20) do
		local row = MOCK.NewReputationRow()
		if cb then cb.fn(cb.owner, row, nil, true) end
	end
	for i, row in ipairs(box._frames) do
		local id = MOCK.order[i]
		if id then
			row.factionIndex, row.factionID, row.elementData = i, id, FactionData(id)
			row.elementData.factionIndex = i
		else
			row.factionIndex, row.factionID, row.elementData = nil, nil, nil
		end
	end
end

-- Opens the character window on the Reputation tab the way ToggleCharacter does
function MOCK.OpenReputation()
	MOCK.FillReputationRows()
	CharacterFrame:Show()
	if MOCK.selected == 0 then
		for i, id in ipairs(MOCK.order) do
			if not MOCK.factions[id].isHeader then MOCK.selected = i; break end
		end
	end
	ReputationFrame:Show()
	EventRegistry:TriggerEvent("ReputationFrame.NewFactionSelected")
end
function MOCK.CloseCharacter()
	ReputationFrame:Hide()
	CharacterFrame:Hide()
	MOCK.selected = 0
end

---------------------------------------------------------------- status bars
StatusTrackingBarInfo = { BarsEnum = { None = -1, Reputation = 1, Honor = 2, Artifact = 3, Experience = 4, Azerite = 5, HouseFavor = 6 } }
function MOCK.BuildStatusBars()
	StatusTrackingBarManager = CreateFrame("Frame", "StatusTrackingBarManager", UIParent)
	StatusTrackingBarManager.barContainers = {}
	for i = 1, 2 do
		local c = CreateFrame("Frame", nil, StatusTrackingBarManager)
		c.bars = {}
		for key, index in pairs(StatusTrackingBarInfo.BarsEnum) do
			if index > 0 then
				local bar = CreateFrame("Frame", nil, c)
				bar:SetScript("OnEnter", function() end)  -- ReputationStatusBarMixin:OnEnter shows the text
				bar:SetScript("OnLeave", function() end)
				c.bars[index] = bar
			end
		end
		StatusTrackingBarManager.barContainers[i] = c
	end
end
EditModeManagerFrame = { IsEditModeActive = function() return MOCK.editMode end }

---------------------------------------------------------------- chat, slash, events
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) assert(type(msg) == "string"); table.insert(MOCK.chat, MOCK.Plain(msg)) end }
function MOCK.Slash(text)
	local cmd, rest = text:match("^(%S+)%s*(.-)$")
	for key, fn in pairs(SlashCmdList) do
		for i = 1, 9 do
			if _G["SLASH_" .. key .. i] == cmd then return fn(rest) end
		end
	end
	error("no slash command " .. cmd)
end
function MOCK.Fire(event, ...)
	for f in pairs(MOCK.events[event] or {}) do f:GetScript("OnEvent")(f, event, ...) end
end
function MOCK.Hover(frame) frame:_Fire("OnEnter", false) end
function MOCK.Leave(frame) frame:_Fire("OnLeave", false) end
function MOCK.Advance(s) MOCK.now = MOCK.now + s end

-- Changes a faction's rep and fires what the client fires
function MOCK.Gain(id, amount)
	MOCK.factions[id].value = math.min(42999, MOCK.factions[id].value + amount)
	MOCK.Fire("UPDATE_FACTION")
end

assert(loadfile(DIR .. "/test/templates.lua"))(DIR)
