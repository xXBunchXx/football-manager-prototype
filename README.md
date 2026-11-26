# Football Manager prototype

A Godot 4.7.2 prototype: physics-driven 3D match engine with deep individual
player instructions. See `docs/CONVENTIONS.md` for structure and naming rules.

Repository: https://github.com/xXBunchXx/football-manager-prototype (public).

## Status

Phase 3 (pitch and pill players) complete: `scenes/pitch.tscn` with procedural
markings/goals, `scenes/match_scene.tscn` spawning 22 `RigidBody3D` capsule
players in 4-3-3 shape, and a camera rig with broadcast/top-down/follow modes
(keys 1/2/3). No ball physics or AI yet.

Earlier phases: typed Resources (`PlayerData`, `StatProfile`, `ClubData`,
`LeagueData`) loaded from JSON fixtures; six clubs, 108 players, 16 attributes
each. To regenerate/rebalance fixtures, edit `tools/generate_fixtures.py` and run
`python3 tools/generate_fixtures.py` from the project root.

To look at the match: open `scenes/match_scene.tscn` and press Play.

Next: phase 4, ball physics and the kick/header API.

## Run the checks

```bash
~/MyStuff/Godot/football-manager/tests/run_checks.sh
```

This parses every script with the real Godot binary and runs the headless test
scene. Exit code 0 means all assertions passed.

## Open the project

`SUPER+G` launches Godot; open `~/MyStuff/Godot/football-manager/project.godot`.
