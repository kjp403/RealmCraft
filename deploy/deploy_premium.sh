#!/usr/bin/env bash
# One-shot setup for the Ark Coin premium currency system on the VPS.
#
#   sudo bash /opt/arkenelle/deploy/deploy_premium.sh
#
# Or, without a terminal, from the "Premium secrets" GitHub Actions workflow,
# which runs this same script with --from-env and feeds it repository secrets.
# Same script on purpose: two ways to ship with different behaviour is how a box
# ends up configured in a way nobody can reproduce.
#
# WHAT THIS IS FOR. Everything else about premium currency deploys itself:
# update.sh already installs the Caddyfile and the systemd units on every push to
# main. The only things it cannot do are the ones that need a SECRET, because a
# secret must never be in the repo. This script collects those interactively,
# writes them where systemd can read them, and restarts what needs restarting.
#
# SAFE TO RE-RUN. Every step checks before it acts: an existing value is offered
# back rather than clobbered, and pressing Enter keeps what is already there.
# Nothing here touches premium.db.
#
# WHAT IT DELIBERATELY DOES NOT DO:
#   - It does not merge or deploy code. That is `git push` + the Deploy VPS
#     workflow, and doing it here would mean two ways to ship with different
#     behaviour.
#   - It does not restart the WORLD unless you ask. Restarting the world drops
#     every player online, and setting a Stripe key is not worth that on its own.

set -euo pipefail

APP_DIR="${APP_DIR:-/opt/arkenelle}"
ENV_DIR="/etc/arkenelle"
ENV_FILE="$ENV_DIR/peddler.env"
APP_USER="${APP_USER:-arkenelle}"

# --------------------------------------------------------------------------
# Guard rails
# --------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
	echo "This needs root (it writes $ENV_FILE and restarts services)." >&2
	echo "Re-run with: sudo bash $0" >&2
	exit 1
fi

if [[ ! -d "$APP_DIR/.git" ]]; then
	echo "No git checkout at $APP_DIR — is this the right host?" >&2
	exit 1
fi

# --from-env takes each secret from the environment variable of the same name
# instead of prompting, so CI can run this over SSH. Anything not supplied that
# has a generator is generated; anything already set is kept.
FROM_ENV=0
for arg in "$@"; do
	case "$arg" in
		--from-env) FROM_ENV=1 ;;
		*) echo "Unknown argument: $arg" >&2; exit 2 ;;
	esac
done

# Interactive by default: it prompts for secrets. Refuse to run headless rather
# than silently write blank keys and leave the store quietly broken - a store
# that takes money and credits nothing is worse than one that is visibly off.
if [[ $FROM_ENV -eq 0 && ! -t 0 ]]; then
	echo "This script prompts for secrets and needs a terminal." >&2
	echo "Run it from an interactive shell, or pass --from-env and set the" >&2
	echo "secrets as environment variables (see the Premium secrets workflow)." >&2
	exit 1
fi

echo "==> Arkenelle premium currency setup"
echo "    checkout: $APP_DIR"
echo "    secrets:  $ENV_FILE"
echo

# --------------------------------------------------------------------------
# 1. Refresh the checkout
# --------------------------------------------------------------------------
# Fast-forward ONLY. A merge or a rebase on a production checkout is how a box
# ends up on a commit that exists nowhere else, with no way to tell what is
# running. If this refuses, something has edited files on the server and that is
# worth looking at before deploying over it.
echo "==> 1/5 Updating $APP_DIR from origin/main"
# NOT in --from-env mode. The Deploy VPS workflow already syncs the checkout on
# every push, so there is nothing to do - and doing it anyway would rewrite THIS
# FILE while bash is still reading it. Bash reads a script incrementally from a
# byte offset, so a running script that edits itself resumes at whatever now sits
# at that offset. Harmless while the file is unchanged, which is why it has never
# bitten; not worth leaving armed.
if [[ $FROM_ENV -eq 1 ]]; then
	echo "    skipped (--from-env; the deploy workflow owns the checkout)"
	echo "    at $(git -C "$APP_DIR" rev-parse --short HEAD)"
else
CURRENT_BRANCH="$(git -C "$APP_DIR" rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
	echo "    checkout is on '$CURRENT_BRANCH', not main — leaving it alone." >&2
	echo "    Switch it by hand if that is wrong, then re-run." >&2
else
	git -C "$APP_DIR" fetch --quiet origin main
	if git -C "$APP_DIR" merge-base --is-ancestor HEAD origin/main; then
		git -C "$APP_DIR" merge --ff-only --quiet origin/main
		echo "    now at $(git -C "$APP_DIR" rev-parse --short HEAD)"
	else
		echo "    local HEAD is not an ancestor of origin/main — NOT fast-forwarding." >&2
		echo "    Resolve by hand; nothing else here depends on it." >&2
	fi
fi
fi
echo

# --------------------------------------------------------------------------
# 2. Secrets
# --------------------------------------------------------------------------
echo "==> 2/5 Secrets"
MISSING_SECRETS=0
install -d -m 0750 -o root -g "$APP_USER" "$ENV_DIR"
if [[ ! -f "$ENV_FILE" ]]; then
	install -m 0640 -o root -g "$APP_USER" \
		"$APP_DIR/deploy/config/peddler.env.example" "$ENV_FILE"
	echo "    created $ENV_FILE from the example"
