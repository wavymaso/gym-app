// Searches the built food database the way the app does.  Run: ./run.sh <foods.sqlite>
import Foundation
setvbuf(stdout, nil, _IONBF, 0)
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
let db = LocalFoods(path: CommandLine.arguments[1])
check("opens, \(db.count) products, built \(db.built)", db.available)
func show(_ q: String, _ s: LocalFoods.Scope = .all) -> [FoodResult] {
    let t = Date(); let r = db.search(q, scope: s)
    print(String(format: "  %-28@ %-10@ %4.0f ms  ", q as NSString, s.rawValue as NSString, Date().timeIntervalSince(t) * 1000),
          r.prefix(3).map { "\($0.name) [\($0.brand ?? "")] \(Int($0.per100.kcal))" })
    return r
}
check("yogur griego", !show("yogur griego").isEmpty)
check("accents ignored (platano)", !show("platano").isEmpty)
check("prefixes (pech pav)", !show("pech pav").isEmpty)
check("Alcampo scope", show("leche", .alcampo).allSatisfy { _ in true } && !show("leche", .alcampo).isEmpty)
check("Costco scope (kirkland)", !show("almendras", .costco).isEmpty || !show("kirkland", .costco).isEmpty)
check("Mercadona scope", !show("hacendado", .mercadona).isEmpty)
check("Saudi scope", !show("almarai", .saudi).isEmpty)
let shake = db.product(barcode: "8432022001734")
check("barcode lookup (your protein shake)", shake?.name.contains("Batido") == true, shake?.name ?? "nil")
let t = Date(); for _ in 0..<20 { _ = db.search("pan") }
check("fast: 20 searches", Date().timeIntervalSince(t) < 2, Date().timeIntervalSince(t))

func chk(_ ok: Bool, _ n: String) { check(n, ok) }
// Typos, Spanish names for USDA foods, Arabic letters
let typo = db.search("platno")
chk(!typo.isEmpty && db.lastCorrection == "platano", "platno → platano (\(db.lastCorrection ?? "-"), \(typo.count))")
_ = db.search("pechga pavo")
chk(db.lastCorrection?.contains("pechuga") == true, "pechga → pechuga (\(db.lastCorrection ?? "-"))")
_ = db.search("yogur griego")
chk(db.lastCorrection == nil, "no correction when it's spelt right")
chk(db.generic("pollo plancha").first.map { $0.food.name.lowercased().contains("chicken") } == true, "Spanish finds USDA: pollo plancha (\(db.generic("pollo plancha").first?.food.name ?? "-"))")
chk(db.generic("lentejas").first.map { $0.food.name.lowercased().contains("lentil") } == true, "lentejas → lentils")
chk(LocalFoods.words("قهوة عربيّة") == ["قهوه", "عربيه"], "Arabic folded (\(LocalFoods.words("قهوة عربيّة")))")
chk(editDistance("pechga", "pechuga") == 1 && editDistance("griejo", "griego") == 1 && editDistance("ab", "ba") == 1, "edit distance")
chk(Nutrients(kcal: 100, protein: 20, fat: 9, carbs: 10).looksWrong && !Nutrients(kcal: 165, protein: 31, fat: 3.6, carbs: 0).looksWrong, "Atwater check")
// Taxonomy: every canonical food's USDA anchor exists; NOVA and food groups are in the database.
let missing = Taxonomy.canonical.filter { c in db.generic(c.usda, limit: 40).first { $0.food.name == c.usda } == nil }
chk(missing.isEmpty, "every canonical food has its USDA anchor (missing: \(missing.map(\.id)))")
chk(db.taxonomy(code: "8410118044575")?.nova == 4 && db.taxonomy(code: "8410118044575")?.group == "Dressings and sauces", "Open Food Facts NOVA and food group (ketchup)")
chk(db.genericCategory(fdc: 170026) == "Vegetables and Vegetable Products", "USDA category (potatoes)")
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
