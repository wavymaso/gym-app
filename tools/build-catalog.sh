#!/bin/bash
# Rebuilds the simple foods catalogue (Gym/SimpleFoods.json) from Gym/foods.sqlite and prints it.
set -e
cd "$(dirname "$0")/.."
Tests/catalog/run.sh "$PWD/Gym/foods.sqlite" "$PWD/Gym/SimpleFoods.json"
