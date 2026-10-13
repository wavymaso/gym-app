import Compression
import Foundation

// Reading exported spreadsheets (MacroFactor's, or any similar app's): CSV or Excel
// .xlsx, columns recognised by their names. Plain Swift, so it can be tested alone.

/// A sheet: header names and rows of text cells.
struct Table {
    var name: String
    var headers: [String]
    var rows: [[String]]
}

// MARK: - CSV

/// Comma, semicolon or tab separated, with quoted fields ("a, b" and "" for a quote).
func parseCSV(_ text: String, name: String = "CSV") -> Table? {
    let body = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    guard let firstLine = body.split(whereSeparator: \.isNewline).first else { return nil }
    let sep: Character = [",", ";", "\t"].max { a, b in firstLine.filter { $0 == a }.count < firstLine.filter { $0 == b }.count }!
    var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
    var chars = body.makeIterator()
    var pending: Character? = nil
    while let c = pending ?? chars.next() {
        pending = nil
        if quoted {
            if c == "\"" {
                if let n = chars.next() {
                    if n == "\"" { field.append("\"") } else { quoted = false; pending = n }
                } else { quoted = false }
            } else { field.append(c) }
        } else if c == "\"" && field.isEmpty {
            quoted = true
        } else if c == sep {
            row.append(field); field = ""
        } else if c == "\n" || c == "\r" || c == "\r\n" {
            row.append(field); field = ""
            if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
            row = []
        } else {
            field.append(c)
        }
    }
    row.append(field)
    if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
    guard let header = rows.first else { return nil }
    return Table(name: name, headers: header.map { $0.trimmingCharacters(in: .whitespaces) }, rows: Array(rows.dropFirst()))
}

// MARK: - XLSX (a zip of XML files)

/// Every worksheet in an .xlsx file, using the first non-empty row as headers.
func readXLSX(_ data: Data) -> [Table] {
    let files = unzip(data)
    let shared = files["xl/sharedStrings.xml"].map(parseSharedStrings) ?? []
    let names = files["xl/workbook.xml"].map(sheetNames) ?? []
    let sheets = files.keys.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
        .sorted { Int($0.filter(\.isNumber)) ?? 0 < Int($1.filter(\.isNumber)) ?? 0 }
    return sheets.enumerated().compactMap { i, path in
        var grid = parseSheet(files[path]!, shared: shared)
        while let f = grid.first, f.allSatisfy({ $0.isEmpty }) { grid.removeFirst() }
        guard let header = grid.first else { return nil }
        return Table(name: i < names.count ? names[i] : "Sheet \(i + 1)", headers: header.map { $0.trimmingCharacters(in: .whitespaces) },
                     rows: Array(grid.dropFirst()).filter { !$0.allSatisfy(\.isEmpty) })
    }
}

/// The files in a zip archive (stored or deflated entries).
func unzip(_ data: Data) -> [String: Data] {
    let b = [UInt8](data)
    func u16(_ i: Int) -> Int { i + 1 < b.count ? Int(b[i]) | Int(b[i + 1]) << 8 : 0 }
    func u32(_ i: Int) -> Int { i + 3 < b.count ? u16(i) | u16(i + 2) << 16 : 0 }
    // End of central directory: the last "PK\5\6".
    var eocd = b.count - 22
    while eocd >= 0 && u32(eocd) != 0x06054b50 { eocd -= 1 }
    guard eocd >= 0 else { return [:] }
    var p = u32(eocd + 16)
    var out: [String: Data] = [:]
    for _ in 0..<u16(eocd + 10) {
        guard u32(p) == 0x02014b50 else { break }
        let method = u16(p + 10), compSize = u32(p + 20), size = u32(p + 24)
        let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32), local = u32(p + 42)
        let name = String(decoding: b[(p + 46)..<min(b.count, p + 46 + nameLen)], as: UTF8.self)
        p += 46 + nameLen + extraLen + commentLen
        guard u32(local) == 0x04034b50 else { continue }
        let start = local + 30 + u16(local + 26) + u16(local + 28)
        guard start + compSize <= b.count else { continue }
        let raw = Data(b[start..<(start + compSize)])
        if method == 0 { out[name] = raw }
        else if method == 8, let d = inflate(raw, size: size) { out[name] = d }
    }
    return out
}

