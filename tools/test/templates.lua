-- Mocks of the Blizzard templates Rep Planner builds its window from, made the way WoW: Forever
-- 1.60.1 defines them (Blizzard_SharedXML's Mainline and Camelot files, Blizzard_Menu): the same
-- children, art and anchors, so preview.py can draw them, the methods the planner calls, and Mock*
-- helpers for the tests. Loaded by wowmock.lua; CreateFrame refuses any template that isn't here.
local T = MOCK.TEMPLATES

local function Kinds(...)
	local k = {}
	for _, v in ipairs({ ... }) do k[v] = true end
	return k
end

local function Atlas(parent, layer, atlas, useAtlasSize)
	local t = parent:CreateTexture(nil, layer)
	t:SetAtlas(atlas, useAtlasSize)
	return t
end

T.BackdropTemplate = { kinds = Kinds("Frame", "Button", "StatusBar", "ScrollFrame") }

-- The old scroll frame with arrow buttons (Rep Planner 1.1 used it)
T.UIPanelScrollFrameTemplate = { kinds = Kinds("ScrollFrame"), build = function(f, name)
	assert(name, "UIPanelScrollFrameTemplate needs a name for its $parentScrollBar")
	f.ScrollBar = CreateFrame("Frame", nil, f)
end }

-- UIPanelCloseButton: the red X. It runs the window's onCloseCallback, then hides the window
-- (HideUIPanel is a plain Hide for a window the game doesn't manage).
local function CloseButton(b)
	b:SetSize(24, 24)
	b:SetFrameLevel(510)
	b.Normal = Atlas(b, "ARTWORK", "RedButton-Exit")
	b.Normal:SetAllPoints()
	b.Highlight = Atlas(b, "HIGHLIGHT", "RedButton-Highlight")
	b.Highlight:SetAllPoints()
	b.Highlight:SetBlendMode("ADD")
	b:SetScript("OnClick", function(self)
		local window = self:GetParent()
		if window.onCloseCallback and not window.onCloseCallback(self) then return end
		window:Hide()
	end)
end
T.UIPanelCloseButton = { kinds = Kinds("Button"), build = CloseButton }
-- Camelot's UIPanelCloseButtonDefaultAnchorsMixin:OnLoad puts it at TOPRIGHT -2, 1
T.UIPanelCloseButtonDefaultAnchors = { kinds = Kinds("Button"), build = function(b)
	CloseButton(b)
	b:SetPoint("TOPRIGHT", -2, 1)
end }

-- PortraitFrameTemplate: the metal border (a NineSlice of layout "PortraitFrameTemplate"), the rock
-- background and its top streaks, the round portrait, the title and the close button
T.PortraitFrameTemplate = { kinds = Kinds("Frame"), build = function(f, name)
	f:SetSize(338, 424)
	f.NineSlice = CreateFrame("Frame", nil, f)
	f.NineSlice:SetAllPoints(f)
	f.NineSlice:SetFrameLevel(500)
	f.NineSlice.layoutType = "PortraitFrameTemplate"
	f.PortraitContainer = CreateFrame("Frame", nil, f)
	f.PortraitContainer:SetSize(1, 1)
	f.PortraitContainer:SetPoint("TOPLEFT")
	f.PortraitContainer:SetFrameLevel(400)
	local portrait = f.PortraitContainer:CreateTexture(nil, "OVERLAY")
	portrait:SetSize(62, 62)
	portrait:SetPoint("TOPLEFT", -5, 7)
	portrait._circleMask = true   -- TempPortraitAlphaMask
	f.PortraitContainer.portrait = portrait
	f.TitleContainer = CreateFrame("Frame", nil, f)
	f.TitleContainer:SetHeight(20)
	f.TitleContainer:SetPoint("TOPLEFT", 58, -1)
	f.TitleContainer:SetPoint("TOPRIGHT", -24, -1)
	f.TitleContainer:SetFrameLevel(510)
	local title = f.TitleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -5)
	title:SetPoint("LEFT")
	title:SetPoint("RIGHT")
	title:SetWordWrap(false)
	f.TitleContainer.TitleText = title
	f.Bg = f:CreateTexture(nil, "BACKGROUND")
	f.Bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock")
	f.Bg:SetHorizTile(true)
	f.Bg:SetVertTile(true)
	f.Bg:SetPoint("TOPLEFT", 2, -21)
	f.Bg:SetPoint("BOTTOMRIGHT", -2, 2)
	f.TopTileStreaks = Atlas(f, "BORDER", "_UI-Frame-TopTileStreaks", true)
	f.TopTileStreaks:SetPoint("TOPLEFT", 6, -21)
	f.TopTileStreaks:SetPoint("TOPRIGHT", -2, -21)
	f.CloseButton = CreateFrame("Button", name and "$parentCloseButton" or nil, f, "UIPanelCloseButtonDefaultAnchors")
	function f:GetTitleText() return self.TitleContainer.TitleText end
	function f:SetTitle(text) self.TitleContainer.TitleText:SetText(text) end
	function f:SetTitleColor(c) self.TitleContainer.TitleText:SetTextColor(c.r, c.g, c.b) end
	function f:GetPortrait() return self.PortraitContainer.portrait end
	function f:SetPortraitToAsset(texture) return self.PortraitContainer.portrait:SetTexture(texture) end
end }

-- ScrollFrameTemplate: ScrollFrame_OnLoad adds a MinimalScrollBar just right of the frame
-- (ScrollDefine.lua: 6 to the right, 2 above the top, 5 above the bottom)
T.ScrollFrameTemplate = { kinds = Kinds("ScrollFrame"), build = function(sf)
	local bar = CreateFrame("Frame", nil, sf)
	bar:SetWidth(8)
	bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 6, 2)
	bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 6, 5)
	bar.Back = CreateFrame("Button", nil, bar)
	bar.Back:SetSize(17, 11)
	bar.Back:SetPoint("TOP")
	bar.Back.Texture = Atlas(bar.Back, "BACKGROUND", "minimal-scrollbar-arrow-top")
	bar.Back.Texture:SetAllPoints()
	bar.Forward = CreateFrame("Button", nil, bar)
	bar.Forward:SetSize(17, 11)
	bar.Forward:SetPoint("BOTTOM")
	bar.Forward.Texture = Atlas(bar.Forward, "BACKGROUND", "minimal-scrollbar-arrow-bottom")
	bar.Forward.Texture:SetAllPoints()
	local track = CreateFrame("Frame", nil, bar)
	track:SetWidth(8)
	track:SetPoint("TOP", 0, -19)
	track:SetPoint("BOTTOM", 0, 19)
	track.Begin = Atlas(track, "ARTWORK", "minimal-scrollbar-track-top", true)
	track.Begin:SetPoint("TOPLEFT")
	track.End = Atlas(track, "ARTWORK", "minimal-scrollbar-track-bottom", true)
	track.End:SetPoint("BOTTOMLEFT")
	track.Middle = Atlas(track, "ARTWORK", "!minimal-scrollbar-track-middle", true)
	track.Middle:SetPoint("TOPLEFT", track.Begin, "BOTTOMLEFT")
	track.Middle:SetPoint("BOTTOMRIGHT", track.End, "TOPRIGHT")
	-- where the thumb sits depends on the scroll, so preview.py places it
	track.Thumb = CreateFrame("Button", nil, track)
	track.Thumb._thumbOf = sf
	bar.Track = track
	function bar:SetHideIfUnscrollable(hide) assert(type(hide) == "boolean"); self.hideIfUnscrollable = hide end
	function bar:SetHideTrackIfThumbExceedsTrack(hide) self.hideTrack = hide end
	sf.ScrollBar = bar
	sf:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 30)))
	end)
