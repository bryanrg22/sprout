import SwiftUI
import SwiftData

/// "Today's checklist" — a warm little planner on the dashboard for the day's
/// movement / wellness intentions (gym, run, a stretch, an early night). She taps to
/// check things off, gets a gentle "2 of 4 done" nudge, and a small celebration when the
/// list is clear. Quick-add chips (plus a custom field) make planning the day a tap.
///
/// Deliberately about **showing up**, never about restricting food or a number on the
/// scale — same anti-restriction tone as the rest of the app.
///
/// Personalized by Vita: when an API key is set, once a day she proposes a few morning
/// tasks AND quick-add chips drawn from this person's goal + recent training + life context
/// (so a soccer player sees "Soccer", a lifter sees "Leg day"). It degrades GRACEFULLY to
/// the static presets when there's no key or on ANY failure — the load never blocks the card
/// and never throws (same model as `WeeklyReflectionCard`). We never auto-insert the AI's
/// tasks (CloudKit dup risk across devices); the "Add these" tap is the deliberate accept.
struct ChecklistCard: View {
    /// Optional override; defaults to the warm standard title.
    var title: String = "Today's checklist"

    /// The person we personalize for. Optional so the `#Preview` (and any no-profile host)
    /// still works — nil simply keeps the static-preset behavior.
    var profile: UserProfile?

    @Environment(\.modelContext) private var context

    /// Sorted broadly by `sortOrder`; we filter to *today* in Swift (cheap, and keeps the
    /// query stable). A secondary sort by `day` keeps things deterministic across days.
    @Query(sort: [SortDescriptor(\ChecklistItem.sortOrder),
                  SortDescriptor(\ChecklistItem.day)])
    private var items: [ChecklistItem]

    // Data the personalized plan is built from — same sources the coach/weekly card @Query.
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    // Real workouts are `WorkoutSession`s from the Workouts tab; the legacy `WorkoutEntry` is
    // debug-only, so the daily plan never saw the user's training. Feed the AI the real sessions.
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query private var water: [WaterEntry]
    @Query private var memories: [CoachMemory]

    /// Presents the "Add your own" custom-task sheet.
    @State private var showCustomSheet = false
    /// Bumped on every check toggle so `.sensoryFeedback(.success)` fires a happy tap.
    @State private var toggleTick = 0

    /// Vita's personalized plan for today (nil until loaded; we start from the fallback so the
    /// chips are never empty). `loadingPlan` drives the shimmer while the AI call is in flight.
    @State private var plan: ChecklistPlan? = ChecklistPlanService.fallback()
    @State private var loadingPlan = false
    /// In the populated state, reveals the quick-add chip row inline (one consistent add UI).
    @State private var showAddChips = false

    // MARK: Derived

    /// Just today's tasks, in their manual order.
    private var todays: [ChecklistItem] {
        items
            .filter { Calendar.current.isDateInToday($0.day) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var doneCount: Int { todays.filter { $0.done }.count }
    private var allDone: Bool { !todays.isEmpty && doneCount == todays.count }

    /// The chips to offer — Vita's personalized set when we have one, else the static presets.
    /// Falls back the moment a plan is missing/empty so the row is never blank.
    private var chipProposals: [ChecklistProposal] {
        let chips = plan?.chips ?? []
        return chips.isEmpty ? ChecklistSuggestion.allProposals : chips
    }

    /// Vita's proposed morning tasks for today (only present when the AI returned some).
    private var proposedTasks: [ChecklistProposal] { plan?.tasks ?? [] }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            header

            if todays.isEmpty {
                emptyState
            } else {
                ForEach(todays) { item in
                    if item.id != todays.first?.id {
                        Divider().background(Theme.divider)
                    }
                    ChecklistRow(item: item,
                                 toggle: { toggle(item) },
                                 remove: { remove(item) })
                }
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .sensoryFeedback(.success, trigger: toggleTick)
        .sheet(isPresented: $showCustomSheet) {
            CustomTaskSheet { title in addCustom(title) }
        }
        // Build (or refresh) Vita's plan once per calendar day, per profile. Never blocks, never
        // throws — on no key / any failure we keep the static-preset fallback already in `plan`.
        .task(id: dayKey) { await loadPlan() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "checklist")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .frame(width: 30, height: 30)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            if !todays.isEmpty {
                Text("\(doneCount) of \(todays.count) done")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(allDone ? Theme.positive : Theme.textSecondary)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer (progress celebration + add)

    @ViewBuilder
    private var footer: some View {
        if allDone {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.positive)
                Text("All done — amazing! 🎉")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.positive)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            .transition(.opacity)
        }
        addMore
            .padding(.top, 2)
    }

    /// The "add more" affordance shown once there are items. Tapping reveals the SAME
    /// personalized quick-add chip row used in the empty state (Vita's chips when we have
    /// them, else the presets) + an "Add your own" chip — one consistent add interaction in
    /// both states (this replaces the old dropdown Menu, fixing the two-different-UIs problem).
    @ViewBuilder
    private var addMore: some View {
        if showAddChips {
            personalizedChips
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showAddChips = true }
            } label: {
                Label("Add task", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.brand)
            }
            .buttonStyle(.plain)
            .bouncyPress()
            .accessibilityLabel("Add a task to today's checklist")
        }
    }

