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
