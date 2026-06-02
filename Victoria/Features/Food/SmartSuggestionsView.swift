import SwiftUI
import SwiftData
import CoreLocation

/// The "Smart picks for you" section on the Food tab.
///
/// It builds a factual `FoodSuggestionEngine.Context` from her REAL logged history
/// (today's intake vs. targets, the current meal slot, her most-logged foods, her recent
/// protein trend), optionally folds in one nearby healthy spot, then asks the LLM to
/// phrase 2–3 specific, additive picks. Numbers are code-owned (the engine); the model
/// only writes the words.
///
/// States it handles gracefully:
/// - loading (a tasteful shimmer of placeholder cards),
/// - loaded (the suggestion cards),
/// - error (a friendly line + Retry),
/// - empty history ("Log a few meals and I'll start tailoring picks"),
/// - no API key (a small muted note — no key-entry field; that lives in Settings).
///
/// Caching: the last result is cached in `UserDefaults` keyed by `day + meal-slot`, so it
/// won't re-call the LLM on every appear; it regenerates automatically when the meal slot
/// rolls over (breakfast → lunch …), and the refresh button forces a fresh call.
struct SmartSuggestionsView: View {
    let profile: UserProfile

    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var phase: Phase = .idle
    /// Bumped by the refresh button to force a regen even if a fresh cache exists.
    @State private var reloadTick = 0
    /// Drives the continuous spin of the refresh icon while loading.
    @State private var spinAngle: Double = 0

    private enum Phase: Equatable {
        case idle
        case loading
        case loaded([Suggestion])
        case empty                  // not enough history to personalize yet
        case error
    }

    // MARK: - Body

    var body: some View {
        // No key configured → a single small, muted note (suggestions need the AI key).
        // We don't duplicate a key-entry field; that lives in Settings → AI.
        if !KeychainStore.hasAPIKey {
            noKeyNote
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardElevated()
            // Re-runs when the task id changes: on first appear, when refresh is tapped
            // (reloadTick), and — on the next render after a meal boundary — when the slot
            // rolls over (so returning to the tab at dinner yields dinner picks, served
            // from cache if already generated). `load()` itself decides cache vs. network.
            .task(id: taskKey) { await load() }
        }
    }

