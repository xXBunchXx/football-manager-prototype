class_name CameraRig
extends Camera3D

## Simple switchable match camera. Keys 1/2/3 select broadcast, top-down and
## follow-ball views; follow-ball tracks an assigned Node3D.

enum Mode { BROADCAST, TOP_DOWN, FOLLOW }

var mode: int = Mode.FOLLOW
var follow_target: Node3D = null


func _ready() -> void:
	apply_mode()


func set_mode(new_mode: int) -> void:
	mode = new_mode
	apply_mode()


func set_follow_target(target: Node3D) -> void:
	follow_target = target


func apply_mode() -> void:
	match mode:
		Mode.BROADCAST:
			position = Vector3(0, 26, -62)
			look_at(Vector3.ZERO, Vector3.UP)
		Mode.TOP_DOWN:
			position = Vector3(0, 100, 0)
			rotation = Vector3(-PI * 0.5, 0, 0)
		Mode.FOLLOW:
			var focus := follow_target.global_position if follow_target != null else Vector3.ZERO
			position = focus + Vector3(0, 14, -26)
			look_at(focus + Vector3(0, 0.6, 0), Vector3.UP)


func _process(_delta: float) -> void:
	if mode != Mode.FOLLOW or follow_target == null:
		return
	var target_pos: Vector3 = follow_target.global_position
	position = target_pos + Vector3(0, 14, -26)
	look_at(target_pos + Vector3(0, 0.6, 0), Vector3.UP)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_1:
			set_mode(Mode.BROADCAST)
		KEY_2:
			set_mode(Mode.TOP_DOWN)
		KEY_3:
			set_mode(Mode.FOLLOW)
