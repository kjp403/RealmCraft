#!/usr/bin/env bash
# Runs one RealmCraft dedicated server for the Cloud Agent `terminals`.
#
# Usage: run-server.sh <mode> [wait_port]
#   mode      = master-server | gateway-server | world-server
#   wait_port = optional TCP port to wait for before starting (gateway/world
#               wait for the master's manager ports so they connect cleanly).
#
# The server is restarted if it exits. The world server has a known
# intermittent native crash on world spin-up that clears on the next attempt,
# so a plain one-shot terminal would leave the world down; the restart loop
# makes the dev stack self-healing.
set -u

MODE="${1:?usage: run-server.sh <mode> [wait_port]}"
WAIT_PORT="${2:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ -n "$WAIT_PORT" ]; then
	echo "[$MODE] waiting for 127.0.0.1:$WAIT_PORT ..."
	until (exec 3<>"/dev/tcp/127.0.0.1/$WAIT_PORT") 2>/dev/null; do sleep 1; done
	exec 3>&- 2>/dev/null || true
	echo "[$MODE] dependency port $WAIT_PORT is up."
fi

while true; do
	echo "[$MODE] starting: godot --headless --mode=$MODE"
	godot --headless --path . --mode="$MODE"
	code=$?
	echo "[$MODE] exited with code $code; restarting in 2s ..." >&2
	sleep 2
done