fi

current_value() {
	# Last assignment wins, matching how systemd parses the file.
	grep -E "^$1=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true
}

set_value() {
	local key="$1" value="$2"
	if grep -qE "^$key=" "$ENV_FILE"; then
		# The value can contain / and &, so use a delimiter that cannot appear in
		# a key and escape the replacement rather than trusting it.
		python3 - "$ENV_FILE" "$key" "$value" <<'PY'
import sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, encoding="utf-8").read().split("\n")
out, done = [], False
for line in lines:
    if line.startswith(key + "="):
        if not done:
            out.append(key + "=" + value)
            done = True
        # Drop any later duplicates so the file has exactly one assignment.
    else:
        out.append(line)
if not done:
    out.append(key + "=" + value)
open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out))
PY
	else
		printf '%s=%s\n' "$key" "$value" >>"$ENV_FILE"
	fi
}

# Prompt that shows whether something is already set WITHOUT printing it. The
# whole point of this file is that these values are not readable from scrollback,
# a terminal log, or over someone's shoulder.
ask_secret() {
	local key="$1" description="$2" generator="${3:-}"
	local existing entered
	existing="$(current_value "$key")"

	if [[ $FROM_ENV -eq 1 ]]; then
		# The variable of the same name, then the existing value, then a
		# generated one. Never a blank: a key that silently ends up empty is the
		# failure this whole script exists to avoid.
		entered="${!key:-}"
		if [[ -n "$entered" ]]; then
			set_value "$key" "$entered"
			echo "    $key set from the environment (${#entered} chars)."
		elif [[ -n "$existing" ]]; then
			echo "    $key already set (${#existing} chars) - kept."
		elif [[ -n "$generator" ]]; then
			entered="$(eval "$generator")"
			set_value "$key" "$entered"
			echo "    $key generated (${#entered} chars)."
		else
			echo "    $key is NOT set and cannot be generated. $description" >&2
			echo "    Add it as a repository secret and re-run." >&2
			MISSING_SECRETS=1
		fi
		return
	fi

	if [[ -n "$existing" ]]; then
		echo "    $key is already set (${#existing} chars). Enter to keep it."
	else
		echo "    $key is NOT set. $description"
	fi
	if [[ -n "$generator" ]]; then
		echo "      (leave blank and type 'generate' to make one)"
	fi

	read -r -s -p "      $key: " entered
	echo
	if [[ -z "$entered" ]]; then
		if [[ -z "$existing" ]]; then
			echo "      left unset — the feature stays off until it has a value."
		fi
		return
	fi
	if [[ "$entered" == "generate" && -n "$generator" ]]; then
		entered="$(eval "$generator")"
		echo "      generated (${#entered} chars)."
	fi
	set_value "$key" "$entered"
	echo "      set (${#entered} chars)."
}

echo
echo "  -- Game server <-> gateway --"
set_value ARKENELLE_PREMIUM_API_URL "http://127.0.0.1:8088"
echo "    ARKENELLE_PREMIUM_API_URL pinned to loopback."
ask_secret ARKENELLE_PREMIUM_API_KEY \
	"Shared secret the world uses to call the gateway." \
	"openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48"

echo
echo "  -- Admin dashboard --"
ask_secret ARKENELLE_DASHBOARD_TOKEN \
	"Gates /v1/premium/grant, which mints currency." \
	"openssl rand -hex 32"

echo
echo "  -- Stripe --"
echo "    From the Stripe dashboard: Developers -> Webhooks -> your endpoint."
echo "    The endpoint URL is https://api.arkenelle.com/v1/premium/stripe-webhook"
echo "    and it must be subscribed to checkout.session.completed."
ask_secret ARKENELLE_STRIPE_WEBHOOK_SECRET \
	"Endpoint signing secret, starts whsec_. NOT your API key."

if [[ $MISSING_SECRETS -ne 0 ]]; then
	# Stop BEFORE restarting anything. Half-configured is a store that takes
	# money and credits nothing, which is the one outcome worth failing loudly
	# for; leaving the services on their old environment is the safe state.
	echo >&2
	echo "    Refusing to continue with a secret missing." >&2
	exit 1
fi

chown root:"$APP_USER" "$ENV_FILE"
chmod 0640 "$ENV_FILE"
echo
echo "    $ENV_FILE is root:$APP_USER 0640 — the services read it, nobody else can."
echo

# --------------------------------------------------------------------------
# 3. Caddy
# --------------------------------------------------------------------------
# update.sh already installs this on every deploy; re-applying here means a
# manual run of this script also fixes a box whose Caddyfile has drifted.
echo "==> 3/5 Caddy"
if [[ -f "$APP_DIR/deploy/Caddyfile" ]]; then
	install -m 0644 "$APP_DIR/deploy/Caddyfile" /etc/caddy/Caddyfile
	if caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
		if ! timeout 15 caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
			echo "    reload failed — restarting caddy"
			timeout 20 systemctl restart caddy || echo "    WARN: caddy still down"
		fi
		echo "    Caddyfile applied and reloaded."
	else
		echo "    WARN: Caddyfile failed validation; leaving the running config alone." >&2
		caddy validate --config /etc/caddy/Caddyfile || true
	fi
