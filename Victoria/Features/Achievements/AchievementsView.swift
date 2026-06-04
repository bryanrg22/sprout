import SwiftUI
import SwiftData

/// Achievements — a wall of warm, health-positive badges.
///
/// Every badge celebrates a *good* habit (eating enough, protein, water, moving,
/// consistency, a guilt-free treat). The rules live in `AchievementCatalog`
/// (pure + testable); this screen just reflects earned vs locked, and on appear
/// evaluates the catalog against the live logs and unlocks any newly-earned
/// badges with a little celebration.
///
/// Slots into the tab bar like every other screen: `AchievementsView(profile:)`.
struct AchievementsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context

    @Query(sort: \AchievementUnlock.unlockedAt) private var unlocks: [AchievementUnlock]
    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var water: [WaterEntry]
    @Query(sort: \StepsEntry.date) private var steps: [StepsEntry]
    @Query(sort: \WorkoutEntry.date) private var workouts: [WorkoutEntry]

    /// Drives the staggered card entrance.
    @State private var didAppear = false
    /// Ids unlocked *this visit* — used to pop a celebratory pulse on those tiles.
    @State private var justUnlocked: Set<String> = []
    /// The badge tapped for its detail sheet.
    @State private var selected: Achievement?
    /// Bumped ONLY when a genuinely new badge unlocks — drives the confetti party
    /// + the success haptic. Never bumped on a plain re-appear.
    @State private var celebrateTick = 0

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Space.md),
        GridItem(.flexible(), spacing: Theme.Space.md),
    ]

    /// id → unlock date, for quick lookup while rendering.
    private var unlockedAt: [String: Date] {
        Dictionary(unlocks.map { ($0.achievementID, $0.unlockedAt) },
                   uniquingKeysWith: min)
    }

    private var earnedCount: Int {
        AchievementCatalog.all.filter { unlockedAt[$0.id] != nil }.count
    }

    private var allEarned: Bool {
        earnedCount == AchievementCatalog.all.count && earnedCount > 0
    }

    /// The position of an earned badge *among the earned ones* (in catalog order),
    /// so the collectible pop-in cascades smoothly with no gaps where locked
    /// badges sit. Returns 0 for anything not yet earned.
    private func earnedRank(of id: String) -> Int {
        let earnedIDs = AchievementCatalog.all.map(\.id).filter { unlockedAt[$0] != nil }
        return earnedIDs.firstIndex(of: id) ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    summaryCard
                        .appearLift(didAppear, index: 0)

                    LazyVGrid(columns: columns, spacing: Theme.Space.md) {
                        ForEach(Array(AchievementCatalog.all.enumerated()), id: \.element.id) { index, badge in
                            let earned = unlockedAt[badge.id] != nil
                            Button {
                                selected = badge
                            } label: {
                                BadgeTile(
                                    badge: badge,
                                    unlockedAt: unlockedAt[badge.id],
                                    isCelebrating: justUnlocked.contains(badge.id),
                                    isCute: profile.themeStyle == .cute,
                                    // Earned badges spring in (collectible pop);
                                    // locked ones drift in gently so they never
                                    // feel like a scolding.
                                    didAppear: didAppear,
                                    popDelay: earned ? Double(earnedRank(of: badge.id)) * 0.08 : 0
                                )
                            }
                            .buttonStyle(.plain)
                            .bouncyPress()
                            // Locked tiles still cascade softly; earned tiles
                            // handle their own springy pop-in internally.
                            .appearLift(earned ? true : didAppear, index: index + 1)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, Theme.Space.xs)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(backdrop)
            // A little party — fires only when `celebrateTick` bumps, which only
            // happens on a genuinely NEW unlock (see `evaluateAndUnlock`). Sits
            // above the scroll content; ignores taps (it's in DelightKit).
            .overlay { ConfettiBurst(trigger: celebrateTick) }
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.large)
            .sensoryFeedback(.success, trigger: celebrateTick)
            .sheet(item: $selected) { badge in
                BadgeDetailSheet(badge: badge, unlockedAt: unlockedAt[badge.id])
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                evaluateAndUnlock()
                guard !didAppear else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    didAppear = true
                }
            }
        }
    }

    /// Near-black canvas with a soft lime glow at the top — matches the dashboard.
    private var backdrop: some View {
        Theme.background
            .overlay(alignment: .top) {
                RadialGradient(colors: [Theme.brand.opacity(0.10), .clear],
                               center: .top, startRadius: 0, endRadius: 380)
                    .frame(height: 420)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }

    // MARK: Summary

    private var summaryCard: some View {
        let total = AchievementCatalog.all.count
        let progress = total > 0 ? Double(earnedCount) / Double(total) : 0
        return VStack(spacing: Theme.Space.md) {
            HStack(spacing: Theme.Space.lg) {
                // The gradient ring pops in and gently breathes, with the live count
                // nested inside — a proud little "trophy meter" for the whole shelf.
                ZStack {
                    // Soft halo behind the ring for a warm, collectible glow.
                    Circle()
                        .fill(Theme.brand.opacity(0.14))
                        .frame(width: 96, height: 96)
                        .blur(radius: 10)

                    GradientRing(progress: didAppear ? progress : 0,
                                 lineWidth: 9, gradient: .brandSweep,
                                 track: Theme.divider)
                        .frame(width: 86, height: 86)

                    // Count lives inside the ring — the headline metric, front and center.
                    VStack(spacing: 0) {
                        Text("\(earnedCount)")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Theme.textPrimary)
                        Text("of \(total)")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .popIn(didAppear)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Your collection")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        // A celebratory medal that wiggles once everything's collected.
                        Image(systemName: "rosette")
                            .font(.headline)
                            .foregroundStyle(Theme.brand)
                            .breathing()
                            .wiggle(allEarned)
                        if allEarned {
                            Text("🎉")
                                .font(.title3)
                                .popIn(didAppear, delay: 0.25)
                        }
                    }
                    Text(summaryMessage)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // A slim brand-gradient progress bar — the clearest at-a-glance read of how
            // far the shelf has filled. (Same MacroBar / speedometer fill idiom.)
            collectionBar(progress: progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated(padding: Theme.Space.lg)
    }

    /// Slim collection-progress bar: a brand-gradient fill on a soft track, growing in
    /// once the view appears. Purely reflects earned/total — no new earning logic.
    private func collectionBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.divider)
                Capsule()
                    .fill(Theme.brandGradient)
                    .frame(width: max(0, min(1, didAppear ? progress : 0)) * geo.size.width)
                    .animation(.spring(response: 0.7, dampingFraction: 0.85), value: didAppear)
            }
        }
        .frame(height: 8)
    }

    /// Warm, never-shaming copy that scales with progress — a little cheer for
    /// wherever you are today. Tone follows the active skin so it lands for both
    /// people: `.cute` is soft and sweet (Victoria), `.cool` is warm but confident
    /// (Bryan). Neither version assumes a direction — every badge here rewards
    /// *showing up and fueling*, which is true whether you're losing or gaining.
    private var summaryMessage: String {
        let cute = profile.themeStyle == .cute
        switch earnedCount {
        case 0:
            return cute
                ? "Log anything today and your first little badge is yours. 💚"
                : "Log anything today to unlock your first badge."
        case 1:
            return cute
                ? "Your first badge! The cutest collection starts with one. ✨"
                : "First badge down. The collection starts here. ✨"
        case AchievementCatalog.all.count:
            return cute
                ? "Every badge collected! You take such sweet care of yourself. 🌟"
                : "Every badge collected. You show up for yourself — it shows. 🌟"
        case (AchievementCatalog.all.count - 1):
            return "So close — just one more to complete the whole set!"
        default:
            return cute
                ? "Look at this little collection grow. Each one is a kindness to you. 💛"
                : "The collection's growing. Every badge is a day you showed up."
        }
    }

    // MARK: Earning

    /// Evaluate the catalog against live data and persist any newly-earned badges.
    private func evaluateAndUnlock() {
        let already = Set(unlocks.map(\.achievementID))
        let newly = AchievementCatalog.newlyEarned(
            foods: foods,
            weights: weights,
            water: water,
            steps: steps,
            workouts: workouts,
            profile: profile,
            alreadyUnlocked: already
        )
        guard !newly.isEmpty else { return }

        for badge in newly {
            context.insert(AchievementUnlock(achievementID: badge.id))
        }
        try? context.save()

        // Celebrate the new ones once the view has settled.
        celebrateTick += 1
        let ids = Set(newly.map(\.id))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                justUnlocked = ids
            }
            // Let the pulse + sparkle play, then relax the tile back to its calm
            // earned state. Without this the freshly-unlocked badges stayed scaled
            // up with the sparkle frozen on for the whole visit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.4)) {
                    justUnlocked.subtract(ids)
                }
            }
        }
    }
}

