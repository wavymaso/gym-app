import Foundation
import SQLite3

// The offline product database bundled with the app (foods.sqlite, built by
// tools/build-food-db.py from Open Food Facts): Spain, Saudi Arabia and the Gulf, and
// Costco's Kirkland Signature. Searched with SQLite full-text search, accents ignored;
// Arabic names are searchable too. Results use the same "off:<barcode>" keys as the
// online search, so foods and sync behave the same either way.

final class LocalFoods {
    static let shared = LocalFoods()

    /// Which shelves to search.
    enum Scope: String, CaseIterable, Identifiable {
        case all, alcampo, costco, mercadona, saudi
        var id: String { rawValue }
        var label: String { ["All", "Alcampo", "Costco", "Mercadona", "Saudi & Gulf"][Self.allCases.firstIndex(of: self)!] }
    }

    private var db: OpaquePointer?
    private let lock = NSLock()
    private(set) var count = 0
    private(set) var built = ""

    init(path: String? = Bundle.main.path(forResource: "foods", ofType: "sqlite")) {
        guard let path else { return }
        // immutable: read-only, no locking or journal (the bundle can't be written anyway)
        let uri = "file:\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)?immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { db = nil; return }
        count = Int(scalar("SELECT count(*) FROM food") ?? "0") ?? 0
        built = scalar("SELECT value FROM meta WHERE key='built'") ?? ""
    }

    var available: Bool { db != nil && count > 0 }

