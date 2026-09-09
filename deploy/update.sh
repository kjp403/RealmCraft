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

# Dump the world's own journal when the deploy exits non-zero. Without this the
# Actions log ends at "handshake failed" and says nothing about WHY, so every
# investigation costs an SSH session — and the obvious guess (the merge broke it)
# is usually wrong. The ~50 address frames of a Godot backtrace carry nothing
# readable here, so strip them and keep the messages, which name the failing
# script and line. Note Godot reports the real signal itself: systemd will say
# status=6/ABRT even for a SIGSEGV, because the crash handler aborts after it
# finishes dumping. Trust the "Program crashed with signal N" line, not systemd.
dump_world_logs() {
	echo
	echo "==> arkenelle-world journal (last 200 lines, backtrace addresses stripped)"
	journalctl -u arkenelle-world -n 200 --no-pager | grep -vE 'main\+|libc\.so' || true
	echo
	echo "==> arkenelle-world unit status"
	systemctl --no-pager --lines=0 status arkenelle-world || true
	echo "    NRestarts=$(world_restart_count)"
}
trap 'rc=$?; if [[ $rc -ne 0 ]]; then dump_world_logs; fi' EXIT

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

# How many times systemd has had to restart the world. A climbing number during
# the wait below is the signature of a startup crash loop rather than a slow boot.
world_restart_count() {
	systemctl show arkenelle-world -p NRestarts --value 2>/dev/null || echo "?"
}

# Godot's world peer only speaks WebSocket. A plain HTTP GET through Caddy always
# surfaces as 502 even when the world is healthy — probe the upgrade handshake.
#
# Deadline-based, not iteration-based. The old loop ran `seq 1 $seconds` with a
# 2s curl timeout inside it, so "45" meant anywhere from 45s to 135s depending on
# whether the port was refusing (instant) or accepting-then-hanging (2s). During a
# crash loop it is both, alternating, which made the real budget unknowable.
wait_world_ws() {
	local seconds="${1:-30}"
	local deadline=$(( SECONDS + seconds ))
	local started=$SECONDS
	local last_note=$SECONDS
	local code=""
	echo "==> Waiting for world WebSocket handshake on 127.0.0.1:8087 (up to ${seconds}s)"
	while (( SECONDS < deadline )); do
		code="$(curl --http1.1 -sS -o /dev/null -w '%{http_code}' --max-time 2 \
			-H 'Connection: Upgrade' \
			-H 'Upgrade: websocket' \
			-H 'Sec-WebSocket-Version: 13' \
			-H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
			"http://127.0.0.1:8087/" 2>/dev/null || true)"
		if [[ "$code" == "101" ]]; then
			echo "    world WebSocket OK (101, $(( SECONDS - started ))s, restarts=$(world_restart_count))"
			return 0
		fi
		# Progress every 30s so a long wait is not silent in the Actions log.
		if (( SECONDS - last_note >= 30 )); then
			last_note=$SECONDS
			echo "    still waiting ($(( SECONDS - started ))s, last=${code:-none}, restarts=$(world_restart_count))"
		fi
		sleep 1
	done
	echo "    ERROR: world WebSocket did not return 101 within ${seconds}s (last=${code:-none})" >&2
	return 1
}

wait_port 8080 "master dashboard" 60 || true
wait_port 8088 "gateway" 90
if ! wait_port 8087 "world" 90; then
	echo "==> World port still closed — restarting arkenelle-world once and retrying"
	systemctl restart arkenelle-world
	wait_port 8087 "world" 90
fi
# The world can segfault while loading its startup maps and then boot cleanly on
# a later attempt. On 2026-09-09 that took 47 crash-restarts over ~8 minutes — on
# a tree byte-identical to a deploy that had passed an hour earlier. The old 45s
# budget gave up ~6 minutes early, so a healthy merge reported a failed deploy.
# That invited a revert, and the revert pushed to main, which restarted the world
# and began the crash loop again: three red deploys in a row, none of them the
# code's fault. Wait long enough to tell a slow start from a dead one.
#
# No manual restart in here on purpose. The unit is Restart=always / RestartSec=3,
# so systemd is ALREADY retrying every three seconds; a `systemctl restart` on top
# only kills whichever boot attempt happens to be in flight, which can turn the
# one attempt that would have survived into another failure.
if ! wait_world_ws 480; then
	echo "==> World never completed a WebSocket handshake — journal dump follows" >&2
	exit 1
fi

echo "==> Status"
systemctl --no-pager --lines=0 status arkenelle-master arkenelle-gateway arkenelle-world || true

echo
echo "Deploy OK @ $(date -u +%Y-%m-%dT%H:%M:%SZ)"
sudo -u "$APP_USER" git -C "$APP_DIR" rev-parse --short HEAD
