#!/bin/bash
# Let the app set and clear the kernel SleepDisabled flag without a password —
# exactly two command lines, arguments included, and nothing else:
#   /usr/bin/pmset -a disablesleep 0
#   /usr/bin/pmset -a disablesleep 1
# NOPASSWD because the 20% battery floor has to be able to stand down with the
# lid shut and nobody there to type one. Asks for the password once — in the
# terminal, or in the macOS dialog when there is none.
#
# Remove with: sudo rm /etc/sudoers.d/victor-insomnia-disablesleep
set -e
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
echo "$USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$TMP"
# Validate first: a broken sudoers file locks you out of sudo.
/usr/sbin/visudo -c -f "$TMP"
INSTALL="/usr/bin/install -m 0440 -o root -g wheel '$TMP' /etc/sudoers.d/victor-insomnia-disablesleep"
if [ -t 0 ]; then
    sudo sh -c "$INSTALL"
else
    # No terminal (e.g. `! ./install-sudoers.sh` from Claude Code): sudo cannot
    # ask, so macOS's own password dialog does.
    osascript -e "do shell script \"$INSTALL\" with prompt \"Victor Insomnia needs to let pmset disablesleep run without a password.\" with administrator privileges"
fi
echo "✅ /etc/sudoers.d/victor-insomnia-disablesleep installed"
