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

	_add_box(Vector3(0, LINE_Y, -half_w), Vector3(cfg.pitch_length_m, 0.01, LINE_WIDTH), mat, "TouchlineNorth")
	_add_box(Vector3(0, LINE_Y, half_w), Vector3(cfg.pitch_length_m, 0.01, LINE_WIDTH), mat, "TouchlineSouth")
	_add_box(Vector3(-half_l, LINE_Y, 0), Vector3(LINE_WIDTH, 0.01, cfg.pitch_width_m), mat, "GoalLineHome")
	_add_box(Vector3(half_l, LINE_Y, 0), Vector3(LINE_WIDTH, 0.01, cfg.pitch_width_m), mat, "GoalLineAway")
	_add_box(Vector3(0, LINE_Y, 0), Vector3(LINE_WIDTH, 0.01, cfg.pitch_width_m), mat, "HalfwayLine")
	_add_circle(Vector3.ZERO, cfg.spot_radius_m, mat)
	_add_circle(Vector3.ZERO, cfg.centre_circle_radius_m, mat)

	for side_sign in [-1.0, 1.0]:
		var sign := float(side_sign)
		var side_name := "Home" if sign < 0.0 else "Away"
		var penalty_line := penalty_area_boundary_x(sign, cfg)
		var penalty_mid: float = sign * (half_l - cfg.penalty_area_depth_m * 0.5)
		var six_line := goal_area_boundary_x(sign, cfg)
		var six_mid: float = sign * (half_l - cfg.goal_area_depth_m * 0.5)

		_add_box(Vector3(penalty_line, LINE_Y, 0), Vector3(LINE_WIDTH, 0.01, cfg.penalty_area_width_m), mat, "PenaltyAreaLine" + side_name)
		for z_sign in [-1.0, 1.0]:
			_add_box(
				Vector3(penalty_mid, LINE_Y, z_sign * cfg.penalty_area_width_m * 0.5),
				Vector3(cfg.penalty_area_depth_m, 0.01, LINE_WIDTH), mat,
				"PenaltyAreaSide%s%s" % [side_name, "North" if z_sign < 0.0 else "South"]
			)
		_add_box(Vector3(six_line, LINE_Y, 0), Vector3(LINE_WIDTH, 0.01, cfg.goal_area_width_m), mat, "GoalAreaLine" + side_name)
		for z_sign in [-1.0, 1.0]:
			_add_box(
				Vector3(six_mid, LINE_Y, z_sign * cfg.goal_area_width_m * 0.5),
				Vector3(cfg.goal_area_depth_m, 0.01, LINE_WIDTH), mat,
				"GoalAreaSide%s%s" % [side_name, "North" if z_sign < 0.0 else "South"]
			)

		var spot_x: float = sign * (half_l - cfg.penalty_spot_distance_m)
		_add_circle(Vector3(spot_x, LINE_Y, 0), cfg.spot_radius_m, mat)
		var arc_span := penalty_arc_span(sign, cfg)
		_add_arc(Vector3(spot_x, LINE_Y, 0), cfg.penalty_arc_radius_m, arc_span.x, arc_span.y, mat)

	for x_sign in [-1.0, 1.0]:
		for z_sign in [-1.0, 1.0]:
			var span := corner_arc_span(x_sign, z_sign)
			_add_arc(Vector3(x_sign * half_l, LINE_Y, z_sign * half_w), cfg.corner_arc_radius_m, span.x, span.y, mat)


## Far edge of the penalty area, measured from the centre spot.
static func penalty_area_boundary_x(side_sign: float, cfg: MatchConfig) -> float:
	return side_sign * (cfg.pitch_length_m * 0.5 - cfg.penalty_area_depth_m)


## Far edge of the six-yard box, measured from the centre spot.
static func goal_area_boundary_x(side_sign: float, cfg: MatchConfig) -> float:
	return side_sign * (cfg.pitch_length_m * 0.5 - cfg.goal_area_depth_m)


## Radians of the penalty arc visible outside the penalty area.
static func penalty_arc_span(side_sign: float, cfg: MatchConfig) -> Vector2:
	var offset := cfg.penalty_area_depth_m - cfg.penalty_spot_distance_m
	var half_angle := acos(clampf(offset / cfg.penalty_arc_radius_m, -1.0, 1.0))
	if side_sign < 0.0:
		return Vector2(-half_angle, half_angle)
	return Vector2(PI - half_angle, PI + half_angle)


## Radians of the quarter-circle inside one corner of the pitch.
static func corner_arc_span(x_sign: float, z_sign: float) -> Vector2:
	if x_sign < 0.0:
		return Vector2(-PI * 0.5, 0.0) if z_sign > 0.0 else Vector2(0.0, PI * 0.5)
	return Vector2(PI, PI * 1.5) if z_sign > 0.0 else Vector2(PI * 0.5, PI)


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


func _add_box(center: Vector3, size: Vector3, mat: Material, node_name: String = "") -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = mat
	mesh_instance.position = center
	if not node_name.is_empty():
		mesh_instance.name = node_name
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
	_add_arc(center, radius, 0.0, TAU, mat)


func _add_arc(center: Vector3, radius: float, from_rad: float, to_rad: float, mat: Material) -> void:
	var span := to_rad - from_rad
	var segments := maxi(2, ceili(absf(span) / TAU * float(CIRCLE_SEGMENTS)))
	var previous := center + Vector3(cos(from_rad) * radius, 0, sin(from_rad) * radius)
	for i in range(1, segments + 1):
		var angle := from_rad + span * float(i) / float(segments)
		var current := center + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		_add_segment(previous, current, mat)
		previous = current
