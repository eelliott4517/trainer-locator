-- The rest of the API Trainer Locator uses, mocked from WoW: Forever 1.60.1's own tables: C_Map with
-- the real map bounds (UiMap and UiMapAssignment from wago.tools, in tools/data/db2), so distances
-- and map-to-map positions come out as in the game; user waypoints and super tracking; the world
-- map's data providers and pins; professions, known spells and the chat edit box.
local DIR = ...

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

local function ReadCSV(path)
	local rows, header = {}, nil
	for line in io.lines(path) do
		local fields, i = {}, 1
		-- quoted names ("The Barrens") may hold commas
		line = line:gsub('"([^"]*)"', function(q) return (q:gsub(",", "\1")) end)
		for f in (line .. ","):gmatch("([^,]*),") do fields[i] = f:gsub("\1", ","); i = i + 1 end
		if not header then header = fields else
			local r = {}
			for k, name in ipairs(header) do r[name] = fields[k] end
			table.insert(rows, r)
		end
	end
	return rows
end

MOCK.maps = {}   -- [uiMapID] = { name, parent, type, instance, minX, minY, maxX, maxY }
for _, r in ipairs(ReadCSV(DIR .. "/data/db2/UiMap.csv")) do
	if r.System == "0" then
		MOCK.maps[tonumber(r.ID)] = { name = r.Name_lang, parent = tonumber(r.ParentUiMapID), type = tonumber(r.Type) }
	end
end
for _, r in ipairs(ReadCSV(DIR .. "/data/db2/UiMapAssignment.csv")) do
	local m = MOCK.maps[tonumber(r.UiMapID)]
	-- the whole-map assignment (0,0 to 1,1) gives the world rectangle the map shows
	if m and r.UiMin_0 == "0" and r.UiMin_1 == "0" and r.UiMax_0 == "1" and r.UiMax_1 == "1" and not m.instance then
		m.instance = tonumber(r.MapID)
		m.minX, m.minY, m.maxX, m.maxY = tonumber(r.Region_0), tonumber(r.Region_1), tonumber(r.Region_3), tonumber(r.Region_4)
	end
end

MOCK.pos = { 1453, 0.5, 0.5 }   -- where the player is: map, x, y (0-1); nil in an instance
MOCK.classToken = "MAGE"
MOCK.professions = {}            -- { name, skill, max, skillLine }
MOCK.knownSpells = {}
MOCK.waypoint = nil
MOCK.superTracked = false
MOCK.openedMap = nil
MOCK.shift = false
MOCK.linked = {}

---------------------------------------------------------------- vectors and mixins
local Vector2D = {}
Vector2D.__index = Vector2D
function Vector2D:GetXY() return self.x, self.y end
function CreateVector2D(x, y)
	assert(finite(x) and finite(y), "CreateVector2D wants numbers")
	return setmetatable({ x = x, y = y }, Vector2D)
end

function CreateFromMixins(...)
	local t = {}
	for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end
	return t
end
function Mixin(obj, ...)
	for _, m in ipairs({ ... }) do for k, v in pairs(m) do obj[k] = v end end
	return obj
end

UiMapPoint = {
	CreateFromCoordinates = function(mapID, x, y)
		assert(type(mapID) == "number" and finite(x) and finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1, "bad UiMapPoint")
		return { uiMapID = mapID, position = CreateVector2D(x, y) }
	end,
}

Enum = Enum or {}
Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }

---------------------------------------------------------------- C_Map
-- A map's x runs west to east (world y falling), its y north to south (world x falling)
local function ToWorld(m, x, y)
	return m.maxX - y * (m.maxX - m.minX), m.maxY - x * (m.maxY - m.minY)
end
local function ToMap(m, wx, wy)
	return (m.maxY - wy) / (m.maxY - m.minY), (m.maxX - wx) / (m.maxX - m.minX)
end

C_Map = {
	GetBestMapForUnit = function(u) assert(u == "player"); return MOCK.pos and MOCK.pos[1] or nil end,
	GetPlayerMapPosition = function(mapID, u)
		assert(type(mapID) == "number" and u == "player")
		local p = MOCK.pos
		if not p then return nil end
		if p.secret then return { GetXY = function() return MOCK.Secret(), MOCK.Secret() end } end
		if mapID == p[1] then return CreateVector2D(p[2], p[3]) end
		local from, to = MOCK.maps[p[1]], MOCK.maps[mapID]
		local wx, wy = ToWorld(from, p[2], p[3])
		return CreateVector2D(ToMap(to, wx, wy))
	end,
	GetMapInfo = function(id)
		assert(type(id) == "number", "GetMapInfo wants a map id")
		local m = MOCK.maps[id]
		if not m then return nil end
		return { mapID = id, name = m.name, mapType = m.type, parentMapID = m.parent }
	end,
	GetWorldPosFromMapPos = function(mapID, pos)
		assert(type(mapID) == "number" and getmetatable(pos) == Vector2D, "GetWorldPosFromMapPos(mapID, vector)")
		local m = MOCK.maps[mapID]
		if not m or not m.instance then return nil end
		local wx, wy = ToWorld(m, pos.x, pos.y)
		return m.instance, CreateVector2D(wx, wy)
	end,
	GetMapPosFromWorldPos = function(instance, pos, mapID)
		assert(type(instance) == "number" and getmetatable(pos) == Vector2D and type(mapID) == "number")
		local m = MOCK.maps[mapID]
		if not m or m.instance ~= instance then return nil end
		return mapID, CreateVector2D(ToMap(m, pos.x, pos.y))
	end,
	GetAreaInfo = function() return nil end,
	CanSetUserWaypointOnMap = function(mapID) assert(type(mapID) == "number"); return MOCK.maps[mapID] ~= nil and MOCK.maps[mapID].type >= 3 end,
	SetUserWaypoint = function(point)
		assert(type(point) == "table" and point.uiMapID and point.position, "SetUserWaypoint wants a UiMapPoint")
		-- Forever hands the waypoint back with a plain { x, y } position, not a Vector2D
		MOCK.waypoint = { uiMapID = point.uiMapID, position = { x = point.position.x, y = point.position.y } }
		MOCK.Fire("USER_WAYPOINT_UPDATED")
	end,
	HasUserWaypoint = function() return MOCK.waypoint ~= nil end,
	GetUserWaypoint = function() return MOCK.waypoint end,
	ClearUserWaypoint = function() MOCK.waypoint = nil; MOCK.superTracked = false end,
	GetUserWaypointHyperlink = function()
		local w = MOCK.waypoint
		return w and string.format("|cffffff00|Hworldmap:%d:%d:%d|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r",
			w.uiMapID, w.position.x * 10000, w.position.y * 10000)
	end,
}
C_SuperTrack = {
	SetSuperTrackedUserWaypoint = function(on) assert(type(on) == "boolean"); MOCK.superTracked = on end,
}

