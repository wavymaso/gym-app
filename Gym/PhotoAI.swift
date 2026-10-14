import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import Vision

// Photo (and text) logging. A vision model names what's on the plate and estimates
// grams; the app then does what models are bad at:
//   · packaged food: barcodes in the photo are read on the device → the exact product
//   · foods you've logged before: your own food (its nutrition and your usual portion)
//   · otherwise the model's estimate per 100 g, with calories made to agree with the macros
// Your corrections to portions are remembered per food, and the foods you log become
// your foods, so the next photo of the same meal comes out closer.
//
// Engines: a model on your Mac (Ollama, free and private; the phone reaches it through
// sync), and Google Gemini's free tier as the fallback (needs a key).

/// What the model saw: one food, its portion and its nutrition per 100 g.
struct AIItem: Equatable {
    var name: String
    var nameES: String = ""
    var search: String = ""          // a short, generic search term
    var grams: Double
    var per100: Nutrients
    var isLiquid = false
    var packaged = false
    var brand: String?
    var confidence: Double = 0.6

    init(name: String, grams: Double, per100: Nutrients) { self.name = name; self.grams = grams; self.per100 = per100 }

    /// From the model's JSON, forgiving about numbers sent as text, and sanity-checked.
    init?(_ d: [String: Any]) {
        func num(_ k: String) -> Double? {
            if let n = d[k] as? Double { return n }
            if let n = d[k] as? Int { return Double(n) }
            if let s = d[k] as? String { return Double(s.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }) }
            return nil
        }
        func text(_ k: String) -> String { (d[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let name = text("name")
        guard !name.isEmpty, let g = num("grams"), g > 0 else { return nil }
        self.name = name
        nameES = text("name_es"); search = text("search").isEmpty ? name : text("search")
        grams = min(max(g, 1), 2000)
        let p = max(0, num("protein_100g") ?? num("protein") ?? 0), f = max(0, num("fat_100g") ?? num("fat") ?? 0)
        let c = max(0, num("carbs_100g") ?? num("carbs") ?? 0)
        let fiber = (num("fiber_100g") ?? num("fiber")).map { max(0, $0) }
        var kcal = max(0, num("kcal_100g") ?? num("kcal") ?? 0)
        // Calories that disagree with the macros: trust the macros (4/9/4, fibre 2).
        let fromMacros = 4 * p + 9 * f + 4 * max(0, c - (fiber ?? 0)) + 2 * (fiber ?? 0)
        if fromMacros > 0, kcal == 0 || abs(kcal - fromMacros) / fromMacros > 0.2 { kcal = fromMacros }
        per100 = Nutrients(kcal: min(kcal, 900), protein: min(p, 100), fat: min(f, 100), carbs: min(c, 100), fiber: fiber)
        isLiquid = d["liquid"] as? Bool ?? false
        packaged = d["packaged"] as? Bool ?? false
        brand = text("brand").isEmpty ? nil : text("brand")
        confidence = min(max(num("confidence") ?? 0.6, 0), 1)
    }

    var dict: [String: Any] {
        ["name": name, "name_es": nameES, "search": search, "grams": grams, "kcal_100g": per100.kcal, "protein_100g": per100.protein,
         "fat_100g": per100.fat, "carbs_100g": per100.carbs, "fiber_100g": per100.fiber ?? 0, "liquid": isLiquid, "packaged": packaged,
         "brand": brand ?? "", "confidence": confidence]
    }
}

enum PhotoAI {
    enum Engine: String, CaseIterable, Identifiable {
        case auto, mac, gemini
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Mac, then Gemini"
            case .mac: return "Only my Mac"
            case .gemini: return "Only Gemini"
            }
        }
    }

    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var engine: Engine { Engine(rawValue: UserDefaults.standard.string(forKey: "photoEngine") ?? "") ?? .auto }
    static var geminiKey: String { (UserDefaults.standard.string(forKey: "geminiKey") ?? "").trimmingCharacters(in: .whitespaces) }
    static var geminiModel: String {
        let m = (UserDefaults.standard.string(forKey: "geminiModel") ?? "").trimmingCharacters(in: .whitespaces)
        return m.isEmpty ? "gemini-flash-latest" : m
    }
    static var localModel: String {
        let m = (UserDefaults.standard.string(forKey: "localVisionModel") ?? "").trimmingCharacters(in: .whitespaces)
        return m.isEmpty ? "qwen3-vl:4b-instruct" : m
    }
    static let ollama = "http://127.0.0.1:11434"

