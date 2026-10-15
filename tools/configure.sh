#!/bin/bash
# Make this checkout yours: your Apple team and your own bundle ID (each person needs their own).
#   tools/configure.sh ABCDE12345 com.yourname.gym
# Find your team ID in Xcode → Settings → Accounts → (your Apple ID) → team, or developer.apple.com → Membership.
set -euo pipefail
cd "$(dirname "$0")/.."
TEAM=${1:?usage: tools/configure.sh TEAMID com.yourname.gym}
BUNDLE=${2:?usage: tools/configure.sh TEAMID com.yourname.gym}
[[ "$BUNDLE" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Bundle ID: letters, digits, dots and dashes only"; exit 1; }
P=Gym.xcodeproj/project.pbxproj
OLD_TEAM=$(grep -m1 -E '^\s*DEVELOPMENT_TEAM = [A-Z0-9]+;' $P | sed -E 's/.*= ([A-Z0-9]+);/\1/')
OLD_BUNDLE=$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER = ' $P | sed -E 's/.*= ([^;]+);/\1/')
echo "Team $OLD_TEAM → $TEAM, bundle $OLD_BUNDLE → $BUNDLE"
FILES=$(grep -rlE "$OLD_TEAM|${OLD_BUNDLE//./\\.}" $P *.entitlements GymWidget-Info.plist Gym/*.swift GymWidget/*.swift tools/*.sh 2>/dev/null | sort -u)
for f in $FILES; do
  sed -i '' -e "s/$OLD_TEAM/$TEAM/g" -e "s/${OLD_BUNDLE//./\\.}/$BUNDLE/g" "$f"
done
echo "Updated: $(echo $FILES | wc -w | tr -d ' ') files. Now: tools/get-food-db.sh, then tools/install-mac.sh and tools/install-phone.sh"
