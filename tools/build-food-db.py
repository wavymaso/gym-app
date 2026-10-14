#!/usr/bin/env python3
"""Builds Gym's offline food database (foods.sqlite) from Open Food Facts.

Streams the public CSV export (https://world.openfoodfacts.org/data, ODbL licence),
keeps products sold in the chosen countries that have nutrition facts, and writes a
compact SQLite file with a full-text index on name and brand.

    python3 build-food-db.py <out.sqlite> [csv.gz path or URL]
"""
import csv, gzip, io, os, re, sqlite3, sys, time, urllib.request, unicodedata

URL = "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"
COUNTRIES = {"en:spain": "es", "en:saudi-arabia": "sa",
             # the rest of the Gulf: largely the same shelves as Saudi Arabia
             "en:united-arab-emirates": "gcc", "en:kuwait": "gcc", "en:qatar": "gcc", "en:bahrain": "gcc", "en:oman": "gcc"}
STORE_KEYS = {"alcampo": "alcampo", "auchan": "alcampo", "producto alcampo": "alcampo", "rik&rok": "alcampo", "cosmia": "alcampo", "costco": "costco", "mercadona": "mercadona", "carrefour": "carrefour",
              "lidl": "lidl", "dia": "dia", "eroski": "eroski", "danube": "danube", "panda": "panda", "tamimi": "tamimi",
              "lulu": "lulu", "othaim": "othaim", "al othaim": "othaim", "hyperpanda": "panda"}
MICROS = {"potassium": ("potassium_100g", 1e3), "calcium": ("calcium_100g", 1e3), "magnesium": ("magnesium_100g", 1e3),
          "iron": ("iron_100g", 1e3), "zinc": ("zinc_100g", 1e3), "vitC": ("vitamin-c_100g", 1e3), "vitD": ("vitamin-d_100g", 1e6),
          "vitA": ("vitamin-a_100g", 1e6), "vitE": ("vitamin-e_100g", 1e3), "vitK": ("vitamin-k_100g", 1e6),
          "b12": ("vitamin-b12_100g", 1e6), "folate": ("vitamin-b9_100g", 1e6), "cholesterol": ("cholesterol_100g", 1e3),
          "caffeine": ("caffeine_100g", 1e3), "alcohol": ("alcohol_100g", 0.789)}      # alcohol: % vol → g per 100 ml

def num(row, k):
    v = row.get(k) or ""
    if not v: return None
    try:
        x = float(v.replace(",", "."))
        return x if x == x and 0 <= x < 1e6 else None
    except ValueError:
        return None

def fold(s):
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c))

def stores(row):
    text = fold((row.get("stores") or "") + "," + (row.get("brands") or ""))
    found = {v for k, v in STORE_KEYS.items() if re.search(r"(^|[,\s])" + re.escape(k) + r"([,\s]|$)", text)}
    if "kirkland" in text: found.add("costco")
    return ",".join(sorted(found))

def main():
    out = sys.argv[1]
    src = sys.argv[2] if len(sys.argv) > 2 else URL
    if os.path.exists(out): os.remove(out)
    db = sqlite3.connect(out)
    db.executescript("""
        PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;
        CREATE TABLE food(code TEXT PRIMARY KEY, name TEXT NOT NULL, name_ar TEXT, brand TEXT, countries TEXT, stores TEXT,
            kcal REAL, protein REAL, fat REAL, carbs REAL, fiber REAL, sugar REAL, satfat REAL, sodium REAL,
            serving_g REAL, serving TEXT, liquid INTEGER, micros TEXT, scans INTEGER);
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
    """)
    raw = urllib.request.urlopen(urllib.request.Request(src, headers={"User-Agent": "Gym/1.0 (personal food database)"})) \
        if src.startswith("http") else open(src, "rb")
    text = io.TextIOWrapper(gzip.GzipFile(fileobj=raw), encoding="utf-8", errors="replace", newline="")
    csv.field_size_limit(10_000_000)
    reader = csv.DictReader(text, delimiter="\t")
    seen = kept = 0
    t0 = time.time()
    batch = []
    for row in reader:
        seen += 1
        if seen % 250_000 == 0:
            print(f"  {seen:,} rows read, {kept:,} kept, {time.time()-t0:.0f}s", flush=True)
        ct = row.get("countries_tags") or ""
        cs = sorted({c for tag, c in COUNTRIES.items() if tag in ct})
        if not cs and "kirkland" in fold(row.get("brands") or ""): cs = ["costco"]     # Costco Spain's own brand, wherever it was added
        if not cs: continue
        name = (row.get("product_name") or "").strip()
        code = (row.get("code") or "").strip()
        if not name or not code: continue
        p, f, c = num(row, "proteins_100g"), num(row, "fat_100g"), num(row, "carbohydrates_100g")
        if p is None and f is None and c is None: continue
        kcal = num(row, "energy-kcal_100g")
        if kcal is None:
            kj = num(row, "energy-kj_100g") or num(row, "energy_100g")
            kcal = kj / 4.184 if kj is not None else (p or 0) * 4 + (c or 0) * 4 + (f or 0) * 9
        if kcal > 950 or (p or 0) > 100 or (f or 0) > 100 or (c or 0) > 100: continue      # broken entries
        micros = []
        for k, (col, scale) in MICROS.items():
            v = num(row, col)
            if v is not None and v > 0: micros.append(f"{k}={v*scale:.4g}")
        qty = (row.get("quantity") or "").lower()
        liquid = 1 if re.search(r"\d\s*(ml|cl|l)\b", qty) else 0
        sod = num(row, "sodium_100g")
        batch.append((code, name, None, (row.get("brands") or "").split(",")[0].strip() or None, ",".join(cs), stores(row),
                      round(kcal, 1), p or 0, f or 0, c or 0, num(row, "fiber_100g"), num(row, "sugars_100g"),
                      num(row, "saturated-fat_100g"), sod * 1000 if sod is not None else None,
                      num(row, "serving_quantity"), (row.get("serving_size") or "").strip() or None, liquid,
                      ";".join(micros) or None, int(num(row, "unique_scans_n") or 0)))
        kept += 1
        if len(batch) >= 5000:
            db.executemany("INSERT OR REPLACE INTO food VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", batch); batch = []
    if batch: db.executemany("INSERT OR REPLACE INTO food VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", batch)
    db.execute("INSERT INTO meta VALUES ('built', ?)", (time.strftime("%Y-%m-%d"),))
    db.execute("INSERT INTO meta VALUES ('source', 'Open Food Facts (ODbL), en.openfoodfacts.org.products.csv.gz')")
    db.commit()
    print(f"done: {seen:,} rows read, {kept:,} products kept in {time.time()-t0:.0f}s", flush=True)

if __name__ == "__main__":
    main()
