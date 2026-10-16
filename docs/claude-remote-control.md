# 🛰️ Claude RC

The row under the four modes that keeps `claude remote-control` — the
persistent server the phone opens new Claude Code sessions against — alive in a
detached tmux session, with an off switch.

Code: `ClaudeRemoteControl.swift` (settings, policy, staleness, watcher), the
row in `StatusMenu`, armed from `main.swift`. Script: `scripts/claude-rc.sh`,
copied into the app as `Contents/Resources/claude-rc.sh`;
`~/.victor-insomnia/claude-rc.sh` (or `$VICTOR_INSOMNIA_CLAUDE_RC`) wins over it.

**Moved here from Victor Addons on 2026-10-16** (Victor: *"the part that keeps a
claude /rc up from startup moves to Insomnia"*), next to the `/rc×1/3` count it
feeds: the sessions this server spawns are the ones `Claude /rc` holds the Mac
up for. The tmux session name (`claude-rc`) did not change, so the server that
was running carried straight over — no restart, no lost phone session.

## What it does

| | |
|---|---|
| **default** | **off** — a public app does not start a server unasked. Victor's Mac carries the tick in `defaults` (`ClaudeRemoteControl.enabled`) |
| **tick on** | run `claude-rc.sh` if the tmux session is down, then watch |
| **tick off** | `tmux kill-session -t claude-rc` — and with it every session open from the phone — stop watching |
| **while ticked** | every **60 s**: session dead? → start it. Alive but **stale** (see Traps)? → kill + start, only with **no live phone sessions** |
| **at app launch** | the same check runs **immediately**, not a minute later |
| **proof** | `GET http://127.0.0.1:55125/test/claude-rc` |

The tmux server double-forks away from whoever spawned it, so Remote Control
survives the rebuild loop (`pkill` + `open`) untouched — the launch-time check
is for the case where it did **not**.

## Why an app and not launchd

From 14 Aug to 22 Sep 2026 a LaunchAgent (`ro.victorrentea.claude-rc`) ran the
script at login and re-checked every 5 minutes. It had no way to be told *no*:
killing the tmux session bought at most five minutes of quiet. It is booted out
and `launchctl disable`d; two watchdogs racing over one tmux session would make
the tick a lie. If it is ever re-enabled, untick this row in the same breath.

## Why a script

It holds the distinction that cost a fortnight once:

- **`claude remote-control`** (alias `claude rc`) is the **server** — capacity 32,
  and the phone can **create new sessions** against it.
- **`claude --remote-control "<name>"`** is a **flag** that exposes one existing
  interactive session. Until 30 Aug 2026 the script used the flag: the Mac showed
  up on the phone, but the "new session" button had nothing to start.

Plus `--permission-mode auto` (the classifier, **not**
`--dangerously-skip-permissions` — anything risky becomes a prompt approved from
the phone) and the `ComputerName` prefix the sessions are named with. The
sessions start in `$CLAUDE_RC_DIR`, else `$HOME`; to start them elsewhere, copy
the script to `~/.victor-insomnia/claude-rc.sh` and edit it.

## The decision

`ClaudeRemoteControlPolicy.decide(enabled:sessionAlive:)` is a two-bit truth
table, and the asymmetry is deliberate: **armed + dead → start**, **disarmed +
alive → kill**, everything else → leave alone. The *tick* never kills — only the
toggle's own edge does, once. An unticked row means "the app is not minding
this", not "the app forbids it", so a server started by hand afterwards survives.

## Traps

- **tmux is found by path** (`/opt/homebrew/bin/tmux` first). Under launchd an
  app has `PATH=/usr/bin:/bin:/usr/sbin:/sbin` — a bare `tmux` would never be
  found, silently, once a minute, forever.
- **`ANTHROPIC_API_KEY` is stripped from the child**: exported, it shadows the
  subscription the server is logged in with, and a key out of credit fails auth.
- **tmux is not decoration.** Remote Control needs a real PTY, and neither
  launchd nor an `NSTask` gives one. That is why the session exists at all, and
  also why the server outlives the app that started it.
- **"Alive" is `tmux has-session`, not "connected".** 25–30 Aug 2026 it ran five
  days with *"Remote Control disconnected — login expired"* in the pane while the
  session itself was alive. If the phone cannot open sessions and
  `/test/claude-rc` says `alive:true`, read the pane —
  `tmux capture-pane -p -t claude-rc` — for `Connected · Capacity: N/32`.
  Missing banner ⇒ untick the row and tick it back (kill + restart).
- **A Claude Code auto-update leaves the server `Ready` but unable to spawn
  sessions** (2026-09-30). The server started on 2.1.282 and ran five days;
  auto-update deleted `~/.local/share/claude/versions/2.1.282`, and the server
  spawns every phone session from **its own** version path, so each one died
  with `spawn error: ENOENT` while the pane kept saying `Ready · Capacity: 0/32`.
  **The tick self-heals** (`ClaudeRemoteControlStaleness`, pure, tested): it
  reads the server's binary (`tmux list-panes -F '#{pane_pid}'` → `proc_pidpath`
  → `…/versions/X`; `ps -o comm=` only says `claude`) and `readlink
  ~/.local/bin/claude`. **Stale** = the server's binary is gone, **or** its
  version differs from the installed one (the early warning), **or** the pane
  (`capture-pane -p -J`) shows `spawn error: ENOENT`. Stale → kill + start,
  **but never while a phone session is live** (`Capacity: N/32` with N>0, or any
  child of the server): it logs and waits, and the first tick after the last
  session ends heals it. Not retried within **10 min** of the previous restart.
  `/test/claude-rc` shows `serverVersion`, `installedVersion`,
  `serverBinaryExists`, `paneSpawnENOENT`, `liveSessions`, `stale`,
  `staleReason`, `lastRestartReason`.
- **`liveSessions` is not the `3` in `/rc×1/3`.** The menu counts the
  `sdk-cli` presence files in `~/.claude/sessions/` whose pid is still a
  `claude` started with `--sdk-url` (`ClaudeActivity.openRemoteSessions`; other
  headless `claude -p` clients write `sdk-cli` too); the probe counts the server's
  child processes. They normally agree; the staleness rule keeps the larger one
  of its own two witnesses so it errs on the side of waiting.

## Seeing it

```
tmux attach -t claude-rc          # detach with Ctrl-B then D
tmux capture-pane -p -t claude-rc # the banner, without attaching
curl -s 127.0.0.1:55125/test/claude-rc
```
