import Charts
import PhotosUI
import SwiftData
import SwiftUI
#if os(macOS)
import UniformTypeIdentifiers
#endif

// MARK: - On the Weight page

struct BodySection: View {
    @Environment(\.modelContext) private var ctx
    @Query private var profiles: [Profile]
    @Query(sort: \Measurement.day) private var measurements: [Measurement]
    @Query(sort: \ProgressPhoto.day, order: .reverse) private var photos: [ProgressPhoto]
    @State private var adding = false
    @State private var detail: BodySite?
    @State private var comparing = false
    @State private var addingPhoto = false
    @State private var viewing: ProgressPhoto?

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        VStack(spacing: 16) {
            Card(title: "Measurements", systemImage: "ruler",
                 accessory: AnyView(Button { adding = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(.borderless))) {
                let latest = latestBySite
                if latest.isEmpty {
                    Text("Weight doesn't show everything: a smaller waist at the same weight is fat lost and muscle gained. Measure every 2–4 weeks, same time of day.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Add measurements") { adding = true }.buttonStyle(.bordered)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                        ForEach(BodySite.allCases.filter { latest[$0] != nil }) { s in
                            Button { detail = s } label: { tile(s, latest[s]!, unit) }.buttonStyle(.plain)
                        }
                    }
                    if let p = profiles.first, let bf = navyBodyFat(sex: p.sexValue, heightCm: p.heightCm, waist: latest[.waist]?.cm,
                                                                   neck: latest[.neck]?.cm, hips: latest[.hips]?.cm) {
                        HStack {
                            Label("Body fat, tape estimate", systemImage: "percent").font(.callout)
                            Spacer()
                            Text("\(number(bf, digits: 1)) %").font(.headline).monospacedDigit()
                        }
                        Text("US Navy method from your waist, neck\(p.sexValue == .female ? ", hips" : "") and height: usually within 3–4 % of a DEXA scan.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Card(title: "Progress photos", systemImage: "person.crop.rectangle",
                 accessory: AnyView(HStack(spacing: 12) {
                     if Set(photos.map(\.day)).count >= 2 { Button("Compare") { comparing = true }.buttonStyle(.borderless) }
                     Button { addingPhoto = true } label: { Label("Add", systemImage: "plus") }.buttonStyle(.borderless)
                 })) {
                if photos.isEmpty {
                    Text("Same spot, same light, every few weeks: the mirror changes too slowly to notice day to day. Photos stay on your devices.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Add a photo") { addingPhoto = true }.buttonStyle(.bordered)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photos) { p in
                                Button { viewing = p } label: {
                                    VStack(spacing: 4) {
                                        PhotoThumb(data: p.jpeg).frame(width: 96, height: 128)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        Text(short(p.day)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { MeasurementsSheet() }
        .sheet(item: $detail) { MeasurementDetail(site: $0) }
        .sheet(isPresented: $addingPhoto) { AddProgressPhoto() }
        .sheet(isPresented: $comparing) { CompareView() }
        .sheet(item: $viewing) { PhotoViewer(photo: $0) }
    }

    /// The latest value of each site, and how it's changed since about 30 days before.
    private var latestBySite: [BodySite: (cm: Double, day: String, change: Double?)] {
        var out: [BodySite: (cm: Double, day: String, change: Double?)] = [:]
        for s in BodySite.allCases {
            let list = measurements.filter { $0.site == s.rawValue }
            guard let last = list.last else { continue }
            let before = list.last { daysBetween($0.day, last.day) >= 21 }
            out[s] = (last.cm, last.day, before.map { last.cm - $0.cm })
        }
        return out
    }

    private func tile(_ s: BodySite, _ v: (cm: Double, day: String, change: Double?), _ unit: WeightUnit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(unit.formatLength(v.cm)).font(.number(20)).monospacedDigit()
            if let c = v.change, abs(c) >= 0.05 {
                Delta(text: (c > 0 ? "+" : "−") + unit.formatLength(abs(c)), good: s.smallerIsBetter.map { $0 == (c < 0) })
            } else {
                Text(short(v.day)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private func short(_ day: String) -> String {
    date(fromKey: day).formatted(.dateTime.day().month(.abbreviated).locale(appLocale))
}

// MARK: - Adding measurements

struct MeasurementsSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @Query(sort: \Measurement.day) private var measurements: [Measurement]
    @State private var day = Date()
    @State private var values: [BodySite: String] = [:]

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        NavigationStack {
            Form {
                DatePicker("Date", selection: $day, in: ...Date(), displayedComponents: .date)
                Section {
                    ForEach(BodySite.allCases) { s in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.label)
                                Text(s.hint).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField(last(s).map { number(unit.fromCm($0), digits: 1) } ?? "–", text: binding(s))
                                .multilineTextAlignment(.trailing).frame(width: 80).monospacedDigit()
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text(unit.lengthUnit).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Leave any blank. The grey number is last time's. Measure on bare skin, tape snug but not pressing.")
                }
            }
            .themedForm()
            .navigationTitle("Measurements")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(unit) }.disabled(parsed(unit).isEmpty) }
            }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 440, height: 620)
        #endif
    }

    private func last(_ s: BodySite) -> Double? { measurements.last { $0.site == s.rawValue }?.cm }

    private func binding(_ s: BodySite) -> Binding<String> {
        Binding(get: { values[s] ?? "" }, set: { values[s] = $0 })
    }

    private func parsed(_ unit: WeightUnit) -> [BodySite: Double] {
        values.compactMapValues { Double($0.replacingOccurrences(of: ",", with: ".")) }.filter { $0.value > 0 }.mapValues(unit.toCm)
    }

    private func save(_ unit: WeightUnit) {
        ctx.saveMeasurements(parsed(unit), day: dayKey(day))
        dismiss()
    }
}

/// One site over time.
struct MeasurementDetail: View {
    let site: BodySite
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [Profile]
    @Query(sort: \Measurement.day) private var all: [Measurement]

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        let list = all.filter { $0.site == site.rawValue }
        NavigationStack {
            List {
                if list.count >= 2 {
                    Chart(list) { m in
                        LineMark(x: .value("Day", date(fromKey: m.day)), y: .value(site.label, unit.fromCm(m.cm)))
                            .interpolationMethod(.monotone).foregroundStyle(palette.accent)
                        PointMark(x: .value("Day", date(fromKey: m.day)), y: .value(site.label, unit.fromCm(m.cm)))
                            .foregroundStyle(palette.accent)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200).listRowBackground(Color.clear)
                }
                ForEach(list.reversed()) { m in
                    HStack {
                        Text(date(fromKey: m.day).formatted(.dateTime.day().month(.abbreviated).year().locale(appLocale)))
                        Spacer()
                        Text(unit.formatLength(m.cm)).monospacedDigit()
                    }
                    .contextMenu { Button("Delete", role: .destructive) { ctx.delete(m); ctx.commit() } }
                }
                .onDelete { idx in for i in idx { ctx.delete(list.reversed()[i]) }; ctx.commit() }
            }
            .themedList()
            .navigationTitle(site.label)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 440, height: 520)
        #endif
    }
}

// MARK: - Photos

struct PhotoThumb: View {
    let data: Data
    var maxPixels = 400
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color.raisedBackground
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
        }
        .clipped()
        .task(id: data.count) { image = PhotoAI.prepare(data, maxPixels: maxPixels)?.image }
    }
}

struct AddProgressPhoto: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \ProgressPhoto.day, order: .reverse) private var previous: [ProgressPhoto]
    private var lastPhoto: ProgressPhoto? { previous.first { $0.pose == pose.rawValue } }
    @Environment(\.dismiss) private var dismiss
    @State private var pose = Pose.front
    @State private var day = Date()
    @State private var jpeg: Data?
    @State private var camera = false
    @State private var item: PhotosPickerItem?
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Pose", selection: $pose) { ForEach(Pose.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                DatePicker("Date", selection: $day, in: ...Date(), displayedComponents: .date)
                Section {
                    if let jpeg {
                        PhotoThumb(data: jpeg, maxPixels: 800).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 14))
                            .listRowInsets(EdgeInsets())
                    }
                    #if os(iOS)
                    Button { camera = true } label: { Label("Take photo", systemImage: "camera") }
                    #else
                    Button { importing = true } label: { Label("Choose file…", systemImage: "folder") }
                    #endif
                    PhotosPicker(selection: $item, matching: .images) { Label("Choose from Photos", systemImage: "photo") }
                } footer: {
                    Text("The camera shows your last \(pose.label.lowercased()) photo faintly: line yourself up with it. Same place, same light, same time of day (morning, before eating).")
                }
            }
            .themedForm()
            .navigationTitle("Progress photo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $camera) { CameraPicker(ghost: lastPhoto?.jpeg) { use($0) }.ignoresSafeArea() }
            #else
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { r in
                if case .success(let url) = r {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    if let d = try? Data(contentsOf: url) { use(d) }
                }
            }
            #endif
            .onChange(of: item) { _, i in
                Task { if let d = try? await i?.loadTransferable(type: Data.self) { use(d) } }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let jpeg { ctx.insert(ProgressPhoto(day: dayKey(day), pose: pose.rawValue, jpeg: jpeg)); ctx.commit() }
                        dismiss()
                    }
                    .disabled(jpeg == nil)
                }
            }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 440, height: 620)
        #endif
    }

    /// Kept at 1600 px: sharp enough to compare, small enough to sync.
    private func use(_ data: Data) { jpeg = PhotoAI.prepare(data, maxPixels: 1600)?.jpeg }
}

