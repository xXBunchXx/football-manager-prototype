class_name FastMatchSimulator
extends RefCounted

## Bulk match model. It does not run Jolt or render anything: each possession
## is resolved from the same attribute/instruction tables as the live brain, so
## a season can be simulated in seconds and the resulting player/team records
## can be analysed for balance problems. Live matches remain the physics truth.

var effects: StatEffects
var rules_config: RulesConfig


func _init(stat_effects: StatEffects, config: RulesConfig) -> void:
	effects = stat_effects
	rules_config = config


func simulate(fixture: Fixture, source_value: String = "fast") -> MatchRecord:
	var stats := MatchStats.new()
	var home_team := _team_instructions(fixture.home_club_id)
	var away_team := _team_instructions(fixture.away_club_id)
	var home_side := _build_side(fixture.home_club_id, FMEnums.Side.HOME, home_team)
	var away_side := _build_side(fixture.away_club_id, FMEnums.Side.AWAY, away_team)
	if home_side.is_empty() or away_side.is_empty():
		push_error("FastMatchSimulator: fixture has an unknown club")
		return null

	_simulate_side(home_side, away_side, FMEnums.Side.HOME, FMEnums.Side.AWAY, stats)
	_simulate_side(away_side, home_side, FMEnums.Side.AWAY, FMEnums.Side.HOME, stats)

	var result := MatchResult.create(
		fixture,
		int(stats.get_side(FMEnums.Side.HOME)["goals"]),
		int(stats.get_side(FMEnums.Side.AWAY)["goals"])
	)
	return MatchRecord.from_match(fixture, result, stats.to_dict(), source_value)


func _simulate_side(attackers: Array, defenders: Array, attack_side: int, defend_side: int, stats: MatchStats) -> void:
	var count := _possession_count(attackers[0]["team"], defenders[0]["team"])
	for _possession in count:
		var carrier: Dictionary = _pick(attackers, _touch_weights(attackers))
		stats.record_touch(String(carrier["id"]), attack_side)
		stats.record_control(attack_side, effects.simulation_value("possession_seconds_per_possession"), String(carrier["id"]))

		var defender: Dictionary = _pick(defenders, _defender_weights(defenders))
		if _challenge(defender, carrier, attack_side, defend_side, stats):
			continue

		var zone := _zone()
		var action := _choose_action(carrier, zone)
		match action:
			"pass", "cross", "switch":
				_execute_pass(action, zone, carrier, attackers, attack_side, stats)
			"dribble":
				_execute_dribble(carrier, defender, attack_side, defend_side, stats)
			"shoot", _:
				_execute_shoot(carrier, defenders, zone, attack_side, defend_side, stats)


func _possession_count(team: TeamInstructions, opponent: TeamInstructions) -> int:
	var value := effects.simulation_value("possessions_per_team")
	value += ActionScoring.team_bonus("pass", team, effects) * effects.simulation_value("tempo_possession_scale") * 0.1
	value += ActionScoring.team_bonus("pass", opponent, effects) * effects.simulation_value("tempo_possession_scale") * 0.05
	var tempo_scale := effects.simulation_value("tempo_possession_scale")
	if team.tempo == FMEnums.Tempo.FAST:
		value += tempo_scale
	elif team.tempo == FMEnums.Tempo.SLOW:
		value -= tempo_scale
	if team.mentality == FMEnums.Mentality.ATTACKING:
		value += effects.simulation_value("mentality_possession_scale")
	elif team.mentality == FMEnums.Mentality.DEFENSIVE:
		value -= effects.simulation_value("mentality_possession_scale")
	value += RngService.randf_range(-effects.simulation_value("action_noise"), effects.simulation_value("action_noise"))
	return int(maxf(20.0, value))


