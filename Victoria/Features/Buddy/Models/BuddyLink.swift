import Foundation
import SwiftData

/// This device's buddy pairing — the link between *me* and one accountability buddy.
///
/// There is exactly **one** of these per user (a 1:1 buddy relationship for now; the
/// social vision is a single warm companion you keep each other accountable with, not
/// a feed). It starts life as `.pending` the moment a pairing code is generated, and
/// flips to `.linked` once the other person enters that code (or, in the local mock,
/// once a simulated buddy "accepts").
///
/// **Why every property has a default value:** this is intentional and load-bearing.
/// CloudKit-backed SwiftData (`ModelConfiguration(cloudKitDatabase:)`, wired up later —
/// see `CloudKitSyncService`) requires every non-optional attribute to have a default
/// or be optional. Matching the existing models' convention here keeps us migration-
/// and CloudKit-ready with zero rework.
@Model
final class BuddyLink {
    /// Stable id for this user (this device's "side" of the pairing). Generated once
    /// and reused; it's what a buddy's `Nudge.toUserID` / `BuddySnapshot` is addressed to.
    var myUserID: String = ""

    /// The paired buddy's user id. `nil` until the pairing completes.
    var buddyUserID: String?

    /// The buddy's friendly name to show in the UI ("Bryan"). `nil` until linked.
    var buddyDisplayName: String?

    /// The short human-shareable code used to connect (e.g. "VITA-7F3K"). One person
    /// generates it; the other types it in. It's the rendezvous key both sides query on.
    var pairingCode: String = ""

    /// Persisted as a raw string (enum accessor below) so it round-trips through both
    /// SwiftData and CloudKit cleanly — mirrors the `typeRaw`/`type` pattern used across
    /// this codebase (see `WorkoutEntry`).
    var statusRaw: String = BuddyLinkStatus.pending.rawValue

    var createdAt: Date = Date.now

    init(myUserID: String,
         buddyUserID: String? = nil,
         buddyDisplayName: String? = nil,
         pairingCode: String,
         status: BuddyLinkStatus = .pending,
         createdAt: Date = .now) {
        self.myUserID = myUserID
        self.buddyUserID = buddyUserID
        self.buddyDisplayName = buddyDisplayName
        self.pairingCode = pairingCode
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
    }

    // MARK: Enum accessor
    var status: BuddyLinkStatus {
        get { BuddyLinkStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    /// Convenience: are we connected to a real buddy yet?
    var isLinked: Bool { status == .linked && buddyUserID != nil }
}

/// Lifecycle of a buddy pairing.
enum BuddyLinkStatus: String, Codable, CaseIterable, Identifiable {
    /// A code has been generated / entered, but the two sides aren't connected yet.
    case pending
    /// Both sides are connected; nudges and snapshots can flow.
    case linked
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pending: return "Waiting to connect"
        case .linked:  return "Connected"
        }
    }
}
