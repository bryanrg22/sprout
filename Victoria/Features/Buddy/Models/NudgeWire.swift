import Foundation

/// Plain, `Sendable` transport form of a `Nudge`.
///
/// **Why this exists.** `Nudge` is a SwiftData `@Model` — a reference type that is *not*
/// `Sendable` and is bound to the main-actor `ModelContext`. When `CloudKitSyncService`
/// talks to CloudKit it `await`s calls that suspend off the main actor, so a `Nudge` must
/// never be live across one of those suspension points (Swift's concurrency checker flags
/// a non-`Sendable` value held across an `await` as a potential data race).
///
/// `NudgeWire` is the safe go-between: the service reads a `Nudge`'s fields into one of
/// these **synchronously, on the main actor, before** any `await`, and rebuilds `[Nudge]`
/// from these **after** the awaits — so no `@Model` ever crosses an actor boundary, and
/// the public `BuddySyncService` API (which speaks in `Nudge`) is unchanged.
///
/// It mirrors `BuddySnapshotPayload`'s role for snapshots, and the field layout of the
/// mock's private `NudgeDTO`. Enum-ish fields are carried as their wire-stable raw string
/// (`kindRaw`) so the format is independent of the persistence layer.
struct NudgeWire: Sendable, Equatable {
    var id: UUID
    var fromUserID: String
    var toUserID: String
    /// Raw value of `NudgeKind` — the wire-stable string (see `Nudge.kindRaw`).
    var kindRaw: String
    var text: String
    var createdAt: Date
    var isRead: Bool
}

// MARK: - Mapping helpers (both directions run on the main actor, where `Nudge` lives)

extension NudgeWire {
    /// Snapshot a persisted/transient `@Model` `Nudge` into a `Sendable` value.
    /// `@MainActor` because reading a `@Model`'s stored properties must happen on the
    /// actor the model is bound to.
    @MainActor
    init(from nudge: Nudge) {
        self.init(id: nudge.id,
                  fromUserID: nudge.fromUserID,
                  toUserID: nudge.toUserID,
                  kindRaw: nudge.kindRaw,
                  text: nudge.text,
                  createdAt: nudge.createdAt,
                  isRead: nudge.isRead)
    }

    /// Materialize a (detached) `@Model` `Nudge` from this wire value. The caller decides
    /// whether/where to insert it into a `ModelContext`. `@MainActor` so the freshly
    /// created `@Model` is born on the main actor.
    @MainActor
    func makeModel() -> Nudge {
        Nudge(id: id,
              fromUserID: fromUserID,
              toUserID: toUserID,
              kind: NudgeKind(rawValue: kindRaw) ?? .cheer,
              text: text,
              createdAt: createdAt,
              isRead: isRead)
    }
}
