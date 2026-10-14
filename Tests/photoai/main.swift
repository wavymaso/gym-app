import Foundation
import SwiftData

// Photo logging: parsing and checks offline; then real photos through the Mac's model.
var failed = 0
func check(_ ok: Bool, _ what: String) { if !ok { failed += 1; print("FAIL \(what)") } }

// 1. Parsing, forgiving and sanity-checked
let fenced = "```json\n{\"items\":[{\"name\":\"Rice\",\"search\":\"white rice cooked\",\"grams\":\"180 g\",\"kcal\":500,\"protein\":2.7,\"fat\":0.3,\"carbs\":28,\"fiber\":0.4}]}\n```"
let items = PhotoAI.parse(fenced)
check(items.count == 1, "fenced JSON parsed")
check(items.first?.grams == 180, "grams from text")
check(abs((items.first?.per100.kcal ?? 0) - 124.7) < 0.5, "kcal made to agree with macros (got \(items.first?.per100.kcal ?? 0))")
check(PhotoAI.parse("[{\"name\":\"Egg\",\"grams\":50,\"kcal\":143,\"protein\":12.6,\"fat\":9.5,\"carbs\":0.7}]").count == 1, "bare list")
check(PhotoAI.parse("{\"items\":[{\"name\":\"\",\"grams\":50}]}").isEmpty, "nameless item dropped")
check(PhotoAI.parse("not json").isEmpty, "garbage gives nothing")

// 2. Learning portions (in a scratch defaults domain)
UserDefaults.standard.removeObject(forKey: "photoPortionBias")
var a = AIItem(name: "Rice", grams: 200, per100: .zero); a.search = "white rice cooked"
check(PhotoAI.portionFactor(for: a) == 1, "no bias at first")
PhotoAI.learn(search: a.search, aiGrams: 200, grams: 300)
check(abs(PhotoAI.portionFactor(for: a) - 1.25) < 0.001, "learned 1.25 after one correction")
var b = AIItem(name: "Pasta", grams: 200, per100: .zero); b.search = "pasta"
check(abs(PhotoAI.portionFactor(for: b) - 1.05) < 0.001, "overall bias nudged for other foods")
UserDefaults.standard.removeObject(forKey: "photoPortionBias")

// 3. Generic foods offline (USDA)
let dbPath = ProcessInfo.processInfo.environment["FOODS"] ?? "../../Gym/foods.sqlite"
let local = LocalFoods(path: dbPath)
let paella = local.generic("paella seafood")
check(paella.first?.food.name.hasPrefix("Paella") == true, "paella found (\(paella.first?.food.name ?? "-"))")
check(paella.first?.typical == 300, "paella usual portion 300 g")
check(local.generic("white rice cooked").first.map { $0.food.per100.kcal > 100 && $0.food.per100.kcal < 160 } == true, "cooked rice ~130 kcal")
check(!local.generic("fried egg").isEmpty, "fried egg")
check(!local.generic("zzzz qqqq").contains { _ in true }, "nonsense finds nothing")
check(local.generic("egg fried").first.map { !$0.food.name.lowercased().contains("eggplant") } == true, "egg is not eggplant (\(local.generic("egg fried").first?.food.name ?? "-"))")
check(local.generic("ham").first.map { !$0.food.name.lowercased().contains("hamburger") } == true, "ham is not hamburger (\(local.generic("ham").first?.food.name ?? "-"))")
check(local.generic("tomato slices").first.map { $0.food.name.lowercased().contains("tomato") } == true, "tomato slices are tomato (\(local.generic("tomato slices").first?.food.name ?? "-"))")
for q in ["bread white toasted", "potato omelet", "bacon fried", "mushroom sauteed", "sausage pork", "baked beans", "chicken breast grilled", "hummus", "lentil stew", "orange juice"] {
    print("  \(q) → \(local.generic(q).first.map { "\($0.food.name) · \(Int($0.food.per100.kcal)) kcal · usual \(Int($0.typical ?? 0)) g" } ?? "nothing")")
}

