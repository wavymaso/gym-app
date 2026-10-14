// Water and activity sync between two stores, through handleSync and JSON like the network.
// Run: ./run.sh
import Foundation
import SwiftData
setvbuf(stdout, nil, _IONBF, 0)
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { print(ok ? "ok   \(n)" : "FAIL \(n) got \(got)"); if !ok { fails += 1 } }
var keep: [ModelContainer] = []
@MainActor func ctx() throws -> ModelContext {
    let c = try ModelContainer(for: Schema(allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    c.mainContext.autosaveEnabled = false; keep.append(c); return c.mainContext
}
@MainActor func round(_ phone: ModelContext, _ mac: ModelContext, _ since: inout Double, _ pushed: inout Double) {
    if phone.hasChanges { phone.commit() }
    let started = Date()
    let (r, d) = phone.syncChanges(since: Date(timeIntervalSince1970: pushed))
    let body = try! JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: ["since": since, "records": r, "deleted": d])) as! [String: Any]
    let reply = try! JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: handleSync(body, ctx: mac))) as! [String: Any]
    phone.applySync(records: reply["records"] as! [[String: Any]], deleted: reply["deleted"] as! [[String: Any]])
    since = (reply["now"] as! Double) - 60; pushed = started.timeIntervalSince1970
}
@MainActor func run() throws {
    let mac = try ctx(), phone = try ctx()
    var since = 0.0, pushed = 0.0
    phone.addWater(250); phone.addWater(500)
    phone.setActivity(day: dayKey(), steps: 4321, activeKcal: 210)
    round(phone, mac, &since, &pushed)
    check("water reaches the Mac", mac.water(on: dayKey()).reduce(0) { $0 + $1.ml } == 750)
    check("steps reach the Mac", mac.activity(on: dayKey())?.steps == 4321)
    Thread.sleep(forTimeInterval: 0.01)
    phone.setActivity(day: dayKey(), steps: 8000, activeKcal: 400); phone.undoWater()
    round(phone, mac, &since, &pushed)
    let n = try mac.fetchCount(FetchDescriptor<DailyActivity>())
    check("steps update, one record per day", mac.activity(on: dayKey())?.steps == 8000 && n == 1, n)
    check("undo removes the glass on the Mac", mac.water(on: dayKey()).reduce(0) { $0 + $1.ml } == 250)
    mac.addWater(330)
    round(phone, mac, &since, &pushed)
    check("Mac's water reaches the phone", phone.water(on: dayKey()).reduce(0) { $0 + $1.ml } == 580)
    phone.setActivity(day: dayKey(), steps: 8000, activeKcal: 400)
    check("same steps again: nothing changes", !phone.hasChanges)
    UserDefaults.standard.removeObject(forKey: "waterGoalMl")
    phone.logWeight(111)
    check("auto water goal 35 ml/kg", phone.waterGoalMl == 3900, phone.waterGoalMl)
}
MainActor.assumeIsolated { do { try run() } catch { print("ERROR", error); fails += 1 } }
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED"); exit(fails == 0 ? 0 : 1)
