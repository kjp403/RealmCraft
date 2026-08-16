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
# Exclude VPS runtime: Godot user:// under HOME=/opt/arkenelle, plus the
# play.arkenelle.com docroot which publish-web-client.sh may own as root.
sudo -u "$APP_USER" git -C "$APP_DIR" clean -fd -e .local -e .cache -e .config -e client-web -e client-windows

echo "==> Importing Godot assets"
sudo -u "$APP_USER" godot --headless --path "$APP_DIR" --import

echo "==> Refreshing systemd units (keeps --env=live and other ExecStart flags current)"
install -m 0644 "$APP_DIR"/deploy/systemd/arkenelle-*.service /etc/systemd/system/
systemctl daemon-reload

echo "==> Refreshing Caddy (browser client on play.arkenelle.com GET, world on WS upgrade)"
install -m 0644 "$APP_DIR/deploy/Caddyfile" /etc/caddy/Caddyfile
mkdir -p /opt/arkenelle/client-web /opt/arkenelle/client-windows
# Directory must be owned by arkenelle so a stray git clean can unlink files.
# Do not chown -R — Caddy is serving this tree.
chown arkenelle:arkenelle /opt/arkenelle/client-web /opt/arkenelle/client-windows
chmod a+rX /opt/arkenelle/client-web /opt/arkenelle/client-windows
if [[ ! -f /opt/arkenelle/client-web/index.html ]]; then
	install -m 0644 "$APP_DIR/deploy/client-web-placeholder/index.html" /opt/arkenelle/client-web/index.html
	chown arkenelle:arkenelle /opt/arkenelle/client-web/index.html
fi
caddy validate --config /etc/caddy/Caddyfile
# systemd `reload caddy` has hung ~90s then failed, aborting the whole deploy
# before game services restart. Use Caddy's admin API with a short timeout so
# a sticky proxy cannot keep the world on the previous version.
if ! timeout 15 caddy reload --config /etc/caddy/Caddyfile; then
	echo "WARN: caddy reload failed or timed out — trying restart"
	timeout 20 systemctl restart caddy || echo "WARN: caddy still down; continuing so the world can come up"
fi

echo "==> Restarting game services"
systemctl restart arkenelle-master arkenelle-gateway arkenelle-world

# Wait until loopback ports are actually accepting connections. systemctl
# "active" alone is not enough — godot can still be mid-boot (or crash-looping)
# before clients can connect.
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

# Godot's world peer only speaks WebSocket. A plain HTTP GET through Caddy always
# surfaces as 502 even when the world is healthy — probe the upgrade handshake.
wait_world_ws() {
	local seconds="${1:-30}"
	local i code
	echo "==> Waiting for world WebSocket handshake on 127.0.0.1:8087 (up to ${seconds}s)"
	for i in $(seq 1 "$seconds"); do
		code="$(curl --http1.1 -sS -o /dev/null -w '%{http_code}' --max-time 2 \
			-H 'Connection: Upgrade' \
			-H 'Upgrade: websocket' \
			-H 'Sec-WebSocket-Version: 13' \
			-H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
			"http://127.0.0.1:8087/" 2>/dev/null || true)"
		if [[ "$code" == "101" ]]; then
			echo "    world WebSocket OK (101, ${i}s)"
			return 0
		fi
		sleep 1
	done
	echo "    ERROR: world WebSocket did not return 101 within ${seconds}s (last=$code)" >&2
	return 1
}

wait_port 8080 "master dashboard" 60 || true
wait_port 8088 "gateway" 90
if ! wait_port 8087 "world" 90; then
	echo "==> World port still closed — restarting arkenelle-world once and retrying"
	systemctl restart arkenelle-world
	wait_port 8087 "world" 90
fi
if ! wait_world_ws 45; then
	echo "==> World WS handshake failed — restarting arkenelle-world once and retrying"
	systemctl restart arkenelle-world
	wait_port 8087 "world" 90
	wait_world_ws 45
fi

echo "==> Status"
systemctl --no-pager --lines=0 status arkenelle-master arkenelle-gateway arkenelle-world || true

echo
echo "Deploy OK @ $(date -u +%Y-%m-%dT%H:%M:%SZ)"
sudo -u "$APP_USER" git -C "$APP_DIR" rev-parse --short HEAD
