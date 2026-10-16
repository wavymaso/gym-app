#!/bin/bash
# The food taxonomy review list from a copy of your real data (nothing in the app changes).
#   tools/taxonomy-review.sh        rules, database groups and NOVA, your corrections
#   tools/taxonomy-review.sh --ai   also asks the local model about uncertain foods
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
cp -p ~/Library/Containers/com.wavymaso.gym/Data/Library/Application\ Support/default.store* "$T/"
GYM_FOODS_DB="$PWD/Gym/foods.sqlite" Tests/taxonomy/run.sh "$T/default.store" "$@"
rm -rf "$T"
