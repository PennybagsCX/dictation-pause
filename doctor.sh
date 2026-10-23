#!/bin/bash
# doctor.sh — self-check + repair for dictation-pause.
# Runs via the com.dts.dictation-pause-doctor LaunchAgent (every 12 h) or manually.
# Auto-repairs what is safe (rebuild, re-register agent) and posts a macOS
# notification when a human action is needed (Accessibility grants, broken
# detection after a macOS update).

set -uo pipefail
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.dts.dictation-pause"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="/tmp/dictation-pause.log"
PROBLEMS=()

notify() {
  osascript -e "display notification \"$1\" with title \"dictation-pause\" subtitle \"action needed\" sound name \"Ping\"" 2>/dev/null
}

# 1. Binary exists (rebuild if it vanished)
if [[ ! -x "$REPO_DIR/bin/dictation-pause" ]]; then
  echo "binary missing — rebuilding"
  "$REPO_DIR/build.sh" >/dev/null 2>&1 || PROBLEMS+=("binary missing and rebuild failed")
fi

# 2. LaunchAgent plist exists
if [[ ! -f "$PLIST" ]]; then
  PROBLEMS+=("LaunchAgent plist missing — run $REPO_DIR/install.sh")
fi

# 3. Agent loaded and running (re-bootstrap if not)
if ! launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -q "state = running"; then
  [[ -f "$PLIST" ]] && launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null
  sleep 2
  launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | grep -q "state = running" \
    || PROBLEMS+=("agent is not running")
fi

# 4. Accessibility: check the LATEST startup block in the log (a grant applies
# live, so only the newest block's warning matters)
if [[ -f "$LOG" ]]; then
  last_block=$(awk '/--- dictation-pause/{buf=""; found=1} found{buf=buf $0 "\n"} END{printf "%s", buf}' "$LOG")
  if grep -q "WARNING: Accessibility not granted" <<<"$last_block"; then
    PROBLEMS+=("Accessibility grant missing — System Settings → Privacy & Security → Accessibility → re-add $REPO_DIR/bin/dictation-pause")
  fi
fi

# 5. Staleness: no log writes in 21 days usually means dictation detection
# broke (e.g. after a macOS update changed the indicator signal)
if [[ -f "$LOG" ]]; then
  age_days=$(( ($(date +%s) - $(stat -f %m "$LOG")) / 86400 ))
  if [[ $age_days -ge 21 ]]; then
    PROBLEMS+=("no activity logged in ${age_days} days — detection may be broken after a macOS update; see $REPO_DIR/README.md and $REPO_DIR/diagnostics/")
  fi
else
  PROBLEMS+=("log file missing at $LOG — agent may never have started successfully")
fi

if [[ ${#PROBLEMS[@]} -gt 0 ]]; then
  msg=$(printf '%s; ' "${PROBLEMS[@]}")
  echo "PROBLEMS: $msg"
  notify "${PROBLEMS[0]}${PROBLEMS[1]:+ — and more} — fix guide: ~/dev/dictation-pause/README.md or github.com/PennybagsCX/dictation-pause"
  exit 1
fi
echo "all checks passed"
