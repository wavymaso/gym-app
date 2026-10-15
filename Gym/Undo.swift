import SwiftData
import SwiftUI

extension ModelContext {
    /// Delete now, with "Undo" for a few seconds: the records come back exactly as they were (same
    /// sync IDs; being newer than the deletion, they also come back on the other device).
    @MainActor func deleteWithUndo<T: Syncable>(_ items: [T], _ message: String) {
        guard !items.isEmpty else { return }
        let saved = items.map { (data: $0.encode(), id: $0.syncID) }
        animate(Motion.snappy) { for i in items { delete(i) }; commit() }
        UndoCenter.shared.offer(message) { [self] in
            animate(Motion.snappy) {
                for s in saved { let n = T.blank(); n.decode(s.data); n.syncID = s.id; insert(n) }
                commit()
            }
        }
    }
}

extension ModelContext {
    /// `day` at the clock time of `clock` (or of the entry itself).
    private func when(_ e: FoodEntry, on day: String, at clock: Date?) -> Date {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: clock ?? e.time)
        return cal.date(bySettingHour: hm.hour ?? 12, minute: hm.minute ?? 0, second: 0, of: date(fromKey: day)) ?? e.time
    }

    /// Exact copies (every field, micronutrients included) on `day`; Undo removes them again.
    @MainActor func copyEntries(_ es: [FoodEntry], to day: String, at clock: Date? = nil) {
        guard !es.isEmpty else { return }
        var made: [FoodEntry] = []
        animate(Motion.snappy) {
            for e in es.sorted(by: { $0.time < $1.time }) {
                let n = FoodEntry.blank(); n.decode(e.encode())
                n.syncID = UUID().uuidString
                n.day = day; n.time = when(e, on: day, at: clock)
                insert(n); made.append(n)
            }
            commit()
        }
        Haptics.success()
        UndoCenter.shared.offer(es.count == 1 ? "Copied \(es[0].name)" : "Copied \(es.count) foods") { [self] in
            for m in made { delete(m) }
            commit()
        }
    }

    /// Move to `day` (at `clock`, or the same time of day); Undo puts them back.
    @MainActor func moveEntries(_ es: [FoodEntry], to day: String, at clock: Date? = nil) {
        guard !es.isEmpty else { return }
        let before = es.map { (e: $0, day: $0.day, time: $0.time) }
        animate(Motion.snappy) {
            for e in es { let t = when(e, on: day, at: clock); e.day = day; e.time = t }
            commit()
        }
        Haptics.success()
        UndoCenter.shared.offer(es.count == 1 ? "Moved \(es[0].name)" : "Moved \(es.count) foods") { [self] in
            for b in before { b.e.day = b.day; b.e.time = b.time }
            commit()
        }
    }

    /// Copies next to the originals.
    @MainActor func duplicateEntries(_ es: [FoodEntry]) {
        for e in es { let n = FoodEntry.blank(); n.decode(e.encode()); n.syncID = UUID().uuidString; insert(n) }
        commit()
        Haptics.tap()
    }
}