struct PhotoViewer: View {
    let photo: ProgressPhoto
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            PhotoThumb(data: photo.jpeg, maxPixels: 1600).aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16)).padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .pageBackground()
                .navigationTitle("\(Pose(rawValue: photo.pose)?.label ?? "") · \(short(photo.day))")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .destructiveAction) { Button("Delete", role: .destructive) { confirmDelete = true } }
                }
                .confirmationDialog("Delete this photo?", isPresented: $confirmDelete) {
                    Button("Delete", role: .destructive) { ctx.delete(photo); ctx.commit(); dismiss() }
                }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 520, height: 720)
        #endif
    }
}

/// Two dates side by side, with what the scale and the tape said then.
struct CompareView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProgressPhoto.day) private var photos: [ProgressPhoto]
    @Query(sort: \WeightEntry.day) private var weights: [WeightEntry]
    @Query(sort: \Measurement.day) private var measurements: [Measurement]
    @Query private var profiles: [Profile]
    @State private var pose = Pose.front
    @State private var before: String?
    @State private var after: String?

    var body: some View {
        let unit = profiles.first?.weight ?? .kg
        let days = Array(Set(photos.filter { $0.pose == pose.rawValue }.map(\.day))).sorted()
        NavigationStack {
            VStack(spacing: 14) {
                Picker("Pose", selection: $pose) { ForEach(Pose.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                if days.count < 2 {
                    Spacer()
                    Text("Add \(pose.label.lowercased()) photos on two different days to compare them.").foregroundStyle(.secondary)
                    Spacer()
                } else {
                    let a = before.flatMap { days.contains($0) ? $0 : nil } ?? days.first!
                    let b = after.flatMap { days.contains($0) ? $0 : nil } ?? days.last!
                    HStack(alignment: .top, spacing: 10) {
                        side(a, days: days, pick: { before = $0 }, unit)
                        side(b, days: days, pick: { after = $0 }, unit)
                    }
                    summary(a, b, unit)
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pageBackground()
            .navigationTitle("Compare")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .appStyle()
        #if os(macOS)
        .frame(width: 720, height: 720)
        #endif
    }

    private func side(_ day: String, days: [String], pick: @escaping (String) -> Void, _ unit: WeightUnit) -> some View {
        VStack(spacing: 8) {
            Menu {
                ForEach(days.reversed(), id: \.self) { d in Button(short(d)) { pick(d) } }
            } label: {
                HStack(spacing: 4) { Text(short(day)).font(.headline); Image(systemName: "chevron.down").font(.caption) }
            }
            .menuStyle(.borderlessButton).fixedSize()
            if let p = photos.last(where: { $0.day == day && $0.pose == pose.rawValue }) {
                PhotoThumb(data: p.jpeg, maxPixels: 1000).aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let w = weight(near: day) { Text(unit.format(w)).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func summary(_ a: String, _ b: String, _ unit: WeightUnit) -> some View {
        let weeks = Double(daysBetween(a, b)) / 7
        let lines: [String] = {
            var out = ["\(number(weeks, digits: weeks < 10 ? 1 : 0)) weeks apart"]
            if let wa = weight(near: a), let wb = weight(near: b) {
                out.append("Weight \(wb >= wa ? "+" : "−")\(unit.format(abs(wb - wa)))")
            }
            for s in [BodySite.waist, .chest, .armR, .thighR] {
                if let ma = tape(s, near: a), let mb = tape(s, near: b), abs(mb - ma) >= 0.1 {
                    out.append("\(s.label) \(mb >= ma ? "+" : "−")\(unit.formatLength(abs(mb - ma)))")
                }
            }
            return out
        }()
        Text(lines.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }

    /// The weigh-in closest to a day (within a week).
    private func weight(near day: String) -> Double? {
        weights.filter { abs(daysBetween($0.day, day)) <= 7 }.min { abs(daysBetween($0.day, day)) < abs(daysBetween($1.day, day)) }?.kg
    }

    private func tape(_ s: BodySite, near day: String) -> Double? {
        measurements.filter { $0.site == s.rawValue && abs(daysBetween($0.day, day)) <= 14 }
            .min { abs(daysBetween($0.day, day)) < abs(daysBetween($1.day, day)) }?.cm
    }
}
