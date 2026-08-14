# Release Windows/Linux/Web clients (itch.io auto-update)

Players should install **once** with the [itch.io app](https://itch.io/app). After that, each Release workflow push updates them **inside the app** — no browser re-download.

Server-only hotfixes still go through **Deploy VPS** on `main` and do **not** need a client release (and should **not** bump `application/config/version`).

---

## One-time setup (you)

### 1. Create the itch.io game page

1. Open https://itch.io/game/new while logged in as **kjp403**
2. **Title:** `Arkenelle`
3. **Project URL:** `arkenelle` → **https://kjp403.itch.io/arkenelle**
4. Classification: **Games** · Kind: **Downloadable**
5. Visibility: **Public**
6. Save

### 2. Add the butler API key to GitHub

1. Create a key: https://itch.io/user/settings/api-keys
2. Repo → **Settings** → **Secrets and variables** → **Actions**
3. Secret name: `BUTLER_API_KEY`

### 3. Clean the itch Uploads page (important)

Manual “Upload files” on the itch edit page fights the butler channel and makes
**Update** open a browser Download instead of patching in the app.

1. Open https://kjp403.itch.io/arkenelle/edit
2. Go to **Uploads** / **Builds**
3. **Delete** any hand-uploaded `Arkenelle.exe` / zip that you added in the browser
4. Leave only the butler channel builds (after CI runs you’ll see channel `windows`)

### 4. Tell testers how to install (exact words)

> 1. Install the [itch.io app](https://itch.io/app)  
> 2. Open https://kjp403.itch.io/arkenelle **inside the itch app**  
> 3. Click **Install** (green / “Install with the itch.io app”)  
> 4. Do **not** use the red **Download** button in a normal browser  
> 5. Always launch from itch **Library**

---

## How to ship a client update

1. Bump `application/config/version` in `project.godot` when the client must change
2. Merge to `main` (VPS deploys; a `config/version` bump also auto-runs **Release clients** for Windows + Web)
3. Or manually: GitHub → **Actions** → **Release clients to itch.io** → **Run workflow** → `platforms: web` to publish only the browser client to `https://play.arkenelle.com/`
   (or `git tag vX.Y.Z && git push origin vX.Y.Z`)
4. Wait for green — butler pushes a **portable folder** (`Arkenelle.exe` + `Arkenelle.pck`) with `--userversion`
5. Players: itch app → Library → Arkenelle → **Update** (stays in the app)

---

## If Install shows “No compatible downloads were found”

The itch app only lists uploads tagged for your OS. On https://kjp403.itch.io/arkenelle/edit → **Uploads**, open the butler `windows` row and confirm the **Windows** checkbox is on (public page should show the Windows icon next to `arkenelle-windows.zip`).

Then recover the Library entry:

1. Fully quit the itch app (tray icon → Quit), then reopen it
2. Library → Arkenelle → ⋯ → **Uninstall** / **Forget** (if present)
3. Still **inside the itch app**, open https://kjp403.itch.io/arkenelle
4. Click **Install** — pick **windows** / `arkenelle-windows.zip` if the dropdown offers it
5. Install under a stable path (e.g. `AppData\Roaming\itch\apps` or `Games\Arkenelle`) — **not** Desktop / OneDrive
6. Always launch from itch **Library**

If the Install dropdown stays empty after that, use browser **Download** once to play, then fix tags/re-push with **Release clients to itch.io**. Moving the itch install folder by hand breaks Update until you Uninstall + Install again.

In-game **Update** opens `itch://games/<id>` (the app game page). After two tries it offers the browser download page so a broken Library entry cannot soft-lock login.

Also confirm the latest CI push shows channel `windows` with your version via `butler status kjp403/arkenelle`.

## Version gate vs itch lag

`application/config/version` is the server build. `application/config/min_client_version` is the oldest itch client still allowed in. When you bump `version` for a server-only merge before Release finishes, leave `min_client_version` on the last published itch userversion so players are not locked out. Bump `min_client_version` only when you intend to force Update.

---

## When NOT to release a client

| Change | Client release? |
|--------|-----------------|
| Pure `source/server/**` logic / DB / config | No — Deploy VPS only |
| `source/client/**`, shared maps/items/UI players must see | Yes — bump version + Release workflow |

The gateway uses an **exact** version match. Bumping the version without publishing a matching itch build locks everyone out until they update.

---

## Slug source of truth

`source/common/network/distribution.gd` and `ITCH_GAME` in `.github/workflows/release.yml` must stay `kjp403/arkenelle`.
