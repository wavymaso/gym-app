#!/bin/bash
# Before/after proof for UI passes: seven screens (Today, Food log, Plan, swap sheet, Workout, Weight,
# Settings) in Dark-Titanium, Light-Titanium and Black-Gold, in the simulator with demo data.
#   tools/proof-snapshots.sh before          → .backups/proof/before/
#   tools/proof-snapshots.sh after           → .backups/proof/after/
#   tools/proof-snapshots.sh grid            → PROOF-<theme>.png: before | after side by side, per screen
set -e
cd "$(dirname "$0")/.."
S=${SIM:-EEC525B0-A6E7-4500-A3E5-C7215EBB1EF1}
if [ "$1" = grid ]; then
  xcrun swiftc -o .backups/proof/grid tools/proof-grid.swift 2>&1 | grep error: || true
  .backups/proof/grid .backups/proof; exit
fi
OUT=.backups/proof/${1:?before or after}; mkdir -p "$OUT"
xcrun simctl boot $S 2>/dev/null || true
xcodebuild -project Gym.xcodeproj -scheme Gym -destination 'generic/platform=iOS Simulator' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
xcrun simctl install $S build/Build/Products/Debug-iphonesimulator/Gym.app
shot() {   # appearance finish name args…
  local a=$1 f=$2 n=$3; shift 3
  xcrun simctl terminate $S com.wavymaso.gym 2>/dev/null || true
  xcrun simctl launch $S com.wavymaso.gym -inMemory YES -demo YES -macAddress x -macCode "" -whatsNewSeen 99 -noPrompts YES -appearance $a -finish $f "$@" >/dev/null
  sleep ${WAIT:-8}
  xcrun simctl io $S screenshot "$OUT/$a-$f-$n.png" >/dev/null 2>&1
}
for t in dark:titanium light:titanium black:gold; do
  a=${t%%:*}; f=${t##*:}
  shot $a $f today -page dashboard
  shot $a $f food -page food -phoneLogStyle timeline
  shot $a $f plan -page food -phoneLogStyle plan
  shot $a $f swap -page food -phoneLogStyle plan -openPlanItem YES
  shot $a $f workout -page workouts -activeWorkout YES
  shot $a $f weight -insight weightTrend
  shot $a $f settings -page settings
done
echo "saved in $OUT"
