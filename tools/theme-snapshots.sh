#!/bin/bash
# Screenshots every distinct Appearance × Finish (15) on five screens (Today, Food log, Workout,
# Weight, Settings) in the simulator, and lays them out in one grid: THEME-SNAPSHOTS.png.
# Uses demo data (in memory). Takes ~12 minutes.
set -e
cd "$(dirname "$0")/.."
S=${SIM:-EEC525B0-A6E7-4500-A3E5-C7215EBB1EF1}
OUT=.backups/theme-shots; mkdir -p "$OUT"
xcodebuild -project Gym.xcodeproj -scheme Gym -destination 'generic/platform=iOS Simulator' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
xcrun simctl install $S build/Build/Products/Debug-iphonesimulator/Gym.app
shot() {   # appearance finish name args…
  local a=$1 f=$2 n=$3; shift 3
  xcrun simctl terminate $S com.wavymaso.gym 2>/dev/null || true
  xcrun simctl launch $S com.wavymaso.gym -inMemory YES -demo YES -macAddress x -macCode "" -whatsNewSeen 99 -appearance $a -finish $f "$@" >/dev/null
  sleep 7
  xcrun simctl io $S screenshot "$OUT/$a-$f-$n.png" >/dev/null 2>&1
}
for a in light dark black; do
  for f in titanium silver graphite gold roseGold; do
    shot $a $f today -page dashboard
    shot $a $f food -page food
    shot $a $f workout -page workouts -activeWorkout YES
    shot $a $f weight -insight weightTrend
    shot $a $f settings -page settings
  done
done
xcrun swiftc -o "$OUT/grid" tools/snapshot-grid.swift 2>&1 | grep error: || true
"$OUT/grid" "$OUT" THEME-SNAPSHOTS.png
