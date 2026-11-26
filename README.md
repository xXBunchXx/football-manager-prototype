# Football Manager prototype

A Godot 4.7.2 prototype: physics-driven 3D match engine with deep individual
player instructions. See `docs/CONVENTIONS.md` for structure and naming rules.

Repository: https://github.com/xXBunchXx/football-manager-prototype (public).

## Status

Phase 4 (ball physics) complete: `scenes/ball.tscn` is an always-physical
`RigidBody3D` ball. Kicks/headers are impulses with loft, scatter and side spin;
a Magnus force curves spinning shots. Possession is steering-force control
(toward a point at the player's feet, no reparenting). `PitchBounds.classify()`
does code-based goal/out-of-play checks. Press **K** in the match scene for a
debug kick. No AI or match rules yet.

Earlier phases: `scenes/pitch.tscn` with procedural markings/goals, 22
`RigidBody3D` capsule players in 4-3-3, camera modes on keys 1/2/3; typed
Resources (`PlayerData`, `StatProfile`, `ClubData`, `LeagueData`) loaded from
JSON fixtures (six clubs, 108 players, 16 attributes each). To regenerate
fixtures, edit `tools/generate_fixtures.py` and run
`python3 tools/generate_fixtures.py` from the project root.

To look at the match: open `scenes/match_scene.tscn` and press Play (K = kick).

Next: phase 5, per-player instructions and player state.

## Run the checks

```bash
~/MyStuff/Godot/football-manager/tests/run_checks.sh
```

This parses every script with the real Godot binary and runs the headless test
scene. Exit code 0 means all assertions passed.

## Open the project

`SUPER+G` launches Godot; open `~/MyStuff/Godot/football-manager/project.godot`.
