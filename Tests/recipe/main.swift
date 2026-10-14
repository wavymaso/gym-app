// Recipe import: JSON-LD found and read, ingredient lines turned into food + grams.
import Foundation
setvbuf(stdout, nil, _IONBF, 0)
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
func line(_ t: String) -> (String, Double?) { let l = RecipeImport.parseLine(t); return (l.food, l.grams) }
check("200 g de arroz", line("200 g de arroz") == ("arroz", 200), line("200 g de arroz"))
check("2 cucharadas de aceite de oliva", line("2 cucharadas de aceite de oliva") == ("aceite de oliva", 30))
check("1 1/2 cups flour", line("1 1/2 cups flour") == ("flour", 360))
check("½ cdta sal", line("½ cdta sal") == ("sal", 2.5))
check("3 huevos (no unit)", line("3 huevos") == ("huevos", nil))
check("1 kg de patatas, peladas", line("1 kg de patatas, peladas") == ("patatas", 1000))
check("250ml leche", line("250 ml de leche") == ("leche", 250))
check("Sal y pimienta", line("Sal y pimienta") == ("Sal y pimienta", nil))
let html = """
<html><head><script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"WebPage"},
{"@type":["Recipe"],"name":"Tortilla de patatas","recipeYield":["4","4 raciones"],
"recipeIngredient":["1 kg de patatas","6 huevos","200 ml de aceite de oliva","Sal"]}]}</script></head></html>
"""
let r = RecipeImport.parse(html: html)
check("finds recipe in @graph", r?.name == "Tortilla de patatas", r?.name ?? "nil")
check("servings", r?.servings == 4, r?.servings ?? -1)
check("4 lines", r?.lines.count == 4)
check("no recipe → nil", RecipeImport.parse(html: "<html></html>") == nil)
// A real page, if reachable (skipped offline)
let sem = DispatchSemaphore(value: 0)
Task {
    if let live = try? await RecipeImport.fetch("https://www.bbcgoodfood.com/recipes/easy-pancakes") {
        print("live:", live.name, live.servings ?? -1, live.lines.prefix(3).map { "\($0.food)=\($0.grams ?? -1)" })
        check("live page has ingredients", live.lines.count >= 3)
    } else { print("live: skipped (couldn't download)") }
    sem.signal()
}
sem.wait()
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
