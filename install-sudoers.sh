#!/bin/bash
# Let the app set and clear the kernel SleepDisabled flag without a password —
# exactly two command lines, arguments included, and nothing else:
#   /usr/bin/pmset -a disablesleep 0
#   /usr/bin/pmset -a disablesleep 1
# NOPASSWD because the 20% battery floor has to be able to stand down with the
# lid shut and nobody there to type one. Needs a terminal (sudo asks once).
#
# Remove with: sudo rm /etc/sudoers.d/victor-insomnia-disablesleep
set -e
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
echo "$USER ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1" > "$TMP"
# Validate first: a broken sudoers file locks you out of sudo.
sudo visudo -c -f "$TMP"
sudo install -m 0440 -o root -g wheel "$TMP" /etc/sudoers.d/victor-insomnia-disablesleep
echo "✅ /etc/sudoers.d/victor-insomnia-disablesleep installed"
