import SwiftUI
#if os(iOS)
import UIKit
#endif

// The design system: every screen takes its motion, feedback, type, spacing and corners from here.
// (See DESIGN.md.) Colours come from the theme's Palette.

// MARK: - Motion

enum Motion {
    /// Taps, toggles, selection: quick and crisp.
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
    /// Things moving or changing size: cards, sheets of content, tab changes.
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.9)
    /// Small celebrations and things that should feel alive: a little overshoot.
    static let bouncy = Animation.spring(response: 0.38, dampingFraction: 0.62)

    /// With Reduce Motion on, nothing travels: changes just cross-fade quickly.
    static func pick(_ a: Animation) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : a
    }

    static var reduceMotion: Bool {
        #if os(iOS)
        UIAccessibility.isReduceMotionEnabled
        #else
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #endif
    }
}

/// `withAnimation`, through the design system (and Reduce Motion).
@discardableResult
func animate<R>(_ a: Animation = Motion.snappy, _ body: () throws -> R) rethrows -> R {
    try withAnimation(Motion.pick(a), body)
}

// MARK: - Haptics

/// The whole vocabulary. Nothing else in the app makes haptics.
enum Haptics {
    /// Pickers, steppers, the day strip, scrubbing a chart, switching tab.
    static func tick() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Adding to the cart, logging a set, a weigh-in saved.
    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// A firmer tap: long-press actions, something that moved for good.
    static func press() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    /// Finishing something: a workout, a check-in, logging the cart.
    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    /// Something went wrong (the AI failed, a scan found nothing).
    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    /// A personal record: a rising double tap no other action uses.
    static func record() {
        #if os(iOS)
        let a = UIImpactFeedbackGenerator(style: .rigid), b = UIImpactFeedbackGenerator(style: .heavy)
        a.prepare(); b.prepare()
        a.impactOccurred(intensity: 0.7)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { b.impactOccurred() }
        #endif
    }
}

// MARK: - Spacing and corners (a 4/8 pt grid)

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let s: CGFloat = 8       // chips, small fields
    static let m: CGFloat = 12      // buttons, inputs, tiles
    static let l: CGFloat = 18      // cards and rows
    static let xl: CGFloat = 24     // big cards, sheets
}

// MARK: - Type

extension Font {
    // Text roles (all scale with Dynamic Type).
    static let screenTitle = Font.largeTitle.weight(.black)
    static let sectionTitle = Font.title2.bold()
    static let cardTitle = Font.headline
    static let bodyText = Font.body
    static let secondaryText = Font.subheadline
    static let label = Font.caption.weight(.semibold)
    static let fine = Font.caption2

    // Number roles: rounded, tabular, and they scale with Dynamic Type too.
    static let numberHero = Font.system(.largeTitle, design: .rounded).weight(.bold)      // calories left, the weigh-in
    static let numberLarge = Font.system(.title, design: .rounded).weight(.bold)          // card values
    static let numberMedium = Font.system(.title3, design: .rounded).weight(.semibold)    // tiles, set fields
    static let numberSmall = Font.system(.subheadline, design: .rounded).weight(.semibold)
}

extension View {
    /// A number that changes: tabular digits, and it rolls to the new value.
    func liveNumber(_ value: Double) -> some View {
        monospacedDigit().contentTransition(.numericText(value: value)).animation(Motion.pick(Motion.snappy), value: value)
    }

    /// A unit after a value: same size, lighter.
    func unitStyle() -> some View { foregroundStyle(.secondary).fontWeight(.medium) }

    /// A button that sinks a little when pressed.
    func pressable() -> some View { buttonStyle(PressableStyle()) }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Motion.reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Undo instead of "Are you sure?"

/// "Removed · Undo" for a few seconds at the bottom of the screen.
@MainActor final class UndoCenter: ObservableObject {
    static let shared = UndoCenter()
    struct Item: Identifiable { let id = UUID(); let message: String; let undo: () -> Void }
    @Published private(set) var item: Item?
    private var timer: Task<Void, Never>?

    func offer(_ message: String, undo: @escaping () -> Void) {
        timer?.cancel()
        animate(Motion.smooth) { item = Item(message: message, undo: undo) }
        Haptics.tap()
        let id = item?.id
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, self?.item?.id == id else { return }
            animate(Motion.smooth) { self?.item = nil }
        }
    }

    func perform() {
        guard let i = item else { return }
        i.undo()
        Haptics.tick()
        animate(Motion.smooth) { item = nil }
    }

    func dismiss() { animate(Motion.smooth) { item = nil } }
}

struct UndoToast: View {
    @ObservedObject private var center = UndoCenter.shared

