import SwiftUI
import SwiftData

/// The "Log a workout" sheet — the core flow, modeled on food logging (tap icons → save):
///
/// 1. **Pick the kind** (gym / run / walk / …) as a grid of chips.
/// 2. **Gym only — pick focuses** (Chest / Back / … ), multi-select. Focus never *locks*
///    machines; it only reorders + highlights the grid.
/// 3. **Tap the machines you did** — a wrapping grid of square icon tiles via
///    `MachineCatalog.ranked(history:)` (ALL machines shown; recents/most-used float up, the
///    selected focuses highlight). A tapped tile shows a ✓ and reveals an optional weight field
///    + reps/sets steppers prefilled to a comfy **3×10** (all editable / all optional). A
///    "＋ Add a machine" tile takes a custom name (Phase 1 = simple text; describe-to-Vita is P3).
/// 4. **Cardio kinds** (run / walk / cycle / swim / sport / yoga / other) skip focus + machines
///    and go straight to a simple **duration** entry.
///
/// "Save" inserts the `WorkoutSession` plus one `ExerciseEntry` per selected machine.
struct WorkoutLogFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// The user's exercise history, newest-first — feeds `MachineCatalog.ranked` so her recents
    /// surface first in the grid.
    @Query(sort: \WorkoutSession.date, order: .reverse) private var history: [ExerciseEntry]

    // MARK: Flow state

    private enum Step { case kind, focus, machines, cardio }
    @State private var step: Step = .kind

    @State private var kind: WorkoutKind = .gym
    @State private var focuses: Set<MuscleFocus> = []

    /// Per-machine selection + editable values, keyed by `Machine.key`. Presence = selected.
    @State private var picks: [String: ExercisePick] = [:]

    /// Custom (off-catalog) machines added via "＋ Add a machine", in add order.
    @State private var customs: [ExercisePick] = []

    /// Cardio duration (minutes), as editable text.
    @State private var durationText: String = ""

    /// Add-a-machine sheet.
    @State private var showAddCustom = false

    var body: some View {
        NavigationStack {
            content
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle(navTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .sheet(isPresented: $showAddCustom) {
                    AddMachineSheet { name in addCustom(named: name) }
                }
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .kind:     kindStep
        case .focus:    focusStep
        case .machines: machinesStep
        case .cardio:   cardioStep
        }
    }

    // 1. Kind --------------------------------------------------------------

    private var kindStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                stepHeading("What did you do?", "Pick the kind of workout.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Space.sm)],
                          spacing: Theme.Space.sm) {
                    ForEach(WorkoutKind.allCases) { k in
                        KindTile(kind: k, selected: kind == k) {
                            kind = k
                            advanceFromKind()
                        }
                    }
                }
            }
            .padding(Theme.Space.md)
        }
    }

    // 2. Focus (gym only) --------------------------------------------------

    private var focusStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                stepHeading("What did you focus on?",
                            "Tap any that fit — you're not locked in. (Optional.)")
                WorkoutFlowLayout(spacing: Theme.Space.sm) {
                    ForEach(MuscleFocus.allCases) { f in
                        Button { toggleFocus(f) } label: {
                            ChipLabel(text: f.label, icon: f.systemImage, filled: focuses.contains(f))
                        }
                        .buttonStyle(.plain)
                        .bouncyPress()
                    }
                }
            }
            .padding(Theme.Space.md)
        }
    }

    // 3. Machines (gym) ----------------------------------------------------

    /// Ranked once per render from history; the selected focuses only highlight + float matches up
    /// (they never hide anything), so everything stays tappable.
    private var rankedMachines: [Machine] {
        let ranked = MachineCatalog.ranked(history: history)
        guard !focuses.isEmpty else { return ranked }
        // Stable partition: focused machines first (keeping ranked order), then the rest.
        let focused = ranked.filter { focuses.contains($0.focus) }
        let others  = ranked.filter { !focuses.contains($0.focus) }
        return focused + others
    }

    private var machinesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                stepHeading("Tap the machines you did",
                            "Each one logs a comfy 3×10 — open it to set weight or tweak reps/sets.")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Theme.Space.sm)],
                          spacing: Theme.Space.sm) {
                    ForEach(rankedMachines) { machine in
                        MachineTile(machine: machine,
                                    selected: picks[machine.key] != nil,
                                    highlighted: focuses.contains(machine.focus)) {
                            toggleMachine(machine)
                        }
                    }
                    // "＋ Add a machine" tile.
                    AddTile { showAddCustom = true }
                }

                // Inline editors for every selected machine (catalog + custom), so weight / reps /
                // sets are adjustable right here without leaving the grid.
                if !selectedPicks.isEmpty {
                    VStack(spacing: Theme.Space.sm) {
                        ForEach(selectedPicks) { pick in
                            ExerciseEditor(pick: binding(for: pick),
                                           remove: { removePick(pick) })
                        }
                    }
                    .padding(.top, Theme.Space.xs)
                }
            }
            .padding(Theme.Space.md)
        }
    }

    // 4. Cardio ------------------------------------------------------------

    private var cardioStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                stepHeading("\(kind.label) — how long?",
                            "Just a rough duration is perfect. (Optional.)")
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: kind.systemImage)
                        .font(.headline)
                        .foregroundStyle(Theme.brand)
                        .frame(width: 38, height: 38)
                        .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                    TextField("Minutes", text: $durationText)
                        .keyboardType(.numberPad)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("min")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardElevated()
            }
            .padding(Theme.Space.md)
        }
    }

    // MARK: Shared heading

    private func stepHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Toolbar (Back / Cancel + Next / Save)

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if step == .kind {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Button { goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            switch step {
            case .kind:
                EmptyView()   // kind selection auto-advances
            case .focus:
                Button("Next") { step = .machines }
                    .fontWeight(.semibold)
            case .machines, .cardio:
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
    }

    private var navTitle: String {
        switch step {
        case .kind:     return "New workout"
        case .focus:    return "Focus"
        case .machines: return "Machines"
        case .cardio:   return kind.label
        }
    }

    // MARK: Derived

    /// All selected picks (catalog + custom) in a stable display order: catalog picks follow the
    /// ranked grid order, customs come after in add order.
    private var selectedPicks: [ExercisePick] {
        let catalog = rankedMachines.compactMap { picks[$0.key] }
        return catalog + customs
    }

    /// Gym can save with nothing logged (a session still counts as showing up); cardio is always
    /// saveable. So Save is always enabled — kept as a hook in case that ever tightens.
    private var canSave: Bool { true }

    // MARK: Navigation helpers

    private func advanceFromKind() {
        step = kind.isGym ? .focus : .cardio
    }

    private func goBack() {
        switch step {
        case .kind:     dismiss()
        case .focus:    step = .kind
        case .machines: step = .focus
        case .cardio:   step = .kind
        }
    }

    // MARK: Mutations

    private func toggleFocus(_ f: MuscleFocus) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if focuses.contains(f) { focuses.remove(f) } else { focuses.insert(f) }
        }
    }

    private func toggleMachine(_ m: Machine) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if picks[m.key] != nil {
                picks[m.key] = nil
            } else {
                picks[m.key] = ExercisePick(machineKey: m.key,
                                            displayName: m.name,
                                            iconName: m.icon)
            }
        }
    }

    private func addCustom(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        // Distinct, stable key so it round-trips in history without colliding with the catalog.
        let key = "custom_\(UUID().uuidString)"
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            customs.append(ExercisePick(machineKey: key, displayName: name, iconName: "dumbbell.fill"))
        }
    }

    /// Remove a selected pick (catalog → clear from `picks`; custom → drop from `customs`).
    private func removePick(_ pick: ExercisePick) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if picks[pick.machineKey] != nil {
                picks[pick.machineKey] = nil
            } else {
                customs.removeAll { $0.id == pick.id }
            }
        }
    }

    /// A two-way binding into whichever store (`picks` or `customs`) owns this pick, so the inline
    /// editor edits the live value.
    private func binding(for pick: ExercisePick) -> Binding<ExercisePick> {
        if picks[pick.machineKey] != nil {
            return Binding(
                get: { picks[pick.machineKey] ?? pick },
                set: { picks[pick.machineKey] = $0 }
            )
        } else {
            return Binding(
                get: { customs.first(where: { $0.id == pick.id }) ?? pick },
                set: { newValue in
                    if let i = customs.firstIndex(where: { $0.id == pick.id }) { customs[i] = newValue }
                }
            )
        }
    }

    private func save() {
        // Preserve time-of-day for ordering; day-comparisons still work via Calendar.
        let session = WorkoutSession(date: .now,
                                     kind: kind,
                                     focuses: kind.isGym ? orderedFocuses : [],
                                     durationMinutes: parsedDuration,
                                     notes: "")
        context.insert(session)

        if kind.isGym {
            for pick in selectedPicks {
                let entry = ExerciseEntry(sessionID: session.id,
                                          machineKey: pick.machineKey,
                                          displayName: pick.displayName,
                                          iconName: pick.iconName,
                                          weightLbs: pick.weightLbs,
                                          reps: pick.reps,
                                          sets: pick.sets)
                context.insert(entry)
            }
        }
        try? context.save()
        dismiss()
    }

    /// Focuses in canonical `MuscleFocus` order (so storage is deterministic regardless of tap
    /// order), filtered to the ones selected.
    private var orderedFocuses: [MuscleFocus] {
        MuscleFocus.allCases.filter { focuses.contains($0) }
    }

    /// Duration parsed from the cardio field (gym sessions leave it 0).
    private var parsedDuration: Int {
        guard !kind.isGym else { return 0 }
        return max(0, Int(durationText.trimmingCharacters(in: .whitespaces)) ?? 0)
    }
}

