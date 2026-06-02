import Foundation
import SwiftData

/// A small, *kind* message between buddies — a tap on the shoulder that says
/// "I see you, keep going." Nudges are the heartbeat of the accountability-buddy
/// feature: low-effort to send, warm to receive.
///
/// **Tone is a hard rule, enforced at the type level.** `NudgeKind` contains
/// health-POSITIVE intents only. There is deliberately no "you skipped today",
/// "you're behind", or any guilt/shame/restriction option — a buddy can only ever
/// cheer you on. This mirrors the app-wide "kind, never guilt-inducing" principle
/// (see `NotificationService`).
///
/// Every property has a default value to stay SwiftData-migration- and CloudKit-ready
/// (see the note in `BuddyLink`).
@Model
final class Nudge {
    /// Stable, client-generated id. Doubles as the CloudKit record name so a nudge
    /// can't be duplicated if a send is retried.
    var id: UUID = UUID()

    var fromUserID: String = ""
    var toUserID: String = ""

    /// Persisted as raw string (enum accessor below) for clean SwiftData + CloudKit
    /// round-tripping — same pattern as `WorkoutEntry.typeRaw`.
    var kindRaw: String = NudgeKind.cheer.rawValue

    /// The visible message. Defaults to the kind's friendly phrasing if left empty,
    /// so a tap-to-send (no typing) still feels warm.
    var text: String = ""

    var createdAt: Date = Date.now

    /// Whether the recipient has seen this in their inbox yet.
    var isRead: Bool = false

    init(id: UUID = UUID(),
         fromUserID: String,
         toUserID: String,
         kind: NudgeKind = .cheer,
         text: String = "",
         createdAt: Date = .now,
         isRead: Bool = false) {
        self.id = id
        self.fromUserID = fromUserID
        self.toUserID = toUserID
        self.kindRaw = kind.rawValue
        self.text = text.isEmpty ? kind.defaultMessage : text
        self.createdAt = createdAt
        self.isRead = isRead
    }

    // MARK: Enum accessor
    var kind: NudgeKind {
        get { NudgeKind(rawValue: kindRaw) ?? .cheer }
        set { kindRaw = newValue.rawValue }
    }
}

/// The intent behind a nudge. **Health-positive ONLY** — see the type-level note above.
/// Adding a guilt/shame/restriction case here would violate the app's core tone contract.
enum NudgeKind: String, Codable, CaseIterable, Identifiable {
    /// Generic encouragement: "You've got this!"
    case cheer
    /// A gentle "how's your day going?" — connection, not pressure.
    case checkIn
    /// Celebrating a win (a streak, a good log day): "Look at you go 💪".
    case flex
    /// Heartfelt: "I'm proud of you."
    case proudOfYou
    /// A warm invitation to get moving together: "Let's go for a walk?"
    case letsMove

    var id: String { rawValue }

    /// Short label for pickers / buttons.
    var label: String {
        switch self {
        case .cheer:      return "Cheer"
        case .checkIn:    return "Check in"
        case .flex:       return "Celebrate"
        case .proudOfYou: return "Proud of you"
        case .letsMove:   return "Let's move"
        }
    }

    /// SF Symbol for the nudge chip.
    var systemImage: String {
        switch self {
        case .cheer:      return "hands.clap.fill"
        case .checkIn:    return "hand.wave.fill"
        case .flex:       return "party.popper.fill"
        case .proudOfYou: return "heart.fill"
        case .letsMove:   return "figure.walk.motion"
        }
    }

    /// Friendly default copy used when the sender doesn't type their own message.
    /// Warm, specific, never preachy.
    var defaultMessage: String {
        switch self {
        case .cheer:      return "You've got this! 💚"
        case .checkIn:    return "Hey! How's your day going?"
        case .flex:       return "Look at you go — that's awesome! 🎉"
        case .proudOfYou: return "I'm really proud of you."
        case .letsMove:   return "Feel like moving a little today? I'm in if you are!"
        }
    }
}
