import SwiftUI

/// The buddy's whole day in ONE widget — replacing the separate status + full-stats cards.
///
/// Always shows who they are and how they're doing (avatar, mood, streak, "logged today",
/// last-active). When they've **opted into sharing** (`sharesFullData`), it adds their day's
/// metrics as home-screen-style tiles — weight + a calories ring + a protein ring — and
/// today's food as friendly chips instead of a comma list. When they share activity only,
/// it gracefully shows just the warm header (the old status-card behavior).
struct BuddyDayCard: View {
    let snapshot: BuddySnapshotPayload
    /// The buddy's pixel character (the OTHER avatar from mine).
    var avatar: CompanionAvatar = .bryan

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            badges
            if snapshot.sharesFullData {
                Divider().overlay(Theme.divider)
                metricTiles
                eatenToday
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Header (avatar · name · mood · last active)

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle()
                    .fill(moodTint.opacity(0.18))
                    .frame(width: 46, height: 46)
                    .overlay(Circle().strokeBorder(moodTint.opacity(0.35), lineWidth: 1))
                pixelAvatar.frame(width: 46, height: 50)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: snapshot.characterMood.systemImage).font(.caption)
                    Text(moodLine).font(.subheadline)
                }
                .foregroundStyle(moodTint)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.caption2)
                Text(relativeLastActive).font(.caption)
            }
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private var badges: some View {
        HStack(spacing: Theme.Space.sm) {
            if snapshot.dayStreak > 0 {
                chip("\(streakEmoji) \(snapshot.dayStreak)-day streak", tint: Theme.warning)
            }
            chip(snapshot.loggedTodayEffective ? "logged today ✓" : "no log yet today",
                 tint: snapshot.loggedTodayEffective ? Theme.positive : Theme.textSecondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Metric tiles (Weight · Calories ring · Protein ring)

    private var metricTiles: some View {
        HStack(spacing: Theme.Space.sm) {
            tile(label: "Weight") {
                VStack(spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(Self.oneDecimal(snapshot.trendWeightLbs))
                            .font(.title3.weight(.bold)).monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text("lb").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Text(rateText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(rateTint)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if snapshot.goalWeightLbs > 0 {
                        Text("→ \(Self.oneDecimal(snapshot.goalWeightLbs))")
                            .font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                }
            }
            ringTile(label: "Calories", eaten: snapshot.caloriesEaten,
                     target: snapshot.calorieTarget, unit: "", color: Theme.calories)
            ringTile(label: "Protein", eaten: snapshot.proteinEaten,
                     target: snapshot.proteinTarget, unit: "g", color: Theme.protein)
        }
    }

    private func ringTile(label: String, eaten: Double, target: Double, unit: String, color: Color) -> some View {
        tile(label: label) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().stroke(Theme.divider.opacity(0.55), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: max(0.001, min(target > 0 ? eaten / target : 0, 1)))
                        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(Self.grouped(eaten))
                        .font(.subheadline.weight(.bold)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .minimumScaleFactor(0.6).lineLimit(1).padding(4)
                }
                .frame(width: 52, height: 52)
                Text(target > 0 ? "of \(Self.grouped(target))\(unit)" : "\(Self.grouped(eaten))\(unit)")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    /// The home-screen-style tile chrome: an uppercase label over centered content on a
    /// raised rounded background, so the three metrics read as a clean little widget.
    private func tile<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold)).textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.sm)
        .padding(.horizontal, 6)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    // MARK: - Eaten today (chips)

    private var eatenToday: some View {
        VStack(alignment: .leading, spacing: 8) {
            // When the snapshot is stale (synced before today), these foods are their LAST logged
            // day's — label them honestly rather than as "today".
            Text(snapshot.reflectsToday ? "Eaten today" : "Last logged")
                .font(.caption.weight(.semibold)).textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
            if foods.isEmpty {
                HStack(spacing: 6) {
                    Text("🌱")
                    Text("Nothing logged yet")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            } else {
                BuddyChipFlow(spacing: 6) {
                    ForEach(foods, id: \.self) { foodChip($0) }
                }
            }
        }
    }

    private var foods: [String] {
        snapshot.todayFoods
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func foodChip(_ name: String) -> some View {
        Text(name)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.brandSoft, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.brand.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Small shared bits

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold)).monospacedDigit()
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(tint.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1))
            .foregroundStyle(tint)
            .lineLimit(1)
    }

    @ViewBuilder private var pixelAvatar: some View {
        Group {
            switch avatar {
            case .victoria: PixelVictoriaView(mood: .happy)
            case .bryan:    PixelBryanView(mood: .happy)
            }
        }
        .scaleEffect(0.34)
    }

    // MARK: - Derived (mood / rate / time / formatting)

    private var moodTint: Color {
        switch snapshot.characterMood {
        case .thriving: return Theme.brand
        case .happy:    return Theme.positive
        case .sleepy:   return Theme.info
        }
    }
    private var moodLine: String {
        switch snapshot.characterMood {
        case .thriving: return "thriving"
        case .happy:    return "doing great"
        case .sleepy:   return "taking it easy"
        }
    }
    private var streakEmoji: String { snapshot.dayStreak >= 7 ? "🔥" : "🌱" }

    private var relativeLastActive: String {
        let interval = Date.now.timeIntervalSince(snapshot.lastActive)
        if interval < 90 { return "just now" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: snapshot.lastActive, relativeTo: .now)
    }

    private static let flatRateThreshold = 0.1
    private var rateText: String {
        let rate = snapshot.weeklyRateLbs
        if abs(rate) < Self.flatRateThreshold { return "holding steady" }
        return "\(rate < 0 ? "↓" : "↑") \(Self.oneDecimal(abs(rate)))/wk"
    }
    private var rateTint: Color {
        let rate = snapshot.weeklyRateLbs
        if abs(rate) < Self.flatRateThreshold { return Theme.textSecondary }
        let goal = snapshot.goalWeightLbs, trend = snapshot.trendWeightLbs
        let towardGoal = (goal > 0 && trend > 0) ? (trend > goal ? rate < 0 : rate > 0) : rate < 0
        return towardGoal ? Theme.positive : Theme.textSecondary
    }

    private static func grouped(_ value: Double) -> String {
        value.rounded().formatted(.number.grouping(.automatic))
    }
    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var accessibilitySummary: String {
        var parts = ["\(snapshot.displayName), \(moodLine)"]
        if snapshot.dayStreak > 0 { parts.append("\(snapshot.dayStreak) day streak") }
        parts.append(snapshot.loggedTodayEffective ? "logged today" : "hasn't logged yet today")
        parts.append("active \(relativeLastActive)")
        if snapshot.sharesFullData {
            parts.append("weight \(Self.oneDecimal(snapshot.trendWeightLbs)) lb, \(rateText)")
            parts.append("calories \(Self.grouped(snapshot.caloriesEaten)) of \(Self.grouped(snapshot.calorieTarget))")
            parts.append("protein \(Self.grouped(snapshot.proteinEaten)) of \(Self.grouped(snapshot.proteinTarget)) grams")
            let foodLabel = snapshot.reflectsToday ? "eaten today: " : "last logged: "
            parts.append(foods.isEmpty ? "nothing logged yet" : foodLabel + snapshot.todayFoods)
        }
        return parts.joined(separator: ", ")
    }
}

/// A minimal wrapping (flow) layout for the food chips — wraps to new rows as needed.
struct BuddyChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? max(0, x - spacing) : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
