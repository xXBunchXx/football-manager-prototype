class_name FoulRule
extends RefCounted

## Detects tackles on a ball carrier with enough closing speed, then rolls a
## foul severity from tackle aggression, tackling skill and the contact speed.

var config: RulesConfig = null
var effects: StatEffects = null
var cooldowns: Dictionary = {}


func configure(rules_config: RulesConfig, stat_effects: StatEffects) -> void:
	config = rules_config
	effects = stat_effects


func tick(delta: float, ctx: MatchContext) -> RuleEvent:
	for player_id in cooldowns:
		cooldowns[player_id] = float(cooldowns[player_id]) - delta
	var carrier := ctx.ball_carrier()
	if carrier == null:
		return null

	for view in ctx.views:
		if view.last_decision == null or view.last_decision.action != FMEnums.Action.TACKLE:
			continue
		if view.side == carrier.side or float(cooldowns.get(view.player_id, 0.0)) > 0.0:
			continue
		var distance := MatchContext.flat_distance(view.global_position, carrier.global_position)
		if distance > effects.context_value("tackle_radius_m"):
			continue
		var closing := (Vector3(view.linear_velocity.x, 0.0, view.linear_velocity.z) - Vector3(carrier.linear_velocity.x, 0.0, carrier.linear_velocity.z)).length()
		if closing < config.value("foul", "closing_speed_threshold_mps"):
			continue
		if RngService.randf() >= _foul_chance(view, closing):
			continue

		cooldowns[view.player_id] = config.value("foul", "tackle_cooldown_seconds")
		var severity := _roll_severity()
		var state: PlayerState = view.match_state
		if severity == FMEnums.FoulSeverity.YELLOW:
			state.apply_card(FMEnums.CardColor.YELLOW)
		elif severity == FMEnums.FoulSeverity.RED:
			state.apply_card(FMEnums.CardColor.RED)
		var label := "foul by %s (%s)" % [view.player_id, _severity_name(severity)]
		return RuleEvent.create(RuleEvent.Type.FOUL, label, view.player_id, carrier.side, severity, FMEnums.RestartType.FREE_KICK, view.global_position)
	return null


func _foul_chance(view: RigidBody3D, closing: float) -> float:
	var profile: StatProfile = view.player_data.attributes
	var instructions: PlayerInstructions = view.instructions
	var chance := config.value("foul", "base_chance")
	chance += closing * config.value("foul", "closing_speed_bonus_per_mps")
	if instructions.tackle_aggression == FMEnums.TackleAggression.AGGRESSIVE:
		chance += config.value("foul", "aggression_bonus")
	chance -= float(profile.tackling) * config.value("foul", "skill_reduction_per_point")
	return clampf(chance, 0.0, 1.0)


func _roll_severity() -> int:
	var roll := RngService.randf()
	if roll < config.value("foul", "red_chance"):
		return FMEnums.FoulSeverity.RED
	if roll < config.value("foul", "red_chance") + config.value("foul", "yellow_chance"):
		return FMEnums.FoulSeverity.YELLOW
	return FMEnums.FoulSeverity.FOUL


static func _severity_name(severity: int) -> String:
	match severity:
		FMEnums.FoulSeverity.RED: return "red card"
		FMEnums.FoulSeverity.YELLOW: return "yellow card"
		_: return "free kick"
