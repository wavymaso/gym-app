var fails = 0
func check(_ n: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", n) } }
// Rejected: anything that states a number.
for bad in ["• Lock in 2113 kcal to start losing.", "• Eat 76g more protein.", "• Weight up 0.41 kg last week.",
            "• Aim for two thousand calories.", "• You're at ninety percent of protein.", "• Cut 10% of carbs.",
            "• Keep fat around 60 grams."] {
    check("rejects: \(bad)", !CoachGuard.isNumberFree(bad))
}
// Allowed: advice in words.
for good in ["• Protein is well behind: make dinner a big lean serving.", "• The trend is a little above your goal rate; your check-in will handle it.",
             "• Train today: it's been a quiet week in the gym."] {
    check("allows: \(good)", CoachGuard.isNumberFree(good))
}
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED")
