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
			["tooltip"] = "Improves bots' decision-making about which melee attack to use.",
			["default_value"] = true
		},
		{
			["setting_name"] = "ping_elites",
			["widget_type"] = "checkbox",
			["text"] = "Bots Ping Attacking Elites",
			["tooltip"] = "Allows bots to ping elite enemies that are targeting them.",
			["default_value"] = true
		},
		{
			["setting_name"] = "heal_threshold",
			["widget_type"] = "dropdown",
			["text"] = "Bots Healing Threshold",
			["tooltip"] = "Choose when bots not wearing Natural Bond will heal themselves.",
			["options"] = {
					{text = "When Hurt (Default)", value = 1},
					{text = "When Wounded", value = 2},
					{text = "Extra Heals Available", value = 3}
				},
			["default_value"] = 1
		},
		{
			["setting_name"] = "heal_threshold_nb",
			["widget_type"] = "dropdown",
			["text"] = "Bots Healing Threshold (Natural Bond)",
			["tooltip"] = "Choose when bots wearing Natural Bond will heal themselves.",
			["options"] = {
					{text = "When Hurt", value = 1},
					{text = "When Wounded (Default)", value = 2},
					{text = "Extra Heals Available", value = 3}
				},
			["default_value"] = 2
		},
		{
			["setting_name"] = "heal_threshold_other",
			["widget_type"] = "dropdown",
			["text"] = "Bots Heal Other Threshold",
			["tooltip"] = "Choose when bots will want to heal their teammates.",
			["options"] = {
					{text = "Low Permanent (Default)", value = 1},
					{text = "Low Temporary", value = 2},
					{text = "When Wounded", value = 3}
				},
			["default_value"] = 1
		},
		{
			["setting_name"] = "heal_threshold_zealot",
			["widget_type"] = "dropdown",
			["text"] = "Bots Heal Zealot Threshold",
			["tooltip"] = "Choose when bots will want to heal the Zealot. Uses Heal Other Threshold when set to Default or to a lower setting than Heal Other.",
			["options"] = {
					{text = "Default", value = 1},
					{text = "Low Temporary", value = 2},
					{text = "When Wounded", value = 3},
					{text = "When Wounded And Low", value = 4}
				},
			["default_value"] = 1
		},
		{
			["setting_name"] = "stop_chasing",
			["widget_type"] = "checkbox",
			["text"] = "Bots No Longer Chase Specials",
			["tooltip"] = "Stop bots from chasing specials that are too far away from them.",
			["default_value"] = true
		},
		{
			["setting_name"] = "ignore_lof",
			["widget_type"] = "checkbox",
			["text"] = "Bots Ignore Line Of Fire",
			["tooltip"] = "Bots will now ignore line-of-fire threats from gunners, unless the gunner is very close.",
			["default_value"] = true
		},
		{
			["setting_name"] = "ignore_bosses",
			["widget_type"] = "checkbox",
			["text"] = "Bots No Longer Focus Bosses",
			["tooltip"] = "Bots will ignore bosses entirely unless attacked by them, or no other enemies are nearby.",
			["default_value"] = true
		},
		{
			["setting_name"] = "better_revive",
			["widget_type"] = "checkbox",
			["text"] = "Improved Revive Logic",
			["tooltip"] = "Makes bots more likely to attempt revives through danger, and makes some careers use their active ability to secure an attempt if needed.",
			["default_value"] = true
		},
		{
			["setting_name"] = "better_ult",
			["widget_type"] = "checkbox",
			["text"] = "Improved Active Ability Usage",
			["tooltip"] = "Changes the logic that several careers use to determine when to use their active ability. \n" ..
			"NOTE : This may cause some careers to use their active ability too sparingly on difficulties below legend.",
			["default_value"] = true
		},
	},
}