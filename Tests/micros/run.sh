#!/bin/bash
set -e
cd "$(dirname "$0")"
G=../../Gym; O=$(mktemp -d)
xcrun swiftc -o "$O/t" $G/Calc.swift $G/FoodAPI.swift $G/Micros.swift main.swift
"$O/t"
