#!/usr/bin/env bash
# Unpack the Windows portable client onto play.arkenelle.com/desktop/.
# Called from the Release workflow after scp of /tmp/arkenelle-windows-client.tar.gz.
# Tarball must contain Arkenelle-windows.zip and latest.json.
set -euo pipefail

TAR="${1:-/tmp/arkenelle-windows-client.tar.gz}"
DEST="/opt/arkenelle/client-windows"
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
if [[ ! -f "$STAGE/Arkenelle-windows.zip" ]] || [[ ! -f "$STAGE/latest.json" ]]; then
	echo "Tarball did not contain Arkenelle-windows.zip and latest.json" >&2
	rm -rf "$STAGE"
	exit 1
fi
rm -rf "$DEST"
mv "$STAGE" "$DEST"
chown -R arkenelle:arkenelle "$DEST"
chmod -R a+rX "$DEST"
rm -f "$TAR"
echo "Published Windows client to $DEST"
ls -lah "$DEST"
cat "$DEST/latest.json"
