import SwiftUI

/// The buddy's love notes. Received nudges via `fetchInbox()`, most-recent first, each a
/// cute card. Opening the inbox marks everything read (`markRead(_:)`). Warm empty state.
struct NudgeInboxView: View {
    @Bindable var model: BuddyViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Space.md) {
                if model.inbox.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(model.inbox.enumerated()), id: \.element.id) { index, nudge in
                        NudgeCard(nudge: nudge)
                            .appearLift(true, index: min(index, 6))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, Theme.Space.sm)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("From your buddy")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await model.loadInbox()
            // Seeing them = reading them.
            await model.markAllRead()
        }
        .refreshable { await model.loadInbox() }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.md) {
            Text("🐼")
                .font(.system(size: 56))
                .breathing()
            Text("No notes yet")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text("When your buddy cheers you on, their notes will land right here 💛")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, Theme.Space.lg)
    }
}

/// One received nudge as a cute card: tinted kind icon, the message, a relative time,
/// and a soft "new" dot while unread.
struct NudgeCard: View {
    let nudge: Nudge

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            // Same soft tinted disc as the send rail + challenge cards, so a note in the inbox
            // visually matches the chip it came from.
            NudgeIconDisc(systemImage: nudge.kind.systemImage, tint: tint, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(nudge.kind.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    if !nudge.isRead {
                        Circle().fill(Theme.brand).frame(width: 7, height: 7)
                            .popIn(true)
                    }
                    Spacer(minLength: 0)
                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(nudge.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(nudge.kind.label) from your buddy, \(relativeTime). \(nudge.text)\(nudge.isRead ? "" : ". New")")
    }

    // Shared per-kind tint (see `NudgeKind.tint`) so the inbox matches the send rail exactly.
    private var tint: Color { nudge.kind.tint }

    private var relativeTime: String {
        let interval = Date.now.timeIntervalSince(nudge.createdAt)
        if interval < 90 { return "just now" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: nudge.createdAt, relativeTo: .now)
    }
}

#Preview("Inbox") {
    NavigationStack {
        NudgeInboxView(model: BuddyViewModel(service: LocalMockSyncService(), myUserID: "me"))
    }
}
