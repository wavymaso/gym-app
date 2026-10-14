import SwiftData
import SwiftUI

// How you move around: on the iPhone a tab bar with a big + in the middle (quick actions)
// and a More page; on the Mac a sidebar with coloured icons and today's calories at the bottom.

/// What the + button can do.
enum QuickSheet: String, Identifiable {
    case food, scan, label, quickAdd, weighIn, water, photo, describe
    var id: String { rawValue }
}

/// The + button's menu: the things you do most, one tap away.
struct QuickActionsSheet: View {
    let choose: (QuickSheet) -> Void
    let train: () -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick add").font(.number(22)).padding(.top, 22)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                tile("Log food", "magnifyingglass", palette.accent) { pick(.food) }
                tile("Photo", "camera.fill", Color(hex: 0xA77BF3)) { pick(.photo) }
                tile("Describe", "text.bubble.fill", Color(hex: 0x7B8CF3)) { pick(.describe) }
                #if os(iOS)
                tile("Scan barcode", "barcode.viewfinder", Macro.carbs.color) { pick(.scan) }
                #endif
                tile("Scan label", "text.viewfinder", Macro.fat.color) { pick(.label) }
                tile("Quick add", "bolt.fill", Macro.fat.color.mix(with: .orange, by: 0.4)) { pick(.quickAdd) }
                tile("Weigh in", "scalemass.fill", DashItem.color("weighIn")) { pick(.weighIn) }
                tile("Water +250", "drop.fill", Color(hex: 0x3BB2F6)) { ctx.addWater(250); dismiss() }
                tile("Train", "dumbbell.fill", Macro.protein.color) { dismiss(); train() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
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
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2.weight(.semibold)).foregroundStyle(c)
                    .frame(width: 50, height: 50).background(c.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
    }
}

#if os(iOS)
enum PhoneTab: Hashable { case dashboard, food, training, more }

/// Dashboard · Food log · + · Training · More
struct PhoneTabBar: View {
    @Binding var tab: PhoneTab
    let plus: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            item(.dashboard, "Dashboard", "square.grid.2x2")
            item(.food, "Food log", "fork.knife")
            Button(action: plus) {
                Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(palette.scheme == .dark ? .black : .white)
                    .frame(width: 58, height: 58)
                    .background(palette.scheme == .dark ? Color.white : palette.accent, in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .sensoryFeedback(.impact(weight: .medium), trigger: tab)
            item(.training, "Training", "dumbbell")
            item(.more, "More", "ellipsis.circle")
        }
        .padding(.top, 8).padding(.horizontal, 6)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(.bottom, palette.glass ? 6 : 0)
        .background {
            if palette.glass { Color.clear.modifier(GlassCapsule()).padding(.horizontal, 10) }
            else { Rectangle().fill(.bar).ignoresSafeArea() }
        }
        .overlay(alignment: .top) { if !palette.glass { Divider() } }
    }

