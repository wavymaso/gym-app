#!/bin/bash
set -e
cd "$(dirname "$0")"
O=$(mktemp -d)
xcrun swiftc -o "$O/t" ../../Gym/Calc.swift ../../Gym/GymCalc.swift main.swift
"$O/t"
