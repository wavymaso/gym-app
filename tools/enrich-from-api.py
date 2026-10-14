#!/usr/bin/env python3
"""Adds products and Arabic names to foods.sqlite from the Open Food Facts API.

The CSV export only has one name per product, so products named only in Arabic (common
in Saudi Arabia) are missing from it. This pages through a country's products slowly (to
respect OFF's rate limits), adds the ones with nutrition facts, and records Arabic names.

    python3 enrich-from-api.py <foods.sqlite> <country tag, e.g. saudi-arabia> <country code, e.g. sa>
"""
import json, sqlite3, sys, time, urllib.request, urllib.error

FIELDS = "code,product_name,product_name_ar,product_name_en,product_name_es,brands,stores,quantity,serving_quantity,serving_size,nutriments,unique_scans_n"

def num(n, k):
    v = n.get(k)
    try:
        x = float(str(v).replace(",", ".")) if v is not None and v != "" else None
        return x if x is not None and 0 <= x < 1e6 else None
    except ValueError:
        return None

def first_brand(b):
    """Brands come as "A, B" from one API and ["A", "B"] from the other."""
    if isinstance(b, list): b = b[0] if b else ""
    return (b or "").split(",")[0].strip() or None

def text(v):
    if isinstance(v, list): v = v[0] if v else None
    return v.strip() if isinstance(v, str) and v.strip() else None

def get(url, tries=6):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Gym/1.0 (personal food database)"})
            return json.load(urllib.request.urlopen(req, timeout=60))
        except Exception as e:
            wait = 20 * (i + 1)
            print(f"    retry in {wait}s ({e})", flush=True)
            time.sleep(wait)
    return None

def main():
    db = sqlite3.connect(sys.argv[1])
    tag, cc = sys.argv[2], sys.argv[3]
    page, added, named = 1, 0, 0
    while True:
        # search-a-licious (search.openfoodfacts.org): the classic search API refuses big pages under load
        d = get(f'https://search.openfoodfacts.org/search?q=countries_tags:%22en:{tag}%22&page_size=100&page={page}&fields={FIELDS}')
        if d is None: print("giving up on page", page); break
        products = d.get("hits", d.get("products", []))
        if not products: break
        for p in products:
            code = str(p.get("code") or "").strip()
            if not code: continue
            ar = text(p.get("product_name_ar"))
            row = db.execute("SELECT countries FROM food WHERE code=?", (code,)).fetchone()
            if row:
                if ar:
                    db.execute("UPDATE food SET name_ar=? WHERE code=?", (ar, code)); named += 1
                if cc not in (row[0] or "").split(","):
                    db.execute("UPDATE food SET countries=? WHERE code=?", (",".join(filter(None, [row[0], cc])), code))
                continue
            n = p.get("nutriments") or {}
            pr, f, c = num(n, "proteins_100g"), num(n, "fat_100g"), num(n, "carbohydrates_100g")
            if pr is None and f is None and c is None: continue
            name = next((x for x in map(text, [p.get("product_name_en"), p.get("product_name"), p.get("product_name_es"), ar]) if x), None)
            if not name: continue
            kcal = num(n, "energy-kcal_100g")
            if kcal is None:
                kj = num(n, "energy-kj_100g") or num(n, "energy_100g")
                kcal = kj / 4.184 if kj is not None else (pr or 0) * 4 + (c or 0) * 4 + (f or 0) * 9
            if kcal > 950: continue
            sod = num(n, "sodium_100g")
            qty = (text(p.get("quantity")) or "").lower()
            db.execute("INSERT OR REPLACE INTO food VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                       (code, name, ar, first_brand(p.get("brands")), cc, "",
                        round(kcal, 1), pr or 0, f or 0, c or 0, num(n, "fiber_100g"), num(n, "sugars_100g"), num(n, "saturated-fat_100g"),
                        sod * 1000 if sod is not None else None, num(p, "serving_quantity"), text(p.get("serving_size")),
                        1 if any(u in qty for u in ("ml", " l", "cl")) else 0, None, int(p.get("unique_scans_n") or 0)))
            added += 1
        db.commit()
        print(f"  page {page}: {added} added, {named} Arabic names so far", flush=True)
        if page * 100 >= d.get("count", 0): break
        page += 1
        time.sleep(3)                                           # be gentle with OFF's servers
    db.commit()
    print(f"done {tag}: {added} products added, {named} Arabic names", flush=True)

if __name__ == "__main__":
    main()
