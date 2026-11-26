extends Node3D

## Builds pitch markings and goals from MatchConfig. The grass, lighting and
## camera are authored in pitch.tscn.

const LINE_Y := 0.015
const LINE_WIDTH := 0.12
const CIRCLE_SEGMENTS := 32
const GROUND_NODE_NAME := "GroundCollider"

@onready var world_environment: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	_setup_environment()
	_build_ground_collision()
	_build_markings()
	_build_goals()


## The grass mesh is visual only. This collider is what actually holds the
## pills and the ball on the pitch; it extends past the markings so running out
## of play does not drop a body through the world.
func _build_ground_collision() -> void:
	if has_node(GROUND_NODE_NAME):
		return
	var cfg := GameData.config
	var body := StaticBody3D.new()
	body.name = GROUND_NODE_NAME
	body.collision_layer = FMEnums.LAYER_WORLD
	body.collision_mask = 0

	var shape := BoxShape3D.new()
	shape.size = Vector3(
		cfg.pitch_length_m + cfg.ground_margin_m * 2.0,
		cfg.ground_thickness_m,
		cfg.pitch_width_m + cfg.ground_margin_m * 2.0
	)
	var collision := CollisionShape3D.new()
	collision.name = "GroundShape"
	collision.shape = shape
	collision.position.y = -cfg.ground_thickness_m * 0.5
	body.add_child(collision)
	add_child(body)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#8ecae6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.55)
	env.ambient_light_energy = 1.0
	world_environment.environment = env


func _build_markings() -> void:
	var cfg := GameData.config
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE

	var half_l := cfg.pitch_length_m * 0.5
	var half_w := cfg.pitch_width_m * 0.5

	_add_box(Vector3(0, LINE_Y, -half_w), Vector3(cfg.pitch_length_m, 0.01, LINE_WIDTH), mat)
	_add_box(Vector3(0, LINE_Y, half_w), Vector3(cfg.pitch_length_m, 0.01, LINE_WIDTH), mat)
	_add_box(Vector3(-half_l, LINE_Y, 0), Vector3(LINE_WIDTH, 0.01, cfg.pitch_width_m), mat)
	_add_box(Vector3(half_l, LINE_Y, 0), Vector3(LINE_WIDTH, 0.01, cfg.pitch_width_m), mat)
	_add_box(Vector3(0, LINE_Y, 0), Vector3(LINE_WIDTH, 0.01, cfg.pitch_width_m), mat)

	_add_box(Vector3(-half_l + 8.25, LINE_Y, 0), Vector3(0.12, 0.01, 40.32), mat)
	_add_box(Vector3(half_l - 8.25, LINE_Y, 0), Vector3(0.12, 0.01, 40.32), mat)
	_add_box(Vector3(-half_l + 8.25, LINE_Y, -20.16), Vector3(16.5, 0.01, LINE_WIDTH), mat)
	_add_box(Vector3(-half_l + 8.25, LINE_Y, 20.16), Vector3(16.5, 0.01, LINE_WIDTH), mat)
	_add_box(Vector3(half_l - 8.25, LINE_Y, -20.16), Vector3(16.5, 0.01, LINE_WIDTH), mat)
	_add_box(Vector3(half_l - 8.25, LINE_Y, 20.16), Vector3(16.5, 0.01, LINE_WIDTH), mat)

	_add_box(Vector3(-half_l + 2.75, LINE_Y, 0), Vector3(0.12, 0.01, 18.32), mat)
	_add_box(Vector3(half_l - 2.75, LINE_Y, 0), Vector3(0.12, 0.01, 18.32), mat)
	_add_box(Vector3(-half_l + 2.75, LINE_Y, -9.16), Vector3(5.5, 0.01, LINE_WIDTH), mat)
	_add_box(Vector3(-half_l + 2.75, LINE_Y, 9.16), Vector3(5.5, 0.01, LINE_WIDTH), mat)
	_add_box(Vector3(half_l - 2.75, LINE_Y, -9.16), Vector3(5.5, 0.01, LINE_WIDTH), mat)
	_add_box(Vector3(half_l - 2.75, LINE_Y, 9.16), Vector3(5.5, 0.01, LINE_WIDTH), mat)

	_add_box(Vector3(-half_l + 11.0, LINE_Y, 0), Vector3(0.3, 0.01, 0.3), mat)
	_add_box(Vector3(half_l - 11.0, LINE_Y, 0), Vector3(0.3, 0.01, 0.3), mat)
	_add_circle(Vector3.ZERO, 9.15, mat)


func _build_goals() -> void:
	var cfg := GameData.config
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	var half_l := cfg.pitch_length_m * 0.5
	var half_goal := cfg.goal_width_m * 0.5
	for side_sign in [-1.0, 1.0]:
		var x: float = float(side_sign) * half_l
		_add_box(Vector3(x, cfg.goal_height_m * 0.5, -half_goal), Vector3(0.12, cfg.goal_height_m, 0.12), mat)
		_add_box(Vector3(x, cfg.goal_height_m * 0.5, half_goal), Vector3(0.12, cfg.goal_height_m, 0.12), mat)
		_add_box(Vector3(x, cfg.goal_height_m, 0), Vector3(0.12, 0.12, cfg.goal_width_m), mat)


func _add_box(center: Vector3, size: Vector3, mat: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = mat
	mesh_instance.position = center
	add_child(mesh_instance)


func _add_segment(from: Vector3, to: Vector3, mat: Material) -> void:
	var delta := to - from
	var length := delta.length()
	if length <= 0.001:
		return
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length, 0.01, LINE_WIDTH)
	mesh_instance.mesh = box
	mesh_instance.material_override = mat
	mesh_instance.position = (from + to) * 0.5
	mesh_instance.rotation.y = -atan2(delta.z, delta.x)
	add_child(mesh_instance)


func _add_circle(center: Vector3, radius: float, mat: Material) -> void:
	var previous := center + Vector3(radius, 0, 0)
	for i in range(1, CIRCLE_SEGMENTS + 1):
		var angle := TAU * float(i) / float(CIRCLE_SEGMENTS)
		var current := center + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		_add_segment(previous, current, mat)
		previous = current
