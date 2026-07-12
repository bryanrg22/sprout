import SwiftUI
import SwiftData
import Charts

/// The tracker quick-card on Today — the "little Fitbit tile": last night's sleep and
/// today's recovery vitals at a glance, tapping through to a detail screen with the
/// 14-night stage history and vitals trends. Mirrors the buddy quick-card pattern.
///
/// Self-hides until tracker data actually exists in Apple Health (no empty tile nagging
/// someone without a wearable).
struct TrackerCard: View {
    @Query(sort: \SleepEntry.date) private var sleep: [SleepEntry]
    @Query(sort: \VitalsEntry.date) private var vitals: [VitalsEntry]

    var body: some View {
        if hasData {
            NavigationLink {
                TrackerDetailView()
            } label: {
                HStack(spacing: Theme.Space.md) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.info)
                        .frame(width: 38, height: 38)
                        .background(Theme.info.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sleepLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(vitalsLine)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardElevated()
            }
            .buttonStyle(.plain)
        }
    }

    private var hasData: Bool {
        sleep.contains { $0.asleepMinutes > 0 } || vitals.contains { $0.restingHeartRate > 0 || $0.hrvMs > 0 }
    }

    private var lastNight: SleepEntry? {
        let today = Calendar.current.startOfDay(for: .now)
        return sleep.first { Calendar.current.isDate($0.date, inSameDayAs: today) && $0.asleepMinutes > 0 }
    }

    private var sleepLine: String {
        if let n = lastNight {
            return "Last night: \(TrackerFormat.hm(n.asleepMinutes)) asleep"
        }
        return "Sleep & recovery"
    }

    private var vitalsLine: String {
        var parts: [String] = []
        if let n = lastNight, n.hasStages, n.deepMinutes > 0 {
            parts.append("\(TrackerFormat.hm(n.deepMinutes)) deep")
        }
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: .now))!
        if let v = vitals.last(where: { $0.date >= cutoff && ($0.restingHeartRate > 0 || $0.hrvMs > 0) }) {
            if v.restingHeartRate > 0 { parts.append("RHR \(Int(v.restingHeartRate.rounded()))") }
            if v.hrvMs > 0 { parts.append("HRV \(Int(v.hrvMs.rounded()))") }
        }
        return parts.isEmpty ? "From your tracker via Apple Health" : parts.joined(separator: " · ")
    }
}

