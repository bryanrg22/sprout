import SwiftUI
import SwiftData

/// The "life happened, and that's fine" card. Shows at the top of Today when the user
/// returns after a real break (7+ silent days) — the moment every other system used to
/// handle worst: streak reset to zero with no acknowledgement, charts implying decline,
/// the coach treating day one back like any other day.
///
/// Philosophy: the app works around the user, not the other way round. A gap is not a
/// failure to repair — nothing is "lost", nothing needs making up. So this card only
/// welcomes: warm, brief, zero guilt, one gentle invitation to log a single thing.
///
/// Lifecycle: appears while the pre-today gap is ≥ 7 days, which self-resolves — the day
/// after any new log, `daysSinceLastLog` becomes 1 and the card is gone. Dismissing hides
/// it for THIS comeback only (keyed on the last-logged day), so a future break months from
/// now is welcomed again.
struct WelcomeBackCard: View {
    @Query private var foods: [FoodEntry]
    @Query private var water: [WaterEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    /// Minimum silent days before this counts as "a break" rather than a busy weekend.
    static let minGapDays = 7

    @State private var dismissedForKey: Double? =
        UserDefaults.standard.object(forKey: Self.dismissKey) as? Double
    private static let dismissKey = "welcomeBack.dismissedForLastLogDay"

    var body: some View {
        if let away = daysAway, away >= Self.minGapDays, !isDismissedForCurrentGap {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "sun.max.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.warning)
                    Text("Welcome back 💛")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    Button {
                        dismissCurrentGap()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(6)
                    }
                    .accessibilityLabel("Dismiss")
                }
                Text("It's been \(away) days — and that's completely okay. This app works around your life, not the other way around. Everything you logged before is still here, nothing needs catching up, and today is simply a fresh start. Log one thing and you're rolling again.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardElevated()
        }
    }

    // MARK: - Gap state

    private var daysAway: Int? {
        StreakCalculator.daysSinceLastLog(foods: foods, waters: water, weights: weights)
    }

    /// The identity of "this" comeback: the start-of-day timestamp of the most recent
    /// pre-today log. Dismissal is stored against it, so the card stays hidden for the
    /// rest of this gap but returns for any future one.
    private var currentGapKey: Double? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let past = StreakCalculator.loggedDays(foods: foods, waters: water, weights: weights)
            .filter { $0 < today }
        return past.max()?.timeIntervalSinceReferenceDate
    }

    private var isDismissedForCurrentGap: Bool {
        guard let dismissedForKey, let currentGapKey else { return false }
        return dismissedForKey == currentGapKey
    }

    private func dismissCurrentGap() {
        guard let currentGapKey else { return }
        withAnimation { dismissedForKey = currentGapKey }
        UserDefaults.standard.set(currentGapKey, forKey: Self.dismissKey)
    }
}
