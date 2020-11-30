local mod = get_mod("BotImprovements_Combat")

--[[
	Will make the bots stick closer to players, especially during swarms.
--]]
local aggro_level = 0
mod:hook(AISystem, "update_brains", function (func, self, ...)
	local result = func(self, ...)

	if mod:get("stay_closer") then
		local fight_melee = BotActions.default.fight_melee
		aggro_level = (self.number_ordinary_aggroed_enemies * 2 / 3)
		fight_melee.override_engage_range_to_follow_pos = math.max(3, 12 - aggro_level)
		fight_melee.engage_range = math.max(2, 6 - aggro_level)
		fight_melee.override_engage_range_to_follow_pos_threat = math.max(3, 6 - aggro_level)
	end

	return result
end)

mod:hook(BTConditions, "bot_in_melee_range", function (func, blackboard)
	if not mod:get("stay_closer") then
		return func(blackboard)
	end

	local target_unit = blackboard.target_unit

	if not ALIVE[target_unit] then
		return false
	end

	local self_unit = blackboard.unit
	local wielded_slot = blackboard.inventory_extension:equipment().wielded_slot
	local melee_range = nil
	local breed = Unit.get_data(target_unit, "breed")

	if blackboard.urgent_target_enemy == target_unit or blackboard.opportunity_target_enemy == target_unit or Vector3.is_valid(blackboard.taking_cover.cover_position:unbox()) then
		melee_range = (breed and breed.bot_opportunity_target_melee_range) or 3

		if wielded_slot == "slot_ranged" then
			melee_range = (breed and breed.bot_opportunity_target_melee_range_while_ranged) or 2
		end
	else
		melee_range = math.max(5, 11 - aggro_level) --12 unmodded

		if wielded_slot == "slot_ranged" then
			melee_range = math.max(3.5, 9 - aggro_level) --10 unmodded
		end
	end

	local target_aim_position = nil
	local override_aim_node_name = breed and breed.bot_melee_aim_node

	if override_aim_node_name then
		local override_aim_node = Unit.node(target_unit, override_aim_node_name)
		target_aim_position = Unit.world_position(target_unit, override_aim_node)
	else
		target_aim_position = POSITION_LOOKUP[target_unit]
	end

	local offset = target_aim_position - POSITION_LOOKUP[self_unit]
	local distance_squared = Vector3.length_squared(offset)
	local in_range = distance_squared < melee_range^2
	local z_offset = offset.z

	return in_range and z_offset > -1.5 and z_offset < 2
end)

--[[
	Improve bot melee behaviour.
--]]
local DEFAULT_MAXIMAL_MELEE_RANGE = 5
mod:hook(BTBotMeleeAction, "_choose_attack", function(func, self, blackboard, target_unit)
	if not mod:get("better_melee") then
		return func(self, blackboard, target_unit)
	end

	local num_enemies = #blackboard.proximite_enemies
	local outnumbered = 1 < num_enemies
	local massively_outnumbered = 3 < num_enemies
	local target_breed = Unit.get_data(target_unit, "breed")
	local target_armor = (target_breed and target_breed.armor_category) or 1
	local inventory_ext = blackboard.inventory_extension
	local wielded_slot_name = inventory_ext.get_wielded_slot_name(inventory_ext)
	local slot_data = inventory_ext.get_slot_data(inventory_ext, wielded_slot_name)
	local item_data = slot_data.item_data
	local item_template = blackboard.wielded_item_template
	local DEFAULT_ATTACK_META_DATA = {
		tap_attack = {
			arc = 0,
			penetrating = false,
			max_range = DEFAULT_MAXIMAL_MELEE_RANGE
		},
		hold_attack = {
			arc = 2,
			penetrating = true,
			max_range = DEFAULT_MAXIMAL_MELEE_RANGE
		}
	}
	local weapon_meta_data = item_template.attack_meta_data or DEFAULT_ATTACK_META_DATA

	if item_data.item_type == "bw_1h_sword" or item_data.item_type == "es_1h_sword" or item_data.item_type == "bw_flame_sword" then
		weapon_meta_data.tap_attack.arc = 2
		weapon_meta_data.tap_attack.penetrating = false
	end

	if item_data.item_type == "ww_2h_axe" then
		weapon_meta_data.tap_attack.arc = 2
		weapon_meta_data.tap_attack.penetrating = true
	end

	local best_utility = -1
	local best_attack_input, best_attack_meta_data = nil

	for attack_input, attack_meta_data in pairs(weapon_meta_data) do
		local utility = 0

		if (not outnumbered) and attack_meta_data.arc ~= 1 then
			utility = utility + 1
		end

		if target_armor ~= 2 or attack_meta_data.penetrating then
			utility = utility + 8
		end

		if best_utility < utility then
			best_utility = utility
			best_attack_input = attack_input
			best_attack_meta_data = attack_meta_data
		end
	end	

	return best_attack_input, best_attack_meta_data
end)

