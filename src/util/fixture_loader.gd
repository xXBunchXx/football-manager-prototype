class_name FixtureLoader
extends RefCounted

## The single place that reads and validates JSON fixtures.

const PLAYERS_FILE := "res://data/players.json"
const CLUBS_FILE := "res://data/clubs.json"
const LEAGUES_FILE := "res://data/leagues.json"
const INSTRUCTIONS_FILE := "res://data/instructions.json"


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("FixtureLoader: missing file %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("FixtureLoader: could not open %s" % path)
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("FixtureLoader: invalid JSON in %s" % path)
	return parsed


static func has_keys(data: Dictionary, keys: Array) -> bool:
	for key in keys:
		if not data.has(key):
			return false
	return true


static func parse_color(value: Variant) -> Color:
	if value is String:
		return Color.html(String(value))
	if value is Color:
		return value
	return Color.WHITE


static func load_players(path: String = PLAYERS_FILE) -> Dictionary:
	var raw: Variant = load_json(path)
	if not (raw is Array):
		push_error("FixtureLoader: %s must contain a JSON array" % path)
		return {}
	var players_by_id := {}
	for item in raw:
		if not (item is Dictionary):
			push_error("FixtureLoader: player entry is not an object")
			return {}
		var player := PlayerData.from_dict(item)
		if player == null or player.id == "":
			push_error("FixtureLoader: invalid player entry")
			return {}
		if players_by_id.has(player.id):
			push_error("FixtureLoader: duplicate player id '%s'" % player.id)
			return {}
		players_by_id[player.id] = player
	return players_by_id


static func load_clubs(path: String = CLUBS_FILE, players_by_id: Dictionary = {}) -> Array[ClubData]:
	var raw: Variant = load_json(path)
	if not (raw is Array):
		push_error("FixtureLoader: %s must contain a JSON array" % path)
		return []
	var clubs: Array[ClubData] = []
	for item in raw:
		if not (item is Dictionary):
			push_error("FixtureLoader: club entry is not an object")
			return []
		var club := ClubData.from_dict(item, players_by_id)
		if club == null:
			push_error("FixtureLoader: invalid club entry")
			return []
		clubs.append(club)
	return clubs


static func load_leagues(path: String = LEAGUES_FILE) -> Array[LeagueData]:
	var raw: Variant = load_json(path)
	if not (raw is Array):
		push_error("FixtureLoader: %s must contain a JSON array" % path)
		return []
	var leagues: Array[LeagueData] = []
	for item in raw:
		if not (item is Dictionary):
			push_error("FixtureLoader: league entry is not an object")
			return []
		var league := LeagueData.from_dict(item)
		if league == null:
			push_error("FixtureLoader: invalid league entry")
			return []
		leagues.append(league)
	return leagues


static func load_instruction_overrides(path: String = INSTRUCTIONS_FILE) -> Dictionary:
	var raw: Variant = load_json(path)
	if not (raw is Dictionary):
		push_error("FixtureLoader: %s must contain a JSON object" % path)
		return {}
	var players: Variant = raw.get("players", {})
	var teams: Variant = raw.get("teams", {})
	if not (players is Dictionary) or not (teams is Dictionary):
		push_error("FixtureLoader: instructions.json 'players' and 'teams' must be objects")
		return {}
	return {"players": players, "teams": teams}


static func build_player_instructions(players_by_id: Dictionary, overrides: Dictionary) -> Dictionary:
	var player_overrides: Dictionary = overrides.get("players", {})
	var result := {}
	for player_id in players_by_id:
		var player: PlayerData = players_by_id[player_id]
		var base := InstructionDefaults.for_role(player.role_id)
		var raw_override: Variant = player_overrides.get(player_id, {})
		var override_dict: Dictionary = {}
		if raw_override is Dictionary:
			override_dict = raw_override
		result[player_id] = base.with_overrides(override_dict)
	return result


static func build_team_instructions(clubs: Array[ClubData], overrides: Dictionary) -> Dictionary:
	var team_overrides: Dictionary = overrides.get("teams", {})
	var result := {}
	for club in clubs:
		var base := TeamInstructions.new()
		var raw_override: Variant = team_overrides.get(club.id, {})
		var override_dict: Dictionary = {}
		if raw_override is Dictionary:
			override_dict = raw_override
		result[club.id] = base.with_overrides(override_dict)
	return result


static func load_all() -> Dictionary:
	var players := load_players()
	if players.is_empty():
		return {}
	var clubs := load_clubs(CLUBS_FILE, players)
	if clubs.is_empty():
		return {}
	var leagues := load_leagues()
	if leagues.is_empty():
		return {}
	return {
		"players": players,
		"clubs": clubs,
		"leagues": leagues,
		"instructions": load_instruction_overrides(),
	}
