import Security
import SwiftUI
import WidgetKit

// Home and lock screen widgets. They read a small summary the app keeps in a shared
// keychain item (WidgetData.swift in the app); after midnight, until you open the app,
// they show the new day as empty with the same targets.

struct TodaySummary: Codable {
    var day: String
    var kcal: Double, protein: Double, fat: Double, carbs: Double
    var targetKcal: Double, targetProtein: Double, targetFat: Double, targetCarbs: Double
    var waterMl: Double, waterGoalMl: Double
    var steps: Int, stepGoal: Int
    var energyUnit: String
    var nextWorkout: String?
    var accent: UInt32, caloriesColor: UInt32, proteinColor: UInt32, fatColor: UInt32, carbsColor: UInt32, background: UInt32

    static func load() -> TodaySummary? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "gym.widget",
                                    kSecAttrAccount as String: "today", kSecAttrAccessGroup as String: "T9XFKG27HP.com.wavymaso.gym.shared",
                                    kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
              var s = try? JSONDecoder().decode(TodaySummary.self, from: data) else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let today = f.string(from: Date())
        if s.day != today { s.day = today; s.kcal = 0; s.protein = 0; s.fat = 0; s.carbs = 0; s.waterMl = 0; s.steps = 0 }
        return s
    }

    static let preview = TodaySummary(day: "", kcal: 1840, protein: 142, fat: 41, carbs: 210, targetKcal: 2590, targetProtein: 178, targetFat: 58,
                                      targetCarbs: 340, waterMl: 1500, waterGoalMl: 3900, steps: 6400, stepGoal: 10000, energyUnit: "kcal",
                                      nextWorkout: "Push", accent: 0x4C7DFF, caloriesColor: 0x4C7DFF, proteinColor: 0xFF4F70,
                                      fatColor: 0xFFB830, carbsColor: 0x2FD39A, background: 0x15151B)

    var left: Double { targetKcal - kcal }
    func kcalText(_ v: Double) -> String {
        let n = energyUnit == "kJ" ? v * 4.184 : v
        return String(Int(n.rounded()))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let summary: TodaySummary?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), summary: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), summary: context.isPreview ? .preview : (TodaySummary.load() ?? .preview)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Refresh just after midnight so a new day starts empty.
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400)).addingTimeInterval(60)
        completion(Timeline(entries: [Entry(date: Date(), summary: TodaySummary.load())], policy: .after(midnight)))
    }
}

/// A ring like the app's.
struct WRing: View {
    let progress: Double
    let color: Color
    var width: CGFloat = 8
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.2), lineWidth: width)
            Circle().trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .padding(width / 2)
    }
}

struct CaloriesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        if let s = entry.summary {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(s.kcal, s.targetKcal), in: 0...max(s.targetKcal, 1)) {
                    Image(systemName: "fork.knife")
                } currentValueLabel: {
                    Text(s.kcalText(abs(s.left))).font(.system(.body, design: .rounded).weight(.bold)).minimumScaleFactor(0.5)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: Space.hairline) {
                    Text("\(s.kcalText(abs(s.left))) \(s.energyUnit) \(s.left >= 0 ? "left" : "over")").font(.cardTitle)
                    Text("P \(Int(max(0, s.targetProtein - s.protein))) · F \(Int(max(0, s.targetFat - s.fat))) · C \(Int(max(0, s.targetCarbs - s.carbs))) g left")
                        .font(.note)
                    Gauge(value: min(s.kcal, s.targetKcal), in: 0...max(s.targetKcal, 1)) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                }
            case .systemMedium:
                HStack(spacing: Space.l) {
                    ring(s).frame(width: 118, height: 118)
                    VStack(alignment: .leading, spacing: Space.s) {
                        bar("Protein", s.protein, s.targetProtein, Color(hex: s.proteinColor))
                        bar("Fat", s.fat, s.targetFat, Color(hex: s.fatColor))
                        bar("Carbs", s.carbs, s.targetCarbs, Color(hex: s.carbsColor))
                        HStack(spacing: Space.m) {
                            Label("\(String(format: "%.1f", s.waterMl / 1000)) L", systemImage: "drop.fill").foregroundStyle(Color(hex: 0x3BB2F6))
                            if s.steps > 0 { Label("\(s.steps)", systemImage: "figure.walk").foregroundStyle(Color(hex: 0x34C77B)) }
                        }
                        .font(.fineLabel)
                    }
                }
            default:
                ring(s)
            }
        } else {
            VStack(spacing: Space.s) {
                Image(systemName: "fork.knife.circle").font(.sectionTitle)
                Text("Open Gym once to fill this in.").font(.note).multilineTextAlignment(.center)
            }
        }
    }

    private func ring(_ s: TodaySummary) -> some View {
        ZStack {
            WRing(progress: s.targetKcal > 0 ? s.kcal / s.targetKcal : 0, color: Color(hex: s.caloriesColor), width: 11)
            VStack(spacing: 0) {
                Text(s.kcalText(abs(s.left))).font(.system(size: 26, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                Text(s.left >= 0 ? "\(s.energyUnit) left" : "\(s.energyUnit) over").font(.fineLabel).foregroundStyle(.secondary)
            }
            .padding(Space.l)
        }
    }

    private func bar(_ name: String, _ v: Double, _ t: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(name).font(.fineLabel)
                Spacer()
                Text("\(Int(v))/\(Int(t)) g").font(.fine).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(c.opacity(0.2))
                    Capsule().fill(c).frame(width: g.size.width * min(1, t > 0 ? v / t : 0))
                }
            }
            .frame(height: 6)
        }
    }
}

struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "calories", provider: Provider()) { entry in
            CaloriesView(entry: entry)
                .containerBackground(for: .widget) { Color(hex: entry.summary?.background ?? 0x15151B) }
                .widgetURL(URL(string: "gym://dashboard"))
        }
        .configurationDisplayName("Calories left")
        .description("Today's calories and macros.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct GymWidgets: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        RestLiveActivity()
    }
}
