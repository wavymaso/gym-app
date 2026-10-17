#!/bin/bash
# Planner timing on the iPhone with your real data: installs the current build, launches it with
# -planBench and prints the timings (the app quits after). tools/plan-bench.sh [--no-install]
set -e
cd "$(dirname "$0")/.."
UDID=${GYM_PHONE:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /iPhone/ && /(available|connected)/ { for (i = 1; i <= NF; i++) if ($i == "(UDID)") print $(i-1) }' | head -1)}
[ "$1" = "--no-install" ] || tools/install-phone.sh
APP=build/Build/Products/Release-iphoneos/Gym.app
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
xcrun devicectl device process launch --console --terminate-existing --device "$UDID" "$BUNDLE" -- -planBench 2>&1 | grep PLANBENCH
