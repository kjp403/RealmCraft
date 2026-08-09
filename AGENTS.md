# AGENTS.md

## Cursor Cloud specific instructions

### Local stack
- Start/refresh servers with `.cursor/run-server.sh` (master → gateway waits on `8064` → world waits on `8062`). Dev binds are loopback: gateway `8088`, world `8087`.
- Client: `godot --path . --mode=client` against `data/config/client_config.cfg` (`127.0.0.1:8088`).
- Do **not** edit `project.godot` `config/version` to “match” a running server. Restart the local servers instead so they pick up the repo version.

### Hollow / Mecha Golem verification (required before merge asks)
Before asking Kyle to merge Hollow/golem changes, run these gates and keep artifacts:

1. Headless: `godot --headless --path . -s tools/verify_hollow_golem.gd` → must print `VERIFY_PASS` (container `node_paths`, baked sync id `0` → `MechaGolem`, GIF anims present, `bad_black_tiles=0`).
2. Visual: `godot --path . -s tools/render_hollow_preview.gd` → `/opt/cursor/artifacts/screenshots/hollow-golem-preview.png` must show the golem on the lit pad.
3. In-game (local): enter Hub → **The Hollow** portal → confirm golem on the center pad. Prefer a levelled/admin test char (`/setlevel`, `/heal`); do not use JailRoom.
4. Live check: `curl -sS -o /dev/null -w '%{http_code}\n' https://play.arkenelle.com/` — WebSocket upstream should not be `502`. If live is down, say so explicitly; do not claim live verification.

Working boss maps (e.g. Fungus Cave) bake `node_paths=PackedStringArray("replicated_props_container")` on the map root **and** `node_paths` for `id_to_node`/`node_to_id` on `ReplicatedPropsContainer`. Hollow must match that pattern; `Map._ready` also resolves a missing container by child name as a safety net.

### Live deploy
- Merges to `main` run **Deploy VPS**. This environment cannot `workflow_dispatch` that action (403) and has no VPS SSH key — ask Kyle to redeploy/check `arkenelle-world` if `play.arkenelle.com` is 502.
- Standard deploy/update flow: `deploy/README.md`, `deploy/update.sh`.
