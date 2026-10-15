import Foundation
import SwiftData

// Before an update changes the data model (a migration), the database files are copied aside,
// so a migration that goes wrong can always be undone. The last 5 copies are kept, in
// Application Support/Backups/Before update …
enum StoreSafety {
    /// Set when the database couldn't be opened (the app then shows recovery instead of your data).
    nonisolated(unsafe) static var openFailure: String?

    static func fingerprint(_ schema: Schema) -> String {
        schema.entities.map { e in
            e.name + "(" + e.attributes.map { "\($0.name):\($0.valueType)" }.sorted().joined(separator: ",") + ")"
        }
        .sorted().joined(separator: ";")
    }

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Backups", isDirectory: true)
    }

    /// Copy the store aside if the model is about to change (or on the very first run with this).
    static func snapshotIfModelChanged(schema: Schema, store: URL) {
        let fp = fingerprint(schema)
        guard UserDefaults.standard.string(forKey: "schemaFingerprint") != fp,
              FileManager.default.fileExists(atPath: store.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = folder.appendingPathComponent("Before update \(stamp)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let src = URL(fileURLWithPath: store.path + suffix)
                if FileManager.default.fileExists(atPath: src.path) {
                    try FileManager.default.copyItem(at: src, to: dest.appendingPathComponent(src.lastPathComponent))
                }
            }
            Log.database.notice("Copied the database aside before a model change")
        } catch {
            Log.problem("database", "Couldn't copy the database before an update: \(error.localizedDescription)")
        }
        // Keep the last 5.
        let old = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Before update ") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for f in old.dropFirst(5) { try? FileManager.default.removeItem(at: f) }
    }

    /// The model opened fine: remember it, so the next copy happens only when it changes again.
    static func opened(schema: Schema) {
        UserDefaults.standard.set(fingerprint(schema), forKey: "schemaFingerprint")
    }

    static var snapshots: [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Before update ") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}

extension StoreSafety {
    /// Recovery: put the database that won't open aside (kept, not deleted) and restore the newest
    /// backup when the app next starts on a fresh one.
    static func quarantineAndRestoreNextLaunch(store: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = folder.appendingPathComponent("Would not open \(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: store.path + suffix)
            if FileManager.default.fileExists(atPath: src.path) { try? FileManager.default.moveItem(at: src, to: dest.appendingPathComponent(src.lastPathComponent)) }
        }
        UserDefaults.standard.set(true, forKey: "restoreLatestBackup")
    }

    /// The newest daily backup inside the app.
    static var latestBackup: URL? {
        ((try? FileManager.default.contentsOfDirectory(at: Backup.insideFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("Gym backup ") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }.first
    }
}
