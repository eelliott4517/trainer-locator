-- Trainer Locator: its page in the game's options (Options > AddOns > Trainer Locator), built with
-- Blizzard's Settings API so it looks and behaves like every other page there.
local _, ns = ...

local category

local TOGGLES = {
	{ "mapPins", "TRAINERLOCATOR_MAP_PINS", "Show trainers on the world map",
		"Marks the trainers the window lists on the world map, for the kind you picked." },
	{ "openMap", "TRAINERLOCATOR_OPEN_MAP", "Open the map at a trainer",
		"Clicking a trainer opens the world map where they are, as well as putting the map pin on them." },
	{ "showOther", "TRAINERLOCATOR_SHOW_OTHER", "List the other faction's trainers",
		"Also lists trainers who won't talk to you, greyed out." },
}

function ns.RegisterOptions()
	if category or not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting
		and Settings.CreateCheckbox and Settings.RegisterAddOnCategory) then return end
	local cat = Settings.RegisterVerticalLayoutCategory("Trainer Locator")
	for _, t in ipairs(TOGGLES) do
		local key = t[1]
		local setting = Settings.RegisterProxySetting(cat, t[2], Settings.VarType.Boolean, t[3],
			key == "showOther" and Settings.Default.False or Settings.Default.True,
			function() return ns.db[key] and true or false end,
			function(value)
				ns.db[key] = value and true or false
				ns.UI.RefreshIfShown()
				if ns.Pins then ns.Pins.Refresh() end
			end)
		Settings.CreateCheckbox(cat, setting, t[4])
	end
	if Settings.CreateSlider and Settings.CreateSliderOptions then
		local setting = Settings.RegisterProxySetting(cat, "TRAINERLOCATOR_SCALE", Settings.VarType.Number, "Window scale", 1,
			function() return ns.db.scale or 1 end,
			function(value) ns.UI.SetScale(math.floor(value * 100 + 0.5) / 100) end)
		local options = Settings.CreateSliderOptions(0.6, 1.6, 0.05)
		if options.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
				return string.format("%d%%", value * 100 + 0.5)
			end)
		end
		Settings.CreateSlider(cat, setting, options, "Makes the window and its text bigger or smaller. Drag its bottom-right corner to change its size.")
	end
	Settings.RegisterAddOnCategory(cat)
	category = cat
end

function ns.OpenOptions()
	if not category then
		ns.Print("The game's options aren't available here.")
	elseif InCombatLockdown and InCombatLockdown() then
		ns.Print("The options open once you're out of combat.")
	else
		Settings.OpenToCategory(category:GetID())
	end
end
