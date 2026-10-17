import Foundation
import SwiftUI

// A free developer account signs the app for 7 days. The date is in the app's own provisioning
// profile; two days before, the dashboard says so (and when it's gone, so do you: reinstall).
enum Signing {
    static let expires: Date? = {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url) else { return nil }
        // The profile is a signed blob with a plist inside.
        let text = String(decoding: raw, as: UTF8.self)
        guard let a = text.range(of: "<?xml"), let b = text.range(of: "</plist>") else { return nil }
        let plist = Data(text[a.lowerBound..<b.upperBound].utf8)
        let dict = (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any]
        return dict?["ExpirationDate"] as? Date
        #else
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "signingExpires") { return ISO8601DateFormatter().date(from: s) }   // testing only
        #endif
        return nil
        #endif
    }()

    /// Within two days: time to reinstall.
    static var soon: Bool { expires.map { $0.timeIntervalSinceNow < 2 * 86400 } ?? false }
}

/// The dashboard banner.
struct SigningBanner: View {
    var body: some View {
        if Signing.soon, let e = Signing.expires {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: "clock.badge.exclamationmark").font(.subsectionTitle).foregroundStyle(palette.warn)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Reinstall before \(e.formatted(.dateTime.weekday(.wide).hour().minute().locale(appLocale)))").font(.cardTitle)
                    Text("The free signature runs out then and the app won't open until it's reinstalled. Plug your phone into the Mac and run tools/install-phone.sh. Your data stays.")
                        .font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
    }
}
