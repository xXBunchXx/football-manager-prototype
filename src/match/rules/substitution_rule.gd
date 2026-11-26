class_name SubstitutionRule
extends RefCounted

## Validates and records substitutions. The scene swaps the actual body once
## the rule approves, keeping scene work out of the rules layer.

var config: RulesConfig = null
var used: Dictionary = {}


func configure(rules_config: RulesConfig) -> void:
	config = rules_config


func can_substitute(club_id: String) -> bool:
	return int(used.get(club_id, 0)) < int(config.value("substitution", "max_per_club"))


func used_count(club_id: String) -> int:
	return int(used.get(club_id, 0))


func request(club_id: String, outgoing_id: String, incoming_id: String) -> bool:
	if not can_substitute(club_id):
		return false
	var club := _club(club_id)
	if club == null or club.get_player(outgoing_id) == null or club.get_player(incoming_id) == null:
		return false
	if outgoing_id == incoming_id:
		return false
	used[club_id] = used_count(club_id) + 1
	return true


func apply_to_view(view: RigidBody3D, incoming: PlayerData, club: ClubData) -> void:
	view.setup(incoming, club, view.side == FMEnums.Side.HOME)


static func _club(club_id: String) -> ClubData:
	for club in GameData.clubs:
		if club.id == club_id:
			return club
	return null