// MARK: - Badge tile

/// One badge in the grid. Earned = full color + medal glow + unlock date.
/// Locked = dimmed icon with a lock overlay and a hint of what's possible.
private struct BadgeTile: View {
    let badge: Achievement
    let unlockedAt: Date?
    let isCelebrating: Bool
    /// Active skin is the soft/cute one — only affects copy tone + emoji choice.
    var isCute: Bool = true
    /// Flipped on screen-appear; earned badges use it to spring in.
    var didAppear: Bool = true
    /// Per-badge stagger so earned medals cascade in like a collection.
    var popDelay: Double = 0

    private var isEarned: Bool { unlockedAt != nil }
    private var tint: Color { badge.tint.color }

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            medal
                // The medal art breathes so the wall feels gently alive. Earned
                // badges already stand apart via full color, glow, and the lock's
                // absence — so locked never reads as punished.
                .breathing()
                // Springy collectible pop-in for earned badges (cascaded by popDelay);
                // locked badges skip it and lift in softly from the parent.
                .popIn(isEarned ? didAppear : true, delay: popDelay)
                .scaleEffect(isCelebrating ? 1.14 : 1)
                .animation(.spring(response: 0.5, dampingFraction: 0.55), value: isCelebrating)

            VStack(spacing: 4) {
                Text(badge.title)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(isEarned ? Theme.textPrimary : Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Status chip: a warm "earned on …" capsule, or a soft locked hint —
                // gives every tile a clear, collectible footer.
                statusChip
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 178)
        .cardElevated(padding: Theme.Space.md, radius: Theme.Radius.lg)
        // Earned tiles get a faint tinted wash + brand-tier ring so the wall reads as a
        // real trophy shelf; locked stays a calm, plain surface (never punishing).
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(isEarned ? tint.opacity(0.05) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(isEarned ? tint.opacity(0.30) : .clear, lineWidth: 1)
        )
        // Locked stays tastefully present (not greyed-out punishing); earned pops.
        .opacity(isEarned ? 1 : 0.8)
        .overlay(alignment: .topTrailing) {
            if isCelebrating {
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundStyle(tint)
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isEarned
            ? "\(badge.title), earned \(earnedDateText). \(badge.blurb)"
            : "\(badge.title), not yet earned. \(badge.blurb)")
    }

    /// The collectible medal: a larger, dimensional "enamel pin" well — a soft
    /// radial gradient gives the disc depth, a glossy top highlight makes earned
    /// medals feel precious, and a tier ring frames it. Locked is a quiet, flat well.
    private var medal: some View {
        ZStack {
            Circle()
                // Skin-aware so the locked well reads on BOTH the dark and the
                // cream skins (a flat white wash vanished on cream). Earned wells get
                // a radial gradient (brighter at the top) for a dimensional, badge feel.
                .fill(
                    isEarned
                        ? AnyShapeStyle(RadialGradient(
                            colors: [tint.opacity(0.32), tint.opacity(0.12)],
                            center: .top, startRadius: 2, endRadius: 78))
                        : AnyShapeStyle(Theme.textSecondary.opacity(0.08))
                )
                .frame(width: 78, height: 78)
                .overlay(
                    // Tier ring — a brand-gradient sweep on earned, a hairline when locked.
                    Circle().strokeBorder(
                        isEarned ? AnyShapeStyle(Theme.brandGradient.opacity(0.55))
                                 : AnyShapeStyle(Theme.divider),
                        lineWidth: 2
                    )
                )
                .overlay(
                    // Glossy top highlight — only on earned, for that enamel-pin sheen.
                    Circle()
                        .trim(from: 0.5, to: 1)
                        .stroke(Color.white.opacity(isEarned ? 0.22 : 0), lineWidth: 1.5)
                        .rotationEffect(.degrees(180))
                        .blur(radius: 0.5)
                )
                // A soft, collectible glow on earned medals — warmer while
                // it's freshly celebrating.
                .shadow(color: isEarned ? tint.opacity(isCelebrating ? 0.6 : 0.35) : .clear,
                        radius: isEarned ? (isCelebrating ? 18 : 11) : 0)

            Image(systemName: badge.systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(isEarned ? tint : Theme.textSecondary.opacity(0.55))
                .shadow(color: isEarned ? tint.opacity(0.35) : .clear, radius: 4)

            if !isEarned {
                // A gentle, friendly lock — dimmed, never punishing.
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(5)
                    .background(Theme.cardRaised, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
                    .offset(x: 28, y: 28)
            }
        }
    }

    /// Earned → a warm tinted capsule with the unlock date; locked → a soft, kind hint.
    @ViewBuilder private var statusChip: some View {
        if isEarned {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill").font(.caption2)
                Text(earnedDateText).monospacedDigit()
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .lineLimit(1)
        } else {
            Text(isCute ? "Soon 🌱" : "Locked")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Theme.textSecondary.opacity(0.08), in: Capsule())
                .lineLimit(1)
        }
    }

    private var earnedDateText: String {
        guard let date = unlockedAt else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Detail sheet

/// Tapping a badge shows the full promise + state, on the same dark surface.
private struct BadgeDetailSheet: View {
    let badge: Achievement
    let unlockedAt: Date?

    /// Springs the sheet contents in warmly when it opens.
    @State private var shown = false
    /// One celebratory confetti puff when opening an *earned* badge.
    @State private var partyTick = 0

    private var isEarned: Bool { unlockedAt != nil }
    private var tint: Color { badge.tint.color }

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            ZStack {
                // Soft glow halo behind an earned medal so it feels precious.
                if isEarned {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 140, height: 140)
                        .blur(radius: 16)
                }
                Circle()
                    // Dimensional radial fill on earned (matches the grid's enamel-pin medal).
                    .fill(
                        isEarned
                            ? AnyShapeStyle(RadialGradient(
                                colors: [tint.opacity(0.34), tint.opacity(0.12)],
                                center: .top, startRadius: 4, endRadius: 120))
                            : AnyShapeStyle(Theme.textSecondary.opacity(0.08))
                    )
                    .frame(width: 116, height: 116)
                    .overlay(
                        // Brand-gradient tier ring on earned; hairline when locked.
                        Circle().strokeBorder(
                            isEarned ? AnyShapeStyle(Theme.brandGradient.opacity(0.55))
                                     : AnyShapeStyle(Theme.divider),
                            lineWidth: 2.5
                        )
                    )
                    .overlay(
                        // Glossy top sheen.
                        Circle()
                            .trim(from: 0.5, to: 1)
                            .stroke(Color.white.opacity(isEarned ? 0.22 : 0), lineWidth: 2)
                            .rotationEffect(.degrees(180))
                            .blur(radius: 0.5)
                    )
                    .shadow(color: isEarned ? tint.opacity(0.38) : .clear, radius: 18)
                Image(systemName: badge.systemImage)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(isEarned ? tint : Theme.textSecondary.opacity(0.55))
                    .shadow(color: isEarned ? tint.opacity(0.35) : .clear, radius: 5)
                    // An earned medal gently breathes; a locked one rests calmly.
                    .breathing()
            }
            .popIn(shown)
            .padding(.top, Theme.Space.lg)

            VStack(spacing: Theme.Space.sm) {
                Text(badge.title)
                    .font(.largeTitle.weight(.bold))
                if isEarned {
                    Text("You earned this. 🎉")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(badge.blurb)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.lg)
            .popIn(shown, delay: 0.08)

            statusPill
                .popIn(shown, delay: 0.16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .overlay { ConfettiBurst(trigger: partyTick) }
        .fontDesign(.rounded)
        .onAppear {
            shown = true
            // A warm little welcome puff for badges you've actually earned.
            if isEarned {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { partyTick += 1 }
            }
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if let date = unlockedAt {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                Text("Earned \(date.formatted(.dateTime.month(.wide).day().year()))")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(tint.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Not yet — and that's perfectly okay 💛")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.textSecondary.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
        }
    }
}

// MARK: - Tint mapping

/// Maps a catalog `TintToken` onto a concrete Theme color. Kept in the view layer
/// so `AchievementCatalog` stays free of SwiftUI.
private extension Achievement.TintToken {
    var color: Color {
        switch self {
        case .brand:    return Theme.brand
        case .protein:  return Theme.protein
        case .water:    return Theme.water
        case .carbs:    return Theme.carbs
        case .fat:      return Theme.fat
        case .positive: return Theme.positive
        case .info:     return Theme.info
        case .warning:  return Theme.warning
        }
    }
}
