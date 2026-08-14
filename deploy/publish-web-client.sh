#!/usr/bin/env bash
# Unpack the Godot web export tarball onto the live play.arkenelle.com docroot.
# Called from the Release workflow after scp of /tmp/arkenelle-web-client.tar.gz.
set -euo pipefail

TAR="${1:-/tmp/arkenelle-web-client.tar.gz}"
DEST="/opt/arkenelle/client-web"
STAGE="${DEST}.new"

if [[ "$(id -u)" -ne 0 ]]; then
	echo "Run as root: sudo bash $0" >&2
	exit 1
fi
if [[ ! -f "$TAR" ]]; then
	echo "Missing tarball: $TAR" >&2
	exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
tar -xzf "$TAR" -C "$STAGE"
if [[ ! -f "$STAGE/index.html" ]]; then
	echo "Tarball did not contain index.html" >&2
	rm -rf "$STAGE"
	exit 1
fi
rm -rf "$DEST"
mv "$STAGE" "$DEST"
chown -R arkenelle:arkenelle "$DEST"
chmod -R a+rX "$DEST"
rm -f "$TAR"
echo "Published web client to $DEST"
ls -lah "$DEST" | head
