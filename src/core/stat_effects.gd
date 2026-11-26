class_name StatEffects
extends RefCounted

## Typed view of data/stat_effects.json. All decision weights and context
## thresholds live in that file so balance changes need no code edits.

const FILE := "res://data/stat_effects.json"

const ACTION_KEYS := [
	"shoot", "pass", "dribble", "press", "tackle", "support", "chase", "mark",
	"cross", "switch", "overlap",
]

const REQUIRED_CONTEXT := [
	"attribute_neutral", "attribute_scale", "stamina_floor",
	"stamina_penalty_per_point", "shoot_range_m", "shoot_near_goal_bonus",
	"shoot_unpressured_bonus", "shoot_pressure_penalty",
	"press_radius_m", "press_proximity_bonus", "tackle_radius_m",
	"tackle_proximity_bonus", "tackle_rank_penalty_per_place",
	"tackle_challenge_cooldown_seconds", "tackle_success_chance",
	"tackle_backoff_seconds", "tackle_backoff_distance_m",
	"pressure_radius_m", "pressure_pass_bonus",
	"mark_proximity_bonus", "mark_unassigned_penalty",
	"mark_stand_off_m", "mark_zone_radius_m", "mark_out_of_zone_penalty",
	"ball_control_radius_m", "support_spacing_m",
	"stamina_penalty_active_scale", "stamina_penalty_passive_scale",
	"support_deep_m", "support_advanced_m", "support_narrow_m",
	"support_wide_m", "dribble_advance_m", "gk_line_depth_m",
	"gk_lateral_follow_scale", "formation_ball_follow_scale",
	"formation_max_shift_m", "chase_nearest_bonus",
	"chase_rank_penalty_per_place", "chase_out_of_range_penalty",
	"skill_action_out_of_range_penalty",
	"controlled_skill_action_bonus", "controlled_pass_bonus",
	"controlled_other_action_penalty", "pass_forward_weight",
	"pass_space_weight", "pass_distance_penalty_per_m", "pass_pressure_penalty",
	"pass_min_distance_m", "pass_too_close_penalty", "pass_backward_penalty_per_m",
	"pass_lane_radius_m", "pass_lane_penalty", "pass_scatter_scale",
	"kick_cooldown_seconds", "gk_intercept_max_distance_m",
	"scatter_degrees_per_missing_composure", "speed_floor_fraction",
	"wing_channel_m", "cross_min_range_m", "cross_max_range_m",
	"cross_box_half_width_m", "cross_allow_behind_m", "cross_target_lead_m", "cross_wide_bonus",
	"cross_space_bonus", "cross_pressure_penalty",
	"switch_min_lateral_m", "switch_min_distance_m", "switch_max_backward_m",
	"switch_lateral_weight", "switch_forward_weight", "switch_space_weight",
	"switch_distance_penalty_per_m", "switch_bonus", "switch_central_penalty",
	"overlap_slot_threshold_m", "overlap_min_behind_m", "overlap_flank_tolerance_m",
	"overlap_advance_m", "overlap_width_m", "overlap_bonus",
	"overlap_pressure_penalty",
	"dribble_space_radius_m", "dribble_space_lane_half_width_m",
	"dribble_space_bonus", "dribble_pressure_penalty", "pass_wide_weight",
	"tempo_cycle_seconds", "tempo_bias_scale", "tempo_wave_scale",
	"tempo_decision_scale", "tempo_kick_scale", "tempo_pass_scale",
	"speed_tempo_scale", "speed_variation_amplitude",
	"speed_variation_period_seconds", "speed_stamina_penalty_per_point",
	"speed_min_fraction", "speed_max_fraction",
]

const SIMULATION_KEYS := [
	"possessions_per_team", "tempo_possession_scale", "mentality_possession_scale",
	"touch_slot_weights", "touch_attribute_scale", "receiver_slot_weights",
	"receiver_attribute_scale", "wide_zone_chance", "attacking_third_chance",
	"defensive_third_chance", "action_noise", "cross_zone_bonus",
	"switch_zone_bonus", "shoot_zone_bonus", "dribble_attacking_bonus",
	"dribble_defensive_penalty", "pass_success_base", "pass_success_attribute_scale",
	"cross_success_penalty", "switch_success_penalty", "pass_risky_penalty",
	"pass_safe_bonus", "pass_direct_penalty", "pass_short_bonus",
	"dribble_success_base", "dribble_success_attribute_scale",
	"tackle_attempt_base", "tackle_modifier_chance_scale", "tackle_win_base",
	"tackle_win_attribute_scale", "tackle_foul_chance", "shot_goal_base",
	"shot_goal_attribute_scale", "shot_save_base", "shot_save_keeper_scale",
	"shot_on_target_base", "shot_wide_penalty", "min_chance", "max_chance",
	"possession_seconds_per_possession",
]

