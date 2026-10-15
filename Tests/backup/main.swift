// Backup then restore into an empty store: everything comes back.  Run: ./run.sh <store copy>
import Foundation
import SwiftData
setvbuf(stdout, nil, _IONBF, 0)
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
MainActor.assumeIsolated {
    let src = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1])))
    let dst = try! ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let a = src.mainContext, b = dst.mainContext
    b.autosaveEnabled = false
    let d = Backup.data(a)
    print("backup size", d.count / 1024, "KB")
    let n = Backup.restore(d, into: b)
    check("restore reports records", (n ?? 0) > 0, n ?? -1)
    func c<T: PersistentModel>(_ t: T.Type, _ x: ModelContext) -> Int { (try? x.fetchCount(FetchDescriptor<T>())) ?? -1 }
    check("entries", c(FoodEntry.self, a) == c(FoodEntry.self, b), (c(FoodEntry.self, a), c(FoodEntry.self, b)))
    check("weights", c(WeightEntry.self, a) == c(WeightEntry.self, b))
    check("foods", c(Food.self, a) == c(Food.self, b))
    check("programs and targets", c(Program.self, a) == c(Program.self, b) && c(TargetSet.self, a) == c(TargetSet.self, b))
    check("exercises", c(Exercise.self, a) == c(Exercise.self, b))
    check("profile", c(Profile.self, b) == 1)
    let ka = (try? a.fetch(FetchDescriptor<FoodEntry>()))?.reduce(0) { $0 + $1.nutrients.kcal } ?? -1
    let kb = (try? b.fetch(FetchDescriptor<FoodEntry>()))?.reduce(0) { $0 + $1.nutrients.kcal } ?? -2
    check("calorie total identical", abs(ka - kb) < 0.001, (ka, kb))
    // Lossless: every record, every field, the same after the round trip.
    func fingerprint(_ x: ModelContext) -> Set<String> {
        let (recs, _) = x.syncChanges(since: .distantPast)
        return Set(recs.map { r in
            let data = (try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        })
    }
    let fa = fingerprint(a), fb = fingerprint(b)
    check("every record identical (\(fa.count))", fa == fb, "\(fa.subtracting(fb).count) differ")
    check("tombstones carried", ((try? b.fetchCount(FetchDescriptor<Tombstone>())) ?? 0) >= ((try? a.fetchCount(FetchDescriptor<Tombstone>())) ?? 0))
    check("not a Gym file is refused", Backup.restore(Data("{}".utf8), into: b) == nil)
}
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
