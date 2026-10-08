#!/bin/bash
# Build /Applications/Victor Insomnia.app from this checkout.
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

APP_NAME="Victor Insomnia"
BUNDLE_ID="ro.victorrentea.victor-insomnia"
APP_DIR="/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
BUILD_CONFIG="release"

BUILD_TIMESTAMP=$(date "+%b %-d, %H:%M")
sed -i '' "s/static let time = .*/static let time = \"$BUILD_TIMESTAMP\"/" "$DIR/Sources/VictorInsomnia/BuildInfo.swift"
echo "Build timestamp: $BUILD_TIMESTAMP"

# Tests first: several of them pin the order of things in the source (tone
# before release, restore before playback) that nothing else would catch.
# SKIP_TESTS=1 forces a build anyway.
if [ "${SKIP_TESTS:-0}" != "1" ]; then
    echo "Running tests..."
    TESTLOG="$(mktemp -t victor-insomnia-tests)"
    if ! swift test > "$TESTLOG" 2>&1; then
        grep -E "error:|failed \(" "$TESTLOG" | head -20
        echo ""
        echo "❌ Tests failed — NOT deploying (full log: $TESTLOG)."
        echo "   Fix them, or force with: SKIP_TESTS=1 ./build-app.sh"
        exit 1
    fi
    grep -E "Executed [0-9]+ tests" "$TESTLOG" | tail -1
    rm -f "$TESTLOG"
fi

swift build -c "$BUILD_CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$DIR/.build/arm64-apple-macosx/$BUILD_CONFIG/VictorInsomnia" "$CONTENTS/MacOS/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# A stable identity when there is one (export CODESIGN_IDENTITY=…); ad-hoc
# otherwise. This app asks for no privacy grants, so ad-hoc costs nothing.
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    for CANDIDATE in "Victor Addons Local Code Signing"; do
        if security find-identity -v -p codesigning "$HOME/Library/Keychains/login.keychain-db" | grep -Fq "$CANDIDATE"; then
            SIGNING_IDENTITY="$CANDIDATE"
            break
        fi
    done
fi
codesign --force --sign "${SIGNING_IDENTITY:--}" "$APP_DIR"

echo "✅ Installed $APP_DIR"
echo "   Restart it with: pkill -f \"$APP_NAME\"; open \"$APP_DIR\""