    // MARK: Empty state

    /// The blank-slate state. Three shapes, in priority order:
    ///  1. Vita PROPOSED tasks → a "Vita's plan for today" section with a one-tap "Add these",
    ///     followed by the personalized quick-add chips for à-la-carte planning.
    ///  2. Vita's plan is still loading → a gentle shimmer placeholder.
    ///  3. No key / fallback → the warm preset blank slate (today's behavior).
    @ViewBuilder
    private var emptyState: some View {
        if !proposedTasks.isEmpty {
            vitaPlanState
        } else if loadingPlan {
            loadingState
        } else {
            presetEmptyState
        }
    }

    /// Vita's morning proposal: a header, the few suggested tasks, a primary "Add these"
    /// button that inserts them ALL (the deliberate accept — we never auto-insert), then the
    /// personalized chips for adding individual things.
    private var vitaPlanState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                ZStack {
                    Circle().fill(Theme.brandSoft).frame(width: 44, height: 44)
                    Text("✨").font(.system(size: 22)).breathing()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(coachName)'s plan for today ✨")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("A few things to show up for — add what fits.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // The proposed tasks as quiet preview rows (icon disc + title), so she sees the
            // plan before accepting it.
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(proposedTasks) { t in
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: t.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.brand)
                            .frame(width: 30, height: 30)
                            .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                        Text(t.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            // Primary accept: insert every proposed task in one tap.
            Button { addProposedTasks() } label: {
                Text("Add these")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.brandGradient,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .bouncyPress()
            .accessibilityLabel("Add \(coachName)'s \(proposedTasks.count) suggested tasks to today")

            personalizedChips
        }
        .padding(.vertical, 2)
    }

    /// Warm, inviting blank slate (no AI plan) — a gently breathing sparkle, an encouraging
    /// line, the preset chips, and an "Add your own" option. Same tone as the Food empty state.
    private var presetEmptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                ZStack {
                    Circle().fill(Theme.brandSoft).frame(width: 44, height: 44)
                    Text("✨").font(.system(size: 22)).breathing()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan your day ✨")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Add a few things you want to hit today.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            personalizedChips
        }
        .padding(.vertical, 2)
    }

    /// Gentle "\(coachName) is planning…" placeholder while the AI call is in flight: a header
    /// plus shimmering skeleton chip rows, so the card reads as composing rather than empty.
    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                ZStack {
                    Circle().fill(Theme.brandSoft).frame(width: 44, height: 44)
                    Text("✨").font(.system(size: 22)).breathing()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(coachName) is planning your day ✨")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("One sec — tailoring this to you.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ChecklistShimmerLine().frame(width: 200, height: 14)
                ChecklistShimmerLine().frame(width: 150, height: 14)
                ChecklistShimmerLine().frame(width: 180, height: 14)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
        .accessibilityLabel("\(coachName) is planning your day")
    }