const ANALYSIS_KEYS := [
	"min_pass_completion_rate", "max_tackles_per_match", "min_tackle_win_rate",
	"max_fouls_per_tackle", "min_shot_conversion", "min_shots_per_match",
	"min_possession_share",
]

var action_attribute_weights: Dictionary = {}
var action_base: Dictionary = {}
var instruction_modifiers: Dictionary = {}
var context: Dictionary = {}
var simulation: Dictionary = {}
var analysis: Dictionary = {}


static func load(path: String = FILE) -> StatEffects:
	var raw: Variant = FixtureLoader.load_json(path)
	if not (raw is Dictionary):
		push_error("StatEffects: %s must contain a JSON object" % path)
		return null
	var data: Dictionary = raw
	var result := StatEffects.new()

	for key in ACTION_KEYS:
		var weights: Variant = data.get("action_attribute_weights", {}).get(key, {})
		if not (weights is Dictionary) or not _numbers_only(weights):
			push_error("StatEffects: invalid weights for '%s'" % key)
			return null
		for attr in weights:
			if not StatProfile.ATTRIBUTE_NAMES.has(attr):
				push_error("StatEffects: unknown attribute '%s'" % attr)
				return null
		result.action_attribute_weights[key] = weights

	var bases: Variant = data.get("action_base", {})
	if not (bases is Dictionary) or not _numbers_only(bases):
		push_error("StatEffects: invalid action_base")
		return null
	for key in ACTION_KEYS:
		if not bases.has(key):
			push_error("StatEffects: action_base missing '%s'" % key)
			return null
	result.action_base = bases

	var modifiers: Variant = data.get("instruction_modifiers", {})
	if not (modifiers is Dictionary):
		push_error("StatEffects: invalid instruction_modifiers")
		return null
	for group in modifiers:
		var group_data: Variant = modifiers[group]
		if not (group_data is Dictionary) or not _numbers_only(group_data):
			push_error("StatEffects: invalid modifier group '%s'" % group)
			return null
	result.instruction_modifiers = modifiers

	var ctx: Variant = data.get("context", {})
	if not (ctx is Dictionary) or not _numbers_only(ctx):
		push_error("StatEffects: invalid context block")
		return null
	for key in REQUIRED_CONTEXT:
		if not ctx.has(key):
			push_error("StatEffects: context missing '%s'" % key)
			return null
	result.context = ctx

	var sim_raw: Variant = data.get("simulation", {})
	if not (sim_raw is Dictionary):
		push_error("StatEffects: invalid simulation block")
		return null
	for key in SIMULATION_KEYS:
		if not (sim_raw as Dictionary).has(key):
			push_error("StatEffects: simulation missing '%s'" % key)
			return null
		var value: Variant = (sim_raw as Dictionary)[key]
		if key.ends_with("_weights"):
			if not (value is Array) or not _array_numbers_only(value):
				push_error("StatEffects: simulation weights '%s' must be numeric" % key)
				return null
		elif not (value is int or value is float):
			push_error("StatEffects: simulation value '%s' must be numeric" % key)
			return null
		result.simulation[key] = value

	var analysis_raw: Variant = data.get("analysis", {})
	if not (analysis_raw is Dictionary) or not _numbers_only(analysis_raw):
		push_error("StatEffects: invalid analysis block")
		return null
	for key in ANALYSIS_KEYS:
		if not (analysis_raw as Dictionary).has(key):
			push_error("StatEffects: analysis missing '%s'" % key)
			return null
	result.analysis = analysis_raw
	return result


static func _numbers_only(data: Dictionary) -> bool:
	for key in data:
		var value: Variant = data[key]
		if not (value is int or value is float):
			return false
	return true


static func _array_numbers_only(data: Array) -> bool:
	for value in data:
		if not (value is int or value is float):
			return false
	return true


func attribute_score(action_key: String, profile: StatProfile) -> float:
	var weights: Dictionary = action_attribute_weights.get(action_key, {})
	var neutral := float(context.get("attribute_neutral", 10.0))
	var scale := float(context.get("attribute_scale", 0.5))
	var total := 0.0
	for attr in weights:
		total += float(weights[attr]) * (float(profile.get_attribute(attr)) - neutral) * scale
	return total


func modifier(group: String, action_key: String) -> float:
	var groups: Dictionary = instruction_modifiers.get(group, {})
	if not (groups is Dictionary):
		return 0.0
	return float(groups.get(action_key, 0.0))


func base_score(action_key: String) -> float:
	return float(action_base.get(action_key, 0.0))


func context_value(key: String) -> float:
	return float(context.get(key, 0.0))


func simulation_value(key: String) -> float:
	return float(simulation.get(key, 0.0))


func simulation_weights(key: String) -> Array:
	var value: Variant = simulation.get(key, [])
	return value if value is Array else []


func analysis_value(key: String) -> float:
	return float(analysis.get(key, 0.0))
