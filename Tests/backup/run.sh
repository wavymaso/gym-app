#!/bin/bash
set -e
cd "$(dirname "$0")"
G=../../Gym; O=$(mktemp -d)
xcrun swiftc -o "$O/t" $G/Calc.swift $G/Models.swift $G/EngineAdapter.swift $G/Coach/*.swift $G/Engine/*.swift $G/EvidenceRegistry.swift $G/Food.swift $G/FoodAPI.swift $G/Micros.swift $G/GymModels.swift $G/GymCalc.swift \
  $G/Trend.swift $G/Progress.swift $G/Sync.swift $G/Body.swift $G/Supplements.swift $G/Phases.swift $G/SyncServer.swift $G/LocalFoods.swift $G/SyncClient.swift $G/WidgetData.swift $G/PhotoAI.swift $G/Secrets.swift $G/Activity.swift $G/Design.swift $G/Meals.swift $G/PartialDays.swift $G/Theme.swift $G/Tokens.swift $G/MetalTexture.swift $G/Backup.swift $G/Log.swift main.swift 2>&1 | grep error || true
"$O/t" "$1"