func _challenge(defender: Dictionary, carrier: Dictionary, attack_side: int, defend_side: int, stats: MatchStats) -> bool:
	var chance_value := effects.simulation_value("tackle_attempt_base")
	var modifier_scale := effects.simulation_value("tackle_modifier_chance_scale")
	chance_value += ActionScoring.instruction_bonus("tackle", defender["instructions"], effects) * modifier_scale
	chance_value += ActionScoring.team_bonus("tackle", defender["team"], effects) * modifier_scale
	chance_value = clampf(chance_value, effects.simulation_value("min_chance"), effects.simulation_value("max_chance"))
	if not RngService.chance(chance_value):
		return false

	var defender_id := String(defender["id"])
	stats.record_tackle_attempt(defender_id, defend_side)
	var win_value := effects.simulation_value("tackle_win_base")
	var attr_scale := effects.simulation_value("tackle_win_attribute_scale")
	var neutral := effects.context_value("attribute_neutral")
	var defender_profile: StatProfile = defender["profile"]
	var carrier_profile: StatProfile = carrier["profile"]
	win_value += (float(defender_profile.tackling) - neutral) * attr_scale
	win_value += (float(defender_profile.strength) - neutral) * attr_scale
	win_value -= (float(carrier_profile.technique) - neutral) * attr_scale
	win_value -= (float(carrier_profile.composure) - neutral) * attr_scale * 0.5
	win_value = clampf(win_value, effects.simulation_value("min_chance"), effects.simulation_value("max_chance"))
	if RngService.chance(win_value):
		stats.record_tackle_win(defender_id, defend_side)
		stats.record_touch(defender_id, defend_side)
		stats.record_control(defend_side, effects.simulation_value("possession_seconds_per_possession") * 0.5, defender_id)
		return true
	if RngService.chance(effects.simulation_value("tackle_foul_chance")):
		var severity := _roll_foul_severity()
		stats.record_event(RuleEvent.create(
			RuleEvent.Type.FOUL, "foul by %s" % defender_id, defender_id,
			attack_side, severity, FMEnums.RestartType.FREE_KICK, Vector3.ZERO
		))
		return true
	return false


func _zone() -> String:
	var roll := RngService.randf()
	if roll < effects.simulation_value("wide_zone_chance"):
		return "wide"
	if roll < effects.simulation_value("wide_zone_chance") + effects.simulation_value("attacking_third_chance"):
		return "attacking"
	if roll < effects.simulation_value("wide_zone_chance") + effects.simulation_value("attacking_third_chance") + effects.simulation_value("defensive_third_chance"):
		return "defensive"
	return "middle"


func _choose_action(carrier: Dictionary, zone: String) -> String:
	var profile: StatProfile = carrier["profile"]
	var instructions: PlayerInstructions = carrier["instructions"]
	var team: TeamInstructions = carrier["team"]
	var noise := effects.simulation_value("action_noise")
	var scores := {}
	for action in ["pass", "cross", "switch", "dribble", "shoot"]:
		var score := ActionScoring.on_ball_score(action, profile, instructions, team, effects)
		match action:
			"cross":
				score += effects.simulation_value("cross_zone_bonus") if zone == "wide" else -effects.simulation_value("cross_zone_bonus")
			"switch":
				score += effects.simulation_value("switch_zone_bonus") if zone != "wide" else -effects.simulation_value("switch_zone_bonus")
			"shoot":
				score += effects.simulation_value("shoot_zone_bonus") if zone == "attacking" else -effects.simulation_value("shoot_zone_bonus")
			"dribble":
				if zone == "attacking":
					score += effects.simulation_value("dribble_attacking_bonus")
				elif zone == "defensive":
					score -= effects.simulation_value("dribble_defensive_penalty")
		scores[action] = score + RngService.randf_range(-noise, noise)
	return _best_key(scores)


