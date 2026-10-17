import SwiftData
import SwiftUI
#if os(iOS)
import HealthKit
import VisionKit
#endif

// iPhone-only features: the barcode camera and weigh-ins from Apple Health.

#if os(iOS)
/// Point the camera at a barcode; hands back the number once.
struct BarcodeScanner: View {
    var title = "Scan a barcode"
    var qr = false                                    // the Mac's pairing code instead of food barcodes
    let found: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerView(qr: qr) { code in found(code); dismiss() }.ignoresSafeArea()
                        .overlay(alignment: .bottom) {
                            if qr {
                                Text("Hold the phone about an arm's length from the screen so the whole code fits.")
                                    .font(.secondaryEmphasis).multilineTextAlignment(.center)
                                    .padding(Space.m).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.m))
                                    .padding(Space.xl)
                            }
                        }
                } else {
                    ContentUnavailableView("Camera not available", systemImage: "camera",
                                           description: Text("Allow camera access for Gym in Settings → Privacy & Security → Camera."))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct ScannerView: UIViewControllerRepresentable {
    let qr: Bool
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: qr ? [.qr] : [.ean13, .ean8, .upce, .code128])],
                                           qualityLevel: qr ? .accurate : .balanced, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        var done = false
        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let b) in items {
                if let code = b.payloadStringValue, !done {
                    done = true
                    Haptics.success()
                    found(code)
                }
            }
        }
    }
}

/// Weigh-ins from Apple Health (a smart scale, or ones you entered there): the first of each day.
enum HealthWeights {
    static let store = HKHealthStore()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestAccess() async -> Bool {
        guard available else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [HKQuantityType(.bodyMass)])
            return true
        } catch { return false }
    }

    /// Adds days you haven't weighed in here. Returns how many were added.
    @MainActor static func importNew(into ctx: ModelContext, days: Int = 120) async -> Int {
        guard available else { return 0 }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKSamplePredicate.quantitySample(type: HKQuantityType(.bodyMass),
                                                         predicate: HKQuery.predicateForSamples(withStart: start, end: nil))
        let query = HKSampleQueryDescriptor(predicates: [predicate], sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await query.result(for: store) else { return 0 }
        let have = Set(((try? ctx.fetch(FetchDescriptor<WeightEntry>())) ?? []).map(\.day))
        var firstOfDay: [String: Double] = [:]
        for s in samples {
            let day = dayKey(s.startDate)
            if firstOfDay[day] == nil { firstOfDay[day] = s.quantity.doubleValue(for: .gramUnit(with: .kilo)) }
        }
        var added = 0
        for (day, kg) in firstOfDay where !have.contains(day) {
            ctx.insert(WeightEntry(day: day, kg: kg)); added += 1
        }
        ctx.commit()
        return added
    }
}
#endif

/// Settings section: Apple Health (iPhone only).
struct HealthSection: View {
    @AppStorage("healthWeights") private var on = false
    @Environment(\.modelContext) private var ctx
    @State private var message: String?

    var body: some View {
        #if os(iOS)
        Section {
            Toggle("Weigh-ins from Apple Health", isOn: $on)
                .onChange(of: on) { _, v in
                    guard v else { return }
                    Task {
                        if await HealthWeights.requestAccess() {
                            let n = await HealthWeights.importNew(into: ctx)
                            message = n == 0 ? "No new weigh-ins in Health." : "Added \(n) weigh-in\(n == 1 ? "" : "s") from Health."
                        } else {
                            message = "Health access wasn't allowed. You can change it in the Health app → Sharing → Apps."
                        }
                    }
                }
            if let message { Text(message).font(.secondaryText).foregroundStyle(.secondary) }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Days you haven't weighed in here get the first weigh-in of that day from Health, every time you open the app.")
        }
        #endif
    }
}