private func inflate(_ raw: Data, size: Int) -> Data? {
    guard size > 0 else { return Data() }
    var dst = [UInt8](repeating: 0, count: size)
    let n = raw.withUnsafeBytes { src in
        compression_decode_buffer(&dst, size, src.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB)  // raw DEFLATE
    }
    return n == size ? Data(dst) : nil
}

private final class XMLCollector: NSObject, XMLParserDelegate {
    var onStart: (String, [String: String]) -> Void = { _, _ in }
    var onEnd: (String, String) -> Void = { _, _ in }
    private var text = ""
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        text = ""; onStart(e, attributes)
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) { onEnd(e, text) }
    func run(_ data: Data) { let p = XMLParser(data: data); p.delegate = self; p.parse() }
}

private func parseSharedStrings(_ data: Data) -> [String] {
    var out: [String] = [], current = ""
    let c = XMLCollector()
    c.onStart = { e, _ in if e == "si" { current = "" } }
    c.onEnd = { e, t in if e == "t" { current += t } else if e == "si" { out.append(current) } }
    c.run(data)
    return out
}

private func sheetNames(_ data: Data) -> [String] {
    var out: [String] = []
    let c = XMLCollector()
    c.onStart = { e, a in if e == "sheet", let n = a["name"] { out.append(n) } }
    c.run(data)
    return out
}

private func parseSheet(_ data: Data, shared: [String]) -> [[String]] {
    var rows: [[String]] = [], row: [String] = []
    var col = 0, type = "", value = ""
    let c = XMLCollector()
    c.onStart = { e, a in
        switch e {
        case "row": row = []
        case "c":
            type = a["t"] ?? ""; value = ""
            col = a["r"].map { ref in ref.prefix { $0.isLetter }.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1 } ?? row.count
        default: break
        }
    }
    c.onEnd = { e, t in
        switch e {
        case "v", "t": value += t
        case "c":
            let cell = type == "s" ? (Int(value).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? "")
                : type == "b" ? (value == "1" ? "TRUE" : "FALSE") : value
            while row.count < col { row.append("") }
            row.append(cell)
        case "row": rows.append(row)
        default: break
        }
    }
    c.run(data)
    return rows
}

// MARK: - Recognising columns

enum Column: String, CaseIterable {
    case date, time, weight, trend, bodyFat, kcal, protein, fat, carbs, fiber, expenditure
    case targetKcal, targetProtein, targetFat, targetCarbs
    case food, amount, unit, exercise, setNumber, reps, rir, workout
}

/// Which column holds what, by header name ("Trend Weight (kg)", "Calories (kcal)", "Target Protein").
func recogniseColumns(_ headers: [String]) -> [Column: Int] {
    var out: [Column: Int] = [:]
    for (i, raw) in headers.enumerated() {
        let h = raw.lowercased()
        func has(_ words: String...) -> Bool { words.contains { h.contains($0) } }
        let target = has("target", "goal", "objetivo")
        let c: Column?
        switch true {
        case has("saturated", "trans fat", "monounsat", "polyunsat", "net carb", "sugar", "azúcar", "saturada"): c = nil
        case has("date", "fecha", "day") && !has("update"): c = .date
        case has("time", "hora") && !has("timestamp"): c = .time
        case has("timestamp"): c = .date
        case has("expenditure", "tdee", "gasto"): c = .expenditure
        case has("trend"): c = .trend
        case has("body fat", "bodyfat", "fat %", "grasa corporal"): c = .bodyFat
        case has("weight", "peso", "scale") && !has("trend"): c = has("set", "lift") ? nil : .weight
        case has("calorie", "energy", "kcal", "energía") && target: c = .targetKcal
        case has("calorie", "energy", "kcal", "energía"): c = .kcal
        case has("protein", "proteína") && target: c = .targetProtein
        case has("protein", "proteína"): c = .protein
        case has("carb", "hidratos") && target: c = .targetCarbs
        case has("carb", "hidratos"): c = .carbs
        case has("fiber", "fibre", "fibra"): c = .fiber
        case has("fat", "grasa") && target: c = .targetFat
        case has("fat", "grasa"): c = .fat
        case has("exercise", "ejercicio"): c = .exercise
        case has("rir", "reps in reserve"): c = .rir
        case has("reps", "repeticiones"): c = .reps
        case h == "set" || has("set #", "set number", "set order", "serie"): c = .setNumber
        case has("workout", "session", "entrenamiento"): c = .workout
        case has("food", "name", "alimento", "item"): c = .food
        case has("unit", "unidad"): c = .unit                       // before amount: "Serving Unit" is the unit
        case has("serving", "amount", "quantity", "cantidad"): c = .amount
        default: c = nil
        }
        if let c, out[c] == nil { out[c] = i }
    }
    return out
}

