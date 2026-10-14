#!/bin/bash
# Install Victor Insomnia on this Mac — one command, no Xcode needed:
#
#   curl -fsSL https://raw.githubusercontent.com/victorrentea/victor-insomnia/master/install.sh | bash
#
# Keeps a MacBook running with the lid shut while a Claude Code session is
# working. What this script does, in order (safe to re-run):
#   1. downloads the latest release (a universal app: Apple silicon + Intel)
#   2. quits a running copy and installs it to /Applications (~/Applications
#      when /Applications is not writable)
#   3. installs the one sudoers rule the app needs — `pmset -a disablesleep 0|1`
#      and nothing else. This is the ONE step that asks for your password:
#      in a terminal sudo asks; with no terminal (an agent running this) macOS
#      shows its own password dialog.
#   4. registers a login item (LaunchAgent), starts it, checks it answers on
#      http://127.0.0.1:55125/ping
#   5. arms the mode you pass with --mode (default: leave it as it is; a fresh
#      install starts Off — pick ☕ Claude in the menu)
#
# Options:
#   --mode off|interactive|background|always
#                     interactive = "☕ Claude" (sessions at the keyboard),
#                     background = "☕ Claude /rc" (also phone-driven ones)
#   --from-source     build from a clone instead (needs Xcode / Command Line Tools)
#   --no-login-item   do not start it at login
#   --no-sudoers      skip step 3 (the app then cannot hold the lid open)
#   --uninstall       remove the app, the login item and the sudoers rule
#   --version <tag>   install a specific release
set -euo pipefail

REPO="victorrentea/victor-insomnia"
APP_NAME="Victor Insomnia"
BUNDLE_ID="ro.victorrentea.victor-insomnia"
ZIP_NAME="Victor-Insomnia.zip"
PORT=55125
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
SUDOERS="/etc/sudoers.d/victor-insomnia-disablesleep"

FROM_SOURCE=0; LOGIN_ITEM=1; SUDOERS_STEP=1; UNINSTALL=0; VERSION=""; MODE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --mode) MODE="${2:?--mode needs a value}"; shift ;;
        --from-source) FROM_SOURCE=1 ;;
        --no-login-item) LOGIN_ITEM=0 ;;
        --no-sudoers) SUDOERS_STEP=0 ;;
        --uninstall) UNINSTALL=1 ;;
        --version) VERSION="${2:?--version needs a tag}"; shift ;;
        -h|--help) sed -n '2,32p' "$0" 2>/dev/null || true; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
done
case "$MODE" in ""|off|interactive|background|always) ;; *) echo "--mode: off|interactive|background|always" >&2; exit 2 ;; esac

