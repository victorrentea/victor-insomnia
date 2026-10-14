#!/bin/bash
# Publish a GitHub release that install.sh can fetch: a universal (arm64 +
# x86_64), ad-hoc signed "Victor Insomnia.app", zipped.
#
#   tools/release.sh            # tag = v<yyyy.mm.dd-HHMM>
#   tools/release.sh v1.2.0
#
# Ad-hoc, not the maintainer's local identity: a self-signed certificate means
# nothing on anyone else's Mac. Not notarized — install.sh downloads with curl,
# which sets no quarantine flag, so Gatekeeper never asks.
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DIR"

TAG="${1:-v$(date +%Y.%m.%d-%H%M)}"
DIST="$DIR/dist"
APP="$DIST/Victor Insomnia.app"
ZIP="$DIST/Victor-Insomnia.zip"

[ -z "$(git status --porcelain -- Sources sounds Package.swift build-app.sh | grep -v BuildInfo.swift)" ] \
    || { echo "Uncommitted changes in Sources/sounds — commit first." >&2; exit 1; }

rm -rf "$DIST"; mkdir -p "$DIST"
# build-app.sh stamps BuildInfo.swift in place; put it back by copy afterwards,
# never `git checkout` (other sessions may have edits in this tree).
cp Sources/VictorInsomnia/BuildInfo.swift "$DIST/BuildInfo.swift.keep"
UNIVERSAL=1 CODESIGN_IDENTITY=- APP_DIR="$APP" ./build-app.sh
cp "$DIST/BuildInfo.swift.keep" Sources/VictorInsomnia/BuildInfo.swift
codesign --verify --strict --deep "$APP"
lipo -archs "$APP/Contents/MacOS/Victor Insomnia"
ditto -c -k --keepParent "$APP" "$ZIP"
ls -lh "$ZIP"

gh release create "$TAG" "$ZIP" install.sh \
    --title "Victor Insomnia $TAG" \
    --notes "Install or update: \`curl -fsSL https://raw.githubusercontent.com/victorrentea/victor-insomnia/master/install.sh | bash\`

Universal app (Apple silicon + Intel), macOS 13+, ad-hoc signed. The installer asks for your password once, for the sudoers rule that allows exactly \`pmset -a disablesleep 0|1\`."
echo "✅ Released $TAG"
