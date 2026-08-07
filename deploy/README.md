# Arkenelle VPS deployment

Deploys the three game servers behind Caddy (auto HTTPS) on one VPS.

- `api.arkenelle.com`  → gateway (login / accounts) on `127.0.0.1:8088`
- `play.arkenelle.com` → world server (gameplay) on `127.0.0.1:8087`
- master + dashboard stay internal on loopback (`8062/8064/8080`)

The game servers bind to `127.0.0.1`, so only Caddy (ports 80/443) is public.

## Prerequisites (already done)
- DNS: `api` and `play` A records → your VPS IP.
- VPS reachable over SSH with your key.

## Deploy (run these on the VPS)

```bash
# 1. Connect (from Windows PowerShell). Replace USER with your VPS user.
ssh USER@144.217.91.100

# 2. Get the project onto the VPS at /opt/arkenelle
sudo mkdir -p /opt/arkenelle
sudo chown "$USER":"$USER" /opt/arkenelle
git clone https://github.com/kjp403/RealmCraft.git /opt/arkenelle   # first time
# (later updates: cd /opt/arkenelle && git pull)

# 3. Run the setup script (installs Godot + Caddy, firewall, services)
cd /opt/arkenelle
sudo bash deploy/setup-vps.sh
```

## Verify

```bash
systemctl status arkenelle-master arkenelle-gateway arkenelle-world caddy --no-pager
# From your PC, these should return HTTPS (a certificate + a response):
curl -I https://api.arkenelle.com
```

Live logs for a service: `journalctl -u arkenelle-world -f`

## Updating later

```bash
cd /opt/arkenelle && git pull
sudo -u arkenelle godot --headless --path /opt/arkenelle --import
sudo systemctl restart arkenelle-master arkenelle-gateway arkenelle-world
```

## Client build

The client already points at `https://api.arkenelle.com` (see
`source/common/network/gateway_api.gd`). Export the Windows client from Godot
and share it once the servers are live.

## Notes
- This runs the servers from source with the headless Godot engine (simplest).
  The `ServerUbuntu` export preset is an alternative if you prefer a packaged
  binary later.
- The self-signed certs in `data/config/tls/` are only used for the internal
  loopback links between master/gateway/world. Public TLS is Caddy's job.