func _execute_pass(action: String, zone: String, carrier: Dictionary, attackers: Array, attack_side: int, stats: MatchStats) -> void:
	var receiver := _pick_receiver(attackers, String(carrier["id"]))
	var receiver_id := String(receiver["id"])
	stats.record_kick(attack_side, true, action, String(carrier["id"]), receiver_id)

	var profile: StatProfile = carrier["profile"]
	var neutral := effects.context_value("attribute_neutral")
	var scale := effects.simulation_value("pass_success_attribute_scale")
	var chance_value := effects.simulation_value("pass_success_base")
	chance_value += (float(profile.passing) + float(profile.vision) + float(profile.first_touch) + float(profile.composure) - neutral * 4.0) * scale
	if action == "cross":
		chance_value -= effects.simulation_value("cross_success_penalty")
	elif action == "switch":
		chance_value -= effects.simulation_value("switch_success_penalty")
	var instructions: PlayerInstructions = carrier["instructions"]
	if instructions.passing_risk == FMEnums.PassingRisk.RISKY:
		chance_value -= effects.simulation_value("pass_risky_penalty")
	elif instructions.passing_risk == FMEnums.PassingRisk.SAFE:
		chance_value += effects.simulation_value("pass_safe_bonus")
	var team: TeamInstructions = carrier["team"]
	if team.passing_style == FMEnums.PassingStyle.DIRECT:
		chance_value -= effects.simulation_value("pass_direct_penalty")
	elif team.passing_style == FMEnums.PassingStyle.SHORT:
		chance_value += effects.simulation_value("pass_short_bonus")
	if zone == "wide" and action == "pass":
		chance_value -= effects.simulation_value("cross_success_penalty") * 0.5
	chance_value = clampf(chance_value, effects.simulation_value("min_chance"), effects.simulation_value("max_chance"))
	if RngService.chance(chance_value):
		stats.record_pass_completion(String(carrier["id"]), receiver_id, attack_side, receiver_id)
		stats.record_touch(receiver_id, attack_side)
		stats.record_control(attack_side, effects.simulation_value("possession_seconds_per_possession") * 0.25, receiver_id)


func _execute_dribble(carrier: Dictionary, defender: Dictionary, attack_side: int, defend_side: int, stats: MatchStats) -> void:
	var profile: StatProfile = carrier["profile"]
	var neutral := effects.context_value("attribute_neutral")
	var scale := effects.simulation_value("dribble_success_attribute_scale")
	var chance_value := effects.simulation_value("dribble_success_base")
	chance_value += (float(profile.technique) + float(profile.pace) + float(profile.acceleration) - neutral * 3.0) * scale
	chance_value -= (float((defender["profile"] as StatProfile).tackling) - neutral) * scale
	chance_value = clampf(chance_value, effects.simulation_value("min_chance"), effects.simulation_value("max_chance"))
	var carrier_id := String(carrier["id"])
	if RngService.chance(chance_value):
		stats.record_dribble(carrier_id, attack_side, true)
		stats.record_control(attack_side, effects.simulation_value("possession_seconds_per_possession") * 0.35, carrier_id)
		return
	stats.record_dribble(carrier_id, attack_side, false)
	var defender_id := String(defender["id"])
	stats.record_tackle_attempt(defender_id, defend_side)
	stats.record_tackle_win(defender_id, defend_side)
	stats.record_touch(defender_id, defend_side)
	stats.record_control(defend_side, effects.simulation_value("possession_seconds_per_possession") * 0.35, defender_id)


func _execute_shoot(carrier: Dictionary, defenders: Array, zone: String, attack_side: int, defend_side: int, stats: MatchStats) -> void:
	var carrier_id := String(carrier["id"])
	stats.record_kick(attack_side, false, "shoot", carrier_id, "")
	var profile: StatProfile = carrier["profile"]
	var neutral := effects.context_value("attribute_neutral")
	var scale := effects.simulation_value("shot_goal_attribute_scale")
	var chance_value := effects.simulation_value("shot_goal_base")
	chance_value += (float(profile.finishing) + float(profile.composure) + float(profile.positioning) - neutral * 3.0) * scale
	if zone == "wide":
		chance_value *= 1.0 - effects.simulation_value("shot_wide_penalty")
	chance_value = clampf(chance_value, effects.simulation_value("min_chance"), effects.simulation_value("max_chance"))
	if RngService.chance(chance_value):
		stats.record_shot_on_target(carrier_id, attack_side)
		stats.record_event(RuleEvent.create(RuleEvent.Type.GOAL, "goal by %s" % carrier_id, carrier_id, attack_side))
		return

	var keeper := _keeper(defenders)
	if keeper.is_empty():
		return
	var keeper_profile: StatProfile = keeper["profile"]
	var save_value := effects.simulation_value("shot_save_base")
	save_value += (float(keeper_profile.positioning) + float(keeper_profile.anticipation) + float(keeper_profile.heading) - neutral * 3.0) * effects.simulation_value("shot_save_keeper_scale")
	save_value = clampf(save_value, effects.simulation_value("min_chance"), effects.simulation_value("max_chance"))
	if RngService.chance(save_value):
		stats.record_shot_on_target(carrier_id, attack_side)
		stats.record_event(RuleEvent.create(RuleEvent.Type.SAVE, "save by %s" % keeper["id"], String(keeper["id"]), defend_side))
	elif RngService.chance(effects.simulation_value("shot_on_target_base")):
		stats.record_shot_on_target(carrier_id, attack_side)