say()  { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m⚠️  %s\033[0m\n' "$*"; }
die()  { printf '\033[31m❌ %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Victor Insomnia is a macOS app."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ] || die "Needs macOS 13 or later."

# Run one command as root: passwordless sudo, else sudo in a terminal, else
# macOS's own password dialog (the case of an agent with no terminal).
as_root() {
    if sudo -n true 2>/dev/null; then sudo "$@"
    elif [ -t 0 ]; then sudo "$@"
    else
        local cmd; cmd=$(printf '%q ' "$@")
        osascript -e "do shell script \"${cmd//\"/\\\"}\" with administrator privileges with prompt \"Victor Insomnia needs your password once, to allow exactly one command: pmset disablesleep 0/1.\""
    fi
}

quit_running() {
    if pgrep -f "$APP_NAME.app/Contents/MacOS" >/dev/null 2>&1; then
        say "Quitting the running copy"
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -f "$APP_NAME.app/Contents/MacOS" >/dev/null 2>&1 || break
            sleep 0.5
        done
        pkill -f "$APP_NAME.app/Contents/MacOS" 2>/dev/null || true
    fi
}

if [ "$UNINSTALL" = 1 ]; then
    quit_running   # Quit clears the kernel flag (LidAwake.releaseForQuit)
    launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT"
    rm -rf "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"
    [ -e "$SUDOERS" ] && as_root /bin/rm -f "$SUDOERS"
    as_root /usr/bin/pmset -a disablesleep 0 >/dev/null 2>&1 || true
    say "Uninstalled (sudoers rule removed, sleep re-enabled)."
    exit 0
fi

DEST_DIR="/Applications"
[ -w "$DEST_DIR" ] || { DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; }
APP="$DEST_DIR/$APP_NAME.app"
WORK=$(mktemp -d -t victor-insomnia-install)
trap 'rm -rf "$WORK"' EXIT

if [ "$FROM_SOURCE" = 1 ]; then
    xcrun --find swift >/dev/null 2>&1 || die "No Swift toolchain. Run: xcode-select --install   (then re-run)"
    SRC="$HOME/.victor-insomnia/src"
    if [ -d "$SRC/.git" ]; then git -C "$SRC" pull --ff-only --quiet
    else mkdir -p "$(dirname "$SRC")"; git clone --quiet --depth 1 "https://github.com/$REPO.git" "$SRC"; fi
    say "Building (1–3 minutes the first time)"
    quit_running
    (cd "$SRC" && SKIP_TESTS=1 CODESIGN_IDENTITY=- APP_DIR="$APP" ./build-app.sh >"$WORK/build.log" 2>&1) \
        || { tail -30 "$WORK/build.log"; die "Build failed."; }
else
    if [ -n "$VERSION" ]; then URL="https://github.com/$REPO/releases/download/$VERSION/$ZIP_NAME"
    else URL="https://github.com/$REPO/releases/latest/download/$ZIP_NAME"; fi
    # Test hook: a zip served from elsewhere (a build not released yet).
    URL="${VICTOR_INSOMNIA_ZIP_URL:-$URL}"
    say "Downloading $URL"
    curl -fL --progress-bar -o "$WORK/$ZIP_NAME" "$URL" \
        || die "Download failed. No release yet? Try: bash install.sh --from-source"
    ditto -x -k "$WORK/$ZIP_NAME" "$WORK/unzipped"
    [ -d "$WORK/unzipped/$APP_NAME.app" ] || die "The download does not contain $APP_NAME.app"
    quit_running
    rm -rf "$APP"
    ditto "$WORK/unzipped/$APP_NAME.app" "$APP"
fi
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
say "Installed $APP"

if [ "$SUDOERS_STEP" = 1 ]; then
    RULE="$USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
    if [ -e "$SUDOERS" ] && sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null; then
        say "sudoers rule already in place ($SUDOERS)"
    else
        say "Installing the sudoers rule — macOS will ask for your password once"
        echo "$RULE" > "$WORK/rule"
        /usr/sbin/visudo -c -q -f "$WORK/rule" >/dev/null 2>&1 || die "The sudoers rule did not validate."
        as_root /usr/bin/install -m 0440 -o root -g wheel "$WORK/rule" "$SUDOERS" \
            || die "Could not install $SUDOERS (password dialog cancelled?). Re-run, or use --no-sudoers."
        sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null \
            && say "sudoers rule works" || warn "sudoers rule installed but sudo -n still refuses — check $SUDOERS"
    fi
fi

if [ "$LOGIN_ITEM" = 1 ]; then
    # `open -a`, never the binary (a binary started by path is a different app to macOS).
    mkdir -p "$(dirname "$LAUNCH_AGENT")"
    cat > "$LAUNCH_AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array><string>/usr/bin/open</string><string>-a</string><string>$APP</string></array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
    launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT" 2>/dev/null || true
    say "Login item registered"
fi

# The login item's RunAtLoad launches it already; a second `open` while that
# launch is still in flight makes the app relaunch itself (a reopen = restart,
# by design). So give the login item up to 10 s, and open only if it did not.
STARTED=0
if [ "$LOGIN_ITEM" = 1 ]; then
    for _ in $(seq 1 20); do
        pgrep -f "$APP_NAME.app/Contents/MacOS" >/dev/null 2>&1 && { STARTED=1; break; }
        sleep 0.5
    done
fi
if [ "$STARTED" = 0 ]; then
    say "Starting $APP_NAME"
    open -a "$APP"
fi
UP=0
# Up to 60 s: right after a boot, or on a slow disk, a first launch can take
# most of a minute (measured on a fresh VM).
for _ in $(seq 1 120); do
    curl -fs -m 1 "http://127.0.0.1:$PORT/ping" >/dev/null 2>&1 && { UP=1; break; }
    sleep 0.5
done
if [ "$UP" != 1 ]; then
    warn "Installed and started, but it has not answered on port $PORT within 60 s yet."
    warn "It may still be starting (first launch after a boot is slow). Check: curl http://127.0.0.1:$PORT/ping — log: /tmp/victor-insomnia.log"
fi

if [ -n "$MODE" ]; then
    SET=0
    for _ in 1 2 3 4 5 6; do
        curl -fs -m 20 "http://127.0.0.1:$PORT/test/lid-awake/mode/$MODE" >/dev/null && { SET=1; break; }
        sleep 5
    done
    [ "$SET" = 1 ] || warn "Could not set mode $MODE yet — pick it in the 🛏 menu, or: curl 127.0.0.1:$PORT/test/lid-awake/mode/$MODE"
fi
STATE=$(curl -fs -m 3 "http://127.0.0.1:$PORT/test/lid-awake/state" || echo '{}')
say "Running. State: $STATE"
cat <<EOF

The menu bar shows 🛏 (the Mac may sleep) or ☕ (held awake). Click it to pick:
  Off · ☕ Claude (sessions you type at) · ☕ Claude /rc (also phone-driven) · Always
With the lid shut on battery you hear a heartbeat every 10 s while it holds.
Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/master/install.sh | bash -s -- --uninstall
EOF
