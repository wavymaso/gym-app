#!/bin/bash
# Builds the model/sync code with this test and runs it.
set -e
cd "$(dirname "$0")"
G=../../Gym
O=$(mktemp -d)
xcrun swiftc -o "$O/t" $G/Calc.swift $G/Models.swift $G/Food.swift $G/FoodAPI.swift $G/Micros.swift $G/GymModels.swift $G/GymCalc.swift \
  $G/Trend.swift $G/Progress.swift $G/Sync.swift $G/SyncServer.swift $G/Activity.swift $G/Theme.swift main.swift
"$O/t"
