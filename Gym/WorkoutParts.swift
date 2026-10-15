import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#else
import AudioToolbox
#endif

/// A number field that accepts "62,5" or "62.5" and saves when you leave it or press return.
struct DecimalField: View {
    @Binding var value: Double
    var digits = 1
    var emptyBelowZero = false
    var step: Double? = nil                 // the keyboard's − / + (a plate's worth, or one rep)
    var onLog: (() -> Void)? = nil          // the keyboard's "Log set"
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(emptyBelowZero ? "–" : "0"))
            .multilineTextAlignment(.trailing).monospacedDigit().focused($focused)
            #if os(iOS)
            .keyboardType(.decimalPad)
            .textFieldStyle(.plain)
            .padding(.horizontal, 8).frame(height: 34)
            .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(focused ? palette.accent : .clear, lineWidth: 1.5))
            #endif
            .onAppear(perform: load)
            .onChange(of: value) { _, _ in if !focused { load() } }
            .onChange(of: focused) { _, f in if !f { commit() } }
            .onSubmit(commit)
            #if os(iOS)
            .toolbar {
                if focused {
                    ToolbarItemGroup(placement: .keyboard) {
                        if let step {
                            Button { nudge(-step) } label: { Text("−\(trimmed(step, digits: 2))").monospacedDigit() }
                            Button { nudge(step) } label: { Text("+\(trimmed(step, digits: 2))").monospacedDigit() }
                        }
                        Spacer()
                        if let onLog {
                            Button { commit(); focused = false; onLog() } label: { Label("Log set", systemImage: "checkmark").labelStyle(.titleAndIcon) }
                                .fontWeight(.semibold)
                        } else {
                            Button("Done") { focused = false }.fontWeight(.semibold)
                        }
                    }
                }
            }
            #endif
    }

    private func nudge(_ d: Double) {
        let v = max(0, (parseNumber(text) ?? max(value, 0)) + d)
        text = trimmed(v, digits: digits)
        Haptics.tick()
    }

    private func load() {
        if emptyBelowZero && value < 0 { text = ""; return }
        text = value == 0 && !emptyBelowZero ? "" : trimmed(value, digits: digits)
    }

    private func commit() {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { value = emptyBelowZero ? -1 : 0; return }
        if let v = parseNumber(text) { value = v }
        load()
    }
}

/// Rest countdown, with ±15 s and skip. Rings once when time's up.
struct RestBar: View {
    let ends: Date
    let total: Int
    let change: (Date?) -> Void
    @State private var rang = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let left = max(0, Int(ends.timeIntervalSince(ctx.date).rounded(.up)))
            let color = left > 0 ? palette.accent : palette.good
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(color.opacity(0.2), lineWidth: 5)
                    Circle().trim(from: 0, to: total > 0 ? Double(left) / Double(total) : 0)
                        .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.5), value: left)
                    Image(systemName: left > 0 ? "timer" : "checkmark").font(.callout.weight(.bold)).foregroundStyle(color)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(left > 0 ? clock(left) : "Go!").font(.number(24)).liveNumber(Double(left))
                    Text(left > 0 ? "Rest" : "Rest over, next set").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("−15") { change(ends.addingTimeInterval(-15)) }.buttonStyle(.bordered)
                Button("+15") { change(ends.addingTimeInterval(15)) }.buttonStyle(.bordered)
                Button { change(nil) } label: { Image(systemName: "xmark") }.buttonStyle(.bordered)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(color.opacity(0.5), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .onChange(of: left == 0) { _, over in if over && !rang { rang = true; ring() } }
        }
    }

    private func ring() {
        #if os(macOS)
        NSSound(named: "Glass")?.play()
        #else
        AudioServicesPlaySystemSound(1005)
        Haptics.success()
        #endif
    }
}

