class_name StatEffects
extends RefCounted

## Typed view of data/stat_effects.json. All decision weights and context
## thresholds live in that file so balance changes need no code edits.

const FILE := "res://data/stat_effects.json"

const ACTION_KEYS := [
	"shoot", "pass", "dribble", "press", "tackle", "support", "chase", "mark",
]

const REQUIRED_CONTEXT := [
	"attribute_neutral", "attribute_scale", "stamina_floor",
	"stamina_penalty_per_point", "shoot_range_m", "shoot_near_goal_bonus",
	"shoot_unpressured_bonus", "shoot_pressure_penalty",
	"press_radius_m", "press_proximity_bonus", "tackle_radius_m",
	"tackle_proximity_bonus", "pressure_radius_m", "pressure_pass_bonus",
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
]

var action_attribute_weights: Dictionary = {}
var action_base: Dictionary = {}
var instruction_modifiers: Dictionary = {}
var context: Dictionary = {}


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
	return result


static func _numbers_only(data: Dictionary) -> bool:
	for key in data:
		var value: Variant = data[key]
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
