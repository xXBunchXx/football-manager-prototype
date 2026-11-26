class_name FMEnums
extends RefCounted

## Shared enums and physics-layer constants.
## Keep enum members UPPER_SNAKE_CASE and reference them as FMEnums.<Enum>.<MEMBER>.

enum MatchState { IDLE, PRE_MATCH, KICKOFF, PLAYING, GOAL, HALF_TIME, FULL_TIME }

enum Action { NONE, SUPPORT, PRESS, CHASE, DRIBBLE, PASS, SHOOT, HEADER, TACKLE, MARK, CLEAR, CROSS }

enum FoulSeverity { NONE, FOUL, YELLOW, RED, PENALTY }

enum Side { HOME, AWAY }

enum Foot { LEFT, RIGHT, BOTH }

enum Position { GK, CB, LB, RB, DM, CM, AM, LW, RW, ST }

enum TeamTier { WEAK, MID, STRONG }

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_BALL := 4
const LAYER_TRIGGER := 8
