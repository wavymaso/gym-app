import SwiftData
import SwiftUI

// MARK: - The database didn't open

struct RecoveryView: View {
    let reason: String
    @State private var done = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 44)).foregroundStyle(palette.warn)
            Text("Your data didn't open").font(.title.bold())
            Text("Nothing has been deleted. The app can put this database aside (kept in Backups) and restore your newest daily backup\(StoreSafety.latestBackup.map { " (\($0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Gym backup ", with: "")))" } ?? "").")
                .foregroundStyle(.secondary)
            Text(reason).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            if done {
                Label("Done. Close the app completely and open it again.", systemImage: "checkmark.circle.fill").foregroundStyle(palette.good).font(.headline)
            } else {
                Button {
                    StoreSafety.quarantineAndRestoreNextLaunch(store: ModelConfiguration().url)
                    done = true
                } label: {
                    Text("Restore my newest backup").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(StoreSafety.latestBackup == nil)
                if StoreSafety.latestBackup == nil {
                    Text("No backup on this device. If your Mac has your data, set up sync again after restoring.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(Space.xl)
        .frame(maxWidth: 520)
        .pageBackground()
    }
}
