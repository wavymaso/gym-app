#!/bin/bash
# Checks the Evidence Registry and writes EVIDENCE.md from it (run.sh write).
set -e
cd "$(dirname "$0")"
O=$(mktemp -d)
xcrun swiftc -o "$O/t" ../../Gym/EvidenceRegistry.swift main.swift 2>&1 | grep error: || true
"$O/t" "$@"
