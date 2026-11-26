class_name LeagueData
extends Resource

## A simple single-division league definition.

const REQUIRED_KEYS := ["id", "name", "club_ids"]

@export var id: String = ""
@export var name: String = ""
@export var club_ids: Array[String] = []


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "club_ids": club_ids.duplicate()}


static func from_dict(data: Dictionary) -> LeagueData:
	if not FixtureLoader.has_keys(data, REQUIRED_KEYS):
		push_error("LeagueData: missing required keys")
		return null
	var raw: Variant = data["club_ids"]
	if not (raw is Array):
		push_error("LeagueData: club_ids must be an array")
		return null
	var league := LeagueData.new()
	league.id = String(data["id"])
	league.name = String(data["name"])
	for club_id in raw:
		league.club_ids.append(String(club_id))
	return league
