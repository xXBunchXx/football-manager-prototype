#!/usr/bin/env python3
"""Summarise fm_playtest_log.jsonl records written by the match scene.

Usage:
    python3 tools/calibrate_playtest.py [path/to/fm_playtest_log.jsonl ...]

With no path, all Godot app_userdata directories are searched. The report only
prints measurements: balance changes belong in data/stat_effects.json and
data/rules.json, never in GDScript.
"""

from __future__ import annotations

import glob
import json
import os
import sys
from pathlib import Path


def default_paths() -> list[str]:
    pattern = os.path.expanduser(
        "~/.local/share/godot/app_userdata/*/fm_playtest_log.jsonl"
    )
    return sorted(glob.glob(pattern))


def load_records(paths: list[str]) -> list[dict]:
    records: list[dict] = []
    for path in paths:
        with Path(path).open(encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    value = json.loads(line)
                except json.JSONDecodeError as error:
                    print(f"skip {path}:{line_number}: {error}")
                    continue
                if isinstance(value, dict):
                    records.append(value)
    return records


def average(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def side_total(records: list[dict], side: str, key: str) -> float:
    return sum(float(record.get("stats", {}).get(side, {}).get(key, 0)) for record in records)


def main() -> int:
    paths = sys.argv[1:] or default_paths()
    records = load_records(paths)
    if not records:
        print("No playtest records found.")
        print("Play a match in Godot; full time writes fm_playtest_log.jsonl.")
        return 0

    matches = len(records)
    goals = side_total(records, "home", "goals") + side_total(records, "away", "goals")
    shots = side_total(records, "home", "shots") + side_total(records, "away", "shots")
    passes = side_total(records, "home", "passes") + side_total(records, "away", "passes")
    fouls = side_total(records, "home", "fouls") + side_total(records, "away", "fouls")
    yellows = side_total(records, "home", "yellow_cards") + side_total(records, "away", "yellow_cards")
    reds = side_total(records, "home", "red_cards") + side_total(records, "away", "red_cards")

    possession_wins = 0
    decisive = 0
    home_goal_totals: list[float] = []
    away_goal_totals: list[float] = []
    for record in records:
        stats = record.get("stats", {})
        home_control = float(stats.get("home", {}).get("control_seconds", 0))
        away_control = float(stats.get("away", {}).get("control_seconds", 0))
        home_goals = float(record.get("home_goals", 0))
        away_goals = float(record.get("away_goals", 0))
        home_goal_totals.append(home_goals)
        away_goal_totals.append(away_goals)
        if home_goals != away_goals:
            decisive += 1
            winner_is_home = home_goals > away_goals
            if (home_control > away_control) == winner_is_home:
                possession_wins += 1

    print(f"Matches logged:            {matches}")
    print(f"Average goals per match:   {goals / matches:.2f}")
    print(f"Home goals per match:      {average(home_goal_totals):.2f}")
    print(f"Away goals per match:      {average(away_goal_totals):.2f}")
    print(f"Shots per goal:            {shots / goals if goals else 0:.2f}")
    print(f"Passes per match:          {passes / matches:.2f}")
    print(f"Fouls per match:           {fouls / matches:.2f}")
    print(f"Cards per match:           {(yellows + reds) / matches:.2f}")
    print(f"Possession matches result: {possession_wins}/{decisive} decisive games")
    print("\nTune data/stat_effects.json and data/rules.json only.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
