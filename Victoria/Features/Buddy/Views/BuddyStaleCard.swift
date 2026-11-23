import SwiftUI

/// Shown in place of the buddy's day when nothing has been published for days
/// (`BuddyFreshness.stale`). Old numbers are not put on screen as if they were today's;
/// the card says since when there has been nothing, why that can happen, and how to get out.
///
/// The case it exists for: the buddy deleted and reinstalled the app, or moved to a new
/// phone. Their install has a new id, the old one never publishes again, and nothing tells
/// this phone (`docs/buddy-identity.md`). Unpairing and pairing again is the way back.
struct BuddyStaleCard: View {
    /// "Sam", or "your buddy" when they never published a name.
    let name: String
    /// The same, to begin a sentence with.
    let nameAtStart: String
    /// When the buddy last published.
    let since: Date
    /// Whole days since then.
    let days: Int
    var onUnpair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(Theme.warning)
                    .frame(width: 44, height: 44)
                    .background(Theme.warning.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(nameAtStart) hasn't shared an update since \(Self.dayText(since))")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(days) days ago")
                        .font(.subheadline)
                        .foregroundStyle(Theme.warning)
                }
            }

            Text("Their day isn't shown because it's that old. If \(name) deleted and reinstalled Sprout, or moved to a new phone, this pairing can't reconnect on its own. Unpair, then pair again with a new code.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(role: .destructive, action: onUnpair) {
                Label("Unpair from \(name)", systemImage: "person.2.slash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.red)   // the app-wide tint would paint a destructive action in the brand colour
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }

    /// "Nov 14" in the user's locale and time zone.
    static func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Shown while paired with a buddy who has not published anything yet.
struct BuddyWaitingCard: View {
    /// "Sam" or "Your buddy": it begins a sentence.
    let name: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: "hourglass")
                .font(.title3)
                .foregroundStyle(Theme.brand)
                .frame(width: 44, height: 44)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("You're paired. Waiting for their first update")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(name)'s day shows up here the first time their phone shares it. You can already send a note below.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardElevated()
    }
}

#Preview("Stale buddy") {
    ScrollView {
        VStack(spacing: Theme.Space.md) {
            BuddyStaleCard(name: "Sam", nameAtStart: "Sam", since: .now.addingTimeInterval(-9 * 86_400), days: 9) {}
            BuddyWaitingCard(name: "Your buddy")
        }
        .padding()
    }
    .background(Theme.background)
}