/// Choose an exercise from the library (or make one).
struct ExercisePicker: View {
    let pick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(Muscle.allCases) { m in
                    let rows = filtered.filter { $0.muscleValue == m }
                    if !rows.isEmpty {
                        Section(m.label) {
                            ForEach(rows) { e in
                                Button { pick(e.key); dismiss() } label: {
                                    HStack {
                                        Text(e.name)
                                        Spacer()
                                        Text(e.equipmentValue.label).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .themedList()
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem { Button("New exercise…") { creating = true } }
            }
            .sheet(isPresented: $creating) { NewExerciseView { pick($0); dismiss() } }
        }
        .appStyle()                             // sheets don't inherit these on the Mac
        #if os(macOS)
        .frame(width: 480, height: 620)
        #endif
    }

    private var filtered: [Exercise] {
        let words = FoodAPI.fold(query).split(separator: " ").map(String.init)
        return words.isEmpty ? exercises : exercises.filter { e in words.allSatisfy { FoodAPI.fold(e.name).contains($0) } }
    }
}

struct NewExerciseView: View {
    var created: (String) -> Void = { _ in }
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscle = Muscle.chest
    @State private var equipment = Equipment.barbell

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Main muscle", selection: $muscle) { ForEach(Muscle.allCases) { Text($0.label).tag($0) } }
                Picker("Equipment", selection: $equipment) { ForEach(Equipment.allCases) { Text($0.label).tag($0) } }
            }
            .themedForm()
            .navigationTitle("New exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let e = Exercise(key: "custom:\(UUID().uuidString)", name: name.trimmingCharacters(in: .whitespaces), muscle: muscle,
                                         equipment: equipment, isCustom: true)
                        ctx.insert(e); ctx.commit()
                        dismiss(); created(e.key)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 260)
        #endif
    }
}

/// Which plates to put on each side of the bar for a weight.
struct PlateCalculator: View {
    let kg: Double
    let unit: WeightUnit
    @AppStorage("barKg") private var bar: Double = 20
    @AppStorage("platesAvailable") private var available = "25,20,15,10,5,2.5,1.25"

    static let plates: [Double] = [25, 20, 15, 10, 5, 2.5, 2, 1.25, 1, 0.5]
    private var have: [Double] { available.split(separator: ",").compactMap { Double($0) }.sorted(by: >) }

    var body: some View {
        let side = Self.perSide(total: kg, bar: bar, plates: have)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(trimmed(unit.fromKg(kg))) \(unit.rawValue)").font(.number(26))
                Text("on a \(trimmed(bar)) kg bar").foregroundStyle(.secondary)
            }
            if side.plates.isEmpty {
                Text(kg <= bar ? "Just the bar." : "Can't make this exactly.").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 3) {
                    Rectangle().fill(.secondary).frame(width: 30, height: 8)
                    ForEach(Array(side.plates.enumerated()), id: \.offset) { _, p in
                        RoundedRectangle(cornerRadius: 3).fill(color(p))
                            .frame(width: p >= 10 ? 14 : 10, height: 34 + p * 2.6)
                            .overlay { Text(trimmed(p)).font(.system(size: 8, weight: .bold)).rotationEffect(.degrees(-90)).foregroundStyle(.white).fixedSize() }
                    }
                }
                .frame(height: 104)
                Text("Each side: " + side.plates.map { trimmed($0) }.joined(separator: " + ") + " kg").font(.callout.weight(.semibold))
                if side.left > 0.01 { Text("\(trimmed(side.left * 2)) kg short of the target").font(.caption).foregroundStyle(palette.warn) }
            }
            Picker("Bar", selection: $bar) {
                Text("20 kg bar").tag(20.0); Text("15 kg bar").tag(15.0); Text("10 kg bar").tag(10.0)
            }
            .pickerStyle(.segmented).labelsHidden()
            VStack(alignment: .leading, spacing: 6) {
                Text("Plates at your gym").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    ForEach(Self.plates, id: \.self) { p in
                        let on = have.contains(p)
                        Button(trimmed(p)) {
                            var set = Set(have); if on { set.remove(p) } else { set.insert(p) }
                            available = set.sorted(by: >).map { trimmed($0).replacingOccurrences(of: ",", with: ".") }.joined(separator: ",")
                        }
                        .font(.caption2.weight(.bold)).buttonStyle(.plain)
                        .frame(minWidth: 24).padding(.vertical, 5)
                        .background(on ? palette.accent : Color.raisedBackground, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(on ? palette.onAccent : .secondary)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
    }

    static func perSide(total: Double, bar: Double, plates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]) -> (plates: [Double], left: Double) {
        var left = max(0, (total - bar) / 2)
        var out: [Double] = []
        for p in plates.sorted(by: >) { while left >= p - 0.001 { out.append(p); left -= p } }
        return (out, left)
    }

    private func color(_ p: Double) -> Color {
        switch p {
        case 25: return Color(hex: 0xE5383B)
        case 20: return Color(hex: 0x3A6FF7)
        case 15: return Color(hex: 0xF2C12E)
        case 10: return Color(hex: 0x2BB673)
        case 5: return Color(hex: 0xF5F5F5).mix(with: .gray, by: 0.3)
        default: return Color(hex: 0x6B6B76)
        }
    }
}
