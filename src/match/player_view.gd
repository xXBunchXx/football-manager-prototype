extends RigidBody3D

## Visual and physical representation of one pill-shaped player.

@onready var body: MeshInstance3D = $Body
@onready var name_label: Label3D = $NameLabel

var player_id: String = ""
var club_id: String = ""
var side: int = FMEnums.Side.HOME
var player_data: PlayerData = null
var instructions: PlayerInstructions = null
var match_state: PlayerState = null
var last_decision: DecisionResult = null
var formation_slot: Vector2 = Vector2.ZERO  # home-team 4-3-3 coordinates


func setup(player: PlayerData, club: ClubData, is_home: bool) -> void:
	player_id = player.id
	club_id = club.id
	side = FMEnums.Side.HOME if is_home else FMEnums.Side.AWAY
	player_data = player
	instructions = GameData.player_instructions.get(player.id, InstructionDefaults.for_role(player.role_id))
	match_state = PlayerState.for_player(player)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = club.primary_color if is_home else club.secondary_color
	body.material_override = mat
	name_label.text = player.last_name
	name_label.modulate = Color.WHITE if is_home else Color(1.0, 0.85, 0.2)


func get_player_id() -> String:
	return player_id


func get_match_state() -> PlayerState:
	return match_state


func get_instructions() -> PlayerInstructions:
	return instructions


func get_last_decision() -> DecisionResult:
	return last_decision
