-- Trainer Locator: the window. Pick a kind of trainer, and it lists every one in the world, nearest
-- first, grouped by continent. Click one to put the game's map pin on it.
-- Built from the game's own templates and art so it reads as part of WoW: Forever's interface: the
-- portrait frame, the character window's backdrop and scroll lines, a Blizzard dropdown and search
-- box, the Reputation tab's section headers and row highlight, and the minimal checkboxes.
local _, ns = ...

local C = ns.COLOR
local DEFAULT_W, DEFAULT_H = 420, 560
local MIN_W, MIN_H, MAX_W, MAX_H = 340, 320, 900, 1400
local SIDE = 12
local SCROLLBAR = 14
local FOOTER_H = 34
local LIST_TOP = 90
local HEADER_ROW_H = 28
local GAP = 3
local ICON_X, TEXT_X = 5, 29
local PORTRAIT = "Interface\\Icons\\INV_Misc_Book_11"
local UI = {}
ns.UI = UI

local panel, scroll, content
local rows, headers = {}, {}

local function ContentWidth() return (panel and panel:GetWidth() or DEFAULT_W) - 2 * SIDE - SCROLLBAR end
local function SetColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font)
	fs:SetJustifyH(justify or "LEFT")
	return fs
end

local function Atlas(parent, layer, atlas)
	local t = parent:CreateTexture(nil, layer)
	t:SetAtlas(atlas)
	return t
end

local function TipLine(text, c) GameTooltip:AddLine(text, c[1], c[2], c[3], true) end

function UI.Selection()
	return ns.char.selection or ns.DefaultSelection()
end

---------------------------------------------------------------- what a row says
local function RankRange(teach)
	if not teach.rank then return nil end
	local low = teach.low or 1
	if low == teach.rank then return ns.RANKS[teach.rank] end
	return ns.RANKS[low] .. " to " .. ns.RANKS[teach.rank]
end

