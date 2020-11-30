local mod = get_mod("BotImprovements_Combat")

return {
	name = "Bot Improvements - Combat",               -- Readable mod name
	description = "A set of various tweaks to empower the fighting capabilities of bots in a fair manner.",  -- Mod description
	is_togglable = false,            -- If the mod can be enabled/disabled
	options_widgets = {				-- Widget settings for the mod options menu
		{
			["setting_name"] = "better_melee",
			["widget_type"] = "checkbox",
			["text"] = "Improved Bot Melee Choices",
			["tooltip"] = "Improves bots' decision-making about which melee attack to use, making them favor normal attacks more.",
			["default_value"] = true
		},
		{
			["setting_name"] = "stay_closer",
			["widget_type"] = "checkbox",
			["text"] = "Bots Stay Closer",
			["tooltip"] = "Bots will stay closer to humans when many enemies are attacking.",
			["default_value"] = true
		},
		{
			["setting_name"] = "ping_elites",
			["widget_type"] = "checkbox",
			["text"] = "Bots Ping Attacking Elites",
			["tooltip"] = "Allows bots to ping elite enemies that are targeting them.",
			["default_value"] = true
		}
	},
}