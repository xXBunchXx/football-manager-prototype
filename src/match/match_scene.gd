extends Node3D

## Spawns the two teams in a 4-3-3 shape for the current phase. Match rules and
## AI will be layered on in later phases.

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

var player_views: Array[RigidBody3D] = []


func _ready() -> void:
	_spawn_teams()


func _spawn_teams() -> void:
	if GameData.clubs.size() < 2:
		push_error("MatchScene: need at least two clubs")
		return
	var players_node := Node3D.new()
	players_node.name = "Players"
	add_child(players_node)

	for side in 2:
		var club: ClubData = GameData.clubs[side]
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
