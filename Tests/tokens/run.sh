#!/bin/bash
set -e
cd "$(dirname "$0")"
G=../../Gym; O=$(mktemp -d)
xcrun swiftc -o "$O/t" $G/Tokens.swift main.swift 2>&1 | grep error: || true
"$O/t" "$@"
