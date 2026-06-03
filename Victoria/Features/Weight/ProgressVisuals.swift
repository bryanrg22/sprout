import SwiftUI
import SwiftData
import Charts

// MARK: - Metric sparkline cards (Calories · Protein · Steps · Water)

/// A compact 2×2 grid of "last 14 days" sparkline cards on the Progress tab, so the page
/// shows the whole picture — not just the scale. Each card: the metric, its recent average,
/// and a tiny trend line against its goal. Self-contained (@Query) so it drops into the page.
struct ProgressMetricsSection: View {
    let profile: UserProfile

    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \StepsEntry.date) private var steps: [StepsEntry]
    @Query private var water: [WaterEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    private let days = 14

    private var basisWeight: Double {
        TrendCalculator.currentTrend(weights) ?? (profile.startWeightLbs > 0 ? profile.startWeightLbs : 150)
    }

    var body: some View {
        let cal = caloriesSeries
        let pro = proteinSeries
        let stp = stepsSeries
        let wtr = waterSeries

        // Only show once there's at least a little to plot across these metrics.
        if (cal + pro + stp + wtr).allSatisfy({ $0 == 0 }) {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Theme.spacingM) {
                SectionHeader(title: "Last 14 days")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.spacingM),
                                    GridItem(.flexible(), spacing: Theme.spacingM)],
                          spacing: Theme.spacingM) {
                    MetricSparklineCard(title: "Calories", systemImage: "flame.fill",
                                        color: Theme.calories, series: cal,
                                        avg: nonzeroAvg(cal), unit: "kcal avg",
                                        target: profile.dailyCalorieTarget(weightLbs: basisWeight))
                    MetricSparklineCard(title: "Protein", systemImage: "fork.knife",
                                        color: Theme.protein, series: pro,
                                        avg: nonzeroAvg(pro), unit: "g avg",
                                        target: profile.macroTargets(weightLbs: basisWeight).proteinG)
                    MetricSparklineCard(title: "Steps", systemImage: "figure.walk",
                                        color: Theme.accent, series: stp,
                                        avg: nonzeroAvg(stp), unit: "avg",
                                        target: Double(profile.dailyStepGoal))
                    MetricSparklineCard(title: "Water", systemImage: "drop.fill",
                                        color: Theme.water, series: wtr,
                                        avg: nonzeroAvg(wtr), unit: "oz avg",
                                        target: profile.waterTargetOz)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Series (oldest → newest), zero-filled for missing days

    private func series(_ value: (Date) -> Double) -> [Double] {
        let calz = Calendar.current
        let today = calz.startOfDay(for: .now)
        return (0..<days).reversed().compactMap { off in
            calz.date(byAdding: .day, value: -off, to: today).map(value)
        }
    }
    private func sameDay(_ a: Date, _ b: Date) -> Bool { Calendar.current.isDate(a, inSameDayAs: b) }

    private var caloriesSeries: [Double] {
        series { d in foods.filter { sameDay($0.date, d) }.reduce(0) { $0 + $1.totalCalories } }
    }
    private var proteinSeries: [Double] {
        series { d in foods.filter { sameDay($0.date, d) }.reduce(0) { $0 + $1.totalProteinG } }
    }
    private var stepsSeries: [Double] {
        series { d in Double(steps.first { sameDay($0.date, d) }?.count ?? 0) }
    }
    private var waterSeries: [Double] {
        series { d in water.filter { sameDay($0.date, d) }.reduce(0) { $0 + $1.amountOz } }
    }

    /// Average over the days that actually have a value (so unlogged days don't drag it down).
    private func nonzeroAvg(_ s: [Double]) -> Double {
        let hits = s.filter { $0 > 0 }
        guard !hits.isEmpty else { return 0 }
        return hits.reduce(0, +) / Double(hits.count)
    }
}

/// One small metric card: label, recent average, and a tiny sparkline vs the goal line.
private struct MetricSparklineCard: View {
    let title: String
    let systemImage: String
    let color: Color
    let series: [Double]
    let avg: Double
    let unit: String
    var target: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(avg > 0 ? avg.formatted(.number.precision(.fractionLength(0))) : "—")
                    .font(.title3.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            sparkline
                .frame(height: 34)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.spacingM)
    }

    private var sparkline: some View {
        Chart {
            if let target, target > 0 {
                RuleMark(y: .value("goal", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Theme.textSecondary.opacity(0.35))
            }
            ForEach(Array(series.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("d", i), y: .value("v", v))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("d", i), y: .value("v", v))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(color)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
    }

    /// Pad the domain so a flat-ish line isn't glued to the edge; include the goal line.
    private var yDomain: ClosedRange<Double> {
        var vals = series
        if let target, target > 0 { vals.append(target) }
        let hi = max(vals.max() ?? 1, 1)
        return 0...(hi * 1.15)
    }
}

// MARK: - Consistency heatmap (GitHub-style "days you showed up")

/// A GitHub-style grid of the last ~12 weeks: each square is a day, shaded by how much was
/// logged. Visual proof of consistency — the most motivating thing on the page. Self-contained.
struct ConsistencyHeatmapCard: View {
    let profile: UserProfile

    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \StepsEntry.date) private var steps: [StepsEntry]

    private let weeks = 12
    private let cell: CGFloat = 13
    private let gap: CGFloat = 3

    var body: some View {
        // Only show once there's any history to fill it in.
        if foods.isEmpty && weights.isEmpty && steps.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Theme.spacingM) {
                SectionHeader(title: "Consistency")
                grid
                legend
                Text("Every square you fill is a day you showed up.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: Theme.spacingL)
        }
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(0..<weeks, id: \.self) { col in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        cellView(week: col, weekday: row)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func cellView(week: Int, weekday: Int) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        if let date = cal.date(byAdding: .day, value: week * 7 + weekday, to: gridStart),
           date <= today {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(fill(for: intensity(for: date)))
                .frame(width: cell, height: cell)
        } else {
            // Future days in the current week — keep the grid rectangular, render empty.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.clear)
                .frame(width: cell, height: cell)
        }
    }

    /// Sunday of the week, `weeks-1` weeks before the current week — the grid's top-left day.
    private var gridStart: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let daysSinceSunday = cal.component(.weekday, from: today) - 1   // 1=Sun
        let weekStart = cal.date(byAdding: .day, value: -daysSinceSunday, to: today) ?? today
        return cal.date(byAdding: .day, value: -7 * (weeks - 1), to: weekStart) ?? today
    }

    /// 0 = nothing, 0.45 = showed up (weight/steps), 1.0 = logged food that day.
    private func intensity(for day: Date) -> Double {
        let cal = Calendar.current
        if foods.contains(where: { cal.isDate($0.date, inSameDayAs: day) }) { return 1.0 }
        let other = weights.contains { cal.isDate($0.date, inSameDayAs: day) }
            || steps.contains { cal.isDate($0.date, inSameDayAs: day) && $0.count > 0 }
        return other ? 0.45 : 0.0
    }

    private func fill(for intensity: Double) -> Color {
        guard intensity > 0 else { return Theme.brand.opacity(0.08) }
        return Theme.brand.opacity(0.30 + intensity * 0.65)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less").font(.caption2).foregroundStyle(Theme.textSecondary)
            ForEach([0.0, 0.45, 1.0], id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill(for: i))
                    .frame(width: 10, height: 10)
            }
            Text("More").font(.caption2).foregroundStyle(Theme.textSecondary)
        }
    }
}
