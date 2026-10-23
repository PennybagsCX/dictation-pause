#!/bin/bash
# Builds the dictation-pause LaunchAgent binary.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p bin
swiftc -O main.swift -o bin/dictation-pause
codesign --force --sign - bin/dictation-pause
echo "built bin/dictation-pause"
echo "NOTE: if Accessibility was granted to a previous build, re-grant it for the new binary (rebuilds get a new ad-hoc signature)."
