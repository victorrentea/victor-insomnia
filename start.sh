#!/bin/bash
# Launch Victor Insomnia (menu bar ☕ / 🛏, test hooks on 127.0.0.1:55125).
LOG=/tmp/victor-insomnia.log
APP="/Applications/Victor Insomnia.app"
echo "$(date '+%H:%M:%S') Starting Victor Insomnia..." >> "$LOG"
if [ ! -x "$APP/Contents/MacOS/Victor Insomnia" ]; then
    echo "$(date '+%H:%M:%S') Victor Insomnia not installed — run: ./build-app.sh" >> "$LOG"
    exit 1
fi
# `open`, never the bundle binary: macOS files a process that exec'd its own
# Mach-O by path, as a second app with the same name.
exec /usr/bin/open -a "$APP"
