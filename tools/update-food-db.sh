#!/bin/bash
# Rebuilds Gym/foods.sqlite from today's Open Food Facts data (about 1,3 GB download, ~25 min):
# Spain, Saudi Arabia and the Gulf, and Costco's Kirkland Signature, with Arabic names.
set -e
cd "$(dirname "$0")/.."
W=.backups/fooddb; mkdir -p "$W"
curl -L -o "$W/off.csv.gz" -A "Gym/1.0 (personal food database)" https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz
python3 tools/build-food-db.py "$W/foods.sqlite" "$W/off.csv.gz"
python3 tools/enrich-from-api.py "$W/foods.sqlite" saudi-arabia sa
python3 tools/enrich-from-api.py "$W/foods.sqlite" united-arab-emirates gcc
python3 tools/finalize-food-db.py "$W/foods.sqlite"
cp "$W/foods.sqlite" Gym/foods.sqlite
echo "Gym/foods.sqlite updated: $(sqlite3 Gym/foods.sqlite 'select count(*) from food') products"