-- The short line under a trainer's name
function UI.Summary(teach)
	local kind = teach[1]
	if kind == "class" then
		return teach.max and teach.max < 60 and ("Spells up to level " .. teach.max) or nil
	elseif kind == "prof" then
		local range = RankRange(teach)
		if range then return range end
		return teach.n and (teach.n .. (teach.n == 1 and " recipe" or " recipes")) or nil
	elseif kind == "weapon" then
		return teach.w and table.concat(teach.w, ", ") or nil
	elseif teach.s then
		local names = {}
		for i = 1, math.min(3, #teach.s) do names[i] = teach.s[i] end
		return table.concat(names, ", ") .. (#teach.s > 3 and ", ..." or "")
	end
end

local SIDE_NAME = { [1] = "Alliance", [2] = "Horde" }

local function Distance(yards)
	if yards < 1000 then return math.floor(yards / 10 + 0.5) * 10 .. " yd" end
	return string.format("%.1fk yd", yards / 1000)
end

---------------------------------------------------------------- building blocks
local function SectionHeader(i)
	local h = headers[i]
	if h then return h end
	h = CreateFrame("Button", nil, content)
	h:SetHeight(HEADER_ROW_H)
	h.bg = Atlas(h, "BACKGROUND", "common-button-list-collapseExpand")
	h.bg:SetAllPoints()
	h.glow = Atlas(h, "HIGHLIGHT", "common-button-list-collapseExpand")
	h.glow:SetAllPoints()
	h.glow:SetBlendMode("ADD")
	h.glow:SetAlpha(0.3)
	h.icon = h:CreateTexture(nil, "BORDER")
	h.icon:SetPoint("RIGHT", -8, -1)
	h.text = Text(h, "GameFontNormalLeft")
	h.text:SetPoint("LEFT", 10, 0)
	h.count = Text(h, "GameFontHighlightSmall", "RIGHT")
	h.count:SetPoint("RIGHT", -28, 0)
	SetColor(h.count, C.grey)
	h:SetScript("OnMouseDown", function(self) self.text:SetPoint("LEFT", 11, -1) end)
	h:SetScript("OnMouseUp", function(self) self.text:SetPoint("LEFT", 10, 0) end)
	h:SetScript("OnClick", function(self)
		ns.char.collapsed[self.key] = not ns.char.collapsed[self.key] or nil
		UI.Refresh()
	end)
	headers[i] = h
	return h
end

local function Row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, content)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- the Reputation tab's hover glow
	r.hlLeft = Atlas(r, "HIGHLIGHT", "charactercreate-customize-dropdown-linemouseover-side")
	r.hlLeft:SetWidth(6)
	r.hlLeft:SetPoint("TOPLEFT")
	r.hlLeft:SetPoint("BOTTOMLEFT")
	r.hlRight = Atlas(r, "HIGHLIGHT", "charactercreate-customize-dropdown-linemouseover-side")
	r.hlRight:SetWidth(6)
	r.hlRight:SetTexCoord(1, 0, 0, 1)
	r.hlRight:SetPoint("TOPRIGHT")
	r.hlRight:SetPoint("BOTTOMRIGHT")
	r.hlMid = Atlas(r, "HIGHLIGHT", "charactercreate-customize-dropdown-linemouseover-middle")
	r.hlMid:SetPoint("TOPLEFT", r.hlLeft, "TOPRIGHT")
	r.hlMid:SetPoint("BOTTOMRIGHT", r.hlRight, "BOTTOMLEFT")
	for _, t in ipairs({ r.hlLeft, r.hlMid, r.hlRight }) do t:SetAlpha(0.1) end
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(20, 20)
	r.icon:SetPoint("TOPLEFT", ICON_X, -6)
	r.title = Text(r, "GameFontHighlight")
	r.title:SetPoint("TOPLEFT", TEXT_X, -5)
	r.title:SetWordWrap(false)
	r.right = Text(r, "GameFontHighlightSmall", "RIGHT")
	r.right:SetPoint("TOPRIGHT", -6, -6)
	r.where = Text(r, "GameFontNormalSmall")
	r.where:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -3)
	r.where:SetWordWrap(false)
	r.body = Text(r, "GameFontHighlightSmall")
	r.body:SetPoint("TOPLEFT", r.where, "BOTTOMLEFT", 0, -2)
	r.body:SetWordWrap(true)
	r:SetScript("OnClick", function(self, button)
		local d = self.data
		if not d then return end
		if button == "RightButton" then
			UI.ClearWaypoint()
		elseif IsShiftKeyDown and IsShiftKeyDown() then
			ns.LinkWaypoint(d.trainer, d.spawn)
		else
			ns.SetWaypoint(d.trainer, d.spawn)
			UI.Refresh()
		end
	end)
	r:SetScript("OnEnter", function(self) UI.RowTooltip(self, self.data) end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = r
	return r
end

local function SetIcon(tex, teach)
	local file, atlas = ns.IconFor(teach)
	if atlas then
		tex:SetAtlas(atlas)
		tex:SetTexCoord(0, 1, 0, 1)
	else
		tex:SetTexture(file)
		-- trims the icon's own border, as the spellbook does
		tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
end
UI.SetIcon = SetIcon

---------------------------------------------------------------- the category menu
local function Select(sel)
	ns.char.selection = sel
	if scroll then scroll:SetVerticalScroll(0) end
	UI.Refresh()
	if ns.Pins then ns.Pins.Refresh() end
end

local function IsSelected(sel) return UI.Selection() == sel end

local function CreateCategoryDropdown(parent)
	local d = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	d:SetWidth(190)
	d:SetupMenu(function(_, root)
		root:CreateRadio("All trainers", IsSelected, Select, "all")
		root:CreateTitle("Class")
		for _, c in ipairs(ns.CLASSES) do
			root:CreateRadio((ns.SelectionName("class:" .. c[1]):gsub(" trainers$", "")), IsSelected, Select, "class:" .. c[1])
		end
		root:CreateTitle("Professions")
		for _, p in ipairs(ns.PROFESSIONS) do root:CreateRadio(p[2], IsSelected, Select, "prof:" .. p[1]) end
		root:CreateTitle("Secondary skills")
		for _, p in ipairs(ns.SECONDARY) do root:CreateRadio(p[2], IsSelected, Select, "prof:" .. p[1]) end
		root:CreateTitle("Other")
		for _, k in ipairs({ "weapon", "riding", "pet", "portal", "other" }) do
			root:CreateRadio(ns.KINDS[k][1], IsSelected, Select, k)
		end
	end)
	-- the closed dropdown names the whole category: "Mage trainers", not just "Mage"
	d:SetSelectionTranslator(function(e) return ns.SelectionName(e.data) end)
	return d
end

---------------------------------------------------------------- panel
local function Checkbox(parent, label, tooltip, get, set)
	local cb = CreateFrame("CheckButton", nil, parent, "MinimalCheckboxTemplate")
	cb:SetSize(24, 24)
	cb.label = Text(cb, "GameFontHighlightSmall")
	cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	cb.label:SetText(label)
	cb:SetChecked(get())
	cb:SetScript("OnClick", function(self)
		local on = self:GetChecked() and true or false
		ns.PlaySound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF")
		set(on)
	end)
	cb:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(label, C.white[1], C.white[2], C.white[3])
		TipLine(tooltip, C.gold)
		GameTooltip:Show()
	end)
	cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	cb.get = get
	return cb
