import Foundation

// Food databases: Open Food Facts for packaged products (filtered to Spain, by
// popularity), USDA FoodData Central for plain foods (rice, chicken, apples).
// Plain Swift (no SwiftUI/SwiftData), so it can be tested on its own.

/// Nutrition for an amount of food. Sodium in mg, the rest in grams (energy in kcal).
struct Nutrients: Codable, Equatable, Hashable {
    var kcal: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var fiber: Double?
    var sugar: Double?
    var satFat: Double?
    var sodium: Double?
    var micros: [String: Double]? = nil       // vitamins and minerals by Micro.key, in the Micro's unit (Micros.swift)

    static let zero = Nutrients(kcal: 0, protein: 0, fat: 0, carbs: 0)

    func scaled(_ f: Double) -> Nutrients {
        Nutrients(kcal: kcal * f, protein: protein * f, fat: fat * f, carbs: carbs * f,
                  fiber: fiber.map { $0 * f }, sugar: sugar.map { $0 * f }, satFat: satFat.map { $0 * f }, sodium: sodium.map { $0 * f },
                  micros: micros?.mapValues { $0 * f })
    }

    static func + (a: Nutrients, b: Nutrients) -> Nutrients {
        func add(_ x: Double?, _ y: Double?) -> Double? { x == nil && y == nil ? nil : (x ?? 0) + (y ?? 0) }
        return Nutrients(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, fat: a.fat + b.fat, carbs: a.carbs + b.carbs,
                         fiber: add(a.fiber, b.fiber), sugar: add(a.sugar, b.sugar), satFat: add(a.satFat, b.satFat),
                         sodium: add(a.sodium, b.sodium),
                         micros: a.micros == nil && b.micros == nil ? nil : (a.micros ?? [:]).merging(b.micros ?? [:], uniquingKeysWith: +))
    }

    var targets: Targets { Targets(kcal: kcal, protein: protein, fat: fat, carbs: carbs) }
}

/// A named portion: "1 cup, cooked" = 158 g.
struct Serving: Codable, Hashable {
    var name: String
    var grams: Double
}

/// A food found in a database, before it's saved to your foods.
struct FoodResult: Identifiable, Hashable {
    var key: String                 // "off:<barcode>", "usda:<fdcId>"
    var name: String
    var brand: String?
    var barcode: String?
    var source: String              // off | usda
    var per100: Nutrients
    var servings: [Serving]
    var isLiquid: Bool
    var popularity: Int = 0
    var id: String { key }
}

struct FoodAPIError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum FoodAPI {
    static let userAgent = "GymApp/0.2 (personal food log)"
    static let demoKey = "DEMO_KEY"

    // MARK: Open Food Facts

    /// Popular products in Spain, best matches first. Falls back to everywhere if Spain has few.
    static func searchProducts(_ query: String) async throws -> [FoodResult] {
        var results = try await offSearch(query, spainOnly: true)
        if results.count < 8 {
            let more = try await offSearch(query, spainOnly: false)
            results += more.filter { m in !results.contains { $0.key == m.key } }
        }
        return Array(rankByWords(results, query: query).prefix(25))
    }

    private static func offSearch(_ query: String, spainOnly: Bool) async throws -> [FoodResult] {
        var c = URLComponents(string: "https://search.openfoodfacts.org/search")!
        c.queryItems = [
            URLQueryItem(name: "q", value: query + (spainOnly ? " countries_tags:\"en:spain\"" : "")),
            URLQueryItem(name: "page_size", value: "40"),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_es,product_name_en,brands,nutriments,unique_scans_n,quantity"),
        ]
        let json = try await getJSON(c.url!)
        return (json["hits"] as? [[String: Any]] ?? []).compactMap(parseOFFProduct)
    }