// MARK: - Editable pick (draft, not a model)

/// A plain-value draft for a selected machine — edited inline, converted to an `ExerciseEntry`
/// only on Save (same pattern as `FoodDraft` → `FoodEntry`). Defaults to the comfy 3×10 / no weight.
struct ExercisePick: Identifiable, Hashable {
    let id = UUID()
    var machineKey: String
    var displayName: String
    var iconName: String
    var weightLbs: Double = 0      // 0 = unset
    var reps: Int = 10
    var sets: Int = 3
}

// MARK: - Tiles

/// A square kind tile (icon + label), filled-brand when selected.
private struct KindTile: View {
    let kind: WorkoutKind
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xs) {
                Image(systemName: kind.systemImage)
                    .font(.title2)
                Text(kind.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .foregroundStyle(selected ? .white : Theme.textPrimary)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.brandGradient)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.card)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(selected ? Color.clear : Theme.divider, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .bouncyPress()
        .accessibilityLabel(kind.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A square machine tile with a ✓ badge when selected. Highlighted (when its focus is selected)
/// gets a soft brand wash + brand border so matches read first — but it's always tappable.
private struct MachineTile: View {
    let machine: Machine
    let selected: Bool
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xs) {
                Image(systemName: machine.icon)
                    .font(.title2)
                Text(machine.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .padding(.horizontal, 4)
            .foregroundStyle(selected ? .white : Theme.textPrimary)
            .background { tileBackground }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .bouncyPress()
        .accessibilityLabel(machine.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var tileBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        if selected {
            shape.fill(Theme.brandGradient)
        } else if highlighted {
            shape.fill(Theme.brandSoft)
        } else {
            shape.fill(Theme.card)
        }
    }

    private var borderColor: Color {
        if selected { return .clear }
        return highlighted ? Theme.brand.opacity(0.45) : Theme.divider
    }
}

/// The dashed "＋ Add a machine" tile.
private struct AddTile: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xs) {
                Image(systemName: "plus")
                    .font(.title2)
                Text("Add a machine")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .padding(.horizontal, 4)
            .foregroundStyle(Theme.brand)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.brandSoft.opacity(0.5)))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(Theme.brand.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
        .buttonStyle(.plain)
        .bouncyPress()
        .accessibilityLabel("Add a machine")
    }
}

