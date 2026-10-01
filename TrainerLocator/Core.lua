-- Trainer Locator: shared state, the player, the trainer categories, filtering and distances.
local ADDON, ns = ...

ns.VERSION = "1.0.0"

-- The game's own text colors: Blizzard's color globals when the client has them, their WoW: Forever
-- values otherwise
local function GameColor(global, r, g, b)
	local c = _G[global]
	if type(c) == "table" and type(c.r) == "number" then return { c.r, c.g, c.b } end
	return { r, g, b }
end
ns.COLOR = {
	gold = GameColor("NORMAL_FONT_COLOR", 1, 0.82, 0),
	white = GameColor("HIGHLIGHT_FONT_COLOR", 1, 1, 1),
	grey = GameColor("GRAY_FONT_COLOR", 0.5, 0.5, 0.5),
	green = GameColor("GREEN_FONT_COLOR", 0.1, 1, 0.1),
	red = GameColor("RED_FONT_COLOR", 1, 0.125, 0.125),
}
local function Hex(c) return string.format("ff%02x%02x%02x", c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5) end
ns.HEX = {}
for k, c in pairs(ns.COLOR) do ns.HEX[k] = Hex(c) end
function ns.Paint(colorName, text) return "|c" .. ns.HEX[colorName] .. text .. "|r" end

function ns.PlaySound(kit)
	if PlaySound and SOUNDKIT and SOUNDKIT[kit] then PlaySound(SOUNDKIT[kit]) end
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(ns.Paint("gold", "Trainer Locator") .. ": " .. msg)
end

local secret = issecretvalue or function() return false end
ns.IsSecret = secret

---------------------------------------------------------------- categories
-- Class tokens in the order the game lists them, with their bit in a spell's class mask
ns.CLASSES = {
	{ "WARRIOR", 1, "Warrior" }, { "PALADIN", 2, "Paladin" }, { "HUNTER", 3, "Hunter" }, { "ROGUE", 4, "Rogue" },
	{ "PRIEST", 5, "Priest" }, { "SHAMAN", 7, "Shaman" }, { "MAGE", 8, "Mage" }, { "WARLOCK", 9, "Warlock" },
	{ "DRUID", 11, "Druid" },
}
ns.CLASS_BY_TOKEN = {}
for _, c in ipairs(ns.CLASSES) do ns.CLASS_BY_TOKEN[c[1]] = c end