func _build_side(club_id: String, side: int, team: TeamInstructions) -> Array:
	var result: Array = []
	var club := _find_club(club_id)
	if club == null:
		return result
	var slots: Array = effects.simulation_weights("touch_slot_weights")
	for i in club.get_starters().size():
		var player: PlayerData = club.get_starters()[i]
		if player == null:
			continue
		var instructions: PlayerInstructions = GameData.player_instructions.get(player.id, InstructionDefaults.for_role(player.role_id))
		result.append({
			"id": player.id,
			"club_id": club_id,
			"side": side,
			"slot": i,
			"role": player.role_id,
			"profile": player.attributes,
			"instructions": instructions,
			"team": team,
		})
	return result


func _touch_weights(players: Array) -> Array:
	var slots: Array = effects.simulation_weights("touch_slot_weights")
	var scale := effects.simulation_value("touch_attribute_scale")
	var weights: Array = []
	for player in players:
		var profile: StatProfile = player["profile"]
		var slot_weight := 1.0
		if int(player["slot"]) < slots.size():
			slot_weight = float(slots[int(player["slot"])])
		var skill := 1.0 + (float(profile.technique) - effects.context_value("attribute_neutral")) * scale
		weights.append(maxf(0.0, slot_weight * skill))
	return weights


func _defender_weights(players: Array) -> Array:
	var slots: Array = effects.simulation_weights("receiver_slot_weights")
	var weights: Array = []
	for player in players:
		var slot_weight := 1.0
		if int(player["slot"]) < slots.size():
			slot_weight = float(slots[int(player["slot"])])
		if player["role"] == "gk":
			slot_weight = 0.0
		weights.append(slot_weight)
	return weights


func _pick_receiver(players: Array, carrier_id: String) -> Dictionary:
	var slots: Array = effects.simulation_weights("receiver_slot_weights")
	var scale := effects.simulation_value("receiver_attribute_scale")
	var weights: Array = []
	for player in players:
		if String(player["id"]) == carrier_id:
			weights.append(0.0)
			continue
		var slot_weight := 1.0
		if int(player["slot"]) < slots.size():
			slot_weight = float(slots[int(player["slot"])])
		var profile: StatProfile = player["profile"]
		var skill := 1.0 + (float(profile.passing) + float(profile.vision) - effects.context_value("attribute_neutral") * 2.0) * scale
		weights.append(maxf(0.0, slot_weight * skill))
	return _pick(players, weights)


func _keeper(players: Array) -> Dictionary:
	for player in players:
		if player["role"] == "gk":
			return player
	return {}


func _pick(items: Array, weights: Array) -> Dictionary:
	var total := 0.0
	for weight in weights:
		total += float(weight)
	if items.is_empty() or total <= 0.0:
		return items[0] if not items.is_empty() else {}
	var roll := RngService.randf() * total
	var running := 0.0
	for i in items.size():
		running += float(weights[i])
		if roll <= running:
			return items[i]
	return items[items.size() - 1]


func _best_key(scores: Dictionary) -> String:
	var best := ""
	var best_score := -INF
	for key in scores:
		var value := float(scores[key])
		if value > best_score:
			best_score = value
			best = String(key)
	return best


func _roll_foul_severity() -> int:
	if rules_config == null:
		return FMEnums.FoulSeverity.FOUL
	var roll := RngService.randf()
	if roll < rules_config.value("foul", "red_chance"):
		return FMEnums.FoulSeverity.RED
	if roll < rules_config.value("foul", "red_chance") + rules_config.value("foul", "yellow_chance"):
		return FMEnums.FoulSeverity.YELLOW
	return FMEnums.FoulSeverity.FOUL


func _team_instructions(club_id: String) -> TeamInstructions:
	var value: Variant = GameData.team_instructions.get(club_id, null)
	return value if value is TeamInstructions else TeamInstructions.new()


func _find_club(club_id: String) -> ClubData:
	for club in GameData.clubs:
		if club.id == club_id:
			return club
	return null
