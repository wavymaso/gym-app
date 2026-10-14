#!/bin/bash
set -e
cd "$(dirname "$0")"
G=../../Gym; O=$(mktemp -d)
python3 -c "s=open('$G/LabelScanner.swift').read(); open('$O/reader.swift','w').write(s[:s.index('/// Pick or take a photo')])"
xcrun swiftc -o "$O/t" $G/Calc.swift $G/FoodAPI.swift $G/Micros.swift "$O/reader.swift" main.swift
"$O/t"
