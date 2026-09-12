# Handoff — Ark Coins: verification, refunds, and cosmetic preview

Delete this file when the branch merges. It exists so a second Claude session
(or a second account) can pick this up cold.

**Branch:** `claude/ark-coins-verification-refund-b0b329`
**PR:** https://github.com/kjp403/RealmCraft/pull/472
**Worktree it was built in:** `.claude/worktrees/sleepy-gauss-f7fa7d`

## What started this

A buyer paid $9.99 for 1000 Ark Coins and typed their **character** name
(sMiguel) into the storefront. Their **account** is Tomatoface. The Stripe
webhook refuses to credit an account that does not exist, so the money landed
in the gateway log and there was no in-game way to put the coins right.

## Done and verified (commits `e10f93d1`, `ea9ffb26`)

1. **The storefront checks the name before checkout.** New PUBLIC
   `POST /v1/account/check` on the gateway answers `account`, `character` or
   nothing. Buy buttons stay dead until it is one of the first two — including
   when the API cannot be reached at all. The old "type it twice" field is gone;
   it could not catch someone typing the same wrong name twice.
2. **Character names credit correctly.** Accounts live in the master's database,
   characters in the world's, so the webhook now falls back to a master → world
   RPC (`resolve_character`) when a credit is refused as `unknown_account`, and
   retries with the SAME Stripe event id so idempotency holds. Account names win
   first.
3. **`/arkcoins <self|Name|#id|@account> [amount] [reason]`** — senior_admin.
   Credits an account from in game through a new server-to-server
   `/v1/premium/grant`. A character name resolves to its owning account via
   `CommandTarget`, online or not. No amount = read the balance.
4. **Loud storefront copy** — a callout that leads with "Use your LOGIN name",
   says it is not always the character name, and says a character name works too.

Files: `source/server/gateway/http_server.gd`,
`source/server/master/components/master_gateway_server/master_gateway_server.gd`,
`source/server/master/components/master_world_server/master_world_server.gd`,
`source/server/world/components/world_manager_client.gd`,
`source/server/world/premium/premium_api.gd`,
`source/server/world/components/chat_command/global_commands/arkcoins_command.gd`,
`deploy/Caddyfile`, `website/build.mjs`, `website/src/store.js`,
`website/src/styles.css`, `tools/verify_premium_live.gd`,
`tools/verify_stripe_webhook.gd`.

## Still to do

Nothing known. The cosmetic preview below was the last item; re-read the PR
before assuming otherwise.

### Done: preview a cosmetic on your own character (commit after `10408789`)

The Cosmetics tab drew the effect in an empty box. It now draws the buyer's own
body under it — their skin and their prestige dye, read off
`ClientState.local_player` — and their worn title over it, so one box shows the
whole look. The body sits at the character scene's own `offset = Vector2(0, -30)`
so its feet land where every preset is anchored; it plays `run` while a trail
preset walks the circle, `idle` otherwise.

The other two tabs were already adequate and were not touched: Skins previews
the body and dye it sells, Titles previews the title it sells. If Kyle wants the
worn aura shown behind the Skins preview too, that is the obvious follow-up.

Screenshot it with:

```
<godot> --path . --mode=client res://tools/render_vault_previews.tscn
```

which writes `previews/vault_{titles,skins,cosmetics}.png`. It needs no server —
it injects the state a live one would send, and `_fake_wearer()` stands in for
the local player. **It prints exactly one `is_server` script error by design**;
see the comment on that function before trying to "fix" it.

## How to run and verify locally (Windows)

Godot is **not on PATH**: `C:\Users\kjpee\Godot\Godot_v4.7.1-stable_win64_console.exe`.
A fresh worktree needs a seeded `.godot` cache or the first headless run
reimports for ~25 minutes — this worktree already has one.

Start the three servers, each in its own background process, in this order
(master, wait ~15s, gateway, wait ~15s, world):

```
ARKENELLE_PREMIUM_API_KEY=localtestkey \
ARKENELLE_STRIPE_WEBHOOK_SECRET=whsec_localtest \
  <godot> --headless --path . --mode=master-server     # then gateway-server, then world-server
```

The world server also wants `ARKENELLE_PREMIUM_API_URL=http://127.0.0.1:8088`.
Local DBs are written under `source/server/master/data/` and are gitignored.

Test fixtures used (recreate with the calls below if the DBs are wiped):

```
curl -s -X POST http://127.0.0.1:8088/v1/account/create -H "Content-Type: application/json" \
  -d '{"a-u":"tomatoface","a-p":"testpass1"}'
curl -s -X POST http://127.0.0.1:8088/v1/login -H "Content-Type: application/json" \
  -d '{"a-u":"tomatoface","a-p":"testpass1","c-v":"<project version>"}'   # returns session_id + world id
curl -s -X POST http://127.0.0.1:8088/v1/world/character/create -H "Content-Type: application/json" \
  -d '{"t-id":"<session_id>","a-u":"tomatoface","w-id":<world id>,"data":{"name":"sMiguel","skin":1}}'
```

Then:

```
ARKENELLE_PREMIUM_API_URL=http://127.0.0.1:8088 ARKENELLE_PREMIUM_API_KEY=localtestkey \
ARKENELLE_VERIFY_ACCOUNT=tomatoface <godot> --headless --path . -s res://tools/verify_premium_live.gd

ARKENELLE_STRIPE_WEBHOOK_SECRET=whsec_localtest ARKENELLE_VERIFY_CHARACTER=smiguel \
ARKENELLE_VERIFY_CHARACTER_ACCOUNT=tomatoface <godot> --headless --path . -s res://tools/verify_stripe_webhook.gd
```

Both printed PASS on 2026-09-12. For the website: `node website/build.mjs`, serve
`website/dist` on 127.0.0.1 (the store points at `127.0.0.1:8088` on localhost
and at `api.arkenelle.com` everywhere else).

## Traps this work already hit

- `--check-only --script` on any file that transitively touches `Client` /
  `ClientState` fails with autoload errors that are NOT your bug. Boot the world
  server instead and read its log for `SCRIPT ERROR`.
- A new `class_name` is invisible until an `--import` pass refreshes
  `.godot/global_script_class_cache.cfg`.
- `deploy/Caddyfile` changed. `/v1/premium/grant` must be blocked (it mints
  currency); `/v1/account/check` must stay public or the storefront silently
  goes back to accepting any name.

## After merge

Merging to main restarts the live world and drops every player — Kyle merges
after midnight. Once it is live, the payment that started this is settled with:

```
/arkcoins sMiguel 1000 stripe typo refund
```
