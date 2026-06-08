import SwiftUI
import SwiftData

/// "More" — the app's Settings hub. A native insetGrouped Form rendered over the
/// dark canvas: a small profile header, editable profile fields, a steps goal
/// control, live (read-only) calorie/macro targets, the Anthropic key, and links
/// out to Reminders / Health.
struct SettingsView: View {
    @Bindable var profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    /// Holds the just-generated backup file so a share sheet can present it.
    @State private var exportItem: ExportItem?

    private struct ExportItem: Identifiable { let id = UUID(); let url: URL }

    // Weight history, used to derive the current trend for live target math.
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    #if DEBUG
    /// Status line for the dev-only CloudKit schema seeder (see `developerSection`).
    @State private var seedStatus: String?
    /// Multi-line result of the dev-only CloudKit diagnostic.
    @State private var diagStatus: String?
    #endif

    /// Current weight for target math: smoothed trend, falling back to start weight.
    private var currentWeightLbs: Double {
        TrendCalculator.currentTrend(weights) ?? (profile.startWeightLbs > 0 ? profile.startWeightLbs : 150)
    }

    private var calorieGoal: NutritionMath.CalorieGoal {
        profile.calorieGoal(weightLbs: currentWeightLbs)
    }

    /// The EFFECTIVE daily calorie target she actually eats to — the plan's number when a plan is
    /// active (mirrored into the override), else the computed goal. Macros already honor the override.
    private var effectiveCalories: Int { Int(profile.dailyCalorieTarget(weightLbs: currentWeightLbs)) }
    /// True when the adaptive plan is driving the targets (so the footer can say so).
    private var planDrivesTargets: Bool { profile.calorieTargetOverride > 0 }

    private var macros: NutritionMath.Macros {
        profile.macroTargets(weightLbs: currentWeightLbs)
    }

