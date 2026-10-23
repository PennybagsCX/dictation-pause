# dictation-pause

Pauses media playback while macOS built-in dictation is active, and resumes it
when you stop dictating (Whisperflow-style). Dictation-only: video calls
(Zoom/Meet/FaceTime) do NOT trigger a pause.

## How it works

A single compiled Swift binary (~10–15 MB RSS, ~0% CPU) runs as a LaunchAgent:

1. The default **input** device is watched via a CoreAudio change listener
   (`kAudioDevicePropertyDeviceIsRunningSomewhere` — event-driven, no busy
   polling), with a 5 s watchdog property-read that recovers edges if the
   listener silently dies (a known coreaudiod quirk).
2. On mic start, the process table is checked (in-process, no forking) for a
   dictation process (`speechrecogn*` / `*dictation*`). No match → not
   dictation → do nothing.
3. Output activity is sampled twice, 0.35 s apart, to skip the short dictation
   start beep. Both samples "running" → something is really playing → a media
   play/pause key event (NX_KEYTYPE_PLAY, byte-identical to pressing the F8
   key) is posted.
4. On mic stop, if we paused it, we post the same event to resume. We never
   resume anything we didn't pause, and a *paused* tab can never be toggled
   back ON by accident (that's what the two-sample guard is for).

## Install

```bash
git clone <repo-url> && cd dictation-pause
./install.sh
```

`install.sh` builds, writes `~/Library/LaunchAgents/com.dts.dictation-pause.plist`
pointing at this checkout, and starts the agent. `RunAtLoad` + `KeepAlive`
mean it launches on every login and restarts if it ever dies — no manual steps
after reboot.

If the log shows `WARNING: Accessibility not granted`, grant it once:
**System Settings → Privacy & Security → Accessibility → +**, press
`Cmd+Shift+G`, choose `<repo>/bin/dictation-pause`. Takes effect immediately.

## Manage

```bash
tail -f /tmp/dictation-pause.log                                  # live log
launchctl print gui/$(id -u)/com.dts.dictation-pause              # status
launchctl bootout gui/$(id -u)/com.dts.dictation-pause            # stop/disable
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.dts.dictation-pause.plist  # start
```

`launchctl bootout` fully disables it until you bootstrap again.

## Troubleshooting

- **A specific app doesn't pause**: press the physical F8 (play/pause) key
  while that app plays. The agent posts the exact same event — if F8 doesn't
  pause it, no media-key event will. Some Chromium browsers have quirky
  media-session handling; F8 is the first thing to test.
- **Nothing happens at all**: check `tail /tmp/dictation-pause.log` — every
  decision (mic edge, dictation gate, output state) is logged.
- **After rebuilding** (`build.sh`): the ad-hoc code signature changes, so
  re-grant Accessibility, then re-run `install.sh`.

## Tuning

- Process gate: `dictationFragments` in `main.swift` (process-name fragments
  that count as dictation). When a non-dictation app has the mic, the log
  records any speech-ish process names under "speech-ish:" — useful if
  dictation needs a new fragment on a future macOS.
- Timing: `sample1Delay` / `sample2Delay` in `main.swift`.
- Known cosmetic edge: a system alert sound landing exactly during a dictation
  start can cause one unnecessary pause/resume blip. Harmless.

## Files

- `main.swift` — all logic
- `build.sh` — build (swiftc, no dependencies)
- `install.sh` — build + LaunchAgent install/start
- `/tmp/dictation-pause.log` — diagnostic log (auto-truncates at 100 KB)