    /// Drives `.task(id:)` — the current meal slot plus the manual reload counter.
    private var taskKey: String { "\(currentSlot.rawValue)#\(reloadTick)" }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle().fill(Theme.brandSoft).frame(width: 30, height: 30)
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.brand)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Smart picks for you")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Built from what you actually eat")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            refreshButton
        }
    }

    private var isLoading: Bool { phase == .loading }

    private var refreshButton: some View {
        Button {
            // Force a regen: bumping the tick changes the task id AND we clear the cache
            // for this slot so we don't just re-read it.
            clearCache(for: currentSlot)
            reloadTick += 1
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isLoading ? Theme.textSecondary : Theme.brand)
                .frame(width: 34, height: 34)
                .background(Theme.brandSoft, in: Circle())
                // Continuous spin while loading: a monotonically increasing angle keyed on
                // `spinAngle` (a fixed 0→360 can't visibly repeat). Reset to 0 when idle.
                .rotationEffect(.degrees(spinAngle))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel("Refresh suggestions")
        .onChange(of: isLoading) { _, loading in
            if loading {
                spinAngle = 0
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    spinAngle = 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { spinAngle = 0 }
            }
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            loadingCards
        case .loaded(let suggestions):
            VStack(spacing: Theme.Space.sm) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, s in
                    SuggestionCard(suggestion: s).appearLift(true, index: index)
                }
            }
        case .empty:
            emptyHistoryState
        case .error:
            errorState
        }
    }

    /// Two shimmering placeholder cards while we wait — tasteful, on-brand, not a bare spinner.
    private var loadingCards: some View {
        VStack(spacing: Theme.Space.sm) {
            ForEach(0..<2, id: \.self) { _ in placeholderCard }
        }
        .accessibilityLabel("Loading suggestions")
    }

    private var placeholderCard: some View {
        HStack(spacing: Theme.Space.sm) {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.brandSoft)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.divider)
                    .frame(width: 110, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(Theme.divider)
                    .frame(maxWidth: .infinity).frame(height: 10)
                RoundedRectangle(cornerRadius: 4).fill(Theme.divider)
                    .frame(width: 160, height: 10)
            }
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .modifier(Shimmer())
    }

    /// Not enough logged history yet to personalize — invite a few logs (direct, not precious).
    private var emptyHistoryState: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "fork.knife")
                .font(.title3)
                .foregroundStyle(Theme.brand)
                .frame(width: 38, height: 38)
                .background(Theme.brandSoft, in: Circle())
            Text("Log a few meals and I'll start tailoring picks to what you actually eat.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Space.xs)
    }

    /// Transient failure — friendly, with a Retry that forces a fresh call.
    private var errorState: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "exclamationmark.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(Theme.warning)
                .frame(width: 38, height: 38)
                .background(Theme.warning.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't load picks right now.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("Tap to try again.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                clearCache(for: currentSlot)
                reloadTick += 1
            } label: {
                Text("Retry")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 8)
                    .background(Theme.brandGradient,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry loading suggestions")
        }
        .padding(.vertical, Theme.Space.xs)
    }

    /// The small, muted "needs the AI key" note. No key-entry field here — just a pointer.
    private var noKeyNote: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "sparkles")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text("Smart picks need your AI key — add it in Settings → AI.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.sm)
        .background(Theme.card.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .strokeBorder(Theme.divider, lineWidth: 1))
    }

    // MARK: - Derived inputs (code-owned numbers — same basis as FoodLogView)

    private var calendar: Calendar { .current }
    private var currentSlot: FoodSuggestionEngine.MealSlot { FoodSuggestionEngine.mealSlot() }

    /// Weight basis for targets, identical to `FoodLogView`'s: smoothed trend → start weight → 150.
    private var basisWeight: Double {
        TrendCalculator.currentTrend(weights) ?? (profile.startWeightLbs > 0 ? profile.startWeightLbs : 150)
    }
    private var calorieTarget: Double { profile.dailyCalorieTarget(weightLbs: basisWeight) }
    private var proteinTarget: Double { profile.macroTargets(weightLbs: basisWeight).proteinG }

    /// Today's running totals (same same-day filter the Food tab uses).
    private var todaysFoods: [FoodEntry] {
        foods.filter { calendar.isDate($0.date, inSameDayAs: .now) }
    }
    private var caloriesEatenToday: Double { todaysFoods.reduce(0) { $0 + $1.calories } }
    private var proteinEatenToday: Double { todaysFoods.reduce(0) { $0 + $1.proteinG } }

    /// Map the profile's pace direction onto the engine's decoupled `Direction`.
    private var direction: FoodSuggestionEngine.Direction {
        switch profile.pace.direction {
        case .lose:     return .lose
        case .maintain: return .maintain
        case .gain:     return .gain
        }
    }

    // MARK: - Load

    /// Assemble the context, serve from cache when fresh, otherwise call the LLM.
    @MainActor
    private func load() async {
        let slot = currentSlot

        // 1) Decide if there's anything to personalize from. The engine's top-foods drive
        //    this; computing it here lets us short-circuit to the empty state WITHOUT an
        //    LLM call (and without caching an "empty" as if it were a real result).
        let top = FoodSuggestionEngine.topFoods(foods)
        guard !top.isEmpty else {
            phase = .empty
            return
        }

        // 2) Fresh cache for this slot? Show it and skip the network. (The refresh button
        //    clears the cache before bumping the tick, so it always regenerates.)
        if let cached = readCache(for: slot) {
            phase = .loaded(cached)
            return
        }

        // 3) Otherwise generate. Show the shimmer while we work.
        phase = .loading

        // Optional nearby place — best-effort, never blocks the core suggestions. If
        // location is off / denied / errors, `place` is nil and we simply omit it.
        let nearby = await fetchNearbyPlace()

        let context = FoodSuggestionEngine.makeContext(
            name: profile.name,
            direction: direction,
            calorieTarget: calorieTarget,
            proteinTarget: proteinTarget,
            caloriesEatenToday: caloriesEatenToday,
            proteinEatenToday: proteinEatenToday,
            foods: foods,
            nearbyPlace: nearby
        )

        do {
            let result = try await FoodSuggestionService.suggestions(for: context)
            // Guard against a stale task: only commit if we're still on this slot/tick.
            guard currentSlot == slot else { return }
            writeCache(result, for: slot)
            phase = .loaded(result)
        } catch AIConfig.AIError.missingKey {
            // Key was removed between the gate and the call — fall back to nothing loud;
            // the no-key note path will take over on next render.
            phase = .error
        } catch {
            phase = .error
        }
    }

    /// One-shot nearby lookup. Returns nil unless location is authorized AND a spot is
    /// found nearby — the whole nearby feature degrades to "omitted" otherwise.
    @MainActor
    private func fetchNearbyPlace() async -> FoodSuggestionEngine.NearbyPlace? {
        guard LocationService.shared.isAuthorized,
              let loc = await LocationService.shared.currentLocation() else { return nil }
        guard let place = await NearbyPlacesService.nearestHealthyPlace(near: loc.coordinate) else { return nil }
        return FoodSuggestionEngine.NearbyPlace(name: place.name, category: place.category)
    }

    // MARK: - Cache (UserDefaults, keyed by day + meal slot)

    /// Cache key for a given slot today: "vita.foodpicks.<yyyy-MM-dd>.<slot>". A new day or
    /// a new meal slot is a fresh key, so suggestions naturally roll over without a timer.
    private func cacheKey(for slot: FoodSuggestionEngine.MealSlot) -> String {
        "vita.foodpicks.\(Self.dayStamp.string(from: .now)).\(slot.rawValue)"
    }

    private func readCache(for slot: FoodSuggestionEngine.MealSlot) -> [Suggestion]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: slot)),
              let decoded = try? JSONDecoder().decode([Suggestion].self, from: data),
              !decoded.isEmpty else { return nil }
        return decoded
    }

    private func writeCache(_ suggestions: [Suggestion], for slot: FoodSuggestionEngine.MealSlot) {
        guard let data = try? JSONEncoder().encode(suggestions) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(for: slot))
    }

    private func clearCache(for slot: FoodSuggestionEngine.MealSlot) {
        UserDefaults.standard.removeObject(forKey: cacheKey(for: slot))
    }

    private static let dayStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Suggestion card

