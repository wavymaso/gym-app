#!/usr/bin/env python3
"""Add USDA's generic foods (SR Legacy, FNDDS survey dishes, Foundation) to foods.sqlite,
offline, for photo logging and search. Public domain data from FoodData Central.

Usage: build-generic-db.py <unzipped FDC folder containing the three *_csv_* folders> <foods.sqlite>
"""
import csv, glob, os, sqlite3, sys

src, dbpath = sys.argv[1], sys.argv[2]
MICROS = {1092: "potassium", 1087: "calcium", 1090: "magnesium", 1089: "iron", 1095: "zinc", 1162: "vitC", 1114: "vitD",
          1106: "vitA", 1109: "vitE", 1185: "vitK", 1178: "b12", 1177: "folate", 1253: "cholesterol", 1057: "caffeine", 1018: "alcohol"}
WANT = {1003, 1004, 1005, 1008, 2047, 2048, 1079, 2000, 1063, 1258, 1093} | set(MICROS)
csv.field_size_limit(1 << 30)

def folder(pattern):
    hits = [p for p in glob.glob(os.path.join(src, "**", pattern), recursive=True) if os.path.isdir(p)]
    if not hits: sys.exit(f"missing {pattern}")
    return sorted(hits)[-1]

foods = {}   # fdc -> dict
for pattern, kinds, kind in [("*sr_legacy_food_csv*", {"sr_legacy_food"}, "sr"),
                             ("*survey_food_csv*", {"survey_fndds_food"}, "dish"),
                             ("*foundation_food_csv*", {"foundation_food"}, "foundation")]:
    d = folder(pattern)
    while not os.path.exists(os.path.join(d, "food.csv")):
        d = os.path.join(d, os.listdir(d)[0])
    ids = set()
    for r in csv.DictReader(open(os.path.join(d, "food.csv"), encoding="utf-8")):
        # Skip baby food, US fast-food and restaurant chains, branded and lab entries.
        if r["data_type"] == "sr_legacy_food" and r.get("food_category_id") in ("3", "21", "24", "25", "26", "27"): continue
        if r["data_type"] in kinds:
            foods[int(r["fdc_id"])] = {"name": r["description"], "kind": kind, "n": {}, "portions": [], "typical": None}
            ids.add(int(r["fdc_id"]))
    # FNDDS files use the old nutrient numbers (203 = protein); map them to ids (1003).
    by_nbr = {}
    for r in csv.DictReader(open(os.path.join(d, "nutrient.csv"), encoding="utf-8")):
        nbr = (r.get("nutrient_nbr") or "").strip()
        if nbr.endswith(".0"): nbr = nbr[:-2]
        if nbr.isdigit() and int(nbr) not in by_nbr: by_nbr[int(nbr)] = int(r["id"])   # 205.2 is not 205 (carbs)
    for r in csv.DictReader(open(os.path.join(d, "food_nutrient.csv"), encoding="utf-8")):
        fid = int(r["fdc_id"]); nid = int(r["nutrient_id"])
        if kind == "dish" and nid < 1000: nid = by_nbr.get(nid, nid)
        if fid in ids and nid in WANT and r["amount"] not in ("", None):
            foods[fid]["n"][nid] = float(r["amount"])
    units = {}
    mu = os.path.join(d, "measure_unit.csv")
    if os.path.exists(mu):
        units = {r["id"]: r["name"] for r in csv.DictReader(open(mu, encoding="utf-8"))}
    for r in csv.DictReader(open(os.path.join(d, "food_portion.csv"), encoding="utf-8")):
        fid = int(r["fdc_id"])
        if fid not in ids: continue
        try: g = float(r["gram_weight"] or 0)
        except ValueError: continue
        if g <= 0: continue
        label = (r.get("portion_description") or "").strip()
        if not label:
            unit = units.get(r.get("measure_unit_id", ""), "")
            label = " ".join(x for x in [r.get("amount", "").rstrip("0").rstrip(".") if r.get("amount") else "", unit if unit != "undetermined" else "", r.get("modifier", "")] if x).strip()
        if label == "Quantity not specified":
            foods[fid]["typical"] = g          # FNDDS: the usual amount people eat
        elif label and len(foods[fid]["portions"]) < 4:
            foods[fid]["portions"].append((label.replace(";", ",").replace("=", "-"), g))
    print(kind, len(ids), "with protein:", sum(1 for i in ids if 1003 in foods[i]["n"]))

db = sqlite3.connect(dbpath)
db.executescript("""
DROP TABLE IF EXISTS generic; DROP TABLE IF EXISTS generic_fts;
CREATE TABLE generic (fdc INTEGER PRIMARY KEY, name TEXT, kind TEXT, kcal REAL, protein REAL, fat REAL, carbs REAL,
  fiber REAL, sugar REAL, satfat REAL, sodium REAL, micros TEXT, portions TEXT, typical_g REAL);
CREATE VIRTUAL TABLE generic_fts USING fts5(name, content='generic', content_rowid='fdc', tokenize='unicode61 remove_diacritics 2');
""")
n = 0
for fid, f in foods.items():
    x = f["n"]
    if not all(k in x for k in (1003, 1004, 1005)): continue
    kcal = x.get(1008) or x.get(2048) or x.get(2047) or (4 * x[1003] + 4 * x[1005] + 9 * x[1004])
    micros = ";".join(f"{MICROS[k]}={round(v, 3)}" for k, v in x.items() if k in MICROS)
    portions = ";".join(f"{l}={round(g, 1)}" for l, g in f["portions"])
    db.execute("INSERT INTO generic VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
               (fid, f["name"], f["kind"], round(kcal, 1), x[1003], x[1004], x[1005], x.get(1079), x.get(2000) or x.get(1063),
                x.get(1258), x.get(1093), micros or None, portions or None, f["typical"]))
    n += 1
db.execute("INSERT INTO generic_fts(rowid, name) SELECT fdc, name FROM generic")
db.execute("INSERT OR REPLACE INTO meta VALUES ('generic', ?)", (str(n),))
db.commit()
db.execute("VACUUM")
print("generic foods:", n, "size", os.path.getsize(dbpath) // 1048576, "MB")
