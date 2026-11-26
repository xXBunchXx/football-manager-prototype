extends Node3D

## Spawns the two teams in a 4-3-3 shape and wires steering agents and the
## rules engine into the match.

const PLAYER_SCENE := preload("res://scenes/player_view.tscn")
const PLAYTEST_LOG_PATH := "user://fm_playtest_log.jsonl"

@onready var ball: Ball = $Ball
@onready var score_label: Label = $HUD/Panel/Layout/ScoreLabel
@onready var clock_label: Label = $HUD/Panel/Layout/ClockLabel
@onready var event_label: Label = $HUD/Panel/Layout/EventLabel
@onready var stats_label: Label = $HUD/Panel/Layout/StatsLabel
@onready var speed_label: Label = $HUD/Panel/Layout/SpeedLabel

var player_views: Array[RigidBody3D] = []
var agents: Array[PlayerAgent] = []
var match_ctx: MatchContext = null
var brain: DecisionBrain = null
var effects: StatEffects = null
var rules_engine: RulesEngine = null
var stats := MatchStats.new()

var fixture_id: String = ""
var home_club_id: String = ""
var away_club_id: String = ""
var pending_pass: Dictionary = {}


func _ready() -> void:
	_read_selected_fixture()
	effects = StatEffects.load()
	if effects == null:
		push_error("MatchScene: could not load stat effects")
		return
	brain = DecisionBrain.new(effects)
	match_ctx = MatchContext.new()
	match_ctx.ball = ball
	match_ctx.team_instructions = GameData.team_instructions
	_spawn_teams()
	for view in player_views:
		match_ctx.add_view(view)
		var agent := PlayerAgent.new(view, brain, match_ctx, effects)
		agent.tackle_attempted.connect(_on_tackle_attempted_for_stats)
		agent.tackle_won.connect(_on_tackle_won_for_stats)
		agents.append(agent)
	var rules_config := RulesConfig.load()
	if rules_config == null:
		push_error("MatchScene: could not load rules config")
		return
	rules_engine = RulesEngine.new()
	rules_engine.setup(match_ctx, effects, rules_config)
	rules_engine.event_raised.connect(_on_rule_event)
	ball.kick_performed.connect(_on_ball_kicked_for_stats)
	ball.control_changed.connect(_on_ball_control_changed_for_stats)
	_refresh_hud()
	var camera := find_child("MatchCamera", true, false) as CameraRig
	if camera != null:
		camera.set_follow_target(ball)
		camera.set_mode(CameraRig.Mode.FOLLOW)


func _physics_process(delta: float) -> void:
	for agent in agents:
		agent.physics_tick(delta)
	if rules_engine != null:
		rules_engine.tick(delta)
	if ball.control_owner != null:
		stats.record_control(ball.control_owner.side, delta, ball.control_owner.player_id)
	_refresh_hud()


func _on_ball_kicked_for_stats(kicker: RigidBody3D, is_pass: bool) -> void:
	var action_key := ""
	var target_id := ""
	if kicker.last_decision != null:
		action_key = kicker.last_decision.best_action_name()
		target_id = kicker.last_decision.pass_to_id
	stats.record_kick(kicker.side, is_pass, action_key, kicker.player_id, target_id)
	if is_pass:
		pending_pass = {
			"kicker_id": kicker.player_id,
			"side": kicker.side,
			"target_id": target_id,
		}
	else:
		pending_pass.clear()


## A pass is completed when the next player to control the ball is a team-mate.
## An interception or dead ball clears the pending pass instead of crediting it.
func _on_ball_control_changed_for_stats(player: RigidBody3D) -> void:
	if player == null:
		return
	stats.record_touch(player.player_id, player.side)
	if pending_pass.is_empty():
		return
	var kicker_id := String(pending_pass.get("kicker_id", ""))
	var side_value := int(pending_pass.get("side", -1))
	if player.side != side_value or player.player_id == kicker_id:
		pending_pass.clear()
		return
	stats.record_pass_completion(kicker_id, player.player_id, side_value, String(pending_pass.get("target_id", "")))
	pending_pass.clear()


func _on_tackle_attempted_for_stats(player: RigidBody3D) -> void:
	stats.record_tackle_attempt(player.player_id, player.side)


func _on_tackle_won_for_stats(player: RigidBody3D) -> void:
	stats.record_tackle_win(player.player_id, player.side)


