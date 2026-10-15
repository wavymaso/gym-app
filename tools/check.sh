#!/bin/bash
# Build both apps and run every test suite. The gate for every commit: ./tools/check.sh
# Suites that need your real data use a copy of the Mac app's store (never the store itself).
cd "$(dirname "$0")/.."
fail=0
step() { printf "%-16s %s\n" "$1" "$2"; [[ "$2" == *"PASSED"* || "$2" == *"SUCCEEDED"* ]] || fail=1; }

for dest in 'generic/platform=iOS Simulator' 'platform=macOS'; do
  r=$(xcodebuild -project Gym.xcodeproj -scheme Gym -destination "$dest" -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u | head -3)
  step "build ${dest##*=}" "$r"
done

for t in activity-sync distribution budget strategy trendv2 photoai progression undo integrity time tokens coachguard partialdays evidence engine; do
  [ -x Tests/$t/run.sh ] || continue
  step "$t" "$(Tests/$t/run.sh 2>&1 | tail -1)"
done
step localfoods "$(Tests/localfoods/run.sh "$PWD/Gym/foods.sqlite" 2>&1 | tail -1)"

D=~/Library/Containers/com.wavymaso.gym/Data/Library/Application\ Support
if [ -f "$D/default.store" ]; then
  for t in migration backup export; do
    M=$(mktemp -d); cp -p "$D"/default.store* "$M/"
    if [ $t = migration ]; then T=$(sqlite3 "$M/default.store" "select sum(ZKCAL) from ZFOODENTRY"); r=$(Tests/$t/run.sh "$M/default.store" "$T" 2>&1 | tail -1)
    else r=$(Tests/$t/run.sh "$M/default.store" 2>&1 | tail -1); fi
    step "$t" "$r"; rm -rf "$M"
  done
fi
[ $fail = 0 ] && echo "ALL GREEN" || echo "SOMETHING FAILED"
exit $fail
