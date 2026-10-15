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
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick add").font(.number(22)).padding(.top, 22)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                tile("Log food", "magnifyingglass", palette.accent) { pick(.food) }
                tile("Photo", "camera.fill", Color.weightTone) { pick(.photo) }
                tile("Describe", "text.bubble.fill", Color.calmTone) { pick(.describe) }
                #if os(iOS)
                tile("Scan barcode", "barcode.viewfinder", Macro.carbs.color) { pick(.scan) }
                #endif
                tile("Scan label", "text.viewfinder", Macro.fat.color) { pick(.label) }
                tile("Quick add", "bolt.fill", Macro.fat.color.mix(with: .orange, by: 0.4)) { pick(.quickAdd) }
                tile("Weigh in", "scalemass.fill", DashItem.color("weighIn")) { pick(.weighIn) }
                tile("Water +250", "drop.fill", Color.waterTone) { ctx.addWater(250); dismiss() }
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
                Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(palette.scheme == .dark ? .black : .white)
                    .frame(width: 58, height: 58)
                    .background(palette.scheme == .dark ? Color.white : palette.accent, in: Circle())
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }
            .pressable()
            .frame(maxWidth: .infinity)
            item(.strategy, "Strategy", "target")
            item(.training, "Training", "dumbbell")
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
        Button { animate(Motion.smooth) { tab = t } } label: {
            VStack(spacing: 4) {
                Image(systemName: tab == t && icon != "fork.knife" && icon != "target" ? icon + ".fill" : icon).font(.system(size: 21, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce.down, options: .speed(1.4), value: tab == t)
                    .frame(width: 56, height: 30)
                    .background {
                        // The selected pill glides from tab to tab.
                        if tab == t {
                            Capsule().fill(palette.accent.opacity(0.16)).matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(tab == t ? palette.accent : Color.secondary)
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        case .insights: return Color.waterTone
        case .strategy: return Macro.fat.color
        case .workouts: return Macro.protein.color
        case .exercises: return Macro.protein.color.mix(with: .orange, by: 0.4)
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
    static let version = 16
    @Environment(\.dismiss) private var dismiss

    private let items: [(String, String, String)] = [
        ("paintpalette", "Noir & Gold, Sterling", "Two matte themes: black with gold or silver, serif titles, no glow (More → Theme)."),
        ("plus.magnifyingglass", "Pinch the charts", "Zoom into any time window on the insight charts; slide it along with the arrows."),
        ("doc.on.clipboard", "Copy and move like MacroFactor", "Pick foods, tap Copy or Move, then tap any hour (any day) to put them there."),
        ("lock.shield", "Safer data", "A copy before every update, a check at every launch, weekly backups for 3 months, Face ID lock, keys in the Keychain."),
        ("stethoscope", "Diagnostics", "More → Diagnostics: version, data health, recent problems."),
        ("sparkles.rectangle.stack", "Smoother everywhere", "Tabs glide, numbers roll, foods drop into the cart, and every haptic means one thing."),
        ("arrow.uturn.backward", "Undo instead of “Are you sure?”", "Remove foods, sets, weigh-ins or photos at once; Undo for 5 seconds."),
        ("hand.tap", "Fewer taps", "Long-press ＋ on a food to log it straight away; −/+ on the keyboard for weights and weigh-ins."),
        ("sparkles", "AI Plate", "Each dish comes with its ingredients (bun, patty, cheese…), each editable; cooking oil and butter it can't see are estimated and marked ✦."),
        ("chart.line.uptrend.xyaxis", "Trend and expenditure match MacroFactor", "Trend weight within 0,01 kg of MacroFactor's on your history; expenditure within about 60 kcal."),
        ("paintpalette.fill", "23 themes", "More → Theme: dark (OLED, Forest, Ember, Crimson, Amethyst, Neon…), light (Sand, Mint, Blush, Arctic, Paper) and Glass (Aurora, Sunset, Ocean, Frost)."),
        ("figure.arms.open", "New icon", "Front double biceps."),
        ("target", "Edit Goal", "Strategy → Edit Goal: drag a ruler to your target weight, set the rate, see your budget and end date, then review."),
        ("calendar", "Edit Program, day by day", "Collaborative or manual: set each day's calories, protein and carb/fat split, or all days at once with the lock."),
        ("list.bullet.rectangle", "The numbers under every chart", "Detail screens now list each day's value by month, with how it changed."),
        ("hand.point.up.left", "Touch any chart", "Hold and drag on any graph to see that day's values."),
        ("chart.bar.xaxis", "Calories & Macros, Scale Weight", "New dashboard cards with full history screens; tap “Calories & macros history” under Nutrition too."),
        ("target", "Strategy has its own tab", "Countdown to check-in, your program and goal, goal history, and every coaching setting in one place."),
        ("person.crop.circle", "More, tidied up", "Top right of the Dashboard: your profile, then short groups of settings, each on its own page."),
        ("hand.point.up.left", "Touch the charts", "Drag on a detail chart to see that day's value."),
        ("flag.2.crossed", "Phase plan", "Cut → maintenance → bulk, each with an end (date or weight); the check-in offers the next phase (Strategy)."),
        ("scalemass", "Scales", "Name your other scales; their offsets are worked out so a trip home isn't a weight jump (Strategy → Scales)."),
        ("eye.slash", "Shadow mode", "The coach calculates check-ins without changing targets, and replays the last 12 weeks (Strategy)."),
        ("bed.double.fill", "Sleep", "From Apple Health, in the weekly review: a bad-sleep week explains a strength dip."),
        ("calendar.badge.checkmark", "Weekly review", "On check-in day: logging, protein, rate vs goal, expenditure, sets per muscle, lifts, and what they say together."),
        ("magnifyingglass", "Search forgives typos", "“platno” finds plátano; Spanish words find USDA foods; foods whose label doesn't add up are flagged."),
        ("link", "Recipes from Instagram", "Paste a post link, the caption, or photograph a cookbook page: ingredients and macros worked out."),
        ("gauge.with.dots.needle.33percent", "Calmer, smarter coaching", "Retuned on your 3 years of data; refeeds and water days don't fool it; each check-in says why."),
        ("dumbbell.fill", "RIR, skip today, your volume ranges", "Reps in reserve on the phone, skip an exercise for one session, and per-muscle set ranges."),
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
                .buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent).controlSize(.large).padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .pageBackground()
        #if os(macOS)
        .frame(width: 460, height: 560)
        #endif
        .appStyle()
    }
}
