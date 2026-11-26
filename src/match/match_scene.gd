extends Node3D

## Spawns the two teams in a 4-3-3 shape and wires steering agents and the
## rules engine into the match.

const PLAYER_SCENE := preload("res://scenes/player_view.tscn")

const FORMATION: Array[Vector2] = [
	Vector2(-48, 0),    # GK
	Vector2(-35, -12),  # CB
	Vector2(-35, 12),   # CB
	Vector2(-28, -28),  # LB
	Vector2(-28, 28),   # RB
	Vector2(-18, 0),    # DM
	Vector2(-6, -10),   # CM
	Vector2(4, 0),      # AM
	Vector2(18, -28),   # LW
	Vector2(22, 0),     # ST
	Vector2(18, 28),    # RW
]

@onready var ball: Ball = $Ball

var player_views: Array[RigidBody3D] = []
var agents: Array[PlayerAgent] = []
var match_ctx: MatchContext = null
var brain: DecisionBrain = null
var effects: StatEffects = null
var rules_engine: RulesEngine = null

var fixture_id: String = ""
var home_club_id: String = ""
var away_club_id: String = ""


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
		agents.append(PlayerAgent.new(view, brain, match_ctx, effects))
	var rules_config := RulesConfig.load()
	if rules_config == null:
		push_error("MatchScene: could not load rules config")
		return
	rules_engine = RulesEngine.new()
	rules_engine.setup(match_ctx, effects, rules_config)
	rules_engine.event_raised.connect(_on_rule_event)
	var camera := find_child("MatchCamera", true, false)
	if camera != null and camera.has_method("set_follow_target"):
		camera.set_follow_target(ball)


func _physics_process(delta: float) -> void:
	for agent in agents:
		agent.physics_tick(delta)
	if rules_engine != null:
		rules_engine.tick(delta)


func _on_rule_event(event: RuleEvent) -> void:
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


func request_home_substitution() -> bool:
	if rules_engine == null or GameData.clubs.is_empty():
		return false
	var club: ClubData = GameData.clubs[FMEnums.Side.HOME]
	var outgoing: String = String(club.get_starters()[9].id)
	var incoming: String = String(club.get_bench()[0].id)
	return rules_engine.request_substitution(club.id, outgoing, incoming)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_K:
		ball.apply_kick(Vector3(1, 0, 0), 18.0, 12.0, 0.0, 60.0)
		MatchEvents.log_event("debug kick: +X, 18 m/s, 12 deg loft, spin 60")
	if event is InputEventKey and event.pressed and event.keycode == KEY_S:
		MatchEvents.log_event("substitution requested: %s" % str(request_home_substitution()))
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		get_tree().change_scene_to_file("res://scenes/ui/league_scene.tscn")


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
			var spot: Vector2 = FORMATION[i]
			if not is_home:
				spot.x = -spot.x
			view.global_position = Vector3(spot.x, 1.0, spot.y)
			player_views.append(view)


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