func _on_rule_event(event: RuleEvent) -> void:
	var same_side_kicker: bool = ball.last_kicker != null and ball.last_kicker.side == event.side
	if event.type == RuleEvent.Type.GOAL and same_side_kicker:
		event.offender_id = ball.last_kicker.player_id
	# On-target shots are the shots that end in a goal or a save. Live play has
	# no shot-placement event, so the rule event is the reliable source and
	# keeps live records consistent with the fast simulator.
	if event.type == RuleEvent.Type.GOAL:
		var goal_shooter_id: String = event.offender_id if same_side_kicker else ""
		stats.record_shot_on_target(goal_shooter_id, event.side)
	elif event.type == RuleEvent.Type.SAVE:
		var attack_side: int = 1 - event.side
		var shooter_id: String = ball.last_kicker.player_id if ball.last_kicker != null and ball.last_kicker.side == attack_side else ""
		stats.record_shot_on_target(shooter_id, attack_side)
	stats.record_event(event)
	if event.type == RuleEvent.Type.RESTART or event.type == RuleEvent.Type.FOUL or event.type == RuleEvent.Type.OFFSIDE:
		pending_pass.clear()
	MatchEvents.log_event("[rules] %s" % event.description)
	if event.type != RuleEvent.Type.FULL_TIME or fixture_id.is_empty():
		return
	var fixture := _fixture_for_match()
	if fixture == null:
		return
	var result := MatchResult.create(fixture, rules_engine.score_home, rules_engine.score_away)
	if LeagueManager.record_result(result):
		MatchEvents.log_event("[league] recorded %d-%d for %s" % [result.home_goals, result.away_goals, fixture_id])
	else:
		MatchEvents.log_event("[league] result was not recorded")
	var record := MatchRecord.from_match(fixture, result, stats.to_dict(), "live")
	LeagueManager.record_match(record)
	_append_playtest_record(result)
	MatchEvents.log_event("[stats] %s" % stats.summary())


func request_home_substitution() -> bool:
	if rules_engine == null or GameData.clubs.is_empty():
		return false
	var club: ClubData = GameData.clubs[FMEnums.Side.HOME]
	var outgoing: String = String(club.get_starters()[9].id)
	var incoming: String = String(club.get_bench()[0].id)
	return rules_engine.request_substitution(club.id, outgoing, incoming)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _set_speed_step(0)
			KEY_2: _set_speed_step(1)
			KEY_3: _set_speed_step(2)
			KEY_4: _set_speed_step(3)
	if event is InputEventKey and event.pressed and event.keycode == KEY_K:
		ball.apply_kick(Vector3(1, 0, 0), 18.0, 12.0, 0.0, 60.0)
		MatchEvents.log_event("debug kick: +X, 18 m/s, 12 deg loft, spin 60")
	if event is InputEventKey and event.pressed and event.keycode == KEY_S:
		MatchEvents.log_event("substitution requested: %s" % str(request_home_substitution()))
	if event is InputEventKey and event.pressed and event.keycode == KEY_P:
		MatchEvents.log_event("[stats] %s" % stats.summary())
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		get_tree().change_scene_to_file("res://scenes/ui/league_scene.tscn")


## 1-4 select the MatchConfig.speed_steps entries. Live speed uses the engine
## clock, so the 90-minute scoreboard still counts true match minutes; only
## wall-clock presentation changes. Bulk simulation is the fast analysis path.
func _set_speed_step(index: int) -> void:
	var steps: Array = GameData.config.speed_steps
	if index < 0 or index >= steps.size():
		return
	Engine.time_scale = maxf(float(steps[index]), 0.0)
	if speed_label != null:
		var value := float(steps[index])
		speed_label.text = "Speed: paused" if value <= 0.0 else "Speed: %.0fx (1-4)" % value
	var speed_text := "changed" if speed_label == null else speed_label.text
	MatchEvents.log_event("[speed] %s" % speed_text)


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _read_selected_fixture() -> void:
	var fixture := LeagueManager.get_selected_fixture()
	if fixture == null:
		return
	fixture_id = fixture.id
	home_club_id = fixture.home_club_id
	away_club_id = fixture.away_club_id


func _fixture_for_match() -> Fixture:
	if fixture_id.is_empty():
		return null
	return LeagueManager.get_fixture(fixture_id)


func _find_club(club_id: String) -> ClubData:
	for club in GameData.clubs:
		if club.id == club_id:
			return club
	return null


