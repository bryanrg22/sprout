import SwiftUI
import SwiftData
import Charts

struct WeightView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var range: ChartRange = .threeMonths
    @State private var showingLog = false

    // MARK: - Derived data

    /// Entries inside the currently selected time range (ascending by date).
    private var rangedWeights: [WeightEntry] {
        guard let cutoff = range.cutoffDate else { return weights }
        return weights.filter { $0.date >= cutoff }
    }

    /// Smoothed trend points for the selected range.
    /// Computed over full history so the EWMA has context, then clipped to range.
    private var trendPoints: [TrendCalculator.TrendPoint] {
        let full = TrendCalculator.trend(weights)
        guard let cutoff = range.cutoffDate else { return full }
        return full.filter { $0.date >= cutoff }
    }

    /// Latest smoothed trend value across all data (the emotional truth).
    private var currentTrend: Double? {
        TrendCalculator.currentTrend(weights)
    }

    /// Weekly rate from the trend (negative = losing).
    private var ratePerWeek: Double {
        TrendCalculator.ratePerWeek(weights)
    }

    /// Pounds still to go from the current trend to goal, in the goal's direction
    /// (lose → above goal; gain → below goal). `nil` for maintain (no gap to close);
    /// 0 once reached.
    private var remaining: Double? {
        guard let t = currentTrend else { return nil }
        switch profile.pace.direction {
        case .lose:     return max(0, t - profile.goalWeightLbs)
        case .gain:     return max(0, profile.goalWeightLbs - t)
        case .maintain: return nil
        }
    }

    /// The most recent raw weigh-in.
    private var latestRaw: WeightEntry? {
        weights.max(by: { $0.date < $1.date })
    }

    /// Weight unit label from the profile ("lb"/"kg"). Values are stored in lb; this
    /// matches the rest of the app, which labels the lb value with the chosen unit
    /// (see DashboardView). True kg *conversion* is an app-wide gap, flagged separately.
    private var unitLabel: String { profile.unitSystem.weightUnit }

    /// True when the latest raw reading sits noticeably OFF the trend in the direction
    /// that tends to discourage THIS user — so we only pop the reassurance when it helps:
    ///   • lose  → an up-day (raw above trend) reads as "I gained"
    ///   • gain  → a down-day (raw below trend) reads as "I'm slipping"
    ///   • maintain → either side, any real wiggle
    /// Returns false with no trend yet (single weigh-in) so we don't reassure prematurely.
    private var rawIsDiscouragingBlip: Bool {
        guard let raw = latestRaw?.weightLbs, let trend = currentTrend else { return false }
        let delta = raw - trend                       // + = above trend, − = below
        switch profile.pace.direction {
        case .lose:     return delta > 0.2
        case .gain:     return delta < -0.2
        case .maintain: return abs(delta) > 0.2
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                if weights.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: Theme.spacingL) {
                        hero
                        // AI recap of the WHOLE picture — weight, nutrition, activity,
                        // consistency — so Progress isn't just the scale. Self-manages its
                        // loading / not-enough-data / no-key states (hides without a key).
                        ProgressSummaryCard(profile: profile)
                        // Metrics at a glance — calories/protein/steps/water sparklines.
                        ProgressMetricsSection(profile: profile)
                        if rawIsDiscouragingBlip { reframeCard }
                        chartCard
                        // GitHub-style "days you showed up" consistency heatmap.
                        ConsistencyHeatmapCard(profile: profile)
                        if let eta = TrendCalculator.projectedGoalDate(weights, goalLbs: profile.goalWeightLbs) {
                            etaCard(date: eta)
                        }
                    }
                    .padding(.horizontal, Theme.spacingM)
                    .padding(.vertical, Theme.spacingL)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Progress")
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) { logBar }
            .sheet(isPresented: $showingLog) {
                LogWeighInSheet(
                    startingValue: (currentTrend ?? latestRaw?.weightLbs ?? profile.startWeightLbs),
                    unitLabel: unitLabel,
                    onSave: save(weight:)
                )
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            Text("Current trend")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: Theme.spacingXS) {
                if let t = currentTrend {
                    Text(t, format: .number.precision(.fractionLength(1)))
                        .font(Theme.number(60))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Text("—")
                        .font(Theme.number(60))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(unitLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: currentTrend)

            // Rate + goal-gap. Side-by-side normally; stacks at large Dynamic Type so
            // neither pill truncates.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.spacingM) { rateBadge; goalGap }
                VStack(alignment: .leading, spacing: Theme.spacingS) { rateBadge; goalGap }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.spacingL)
    }

    private var rateBadge: some View {
        // Arrow shows the ACTUAL direction of the trend; color shows whether that
        // movement is on track for THIS user's goal (green) or worth a gentle nudge
        // (amber). So a rising trend is "good" for a gain goal, not a warning.
        let goingDown = ratePerWeek <= 0
        let onTrack: Bool
        switch profile.pace.direction {
        case .lose:     onTrack = ratePerWeek <= 0.05
        case .gain:     onTrack = ratePerWeek >= -0.05
        case .maintain: onTrack = abs(ratePerWeek) <= 0.25
        }
        let color = onTrack ? Theme.positive : Theme.warning
        return HStack(spacing: Theme.spacingXS) {
            Image(systemName: goingDown ? "arrow.down.right" : "arrow.up.right")
                .font(.caption.weight(.bold))
            Text("\(abs(ratePerWeek), format: .number.precision(.fractionLength(1))) \(unitLabel)/wk")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingXS)
        .background(color.opacity(0.14), in: Capsule())
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: ratePerWeek)
    }

    /// "X lb to goal" while there's a gap, a celebratory chip once reached. `remaining`
    /// is already direction-correct (lose: trend−goal, gain: goal−trend), so this reads
    /// right for both users. Empty for maintain (no gap to close).
    @ViewBuilder private var goalGap: some View {
        if let remaining, remaining > 0 {
            Label {
                Text("\(remaining, format: .number.precision(.fractionLength(1))) \(unitLabel) to goal")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "flag.checkered")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
        } else if remaining != nil {
            Label("Goal reached", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.positive)
        }
    }

    // MARK: - Reframe

    private var reframeCard: some View {
        HStack(alignment: .top, spacing: Theme.spacingM) {
            Image(systemName: "drop.fill")
                .font(.title3)
                .foregroundStyle(Theme.water)
            Text(reframeText)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.spacingL)
    }

    /// Daily-noise reassurance for a single weigh-in that landed on the discouraging
    /// side of the trend. Framed by goal direction, and careful NOT to over-promise the
    /// trend's direction (we don't claim "still going down" — the trend may be flat that
    /// day); it just reframes one reading as noise. Never shames either user.
    private var reframeText: String {
        switch profile.pace.direction {
        case .lose:     return "Up a touch today — that's water and food weight, not fat. One reading isn't your trend 💚"
        case .gain:     return "Down a touch today — that's just water and food swing, not lost progress. Watch the trend, not one reading 💚"
        case .maintain: return "A little wiggle today is normal — the trend line is what matters, not one reading 💚"
        }
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacingM) {
            HStack {
                SectionHeader(title: "Trend")
                Spacer()
            }

            Picker("Range", selection: $range) {
                ForEach(ChartRange.allCases) { r in
                    Text(r.label).tag(r)
                }
            }
            .pickerStyle(.segmented)

            if rangedWeights.isEmpty {
                emptyChartState
            } else {
                trendChart
                    .frame(height: 230)
                    .animation(.easeInOut(duration: 0.3), value: range)
                legend
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.spacingL)
    }

    private var trendChart: some View {
        Chart {
            // Faint raw weigh-ins — present but never competing with the trend.
            ForEach(rangedWeights) { entry in
                PointMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", entry.weightLbs)
                )
                .foregroundStyle(Theme.textSecondary.opacity(0.35))
                .symbolSize(20)
            }

            // Soft gradient fade beneath the trend.
            ForEach(trendPoints) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Floor", chartYDomain.lowerBound),
                    yEnd: .value("Trend", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.positive.opacity(0.28), Theme.positive.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }

            // The bold smoothed trend line — the star.
            ForEach(trendPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Trend", point.value)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Theme.positive)
            }

            // Dashed goal line.
            RuleMark(y: .value("Goal", profile.goalWeightLbs))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(Theme.accent.opacity(0.85))
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    Text("Goal \(Int(profile.goalWeightLbs.rounded())) \(unitLabel)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
        }
        .chartYScale(domain: chartYDomain)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.divider)
                AxisValueLabel {
                    if let n = value.as(Double.self) {
                        Text("\(Int(n))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.divider)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: Theme.spacingL) {
            HStack(spacing: 6) {
                Capsule().fill(Theme.positive).frame(width: 18, height: 3)
                Text("Trend").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                Circle().fill(Theme.textSecondary.opacity(0.35)).frame(width: 7, height: 7)
                Text("Daily").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                Capsule().fill(Theme.accent).frame(width: 18, height: 2)
                Text("Goal").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Y-domain padded to include both the data and the goal line, with breathing room.
    private var chartYDomain: ClosedRange<Double> {
        var values = rangedWeights.map(\.weightLbs)
        values.append(contentsOf: trendPoints.map(\.value))
        values.append(profile.goalWeightLbs)
        guard let lo = values.min(), let hi = values.max(), lo < hi else {
            let base = profile.goalWeightLbs > 0 ? profile.goalWeightLbs : 150
            return (base - 5)...(base + 5)
        }
        let pad = max(1.5, (hi - lo) * 0.12)
        return (lo - pad)...(hi + pad)
    }

    private var emptyChartState: some View {
        VStack(spacing: Theme.spacingS) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40))
                .foregroundStyle(Theme.brand.opacity(0.55))
            Text("No weigh-ins in this range yet — try a longer range or log today.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.spacingXL)
    }

    // MARK: - ETA

    private func etaCard(date: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack(spacing: Theme.spacingS) {
                Image(systemName: "calendar")
                    .foregroundStyle(Theme.accent)
                Text("On track for")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(date, format: .dateTime.month(.wide).day().year())
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Theme.textPrimary)
            Text("A rough estimate — plateaus are normal.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.spacingL)
        .animation(.easeInOut(duration: 0.3), value: date)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Theme.spacingL) {
            Image(systemName: emptyStateSymbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.brand)
            Text("No weigh-ins yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.spacingXL)
        .padding(.horizontal, Theme.spacingL)
    }

    /// Icon hints at the goal direction (down for lose, up for gain) without ever
    /// implying one is "good"; maintain gets a neutral line.
    private var emptyStateSymbol: String {
        switch profile.pace.direction {
        case .lose:     return "chart.line.downtrend.xyaxis"
        case .gain:     return "chart.line.uptrend.xyaxis"
        case .maintain: return "chart.line.flattrend.xyaxis"
        }
    }

    /// First-run nudge, framed for the goal direction — trend-first, never about a number.
    private var emptyStateMessage: String {
        switch profile.pace.direction {
        case .lose, .gain:
            return "Log your first weigh-in to start your trend line. One number is just one day — the trend is what we watch."
        case .maintain:
            return "Log your first weigh-in to start your trend line. We'll watch the trend, so a daily wiggle never has to worry you."
        }
    }

    // MARK: - Log bar

    private var logBar: some View {
        Button {
            showingLog = true
        } label: {
            Label("Log weigh-in", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.primary)
        .padding(.horizontal, Theme.spacingM)
        .padding(.vertical, Theme.spacingM)
        .background(.ultraThinMaterial)
    }

    // MARK: - Persistence

    private func save(weight: Double) {
        let entry = WeightEntry(weightLbs: weight)
        context.insert(entry)
        try? context.save()
    }
}

// MARK: - Chart range

private enum ChartRange: String, CaseIterable, Identifiable {
    case oneMonth, threeMonths, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneMonth: return "1M"
        case .threeMonths: return "3M"
        case .all: return "All"
        }
    }

    /// Inclusive lower bound for filtering; nil means "all time".
    var cutoffDate: Date? {
        switch self {
        case .oneMonth: return Calendar.current.date(byAdding: .month, value: -1, to: .now)
        case .threeMonths: return Calendar.current.date(byAdding: .month, value: -3, to: .now)
        case .all: return nil
        }
    }
}

// MARK: - Log weigh-in sheet

private struct LogWeighInSheet: View {
    let startingValue: Double
    let unitLabel: String
    let onSave: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weight: Double
    @State private var didSave = false

    private let bounds: ClosedRange<Double> = 50...500
    private let step: Double = 0.2

    init(startingValue: Double, unitLabel: String, onSave: @escaping (Double) -> Void) {
        self.startingValue = startingValue
        self.unitLabel = unitLabel
        self.onSave = onSave
        let clamped = min(500, max(50, startingValue))
        _weight = State(initialValue: (clamped * 5).rounded() / 5) // snap to 0.2 lb
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacingXL) {
                Spacer(minLength: Theme.spacingL)

                VStack(spacing: Theme.spacingS) {
                    Text("Today's weigh-in")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: Theme.spacingXS) {
                        Text(weight, format: .number.precision(.fractionLength(1)))
                            .font(Theme.number(64))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Theme.textPrimary)
                        Text(unitLabel)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: weight)
                }

                Text("One number is just one day — we care about the trend.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacingL)

                HStack(spacing: Theme.spacingL) {
                    stepperButton(symbol: "minus") { adjust(-step) }
                    Slider(value: $weight, in: bounds, step: step)
                        .tint(Theme.accent)
                    stepperButton(symbol: "plus") { adjust(step) }
                }
                .padding(.horizontal, Theme.spacingS)

                Spacer()

                Button {
                    onSave(weight)
                    didSave = true
                    dismiss()
                } label: {
                    Text("Save weigh-in")
                }
                .buttonStyle(.primary)
            }
            .padding(.horizontal, Theme.spacingM)
            .padding(.vertical, Theme.spacingL)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Log weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .sensoryFeedback(.success, trigger: didSave)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func adjust(_ delta: Double) {
        weight = min(bounds.upperBound, max(bounds.lowerBound, ((weight + delta) * 5).rounded() / 5))
    }

    private func stepperButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.brandSoft))
        }
        .buttonStyle(.plain)
    }
}
