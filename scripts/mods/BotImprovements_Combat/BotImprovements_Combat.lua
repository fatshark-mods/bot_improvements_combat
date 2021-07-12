local mod = get_mod("BotImprovements_Combat")

mod.on_setting_changed = function(setting_name)
	if setting_name == "better_revive" then
		if mod:get("better_revive") then
			BotBehaviors.default[3][3] = {
				"BTBotActivateAbilityAction",
				name = "use_ability",
				condition = "can_activate_ability_revive",
				condition_args = {
					"activate_ability"
				},
				action_data = BotActions.default.use_ability
			}
			
			BotBehaviors.default[3][4] = {
				"BTBotInteractAction",
				name = "do_revive",
				action_data = BotActions.default.revive
			}
		else
			BotBehaviors.default[3][3] = {
				"BTBotInteractAction",
				name = "do_revive",
				action_data = BotActions.default.revive
			}
			BotBehaviors.default[3][4] = nil
		end
	end
end

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

mod:hook(PingTargetExtension, "set_pinged", function (func, self, pinged, ...)
	if not pinged then
		for bot_unit, ping_data in pairs(pinged_elites) do
			if ping_data.unit == self._unit then
				ping_data.unit = nil
			end
		end
	end

	return func(self, pinged, ...)
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
			local ping_type = PingTypes.PING_ONLY
			network_manager.network_transmit:send_rpc_server("rpc_ping_unit", self_unit_id, enemy_unit_id, false, ping_type, 1)
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

--[[
	Gives control over how quickly bots will use their healing items.
--]]
mod:hook(BTConditions, "bot_should_heal", function (func, blackboard)
	local heal_threshold = mod:get("heal_threshold")
	local heal_threshold_nb = mod:get("heal_threshold_nb")
	if heal_threshold == 1 and heal_threshold_nb == 2 then
		return func(blackboard)
	end
	local self_unit = blackboard.unit
	local force_use_health_pickup = blackboard.force_use_health_pickup
	local inventory_extension = blackboard.inventory_extension
	local buff_extension = ScriptUnit.extension(self_unit, "buff_system")
	local health_slot_data = inventory_extension:get_slot_data("slot_healthkit")
	local template = health_slot_data and inventory_extension:get_item_template(health_slot_data)
	local can_heal_self = template and template.can_heal_self

	if not can_heal_self then
		return false
	end

	local has_no_permanent_health_from_item_buff = buff_extension:has_buff_type("trait_necklace_no_healing_health_regen")
	local current_health_percent = blackboard.health_extension:current_health_percent()
	local hurt = current_health_percent <= template.bot_heal_threshold
	local target_unit = blackboard.target_unit
	local is_safe = not target_unit or ((template.fast_heal or blackboard.is_healing_self) and #blackboard.proximite_enemies == 0) or (target_unit ~= blackboard.priority_target_enemy and target_unit ~= blackboard.urgent_target_enemy and target_unit ~= blackboard.proximity_target_enemy and target_unit ~= blackboard.slot_target_enemy)
	local wounded = blackboard.status_extension:is_wounded()

	local should_heal_threshold = force_use_health_pickup and 3 or wounded and 2 or hurt and 1 or 0

	return is_safe and (has_no_permanent_health_from_item_buff and heal_threshold_nb <= should_heal_threshold or heal_threshold <= should_heal_threshold)
end)

local SELF_HEAL_STICKINESS = 0.1
local PLAYER_HEAL_STICKYBESS = 0.11
local WANTS_TO_HEAL_THRESHOLD = 0.25
local WANTS_TO_GIVE_HEAL_TO_OTHER = 0.6
mod:hook(PlayerBotBase, "_select_ally_by_utility", function (func, self, unit, blackboard, breed, t)
	local heal_threshold_other = mod:get("heal_threshold_other")
	local heal_threshold_zealot = mod:get("heal_threshold_zealot")
	if heal_threshold_other == 1 and heal_threshold_zealot == 1 then
		return func(self, unit, blackboard, breed, t)
	end

	local self_pos = POSITION_LOOKUP[unit]
	local closest_ally = nil
	local closest_dist = math.huge
	local closest_real_dist = math.huge
	local closest_in_need_type = nil
	local closest_ally_look_at = false
	local buff_extension = ScriptUnit.extension(unit, "buff_system")
	local inventory_extension = blackboard.inventory_extension
	local health_slot_data = inventory_extension:get_slot_data("slot_healthkit")
	local can_heal_other = false
	local can_give_healing_to_other = false
	local self_health_utiliy = 0

	if health_slot_data then
		local self_wounded = self._status_extension:is_wounded()
		local template = inventory_extension:get_item_template(health_slot_data)
		local has_no_permanent_health_from_item_buff = buff_extension:has_buff_type("trait_necklace_no_healing_health_regen")
		can_heal_other = template.can_heal_other
		can_give_healing_to_other = template.can_give_other

		if not has_no_permanent_health_from_item_buff or self_wounded then
			local self_health_percent = self._health_extension:current_health_percent()
			self_health_utiliy = self:_calculate_healing_item_utility(self_health_percent, self_wounded, can_give_healing_to_other) + SELF_HEAL_STICKINESS
		end
	end

	local can_give_grenade_to_other = false
	local grenade_slot_data = inventory_extension:get_slot_data("slot_grenade")

	if grenade_slot_data then
		local template = inventory_extension:get_item_template(grenade_slot_data)
		can_give_grenade_to_other = template.can_give_other
	end

	local can_give_potion_to_other = false
	local potion_slot_data = inventory_extension:get_slot_data("slot_potion")

	if potion_slot_data then
		local template = inventory_extension:get_item_template(potion_slot_data)
		can_give_potion_to_other = template.can_give_other
	end

	local conflict_director = Managers.state.conflict
	local self_segment = conflict_director:get_player_unit_segment(unit) or 1
	local level_settings = LevelHelper:current_level_settings()
	local disable_bot_main_path_teleport_check = level_settings.disable_bot_main_path_teleport_check
	local side = Managers.state.side.side_by_unit[unit]
	local player_and_bot_units = side.PLAYER_AND_BOT_UNITS

	for k = 1, #player_and_bot_units, 1 do
		local player_unit = player_and_bot_units[k]

		if player_unit ~= unit and AiUtils.unit_alive(player_unit) then
			local status_ext = ScriptUnit.extension(player_unit, "status_system")
			local utility = 0
			local look_at_ally = false

			if not status_ext:is_ready_for_assisted_respawn() and not status_ext.near_vortex and (disable_bot_main_path_teleport_check or self_segment <= (conflict_director:get_player_unit_segment(player_unit) or 1)) then
				local player = Managers.player:owner(player_unit)
				local is_bot = not player:is_player_controlled()
				local heal_player_preference = (is_bot and 0) or PLAYER_HEAL_STICKYBESS
				local in_need_type = nil

				if status_ext:is_knocked_down() then
					in_need_type = "knocked_down"
					utility = 100
				elseif status_ext:get_is_ledge_hanging() and not status_ext:is_pulled_up() then
					in_need_type = "ledge"
					utility = 100
				elseif status_ext:is_hanging_from_hook() then
					in_need_type = "hook"
					utility = 100
				else
					local health_percent = ScriptUnit.extension(player_unit, "health_system"):current_permanent_health_percent()
					local health_percent_temporary = ScriptUnit.extension(player_unit, "health_system"):current_health_percent()
					local has_no_permanent_health_from_item_buff = ScriptUnit.extension(player_unit, "buff_system"):has_buff_type("trait_necklace_no_healing_health_regen")
					local player_inventory_extension = ScriptUnit.extension(player_unit, "inventory_system")
					local player_locomotion_extension = ScriptUnit.extension(player_unit, "locomotion_system")
					local is_wounded = status_ext:is_wounded()
					local health_utility = self:_calculate_healing_item_utility(health_percent, is_wounded, can_give_healing_to_other) + heal_player_preference
					local heal_other_allowed = self_health_utiliy < health_utility
					local need_attention_type, extra_utility = self:_player_needs_attention(unit, player_unit, blackboard, player_inventory_extension, player_locomotion_extension, t)
					local ally_is_zealot = ScriptUnit.has_extension(player_unit, "career_system") and ScriptUnit.extension(player_unit, "career_system"):career_name() == "wh_zealot"
					local used_heal_threshold = ally_is_zealot and heal_threshold_zealot > heal_threshold_other and heal_threshold_zealot or heal_threshold_other

					if can_heal_other and (used_heal_threshold == 1 and health_percent < WANTS_TO_HEAL_THRESHOLD or used_heal_threshold == 2 and health_percent_temporary < WANTS_TO_HEAL_THRESHOLD or used_heal_threshold == 3 and is_wounded or used_heal_threshold == 4 and health_percent_temporary < WANTS_TO_HEAL_THRESHOLD and is_wounded) and heal_other_allowed then
						in_need_type = "in_need_of_heal"
						utility = 70 + health_utility * 15
					elseif can_give_healing_to_other and (not has_no_permanent_health_from_item_buff or is_wounded) and (health_percent < WANTS_TO_GIVE_HEAL_TO_OTHER or is_wounded) and not player_inventory_extension:get_slot_data("slot_healthkit") and heal_other_allowed then
						in_need_type = "can_accept_heal_item"
						utility = 70 + health_utility * 10
					elseif can_give_grenade_to_other and (not player_inventory_extension:get_slot_data("slot_grenade") or player_inventory_extension:can_store_additional_item("slot_grenade")) and not is_bot then
						in_need_type = "can_accept_grenade"
						utility = 70
					elseif can_give_potion_to_other and not player_inventory_extension:get_slot_data("slot_potion") and not is_bot then
						in_need_type = "can_accept_potion"
						utility = 70
					elseif need_attention_type == "stop" then
						in_need_type = "in_need_of_attention_stop"
						look_at_ally = true
						utility = 5 + extra_utility
					elseif need_attention_type == "look_at" then
						in_need_type = "in_need_of_attention_look"
						look_at_ally = true
						utility = 2 + extra_utility
					end
				end

				if in_need_type or not is_bot then
					local target_pos = POSITION_LOOKUP[player_unit]
					local allowed_follow_path, allowed_aid_path = self:_ally_path_allowed(unit, player_unit, t)

					if allowed_follow_path then
						if not allowed_aid_path then
							in_need_type = nil
						elseif in_need_type then
							local alive_bosses = conflict_director:alive_bosses()
							local num_alive_bosses = #alive_bosses

							for i = 1, num_alive_bosses, 1 do
								local boss_unit = alive_bosses[i]
								local boss_position = POSITION_LOOKUP[boss_unit]
								local self_to_boss_distance_sq = Vector3.distance_squared(self_pos, boss_position)
								local boss_target = BLACKBOARDS[boss_unit].target_unit

								if boss_target == unit and self_to_boss_distance_sq < 36 then
									in_need_type = nil
									utility = 0

									break
								end
							end
						end

						if not is_bot then
							utility = utility * 1.25
						end

						if in_need_type or not is_bot then
							local real_dist = Vector3.distance(self_pos, target_pos)
							local dist = real_dist - utility

							if closest_dist > dist then
								closest_dist = dist
								closest_real_dist = real_dist
								closest_ally = player_unit
								closest_in_need_type = in_need_type
								closest_ally_look_at = look_at_ally
							end
						end
					end
				end
			end
		end
	end

	return closest_ally, closest_real_dist, closest_in_need_type, closest_ally_look_at
end)

--[[
	Stop bots from chasing far-away enemies.
--]]
mod:hook(PlayerBotBase, "_enemy_path_allowed", function (func, self, enemy_unit)
	if not mod:get("stop_chasing") then
		return func(self, enemy_unit)
	end
	local enemy_pos = POSITION_LOOKUP[enemy_unit]
	local self_pos = POSITION_LOOKUP[self._unit]
	
	if Vector3.distance_squared(enemy_pos, self_pos) > 350 then
		return false
	end

	return func(self, enemy_unit)
end)

--[[
	Make bots ignore line-of-fire threats from gunners unless within lethal range.
--]]
local TAKE_COVER_TEMP_TABLE = {}
local function line_of_fire_check(from, to, p, width, length)
	local diff = p - from
	local dir = Vector3.normalize(to - from)
	local lateral_dist = Vector3.dot(diff, dir)

	if lateral_dist <= 0 or length < lateral_dist then
		return false
	end

	local direct_dist = Vector3.length(diff - lateral_dist * dir)

	if math.min(lateral_dist, width) < direct_dist then
		return false
	else
		return true
	end
end

mod:hook(PlayerBotBase, "_in_line_of_fire", function(func, self, self_unit, self_pos, take_cover_targets, taking_cover_from)
	if not mod:get("ignore_lof") then
		return func(self, self_unit, self_pos, take_cover_targets, taking_cover_from)
	end

	local changed = false
	local in_line_of_fire = false
	local width = 2.5
	local sticky_width = 6
	local length = 40

	for attacker, victim in pairs(take_cover_targets) do
		local already_in_cover_from = taking_cover_from[attacker]

		if ALIVE[victim] and (victim == self_unit or line_of_fire_check(POSITION_LOOKUP[attacker], POSITION_LOOKUP[victim], self_pos, (already_in_cover_from and sticky_width) or width, length))
		and Vector3.distance_squared(POSITION_LOOKUP[attacker], POSITION_LOOKUP[victim]) < 140 then -- added bit
			TAKE_COVER_TEMP_TABLE[attacker] = victim
			changed = changed or not already_in_cover_from
			in_line_of_fire = true
		end
	end

	for attacker, victim in pairs(taking_cover_from) do
		if not TAKE_COVER_TEMP_TABLE[attacker] then
			changed = true

			break
		end
	end

	table.clear(taking_cover_from)

	for attacker, victim in pairs(TAKE_COVER_TEMP_TABLE) do
		taking_cover_from[attacker] = victim
	end

	table.clear(TAKE_COVER_TEMP_TABLE)

	return in_line_of_fire, changed
end)

--[[
	Stop bots from attacking bosses mindlessly when other threats are nearby.
--]]
local BOSS_ENGAGE_DISTANCE = 15
local BOSS_ENGAGE_DISTANCE_SQ = BOSS_ENGAGE_DISTANCE^2
mod:hook(AIBotGroupSystem, "_update_urgent_targets", function (func, self, dt, t)
	if not mod:get("ignore_bosses") then
		return func(self, dt, t)
	end

	local conflict_director = Managers.state.conflict
	local alive_bosses = conflict_director:alive_bosses()
	local num_alive_bosses = #alive_bosses
	local bot_ai_data = self._bot_ai_data
	local urgent_targets = self._urgent_targets

	for side_id = 1, #bot_ai_data, 1 do
		local side_bot_data = bot_ai_data[side_id]

		for bot_unit, data in pairs(side_bot_data) do
			local best_utility = -math.huge
			local best_target = nil
			local best_distance = math.huge
			local blackboard = data.blackboard
			local self_pos = POSITION_LOOKUP[bot_unit]
			local old_target = blackboard.urgent_target_enemy

			for target_unit, is_target_until in pairs(urgent_targets) do
				local time_left = is_target_until - t

				if time_left > 0 then
					if AiUtils.unit_alive(target_unit) then
						local utility, distance = self:_calculate_opportunity_utility(bot_unit, blackboard, self_pos, old_target, target_unit, t, false, false)

						if best_utility < utility then
							best_utility = utility
							best_target = target_unit
							best_distance = distance
						end
					else
						urgent_targets[target_unit] = nil
					end
				else
					urgent_targets[target_unit] = nil
				end
			end
			
			if not best_target then
				for j = 1, num_alive_bosses, 1 do
					local target_unit = alive_bosses[j]
					local pos = POSITION_LOOKUP[target_unit]

					if AiUtils.unit_alive(target_unit) and not AiUtils.unit_invincible(target_unit) and Vector3.distance_squared(pos, self_pos) < BOSS_ENGAGE_DISTANCE_SQ and not BLACKBOARDS[target_unit].defensive_mode_duration
					and (#blackboard.proximite_enemies < 2 or BLACKBOARDS[target_unit].target_unit == bot_unit) then -- added bit
						local utility, distance = self:_calculate_opportunity_utility(bot_unit, blackboard, self_pos, old_target, target_unit, t, false, false)

						if best_utility < utility then
							best_utility = utility
							best_target = target_unit
							best_distance = distance
						end
					end
				end
			end

			blackboard.revive_with_urgent_target = best_target and self:_can_revive_with_urgent_target(bot_unit, self_pos, blackboard, best_target, t)
			blackboard.urgent_target_enemy = best_target
			blackboard.urgent_target_distance = best_distance
			local hit_by_projectile = blackboard.hit_by_projectile

			for attacking_unit, _ in pairs(hit_by_projectile) do
				if not AiUtils.unit_alive(attacking_unit) then
					hit_by_projectile[attacking_unit] = nil
				end
			end
		end
	end
end)

--[[
	Makes bots more likely to attempt revive through danger, and makes them use their active ability to secure revives if needed (and ability is relevant).
--]]

-- Copied code.
local PUSHED_COOLDOWN = 2
local BLOCK_BROKEN_COOLDOWN = 4
local function is_safe_to_block_interact(status_extension, interaction_extension, wanted_interaction_type)
	local t = Managers.time:time("game")
	local pushed_t = status_extension.pushed_at_t
	local block_broken_t = status_extension.block_broken_at_t
	local enough_fatigue = true
	local is_interacting, interaction_type = interaction_extension:is_interacting()

	if not is_interacting or interaction_type ~= wanted_interaction_type then
		local current_fatigue, max_fatigue = status_extension:current_fatigue_points()
		local stamina_left = max_fatigue - current_fatigue
		local blocked_attack_cost = PlayerUnitStatusSettings.fatigue_point_costs.blocked_attack
		enough_fatigue = current_fatigue == 0 or blocked_attack_cost < stamina_left
	end

	if enough_fatigue and t > pushed_t + PUSHED_COOLDOWN and t > block_broken_t + BLOCK_BROKEN_COOLDOWN then
		return true
	else
		return false
	end
end

local function can_interact_with_ally(self_unit, target_ally_unit)
	local interactable_extension = ScriptUnit.extension(target_ally_unit, "interactable_system")
	local interactor_unit = interactable_extension:is_being_interacted_with()
	local can_interact_with_ally = interactor_unit == nil or interactor_unit == self_unit

	return can_interact_with_ally
end

local FLAT_MOVE_TO_EPSILON_SQ = BotConstants.default.FLAT_MOVE_TO_EPSILON^2
local Z_MOVE_TO_EPSILON = BotConstants.default.Z_MOVE_TO_EPSILON

local function has_reached_ally_aid_destination(self_position, blackboard)
	local navigation_extension = blackboard.navigation_extension
	local destination = navigation_extension:destination()
	local target_ally_aid_destination = blackboard.target_ally_aid_destination:unbox()
	local has_target_ally_aid_destination = Vector3.equal(destination, target_ally_aid_destination)

	if has_target_ally_aid_destination then
		return navigation_extension:destination_reached()
	elseif navigation_extension:destination_reached() then
		local bot_ai_extension = blackboard.ai_extension
		local is_near = not bot_ai_extension:new_destination_distance_check(self_position, destination, target_ally_aid_destination, navigation_extension)

		return is_near
	else
		local offset = target_ally_aid_destination - self_position

		return math.abs(offset.z) <= Z_MOVE_TO_EPSILON and Vector3.length_squared(Vector3.flat(offset)) <= FLAT_MOVE_TO_EPSILON_SQ
	end
end

-- Now requires multiple threatening elites to return true.
local function is_there_threat_to_aid(self_unit, proximite_enemies, force_aid)
	local num_proximite_enemies = #proximite_enemies
	local num_threat = 0

	for i = 1, num_proximite_enemies, 1 do
		local enemy_unit = proximite_enemies[i]

		if ALIVE[enemy_unit] then
			local enemy_blackboard = BLACKBOARDS[enemy_unit]
			local enemy_breed = enemy_blackboard.breed

			if enemy_blackboard.target_unit == self_unit and (not force_aid or enemy_breed.is_bot_aid_threat) then
				num_threat = num_threat + enemy_breed.threat_value
			end
		end
	end

	if num_threat > 14 then
		return true
	end

	return false
end

-- Increased ally_distance from 1 to 1.5, allowing the bots to revive without standing on top of the downed player. Still shorter range than players.
mod:hook(BTConditions, "can_revive", function (func, blackboard)
	if not mod:get("better_revive") then
		return func(blackboard)
	end

	local target_ally_unit = blackboard.target_ally_unit

	if blackboard.interaction_unit == target_ally_unit and blackboard.target_ally_need_type == "knocked_down" then
		local interaction_extension = blackboard.interaction_extension

		if not is_safe_to_block_interact(blackboard.status_extension, interaction_extension, "revive") then
			return false
		end

		local self_unit = blackboard.unit
		local health = ScriptUnit.extension(target_ally_unit, "health_system"):current_health_percent()

		if health > 0.3 and is_there_threat_to_aid(self_unit, blackboard.proximite_enemies, blackboard.force_aid) then
			return false
		end

		local ally_distance = blackboard.ally_distance
		local is_interacting, interaction_type = interaction_extension:is_interacting()

		if is_interacting and interaction_type == "revive" and ally_distance < 1.5 then
			return true
		end

		local self_position = POSITION_LOOKUP[self_unit]
		local ally_destination_reached = has_reached_ally_aid_destination(self_position, blackboard) or blackboard.is_transported
		local can_interact_with_ally = can_interact_with_ally(self_unit, target_ally_unit)

		if can_interact_with_ally and ally_destination_reached then
			return true
		end
	end
end)

if mod:get("better_revive") then
	BotBehaviors.default[3][3] = {
		"BTBotActivateAbilityAction",
		name = "use_ability",
		condition = "can_activate_ability_revive",
		condition_args = {
			"activate_ability"
		},
		action_data = BotActions.default.use_ability
	}
	
	BotBehaviors.default[3][4] = {
		"BTBotInteractAction",
		name = "do_revive",
		action_data = BotActions.default.revive
	}
end

-- Same as original is_there_threat_to_aid function, but now applied to requiring ability use to secure revive.
local function is_there_threat_to_aid_requiring_ability(self_unit, proximite_enemies, force_aid)
	local num_proximite_enemies = #proximite_enemies

	for i = 1, num_proximite_enemies, 1 do
		local enemy_unit = proximite_enemies[i]

		if ALIVE[enemy_unit] then
			local enemy_blackboard = BLACKBOARDS[enemy_unit]
			local enemy_breed = enemy_blackboard.breed

			if enemy_blackboard.target_unit == self_unit and (not force_aid or enemy_breed.is_bot_aid_threat) then
				return true
			end
		end
	end

	return false
end

-- New condition used to know if bot needs to use ability before attempting revive.
BTConditions.can_activate_ability_revive = function (blackboard, args)
	local career_extension = blackboard.career_extension
	local is_using_ability = blackboard.activate_ability_data.is_using_ability
	local career_name = career_extension:career_name()
	local ability_check_category_name = args[1]
	local ability_check_category = BTConditions.ability_check_categories[ability_check_category_name]

	if not ability_check_category or not ability_check_category[career_name] then
		return false
	end

	if ability_check_category_name == "shoot_ability" or career_name == "we_maidenguard" or career_name == "dr_slayer" or career_name == "wh_zealot" or career_name == "bw_adept" or career_name == "es_knight" or career_name == "es_questingknight" then
		return false
	end
	
	if not career_extension._abilities[1].is_ready then
		return false
	end
	
	if not is_there_threat_to_aid_requiring_ability(blackboard.unit, blackboard.proximite_enemies, false) then
		return false
	end

	return true
end

--[[
	Updates the logic for when bots should use active abilities for some careers.
--]]
-- Increased threat required significantly. Low stamina now reduces threat required.
mod:hook(BTConditions.can_activate, "dr_ironbreaker", function (func, blackboard)
	if not mod:get("better_ult") then
		return func(blackboard)
	end

	local self_unit = blackboard.unit
	local self_position = POSITION_LOOKUP[self_unit]
	local proximite_enemies = blackboard.proximite_enemies
	local num_proximite_enemies = #proximite_enemies
	local max_distance_sq = 64
	local low_stamina = blackboard.status_extension:current_fatigue() >= 90
	local threat_threshold = 50 --15 unmodded
	local total_threat_value = (low_stamina and 15) or 0

	for i = 1, num_proximite_enemies, 1 do
		local enemy_unit = proximite_enemies[i]
		local enemy_position = POSITION_LOOKUP[enemy_unit]

		if ALIVE[enemy_unit] and Vector3.distance_squared(self_position, enemy_position) <= max_distance_sq then
			local enemy_blackboard = BLACKBOARDS[enemy_unit]
			local enemy_breed = enemy_blackboard.breed
			local is_elite = enemy_breed.elite
			local is_targeting_bot = enemy_blackboard.target_unit == self_unit
			local threat_value = enemy_breed.threat_value * (((is_elite or is_targeting_bot) and 1.25) or 1)
			total_threat_value = total_threat_value + threat_value

			if threat_threshold <= total_threat_value then
				return true
			end
		end
	end

	return false
end)

-- Redid logic for considering group presence and health. Increased max threat required. Low stamina now reduces threat required.
mod:hook(BTConditions.can_activate, "es_mercenary", function (func, blackboard)
	if not mod:get("better_ult") then
		return func(blackboard)
	end

	local self_unit = blackboard.unit
	local self_position = POSITION_LOOKUP[self_unit]
	local max_ally_distance_sq = 225
	local side = blackboard.side
	local PLAYER_AND_BOT_UNITS = side.PLAYER_AND_BOT_UNITS
	local num_players = #PLAYER_AND_BOT_UNITS
	local group_health_multiplier = 0

	for i = 1, num_players, 1 do
		local player_unit = PLAYER_AND_BOT_UNITS[i]
		local player_position = POSITION_LOOKUP[player_unit]
		local distance_squared = Vector3.distance_squared(self_position, player_position)
		local current_health_percent = ScriptUnit.extension(player_unit, "health_system"):current_health_percent()
		local health_multiplier_value = math.max(current_health_percent - 0.6, 0) * 2.5
		
		if player_unit == self_unit then
			group_health_multiplier = group_health_multiplier + (health_multiplier_value * 2 * (1 / (num_players + 1)))
		elseif player_unit ~= self_unit and distance_squared < max_ally_distance_sq then
			group_health_multiplier = group_health_multiplier + (health_multiplier_value * (1 / (num_players + 1)))
		else
			group_health_multiplier = group_health_multiplier + (1 * (1 / (num_players + 1)))
		end
	end

	local proximite_enemies = blackboard.proximite_enemies
	local num_proximite_enemies = #proximite_enemies
	local max_threat_distance_sq = 49
	local low_stamina = blackboard.status_extension:current_fatigue() >= 90
	local total_threat_value = (low_stamina and 15) or 0
	local threat_threshold = math.max(35 * (group_health_multiplier), 6)

	for i = 1, num_proximite_enemies, 1 do
		local enemy_unit = proximite_enemies[i]
		local enemy_position = POSITION_LOOKUP[enemy_unit]

		if ALIVE[enemy_unit] and Vector3.distance_squared(self_position, enemy_position) <= max_threat_distance_sq then
			local enemy_blackboard = BLACKBOARDS[enemy_unit]
			local enemy_breed = enemy_blackboard.breed
			local is_elite = enemy_breed.elite
			local is_targeting_bot = enemy_blackboard.target_unit == self_unit
			local threat_value = enemy_breed.threat_value * (((is_elite or is_targeting_bot) and 1.25) or 1)
			total_threat_value = total_threat_value + threat_value

			if threat_threshold <= total_threat_value then
				return true
			end
		end
	end

	return false
end)

-- No longer considers own health. Instead considers low stamina.
mod:hook(BTConditions.can_activate, "es_huntsman", function (func, blackboard)
	if not mod:get("better_ult") then
		return func(blackboard)
	end

	local proximite_enemies = blackboard.proximite_enemies
	local num_proximite_enemies = #proximite_enemies
	local target_unit = blackboard.target_unit

	if num_proximite_enemies == 0 and target_unit == nil then
		return false
	end

	local self_unit = blackboard.unit
	local self_position = POSITION_LOOKUP[self_unit]
	local target_blackboard = BLACKBOARDS[target_unit]
	local target_breed = target_blackboard and target_blackboard.breed
	local target_threat_value = (target_breed and target_breed.threat_value) or 0
	local target_ally_unit = blackboard.target_ally_unit
	local target_ally_need_type = blackboard.target_ally_need_type
	local ai_bot_group_system = Managers.state.entity:system("ai_bot_group_system")
	local is_prioritized = ai_bot_group_system:is_prioritized_ally(self_unit, target_ally_unit)
	local low_stamina = blackboard.status_extension:current_fatigue() >= 90

	if is_prioritized and (target_ally_need_type == "knocked_down" or target_ally_need_type == "hook" or target_ally_need_type == "ledge") then
		return true
	elseif low_stamina then
		return true
	elseif target_unit and target_threat_value >= 8 then
		return true
	end

	return false
end)

-- Now only dashes at threat 8 units (specials). Now dashes if low stamina.
mod:hook(BTConditions.can_activate, "we_maidenguard", function (func, blackboard)
	if not mod:get("better_ult") then
		return func(blackboard)
	end

	local self_unit = blackboard.unit
	local self_position = POSITION_LOOKUP[self_unit]
	local target_unit = blackboard.target_unit
	local target_blackboard = BLACKBOARDS[target_unit]
	local target_breed = target_blackboard and target_blackboard.breed
	local target_threat_value = (target_breed and target_breed.threat_value) or 0
	local target_ally_unit = blackboard.target_ally_unit
	local target_ally_need_type = blackboard.target_ally_need_type
	local ai_bot_group_system = Managers.state.entity:system("ai_bot_group_system")
	local is_prioritized = ai_bot_group_system:is_prioritized_ally(self_unit, target_ally_unit)
	local dash_target, dash_target_distance_sq = nil
	local low_stamina = blackboard.status_extension:current_fatigue() >= 90

	if is_prioritized and (target_ally_need_type == "knocked_down" or target_ally_need_type == "hook") then
		dash_target = target_ally_unit
		dash_target_distance_sq = blackboard.ally_distance^2
	elseif target_unit and ((target_threat_value == 8 and not target_breed.name == "beastmen_bestigor") or low_stamina) then
		local target_position = POSITION_LOOKUP[target_unit]
		dash_target = target_unit
		dash_target_distance_sq = Vector3.distance_squared(self_position, target_position)
	end

	local min_distance_sq = 81
	local max_distance = 12
	local max_distance_sq = 144

	if dash_target and min_distance_sq < dash_target_distance_sq and dash_target_distance_sq < max_distance_sq then
		local dash_target_position = POSITION_LOOKUP[dash_target]
		local dash_target_direction = Vector3.normalize(dash_target_position - self_position)
		local check_position = self_position + dash_target_direction * (max_distance + 2)
		local nav_world = blackboard.nav_world
		local success = LocomotionUtils.ray_can_go_on_mesh(nav_world, self_position, check_position, nil, 1, 1)

		if success then
			blackboard.activate_ability_data.aim_position:store(dash_target_position)

			return true
		end
	end

	return false
end)

-- No longer considers own health. Instead considers low stamina. Also no longer stealths when targeting threat 8 enemies.
mod:hook(BTConditions.can_activate, "we_shade", function (func, blackboard)
	if not mod:get("better_ult") then
		return func(blackboard)
	end

	local proximite_enemies = blackboard.proximite_enemies
	local num_proximite_enemies = #proximite_enemies
	local target_unit = blackboard.target_unit

	if num_proximite_enemies == 0 and target_unit == nil then
		return false
	end

	local self_unit = blackboard.unit
	local self_position = POSITION_LOOKUP[self_unit]
	local target_blackboard = BLACKBOARDS[target_unit]
	local target_breed = target_blackboard and target_blackboard.breed
	local target_threat_value = (target_breed and target_breed.threat_value) or 0
	local target_ally_unit = blackboard.target_ally_unit
	local target_ally_need_type = blackboard.target_ally_need_type
	local ai_bot_group_system = Managers.state.entity:system("ai_bot_group_system")
	local is_prioritized = ai_bot_group_system:is_prioritized_ally(self_unit, target_ally_unit)
	local low_stamina = blackboard.status_extension:current_fatigue() >= 90

	if is_prioritized and (target_ally_need_type == "knocked_down" or target_ally_need_type == "hook" or target_ally_need_type == "ledge") then
		return true
	elseif low_stamina then
		return true
	elseif target_unit and target_threat_value >= 12 then
		return true
	end

	return false
end)

-- No longer considers own health and closeness to allies. Threat required increased. Low stamina reduces threat required.
mod:hook(BTConditions.can_activate, "wh_captain", function (func, blackboard)
	if not mod:get("better_ult") then
		return func(blackboard)
	end

	local self_unit = blackboard.unit
	local self_position = POSITION_LOOKUP[self_unit]

	local proximite_enemies = blackboard.proximite_enemies
	local num_proximite_enemies = #proximite_enemies
	local max_threat_distance_sq = 49
	local low_stamina = blackboard.status_extension:current_fatigue() >= 90
	local total_threat_value = (low_stamina and 15) or 0
	local threat_threshold = 30

	for i = 1, num_proximite_enemies, 1 do
		local enemy_unit = proximite_enemies[i]
		local enemy_position = POSITION_LOOKUP[enemy_unit]

		if ALIVE[enemy_unit] and Vector3.distance_squared(self_position, enemy_position) <= max_threat_distance_sq then
			local enemy_blackboard = BLACKBOARDS[enemy_unit]
			local enemy_breed = enemy_blackboard.breed
			local is_elite = enemy_breed.elite
			local is_targeting_bot = enemy_blackboard.target_unit == self_unit
			local threat_value = enemy_breed.threat_value * (((is_elite or is_targeting_bot) and 1.25) or 1)
			total_threat_value = total_threat_value + threat_value

			if threat_threshold <= total_threat_value then
				return true
			end
		end
	end

	return false
end)

-- Threat required increased to 35 unless own health is low. No longer considers enemies not targeting it.
mod:hook(BTConditions.can_activate, "bw_unchained", function (func, blackboard)
	if not mod:get("better_ult") then
		return func(blackboard)
	end

	local overcharge_extension = blackboard.overcharge_extension
	local is_above_critical_limit = overcharge_extension:is_above_critical_limit()

	if is_above_critical_limit then
		return true
	end

	local self_unit = blackboard.unit
	local self_position = POSITION_LOOKUP[self_unit]
	local proximite_enemies = blackboard.proximite_enemies
	local num_proximite_enemies = #proximite_enemies
	local max_distance_sq = 16
	local total_threat_value = 0
	local critical_health = blackboard.health_extension:current_health_percent() <= 0.2
	local threat_threshold = (critical_health and 10) or 35 --10 unmodded

	for i = 1, num_proximite_enemies, 1 do
		local enemy_unit = proximite_enemies[i]
		local enemy_position = POSITION_LOOKUP[enemy_unit]

		if ALIVE[enemy_unit] and Vector3.distance_squared(self_position, enemy_position) <= max_distance_sq then
			local enemy_blackboard = BLACKBOARDS[enemy_unit]
			local enemy_breed = enemy_blackboard.breed
			local is_targeting_bot = enemy_blackboard.target_unit == self_unit
			local threat_value = enemy_breed.threat_value * ((is_targeting_bot and 1) or 0) --1.25 and 1 unmodded
			total_threat_value = total_threat_value + threat_value

			if threat_threshold <= total_threat_value then
				return true
			end
		end
	end

	return false
end)