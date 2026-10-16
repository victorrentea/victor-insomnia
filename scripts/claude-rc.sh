#!/bin/zsh
# Starts the Claude Code Remote Control server in a detached tmux session.
# Idempotent: if the tmux session already exists, exits at once.
# Run by Victor Insomnia's 🛰️ Claude RC row: at launch and every 60 s while
# it is ticked. Copy it to ~/.victor-insomnia/claude-rc.sh to change it —
# that copy wins over this one. docs/claude-remote-control.md
#
#   see it:   tmux attach -t claude-rc      (detach: Ctrl-B, then D)
#   kill it:  tmux kill-session -t claude-rc

# ~/.local/bin first: the native Claude Code build, not an npm/nvm one.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SESSION=claude-rc
# Where the sessions opened from the phone start.
WORKDIR="${CLAUDE_RC_DIR:-$HOME}"
# The name the sessions show under in Remote Control (claude.ai / the app).
RC_NAME="$(scutil --get ComputerName 2>/dev/null || hostname -s)"

# Auto mode: the classifier decides, and anything risky becomes a prompt you
# approve from the phone. No blanket bypass.
PERMS="--permission-mode auto"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "$(date '+%F %T') claude-rc: tmux session already up, nothing to do"
  exit 0
fi

echo "$(date '+%F %T') claude-rc: starting the RC server in $WORKDIR as '$RC_NAME'"
# `claude remote-control` (alias `claude rc`) is the SERVER: up to 32
# concurrent sessions, and the phone can CREATE new ones. NOT the flag
# `claude --remote-control <name>`, which exposes one existing interactive
# session and cannot create any.
exec tmux new-session -d -s "$SESSION" -c "$WORKDIR" \
  "exec zsh -lc 'exec claude remote-control $PERMS --remote-control-session-name-prefix \"$RC_NAME\"'"