enum TrackerFormat {
    static func hm(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Detail screen

/// Sleep + recovery detail: last night's stage breakdown, a 14-night stacked history,
/// and the recent vitals — everything the tracker feeds through Apple Health, presented
/// in Sprout's warm style (no scores, no judgments, no red numbers).
struct TrackerDetailView: View {
    @Query(sort: \SleepEntry.date, order: .reverse) private var sleep: [SleepEntry]
    @Query(sort: \VitalsEntry.date, order: .reverse) private var vitals: [VitalsEntry]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.md) {
                if let night = lastNight { lastNightCard(night) }
                if nights.count >= 2 { historyCard }
                if !recentVitals.isEmpty { vitalsCard }
                sourceFootnote
            }
            .padding(.horizontal)
            .padding(.top, Theme.Space.xs)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Sleep & recovery")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Last night

    private var lastNight: SleepEntry? {
        let today = Calendar.current.startOfDay(for: .now)
        return sleep.first { Calendar.current.isDate($0.date, inSameDayAs: today) && $0.asleepMinutes > 0 }
            ?? sleep.first { $0.asleepMinutes > 0 }
    }

    private func lastNightCard(_ n: SleepEntry) -> some View {
        let isToday = Calendar.current.isDateInToday(n.date)
        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(isToday ? "Last night" : "Latest night")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(TrackerFormat.hm(n.asleepMinutes))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("asleep")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            if n.hasStages {
                stageBar(n)
                HStack(spacing: Theme.Space.md) {
                    stageLegend("Deep", minutes: n.deepMinutes, color: Theme.protein)
                    stageLegend("REM", minutes: n.remMinutes, color: Theme.brand)
                    stageLegend("Light", minutes: n.coreMinutes, color: Theme.water)
                    if n.awakeMinutes > 0 {
                        stageLegend("Awake", minutes: n.awakeMinutes, color: Theme.textSecondary.opacity(0.5))
                    }
                }
            }
            if n.inBedMinutes > n.asleepMinutes {
                Text("In bed \(TrackerFormat.hm(n.inBedMinutes)) — falling asleep and stirring is part of every normal night.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    /// One horizontal proportional bar of the night's stages (Fitbit-style, minus the drama).
    private func stageBar(_ n: SleepEntry) -> some View {
        let total = max(n.deepMinutes + n.remMinutes + n.coreMinutes + n.awakeMinutes, 1)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                segment(geo, n.deepMinutes, total, Theme.protein)
                segment(geo, n.remMinutes, total, Theme.brand)
                segment(geo, n.coreMinutes, total, Theme.water)
                segment(geo, n.awakeMinutes, total, Theme.textSecondary.opacity(0.35))
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
    }

    private func segment(_ geo: GeometryProxy, _ minutes: Int, _ total: Int, _ color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(geo.size.width * CGFloat(minutes) / CGFloat(total), minutes > 0 ? 3 : 0))
    }

    private func stageLegend(_ label: String, minutes: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(TrackerFormat.hm(minutes))")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: 14-night history

    private var nights: [SleepEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Calendar.current.startOfDay(for: .now))!
        return sleep.filter { $0.asleepMinutes > 0 && $0.date > cutoff }.sorted { $0.date < $1.date }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Last 14 nights")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Chart(nights, id: \.id) { n in
                if n.hasStages {
                    BarMark(x: .value("night", n.date, unit: .day),
                            y: .value("deep", Double(n.deepMinutes) / 60))
                        .foregroundStyle(Theme.protein)
                    BarMark(x: .value("night", n.date, unit: .day),
                            y: .value("rem", Double(n.remMinutes) / 60))
                        .foregroundStyle(Theme.brand)
                    BarMark(x: .value("night", n.date, unit: .day),
                            y: .value("light", Double(n.coreMinutes) / 60))
                        .foregroundStyle(Theme.water)
                } else {
                    BarMark(x: .value("night", n.date, unit: .day),
                            y: .value("asleep", Double(n.asleepMinutes) / 60))
                        .foregroundStyle(Theme.water)
                }
            }
            .chartYAxisLabel("hours")
            .frame(height: 160)
            if let avg = averageLine {
                Text(avg)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    private var averageLine: String? {
        guard nights.count >= 3 else { return nil }
        let avg = nights.reduce(0) { $0 + $1.asleepMinutes } / nights.count
        return "You're averaging \(TrackerFormat.hm(avg)) a night lately."
    }

    // MARK: Vitals

    private var recentVitals: [VitalsEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: .now))!
        return vitals.filter { $0.date > cutoff && ($0.restingHeartRate > 0 || $0.hrvMs > 0) }
    }

    private var vitalsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Text("Recovery signals")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                if let signal = RecoverySignal.fromDailyVitals(vitals) {
                    Text(signal.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(signalTint(signal).opacity(0.15), in: Capsule())
                        .foregroundStyle(signalTint(signal))
                }
            }
            HStack(spacing: Theme.Space.sm) {
                if let rhr = latestValue(\.restingHeartRate) {
                    vitalTile("Resting HR", value: "\(Int(rhr.rounded()))", unit: "bpm",
                              icon: "heart.fill", tint: Theme.calories)
                }
                if let hrv = latestValue(\.hrvMs) {
                    vitalTile("HRV", value: "\(Int(hrv.rounded()))", unit: "ms",
                              icon: "waveform.path.ecg", tint: Theme.positive)
                }
            }
            Text(RecoverySignal.fromDailyVitals(vitals)?.sentence
                 ?? "These are your body's recovery signals — steady is good, and day-to-day wiggle is completely normal.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    /// Signal tint — deliberately no red anywhere: tender is a warm amber, not an alarm.
    private func signalTint(_ s: RecoverySignal) -> Color {
        switch s {
        case .rested: return Theme.positive
        case .steady: return Theme.info
        case .tender: return Theme.warning
        }
    }

    private func latestValue(_ keyPath: KeyPath<VitalsEntry, Double>) -> Double? {
        recentVitals.first(where: { $0[keyPath: keyPath] > 0 })?[keyPath: keyPath]
    }

    private func vitalTile(_ label: String, value: String, unit: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2).foregroundStyle(tint)
                Text(label)
                    .font(.caption2.weight(.semibold)).textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(unit).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.sm)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private var sourceFootnote: some View {
        // Name the pipe that's actually delivering the data — direct Google Health
        // when connected, otherwise the Apple Health path.
        Text(GoogleHealthSync.isConnected
             ? "Synced straight from Google Health (your Fitbit). Refreshes every time the app opens."
             : "Synced from your tracker through Apple Health. New data lands whenever your tracker's app syncs.")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.xs)
    }
}
