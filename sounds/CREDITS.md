# Sounds

Both files are synthesized for this project (Python, sine partials with
envelopes) — own work, released under CC0 like the rest of the repo's media.

| file | what | timing the code relies on |
|---|---|---|
| `13_heartbeat.mp3` | lub-dub every second, 7.1 s | each beat starts at 0.50 s + n·1.0 s; `LidAwake` plays the 0.50–1.05 s window |
| `15_flatline.mp3` | two ECG beeps (0.50 s, 1.90 s), then a 1 kHz tone from 3.34 s to 5.2 s | `SleepChime.toneStart` = 3.30 s plays only the tone |

Replace them with your own by dropping files with the same names into
`~/.victor-insomnia/sounds/`.