    /// One product by barcode, with its serving size. nil if Open Food Facts doesn't know it.
    static func product(barcode: String) async throws -> FoodResult? {
        let code = barcode.filter(\.isNumber)
        guard !code.isEmpty else { return nil }
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=code,product_name,product_name_es,product_name_en,brands,nutriments,serving_size,serving_quantity,quantity")!
        let json = try await getJSON(url, allow404: true)
        guard (json["status"] as? Int) == 1, var p = json["product"] as? [String: Any] else { return nil }
        p["code"] = p["code"] ?? code
        return parseOFFProduct(p)
    }

    static func parseOFFProduct(_ p: [String: Any]) -> FoodResult? {
        let name = [p["product_name_es"], p["product_name"], p["product_name_en"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        guard let name, let code = p["code"] as? String ?? (p["code"] as? Int).map(String.init) else { return nil }
        let n = p["nutriments"] as? [String: Any] ?? [:]
        func v(_ k: String) -> Double? {
            if let d = n[k] as? Double { return d }
            if let i = n[k] as? Int { return Double(i) }
            if let s = n[k] as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        let protein = v("proteins_100g"), fat = v("fat_100g"), carbs = v("carbohydrates_100g")
        guard protein != nil || fat != nil || carbs != nil else { return nil }        // no nutrition facts
        let kcal = v("energy-kcal_100g") ?? v("energy-kj_100g").map { $0 / 4.184 } ?? v("energy_100g").map { $0 / 4.184 }
            ?? ((protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9)
        let per100 = Nutrients(kcal: kcal, protein: protein ?? 0, fat: fat ?? 0, carbs: carbs ?? 0, fiber: v("fiber_100g"),
                               sugar: v("sugars_100g"), satFat: v("saturated-fat_100g"), sodium: v("sodium_100g").map { $0 * 1000 },
                               micros: Micro.fromOFF(v))
        let brand: String? = (p["brands"] as? [String])?.first ?? (p["brands"] as? String)?.split(separator: ",").first.map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var servings: [Serving] = []
        let sq = (p["serving_quantity"] as? Double) ?? (p["serving_quantity"] as? Int).map(Double.init)
            ?? (p["serving_quantity"] as? String).flatMap { Double($0) }
        if let sq, sq > 0 {
            let label = (p["serving_size"] as? String).map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            servings.append(Serving(name: label.isEmpty ? "1 serving" : "1 serving (\(label))", grams: sq))
        }
        let quantity = (p["quantity"] as? String ?? "").lowercased()
        let liquid = quantity.range(of: #"\d\s*(ml|cl|l)\b"#, options: .regularExpression) != nil
        return FoodResult(key: "off:\(code)", name: name, brand: brand?.isEmpty == true ? nil : brand, barcode: code, source: "off",
                          per100: per100, servings: servings, isLiquid: liquid,
                          popularity: (p["unique_scans_n"] as? Int) ?? 0)
    }

    /// Products matching all the words first, then more of them, then the most scanned.
    static func rankByWords(_ results: [FoodResult], query: String) -> [FoodResult] {
        let words = fold(query).split(separator: " ").map(String.init).filter { $0.count >= 2 }
        guard !words.isEmpty else { return results }
        func score(_ r: FoodResult) -> Int {
            let text = fold("\(r.name) \(r.brand ?? "")")
            return words.filter { text.contains($0) }.count
        }
        return results.enumerated().sorted { a, b in
            let (sa, sb) = (score(a.element), score(b.element))
            if sa != sb { return sa > sb }
            if a.element.popularity != b.element.popularity { return a.element.popularity > b.element.popularity }
            return a.offset < b.offset
        }.map(\.element)
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).lowercased()
    }

    // MARK: USDA

    /// Plain foods with their common portions. The free DEMO_KEY allows only a few searches an hour.
    static func searchGeneric(_ query: String, apiKey: String) async throws -> [FoodResult] {
        var c = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        c.queryItems = [URLQueryItem(name: "api_key", value: apiKey.isEmpty ? demoKey : apiKey)]
        // A JSON body: USDA sometimes rejects "Survey (FNDDS)" in the URL, depending on how the brackets are encoded.
        let body: [String: Any] = ["query": query, "pageSize": 25, "dataType": ["Foundation", "SR Legacy", "Survey (FNDDS)"]]
        let json = try await getJSON(c.url!, usda: true, body: try JSONSerialization.data(withJSONObject: body))
        return (json["foods"] as? [[String: Any]] ?? []).compactMap(parseUSDAFood)
    }

    static func parseUSDAFood(_ f: [String: Any]) -> FoodResult? {
        guard let id = f["fdcId"] as? Int, let name = f["description"] as? String else { return nil }
        var n: [Int: Double] = [:]
        for x in f["foodNutrients"] as? [[String: Any]] ?? [] {
            if let nid = x["nutrientId"] as? Int, let val = (x["value"] as? Double) ?? (x["value"] as? Int).map(Double.init) { n[nid] = val }
        }
        guard let protein = n[1003], let fat = n[1004], let carbs = n[1005] else { return nil }
        let kcal = n[1008] ?? n[2047] ?? n[2048] ?? (protein * 4 + carbs * 4 + fat * 9)
        let per100 = Nutrients(kcal: kcal, protein: protein, fat: fat, carbs: carbs, fiber: n[1079], sugar: n[2000] ?? n[1063],
                               satFat: n[1258], sodium: n[1093], micros: Micro.fromUSDA(n))
        let servings: [Serving] = (f["foodMeasures"] as? [[String: Any]] ?? []).compactMap { m in
            guard let text = m["disseminationText"] as? String, text != "Quantity not specified",
                  let g = (m["gramWeight"] as? Double) ?? (m["gramWeight"] as? Int).map(Double.init), g > 0 else { return nil }
            return Serving(name: text, grams: g)
        }
        return FoodResult(key: "usda:\(id)", name: name, brand: nil, barcode: nil, source: "usda", per100: per100,
                          servings: servings, isLiquid: false)
    }

    // MARK: HTTP

    private static func getJSON(_ url: URL, allow404: Bool = false, usda: Bool = false, body: Data? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let name = usda ? "USDA" : "Open Food Facts"
        var data = Data(), resp: URLResponse?
        // Brief drops and busy servers: try again after 0,6 s and 1,5 s before giving up.
        for (attempt, wait) in [0.0, 0.6, 1.5].enumerated() {
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
            do {
                (data, resp) = try await URLSession.shared.data(for: req)
                let c = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if (500...599).contains(c) || (c == 429 && !usda), attempt < 2 { continue }
                break
            } catch let e as URLError where e.code == .cancelled {
                throw e
            } catch {
                if attempt < 2 { continue }
                Log.network.error("\(name, privacy: .public) unreachable: \(error.localizedDescription, privacy: .public)")
                throw FoodAPIError(message: "Couldn't reach \(name). Check your internet connection; the built-in database still works offline.")
            }
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 && !usda { throw FoodAPIError(message: "Open Food Facts is limiting searches right now. Try again in a minute.") }
        if usda && (code == 429 || code == 403) {
            throw FoodAPIError(message: "USDA search limit reached. Add your free USDA API key in Settings for unlimited searches.")
        }
        if code == 404 && allow404 { return [:] }
        guard code == 200 else {
            Log.network.error("\(name, privacy: .public) error \(code)")
            throw FoodAPIError(message: code >= 500 ? "\(name) is having problems (error \(code)). Try again later." : "\(name) answered with error \(code).")
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

extension Nutrients {
    /// Calories that don't match the macros (4/4/9, plus alcohol): a likely database error.
    var looksWrong: Bool {
        let est = protein * 4 + carbs * 4 + fat * 9 + (micros?["alcohol"] ?? 0) * 7
        guard kcal > 25 || est > 25 else { return false }
        return abs(est - kcal) / max(kcal, est) > 0.2
    }
}
