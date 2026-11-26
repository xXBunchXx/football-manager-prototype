extends Node

## Central read-only store for loaded configuration and fixture data.
## Mutable per-match state must NOT be kept here.

var config: MatchConfig = MatchConfig.new()
var clubs: Array[ClubData] = []
var players_by_id: Dictionary = {}
var leagues: Array[LeagueData] = []


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
	return true