/// "kg" or "lb" if a header says so ("Weight (lbs)").
func unitInHeader(_ h: String) -> WeightUnit? {
    let l = h.lowercased()
    if l.contains("lb") { return .lb }
    if l.contains("kg") { return .kg }
    return nil
}

/// Dates as they appear in exports: 2026-10-14, 14/10/2026, 10/14/2026, 2026-10-14T08:30, or an Excel day number.
func parseImportDate(_ s: String) -> (day: String, time: Date?)? {
    let t = s.trimmingCharacters(in: .whitespaces)
    if let serial = Double(t), serial > 20000, serial < 80000 {            // Excel: days since 30 Dec 1899
        let d = Date(timeIntervalSince1970: (serial - 25569) * 86400)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        let day = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        let hasTime = serial != serial.rounded(.down)
        return (day, hasTime ? Calendar.current.date(bySettingHour: c.hour!, minute: c.minute!, second: 0, of: date(fromKey: day)) : nil)
    }
    let digits = t.split(whereSeparator: { !$0.isNumber }).map(String.init)
    guard digits.count >= 3, let a = Int(digits[0]), let b = Int(digits[1]), let c = Int(digits[2]) else { return nil }
    var y: Int, m: Int, d: Int
    if digits[0].count == 4 { (y, m, d) = (a, b, c) }                         // 2026-10-14
    else if a > 12 { (y, m, d) = (c, b, a) }                                   // 14/10/2026
    else if b > 12 { (y, m, d) = (c, a, b) }                                   // 10/14/2026
    else { (y, m, d) = (c, b, a) }                                             // ambiguous: day first, as in Spain
    if y < 100 { y += 2000 }
    guard (1...12).contains(m), (1...31).contains(d), (1990...2100).contains(y) else { return nil }
    let day = String(format: "%04d-%02d-%02d", y, m, d)
    var time: Date?
    if digits.count >= 5, let hh = Int(digits[3]), let mm = Int(digits[4]), hh < 24, mm < 60 {
        time = Calendar.current.date(bySettingHour: hh, minute: mm, second: 0, of: date(fromKey: day))
    }
    return (day, time)
}