    private func item(_ t: PhoneTab, _ title: String, _ icon: String) -> some View {
        Button { tab = t } label: {
            VStack(spacing: 4) {
                Image(systemName: tab == t && icon != "fork.knife" ? icon + ".fill" : icon).font(.system(size: 21, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 26)
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(tab == t ? palette.accent : Color.secondary)
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// More: everything else, as big friendly rows.
struct MorePage: View {
    @Binding var path: [Page]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("More").font(.number(32)).padding(.top, 8)
                group("Progress", [.weight, .insights, .strategy])
                group("Training", [.exercises])
                group("App", [.settings])
            }
            .padding(pagePadding)
        }
        .pageBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func group(_ title: String, _ pages: [Page]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(pages) { p in
                    Button { path.append(p) } label: {
                        HStack(spacing: 14) {
                            PageIcon(page: p)
                            Text(p.label).font(.body.weight(.medium)).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .padding(14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if p != pages.last { Divider().padding(.leading, 60) }
                }
            }
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
#endif

/// A page's icon in a coloured tile (sidebar, More).
struct PageIcon: View {
    let page: Page
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: page.icon).font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(page.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

extension Page {
    var color: Color {
        switch self {
        case .dashboard: return palette.accent
        case .food: return Macro.carbs.color
        case .weight: return DashItem.color("weight")
        case .insights: return Color(hex: 0x3BB2F6)
        case .strategy: return Macro.fat.color
        case .workouts: return Macro.protein.color
        case .exercises: return Macro.protein.color.mix(with: .orange, by: 0.4)
        case .settings: return Color(hex: 0x8E8E93)
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
            HStack(spacing: 12) {
                ZStack {
                    Ring(progress: t.kcal > 0 ? eaten / t.kcal : 0, color: Macro.calories.color, lineWidth: 5)
                    Image(systemName: "flame.fill").font(.caption).foregroundStyle(Macro.calories.color)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(number(p.energy.fromKcal(abs(t.kcal - eaten)))).font(.number(18)).monospacedDigit()
                    Text("\(p.energy.rawValue) \(eaten <= t.kcal ? "left today" : "over today")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(10)
        }
    }
}

/// Shown once after an update: what's new, briefly.
struct WhatsNewSheet: View {
    static let version = 6
    @Environment(\.dismiss) private var dismiss

    private let items: [(String, String, String)] = [
        ("timer", "Rest timer on your lock screen", "Counts down on the lock screen and Dynamic Island, and alerts you when rest is over."),
        ("pills.fill", "Supplements", "Tick off creatine and the rest each day and keep the streak (Dashboard → Habits)."),
        ("figure.strengthtraining.traditional", "Strength retention & deloads", "Your main lifts against body weight while you cut, and a deload when they slip (Training)."),
        ("arrow.up.circle", "Refeeds & diet breaks", "A weekly high-carb day and planned weeks at maintenance (Strategy). Plus Collaborative mode and smoother check-ins."),
        ("fork.knife", "Protein per meal", "How evenly your protein is spread, against about 0,4 g per kg per meal."),
        ("square.stack.3d.up.fill", "A new way to log food", "One sheet: Scan · Search · AI · Quick Add · Library. Add foods to a cart, then Log Foods. The food screen shows its impact on today's targets and has a number pad with units."),
        ("chart.bar.xaxis", "Dashboard, MacroFactor style", "Swipe the top card for the weekly nutrition grid. Insight cards with sparklines, and Search for a food right above the tab bar."),
        ("sparkles", "Glass and Maximal", "Settings → Appearance: a Liquid Glass theme, and a Maximal style with glow."),
        ("camera.fill", "Log a meal with a photo", "Snap your plate (or just describe it): the model on your Mac names the foods and portions, nutrition comes from USDA, barcodes and your own foods. + → Photo."),
        ("ruler", "Measurements & progress photos", "On the Weight page: waist, arms and more, a tape body-fat estimate, and side-by-side photos."),
        ("mic.fill", "Siri & Shortcuts", "“Log water in Gym”, “How many calories do I have left in Gym”, weigh in, quick add. Put one on the Action button."),
        ("plus.circle.fill", "The + button", "Log food, scan a barcode or label, quick add, weigh in, water or train, from anywhere."),
        ("slider.horizontal.3", "Your dashboard", "Customize it: move sections, pick nutrients, consumed or remaining. Swipe the top widgets."),
        ("chart.line.uptrend.xyaxis", "Smarter numbers", "Weight trend V2 and expenditure V2: more accurate and quicker to react (Settings → Feature settings)."),
        ("calendar", "Calorie distribution", "More on training days, fasting days, and an optional weekly budget (Strategy)."),
        ("square.and.arrow.down", "Saved meals & day notes", "Save a meal to log it in one tap; mark a day as partially logged."),
        ("link", "Supersets & notes", "Superset exercises, track left and right, and keep notes per exercise."),
        ("externaldrive", "Backups", "A full backup every day; add a folder like iCloud Drive in Settings."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What's new").font(.number(30)).padding(.top, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(items, id: \.1) { icon, title, text in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(palette.accent).frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(.headline)
                                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            Button { dismiss() } label: { Text("Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6) }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .pageBackground()
        #if os(macOS)
        .frame(width: 460, height: 560)
        #endif
        .appStyle()
    }
}