-- Skill line id, name and icon. Primary professions, then the secondary skills.
ns.PROFESSIONS = {
	{ 171, "Alchemy", "Interface\\Icons\\Trade_Alchemy" },
	{ 164, "Blacksmithing", "Interface\\Icons\\Trade_BlackSmithing" },
	{ 333, "Enchanting", "Interface\\Icons\\Trade_Engraving" },
	{ 202, "Engineering", "Interface\\Icons\\Trade_Engineering" },
	{ 182, "Herbalism", "Interface\\Icons\\Spell_Nature_NatureTouchGrow" },
	{ 165, "Leatherworking", "Interface\\Icons\\INV_Misc_ArmorKit_17" },
	{ 186, "Mining", "Interface\\Icons\\Trade_Mining" },
	{ 393, "Skinning", "Interface\\Icons\\INV_Misc_Pelt_Wolf_01" },
	{ 197, "Tailoring", "Interface\\Icons\\Trade_Tailoring" },
}
ns.SECONDARY = {
	{ 185, "Cooking", "Interface\\Icons\\INV_Misc_Food_15" },
	{ 129, "First Aid", "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
	{ 356, "Fishing", "Interface\\Icons\\Trade_Fishing" },
}
ns.SKILL = {}
for _, p in ipairs(ns.PROFESSIONS) do ns.SKILL[p[1]] = p end
for _, p in ipairs(ns.SECONDARY) do ns.SKILL[p[1]] = p end

-- Profession ranks, as the trainers' rank spells name them
ns.RANKS = { "Apprentice", "Journeyman", "Expert", "Artisan", "Master" }
ns.RANK_CAP = { 75, 150, 225, 300, 375 }

-- The other kinds of trainer, with their icons
ns.KINDS = {
	weapon = { "Weapon masters", "Interface\\Icons\\INV_Sword_04" },
	riding = { "Riding trainers", "Interface\\Icons\\Ability_Mount_RidingHorse" },
	pet = { "Pet trainers", "Interface\\Icons\\Ability_Hunter_BeastTraining" },
	portal = { "Portal trainers", "Interface\\Icons\\Spell_Arcane_PortalStormWind" },
	other = { "Other trainers", "Interface\\Icons\\INV_Misc_Book_09" },
}

-- A selection is a string: "all", "class:MAGE", "prof:171", "weapon", "riding", "pet", "portal", "other"
function ns.SelectionName(sel)
	if sel == "all" then return "All trainers" end
	local kind, key = sel:match("^(%a+):(.+)$")
	if kind == "class" then
		local names = LOCALIZED_CLASS_NAMES_MALE
		local c = ns.CLASS_BY_TOKEN[key]
		return ((names and names[key]) or (c and c[3]) or key) .. " trainers"
	elseif kind == "prof" then
		local p = ns.SKILL[tonumber(key)]
		return p and (p[2] .. " trainers") or "Trainers"
	end
	local k = ns.KINDS[sel]
	return k and k[1] or "Trainers"
end

-- What a trainer's entry for one selection says, or nil when it doesn't teach that
function ns.TeachFor(trainer, sel)
	for _, t in ipairs(trainer.teach) do
		if sel == "all" then return t end
		if t[1] == "class" and sel == "class:" .. t[2] then return t end
		if t[1] == "prof" and sel == "prof:" .. t[2] then return t end
		if t[1] == sel then return t end
	end
end

function ns.IconFor(teach)
	if not teach then return nil end
	if teach[1] == "class" then return nil, "classicon-" .. teach[2]:lower() end
	if teach[1] == "prof" then
		local p = ns.SKILL[teach[2]]
		return p and p[3] or ns.KINDS.other[2]
	end
	local k = ns.KINDS[teach[1]]
	return k and k[2] or ns.KINDS.other[2]
end

---------------------------------------------------------------- the player
ns.player = { side = 0, class = nil, level = 1 }

function ns.RefreshPlayer()
	local p = ns.player
	local group = UnitFactionGroup("player")
	if group and not secret(group) then
		p.side = (group == "Alliance" and 1) or (group == "Horde" and 2) or 0
	end
	local _, token = UnitClass("player")
	if token and not secret(token) then p.class = token end
	local level = UnitLevel("player")
	if type(level) == "number" and not secret(level) then p.level = level end
end

-- Whether a trainer will talk to you: friendly or neutral to your faction
function ns.Usable(trainer)
	local side = ns.player.side
	if side == 0 then return true end
	return bit.band(trainer.side, side) ~= 0
end

-- Forever's reworked profession skill lines, beside the originals the data uses
local REWORKED = { [171] = 2937, [164] = 2938, [185] = 2939, [333] = 2940, [202] = 2941, [129] = 2942, [356] = 2943,
	[182] = 2944, [165] = 2945, [186] = 2946, [393] = 2947, [197] = 2948 }

-- Your skill in a profession: rank, max. Nil when you don't have it.
function ns.ProfessionSkill(skillLine)
	local p = ns.SKILL[skillLine]
	if not p then return nil end
	local info = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
	if info then
		for _, id in ipairs({ skillLine, REWORKED[skillLine] }) do
			local ok, d = pcall(info, id)
			if ok and type(d) == "table" and d.maxRank and d.maxRank > 0 and not secret(d.rank) then return d.rank, d.maxRank end
		end
		return nil
	end
	if GetProfessions and GetProfessionInfo then
		local list = { GetProfessions() }
		for i = 1, 6 do
			local index = list[i]
			if index then
				local name, _, rank, maxRank, _, _, line = GetProfessionInfo(index)
				if line == skillLine or line == REWORKED[skillLine] or name == p[2] then return rank, maxRank end
			end
		end
	end
end

-- Whether you know a spell (a weapon skill)
function ns.Knows(spellID)
	if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(spellID) end
	return IsPlayerSpell and IsPlayerSpell(spellID) or false
end

-- The rank (1 Apprentice .. 5 Master) a skill cap stands for
function ns.RankOfCap(maxRank)
	for i, cap in ipairs(ns.RANK_CAP) do
		if maxRank <= cap then return i end
	end
	return #ns.RANK_CAP
end

---------------------------------------------------------------- maps and distances
-- x, y of a map position. The client hands some back as Vector2D objects and some (the user
-- waypoint's) as plain { x, y } tables, so read either.
function ns.XY(v)
	if type(v) ~= "table" and type(v) ~= "userdata" then return nil end
	if type(v.GetXY) == "function" then return v:GetXY() end
	return v.x, v.y
end

-- Zone names from the client (localized), the data's English names otherwise
function ns.MapName(mapID)
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	if info and info.name and info.name ~= "" then return info.name end
	local m = ns.Data.maps[mapID]
	return m and m[1] or ("Map " .. mapID)
end

-- A map's parent and type, from the data or else the client (for where you are: an instance, a
-- zone no trainer stands in)
local function MapParent(mapID)
	local m = ns.Data.maps[mapID]
	if m then return m[2], m[3] end
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
	if info then return info.parentMapID, info.mapType end
end

-- The continent a zone is on (a zone of its own, like Zephras Isle, is its own group)
function ns.ContinentOf(mapID)
	local id = mapID
	for _ = 1, 8 do
		local parent, kind = MapParent(id)
		if kind == 2 then return id end
		if not parent or parent == 0 or parent == 947 then return id end
		id = parent
	end
	return id
end

-- World position of a spot, cached: continent (instance) id, x, y in yards
local worldCache = {}
function ns.WorldPos(mapID, x, y)
	local key = mapID * 1e8 + math.floor(x * 10 + 0.5) * 1e4 + math.floor(y * 10 + 0.5)
	local cached = worldCache[key]
	if cached == nil then
		cached = false
		if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
			local ok, instance, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x / 100, y / 100))
			if ok and instance and pos and not secret(instance) then
				local wx, wy = ns.XY(pos)
				if not secret(wx) then cached = { instance, wx, wy } end
			end
		end
		worldCache[key] = cached
	end
	if cached then return cached[1], cached[2], cached[3] end
