// Renders nutrition labels, reads them with Vision (as the app does) and checks the values.
import AppKit
import SwiftUI
setvbuf(stdout, nil, _IONBF, 0)
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
func near(_ a: Double?, _ b: Double, _ tol: Double = 0.051) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

struct Label: View {
    let title: String
    let header: [String]
    let rows: [[String]]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 30, weight: .black)).padding(.bottom, 8)
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 10) {
                GridRow { ForEach(header, id: \.self) { Text($0).font(.system(size: 22, weight: .bold)) } }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(rows, id: \.self) { r in
                    GridRow { ForEach(r, id: \.self) { Text($0).font(.system(size: 22)) } }
                }
            }
        }
        .padding(30).foregroundStyle(.black).background(.white)
    }
}

@MainActor func render(_ v: some View) -> CGImage { let r = ImageRenderer(content: v); r.scale = 2; return r.cgImage! }

let sem = DispatchSemaphore(value: 0)
Task { @MainActor in
    let es = Label(title: "Información nutricional", header: ["", "Por 100 g", "Por ración (30 g)"], rows: [
        ["Valor energético", "1590 kJ / 380 kcal", "477 kJ / 114 kcal"],
        ["Grasas", "3,0 g", "0,9 g"],
        ["   de las cuales saturadas", "1,2 g", "0,4 g"],
        ["Hidratos de carbono", "79 g", "24 g"],
        ["   de los cuales azúcares", "12,5 g", "3,8 g"],
        ["Fibra alimentaria", "6,1 g", "1,8 g"],
        ["Proteínas", "6,0 g", "1,8 g"],
        ["Sal", "0,15 g", "0,05 g"]])
    let rowsES = try! await LabelReader.rows(from: render(es))
    print("rows:", rowsES)
    let v = LabelReader.parse(rowsES)
    check("ES kcal", near(v.kcal, 380), v.kcal ?? -1)
    check("ES fat", near(v.fat, 3.0), v.fat ?? -1)
    check("ES saturated", near(v.satFat, 1.2), v.satFat ?? -1)
    check("ES carbs", near(v.carbs, 79), v.carbs ?? -1)
    check("ES sugars", near(v.sugar, 12.5), v.sugar ?? -1)
    check("ES fibre", near(v.fiber, 6.1), v.fiber ?? -1)
    check("ES protein", near(v.protein, 6.0), v.protein ?? -1)
    check("ES salt", near(v.salt, 0.15, 0.001), v.salt ?? -1)
    check("ES serving 30 g", near(v.servingGrams, 30), v.servingGrams ?? -1)
    let en = Label(title: "Nutrition", header: ["Typical values", "per 100g"], rows: [
        ["Energy", "1046 kJ"], ["Fat", "8.4g"], ["of which saturates", "2.1g"], ["Carbohydrate", "30g"],
        ["of which sugars", "1.9g"], ["Protein", "11g"], ["Salt", "1.1g"]])
    let w = LabelReader.parse(try! await LabelReader.rows(from: render(en)))
    check("EN kcal from kJ", near(w.kcal, 1046 / 4.184, 0.5), w.kcal ?? -1)
    check("EN fat", near(w.fat, 8.4), w.fat ?? -1)
    check("EN saturates", near(w.satFat, 2.1), w.satFat ?? -1)
    check("EN carbs", near(w.carbs, 30), w.carbs ?? -1)
    check("EN protein", near(w.protein, 11), w.protein ?? -1)
    check("EN salt → sodium", near(w.sodiumMg, 440, 1), w.sodiumMg ?? -1)
    sem.signal()
}
while sem.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
