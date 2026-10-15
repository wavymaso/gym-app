var fails = 0
func check(_ n: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", n) } }
// Usual day: 8 entries.
let history = (1...20).map { LoggedDay(day: "h\($0)", entries: 8, kcal: 2400, target: 2400) }
let usual = PartialDayRule.usualEntries(history)
check("usual is the median", usual == 8)
let days = [
    LoggedDay(day: "a", entries: 2, kcal: 600, target: 2400),     // few entries, far under: suspect
    LoggedDay(day: "b", entries: 2, kcal: 2200, target: 2400),    // few entries but a big meal: fine
    LoggedDay(day: "c", entries: 7, kcal: 900, target: 2400),     // usual entries, just ate little: fine
    LoggedDay(day: "d", entries: 1, kcal: 500, target: 600),      // a fasting day near its own target: fine
    LoggedDay(day: "e", entries: 3, kcal: 1000, target: nil),     // no target known: never flagged
]
check("only the half-logged day is flagged", PartialDayRule.suspects(days, usual: usual) == ["a"])
check("not enough history: nothing flagged", PartialDayRule.suspects(days, usual: PartialDayRule.usualEntries(Array(history.prefix(5)))).isEmpty)
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED")
