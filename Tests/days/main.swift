// The integer day maths in Trend.swift against Foundation's calendar, every day 1950–2100.
import Foundation
var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
var d = f.date(from: "1950-01-01")!, n = dayNumber("1950-01-01"), bad = 0, count = 0
let end = f.date(from: "2100-12-31")!
while d <= end {
    let key = f.string(from: d)
    if dayKey(number: n) != key || dayNumber(key) != n { bad += 1; if bad < 5 { print("mismatch", key, n, dayKey(number: n)) } }
    d = cal.date(byAdding: .day, value: 1, to: d)!; n += 1; count += 1
}
let ok = bad == 0 && daysBetween("2024-02-28", "2024-03-01") == 2 && addDays("2025-12-31", 1) == "2026-01-01"
    && addDays("2026-03-01", -1) == "2026-02-28" && days(from: "2026-10-12", through: "2026-10-14") == ["2026-10-12", "2026-10-13", "2026-10-14"]
print(ok ? "ALL PASSED (\(count) days)" : "FAILED \(bad)"); exit(ok ? 0 : 1)