/// One suggestion rendered as a compact card: emoji + kind tag + title + the single
/// specific detail sentence. Matches the app's card aesthetics (Theme tokens, soft tint).
private struct SuggestionCard: View {
    let suggestion: Suggestion

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            // Emoji chip on the brand-soft wash (falls back to the kind's SF Symbol if the
            // model somehow returned no emoji).
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.brandSoft)
                    .frame(width: 40, height: 40)
                if suggestion.emoji.isEmpty {
                    Image(systemName: suggestion.kind.systemImage)
                        .font(.headline)
                        .foregroundStyle(Theme.brand)
                } else {
                    Text(suggestion.emoji).font(.title3)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: suggestion.kind.systemImage)
                        .font(.caption2.weight(.bold))
                    Text(suggestion.kind.tag.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                }
                .foregroundStyle(Theme.brand)

                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(suggestion.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .strokeBorder(Theme.divider, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(suggestion.kind.tag): \(suggestion.title). \(suggestion.detail)")
    }
}

// MARK: - Shimmer

/// A soft sheen that sweeps left-to-right across the content — the universal "loading"
/// cue, applied to the placeholder cards. Same recipe + timing as the dashboard's
/// `ShimmerLine` (which is file-private there), and it respects Reduce Motion: with motion
/// off it's a no-op so the placeholder just sits as a static muted card.
private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Theme.textSecondary.opacity(0.22), .clear],
                            startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width)
                        .offset(x: phase * geo.size.width)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}