/// "1.234,5", "1,234.5", "72,4", "" -> number
func parseImportNumber(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{00A0}", with: "")
    guard !t.isEmpty, t.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
    var x = t.filter { $0.isNumber || $0 == "," || $0 == "." || $0 == "-" }
    if x.contains(",") && x.contains(".") {
        if x.lastIndex(of: ",")! > x.lastIndex(of: ".")! { x = x.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else { x = x.replacingOccurrences(of: ",", with: "") }
    } else {
        x = x.replacingOccurrences(of: ",", with: ".")
    }
    return Double(x)
}

// MARK: - What a file contains

struct ImportDay: Equatable {
    var day: String
    var weightKg: Double?
    var bodyFat: Double?
    var nutrients: Nutrients?
    var expenditure: Double?
    var targets: Targets?
}

struct ImportFood: Equatable {
    var day: String
    var time: Date?
    var name: String
    var amountText: String
    var nutrients: Nutrients
}

struct ImportSet: Equatable {
    var day: String
    var time: Date?
    var workout: String
    var exercise: String
    var setNumber: Int
    var kg: Double
    var reps: Int
    var rir: Double?
}

struct ImportContents {
    var days: [ImportDay] = []
    var foods: [ImportFood] = []
    var sets: [ImportSet] = []
    var skipped: [String] = []                  // sheets we couldn't make sense of

    var isEmpty: Bool { days.isEmpty && foods.isEmpty && sets.isEmpty }
}

/// Sort each table into days (weight, totals, expenditure, targets), foods, or workout sets.
func interpret(_ tables: [Table], defaultUnit: WeightUnit) -> ImportContents {
    var out = ImportContents()
    var byDay: [String: ImportDay] = [:]
    for t in tables {
        let c = recogniseColumns(t.headers)
        guard let dateCol = c[.date] else { out.skipped.append(t.name); continue }
        func cell(_ r: [String], _ k: Column) -> String? { c[k].flatMap { r.indices.contains($0) ? r[$0] : nil } }
        func num(_ r: [String], _ k: Column) -> Double? { cell(r, k).flatMap(parseImportNumber) }
        func kg(_ v: Double?, _ k: Column) -> Double? { v.map { (c[k].flatMap { unitInHeader(t.headers[$0]) } ?? defaultUnit).toKg($0) } }

        if c[.exercise] != nil && c[.reps] != nil {                                  // a workout log
            for r in t.rows {
                guard let (day, time) = cell(r, .date).flatMap(parseImportDate), let ex = cell(r, .exercise), !ex.isEmpty,
                      let reps = num(r, .reps) else { continue }
                out.sets.append(ImportSet(day: day, time: time ?? cell(r, .time).flatMap { parseImportDate("\(day) \($0)")?.time },
                                          workout: cell(r, .workout) ?? "Workout", exercise: ex, setNumber: Int(num(r, .setNumber) ?? 0),
                                          kg: kg(num(r, .weight), .weight) ?? 0, reps: Int(reps), rir: num(r, .rir)))
            }
        } else if c[.food] != nil && c[.kcal] != nil {                               // a food log
            for r in t.rows {
                guard let (day, time) = cell(r, .date).flatMap(parseImportDate), let name = cell(r, .food), !name.isEmpty else { continue }
                let n = Nutrients(kcal: num(r, .kcal) ?? 0, protein: num(r, .protein) ?? 0, fat: num(r, .fat) ?? 0, carbs: num(r, .carbs) ?? 0,
                                  fiber: num(r, .fiber))
                let amount = [cell(r, .amount), cell(r, .unit)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
                out.foods.append(ImportFood(day: day, time: time ?? cell(r, .time).flatMap { parseImportDate("\(day) \($0)")?.time },
                                            name: name, amountText: amount, nutrients: n))
            }
        } else if [.weight, .kcal, .expenditure, .trend].contains(where: { c[$0] != nil }) {   // daily progress
            for r in t.rows {
                guard let (day, _) = cell(r, .date).flatMap(parseImportDate) else { continue }
                var d = byDay[day] ?? ImportDay(day: day)
                if let w = kg(num(r, .weight), .weight), (25...350).contains(w) { d.weightKg = w }
                if let bf = num(r, .bodyFat), (2...70).contains(bf) { d.bodyFat = bf }
                if let k = num(r, .kcal), k > 0 {
                    d.nutrients = Nutrients(kcal: k, protein: num(r, .protein) ?? 0, fat: num(r, .fat) ?? 0, carbs: num(r, .carbs) ?? 0, fiber: num(r, .fiber))
                }
                if let e = num(r, .expenditure), e > 500 { d.expenditure = e }
                if let tk = num(r, .targetKcal), tk > 0 {
                    d.targets = Targets(kcal: tk, protein: num(r, .targetProtein) ?? 0, fat: num(r, .targetFat) ?? 0, carbs: num(r, .targetCarbs) ?? 0)
                }
                byDay[day] = d
            }
        } else {
            out.skipped.append(t.name)
        }
    }
    out.days = byDay.values.sorted { $0.day < $1.day }
    out.foods.sort { ($0.day, $0.time ?? .distantPast) < ($1.day, $1.time ?? .distantPast) }
    out.sets.sort { ($0.day, $0.workout, $0.setNumber) < ($1.day, $1.workout, $1.setNumber) }
    return out
}

/// Read any supported file into tables.
func readTables(_ data: Data, fileName: String) -> [Table] {
    if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {                            // a zip: xlsx, or a zip of CSVs
        let x = readXLSX(data)
        if !x.isEmpty { return x }
        return unzip(data).filter { $0.key.lowercased().hasSuffix(".csv") }.sorted { $0.key < $1.key }.compactMap { k, v in
            parseCSV(String(decoding: v, as: UTF8.self), name: (k as NSString).lastPathComponent)
        }
    }
    let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    return parseCSV(text, name: fileName).map { [$0] } ?? []
}
