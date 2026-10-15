#!/bin/bash
# Downloads the ready-made offline food database (Gym/foods.sqlite, ~50 MB) from the repo's
# releases. To build it yourself instead (1,3 GB download, ~25 min): tools/update-food-db.sh
set -e
cd "$(dirname "$0")/.."
command -v gh >/dev/null || { echo "Needs the GitHub CLI: brew install gh, then gh auth login"; exit 1; }
gh release download food-db --pattern foods.sqlite --dir Gym --clobber
echo "Gym/foods.sqlite: $(sqlite3 Gym/foods.sqlite 'select count(*) from food') products"