else
	echo "    WARN: no Caddyfile in the checkout; skipped." >&2
fi
echo

# --------------------------------------------------------------------------
# 4. Restart what reads the new values
# --------------------------------------------------------------------------
# Master and gateway only. The WORLD also reads ARKENELLE_PREMIUM_API_KEY, but
# restarting it disconnects every player online, so that is asked for explicitly
# rather than done as a side effect of setting a key. Until the world restarts,
# the in-game Vault store reports itself offline — which is correct and harmless.
echo "==> 4/5 Restarting master + gateway"
systemctl daemon-reload
for unit in arkenelle-master arkenelle-gateway; do
	systemctl restart "$unit"
	sleep 2
	if systemctl is-active --quiet "$unit"; then
		echo "    $unit active"
	else
		echo "    ERROR: $unit failed to start:" >&2
		journalctl -u "$unit" -n 30 --no-pager >&2
		exit 1
	fi
done
echo

# Never implicit. Restarting the world drops every player, so in --from-env mode
# it happens only when RESTART_WORLD is explicitly "y" - the workflow makes that
# a checkbox rather than a side effect of setting a key.
if [[ $FROM_ENV -eq 1 ]]; then
	restart_world="${RESTART_WORLD:-n}"
	echo "    Restart the WORLD? ${restart_world}  (from RESTART_WORLD)"
else
	read -r -p "    Restart the WORLD too? This disconnects everyone online. [y/N] " restart_world
fi
if [[ "${restart_world,,}" == "y" ]]; then
	systemctl restart arkenelle-world
	sleep 3
	systemctl is-active --quiet arkenelle-world \
		&& echo "    arkenelle-world active" \
		|| { echo "    ERROR: world failed to start" >&2; journalctl -u arkenelle-world -n 40 --no-pager >&2; }
else
	echo "    Skipped. The Vault store stays offline until the world restarts."
fi
echo

# --------------------------------------------------------------------------
# 5. Checks
# --------------------------------------------------------------------------
# WHY premium.db IS NOT IN A CRON JOB. Its backups are taken by the master
# itself (PremiumDatabase.backup_database — hourly, WAL-checkpointed, ten kept in
# user://db_backups), the same way the world backs up classic.db. A shell-level
# `sqlite3 .backup` alongside that would be a second mechanism racing the first.
# This step verifies the in-process one is actually producing files.
echo "==> 5/5 Checks"

BACKUP_DIR="/home/$APP_USER/.local/share/godot/app_userdata/Arkenelle/db_backups"
[[ -d "$BACKUP_DIR" ]] || BACKUP_DIR="$(sudo -u "$APP_USER" find /home/"$APP_USER" -type d -name db_backups 2>/dev/null | head -n1)"
if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
	count="$(find "$BACKUP_DIR" -name 'premium_*.db' 2>/dev/null | wc -l)"
	echo "    premium.db snapshots on disk: $count  ($BACKUP_DIR)"
	if [[ "$count" -eq 0 ]]; then
		echo "    none yet — the master takes one on boot, so check again in a minute."
	fi
else
	echo "    could not locate db_backups; check after the master has run once."
fi

echo -n "    public webhook route: "
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
	-H 'Content-Type: application/json' -d '{}' \
	https://api.arkenelle.com/v1/premium/stripe-webhook || echo 000)"
case "$code" in
	400) echo "reachable, rejecting unsigned posts (400) — correct." ;;
	404) echo "404 — Caddy is blocking it. The webhook will never fire." >&2 ;;
	503) echo "503 — reachable but ARKENELLE_STRIPE_WEBHOOK_SECRET is not set." >&2 ;;
	000) echo "no response — check DNS and that caddy is running." >&2 ;;
	*)   echo "HTTP $code (unexpected — check the gateway log)." >&2 ;;
esac

echo -n "    internal routes blocked publicly: "
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
	-H 'Content-Type: application/json' -d '{}' \
	https://api.arkenelle.com/v1/premium/balance || echo 000)"
[[ "$code" == "404" ]] \
	&& echo "yes (404) — correct." \
	|| echo "NO — got HTTP $code, expected 404. Check the Caddyfile." >&2

echo
echo "Done."
echo
echo "Remaining, in the Stripe dashboard — this script cannot do these for you:"
echo "  1. Create four Payment Links: \$2.49 / \$4.99 / \$9.99 / \$24.99 (USD)."
echo "  2. Point the webhook endpoint at"
echo "     https://api.arkenelle.com/v1/premium/stripe-webhook"
echo "     subscribed to checkout.session.completed."
echo "  3. Put the four link URLs in the website build environment as"
echo "     ARKENELLE_STRIPE_LINK_249 / _499 / _999 / _2499, then redeploy the site."
echo "     Until then /store/ shows every package as 'Coming soon'."
