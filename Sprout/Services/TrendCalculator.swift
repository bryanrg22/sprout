import Foundation

/// The emotional heart of the app: turns noisy daily weigh-ins into a smooth trend
/// so a discouraging up-day reads as "water, not fat." Uses a time-decayed
/// exponentially-weighted moving average (Libra-style) which handles skipped days
/// gracefully, plus a least-squares slope on the trend for rate + ETA.
enum TrendCalculator {

    struct TrendPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// Time-decayed EWMA over weigh-ins (must be sorted ascending by date).
    /// `smoothingDays` ~7 → responds over ~2–3 weeks.
    static func trend(_ entries: [WeightEntry], smoothingDays: Double = 7) -> [TrendPoint] {
        let sorted = entries.sorted { $0.date < $1.date }
        guard var t = sorted.first?.weightLbs else { return [] }
        var prevDate = sorted.first!.date
        var out: [TrendPoint] = [TrendPoint(date: prevDate, value: t)]
        for e in sorted.dropFirst() {
            let dt = max(0, e.date.timeIntervalSince(prevDate) / 86_400)   // days
            let alpha = 1 - exp(-dt / smoothingDays)
            t += alpha * (e.weightLbs - t)
            out.append(TrendPoint(date: e.date, value: t))
            prevDate = e.date
        }
        return out
    }

    /// Latest smoothed trend value (what we show as "your weight" instead of the raw scale).
    static func currentTrend(_ entries: [WeightEntry]) -> Double? {
        trend(entries).last?.value
    }

    /// Least-squares slope over the last `windowDays` of trend → lbs/week.
    static func ratePerWeek(_ entries: [WeightEntry], windowDays: Int = 14) -> Double {
        let pts = trend(entries)
        guard pts.count >= 2 else { return 0 }
        let cutoff = pts.last!.date.addingTimeInterval(-Double(windowDays) * 86_400)
        let window = pts.filter { $0.date >= cutoff }
        let use = window.count >= 2 ? window : pts
        let x = use.map { $0.date.timeIntervalSince(use[0].date) / 86_400 }
        let y = use.map(\.value)
        let n = Double(x.count)
        let sx = x.reduce(0, +), sy = y.reduce(0, +)
        let sxy = zip(x, y).map(*).reduce(0, +)
        let sxx = x.map { $0 * $0 }.reduce(0, +)
        let denom = n * sxx - sx * sx
        guard abs(denom) > 0.0001 else { return 0 }
        let slopePerDay = (n * sxy - sx * sy) / denom
        return slopePerDay * 7
    }

    /// Projected date to reach `goalLbs`, or nil if not meaningfully trending toward it.
    static func projectedGoalDate(_ entries: [WeightEntry], goalLbs: Double) -> Date? {
        guard let current = currentTrend(entries) else { return nil }
        let rate = ratePerWeek(entries)                      // lbs/week (negative = losing)
        let perDay = rate / 7
        let remaining = current - goalLbs
        // Need to be moving toward the goal at a non-trivial pace.
        guard abs(perDay) > 0.0005, (remaining > 0) == (perDay < 0) else { return nil }
        // Days to reach goal: current + perDay·days == goal → days = (goal − current)/perDay.
        // (remaining and perDay have opposite signs here, so this is positive.)
        let days = -remaining / perDay
        guard days > 0, days < 365 * 3 else { return nil }
        return Date.now.addingTimeInterval(days * 86_400)
    }

    /// Feedback tier for the current rate, scaled to bodyweight (0.5–1%/wk is the green zone).
    enum RateAssessment { case gainingOrFlat, slow, ideal, fast }

    static func assess(ratePerWeek rate: Double, currentWeightLbs weight: Double) -> RateAssessment {
        let lossRate = -rate                                  // positive when losing
        guard weight > 0 else { return .gainingOrFlat }
        let onePct = 0.01 * weight
        let halfPct = 0.005 * weight
        if lossRate <= 0.05 { return .gainingOrFlat }
        if lossRate < halfPct { return .slow }
        if lossRate <= onePct { return .ideal }
        return .fast
    }
}
