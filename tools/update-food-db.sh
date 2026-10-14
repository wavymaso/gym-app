#!/bin/bash
# Rebuilds Gym/foods.sqlite from today's Open Food Facts data (about 1,3 GB download, ~25 min):
# Spain, Saudi Arabia and the Gulf, and Costco's Kirkland Signature, with Arabic names; plus USDA generic foods.
set -e
cd "$(dirname "$0")/.."
W=.backups/fooddb; mkdir -p "$W"
curl -L -o "$W/off.csv.gz" -A "Gym/1.0 (personal food database)" https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz
python3 tools/build-food-db.py "$W/foods.sqlite" "$W/off.csv.gz"
python3 tools/enrich-from-api.py "$W/foods.sqlite" saudi-arabia sa
python3 tools/enrich-from-api.py "$W/foods.sqlite" united-arab-emirates gcc
python3 tools/finalize-food-db.py "$W/foods.sqlite"
# USDA's generic foods and dishes (public domain), for photo logging
U=.backups/usda; mkdir -p "$U"
for f in FoodData_Central_sr_legacy_food_csv_2018-04 FoodData_Central_survey_food_csv_2024-10-31 FoodData_Central_foundation_food_csv_2025-04-24; do
  [ -d "$U/x/$f" ] || { curl -sL -o "$U/$f.zip" "https://fdc.nal.usda.gov/fdc-datasets/$f.zip"; mkdir -p "$U/x/$f"; ditto -x -k "$U/$f.zip" "$U/x/$f"; }
done
python3 tools/build-generic-db.py "$U/x" "$W/foods.sqlite"
python3 tools/build-search-extras.py "$W/foods.sqlite"     # Spanish names for USDA, Arabic folding, typo vocabulary
cp "$W/foods.sqlite" Gym/foods.sqlite
echo "Gym/foods.sqlite updated: $(sqlite3 Gym/foods.sqlite 'select count(*) from food') products"
