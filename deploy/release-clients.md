# Release Windows / Web clients (self-hosted auto-update)

Official Windows install: download **https://play.arkenelle.com/desktop/Arkenelle-windows.zip**, extract, run `Arkenelle.exe`. Each launch checks `latest.json` and replaces itself when a newer build is up.

itch.io remains a **backup** channel (butler push still runs when `BUTLER_API_KEY` is set). Existing itch-app installs keep updating there.

Server-only hotfixes still go through **Deploy VPS** on `main` and do **not** need a client release (and should **not** bump `application/config/version`).

---

## How to ship a client update

1. Bump `application/config/version` in `project.godot` when the client must change
2. Merge to `main` (VPS deploys; a `config/version` bump also auto-runs **Release clients** for Windows + Web)
3. Or manually: GitHub → **Actions** → **Release clients to itch.io** → **Run workflow** → `platforms: windows` (desktop zip) or `web` (browser client) or `all`
4. Wait for green — the VPS gets `Arkenelle-windows.zip` + `latest.json` at `/opt/arkenelle/client-windows/` (`https://play.arkenelle.com/desktop/`)
5. Players who already have the zip install just relaunch `Arkenelle.exe`

Local debug: `--skip-update` skips the boot check. `--update-manifest=https://…/latest.json` points at a fixture.

---

## itch.io backup (optional)

If `BUTLER_API_KEY` is set, the same workflow still butler-pushes portable folders so itch Library can patch. Players who already installed via the [itch.io app](https://itch.io/app) do not need to switch.

To keep that channel healthy: do not add manual Uploads on the itch edit page (they fight the butler channel).

---

## Version gate vs publish lag

`application/config/version` is the server build. `application/config/min_client_version` is the oldest client still allowed in. When you bump `version` for a server-only merge before Release finishes, leave `min_client_version` on the last published userversion so players are not locked out. Bump `min_client_version` only when you intend to force Update.

The in-game **Update** button downloads the self-hosted zip. After two failed applies it opens the zip URL in the browser.

---

## When NOT to release a client

| Change | Client release? |
|--------|-----------------|
| Pure `source/server/**` logic / DB / config | No — Deploy VPS only |
| `source/client/**`, shared maps/items/UI players must see | Yes — bump version + Release workflow |

Bumping the version without publishing a matching Windows zip (and web export) locks everyone out until they update.

---

## Slug source of truth

`source/common/network/distribution.gd` holds `CLIENT_DOWNLOAD_URL` / `CLIENT_MANIFEST_URL`. itch `ITCH_GAME` in `.github/workflows/release.yml` must stay `kjp403/arkenelle` while the backup channel exists.
