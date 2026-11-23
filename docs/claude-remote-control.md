# 🛰️ Claude RC

The row under the four modes that keeps `claude remote-control` — the
persistent server the phone opens new Claude Code sessions against — alive in a
detached tmux session, with an off switch.

Code: `ClaudeRemoteControl.swift` (settings, policy, staleness, watcher), the
row in `StatusMenu`, armed from `main.swift`. Script: `scripts/claude-rc.sh`,
copied into the app as `Contents/Resources/claude-rc.sh`;
`~/.victor-insomnia/claude-rc.sh` (or `$VICTOR_INSOMNIA_CLAUDE_RC`) wins over it.

**Moved here from Victor Mac on 2026-10-16** (Victor: *"the part that keeps a
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

## 📡 Background (2026-11-23)

*Named „Background”, not „Phone sessions” (Victor, same evening): they are the
`/rc` sessions the host runs in the background, opened from the phone **or**
claude.ai.*

The row under 🛰️ Claude RC, shown only while the phone has sessions open on
this Mac: a submenu with one row per session (`⚙️` working, `💤` idle, the
first prompt as the name). **Click one and it continues in a Terminal window,
still the same session on the phone.** Code: `BackgroundSessions.swift`; proof:
`GET /test/background-sessions` (read-only — the move itself has no HTTP hook, so a
web page cannot trigger a kill through localhost).

What the click does, each step measured on CLI 2.1.330 with a throwaway session:

1. **Find it.** `~/.claude/sessions/<pid>.json` of every `claude --print
   --sdk-url …` child names the local transcript (`sessionId`) and the phone's
   id (`bridgeSessionId`, `session_01…`). The transcript is local.
2. **Open Terminal** on a self-deleting `.command` file (an interactive login
   zsh, in the session's cwd).
3. **The script stops the headless child** — `SIGTERM`, `kill -9` after 5 s,
   the pid's argv re-checked first; the host does not archive the session for
   that — **and at once** runs
   `CLAUDE_BRIDGE_REATTACH_SESSION=<bridgeSessionId> claude --resume <sessionId>`. The env var turns Remote Control on and **reattaches
   to the same session**: same URL, same entry on the phone, full history; a
   message from claude.ai was answered by the terminal and no headless child
   came back.

A session mid-turn asks first: the move cuts the turn short.

**Closing that Terminal archives the session on the phone** (seen live): an
interactive /rc session archives on exit, as it always does. It is not lost —
claude.ai shows *Unarchive*, and `claude --resume` still has the transcript.

**Why the stop is in the script, not in the app** (first version, same day):
the app killed the child, then opened Terminal; the shell took ~25 s to start,
a message sent from claude.ai in that gap made the host re-queue the work and
spawn a **new** headless child, and that child kept the session — the Terminal
never got a message. Stopped from the script, the gap is the CLI's own start-up
(~1.5 s). A message landing inside those 1.5 s can still bring a child back.

**How to tell who answered** — not from claude.ai's footer, which fooled the
first test: each transcript line carries `entrypoint`, `sdk-cli` for the
headless child, `cli` for the Terminal.

Proved end to end on 2026-11-23 (`takeOver` on a fresh session started from
claude.ai): one message sent while the Terminal was still starting and one
after, both written with `entrypoint: cli`, no headless child came back, and
the row left the submenu.

**Dead end: `claude --resume <id> --remote-control`.** It reopens the
conversation but mints a **new** phone session; the old entry stays, offline.
Writing into the old one makes the host spawn a fresh headless child **on the
same transcript** as the terminal — two writers, a forked conversation.

**Fragile on purpose-built ground**: `CLAUDE_BRIDGE_REATTACH_SESSION` is an
internal variable (the CLI uses it to hand a session to a relaunched process),
not a documented flag. If a release drops it, the Terminal still resumes the
conversation, only without Remote Control; re-test after a CLI upgrade if the
phone stops following.
