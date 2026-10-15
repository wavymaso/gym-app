import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// Backups of everything you've logged: one JSON file a day (the same records sync uses, so a
// restore is exact). Kept inside the app and, if you pick one, in a folder of your choice such
// as iCloud Drive: every day for the last 14 (30 in your folder), then one a week for 3 months.

enum Backup {
    static let keepInside = 14, keepOutside = 30, keepWeeks = 13

    /// Which backup files stay: the newest `daily`, then the newest of each older week, for `weeks` weeks.
    static func keep(_ names: [String], daily: Int, weeks: Int) -> Set<String> {
        let sorted = names.sorted(by: >)
        var kept = Set(sorted.prefix(daily))
        guard let newest = sorted.first.flatMap(day(of:)) else { return kept }
        let oldest = addDays(newest, -7 * weeks)
        var seenWeeks = Set(sorted.prefix(daily).compactMap(day(of:)).map(weekStart))
        for n in sorted.dropFirst(daily) {
            guard let d = day(of: n), d >= oldest else { continue }
            if seenWeeks.insert(weekStart(d)).inserted { kept.insert(n) }
        }
        return kept
    }

    /// "Gym backup 2026-10-15.json" → "2026-10-15"
    static func day(of name: String) -> String? {
        let d = name.replacingOccurrences(of: "Gym backup ", with: "").replacingOccurrences(of: ".json", with: "")
        return d.count == 10 ? d : nil
    }
    static var last: Date? {
        get { UserDefaults.standard.object(forKey: "lastBackup") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastBackup") }
    }

    @MainActor static func data(_ ctx: ModelContext) -> Data {
        let (records, _) = ctx.syncChanges(since: .distantPast)
        let tombs = ((try? ctx.fetch(FetchDescriptor<Tombstone>())) ?? []).map {
            ["type": $0.type, "id": $0.syncID, "deletedAt": $0.deletedAt.timeIntervalSince1970] as [String: Any]
        }
        let json: [String: Any] = ["app": "Gym", "version": 1, "exported": Date().timeIntervalSince1970, "records": records, "deleted": tombs]
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }

    static var insideFolder: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static var filename: String { "Gym backup \(dayKey()).json" }

    /// Once a day (on launch or when you leave the app).
    @MainActor static func daily(_ ctx: ModelContext) {
        if let l = last, Date().timeIntervalSince(l) < 20 * 3600 { return }
        _ = now(ctx)
    }

    /// Writes today's backup; returns where it went outside the app, if anywhere.
    @MainActor @discardableResult static func now(_ ctx: ModelContext) -> String? {
        guard ctx.hasSyncedData else { return nil }
        let d = data(ctx)
        write(d, in: insideFolder, keep: keepInside)
        var outside: String?
        if let folder = chosenFolder() {
            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }
            if write(d, in: folder, keep: keepOutside) { outside = folder.lastPathComponent }
        }
        last = Date()
        return outside
    }

    @discardableResult private static func write(_ d: Data, in folder: URL, keep: Int) -> Bool {
        do {
            try d.write(to: folder.appendingPathComponent(filename), options: .atomic)
            let old = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            let ours = old.filter { $0.lastPathComponent.hasPrefix("Gym backup ") && $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            let staying = Backup.keep(ours.map(\.lastPathComponent), daily: keep, weeks: keepWeeks)
            for f in ours where !staying.contains(f.lastPathComponent) { try? FileManager.default.removeItem(at: f) }
            return true
        } catch {
            Log.problem("backup", "Couldn't write a backup to \(folder.lastPathComponent): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: A folder you choose (kept as a bookmark so it still works after a restart)

    static func choose(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let b = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let b = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        UserDefaults.standard.set(b, forKey: "backupFolder")
    }

    static func chosenFolder() -> URL? {
        guard let b = UserDefaults.standard.data(forKey: "backupFolder") else { return nil }
        var stale = false
        #if os(macOS)
        return try? URL(resolvingBookmarkData: b, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
        #else
        return try? URL(resolvingBookmarkData: b, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        #endif
    }

    static func forgetFolder() { UserDefaults.standard.removeObject(forKey: "backupFolder") }

    /// Replace everything with a backup's contents. Returns how many records came back.
    @MainActor static func restore(_ d: Data, into ctx: ModelContext) -> Int? {
        guard let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], json["app"] as? String == "Gym",
              let records = json["records"] as? [[String: Any]] else { return nil }
        _ = now(ctx)                                             // just in case: today's state first
        ctx.wipeSyncedData()
        ctx.applySync(records: records, deleted: json["deleted"] as? [[String: Any]] ?? [])
        ctx.backfillSyncIDs()
        return records.count
    }
}

/// Settings: backups.
struct BackupSection: View {
    @Environment(\.modelContext) private var ctx
    @State private var picking = false
    @State private var restoring = false
    @State private var confirmRestore: Data?
    @State private var message: String?
    @State private var folder = Backup.chosenFolder()?.lastPathComponent

    var body: some View {
        Section {
            LabeledContent("Last backup", value: Backup.last.map { $0.formatted(.relative(presentation: .named).locale(appLocale)) } ?? "Not yet")
            Button("Back up now") {
                let out = Backup.now(ctx)
                message = out.map { "Saved here and in “\($0)”." } ?? "Saved inside the app."
            }
            Button(folder.map { "Also saving to “\($0)” · Change…" } ?? "Also save to a folder… (iCloud Drive, say)") { picking = true }
            if folder != nil { Button("Stop saving to that folder", role: .destructive) { Backup.forgetFolder(); folder = nil } }
            Button("Restore from a backup…") { restoring = true }
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
        } header: {
            Text("Backups")
        } footer: {
            Text("A full copy of your data once a day: the last \(Backup.keepInside) inside the app, and the last \(Backup.keepOutside) in the folder you choose. Restoring replaces what's here (and on your other device, at the next sync).")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
            if case .success(let url) = r { Backup.choose(url); folder = Backup.chosenFolder()?.lastPathComponent; _ = Backup.now(ctx) }
        }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.json]) { r in
            guard case .success(let url) = r else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            confirmRestore = try? Data(contentsOf: url)
            if confirmRestore == nil { message = "That file couldn't be read." }
        }
        .confirmationDialog("Replace all your data with this backup?", isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } }),
                            titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                if let d = confirmRestore { message = Backup.restore(d, into: ctx).map { "Restored \($0) records." } ?? "That isn't a Gym backup." }
                confirmRestore = nil
            }
        } message: {
            Text("Today's data is backed up first, so you can undo this.")
        }
    }
}
