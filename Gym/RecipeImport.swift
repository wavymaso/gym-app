import Foundation

// Recipes from a link: most recipe sites publish schema.org Recipe data (JSON-LD) for
// search engines. We read its name, servings and ingredient lines, and estimate grams
// from each line ("200 g de arroz", "2 cucharadas de aceite", "1 cup flour").

struct ImportedRecipe: Equatable {
    var name: String
    var servings: Double?
    var lines: [RecipeLine]
}

struct RecipeLine: Identifiable, Equatable {
    var id = UUID()
    var text: String              // as the site wrote it
    var food: String              // the ingredient, for searching
    var grams: Double?            // when the line says how much in a convertible unit

    static func == (a: RecipeLine, b: RecipeLine) -> Bool { a.text == b.text && a.food == b.food && a.grams == b.grams }
}

enum RecipeImport {
    enum Failure: Error { case download, noRecipe }

    static func fetch(_ link: String) async throws -> ImportedRecipe {
        var s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { throw Failure.download }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                   forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode ?? 0 < 400 else {
            throw Failure.download
        }
        let html = String(decoding: data, as: UTF8.self)
        guard let recipe = parse(html: html) else { throw Failure.noRecipe }
        return recipe
    }

    /// A post's text (Instagram, TikTok, YouTube, a blog without recipe data): its caption from the
    /// preview tags, which these sites give to link previews without logging in.
    static func caption(_ link: String) async -> String? {
        var s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 20)
        // Link-preview robots get the caption in the page head.
        r.setValue("facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: r) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        var best = ""
        for key in ["og:description", "description", "twitter:description", "og:title"] {
            for pattern in ["<meta[^>]+(?:property|name)=\"\(key)\"[^>]+content=\"([^\"]*)\"", "<meta[^>]+content=\"([^\"]*)\"[^>]+(?:property|name)=\"\(key)\""] {
                if let m = html.range(of: pattern, options: .regularExpression) {
                    let tag = String(html[m])
                    if let c = tag.range(of: "content=\"([^\"]*)\"", options: .regularExpression) {
                        let v = decode(String(tag[c]).dropFirst(9).dropLast().description)
                        if v.count > best.count { best = v }
                    }
                }
            }
        }
        return best.count >= 40 ? best : nil
    }

    /// The first schema.org Recipe in the page's JSON-LD blocks.
    static func parse(html: String) -> ImportedRecipe? {
        guard let re = try? NSRegularExpression(pattern: #"<script[^>]*application/ld\+json[^>]*>(.*?)</script>"#,
                                                options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return nil }
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(m.range(at: 1), in: html),
                  let json = try? JSONSerialization.jsonObject(with: Data(html[r].utf8), options: [.fragmentsAllowed]),
                  let recipe = findRecipe(json) else { continue }
            let lines = (recipe["recipeIngredient"] as? [String] ?? recipe["ingredients"] as? [String] ?? []).map { parseLine(decode($0)) }
            guard !lines.isEmpty else { continue }
            return ImportedRecipe(name: decode(recipe["name"] as? String ?? "Recipe"), servings: servings(recipe["recipeYield"]), lines: lines)
        }
        return nil
    }

    private static func findRecipe(_ any: Any) -> [String: Any]? {
        if let d = any as? [String: Any] {
            let type = d["@type"]
            if (type as? String) == "Recipe" || ((type as? [String])?.contains("Recipe") ?? false) { return d }
            for v in d.values { if let f = findRecipe(v) { return f } }
        } else if let a = any as? [Any] {
            for v in a { if let f = findRecipe(v) { return f } }
        }
        return nil
    }

    private static func servings(_ any: Any?) -> Double? {
        if let n = any as? Double { return n }
        if let n = any as? Int { return Double(n) }
        if let s = any as? String { return firstNumber(s) }
        if let a = any as? [Any] { for x in a { if let v = servings(x) { return v } } }
        return nil
    }

    /// Grams per unit, for units that convert reliably enough for a recipe.
    static let units: [(words: [String], grams: Double)] = [
        (["kg", "kilo", "kilos", "kilogramos", "kilograms"], 1000),
        (["g", "gr", "grs", "gramo", "gramos", "gram", "grams"], 1),
        (["mg"], 0.001),
        (["l", "litro", "litros", "liter", "litre", "liters", "litres"], 1000),
        (["dl"], 100), (["cl"], 10),
        (["ml", "mililitro", "mililitros", "milliliter", "millilitre", "milliliters"], 1),
        (["cucharada", "cucharadas", "cda", "cdas", "tbsp", "tablespoon", "tablespoons"], 15),
        (["cucharadita", "cucharaditas", "cdta", "cdtas", "tsp", "teaspoon", "teaspoons"], 5),
        (["taza", "tazas", "vaso", "vasos", "cup", "cups"], 240),
        (["oz", "onza", "onzas", "ounce", "ounces"], 28.35),
        (["lb", "lbs", "libra", "libras", "pound", "pounds"], 453.6),
    ]

    static func parseLine(_ text: String) -> RecipeLine {
        var s = text.replacingOccurrences(of: "½", with: " 1/2").replacingOccurrences(of: "¼", with: " 1/4").replacingOccurrences(of: "¾", with: " 3/4")
        s = s.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)       // "(opcional)", "(200 g)" side notes
            .trimmingCharacters(in: .whitespaces)
        // Leading amount: "200", "1,5", "1 1/2", "1/2", "2-3" (takes the first)
        var amount: Double?
        if let m = s.range(of: #"^\d+\s+\d+/\d+|^\d+/\d+|^\d+(?:[.,]\d+)?"#, options: .regularExpression) {
            amount = quantity(String(s[m]))
            s = String(s[m.upperBound...]).replacingOccurrences(of: #"^\s*-\s*\d+(?:[.,]\d+)?"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        var grams: Double?
        let words = s.split(separator: " ", maxSplits: 1).map(String.init)
        if let first = words.first {
            let unit = first.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
            if let u = units.first(where: { $0.words.contains(unit) }) {
                grams = amount.map { $0 * u.grams }
                s = words.count > 1 ? words[1] : ""
            }
        }
        // "de arroz" / "of flour" → "arroz"; drop trailing notes after a comma
        s = s.replacingOccurrences(of: #"^(?:de|del|of)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        if let comma = s.firstIndex(of: ",") { s = String(s[..<comma]) }
        return RecipeLine(text: text, food: s.trimmingCharacters(in: .whitespaces), grams: grams)
    }

    private static func quantity(_ s: String) -> Double? {
        var total = 0.0
        for part in s.split(separator: " ") {
            if part.contains("/") {
                let f = part.split(separator: "/").compactMap { Double($0) }
                if f.count == 2, f[1] != 0 { total += f[0] / f[1] }
            } else if let v = Double(part.replacingOccurrences(of: ",", with: ".")) {
                total += v
            }
        }
        return total > 0 ? total : nil
    }

    private static func firstNumber(_ s: String) -> Double? {
        s.range(of: #"\d+(?:[.,]\d+)?"#, options: .regularExpression).flatMap { Double(s[$0].replacingOccurrences(of: ",", with: ".")) }
    }

    /// The few HTML entities recipe sites leave in their JSON.
    static func decode(_ s: String) -> String {
        var out = s
        for (k, v) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#039;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
                       "&aacute;": "á", "&eacute;": "é", "&iacute;": "í", "&oacute;": "ó", "&uacute;": "ú", "&ntilde;": "ñ"] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
