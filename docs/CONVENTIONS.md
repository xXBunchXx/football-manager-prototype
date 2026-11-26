# Project conventions

Godot 4.7.2, GDScript, Jolt Physics. These rules are binding for all code in this
project. Update this document in the same change if a convention changes.

## Layout

- `data/` — hand-editable JSON fixtures: generated players/clubs/leagues plus
  `instructions.json`, `stat_effects.json` and `rules.json` for tuning.
- `src/core/` — Resource classes, enums, config. No scene logic here.
- `src/autoload/` — global singletons: `GameData`, `RngService`, `MatchEvents`,
  `SaveGame`, `LeagueManager`.
- `src/match/` — match simulation, agents, ball, rules engine and debug overlay.
- `src/league/` — fixtures, table and season manager. No scene logic here.
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
  resolve autoload globals (`GameData`, `RngService`, `MatchEvents`, `SaveGame`,
  `LeagueManager`), so scripts using them are validated by the test scene instead.

## Data rules

- No magic numbers in logic. Tuning goes in `MatchConfig`,
  `data/stat_effects.json` (decisions and movement) or `data/rules.json`
  (officiating, restarts and clock).
- Decisions are utility scores: `DecisionBrain` combines action base scores,
  attribute weights and instruction modifiers from `stat_effects.json`. Never
  add a hardcoded weight to the brain — put it in that JSON instead.
- JSON is the source of truth for generated content; `FixtureLoader` validates it
  and constructs typed Resources. `StatEffects` and `RulesConfig` are the typed
  views for the two tuning files. User-created content is saved as JSON in `user://`.
- Rules live in one class per concern under `src/match/rules/`; `RulesEngine`
  orchestrates them, owns match state and raises `RuleEvent`s. Rule classes stay
  headless-testable: the scene owns presentation and body placement.
- Season progress lives in the fixture list; standings are derived from played
  fixtures, never stored as a second source of truth. `LeagueManager` is the
  scene-facing wrapper around the headless `SeasonManager`.
- Balance changes are JSON-only: tune `stat_effects.json` or `rules.json`, not
  GDScript weights. `MatchStats` records playtest measurements; the calibration
  tool only reports them.
- The grass mesh is visual only; `Pitch` must create the `GroundCollider` from
  `MatchConfig` so the ball and pills cannot fall through the world. Player
  separation belongs in `PlayerAgent` and support lanes in `DecisionBrain`; keep
  both when retuning steering so bodies do not clump.
- Ball-only modifiers (`shoot_on_sight`, `runs_forward` dribble) are gated by
  `ball_control_radius_m` in `DecisionBrain`; do not reapply them globally. GK
  positioning uses `gk_line_depth_m` / `gk_lateral_follow_scale` from
  `stat_effects.json`, and support targets are clamped by
  `MatchConfig.support_edge_inset_m`.
- The 4-3-3 shape lives once in `src/core/formation.gd`; `MatchScene` copies each
  slot onto `PlayerView.formation_slot` and `DecisionBrain` anchors support there.
  Keep the ball's influence capped by `formation_ball_follow_scale` and
  `formation_max_shift_m` so the team holds structure. The match camera defaults
  to FOLLOW; keep the ball's `BALL` marker when changing its scene.
- Loose-ball pursuit is ranked: `MatchContext.ball_chaser_rank()` says who chases,
  and `PlayerAgent` only lets the nearest outfielder take control. On-ball actions
  get their bonus only when the ball is in reach; keep the out-of-range penalties
  and `mark_unassigned_penalty` in `stat_effects.json` when retuning behaviour.
- A match is 45 real minutes per half (`MatchConfig.half_length_seconds`), so the
  scoreboard clock advances one match second per real second. Restart geometry
  (`restart_exclusion_radius_m`, `taker_offset_m`) belongs in `rules.json`;
  `RestartRule` places the bodies, and `PlayerAgent` freezes during
  `MatchState.RESTART` and honours the goal-kick restriction through
  `MatchContext.can_play_ball()`.
- Assigned markers stand `mark_stand_off_m` goal-side of their opponent and only
  follow targets inside `mark_zone_radius_m`; keep both in `stat_effects.json`.
  Pitch dimensions and arc radii are exported on `MatchConfig`; `Pitch` must draw
  the penalty-area and six-yard lines at their far edges, and keep the centre
  spot, penalty arcs and corner arcs.
- A pass or shot is one strike, not a per-frame decision: keep the
  `kick_cooldown_seconds` gate in `PlayerAgent`. `MatchContext.best_pass_target()`
  uses the whole `StatEffects.context` dictionary, so pass weights and lane
  checks stay in `stat_effects.json`; pass speed comes from `MatchConfig`
  (`pass_travel_seconds`, `pass_min_speed_mps`, `pass_speed_mps`), never a single
  fixed value.
- A defender within `tackle_radius_m` may take control from an opponent carrier
  even though he is not the closest player to the ball, but only the closest
  defender per side gets the tackle bonus (`ball_chaser_rank()` +
  `tackle_rank_penalty_per_place`). A tackle is one contested roll, not a
  per-frame control grab: keep `tackle_challenge_cooldown_seconds`,
  `tackle_success_chance`, `tackle_backoff_seconds` and
  `tackle_backoff_distance_m` in `stat_effects.json`, and never let a carrier
  choose TACKLE. A PASS decision with no eligible receiver must fall back to the
  next action. `FoulRule` must roll once per challenge
  (`foul.tackle_cooldown_seconds`) and `KeeperRule` must emit a
  `RuleEvent.Type.SAVE` via `Ball.deflect()`; keep keeper radii and speeds in
  `rules.json` and saves in `MatchStats`.
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
