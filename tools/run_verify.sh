#!/usr/bin/env bash
# Run the headless verify gates and assert each one actually PASSED.
#
#   tools/run_verify.sh [godot-binary] [gate ...]
#
# With no gate names it runs DEFAULT_GATES below.
#
# WHY THIS EXISTS
# A verify gate can exit 0 having checked nothing. tools/verify_boss_hunt.gd is
# scene-mode; run it as `-s` and the catalog scan dies on the missing autoloads
# before the first check, printing NO output at all — and then exiting 0. Any
# step that trusts the exit code, or greps for the ABSENCE of VERIFY_FAIL, reads
# that as a green gate forever. This script asserts on the literal string
# VERIFY_PASS and on nothing else.
#
# It also encodes the run mode per gate, which is the other half of the same
# trap: a scene-mode tool invoked with `-s` is silently useless. If a gate has a
# sibling .tscn, it MUST be run as a scene.
set -euo pipefail

GODOT="${1:-godot}"
shift || true

# Gates known green. Deliberately a short allow-list rather than "everything in
# tools/": several verify_* tools are historical one-shots for content that has
# since changed, and tools/verify_progression_pass.gd currently reports 6
# pre-existing content failures (crafting XP + quest reward tuning). Add a gate
# here once it is green and expected to stay that way.
DEFAULT_GATES=(
	verify_client_updater
	verify_boss_hunt
	verify_skilling_rewards
	verify_reward_audio
	verify_pixel_chrome
	verify_reward_window_layer
)

GATES=("$@")
if [ ${#GATES[@]} -eq 0 ]; then
	GATES=("${DEFAULT_GATES[@]}")
fi

failed=0
for gate in "${GATES[@]}"; do
	scene="tools/${gate}.tscn"
	script="tools/${gate}.gd"
	if [ -f "$scene" ]; then
		# Scene mode: the tool needs autoloads.
		cmd=("$GODOT" --headless --path . "res://${scene}")
		mode="scene"
	elif [ -f "$script" ]; then
		cmd=("$GODOT" --headless --path . -s "$script")
		mode="-s"
	else
		echo "MISSING GATE: $gate (no tools/${gate}.tscn or .gd)"
		failed=1
		continue
	fi

	log="$(mktemp)"
	# The gate's own exit code is deliberately ignored (|| true): it is not the
	# signal. The printed VERIFY_PASS is.
	"${cmd[@]}" >"$log" 2>&1 || true

	if grep -q "VERIFY_PASS" "$log"; then
		echo "PASS  $gate ($mode)"
	else
		failed=1
		echo "FAIL  $gate ($mode)"
		# Show why. A gate that printed nothing at all is the silent-pass case
		# this script exists to catch, so say so explicitly.
		if ! grep -qE "VERIFY_(PASS|FAIL)" "$log"; then
			echo "      no VERIFY_ output at all — the gate never ran (wrong mode? load error?)"
		fi
		grep -E "^  - |^VERIFY_FAIL|SCRIPT ERROR|Parse Error" "$log" | head -20 | sed 's/^/      /'
	fi
	rm -f "$log"
done

if [ "$failed" -ne 0 ]; then
	echo "VERIFY GATES FAILED"
	exit 1
fi
echo "ALL VERIFY GATES PASSED"
