import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Import from MacroFactor (or a similar app): choose the exported files, check what was found, import.
struct ImportView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @State private var choosing = false
    @State private var contents: ImportContents?
    @State private var fileNames: [String] = []
    @State private var result: ImportResult?
    @State private var error: String?

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        NavigationStack {
            Form {
                if let result {
                    Section("Imported") {
                        line("Weigh-ins", result.weights)
                        line("Days of food, item by item", result.foodDays)
                        line("Days of food, as day totals", result.totalDays)
                        line("Workouts", result.workouts)
                        line("Sets", result.sets)
                        line("New exercises (not in the library)", result.newExercises)
                        line("Target changes", result.targetChanges)
                        if let s = result.historyStart {
                            Text("Your expenditure estimate now learns from your history since \(date(fromKey: s).formatted(.dateTime.day().month(.wide).year().locale(appLocale))).")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                } else if let c = contents {
                    Section("Found in \(fileNames.joined(separator: ", "))") {
                        let weighed = c.days.filter { $0.weightKg != nil }
                        if let f = c.days.first, let l = c.days.last { LabeledContent("Days", value: "\(c.days.count) · \(short(f.day)) to \(short(l.day))") }
                        line("Weigh-ins", weighed.count)
                        line("Days with calories", c.days.filter { $0.nutrients != nil }.count)
                        line("Foods (item by item)", c.foods.count)
                        line("Workout sets", c.sets.count)
                        if let e = c.days.last(where: { $0.expenditure != nil })?.expenditure {
                            LabeledContent("Latest expenditure", value: "\(number(e)) kcal")
                        }
                        if let w = weighed.last?.weightKg { LabeledContent("Latest weigh-in", value: unit.format(w)) }
                        if !c.skipped.isEmpty {
                            Text("Not recognised: \(c.skipped.joined(separator: ", "))").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        Text("Days you've already logged here, weigh-ins you already have, and workouts already in your history are left as they are. Importing the same file again adds nothing.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("In MacroFactor, find Export data in its settings. The Quick Export spreadsheet has weight, trend, calories, macros, expenditure and targets; the Granular Export adds your food log and workouts. Choose all the files at once.")
                            .font(.callout)
                        Button("Choose files…") { choosing = true }
                    }
                }
                if let error { Text(error).foregroundStyle(Macro.protein.color) }
            }
            .formStyle(.grouped)
            .navigationTitle("Import from MacroFactor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(result == nil ? "Cancel" : "Done") { dismiss() } }
                if result == nil, let c = contents, !c.isEmpty {
                    ToolbarItem(placement: .confirmationAction) { Button("Import") { result = ctx.applyImport(c) } }
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText, .plainText, .zip, .spreadsheet,
                                                                           UTType(filenameExtension: "xlsx") ?? .data],
                          allowsMultipleSelection: true, onCompletion: read)
        }
        .environment(\.locale, appLocale)       // sheets don't inherit it on the Mac
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
    }

    private func line(_ label: String, _ n: Int) -> some View {
        LabeledContent(label, value: "\(n)")
    }

    private func short(_ day: String) -> String { date(fromKey: day).formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale)) }

    private func read(_ r: Result<[URL], Error>) {
        error = nil
        guard case .success(let urls) = r else { error = "Couldn't open those files."; return }
        var tables: [Table] = []
        for url in urls {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { error = "Couldn't read \(url.lastPathComponent)."; continue }
            tables += readTables(data, fileName: url.lastPathComponent)
        }
        let c = interpret(tables, defaultUnit: profiles.first?.weight ?? .kg)
        fileNames = urls.map(\.lastPathComponent)
        if c.isEmpty { error = "Nothing recognisable in \(fileNames.joined(separator: ", ")). Send me the file and I'll teach the importer its format." }
        contents = c
    }
}
