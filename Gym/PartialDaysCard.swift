import SwiftData
import SwiftUI

/// The dashboard card: "Were these days fully logged?" Until you answer, they're left out of expenditure.
struct PartialDaysCard: View {
    @Environment(\.modelContext) private var ctx
    @State private var days: [String] = []

    var body: some View {
        Group {
            if !days.isEmpty {
                VStack(alignment: .leading, spacing: Space.m) {
                    Label("Were these days fully logged?", systemImage: "questionmark.circle").font(.cardTitle)
                    Text("They have far fewer entries than usual. Until you answer, they're left out of your expenditure estimate.")
                        .font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(days.prefix(4), id: \.self) { d in
                        HStack(spacing: Space.s) {
                            VStack(alignment: .leading, spacing: Space.hairline) {
                                Text(date(fromKey: d).formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(appLocale))).font(.secondaryText.weight(.semibold))
                                Text(summary(d)).font(.fine).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Spacer()
                            Button("Complete") { answer(d, true) }.buttonStyle(.bordered).controlSize(.small)
                            Button("Partly") { answer(d, false) }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                .padding(Space.l)
                .modifier(CardSurface())
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear { days = ctx.suspectedPartialDays }
    }

    private func summary(_ d: String) -> String {
        let es = ctx.entries(on: d)
        let kcal = es.reduce(0) { $0 + $1.nutrients.kcal }
        let t = ctx.dayTargets(on: d)?.kcal ?? 0
        return "\(es.count) entr\(es.count == 1 ? "y" : "ies") · \(Int(kcal)) of \(Int(t)) kcal"
    }

    private func answer(_ d: String, _ complete: Bool) {
        ctx.answerPartial(d, complete: complete)
        Haptics.tap()
        animate(Motion.smooth) { days.removeAll { $0 == d } }
    }
}
