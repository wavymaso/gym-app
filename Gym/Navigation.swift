import SwiftData
import SwiftUI

// How you move around: on the iPhone a tab bar with a big + in the middle (quick actions)
// and a More page; on the Mac a sidebar with coloured icons and today's calories at the bottom.

/// What the + button can do.
enum QuickSheet: String, Identifiable {
    case food, scan, label, quickAdd, weighIn, water, photo, describe, recipeLink
    var id: String { rawValue }
}

/// The + button's menu: the things you do most, one tap away.
struct QuickActionsSheet: View {
    let choose: (QuickSheet) -> Void
    let train: () -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Quick add").font(.numberMedium).padding(.top, Space.xl)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.m), count: 3), spacing: Space.m) {
                tile("Log food", "magnifyingglass", palette.accent) { pick(.food) }
                tile("Photo", "camera.fill", Color.weightTone) { pick(.photo) }
                tile("Describe", "text.bubble.fill", Color.calmTone) { pick(.describe) }
                #if os(iOS)
                tile("Scan barcode", "barcode.viewfinder", Macro.carbs.color) { pick(.scan) }
                #endif
                tile("Scan label", "text.viewfinder", Macro.fat.color) { pick(.label) }
                tile("Quick add", "bolt.fill", Macro.fat.color) { pick(.quickAdd) }
                tile("Weigh in", "scalemass.fill", DashItem.color("weighIn")) { pick(.weighIn) }
                tile("Water +250", "drop.fill", Color.waterTone) { ctx.addWater(250); dismiss() }
                tile("Train", "dumbbell.fill", Macro.protein.color) { dismiss(); train() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageBackground()
        #if os(iOS)
        .presentationDetents([.height(isPhone ? 380 : 340)])
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 420, height: 320)
        #endif
        .appStyle()
    }

    private func pick(_ s: QuickSheet) { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { choose(s) } }

    private func tile(_ title: String, _ icon: String, _ c: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Space.s) {
                // Monochrome symbols on a tonal tile (no rainbow).
                Image(systemName: icon).font(.sectionTitle).foregroundStyle(palette.text1)
                    .frame(width: 50, height: 50).background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: Radius.m + 2, style: .continuous))
                Text(title).font(.label).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, Space.m)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The sheet behind each quick action.
@ViewBuilder func quickSheet(_ s: QuickSheet) -> some View {
    switch s {
    case .food: FoodLogger(day: dayKey(), start: .search)
    case .scan: FoodLogger(day: dayKey(), start: .scan)
    case .label: LabelScanView()
    case .quickAdd: FoodLogger(day: dayKey(), start: .quickAdd)
    case .weighIn: WeighInSheet()
    case .water: WaterAmountSheet()
    case .photo: FoodLogger(day: dayKey(), start: .ai, startCamera: true)
    case .describe: FoodLogger(day: dayKey(), start: .ai, describe: true)
    case .recipeLink: RecipeView(recipe: nil, startImport: true)
    }
}

#if os(iOS)
enum PhoneTab: Hashable, CaseIterable {
    case dashboard, food, strategy, training, more
    var order: Int { PhoneTab.allCases.firstIndex(of: self) ?? 0 }
}

