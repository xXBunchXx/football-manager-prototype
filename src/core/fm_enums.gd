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

# Individual instruction scales (all mid-point values are the neutral default).
enum Duty { DEFEND, SUPPORT, ATTACK }
enum SupportDepth { DEEP, STANDARD, ADVANCED }
enum WidthMode { NARROW, STANDARD, WIDE }
enum Runs { HOLD, BALANCED, FORWARD }
enum Pressing { LOW, STANDARD, HIGH }
enum TackleAggression { CAUTIOUS, BALANCED, AGGRESSIVE }
enum PassingRisk { SAFE, BALANCED, RISKY }

# Team instruction scales.
enum Mentality { DEFENSIVE, BALANCED, ATTACKING }
enum Tempo { SLOW, STANDARD, FAST }
enum DefensiveLine { DEEP, STANDARD, HIGH }
enum PassingStyle { SHORT, MIXED, DIRECT }

enum CardColor { YELLOW, RED }

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_BALL := 4
const LAYER_TRIGGER := 8
