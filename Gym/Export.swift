import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// Your data as CSV files (open in Numbers or Excel). Semicolons and decimal commas, as
// Spanish spreadsheets expect.

enum Export: String, CaseIterable, Identifiable {
    case food, weights, workouts, water
    var id: String { rawValue }
    var label: String { ["Food log", "Weigh-ins", "Workouts", "Water & steps"][Self.allCases.firstIndex(of: self)!] }
    var filename: String { "Gym \(label) \(dayKey()).csv" }

    @MainActor func csv(_ ctx: ModelContext) -> String {
        func n(_ v: Double?) -> String { v.map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? "" }
        func q(_ s: String?) -> String { "\"" + (s ?? "").replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var rows: [String] = []
        switch self {
        case .food:
            rows.append("Day;Time;Meal;Name;Brand;Amount;Unit;Grams;kcal;Protein;Fat;Carbs;Fibre;Sugar;Saturated fat;Sodium mg")
            for e in (try? ctx.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.day), SortDescriptor(\.time)]))) ?? [] {
                let x = e.nutrients
                rows.append([e.day, e.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(appLocale)),
                             Meal(time: e.time).label, q(e.name), q(e.brand), n(e.amount), q(e.unit), n(e.grams), n(x.kcal), n(x.protein),
                             n(x.fat), n(x.carbs), n(x.fiber), n(x.sugar), n(x.satFat), n(x.sodium)].joined(separator: ";"))
            }
        case .weights:
            rows.append("Day;kg;Body fat %")
            for w in (try? ctx.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.day)]))) ?? [] {
                rows.append([w.day, n(w.kg), n(w.bodyFatPercent)].joined(separator: ";"))
            }
        case .workouts:
            rows.append("Day;Workout;Exercise;Set;Kind;kg;Reps;RIR;Done")
            let names = Dictionary(((try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []).map { ($0.key, $0.name) }, uniquingKeysWith: { a, _ in a })
            for w in (try? ctx.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.start)]))) ?? [] where w.end != nil {
                for s in ctx.sets(of: w.key) {
                    rows.append([w.day, q(w.name), q(names[s.exerciseKey] ?? s.exerciseKey), "\(s.setOrder + 1)", s.kindValue.label,
                                 n(s.kg), "\(s.reps)", n(s.rir), s.done ? "yes" : "no"].joined(separator: ";"))
                }
            }
        case .water:
            rows.append("Day;Water ml;Steps;Active kcal")
            let water = Dictionary(grouping: (try? ctx.fetch(FetchDescriptor<WaterEntry>())) ?? [], by: \.day).mapValues { $0.reduce(0) { $0 + $1.ml } }
            let act = Dictionary(((try? ctx.fetch(FetchDescriptor<DailyActivity>())) ?? []).map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
            for d in Set(water.keys).union(act.keys).sorted() {
                rows.append([d, n(water[d]), act[d].map { "\($0.steps)" } ?? "", n(act[d]?.activeKcal)].joined(separator: ";"))
            }
        }
        return "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"      // BOM so Excel reads accents
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

/// Settings: export each kind of data.
struct ExportSection: View {
    @Environment(\.modelContext) private var ctx
    @State private var exporting: Export?
    @State private var document = CSVDocument(text: "")
    @State private var done: String?
    @State private var archive: JSONDocument?
    @State private var withPhotos = false

    var body: some View {
        Section {
            Button {
                archive = JSONDocument(data: Backup.data(ctx, photos: withPhotos))
            } label: { Label("Everything (JSON archive)", systemImage: "archivebox") }
            Toggle("Include progress photos", isOn: $withPhotos)
            ForEach(Export.allCases) { e in
                Button { document = CSVDocument(text: e.csv(ctx)); exporting = e } label: { Label("\(e.label) (CSV)", systemImage: "square.and.arrow.up") }
            }
            if let done { Text(done).font(.secondaryText).foregroundStyle(palette.good) }
        } header: {
            Text("Export your data")
        } footer: {
            Text("The archive holds every record exactly (restore it from Backups on any device); the CSV files open in Numbers or Excel. Progress photos stay out unless you include them.")
        }
        .fileExporter(isPresented: Binding(get: { archive != nil }, set: { if !$0 { archive = nil } }), document: archive,
                      contentType: .json, defaultFilename: "Gym archive \(dayKey()).json") { r in
            if case .success(let url) = r { done = "Saved \(url.lastPathComponent)" }
            archive = nil
        }
        .fileExporter(isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }), document: document,
                      contentType: .commaSeparatedText, defaultFilename: exporting?.filename ?? "Gym.csv") { r in
            if case .success(let url) = r { done = "Saved \(url.lastPathComponent)" }
            exporting = nil
        }
    }
}


struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
