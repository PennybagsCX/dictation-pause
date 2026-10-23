# Post draft — r/MacOS (or reply material for Apple Discussions threads)

**Title:** I made a free tool that pauses YouTube/Music while you're using voice dictation (and resumes after) — macOS Sonoma+

**Body:**

tl;dr: https://github.com/PennybagsCX/dictation-pause — `git clone` + `./install.sh`, done.

macOS dictation has a small annoyance: it mutes (but doesn't pause) whatever
you're watching while you dictate, so the video keeps playing silently and
you miss a chunk of it. Whisperflow-style apps do pause properly, but I
didn't want another subscription app running.

So I built a tiny open-source LaunchAgent (~10 MB, ~0% CPU, no dependencies):

- Video playing + you start dictating → it actually **pauses** (not mute)
- Stop dictating → it **resumes**
- Never touches a paused tab (won't randomly start playback)
- Pauses on any mic activity, so calls also pause music (feature, IMO)
- Self-healing: a doctor agent checks itself twice a day and sends a macOS
  notification if a macOS update ever breaks it

One fun reverse-engineering note: dictation on recent macOS **cannot be
detected via CoreAudio** — it captures through a path that never sets the
input device's "in use" flag (I verified this with probes; process-watching
the speech daemons doesn't work either — they're persistent and their churn
is uncorrelated). The only public signal that works is the Window Server's
"StatusIndicator" windows (the mic dot in the menu bar), so the agent polls
those at 4 Hz. All documented in the README with the probe scripts.

Requirements: macOS + a one-time Accessibility permission. Source is ~200
lines of Swift, MIT licensed.

Feedback welcome — especially whether it works on your Mac/varsion.

---

# Alternative short version — good as a reply on existing Apple Discussions
# threads about "dictation doesn't pause media":
"Built an open-source tool for exactly this — it watches the system mic
indicator and posts a real pause/resume media event (free, ~10 MB, no
subscription): https://github.com/PennybagsCX/dictation-pause"

# Show HN title option:
"Show HN: Pause media during macOS dictation (dictation is undetectable via CoreAudio)"
