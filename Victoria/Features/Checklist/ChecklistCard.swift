import SwiftUI
import SwiftData

/// "Today's checklist" — a warm little planner on the dashboard for the day's
/// movement / wellness intentions (gym, run, a stretch, an early night). She taps to
/// check things off, gets a gentle "2 of 4 done" nudge, and a small celebration when the
/// list is clear. Quick-add chips (plus a custom field) make planning the day a tap.
///
/// Deliberately about **showing up**, never about restricting food or a number on the
/// scale — same anti-restriction tone as the rest of the app.
struct ChecklistCard: View {
    /// Optional override; defaults to the warm standard title.
    var title: String = "Today's checklist"

    @Environment(\.modelContext) private var context

    /// Sorted broadly by `sortOrder`; we filter to *today* in Swift (cheap, and keeps the
    /// query stable). A secondary sort by `day` keeps things deterministic across days.
    @Query(sort: [SortDescriptor(\ChecklistItem.sortOrder),
                  SortDescriptor(\ChecklistItem.day)])
    private var items: [ChecklistItem]

    /// Presents the "Add your own" custom-task sheet.
    @State private var showCustomSheet = false
    /// Bumped on every check toggle so `.sensoryFeedback(.success)` fires a happy tap.
    @State private var toggleTick = 0

    // MARK: Derived

    /// Just today's tasks, in their manual order.
    private var todays: [ChecklistItem] {
        items
            .filter { Calendar.current.isDateInToday($0.day) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var doneCount: Int { todays.filter { $0.done }.count }
    private var allDone: Bool { !todays.isEmpty && doneCount == todays.count }

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
        addMenu
            .padding(.top, 2)
    }

    /// The "+ Add task" affordance shown once there are items: the presets as chips, plus
    /// an "Add your own" entry that opens the custom-title sheet.
    private var addMenu: some View {
        Menu {
            ForEach(ChecklistSuggestion.all) { s in
                Button { add(s) } label: { Label(s.title, systemImage: s.systemIcon) }
            }
            Divider()
            Button { showCustomSheet = true } label: {
                Label("Add your own", systemImage: "square.and.pencil")
            }
        } label: {
            Label("Add task", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.brand)
        }
        .accessibilityLabel("Add a task to today's checklist")
    }

    // MARK: Empty state

    /// Warm, inviting blank slate — a gently breathing sparkle, an encouraging line, the
    /// preset chips, and an "Add your own" option. Same tone as the Food empty state.
    private var emptyState: some View {
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

            presetChips
        }
        .padding(.vertical, 2)
    }

    /// The quick-add presets as tappable brand-soft chips, with an "Add your own" chip
    /// that opens the custom sheet. Wraps onto new lines at any width / Dynamic Type size.
    private var presetChips: some View {
        ChecklistFlowLayout(spacing: Theme.Space.sm) {
            ForEach(ChecklistSuggestion.all) { s in
                Button { add(s) } label: {
                    chipLabel(s.title, icon: s.systemIcon, filled: false)
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

    private func add(_ suggestion: ChecklistSuggestion) {
        insert(title: suggestion.title, icon: suggestion.systemIcon)
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

// MARK: - Preview

#Preview {
    ScrollView {
        ChecklistCard()
            .padding()
    }
    .background(Theme.background.ignoresSafeArea())
    .modelContainer(for: ChecklistItem.self, inMemory: true)
}
