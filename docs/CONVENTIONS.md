# Project conventions

Godot 4.7.2, GDScript, Jolt Physics. These rules are binding for all code in this
project. Update this document in the same change if a convention changes.

## Layout

- `data/` — hand-editable JSON fixtures: generated players/clubs/leagues plus
  `instructions.json` for tactical overrides.
- `src/core/` — Resource classes, enums, config. No scene logic here.
- `src/autoload/` — global singletons: `GameData`, `RngService`, `MatchEvents`, `SaveGame`.
- `src/match/` — match simulation, agents, ball, rules engine and debug overlay.
- `src/ui/` — one script per screen/widget in `scenes/ui/`.
- `src/util/` — small stateless helpers (`FixtureLoader`, math).
- `tests/` — headless assertions and the batch calibration harness.
- `tools/` — development utilities that regenerate data fixtures (`generate_fixtures.py`).

## Files and nodes

- Files and directories: `snake_case`.
- A scene and its script share a name and match the root node:
  `player_agent.tscn` → root `PlayerAgent` → `player_agent.gd`.
- Autoload globals are PascalCase (`GameData`) over snake_case files.
- `class_name` types are PascalCase (`PlayerData`, `MatchConfig`, `DecisionBrain`).
- Scene nodes are PascalCase (`MatchManager`, `HomeGoal`, `Ball`); generated
  instances are snake_case with a role suffix (`striker_left_agent`).

## GDScript

- Variables and functions: `snake_case`.
- Internal-only members prefix `_` (`_compute_utility()`).
- Booleans read as `is_`, `has_`, `can_` (`is_on_side`, `has_ball`, `can_press`).
- Constants: `UPPER_SNAKE_CASE` (`MAX_PLAYERS`, `DECISION_HZ`).
- Signals are past tense (`ball_kicked`, `goal_scored`, `foul_called`).
- Enums: `Action.SHOOT`, `FoulSeverity.YELLOW`; members UPPER_SNAKE_CASE.
- Use Godot 4 APIs only: real class names (`Node3D`, `CharacterBody3D`,
  `MeshInstance3D`), `signal.connect(callable)`, and `@export` for inspector fields.
  Never use Godot 3 aliases or `connect("signal", self, "method")`.
- Run `tests/run_checks.sh` after every script edit. It parses every script with
  the real binary and runs the headless test scene. `--check-only` alone cannot
  resolve autoload globals (`GameData`, `RngService`, `MatchEvents`, `SaveGame`),
  so scripts using them are validated by the test scene instead.

## Data rules

- No magic numbers in logic. Tuning goes in `MatchConfig` or `data/stat_effects.json`.
- JSON is the source of truth for generated content; `FixtureLoader` validates it
  and constructs typed Resources. User-created content is saved as JSON in `user://`.
- Resources are reference types. `PlayerData` and friends are immutable definitions;
  per-match mutable values (stamina, morale, form, cards, mark assignment,
  event counters) belong in a separate `PlayerState` object that stores only the
  player's id string — never a reference back to `PlayerData`.
- Instructions are typed Resources. `InstructionDefaults` supplies a baseline per
  `role_id`; `data/instructions.json` holds only per-player and per-club overrides.
- In `instructions.json`, enum values are written as UPPER_SNAKE_CASE strings
  (`"ATTACKING"`, `"NARROW"`), never raw integers. Validation rejects unknown
  keys and unknown names. Booleans stay JSON `true`/`false`.

## Physics layers

Configured in `project.godot`: `world` (1), `player` (2), `ball` (4), `trigger` (8).
Reference them through `FMEnums.LAYER_*`, never raw integers.

## Verification

- Headless suite: `Godot_v4.7.2-stable_linux.x86_64 --headless --path . res://tests/test_scene.tscn`
- `--check-only` relies on Godot's global class cache, so new `class_name` scripts
  must be scanned by the editor before standalone checks work; `run_checks.sh`
  does this automatically and also applies timeouts so a failed autoload cannot
  hang the run.
- Exit code 0 means all assertions passed; any `push_error` is a failure.
- Visual work (pitch, pills, UI) requires the user to look at it — headless tests
  cannot verify appearance.
