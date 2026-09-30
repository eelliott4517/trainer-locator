-- Trainer Locator: pins on the world map for the trainers the window lists. A map data provider,
-- the way Blizzard's own map pins are made, so they zoom, scale and click like theirs.
local _, ns = ...

local Pins = {}
ns.Pins = Pins

local TEMPLATE = "TrainerLocatorPinTemplate"
local provider

TrainerLocatorPinMixin = CreateFromMixins and CreateFromMixins(MapCanvasPinMixin or {}) or {}

function TrainerLocatorPinMixin:OnLoad()
	if self.UseFrameLevelType then self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI") end
	if self.SetScalingLimits then self:SetScalingLimits(1, 1.0, 1.2) end
end

function TrainerLocatorPinMixin:OnAcquired(row, x, y)
	self.row = row
	self:SetSize(20, 20)
	ns.UI.SetIcon(self.Icon, row.teach)
	self.Icon:SetDesaturated((not row.usable or not row.fit) and true or false)
	self:SetPosition(x, y)
end

function TrainerLocatorPinMixin:OnMouseEnter()
	if self.row then ns.UI.TrainerTooltip(self, self.row, "ANCHOR_RIGHT") end
end

function TrainerLocatorPinMixin:OnMouseLeave() GameTooltip:Hide() end

function TrainerLocatorPinMixin:OnMouseClickAction(button)
	local row = self.row
	if not row or button ~= "LeftButton" then return end
	if IsShiftKeyDown and IsShiftKeyDown() then
		ns.LinkWaypoint(row.trainer, self.spawn or row.spawn)
	else
		-- the map is already open where the player is looking; don't jump it
		local open = ns.db.openMap
		ns.db.openMap = false
		ns.SetWaypoint(row.trainer, self.spawn or row.spawn)
		ns.db.openMap = open
		ns.UI.RefreshIfShown()
	end
end

-- Where a spot lands on the map being shown: the same map, or one above or beside it that covers
-- the spot (a city on its zone's map, a zone on the continent's)
local function OnMap(viewMapID, spawn)
	if spawn[1] == viewMapID then return spawn[2] / 100, spawn[3] / 100 end
	local instance, wx, wy = ns.WorldPos(spawn[1], spawn[2], spawn[3])
	if not instance or not (C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
	local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, instance, CreateVector2D(wx, wy), viewMapID)
	if not ok or not pos then return nil end
	local x, y = ns.XY(pos)
	if x and x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

local function NewProvider()
	local p = CreateFromMixins(MapCanvasDataProviderMixin)
	function p:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
	end
	function p:RefreshAllData()
		self:RemoveAllData()
		if not ns.db or not ns.db.mapPins then return end
		local mapID = self:GetMap():GetMapID()
		if not mapID then return end
		local info = C_Map.GetMapInfo(mapID)
		-- zone and city maps only: a continent full of icons helps no one
		if info and info.mapType and Enum and Enum.UIMapType and info.mapType < Enum.UIMapType.Zone then return end
		local result = ns.Query(ns.UI.Selection(), ns.UI.searchText, ns.db.showOther)
		for _, g in ipairs(result.groups) do
			for _, row in ipairs(g.rows) do
				for _, spawn in ipairs(row.trainer.at) do
					local x, y = OnMap(mapID, spawn)
					if x then
						local pin = self:GetMap():AcquirePin(TEMPLATE, row, x, y)
						pin.spawn = spawn
					end
				end
			end
		end
	end
	return p
end

function Pins.Register()
	if provider or not (WorldMapFrame and WorldMapFrame.AddDataProvider and MapCanvasDataProviderMixin) then return end
	provider = NewProvider()
	WorldMapFrame:AddDataProvider(provider)
end

function Pins.Refresh()
	if provider and provider:GetMap() and WorldMapFrame:IsShown() then provider:RefreshAllData() end
end
