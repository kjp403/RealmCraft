#!/usr/bin/env bash
# Cloud Agent install step for RealmCraft (Godot 4 MMO).
#
# 1. Provisions the Godot 4.7 editor binary (matches project.godot's "4.7"
#    config/features tag). The editor's --headless mode runs the game's
#    dedicated servers and its CLI imports assets.
# 2. Warms the res:// import cache (.godot/) so servers and clients boot
#    without a slow cold import.
#
# Idempotent: safe to re-run. Skips the download when the correct Godot
# version is already installed.
set -euo pipefail

GODOT_VERSION="4.7.1-stable"
GODOT_VERSION_STRING="4.7.1.stable"
DL_NAME="Godot_v${GODOT_VERSION}_linux.x86_64"
DL_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${DL_NAME}.zip"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

have_godot() {
	command -v godot >/dev/null 2>&1 &&
		godot --headless --version 2>/dev/null | grep -q "$GODOT_VERSION_STRING"
}

if have_godot; then
	echo "Godot $GODOT_VERSION_STRING already installed: $(command -v godot)"
else
	echo "Installing Godot $GODOT_VERSION ..."
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	curl -fL --retry 4 --retry-delay 4 -o "$tmp/godot.zip" "$DL_URL"
	unzip -o "$tmp/godot.zip" -d "$tmp" >/dev/null
	if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
		sudo install -m 0755 "$tmp/$DL_NAME" /usr/local/bin/godot
	else
		mkdir -p "$HOME/.local/bin"
		install -m 0755 "$tmp/$DL_NAME" "$HOME/.local/bin/godot"
	fi
fi

# Resolve the editor path (covers the ~/.local/bin fallback not yet on PATH).
GODOT="$(command -v godot || true)"
if [ -z "$GODOT" ] && [ -x "$HOME/.local/bin/godot" ]; then
	GODOT="$HOME/.local/bin/godot"
fi
if [ -z "$GODOT" ]; then
	echo "ERROR: godot binary not found after install." >&2
	exit 1
fi
"$GODOT" --headless --version

# Warm the import cache. A cold headless run can exit non-zero purely from
# benign "leaked instances" cleanup noise, so don't treat that as fatal — the
# .godot/ cache is still produced and servers re-import on first boot if needed.
echo "Importing project assets (warming .godot cache) ..."
if ! "$GODOT" --headless --path . --import; then
	echo "WARN: first import returned non-zero; retrying once ..." >&2
	"$GODOT" --headless --path . --import ||
		echo "WARN: import still non-zero; servers will import on first boot." >&2
fi

echo "RealmCraft install complete."
