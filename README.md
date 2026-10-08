# Victor Insomnia

A macOS menu bar app that keeps a MacBook running **with the lid shut, on
battery, with nothing plugged in — but only while a Claude Code session is
actually working.** Close the lid mid-loop, put the laptop in the bag, and the
work is still there when you open it. When the last session finishes, the Mac
is let go to sleep like any other.

| menu bar | meaning |
|---|---|
| 🛏 (white) | nothing is keeping the Mac awake — the lid sleeps it |
| ☕ white | `Claude` — held awake for a session you are typing at |
| ☕ orange | `Claude /rc` — also for sessions driven from the phone over remote control |
| ☕ red | `Always` — held awake whatever is running |

The menu: **Off / Claude / Claude /rc / Always**, each with the count of
sessions working right now, plus **Sleep under 20%** (the battery floor that
stands the whole thing down, on by default).

With the lid shut on battery it beats a quiet heartbeat every 10 s out of the
built-in speaker, so you can hear through the bag that it is still up; a
flatline when the work is done and the Mac is about to sleep.

## Why it needs a sudoers rule

No power assertion (`caffeinate`, `IOPMAssertion…`) survives a lid close; only
the kernel's `SleepDisabled` flag does (`pmset -a disablesleep 1`, the same
switch Amphetamine's closed-display mode uses). That needs root, so the app runs
`sudo -n` against a rule that allows exactly `disablesleep 0` and `disablesleep 1`:

```sh
./install-sudoers.sh
```

## Build and run

```sh
./build-app.sh            # tests, release build → /Applications/Victor Insomnia.app
open "/Applications/Victor Insomnia.app"
./install-startup.sh      # optional: start at login
```

Optional sounds: put `13_heartbeat.mp3` and `15_flatline.mp3` in
`~/.victor-insomnia/sounds/`; without them it uses macOS system sounds.

Headless state for debugging: `curl 127.0.0.1:55125/test/lid-awake/state`.

Everything else — why, what was measured, what failed — is in
[docs/insomnia.md](docs/insomnia.md).