--[[
	Allow bots to ping elites attacking them.
--]]
local obstructed_line_of_sight = function(world, player_unit, target_unit)
	local INDEX_POSITION = 1
	local INDEX_DISTANCE = 2
	local INDEX_NORMAL = 3
	local INDEX_ACTOR = 4

	local player_unit_pos = Unit.world_position(player_unit, 0)
	player_unit_pos.z = player_unit_pos.z + 1.5
	local target_unit_pos = Unit.world_position(target_unit, 0)
	target_unit_pos.z = target_unit_pos.z + 1.4

	local physics_world = World.get_data(world, "physics_world")
	local max_distance = Vector3.length(target_unit_pos - player_unit_pos)

	local direction = target_unit_pos - player_unit_pos
	local length = Vector3.length(direction)
	direction = Vector3.normalize(direction)
	local collision_filter = "filter_player_ray_projectile"

	PhysicsWorld.prepare_actors_for_raycast(physics_world, player_unit_pos, direction, 0.01, 10, max_distance*max_distance)

	local raycast_hits = PhysicsWorld.immediate_raycast(physics_world, player_unit_pos, direction, max_distance, "all", "collision_filter", collision_filter)

	if raycast_hits then
		local num_hits = #raycast_hits

		for i = 1, num_hits, 1 do
			local hit = raycast_hits[i]
			local hit_actor = hit[INDEX_ACTOR]
			local hit_unit = Actor.unit(hit_actor)

			if hit_unit == target_unit then
				return false
			elseif hit_unit ~= player_unit then
				local obstructed_by_static = Actor.is_static(hit_actor)

				if obstructed_by_static then
					return obstructed_by_static
				end
			end
		end
	end

	return false
end

local pinged_elites = mod:persistent_table("pinged_elites")

mod:hook(PingTargetExtension, "set_pinged", function (func, self, pinged, flash, pinger_unit)
	if not pinged then
		for bot_unit, ping_data in pairs(pinged_elites) do
			if ping_data.unit == self._unit then
				ping_data.unit = nil
			end
		end
	end

	return func(self, pinged, flash, pinger_unit)
end)

local attempt_ping_elite = function (blackboard)
	if blackboard.unit == nil then
		return
	end

	local self_unit = blackboard.unit
	local PING_COOLDOWN = 2

	if not pinged_elites[self_unit] then
		pinged_elites[self_unit] = {}
	end

	-- Remove pinged elite from bot if elite is no longer alive.
	if pinged_elites[self_unit].unit then
		local health_extension = ScriptUnit.has_extension(pinged_elites[self_unit].unit, "health_system") and ScriptUnit.extension(pinged_elites[self_unit].unit, "health_system")

		if (not health_extension) or health_extension and health_extension.current_health_percent(health_extension) <= 0 then
			pinged_elites[self_unit].unit = nil
		end
	end

	for _, enemy_unit in pairs(blackboard.proximite_enemies) do
		if Unit.alive(enemy_unit) and BLACKBOARDS[enemy_unit].target_unit == self_unit and --Enemy is targeting the bot
		Unit.get_data(enemy_unit, "breed").elite and --Enemy is elite
		ScriptUnit.extension(enemy_unit, "health_system").current_health_percent(ScriptUnit.extension(enemy_unit, "health_system")) > 0 and --Enemy is alive
		(not (ScriptUnit.has_extension(enemy_unit, "ping_system") and ScriptUnit.extension(enemy_unit, "ping_system"):pinged())) and --Enemy is not already pinged
		(not pinged_elites[self_unit].unit) and --Bot doesn't have an active pinged enemy
		(not obstructed_line_of_sight(blackboard.world, self_unit, enemy_unit)) and --Bot has line of sight of enemy
		((not pinged_elites[self_unit].time) or (pinged_elites[self_unit].time + PING_COOLDOWN < Managers.time:time("main"))) then --Bot hasn't pinged something recently
			pinged_elites[self_unit].unit = enemy_unit
			pinged_elites[self_unit].time = Managers.time:time("main")
			local network_manager = Managers.state.network
			local self_unit_id = network_manager.unit_game_object_id(network_manager, self_unit)
			local enemy_unit_id = network_manager.unit_game_object_id(network_manager, enemy_unit)
			network_manager.network_transmit:send_rpc_server("rpc_ping_unit", self_unit_id, enemy_unit_id, false)
			return
		end
	end

	return
end

mod:hook(BTBotMeleeAction, "run", function (func, self, unit, blackboard, t, dt)
	local result = func(self, unit, blackboard, t, dt)

	if mod:get("ping_elites") then
		attempt_ping_elite(blackboard)
	end

	return result
end)

mod:hook(BTBotShootAction, "run", function (func, self, unit, blackboard, t, dt)
	local result = func(self, unit, blackboard, t, dt)
	
	if mod:get("ping_elites") then
		attempt_ping_elite(blackboard)
	end

	return result
end)