func _spawn_teams() -> void:
	if GameData.clubs.size() < 2:
		push_error("MatchScene: need at least two clubs")
		return
	var home_club := _find_club(home_club_id) if not home_club_id.is_empty() else GameData.clubs[FMEnums.Side.HOME]
	var away_club := _find_club(away_club_id) if not away_club_id.is_empty() else GameData.clubs[FMEnums.Side.AWAY]
	if home_club == null or away_club == null:
		push_error("MatchScene: selected fixture has an unknown club")
		return
	var players_node := Node3D.new()
	players_node.name = "Players"
	add_child(players_node)

	var clubs: Array[ClubData] = [home_club, away_club]
	for side in 2:
		var club: ClubData = clubs[side]
		var is_home := side == FMEnums.Side.HOME
		var starters: Array = club.get_starters()
		for i in starters.size():
			var view: RigidBody3D = PLAYER_SCENE.instantiate()
			players_node.add_child(view)
			view.setup(starters[i], club, is_home)
			view.formation_slot = Formation.slot(i)
			view.global_position = _formation_position(side, i)
			player_views.append(view)


func _formation_position(side: int, index: int) -> Vector3:
	var spot: Vector2 = Formation.slot(index)
	if side == FMEnums.Side.AWAY:
		spot.x = -spot.x
	return Vector3(spot.x, 1.0, spot.y)


func _refresh_hud() -> void:
	if score_label == null or clock_label == null or event_label == null:
		return
	var home_name := _short_name(home_club_id, "HOME")
	var away_name := _short_name(away_club_id, "AWAY")
	var home_goals := rules_engine.score_home if rules_engine != null else 0
	var away_goals := rules_engine.score_away if rules_engine != null else 0
	score_label.text = "%s  %d - %d  %s" % [home_name, home_goals, away_goals, away_name]
	var clock_text := rules_engine.clock_rule.formatted() if rules_engine != null else "00:00 (+0)"
	var state_text := _state_name(rules_engine.state) if rules_engine != null else "IDLE"
	clock_label.text = "%s  %s" % [clock_text, state_text]
	if stats_label != null:
		var home: Dictionary = stats.get_side(FMEnums.Side.HOME)
		var away: Dictionary = stats.get_side(FMEnums.Side.AWAY)
		stats_label.text = "Passes %d/%d  Tackles %d/%d  Shots %d-%d" % [
			int(home["passes_completed"]), int(home["passes_attempted"]),
			int(home["tackle_wins"]), int(home["tackles"]),
			int(home["shots"]), int(away["shots"]),
		]
	var latest := ""
	for line in MatchEvents.recent:
		if line.begins_with("[rules]") or line.begins_with("[league]") or line.begins_with("[stats]"):
			latest = line
	event_label.text = latest if not latest.is_empty() else "Waiting for kick-off"


func _state_name(state_value: int) -> String:
	match state_value:
		FMEnums.MatchState.PLAYING: return "PLAYING"
		FMEnums.MatchState.RESTART: return "RESTART"
		FMEnums.MatchState.HALF_TIME: return "HALF TIME"
		FMEnums.MatchState.FULL_TIME: return "FULL TIME"
		FMEnums.MatchState.SUBSTITUTION: return "SUBSTITUTION"
		_: return "STOPPED"


func _short_name(club_id: String, fallback: String) -> String:
	if club_id.is_empty():
		return fallback
	var club := _find_club(club_id)
	return club.short_name if club != null else club_id


func _append_playtest_record(result: MatchResult) -> void:
	var record := {
		"timestamp": Time.get_datetime_string_from_system(),
		"fixture_id": fixture_id,
		"home_club_id": result.home_club_id,
		"away_club_id": result.away_club_id,
		"home_goals": result.home_goals,
		"away_goals": result.away_goals,
		"stats": stats.to_dict(),
	}
	var file := FileAccess.open(PLAYTEST_LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(PLAYTEST_LOG_PATH, FileAccess.WRITE)
	if file == null:
		push_error("MatchScene: could not append to %s" % PLAYTEST_LOG_PATH)
		return
	file.seek_end()
	file.store_line(JSON.stringify(record))
	file.close()


func get_player_views() -> Array[RigidBody3D]:
	return player_views


func get_ball() -> Ball:
	return ball


func get_agents() -> Array[PlayerAgent]:
	return agents


func get_context() -> MatchContext:
	return match_ctx


func get_rules_engine() -> RulesEngine:
	return rules_engine


func get_fixture_id() -> String:
	return fixture_id


func get_stats() -> MatchStats:
	return stats
