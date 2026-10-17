import SwiftUI

// Debug: every token in all 20 Appearance × Finish combinations, side by side.
// In the app: More → Diagnostics → Theme tokens (debug builds). Rendered to a PNG by Tests/tokens.

struct TokenGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Gym theme tokens · Appearance × Finish").font(.system(size: 26, weight: .semibold))
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    Text("")
                    ForEach(Appearance.allCases) { a in
                        Text(a == .automatic ? "Automatic (shown: system dark)" : a.label).font(.system(size: 15, weight: .semibold)).frame(width: 300)
                    }
                }
                ForEach(Finish.allCases) { f in
                    GridRow {
                        Text(f.label).font(.system(size: 15, weight: .semibold)).frame(width: 80, alignment: .leading)
                        ForEach(Appearance.allCases) { a in TokenCell(t: Tokens.make(a, f), automatic: a == .automatic) }
                    }
                }
            }
        }
        .padding(Space.xl)
        .background(Color(white: 0.5))
    }
}

struct TokenCell: View {
    let t: Tokens
    var automatic = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            // The neutral ramp, back to front.
            HStack(spacing: Space.xs) {
                ForEach(Array([t.background, t.grouped, t.card, t.raised, t.separator, t.text3, t.text2, t.text1].enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: Radius.xs).fill(c.color).frame(height: 14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.xs).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                }
            }
            // A slice of Today on a card.
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .center, spacing: Space.l) {
                    ZStack {
                        Circle().stroke(t.raised.color, lineWidth: 9)
                        Circle().trim(from: 0, to: 0.68)
                            .stroke(AngularGradient(colors: [t.accentLow.color, t.accent.color, t.accentHigh.color, t.accent.color], center: .center),
                                    style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("1 557").font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(t.text1.color)
                            Text("kcal left").font(.system(size: 9, weight: .medium)).foregroundStyle(t.text2.color)
                        }
                    }
                    .frame(width: 92, height: 92)
                    VStack(alignment: .leading, spacing: Space.s) {
                        bar("Protein", "142 / 188 g", t.protein, 0.75)
                        bar("Fat", "48 / 79 g", t.fat, 0.6)
                        bar("Carbs", "201 / 193 g", t.carbs, 1.0)
                        bar("Calories", "674 / 2231", t.calories, 0.3)
                    }
                }
                Rectangle().fill(t.separator.color).frame(height: 0.5)
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text("110,8").font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(t.text1.color)
                    Text("kg").font(.system(size: 12, weight: .medium)).foregroundStyle(t.text2.color)
                    Spacer()
                    Text("TREND").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(t.text3.color)
                }
                HStack(spacing: Space.s) {
                    Text("Log Foods").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.onAccent.color)
                        .padding(.horizontal, Space.m).frame(height: 28).background(t.metal, in: Capsule())
                    Text("Chip").font(.system(size: 11, weight: .medium)).foregroundStyle(t.text1.color)
                        .padding(.horizontal, Space.m).frame(height: 24).background(t.raised.color, in: Capsule())
                    Spacer()
                    Text("Link").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.accent.color)
                }
                HStack(spacing: Space.s) {
                    ForEach([("on target", t.good), ("over", t.over), ("under", t.under), ("PR", t.record), ("warn", t.warning)], id: \.0) { n, c in
                        HStack(spacing: Space.xs) { Circle().fill(c.color).frame(width: 7, height: 7); Text(n).font(.system(size: 9)).foregroundStyle(t.text2.color) }
                    }
                }
            }
            .padding(Space.m)
            .background(t.card.color, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .overlay(alignment: .top) {
                // The hairline at the top edge.
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous).stroke(t.hairline, lineWidth: 0.5)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
            }
            // The finish swatch, as in the picker.
            HStack(spacing: Space.s) {
                Circle().fill(t.metal).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(t.accent.color, lineWidth: 1.5).padding(-3))
                Text(worstContrast).font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundStyle(t.text2.color)
            }
        }
        .padding(Space.m)
        .frame(width: 300, alignment: .leading)
        .background(t.background.color, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
    }

    private var worstContrast: String {
        let w = t.contrastPairs.filter { $0.minimum == 4.5 }.min { $0.ratio < $1.ratio }!
        return "lowest text contrast \(String(format: "%.1f", w.ratio)):1 (\(w.name))"
    }

    private func bar(_ label: String, _ value: String, _ c: RGB, _ frac: Double) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack {
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(t.text2.color)
                Spacer()
                Text(value).font(.system(size: 9, weight: .semibold)).monospacedDigit().foregroundStyle(t.text1.color)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.raised.color)
                    Capsule().fill(c.color).frame(width: g.size.width * min(frac, 1))
                }
            }
            .frame(height: 4)
        }
        .frame(width: 160)
    }
}