end }

-- The Reputation tab's gold-trimmed button (a ThreeSliceButton; its ends scale to its height)
T.SharedGoldRedButtonSmallTemplate = { kinds = Kinds("Button"), build = function(b)
	b.Left = Atlas(b, "BACKGROUND", "128-GoldRedButton-Left", true)
	b.Left:SetPoint("TOPLEFT")
	b.Right = Atlas(b, "BACKGROUND", "128-GoldRedButton-Right", true)
	b.Right:SetPoint("TOPRIGHT")
	b.Center = Atlas(b, "BACKGROUND", "_128-GoldRedButton-Center")
	b.Center:SetPoint("TOPLEFT", b.Left, "TOPRIGHT")
	b.Center:SetPoint("BOTTOMRIGHT", b.Right, "BOTTOMLEFT")
	b.Highlight = Atlas(b, "HIGHLIGHT", "128-GoldRedButton-Highlight")
	b.Highlight:SetAllPoints()
	b.Highlight:SetBlendMode("ADD")
	-- ThreeSliceButtonMixin:UpdateScale
	b:HookScript("OnSizeChanged", function(self)
		local h = self:GetHeight()
		if h <= 0 then return end
		local scale = h / 128
		self.Left:SetSize(114 * scale, h)
		self.Right:SetSize(math.min(292 * scale, math.max(0, self:GetWidth() - 114 * scale)), h)
	end)
	b:SetNormalFontObject("GameFontNormal")
	b:SetHighlightFontObject("GameFontHighlight")
	b:SetDisabledFontObject("GameFontDisable")
	b:SetSize(138, 28)
end }

