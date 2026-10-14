#!/bin/bash
set -e
cd "$(dirname "$0")"
G=../../Gym; O=$(mktemp -d)
xcrun swiftc -o "$O/t" $G/Calc.swift $G/Models.swift $G/Food.swift $G/FoodAPI.swift $G/Micros.swift $G/GymModels.swift $G/GymCalc.swift \
  $G/Trend.swift $G/Progress.swift $G/Sync.swift $G/SyncServer.swift $G/Activity.swift $G/Theme.swift $G/FoodLogView.swift $G/Export.swift \
  $G/AddFoodView.swift $G/FoodEditors.swift $G/LabelScanner.swift $G/RecipeImport.swift $G/MicrosView.swift $G/PhoneOnly.swift $G/Setup.swift main.swift 2>&1 | grep -E "error" | head -5
"$O/t" "$1"