function OpenWorldMap(mapID)
	assert(mapID == nil or type(mapID) == "number")
	MOCK.openedMap = mapID
	WorldMapFrame:SetMapID(mapID)
	WorldMapFrame:Show()
end

---------------------------------------------------------------- the world map
MapCanvasDataProviderMixin = {}
function MapCanvasDataProviderMixin:OnAdded(map) self.owningMap = map end
function MapCanvasDataProviderMixin:GetMap() return self.owningMap end
function MapCanvasDataProviderMixin:RemoveAllData() end
function MapCanvasDataProviderMixin:RefreshAllData() end
function MapCanvasDataProviderMixin:OnMapChanged() self:RefreshAllData() end

MapCanvasPinMixin = {}
function MapCanvasPinMixin:OnLoad() end
function MapCanvasPinMixin:OnAcquired() end
function MapCanvasPinMixin:UseFrameLevelType(t) assert(type(t) == "string"); self._levelType = t end
function MapCanvasPinMixin:SetScalingLimits(a, b, c) assert(finite(a) and finite(b) and finite(c)) end
function MapCanvasPinMixin:SetPosition(x, y)
	assert(finite(x) and finite(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1, "pin position out of the map")
	self._x, self._y = x, y
end
function MapCanvasPinMixin:GetPosition() return self._x, self._y end
function MapCanvasPinMixin:GetMap() return WorldMapFrame end

WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame:Hide()
WorldMapFrame._providers, WorldMapFrame._pins = {}, {}
function WorldMapFrame:AddDataProvider(p)
	table.insert(self._providers, p)
	p:OnAdded(self)
end
function WorldMapFrame:GetMapID() return self._mapID end
function WorldMapFrame:SetMapID(id)
	self._mapID = id
	for _, p in ipairs(self._providers) do p:RefreshAllData() end
end
function WorldMapFrame:AcquirePin(template, ...)
	-- the template has to be one the addon's XML makes
	local spec = MOCK.TEMPLATES[template]
	assert(spec and spec.pin, "AcquirePin: " .. tostring(template) .. " isn't a pin template")
	local pin = CreateFrame("Frame", nil, self, template)
	pin.pinTemplate = template
	pin:OnAcquired(...)
	table.insert(self._pins, pin)
	return pin
end
function WorldMapFrame:RemoveAllPinsByTemplate(template)
	local keep = {}
	for _, pin in ipairs(self._pins) do
		if pin.pinTemplate == template then pin:Hide() else table.insert(keep, pin) end
	end
	self._pins = keep
end
function MOCK.Pins() return WorldMapFrame._pins end
-- What opening the map at a zone does: the providers fill it
function MOCK.ShowMap(mapID)
	WorldMapFrame:Show()
	WorldMapFrame:SetMapID(mapID)
end

---------------------------------------------------------------- the player
function UnitClass(u) assert(u == "player"); return "Class", MOCK.classToken, 8 end
LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
-- C_SkillInfo: one table per skill line the character has
C_SkillInfo = {
	GetSkillLineInfoByID = function(id)
		assert(type(id) == "number", "GetSkillLineInfoByID wants a skill line id")
		for _, p in ipairs(MOCK.professions) do
			if p[4] == id then
				return { skillID = id, name = p[1], isHeader = false, rank = p[2], maxRank = p[3], skillLineCategoryID = 11 }
			end
		end
		return nil
	end,
}
C_SpellBook = { IsSpellKnown = function(id, bank) assert(type(id) == "number" and bank == nil); return MOCK.knownSpells[id] == true end }
function IsShiftKeyDown() return MOCK.shift end
ChatFrameUtil = {
	-- false when no chat line is open, as in the game
	InsertLink = function(text) assert(type(text) == "string"); if MOCK.chatOpen then table.insert(MOCK.linked, text); return true end; return false end,
	OpenChat = function(text) assert(type(text) == "string"); MOCK.chatOpen = true; table.insert(MOCK.linked, text) end,
}

SOUNDKIT.UI_MAP_WAYPOINT_CLICK_TO_PLACE = 169065
SOUNDKIT.UI_MAP_WAYPOINT_REMOVE = 169066
SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF = 857

bit = bit or {}
bit.band = bit.band or function(a, b)
	local r, m = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then r = r + m end
		a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
	end
	return r
end
