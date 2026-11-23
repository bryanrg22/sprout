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
    /// When set (she tapped a specific meal), a food picked here lands in that meal.
    var preferredMeal: MealType? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Which meal a one-tap re-log lands in. Defaults to the tapped meal section, else the
    /// time-of-day guess — but she can change it on the chips up top (so a snack never silently
    /// becomes "dinner" the way it used to). Search results still confirm in `AddFoodSheet`.
    @State private var selectedMeal: MealType

    init(date: Date, preferredMeal: MealType? = nil) {
        self.date = date
        self.preferredMeal = preferredMeal
        _selectedMeal = State(initialValue: preferredMeal ?? MealTime.current())
    }

    /// Newest-first across all history; we derive favorites + de-duped recents from this.
    @Query(sort: \FoodEntry.createdAt, order: .reverse) private var allFoods: [FoodEntry]

    /// Feedback: a warm tap when something is logged, a lighter tick when a star flips.
    @State private var logTick = 0
    @State private var starTick = 0

    // Database search (replaces the old standalone "Search foods" sheet): typing in the
    // search bar queries Open Food Facts; picking a result opens the confirm sheet.
    @State private var query = ""
    @State private var searchResults: [OFFProduct] = []
    @State private var searchPhase: SearchPhase = .idle
    @State private var searchTask: Task<Void, Never>?
    @State private var draft: FoodDraft?

    private enum SearchPhase { case idle, searching, results, failed }

    /// How many distinct recent foods to surface. Enough to cover her usual rotation
    /// without turning the list into a wall.
    private let recentLimit = 15

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isSearching: Bool { !trimmedQuery.isEmpty }

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
                if isSearching {
                    searchContent
                } else if hasHistory {
                    listContent
                } else {
                    emptyState
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Recents & Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search all foods, e.g. greek yogurt")
            .onChange(of: query) { _, _ in scheduleSearch() }
            .onSubmit(of: .search) { runSearchNow() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.brand)
                }
            }
            .sensoryFeedback(.success, trigger: logTick)
            .sensoryFeedback(.selection, trigger: starTick)
        }
        // Picking a database result opens the editable confirm sheet (then closes this one).
        .sheet(item: $draft, onDismiss: { dismiss() }) { d in
            AddFoodSheet(draft: d, date: date)
        }
    }

    /// The meal a one-tap re-log lands in — clearly visible + changeable up top, so re-logging a
    /// snack in the evening doesn't silently file it under "Dinner."
    private var mealChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log to which meal?").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            MealChipsRow(selection: $selectedMeal)
        }
        .padding(.vertical, 4)
    }

    private var listContent: some View {
        List {
            Section {
                mealChips
            }
            .listRowBackground(Color.clear)

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

    // MARK: Database search

    /// Her own favorites/recents whose name contains the query — shown above the
    /// database results so foods she already eats are one tap to repeat.
    private var localMatches: [FoodEntry] {
        guard isSearching else { return [] }
        let key = trimmedQuery.lowercased()
        var seen = Set<String>()
        var out: [FoodEntry] = []
        for food in favorites + recents where food.name.lowercased().contains(key) {
            let k = food.name.normalizedFoodKey
            guard !seen.contains(k) else { continue }
            seen.insert(k); out.append(food)
        }
        return out
    }

    private var searchContent: some View {
        List {
            if !localMatches.isEmpty {
                Section {
                    ForEach(localMatches) { row(for: $0) }
                } header: {
                    sectionHeader("Your foods", systemImage: "star.fill")
                }
            }
            Section {
                switch searchPhase {
                case .idle, .searching:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching the food database…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.card)
                case .results:
                    if searchResults.isEmpty {
                        Text("No matches in the database. Try different words, scan a barcode, or add it manually.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .listRowBackground(Theme.card)
                    } else {
                        ForEach(searchResults) { product in
                            Button {
                                draft = FoodDraft(from: product,
                                                  meal: preferredMeal ?? MealTime.current(),
                                                  source: .search)
                            } label: {
                                searchResultRow(product)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.card)
                        }
                    }
                case .failed:
                    Text("Search didn't work. Check your connection and try again.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.card)
                }
            } header: {
                sectionHeader("All foods", systemImage: "magnifyingglass")
            } footer: {
                Text("Results come from the Open Food Facts community database.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
    }

    private func searchResultRow(_ product: OFFProduct) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name.isEmpty ? "Unnamed food" : product.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let brand = product.brand, !brand.isEmpty { Text(brand).lineLimit(1) }
                    Text(product.servingDescription).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(product.calories.rounded()))")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Theme.calories)
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: Search logic

    /// Debounced search as she types (350 ms after the last keystroke).
    private func scheduleSearch() {
        searchTask?.cancel()
        let q = trimmedQuery
        guard !q.isEmpty else { searchPhase = .idle; searchResults = []; return }
        searchPhase = .searching
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            await performSearch(q)
        }
    }

    /// Immediate search when she taps the keyboard's Search key.
    private func runSearchNow() {
        searchTask?.cancel()
        let q = trimmedQuery
        guard !q.isEmpty else { return }
        searchPhase = .searching
        searchTask = Task { await performSearch(q) }
    }

    private func performSearch(_ q: String) async {
        do {
            let found = try await OpenFoodFactsService.search(query: q)
            if Task.isCancelled { return }
            await MainActor.run {
                searchResults = found
                searchPhase = .results
            }
        } catch {
            if Task.isCancelled { return }
            await MainActor.run {
                searchResults = []
                searchPhase = .failed
            }
        }
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
    /// calories, macros, label nutrients, source, notes, favorite flag) but gets a brand-new identity
    /// and timestamps via the model's init — so it reads as a genuinely new log,
    /// including the freshly-added `.popIn` in FoodLogView (which keys off createdAt).
    private func logAgain(_ food: FoodEntry) {
        let copy = food.relogged(on: date, meal: selectedMeal)
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
