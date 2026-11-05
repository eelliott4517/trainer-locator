#!/bin/sh
# Copy the addon into the live WoW: Forever client's AddOns folder (macOS). A new addon needs a game
# restart, an update just a /reload.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WOW="${WOW_DIR:-/Applications/World of Warcraft/_forever_}"
DEST="$WOW/Interface/AddOns/TrainerLocator"
rm -rf "$DEST"
mkdir -p "$DEST"
cp "$HERE"/TrainerLocator/*.toc "$HERE"/TrainerLocator/*.lua "$HERE"/TrainerLocator/*.xml "$DEST"/
echo "Installed to $DEST"
