import Foundation
var fails = 0
func check(_ n: String, _ ok: Bool) { if !ok { fails += 1; print("FAIL", n) } }
let all = Evidence.all
check("ids unique", Set(all.map(\.id)).count == all.count)
for e in all {
    check("\(e.id): default inside its range", e.range.contains(e.value))
    check("\(e.id): has a source", !e.sources.isEmpty)
    check("\(e.id): has a description", e.description.count > 20)
    check("\(e.id): non-D entries cite a published source", e.grade == .D || e.sources.contains { $0.link.hasPrefix("https://") })
    check("\(e.id): verified", e.verified)
}
if CommandLine.arguments.contains("write") {
    var md = "# Evidence registry\n\nGenerated from `Gym/EvidenceRegistry.swift` (don't edit by hand: `Tests/evidence/run.sh write`).\n\n"
    md += "Every citation was checked by web search on 15 Oct 2026. Grades: **A** meta-analysis or several RCTs · **B** a single RCT or strong observational/model study · **C** expert consensus, position stand or narrative review · **D** practitioner convention, a fit to data, or the user's choice.\n\n"
    md += "Where the evidence is weak or mixed (diet breaks, refeeds, bulking rates, sleep), it says so here and in the app.\n\n"
    md += "| Id | What | Default | Range | Grade |\n|---|---|---|---|---|\n"
    func num(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
    for e in all {
        let d = e.unit == "—" ? "—" : "\(num(e.value)) \(e.unit)"
        let r = e.range.lowerBound == e.range.upperBound ? "—" : "\(num(e.range.lowerBound))–\(num(e.range.upperBound))"
        md += "| `\(e.id)` | \(e.description) | \(d) | \(r) | \(e.grade.rawValue) |\n"
    }
    md += "\n## Details\n"
    for e in all {
        md += "\n### `\(e.id)` (grade \(e.grade.rawValue))\n\n\(e.description)\n\n"
        md += "- **Studied in:** \(e.population)\n"
        if !e.note.isEmpty { md += "- **Note:** \(e.note)\n" }
        for s in e.sources { md += "- \(s.citation). \(s.link.hasPrefix("https") ? "<\(s.link)>" : "`\(s.link)`")\n" }
    }
    try! md.write(toFile: "../../EVIDENCE.md", atomically: true, encoding: .utf8)
    print("wrote EVIDENCE.md (\(all.count) entries)")
}
print(fails == 0 ? "ALL PASSED" : "\(fails) FAILED")
