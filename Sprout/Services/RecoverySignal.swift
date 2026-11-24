import Foundation

/// A daily recovery read from resting heart rate + HRV against the user's OWN recent
/// baseline — Whoop's recovery idea at the resolution our data honestly supports.
///
/// Why daily and not real-time stress: Whoop's Stress Monitor scores live HR/HRV streamed
/// continuously from the strap. A tracker bridged through Apple Health delivers DAILY
/// aggregates, so a "right now" stress number would be fiction. What the daily numbers CAN
/// say truthfully: whether the body is running rested, steady, or under load compared to
/// its own last two weeks — which is exactly the signal a warm coach can use.
///
/// Wording contract (anti-clinical, anti-alarm): never "stress score", never red, never a
/// number to chase. Three states in plain words, and `tender` is framed as the body
/// carrying something (hard training, short sleep, a big week) with gentleness as the
/// response — not as a problem reading.
enum RecoverySignal: String {
    case rested   // signals better than baseline — body topped up
    case steady   // within normal wiggle
    case tender   // running above usual load — be gentle today

    /// Compute today's signal vs a personal baseline.
    /// - Parameters:
    ///   - todayRHR/todayHRV: today's (or most recent ≤2-day-old) daily values; pass nil when absent.
    ///   - baselineRHR/baselineHRV: mean of the prior window (exclude today); nil when < 5 days of data.
    /// Returns nil when there isn't enough signal to say anything honest.
    static func compute(todayRHR: Double?, baselineRHR: Double?,
                        todayHRV: Double?, baselineHRV: Double?) -> RecoverySignal? {
        let rhrDelta: Double? = {
            guard let t = todayRHR, let b = baselineRHR, t > 0, b > 0 else { return nil }
            return t - b                                    // + = elevated (load)
        }()
        let hrvRatio: Double? = {
            guard let t = todayHRV, let b = baselineHRV, t > 0, b > 0 else { return nil }
            return t / b                                    // < 1 = suppressed (load)
        }()
        guard rhrDelta != nil || hrvRatio != nil else { return nil }

        // Under load: RHR clearly above baseline OR HRV clearly suppressed.
        if (rhrDelta ?? 0) >= 4 || (hrvRatio ?? 1) <= 0.75 { return .tender }
        // Topped up: RHR below baseline or HRV clearly above it (and nothing says load).
        if (rhrDelta ?? 0) <= -2 || (hrvRatio ?? 1) >= 1.15 { return .rested }
        return .steady
    }

    /// Compute from daily `VitalsEntry` rows: latest value within 2 days vs the mean of
    /// the prior 14 days (needs ≥5 baseline days per metric to count it).
    static func fromDailyVitals(_ vitals: [VitalsEntry],
                                now: Date = .now,
                                calendar cal: Calendar = .current) -> RecoverySignal? {
        let today = cal.startOfDay(for: now)
        guard let recentCutoff = cal.date(byAdding: .day, value: -2, to: today),
              let baseCutoff = cal.date(byAdding: .day, value: -14, to: today) else { return nil }

        let latest = vitals
            .filter { $0.date >= recentCutoff && ($0.restingHeartRate > 0 || $0.hrvMs > 0) }
            .max(by: { $0.date < $1.date })
        let baseRows = vitals.filter { $0.date >= baseCutoff && $0.date < (latest?.date ?? today) }

        func mean(_ values: [Double]) -> Double? {
            let v = values.filter { $0 > 0 }
            return v.count >= 5 ? v.reduce(0, +) / Double(v.count) : nil
        }
        return compute(todayRHR: (latest?.restingHeartRate).flatMap { $0 > 0 ? $0 : nil },
                       baselineRHR: mean(baseRows.map(\.restingHeartRate)),
                       todayHRV: (latest?.hrvMs).flatMap { $0 > 0 ? $0 : nil },
                       baselineHRV: mean(baseRows.map(\.hrvMs)))
    }

    // MARK: - Copy (the only words the UI/coach may use for this)

    /// Short label for tiles/chips.
    var label: String {
        switch self {
        case .rested: return "Rested"
        case .steady: return "Steady"
        case .tender: return "A bit tender"
        }
    }

    /// One warm sentence for the detail screen.
    var sentence: String {
        switch self {
        case .rested:
            return "Your signals are running better than your usual — your body's topped up. Great day to do whatever sounds good."
        case .steady:
            return "Right in your normal range — your body's handling the week just fine."
        case .tender:
            return "Your body's carrying a little extra load right now — a hard workout, short sleep, or a big week can all do it. Gentleness counts double today."
        }
    }

    /// The line Vita sees (folded into her data snapshot).
    var coachLine: String {
        switch self {
        case .rested:
            return "Recovery signal: RESTED — RHR/HRV are running better than the user's own baseline; a good day for anything."
        case .steady:
            return "Recovery signal: steady — vitals in the user's normal range."
        case .tender:
            return "Recovery signal: TENDER — RHR/HRV are running above the user's usual load (hard training, short sleep, or a big week). Favor gentleness today: suggest rest, a walk, hydration, an early night — never push, and never dramatize the reading."
        }
    }
}
