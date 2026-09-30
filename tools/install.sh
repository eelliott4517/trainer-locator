#!/bin/sh
# Copy the addon into the WoW: Forever beta AddOns folder (macOS). A new addon needs a game
# restart, an update just a /reload.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WOW="${WOW_DIR:-/Applications/World of Warcraft/_classic_beta_}"
DEST="$WOW/Interface/AddOns/TrainerLocator"
rm -rf "$DEST"
mkdir -p "$DEST"
cp "$HERE"/TrainerLocator/*.toc "$HERE"/TrainerLocator/*.lua "$HERE"/TrainerLocator/*.xml "$DEST"/
echo "Installed to $DEST"
