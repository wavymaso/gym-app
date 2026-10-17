#!/bin/bash
# Builds the simple foods catalogue (Gym/SimpleFoods.json) from foods.sqlite: tools/build-catalog.sh
set -e
cd "$(dirname "$0")"
G=../../Gym; O=$(mktemp -d)
xcrun swiftc -O -o "$O/t" $G/EvidenceRegistry.swift $G/Engine/*.swift $G/Engine/Planner/*.swift $G/SimpleFoods.swift main.swift 2>&1 | grep error: || true
"$O/t" "$@"
