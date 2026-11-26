# Football Manager prototype

A Godot 4.7.2 prototype: physics-driven 3D match engine with deep individual
player instructions. See `docs/CONVENTIONS.md` for structure and naming rules.

Repository: https://github.com/xXBunchXx/football-manager-prototype (public).

## Status

Phase 8 (league layer) complete: `FixtureGenerator` builds a deterministic
double round-robin (30 fixtures, 10 rounds). Every fixture is playable — click
one in `scenes/ui/league_scene.tscn`, or use **Play next fixture**. `LeagueManager`
persists results through `SaveGame`; standings are rebuilt from played fixtures,
so saves cannot disagree with the table. Full time in a played match records the
score, and **L** returns to the league screen.

Earlier: Phase 7 (match rules) — `RulesEngine` orchestrates small, independent
rule classes under `src/match/rules/`. Offside is judged at the pass and resolved
at first touch; tackle-based fouls roll cards through `PlayerState`; all six
restarts place the ball from `data/rules.json`; substitutions are capped per club;
stoppage is banked as added time. Press **K** for a debug kick and **S** to
request a home substitution.

Earlier: Phase 6 (decision layer) — `DecisionBrain` scores eight actions from
attribute weights, instruction modifiers and context thresholds in
`data/stat_effects.json`; the highest score drives each player's target and
action. `PlayerAgent` steers `RigidBody3D` players with forces toward that
target and kicks/passes when the ball is in control range. `MatchContext` keeps
the world snapshot testable. Stronger attributes and shoot-on-sight measurably
raise shoot utility; low stamina lowers pressing utility.

Earlier: Phase 5 (instructions and player state) — `PlayerInstructions` and
`TeamInstructions` are typed Resources with validated UPPER_SNAKE_CASE enum names
in `data/instructions.json`. `InstructionDefaults` supplies role baselines and
JSON overrides only the exceptions. `PlayerState` holds mutable per-match values
(stamina, fatigue, morale, form, injury risk, cards, mark assignment, duty
override, event counters) and stores only a player id, so it cannot mutate the
immutable `PlayerData`. Every match starter carries both.

Phase 4: `scenes/ball.tscn` is an always-physical
`RigidBody3D` ball. Kicks/headers are impulses with loft, scatter and side spin;
a Magnus force curves spinning shots. Possession is steering-force control
(toward a point at the player's feet, no reparenting). `PitchBounds.classify()`
does code-based goal/out-of-play checks. Press **K** in the match scene for a
debug kick; rules are layered on separately by `RulesEngine`.

Earlier phases: `scenes/pitch.tscn` with procedural markings/goals, 22
`RigidBody3D` capsule players in 4-3-3, camera modes on keys 1/2/3; typed
Resources (`PlayerData`, `StatProfile`, `ClubData`, `LeagueData`) loaded from
JSON fixtures (six clubs, 108 players, 16 attributes each). To regenerate
fixtures, edit `tools/generate_fixtures.py` and run
`python3 tools/generate_fixtures.py` from the project root.

To play a season: open `scenes/ui/league_scene.tscn` and press Play, then click a
fixture. In a match: **K** = debug kick, **S** = substitution, **L** = league
screen. `scenes/match_scene.tscn` still opens directly for engine work.

Next: phase 9, polish and balance — visual pass, full-season playtest and
calibration.

## Run the checks

```bash
~/MyStuff/Godot/football-manager/tests/run_checks.sh
```

This parses every script with the real Godot binary and runs the headless test
scene. Exit code 0 means all assertions passed.

## Open the project

`SUPER+G` launches Godot; open `~/MyStuff/Godot/football-manager/project.godot`.
