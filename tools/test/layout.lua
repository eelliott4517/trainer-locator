-- Resolves the mock's anchors into screen rectangles and lists everything preview.py draws, the way
-- the game orders it: strata, then frame level, then draw layer, then creation order.
-- Rectangles are { left, top, right, bottom } in screen pixels with y going down.
local L = {}

local SCREEN_W, SCREEN_H = 1920, 1080
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, TOOLTIP = 7 }
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local cache = {}

local function Size(r)
	local w, h = r._w, r._h
	if r._kind == "FontString" then
		if not w or w == 0 then w = r:GetStringWidth() end
		if not h or h == 0 then h = r:GetStringHeight() end
	end
	return w, h
end

local Rect
local function Coord(rel, point)
	local x0, y0, x1, y1 = Rect(rel)   -- left, bottom, right, top (y up)
	local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	local px = point:find("LEFT") and x0 or (point:find("RIGHT") and x1 or cx)
	local py = point:find("TOP") and y1 or (point:find("BOTTOM") and y0 or cy)
	return px, py
end

function Rect(r)
	if r == UIParent then return 0, 0, SCREEN_W, SCREEN_H end
	if cache[r] then return unpack(cache[r]) end
	cache[r] = { 0, 0, 0, 0 } -- guards cycles
	local left, right, top, bottom, cx, cy
	local points = r._points or {}
	if #points == 0 and r._parent and r._parent._child == r then
		-- a scroll child sits at its scroll frame's top left, moved up by the scroll
		local sx0, _, _, sy1 = Rect(r._parent)
		left, top = sx0, sy1 + (r._parent._scroll or 0)
	end
	for _, p in ipairs(points) do
		local point, rel, relPoint, x, y = p[1], p[2], p[3], p[4], p[5]
		local px, py = Coord(rel, relPoint)
		px, py = px + x, py + y
		if point:find("LEFT") then left = px elseif point:find("RIGHT") then right = px else cx = px end
		if point:find("TOP") then top = py elseif point:find("BOTTOM") then bottom = py else cy = py end
	end
	local w, h = Size(r)
	w, h = w or 0, h or 0
	if left and right then w = right - left end
	if top and bottom then h = top - bottom end
	if not left then left = right and (right - w) or (cx and (cx - w / 2)) or 0 end
	if not right then right = left + w end
	if not top then top = bottom and (bottom + h) or (cy and (cy + h / 2)) or 0 end
	if not bottom then bottom = top - h end
	cache[r] = { left, bottom, right, top }
	return left, bottom, right, top
end

-- A region's rectangle, y down
local function Box(r)
	local x0, y0, x1, y1 = Rect(r)
	return { x0, SCREEN_H - y1, x1, SCREEN_H - y0 }
end
L.Box = function(r) cache = {}; return Box(r) end
function MOCK.RegionHeight(r) cache = {}; local _, y0, _, y1 = Rect(r); return y1 - y0 end

local function Visible(r)
	while r do
		if r._shown == false then return false end
		r = r._parent
	end
	return true
end

local function Descends(r, root)
	while r do
		if r == root then return true end
		r = r._parent
	end
	return false
end

local levels, stratas = {}, {}
local function Level(f)
	if levels[f] then return levels[f] end
	local l = f._level or ((f._parent and f._parent ~= UIParent) and (Level(f._parent) + 1) or 1)
	levels[f] = l
	return l
end
local function Strata(f)
	if stratas[f] then return stratas[f] end
	local s = f._strata or ((f._parent and f._parent ~= UIParent) and Strata(f._parent) or "MEDIUM")
	stratas[f] = s
	return s
end
local function Alpha(f)
	local a = 1
	while f do
		a = a * (f._alpha or 1)
		f = f._parent
	end
	return a
end
local function ClipOf(f)
	while f do
		if f._kind == "ScrollFrame" then return Box(f) end
		f = f._parent
	end
end

-- Everything visible under the roots, as drawable items
function L.Dump(roots, hovered)
	cache, levels, stratas = {}, {}, {}
	local out, order = {}, 0
	local function Under(f)
		for _, root in ipairs(roots) do if Descends(f, root) then return true end end
	end
	local function Add(item, f, layer)
		order = order + 1
		item.strata, item.level, item.layer, item.order = STRATA[Strata(f)], Level(f), LAYERS[layer] or 3, order
		item.clip = ClipOf(f._kind == "ScrollFrame" and f._parent or f)
		table.insert(out, item)
	end
	for _, f in ipairs(MOCK.frames) do
		if Under(f) and Visible(f) then
			local alpha = Alpha(f)
			if f.layoutType then
				Add({ kind = "nineslice", layout = f.layoutType, box = Box(f), alpha = alpha }, f, "OVERLAY")
			end
			local lit = hovered == f or f._highlightLocked
			for _, t in ipairs(f._textures or {}) do
				local checkedOnly = t._whenChecked and not f._checked
				if t._shown and not checkedOnly and (t._layer ~= "HIGHLIGHT" or lit) and (t._atlas or t._file or t._color) then
					Add({ kind = "texture", box = Box(t), atlas = t._atlas, file = t._file, color = t._color, vcolor = t._vcolor,
						alpha = alpha * (t._alpha or 1), blend = t._blend, desaturated = t._desaturated, coords = t._coords,
						htile = t._htile, vtile = t._vtile, circle = t._circleMask, mask = t._mask,
						maskBox = t._mask and Box(t._parent) or nil }, f, t._layer)
				end
			end
			for _, fs in ipairs(f._fontstrings or {}) do
				if fs._shown and fs._text and fs._text ~= "" then
					Add({ kind = "text", box = Box(fs), text = fs._text, font = fs._font, color = fs._color, justify = fs._justify,
						wrap = fs._wrap ~= false and (fs._w and fs._w > 0 or (#(fs._points or {}) >= 2)) or false,
						spacing = fs._spacing or 0, alpha = alpha }, f, fs._layer)
				end
			end
			-- an edit box draws what's typed in it, past its search icon
			if f._kind == "EditBox" and (f._text or "") ~= "" then
				local b = Box(f)
				Add({ kind = "text", box = { b[1] + 16, b[2], b[3] - 20, b[4] }, text = f._text, font = f._textFont or "GameFontHighlightSmall",
					justify = "LEFT", wrap = false, spacing = 0, alpha = alpha, vcenter = true }, f, "OVERLAY")
			end
			-- the scroll bar's thumb follows the scroll
			if f._thumbOf then
				local sf = f._thumbOf
				local track = Box(f._parent)
				local view = Box(sf)
				local contentH = sf._child and sf._child:GetHeight() or 0
				local viewH = view[4] - view[2]
				if contentH > viewH + 0.5 then
					local trackH = track[4] - track[2]
					local extent = math.max(23, trackH * viewH / contentH)
					local range = contentH - viewH
					local y = track[2] + (trackH - extent) * math.min(1, (sf._scroll or 0) / range)
					Add({ kind = "thumb", box = { track[1], y, track[3], y + extent }, alpha = alpha }, f, "ARTWORK")
				end
			end
		end
	end
	return out
end

-- Scroll bars with nothing to scroll hide themselves (SetHideIfUnscrollable)
function L.HideIdleScrollBars()
	for _, f in ipairs(MOCK.frames) do
		if f._kind == "ScrollFrame" and f.ScrollBar and f.ScrollBar.hideIfUnscrollable then
			cache = {}
			local view = Box(f)
			local contentH = f._child and f._child:GetHeight() or 0
			f.ScrollBar._shown = contentH > (view[4] - view[2]) + 0.5
		end
	end
end

return L
