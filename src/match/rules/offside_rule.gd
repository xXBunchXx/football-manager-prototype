class_name OffsideRule
extends RefCounted

## Judges offside at the instant of a pass, then resolves it on the receiver's
## first touch. Snapshotting at the pass avoids false positives from players
## running in and out of the plane afterwards.

var tolerance_m: float = 0.5
var armed: bool = false
var passer_side: int = -1
var offside_line_signed: float = 0.0


func configure(config: RulesConfig) -> void:
	tolerance_m = config.value("offside", "tolerance_m")


func record_pass(passer: RigidBody3D, ctx: MatchContext) -> void:
	if ctx.ball == null:
		return
	var defenders := ctx.opponents_of(passer)
	if defenders.is_empty():
		return
	var sign := ctx.attack_sign(passer)
	var sorted := defenders.duplicate()
	sorted.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool: return a.global_position.x * sign < b.global_position.x * sign)
	var second_last: int = max(sorted.size() - 2, 0)
	var defender_line: float = sorted[second_last].global_position.x * sign
	var ball_line: float = ctx.ball.global_position.x * sign
	armed = true
	passer_side = passer.side
	offside_line_signed = maxf(defender_line, ball_line)


func clear() -> void:
	armed = false
	passer_side = -1


## Returns true when the player gaining control was offside at the pass.
func check_first_touch(player: RigidBody3D, ctx: MatchContext) -> bool:
	if not armed or player == null:
		return false
	armed = false
	if player.side != passer_side:
		return false
	var sign := ctx.attack_sign(player)
	return player.global_position.x * sign > offside_line_signed + tolerance_m
