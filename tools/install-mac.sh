#!/bin/bash
# Builds Gym for the Mac, backs up your data, and replaces /Applications/Gym.app.
# Stops (without touching anything) if the running app won't quit, e.g. a sheet is open.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Gym.xcodeproj -scheme Gym -configuration Release -destination 'platform=macOS' -derivedDataPath build build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
APP=build/Build/Products/Release/Gym.app
[ -d "$APP" ] || { echo "No build."; exit 1; }
osascript -e 'tell application id "com.wavymaso.gym" to quit' >/dev/null 2>&1 || true
for i in 1 2 3 4 5; do pgrep -f "/Applications/Gym.app/Contents/MacOS/Gym" >/dev/null || break; sleep 2; done
if pgrep -f "/Applications/Gym.app/Contents/MacOS/Gym" >/dev/null; then
  echo "Gym didn't quit (an open sheet or dialog?). Close it in the app and run this again. Nothing was changed."; exit 1
fi
D="$HOME/Library/Containers/com.wavymaso.gym/Data/Library/Application Support"
B=".backups/before-install-$(date +%Y%m%d-%H%M)"; mkdir -p "$B"; cp -p "$D"/default.store* "$B"/
rm -rf /Applications/Gym.app && ditto "$APP" /Applications/Gym.app && open /Applications/Gym.app
echo "Installed. Data backed up to $B."
