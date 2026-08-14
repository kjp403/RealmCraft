#!/usr/bin/env bash
# One-time-ish Arkenelle VPS setup. Idempotent: safe to re-run.
# Run it ON THE VPS as root (or with sudo), from inside the project folder:
#   cd /opt/arkenelle && sudo bash deploy/setup-vps.sh
#
# It installs the headless Godot engine + Caddy, opens the firewall (80/443 only),
# imports the project, and installs + starts the three game services.

set -euo pipefail

GODOT_VERSION="4.7.1-stable"
GODOT_DL="Godot_v${GODOT_VERSION}_linux.x86_64"
APP_DIR="/opt/arkenelle"
APP_USER="arkenelle"

echo "==> 1/7 Installing base packages (curl, unzip, ufw)"
apt-get update -y
apt-get install -y curl unzip ufw ca-certificates

echo "==> 2/7 Installing headless Godot ${GODOT_VERSION}"
if ! (command -v godot >/dev/null 2>&1 && godot --headless --version 2>/dev/null | grep -q "4.7.1.stable"); then
	tmp="$(mktemp -d)"
	curl -fL --retry 4 -o "$tmp/godot.zip" \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${GODOT_DL}.zip"
	unzip -o "$tmp/godot.zip" -d "$tmp" >/dev/null
	install -m 0755 "$tmp/${GODOT_DL}" /usr/local/bin/godot
	rm -rf "$tmp"
fi
godot --headless --version

echo "==> 3/7 Installing Caddy (reverse proxy + auto HTTPS)"
if ! command -v caddy >/dev/null 2>&1; then
	apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
	curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
		| gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
	curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
		> /etc/apt/sources.list.d/caddy-stable.list
	apt-get update -y
	apt-get install -y caddy
fi

echo "==> 4/7 Creating service user + fixing ownership"
id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
chown -R "$APP_USER":"$APP_USER" "$APP_DIR"

echo "==> 5/7 Firewall: allow SSH + 80/443, deny everything else inbound"
ufw allow OpenSSH || ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
ufw status verbose

echo "==> 6/7 Importing project assets (as $APP_USER, one time)"
sudo -u "$APP_USER" godot --headless --path "$APP_DIR" --import || \
	sudo -u "$APP_USER" godot --headless --path "$APP_DIR" --import || true

echo "==> 7/7 Installing Caddy config + systemd services"
mkdir -p /opt/arkenelle/client-web /opt/arkenelle/client-windows
chmod a+rX /opt/arkenelle/client-web /opt/arkenelle/client-windows
if [[ ! -f /opt/arkenelle/client-web/index.html ]]; then
	install -m 0644 "$APP_DIR/deploy/client-web-placeholder/index.html" /opt/arkenelle/client-web/index.html
	chown "$APP_USER":"$APP_USER" /opt/arkenelle/client-web/index.html
fi
install -m 0644 "$APP_DIR/deploy/Caddyfile" /etc/caddy/Caddyfile
install -m 0644 "$APP_DIR"/deploy/systemd/arkenelle-*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now arkenelle-master.service
systemctl enable --now arkenelle-gateway.service
systemctl enable --now arkenelle-world.service
systemctl restart caddy

echo
echo "Done. Check status with:"
echo "  systemctl status arkenelle-master arkenelle-gateway arkenelle-world caddy --no-pager"
