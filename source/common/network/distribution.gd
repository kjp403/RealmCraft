class_name Distribution
## Canonical public download / auto-update targets. Keep the itch slug in ONE place
## so the outdated-client dialog, web notice, and CI butler push stay aligned.
##
## Players should install via the itch.io app once; later tagged releases push
## new builds with butler and the app updates them automatically.


const ITCH_USER: String = "kjp403"
const ITCH_GAME: String = "arkenelle"
## Butler push target (`user/game`). Must match the itch project URL slug.
const ITCH_PUSH_TARGET: String = ITCH_USER + "/" + ITCH_GAME
## Public game page (Install with itch.app / browser download).
const ITCH_URL: String = "https://kjp403.itch.io/arkenelle"
## Marketing site (community links, landing page — not the auto-updater).
const WEBSITE_URL: String = "https://arkenelle.com"