end

-- Where you are: the map you're on, x and y on it (0-100), and your world position. Nothing in
-- places the client keeps to itself (instances hide the player's position).
function ns.PlayerPos()
	if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID or secret(mapID) then return nil end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return mapID end
	local x, y = ns.XY(pos)
	if not x or secret(x) then return mapID end
	x, y = x * 100, y * 100
	local instance, wx, wy = ns.WorldPos(mapID, x, y)
	return mapID, x, y, instance, wx, wy
end

-- Yards from you to a trainer's nearest spawn, and that spawn; nil when it's on another continent
function ns.Distance(trainer, here)
	if not here or not here.instance then return nil end
	local best, bestSpawn
	for _, s in ipairs(trainer.at) do
		local instance, wx, wy = ns.WorldPos(s[1], s[2], s[3])
		if instance == here.instance then
			local d = math.sqrt((wx - here.wx) ^ 2 + (wy - here.wy) ^ 2)
			if not best or d < best then best, bestSpawn = d, s end
		end
	end
	return best, bestSpawn
end

---------------------------------------------------------------- the list
-- Everything the window and the map show for a selection: trainers grouped by continent, the
-- nearest first, and the groups ordered with yours first
function ns.Query(sel, search, showOther)
	local mapID, _, _, instance, wx, wy = ns.PlayerPos()
	local here = { mapID = mapID, instance = instance, wx = wx, wy = wy }
	here.continent = mapID and ns.ContinentOf(mapID)
	local needle = search and search ~= "" and search:lower() or nil
	local groups, byKey, total, nearest = {}, {}, 0, nil
	for _, t in ipairs(ns.Data.trainers) do
		local teach = ns.TeachFor(t, sel)
		local usable = ns.Usable(t)
		if teach and (usable or showOther) then
			local spawn = t.at[1]
			local zone = ns.MapName(spawn[1])
			local ok = true
			if needle then
				local hay = (t.name .. "\n" .. (t.tag or "") .. "\n" .. zone):lower()
				ok = hay:find(needle, 1, true) ~= nil
			end
			if ok then
				local dist, near = ns.Distance(t, here)
				if near then spawn = near; zone = ns.MapName(spawn[1]) end
				local cont = ns.ContinentOf(spawn[1])
				local g = byKey[cont]
				if not g then
					g = { key = cont, name = ns.MapName(cont), rows = {}, mine = cont == here.continent }
					byKey[cont] = g
					table.insert(groups, g)
				end
				local row = { trainer = t, teach = teach, spawn = spawn, zone = zone, dist = dist, usable = usable }
				row.fit, row.note = ns.Fit(t, teach)
				table.insert(g.rows, row)
				total = total + 1
				if usable and row.fit and dist and (not nearest or dist < nearest.dist) then nearest = row end
			end
		end
	end
	for _, g in ipairs(groups) do
		table.sort(g.rows, function(a, b)
			if a.dist and b.dist then return a.dist < b.dist end
			if a.dist or b.dist then return a.dist ~= nil end
			if a.zone ~= b.zone then return a.zone < b.zone end
			return a.trainer.name < b.trainer.name
		end)
	end
	table.sort(groups, function(a, b)
		if a.mine ~= b.mine then return a.mine end
		return a.name < b.name
	end)
	return { groups = groups, total = total, nearest = nearest, here = here }
end

-- Whether a trainer has something for you, and a note when it doesn't: a class trainer whose
-- spells stop below your level, a profession trainer who can't take you past your rank
function ns.Fit(trainer, teach)
	local p = ns.player
	if teach[1] == "class" then
		if p.class == teach[2] and teach.max and p.level > teach.max + 1 and teach.max < 60 then
			return false, "only teaches up to level " .. teach.max
		end
	elseif teach[1] == "prof" and teach.rank then
		local skill, maxSkill = ns.ProfessionSkill(teach[2])
		if skill and maxSkill and maxSkill > 0 then
			local mine = ns.RankOfCap(maxSkill)
			if teach.rank <= mine and skill >= maxSkill - 25 then
				return false, "can't train you past " .. ns.RANKS[mine]
			end
		end
	end
	return true
end

---------------------------------------------------------------- saved variables
local DEFAULTS = {
	point = nil,           -- where the window sits
	size = nil,            -- { width, height } once resized
	scale = 1,
	mapPins = true,        -- show the selection on the world map
	openMap = true,        -- open the map at a trainer when you set a waypoint
	showOther = false,     -- include the other faction's trainers
	minimapButton = true,  -- the button on the minimap's edge
	minimapAngle = 225,    -- where on the edge, in degrees (225 is bottom left)
}
local CHAR_DEFAULTS = {
	selection = nil,       -- the last category picked
	collapsed = {},        -- continent groups folded away
}

local function Fill(db, defaults)
	for k, v in pairs(defaults) do
		if db[k] == nil then db[k] = type(v) == "table" and {} or v end
	end
end

function ns.DefaultSelection()
	local class = ns.player.class
	if class and ns.CLASS_BY_TOKEN[class] then return "class:" .. class end
	return "all"
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		TrainerLocatorDB = TrainerLocatorDB or {}
		TrainerLocatorCharDB = TrainerLocatorCharDB or {}
		ns.db, ns.char = TrainerLocatorDB, TrainerLocatorCharDB
		Fill(ns.db, DEFAULTS)
		Fill(ns.char, CHAR_DEFAULTS)
	elseif event == "PLAYER_LOGIN" then
		ns.RefreshPlayer()
		if ns.RegisterOptions then ns.RegisterOptions() end
		if ns.Pins then ns.Pins.Register() end
		if ns.MinimapButton then ns.MinimapButton.Create() end
	elseif event == "PLAYER_LEVEL_UP" then
		ns.RefreshPlayer()
		if type(arg1) == "number" then ns.player.level = arg1 end
		if ns.UI then ns.UI.RefreshIfShown() end
	else
		if ns.UI then ns.UI.RefreshIfShown() end
	end
end)

