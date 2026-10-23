#!/bin/bash
# Builds and installs the dictation-pause LaunchAgent for the current user.
# Clone the repo anywhere; the agent will point at this checkout's binary.
set -euo pipefail
cd "$(dirname "$0")"
REPO_DIR="$(pwd)"
./build.sh

PLIST="$HOME/Library/LaunchAgents/com.dts.dictation-pause.plist"
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.dts.dictation-pause</string>
	<key>ProgramArguments</key>
	<array>
		<string>$REPO_DIR/bin/dictation-pause</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ProcessType</key>
	<string>Adaptive</string>
	<key>StandardOutPath</key>
	<string>/tmp/dictation-pause.launchd.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/dictation-pause.launchd.log</string>
</dict>
</plist>
EOF

# Stop an already-loaded instance first (no-op on fresh installs).
launchctl bootout gui/$(id -u)/com.dts.dictation-pause 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PLIST"

echo
echo "installed and started (RunAtLoad + KeepAlive: launches on every login, restarts if it dies)"
echo "log:  tail -f /tmp/dictation-pause.log"
echo
echo "If the log shows 'WARNING: Accessibility not granted', grant it once:"
echo "  System Settings → Privacy & Security → Accessibility → + →"
echo "  press Cmd+Shift+G and choose: $REPO_DIR/bin/dictation-pause"
