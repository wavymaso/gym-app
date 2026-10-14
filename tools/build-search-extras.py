#!/usr/bin/env python3
"""Search extras for foods.sqlite (run after build-generic-db.py):
  - Spanish search names for USDA generic foods (word glossary), indexed with the English
  - normalised Arabic names (alef, taa marbuta, alef maqsura, diacritics), indexed
  - a vocabulary of every indexed word with its frequency, for typo correction in the app
Usage: build-search-extras.py foods.sqlite"""
import re, sqlite3, sys, unicodedata

db = sqlite3.connect(sys.argv[1])

ES = {
 # proteins
 "chicken": "pollo", "breast": "pechuga", "thigh": "muslo", "drumstick": "muslo", "wing": "alitas", "turkey": "pavo",
 "beef": "ternera vaca", "steak": "filete", "pork": "cerdo", "ham": "jamon", "bacon": "bacon beicon", "sausage": "salchicha",
 "lamb": "cordero", "veal": "ternera", "goat": "cabra", "duck": "pato", "rabbit": "conejo", "liver": "higado",
 "egg": "huevo", "eggs": "huevos", "white": "blanco clara", "yolk": "yema", "omelet": "tortilla", "omelette": "tortilla",
 "fish": "pescado", "salmon": "salmon", "tuna": "atun", "cod": "bacalao", "hake": "merluza", "sardine": "sardina", "sardines": "sardinas",
 "anchovy": "anchoa boqueron", "mackerel": "caballa", "trout": "trucha", "shrimp": "gamba langostino", "prawn": "gamba",
 "squid": "calamar", "octopus": "pulpo", "mussels": "mejillones", "clam": "almeja", "clams": "almejas", "crab": "cangrejo",
 "tofu": "tofu", "meatballs": "albondigas", "meatball": "albondiga", "burger": "hamburguesa", "hamburger": "hamburguesa",
 # dairy
 "milk": "leche", "cheese": "queso", "yogurt": "yogur", "greek": "griego", "butter": "mantequilla", "cream": "nata crema",
 "whole": "entera", "skim": "desnatada", "lowfat": "semidesnatada", "nonfat": "desnatado", "ice": "helado",
 # carbs
 "rice": "arroz", "brown": "integral", "bread": "pan", "toast": "tostada", "toasted": "tostado", "pasta": "pasta",
 "spaghetti": "espaguetis", "macaroni": "macarrones", "noodles": "fideos", "oats": "avena", "oatmeal": "avena gachas",
 "cereal": "cereales", "flour": "harina", "wheat": "trigo", "corn": "maiz", "tortilla": "tortilla", "potato": "patata",
 "potatoes": "patatas", "sweet": "dulce boniato", "fries": "patatas fritas", "french": "fritas", "cookie": "galleta",
 "cookies": "galletas", "cracker": "galleta salada", "crackers": "galletas saladas", "cake": "bizcocho tarta pastel",
 "pie": "tarta", "muffin": "magdalena", "croissant": "cruasan", "pancakes": "tortitas", "pancake": "tortita",
 "waffle": "gofre", "honey": "miel", "sugar": "azucar", "jam": "mermelada", "chocolate": "chocolate", "granola": "granola",
 "couscous": "cuscus", "quinoa": "quinoa", "barley": "cebada", "rye": "centeno",
 # legumes, nuts
 "beans": "alubias judias frijoles", "bean": "alubia judia", "chickpeas": "garbanzos", "chickpea": "garbanzo",
 "lentils": "lentejas", "lentil": "lenteja", "peas": "guisantes", "pea": "guisante", "hummus": "hummus",
 "peanut": "cacahuete", "peanuts": "cacahuetes", "almonds": "almendras", "almond": "almendra", "walnuts": "nueces",
 "walnut": "nuez", "pistachio": "pistacho", "pistachios": "pistachos", "cashews": "anacardos", "hazelnuts": "avellanas",
 "seeds": "semillas", "sunflower": "girasol", "sesame": "sesamo", "chia": "chia", "flaxseed": "linaza",
 # vegetables
 "tomato": "tomate", "tomatoes": "tomates", "onion": "cebolla", "onions": "cebollas", "garlic": "ajo", "pepper": "pimiento pimienta",
 "peppers": "pimientos", "lettuce": "lechuga", "spinach": "espinacas", "carrot": "zanahoria", "carrots": "zanahorias",
 "broccoli": "brocoli", "cauliflower": "coliflor", "cabbage": "col repollo", "cucumber": "pepino", "zucchini": "calabacin",
 "eggplant": "berenjena", "mushrooms": "champinones setas", "mushroom": "champinon seta", "asparagus": "esparragos",
 "celery": "apio", "beet": "remolacha", "beets": "remolacha", "pumpkin": "calabaza", "squash": "calabaza", "leek": "puerro",
 "artichoke": "alcachofa", "olive": "aceituna oliva", "olives": "aceitunas", "avocado": "aguacate", "salad": "ensalada",
 "kale": "col rizada", "green": "verde", "red": "rojo", "vegetables": "verduras", "vegetable": "verdura",
 # fruit
 "apple": "manzana", "apples": "manzanas", "banana": "platano", "bananas": "platanos", "orange": "naranja", "oranges": "naranjas",
 "pear": "pera", "peach": "melocoton", "apricot": "albaricoque", "plum": "ciruela", "cherries": "cerezas", "cherry": "cereza",
 "grapes": "uvas", "grape": "uva", "strawberries": "fresas", "strawberry": "fresa", "blueberries": "arandanos",
 "raspberries": "frambuesas", "watermelon": "sandia", "melon": "melon", "pineapple": "pina", "mango": "mango",
 "kiwi": "kiwi", "lemon": "limon", "lime": "lima", "fig": "higo", "figs": "higos", "dates": "datiles", "date": "datil",
 "raisins": "pasas", "coconut": "coco", "pomegranate": "granada", "tangerine": "mandarina", "grapefruit": "pomelo",
 # fats, sauces, drinks
 "oil": "aceite", "mayonnaise": "mayonesa", "ketchup": "ketchup", "mustard": "mostaza", "sauce": "salsa", "vinegar": "vinagre",
 "soup": "sopa crema", "broth": "caldo", "stew": "guiso estofado", "juice": "zumo", "coffee": "cafe", "tea": "te",
 "water": "agua", "beer": "cerveza", "wine": "vino", "soda": "refresco", "drink": "bebida", "smoothie": "batido",
 "shake": "batido", "protein": "proteina", "powder": "polvo", "bar": "barrita",
 # preparation
 "cooked": "cocido cocinado", "boiled": "hervido cocido", "fried": "frito", "grilled": "plancha parrilla", "roasted": "asado",
 "baked": "horneado al horno", "raw": "crudo", "steamed": "al vapor", "canned": "lata conserva", "frozen": "congelado",
 "dried": "seco deshidratado", "fresh": "fresco", "smoked": "ahumado", "stewed": "guisado", "breaded": "empanado",
 "scrambled": "revuelto", "sliced": "loncheado", "ground": "picada molido", "lean": "magro", "fat": "grasa",
 "skin": "piel", "skinless": "sin piel", "without": "sin", "with": "con", "plain": "natural", "salted": "salado",
 "unsalted": "sin sal", "sandwich": "bocadillo sandwich", "pizza": "pizza", "paella": "paella", "gazpacho": "gazpacho",
}