/// Dashboard · Food log · + · Strategy · Training   (More opens from the Dashboard's top right)
struct PhoneTabBar: View {
    @Binding var tab: PhoneTab
    let plus: () -> Void
    @Namespace private var pill

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            item(.dashboard, "Dashboard", "square.grid.2x2")
            item(.food, "Food log", "fork.knife")
            Button(action: plus) {
                Image(systemName: "plus").font(.sectionTitle).foregroundStyle(palette.onAccent)
                    .frame(width: 58, height: 58)
                    .background(palette.accentFill, in: Circle())
                    .floatShadow()
            }
            .pressable()
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Add: food, weight, workout and more")
            item(.strategy, "Strategy", "target")
            item(.training, "Training", "dumbbell")
        }
        .padding(.top, Space.s).padding(.horizontal, Space.s)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .background { Rectangle().fill(.bar).ignoresSafeArea() }     // a material: content scrolls behind the tab bar
        .overlay(alignment: .top) { Rectangle().fill(palette.hairline).frame(height: 0.5) }
    }

    private func item(_ t: PhoneTab, _ title: String, _ icon: String) -> some View {
        Button { animate(Motion.smooth) { tab = t } } label: {
            VStack(spacing: Space.xs) {
                Image(systemName: tab == t && icon != "fork.knife" && icon != "target" ? icon + ".fill" : icon).font(.iconSmall)
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce.down, options: .speed(1.4), value: tab == t)
                    .frame(width: 56, height: 30)
                    .background {
                        // The selected pill glides from tab to tab.
                        if tab == t {
                            Capsule().fill(palette.accent.opacity(0.16)).matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                Text(title).font(.label).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(tab == t ? palette.accent : Color.secondary)
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title).accessibilityAddTraits(tab == t ? [.isSelected, .isButton] : .isButton)
        .accessibilityShowsLargeContentViewer()     // the bar stops growing at xLarge: long-press shows it big, like the system's
    }
}

/// More: your profile, settings and the other pages, MacroFactor-style (SettingsView).
struct MorePage: View {
    @Binding var path: [Page]
    var body: some View { SettingsView() }
}
#endif

/// A page's icon in a coloured tile (sidebar, More).
struct PageIcon: View {
    let page: Page
    var size: CGFloat = 32
    var body: some View {
        // Monochrome: the symbol alone, in the secondary text colour (the list's selection shows the accent).
        Image(systemName: page.icon).font(.system(size: size * 0.52, weight: .regular)).foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

extension Page {
    var color: Color {
        switch self {
        case .dashboard: return palette.accent
        case .food: return Macro.carbs.color
        case .weight: return DashItem.color("weight")
        case .insights: return Color.waterTone
        case .strategy: return Macro.fat.color
        case .workouts: return Macro.protein.color
        case .exercises: return Macro.protein.color
        case .settings: return Color.neutralTone
        }
    }
}

/// Bottom of the Mac sidebar: today's calories left, always in view.
struct SidebarToday: View {
    @Query private var today: [FoodEntry]
    @Query(sort: \TargetSet.fromDay, order: .reverse) private var targetSets: [TargetSet]
    @Query private var profiles: [Profile]

    init() {
        let d = dayKey()
        _today = Query(filter: #Predicate<FoodEntry> { $0.day == d })
    }

    var body: some View {
        if let p = profiles.first, let base = targetSets.first(where: { $0.fromDay <= dayKey() })?.targets {
            let t = p.adjust(base, on: dayKey())
            let eaten = today.reduce(0) { $0 + $1.nutrients.kcal }
            HStack(spacing: Space.m) {
                ZStack {
                    Ring(progress: t.kcal > 0 ? eaten / t.kcal : 0, color: Macro.calories.color, lineWidth: 5)
                    Image(systemName: "flame.fill").font(.note).foregroundStyle(Macro.calories.color)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: Space.hairline) {
                    Text(number(p.energy.fromKcal(abs(t.kcal - eaten)))).font(.numberMedium).monospacedDigit()
                    Text("\(p.energy.rawValue) \(eaten <= t.kcal ? "left today" : "over today")").font(.note).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.m)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .padding(Space.m)
        }
    }
}

/// Shown once after an update: what's new, briefly.
struct WhatsNewSheet: View {
    static let version = 18
    @Environment(\.dismiss) private var dismiss
    @State private var earlier = false

    /// This update.
    private let items: [(String, String, String)] = [
        ("chart.line.uptrend.xyaxis", "One trend everywhere", "The trend you see is the one behind your targets: the coaching engine's trend and its expenditure, on every device."),
        ("textformat.size", "Calmer pages", "Plain large titles that tuck away as you scroll, one type scale and spacing everywhere, and nothing hidden under the tab bar. Search lives in ＋ and the Food log."),
        ("clock", "A tidier food log", "Only the hours you logged and your next planned meal; gaps are one thin ＋ Add row (⋯ → Show empty hours for the full day)."),
        ("calendar.badge.clock", "Plan your meals", "Food log → ⋯ → Plan: swap a food, keep one at a portion, servings in units (2 eggs, 1 bar), and how many meals you ate as planned."),
        ("questionmark.bubble", "Six questions at the check-in", "Hunger, energy, sleep, training, stress and how hard the plan was: suggestions you accept or decline, never automatic."),
        ("accessibility", "VoiceOver", "Charts, rings, the day strip, sets and plan meals read out properly."),
    ]

    /// Earlier updates that still describe the app (removed features are gone from this list).
    private let earlierItems: [(String, String)] = [
        ("A new look: Appearance × Finish", "Automatic, Light, Dark or Black, in Titanium, Silver, Graphite, Gold or Rose Gold (More → Theme)."),
        ("Copy and move like MacroFactor", "Pick foods, tap Copy or Move, then tap any hour on any day."),
        ("Safer data", "A copy before every update, a check at every launch, backups, Face ID lock, keys in the Keychain."),
        ("Undo instead of “Are you sure?”", "Remove foods, sets, weigh-ins or photos at once; Undo for 5 seconds."),
        ("Fewer taps", "Long-press ＋ on a food to log it; −/+ on the keyboard for weights."),
        ("AI Plate and photo logging", "Snap your plate or describe it: foods and portions, with nutrition from USDA, barcodes and your own foods."),
        ("Edit goal and program", "Drag a ruler to your target weight, set the rate, see your budget; collaborative or manual day by day."),
        ("Touch and zoom the charts", "Hold and drag for a day's values; pinch to zoom; every chart lists its numbers by month."),
        ("Strategy", "Countdown to check-in, program, goal history, phase plan, scales, shadow mode, refeeds and diet breaks."),
        ("Weekly review", "Logging, protein, rate vs goal, expenditure, sets per muscle, lifts and sleep."),
        ("Search forgives typos", "“platno” finds plátano; Spanish words find USDA foods; labels that don't add up are flagged."),
        ("Recipes from links and photos", "Paste a post link or caption, or photograph a cookbook page."),
        ("Training", "RIR, supersets, notes, per-muscle set ranges, strength retention and deloads, a rest timer on the lock screen."),
        ("Supplements and protein per meal", "Tick off supplements and keep the streak; see how evenly protein is spread."),
        ("One sheet to log food", "Scan · Search · AI · Quick Add · Library, with a cart and a number pad."),
        ("Measurements & progress photos", "Waist, arms and more, a tape body-fat estimate, side-by-side photos."),
        ("Siri & Shortcuts", "Log water, ask what's left, weigh in, quick add."),
        ("Your dashboard", "Move sections, pick nutrients, consumed or remaining."),
        ("Calorie distribution", "More on training days, fasting days, an optional weekly budget."),
        ("Saved meals, day notes, backups", "Log a saved meal in one tap; mark a day as partly logged; a backup every day."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("What's new").font(.screenTitle).padding(.top, Space.xl)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    ForEach(items, id: \.1) { icon, title, text in
                        HStack(alignment: .top, spacing: Space.l) {
                            Image(systemName: icon).font(.subsectionTitle).foregroundStyle(palette.accent).frame(width: 32)
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(title).font(.cardTitle)
                                Text(text).font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    DisclosureGroup("Earlier", isExpanded: $earlier) {
                        VStack(alignment: .leading, spacing: Space.m) {
                            ForEach(earlierItems, id: \.0) { title, text in
                                VStack(alignment: .leading, spacing: Space.xxs) {
                                    Text(title).font(.secondaryEmphasis)
                                    Text(text).font(.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.top, Space.s)
                    }
                    .font(.cardTitle).tint(palette.accent)
                }
            }
            Button { dismiss() } label: { Text("Continue").font(.cardTitle).frame(maxWidth: .infinity).padding(.vertical, Space.s) }
                .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent).controlSize(.large).padding(.bottom, Space.xl)
        }
        .padding(.horizontal, Space.xl)
        .pageBackground()
        #if os(macOS)
        .frame(width: 460, height: 560)
        #endif
        .appStyle()
    }
}
