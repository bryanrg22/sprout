import SwiftUI
import SwiftData

/// Today's food, grouped by meal with subtotals, plus a "＋" menu that opens the
/// photo, barcode, search, or manual entry flows. Dark, native, calorie-led.
struct FoodLogView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    /// Shared bus so a food's long-press can hand a topic to the coach.
    @Environment(AskVitaCenter.self) private var askVita: AskVitaCenter?

    @Query(sort: \FoodEntry.date, order: .reverse) private var food: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var water: [WaterEntry]

    @State private var sheet: FoodSheet?
    @State private var showWaterSheet = false
    /// The meal a chosen add-flow should log into (set when she taps a meal's "＋" or
    /// an empty meal row). `nil` for a top-level add → defaults to the current time's meal.
    @State private var preferredMeal: MealType?
    @State private var showMealChooser = false
    /// Tapping a logged food opens it in a detail card; long-press / detail "Edit" opens
    /// the editor. `pendingEditFromDetail` bridges the two sheets so the editor opens only
    /// after the detail card has dismissed (avoids a sheet-over-sheet race).
    @State private var detailEntry: FoodEntry?
    @State private var editingEntry: FoodEntry?
    @State private var pendingEditFromDetail: FoodEntry?
    @State private var addTick = 0
    @State private var deleteTick = 0
    @State private var navTick = 0

    /// Bumped to fire a one-shot confetti burst when she logs her FIRST item of
    /// the day — a small, warm celebration, not on every add. (The per-row
    /// `.popIn` is handled inside `FoodRow` itself.)
    @State private var firstLogConfetti = 0
    /// Remembers how many entries existed for the selected day so we can tell an
    /// *add* (count went up) apart from a delete or a day-switch.
    @State private var lastDayCount: Int?

    /// The day currently being viewed (start of day). Defaults to today; the
    /// chevron header lets her browse backward through her history.
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var showDatePicker = false

    private enum FoodSheet: Identifiable {
        case photo, barcode, manual, recents, label
        var id: Int { hashValue }
    }

    // MARK: Day helpers

    private var cal: Calendar { Calendar.current }
    private var startOfToday: Date { cal.startOfDay(for: .now) }
    private var isViewingToday: Bool { cal.isDateInToday(selectedDay) }
    /// Can't log or browse into the future.
    private var canGoForward: Bool { selectedDay < startOfToday }

    /// "Today" / "Yesterday" / "Mon, Jun 1" (with year if it's an older year).
    private var dayLabel: String {
        if cal.isDateInToday(selectedDay) { return "Today" }
        if cal.isDateInYesterday(selectedDay) { return "Yesterday" }
        let sameYear = cal.isDate(selectedDay, equalTo: .now, toGranularity: .year)
        return selectedDay.formatted(
            sameYear
            ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
            : .dateTime.month(.abbreviated).day().year()
        )
    }

    private func step(_ days: Int) {
        guard let next = cal.date(byAdding: .day, value: days, to: selectedDay) else { return }
        let clamped = min(cal.startOfDay(for: next), startOfToday)
        guard clamped != selectedDay else { return }
        navTick += 1
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            selectedDay = clamped
        }
    }

    // MARK: Derived values

    /// Entries for the selected day (same-day comparison ignores time-of-day, so
    /// real-timestamped entries and midnight-stamped past entries both match).
    private var dayEntries: [FoodEntry] { food.filter { cal.isDate($0.date, inSameDayAs: selectedDay) } }
    private var consumed: Double { dayEntries.reduce(0) { $0 + $1.totalCalories } }
    private var basisWeight: Double {
        TrendCalculator.currentTrend(weights) ?? (profile.startWeightLbs > 0 ? profile.startWeightLbs : 150)
    }
    private var target: Double { profile.dailyCalorieTarget(weightLbs: basisWeight) }
    private var remaining: Double { target - consumed }
    private var isOver: Bool { remaining < 0 }
    private var progress: Double { target > 0 ? consumed / target : 0 }
    private var ringColor: Color { isOver ? Theme.warning : Theme.calories }
    /// True once she's reached ~97%+ of her fuel goal. We celebrate "fueled up"
    /// rather than counting calories "remaining"/"over" — kinder, and
    /// consistent with the Dashboard hero's framing.
    private var reachedFuel: Bool { target > 0 && consumed >= target * 0.97 }

    private var meals: [MealType] { MealType.allCases.sorted { $0.sortOrder < $1.sortOrder } }

    /// Reacts to `dayEntries` changing. When the count grows from zero it's the
    /// day's very first item — a moment worth a little confetti.
    private func reactToDayEntriesChange() {
        let count = dayEntries.count
        defer { lastDayCount = count }
        guard let previous = lastDayCount else { return }   // first render: just record
        if count > previous && previous == 0 && isViewingToday {
            firstLogConfetti += 1
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    dayNav
                    summaryCard
                    // Water belongs in Nutrients too — quick-add your bottle or tap for custom.
                    if isViewingToday {
                        waterCard
                    }
                    // Smart, data-grounded food picks for the current meal. Only on today
                    // (suggestions are forward-looking for the current slot; they'd be
                    // meaningless while browsing a past day). The section self-manages its
                    // loading / empty / error / no-key states.
                    if isViewingToday {
                        SmartSuggestionsView(profile: profile)
                    }
                    if dayEntries.isEmpty && isViewingToday {
                        todayEmptyState
                    } else if dayEntries.isEmpty {
                        pastDayEmptyState
                    } else {
                        ForEach(meals) { mealCard($0) }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            // A subtle one-shot celebration for the first food logged today.
            .overlay(ConfettiBurst(trigger: firstLogConfetti).ignoresSafeArea())
            .navigationTitle("Nutrients")
            .toolbar { ToolbarItem(placement: .primaryAction) { addMenu } }
            .sheet(isPresented: $showWaterSheet) { WaterLogSheet(profile: profile) }
            .sheet(item: $sheet) { which in
                switch which {
                case .photo:   PhotoFoodFlow(date: selectedDay, preferredMeal: preferredMeal)
                case .barcode: BarcodeScanView(date: selectedDay, preferredMeal: preferredMeal)
                case .manual:  AddFoodSheet(draft: FoodDraft(meal: preferredMeal ?? MealTime.current()), date: selectedDay)
                case .recents: RecentFoodsSheet(date: selectedDay, preferredMeal: preferredMeal)
                case .label:   LabelScanView(date: selectedDay, preferredMeal: preferredMeal)
                }
            }
            // Tap a logged food → detail card. Its "Edit" defers to here so the editor
            // opens cleanly once the card has dismissed.
            .sheet(item: $detailEntry, onDismiss: {
                if let entry = pendingEditFromDetail {
                    pendingEditFromDetail = nil
                    editingEntry = entry
                }
            }) { entry in
                FoodDetailView(entry: entry, coachName: profile.coachName,
                               onEdit: { pendingEditFromDetail = entry })
            }
            .sheet(item: $editingEntry) { entry in
                AddFoodSheet(editing: entry)
            }
            // Tapping a meal's "＋" (or an empty meal row) routes the add into THAT meal.
            .confirmationDialog(mealChooserTitle, isPresented: $showMealChooser, titleVisibility: .visible) {
                Button("Snap or describe a meal") { open(.photo, for: preferredMeal) }
                Button("Scan barcode") { open(.barcode, for: preferredMeal) }
                Button("Scan a label") { open(.label, for: preferredMeal) }
                Button("Recents & favorites") { open(.recents, for: preferredMeal) }
                Button("Add manually") { open(.manual, for: preferredMeal) }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showDatePicker) { dayPickerSheet }
            .sensoryFeedback(.success, trigger: addTick)
            .sensoryFeedback(.impact(weight: .light), trigger: deleteTick)
            .sensoryFeedback(.selection, trigger: navTick)
            // Detect adds (vs. deletes / day-switches) to drive pop-in + confetti.
            .onChange(of: dayEntries.count) { reactToDayEntriesChange() }
            .onChange(of: selectedDay) {
                // A day-switch isn't an add: re-baseline the count so browsing to
                // a day that already has food doesn't fire the first-log confetti.
                lastDayCount = dayEntries.count
            }
            .onAppear { if lastDayCount == nil { lastDayCount = dayEntries.count } }
        }
    }

    // MARK: Day navigation

    private var dayNav: some View {
        HStack(spacing: Theme.Space.sm) {
            navChevron("chevron.left", enabled: true) { step(-1) }
                .accessibilityLabel("Previous day")

            Button {
                navTick += 1
                showDatePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.brand)
                    VStack(spacing: 1) {
                        Text(dayLabel)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        if !isViewingToday {
                            Text(selectedDay.formatted(.dateTime.year().month().day()))
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Theme.brandSoft, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.brand.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Selected day, \(dayLabel). Tap to pick a day.")

            navChevron("chevron.right", enabled: canGoForward) { step(1) }
                .accessibilityLabel("Next day")
        }
        .padding(.top, Theme.Space.xs)
    }

    private func navChevron(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(enabled ? Theme.brand : Theme.textSecondary.opacity(0.35))
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(enabled ? Theme.brandSoft : Color.white.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var dayPickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Jump to a day",
                selection: Binding(
                    get: { selectedDay },
                    set: { selectedDay = min(cal.startOfDay(for: $0), startOfToday) }
                ),
                in: ...startOfToday,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(Theme.brand)
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Pick a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDatePicker = false }
                        .foregroundStyle(Theme.brand)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Empty states

    // MARK: - Water (Nutrients tab)

    private var waterToday: Double {
        water.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountOz }
    }
    private var waterContainerOz: Double { profile.waterContainerOz > 0 ? profile.waterContainerOz : 16.9 }

    /// Water card on the Nutrients tab: the "＋" quick-adds your bottle; tapping the card
    /// opens `WaterLogSheet` to log a custom amount or change your bottle's size.
    private var waterCard: some View {
        HStack(spacing: Theme.Space.md) {
            ZStack {
                Circle().fill(Theme.water.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: "drop.fill").foregroundStyle(Theme.water)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Water")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(Int(waterToday.rounded())) of \(Int(profile.waterTargetOz.rounded())) oz today")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                context.insert(WaterEntry(amountOz: waterContainerOz))
                try? context.save()
            } label: {
                Image(systemName: "plus")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.water)
                    .frame(width: 32, height: 32)
                    .background(Theme.water.opacity(0.15), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.water.opacity(0.30), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add one \(profile.waterContainerLabel) of water")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .contentShape(Rectangle())
        .onTapGesture { showWaterSheet = true }
    }

    /// Today, nothing logged yet — warm + inviting, with a gently breathing
    /// strawberry to make the blank slate feel friendly rather than empty.
    private var todayEmptyState: some View {
        VStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle()
                    .fill(Theme.brandSoft)
                    .frame(width: 76, height: 76)
                Text("🍓")
                    .font(.system(size: 40))
                    .frame(width: 76, height: 76)
            }
            Text("Nothing logged yet — what's first? 🍓")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Snap a photo, scan a barcode, or search — every bite you log helps Victoria cheer you on.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Same four options as the toolbar "＋", surfaced as a friendly,
            // filled brand-gradient pill so the empty state has an obvious,
            // inviting next step. (A real Button keeps the menu's tap reliable.)
            Menu {
                Button { open(.recents) } label: { Label("Recents & favorites", systemImage: "clock.arrow.circlepath") }
                Button { open(.photo) }   label: { Label("Snap or describe a meal", systemImage: "camera.fill") }
                Button { open(.barcode) } label: { Label("Scan barcode", systemImage: "barcode.viewfinder") }
                Button { open(.label) }   label: { Label("Scan a label", systemImage: "doc.text.viewfinder") }
                Button { open(.manual) }  label: { Label("Add manually", systemImage: "square.and.pencil") }
            } label: {
                Label("Log your first bite", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, 13)
                    .background(Theme.brandGradient,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
            }
            .padding(.top, Theme.Space.xs)
            .accessibilityLabel("Add food")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.lg)
        .cardElevated()
    }

    /// A past day with nothing on it — friendly nudge back to today.
    private var pastDayEmptyState: some View {
        VStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle()
                    .fill(Theme.brandSoft)
                    .frame(width: 64, height: 64)
                Image(systemName: "fork.knife")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .wiggle()
            }
            Text("A quiet day here 🌙")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Nothing logged. Tap ＋ to add what you ate, or use ▶ to hop back to today.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.lg)
        .cardElevated()
    }

    // MARK: Add menu

    private var addMenu: some View {
        Menu {
            Button { open(.recents) } label: { Label("Recents & favorites", systemImage: "clock.arrow.circlepath") }
            Button { open(.photo) }   label: { Label("Snap or describe a meal", systemImage: "camera.fill") }
            Button { open(.barcode) } label: { Label("Scan barcode", systemImage: "barcode.viewfinder") }
            Button { open(.label) }   label: { Label("Scan a label", systemImage: "doc.text.viewfinder") }
            Button { open(.manual) }  label: { Label("Add manually", systemImage: "square.and.pencil") }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.brand)
        }
        .accessibilityLabel("Add food")
    }

    /// Opens an add-flow, optionally targeting a specific meal (otherwise the flow
    /// picks the meal from the time of day).
    private func open(_ which: FoodSheet, for meal: MealType? = nil) {
        addTick += 1
        preferredMeal = meal
        sheet = which
    }

    private var mealChooserTitle: String {
        preferredMeal.map { "Add to \($0.label)" } ?? "Add food"
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            // Hero: fuel TOWARD the goal, not a draining "budget". Once she's
            // reached ~97%+, celebrate "Fueled!" with no "over" number to dwell on.
            if reachedFuel {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.brand)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Fueled!")
                            .font(Theme.number(34).weight(.bold))
                            .foregroundStyle(Theme.brand)
                        Text(isOver ? "fully fueled 💛" : "goal reached 🎉")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                    Text("\(Int(max(0, remaining).rounded()))")
                        .font(Theme.number(40).weight(.bold))
                        .foregroundStyle(Theme.calories)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: remaining)
                    Text("kcal to go")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
            }

            // A warm, non-shaming one-liner about how the day's going.
            Text(summaryMessage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            progressBar

            // Eaten / target footing.
            HStack {
                footStat("Eaten", value: consumed, tint: Theme.textPrimary)
                Spacer()
                footStat("Goal", value: target, tint: Theme.textSecondary)
            }
        }
        .cardElevated()
    }

    /// Kind, encouraging status copy keyed off the day's progress. Never shames
    /// going over — just a gentle, friendly note.
    private var summaryMessage: String {
        if consumed <= 0 {
            return isViewingToday ? "Fresh start — let's fill this in 🌱" : "Nothing logged this day"
        }
        if reachedFuel && !isOver { return "You hit your fuel goal — amazing 💚" }
        if isOver { return "A little over today — tomorrow's a clean slate 💛" }
        if progress >= 0.85 { return "So close — almost fully fueled! 🎯" }
        if progress >= 0.5 { return "Nice and steady — keep fueling 💚" }
        return "Great start — plenty more to enjoy 🍽️"
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(ringColor)
                    .frame(width: max(0, min(1, progress)) * geo.size.width)
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
            }
        }
        .frame(height: 10)
    }

    private func footStat(_ title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 3) {
                Text("\(Int(value.rounded()))")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)
                Text("kcal").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: Meal section

    private func entries(for meal: MealType) -> [FoodEntry] {
        dayEntries.filter { $0.mealType == meal }.sorted { $0.date < $1.date }
    }

    private func mealCard(_ meal: MealType) -> some View {
        let items = entries(for: meal)
        let subtotal = items.reduce(0) { $0 + $1.totalCalories }
        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            mealHeader(meal, subtotal: subtotal, isEmpty: items.isEmpty)

            if items.isEmpty {
                // Tappable: drops straight into adding for THIS meal (was inert text).
                Button {
                    preferredMeal = meal
                    showMealChooser = true
                } label: {
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: "plus.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.brand)
                        Text(emptyMealPrompt(meal))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Space.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to \(meal.label)")
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Divider().background(Theme.divider)
                    }
                    FoodRow(
                        entry: entry,
                        onOpen: { detailEntry = entry },
                        onEdit: { editingEntry = entry },
                        onDelete: { delete(entry) },
                        onAskVita: { askVita?.ask(askVitaTopic(for: entry)) }
                    )
                }
            }
        }
        .cardElevated()
    }

    /// A warm, meal-specific nudge for an empty meal section.
    private func emptyMealPrompt(_ meal: MealType) -> String {
        switch meal {
        case .breakfast: return "What's for breakfast? ☀️"
        case .lunch:     return "Add your lunch when you're ready 🥗"
        case .dinner:    return "Dinner goes here 🌙"
        case .snack:     return "Any little snacks? 🍓"
        }
    }

    private func mealHeader(_ meal: MealType, subtotal: Double, isEmpty: Bool) -> some View {
        HStack(spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: meal.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 30, height: 30)
                    .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                Text(meal.label)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                HStack(spacing: 3) {
                    Text("\(Int(subtotal.rounded()))")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(isEmpty ? Theme.textSecondary : Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: subtotal)
                    Text("kcal").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(meal.label), \(Int(subtotal.rounded())) calories")

            // Quick add straight into this meal.
            Button {
                preferredMeal = meal
                showMealChooser = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.brand)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to \(meal.label)")
        }
    }

    // MARK: Mutations

    private func delete(_ entry: FoodEntry) {
        deleteTick += 1
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            context.delete(entry)
            try? context.save()
        }
    }
}

