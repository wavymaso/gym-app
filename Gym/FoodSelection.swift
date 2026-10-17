import SwiftData
import SwiftUI

#if os(iOS)
/// 1811 🔥  145 P  32 F  236 C — an hour's (or meal's) totals as small chips.
struct HourTotals: View {
    let n: Nutrients
    let energy: EnergyUnit

    var body: some View {
        HStack(spacing: Space.m) {
            chip(number(energy.fromKcal(n.kcal)), icon: "flame.fill", color: palette.calories)
            chip(number(n.protein), letter: "P", color: palette.protein)
            chip(number(n.fat), letter: "F", color: palette.fat)
            chip(number(n.carbs), letter: "C", color: palette.carbs)
        }
        .font(.secondaryEmphasis).monospacedDigit()
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    private func chip(_ v: String, icon: String? = nil, letter: String? = nil, color: Color) -> some View {
        HStack(spacing: Space.xs) {
            Text(v)
            Group {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
                else { Text(letter ?? "").font(.system(size: 11, weight: .heavy)) }
            }
            .foregroundStyle(color)
            .frame(width: 20, height: 20)
            .background(color.opacity(0.18), in: Circle())
        }
    }
}

/// A logged food: emoji, name, kcal and macros (coloured letters), amount, and an edit button.
struct EntryCard: View {
    let entry: FoodEntry
    let energy: EnergyUnit
    var tap: (() -> Void)? = nil
    let edit: () -> Void

    var body: some View {
        let n = entry.nutrients
        Button(action: tap ?? edit) {
            HStack(spacing: Space.m) {
                Text(foodEmoji(entry))
                    .font(.iconMedium)
                    .frame(width: 46, height: 46)
                    .background(dominant(n).opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(entry.name).font(.bodyEmphasis).lineLimit(2).multilineTextAlignment(.leading)
                    FoodMacroLine(kcal: energy.fromKcal(n.kcal), protein: n.protein, fat: n.fat, carbs: n.carbs,
                              amount: entry.isQuickAdd ? nil : entry.amountText, colored: true)
                }
                Spacer(minLength: 4)
                if tap == nil {
                    Image(systemName: "pencil").font(.secondaryEmphasis)
                        .frame(width: 36, height: 36).background(Color.raisedBackground, in: Circle())
                }
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.m)
            .modifier(CardSurface(cornerRadius: Radius.l))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name), \(Int(entry.nutrients.kcal)) calories, \(Int(entry.nutrients.protein)) grams protein, \(entry.amountText)")
        .accessibilityHint(tap == nil ? "Edit" : "Select")
    }

    private func dominant(_ n: Nutrients) -> Color {
        let p = n.protein * 4, f = n.fat * 9, c = n.carbs * 4
        return p >= f && p >= c ? palette.protein : f >= c ? palette.fat : palette.carbs
    }
}

/// Which logged foods are selected, and whether you're choosing where to copy or move them to.
@MainActor final class FoodSelection: ObservableObject {
    enum Mode { case copy, move }
    static let shared = FoodSelection()
    @Published var ids: Set<String> = []
    @Published var mode: Mode?
    @Published var editing: FoodEntry?
    var day = dayKey()                  // the day on screen
    var sourceDay = dayKey()            // the day the selected foods are on

    func clear() { animate(Motion.snappy) { ids = []; mode = nil } }
}

/// MacroFactor's bar for selected foods. Copy and Move turn it into a destination bar, and every
/// hour of the timeline (on any day) becomes a place to paste them.
struct SelectionBar: View {
    @Environment(\.modelContext) private var ctx
    @ObservedObject private var sel = FoodSelection.shared
    @State private var picking = false
    @State private var target = Date()

    private var chosen: [FoodEntry] { ctx.entries(on: sel.sourceDay).filter { sel.ids.contains($0.syncID) } }
    private var countText: String { "\(sel.ids.count) food\(sel.ids.count == 1 ? "" : "s")" }

