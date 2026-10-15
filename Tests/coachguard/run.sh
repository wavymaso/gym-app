#!/bin/bash
set -e
cd "$(dirname "$0")"
O=$(mktemp -d)
xcrun swiftc -o "$O/t" ../../Gym/CoachGuard.swift main.swift 2>&1 | grep error: || true
"$O/t"
