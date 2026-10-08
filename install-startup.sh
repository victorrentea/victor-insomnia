#!/bin/bash
# Install Victor Insomnia as a login item (LaunchAgent).
set -e
PLIST_NAME="ro.victorrentea.victor-insomnia.plist"
DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"

# The plist ships with a placeholder so the repo carries nobody's home folder.
mkdir -p "$DIR/.build" "$HOME/Library/LaunchAgents"
sed "s|__START_SH__|$DIR/start.sh|" "$DIR/$PLIST_NAME" > "$DIR/.build/$PLIST_NAME"
cp "$DIR/.build/$PLIST_NAME" "$PLIST_DST"
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"

echo "✅ Victor Insomnia installed as login item"
echo "   Logs: tail -f /tmp/victor-insomnia.log"
