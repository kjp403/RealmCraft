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

## Traveling Peddler web export (one-time secret setup)

The world server POSTs the Peddler's live state to the gateway, which caches it
for `arkenelle.com/peddler/`. Both services read ONE file for the shared secret,
so the two halves can never drift apart.

The file lives at `/etc/arkenelle/peddler.env` — **not** in `/opt/arkenelle`.
That is the git checkout: `update.sh` reinstalls over it, and a secret in a
working tree is one `git add -A` from being public forever.

```bash
# 1. Connect
ssh -i $env:USERPROFILE\.ssh\arkenelle_ovh ubuntu@144.217.91.100

# 2. Generate a key. Copy the output — it is not stored anywhere yet.
openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48; echo

# 3. Install the template, readable only by root and the service user
sudo install -d -m 0750 -o root -g arkenelle /etc/arkenelle
sudo install -m 0640 -o root -g arkenelle      /opt/arkenelle/deploy/config/peddler.env.example /etc/arkenelle/peddler.env

# 4. Paste the key in, replacing REPLACE_ME_WITH_A_GENERATED_KEY
sudo nano /etc/arkenelle/peddler.env

# 5. Pick up the new EnvironmentFile= lines and restart the two services.
#    daemon-reload is REQUIRED: without it systemd keeps the old unit in memory
#    and the restart silently starts with no environment at all.
sudo systemctl daemon-reload
sudo systemctl restart arkenelle-gateway arkenelle-world

# 6. Confirm both processes actually have the variables
sudo systemctl show arkenelle-world   -p Environment
sudo systemctl show arkenelle-gateway -p Environment
```

A normal deploy needs none of this again: `update.sh` reinstalls the unit files
and `daemon-reload`s, and `/etc/arkenelle/` is outside everything it touches.

**Verify end to end** — the write path is loopback-only, so this must be run ON
the VPS. The public read is what the website polls.

```bash
# On the VPS: rejected without the bearer (fail-closed proof)
curl -s -X POST http://127.0.0.1:8088/v1/peddler/update -d '{}'
# -> {"ok":false,"error":"unauthorized"}

# From anywhere: the public read. "unavailable" until the world posts —
# it does that on the next spawn, despawn, or UTC stock roll.
curl -s https://api.arkenelle.com/v1/peddler

# From anywhere: the write endpoint must NOT be reachable publicly (404 from Caddy)
curl -s -o /dev/null -w '%{http_code}
' -X POST https://api.arkenelle.com/v1/peddler/update
# -> 404
```

If the tracker stays empty, check the world's log for the export line:

```bash
sudo journalctl -u arkenelle-world -n 100 --no-pager | grep -i peddler
```

No line at all means the variables are not reaching the process (step 5), not
that the POST failed — the exporter is silent by design when unconfigured.

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
