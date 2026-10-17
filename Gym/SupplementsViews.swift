import SwiftData
import SwiftUI

/// Dashboard: today's supplements as chips to tick, with streaks.
struct SupplementsCard: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Supplement> { $0.active }, sort: \Supplement.order) private var list: [Supplement]
    @Query private var today: [SupplementTake]
    @State private var managing = false

    init() {
        let d = dayKey()
        _today = Query(filter: #Predicate<SupplementTake> { $0.day == d })
    }

    var body: some View {
        let taken = Set(today.map(\.supplementKey))
        Card(title: "Supplements", systemImage: "pills.fill",
             accessory: AnyView(Button(list.isEmpty ? "Add" : "Edit") { managing = true }.buttonStyle(.borderless).font(.label))) {
            if list.isEmpty {
                Text("Creatine, vitamin D, omega-3… tick them off each day and keep the streak going.").font(.secondaryText).foregroundStyle(.secondary)
                Button("Add supplements") { managing = true }.buttonStyle(.bordered)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(list.filter { taken.contains($0.key) }.count)/\(list.count)").font(.numberLarge).monospacedDigit()
                    Text("taken today").font(.secondaryText).foregroundStyle(.secondary)
                    Spacer()
                }
                FlowChips(items: list) { s in
                    let on = taken.contains(s.key)
                    Button {
                        animate(Motion.snappy) { ctx.toggleTake(s, on: dayKey()) }
                        #if os(iOS)
                        Haptics.tap()
                        #endif
                    } label: {
                        HStack(spacing: Space.s) {
                            Text(s.emoji)
                            Text(s.name).font(.secondaryEmphasis)
                            if on { Image(systemName: "checkmark").font(.label) }
                            let st = ctx.streak(s)
                            if st > 1 { Text("🔥\(st)").font(.fineLabel).monospacedDigit() }
                        }
                        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                        .background(on ? palette.good.opacity(0.85) : Color.raisedBackground, in: Capsule())
                        .foregroundStyle(on ? palette.onData : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $managing) { SupplementsEditor() }
    }
}

/// Chips that wrap onto new lines.
struct FlowChips<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    var body: some View {
        FlowLayout(spacing: Space.s) { ForEach(items) { content($0) } }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing; row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

/// Add, edit, reorder and remove supplements; see the last two weeks.
struct SupplementsEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Supplement> { $0.active }, sort: \Supplement.order) private var list: [Supplement]
    @Query private var recent: [SupplementTake]
    @State private var name = ""
    @State private var dose = ""
    @State private var emoji = "💊"
    @State private var timing = SupplementTiming.any

    init() {
        let from = addDays(dayKey(), -13)
        _recent = Query(filter: #Predicate<SupplementTake> { $0.day >= from })
    }

    var body: some View {
        let days = (0..<14).map { addDays(dayKey(), $0 - 13) }
        NavigationStack {
            List {
                if !list.isEmpty {
                    Section("Yours · last 14 days") {
                        ForEach(list) { s in
                            VStack(alignment: .leading, spacing: Space.s) {
                                HStack {
                                    Text(s.emoji)
                                    VStack(alignment: .leading, spacing: Space.hairline) {
                                        Text(s.name).font(.cardTitle)
                                        Text([s.dose, SupplementTiming(rawValue: s.timing)?.label].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.note).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("🔥 \(ctx.streak(s))").font(.label).monospacedDigit()
                                }
                                HStack(spacing: Space.xs) {
                                    ForEach(days, id: \.self) { d in
                                        let on = recent.contains { $0.day == d && $0.supplementKey == s.key }
                                        RoundedRectangle(cornerRadius: Radius.xs).fill(on ? palette.good : Color.raisedBackground).frame(height: 14)
                                            .onTapGesture { ctx.toggleTake(s, on: d) }
                                    }
                                }
                            }
                            .padding(.vertical, Space.xs)
                        }
                        .onDelete { idx in for i in idx { list[i].active = false }; ctx.commit() }
                        .onMove { from, to in
                            var l = list; l.move(fromOffsets: from, toOffset: to)
                            for (i, s) in l.enumerated() { s.order = i }
                            ctx.commit()
                        }
                    }
                }
                Section("Add your own") {
                    HStack {
                        TextField("💊", text: $emoji).frame(width: 36)
                        TextField("Name", text: $name)
                        TextField("Dose", text: $dose).frame(width: 90)
                    }
                    Picker("When", selection: $timing) { ForEach(SupplementTiming.allCases) { Text($0.label).tag($0) } }
                    Button("Add") { add(name, dose, emoji, timing.rawValue); name = ""; dose = "" }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section("Quick add") {
                    let have = Set(list.map { $0.name.lowercased() })
                    ForEach(supplementSuggestions.filter { !have.contains($0.0.lowercased()) }, id: \.0) { s in
                        Button { add(s.0, s.1, s.2, s.3) } label: {
                            HStack { Text(s.2); Text(s.0); Spacer(); Text(s.1).foregroundStyle(.secondary); Image(systemName: "plus.circle.fill") }
                        }
                    }
                }
            }
            .themedList()
            .navigationTitle("Supplements")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                #endif
            }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 520, height: 640)
        #endif
    }

    private func add(_ n: String, _ d: String, _ e: String, _ t: String) {
        ctx.insert(Supplement(name: n.trimmingCharacters(in: .whitespaces), dose: d, emoji: e.isEmpty ? "💊" : String(e.prefix(2)), timing: t,
                              order: (list.map(\.order).max() ?? -1) + 1))
        ctx.commit()
    }
}
