# Arkenelle VPS deployment

Deploys the three game servers behind Caddy (auto HTTPS) on one VPS.

- `api.arkenelle.com`  → gateway (login / accounts) on `127.0.0.1:8088`
- `play.arkenelle.com` → browser client (`/opt/arkenelle/client-web`), Windows zip (`/opt/arkenelle/client-windows` at `/desktop/`), and world WebSocket on `127.0.0.1:8087`
- master + dashboard stay internal on loopback (`8062/8064/8080`)

The game servers bind to `127.0.0.1`, so only Caddy (ports 80/443) is public.

---

## Auto-deploy (recommended — do this once)

After a **one-time** GitHub secrets setup, merging to `main` updates the live
server automatically. No SSH, no PowerShell paste.

### 1. Add GitHub Actions secrets

Repo page → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

| Secret name | Value |
|-------------|--------|
| `VPS_HOST` | `144.217.91.100` |
| `VPS_USER` | `ubuntu` |
| `VPS_SSH_KEY` | Full contents of your **private** key file (usually `C:\Users\YOU\.ssh\arkenelle_ovh`) |
| `VPS_SSH_PASSPHRASE` | The password you typed when you created that SSH key (if it has none, leave this secret empty / omit it) |

**Important:** use the file **without** `.pub` on the end.  
Private key text starts with `-----BEGIN OPENSSH PRIVATE KEY-----` (or `BEGIN RSA PRIVATE KEY`).  
A `.pub` file starts with `ssh-ed25519` / `ssh-rsa` — that will **fail**.

Copy on Windows PowerShell (keeps line breaks):

```powershell
Get-Content $env:USERPROFILE\.ssh\arkenelle_ovh -Raw | Set-Clipboard
```

Then edit the `VPS_SSH_KEY` secret → paste → save.  
If your key asks for a password when you SSH, also add `VPS_SSH_PASSPHRASE` with that same password.

### 2. Merge the auto-deploy PR / push to `main`

That installs `.github/workflows/deploy-vps.yml` and `deploy/update.sh`.

### 3. From then on

| What you want | What you do |
|---------------|-------------|
| Put content live | Merge (or push) to `main` → wait for the green **Deploy VPS** check |
| Redeploy without code changes | GitHub → **Actions** → **Deploy VPS** → **Run workflow** |
| Update Godot project on your PC | Double-click `deploy/Sync-Game-From-GitHub.ps1` (or run it in PowerShell) |

Watch deploys: GitHub → **Actions** → **Deploy VPS**.

---

## Browser client (play.arkenelle.com)

The Godot **Web** export is the in-browser game. Caddy serves it on GET
`https://play.arkenelle.com/` and still forwards WebSocket upgrades to the world.

It does **not** ship on Deploy VPS. After merging the Caddy change, run
**Release clients to itch.io** with `platforms: web` (or `all`). That workflow
exports Web, butler-pushes the itch `web` channel, and unpacks the files to
`/opt/arkenelle/client-web` on the VPS.

Keep `play` **DNS only** (grey cloud) in Cloudflare. Orange-clouding it breaks
WebSockets.

First browser load is the full client (wasm + pck, similar size to the Windows
zip). Desktop Chrome or Firefox. The web build is the lite client (no weather).

---

## Client auto-updates (self-hosted Windows)

Server deploys do **not** update player EXEs. Windows clients check
`https://play.arkenelle.com/desktop/latest.json` on launch and download
`Arkenelle-windows.zip` when the version is newer.

→ **[release-clients.md](./release-clients.md)** (VPS zip + optional itch butler)

Players download the zip once from the site (or `/desktop/Arkenelle-windows.zip`),
extract, and run `Arkenelle.exe`. itch.io remains an optional backup if
`BUTLER_API_KEY` is set.

---

## Prerequisites (already done)
- DNS: `api` and `play` A records → your VPS IP.
- VPS reachable over SSH with your key.

## First-time VPS install (already done for Arkenelle)

```bash
# 1. Connect (from Windows PowerShell).
ssh -i $env:USERPROFILE\.ssh\arkenelle_ovh ubuntu@144.217.91.100

# 2. Get the project onto the VPS at /opt/arkenelle
sudo mkdir -p /opt/arkenelle
sudo chown "$USER":"$USER" /opt/arkenelle
git clone https://github.com/kjp403/RealmCraft.git /opt/arkenelle   # first time

# 3. Run the setup script (installs Godot + Caddy, firewall, services)
cd /opt/arkenelle
sudo bash deploy/setup-vps.sh
```

## Verify

```bash
systemctl status arkenelle-master arkenelle-gateway arkenelle-world caddy --no-pager
# Gateway (any non-empty JSON response means Caddy → :8088 is fine):
curl -sS https://api.arkenelle.com/ | head
# World is WebSocket-only on Upgrade. GET `/` serves the browser client (or a
# placeholder until the first Web export is published).
# Expect 101 from an HTTP/1.1 upgrade probe:
curl --http1.1 -sS -o /dev/null -w '%{http_code}\n' \
  -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
  -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
  https://play.arkenelle.com/
# Expect HTML from a plain GET after Caddy is updated:
curl -sS -o /dev/null -w '%{http_code}\n' https://play.arkenelle.com/
```

Live logs: `journalctl -u arkenelle-world -f`

## Manual update (only if auto-deploy is not set up)

On the VPS:

```bash
sudo bash /opt/arkenelle/deploy/update.sh
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
- Auto-deploy uses fast-forward only. If someone edits files directly on the VPS,
  the Action will fail until those edits are discarded or committed.
