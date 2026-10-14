import Foundation
import SwiftData
#if os(iOS)
import Security
import WidgetKit
#endif

// What the home and lock screen widgets show (GymWidget reads it): today's totals,
// targets, water, steps and the theme's colours. Free signing has no App Groups, so it's
// handed over as a keychain item in a group both share (keychain-access-groups).

enum WidgetData {
    static let keychainGroup = "T9XFKG27HP.com.wavymaso.gym.shared"
    private static var pending: Task<Void, Never>?

    /// Soon after a change (several quick changes write once).
    @MainActor static func changed(_ ctx: ModelContext) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { write(ctx) }
        }
    }

    @MainActor static func write(_ ctx: ModelContext) {
        #if os(iOS)
        guard let set = ctx.targets(on: dayKey()) else { return }
        let base = set.targets
        let profile: Profile? = (try? ctx.fetch(FetchDescriptor<Profile>()))?.first
        let t = ctx.dayTargets(on: dayKey()) ?? profile?.adjust(base, on: dayKey()) ?? base
        let today = dayKey()
        let eaten = ctx.entries(on: today).reduce(Nutrients.zero) { $0 + $1.nutrients }
        let act = ctx.activity(on: today)
        let json: [String: Any] = [
            "day": today, "kcal": eaten.kcal, "protein": eaten.protein, "fat": eaten.fat, "carbs": eaten.carbs,
            "targetKcal": t.kcal, "targetProtein": t.protein, "targetFat": t.fat, "targetCarbs": t.carbs,
            "waterMl": ctx.water(on: today).reduce(0) { $0 + $1.ml }, "waterGoalMl": ctx.waterGoalMl,
            "steps": act?.steps ?? 0, "stepGoal": stepGoal,
            "energyUnit": (try? ctx.fetch(FetchDescriptor<Profile>()).first?.energyUnit) ?? "kcal",
            "accent": hex(palette.name, \.accent), "caloriesColor": hex(palette.name, \.calories), "proteinColor": hex(palette.name, \.protein),
            "fatColor": hex(palette.name, \.fat), "carbsColor": hex(palette.name, \.carbs), "background": hex(palette.name, \.surface),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "gym.widget",
                                    kSecAttrAccount as String: "today", kSecAttrAccessGroup as String: keychainGroup]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// The theme's colours as numbers the widget can read.
    private static func hex(_ theme: String, _ key: KeyPath<WidgetColors, UInt32>) -> UInt32 {
        (WidgetColors.byTheme[theme] ?? WidgetColors.byTheme["midnight"]!)[keyPath: key]
    }
}

/// The same values as the palettes in Theme.swift, as hex.
struct WidgetColors {
    var accent: UInt32, calories: UInt32, protein: UInt32, fat: UInt32, carbs: UInt32, surface: UInt32
    static let byTheme: [String: WidgetColors] = [
        "midnight": .init(accent: 0x4C7DFF, calories: 0x4C7DFF, protein: 0xFF4F70, fat: 0xFFB830, carbs: 0x2FD39A, surface: 0x15151B),
        "graphite": .init(accent: 0xFF7A1A, calories: 0xFF7A1A, protein: 0xFF4D5E, fat: 0xFFD04A, carbs: 0x4CC38A, surface: 0x1D1D1F),
        "ocean": .init(accent: 0x14B8C8, calories: 0x22C7DA, protein: 0xFF6A88, fat: 0xFFC65A, carbs: 0x7BE38E, surface: 0x0E1F31),
        "daylight": .init(accent: 0x2F6BFF, calories: 0x2F6BFF, protein: 0xE8445A, fat: 0xEFA300, carbs: 0x1FA774, surface: 0xFFFFFF),
    ]
}
