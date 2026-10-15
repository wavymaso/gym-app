#!/bin/bash
set -e
cd "$(dirname "$0")"
O=$(mktemp -d)
xcrun swiftc -O -o "$O/t" ../../Gym/Trend.swift ../../Gym/Engine/EngineTypes.swift ../../Gym/Engine/EngineTrend.swift ../../Gym/Calc.swift main.swift
"$O/t" "$@"
