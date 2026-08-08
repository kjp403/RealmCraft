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
2. Merge to `main` (VPS deploys matching server version)
3. GitHub → **Actions** → **Release clients to itch.io** → **Run workflow**  
   (or `git tag vX.Y.Z && git push origin vX.Y.Z`)
4. Wait for green — butler pushes a **portable folder** (`Arkenelle.exe` + `Arkenelle.pck`) with `--userversion`
5. Players: itch app → Library → Arkenelle → **Update** (stays in the app)

---

## If Update still opens a browser

That Library entry was created from a **browser Download** (or a hand Upload), not an itch **Install**. The itch app cannot patch those — it can only open Download again. Fix **once**:

1. Confirm you deleted every **manual Upload** on https://kjp403.itch.io/arkenelle/edit (step 3)
2. itch app → Library → Arkenelle → ⋯ → **Uninstall** / **Forget**
3. Still in the itch app, open https://kjp403.itch.io/arkenelle
4. Click **Install** (green / “Install with the itch.io app”) — **not** Download
5. Later: Library → Arkenelle → **Update** patches in-app and relaunches

In-game **Update** uses `itch://install/?game_id=…` so it opens the itch app’s Install/Update flow and does **not** open the browser Download page.

Also confirm the latest CI push shows channel `windows` with your version (e.g. `0.28.18`) via `butler status kjp403/arkenelle`.

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
