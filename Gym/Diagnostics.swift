import SwiftData
import SwiftUI
#if os(iOS)
import MetricKit
#endif

// More → Diagnostics: what version this is, how big the data is, when it last synced and backed
// up, what the launch check found, recent problems, and crash/hang reports from iOS (MetricKit).

#if os(iOS)
/// Receives iOS's daily performance and crash reports and keeps a one-line summary of each.
final class MetricsReceiver: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricsReceiver()
    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            let crashes = p.crashDiagnostics?.count ?? 0, hangs = p.hangDiagnostics?.count ?? 0
            let disk = p.diskWriteExceptionDiagnostics?.count ?? 0, cpu = p.cpuExceptionDiagnostics?.count ?? 0
            if crashes + hangs + disk + cpu > 0 {
                var parts: [String] = []
                if crashes > 0 { parts.append("\(crashes) crash\(crashes == 1 ? "" : "es")") }
                if hangs > 0 { parts.append("\(hangs) hang\(hangs == 1 ? "" : "s")") }
                if cpu > 0 { parts.append("\(cpu) CPU spike\(cpu == 1 ? "" : "s")") }
                if disk > 0 { parts.append("\(disk) heavy disk write\(disk == 1 ? "" : "s")") }
                Log.problem("metrics", "iOS reported " + parts.joined(separator: ", ") + " (\(p.timeStampBegin.formatted(date: .abbreviated, time: .omitted)))")
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads {
            if let launch = p.applicationLaunchMetrics?.histogrammedTimeToFirstDraw.bucketEnumerator.allObjects as? [MXHistogramBucket<UnitDuration>],
               let worst = launch.max(by: { $0.bucketCount < $1.bucketCount }) {
                UserDefaults.standard.set(worst.bucketEnd.converted(to: .milliseconds).value, forKey: "typicalLaunchMs")
            }
        }
    }
}
#endif

struct DiagnosticsView: View {
    @Environment(\.modelContext) private var ctx
    @State private var problems = Log.problems
    @State private var report = IntegrityReport.last

    var body: some View {
        Form {
            Section("This app") {
                row("Version", "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                if let e = Signing.expires { row("Signed until", e.formatted(date: .abbreviated, time: .shortened)) }
                if let ms = UserDefaults.standard.object(forKey: "typicalLaunchMs") as? Double { row("Typical launch", "\(Int(ms)) ms") }
            }
            Section("Data") {
                row("Database", sizeText)
                row("Records", "\(count(FoodEntry.self)) foods logged · \(count(WeightEntry.self)) weigh-ins · \(count(WorkoutSet.self)) sets")
                row("Data model", "#" + String(StoreSafety.fingerprint(Schema(allModels)).utf8.reduce(UInt32(5381)) { ($0 &* 33) &+ UInt32($1) } % 100000))
                row("Copies before updates", "\(StoreSafety.snapshots.count)")
                row("Last backup", Backup.last.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                #if os(iOS)
                row("Last sync with the Mac", SyncClient.shared.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                #endif
            }
            Section {
                Text(report?.summary ?? "Not run yet").foregroundStyle(report?.isClean == false ? palette.warn : .secondary)
                Button("Check again") {
                    let r = ctx.integrityCheck()
                    IntegrityReport.last = r
                    animate { report = r; problems = Log.problems }
                }
            } header: { Text("Integrity check") } footer: { Text("Runs at every launch: duplicates, leftovers, impossible numbers. Safe fixes are made automatically.") }
            Section {
                if problems.isEmpty {
                    Text("Nothing has gone wrong recently.").foregroundStyle(.secondary)
                } else {
                    ForEach(problems.prefix(30)) { p in
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(p.message).font(.secondaryText)
                            Text("\(p.area) · \(p.at.formatted(date: .abbreviated, time: .shortened))").font(.note).foregroundStyle(.secondary)
                        }
                    }
                    Button("Clear", role: .destructive) { Log.clearProblems(); animate { problems = [] } }
                }
            } header: { Text("Recent problems") }
            Section {
                NavigationLink("Developer") { DeveloperView() }
            } footer: { Text("Algorithm choices, for comparing models.") }
            Section {
                ShareLink(item: bundle, preview: SharePreview("Gym diagnostics")) { Label("Export diagnostics", systemImage: "square.and.arrow.up") }
            } footer: { Text("A text file with the above, for sending to whoever is helping. No food, weights or photos in it.") }
        }
        .themedForm()
        .navigationTitle("Diagnostics")
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
    }

    private func count<T: PersistentModel>(_ t: T.Type) -> Int { (try? ctx.fetchCount(FetchDescriptor<T>())) ?? 0 }

    private var sizeText: String {
        let url = ModelConfiguration().url
        let bytes = ["", "-wal", "-shm"].compactMap { (try? FileManager.default.attributesOfItem(atPath: url.path + $0))?[.size] as? Int }.reduce(0, +)
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var bundle: String {
        var s = "Gym diagnostics \(Date().formatted())\n"
        s += "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")\n"
        s += "Database \(sizeText), \(count(FoodEntry.self)) entries, \(count(WeightEntry.self)) weigh-ins, \(count(WorkoutSet.self)) sets\n"
        s += "Last backup \(Backup.last?.description ?? "never")\n"
        s += "Integrity: \(report?.summary ?? "not run")\n\nRecent problems:\n"
        s += problems.map { "\($0.at) [\($0.area)] \($0.message)" }.joined(separator: "\n")
        return s
    }
}
