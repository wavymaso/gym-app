import Foundation
import Security
import SwiftUI

// API keys (Gemini, USDA) live in the Keychain, not in the app's preferences file. A key still
// in the old place moves over the first time it's read.
enum Secrets {
    private static let service = "com.wavymaso.gym.keys"

    static func get(_ name: String) -> String {
        if let v = read(name) { return v }
        // Moved from preferences (older versions kept keys there).
        if let old = UserDefaults.standard.string(forKey: name), !old.isEmpty {
            if write(name, old) { UserDefaults.standard.removeObject(forKey: name) }
            return old.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    static func set(_ name: String, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { delete(name) } else { _ = write(name, v) }
        UserDefaults.standard.removeObject(forKey: name)
    }

    /// For a text field.
    static func binding(_ name: String) -> Binding<String> {
        Binding(get: { get(name) }, set: { set(name, $0) })
    }

    private static func query(_ name: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: name]
    }

    private static func read(_ name: String) -> String? {
        var q = query(name)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func write(_ name: String, _ value: String) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(name) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(name)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    private static func delete(_ name: String) { SecItemDelete(query(name) as CFDictionary) }
}
