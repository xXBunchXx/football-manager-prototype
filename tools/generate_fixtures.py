#!/usr/bin/env python3
"""Generate deterministic JSON fixtures for the football manager prototype.

The JSON files are the source of truth used by the Godot project; this script is
a development tool for regenerating or rebalancing them. Edit the tier bases and
position boosts here, then rerun to rewrite data/*.json.
"""
from __future__ import annotations

import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
SEED = 20261126

ATTRIBUTES = [
    "pace", "acceleration", "finishing", "passing", "first_touch", "heading",
    "tackling", "strength", "stamina", "anticipation", "positioning",
    "composure", "decisions", "vision", "work_rate", "technique",
]

POSITIONS = ["GK", "CB", "LB", "RB", "DM", "CM", "AM", "LW", "RW", "ST"]
STARTERS = ["GK", "CB", "CB", "LB", "RB", "DM", "CM", "AM", "LW", "ST", "RW"]
BENCH = ["GK", "CB", "LB", "DM", "CM", "RW", "ST"]

CLUBS = [
    {"id": "ashford-city", "name": "Ashford City", "short": "ASH", "tier": 2, "primary": "#c8102e", "secondary": "#ffffff"},
    {"id": "kingsport-rovers", "name": "Kingsport Rovers", "short": "KGS", "tier": 2, "primary": "#1d4ed8", "secondary": "#ffffff"},
    {"id": "northbridge-united", "name": "Northbridge United", "short": "NOR", "tier": 1, "primary": "#15803d", "secondary": "#ffffff"},
    {"id": "riverton-athletic", "name": "Riverton Athletic", "short": "RIV", "tier": 1, "primary": "#b45309", "secondary": "#111827"},
    {"id": "dunmoor-town", "name": "Dunmoor Town", "short": "DUN", "tier": 0, "primary": "#6b7280", "secondary": "#dbeafe"},
    {"id": "westfield-fc", "name": "Westfield FC", "short": "WES", "tier": 0, "primary": "#7f1d1d", "secondary": "#fef3c7"},
]

TIER_BASE = {0: 7, 1: 10, 2: 13}

BOOSTS = {
    "GK": {"positioning": 4, "anticipation": 3, "composure": 3, "decisions": 2, "heading": 2, "strength": 1},
    "CB": {"tackling": 4, "strength": 3, "heading": 4, "positioning": 2, "anticipation": 1, "pace": -2},
    "LB": {"pace": 3, "acceleration": 3, "stamina": 2, "tackling": 2, "passing": 1},
    "RB": {"pace": 3, "acceleration": 3, "stamina": 2, "tackling": 2, "passing": 1},
    "DM": {"tackling": 3, "strength": 2, "passing": 2, "positioning": 2, "stamina": 2},
    "CM": {"passing": 3, "vision": 3, "technique": 3, "stamina": 2, "first_touch": 2},
    "AM": {"passing": 3, "vision": 4, "technique": 3, "first_touch": 3, "finishing": 1},
    "LW": {"pace": 4, "acceleration": 4, "technique": 3, "first_touch": 2, "finishing": 1},
    "RW": {"pace": 4, "acceleration": 4, "technique": 3, "first_touch": 2, "finishing": 1},
    "ST": {"finishing": 4, "positioning": 3, "heading": 3, "strength": 2, "pace": 2},
}

FIRST_NAMES = [
    "James", "Oliver", "William", "Harry", "George", "Noah", "Jack", "Charlie", "Leo", "Freddie",
    "Alfie", "Thomas", "Oscar", "Archie", "Finley", "Ethan", "Mason", "Logan", "Callum", "Nathan",
    "Samuel", "Benjamin", "Daniel", "Alexander", "Joshua", "Max", "Lucas", "Henry", "Isaac", "Theo",
    "Elias", "Mateo", "Rafael", "Diego", "Hugo", "Marco",
]

LAST_NAMES = [
    "Smith", "Jones", "Taylor", "Brown", "Williams", "Wilson", "Johnson", "Davies", "Miller", "Moore",
    "Clarke", "Harrison", "Turner", "Walker", "Hughes", "Cooper", "Ward", "Morris", "King", "Wright",
    "Bennett", "Foster", "Gray", "Price", "Evans", "Baker", "Hall", "Cook", "Norton", "Reed",
    "Silva", "Moreau", "Keller", "Rossi", "Vincent", "Fischer",
]

NATIONALITIES = ["ENG", "SCO", "WAL", "IRL", "FRA", "GER", "ESP", "ITA", "NED", "POR", "BRA", "ARG"]


def clamp(value: int) -> int:
    return max(1, min(20, value))


def make_player(club_id: str, number: int, position: str, tier: int, starter: bool, rng: random.Random) -> dict:
    base = TIER_BASE[tier] + (1 if starter else -1)
    boosts = BOOSTS[position]
    attributes = {}
    for key in ATTRIBUTES:
        attributes[key] = clamp(base + boosts.get(key, 0) + rng.randint(-2, 2))

    return {
        "id": f"{club_id}-{number:02d}",
        "first_name": "",  # filled by main() to guarantee uniqueness
        "last_name": "",
        "known_as": "",
        "age": rng.randint(23, 31) if starter else rng.randint(18, 32),
        "nationality": rng.choice(NATIONALITIES),
        "preferred_foot": rng.choices([0, 1, 2], weights=[15, 80, 5], k=1)[0],
        "positions": [POSITIONS.index(position)],
        "role_id": position.lower(),
        "attributes": attributes,
    }


def unique_name(rng: random.Random, used: set[tuple[str, str]]) -> tuple[str, str]:
    for _ in range(200):
        candidate = (rng.choice(FIRST_NAMES), rng.choice(LAST_NAMES))
        if candidate not in used:
            used.add(candidate)
            return candidate
    raise RuntimeError("Could not generate a unique player name")


def write_json(filename: str, payload) -> None:
    path = DATA_DIR / filename
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)} ({len(payload)} entries)")


def main() -> None:
    rng = random.Random(SEED)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    used_names: set[tuple[str, str]] = set()
    players: list[dict] = []
    clubs: list[dict] = []

    for club in CLUBS:
        player_ids: list[str] = []
        for number, position in enumerate(STARTERS + BENCH, start=1):
            player = make_player(club["id"], number, position, club["tier"], number <= 11, rng)
            first, last = unique_name(rng, used_names)
            player["first_name"] = first
            player["last_name"] = last
            players.append(player)
            player_ids.append(player["id"])
        clubs.append({
            "id": club["id"],
            "name": club["name"],
            "short_name": club["short"],
            "tier": club["tier"],
            "primary_color": club["primary"],
            "secondary_color": club["secondary"],
            "player_ids": player_ids,
        })

    leagues = [{
        "id": "premier-division",
        "name": "Premier Division",
        "club_ids": [club["id"] for club in clubs],
    }]

    write_json("players.json", players)
    write_json("clubs.json", clubs)
    write_json("leagues.json", leagues)

    for tier in (0, 1, 2):
        tier_players = [p for p, c in zip(players, [c for c in clubs for _ in c["player_ids"]]) if c["tier"] == tier]
        average = sum(sum(p["attributes"].values()) / len(ATTRIBUTES) for p in tier_players) / len(tier_players)
        print(f"tier {tier}: average {average:.2f}")


if __name__ == "__main__":
    main()
