// Micronutrient parsing from both databases, and how micros add up and scale.
import Foundation
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
func near(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 1e-6 } ?? false }
// Open Food Facts: grams per 100 g (a fortified cocoa drink)
func json(_ t: String) -> [String: Any] { try! JSONSerialization.jsonObject(with: Data(t.utf8)) as! [String: Any] }
let off = json(#"{"code": "8410014000000", "product_name": "Cacao soluble", "nutriments": {"energy-kcal_100g": 380, "proteins_100g": 6.0, "fat_100g": 3.0, "carbohydrates_100g": 79.0, "calcium_100g": 0.6, "iron_100g": 0.0105, "vitamin-d_100g": 0.0000075, "vitamin-c_100g": "0,06"}}"#)
let r = FoodAPI.parseOFFProduct(off)!
check("OFF calcium g → mg", near(r.per100.micros?["calcium"], 600), r.per100.micros ?? [:])
check("OFF iron g → mg", near(r.per100.micros?["iron"], 10.5))
check("OFF vitamin D g → µg", near(r.per100.micros?["vitD"], 7.5))
check("OFF comma decimals", near(r.per100.micros?["vitC"], 60))
check("OFF missing ones absent", r.per100.micros?["zinc"] == nil)
// USDA: already mg / µg
let usda = json(#"{"fdcId": 171287, "description": "Egg, whole, raw", "foodNutrients": [{"nutrientId": 1003, "value": 12.6}, {"nutrientId": 1004, "value": 9.5}, {"nutrientId": 1005, "value": 0.7}, {"nutrientId": 1008, "value": 143}, {"nutrientId": 1089, "value": 1.75}, {"nutrientId": 1178, "value": 0.89}, {"nutrientId": 1253, "value": 372}, {"nutrientId": 1114, "value": 2}]}"#)
let u = FoodAPI.parseUSDAFood(usda)!
check("USDA iron", near(u.per100.micros?["iron"], 1.75))
check("USDA B12", near(u.per100.micros?["b12"], 0.89))
check("USDA cholesterol", near(u.per100.micros?["cholesterol"], 372))
// Maths
let two = u.per100.scaled(0.5) + u.per100.scaled(0.5)
check("scaling and adding keep micros", near(two.micros?["iron"], 1.75))
let plain = Nutrients(kcal: 100, protein: 1, fat: 1, carbs: 1)
check("food without micros adds cleanly", near((plain + u.per100).micros?["iron"], 1.75) && (plain + plain).micros == nil)
// Stored as JSON (sync): micros survive
let data = try! JSONEncoder().encode(u.per100), back = try! JSONDecoder().decode(Nutrients.self, from: data)
check("JSON round trip", back == u.per100)
check("old JSON without micros decodes", (try? JSONDecoder().decode(Nutrients.self, from: Data(#"{"kcal":1,"protein":0,"fat":0,"carbs":0}"#.utf8)))?.micros == nil)
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
