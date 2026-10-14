#!/bin/bash
# Tests distribute() from Models.swift on its own (with a stand-in Targets).
set -e
cd "$(dirname "$0")"
O=$(mktemp -d)
echo 'struct Targets: Equatable { var kcal: Double; var protein: Double; var fat: Double; var carbs: Double }' > "$O/stub.swift"
python3 -c "s=open('../../Gym/Models.swift').read(); open('$O/dist.swift','w').write(s[s.index('/// Keeps the week'):])"
xcrun swiftc -o "$O/t" "$O/stub.swift" "$O/dist.swift" main.swift
"$O/t"
