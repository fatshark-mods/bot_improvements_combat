return {
	run = function()
		fassert(rawget(_G, "new_mod"), "Bot Improvements - Combat must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("BotImprovements_Combat", {
			mod_script       = "scripts/mods/BotImprovements_Combat/BotImprovements_Combat",
			mod_data         = "scripts/mods/BotImprovements_Combat/BotImprovements_Combat_data",
			mod_localization = "scripts/mods/BotImprovements_Combat/BotImprovements_Combat_localization"
		})
	end,
	packages = {
		"resource_packages/BotImprovements_Combat/BotImprovements_Combat"
	}
}
