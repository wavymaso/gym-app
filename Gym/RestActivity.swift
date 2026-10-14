import Foundation
#if os(iOS)
import ActivityKit
import UserNotifications

/// The rest timer on the lock screen and in the Dynamic Island (shown by GymWidget), plus a
/// "rest over" alert for when the phone is in your pocket. The same type is defined in GymWidget.
struct RestAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var ends: Date
        var total: Int
        var next: String              // the exercise you're resting for
        var setText: String           // "Set 3 of 4"
    }
    var workout: String
}

enum RestLive {
    private static var current: ActivityKit.Activity<RestAttributes>?

    /// Start or move the countdown; nil ends it.
    static func show(ends: Date?, total: Int, workout: String, next: String, setText: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        guard let ends, ends > Date() else { end(); return }
        // The alert: sounds through the notification (respects silent mode, buzzes on the watch).
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = next.isEmpty ? "Next set." : "Next: \(next)"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: "rest", content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, ends.timeIntervalSinceNow), repeats: false)))
        let state = RestAttributes.ContentState(ends: ends, total: total, next: next, setText: setText)
        let content2 = ActivityContent(state: state, staleDate: ends.addingTimeInterval(60))
        Task {
            if let a = current, a.activityState == .active {
                await a.update(content2)
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                current = try? ActivityKit.Activity.request(attributes: RestAttributes(workout: workout), content: content2)
            }
        }
    }

    static func end() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
        let a = current
        current = nil
        Task { await a?.end(nil, dismissalPolicy: .immediate) }
        // Any left over from before a relaunch.
        Task { for x in ActivityKit.Activity<RestAttributes>.activities { await x.end(nil, dismissalPolicy: .immediate) } }
    }
}
#endif
