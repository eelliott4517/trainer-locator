-- Trainer Locator scenarios, run against the real Data.lua. Loaded fresh for each scenario by run.py:
--   loadfile(dir .. "/test/tltest.lua")(dir, scenario) -> number of failures
local DIR, SCENARIO = ...
assert(loadfile(DIR .. "/test/wowmock.lua"))(DIR)
assert(loadfile(DIR .. "/test/tlmock.lua"))(DIR)

local failures = 0
local function check(ok, msg)
	if ok then
		print("  ok   " .. msg)
	else
		failures = failures + 1
		print("  FAIL " .. msg)
	end
end
local function has(haystack, needle) return type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil end

---------------------------------------------------------------- load the addon like the client does
local ns = {}
local ADDON_DIR = DIR .. "/../TrainerLocator/"
for line in io.lines(ADDON_DIR .. "TrainerLocator.toc") do
	if line:match("%.lua%s*$") then
		assert(loadfile(ADDON_DIR .. line))("TrainerLocator", ns)
	elseif line:match("%.xml%s*$") then
		-- MapPins.xml only defines the pin template, which templates.lua mocks
		assert(line:match("MapPins%.xml"), "unmocked XML file " .. line)
	end
end

local function Login()
	MOCK.Fire("ADDON_LOADED", "TrainerLocator")
	MOCK.Fire("PLAYER_LOGIN")
end

-- The rows the window shows, top to bottom, as { top, bottom, text, frame }
local function PanelRows()
	local out = {}
	local content = TrainerLocatorScrollFrame:GetScrollChild()
	for _, f in ipairs(MOCK.frames) do
		if f._parent == content and f:IsShown() and f._points and f._points[1] then
			local top = f._points[1][5]
			local texts = {}
			for _, fs in ipairs(f._fontstrings or {}) do
				if fs._shown and fs._text and fs._text ~= "" then table.insert(texts, MOCK.Plain(fs._text)) end
			end
			table.insert(out, { top = top, bottom = top - f:GetHeight(), text = table.concat(texts, " | "), frame = f })
		end
	end
	table.sort(out, function(a, b) return a.top > b.top end)
	return out
end
local function TrainerRows()
	local out = {}
	for _, r in ipairs(PanelRows()) do if r.frame.data then table.insert(out, r) end end
	return out
end
local function NoOverlap()
	local rows = PanelRows()
	for i = 2, #rows do
		if rows[i].top > rows[i - 1].bottom + 0.01 then return false, rows[i - 1].text .. " / " .. rows[i].text end
	end
	return true
end
local function Find(pred)
	for _, t in ipairs(ns.Data.trainers) do if pred(t) then return t end end
end
local function Teaches(t, kind, key)
	for _, e in ipairs(t.teach) do if e[1] == kind and (key == nil or e[2] == key) then return e end end
end

---------------------------------------------------------------- scenarios
local S = {}