---------------------------------------------------------------- waypoints
-- Puts the game's map pin (and its arrow in the world) on a trainer, and TomTom's too when it's
-- installed. Opens the map there unless the player turned that off.
function ns.SetWaypoint(trainer, spawn)
	spawn = spawn or trainer.at[1]
	local mapID, x, y = spawn[1], spawn[2], spawn[3]
	local placed = false
	if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) and UiMapPoint then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
		placed = true
	end
	if TomTom and TomTom.AddWaypoint then
		TomTom:AddWaypoint(mapID, x / 100, y / 100, { title = trainer.name, from = "Trainer Locator" })
		placed = true
	end
	ns.PlaySound("UI_MAP_WAYPOINT_CLICK_TO_PLACE")
	ns.Print(string.format("%s, %s %s", ns.Paint("white", trainer.name), ns.MapName(mapID), ns.Coords(spawn)))
	if ns.db.openMap and OpenWorldMap then OpenWorldMap(mapID) end
	if ns.Pins then ns.Pins.Refresh() end
	return placed
end

function ns.Coords(spawn) return string.format("%.1f, %.1f", spawn[2], spawn[3]) end

-- A chat link to the spot: the game's map pin link when it can make one
function ns.LinkWaypoint(trainer, spawn)
	spawn = spawn or trainer.at[1]
	local link
	if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(spawn[1]) and C_Map.GetUserWaypointHyperlink then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(spawn[1], spawn[2] / 100, spawn[3] / 100))
		link = C_Map.GetUserWaypointHyperlink()
	end
	local text = trainer.name .. " " .. (link or (ns.MapName(spawn[1]) .. " " .. ns.Coords(spawn)))
	-- into the chat line being typed, or a new one opened with it
	local util = ChatFrameUtil
	local insert = util and util.InsertLink or ChatEdit_InsertLink
	local open = util and util.OpenChat or ChatFrame_OpenChat
	if insert and insert(text) then return true end
	if open then open(text) end
	return true
end

---------------------------------------------------------------- slash commands
SLASH_TRAINERLOCATOR1 = "/trainers"
SLASH_TRAINERLOCATOR2 = "/tl"
SlashCmdList.TRAINERLOCATOR = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "options" or msg == "config" then
		ns.OpenOptions()
	elseif msg == "minimap" then
		local shown = ns.MinimapButton.Toggle()
		ns.Print(shown and "Minimap button shown. Drag it to move it around the minimap." or
			"Minimap button hidden. /trainers minimap brings it back.")
	elseif msg == "help" then
		ns.Print("/trainers opens the window. /trainers <search> opens it searching, like /trainers alchemy. /trainers options opens the settings. /trainers minimap shows or hides the minimap button.")
	elseif msg == "" then
		ns.UI.Toggle()
	else
		ns.UI.OpenSearch(msg)
	end
end

-- The minimap's addon menu and the key binding
function TrainerLocator_Toggle() ns.UI.Toggle() end
function TrainerLocator_OnAddonCompartmentClick() ns.UI.Toggle() end
BINDING_HEADER_TRAINERLOCATOR = "Trainer Locator"
BINDING_NAME_TRAINERLOCATOR_TOGGLE = "Open Trainer Locator"
