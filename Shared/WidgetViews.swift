import SwiftUI
import WidgetKit

/// Pure SwiftUI widget content, fed by a `WidgetSnapshot`. Lives in BOTH the app
/// (so the in-app gallery can preview/verify it) and the widget extension (which
/// wraps it in WidgetKit). No SwiftData, no app-only types — only `Theme` + the
/// snapshot, so it compiles cleanly in the extension.

// MARK: - Calories

struct CalorieBudgetView: View {
    var snap: WidgetSnapshot
    var family: WidgetFamily

    var body: some View {
        // Adopt the user's skin before any Theme color resolves. The widget extension
        // never runs RootView, so `Theme.current` would otherwise stay at its `.cool`
        // default and a Cute (Victoria) user would get dark widgets.
        let _ = (Theme.current = snap.skin)
        switch family {
        case .systemSmall:        small
        case .systemMedium:       medium
        case .accessoryCircular:  circular
        case .accessoryRectangular: rectangular
        case .accessoryInline:    inline
        default:                  small
        }
    }

    private var remaining: Int { Int(max(snap.caloriesRemaining, 0).rounded()) }
    private var over: Bool { snap.caloriesRemaining < 0 }

    // systemSmall — the ring + big number
    private var small: some View {
        VStack(spacing: 10) {
            ZStack {
                WRing(progress: snap.calorieProgress, lineWidth: 11, color: over ? Theme.warning : Theme.brand)
                VStack(spacing: 0) {
                    Text("\(remaining)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    Text(over ? "OVER" : "LEFT")
                        .font(.system(size: 10, weight: .bold)).tracking(0.5)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(Theme.brand)
                Text("\(Int(snap.caloriesEaten.rounded())) / \(Int(snap.calorieTarget.rounded())) kcal")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .minimumScaleFactor(0.8).lineLimit(1)
            }
        }
    }

    // systemMedium — ring + macros + activity
    private var medium: some View {
        HStack(spacing: 12) {
            VStack(spacing: 8) {
                ZStack {
                    WRing(progress: snap.calorieProgress, lineWidth: 11, color: over ? Theme.warning : Theme.brand)
                    VStack(spacing: 0) {
                        Text("\(remaining)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                            .foregroundStyle(Theme.textPrimary)
                        Text(over ? "OVER" : "LEFT")
                            .font(.system(size: 10, weight: .bold)).tracking(0.5)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 92, height: 92)
                if snap.streak > 0 {
                    Label("\(snap.streak)", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Theme.warning)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                WMacroBar(label: "Protein", value: snap.protein, target: snap.proteinTarget, color: Theme.protein)
                WMacroBar(label: "Carbs", value: snap.carbs, target: snap.carbsTarget, color: Theme.carbs)
                WMacroBar(label: "Fat", value: snap.fat, target: snap.fatTarget, color: Theme.fat)
                HStack(spacing: 12) {
                    miniStat("figure.walk", "\(snap.steps)", Theme.info)
                    miniStat("drop.fill", "\(Int(snap.waterOz)) oz", Theme.water)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var greeting: String { "\(snap.name)'s day" }

    private func miniStat(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(color)
            Text(value).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // Lock screen — circular gauge
    private var circular: some View {
        Gauge(value: snap.calorieProgress) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(remaining)").font(.system(size: 15, weight: .bold)).minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(over ? Theme.warning : Theme.brand)
    }

    // Lock screen — rectangular
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(over ? "\(-Int(snap.caloriesRemaining.rounded())) over" : "\(remaining) kcal left")
                    .font(.headline).fontWeight(.bold)
            } icon: {
                Image(systemName: "flame.fill")
            }
            Text("P \(Int(snap.protein))g · C \(Int(snap.carbs))g · F \(Int(snap.fat))g")
                .font(.caption2).foregroundStyle(.secondary)
            if snap.streak > 0 {
                Text("\(snap.streak)-day streak").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .widgetAccentable()
    }

    // Lock screen — inline (next to the clock)
    private var inline: some View {
        Label("\(remaining) kcal left", systemImage: "flame.fill")
    }
}

// MARK: - Weight trend

struct WeightTrendView: View {
    var snap: WidgetSnapshot
    var family: WidgetFamily

    var body: some View {
        // Adopt the user's skin before any Theme color resolves (see CalorieBudgetView).
        let _ = (Theme.current = snap.skin)
        switch family {
        case .systemSmall:          small
        case .accessoryRectangular: rectangular
        default:                    small
        }
    }

    private var trendText: String {
        guard let t = snap.trendWeight else { return "—" }
        return String(format: "%.1f", t)
    }
    private var rateText: String {
        String(format: "%@%.1f lb/wk", snap.isLosing ? "↓ " : "↑ ", abs(snap.ratePerWeek))
    }
    private var rateColor: Color { snap.isLosing ? Theme.positive : Theme.warning }

    private var small: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TREND").font(.system(size: 10, weight: .bold)).tracking(1)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(trendText)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                Text("lb").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }
            Spark(points: snap.trendSpark, color: Theme.positive)
                .frame(height: 36)
                .padding(.vertical, 2)
            HStack(spacing: 4) {
                Text(rateText).font(.system(size: 12, weight: .bold)).foregroundStyle(rateColor)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let r = snap.poundsToGoal, r > 0 {
                    Text("· \(Int(r)) to go").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label { Text("\(trendText) lb").font(.headline).fontWeight(.bold) }
                  icon: { Image(systemName: "chart.line.downtrend.xyaxis") }
            Text(rateText).font(.caption2).foregroundStyle(.secondary)
            if let r = snap.poundsToGoal, r > 0 {
                Text("\(Int(r)) lb to goal").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .widgetAccentable()
    }
}

// MARK: - Companion

/// "Companion" — the cute pixel buddy + a key metric, so opening the app feels
/// like checking in on someone. Small = companion + calories-to-go (with a tiny
/// step ring); medium = companion + a few glanceable metrics and the streak.
///
/// Calories *to go* is the hero number on purpose: the user tends to UNDER-eat,
/// so "385 to go" nudges toward fueling up rather than restricting. When she's at
/// or over target it flips to a warm "Fueled" — never a penalty.
struct CompanionView: View {
    var snap: WidgetSnapshot
    var family: WidgetFamily

    var body: some View {
        // Adopt the user's skin before any Theme color resolves (see CalorieBudgetView).
        let _ = (Theme.current = snap.skin)
        switch family {
        case .systemSmall:  small
        case .systemMedium: medium
        default:            small
        }
    }

    // To-go calories, floored at 0; `fueled` once she's met/exceeded the target.
    private var toGo: Int { Int(max(snap.caloriesRemaining, 0).rounded()) }
    private var fueled: Bool { snap.caloriesRemaining <= 0 }

    /// The right frozen pixel buddy for this profile (Bryan vs Victoria).
    @ViewBuilder private var companion: some View {
        if snap.usesBryanAvatar { WidgetPixelBryanView() }
        else                    { WidgetPixelVictoriaView() }
    }

    // systemSmall — companion in its step ring on the left, calories-to-go on the right.
    private var small: some View {
        HStack(spacing: 10) {
            ZStack {
                WRing(progress: snap.stepProgress, lineWidth: 6, color: Theme.info)
                companion
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if fueled {
                Label("Fueled", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.positive)
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                VStack(spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.brand)
                        Text("\(toGo)")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text("cal to go")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    // systemMedium — companion on the left, a stack of glanceable metrics right.
    private var medium: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                companion
                    .frame(maxHeight: .infinity)
                Text(snap.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 92)

            VStack(alignment: .leading, spacing: 9) {
                // Macro progress bars — the rich "fills up as you go" right side: each macro
                // shows value/target and a bar that fills toward the goal. Steps + water sit
                // beneath as compact glance stats.
                WMacroBar(label: "Protein", value: snap.protein, target: snap.proteinTarget, color: Theme.protein)
                WMacroBar(label: "Carbs", value: snap.carbs, target: snap.carbsTarget, color: Theme.carbs)
                WMacroBar(label: "Fat", value: snap.fat, target: snap.fatTarget, color: Theme.fat)
                // Four glance stats: calories first (the headline number), then steps, water,
                // and the day-streak flame. Tighter spacing + per-stat auto-shrink so all four
                // fit the narrow column without truncating.
                HStack(spacing: 8) {
                    wMiniStat("fork.knife", "\(Int(snap.caloriesEaten.rounded()))", Theme.calories)
                    wMiniStat("figure.walk", "\(snap.steps)", Theme.info)
                    wMiniStat("drop.fill", "\(Int(snap.waterOz.rounded())) oz", Theme.water)
                    if snap.streak > 0 {
                        wMiniStat("flame.fill", "\(snap.streak)", Theme.warning)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A compact glance stat (icon + value) for the row beneath the macro bars.
    private func wMiniStat(_ icon: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)        // shrink to fit four stats in the narrow column
    }
}

// MARK: - Reusable bits

/// A progress ring with a soft track and rounded cap.
struct WRing: View {
    var progress: Double
    var lineWidth: CGFloat
    var color: Color
    var body: some View {
        ZStack {
            Circle().stroke(Theme.textSecondary.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// A compact labeled macro progress bar.
struct WMacroBar: View {
    var label: String
    var value: Double
    var target: Double
    var color: Color
    private var progress: Double { target > 0 ? min(value / target, 1) : 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(label)
                Spacer()
                Text("\(Int(value))/\(Int(target))g").foregroundStyle(Theme.textSecondary).monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textPrimary.opacity(0.9))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.textSecondary.opacity(0.22))
                    Capsule().fill(color).frame(width: g.size.width * progress)
                }
            }
            .frame(height: 6)
        }
    }
}

/// A lightweight sparkline drawn with a Path (no Charts dependency).
struct Spark: View {
    var points: [Double]
    var color: Color
    var body: some View {
        GeometryReader { geo in
            if points.count > 1, let lo = points.min(), let hi = points.max() {
                let range = max(hi - lo, 0.0001)
                let step = geo.size.width / CGFloat(points.count - 1)
                ZStack {
                    // soft fill under the line
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: geo.size.height))
                        for (i, v) in points.enumerated() {
                            let x = step * CGFloat(i)
                            let y = geo.size.height * (1 - CGFloat((v - lo) / range))
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.25), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    // the line
                    Path { p in
                        for (i, v) in points.enumerated() {
                            let x = step * CGFloat(i)
                            let y = geo.size.height * (1 - CGFloat((v - lo) / range))
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                            else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
