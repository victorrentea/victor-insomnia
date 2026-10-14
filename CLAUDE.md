# Victor Insomnia

Menu bar app (☕ / 🛏) that holds the Mac awake with the lid shut **while a
Claude Code session is working**. Extracted from `victor-macos-addons` on
2026-10-08; public repo `victorrentea/victor-insomnia`, branch `master`.

**Read [docs/insomnia.md](docs/insomnia.md) before touching the code** — every
decision, measurement and dead end is there.

**What the lid and the battery floor do and sound like is decided by
[docs/lid-close.puml](docs/lid-close.puml)** — change the diagram first, then
`LidAwakePolicy`; `LidRulesDiagramTests` fails when the two disagree.
Re-render with `plantuml -tsvg docs/lid-close.puml`.

- **Build**: `swift build && swift test`
- **Deploy after any code change**: `git push`, `./build-app.sh`, then
  `pkill -f "Victor Insomnia"; open "/Applications/Victor Insomnia.app"`.
  Never start it through the bundle binary.
- **Test hooks**: `127.0.0.1:55125` (`/test/lid-awake/state`, `/mode/<m>`, …),
  listed in `HttpServer.swift`.
- **Log**: `/tmp/victor-insomnia.log`.
- **Public repo**: no personal paths, no client names. Only our own sounds are
  committed (`sounds/`, synthesized); private recordings go in
  `~/.victor-insomnia/sounds/`, which wins over them.
- **Users install with `install.sh`, releases come from `tools/release.sh`** —
  docs/insomnia.md, "Install and release".
- Talks to Victor Addons (55123) for one thing only, `/chrome/audible`, and
  works without it.
