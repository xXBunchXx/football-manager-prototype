# Football Manager prototype

A Godot 4.7.2 prototype: physics-driven 3D match engine with deep individual
player instructions. See `docs/CONVENTIONS.md` for structure and naming rules.

Repository: https://github.com/xXBunchXx/football-manager-prototype (public).

## Status

Phase 9 (playtest instrumentation) plus the statistics/simulation layer is
complete. The match HUD shows score, clock/added time, state, last event, a live
team-stat strip and the selected speed step. `MatchStats` records team and
per-player attempts/completions (passes, crosses, switches, shots, dribbles),
touches, control time, tackles/wins, fouls, cards, saves and goals. At full time
the match writes a `MatchRecord` to `MatchHistory` through `SaveGame`, so live
and simulated records can be compared from the same save. **P** prints the
current summary to the event log; the older per-match JSONL log is still written
for `tools/calibrate_playtest.py`.

Bulk analysis is the fast path: `FastMatchSimulator` resolves possessions from
the same attribute/instruction/tactic tables as the live brain without running
Jolt or rendering, a season in seconds. The league screen has **Sim round**,
**Sim season** and **Analysis** buttons; played fixtures show saved stats instead
of replaying the score. The report aggregates club and player rates and flags
patterns such as high tackle volume with a low win rate, poor pass completion,
low shot conversion and possession starvation. Thresholds live in the
`simulation` and `analysis` blocks of `data/stat_effects.json`; live matches stay
the physical truth and still run a real-time 90-minute clock at 1x.

Headless suite: 235 checks passing, including seeded fast-sim determinism and
`RngService.chance` using the seeded stream. Balance changes remain JSON-only.
Actual weight tuning is pending your playtest.

Playtest fix: the pitch now creates a real static `GroundCollider`, pills use a
frictionless physics material, `PlayerAgent` adds proximity separation (opponents
push harder than team-mates), and support targets use stable per-player lanes so
team-mates spread out instead of stacking on one spot.

Behaviour fix: `shoot_on_sight` and the `runs_forward` dribble bonus now apply only
when the ball is in control range, so players chase play instead of walking to the
opponent goal. Goalkeepers anchor near their own goal, support targets are clamped
to the pitch, and kick-offs return players to their formation. Magnitudes remain
in `data/stat_effects.json`.

Visibility and shape: the match now opens in a closer follow-ball camera (keys
1/2/3 still switch broadcast/top-down/follow), the ball is larger and emissive
with a `BALL` marker, and support targets are anchored to each player's 4-3-3 slot
in `Formation`. The ball shifts the whole shape slightly rather than pulling
everyone to it; `formation_ball_follow_scale` and `formation_max_shift_m` are
JSON-only tuning keys.

Possession fix: only the closest outfielder chases a loose ball or takes control,
and pass/dribble/shoot are penalised when the ball is out of reach. Once a player
owns the ball, pass/dribble win over passive support; marking is only for players
with `man_mark`. These thresholds are all in `data/stat_effects.json`.

Pacing, restarts and markings: one match now runs at true 90-minute wall-clock
speed (45 real minutes per half). Every restart places both sides legally —
kick-offs in their own halves, goal kicks from the six-yard box with everyone
else outside the penalty area, and opponents outside the 9.15 m exclusion circle
for free kicks, corners and throw-ins. A goal kick stays restricted until the
ball clears the box. Assigned markers stand 3 m goal-side and only follow
opponents inside their own zone. The pitch now draws the penalty-area and
six-yard-box lines at their real far edges, plus the centre spot, penalty arcs
and corner arcs. New thresholds are in `data/stat_effects.json`, `data/rules.json`
and `MatchConfig`.

Play-rate fix: a pass or shot now fires at most once every
`kick_cooldown_seconds` instead of every physics frame, and passes are aimed at
an open forward team-mate with a strike speed scaled to the distance. Only the
closest defender on each side challenges within `tackle_radius_m` (later team-mates
are penalised by `tackle_rank_penalty_per_place`). A challenge is one roll with a
cooldown: a beaten tackler backs off instead of instantly snapping the ball back,
and a carrier can never tackle himself. A pass with no eligible receiver is
rejected in favour of the next useful action. `KeeperRule` parries shots heading
into the goal; saves are counted in the playtest log. `FoulRule` rolls once per
challenge rather than every frame. All new thresholds are in
`data/stat_effects.json`, `data/rules.json` and `MatchConfig`.

Generic match style: carriers now use the wings, switch play to the far side,
cross from wide areas and drive forward when they have space. Wide players
behind the carrier make overlapping runs instead of standing in shape, and a
pass with no forward receiver falls back to the next useful action. Players
move at speeds derived from `pace` and stamina, with a shared tempo pulse that
gently slows and quickens decision-making, strike pace and movement without
touching the real-time match clock. Team mentality, tempo, width and passing
style feed the same modifier tables, so later tactic work can bias crosses,
switches or overlaps from `data/stat_effects.json`. Cross and switch strike
shapes are tuned in `MatchConfig`.

Earlier: Phase 8 (league layer) — `FixtureGenerator` builds a deterministic
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

To play a season: open `scenes/ui/league_scene.tscn` and click an unplayed
fixture or **Play next**. Played fixtures open their saved stats. The other
buttons are **Sim round**, **Sim season**, **Analysis** and **Reset season**.
In a match: **1-4** select `MatchConfig.speed_steps` (`0, 1, 2, 4` — key 2 is the
default real-time 90 minutes), **K** = debug kick, **S** = substitution,
**P** = print stats, **L** = league screen. `scenes/match_scene.tscn` still opens
directly for engine work.

Next: visually confirm the HUD stat strip, speed label and league
simulation/analysis screens on the live desktop, then apply the calibration
findings from your playtest, changing only `data/stat_effects.json` and
`data/rules.json`.

Aggregate a playtest log with:

```bash
python3 tools/calibrate_playtest.py
```

## Run the checks

```bash
~/MyStuff/Godot/football-manager/tests/run_checks.sh
```

This parses every script with the real Godot binary and runs the headless test
scene. Exit code 0 means all assertions passed.

## Open the project

`SUPER+G` launches Godot; open `~/MyStuff/Godot/football-manager/project.godot`.
