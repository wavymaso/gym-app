#!/bin/bash
# Run the expenditure and trend algorithms on your real data and compare with MacroFactor's own
# numbers, in one command (~20 s). Works on a copy of the Mac app's database, never the live one.
#   tools/backtest.sh            → every algorithm's error vs MacroFactor, and recent days side by side
#   tools/backtest.sh full       → the full backtest report (train/test, V1 vs V2)
#   tools/backtest.sh cohere     → which trend should drive both the screens and the targets
cd "$(dirname "$0")/.."
D=~/Library/Containers/com.wavymaso.gym/Data/Library/Application\ Support
M=$(mktemp -d); trap 'rm -rf "$M"' EXIT
cp -p "$D"/default.store* "$M/"
MF="$PWD/.backups/backtest/mf-expenditure.csv"
if [ "$1" = full ]; then Tests/backtest/run.sh "$M/default.store" "$MF"
elif [ "$1" = cohere ]; then COHERE=1 Tests/backtest/run.sh "$M/default.store" "$MF"
else MFCMP=1 Tests/backtest/run.sh "$M/default.store" "$MF"; fi
