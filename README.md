# Football Manager prototype

A Godot 4.7.2 prototype: physics-driven 3D match engine with deep individual
player instructions. See `docs/CONVENTIONS.md` for structure and naming rules.

Repository: https://github.com/xXBunchXx/football-manager-prototype (public).

## Status

Phase 2 (player/club data) complete: typed Resources (`PlayerData`,
`StatProfile`, `ClubData`, `LeagueData`) loaded and validated from JSON fixtures
in `data/`. Six clubs, 108 players, 16 attributes per player.

To regenerate/rebalance the fixtures, edit `tools/generate_fixtures.py` and run
`python3 tools/generate_fixtures.py` from the project root.

Next: phase 3, the 3D pitch and pill players.

## Run the checks

```bash
~/MyStuff/Godot/football-manager/tests/run_checks.sh
```

This parses every script with the real Godot binary and runs the headless test
scene. Exit code 0 means all assertions passed.

## Open the project

`SUPER+G` launches Godot; open `~/MyStuff/Godot/football-manager/project.godot`.
