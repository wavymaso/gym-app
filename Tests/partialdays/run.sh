#!/bin/bash
set -e
cd "$(dirname "$0")"
O=$(mktemp -d)
cp ../../Gym/PartialDays.swift "$O/pd.swift"
xcrun swiftc -o "$O/t" "$O/pd.swift" main.swift 2>&1 | grep error: || true
"$O/t"
