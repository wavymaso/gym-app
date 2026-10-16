#!/usr/bin/env python3
"""Adds the food taxonomy inputs to foods.sqlite, offline:
  food:    nova (NOVA group 1-4 from Open Food Facts), pnns2 (OFF food group), cats (a few category tags)
  generic: category (USDA food category / WWEIA group)

    python3 build-taxonomy-db.py <foods.sqlite> <off.csv.gz> <unzipped FDC folder>
"""
import csv, glob, gzip, io, os, sqlite3, sys
db, offpath, fdc = sys.argv[1], sys.argv[2], sys.argv[3]
con = sqlite3.connect(db)
cols = {r[1] for r in con.execute("pragma table_info(food)")}
for c, t in [("nova", "INTEGER"), ("pnns2", "TEXT"), ("cats", "TEXT")]:
    if c not in cols: con.execute(f"alter table food add column {c} {t}")
gcols = {r[1] for r in con.execute("pragma table_info(generic)")}
if "category" not in gcols: con.execute("alter table generic add column category TEXT")
codes = {r[0] for r in con.execute("select code from food")}
csv.field_size_limit(1 << 30)
n = 0
with gzip.open(offpath, "rt", encoding="utf-8", errors="replace", newline="") as f:
    for row in csv.DictReader(f, delimiter="\t"):
        code = row.get("code") or ""
        if code not in codes: continue
        nova = row.get("nova_group") or ""
        nova = int(float(nova)) if nova.strip() else None
        pn = (row.get("pnns_groups_2") or "").strip() or None
        cats = ",".join([c for c in (row.get("categories_tags") or "").split(",") if c][-4:]) or None
        con.execute("update food set nova=?, pnns2=?, cats=? where code=?", (nova, pn, cats, code)); n += 1
con.commit()
print("food rows with taxonomy:", n, "with NOVA:", con.execute("select count(*) from food where nova is not null").fetchone()[0])
# USDA categories: SR Legacy / Foundation food_category, FNDDS WWEIA category.
cat_names = {}
for p in glob.glob(os.path.join(fdc, "**", "food_category.csv"), recursive=True):
    for r in csv.DictReader(open(p, encoding="utf-8")): cat_names["c" + r["id"]] = r["description"]
for p in glob.glob(os.path.join(fdc, "**", "wweia_food_category.csv"), recursive=True):
    for r in csv.DictReader(open(p, encoding="utf-8")): cat_names["w" + r["wweia_food_category"]] = r["wweia_food_category_description"]
fdcs = {r[0] for r in con.execute("select fdc from generic")}
m = 0
for p in glob.glob(os.path.join(fdc, "**", "food.csv"), recursive=True):
    for r in csv.DictReader(open(p, encoding="utf-8")):
        try: i = int(r["fdc_id"])
        except ValueError: continue
        if i not in fdcs: continue
        cat = r.get("food_category_id") or ""
        name = cat_names.get("c" + cat) or cat_names.get("w" + cat)
        if name: con.execute("update generic set category=? where fdc=?", (name, i)); m += 1
con.commit()
print("generic rows with a category:", m)
