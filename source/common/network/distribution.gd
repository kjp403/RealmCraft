class_name Distribution
## Canonical public download / auto-update targets. Keep the itch slug in ONE place
## so the outdated-client dialog, web notice, and CI butler push stay aligned.
##
## Official Windows install is the self-hosted zip (CLIENT_DOWNLOAD_URL). The
## exported client checks CLIENT_MANIFEST_URL on boot and replaces itself.
## itch.io remains a backup channel for players who already installed via the app.


const ITCH_USER: String = "kjp403"
const ITCH_GAME: String = "arkenelle"
## Numeric game id from the itch edit page (used by the itch:// deep link).
const ITCH_GAME_ID: int = 4874380
## Butler push target (`user/game`). Must match the itch project URL slug.
const ITCH_PUSH_TARGET: String = ITCH_USER + "/" + ITCH_GAME
## Public game page (optional backup / marketing — not the official updater).
const ITCH_URL: String = "https://kjp403.itch.io/arkenelle"
## Opens the game page inside the itch.io desktop app. Backup channel only.
const ITCH_APP_URL: String = "itch://games/%d" % ITCH_GAME_ID
## Legacy install-queue deep link. Kept for docs.
const ITCH_INSTALL_URL: String = "itch://install/?game_id=%d" % ITCH_GAME_ID
## Marketing site (community links, landing page — not the auto-updater).
const WEBSITE_URL: String = "https://arkenelle.com"
## Public in-browser client (Godot web export on the VPS).
const PLAY_WEB_URL: String = "https://play.arkenelle.com/"
## Portable Windows zip (exe + pck). Auto-update reads CLIENT_MANIFEST_URL.
const CLIENT_DOWNLOAD_URL: String = "https://play.arkenelle.com/desktop/Arkenelle-windows.zip"
const CLIENT_MANIFEST_URL: String = "https://play.arkenelle.com/desktop/latest.json"
## Public Discord invite (settings, gateway More menu, help, feedback replies).
const DISCORD_URL: String = "https://discord.gg/kSs3hxByV"