-- The standing bar: Camelot's ColoredProgressBarTemplate (the Reputation tab's bars inherit it)
T.ColoredProgressBarTemplate = { kinds = Kinds("Frame"), build = function(bar)
	bar:SetSize(67, 29)
	bar.BG = Atlas(bar, "BACKGROUND", "common-stat-bar-BG")
	bar.BG:SetAllPoints()
	bar.Fill = Atlas(bar, "BORDER", "common-stat-bar-white", true)
	bar.Fill:SetSize(0, 15)
	bar.Fill:SetPoint("LEFT")
	bar.Fill._mask = "common-stat-bar-Mask"
	bar.Text = bar:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	bar.Text:SetHeight(20)
	bar.Text:SetPoint("LEFT")
	bar.Text:SetPoint("RIGHT")
	bar.Text:SetJustifyH("CENTER")
	function bar:SetText(text) self.Text:SetText(text) end
	function bar:GetText() return self.Text:GetText() end
	function bar:SetFillPercent(percent)
		assert(type(percent) == "number" and percent == percent, "SetFillPercent wants a number")
		local p = math.min(1, math.max(0, percent))
		self.fillPercent = p
		self.Fill:SetWidth(p * self:GetWidth())
		self.Fill:SetTexCoord(0, p, 1, 0)
	end
	bar:SetFillPercent(0)
end }

---------------------------------------------------------------- Blizzard_Menu dropdowns
-- A menu description: what the generator adds, and what picking an entry does
local function NewMenuDescription()
	local root = { elements = {} }
	local function Add(e)
		table.insert(root.elements, e)
		return e
	end
	function root:CreateRadio(text, isSelected, setSelected, data)
		assert(type(text) == "string" and type(isSelected) == "function" and type(setSelected) == "function", "CreateRadio(text, isSelected, setSelected, data)")
		return Add({ kind = "radio", text = text, isSelected = isSelected, setSelected = setSelected, data = data })
	end
	function root:CreateButton(text, onClick, data) return Add({ kind = "button", text = text, onClick = onClick, data = data }) end
	function root:CreateTitle(text) return Add({ kind = "title", text = text }) end
	function root:CreateDivider() return Add({ kind = "divider" }) end
	return root
end
MOCK.NewMenuDescription = NewMenuDescription

