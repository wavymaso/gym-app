import SwiftData
import SwiftUI

/// Raw or cooked for one food: what its values are per, and the cooked ÷ raw ratio, typical or from a
/// batch you weighed (weigh it raw, cook it, weigh it again). Then you can log either weight.
struct CookingSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let food: Food
    @State private var state: WeightState = .raw
    @State private var weighAs: WeightState = .raw
    @State private var raw = ""
    @State private var cooked = ""
    @State private var loaded = false

    private var batch: Double? { Cooking.ratio(raw: parseNumber(raw) ?? 0, cooked: parseNumber(cooked) ?? 0) }

    var body: some View {
        Form {
            Section {
                Picker("Values are per", selection: $state) { ForEach(WeightState.allCases, id: \.self) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented)
            } header: { Text("The nutrition values are per 100 g of…") } footer: {
                Text(food.source == "recipe" ? "A recipe's values are per gram of its raw ingredients." :
                     "Packets of pasta, rice and pulses give dry values. Supermarket roast chicken gives cooked values.")
            }
            Section {
                Picker("I weigh it", selection: $weighAs) { ForEach(WeightState.allCases, id: \.self) { Text($0 == .raw ? "Raw / dry" : "Cooked").tag($0) } }
                    .pickerStyle(.segmented)
            } header: { Text("When you weigh it") } footer: {
                Text("Meal plans show this food's portions this way, converted with the ratio below (e.g. 75 g dry rice → 210 g cooked).")
            }
            Section {
                HStack { Text("Raw weight"); Spacer(); TextField("g", text: $raw).multilineTextAlignment(.trailing).frame(width: 90); Text("g").foregroundStyle(.secondary) }
                HStack { Text("Cooked weight"); Spacer(); TextField("g", text: $cooked).multilineTextAlignment(.trailing).frame(width: 90); Text("g").foregroundStyle(.secondary) }
                if let b = batch {
                    Text("Cooked weighs \(number(b, digits: 2))× raw. 100 g cooked = \(number(100 / b)) g raw.").font(.secondaryText).monospacedDigit()
                }
            } header: { Text("Weigh a batch") } footer: {
                if let g = Cooking.guessRatio(food.name), food.source != "recipe" {
                    Text("Without a batch: typical for \(g.what), cooked = \(number(g.ratio, digits: 2))× raw. Your own batch is more accurate (cooking time and water change it).")
                } else {
                    Text("Weigh the whole batch (or pot contents) raw, then cooked, without the pot.")
                }
            }
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            if food.cookedRatio > 0 {
                Section { Button("Use the typical value instead", role: .destructive) { food.cookedRatio = 0; raw = ""; cooked = ""; ctx.commit() } }
            }
        }
        .themedForm()
        .navigationTitle("Raw or cooked")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    food.weightState = state.rawValue
                    if let b = batch { food.cookedRatio = (b * 1000).rounded() / 1000 }
                    if let p = ctx.profile {
                        var s = p.planner
                        s.weighAs[food.key] = weighAs == ModelContext.defaultWeighing(state) ? nil : weighAs
                        p.planner = s
                    }
                    ctx.commit(); Haptics.success(); dismiss()
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            state = food.state ?? .raw
            weighAs = ctx.profile?.planner.weighAs[food.key] ?? ModelContext.defaultWeighing(state)
        }
    }
}
