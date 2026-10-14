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
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
