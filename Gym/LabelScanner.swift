import PhotosUI
import SwiftUI
import Vision
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Nutrition label scanning: on-device text recognition (Vision) on a photo of the label,
// then the per-100 g column read row by row. Works for Spanish and English labels.

/// What a label says, per 100 g (or ml).
struct LabelValues: Equatable {
    var kcal: Double?
    var fat: Double?
    var satFat: Double?
    var carbs: Double?
    var sugar: Double?
    var fiber: Double?
    var protein: Double?
    var salt: Double?             // grams of salt; sodium = salt / 2,5
    var servingGrams: Double?

    var sodiumMg: Double? { salt.map { $0 * 400 } }
    var found: Int { [kcal, fat, satFat, carbs, sugar, fiber, protein, salt].compactMap { $0 }.count }
}

enum LabelReader {
    /// The label's text, one string per printed row (left to right, top to bottom).
    static func rows(from image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, err in
                if let err { cont.resume(throwing: err); return }
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                let items = obs.compactMap { o in o.topCandidates(1).first.map { (box: o.boundingBox, text: $0.string) } }
                cont.resume(returning: group(items))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["es-ES", "en-GB"]
            request.usesLanguageCorrection = false               // numbers and units, not prose
            do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { cont.resume(throwing: error) }
        }
    }

    /// Pieces of text on the same line (their vertical centres close together) joined into rows.
    static func group(_ items: [(box: CGRect, text: String)]) -> [String] {
        var rows: [(y: CGFloat, h: CGFloat, parts: [(x: CGFloat, text: String)])] = []
        for it in items.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let i = rows.firstIndex(where: { abs($0.y - it.box.midY) < max($0.h, it.box.height) * 0.6 }) {
                rows[i].parts.append((it.box.minX, it.text))
            } else {
                rows.append((it.box.midY, it.box.height, [(it.box.minX, it.text)]))
            }
        }
        return rows.sorted { $0.y > $1.y }.map { $0.parts.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
    }

    /// The per-100 g values from the label's rows (the first number after each nutrient's name).
    static func parse(_ rows: [String]) -> LabelValues {
        var v = LabelValues()
        var kj: Double?
        for raw in rows {
            let row = FoodAPI.fold(raw).replacingOccurrences(of: "\u{00A0}", with: " ")
            let nums = numbers(in: row)
            if v.kcal == nil, let k = firstMatch(#"(\d+(?:[.,]\d+)?)\s*kcal"#, row) { v.kcal = k }
            if kj == nil, let k = firstMatch(#"(\d+(?:[.,]\d+)?)\s*kj"#, row) { kj = k }
            if v.servingGrams == nil, row.contains("racion") || row.contains("porcion") || row.contains("serving") || row.contains("portion") {
                v.servingGrams = allMatches(#"(\d+(?:[.,]\d+)?)\s*(?:g|ml)\b"#, row).first { $0 != 100 }
            }
            guard let first = nums.first else { continue }
            func has(_ words: String...) -> Bool { words.contains { row.contains($0) } }
            if has("saturad", "saturate") { if v.satFat == nil { v.satFat = first } }
            else if has("grasa", "fat", "lipid") && !has("mono", "poli", "poly", "trans") { if v.fat == nil { v.fat = first } }
            else if has("azucar", "sugar") { if v.sugar == nil { v.sugar = first } }
            else if has("hidratos", "carbohidrat", "carbohydrate", "glucid") { if v.carbs == nil { v.carbs = first } }
            else if has("fibra", "fibre", "fiber") { if v.fiber == nil { v.fiber = first } }
            else if has("protein") { if v.protein == nil { v.protein = first } }
            else if row.hasPrefix("sal ") || row.hasPrefix("sal:") || row.contains(" sal ") || has("salt") { if v.salt == nil { v.salt = first } }
        }
        if v.kcal == nil, let kj { v.kcal = kj / 4.184 }
        return v
    }

    private static func numbers(in s: String) -> [Double] {
        // skip numbers that are part of "100 g" headers or kJ/kcal energy (handled separately)
        let cleaned = s.replacingOccurrences(of: #"(?:por|per)\s*100\s*(?:g|ml)"#, with: " ", options: .regularExpression)
        return allMatches(#"(?<![\d.,])(\d+(?:[.,]\d+)?)"#, cleaned)
    }

    private static func firstMatch(_ pattern: String, _ s: String) -> Double? { allMatches(pattern, s).first }

    private static func allMatches(_ pattern: String, _ s: String) -> [Double] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            Range(m.range(at: 1), in: s).flatMap { Double(s[$0].replacingOccurrences(of: ",", with: ".")) }
        }
    }
}

/// Pick or take a photo of a label, read it, then finish the food in the usual editor.
struct LabelScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var reading = false
    @State private var result: LabelValues?
    @State private var error: String?
    @State private var importing = false
    @State private var camera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "text.viewfinder").font(.system(size: 56)).foregroundStyle(palette.accent).padding(.top, 20)
                Text("Photograph the nutrition table, straight on and filling the frame. The numbers per 100 g are read; you check them before saving.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal)
                #if os(iOS)
                Button { camera = true } label: { Label("Take a photo", systemImage: "camera").frame(maxWidth: 260) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                #else
                Button { importing = true } label: { Label("Choose an image file…", systemImage: "folder").frame(maxWidth: 260) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                #endif
                PhotosPicker(selection: $item, matching: .images) { Label("Choose from Photos", systemImage: "photo").frame(maxWidth: 260) }
                    .buttonStyle(.bordered).controlSize(.large)
                if reading { ProgressView("Reading the label…") }
                if let error { Text(error).foregroundStyle(palette.warn).multilineTextAlignment(.center).padding(.horizontal) }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.pageBackground)
            .navigationTitle("Scan a label")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: item) { _, it in
                guard let it else { return }
                Task { if let data = try? await it.loadTransferable(type: Data.self) { await read(data) } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { r in
                guard case .success(let url) = r else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { Task { await read(data) } }
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $camera) { CameraPicker { data in Task { await read(data) } }.ignoresSafeArea() }
            #endif
            .sheet(item: Binding(get: { result.map { IdentifiedValues(values: $0) } }, set: { if $0 == nil { result = nil } }),
                   onDismiss: { dismiss() }) { r in
                CustomFoodView(food: nil, prefill: r.values)
            }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 440, height: 460)
        #endif
    }

    private func read(_ data: Data) async {
        guard let cg = cgImage(data) else { error = "That image couldn't be opened."; return }
        reading = true; error = nil
        defer { reading = false }
        do {
            let v = LabelReader.parse(try await LabelReader.rows(from: cg))
            if v.found < 3 || v.kcal == nil {
                error = "Couldn't read enough of the table (\(v.found) values). Try a sharper photo, closer and straight on."
            } else {
                result = v
            }
        } catch {
            self.error = "Text recognition failed: \(error.localizedDescription)"
        }
    }

    private func cgImage(_ data: Data) -> CGImage? {
        #if os(macOS)
        return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        guard let ui = UIImage(data: data) else { return nil }
        // Photos from the camera carry a rotation; draw them upright for Vision.
        let r = UIGraphicsImageRenderer(size: ui.size)
        return r.image { _ in ui.draw(in: CGRect(origin: .zero, size: ui.size)) }.cgImage
        #endif
    }
}

private struct IdentifiedValues: Identifiable {
    let id = UUID()
    let values: LabelValues
}

#if os(iOS)
/// The system camera, returning the photo as JPEG data.
struct CameraPicker: UIViewControllerRepresentable {
    let done: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage, let data = img.jpegData(compressionQuality: 0.9) { parent.done(data) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#endif