end

local function Build()
	panel = CreateFrame("Frame", "TrainerLocatorFrame", UIParent, "PortraitFrameTemplate")
	panel:SetSize(UI.SavedSize())
	panel:SetScale(ns.db.scale or 1)
	panel:SetFrameStrata("MEDIUM")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:SetResizable(true)
	if panel.SetResizeBounds then
		panel:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
	end
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		local point, _, relPoint, x, y = self:GetPoint(1)
		ns.db.point = { point, relPoint, x, y }
	end)
	panel:Hide()
	tinsert(UISpecialFrames, "TrainerLocatorFrame")
	panel:SetScript("OnHide", function()
		if panel.category.CloseMenu then panel.category:CloseMenu() end
		ns.PlaySound("IG_CHARACTER_INFO_CLOSE")
	end)

	panel:SetTitle("Trainer Locator")
	local portrait = panel.GetPortrait and panel:GetPortrait()
	if portrait then portrait:SetTexture(PORTRAIT) end

	panel.Bg:Hide()
	if panel.TopTileStreaks then panel.TopTileStreaks:Hide() end
	panel.backdrop = panel:CreateTexture(nil, "BACKGROUND")
	panel.backdrop:SetAtlas("UI-Character-Info-General-BG")
	panel.backdrop:SetPoint("TOPLEFT", 2, -21)
	panel.backdrop:SetPoint("BOTTOMRIGHT", -2, 2)

	-- the category menu, and a search box beside it
	panel.category = CreateCategoryDropdown(panel)
	panel.category:SetPoint("TOPLEFT", 64, -32)

	panel.search = CreateFrame("EditBox", "TrainerLocatorSearchBox", panel, "SearchBoxTemplate")
	panel.search:SetHeight(20)
	-- both ends hang from the top, level with the dropdown's middle
	panel.search:SetPoint("TOPLEFT", panel.category, "TOPRIGHT", 16, -2)
	panel.search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(SIDE + 4), -34)
	panel.search:HookScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		if text ~= (UI.searchText or "") then
			UI.searchText = text
			UI.Refresh()
		end
	end)

	panel.summary = Text(panel, "GameFontHighlightSmall", "LEFT")
	panel.summary:SetPoint("TOPLEFT", 64, -64)
	panel.summary:SetPoint("RIGHT", panel, "RIGHT", -(SIDE + 4), 0)
	panel.summary:SetWordWrap(false)

	panel.topLine = Atlas(panel, "ARTWORK", "UI-Character-Info-ScrollLine-Long")
	panel.topLine:SetHeight(8)
	panel.topLine:SetPoint("TOPLEFT", SIDE - 6, -(LIST_TOP - 6))
	panel.topLine:SetPoint("TOPRIGHT", -(SIDE - 6), -(LIST_TOP - 6))
	panel.bottomLine = Atlas(panel, "ARTWORK", "UI-Character-Info-ScrollLine-Long")
	panel.bottomLine:SetHeight(8)
	panel.bottomLine:SetPoint("BOTTOMLEFT", SIDE - 6, FOOTER_H - 2)
	panel.bottomLine:SetPoint("BOTTOMRIGHT", -(SIDE - 6), FOOTER_H - 2)

	scroll = CreateFrame("ScrollFrame", "TrainerLocatorScrollFrame", panel, "ScrollFrameTemplate")
	if scroll.ScrollBar and scroll.ScrollBar.SetHideIfUnscrollable then scroll.ScrollBar:SetHideIfUnscrollable(true) end
	scroll:SetPoint("TOPLEFT", SIDE, -(LIST_TOP + 2))
	scroll:SetPoint("BOTTOMRIGHT", -(SIDE + SCROLLBAR), FOOTER_H + 6)
	content = CreateFrame("Frame", nil, scroll)
	content:SetSize(ContentWidth(), 10)
	scroll:SetScrollChild(content)

	panel.empty = Text(content, "GameFontDisable", "CENTER")
	panel.empty:SetPoint("TOP", content, "TOP", 0, -18)
	panel.empty:SetSpacing(3)

	-- the footer's two switches
	panel.other = Checkbox(panel, "Other faction", "Also list the trainers who won't talk to you, greyed out.",
		function() return ns.db.showOther end,
		function(on) ns.db.showOther = on; UI.Refresh(); if ns.Pins then ns.Pins.Refresh() end end)
	panel.other:SetPoint("BOTTOMLEFT", SIDE - 2, 6)
	panel.pins = Checkbox(panel, "Show on map", "Marks every trainer in the list on the world map.",
		function() return ns.db.mapPins end,
		function(on) ns.db.mapPins = on; if ns.Pins then ns.Pins.Refresh() end end)
	panel.pins:SetPoint("LEFT", panel.other.label, "RIGHT", 14, 0)

	local grip = CreateFrame("Button", nil, panel)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
	grip:SetFrameLevel(panel.CloseButton:GetFrameLevel())
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then panel:StartSizing("BOTTOMRIGHT") end
	end)
	grip:SetScript("OnMouseUp", function()
		panel:StopMovingOrSizing()
		panel:SetUserPlaced(false)
		ns.db.size = { math.floor(panel:GetWidth() + 0.5), math.floor(panel:GetHeight() + 0.5) }
		local point, _, relPoint, x, y = panel:GetPoint(1)
		if point then ns.db.point = { point, relPoint, x, y } end
		UI.Refresh()
	end)
	grip:SetScript("OnEnter", function() if SetCursor then SetCursor("UI_RESIZE_CURSOR") end end)
	grip:SetScript("OnLeave", function() if SetCursor then SetCursor(nil) end end)
	panel.grip = grip

	panel:SetScript("OnSizeChanged", function()
		if panel:IsShown() and UI.result then UI.Render(UI.result) end
	end)

	-- distances change as you walk, so the list follows you while it's open: once a second it
	-- checks, and redoes the list after you've gone 10 yards (nothing reads finer than that)
	local elapsed = 0
	panel:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 1 then return end
		elapsed = 0
		local here = UI.result and UI.result.here
		local _, _, _, instance, wx, wy = ns.PlayerPos()
		if not here or instance ~= here.instance or (wx and here.wx and ((wx - here.wx) ^ 2 + (wy - here.wy) ^ 2) > 100) then
			UI.Refresh()
		end
	end)
