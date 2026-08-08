# Release Windows/Linux/Web clients (itch.io auto-update)

Players should install **once** with the [itch.io app](https://itch.io/app). After that, tagging a release here pushes a new build and the app updates them — no manual re-download for every change.

Server-only hotfixes still go through **Deploy VPS** on `main` and do **not** need a client release (and should **not** bump `application/config/version`).

---

## One-time setup (you)

### 1. Create the itch.io game page

1. Open https://itch.io/game/new while logged in as **kjp403**
2. **Title:** `Arkenelle`
3. **Project URL:** `arkenelle`  
   Final page must be: **https://kjp403.itch.io/arkenelle**
4. Classification: **Games** · Kind: **Downloadable** (you can also enable HTML later for web)
5. Visibility can start as **Draft** until the first butler push lands
6. Save

### 2. Add the butler API key to GitHub

1. Create a key: https://itch.io/user/settings/api-keys  
   (label it e.g. `arkenelle-github-actions`)
2. Repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**
3. Name: `BUTLER_API_KEY`  
   Value: paste the key

### 3. Tell testers how to install

> Install the [itch.io app](https://itch.io/app), open https://kjp403.itch.io/arkenelle, click **Install**.  
> Later updates appear in the itch app — you don’t need a new zip each time.

---

## How to ship a client update

Only when players need new **client** content (UI, maps they load locally, icons, click/menu fixes, etc.):

1. Bump `application/config/version` in `project.godot` (e.g. `0.28.0` → `0.28.1`)
2. Merge that to `main` (VPS deploys the matching server version)
3. Tag and push:

```bash
git checkout main
git pull origin main
git tag v0.28.1
git push origin v0.28.1
```

4. Watch **Actions → Release clients to itch.io** until green
5. Confirm https://kjp403.itch.io/arkenelle shows the new Windows build  
6. itch.app users get the update automatically; outdated EXEs are blocked at login and pointed at the itch page

Manual run (no tag): **Actions → Release clients to itch.io → Run workflow**.

---

## When NOT to release a client

| Change | Client release? |
|--------|-----------------|
| Pure `source/server/**` logic / DB / config | No — Deploy VPS only; leave version alone |
| `source/client/**`, shared maps/items/shops players must see, UI | Yes — bump version + tag |

The gateway uses an **exact** version match (`source/server/gateway/http_server.gd`). Bumping the version without publishing a matching itch build will lock everyone out until they update.

---

## Slug source of truth

`source/common/network/distribution.gd` and `ITCH_GAME` in `.github/workflows/release.yml` must stay `kjp403/arkenelle`.