    var body: some View {
        HStack(spacing: Space.m) {
            Button {
                if sel.mode != nil { animate(Motion.snappy) { sel.mode = nil } } else { sel.clear() }
            } label: {
                Image(systemName: sel.mode == nil ? "xmark" : "chevron.left").font(.cardTitle)
                    .frame(width: 40, height: 40)
                    .background(sel.mode == nil ? Color.primary : Color.clear, in: Circle())
                    .foregroundStyle(sel.mode == nil ? palette.onInverse : .primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 0) {
                Text(sel.mode == .copy ? "Copy" : sel.mode == .move ? "Move" : "Select").font(.secondaryEmphasis)
                Text(countText).font(.note).foregroundStyle(.secondary)
            }
            .contentTransition(.opacity)
            Divider().frame(height: 36)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    switch sel.mode {
                    case .copy?:
                        action("To Now") { finish { ctx.copyEntries(chosen, to: dayKey(), at: Date()) } }
                        action("To Today") { finish { ctx.copyEntries(chosen, to: dayKey()) } }
                        action("To Tomorrow") { finish { ctx.copyEntries(chosen, to: addDays(dayKey(), 1)) } }
                        action("To Date & Time") { target = Date(); picking = true }
                    case .move?:
                        action("To Now") { finish { ctx.moveEntries(chosen, to: dayKey(), at: Date()) } }
                        action("To Today") { finish { ctx.moveEntries(chosen, to: dayKey()) } }
                        action("To Tomorrow") { finish { ctx.moveEntries(chosen, to: addDays(dayKey(), 1)) } }
                        action("To Date & Time") { target = Date(); picking = true }
                    case nil:
                        if sel.ids.count == 1, let e = chosen.first { action("Edit") { sel.clear(); sel.editing = e } }
                        action("Copy") { animate(Motion.snappy) { sel.mode = .copy } }
                        action("Move") { animate(Motion.snappy) { sel.mode = .move } }
                        action("Remove", destructive: true) { remove() }
                        Menu {
                            Button("Duplicate", systemImage: "plus.square.on.square") { let c = chosen; sel.clear(); ctx.duplicateEntries(c) }
                            Button("Save as meal", systemImage: "square.and.arrow.down") {
                                ctx.saveMeal(chosen.first?.name ?? "Meal", from: chosen); sel.clear(); Haptics.success()
                            }
                            Button("Select all", systemImage: "checkmark.circle") { sel.ids = Set(ctx.entries(on: sel.sourceDay).map(\.syncID)) }
                        } label: { pill("More") }
                        .menuStyle(.button).buttonStyle(.plain)
                    }
                }
                .id(sel.mode.map { "\($0)" } ?? "select")
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.m)
        .background(.bar)
        .animation(Motion.pick(Motion.smooth), value: sel.mode)
        .sheet(isPresented: $picking) {
            NavigationStack {
                DatePicker("When", selection: $target, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical).padding()
                    .navigationTitle(sel.mode == .copy ? "Copy to" : "Move to").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { picking = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(sel.mode == .copy ? "Copy" : "Move") {
                                let d = dayKey(target), t = target, m = sel.mode
                                picking = false
                                finish { if m == .copy { ctx.copyEntries(chosen, to: d, at: t) } else { ctx.moveEntries(chosen, to: d, at: t) } }
                            }
                            .fontWeight(.semibold)
                        }
                    }
            }
            .appStyle().presentationDetents([.large])
        }
    }

    /// Do it, then leave selection.
    private func finish(_ f: () -> Void) { f(); sel.clear() }

    private func action(_ t: String, destructive: Bool = false, _ f: @escaping () -> Void) -> some View {
        Button(action: f) { pill(t, destructive: destructive) }.pressable()
    }

    private func pill(_ t: String, destructive: Bool = false) -> some View {
        Text(t).font(.secondaryEmphasis).foregroundStyle(destructive ? palette.warn : .primary)
            .padding(.horizontal, Space.l).frame(height: 40).background(Color.raisedBackground, in: Capsule())
    }

    private func remove() {
        let c = chosen
        sel.clear()
        ctx.deleteWithUndo(c, c.count == 1 ? "\(c[0].name) removed" : "\(c.count) foods removed")
    }
}
#endif
