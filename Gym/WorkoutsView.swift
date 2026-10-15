import Charts
import SwiftData
import SwiftUI
import UserNotifications

/// Start a workout (empty or from a routine), see this week's training, and your history.
/// While a workout is going, this page shows it.
struct WorkoutsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Workout> { $0.end == nil }) private var active: [Workout]
    @Query(filter: #Predicate<Workout> { $0.end != nil }, sort: \Workout.start, order: .reverse) private var finished: [Workout]
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query private var profiles: [Profile]
    @State private var editingRoutine: Routine?
    @State private var newRoutine = false
    @State private var showing: Workout?

    @State private var summary: Workout?
    @State private var lastActiveKey: String?

    var body: some View {
        Group {
            if let w = active.first {
                ActiveWorkoutView(workout: w).navigationTitle("Workout")
                    #if os(iOS)
                    .toolbar(.hidden, for: .navigationBar)
                    #endif
            } else {
                overview
            }
        }
        .onChange(of: active.first?.key, initial: true) { old, new in
            // A workout just finished: show how it went.
            if new == nil, let k = lastActiveKey, let w = finished.first(where: { $0.key == k }) { summary = w }
            #if os(iOS)
            if new == nil { RestLive.end() }
            else { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) } }
            #endif
            lastActiveKey = new
        }
        .sheet(item: $summary) { WorkoutSummary(workout: $0) }
    }

    private var nextRoutine: Routine? {
        guard !routines.isEmpty else { return nil }
        if let lastKey = finished.first(where: { $0.routineKey != nil })?.routineKey, let i = routines.firstIndex(where: { $0.key == lastKey }) {
            return routines[(i + 1) % routines.count]
        }
        return routines.first
    }

    private var overview: some View {
        let unit = profiles.first?.weight ?? .kg
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(unit)
                hero
                if !routines.isEmpty {
                    HStack {
                        Text("Routines").font(.title2.bold())
                        Spacer()
                        Button { newRoutine = true } label: { Label("New", systemImage: "plus") }.buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                    }
                    VStack(spacing: 0) {
                        ForEach(routines) { r in
                            routineRow(r)
                            if r.id != routines.last?.id { Divider().padding(.leading, 70) }
                        }
                    }
                    .modifier(CardSurface())
                }
                WeekCard()
                StrengthRetentionCard(unit: unit)
                StrengthCard(unit: unit)
                if finished.isEmpty {
                    EmptyState(icon: "dumbbell.fill", title: "No workouts yet",
                               message: "Log your first session and your history, records and volume per muscle build from here.",
                               action: ("Start a workout", { ctx.startWorkout(routine: nil) }))
                } else {
                    Text("History").font(.title3.bold()).padding(.top, 4)
                    let months = Dictionary(grouping: finished.prefix(120), by: { monthKey($0.start) }).sorted { $0.key > $1.key }
                    ForEach(months, id: \.key) { _, ws in
                        Card(title: ws[0].start.formatted(.dateTime.month(.wide).year().locale(appLocale)), systemImage: "calendar",
                             accessory: AnyView(Text("\(ws.count) workouts").font(.caption).foregroundStyle(.secondary))) {
                            ForEach(ws) { w in
                                Button { showing = w } label: { WorkoutRow(workout: w, unit: unit) }.buttonStyle(.plain)
                                if w.id != ws.last?.id { Divider() }
                            }
                        }
                    }
                }
            }
            .padding(pagePadding)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .debugScrollAnchor()
        .pageBackground()
        .navigationTitle("Training")
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(item: $editingRoutine) { RoutineEditor(routine: $0) }
        .sheet(isPresented: $newRoutine) { RoutineEditor(routine: nil) }
        .sheet(item: $showing) { WorkoutDetail(workout: $0) }
    }

    /// The big "start" card: your next routine, or an empty workout.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let r = nextRoutine {
                Text("UP NEXT").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.75))
                Text(r.name).font(.number(34)).foregroundStyle(.white)
                Text(routineSummary(r)).font(.callout).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                HStack(spacing: 10) {
                    Button { ctx.startWorkout(routine: r) } label: {
                        Label("Start \(r.name)", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    Button { ctx.startWorkout(routine: nil) } label: {
                        Text("Empty").font(.headline).padding(.horizontal, 18).padding(.vertical, 12)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("READY WHEN YOU ARE").font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.white.opacity(0.75))
                Text("Start training").font(.number(34)).foregroundStyle(.white)
                HStack(spacing: 10) {
                    Button { ctx.startWorkout(routine: nil) } label: {
                        Label("Empty workout", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    Button { newRoutine = true } label: {
                        Text("New routine").font(.headline).padding(.horizontal, 18).padding(.vertical, 12)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Macro.protein.color, Macro.protein.color.mix(with: palette.accent, by: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "dumbbell.fill").font(.system(size: 90, weight: .bold)).foregroundStyle(.white.opacity(0.1))
                .rotationEffect(.degrees(-25)).offset(x: 10, y: 6).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: GlowStyle.on || palette.glass ? Macro.protein.color.opacity(0.45) : .clear, radius: 18, y: 6)
    }

    /// TRAINING, this week's numbers, and Mon–Sun with the days you trained.
    private func header(_ unit: WeightUnit) -> some View {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let monday = dayKey(cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date())
        let week = finished.filter { $0.day >= monday }
        let trained = Set(week.map(\.day))
        let volume = week.reduce(0.0) { t, w in t + ctx.sets(of: w.key).filter(\.done).reduce(0) { $0 + $1.kg * Double($1.reps) } }
        let minutes = week.reduce(0.0) { $0 + ($1.end ?? $1.start).timeIntervalSince($1.start) / 60 }
        return VStack(alignment: .leading, spacing: 14) {
            if isPhone {
                HStack {
                    Text("TRAINING").font(.pageTitle(30)).lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(GlowStyle.on || palette.glass
                                         ? AnyShapeStyle(LinearGradient(colors: [.primary, palette.protein], startPoint: .leading, endPoint: .trailing))
                                         : AnyShapeStyle(.primary))
                    Spacer()
                    NavigationLink { ExercisesView() } label: {
                        Image(systemName: "list.bullet").font(.headline).frame(width: 44, height: 44).modifier(GlassCapsule())
                    }
                    .buttonStyle(.plain)
                    Button { newRoutine = true } label: {
                        Image(systemName: "plus").font(.headline).frame(width: 44, height: 44).modifier(GlassCapsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let d = addDays(monday, i)
                    VStack(spacing: 6) {
                        Text(date(fromKey: d).formatted(.dateTime.weekday(.narrow).locale(appLocale))).font(.caption2.weight(.semibold))
                            .foregroundStyle(d == dayKey() ? .primary : .secondary)
                        ZStack {
                            Circle().fill(trained.contains(d) ? Macro.protein.color : Color.raisedBackground)
                            if trained.contains(d) { Image(systemName: "checkmark").font(.caption.weight(.black)).foregroundStyle(.white) }
                        }
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(d == dayKey() ? Color.primary.opacity(0.8) : .clear, lineWidth: 2).padding(-3))
                        .shadow(color: trained.contains(d) && GlowStyle.on ? Macro.protein.color.opacity(0.7) : .clear, radius: 6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 0) {
                stat("\(week.count)", week.count == 1 ? "workout" : "workouts")
                stat(minutes >= 60 ? "\(Int(minutes) / 60) h \(Int(minutes) % 60)" : "\(Int(minutes)) min", "time")
                stat(volume >= 1000 ? "\(number(unit.fromKg(volume) / 1000, digits: 1)) t" : "\(number(unit.fromKg(volume))) \(unit.rawValue)", "volume")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.number(20, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// A routine as a row: initial, name, exercises and when you last did it, play.
    private func routineRow(_ r: Routine) -> some View {
        let count = routineCount(r)
        let last = finished.first { $0.routineKey == r.key || $0.name == r.name }
        let colors = [Macro.protein.color, Macro.calories.color, Macro.carbs.color, Macro.fat.color]
        let c = colors[abs(r.name.hashValue) % colors.count]
        return HStack(spacing: 14) {
            Text(String(r.name.prefix(1)).uppercased()).font(.number(18)).foregroundStyle(c)
                .frame(width: 42, height: 42).background(c.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(.headline)
                Text("\(count) exercises · \(last.map { relative($0.day) } ?? "not done yet")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { editingRoutine = r } label: { Image(systemName: "pencil").font(.callout) }.buttonStyle(.borderless)
            Button { ctx.startWorkout(routine: r) } label: {
                Image(systemName: "play.fill").font(.callout).foregroundStyle(.white).frame(width: 38, height: 38).background(palette.accent, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Start") { ctx.startWorkout(routine: r) }
            Button("Edit…") { editingRoutine = r }
        }
    }

    private func routineCard(_ r: Routine) -> some View {
        let count = routineCount(r)
        let last = finished.first { $0.routineKey == r.key || $0.name == r.name }
        return VStack(alignment: .leading, spacing: 8) {
            Text(r.name).font(.headline).lineLimit(1)
            Text("\(count) exercises").font(.caption).foregroundStyle(.secondary)
            Text(last.map { "Last \(relative($0.day))" } ?? "Not done yet").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Start") { ctx.startWorkout(routine: r) }.buttonStyle(.borderedProminent).controlSize(.small)
                Spacer()
                Button { editingRoutine = r } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardSurface(cornerRadius: Radius.l))
        .contextMenu {
            Button("Start") { ctx.startWorkout(routine: r) }
            Button("Edit…") { editingRoutine = r }
        }
    }

    private func routineCount(_ r: Routine) -> Int {
        let key = r.key
        return (try? ctx.fetchCount(FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.routineKey == key }))) ?? 0
    }

    private func monthKey(_ d: Date) -> String { String(dayKey(d).prefix(7)) }

    private func routineSummary(_ r: Routine) -> String {
        let key = r.key
        let items = (try? ctx.fetch(FetchDescriptor<RoutineExercise>(predicate: #Predicate { $0.routineKey == key }, sortBy: [SortDescriptor(\.order)]))) ?? []
        return items.compactMap { ctx.exercise($0.exerciseKey)?.name }.joined(separator: ", ")
    }
}
