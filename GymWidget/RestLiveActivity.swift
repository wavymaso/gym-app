import ActivityKit
import SwiftUI
import WidgetKit

/// Same as RestAttributes in the app (Gym/RestActivity.swift).
struct RestAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var ends: Date
        var total: Int
        var next: String
        var setText: String
    }
    var workout: String
}

/// The rest countdown on the lock screen and in the Dynamic Island.
struct RestLiveActivity: Widget {
    private let accent = Color(red: 0.30, green: 0.49, blue: 1.0)
    private let done = Color(red: 0.20, green: 0.78, blue: 0.48)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { ctx in
            let s = ctx.state
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(accent.opacity(0.25), lineWidth: 6)
                    ProgressView(timerInterval: s.ends.addingTimeInterval(-Double(s.total))...s.ends, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.circular).tint(accent)
                    Image(systemName: "timer").font(.title3.weight(.bold)).foregroundStyle(accent)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("REST · \(ctx.attributes.workout.uppercased())").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(timerInterval: Date()...s.ends, countsDown: true).font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundStyle(.white)
                    Text(s.next.isEmpty ? s.setText : "Next: \(s.next) · \(s.setText)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(16)
            .activityBackgroundTint(Color.black.opacity(0.75))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Rest", systemImage: "timer").font(.headline).foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...s.ends, countsDown: true).font(.title2.weight(.bold)).monospacedDigit()
                        .multilineTextAlignment(.trailing).frame(width: 80)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(s.next.isEmpty ? s.setText : "Next: \(s.next) · \(s.setText)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(accent)
            } compactTrailing: {
                Text(timerInterval: Date()...s.ends, countsDown: true).monospacedDigit().frame(width: 44).foregroundStyle(accent)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(accent)
            }
        }
    }
}
