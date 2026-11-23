import SwiftUI
import Combine
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
    @Query(sort: \StepsEntry.date) private var stepsEntries: [StepsEntry]

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
    /// Start of "today" as of the last check, so a day change while the app sat in the
    /// background can be told apart from the user browsing to another day.
    @State private var lastKnownToday: Date = Calendar.current.startOfDay(for: .now)
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDatePicker = false

    private enum FoodSheet: Identifiable {
        case photo, scan, manual, recents
        var id: Int { hashValue }
    }

    // MARK: Day helpers

    private var cal: Calendar { Calendar.current }
    private var startOfToday: Date { cal.startOfDay(for: .now) }
    private var isViewingToday: Bool { cal.isDateInToday(selectedDay) }
    /// Can't log or browse into the future.
    private var canGoForward: Bool { selectedDay < startOfToday }
    /// The day the account began — there's no data before this, so browsing earlier is meaningless.
    private var accountStart: Date { min(cal.startOfDay(for: profile.createdAt), startOfToday) }
    /// Can't browse earlier than the account start.
    private var canGoBack: Bool { selectedDay > accountStart }

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
        let clamped = min(max(cal.startOfDay(for: next), accountStart), startOfToday)
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
    private var isOver: Bool { profile.calorieStatus(consumed: consumed, weightLbs: basisWeight) == .over }
    private var progress: Double { target > 0 ? consumed / target : 0 }
    private var ringColor: Color { isOver ? Theme.warning : Theme.calories }
    /// True once she's reached ~97%+ of her fuel goal. We celebrate "fueled up"
    /// rather than counting calories "remaining"/"over" — kinder for someone who
    /// tends to under-eat, and consistent with the Dashboard hero's framing.
    private var reachedFuel: Bool { profile.hasReachedCalorieGoal(consumed: consumed, weightLbs: basisWeight) }

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
            ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    dayNav
                    summaryCard
                    // Macros as goal rings, for any day.
                    macrosCard
                    // The rest of the label for the day: fiber, sugars, sodium and so on, each
                    // with how many of the day's foods the total covers.
                    if !dayEntries.isEmpty {
                        DayNutrientDetailCard(totals: NutrientTotals(dayEntries))
                            .id(Self.detailCardID)
                    }
                    // Steps + Water — each its own card (steps above water), with a goal ring.
                    stepsCard
                    waterCard
                    // Food logging comes FIRST so the suggestions never bury it.
                    if dayEntries.isEmpty && isViewingToday {
                        todayEmptyState
                    } else if dayEntries.isEmpty {
                        pastDayEmptyState
                    } else {
                        ForEach(meals) { mealCard($0) }
                    }
                    // Smart picks — moved BELOW the meals (was burying them), today only.
                    if isViewingToday {
                        SmartSuggestionsView(profile: profile)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, Theme.Space.xl)
            }
            .background(Theme.background.ignoresSafeArea())
            .scrollIndicators(.hidden)
            #if DEBUG
            .task { await applyDemoArguments(scroller) }
            #endif
            }
            // A subtle one-shot celebration for the first food logged today.
            .overlay(ConfettiBurst(trigger: firstLogConfetti).ignoresSafeArea())
            .navigationTitle("Nutrients")
            .toolbar { ToolbarItem(placement: .primaryAction) { addMenu } }
            .sheet(isPresented: $showWaterSheet) { WaterLogSheet(profile: profile) }
            .sheet(item: $sheet) { which in
                switch which {
                case .photo:   PhotoFoodFlow(date: selectedDay, preferredMeal: preferredMeal)
                case .scan:    ScanView(date: selectedDay, preferredMeal: preferredMeal)
                case .manual:  AddFoodSheet(draft: FoodDraft(meal: preferredMeal ?? MealTime.current()), date: selectedDay)
                case .recents: RecentFoodsSheet(date: selectedDay, preferredMeal: preferredMeal)
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
                Button("Scan") { open(.scan, for: preferredMeal) }
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
            .onAppear {
                if lastDayCount == nil { lastDayCount = dayEntries.count }
                followTodayIfTheDayChanged()
            }
            // The tab can stay alive across midnight (in the background, or simply left open).
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { followTodayIfTheDayChanged() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
                .receive(on: DispatchQueue.main)) { _ in followTodayIfTheDayChanged() }
        }
    }

    private static let detailCardID = "nutrientDetailCard"

    #if DEBUG
    /// DEBUG launch arguments that put this tab in a state worth a screenshot, since a
    /// simulator launch cannot tap: `--demo-food-detail <text>` opens the detail card of
    /// today's food whose name contains the text, `--demo-food-edit <text>` opens its edit
    /// sheet, and `--demo-scroll-nutrients` scrolls to the "More nutrients" card.
    @MainActor
    private func applyDemoArguments(_ scroller: ScrollViewProxy) async {
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        // Let the seeded rows arrive and the first layout settle.
        try? await Task.sleep(nanoseconds: 900_000_000)
        func entry(matching text: String) -> FoodEntry? {
            dayEntries.first { $0.name.localizedCaseInsensitiveContains(text) }
        }
        if arguments.contains("--demo-scroll-nutrients") {
            scroller.scrollTo(Self.detailCardID, anchor: .center)
        }
        if let text = value(after: "--demo-food-detail"), let found = entry(matching: text) {
            detailEntry = found
        } else if let text = value(after: "--demo-food-edit"), let found = entry(matching: text) {
            editingEntry = found
        }
    }
    #endif

    private func followTodayIfTheDayChanged() {
        let next = FoodLogDay.rolledForward(selected: selectedDay, lastKnownToday: lastKnownToday, now: .now)
        lastKnownToday = next.today
        if next.selected != selectedDay { selectedDay = next.selected }
    }

    // MARK: Day navigation

    private var dayNav: some View {
        HStack(spacing: Theme.Space.sm) {
            navChevron("chevron.left", enabled: canGoBack) { step(-1) }
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
                    set: { selectedDay = min(max(cal.startOfDay(for: $0), accountStart), startOfToday) }
                ),
                in: accountStart...startOfToday,
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
    // MARK: Steps (its own card, above water — same style she liked)

    /// Steps logged for the selected day (mirrored from Health), 0 if none.
    private var stepsForDay: Int {
        stepsEntries.first { cal.isDate($0.date, inSameDayAs: selectedDay) }?.count ?? 0
    }

    private var stepsCard: some View {
        let goal = max(profile.dailyStepGoal, 0)
        let steps = stepsForDay
        let pct = goal > 0 ? Double(steps) / Double(goal) : 0
        let reached = goal > 0 && steps >= Int(Double(goal) * 0.97)
        return HStack(spacing: Theme.Space.md) {
            ZStack {
                ProgressRing(progress: pct, lineWidth: 5, color: Theme.positive)
                    .frame(width: 44, height: 44)
                Image(systemName: "figure.walk").font(.subheadline).foregroundStyle(Theme.positive)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("Steps")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if reached {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(Theme.positive)
                    }
                }
                Text("\(steps.formatted()) of \(goal.formatted()) steps\(isViewingToday ? " today" : "")")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    /// Water logged on the selected day (today or a past day being browsed).
    private var waterForDay: Double {
        water.filter { cal.isDate($0.date, inSameDayAs: selectedDay) }.reduce(0) { $0 + $1.amountOz }
    }

    private var waterCard: some View {
        let goal = profile.waterTargetOz
        let amount = waterForDay
        let pct = goal > 0 ? amount / goal : 0
        let reached = goal > 0 && amount >= goal * 0.97
        return HStack(spacing: Theme.Space.md) {
            // A goal ring around the drop, so you can see if you hit your water target.
            ZStack {
                ProgressRing(progress: pct, lineWidth: 5, color: Theme.water)
                    .frame(width: 44, height: 44)
                Image(systemName: "drop.fill").font(.subheadline).foregroundStyle(Theme.water)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("Water")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if reached {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(Theme.water)
                    }
                }
                Text("\(profile.waterText(amount, goalOz: goal))\(isViewingToday ? " today" : "")")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            // Quick-add is today-only (water is logged for today); past days are read-only.
            if isViewingToday {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .contentShape(Rectangle())
        .onTapGesture { if isViewingToday { showWaterSheet = true } }
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
            Text("Snap a photo, scan a barcode, or search — every bite you log helps \(profile.coachName) cheer you on.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Same four options as the toolbar "＋", surfaced as a friendly,
            // filled brand-gradient pill so the empty state has an obvious,
            // inviting next step. (A real Button keeps the menu's tap reliable.)
            Menu { addMenuItems } label: {
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
        VStack(spacing: Theme.Space.md) {
            ZStack {
                Circle()
                    .fill(Theme.brandSoft)
                    .frame(width: 64, height: 64)
                Image(systemName: "fork.knife")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.brand)
                    .wiggle()
            }
            VStack(spacing: Theme.Space.xs) {
                Text("A quiet day here 🌙")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Nothing logged. Forgot to add what you ate? Add it for this day, or ask \(profile.coachName) to help.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Space.sm) {
                Menu { addMenuItems } label: {
                    Label("Add food", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Button { askToAddPastFood() } label: {
                    Label("Ask \(profile.coachName)", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                        .foregroundStyle(Theme.brand)
                }
                .buttonStyle(.plain)
                .disabled(askVita == nil)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.md)
        .cardElevated()
    }

    /// Deep-link the coach to help back-fill a forgotten meal for the day being viewed.
    private func askToAddPastFood() {
        askVita?.ask(AskVitaTopic(
            name: "Add a past meal",
            icon: "fork.knife",
            value: dayLabel,
            question: "I forgot to log what I ate on \(selectedDay.formatted(.dateTime.weekday(.wide).month().day())). Can you help me add it for that day? Ask me what I had, then log it."))
    }

    // MARK: Add menu

    /// The four add-food entry points — shared by the toolbar "＋", the empty-state pill, and the
    /// past-day card so all three offer the SAME choices (Recents / Snap / Scan / Add manually).
    @ViewBuilder private var addMenuItems: some View {
        Button { open(.recents) } label: { Label("Recents & favorites", systemImage: "clock.arrow.circlepath") }
        Button { open(.photo) }   label: { Label("Snap or describe a meal", systemImage: "camera.fill") }
        Button { open(.scan) }    label: { Label("Scan", systemImage: "barcode.viewfinder") }
        Button { open(.manual) }  label: { Label("Add manually", systemImage: "square.and.pencil") }
    }

    private var addMenu: some View {
        Menu { addMenuItems } label: {
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

    // MARK: Macros

    /// The selected day's macros — protein / carbs / fat totals — as a compact 3-column card right
    /// under the calorie summary. Shown for ANY day with food (so PAST-day macros are visible, the
    /// thing Victoria asked for), using the same colored-dot language as the food detail card.
    /// The selected day's macros as goal RINGS — protein / carbs / fat filling toward their targets,
    /// so you can SEE whether you hit each goal (alive + glanceable, vs the old flat numbers). Shown
    /// for ANY day with food (past days too — what Victoria asked for).
    @ViewBuilder
    private var macrosCard: some View {
        if !dayEntries.isEmpty {
            let targets = profile.macroTargets(weightLbs: basisWeight)
            let p = dayEntries.reduce(0) { $0 + $1.totalProteinG }
            let c = dayEntries.reduce(0) { $0 + $1.totalCarbsG }
            let f = dayEntries.reduce(0) { $0 + $1.totalFatG }
            HStack(spacing: Theme.Space.sm) {
                macroRing("Protein", value: p, target: targets.proteinG, color: Theme.protein)
                macroRing("Carbs", value: c, target: targets.carbsG, color: Theme.carbs)
                macroRing("Fat", value: f, target: targets.fatG, color: Theme.fat)
            }
            .frame(maxWidth: .infinity)
            .cardElevated()
        }
    }

    /// One macro goal ring: grams in the center, the ring filling toward the target, and a small ✓
    /// once the goal is reached (≥97%).
    private func macroRing(_ label: String, value: Double, target: Double, color: Color) -> some View {
        let pct = target > 0 ? value / target : 0
        let reached = target > 0 && value >= target * 0.97
        return VStack(spacing: 7) {
            ZStack {
                ProgressRing(progress: pct, lineWidth: 7, color: color)
                    .frame(width: 62, height: 62)
                VStack(spacing: -1) {
                    Text("\(Int(value.rounded()))")
                        .font(.headline.weight(.bold)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("g").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 4) {
                Text(label).font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
                if reached {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(color)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(Int(value.rounded())) of \(Int(target.rounded())) grams\(reached ? ", goal reached" : "")")
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
                footStatText("Goal", text: profile.calorieGoalText(weightLbs: basisWeight), tint: Theme.textSecondary)
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

    /// Like `footStat` but shows a pre-formatted string (e.g. the "1,580–1,750" goal range).
    private func footStatText(_ title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 3) {
                Text(text)
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(tint)
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
        case .other:     return "Anything else? 🍴"
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