    /// Products matching every word (prefixes count: "yog gri" finds "yogur griego").
    func search(_ query: String, scope: Scope = .all, limit: Int = 40) -> [FoodResult] {
        let words = query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 1 }
        guard db != nil, !words.isEmpty else { return [] }
        let match = words.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }.joined(separator: " AND ")
        let filter: String
        switch scope {
        case .all: filter = ""
        case .alcampo: filter = "AND f.stores LIKE '%alcampo%'"
        case .costco: filter = "AND f.stores LIKE '%costco%'"
        case .mercadona: filter = "AND f.stores LIKE '%mercadona%'"
        case .saudi: filter = "AND (f.countries LIKE '%sa%' OR f.countries LIKE '%gcc%')"
        }
        let sql = """
            SELECT \(columns) FROM food_fts JOIN food f ON f.rowid = food_fts.rowid
            WHERE food_fts MATCH ?1 \(filter)
            ORDER BY bm25(food_fts, 10.0, 10.0, 4.0)
                     - (CASE WHEN f.stores LIKE '%alcampo%' OR f.stores LIKE '%costco%' THEN 2.0 ELSE 0 END)
                     - min(f.scans, 1000) / 200.0
            LIMIT \(limit)
            """
        return rows(sql, bind: [match])
    }

    /// Generic foods and dishes (USDA, in English), best match first, with the usual portion
    /// people eat where USDA knows it. Whole words (plurals allowed: "egg" never finds "eggplant");
    /// if nothing has every word, the best match missing one of them; never just any word.
    func generic(_ query: String, limit: Int = 10) -> [(food: FoodResult, typical: Double?)] {
        let stop: Set<String> = ["with", "and", "the", "of", "in", "a", "fresh", "plain", "homemade", "slice", "slices", "piece", "pieces",
                                 "portion", "serving", "side", "some", "small", "large", "medium", "bowl", "plate", "glass", "cup"]
        let words = Array(NSOrderedSet(array: query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stop.contains($0) }.map(Self.singular))) as? [String] ?? []
        guard db != nil, !words.isEmpty, hasGeneric else { return [] }
        func term(_ w: String) -> String {      // egg, eggs; tomato, tomatoes; toast, toasted; bake, baked
            "(" + [w, w + "s", w + "es", w + "ed", w + "d"].map { "\"\($0)\"" }.joined(separator: " OR ") + ")"
        }
        // Every word; then without one of them; then the first two; then the first alone.
        // Never without the first word: it's the food ("mushroom sauteed" must not become a sauteed chicken wing).
        let ws = Array(words.prefix(5))
        var tries = [ws]
        if ws.count >= 2 { tries += ws.indices.dropFirst().map { i in ws.enumerated().filter { $0.offset != i }.map(\.element) } }
        if ws.count >= 4 { tries.append(Array(ws.prefix(2))) }
        if ws.count >= 2 { tries.append([ws[0]]) }
        // Each step only if the one before found nothing; within a step, the best-scoring.
        var groups: [[[String]]] = [[tries[0]]]
        if ws.count >= 2 { groups.append(Array(tries[1..<ws.count])) }
        groups += tries[(ws.count >= 2 ? ws.count : 1)...].map { [$0] }
        for group in groups {
            var best: [(food: FoodResult, typical: Double?, score: Double)] = []
            for t in group {
                let found = genericRows(sql(limit), bind: [t.map(term).joined(separator: " AND "), ws[0]])
                if let top = found.first, best.isEmpty || top.score < best[0].score { best = found }
            }
            if !best.isEmpty { return best.map { ($0.food, $0.typical) } }
        }
        return []
    }

    /// "tomatoes" → "tomato", "slices" → "slice" (the search adds the plural back).
    static func singular(_ w: String) -> String {
        if w.count > 4, w.hasSuffix("oes") { return String(w.dropLast(2)) }
        if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss"), !w.hasSuffix("us") { return String(w.dropLast()) }
        return w
    }

    private func sql(_ limit: Int) -> String {
        // Dishes "as eaten" first; "not further specified" is USDA's average version; shorter names are plainer.
        """
        SELECT g.fdc, g.name, g.kcal, g.protein, g.fat, g.carbs, g.fiber, g.sugar, g.satfat, g.sodium, g.micros, g.portions, g.typical_g,
               bm25(generic_fts) + length(g.name) / 60.0 - (CASE g.kind WHEN 'dish' THEN 0.6 ELSE 0 END)
                 - (CASE WHEN g.name LIKE '%NFS%' OR g.name LIKE '%NS as to%' THEN 1.5 ELSE 0 END)
                 - (CASE WHEN g.name LIKE ?2 || '%' THEN 2.5 ELSE 0 END)
                 + (CASE WHEN g.name LIKE '%as ingredient%' OR g.name LIKE '%glutinous%' OR g.name LIKE '%baby%'
                           OR g.name LIKE '%infant%' OR g.name LIKE '%dehydrated%' THEN 3 ELSE 0 END) AS score
        FROM generic_fts JOIN generic g ON g.fdc = generic_fts.rowid
        WHERE generic_fts MATCH ?1
        ORDER BY score
        LIMIT \(limit)
        """
    }

    private lazy var hasGeneric: Bool = scalar("SELECT count(*) FROM sqlite_master WHERE name='generic'") == "1"

    private func genericRows(_ sql: String, bind: [String]) -> [(food: FoodResult, typical: Double?, score: Double)] {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, b) in bind.enumerated() { sqlite3_bind_text(st, Int32(i + 1), b, -1, transient) }
        var out: [(food: FoodResult, typical: Double?, score: Double)] = []
        while sqlite3_step(st) == SQLITE_ROW {
            func text(_ i: Int32) -> String? { sqlite3_column_text(st, i).map { String(cString: $0) } }
            func real(_ i: Int32) -> Double? { sqlite3_column_type(st, i) == SQLITE_NULL ? nil : sqlite3_column_double(st, i) }
            func pairs(_ s: String?) -> [(String, Double)] {
                (s ?? "").split(separator: ";").compactMap { kv in
                    guard let eq = kv.lastIndex(of: "="), let v = Double(kv[kv.index(after: eq)...]) else { return nil }
                    return (String(kv[..<eq]), v)
                }
            }
            guard let name = text(1) else { continue }
            let micros = Dictionary(pairs(text(10)), uniquingKeysWith: { a, _ in a })
            let per100 = Nutrients(kcal: real(2) ?? 0, protein: real(3) ?? 0, fat: real(4) ?? 0, carbs: real(5) ?? 0, fiber: real(6),
                                   sugar: real(7), satFat: real(8), sodium: real(9), micros: micros.isEmpty ? nil : micros)
            let servings = pairs(text(11)).map { Serving(name: $0.0, grams: $0.1) }
            let liquid = ["juice", "milk", "soda", "beer", "wine", "coffee", "tea,", "water", "drink", "smoothie", "soup"].contains { name.lowercased().contains($0) }
            out.append((FoodResult(key: "usda:\(sqlite3_column_int(st, 0))", name: name, brand: nil, barcode: nil, source: "usda",
                                   per100: per100, servings: servings, isLiquid: liquid), real(12), sqlite3_column_double(st, 13)))
        }
        return out
    }

    func product(barcode: String) -> FoodResult? {
        let code = barcode.trimmingCharacters(in: .whitespaces)
        // Open Food Facts stores short EAN-8/UPC codes as written, and sometimes padded to 13 digits.
        let candidates = Array(Set([code, String(repeating: "0", count: max(0, 13 - code.count)) + code, code.drop { $0 == "0" }.description]))
        for c in candidates where !c.isEmpty {
            if let r = rows("SELECT \(columns) FROM food f WHERE f.code = ?1", bind: [c]).first { return r }
        }
        return nil
    }

    // MARK: SQLite

    private let columns = "f.code, f.name, f.name_ar, f.brand, f.kcal, f.protein, f.fat, f.carbs, f.fiber, f.sugar, f.satfat, f.sodium, f.serving_g, f.serving, f.liquid, f.micros, f.scans"

    private func rows(_ sql: String, bind: [String]) -> [FoodResult] {
        lock.lock(); defer { lock.unlock() }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, b) in bind.enumerated() { sqlite3_bind_text(st, Int32(i + 1), b, -1, transient) }
        var out: [FoodResult] = []
        while sqlite3_step(st) == SQLITE_ROW {
            func text(_ i: Int32) -> String? { sqlite3_column_text(st, i).map { String(cString: $0) } }
            func real(_ i: Int32) -> Double? { sqlite3_column_type(st, i) == SQLITE_NULL ? nil : sqlite3_column_double(st, i) }
            guard let code = text(0), let name = text(1) else { continue }
            var micros: [String: Double]?
            if let m = text(15) {
                micros = Dictionary(m.split(separator: ";").compactMap { kv -> (String, Double)? in
                    let p = kv.split(separator: "="); guard p.count == 2, let v = Double(p[1]) else { return nil }
                    return (String(p[0]), v)
                }, uniquingKeysWith: { a, _ in a })
            }
            let per100 = Nutrients(kcal: real(4) ?? 0, protein: real(5) ?? 0, fat: real(6) ?? 0, carbs: real(7) ?? 0, fiber: real(8),
                                   sugar: real(9), satFat: real(10), sodium: real(11), micros: micros)
            var servings: [Serving] = []
            if let g = real(12), g > 0 {
                let label = text(13) ?? ""
                servings.append(Serving(name: label.isEmpty ? "1 serving" : "1 serving (\(label))", grams: g))
            }
            // Arabic name alongside, for products sold in Saudi Arabia
            let ar = text(2)
            let brand = [text(3), ar.flatMap { $0 == name ? nil : $0 }].compactMap { $0 }.joined(separator: " · ")
            out.append(FoodResult(key: "off:\(code)", name: name, brand: brand.isEmpty ? nil : brand, barcode: code, source: "off",
                                  per100: per100, servings: servings, isLiquid: sqlite3_column_int(st, 14) == 1,
                                  popularity: Int(sqlite3_column_int(st, 16))))
        }
        return out
    }

    private func scalar(_ sql: String) -> String? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_text(st, 0).map { String(cString: $0) } : nil
    }
}
