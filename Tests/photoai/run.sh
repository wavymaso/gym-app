#!/bin/bash
# Usage: run.sh [photo.jpg ...]   (photos need Ollama running with the vision model)
set -e
cd "$(dirname "$0")"
export FOODS="$PWD/../../Gym/foods.sqlite"
G=../../Gym; O=$(mktemp -d)
xcrun swiftc -o "$O/t" $G/Calc.swift $G/Models.swift $G/Food.swift $G/FoodAPI.swift $G/Log.swift $G/Micros.swift $G/GymModels.swift $G/GymCalc.swift \
  $G/Trend.swift $G/Progress.swift $G/Sync.swift $G/Body.swift $G/Supplements.swift $G/Phases.swift $G/SyncServer.swift $G/Activity.swift $G/Design.swift $G/Meals.swift $G/Theme.swift $G/Tokens.swift $G/LocalFoods.swift $G/SyncClient.swift $G/WidgetData.swift $G/PhotoAI.swift $G/Secrets.swift main.swift 2>&1 | grep -E "error" | head -8
"$O/t" "$@"