    // MARK: Asking the model

    static func prompt(text: String, hasImage: Bool, photos: Int = 1) -> String {
        var p = """
        You are a meticulous dietitian logging a meal for someone in Spain (they also eat Saudi/Gulf food).
        \(hasImage ? "Look at the photo and identify every food and drink that will be eaten." : "Identify every food and drink in the description.")
        Rules:
        - One item per distinct food. A composed dish (paella, tortilla de patatas, lasagne, kabsa, a sandwich) is ONE item unless its parts are clearly separate on the plate.
        - Estimate the portion in grams (ml for drinks) as eaten. \(hasImage ? "Use visual scale: a dinner plate is about 26 cm, a fork 19 cm, a can 33 cl. Think about depth, not just area." : "Use amounts given; otherwise a typical adult portion.")
        - A whole pan, tray, cake or serving dish: estimate ONE person's portion of it, unless the person says they ate it all.
        - Include visible sauces, dressings and cooking oil as their own items when there's a noticeable amount.
        - The _100g fields are nutrition PER 100 g of the food as served (NOT for the portion), typical USDA/BEDCA values.
        - "search": 1 to 3 English words, the food first then how it's cooked, like a USDA name (e.g. "egg fried", "bread toasted", "rice white cooked", "chicken breast grilled", "paella seafood", "potato omelet").
        - "packaged": true only for a branded packaged product; give its "brand" if readable.
        - "confidence": 0 to 1, how sure you are of the identity and portion.
        Reply with JSON only: {"items":[{"name":"","name_es":"","search":"","grams":0,"kcal_100g":0,"protein_100g":0,"fat_100g":0,"carbs_100g":0,"fiber_100g":0,"liquid":false,"packaged":false,"brand":"","confidence":0.0}]}
        """
        if photos > 1 { p += "\n\nThe \(photos) photos show the SAME meal from different angles or parts of it: don't count anything twice." }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { p += "\n\nWhat the person says about the meal (trust it over the photo): \(t)" }
        return p
    }

    static func recipePrompt(text: String, hasImage: Bool) -> String {
        """
        You turn a recipe into a list of ingredients with weights. \(hasImage ? "The photos show a recipe (cookbook page, screenshot or the dish)." : "Below is a recipe, often an Instagram or TikTok caption.")
        Rules:
        - Every ingredient that is eaten, with its amount in grams (ml for liquids) for the WHOLE recipe. Convert cups, spoons, pieces and "1 can" to grams (1 tbsp oil 13 g, 1 egg 50 g, 1 cup cooked rice 160 g, 1 scoop whey 30 g).
        - Skip salt, pepper, water and spices under 5 g. Raw/dry weight when the recipe gives raw amounts.
        - "servings": how many portions it makes (from the text; else your best guess).
        - "name": a short name for the dish, in the recipe's language.
        - For each ingredient: name (as written), name_es (Spanish), search (1–3 English words, USDA-style, food first), grams, and nutrition PER 100 g (kcal_100g, protein_100g, fat_100g, carbs_100g, fiber_100g), confidence 0–1.
        Reply with JSON only: {"name":"","servings":0,"items":[{"name":"","name_es":"","search":"","grams":0,"kcal_100g":0,"protein_100g":0,"fat_100g":0,"carbs_100g":0,"fiber_100g":0,"liquid":false,"packaged":false,"brand":"","confidence":0.0}]}

        Recipe:
        \(text)
        """
    }