end

function UI.SavedSize()
	local size = ns.db.size
	if size and size[1] and size[2] then
		return math.max(MIN_W, math.min(MAX_W, size[1])), math.max(MIN_H, math.min(MAX_H, size[2]))
	end
	return DEFAULT_W, DEFAULT_H
end

---------------------------------------------------------------- render
local function RenderSummary(result, sel)
	local parts = {}
	local n = result.total
	table.insert(parts, n .. (n == 1 and " trainer" or " trainers"))
	local near = result.nearest
	if near then
		table.insert(parts, "nearest " .. ns.Paint("white", near.trainer.name) .. ", " .. Distance(near.dist))
	elseif not result.here.instance and result.here.mapID then
		table.insert(parts, ns.Paint("grey", "distances show outside instances"))
	end
	panel.summary:SetText(ns.Paint("gold", table.concat(parts, ns.Paint("grey", "  /  "))))
	if not panel.category:IsMenuOpen() then panel.category:GenerateMenu() end
end

local function RowText(r, d)
	local t = d.trainer
	local dim = not d.usable or not d.fit
	local tag = t.tag and (" " .. ns.Paint("grey", "<" .. t.tag .. ">")) or ""
	r.title:SetText(t.name .. tag)
	SetColor(r.title, dim and C.grey or C.white)
	r.right:SetText(d.dist and Distance(d.dist) or "")
	SetColor(r.right, dim and C.grey or C.white)
	r.where:SetText(d.zone .. "  " .. ns.Paint("grey", ns.Coords(d.spawn)))
	SetColor(r.where, dim and C.grey or C.gold)
	local body = {}
	if not d.usable then
		local only = SIDE_NAME[t.side]
		table.insert(body, ns.Paint("red", only and (only .. " only") or "Won't talk to you"))
	elseif d.note then
		table.insert(body, ns.Paint("grey", d.note))
	end
	-- the note already says where a class trainer stops
	local summary = not (d.note and d.teach[1] == "class") and UI.Summary(d.teach)
	if summary then table.insert(body, summary) end
	if UI.Selection() == "all" and d.teach[1] ~= "prof" then
		-- the list mixes kinds, so say which this is when the tag doesn't
		if not t.tag then table.insert(body, 1, ns.SelectionName(d.teach[1] == "class" and ("class:" .. d.teach[2]) or d.teach[1])) end
	end
	r.body:SetText(table.concat(body, ns.Paint("grey", "  /  ")))
	SetColor(r.body, dim and C.grey or C.white)
	r.icon:SetDesaturated(dim and true or false)