    /// The quick-add chips — Vita's personalized set when we have one, else the presets — as
    /// tappable brand-soft chips, with an "Add your own" chip that opens the custom sheet.
    /// Wraps onto new lines at any width / Dynamic Type size. This is the SINGLE add UI, shared
    /// by the empty state and the populated "add more" reveal.
    private var personalizedChips: some View {
        ChecklistFlowLayout(spacing: Theme.Space.sm) {
            ForEach(chipProposals) { p in
                Button { addProposal(p) } label: {
                    chipLabel(p.title, icon: p.icon, filled: false)
                }
                .buttonStyle(.plain)
                .bouncyPress()
            }
            // Custom: a filled brand-gradient pill so the "your own" path stays inviting.
            Button { showCustomSheet = true } label: {
                chipLabel("Add your own", icon: "plus", filled: true)
            }
            .buttonStyle(.plain)
            .bouncyPress()
            .accessibilityLabel("Add your own task")
        }
    }

    /// A pill chip: soft brand wash by default, or a filled brand gradient for the
    /// primary "Add your own" action — both match the chip/CTA styles used elsewhere.
    private func chipLabel(_ text: String, icon: String, filled: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption.weight(.semibold))
            Text(text).font(.subheadline.weight(.medium))
        }
        .foregroundStyle(filled ? .white : Theme.textPrimary)
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background {
            if filled {
                Capsule().fill(Theme.brandGradient)
            } else {
                Capsule().fill(Theme.brandSoft)
            }
        }
        .overlay {
            if !filled {
                Capsule().strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1)
            }
        }
    }

    // MARK: Mutations

    /// Add one quick-add chip (a preset or one of Vita's personalized chips).
    private func addProposal(_ proposal: ChecklistProposal) {
        insert(title: proposal.title, icon: proposal.icon)
    }

    /// The deliberate accept of Vita's morning plan: insert every proposed task at once. We
    /// assign sort orders from the current count up so they keep the order she was shown them
    /// in (a single save). This is the ONLY path that adds the AI tasks — never automatic.
    private func addProposedTasks() {
        let tasks = proposedTasks
        guard !tasks.isEmpty else { return }
        let day = Calendar.current.startOfDay(for: .now)
        let base = todays.count
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            for (offset, t) in tasks.enumerated() {
                let item = ChecklistItem(title: t.title,
                                         systemIcon: t.icon,
                                         day: day,
                                         sortOrder: base + offset)
                context.insert(item)
            }
            try? context.save()
        }
    }

    private func addCustom(_ rawTitle: String) {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        insert(title: trimmed, icon: "checklist")
    }

    private func insert(title: String, icon: String) {
        let day = Calendar.current.startOfDay(for: .now)
        let item = ChecklistItem(title: title,
                                 systemIcon: icon,
                                 day: day,
                                 sortOrder: todays.count)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            context.insert(item)
            try? context.save()
        }
    }

    private func toggle(_ item: ChecklistItem) {
        toggleTick += 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            item.done.toggle()
            try? context.save()
        }
    }

    private func remove(_ item: ChecklistItem) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            context.delete(item)
            try? context.save()
        }
    }

    // MARK: - Personalized plan (Vita) — load + day cache

    /// Her coach's name for the warm copy (falls back to "Vita").
    private var coachName: String {
        let n = profile?.coachName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return n.isEmpty ? "Vita" : n
    }

    /// Per-profile, per-day key. Drives `.task(id:)` (a new day rebuilds) and the UserDefaults
    /// cache. "no-profile" keeps the preview/no-profile host on a stable, fallback-only key.
    private var dayKey: String {
        let pid = profile?.id.uuidString ?? "no-profile"
        return "vita.checklist.\(pid).\(Self.dayStamp.string(from: .now))"
    }

    /// Build (or reuse) today's personalized plan. Order of operations mirrors `WeeklyReflection`:
    /// start from the fallback (so chips always render), bail to fallback with NO network when
    /// there's no key, serve a same-day cache hit, otherwise call the model — and on ANY failure
    /// keep the fallback. Never throws, never blocks the card. Guards staleness on `dayKey` so a
    /// slow call that resolves after midnight (or a profile switch) can't commit to the wrong day.
    @MainActor
    private func loadPlan() async {
        let key = dayKey

        // No profile or no key → the static-preset fallback, and we never touch the network.
        guard let profile, AIConfig.hasActiveKey else {
            plan = ChecklistPlanService.fallback()
            loadingPlan = false
            return
        }

        // Same-day cache hit → use it (no network). Daily key means it naturally rolls over.
        if let cached = readCache(key) {
            plan = cached
            loadingPlan = false
            return
        }

        // Otherwise generate. Keep the fallback chips visible behind the shimmer.
        loadingPlan = true
        do {
            let fresh = try await ChecklistPlanService.make(
                profile: profile,
                foods: foods,
                weights: weights,
                sessions: sessions,
                water: water,
                memory: memories.first
            )
            // Guard against a stale task (day rolled over / profile changed mid-flight).
            guard key == dayKey else { return }
            writeCache(fresh, key: key)
            plan = fresh
        } catch {
            // No key mid-flight, network, parse, or guardrail rejection — keep the fallback.
            guard key == dayKey else { return }
            plan = ChecklistPlanService.fallback()
        }
        loadingPlan = false
    }

    // MARK: Cache (UserDefaults, keyed by profile + day)

    private func readCache(_ key: String) -> ChecklistPlan? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ChecklistPlan.self, from: data) else { return nil }
        return decoded
    }

    private func writeCache(_ plan: ChecklistPlan, key: String) {
        guard let data = try? JSONEncoder().encode(plan) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// POSIX yyyy-MM-dd day stamp for the cache key (locale-independent so the bucket is stable).
    private static let dayStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Row

/// A single checklist row: a tappable circular checkbox, the task's icon in a soft tinted
/// disc, and the title (struck through + dimmed once done). Tapping anywhere toggles it.
private struct ChecklistRow: View {
    let item: ChecklistItem
    let toggle: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.done ? Theme.positive : Theme.textSecondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))

                Image(systemName: item.systemIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 30, height: 30)
                    .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                    .opacity(item.done ? 0.55 : 1)

                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(item.done ? Theme.textSecondary : Theme.textPrimary)
                    .strikethrough(item.done, color: Theme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bouncyPress()
        // Swipe to remove (works when the card is hosted in a List); the long-press
        // context menu below is the always-available fallback in a ScrollView.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: remove) {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: remove) {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.done ? "done" : "not done")")
        .accessibilityHint("Double-tap to toggle")
        .accessibilityAction(named: "Remove", remove)
    }
}

