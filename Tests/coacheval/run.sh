#!/bin/bash
# The coach's evaluation suite: 30+ scenario snapshots. Always: templates valid, validator catches bad
# messages. With EVAL_LIVE=1 (and GEMINI_KEY or a running Ollama): asks the real model for each
# scenario and grades it. Run it whenever the prompt or model changes.
set -e
cd "$(dirname "$0")"
G=../../Gym; O=$(mktemp -d)
xcrun swiftc -O -o "$O/t" $G/Coach/*.swift scenarios.swift main.swift 2>&1 | grep error: || true
"$O/t"
