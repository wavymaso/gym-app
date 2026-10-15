#!/bin/bash
# Builds Gym and installs it on the iPhone (plugged in, or on the same Wi-Fi, unlocked).
# Free Apple developer signing lasts 7 days; run this before it runs out. Prints the new expiry.
set -e
cd "$(dirname "$0")/.."
# Your iPhone: GYM_PHONE=<UDID>, or the first one that's connected or paired.
UDID=${GYM_PHONE:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /iPhone/ && /(available|connected)/ { for (i = 1; i <= NF; i++) if ($i == "(UDID)") print $(i-1) }' | head -1)}
[ -n "$UDID" ] || { echo "No iPhone found. Plug it in, unlock it, trust this Mac, and turn on Developer Mode (Settings → Privacy & Security)."; exit 1; }
[ -f Gym/foods.sqlite ] || echo "warning: Gym/foods.sqlite missing (offline food database); run tools/update-food-db.sh"
echo "Building…"
xcodebuild -project Gym.xcodeproj -scheme Gym -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | sort -u
APP=build/Build/Products/Release-iphoneos/Gym.app
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
for i in 1 2 3; do
  if xcrun devicectl device install app --device "$UDID" "$APP" 2>&1 | grep -q "bundleID: $BUNDLE"; then
    EXP=$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw -)
    SECS=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$EXP" "+%s" 2>/dev/null)
    echo "Installed. Works until $(date -r "$SECS" "+%A %-d %B, %H:%M") (then run this again)."
    exit 0
  fi
  echo "Couldn't reach the iPhone (attempt $i). Is it unlocked and connected?"; sleep 5
done
exit 1
