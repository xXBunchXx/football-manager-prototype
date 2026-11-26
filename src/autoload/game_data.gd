extends Node

## Central read-only store for loaded configuration and fixture data.
## Mutable per-match state must NOT be kept here.

var config: MatchConfig = MatchConfig.new()
var clubs: Array = []
var players_by_id: Dictionary = {}


func _ready() -> void:
	config.configure_engine()