end

function UI.Render(result)
	for _, r in ipairs(rows) do r:Hide(); r.data = nil end
	for _, h in ipairs(headers) do h:Hide() end
	panel.empty:Hide()
	local cw = ContentWidth()
	content:SetWidth(cw)
	panel.empty:SetWidth(cw - 24)

	if result.total == 0 then
		local search = UI.searchText or ""
		panel.empty:SetText(search ~= "" and ("No trainers match \"" .. search .. "\".") or
			"There are no trainers of this kind for your faction.\n\nTick Other faction to see the rest.")
		panel.empty:Show()
		content:SetHeight(80)
		return
	end

	local y, ri, hi = 0, 0, 0
	local wp = UI.Waypoint()
	for _, g in ipairs(result.groups) do
		hi = hi + 1
		local h = SectionHeader(hi)
		h.key = g.key
		h:SetWidth(cw)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
		h.text:SetText(g.name)
		-- a search opens every group, so what it found is never folded away
		local collapsed = ns.char.collapsed[g.key] and (UI.searchText or "") == ""
		h.icon:SetAtlas(collapsed and "common-button-list-plus" or "common-button-list-minus", true)
		h.count:SetText(tostring(#g.rows))
		h:Show()
		y = y - (HEADER_ROW_H + GAP)
		if not collapsed then
			for _, d in ipairs(g.rows) do
				ri = ri + 1
				local r = Row(ri)
				r.data = d
				r:SetWidth(cw)
				r:ClearAllPoints()
				r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
				SetIcon(r.icon, d.teach)
				RowText(r, d)
				r.title:SetWidth(math.max(80, cw - TEXT_X - 6 - r.right:GetStringWidth() - 8))
				r.where:SetWidth(cw - TEXT_X - 6)
				r.body:SetWidth(cw - TEXT_X - 6)
				local hasBody = (r.body:GetText() or "") ~= ""
				r.body:SetShown(hasBody)
				-- the trainer the map pin is on keeps its highlight
				if wp and wp[1] == d.spawn[1] and math.abs(wp[2] - d.spawn[2]) < 0.2 and math.abs(wp[3] - d.spawn[3]) < 0.2 then
					r:LockHighlight()
				else
					r:UnlockHighlight()
				end
				local h2 = 5 + r.title:GetStringHeight() + 3 + r.where:GetStringHeight()
				if hasBody then h2 = h2 + 2 + r.body:GetStringHeight() end
				r:SetHeight(h2 + 6)
				r:Show()
				y = y - (h2 + 6 + GAP)
			end
		end
		y = y - 3
	end
	content:SetHeight(math.max(10, -y + 6))
	if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
	local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
	if scroll.GetVerticalScroll and scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
end

function UI.Refresh()
	if not panel or not panel:IsShown() then return end
	ns.RefreshPlayer()
	local sel = UI.Selection()
	local result = ns.Query(sel, UI.searchText, ns.db.showOther)
	UI.result = result
	RenderSummary(result, sel)
	UI.Render(result)
	panel.other:SetChecked(ns.db.showOther and true or false)
	panel.pins:SetChecked(ns.db.mapPins and true or false)
end

function UI.RefreshIfShown()
	if panel and panel:IsShown() then UI.Refresh() end
end

---------------------------------------------------------------- tooltips
-- A trainer, in the game's style: a white name, gold for what they are, white for what they teach,
-- green for what a click does. Shared with the map pins.
function UI.TrainerTooltip(owner, d, anchor)
	local t = d.trainer
	GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
	GameTooltip:SetText(t.name, C.white[1], C.white[2], C.white[3])
	if t.tag then TipLine(t.tag, C.gold) end
	TipLine(d.zone .. "  " .. ns.Coords(d.spawn), C.white)
	if d.dist then TipLine(Distance(d.dist) .. " away", C.grey) end
	if not d.usable then
		local only = SIDE_NAME[t.side]
		TipLine(only and (only .. " only") or "Won't talk to you", C.red)
	end
	local teach = d.teach
	GameTooltip:AddLine(" ")
	if teach[1] == "class" then
		TipLine((ns.SelectionName("class:" .. teach[2]):gsub(" trainers$", " spells")), C.gold)
		if teach.n then TipLine(teach.n .. " spells and ranks, up to level " .. (teach.max or 60), C.white) end
	elseif teach[1] == "prof" then
		local p = ns.SKILL[teach[2]]
		TipLine(p and p[2] or "Profession", C.gold)
		local range = RankRange(teach)
		if range then TipLine("Trains " .. range .. " (up to " .. ns.RANK_CAP[teach.rank] .. " skill)", C.white) end
		if teach.n and teach.n > 0 then
			TipLine(teach.n .. (teach.n == 1 and " recipe" or " recipes") .. (teach.top and (", up to skill " .. teach.top) or ""), C.white)
		end
		local skill, maxSkill = ns.ProfessionSkill(teach[2])
		if skill then TipLine("You: " .. skill .. " / " .. maxSkill, C.grey) end
	elseif teach[1] == "weapon" then
		TipLine("Weapon skills", C.gold)
		for i, w in ipairs(teach.w or {}) do
			local spell = teach.ids and teach.ids[i]
			local known = spell and ns.Knows(spell)
			if known then
				TipLine(w .. " (known)", C.grey)
			else
				TipLine(w, C.white)
			end
		end
	elseif teach.s then
		for i = 1, math.min(12, #teach.s) do TipLine(teach.s[i], C.white) end
		if #teach.s > 12 then TipLine("and " .. (#teach.s - 12) .. " more", C.grey) end
	end
	if d.note then TipLine((d.note:gsub("^%l", string.upper)), C.grey) end
	if #t.teach > 1 then
		local also = {}
		for _, other in ipairs(t.teach) do
			if other ~= teach then
				table.insert(also, other[1] == "prof" and (ns.SKILL[other[2]] or { 0, "?" })[2]
					or ns.SelectionName(other[1] == "class" and ("class:" .. other[2]) or other[1]))
			end
		end
		TipLine("Also: " .. table.concat(also, ", "), C.grey)
	end
	if #t.at > 1 then TipLine("Found in " .. #t.at .. " places; this is the nearest.", C.grey) end
	GameTooltip:AddLine(" ")
	TipLine("Click to put a map pin on them", C.green)
	TipLine("Shift-click to link the spot in chat", C.green)
	if owner.GetParent and owner:GetParent() == content then TipLine("Right-click to clear the pin", C.green) end
	GameTooltip:Show()
end
function UI.RowTooltip(row, d) if d then UI.TrainerTooltip(row, d) end end

---------------------------------------------------------------- the waypoint
function UI.Waypoint()
	if not (C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return nil end
	local p = C_Map.GetUserWaypoint()
	if not p or not p.position then return nil end
	local x, y = ns.XY(p.position)
	if type(x) ~= "number" or type(y) ~= "number" then return nil end
	return { p.uiMapID, x * 100, y * 100 }
end

function UI.ClearWaypoint()
	if C_Map and C_Map.ClearUserWaypoint and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
		C_Map.ClearUserWaypoint()
		ns.PlaySound("UI_MAP_WAYPOINT_REMOVE")
	end
	UI.Refresh()
	if ns.Pins then ns.Pins.Refresh() end
end

---------------------------------------------------------------- showing
function UI.Show()
	if not panel then Build() end
	panel:SetSize(UI.SavedSize())
	panel:ClearAllPoints()
	local p = ns.db.point
	if p then
		panel:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
	if not panel:IsShown() then ns.PlaySound("IG_CHARACTER_INFO_OPEN") end
	panel:Show()
	UI.Refresh()
end

function UI.Close()
	if panel then panel:Hide() end
end

function UI.Toggle()
	if panel and panel:IsShown() then UI.Close() else UI.Show() end
end

function UI.IsShown() return panel and panel:IsShown() end

-- /trainers <text>: a category by name ("alchemy", "mage", "weapon") or else a search
function UI.OpenSearch(text)
	local want = text:lower()
	local found
	local candidates = { "all" }
	for _, c in ipairs(ns.CLASSES) do table.insert(candidates, "class:" .. c[1]) end
	for _, p in ipairs(ns.PROFESSIONS) do table.insert(candidates, "prof:" .. p[1]) end
	for _, p in ipairs(ns.SECONDARY) do table.insert(candidates, "prof:" .. p[1]) end
	for _, k in ipairs({ "weapon", "riding", "pet", "portal", "other" }) do table.insert(candidates, k) end
	for _, sel in ipairs(candidates) do
		local name = ns.SelectionName(sel):lower()
		if name == want or name:gsub(" trainers$", "") == want or name:gsub(" masters$", "") == want then
			found = sel
			break
		end
	end
	UI.Show()
	if found then
		panel.search:SetText("")
		UI.searchText = ""
		Select(found)
	else
		ns.char.selection = "all"
		panel.search:SetText(text)
		UI.searchText = text
		UI.Refresh()
		if ns.Pins then ns.Pins.Refresh() end
	end
end

function UI.SetScale(scale)
	ns.db.scale = scale
	if panel then panel:SetScale(scale) end
end