// MARK: - Custom task sheet

/// A tiny sheet to type a custom task title. Warm, minimal, on-theme; commits on "Add".
private struct CustomTaskSheet: View {
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool { !trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("What do you want to do today?")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)

                TextField("e.g. Evening walk", text: $text)
                    .font(.body)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .padding(Theme.Space.md)
                    .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1))

                Button(action: commit) {
                    Text("Add to checklist")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.brandGradient,
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
                        .opacity(canAdd ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .bouncyPress()
                .disabled(!canAdd)

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add a task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(260), .medium])
        .presentationDragIndicator(.visible)
    }

    private func commit() {
        guard canAdd else { return }
        onAdd(trimmed)
        dismiss()
    }
}

// MARK: - Flow layout (chip wrapping)

/// Minimal wrapping layout so the quick-add chips flow onto new lines instead of
/// overflowing — correct at any width / Dynamic Type size. (A self-contained copy: the
/// app's other flow layout is `private` to its own file, so this card stays standalone.)
private struct ChecklistFlowLayout: Layout {
    var spacing: CGFloat = Theme.Space.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Shimmer placeholder line

/// A single rounded "skeleton" line with a soft sheen sweeping across it — the universal
/// "content is loading" cue, used by the personalized-plan loading state. A self-contained
/// copy of the dashboard's `ShimmerLine` (which is file-private there), same recipe + timing,
/// and it respects Reduce Motion (falls back to a static muted bar).
private struct ChecklistShimmerLine: View {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let base = Theme.textSecondary.opacity(0.18)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(base)
                .overlay {
                    if !reduceMotion {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Theme.textSecondary.opacity(0.28), .clear],
                                    startPoint: .leading, endPoint: .trailing)
                            )
                            .offset(x: phase * geo.size.width)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                        phase = 1.2
                    }
                }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ChecklistCard()
            .padding()
    }
    .background(Theme.background.ignoresSafeArea())
    .modelContainer(for: [ChecklistItem.self, FoodEntry.self, WeightEntry.self,
                          WorkoutSession.self, WaterEntry.self, CoachMemory.self],
                    inMemory: true)
}
