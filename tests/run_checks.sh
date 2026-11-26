#!/usr/bin/env bash
# Full check: standalone parse of every script, then the headless test scene.
# Autoload globals cannot resolve under --check-only, so those scripts are skipped
# there and validated by the test scene instead.
set -uo pipefail

GODOT="${GODOT_BIN:-/home/bubbles/MyStuff/Godot/Godot_v4.7.2-stable_linux.x86_64}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

# New class_name scripts are not visible to --check-only until the editor scans
# them, so refresh the global class cache first.
timeout 90s "$GODOT" --headless --path "$PROJECT" --editor --quit >/dev/null 2>&1

while IFS= read -r file; do
	rel="${file#$PROJECT/}"
	output=$(timeout 30s "$GODOT" --headless --path "$PROJECT" --check-only --script "res://$rel" 2>&1)
	rc=$?
	if [ $rc -eq 0 ]; then
		printf 'OK    %s\n' "$rel"
	elif printf '%s' "$output" | grep -Eq 'Identifier not found: (GameData|RngService|MatchEvents|SaveGame|LeagueManager)'; then
		printf 'SKIP  %s (autoload ref; covered by test scene)\n' "$rel"
	else
		printf 'FAIL  %s\n%s\n' "$rel" "$output"
		fail=1
	fi
done < <(find "$PROJECT/src" "$PROJECT/tests" -name '*.gd' -type f | sort)

timeout 60s "$GODOT" --headless --path "$PROJECT" res://tests/test_scene.tscn
rc=$?
if [ $rc -ne 0 ]; then
	printf 'FAIL  test scene (exit %s)\n' "$rc"
	fail=1
fi

exit $fail
