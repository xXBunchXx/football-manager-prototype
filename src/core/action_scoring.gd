class_name ActionScoring
extends RefCounted

## Pure action-utility helpers shared by the live DecisionBrain and the bulk
## match simulator. Keeping this stateless means both paths read the same
## instruction/attribute tables and tactics tuning cannot drift apart.


static func instruction_bonus(action_key: String, instructions: PlayerInstructions, effects: StatEffects) -> float:
	if instructions == null:
		return 0.0
	var score := 0.0
	match instructions.duty:
		FMEnums.Duty.ATTACK:
			score += effects.modifier("duty_attack", action_key)
		FMEnums.Duty.DEFEND:
			score += effects.modifier("duty_defend", action_key)
	match instructions.passing_risk:
		FMEnums.PassingRisk.RISKY:
			score += effects.modifier("passing_risk_risky", action_key)
		FMEnums.PassingRisk.SAFE:
			score += effects.modifier("passing_risk_safe", action_key)
	match instructions.pressing:
		FMEnums.Pressing.HIGH:
			score += effects.modifier("pressing_high", action_key)
		FMEnums.Pressing.LOW:
			score += effects.modifier("pressing_low", action_key)
	match instructions.tackle_aggression:
		FMEnums.TackleAggression.AGGRESSIVE:
			score += effects.modifier("tackle_aggressive", action_key)
		FMEnums.TackleAggression.CAUTIOUS:
			score += effects.modifier("tackle_cautious", action_key)
	if action_key != "dribble":
		match instructions.runs:
			FMEnums.Runs.FORWARD:
				score += effects.modifier("runs_forward", action_key)
			FMEnums.Runs.HOLD:
				score += effects.modifier("runs_hold", action_key)
	match instructions.width:
		FMEnums.WidthMode.WIDE:
			score += effects.modifier("width_wide", action_key)
		FMEnums.WidthMode.NARROW:
			score += effects.modifier("width_narrow", action_key)
	if instructions.man_mark:
		score += effects.modifier("man_mark", action_key)
	return score


static func team_bonus(action_key: String, team: TeamInstructions, effects: StatEffects) -> float:
	if team == null:
		return 0.0
	var score := 0.0
	match team.mentality:
		FMEnums.Mentality.ATTACKING:
			score += effects.modifier("mentality_attacking", action_key)
		FMEnums.Mentality.DEFENSIVE:
			score += effects.modifier("mentality_defensive", action_key)
	match team.tempo:
		FMEnums.Tempo.FAST:
			score += effects.modifier("tempo_fast", action_key)
		FMEnums.Tempo.SLOW:
			score += effects.modifier("tempo_slow", action_key)
	match team.passing_style:
		FMEnums.PassingStyle.DIRECT:
			score += effects.modifier("passing_style_direct", action_key)
		FMEnums.PassingStyle.SHORT:
			score += effects.modifier("passing_style_short", action_key)
	match team.width:
		FMEnums.WidthMode.WIDE:
			score += effects.modifier("team_width_wide", action_key)
		FMEnums.WidthMode.NARROW:
			score += effects.modifier("team_width_narrow", action_key)
	return score


## Base + attribute + individual tactics + team tactics. Context bonuses (wide,
## near goal, pressure, space) are deliberately added by the caller because a
## live pitch can measure them and the fast simulator can only estimate them.
static func on_ball_score(action_key: String, profile: StatProfile, instructions: PlayerInstructions, team: TeamInstructions, effects: StatEffects) -> float:
	var score := effects.base_score(action_key)
	if profile != null:
		score += effects.attribute_score(action_key, profile)
	score += instruction_bonus(action_key, instructions, effects)
	score += team_bonus(action_key, team, effects)
	if action_key == "shoot" and instructions != null and instructions.shoot_on_sight:
		score += effects.modifier("shoot_on_sight", action_key)
	return score
