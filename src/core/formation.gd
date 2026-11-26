class_name Formation
extends RefCounted

## Shared 4-3-3 shape in home-team coordinates. Both the match scene and the
## decision layer use it, so support targets keep a real shape instead of
## collapsing onto the ball.

const SLOTS: Array[Vector2] = [
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


static func slot(index: int) -> Vector2:
	return SLOTS[index % SLOTS.size()]
