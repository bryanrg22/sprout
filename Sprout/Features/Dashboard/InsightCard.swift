import SwiftUI
import SwiftData

/// The proactive "your coach noticed something" card for the Today screen. It runs
/// the free on-device `DailyInsightEngine` over today's numbers, shows the single
/// best fresh insight, and records that it was shown (so it won't repeat for a few
/// days). No LLM yet — the templated copy ships as-is; the AI rephrasing layer will
/// later swap in a warmer voice behind this same seam.
struct InsightCard: View {
    let input: DailyInsightEngine.Input

    @Environment(\.modelContext) private var context
    @Query(sort: \InsightShown.shownAt, order: .reverse) private var shownLog: [InsightShown]

    /// Ids surfaced in the last 3 days — kept out of today's pick for freshness.
    private var recentlyShown: Set<String> {
        let cutoff = Date().addingTimeInterval(-3 * 86_400)
        return Set(shownLog.filter { $0.shownAt >= cutoff }.map(\.insightID))
    }

    /// The AI-rephrased line, once it arrives. Until then we show the template.
    @State private var phrasedText: String?
    @State private var phrasedForID: String?

    /// Computed synchronously (no onAppear race): the @Query drives re-evaluation
    /// when the log changes, and the inputs are all available immediately.
    private var insight: DailyInsightEngine.Insight? {
        DailyInsightEngine.bestInsight(input, recentlyShown: recentlyShown)
    }

    var body: some View {
        if let insight {
            // Show the AI line if we have it for THIS insight, else the instant template.
            let line = (phrasedForID == insight.id ? phrasedText : nil) ?? insight.template
            content(insight, line: line)
                .task(id: insight.id) { await appear(insight) }
        }
    }

    private func appear(_ chosen: DailyInsightEngine.Insight) async {
        record(chosen)
        // Rephrase at most once per day per insight, using the cheap Haiku model.
        // Falls back to the template inside the phraser on any failure.
        guard !rephrasedToday(chosen.id) else { return }
        let hint = chosen.factualHint.isEmpty ? chosen.template : chosen.factualHint
        let warm = await InsightPhraser.phrase(template: chosen.template, factualHint: hint)
        await MainActor.run {
            phrasedText = warm
            phrasedForID = chosen.id
        }
        markRephrasedToday(chosen.id)
    }

    /// Record the shown insight once per day so freshness tracking works.
    private func record(_ chosen: DailyInsightEngine.Insight) {
        let today = Calendar.current.startOfDay(for: .now)
        let alreadyToday = shownLog.contains {
            $0.insightID == chosen.id && Calendar.current.isDate($0.shownAt, inSameDayAs: today)
        }
        if !alreadyToday {
            context.insert(InsightShown(insightID: chosen.id))
            try? context.save()
        }
    }

    // Gate the (paid) rephrase to once/day per insight via UserDefaults.
    private func rephrasedKey(_ id: String) -> String {
        let day = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: .now))
        return "insightPhrased.\(id).\(day)"
    }
    private func rephrasedToday(_ id: String) -> Bool {
        UserDefaults.standard.bool(forKey: rephrasedKey(id))
    }
    private func markRephrasedToday(_ id: String) {
        UserDefaults.standard.set(true, forKey: rephrasedKey(id))
    }

    private func content(_ insight: DailyInsightEngine.Insight, line: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            ZStack {
                Circle().fill(tint(insight.tintToken).opacity(0.18))
                Image(systemName: insight.systemImage)
                    .font(.headline)
                    .foregroundStyle(tint(insight.tintToken))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(coachName) noticed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeInOut(duration: 0.35), value: line)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(tint(insight.tintToken).opacity(0.6))
                .padding(10)
        }
    }

    private var coachName: String { "Vita" }

    private func tint(_ t: DailyInsightEngine.Insight.Tint) -> Color {
        switch t {
        case .brand:    return Theme.brand
        case .protein:  return Theme.protein
        case .water:    return Theme.water
        case .info:     return Theme.info
        case .warning:  return Theme.warning
        case .positive: return Theme.positive
        }
    }
}
