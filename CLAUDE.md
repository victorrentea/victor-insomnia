# Victor Insomnia

Menu bar app (☕ / 🛏) that holds the Mac awake with the lid shut **while a
Claude Code session is working**. Extracted from `victor-macos-addons` on
2026-10-08; public repo `victorrentea/victor-insomnia`, branch `master`.

**Read [docs/insomnia.md](docs/insomnia.md) before touching the code** — every
decision, measurement and dead end is there.

- **Build**: `swift build && swift test`
- **Deploy after any code change**: `git push`, `./build-app.sh`, then
  `pkill -f "Victor Insomnia"; open "/Applications/Victor Insomnia.app"`.
  Never start it through the bundle binary.
- **Test hooks**: `127.0.0.1:55125` (`/test/lid-awake/state`, `/mode/<m>`, …),
  listed in `HttpServer.swift`.
- **Log**: `/tmp/victor-insomnia.log`.
- **Public repo**: no personal paths, no client names. The sound files stay out
  (`~/.victor-insomnia/sounds/`).
- Talks to Victor Addons (55123) for one thing only, `/chrome/audible`, and
  works without it.
