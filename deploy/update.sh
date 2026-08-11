#!/usr/bin/env bash
# Update the live Arkenelle world from the latest main branch.
# Safe to re-run. Prefer calling via GitHub Actions; you can also run manually:
#   sudo bash /opt/arkenelle/deploy/update.sh
set -euo pipefail

APP_DIR="/opt/arkenelle"
APP_USER="arkenelle"
BRANCH="${ARKENELLE_DEPLOY_BRANCH:-main}"

if [[ "$(id -u)" -ne 0 ]]; then
	echo "Run as root: sudo bash $0" >&2
	exit 1
fi

if [[ ! -d "$APP_DIR/.git" ]]; then
	echo "Missing git repo at $APP_DIR" >&2
	exit 1
fi

echo "==> Fetching origin/${BRANCH}"
sudo -u "$APP_USER" git -C "$APP_DIR" fetch --prune origin "$BRANCH"

echo "==> Resetting to origin/${BRANCH}"
# Deploy machine must match the branch exactly. Prior `godot --import` runs
# rewrite *.import files on disk; reset --hard clears those so pulls never stall.
sudo -u "$APP_USER" git -C "$APP_DIR" reset --hard "origin/${BRANCH}"
sudo -u "$APP_USER" git -C "$APP_DIR" clean -fd

echo "==> Importing Godot assets"
sudo -u "$APP_USER" godot --headless --path "$APP_DIR" --import

echo "==> Refreshing systemd units (keeps --env=live and other ExecStart flags current)"
install -m 0644 "$APP_DIR"/deploy/systemd/arkenelle-*.service /etc/systemd/system/
systemctl daemon-reload

echo "==> Restarting game services"
systemctl restart arkenelle-master arkenelle-gateway arkenelle-world

# Wait until loopback ports are actually accepting connections. systemctl
# "active" alone is not enough — godot can still be mid-boot (or crash-looping)
# while Caddy already returns 502 for play.arkenelle.com.
wait_port() {
	local port="$1"
	local label="$2"
	local seconds="${3:-90}"
	local i
	echo "==> Waiting for $label on 127.0.0.1:$port (up to ${seconds}s)"
	for i in $(seq 1 "$seconds"); do
		if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
			exec 3>&- 2>/dev/null || true
			echo "    $label is up (${i}s)"
			return 0
		fi
		sleep 1
	done
	echo "    ERROR: $label did not open 127.0.0.1:$port within ${seconds}s" >&2
	return 1
}

wait_port 8080 "master dashboard" 60 || true
wait_port 8088 "gateway" 90
if ! wait_port 8087 "world" 90; then
	echo "==> World port still closed — restarting arkenelle-world once and retrying"
	systemctl restart arkenelle-world
	wait_port 8087 "world" 90
fi

echo "==> Status"
systemctl --no-pager --lines=0 status arkenelle-master arkenelle-gateway arkenelle-world || true

echo
echo "Deploy OK @ $(date -u +%Y-%m-%dT%H:%M:%SZ)"
sudo -u "$APP_USER" git -C "$APP_DIR" rev-parse --short HEAD
