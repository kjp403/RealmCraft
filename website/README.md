# Arkenelle website

Static landing page + wiki generated from Godot `.tres` files.

```powershell
node website/build.mjs
```

Output is `website/dist/`. Open `website/dist/index.html` locally, or serve that folder.

## Cloudflare Pages (live site)

The domain is already on Cloudflare. After this folder is on GitHub `main`:

1. Cloudflare dashboard → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**
2. Select the **RealmCraft** repo
3. Settings:
   - **Framework preset:** None
   - **Build command:** `node website/build.mjs`
   - **Build output directory:** `website/dist`
   - **Root directory:** leave empty (the script reads `source/` and `assets/` from the repo root)
4. Deploy. You will get a `*.pages.dev` URL first.
5. **Custom domains** → add `arkenelle.com` and `www.arkenelle.com`

Cloudflare will replace the old OVH placeholder A records for the apex and `www`. Leave `api` and `play` as **DNS only** (grey cloud) pointing at `144.217.91.100`.

Rebuilds happen on every push to `main` that Cloudflare Pages is watching.
