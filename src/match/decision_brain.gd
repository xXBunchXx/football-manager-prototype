class_name DecisionBrain
extends RefCounted

## Utility scoring brain. Every candidate action is scored from attributes,
## instructions, physical state and context; the highest score wins.

const ACTION_TO_ENUM := {
	"shoot": FMEnums.Action.SHOOT,
	"pass": FMEnums.Action.PASS,
	"dribble": FMEnums.Action.DRIBBLE,
	"press": FMEnums.Action.PRESS,
	"tackle": FMEnums.Action.TACKLE,
	"support": FMEnums.Action.SUPPORT,
	"chase": FMEnums.Action.CHASE,
	"mark": FMEnums.Action.MARK,
}
const EXERTION_KEYS := ["press", "chase", "dribble", "tackle"]

var effects: StatEffects


func _init(stat_effects: StatEffects) -> void:
	effects = stat_effects


func decide(view: RigidBody3D, ctx: MatchContext) -> DecisionResult:
	var profile: StatProfile = view.player_data.attributes
	var instructions: PlayerInstructions = view.instructions
	var state: PlayerState = view.match_state

	var scores := {}
	for key in StatEffects.ACTION_KEYS:
		var score := effects.base_score(key)
		score += effects.attribute_score(key, profile)
		score += _instruction_score(key, instructions)
		score += _stamina_score(key, state)
		score += _context_score(key, view, ctx, instructions)
		scores[key] = score

	var best_key := ""
	var best_score := -INF
	for key in scores:
		var value := float(scores[key])
		if value > best_score:
			best_score = value
			best_key = String(key)

	var target := _target_for(best_key, view, ctx, instructions)
	var pass_to := ""
	if best_key == "pass":
		var mate := ctx.best_pass_target(view)
		if mate != null:
			pass_to = mate.player_id
			target = mate.global_position
	return DecisionResult.create(ACTION_TO_ENUM[best_key], target, scores, pass_to)


func _instruction_score(key: String, instructions: PlayerInstructions) -> float:
	var score := 0.0
	match instructions.duty:
		FMEnums.Duty.ATTACK:
			score += effects.modifier("duty_attack", key)
		FMEnums.Duty.DEFEND:
			score += effects.modifier("duty_defend", key)
	if instructions.shoot_on_sight:
		score += effects.modifier("shoot_on_sight", key)
	match instructions.passing_risk:
		FMEnums.PassingRisk.RISKY:
			score += effects.modifier("passing_risk_risky", key)
		FMEnums.PassingRisk.SAFE:
			score += effects.modifier("passing_risk_safe", key)
	match instructions.pressing:
		FMEnums.Pressing.HIGH:
			score += effects.modifier("pressing_high", key)
		FMEnums.Pressing.LOW:
			score += effects.modifier("pressing_low", key)
	match instructions.tackle_aggression:
		FMEnums.TackleAggression.AGGRESSIVE:
			score += effects.modifier("tackle_aggressive", key)
		FMEnums.TackleAggression.CAUTIOUS:
			score += effects.modifier("tackle_cautious", key)
	match instructions.runs:
		FMEnums.Runs.FORWARD:
			score += effects.modifier("runs_forward", key)
		FMEnums.Runs.HOLD:
			score += effects.modifier("runs_hold", key)
	if instructions.man_mark:
		score += effects.modifier("man_mark", key)
	return score


func _stamina_score(key: String, state: PlayerState) -> float:
	var floor_value := effects.context_value("stamina_floor")
	if state.stamina >= floor_value:
		return 0.0
	var deficit := floor_value - state.stamina
	var scale := effects.context_value("stamina_penalty_active_scale") if EXERTION_KEYS.has(key) else effects.context_value("stamina_penalty_passive_scale")
	return -deficit * effects.context_value("stamina_penalty_per_point") * scale


func _context_score(key: String, view: RigidBody3D, ctx: MatchContext, instructions: PlayerInstructions) -> float:
	var score := 0.0
	var ball_position := ctx.ball.global_position if ctx.ball != null else view.global_position
	match key:
		"shoot":
			var distance := MatchContext.flat_distance(view.global_position, ctx.goal_for(view))
			var radius := effects.context_value("shoot_range_m")
			if distance < radius:
				score += effects.context_value("shoot_near_goal_bonus") * (1.0 - distance / radius)
		"press", "chase":
			var distance := MatchContext.flat_distance(view.global_position, ball_position)
			var radius := effects.context_value("press_radius_m")
			if distance < radius:
				score += effects.context_value("press_proximity_bonus") * (1.0 - distance / radius)
		"tackle":
			var carrier := ctx.ball_carrier()
			if carrier != null and carrier != view:
				var distance := MatchContext.flat_distance(view.global_position, carrier.global_position)
				if distance < effects.context_value("tackle_radius_m"):
					score += effects.context_value("tackle_proximity_bonus")
		"pass":
			if ctx.is_pressured(view, effects.context_value("pressure_radius_m")):
				score += effects.context_value("pressure_pass_bonus")
		"mark":
			if instructions.man_mark:
				score += effects.context_value("mark_proximity_bonus")
	return score


func _target_for(key: String, view: RigidBody3D, ctx: MatchContext, instructions: PlayerInstructions) -> Vector3:
	var cfg := GameData.config
	var ball_position := ctx.ball.global_position if ctx.ball != null else view.global_position
	match key:
		"shoot":
			return ctx.goal_for(view)
		"chase", "press", "tackle":
			var carrier := ctx.ball_carrier()
			return carrier.global_position if carrier != null else ball_position
		"dribble":
			return ctx.goal_for(view).lerp(view.global_position, 1.0 - effects.context_value("dribble_advance_m") / cfg.pitch_length_m)
		"mark":
			var marker := ctx.nearest_opponent(view, 100.0)
			return marker.global_position if marker != null else ball_position
		"support":
			var depth := 0.0
			match instructions.support_depth:
				FMEnums.SupportDepth.DEEP:
					depth = -effects.context_value("support_deep_m")
				FMEnums.SupportDepth.ADVANCED:
					depth = effects.context_value("support_advanced_m")
			var width := 0.0
			match instructions.width:
				FMEnums.WidthMode.NARROW:
					width = effects.context_value("support_narrow_m")
				FMEnums.WidthMode.WIDE:
					width = effects.context_value("support_wide_m")
			var lane := 1.0 if view.global_position.z >= 0.0 else -1.0
			var z := clampf(ball_position.z + lane * width, -cfg.pitch_width_m * 0.5 + 2.0, cfg.pitch_width_m * 0.5 - 2.0)
			return Vector3(ball_position.x + ctx.attack_sign(view) * depth, 0.0, z)
		_:
			return ball_position
