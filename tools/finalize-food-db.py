#!/usr/bin/env python3
"""Adds the full-text index to foods.sqlite and compacts it, ready to bundle with the app.

    python3 finalize-food-db.py <foods.sqlite>
"""
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.executescript("""
    DROP TABLE IF EXISTS food_fts;
    CREATE VIRTUAL TABLE food_fts USING fts5(name, name_ar, brand, content='food', content_rowid='rowid',
                                             tokenize='unicode61 remove_diacritics 2');
    INSERT INTO food_fts(rowid, name, name_ar, brand) SELECT rowid, name, coalesce(name_ar, ''), coalesce(brand, '') FROM food;
    INSERT INTO food_fts(food_fts) VALUES ('optimize');
""")
db.execute("INSERT OR REPLACE INTO meta VALUES ('count', (SELECT count(*) FROM food))")
db.commit()
db.execute("VACUUM")
db.close()
print("finalized", sys.argv[1])
