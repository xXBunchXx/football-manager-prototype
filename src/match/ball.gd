class_name Ball
extends RigidBody3D

## Always-physical ball. Kicks and headers are impulses; control is a steering
## force toward a target point, never a parent/child reparent.

var spin: Vector3 = Vector3.ZERO
var is_controlled: bool = false
var control_owner: RigidBody3D = null
var control_target: Vector3 = Vector3.ZERO


func _physics_process(delta: float) -> void:
	var cfg := GameData.config

	if is_controlled and control_owner != null:
		var to_target := control_target - global_position
		var desired_velocity := to_target * cfg.control_damping
		var steer := (desired_velocity - linear_velocity) * cfg.control_acceleration * mass
		apply_central_force(steer)

	if spin.length_squared() > 0.0001:
		var magnus := spin.cross(linear_velocity) * cfg.magnus_coefficient * mass
		apply_central_force(magnus)
		spin *= exp(-cfg.spin_decay_per_second * delta)

	if linear_velocity.length() > cfg.max_ball_speed_mps:
		linear_velocity = linear_velocity.normalized() * cfg.max_ball_speed_mps


func apply_kick(direction: Vector3, speed_mps: float, loft_degrees: float, scatter_degrees: float, spin_rad_per_sec: float) -> void:
	var dir := direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	dir = dir.normalized()

	var loft_axis := Vector3(-dir.z, 0.0, dir.x).normalized()
	dir = dir.rotated(loft_axis, deg_to_rad(loft_degrees))

	if not is_zero_approx(scatter_degrees):
		var scatter := RngService.randfn(0.0, scatter_degrees)
		dir = dir.rotated(Vector3.UP, deg_to_rad(scatter))

	apply_impulse(dir.normalized() * (mass * speed_mps))
	spin = Vector3(0.0, spin_rad_per_sec, 0.0)


func apply_header(direction: Vector3, speed_mps: float, loft_degrees: float, scatter_degrees: float, spin_rad_per_sec: float) -> void:
	apply_kick(direction, speed_mps, loft_degrees, scatter_degrees, spin_rad_per_sec)


func set_control(player: RigidBody3D, target: Vector3) -> void:
	is_controlled = true
	control_owner = player
	control_target = target


func release_control() -> void:
	is_controlled = false
	control_owner = null


func reset_to(position: Vector3) -> void:
	global_position = position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	spin = Vector3.ZERO
	release_control()
