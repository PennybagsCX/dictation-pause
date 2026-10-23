#!/bin/bash
# Streams DictationIM / speech daemon logs to a file (quoting kept out of the shell).
exec /usr/bin/log stream --style compact --level default \
  --predicate 'processImagePath CONTAINS "DictationIM" OR processImagePath CONTAINS "localspeechrecognition" OR processImagePath CONTAINS "speechrecognitiond"' \
  > /tmp/dict-logstream2.log 2>&1