// MARK: - Inline exercise editor

/// The expandable editor revealed for a selected machine: optional weight field + reps/sets
/// steppers prefilled 3×10 (all editable / all optional), plus a remove button.
private struct ExerciseEditor: View {
    @Binding var pick: ExercisePick
    let remove: () -> Void

    /// Mirrors `weightLbs` as text so the field can be blank (0 = unset).
    @State private var weightText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: pick.iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 30, height: 30)
                    .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                Text(pick.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(pick.displayName)")
            }

            // Weight (optional)
            HStack {
                Text("Weight")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                TextField("optional", text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .onChange(of: weightText) { _, new in
                        pick.weightLbs = max(0, Double(new.trimmingCharacters(in: .whitespaces)) ?? 0)
                    }
                Text("lb")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, alignment: .leading)
            }

            // Sets / reps steppers, prefilled to the 3×10 default.
            Stepper(value: $pick.sets, in: 1...20) {
                HStack { Text("Sets").foregroundStyle(Theme.textSecondary); Spacer()
                    Text("\(pick.sets)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary) }
                    .font(.subheadline)
            }
            Stepper(value: $pick.reps, in: 1...50) {
                HStack { Text("Reps").foregroundStyle(Theme.textSecondary); Spacer()
                    Text("\(pick.reps)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary) }
                    .font(.subheadline)
            }
        }
        .tint(Theme.brand)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .onAppear {
            // Seed the field from any existing value (e.g. re-render), blank when unset.
            weightText = pick.weightLbs > 0 ? WorkoutFormat.weight(pick.weightLbs) : ""
        }
    }
}

// MARK: - Add-a-machine sheet (custom name)

/// Phase 1 "add a machine": a tiny sheet to type a custom name → a custom `ExercisePick` with the
/// generic `dumbbell.fill` icon. (The describe-to-Vita / photo flow is Phase 3.)
private struct AddMachineSheet: View {
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool { !trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("What machine or exercise?")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)

                TextField("e.g. Sled push", text: $text)
                    .font(.body)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(commit)
                    .padding(Theme.Space.md)
                    .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1))

                Button(action: commit) {
                    Text("Add machine")
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
            .navigationTitle("Add a machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(240), .medium])
        .presentationDragIndicator(.visible)
    }

    private func commit() {
        guard canAdd else { return }
        onAdd(trimmed)
        dismiss()
    }
}

// MARK: - Chip label

/// A pill chip matching the app's chip style: soft brand wash by default, filled brand gradient
/// when selected. (Self-contained copy of the `ChecklistCard` chip so this flow stays standalone.)
private struct ChipLabel: View {
    let text: String
    let icon: String
    let filled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption.weight(.semibold))
            Text(text).font(.subheadline.weight(.medium))
        }
        .foregroundStyle(filled ? .white : Theme.textPrimary)
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background {
            if filled { Capsule().fill(Theme.brandGradient) }
            else { Capsule().fill(Theme.brandSoft) }
        }
        .overlay {
            if !filled { Capsule().strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1) }
        }
    }
}

// MARK: - Flow layout (chip wrapping)

/// Minimal wrapping layout so the focus chips flow onto new lines at any width / Dynamic Type
/// size. (A self-contained copy — the app's other flow layouts are `private` to their files.)
private struct WorkoutFlowLayout: Layout {
    var spacing: CGFloat = Theme.Space.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth && x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    WorkoutLogFlow()
        .modelContainer(for: [WorkoutSession.self, ExerciseEntry.self], inMemory: true)
}
