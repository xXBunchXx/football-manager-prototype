class_name ClubData
extends Resource

## Club identity plus its 18-player squad, in starter order.

const REQUIRED_KEYS := [
	"id", "name", "short_name", "tier", "primary_color", "secondary_color", "player_ids",
]

@export var id: String = ""
@export var name: String = ""
@export var short_name: String = ""
@export var tier: int = FMEnums.TeamTier.MID
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.BLACK
@export var squad: Array[PlayerData] = []


func get_starters() -> Array:
	return squad.slice(0, 11)


func get_bench() -> Array:
	return squad.slice(11)


func get_player(player_id: String) -> PlayerData:
	for player in squad:
		if player.id == player_id:
			return player
	return null


func average_attribute(attribute_name: String) -> float:
	if squad.is_empty():
		return 0.0
	var total := 0.0
	for player in squad:
		total += player.attributes.get_attribute(attribute_name)
	return total / float(squad.size())


func to_dict() -> Dictionary:
	var player_ids: Array[String] = []
	for player in squad:
		player_ids.append(player.id)
	return {
		"id": id,
		"name": name,
		"short_name": short_name,
		"tier": tier,
		"primary_color": "#%s" % primary_color.to_html(false),
		"secondary_color": "#%s" % secondary_color.to_html(false),
		"player_ids": player_ids,
	}


static func from_dict(data: Dictionary, players_by_id: Dictionary) -> ClubData:
	if not FixtureLoader.has_keys(data, REQUIRED_KEYS):
		push_error("ClubData: missing required keys")
		return null
	var tier_value := int(data["tier"])
	if tier_value < 0 or tier_value > 2:
		push_error("ClubData: tier %d out of range" % tier_value)
		return null
	var player_ids: Variant = data["player_ids"]
	if not (player_ids is Array):
		push_error("ClubData: player_ids must be an array")
		return null

	var club := ClubData.new()
	club.id = String(data["id"])
	club.name = String(data["name"])
	club.short_name = String(data["short_name"])
	club.tier = tier_value
	club.primary_color = FixtureLoader.parse_color(data["primary_color"])
	club.secondary_color = FixtureLoader.parse_color(data["secondary_color"])
	for player_id in player_ids:
		var key := String(player_id)
		if not players_by_id.has(key):
			push_error("ClubData: unknown player id '%s'" % key)
			return null
		club.squad.append(players_by_id[key])
	return club