def fold(s):
    s = unicodedata.normalize("NFKD", s or "").lower()
    return "".join(c for c in s if not unicodedata.combining(c))

def to_es(name):
    words = re.findall(r"[a-z]+", fold(name))
    out = []
    for w in words:
        t = ES.get(w) or ES.get(w.rstrip("s"))
        if t and t not in out: out.append(t)
    return " ".join(out)

AR = str.maketrans({"أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ة": "ه", "ى": "ي", "ؤ": "و", "ئ": "ي", "ـ": None})
def ar_norm(s):
    s = re.sub(r"[ً-ْٰ]", "", s or "")      # harakat, superscript alef
    return s.translate(AR)

cols = [r[1] for r in db.execute("PRAGMA table_info(generic)")]
if "name_es" not in cols: db.execute("ALTER TABLE generic ADD COLUMN name_es TEXT")
for fdc, name in db.execute("SELECT fdc, name FROM generic").fetchall():
    db.execute("UPDATE generic SET name_es=? WHERE fdc=?", (to_es(name), fdc))
db.executescript("""
DROP TABLE IF EXISTS generic_fts;
CREATE VIRTUAL TABLE generic_fts USING fts5(name, name_es, content='generic', content_rowid='fdc', tokenize='unicode61 remove_diacritics 2');
INSERT INTO generic_fts(rowid, name, name_es) SELECT fdc, name, name_es FROM generic;
""")

cols = [r[1] for r in db.execute("PRAGMA table_info(food)")]
if "name_ar_norm" not in cols: db.execute("ALTER TABLE food ADD COLUMN name_ar_norm TEXT")
db.execute("UPDATE food SET name_ar_norm = NULL")
for rid, ar in db.execute("SELECT rowid, name_ar FROM food WHERE name_ar IS NOT NULL AND name_ar != ''").fetchall():
    db.execute("UPDATE food SET name_ar_norm=? WHERE rowid=?", (ar_norm(ar), rid))
db.executescript("""
DROP TABLE IF EXISTS food_fts;
CREATE VIRTUAL TABLE food_fts USING fts5(name, name_ar, brand, name_ar_norm, content='food', content_rowid='rowid',
                                         tokenize='unicode61 remove_diacritics 2');
INSERT INTO food_fts(rowid, name, name_ar, brand, name_ar_norm) SELECT rowid, name, name_ar, brand, name_ar_norm FROM food;
""")

# Vocabulary: every indexed word and how many products/foods use it (typo correction picks common words)
db.executescript("""
DROP TABLE IF EXISTS vocab;
CREATE TABLE vocab (term TEXT PRIMARY KEY, n INTEGER) WITHOUT ROWID;
CREATE VIRTUAL TABLE temp.v1 USING fts5vocab(main, food_fts, 'row');
CREATE VIRTUAL TABLE temp.v2 USING fts5vocab(main, generic_fts, 'row');
INSERT INTO vocab SELECT term, sum(doc) FROM (SELECT term, doc FROM temp.v1 UNION ALL SELECT term, doc FROM temp.v2)
  WHERE length(term) BETWEEN 3 AND 24 AND term NOT GLOB '*[0-9]*' GROUP BY term;
""")
db.execute("INSERT OR REPLACE INTO meta VALUES ('searchExtras', '1')")
db.commit()
db.execute("VACUUM")
print("vocab", db.execute("SELECT count(*) FROM vocab").fetchone()[0],
      "· generic with Spanish", db.execute("SELECT count(*) FROM generic WHERE name_es != ''").fetchone()[0],
      "· Arabic normalised", db.execute("SELECT count(*) FROM food WHERE name_ar_norm IS NOT NULL").fetchone()[0])
