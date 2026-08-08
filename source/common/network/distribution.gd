class_name Distribution
## Canonical public download / auto-update targets. Keep the itch slug in ONE place
## so the outdated-client dialog, web notice, and CI butler push stay aligned.
##
## Players should install via the itch.io app once; later tagged releases push
## portable folder builds with butler and the app updates them automatically.


const ITCH_USER: String = "kjp403"
const ITCH_GAME: String = "arkenelle"
## Numeric game id from the itch edit page (used by the itch:// deep link).
const ITCH_GAME_ID: int = 4874380
## Butler push target (`user/game`). Must match the itch project URL slug.
const ITCH_PUSH_TARGET: String = ITCH_USER + "/" + ITCH_GAME
## Public game page (browser fallback / marketing — NOT the updater).
const ITCH_URL: String = "https://kjp403.itch.io/arkenelle"
## Opens the game page inside the itch.io desktop app.
const ITCH_APP_URL: String = "itch://games/%d" % ITCH_GAME_ID
## Queues Install/Update inside the itch.io desktop app (preferred Update button).
## Must NOT fall back to [constant ITCH_URL] automatically — that opens browser Download.
const ITCH_INSTALL_URL: String = "itch://install/?game_id=%d" % ITCH_GAME_ID
## Marketing site (community links, landing page — not the auto-updater).
const WEBSITE_URL: String = "https://arkenelle.com"