    static var recipeSchema: [String: Any] {
        var s = schema
        var props = s["properties"] as? [String: Any] ?? [:]
        props["name"] = ["type": "string"]; props["servings"] = ["type": "number"]
        s["properties"] = props
        s["required"] = ["name", "servings", "items"]
        return s
    }

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "items": ["type": "array", "items": [
                "type": "object",
                "properties": [
                    "name": ["type": "string"], "name_es": ["type": "string"], "search": ["type": "string"],
                    "grams": ["type": "number"], "kcal_100g": ["type": "number"], "protein_100g": ["type": "number"],
                    "fat_100g": ["type": "number"], "carbs_100g": ["type": "number"], "fiber_100g": ["type": "number"],
                    "liquid": ["type": "boolean"], "packaged": ["type": "boolean"], "brand": ["type": "string"],
                    "confidence": ["type": "number"],
                ],
                "required": ["name", "name_es", "search", "grams", "kcal_100g", "protein_100g", "fat_100g", "carbs_100g"],
            ]],
        ],
        "required": ["items"],
    ]

    /// The model on this Mac, through Ollama.
    static func askLocal(images: [Data], text: String) async throws -> [AIItem] {
        parse(try await askLocalRaw(images: images, text: text, recipe: false))
    }

    static func askLocalRaw(images: [Data], text: String, recipe: Bool) async throws -> String {
        let p = recipe ? recipePrompt(text: text, hasImage: !images.isEmpty) : prompt(text: text, hasImage: !images.isEmpty, photos: images.count)
        var message: [String: Any] = ["role": "user", "content": p]
        if !images.isEmpty { message["images"] = images.map { $0.base64EncodedString() } }
        let body: [String: Any] = ["model": localModel, "messages": [message], "stream": false, "format": recipe ? recipeSchema : schema,
                                   "options": ["temperature": 0.1, "num_ctx": 8192, "num_predict": 1500], "keep_alive": "15m"]
        var r = URLRequest(url: URL(string: "\(ollama)/api/chat")!, timeoutInterval: 240)
        r.httpMethod = "POST"; r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: r) } catch {
            throw Failure(message: "The photo model on the Mac isn't running. Open Ollama on the Mac.")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            let e = json["error"] as? String ?? ""
            if e.contains("not found") { throw Failure(message: "The Mac doesn't have the photo model yet (\(localModel)).") }
            throw Failure(message: "The photo model on the Mac failed. \(e)")
        }
        return (json["message"] as? [String: Any])?["content"] as? String ?? ""
    }

    /// Google Gemini (free tier with your own key). Busy or out of free quota: try once more,
    /// then the next model (each has its own free quota).
    static func askGemini(images: [Data], text: String) async throws -> [AIItem] {
        parse(try await askGeminiRaw(images: images, text: text, recipe: false))
    }

    static func askGeminiRaw(images: [Data], text: String, recipe: Bool) async throws -> String {
        guard !geminiKey.isEmpty else { throw Failure(message: "Add a free Gemini key in Settings → Photo logging.") }
        let models = Array(NSOrderedSet(array: [geminiModel, "gemini-2.5-flash", "gemini-flash-lite-latest"])) as? [String] ?? [geminiModel]
        var last: Failure?
        for (n, model) in models.enumerated() {
            for attempt in 0..<(n == 0 ? 2 : 1) {
                do { return try await askGemini(model: model, images: images, text: text, recipe: recipe) } catch let f as GeminiFailure {
                    last = Failure(message: f.message)
                    if !f.tryAnother { throw Failure(message: f.message) }
                    if f.status == 503 && attempt == 0 && n == 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) } else { break }
                }
            }
        }
        throw last ?? Failure(message: "Gemini didn't answer.")
    }

    private struct GeminiFailure: Error { let status: Int; let message: String; var tryAnother: Bool { [404, 429, 500, 503].contains(status) } }

    private static func askGemini(model: String, images: [Data], text: String, recipe: Bool) async throws -> String {
        var parts: [[String: Any]] = [["text": recipe ? recipePrompt(text: text, hasImage: !images.isEmpty)
                                                      : prompt(text: text, hasImage: !images.isEmpty, photos: images.count)]]
        for image in images { parts.append(["inline_data": ["mime_type": "image/jpeg", "data": image.base64EncodedString()]]) }
        let body: [String: Any] = ["contents": [["parts": parts]],
                                   "generationConfig": ["temperature": 0.1, "responseMimeType": "application/json"]]
        let m = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        var r = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(m):generateContent")!,
                           timeoutInterval: 90)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(geminiKey, forHTTPHeaderField: "x-goog-api-key")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: r)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "error \(status)"
            switch status {
            case 400, 403: throw GeminiFailure(status: status, message: "Gemini didn't accept the key: \(msg)")
            case 404: throw GeminiFailure(status: status, message: "Gemini doesn't know the model “\(model)”. Change it in Settings → Photo logging.")
            case 429: throw GeminiFailure(status: status, message: "Gemini's free limit is used up for now. Try again later, or use your Mac.")
            case 500, 503: throw GeminiFailure(status: status, message: "Gemini is busy right now. Try again in a minute, or use your Mac.")
            default: throw GeminiFailure(status: status, message: "Gemini: \(msg)")
            }
        }
        let out = (((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        return out.compactMap { $0["text"] as? String }.joined()
    }

    /// The model's answer → items (tolerates ```json fences or a bare list).
    static func parse(_ s: String) -> [AIItem] {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") { t = t.components(separatedBy: "\n").dropFirst().joined(separator: "\n").replacingOccurrences(of: "```", with: "") }
        if let data = t.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data) {
            let list = (any as? [String: Any])?["items"] as? [[String: Any]] ?? any as? [[String: Any]] ?? []
            return list.compactMap(AIItem.init)
        }
        // Cut off part-way (too long an answer): keep every item that's complete.
        var items: [AIItem] = [], depth = 0, start: String.Index?
        let body = t.range(of: "[").map { t[$0.upperBound...] } ?? t[...]
        for i in body.indices {
            switch body[i] {
            case "{": if depth == 0 { start = i }; depth += 1
            case "}":
                depth -= 1
                if depth == 0, let s = start,
                   let d = (try? JSONSerialization.jsonObject(with: Data(body[s...i].utf8))) as? [String: Any], let item = AIItem(d) {
                    items.append(item)
                }
            default: break
            }
        }
        return items
    }

    /// Ask whichever engine is set and reachable. Returns the items and who answered.
    @MainActor static func analyse(images: [Data], text: String) async throws -> (items: [AIItem], by: String) {
        let (raw, by) = try await analyseRaw(images: images, text: text, recipe: false)
        return (parse(raw), by)
    }

    /// A recipe from a caption, pasted text or cookbook photos: its name, servings and ingredients.
    @MainActor static func recipe(images: [Data], text: String) async throws -> (name: String, servings: Double?, items: [AIItem], by: String) {
        let (raw, by) = try await analyseRaw(images: images, text: text, recipe: true)
        let items = parse(raw)
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") { t = t.components(separatedBy: "\n").dropFirst().joined(separator: "\n").replacingOccurrences(of: "```", with: "") }
        let json = (try? JSONSerialization.jsonObject(with: Data(t.utf8))) as? [String: Any] ?? [:]
        let servings = (json["servings"] as? Double) ?? (json["servings"] as? Int).map(Double.init)
        return ((json["name"] as? String) ?? "", servings.flatMap { $0 > 0 ? $0 : nil }, items, by)
    }

    @MainActor static func analyseRaw(images: [Data], text: String, recipe: Bool) async throws -> (String, String) {
        var errors: [String] = []
        let e = engine
        if e != .gemini {
            do {
                #if os(macOS)
                return (try await askLocalRaw(images: images, text: text, recipe: recipe), "this Mac")
                #else
                let client = SyncClient.shared
                if client.connected {
                    return (try await client.photoRaw(images: images, text: text, recipe: recipe), client.macName)
                }
                errors.append("This iPhone isn't connected to your Mac (Settings → Mac sync).")
                #endif
            } catch let err as SyncClient.SyncError {
                errors.append(err.text)
            } catch let err as URLError where err.code == .timedOut {
                errors.append("Your Mac took too long to answer.")
            } catch let err as URLError {
                errors.append("Couldn't reach your Mac (\(err.code == .notConnectedToInternet ? "no connection" : "is it on, with Gym open?")).")
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        if e != .mac {
            if e == .gemini || !geminiKey.isEmpty {
                do { return (try await askGeminiRaw(images: images, text: text, recipe: recipe), "Gemini") } catch { errors.append(error.localizedDescription) }
            } else {
                errors.append("No Gemini key for when the Mac can't be reached (Settings → Photo logging).")
            }
        }
        throw Failure(message: errors.joined(separator: "\n"))
    }

    // MARK: The photo

    /// At most 1024 px on the long side, upright, as JPEG: plenty for the models, quick to send.
    static func prepare(_ data: Data, maxPixels: Int = 1024) -> (jpeg: Data, image: CGImage)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return (out as Data, img)
    }

    /// Barcodes visible in the photo (EAN/UPC), read on the device.
    static func barcodes(in image: CGImage) async -> [String] {
        await withCheckedContinuation { cont in
            let req = VNDetectBarcodesRequest { req, _ in
                let codes = (req.results as? [VNBarcodeObservation] ?? [])
                    .filter { [.ean13, .ean8, .upce, .code128].contains($0.symbology) }
                    .compactMap(\.payloadStringValue)
                cont.resume(returning: Array(NSOrderedSet(array: codes)) as? [String] ?? [])
            }
            do { try VNImageRequestHandler(cgImage: image).perform([req]) } catch { cont.resume(returning: []) }
        }
    }

    // MARK: Spanish and Gulf dishes USDA calls something else

    /// Local dish name (folded) → a USDA search that finds it or its nearest equivalent.
    static let dishes: [String: String] = [
        "tortilla de patatas": "omelet potatoes", "tortilla espanola": "omelet potatoes", "tortilla de patata": "omelet potatoes",
        "pan con tomate": "bread toasted", "pan tumaca": "bread toasted", "patatas bravas": "potato fried",
        "patatas fritas": "french fries", "croquetas": "ham croquette", "croqueta": "ham croquette",
        "jamon serrano": "ham prosciutto", "jamon iberico": "ham prosciutto", "lomo embuchado": "pork loin cured",
        "salmorejo": "gazpacho", "gazpacho": "gazpacho", "lentejas": "lentils", "garbanzos": "chickpeas",
        "cocido": "beef stew", "cocido madrileno": "beef stew", "fabada": "beans pork", "pulpo a la gallega": "octopus",
        "calamares": "squid fried", "calamares a la romana": "squid fried", "boquerones": "anchovy", "sardinas": "sardine",
        "albondigas": "meatballs sauce", "pisto": "ratatouille", "migas": "bread stuffing", "flan": "flan",
        "arroz con leche": "rice pudding", "natillas": "custard", "churros": "churros", "torrija": "french toast",
        "bocadillo": "sandwich", "ensaladilla rusa": "potato salad", "empanada": "empanada", "gambas al ajillo": "shrimp sauteed",
        "kabsa": "rice chicken", "mandi": "rice chicken", "machboos": "rice chicken", "biryani": "biryani",
        "shawarma": "gyro", "shawerma": "gyro", "kebab": "kabob", "kofta": "meatballs", "kibbeh": "meatballs",
        "falafel": "falafel", "hummus": "hummus", "mutabbal": "baba ghanoush", "moutabal": "baba ghanoush",
        "tabbouleh": "tabbouleh", "fattoush": "salad lettuce", "labneh": "yogurt greek", "laban": "buttermilk",
        "foul": "fava beans", "ful medames": "fava beans", "harees": "porridge wheat", "jareesh": "porridge wheat",
        "kunafa": "baklava", "kunafeh": "baklava", "luqaimat": "doughnut", "khubz": "pita bread", "samboosa": "samosa",
        "sambousek": "samosa", "dates": "dates medjool", "tamr": "dates medjool", "saleeg": "rice pudding",
    ]

    /// An item named as a local dish searches with the USDA name for it.
    static func translated(_ a: AIItem) -> AIItem {
        for n in [a.nameES, a.name, a.search].map(FoodAPI.fold) where !n.isEmpty {
            if let s = dishes[n] ?? dishes.first(where: { n.hasPrefix($0.key + " ") || n == $0.key })?.value {
                var b = a; b.search = s; return b
            }
        }
        return a
    }

    // MARK: Learning your portions

    private static let biasKey = "photoPortionBias"

    /// How your portions compare with the model's guesses: per food, and overall.
    static func portionFactor(for item: AIItem) -> Double {
        let all = UserDefaults.standard.dictionary(forKey: biasKey) as? [String: Double] ?? [:]
        return all[FoodAPI.fold(item.search)] ?? all["_all"] ?? 1
    }

    /// You logged `grams` where the model said `aiGrams` (before any learned factor).
    static func learn(search: String, aiGrams: Double, grams: Double) {
        guard aiGrams > 0, grams > 0 else { return }
        let ratio = min(max(grams / aiGrams, 0.3), 3)
        var all = UserDefaults.standard.dictionary(forKey: biasKey) as? [String: Double] ?? [:]
        let k = FoodAPI.fold(search)
        all[k] = (all[k] ?? 1) * 0.5 + ratio * 0.5
        all["_all"] = (all["_all"] ?? 1) * 0.9 + ratio * 0.1
        UserDefaults.standard.set(all, forKey: biasKey)
    }
}

// MARK: - From the model's items to what you log

/// One line on the plate: what it is, where its nutrition comes from, how much.
struct PlateItem: Identifiable, Equatable {
    enum Source: Equatable { case yours, product, generic, estimate, picked }
    let id = UUID()
    var ai: AIItem?                  // nil for a barcode found in the photo
    var name: String
    var detail: String?
    var per100: Nutrients
    var isLiquid: Bool
    var grams: Double
    var suggested: Double            // what the model (with your learned portions) said, for learning
    var foodKey: String?             // an existing food, or nil: logged as a new "ai:" food
    var product: FoodResult?         // a product or generic food to save as one of yours when logged
    var source: Source
    var options: [FoodResult] = []   // other close matches, to swap to in one tap
    var included = true

    var nutrients: Nutrients { per100.scaled(grams / 100) }
    var unit: String { isLiquid ? "ml" : "g" }

    static func == (a: PlateItem, b: PlateItem) -> Bool { a.id == b.id && a.grams == b.grams && a.included == b.included && a.name == b.name }
}

extension ModelContext {
    /// Match each item: your own foods first, then USDA's generic foods and dishes, then the
    /// model's own estimate. A portion far from what people usually eat is pulled toward it.
    func plate(from items: [AIItem], foods local: LocalFoods = .shared) -> [PlateItem] {
        let items = items.map(PhotoAI.translated)
        let mine = ((try? fetch(FetchDescriptor<Food>(predicate: #Predicate { $0.useCount > 0 }))) ?? [])
            .map { (food: $0, text: FoodAPI.fold("\($0.name) \($0.brand ?? "")")) }
        return items.map { a in
            var suggested = (a.grams * PhotoAI.portionFactor(for: a)).rounded()
            var generic = local.generic(a.search, limit: 6)
            if generic.isEmpty { generic = local.generic(a.name, limit: 6) }
            // A guess more than 3× off the usual portion is usually the model misjudging scale.
            if let typical = generic.first?.typical, typical > 0 {     // (models say they're sure even when they aren't)
                let r = suggested / typical
                if r > 3 || r < 1 / 3 { suggested = (suggested * typical).squareRoot().rounded() }
            }
            // Your food whose name contains every word of one of the item's names.
            let names = [a.nameES, a.name, a.search].map(FoodAPI.fold).filter { !$0.isEmpty }
            let match = mine.filter { m in
                names.contains { n in
                    let words = n.split(separator: " ").filter { $0.count > 2 }
                    return !words.isEmpty && words.allSatisfy { m.text.contains($0) }
                }
            }.max { $0.food.useCount < $1.food.useCount }?.food
            let options = generic.map(\.food)
            if let f = match {
                return PlateItem(ai: a, name: f.name, detail: f.brand, per100: f.per100, isLiquid: f.isLiquid,
                                 grams: suggested, suggested: suggested, foodKey: f.key, source: .yours, options: options)
            }
            // USDA's food (generic() only returns whole-word matches, missing at most one word).
            if let g = options.first {
                return PlateItem(ai: a, name: a.nameES.isEmpty ? a.name : a.nameES, detail: g.name, per100: g.per100,
                                 isLiquid: g.isLiquid || a.isLiquid, grams: suggested, suggested: suggested, product: g,
                                 source: .generic, options: Array(options.dropFirst()))
            }
            return PlateItem(ai: a, name: a.nameES.isEmpty ? a.name : a.nameES, detail: a.nameES.isEmpty ? nil : a.name,
                             per100: a.per100, isLiquid: a.isLiquid, grams: suggested, suggested: suggested, source: .estimate, options: options)
        }
    }

    /// Log the plate; learn from how you changed the portions.
    /// The plate as foods and grams (making foods for estimates); learns from changed portions.
    func foods(for plate: [PlateItem]) -> [(food: Food, grams: Double)] {
        plate.filter { $0.included && $0.grams > 0 }.map { item in
            if let a = item.ai, item.source != .picked {
                PhotoAI.learn(search: a.search, aiGrams: a.grams, grams: item.grams)
            }
            let food: Food
            if let k = item.foodKey, let f = self.food(key: k) {
                food = f
            } else if let p = item.product {
                food = self.food(for: p)
            } else {
                // A food of its own, so next time it's one of "your foods" (with your portion).
                let key = "ai:" + FoodAPI.fold(item.name).replacingOccurrences(of: " ", with: "-")
                if let f = self.food(key: key) { f.per100 = item.per100; food = f } else {
                    food = Food(key: key, name: item.name, brand: item.detail, source: "ai", per100: item.per100, isLiquid: item.isLiquid)
                    insert(food)
                }
            }
            return (food, item.grams.rounded())
        }
    }

    func log(plate: [PlateItem], day: String, time: Date) {
        for (food, grams) in foods(for: plate) { log(food, amount: grams, unit: food.baseUnit, day: day, time: time) }
    }
}
