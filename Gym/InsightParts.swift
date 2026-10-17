import Charts
import SwiftData
import SwiftUI

/// A tiny filled sparkline for the changes table.
struct MiniArea: View {
    let values: [Double]
    let color: Color
    var body: some View {
        if values.count >= 2 {
            let lo = values.min()!, hi = values.max()!
            Chart(Array(values.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("i", i), yStart: .value("lo", lo - (hi - lo) * 0.1), yEnd: .value("v", v)).foregroundStyle(color.opacity(0.25))
                LineMark(x: .value("i", i), y: .value("v", v)).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 1.8))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: (lo - (hi - lo) * 0.1 - 0.0001)...(hi + 0.0001))
        } else {
            Capsule().fill(color.opacity(0.2)).frame(height: 2)
        }
    }
}

struct TintIconLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s) { configuration.icon.foregroundStyle(color); configuration.title }
    }
}

/// Change or delete one weigh-in.
struct EditWeighIn: View {
    let entry: WeightEntry
    let unit: WeightUnit
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Day", value: date(fromKey: entry.day).formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(appLocale)))
                HStack {
                    TextField("Weight", text: $text)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(unit.rawValue).foregroundStyle(.secondary)
                }
                Button("Delete weigh-in", role: .destructive) { dismiss(); ctx.deleteWithUndo([entry], "Weigh-in deleted") }
            }
            .themedForm()
            .navigationTitle("Weigh-in")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let v = parseNumber(text), v > 0 { entry.kg = unit.toKg(v); ctx.commit() }
                        dismiss()
                    }
                }
            }
        }
        .appStyle()
        .presentationDetents([.medium])
        .onAppear { text = number(unit.fromKg(entry.kg), digits: 1) }
    }
}
