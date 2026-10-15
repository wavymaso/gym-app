import Charts
import SwiftData
import SwiftUI

/// Log today's (or another day's) weight, from anywhere.
struct WeighInSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @Query(sort: \WeightEntry.day, order: .reverse) private var weights: [WeightEntry]
    @State private var text = ""
    @State private var day = Date()
    @AppStorage("lastScale") private var scale = ""
    @FocusState private var focused: Bool

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        let names = profiles.first?.scaleNames ?? []
        NavigationStack {
            VStack(spacing: 18) {
                if !names.isEmpty {
                    Picker("Scale", selection: $scale) {
                        Text("Main").tag("")
                        ForEach(names, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 320)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("", text: $text, prompt: Text(weights.first.map { number(unit == .kg ? $0.kg : $0.kg / 0.45359237, digits: 1) } ?? "78,4"))
                        .font(.number(56)).multilineTextAlignment(.center).focused($focused).frame(maxWidth: 220)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                // From your last weigh-in, a tenth at a time: often no typing at all.
                                Button { nudge(-0.1) } label: { Text("−0,1").monospacedDigit() }
                                Button { nudge(0.1) } label: { Text("+0,1").monospacedDigit() }
                                Spacer()
                                Button("Save", action: save).fontWeight(.semibold).disabled(kg == nil)
                            }
                        }
                        #endif
                        .onSubmit(save)
                    Text(unit.rawValue).font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                }
                DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                    .frame(maxWidth: 280)
                if let w = weights.first {
                    Text("Last: \(unit.format(w.kg)) \(relative(w.day))").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .pageBackground()
            .navigationTitle("Weigh in")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(kg == nil) }
            }
            .onAppear { focused = true }
        }
        #if os(macOS)
        .frame(width: 380, height: 300)
        #else
        .presentationDetents([.medium])
        #endif
        .appStyle()
    }

    private var kg: Double? {
        guard let v = parseImportNumber(text), v > 20, v < 700 else { return nil }
        return (profiles.first?.weight ?? .kg) == .kg ? v : v * 0.45359237
    }

    private func nudge(_ d: Double) {
        let unit = profiles.first?.weight ?? .kg
        let last = weights.first.map { unit == .kg ? $0.kg : $0.kg / 0.45359237 } ?? 75
        let v = ((parseImportNumber(text) ?? last) + d) * 10
        text = number(v.rounded() / 10, digits: 1)
        Haptics.tick()
    }

    private func save() {
        guard let kg else { return }
        ctx.logWeight(kg, on: dayKey(day), scale: (profiles.first?.scaleNames ?? []).contains(scale) ? scale : "")
        Haptics.tap()
        dismiss()
    }
}
