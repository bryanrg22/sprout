import SwiftUI
import SwiftData

/// One-tap re-logging. Repeat meals are most of real-world logging, so this sheet
/// surfaces ⭐ favorites and the foods she's eaten recently and lets her drop a
/// fresh copy onto the chosen day with a single tap — no re-typing, no AI round-trip.
///
/// Numbers are copied verbatim from the prior entry (a new id/date/createdAt is
/// minted) so the re-log is a faithful repeat she can still edit afterward.
struct RecentFoodsSheet: View {
    /// The day the re-logged entry should land on (matches the day FoodLogView is viewing).
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Newest-first across all history; we derive favorites + de-duped recents from this.
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var allFoods: [FoodEntry]

    /// Feedback: a warm tap when something is logged, a lighter tick when a star flips.
    @State private var logTick = 0
    @State private var starTick = 0

    /// How many distinct recent foods to surface. Enough to cover her usual rotation
    /// without turning the list into a wall.
    private let recentLimit = 15

    // MARK: Derived lists

    /// Everything she's starred, newest-first (the query is already reverse-sorted).
    private var favorites: [FoodEntry] {
        allFoods.filter { $0.isFavorite }
    }

    /// The most-recent entry per distinct name (case-insensitive), excluding anything
    /// already shown under Favorites, capped at `recentLimit`. Because `allFoods` is
    /// newest-first, the first time we see a name it's that food's latest log.
    private var recents: [FoodEntry] {
        let favoriteNames = Set(favorites.map { $0.name.normalizedFoodKey })
        var seen = Set<String>()
        var result: [FoodEntry] = []
        for food in allFoods {
            let key = food.name.normalizedFoodKey
            guard !key.isEmpty else { continue }          // skip blank-named rows
            guard !favoriteNames.contains(key) else { continue }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(food)
            if result.count >= recentLimit { break }
        }
        return result
    }