// MARK: - Food row

/// A single logged-food row. A freshly-added row (created seconds ago) springs in
/// with a `.popIn` for a satisfying "just added!" feel; existing rows render
/// normally. Owns a private `appeared` flag so only the new row animates.
private struct FoodRow: View {
    let entry: FoodEntry
    var onOpen: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onAskVita: () -> Void

    @Environment(AskVitaCenter.self) private var askVitaCenter: AskVitaCenter?
    @State private var appeared = false

    /// A row is "fresh" if it was created within the last few seconds — i.e. she
    /// just logged it. Derived purely from data (no cross-view state race), so
    /// only the genuinely-new row springs in; existing/historical rows don't.
    private var isFresh: Bool { Date.now.timeIntervalSince(entry.createdAt) < 3 }

    /// Existing rows are shown full-size immediately; a freshly-added row stays
    /// small until `appeared` flips, giving the springy `.popIn` entrance.
    private var popActive: Bool { isFresh ? appeared : true }

    var body: some View {
        // The whole row is one tappable control → the detail card. The trailing
        // chevron signals it's actionable (the old "−" read as "subtract" and was
        // the only affordance — confusing). Delete/Edit/Ask Vita live in the long-press.
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if !entry.servingDescription.isEmpty {
                        Text(entry.servingDescription)
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Theme.Space.sm)
                Text("\(Int(entry.totalCalories.rounded()))")
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.4))
            }
            .padding(.vertical, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Only the just-added row pops in; others appear instantly.
        .popIn(popActive)
        .onAppear { appeared = true }
        .contextMenu {
            Button(action: onOpen) { Label("View details", systemImage: "info.circle") }
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
            if askVitaCenter != nil {
                Button(action: onAskVita) { Label("Ask Vita about this", systemImage: "sparkles") }
            }
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(Int(entry.totalCalories.rounded())) calories")
        .accessibilityHint("Opens details")
        .accessibilityAction(named: "Edit", onEdit)
        .accessibilityAction(named: "Delete", onDelete)
    }
}
