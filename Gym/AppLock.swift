import LocalAuthentication
import SwiftUI

// Optional: Face ID (or your passcode) when the app opens or comes back after a minute away.
enum AppLock {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "appLock") }
    static var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    static func unlock() async -> Bool {
        let c = LAContext()
        c.localizedCancelTitle = "Not now"
        return (try? await c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Gym")) ?? false
    }
}

/// Covers the app until you unlock it.
struct LockGate: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @State private var locked = AppLock.enabled
    @State private var leftAt: Date?

    func body(content: Content) -> some View {
        content
            .overlay {
                if locked {
                    ZStack {
                        Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
                        VStack(spacing: Space.l) {
                            Image(systemName: "lock.fill").font(.iconHero).foregroundStyle(palette.accent)
                            Text("Gym is locked").font(.sectionTitle)
                            Button("Unlock") { Task { await tryUnlock() } }.buttonStyle(.borderedProminent).foregroundStyle(palette.onAccent)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .task { if locked { await tryUnlock() } }
            .onChange(of: phase) { _, p in
                guard AppLock.enabled else { return }
                if p == .background { leftAt = Date() }
                if p == .active, let l = leftAt, Date().timeIntervalSince(l) > 60 {
                    locked = true
                    Task { await tryUnlock() }
                }
                if p == .active { leftAt = nil }
            }
    }

    private func tryUnlock() async {
        if await AppLock.unlock() { animate(Motion.smooth) { locked = false } }
    }
}

/// Settings toggle.
struct AppLockToggle: View {
    @AppStorage("appLock") private var on = false
    var body: some View {
        Toggle(isOn: $on) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Lock with Face ID")
                Text("When the app opens, and after a minute away.").font(.note).foregroundStyle(.secondary)
            }
        }
        .disabled(!AppLock.available && !on)
    }
}
