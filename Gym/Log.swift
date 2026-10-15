import Foundation
import os

/// Structured logging (Console.app → filter "com.wavymaso.gym"), plus the last problems kept for
/// the Diagnostics page.
enum Log {
    private static let subsystem = "com.wavymaso.gym"
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let database = Logger(subsystem: subsystem, category: "database")
    static let ai = Logger(subsystem: subsystem, category: "ai")
    static let coaching = Logger(subsystem: subsystem, category: "coaching")
    static let importing = Logger(subsystem: subsystem, category: "import")
    static let network = Logger(subsystem: subsystem, category: "network")

    struct Problem: Codable, Identifiable {
        var id = UUID()
        var at: Date
        var area: String
        var message: String
    }

    /// Something went wrong that you might want to see later (kept: the last 60).
    static func problem(_ area: String, _ message: String) {
        Logger(subsystem: subsystem, category: area).error("\(message, privacy: .public)")
        var all = problems
        all.insert(Problem(at: Date(), area: area, message: message), at: 0)
        if let d = try? JSONEncoder().encode(Array(all.prefix(60))) { UserDefaults.standard.set(d, forKey: "recentProblems") }
    }

    static var problems: [Problem] {
        (UserDefaults.standard.data(forKey: "recentProblems")).flatMap { try? JSONDecoder().decode([Problem].self, from: $0) } ?? []
    }

    static func clearProblems() { UserDefaults.standard.removeObject(forKey: "recentProblems") }
}