-- A human mage in Stormwind's Trade District opens the window
function S.basics()
	MOCK.side, MOCK.classToken, MOCK.level = "Alliance", "MAGE", 60
	MOCK.pos = { 1453, 0.60, 0.70 }
	Login()
	check(ns.Data and #ns.Data.trainers > 20, "the data loads (" .. #ns.Data.trainers .. " trainers)")
	MOCK.Slash("/trainers")
	check(TrainerLocatorFrame:IsShown(), "/trainers opens the window")
	check(TrainerLocatorFrame:GetWidth() == 420 and TrainerLocatorFrame:GetHeight() == 560, "at its default size")
	check(ns.UI.Selection() == "class:MAGE", "it starts on your class's trainers")
	check(MOCK.Plain(TrainerLocatorFrame.category.Text:GetText()) == "Mage trainers", "the menu names the whole category")
	local rows = TrainerRows()
	check(#rows > 0, "it lists mage trainers (" .. #rows .. ")")
	local allMage, allUsable, sorted = true, true, true
	local last = -1
	for _, r in ipairs(rows) do
		local d = r.frame.data
		if d.teach[1] ~= "class" or d.teach[2] ~= "MAGE" then allMage = false end
		if not d.usable then allUsable = false end
		if d.dist then
			if d.trainer.at[1][1] ~= 1453 and last > d.dist then sorted = false end
			last = math.max(last, d.dist)
		end
	end
	check(allMage, "every row is a mage trainer")
	check(allUsable, "and one who'll talk to an Alliance character")
	local first = rows[1].frame.data
	check(first.dist and first.dist < 400, "the first is close by (" .. tostring(first.dist and math.floor(first.dist)) .. " yd, " .. first.trainer.name .. ")")
	local groups = ns.UI.result.groups
	check(groups[1].name == "Eastern Kingdoms", "Eastern Kingdoms comes first, since you're on it")
	local okOrder = true
	for _, g in ipairs(groups) do
		local prev
		for _, row in ipairs(g.rows) do
			if prev and prev.dist and row.dist and row.dist < prev.dist then okOrder = false end
			prev = row
		end
	end
	check(okOrder, "each group lists the nearest first")
	local summary = MOCK.Plain(TrainerLocatorFrame.summary:GetText())
	check(has(summary, "nearest " .. first.trainer.name), "the summary names the nearest: " .. summary)
	check(NoOverlap(), "rows don't overlap")
	local r1 = MOCK.Plain(rows[1].text)
	check(has(r1, first.trainer.name) and has(r1, "yd") and has(r1, ns.Coords(first.spawn)), "a row shows name, distance and coordinates: " .. r1)
end

-- Picking another kind from the menu, and a profession's ranks against your own skill
function S.professions()
	MOCK.side, MOCK.classToken = "Alliance", "WARRIOR"
	MOCK.pos = { 1453, 0.55, 0.75 }
	MOCK.professions = { { "Tailoring", 148, 150, 197 } }
	Login()
	MOCK.Slash("/trainers")
	TrainerLocatorFrame.category:MockPick("prof:197")
	check(ns.UI.Selection() == "prof:197" and MOCK.Plain(TrainerLocatorFrame.category.Text:GetText()) == "Tailoring trainers", "the menu picks Tailoring")
	local rows = TrainerRows()
	check(#rows > 0, "tailoring trainers are listed (" .. #rows .. ")")
	local low, high
	for _, r in ipairs(rows) do
		local d = r.frame.data
		if d.teach.rank and d.teach.rank <= 2 then low = low or d end
		if d.teach.rank and d.teach.rank >= 3 then high = high or d end
	end
	if low then
		check(not low.fit and has(low.note, "past Journeyman"), "a trainer who stops at Journeyman can't take a 148/150 tailor further: " .. tostring(low.note))
	end
	if high then
		check(high.fit, "one who trains " .. ns.RANKS[high.teach.rank] .. " can")
		local text
		for _, r in ipairs(rows) do if r.frame.data == high then text = MOCK.Plain(r.text) end end
		check(has(text, ns.RANKS[high.teach.rank]), "its row says how far it trains: " .. tostring(text))
	end
	check(ns.UI.result.nearest == nil or ns.UI.result.nearest.fit, "the nearest named is one who can train you")
	-- the tooltip gives the details
	for _, r in ipairs(TrainerRows()) do
		if r.frame.data == (high or low) then
			MOCK.Hover(r.frame)
			local tip = MOCK.TooltipText()
			check(has(tip, "Tailoring") and has(tip, "You: 148 / 150") and has(tip, "Click to put a map pin"), "the tooltip has the profession, your skill and the clicks")
			break
		end
	end
	TrainerLocatorFrame.category:MockPick("weapon")
	local w = TrainerRows()[1]
	check(w and w.frame.data.teach[1] == "weapon" and has(w.text, "Swords") or has(w and w.text, "Axes") or has(w and w.text, "Maces"),
		"weapon masters list their weapons: " .. tostring(w and w.text))
	check(NoOverlap(), "rows don't overlap")
end

-- Searching, and the empty list
function S.search()
	MOCK.side, MOCK.classToken = "Alliance", "PRIEST"
	MOCK.pos = { 1429, 0.42, 0.65 }
	Login()
	MOCK.Slash("/trainers")
	TrainerLocatorFrame.category:MockPick("all")
	local all = #TrainerRows()
	TrainerLocatorFrame.search:MockType("stormwind")
	local rows = TrainerRows()
	local allSW = #rows > 0
	for _, r in ipairs(rows) do if r.frame.data.zone ~= "Stormwind City" and not has(r.text:lower(), "stormwind") then allSW = false end end
	check(allSW and #rows < all, "typing a zone keeps its trainers (" .. #rows .. " of " .. all .. ")")
	TrainerLocatorFrame.search:MockType("zzzq")
	check(#TrainerRows() == 0 and TrainerLocatorFrame.empty:IsShown() and has(TrainerLocatorFrame.empty:GetText(), "zzzq"), "no match says so")
	TrainerLocatorFrame.search:MockType("")
	check(#TrainerRows() == all, "clearing it brings them back")
	-- /trainers <name of a kind> picks it, anything else searches
	MOCK.Slash("/trainers alchemy")
	check(ns.UI.Selection() == "prof:171" and TrainerLocatorFrame.search:GetText() == "", "/trainers alchemy picks Alchemy")
	MOCK.Slash("/trainers weapon")
	check(ns.UI.Selection() == "weapon", "/trainers weapon picks weapon masters")
	local someone = Find(function(t) return bit.band(t.side, 1) ~= 0 end).name
	MOCK.Slash("/trainers " .. someone:lower())
	check(ns.UI.Selection() == "all" and TrainerLocatorFrame.search:GetText() == someone:lower() and #TrainerRows() >= 1,
		"/trainers <name> searches for them (" .. ns.UI.Selection() .. ", " .. TrainerLocatorFrame.search:GetText() .. ", " .. #TrainerRows() .. ")")
end

-- Clicking a row: the map pin, the arrow, the map, the chat line; shift-click links; right-click clears
function S.waypoint()
	MOCK.side, MOCK.classToken = "Alliance", "MAGE"
	MOCK.pos = { 1453, 0.6, 0.7 }
	Login()
	MOCK.Slash("/trainers")
	local row = TrainerRows()[1]
	local d = row.frame.data
	row.frame:Click("LeftButton")
	local w = MOCK.waypoint
	check(w and w.uiMapID == d.spawn[1] and math.abs(w.position.x * 100 - d.spawn[2]) < 0.01, "a click puts the map pin on them")
	check(MOCK.superTracked, "and tracks it, so the arrow shows in the world")
	check(MOCK.openedMap == d.spawn[1], "the map opens there")
	check(has(MOCK.chat[#MOCK.chat], d.trainer.name), "chat says where: " .. tostring(MOCK.chat[#MOCK.chat]))
	local locked = false
	for _, r in ipairs(TrainerRows()) do if r.frame.data.trainer == d.trainer then locked = r.frame._highlightLocked end end
	check(locked, "their row stays lit")
	MOCK.shift = true
	TrainerRows()[1].frame:Click("LeftButton")
	MOCK.shift = false
	check(has(MOCK.linked[1], d.trainer.name) and has(MOCK.linked[1], "worldmap:"), "shift-click links the spot in chat")
	TrainerRows()[1].frame:Click("RightButton")
	check(MOCK.waypoint == nil, "right-click clears the pin")
	-- with the map-opening option off, only the pin moves
	ns.db.openMap = false
	MOCK.openedMap = nil
	TrainerRows()[1].frame:Click("LeftButton")
	check(MOCK.waypoint ~= nil and MOCK.openedMap == nil, "the map stays shut when that's turned off")
end

-- The world map shows the list as pins, on zone and city maps
function S.pins()
	MOCK.side, MOCK.classToken = "Alliance", "MAGE"
	MOCK.pos = { 1453, 0.6, 0.7 }
	Login()
	check(#WorldMapFrame._providers == 1, "a map data provider is added at login")
	MOCK.ShowMap(1453)
	local pins = {}
	for _, p in ipairs(MOCK.Pins()) do if p:IsShown() then table.insert(pins, p) end end
	check(#pins > 0, "Stormwind's map shows its mage trainers (" .. #pins .. ")")
	local ok = true
	for _, p in ipairs(pins) do if p.row.teach[2] ~= "MAGE" then ok = false end end
	check(ok, "only the kind picked")
	check(pins[1] and pins[1].Icon:GetAtlas() == "classicon-mage", "with the class icon")
	MOCK.ShowMap(1429)
	local elwynn = 0
	for _, p in ipairs(MOCK.Pins()) do
		if p:IsShown() and p.spawn[1] == 1453 then elwynn = elwynn + 1 end
	end
	check(elwynn > 0, "Stormwind's trainers show on Elwynn's map too, where the city is")
	MOCK.ShowMap(1415)
	check(#MOCK.Pins() == 0, "the continent map stays clear")
	MOCK.ShowMap(1453)
	local pin = MOCK.Pins()[1]
	pin:OnMouseEnter()
	check(has(MOCK.TooltipText(), pin.row.trainer.name), "hovering a pin shows the trainer")
	pin:OnMouseClickAction("LeftButton")
	check(MOCK.waypoint and MOCK.waypoint.uiMapID == pin.spawn[1], "clicking a pin puts the map pin there")
	check(MOCK.openedMap == nil, "without jumping the map somewhere else")
	MOCK.Slash("/trainers")
	TrainerLocatorFrame.pins:Click()
	check(ns.db.mapPins == false and #MOCK.Pins() == 0, "the Show on map box takes them off")
end

-- The other faction's trainers, greyed out
function S.otherfaction()
	MOCK.side, MOCK.classToken = "Alliance", "PALADIN"
	MOCK.pos = { 1453, 0.6, 0.7 }
	Login()
	MOCK.Slash("/trainers")
	local before = #TrainerRows()
	TrainerLocatorFrame.other:Click()
	check(ns.db.showOther == true, "the box turns it on")
	local rows, horde = TrainerRows(), nil
	for _, r in ipairs(rows) do if not r.frame.data.usable then horde = r end end
	check(#rows > before and horde ~= nil, "Horde trainers join the list (" .. before .. " -> " .. #rows .. ")")
	if horde then
		check(has(horde.text, "Horde only"), "marked Horde only: " .. horde.text)
		check(horde.frame.icon._desaturated == true, "with a grey icon")
	end
	check(ns.UI.result.nearest == nil or ns.UI.result.nearest.usable, "the nearest named is one of yours")
end

-- A class trainer whose spells stop below your level
function S.lowtrainer()
	local t, e = nil, nil
	for _, tr in ipairs(ns.Data.trainers) do
		local c = Teaches(tr, "class")
		if c and c.max and c.max < 20 and tr.side ~= 3 then t, e = tr, c; break end
	end
	if not t then print("  skip (no starting-area class trainer in this data)"); return end
	MOCK.side = t.side == 1 and "Alliance" or "Horde"
	MOCK.classToken, MOCK.level = e[2], 30
	MOCK.pos = { t.at[1][1], t.at[1][2] / 100, t.at[1][3] / 100 }
	Login()
	MOCK.Slash("/trainers")
	local row
	for _, r in ipairs(TrainerRows()) do if r.frame.data.trainer == t then row = r end end
	check(row and has(row.text, "only teaches up to level " .. e.max), t.name .. " says they stop at level " .. e.max .. ": " .. tostring(row and row.text))
	check(ns.UI.result.nearest and ns.UI.result.nearest.trainer ~= t, "and isn't named the nearest for a level 30")
end

-- Where the client hides your position: no distances, nothing breaks
function S.instance()
	MOCK.side, MOCK.classToken = "Horde", "WARRIOR"
	MOCK.pos = nil
	Login()
	MOCK.Slash("/trainers")
	local rows = TrainerRows()
	check(#rows > 0, "the list still shows")
	check(rows[1].frame.data.dist == nil, "without distances")
	MOCK.pos = { 1454, 0.5, 0.5, secret = true }
	ns.UI.Refresh()
	check(#TrainerRows() > 0, "a secret position is left alone")
	MOCK.pos = { 1454, 0.5, 0.5 }
	ns.UI.Refresh()
	check(TrainerRows()[1].frame.data.dist ~= nil, "distances come back outside")
end

-- Options, the saved size, the addon menu and the key binding
function S.options()
	Login()
	local cat = MOCK.settings.categories[1]
	check(cat and cat.name == "Trainer Locator" and cat.registered, "a page in the game's options")
	local names = {}
	for name, v in pairs(MOCK.settings.variables) do names[#names + 1] = name end
	check(#names == 4, "with its four settings")
	TrainerLocator_OnAddonCompartmentClick()
	check(TrainerLocatorFrame:IsShown(), "the minimap's addon menu opens it")
	TrainerLocator_Toggle()
	check(not TrainerLocatorFrame:IsShown(), "the key binding closes it")
	check(BINDING_NAME_TRAINERLOCATOR_TOGGLE ~= nil, "the binding has a name")
	MOCK.Slash("/trainers options")
	check(MOCK.settings.opened == cat:GetID(), "/trainers options opens the page")
end

-- Every trainer in the data draws a row without error, and every one has somewhere to be
function S.alldata()
	MOCK.side, MOCK.classToken = "Alliance", "MAGE"
	MOCK.pos = { 1453, 0.6, 0.7 }
	Login()
	ns.db.showOther = true
	MOCK.Slash("/trainers")
	TrainerLocatorFrame.category:MockPick("all")
	local rows = TrainerRows()
	check(#rows == #ns.Data.trainers, "all " .. #ns.Data.trainers .. " trainers list")
	local placed = true
	for _, t in ipairs(ns.Data.trainers) do
		for _, s in ipairs(t.at) do
			if not ns.Data.maps[s[1]] or s[2] < 0 or s[2] > 100 or s[3] < 0 or s[3] > 100 then placed = false; print("    bad spot", t.name, s[1], s[2], s[3]) end
		end
	end
	check(placed, "every spot is on a known map")
	for _, r in ipairs(rows) do MOCK.Hover(r.frame) end
	check(true, "every tooltip builds")
	check(NoOverlap(), "rows don't overlap")
	local kinds = {}
	for _, sel in ipairs({ "weapon", "riding", "pet", "portal", "other" }) do
		TrainerLocatorFrame.category:MockPick(sel)
		kinds[#kinds + 1] = sel .. " " .. #TrainerRows()
	end
	print("    " .. table.concat(kinds, ", "))
end

local fn = S[SCENARIO]
assert(fn, "no scenario " .. tostring(SCENARIO))
fn()
return failures