-- WowStyle1DropdownTemplate: the text holder, the gold arrow, and the selection as its text
T.WowStyle1DropdownTemplate = { kinds = Kinds("DropdownButton"), build = function(d)
	d:SetSize(120, 25)
	d.Background = Atlas(d, "BACKGROUND", "common-dropdown-textholder", true)
	d.Background:SetPoint("TOPLEFT", -8, 7)
	d.Background:SetPoint("BOTTOMRIGHT", 8, -9)
	d.Arrow = Atlas(d, "OVERLAY", "common-dropdown-a-button", true)
	d.Arrow:SetPoint("RIGHT", d, "RIGHT", 1, -3)
	d.Text = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	d.Text:SetHeight(10)
	d.Text:SetPoint("TOPRIGHT", d.Arrow, "LEFT")
	d.Text:SetPoint("TOPLEFT", 8, -8)
	d.Text:SetJustifyH("LEFT")
	d.Text:SetWordWrap(false)
	function d:SetDefaultText(text) self.defaultText = text; self:GenerateMenu() end
	function d:SetSelectionTranslator(translator) self.translator = translator end
	function d:SetupMenu(generator)
		assert(type(generator) == "function", "SetupMenu wants a function")
		self.generator = generator
		self:GenerateMenu()
	end
	function d:GenerateMenu()
		if not self.generator then return end
		local root = NewMenuDescription()
		self.generator(self, root)
		self.menuDescription = root
		local texts = {}
		for _, e in ipairs(root.elements) do
			if e.kind == "radio" and e.isSelected(e.data) then texts[#texts + 1] = self.translator and self.translator(e) or e.text end
		end
		self.Text:SetText(#texts > 0 and table.concat(texts, ", ") or (self.defaultText or ""))
	end
	function d:OpenMenu() self:GenerateMenu(); self.menuOpen = true end
	function d:CloseMenu() self.menuOpen = false end
	function d:IsMenuOpen() return self.menuOpen == true end
	-- The menu's entries, as it would open now
	function d:MockOptions()
		self:OpenMenu()
		return self.menuDescription.elements
	end
	-- Picks the radio with this text or data, as a click does (the menu closes, the text updates)
	function d:MockPick(textOrData)
		for _, e in ipairs(self:MockOptions()) do
			if e.kind == "radio" and (MOCK.Plain(e.text) == textOrData or (e.data ~= nil and e.data == textOrData)) then
				-- the pick runs with the menu open; then the menu updates the text and closes
				e.setSelected(e.data)
				self:GenerateMenu()
				self.menuOpen = false
				return true
			end
		end
		error("no menu option " .. tostring(textOrData))
	end
end }

---------------------------------------------------------------- Blizzard_Settings
-- The vertical-layout part of the Settings API addons use (Blizzard_Settings_Shared in 1.60.1)
MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 } }
Settings = { VarType = { Boolean = "boolean", String = "string", Number = "number" }, Default = { True = true, False = false } }
MOCK.settings = { categories = {}, variables = {} }
function Settings.RegisterVerticalLayoutCategory(name)
	assert(type(name) == "string", "a category needs a name")
	local category = { name = name, controls = {}, id = 1000 + #MOCK.settings.categories }
	function category:GetID() return self.id end
	function category:GetName() return self.name end
	table.insert(MOCK.settings.categories, category)
	return category, {}
end
function Settings.RegisterProxySetting(category, variable, varType, name, default, getValue, setValue)
	assert(type(category) == "table" and category.controls, "RegisterProxySetting(category, ...)")
	assert(type(variable) == "string" and not MOCK.settings.variables[variable], "setting variables are unique strings")
	assert(Settings.VarType[varType == "boolean" and "Boolean" or (varType == "number" and "Number" or "String")] == varType, "bad variable type")
	assert(type(name) == "string" and type(default) == varType, "a setting needs a name and a default of its type")
	assert(type(getValue) == "function" and type(setValue) == "function", "proxy settings need a getter and a setter")
	local setting = { variable = variable, varType = varType, name = name, default = default, get = getValue, set = setValue }
	function setting:GetValue() return self.get() end
	function setting:SetValue(value)
		assert(type(value) == self.varType, "setting " .. self.variable .. " wants a " .. self.varType)
		self.set(value)
	end
	function setting:GetName() return self.name end
	function setting:GetVariableType() return self.varType end
	MOCK.settings.variables[variable] = setting
	return setting
end
function Settings.CreateCheckbox(category, setting, tooltip)
	assert(setting:GetVariableType() == "boolean", "checkboxes are for boolean settings")
	table.insert(category.controls, { kind = "checkbox", setting = setting, tooltip = tooltip })
end
function Settings.CreateSliderOptions(minValue, maxValue, rate)
	local options = { minValue = minValue, maxValue = maxValue, steps = (maxValue - minValue) / rate }
	function options:SetLabelFormatter(label, formatter)
		assert(label and type(formatter) == "function")
		self.formatter = formatter
	end
	return options
end
function Settings.CreateSlider(category, setting, options, tooltip)
	assert(setting:GetVariableType() == "number" and options, "sliders are for number settings, with options")
	table.insert(category.controls, { kind = "slider", setting = setting, options = options, tooltip = tooltip })
end
function Settings.RegisterAddOnCategory(category) category.registered = true end
function Settings.OpenToCategory(id) assert(type(id) == "number", "OpenToCategory wants a category id"); MOCK.settings.opened = id end
function InCombatLockdown() return MOCK.inCombat == true end

---------------------------------------------------------------- Trainer Locator's templates
-- SearchBoxTemplate (InputBoxTemplates.xml): the search border's three pieces, the magnifying glass,
-- the grey "Search" instructions and the clear button that shows once there's text
T.SearchBoxTemplate = { kinds = Kinds("EditBox"), build = function(e)
	e.Left = Atlas(e, "BACKGROUND", "common-search-border-left")
	e.Left:SetSize(8, 20)
	e.Left:SetPoint("LEFT", -5, 0)
	e.Right = Atlas(e, "BACKGROUND", "common-search-border-right")
	e.Right:SetSize(8, 20)
	e.Right:SetPoint("RIGHT", 0, 0)
	e.Middle = Atlas(e, "BACKGROUND", "common-search-border-middle")
	e.Middle:SetSize(10, 20)
	e.Middle:SetPoint("LEFT", e.Left, "RIGHT")
	e.Middle:SetPoint("RIGHT", e.Right, "LEFT")
	e.searchIcon = Atlas(e, "OVERLAY", "common-search-magnifyingglass")
	e.searchIcon:SetSize(10, 10)
	e.searchIcon:SetPoint("LEFT", 1, -1)
	e.Instructions = e:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	e.Instructions:SetPoint("TOPLEFT", 16, 0)
	e.Instructions:SetPoint("BOTTOMRIGHT", -20, 0)
	e.Instructions:SetText("Search")
	e.clearButton = CreateFrame("Button", nil, e)
	e.clearButton:SetSize(17, 17)
	e.clearButton:SetPoint("RIGHT", -3, 0)
	e.clearButton.Icon = Atlas(e.clearButton, "ARTWORK", "common-search-clearbutton")
	e.clearButton.Icon:SetSize(10, 10)
	e.clearButton.Icon:SetPoint("TOPLEFT", 3, -3)
	e.clearButton:Hide()
	e.clearButton:SetScript("OnClick", function() e:SetText(""); e:ClearFocus() end)
	e._textFont = "GameFontHighlightSmall"
	-- SearchBoxTemplate_OnTextChanged
	e:SetScript("OnTextChanged", function(self)
		local empty = self:GetText() == ""
		self.clearButton:SetShown(not empty)
		self.Instructions:SetShown(empty)
	end)
end }

-- MinimalCheckboxTemplate: Camelot's small square box and its tick
T.MinimalCheckboxTemplate = { kinds = Kinds("CheckButton"), build = function(cb)
	cb:SetSize(30, 29)
	cb.NormalTexture = Atlas(cb, "ARTWORK", "checkbox-minimal")
	cb.NormalTexture:SetAllPoints()
	cb.HighlightTexture = Atlas(cb, "HIGHLIGHT", "checkbox-minimal")
	cb.HighlightTexture:SetAllPoints()
	cb.HighlightTexture:SetBlendMode("ADD")
	cb.CheckedTexture = Atlas(cb, "OVERLAY", "checkmark-minimal")
	cb.CheckedTexture:SetAllPoints()
	cb.CheckedTexture._whenChecked = true
end }

-- TrainerLocatorPinTemplate, as MapPins.xml makes it: the mixin, an Icon filling it, OnLoad
T.TrainerLocatorPinTemplate = { kinds = Kinds("Frame"), pin = true, build = function(pin)
	assert(TrainerLocatorPinMixin, "MapPins.xml loads after MapPins.lua defines the mixin")
	for k, v in pairs(TrainerLocatorPinMixin) do pin[k] = v end
	pin:SetSize(20, 20)
	pin.Icon = pin:CreateTexture(nil, "ARTWORK")
	pin.Icon:SetAllPoints()
	pin:OnLoad()
end }