    /// No favorites and no recents → she hasn't logged anything yet.
    private var hasHistory: Bool { !favorites.isEmpty || !recents.isEmpty }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if hasHistory {
                    listContent
                } else {
                    emptyState
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Recents & Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.brand)
                }
            }
            .sensoryFeedback(.success, trigger: logTick)
            .sensoryFeedback(.selection, trigger: starTick)
        }
    }

    private var listContent: some View {
        List {
            if !favorites.isEmpty {
                Section {
                    ForEach(favorites) { food in
                        row(for: food)
                    }
                } header: {
                    sectionHeader("Favorites", systemImage: "star.fill")
                } footer: {
                    Text("Your starred foods — tap to log one again.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if !recents.isEmpty {
                Section {
                    ForEach(recents) { food in
                        row(for: food)
                    }
                } header: {
                    sectionHeader("Recent", systemImage: "clock.arrow.circlepath")
                } footer: {
                    if favorites.isEmpty {
                        Text("Tap a food to log it again, or tap the star to keep it handy. 💛")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .textCase(nil)
    }

    // MARK: Row

    /// A single re-loggable food. Tapping the row body logs it again; the trailing
    /// star toggles favorite. A swipe + context menu offer the same star action so
    /// it's discoverable however she reaches for it.
    private func row(for food: FoodEntry) -> some View {
        Button {
            logAgain(food)
        } label: {
            HStack(spacing: Theme.Space.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(food.name.isEmpty ? "Untitled food" : food.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle(for: food))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.Space.sm)

                // Star toggle — tappable on its own without triggering the row's log action.
                Button {
                    toggleFavorite(food)
                } label: {
                    Image(systemName: food.isFavorite ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(food.isFavorite ? Theme.brand : Theme.textSecondary.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(food.isFavorite ? "Remove \(food.name) from favorites" : "Add \(food.name) to favorites")

                // A quiet "tap to repeat" affordance so the row reads as actionable.
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.brand)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.card)
        // Swipe to log again (leading) and to toggle the star (trailing).
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                logAgain(food)
            } label: {
                Label("Log again", systemImage: "plus")
            }
            .tint(Theme.brand)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                toggleFavorite(food)
            } label: {
                Label(food.isFavorite ? "Unfavorite" : "Favorite",
                      systemImage: food.isFavorite ? "star.slash" : "star")
            }
            .tint(Theme.warning)
        }
        .contextMenu {
            Button {
                logAgain(food)
            } label: {
                Label("Log again", systemImage: "arrow.counterclockwise")
            }
            Button {
                toggleFavorite(food)
            } label: {
                Label(food.isFavorite ? "Remove from favorites" : "Add to favorites",
                      systemImage: food.isFavorite ? "star.slash" : "star")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(food.name), \(subtitle(for: food))")
        .accessibilityHint("Logs this again")
        .accessibilityAction(named: food.isFavorite ? "Remove from favorites" : "Add to favorites") {
            toggleFavorite(food)
        }
    }

    /// "320 kcal · P 24 / C 30 / F 12" — calories lead, macros rounded to whole grams.
    private func subtitle(for food: FoodEntry) -> String {
        let cals = "\(Int(food.calories.rounded())) kcal"
        let macros = "P \(g(food.proteinG)) / C \(g(food.carbsG)) / F \(g(food.fatG))"
        return "\(cals) · \(macros)"
    }

    private func g(_ value: Double) -> String { "\(Int(value.rounded()))" }

    // MARK: Empty state

    /// No history yet — warm and inviting, matching the FoodLogView tone.
    private var emptyState: some View {
        VStack(spacing: Theme.Space.md) {
            ZStack {
                Circle()
                    .fill(Theme.brandSoft)
                    .frame(width: 76, height: 76)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.brand)
            }
            Text("Nothing to repeat yet")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Log a few meals and they'll show up here for one-tap repeat 💛")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
        .padding(.horizontal, Theme.Space.md)
    }

    // MARK: Mutations

    /// Inserts a fresh copy of `food` onto `date` for the time-appropriate meal, then
    /// dismisses. The copy keeps the user-meaningful fields (name, serving, quantity,
    /// calories, macros, source, notes, favorite flag) but gets a brand-new identity
    /// and timestamps via the model's init — so it reads as a genuinely new log,
    /// including the freshly-added `.popIn` in FoodLogView (which keys off createdAt).
    private func logAgain(_ food: FoodEntry) {
        let copy = FoodEntry(
            date: date,
            mealType: MealTime.current(),
            name: food.name,
            servingDescription: food.servingDescription,
            quantity: food.quantity,
            calories: food.calories,
            proteinG: food.proteinG,
            carbsG: food.carbsG,
            fatG: food.fatG,
            caloriesLow: food.caloriesLow,
            caloriesHigh: food.caloriesHigh,
            source: food.source,
            confidence: food.confidence,
            notes: food.notes,
            barcode: food.barcode,
            // Don't copy the original photo: a re-log is a quick repeat, not the same
            // meal/photo, and copying external-storage blobs would bloat the store.
            photoData: nil,
            isFavorite: food.isFavorite
        )
        context.insert(copy)
        try? context.save()
        logTick += 1
        dismiss()
    }

    /// Flips the favorite flag in place and persists. (Mutating the stored property
    /// re-runs the @Query, so the row + sections update immediately.)
    private func toggleFavorite(_ food: FoodEntry) {
        food.isFavorite.toggle()
        try? context.save()
        starTick += 1
    }
}

// MARK: - Name de-dupe key

private extension String {
    /// A case/whitespace-insensitive key so "Greek Yogurt" and "greek yogurt " collapse
    /// to the same recent. Kept tiny on purpose — just enough to avoid obvious dupes.
    var normalizedFoodKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

#Preview {
    RecentFoodsSheet(date: .now)
        .modelContainer(for: FoodEntry.self, inMemory: true)
}