    var body: some View {
        NavigationStack {
            Form {
                profileHeaderSection
                youSection
                bioSection
                stepsSection
                waterSection
                targetsSection
                aiSection
                connectionsSection
                buddySection
                #if DEBUG
                developerSection
                #endif
                dataSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(Theme.brand)
        .sheet(item: $exportItem) { item in
            ActivityShareSheet(items: [item.url])
        }
    }

    // MARK: - Your data

    private var dataSection: some View {
        Section {
            Button {
                if let url = DataExport.makeBackup(context: context, profile: profile) {
                    exportItem = ExportItem(url: url)
                }
            } label: {
                row(icon: "square.and.arrow.up") {
                    Text("Export a backup")
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
            }
        } header: {
            sectionHeader("Your data")
        } footer: {
            footer("Saves everything you've logged to a file you can keep or AirDrop to yourself. Your data lives only on this phone — a backup means a reinstall can never lose it.")
        }
    }

    // MARK: - Profile header

    private var profileHeaderSection: some View {
        Section {
            HStack(spacing: Theme.Space.md) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(paceSummary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Space.xs)
            .listRowBackground(Theme.card)
        }
    }

    private var avatar: some View {
        // The pixel companion — same character shown on the Dashboard pfp button, not a flat initial.
        Group {
            switch profile.companionAvatar {
            case .bryan:    PixelArtView(rows: PixelBryan.rows(mood: .happy, eyesOpen: true), palette: PixelBryan.palette)
            case .victoria: PixelArtView(rows: PixelVictoria.rows(mood: .happy, eyesOpen: true), palette: PixelVictoria.palette)
            }
        }
        .frame(width: 34, height: 41)
        .frame(width: 52, height: 52)
        .background(Theme.brandSoft, in: Circle())
        .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var displayName: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Your profile" : trimmed
    }

    private var paceSummary: String {
        "\(profile.pace.label) · goal \(Int(profile.goalWeightLbs)) lb"
    }

    /// Reads/writes the goal DIRECTION via the persisted pace. Changing direction
    /// snaps the pace to the first option for that direction (e.g. switching to Gain
    /// selects Lean gain), keeping pace + direction always consistent. The pace
    /// itself remains the single stored source of truth (`profile.pace`).
    private var goalDirectionBinding: Binding<GoalPace.Direction> {
        Binding(
            get: { profile.pace.direction },
            set: { newDirection in
                guard newDirection != profile.pace.direction else { return }
                // Pick the gentlest pace that actually moves weight in the new
                // direction (gain → Lean gain, not the always-listed Maintain).
                profile.pace = GoalPace.paces(for: newDirection)
                    .first { $0.direction == newDirection } ?? .maintain
            }
        )
    }

    /// Non-optional view over `profile.homeGym` for the Settings picker: an unset gym reads as
    /// `.usc` (the app's primary persona) so a valid option is always selected, and choosing one
    /// writes through to the stored optional.
    private var homeGymBinding: Binding<HomeGym> {
        Binding(
            get: { profile.homeGym ?? .usc },
            set: { profile.homeGym = $0 }
        )
    }

    // MARK: - You

    private var youSection: some View {
        Section {
            row(icon: "person.fill") {
                LabeledContent("Name") {
                    TextField("Your name", text: $profile.name)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.words)
                }
            }

            row(icon: "figure.stand") {
                Picker("Sex", selection: $profile.sex) {
                    ForEach(BiologicalSex.allCases) { sex in
                        Text(sex.label).tag(sex)
                    }
                }
            }

            row(icon: "figure.walk.motion") {
                Picker("Activity", selection: $profile.activityLevel) {
                    ForEach(ActivityLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
            }

            row(icon: "target") {
                Picker("Goal", selection: goalDirectionBinding) {
                    Text("Lose").tag(GoalPace.Direction.lose)
                    Text("Maintain").tag(GoalPace.Direction.maintain)
                    Text("Gain").tag(GoalPace.Direction.gain)
                }
            }

            // Pace options are scoped to the chosen goal direction, so flipping to
            // "Gain" surfaces the lean-gain paces (and hides the loss ones).
            row(icon: "speedometer") {
                Picker("Pace", selection: $profile.pace) {
                    ForEach(GoalPace.paces(for: profile.pace.direction)) { pace in
                        Text(pace.label).tag(pace)
                    }
                }
            }

            row(icon: "flag.checkered") {
                Stepper(value: $profile.goalWeightLbs, in: 70...500, step: 1) {
                    LabeledContent("Goal weight") {
                        Text("\(Int(profile.goalWeightLbs)) lb")
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }
            }

            row(icon: "paintbrush.pointed.fill") {
                Picker("Appearance", selection: $profile.themeStyle) {
                    ForEach(ThemeStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
            }

            NavigationLink {
                AppIconPickerView()
            } label: {
                navRow(icon: "app.badge.fill", title: "App Icon")
            }

            // Which pixel character is your companion (and your buddy avatar).
            row(icon: "person.crop.circle.fill") {
                Picker("Companion", selection: $profile.companionAvatar) {
                    Text("Victoria").tag(CompanionAvatar.victoria)
                    Text("Bryan").tag(CompanionAvatar.bryan)
                }
            }

            // Your primary gym — used to show machine photos + personalize advice. (Doesn't change
            // which machines are listed; the catalog stays the same.)
            row(icon: "dumbbell.fill") {
                Picker("Home gym", selection: homeGymBinding) {
                    ForEach(HomeGym.allCases) { gym in
                        Text(gym.label).tag(gym)
                    }
                }
            }

            row(icon: "sparkles") {
                LabeledContent("Coach name") {
                    TextField("Coach", text: $profile.coachName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.words)
                }
            }
        } header: {
            sectionHeader("You")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Steps & activity

    /// An editable, free-text bio Vita actually reads (woven into the coach's context via
    /// `CoachContext.bioLine`). This is the "the app understands you, it's not just a database"
    /// touch — she tells it about herself once and every reply can reflect it.
    private var bioSection: some View {
        let coach = profile.coachName.isEmpty ? "Vita" : profile.coachName
        return Section {
            TextField("e.g. I'm a busy nurse, weekends are hard, I love spicy food, salads bore me…",
                      text: $profile.onboardingNote, axis: .vertical)
                // No upper line cap — the field grows to show the WHOLE profile (the plan now writes a
                // multi-sentence summary here), instead of clipping it into a tiny internal scroll.
                .lineLimit(3...)
                .foregroundStyle(Theme.textPrimary)
        } header: {
            sectionHeader("About you")
        } footer: {
            footer("Tell \(coach) about yourself — your routine, what you like, what's hard. \(coach) keeps this in mind so advice feels personal, not generic.")
        }
        .listRowBackground(Theme.card)
    }

    private var stepsSection: some View {
        Section {
            row(icon: "shoeprints.fill") {
                Stepper(value: $profile.dailyStepGoal, in: 4000...20000, step: 500) {
                    LabeledContent("Daily step goal") {
                        Text(Self.stepFormat(profile.dailyStepGoal))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }
            }

            row(icon: "flame.fill") {
                Toggle("Let steps add to my budget", isOn: $profile.stepsAdjustCalories)
            }
        } header: {
            sectionHeader("Steps & activity")
        } footer: {
            footer("When on, steps you walk above your baseline add a little to your daily calorie budget.")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Water

    /// What "one drink" means, offered as friendly presets (no ounce math for her).
    private static let waterContainers: [(label: String, oz: Double, icon: String)] = [
        ("glass", 8, "cup.and.saucer.fill"),
        ("bottle", 16.9, "waterbottle.fill"),
        ("big bottle", 32, "waterbottle.fill"),
    ]

    private var waterGoalBinding: Binding<Double> {
        Binding(
            get: { profile.waterTargetOz },
            set: { profile.waterGoalOzOverride = $0 }   // setting an explicit goal turns off auto
        )
    }

    private var waterSection: some View {
        Section {
            // Units (oz / mL) — affects display + input only; storage stays canonical oz.
            row(icon: "ruler", tint: Theme.water) {
                Picker("Units", selection: Binding(get: { profile.waterUnit },
                                                   set: { profile.waterUnit = $0 })) {
                    ForEach(WaterUnit.allCases) { u in Text(u.label).tag(u) }
                }
                .pickerStyle(.segmented)
            }
            // Pick the container she actually drinks from.
            row(icon: "drop.fill", tint: Theme.water) {
                Picker("One drink is a", selection: containerBinding) {
                    ForEach(Self.waterContainers, id: \.label) { c in
                        Text("\(c.label.capitalized) (\(profile.waterAmount(c.oz)))").tag(c.label)
                    }
                }
            }

            // Goal expressed in her containers, not ounces.
            row(icon: "target", tint: Theme.water) {
                Stepper(value: waterGoalBinding,
                        in: profile.waterContainerOz...(profile.waterContainerOz * 16),
                        step: profile.waterContainerOz) {
                    LabeledContent("Daily goal") {
                        Text("\(profile.waterGoalContainers) \(profile.waterContainerLabel)s")
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                }
            }

            if profile.waterGoalOzOverride > 0 {
                Button("Reset to recommended (\(profile.waterAmount(NutritionMath.dailyWaterOz(weightLbs: currentWeightLbs))))") {
                    profile.waterGoalOzOverride = 0
                }
                .foregroundStyle(Theme.water)
            }
        } header: {
            sectionHeader("Water")
        } footer: {
            footer("Tap the + on the Water card to log one \(profile.waterContainerLabel). Goal ≈ \(profile.waterAmount(profile.waterTargetOz)) a day.")
        }
        .listRowBackground(Theme.card)
    }

    /// Choosing a container updates both its size and label together.
    private var containerBinding: Binding<String> {
        Binding(
            get: { profile.waterContainerLabel },
            set: { label in
                if let c = Self.waterContainers.first(where: { $0.label == label }) {
                    profile.waterContainerLabel = c.label
                    profile.waterContainerOz = c.oz
                }
            }
        )
    }

    // MARK: - Daily targets (read-only, computed)

    private var targetsSection: some View {
        Section {
            row(icon: "fork.knife") {
                LabeledContent("Calories") {
                    Text("\(effectiveCalories) kcal")
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
            }
            row(icon: "p.circle.fill", tint: Theme.protein) {
                macroRow(label: "Protein", grams: macros.proteinG)
            }
            row(icon: "c.circle.fill", tint: Theme.carbs) {
                macroRow(label: "Carbs", grams: macros.carbsG)
            }
            row(icon: "f.circle.fill", tint: Theme.fat) {
                macroRow(label: "Fat", grams: macros.fatG)
            }
        } header: {
            sectionHeader("Your daily targets")
        } footer: {
            if planDrivesTargets {
                footer("Set by your adaptive plan — these adapt as the plan does. (Calories are kept at or above a safe minimum.)")
            } else if calorieGoal.wasClampedToFloor {
                footer("Adjusted up to a safe minimum — we never recommend going lower. Targets update with your weight and plan.")
            } else {
                footer("Calculated from your weight. Updates automatically as you log.")
            }
        }
        .listRowBackground(Theme.card)
    }

    private func macroRow(label: String, grams: Double) -> some View {
        LabeledContent(label) {
            Text("\(Int(grams)) g")
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        Section {
            NavigationLink {
                AIProviderSettingsView()
            } label: {
                navRow(icon: "brain.head.profile", title: "AI Provider")
            }
        } header: {
            sectionHeader("AI")
        } footer: {
            footer("Choose your provider (Anthropic or OpenAI) and add your key. It’s stored only in this device’s Keychain and powers meal-photo estimates and your coach.")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Reminders & Health

    private var connectionsSection: some View {
        Section {
            NavigationLink {
                RemindersSettingsView(profile: profile)
            } label: {
                navRow(icon: "bell.badge.fill", title: "Reminders")
            }

            NavigationLink {
                HealthSettingsView(profile: profile)
            } label: {
                navRow(icon: "heart.fill", title: "Apple Health")
            }
        } header: {
            sectionHeader("Reminders & Health")
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Buddy

    /// Opt-in to sharing the FULL daily picture with a paired buddy. Default on — this is
    /// for partners who've chosen to share everything. When off, a buddy sees only the safe
    /// activity face-off (steps/water/movement), never weight/calories/food.
    private var buddySection: some View {
        Section {
            row(icon: "person.2.fill") {
                Toggle("Share my full stats with your buddy",
                       isOn: $profile.shareFullStatsWithBuddy)
            }
        } header: {
            sectionHeader("Buddy")
        } footer: {
            footer("Lets your buddy see your weight, calories, and food — not just your activity.")
        }
        .listRowBackground(Theme.card)
    }

    #if DEBUG
    // MARK: - Developer (DEBUG only)

    /// One-tap CloudKit schema seeder. Run **once on a real iPhone** (not the Simulator —
    /// the buddy service uses a local mock there) to register every buddy record type +
    /// field in CloudKit's *Development* schema, so you can add the two `Nudge` indexes and
    /// Deploy to Production. See `BuddyViewModel.seedCloudKitSchemaForDev`.
    private var developerSection: some View {
        Section {
            Button {
                seedStatus = "Seeding…"
                Task { seedStatus = await BuddyViewModel().seedCloudKitSchemaForDev() }
            } label: {
                row(icon: "icloud.and.arrow.up.fill") {
                    Text("Seed CloudKit Schema")
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            if let seedStatus {
                Text(seedStatus)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                diagStatus = "Running CloudKit diagnostic…"
                Task { diagStatus = await BuddyViewModel().diagnoseCloudKitForDev() }
            } label: {
                row(icon: "stethoscope") {
                    Text("Diagnose CloudKit")
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            if let diagStatus {
                Text(diagStatus)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
            }
        } header: {
            sectionHeader("Developer")
        } footer: {
            footer("Run on a real iPhone. Seed registers the buddy record types in CloudKit Development; Diagnose shows the EXACT iCloud/CloudKit error the buddy flow otherwise hides. (No-op in the Simulator.)")
        }
        .listRowBackground(Theme.card)
    }
    #endif

    // MARK: - About

    /// Hidden diagnostics gate: 7 taps on the version line opens the log viewer
    /// (so we can pull field logs without exposing anything to the user).
    @State private var diagTapCount = 0
    @State private var showDiagnostics = false

    private var aboutSection: some View {
        Section {
            VStack(spacing: 6) {
                Text("Estimates only — not medical advice.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Text(versionLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        diagTapCount += 1
                        if diagTapCount >= 7 { diagTapCount = 0; showDiagnostics = true }
                    }
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
        }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
    }

    private var versionLine: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Sprout \(v) (\(b))"
    }

    // MARK: - Row helpers

    /// A form row with a leading tinted SF Symbol icon and trailing content.
    private func row<Content: View>(icon: String,
                                    tint: Color = Theme.brand,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: Theme.Space.md) {
            iconBadge(icon, tint: tint)
            content()
        }
    }

    private func navRow(icon: String, title: String) -> some View {
        HStack(spacing: Theme.Space.md) {
            iconBadge(icon, tint: Theme.brand)
            Text(title)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func iconBadge(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 22, alignment: .center)
            .accessibilityHidden(true)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
    }

    /// Grouped thousands formatting for the step goal (e.g. "8,000").
    private static func stepFormat(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}
