#!/bin/bash
# A 7-day sample meal plan from a copy of your real data, as plain text (nothing in the app changes).
#   tools/sample-plan.sh                      → plan with your week (set or inferred)
#   tools/sample-plan.sh "2=18:00,7=11:00"    → example training week if you have none (1 = Sunday)
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
cp -p ~/Library/Containers/com.wavymaso.gym/Data/Library/Application\ Support/default.store* "$T/"
Tests/sampleplan/run.sh "$T/default.store" "$@"
rm -rf "$T"
