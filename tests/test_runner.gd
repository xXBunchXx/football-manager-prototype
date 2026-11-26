extends Node

## Headless entry point. Run with:
##   Godot_v4.7.2-stable_linux.x86_64 --headless --path <project> res://tests/test_scene.tscn

var _passed: int = 0
var _failed: int = 0
var _received_events: Array[String] = []


func _ready() -> void:
	MatchEvents.event_logged.connect(_on_event_logged)
	_test_config()
	_test_data()
	_test_instructions()
	await _test_decisions()
	_test_match_scene()
	await _test_ball()
	_test_rng()
	_test_events()
	_test_save()
	_test_fixture_loader()
	print("[tests] passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)


func _on_event_logged(text: String) -> void:
	_received_events.append(text)


func _test_config() -> void:
	var cfg := MatchConfig.new()
	_check(cfg.pitch_length_m == 105.0 and cfg.pitch_width_m == 68.0, "MatchConfig pitch dimensions")
	_check(absf(cfg.get_decision_interval() - (1.0 / 6.0)) < 0.0001, "MatchConfig decision interval")
	_check(cfg.speed_steps.size() == 4, "MatchConfig speed steps")


func _test_rng() -> void:
	RngService.set_seed(4242)
	var first: Array[float] = []
	for i in 5:
		first.append(RngService.randf())
	RngService.set_seed(4242)
	var second: Array[float] = []
	for i in 5:
		second.append(RngService.randf())

	var reproducible := first.size() == second.size()
	for i in first.size():
		if absf(first[i] - second[i]) > 0.000001:
			reproducible = false
	_check(reproducible, "RngService reproduces a seeded sequence")

	var in_range := true
	for value in second:
		if value < 0.0 or value >= 1.0:
			in_range = false
	_check(in_range, "RngService.randf stays in [0,1)")


func _test_events() -> void:
	MatchEvents.log_event("phase1-test")
	var last := _received_events[_received_events.size() - 1] if _received_events.size() > 0 else ""
	_check(_received_events.size() >= 1 and last == "phase1-test", "MatchEvents signal bus")


func _test_save() -> void:
	var test_path := "user://fm_phase1_test.json"
	SaveGame.set_path(test_path)
	var ok := SaveGame.save_state({"alpha": 7})
	var loaded := SaveGame.load_state()
	_check(ok and loaded.get("alpha", -1) == 7, "SaveGame round trip")

	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("fm_phase1_test.json")
	SaveGame.set_path("user://fm_save.json")


func _test_fixture_loader() -> void:
	var path := "user://fm_phase1_fixture.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("{\"name\": \"Test FC\", \"tier\": 1}")
		file.close()

	var data: Variant = FixtureLoader.load_json(path)
	var parsed_ok := data is Dictionary
	if parsed_ok:
		parsed_ok = FixtureLoader.has_keys(data, ["name", "tier"])
	_check(parsed_ok, "FixtureLoader parses JSON and checks keys")

	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("fm_phase1_fixture.json")


func _test_data() -> void:
	var loaded := GameData.load_fixtures()
	_check(loaded, "fixtures load from res://data/")
	_check(GameData.clubs.size() == 6, "six clubs loaded")
	_check(GameData.leagues.size() == 1, "one league loaded")
	_check(GameData.players_by_id.size() == 108, "108 unique players loaded")

	var structure_ok := true
	var attributes_ok := true
	var seen_ids := {}
	var cfg := MatchConfig.new()
	for club in GameData.clubs:
		if club.squad.size() != cfg.squad_size:
			structure_ok = false
		if club.get_starters().size() != cfg.starters_per_club:
			structure_ok = false
		if club.get_bench().size() != cfg.squad_size - cfg.starters_per_club:
			structure_ok = false
		for player in club.squad:
			if seen_ids.has(player.id):
				structure_ok = false
			seen_ids[player.id] = true
			for key in StatProfile.ATTRIBUTE_NAMES:
				var value := player.attributes.get_attribute(key)
				if value < StatProfile.MIN_VALUE or value > StatProfile.MAX_VALUE:
					attributes_ok = false
	_check(structure_ok, "squad sizes, starter counts and unique ids")
	_check(attributes_ok, "all attributes within 1..20")

	var weak := _average_tier(FMEnums.TeamTier.WEAK)
	var mid := _average_tier(FMEnums.TeamTier.MID)
	var strong := _average_tier(FMEnums.TeamTier.STRONG)
	_check(weak < mid and mid < strong, "tier averages ordered weak < mid < strong")
	print("[data] tier averages: weak=%.2f mid=%.2f strong=%.2f" % [weak, mid, strong])

	var bad_attributes := StatProfile.new().to_dict()
	bad_attributes["pace"] = 99
	_check(not StatProfile.is_valid_dict(bad_attributes), "StatProfile rejects out-of-range values")

	var sample: PlayerData = GameData.clubs[0].squad[0]
	var rebuilt := PlayerData.from_dict(sample.to_dict())
	_check(rebuilt != null and rebuilt.display_name() == sample.display_name(), "PlayerData round trip")


func _test_instructions() -> void:
	var all_valid := true
	for player_id in GameData.players_by_id:
		var inst: PlayerInstructions = GameData.player_instructions.get(player_id)
		if inst == null or not PlayerInstructions.is_valid_dict(inst.to_dict()):
			all_valid = false
	_check(all_valid, "every player has valid typed instructions")
	_check(GameData.player_instructions.size() == 108, "instructions built for all players")

	var teams_valid := true
	for club_id in GameData.team_instructions:
		var ti: TeamInstructions = GameData.team_instructions[club_id]
		if not TeamInstructions.is_valid_dict(ti.to_dict()):
			teams_valid = false
	_check(teams_valid and GameData.team_instructions.size() == 6, "every club has valid team instructions")

	var st := InstructionDefaults.for_role("st")
	var cb := InstructionDefaults.for_role("cb")
	_check(st.duty == FMEnums.Duty.ATTACK and st.shoot_on_sight, "ST baseline is attacking and shoots on sight")
	_check(cb.duty == FMEnums.Duty.DEFEND and not cb.shoot_on_sight, "CB baseline is defensive and holds shots")

	var overridden: PlayerInstructions = GameData.player_instructions["ashford-city-10"]
	_check(not overridden.shoot_on_sight and overridden.passing_risk == FMEnums.PassingRisk.BALANCED, "JSON player overrides win over role baseline")
	var untouched: PlayerInstructions = GameData.player_instructions["kingsport-rovers-10"]
	_check(untouched.shoot_on_sight, "players without overrides keep role baseline")
	_check(not PlayerInstructions.is_valid_dict({"duty": "DEFEND", "bogus": 1}), "instruction validation rejects unknown keys")
	_check(PlayerInstructions.is_valid_dict({"duty": "DEFEND"}, true), "instruction validation accepts named partial overrides")

	var ashford_team: TeamInstructions = GameData.team_instructions["ashford-city"]
	var kingsport_team: TeamInstructions = GameData.team_instructions["kingsport-rovers"]
	_check(ashford_team.mentality == FMEnums.Mentality.ATTACKING, "JSON team override wins")
	_check(kingsport_team.mentality == FMEnums.Mentality.BALANCED, "team default applies without override")

	var sample: PlayerData = GameData.clubs[0].squad[0]
	var before := sample.to_dict()
	var state := PlayerState.for_player(sample)
	state.player_id = "hacked"
	state.spend_stamina(1000.0)
	state.adjust_morale(-10.0)
	state.apply_card(FMEnums.CardColor.YELLOW)
	state.apply_card(FMEnums.CardColor.YELLOW)
	_check(sample.to_dict() == before, "PlayerState never mutates PlayerData")
	_check(state.stamina == 0.0 and state.morale == 0.0, "PlayerState clamps physical and mental values")
	_check(state.red_cards == 1 and state.is_suspended(), "two yellows produce a suspension")
	_check(state.is_valid(), "mutated PlayerState remains valid")

	var with_duty := PlayerState.for_player(sample)
	with_duty.duty_override = FMEnums.Duty.ATTACK
	_check(with_duty.effective_duty(cb) == FMEnums.Duty.ATTACK, "duty override beats instruction duty")


func _make_view(player: PlayerData, club: ClubData, is_home: bool, position: Vector3, ctx: MatchContext) -> RigidBody3D:
	var packed: PackedScene = load("res://scenes/player_view.tscn")
	var view := packed.instantiate() as RigidBody3D
	add_child(view)
	view.setup(player, club, is_home)
	view.global_position = position
	ctx.add_view(view)
	return view


func _test_decisions() -> void:
	var effects := StatEffects.load()
	_check(effects != null, "stat effects load and validate")
	if effects == null:
		return
	_check(effects.action_attribute_weights.size() == StatEffects.ACTION_KEYS.size(), "all action weight tables present")
	_check(effects.modifier("shoot_on_sight", "shoot") > 0.0, "shoot-on-sight modifier is positive")

	var brain := DecisionBrain.new(effects)
	var ctx := MatchContext.new()
	var ball_scene: PackedScene = load("res://scenes/ball.tscn")
	var ball := ball_scene.instantiate() as Ball
	add_child(ball)
	await get_tree().physics_frame
	ctx.ball = ball
	ball.reset_to(Vector3(30, 1, 0))

	var strong_club: ClubData = GameData.clubs[1]
	var weak_club: ClubData = GameData.clubs[4]
	var striker := _make_view(strong_club.get_starters()[9], strong_club, true, Vector3(38, 1, 0), ctx)
	var striker_decision := brain.decide(striker, ctx)
	_check(striker_decision.action == FMEnums.Action.SHOOT, "striker inside shooting range chooses shoot")

	var midfielder := _make_view(strong_club.get_starters()[6], strong_club, true, Vector3(-8, 1, 0), ctx)
	var base_scores: Dictionary = brain.decide(midfielder, ctx).scores
	midfielder.instructions = midfielder.instructions.with_overrides({"shoot_on_sight": true})
	var boosted_scores: Dictionary = brain.decide(midfielder, ctx).scores
	_check(boosted_scores["shoot"] > base_scores["shoot"], "shoot-on-sight lifts shoot utility")

	var fresh := _make_view(strong_club.get_starters()[2], strong_club, true, Vector3(-30, 1, 8), ctx)
	var tired := _make_view(strong_club.get_starters()[2], strong_club, true, Vector3(-30, 1, -8), ctx)
	tired.match_state.stamina = 10.0
	_check(float(brain.decide(tired, ctx).scores["press"]) < float(brain.decide(fresh, ctx).scores["press"]), "low stamina reduces pressing utility")

	var strong_st := _make_view(strong_club.get_starters()[9], strong_club, true, Vector3(20, 1, 20), ctx)
	var weak_st := _make_view(weak_club.get_starters()[9], weak_club, false, Vector3(20, 1, -20), ctx)
	_check(float(brain.decide(strong_st, ctx).scores["shoot"]) > float(brain.decide(weak_st, ctx).scores["shoot"]), "stronger attributes raise shoot utility")

	var deep_cb := _make_view(strong_club.get_starters()[1], strong_club, true, Vector3(-25, 1, 15), ctx)
	deep_cb.instructions = deep_cb.instructions.with_overrides({"support_depth": "DEEP"})
	var deep_target: Vector3 = brain.decide(deep_cb, ctx).target
	deep_cb.instructions = deep_cb.instructions.with_overrides({"support_depth": "ADVANCED"})
	var high_target: Vector3 = brain.decide(deep_cb, ctx).target
	_check(deep_target.x < high_target.x, "support depth shifts the target up or down pitch")

	var agent := PlayerAgent.new(striker, brain, ctx, effects)
	agent.decision_timer = 10.0
	striker.last_decision = DecisionResult.create(FMEnums.Action.SUPPORT, Vector3(60, 0, 0), {}, "")
	var start_velocity := Vector3(striker.linear_velocity.x, 0.0, striker.linear_velocity.z)
	for i in 5:
		agent.physics_tick(1.0 / 60.0)
		await get_tree().physics_frame
	var end_velocity := Vector3(striker.linear_velocity.x, 0.0, striker.linear_velocity.z)
	_check(end_velocity.x > start_velocity.x, "steering accelerates the player toward its target")

	ball.reset_to(Vector3(striker.global_position.x + 1.0, GameData.config.ball_radius_m, striker.global_position.z))
	striker.last_decision = DecisionResult.create(FMEnums.Action.SHOOT, ctx.goal_for(striker), {}, "")
	agent.physics_tick(1.0 / 60.0)
	await get_tree().physics_frame
	_check(ball.linear_velocity.length() > 5.0, "agent shoots when the ball is in control range")

	for view in ctx.views:
		view.free()
	ball.free()


func _test_match_scene() -> void:
	var packed: PackedScene = load("res://scenes/match_scene.tscn")
	_check(packed != null, "match scene resource loads")
	if packed == null:
		return
	var instance: Node = packed.instantiate()
	add_child(instance)
	var views: Array = instance.call("get_player_views")
	_check(views.size() == 22, "match scene spawns 22 players")
	var tactical_ready := true
	for view in views:
		if view.call("get_instructions") == null or view.call("get_match_state") == null:
			tactical_ready = false
	_check(tactical_ready, "all 22 starters carry instructions and match state")
	var agents: Array = instance.call("get_agents")
	_check(agents.size() == 22, "match scene builds 22 decision agents")
	var camera := instance.find_child("MatchCamera", true, false)
	_check(camera != null, "match scene has a match camera")
	instance.free()


func _test_ball() -> void:
	var cfg := GameData.config
	_check(PitchBounds.classify(Vector3.ZERO, cfg) == PitchBounds.Result.IN_PLAY, "bounds: centre in play")
	_check(PitchBounds.classify(Vector3(cfg.pitch_length_m * 0.5 + 1.0, 1.0, 0.0), cfg) == PitchBounds.Result.GOAL_HOME, "bounds: home goal")
	_check(PitchBounds.classify(Vector3(-cfg.pitch_length_m * 0.5 - 1.0, 1.0, 0.0), cfg) == PitchBounds.Result.GOAL_AWAY, "bounds: away goal")
	_check(PitchBounds.classify(Vector3(0.0, 1.0, cfg.pitch_width_m * 0.5 + 1.0), cfg) == PitchBounds.Result.OUT_TOUCHLINE, "bounds: touchline")
	_check(PitchBounds.classify(Vector3(cfg.pitch_length_m * 0.5 + 1.0, 1.0, cfg.goal_width_m), cfg) == PitchBounds.Result.OUT_GOAL_LINE, "bounds: goal line outside posts")

	var packed: PackedScene = load("res://scenes/ball.tscn")
	var ball := packed.instantiate() as Ball
	_check(ball != null, "ball scene resource loads")
	if ball == null:
		return
	add_child(ball)
	# The first physics frame after adding a body initialises it; impulses
	# applied before that are not integrated until the following step.
	await get_tree().physics_frame
	ball.reset_to(Vector3(0, 1, 0))

	ball.apply_kick(Vector3(1, 0, 0), 10.0, 0.0, 0.0, 0.0)
	await get_tree().physics_frame
	_check(ball.linear_velocity.x > 5.0 and absf(ball.linear_velocity.z) < 0.01, "kick impulse travels along +X")
	var first_speed := ball.linear_velocity.length()

	ball.reset_to(Vector3(0, 1, 0))
	ball.apply_kick(Vector3(1, 0, 0), 20.0, 0.0, 0.0, 0.0)
	await get_tree().physics_frame
	_check(ball.linear_velocity.length() > first_speed, "higher kick speed raises ball velocity")

	ball.reset_to(Vector3(0, 1, 0))
	ball.apply_kick(Vector3(1, 0, 0), 15.0, 0.0, 0.0, 80.0)
	_check(absf(ball.spin.y - 80.0) < 0.01, "kick sets side spin")
	var start_z := ball.global_position.z
	for i in 5:
		await get_tree().physics_frame
	_check(absf(ball.global_position.z - start_z) > 0.001, "Magnus force curves the ball")

	ball.reset_to(Vector3(0, 1, 0))
	var dummy := RigidBody3D.new()
	add_child(dummy)
	ball.set_control(dummy, Vector3(4, 1, 0))
	for i in 10:
		await get_tree().physics_frame
	_check(ball.global_position.x > 0.05, "control steering moves ball toward target")
	ball.release_control()
	dummy.free()
	ball.free()


func _average_tier(tier: int) -> float:
	var total := 0.0
	var count := 0
	for club in GameData.clubs:
		if club.tier != tier:
			continue
		for player in club.squad:
			total += player.attributes.average()
			count += 1
	return total / float(count) if count > 0 else 0.0