// Cut-off answers keep their complete items
let cut = "{\"items\":[{\"name\":\"Rice\",\"search\":\"rice\",\"grams\":150,\"kcal_100g\":130,\"protein_100g\":2.7,\"fat_100g\":0.3,\"carbs_100g\":28},{\"name\":\"Pra"
check(PhotoAI.parse(cut).count == 1, "salvaged the complete item from a cut-off answer")
var tort = AIItem(name: "Spanish omelette", grams: 200, per100: .zero); tort.nameES = "Tortilla de patatas"; tort.search = "tortilla potato"
check(PhotoAI.translated(tort).search == "omelet potatoes", "tortilla de patatas → potato omelet")
check(local.generic("omelet potatoes").first?.food.name.lowercased().contains("potato") == true, "potato omelet found (\(local.generic("omelet potatoes").first?.food.name ?? "-"))")
check(local.generic("tomato roasted").first.map { !$0.food.name.contains("SUBWAY") } == true, "no fast-food chains")
check(local.generic("bread toast").first?.food.name.lowercased().contains("toast") == true, "toast finds toasted (\(local.generic("bread toast").first?.food.name ?? "-"))")
check(local.generic("paella seafood cooked with rice shrimp mussels lemon").first?.food.name.hasPrefix("Paella") == true, "long search narrowed (\(local.generic("paella seafood cooked with rice shrimp mussels lemon").first?.food.name ?? "-"))")

check(local.generic("tomato roasted").first?.food.name.hasPrefix("Tomato") == true, "roasted tomato is a tomato (\(local.generic("tomato roasted").first?.food.name ?? "-"))")
check(local.generic("shrimp").first?.food.name.lowercased().contains("shrimp") == true, "shrimp (\(local.generic("shrimp").first?.food.name ?? "-"))")

// 4. Matching on a plate
let container = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
let ctx = ModelContext(container)
var big = AIItem(name: "Seafood paella", grams: 1000, per100: Nutrients(kcal: 350, protein: 0, fat: 15, carbs: 45))
big.search = "paella seafood"; big.nameES = "Paella de marisco"; big.confidence = 0.6
let plate1 = ctx.plate(from: [big], foods: local)
check(plate1.first?.source == .generic, "paella matched to USDA")
check(abs((plate1.first?.per100.kcal ?? 0) - 143) < 1, "USDA nutrition used, not the model's")
check(plate1.first?.grams == 548, "1000 g pulled toward the usual 300 g (got \(plate1.first?.grams ?? 0))")
// Something you've logged before wins
let mine = Food(key: "custom:x", name: "Paella de marisco casera", source: "custom", per100: Nutrients(kcal: 160, protein: 9, fat: 6, carbs: 18))
mine.useCount = 3; ctx.insert(mine)
check(ctx.plate(from: [big], foods: local).first?.source == .yours, "your own paella preferred")
ctx.log(plate: ctx.plate(from: [big], foods: local), day: "2026-10-14", time: Date())
check(ctx.entries(on: "2026-10-14").count == 1, "logged")
UserDefaults.standard.removeObject(forKey: "photoPortionBias")

// 5. Real photos
let photos = CommandLine.arguments.dropFirst()
if let m = ProcessInfo.processInfo.environment["MODEL"] { UserDefaults.standard.set(m, forKey: "localVisionModel") }
let group = DispatchGroup(); group.enter()
Task {
    for path in photos {
        guard let raw = FileManager.default.contents(atPath: path), let (jpeg, cg) = PhotoAI.prepare(raw) else { check(false, "prepare \(path)"); continue }
        let codes = await PhotoAI.barcodes(in: cg)
        let t = Date()
        do {
            let found = try await PhotoAI.askLocal(image: jpeg, text: "")
            print("\n\((path as NSString).lastPathComponent)  \(jpeg.count / 1024) KB  \(cg.width)x\(cg.height)  \(String(format: "%.0f", Date().timeIntervalSince(t))) s  barcodes \(codes)")
            var total = 0.0
            for p in ctx.plate(from: found, foods: local) {
                let n = p.nutrients; total += n.kcal
                print(String(format: "  %-26@ %5.0f g  %4.0f kcal  P%3.0f F%3.0f C%3.0f  %@", p.name as NSString, p.grams, n.kcal, n.protein, n.fat, n.carbs,
                             "\(p.source) \(p.source == .generic ? p.detail ?? "" : "")  (model: \(Int(p.ai?.grams ?? 0)) g)" as NSString))
            }
            print(String(format: "  total %.0f kcal", total))
            total = 0
            for i in found where false {
                let kcal = i.per100.kcal * i.grams / 100; total += kcal
                print(String(format: "  %-28@ %5.0f g  %4.0f kcal  P%3.0f F%3.0f C%3.0f  conf %.1f  [%@]", i.nameES.isEmpty ? i.name : i.nameES, i.grams, kcal,
                             i.per100.protein * i.grams / 100, i.per100.fat * i.grams / 100, i.per100.carbs * i.grams / 100, i.confidence, i.search))
            }
            check(!found.isEmpty, "found food in \(path)")
        } catch { check(false, "\(path): \(error.localizedDescription)") }
    }
    group.leave()
}
group.wait()
print(failed == 0 ? "ALL PASSED" : "\(failed) FAILED")
exit(failed == 0 ? 0 : 1)