    var body: some View {
        if let i = center.item {
            HStack(spacing: Space.m) {
                Text(i.message).font(.secondaryText.weight(.medium)).lineLimit(2)
                Spacer(minLength: Space.s)
                Button("Undo") { center.perform() }.font(.secondaryText.weight(.bold)).foregroundStyle(palette.accent)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
            .padding(.horizontal, Space.l)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .gesture(DragGesture().onEnded { if $0.translation.height > 20 { center.dismiss() } })
            .id(i.id)
        }
    }
}

extension View {
    /// The undo toast, floating above this screen's bottom bars.
    func undoToast(bottom: CGFloat = Space.s) -> some View {
        overlay(alignment: .bottom) { UndoToast().padding(.bottom, bottom) }
    }
}

// MARK: - Problems: what happened, and what you can do

struct ProblemCard: View {
    let title: String
    let message: String
    var icon = "exclamationmark.triangle.fill"
    var actions: [(label: String, run: () -> Void)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label(title, systemImage: icon).font(.cardTitle).foregroundStyle(palette.warn)
            Text(message).font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !actions.isEmpty {
                HStack(spacing: Space.s) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { i, a in
                        Button(a.label, action: a.run)
                            .font(.secondaryText.weight(.semibold))
                            .padding(.horizontal, Space.m).frame(height: 36)
                            .background(i == 0 ? palette.accent : Color.raisedBackground, in: Capsule())
                            .foregroundStyle(i == 0 ? Color.white : .primary)
                            .pressable()
                    }
                }
                .padding(.top, Space.xs)
            }
        }
        .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.warn.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
        .onAppear { Haptics.warning() }
    }
}

/// Waiting on the network: a calm, alive line instead of a bare spinner.
struct WorkingCard: View {
    let title: String
    var detail: String? = nil
    @State private var on = false

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "sparkles").font(.title2).foregroundStyle(palette.accent)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !Motion.reduceMotion)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.secondaryText.weight(.semibold))
                if let detail { Text(detail).font(.fine).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(Space.l)
        .background(Color.raisedBackground, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .overlay {
            // A soft sheen sweeping across while it works.
            GeometryReader { g in
                LinearGradient(colors: [.clear, palette.accent.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width * 0.4)
                    .offset(x: on ? g.size.width : -g.size.width * 0.4)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .allowsHitTesting(false)
            .opacity(Motion.reduceMotion ? 0 : 1)
        }
        .onAppear { withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { on = true } }
        .transition(.opacity)
    }
}

// MARK: - Empty lists: say what goes here, offer the one thing to do

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: (label: String, run: () -> Void)? = nil

    var body: some View {
        VStack(spacing: Space.m) {
            Image(systemName: icon).font(.title2.weight(.semibold)).foregroundStyle(palette.accent)
                .frame(width: 60, height: 60).background(palette.accent.opacity(0.12), in: Circle())
            Text(title).font(.cardTitle)
            Text(message).font(.secondaryText).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: action.run) {
                    Text(action.label).font(.secondaryText.weight(.semibold)).padding(.horizontal, Space.xl).frame(height: 44)
                        .background(palette.accent, in: Capsule()).foregroundStyle(.white)
                }
                .pressable().padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, Space.xxl).padding(.horizontal, Space.l)
    }
}

// MARK: - Meaning colours (the same everywhere they appear)

extension Color {
    static let weightTone = Color(hex: 0xA77BF3)        // weight, trend, AI photo
    static let expenditureTone = Color(hex: 0xFF8A5B)
    static let waterTone = Color(hex: 0x3BB2F6)         // water, activity, insights
    static let calmTone = Color(hex: 0x7B8CF3)          // describe, sleep
    static let extraTone = Color(hex: 0xA78BFA)         // other nutrients, supersets
    static let alertTone = Color(hex: 0xFF6F91)         // sugar, sodium
    static let linkTone = Color(hex: 0xFF5C86)
    static let neutralTone = Color(hex: 0x8E8E93)
}

// MARK: - Arriving: a screen's sections come in one after another

private struct Arrive: ViewModifier {
    let order: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || Motion.reduceMotion ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                withAnimation(Motion.pick(Motion.smooth).delay(Motion.reduceMotion ? 0 : Double(order) * 0.06)) { shown = true }
            }
    }
}

extension View {
    /// Fades and rises in, `order` steps after the first (60 ms apart).
    func arrive(_ order: Int) -> some View { modifier(Arrive(order: order)) }
}

// MARK: - A page of choices (MacroFactor's "Program Style" page): pushed, not a pop-up menu

struct OptionsPage<ID: Hashable>: View {
    struct Option: Identifiable { let id: ID; let title: String; var detail: String? = nil }
    let title: String
    var header: String? = nil
    var footer: String? = nil
    let options: [Option]
    let selected: ID?
    let choose: (ID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                if let header { Text(header).font(.secondaryText).foregroundStyle(.secondary).padding(.horizontal, Space.xs) }
                VStack(spacing: 0) {
                    ForEach(options) { o in
                        Button {
                            Haptics.tick()
                            choose(o.id)
                            dismiss()
                        } label: {
                            HStack(alignment: .center, spacing: Space.m) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(o.title).font(.bodyText)
                                    if let d = o.detail { Text(d).font(.secondaryText).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                                }
                                Spacer(minLength: Space.s)
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(palette.accent)
                                    .opacity(o.id == selected ? 1 : 0)
                            }
                            .padding(.horizontal, Space.l).padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if o.id != options.last?.id { Divider().padding(.leading, Space.l) }
                    }
                }
                .modifier(CardSurface(cornerRadius: Radius.l))
                if let footer { Text(footer).font(.fine).foregroundStyle(.secondary).padding(.horizontal, Space.xs) }
            }
            .padding(Space.l)
        }
        .pageBackground()
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Behind the status bar: content never scrolls under the clock bare

struct StatusBarBackdrop: View {
    var body: some View {
        GeometryReader { g in
            Group {
                if palette.glass { Rectangle().fill(.ultraThinMaterial) } else { Rectangle().fill(Color.pageBackground) }
            }
            .frame(height: g.safeAreaInsets.top)
            .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
    }
}
