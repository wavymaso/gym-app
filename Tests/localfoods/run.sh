#!/bin/bash
set -e
cd "$(dirname "$0")"
G=../../Gym; O=$(mktemp -d)
xcrun swiftc -O -o "$O/t" $G/Calc.swift $G/FoodAPI.swift $G/Micros.swift $G/LocalFoods.swift main.swift
"$O/t" "$1"
