extends Node

## Central read-only store for loaded configuration and fixture data.
## Mutable per-match state must NOT be kept here.

var config: MatchConfig = MatchConfig.new()
var clubs: Array[ClubData] = []
var players_by_id: Dictionary = {}
var leagues: Array[LeagueData] = []
var player_instructions: Dictionary = {}  # player_id -> PlayerInstructions
var team_instructions: Dictionary = {}     # club_id -> TeamInstructions


func _ready() -> void:
	config.configure_engine()
	load_fixtures()


func load_fixtures() -> bool:
	var loaded := FixtureLoader.load_all()
	if loaded.is_empty():
		push_error("GameData: fixture load failed")
		return false
	players_by_id = loaded["players"]
	clubs = loaded["clubs"]
	leagues = loaded["leagues"]
	var overrides: Dictionary = loaded.get("instructions", {})
	player_instructions = FixtureLoader.build_player_instructions(players_by_id, overrides)
	team_instructions = FixtureLoader.build_team_instructions(clubs, overrides)
	return true
