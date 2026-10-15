import Foundation
var fails = 0
func check(_ n: String, _ ok: Bool, _ got: Any = "") { if !ok { fails += 1; print("FAIL", n, got) } }
let madrid = TimeZone(identifier: "Europe/Madrid")!, riyadh = TimeZone(identifier: "Asia/Riyadh")!
func at(_ s: String, _ tz: TimeZone) -> Date {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz; f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}
UserDefaults.standard.removeObject(forKey: "dayStartHour")

// Spain's clock changes: every hour still lands on the right day, and day arithmetic doesn't skip.
NSTimeZone.default = madrid
for (night, label) in [("2026-03-29", "spring forward"), ("2026-10-25", "fall back")] {
    let before = addDays(night, -1)
    check("\(label): 23:30 the evening before", dayKey(at("\(before) 23:30", madrid)) == before)
    check("\(label): 00:30", dayKey(at("\(night) 00:30", madrid)) == night)
    check("\(label): 03:30", dayKey(at("\(night) 03:30", madrid)) == night)
    check("\(label): 23:59", dayKey(at("\(night) 23:59", madrid)) == night)
    check("\(label): next day", addDays(night, 1) == dayKey(at("\(night) 23:59", madrid).addingTimeInterval(120)))
    check("\(label): days between", daysBetween(before, addDays(night, 1)) == 2)
    check("\(label): key round trip", dayKey(date(fromKey: night)) == night)
}
// 24 consecutive hours across each change map to at most two days, in order.
for night in ["2026-03-29", "2026-10-25"] {
    var keys: [String] = []
    var t = at("\(night) 00:00", madrid)
    for _ in 0..<26 { keys.append(dayKey(t)); t.addTimeInterval(3600) }
    check("hours in order \(night)", keys == keys.sorted() && Set(keys).count == 2, Set(keys))
}

// Travel Madrid → Riyadh with the app open: "today" follows the new zone straight away.
NSTimeZone.default = madrid
let late = at("2026-10-10 23:30", madrid)            // 00:30 on the 11th in Riyadh
check("Madrid evening", dayKey(late) == "2026-10-10", dayKey(late))
NSTimeZone.default = riyadh
check("same moment in Riyadh is the next day", dayKey(late) == "2026-10-11", dayKey(late))
// A day's key, read back in the new zone, is still that day (stored entries don't move).
check("stored day reads back", dayKey(date(fromKey: "2026-10-10")) == "2026-10-10")
// A flight over midnight: departing 22:00 Madrid, landing 05:00 Riyadh: two different days, no gap.
let dep = at("2026-10-12 22:00", madrid), arr = at("2026-10-13 05:00", riyadh)
NSTimeZone.default = madrid; let k1 = dayKey(dep)
NSTimeZone.default = riyadh; let k2 = dayKey(arr)
check("flight: consecutive days", daysBetween(k1, k2) == 1, (k1, k2))

// Day start: at 4, 02:00 still belongs to yesterday; 05:00 is today. Default (midnight) unchanged.
NSTimeZone.default = madrid
let two = at("2026-10-15 02:00", madrid), five = at("2026-10-15 05:00", madrid)
check("midnight default", todayKey(now: two) == "2026-10-15")
UserDefaults.standard.set(4, forKey: "dayStartHour")
check("02:00 counts for yesterday", todayKey(now: two) == "2026-10-14", todayKey(now: two))
check("05:00 is today", todayKey(now: five) == "2026-10-15")
UserDefaults.standard.set(12, forKey: "dayStartHour")
check("clamped to 6", dayStartHour == 6)
UserDefaults.standard.removeObject(forKey: "dayStartHour")
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED")
