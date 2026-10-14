import Foundation
import SwiftData
import SwiftUI
import UserNotifications

// Local reminders, set per device (turn them on where you want them, usually the iPhone).
// They're planned a week ahead and re-planned whenever you leave the app, so today's
// is skipped once you've already weighed in or logged that meal.

enum Reminders {
    static let center = UNUserNotificationCenter.current()
    static let prefix = "gym."

    static var weighIn: Bool { UserDefaults.standard.bool(forKey: "remindWeighIn") }
    static var meals: Bool { UserDefaults.standard.bool(forKey: "remindMeals") }
    static var checkIn: Bool { UserDefaults.standard.bool(forKey: "remindCheckIn") }
    /// Minutes after midnight (default 08:00).
    static var weighInAt: Int {
        let v = UserDefaults.standard.integer(forKey: "remindWeighInAt")
        return v > 0 ? v : 8 * 60
    }

    static func requestAccess() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// When each meal's reminder goes off if nothing's logged: the end of its window.
    static func mealDeadline(_ m: Meal) -> (Int, Int) { [(11, 0), (16, 45), (20, 15), (23, 0)][m.rawValue] }

    /// Throw away what's planned and plan the next 7 days again.
    @MainActor static func reschedule(_ ctx: ModelContext) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard weighIn || meals || checkIn else { return }
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }

        let today = dayKey()
        let weighedToday = ctx.fetchCountSafe(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.day == today })) > 0
        let todays = ctx.entries(on: today)
        let usual = usualMeals(ctx)
        let program = ctx.activeProgram

        for offset in 0..<7 {
            let day = addDays(today, offset)
            let date0 = date(fromKey: day)
            if weighIn && !(offset == 0 && weighedToday) {
                add("weigh.\(day)", at: date0, minutes: weighInAt, title: "Time to weigh in",
                    body: "Morning, before eating. The trend does the rest.")
            }
            if meals {
                for m in usual where !(offset == 0 && todays.contains { Meal(time: $0.time) == m }) {
                    let (h, mi) = mealDeadline(m)
                    add("meal.\(m.rawValue).\(day)", at: date0, minutes: h * 60 + mi, title: "Log your \(m.label.lowercased())?",
                        body: "Nothing logged for \(m.label.lowercased()) yet today.")
                }
            }
            if checkIn, let p = program, Calendar(identifier: .gregorian).component(.weekday, from: date0) == p.checkInWeekday,
               p.lastCheckIn != day {
                add("checkin.\(day)", at: date0, minutes: 9 * 60 + 30, title: "Weekly check-in",
                    body: "See how the week went and update your targets.")
            }
        }
    }

    /// Meals you've logged on at least 4 of the last 7 days.
    @MainActor static func usualMeals(_ ctx: ModelContext) -> [Meal] {
        let from = addDays(dayKey(), -7), to = dayKey()
        let recent = (try? ctx.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.day >= from && $0.day < to && $0.foodKey != "import" }))) ?? []
        return Meal.allCases.filter { m in Set(recent.filter { Meal(time: $0.time) == m }.map(\.day)).count >= 4 }
    }

    private static func add(_ id: String, at day: Date, minutes: Int, title: String, body: String) {
        guard let when = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day), when > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        center.add(UNNotificationRequest(identifier: prefix + id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

extension ModelContext {
    func fetchCountSafe<T: PersistentModel>(_ d: FetchDescriptor<T>) -> Int { (try? fetchCount(d)) ?? 0 }
}

/// Settings: which reminders this device shows.
struct RemindersSection: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage("remindWeighIn") private var weighIn = false
    @AppStorage("remindMeals") private var meals = false
    @AppStorage("remindCheckIn") private var checkIn = false
    @AppStorage("remindWeighInAt") private var weighInAt = 8 * 60
    @State private var denied = false

    var body: some View {
        Section {
            Toggle("Weigh-in", isOn: $weighIn)
            if weighIn {
                DatePicker("At", selection: Binding(get: {
                    Calendar.current.date(bySettingHour: weighInAt / 60, minute: weighInAt % 60, second: 0, of: Date()) ?? Date()
                }, set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d); weighInAt = (c.hour ?? 8) * 60 + (c.minute ?? 0)
                }), displayedComponents: .hourAndMinute)
            }
            Toggle("Meals you usually log", isOn: $meals)
            Toggle("Weekly check-in", isOn: $checkIn)
            if denied {
                Text("Notifications are off for Gym. Turn them on in System Settings → Notifications.").font(.callout).foregroundStyle(palette.warn)
            }
        } header: {
            Text("Reminders on this \(isPhone ? "iPhone" : "Mac")")
        } footer: {
            Text("Skipped when you've already done it. Meal reminders come at the end of a meal you've logged on 4 of the last 7 days, if it's still empty.")
        }
        .onChange(of: [weighIn, meals, checkIn]) { _, v in
            Task {
                if v.contains(true) { denied = !(await Reminders.requestAccess()) }
                await Reminders.reschedule(ctx)
            }
        }
        .onChange(of: weighInAt) { _, _ in Task { await Reminders.reschedule(ctx) } }
    }
}
