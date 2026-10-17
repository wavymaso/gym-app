// Groups the offline database's products under canonical foods and writes the simple foods
// catalogue: tier 1–2 canonical foods available at Mercadona, Alcampo or Costco.
//   run.sh <foods.sqlite> <out.json>          writes the catalogue and prints it by role
import Foundation
import SQLite3
setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
var db: OpaquePointer?
guard sqlite3_open_v2(args[1], &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { print("can't open"); exit(1) }
let sql = "SELECT name, IFNULL(brand,''), IFNULL(stores,''), IFNULL(countries,''), kcal, protein, fat, carbs, IFNULL(fiber,-1), IFNULL(sugar,-1), IFNULL(liquid,0), IFNULL(nova,0), IFNULL(pnns2,''), IFNULL(pack,0), IFNULL(serving_g,0), IFNULL(scans,0) FROM food WHERE countries LIKE '%es%'"
var st: OpaquePointer?
guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { print("bad query"); exit(1) }
struct Acc { var stores: [String: Int] = [:]; var n = 0; var v: [[Double]] = [[], [], [], [], []]; var rows: [SimpleFood.Values] = []; var pack: [Double] = []; var serving: [Double] = []; var nova: [Int] = []; var ex: [(String, Int)] = [] }
var acc: [String: Acc] = [:]
func text(_ i: Int32) -> String { sqlite3_column_text(st, i).map { String(cString: $0) } ?? "" }
var rows = 0
while sqlite3_step(st) == SQLITE_ROW {
    rows += 1
    let name = text(0), brand = text(1), stores = text(2)
    let kcal = sqlite3_column_double(st, 4), p = sqlite3_column_double(st, 5), f = sqlite3_column_double(st, 6), c = sqlite3_column_double(st, 7)
    let fibre = sqlite3_column_double(st, 8), sugar = sqlite3_column_double(st, 9), liquid = sqlite3_column_int(st, 10) == 1
    guard let canon = Taxonomy.match(name, brand: brand), kcal > 0 || canon.role == .vegetable || canon.role == .drink else { continue }
    // Only products that really are that food: the database's group and the macros must not contradict it.
    let group = text(12)
    let byGroup = Taxonomy.role(group: group, usdaCategory: nil)
    let byMacros = Taxonomy.role(kcal: kcal, protein: p, fat: f, carbs: c, sugar: sugar >= 0 ? sugar : nil, isLiquid: liquid)
    if let g = byGroup, !Taxonomy.compatible(g, canon.role) { continue }
    if byGroup == nil, let m = byMacros, !Taxonomy.compatible(m, canon.role) { continue }
    if Taxonomy.tier(canon.id) == 1 && !Taxonomy.isPlainForm(name) { continue }
    var a = acc[canon.id] ?? Acc()
    a.n += 1
    for s in SimpleFoods.myStores where stores.contains(s) { a.stores[s, default: 0] += 1 }
    a.v[0].append(kcal); a.v[1].append(p); a.v[2].append(f); a.v[3].append(c); if fibre >= 0 { a.v[4].append(fibre) }
    a.rows.append(.init(kcal: kcal, protein: p, fat: f, carbs: c, fibre: max(fibre, 0)))
    let pack = sqlite3_column_double(st, 13), serving = sqlite3_column_double(st, 14)
    if pack > 0 { a.pack.append(pack) }; if serving > 0 { a.serving.append(serving) }
    let nova = Int(sqlite3_column_int(st, 11)); if nova > 0 { a.nova.append(nova) }
    if SimpleFoods.myStores.contains(where: stores.contains) { a.ex.append(("\(name)\(brand.isEmpty ? "" : " (\(brand))")", Int(sqlite3_column_int(st, 15)))) }
    acc[canon.id] = a
}
// The USDA anchor of each canonical food, to check the Spanish median against.
var anchors: [String: SimpleFood.Values] = [:]
for c in Taxonomy.canonical {
    var q: OpaquePointer?
    if sqlite3_prepare_v2(db, "SELECT kcal, protein, fat, carbs, IFNULL(fiber,0) FROM generic WHERE name = ?1", -1, &q, nil) == SQLITE_OK {
        sqlite3_bind_text(q, 1, c.usda, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if sqlite3_step(q) == SQLITE_ROW {
            anchors[c.id] = .init(kcal: sqlite3_column_double(q, 0), protein: sqlite3_column_double(q, 1), fat: sqlite3_column_double(q, 2),
                                  carbs: sqlite3_column_double(q, 3), fibre: sqlite3_column_double(q, 4))
        }
    }
    sqlite3_finalize(q)
}
func median(_ x: [Double]) -> Double? { let s = x.sorted(); return s.isEmpty ? nil : s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2 }
func r1(_ x: Double?) -> Double { ((x ?? 0) * 10).rounded() / 10 }
var out: [SimpleFood] = []
for c in Taxonomy.canonical where c.role != .drink {
    let a = acc[c.id] ?? Acc()
    // The median product (by calories), all its values together, so they stay consistent with each other.
    // Products whose calories don't match their own macros are data errors: skip them.
    let consistent = a.rows.filter { r in abs(r.protein * 4 + r.carbs * 4 + r.fat * 9 + r.fibre * 2 - r.kcal) <= max(r.kcal * 0.2, 10) }
    let mid = consistent.sorted { ($0.kcal, $0.protein) < ($1.kcal, $1.protein) }.dropFirst(max(0, (a.rows.count - 1) / 2)).first
    var v = mid.map { SimpleFood.Values(kcal: r1($0.kcal), protein: r1($0.protein), fat: r1($0.fat), carbs: r1($0.carbs), fibre: r1($0.fibre)) }
        ?? SimpleFood.Values(kcal: 0, protein: 0, fat: 0, carbs: 0, fibre: 0)
    var from = "Spain (\(a.n))"
    // A whole food's Spanish median far from its generic USDA food means the products were mostly prepared forms.
    // (Pulses are sold cooked in jars; their USDA anchor is dry, so it isn't comparable.)
    if c.id != "pulses", let u = anchors[c.id], Taxonomy.tier(c.id) == 1, a.n < 5 || abs(v.kcal - u.kcal) > max(u.kcal * 0.25, 15) { v = .init(kcal: r1(u.kcal), protein: r1(u.protein), fat: r1(u.fat), carbs: r1(u.carbs), fibre: r1(u.fibre)); from = "USDA" }
    out.append(SimpleFood(id: c.id, name: c.name, role: c.role, tier: Taxonomy.tier(c.id), stores: a.stores, products: a.n,
                          values: v, valuesFrom: from,
                          pack: median(a.pack).map { ($0 / 5).rounded() * 5 }, serving: median(a.serving).map { ($0 / 5).rounded() * 5 },
                          nova: median(a.nova.map(Double.init)).map { Int($0.rounded()) },
                          examples: a.ex.sorted { ($0.1, $1.0) > ($1.1, $0.0) }.prefix(3).map(\.0)))
}
if args.count > 2 { try! JSONEncoder().encode(out).write(to: URL(fileURLWithPath: args[2])) }
print("SIMPLE FOODS CATALOGUE · \(rows) Spanish products scanned · tier 1–2 canonical foods sold at Mercadona, Alcampo or Costco\n")
let shown = out.filter { $0.tier <= 2 && $0.availableAtMyStores }
for role in FoodRole.allCases {
    let list = shown.filter { $0.role == role }
    guard !list.isEmpty else { continue }
    print(role.label.uppercased())
    for f in list {
        let s = SimpleFoods.myStores.map { "\($0.prefix(1).uppercased())\($0.dropFirst()) \(f.stores[$0] ?? 0)" }.joined(separator: " · ")
        print(String(format: "  T%d %-28@ %4.0f kcal %4.1f P %4.1f F %4.1f C %3.1f fibre (%@) · pack %@ · %@", f.tier, f.name as NSString, f.values.kcal, f.values.protein,
                     f.values.fat, f.values.carbs, f.values.fibre, f.valuesFrom as NSString, (f.pack.map { "\(Int($0)) g" } ?? "—") as NSString, s as NSString))
        if !f.examples.isEmpty { print("        e.g. \(f.examples.joined(separator: "; "))") }
    }
    print("")
}
let missing = out.filter { $0.tier <= 2 && !$0.availableAtMyStores }
print("Not found at your stores (left out): \(missing.map(\.name).joined(separator: ", "))")
print("Tier 3 (only when in stock): \(out.filter { $0.tier == 3 }.map(\.name).joined(separator: ", "))")
