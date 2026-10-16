#!/bin/bash
set -e
cd "$(dirname "$0")"
G=../../Gym; O=$(mktemp -d)
xcrun swiftc -O -o "$O/t" $G/Calc.swift $G/FoodAPI.swift $G/Log.swift $G/Micros.swift $G/LocalFoods.swift $G/Engine/Planner/Taxonomy.swift $G/Engine/Planner/PlanRules.swift $G/Engine/Planner/Planner.swift $G/Engine/Planner/EatingProfile.swift $G/Engine/EngineTypes.swift $G/EvidenceRegistry.swift main.swift
"$O/t" "$1"
