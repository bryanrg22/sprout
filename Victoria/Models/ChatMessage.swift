import Foundation
import SwiftData

/// One message in the AI coach conversation. Persisted so the coach has memory of
/// past chats and the user can scroll back.
@Model
final class ChatMessage {
    var id: UUID = UUID()
    /// "user" or "assistant".
    var roleRaw: String = "assistant"
    var content: String = ""
    /// An optional photo the user attached to this message (downscaled JPEG), stored outside
    /// the main store for performance. Defaulted/optional so existing rows migrate cleanly.
    @Attribute(.externalStorage) var imageData: Data?
    var createdAt: Date = Date.now
    /// True for the canned welcome message so we can avoid sending it to the API.
    var isSystemSeed: Bool = false

    /// When non-nil, this row is NOT prose — it's a durable record of a tool-confirm decision the
    /// user made (e.g. "set your daily step goal to 12,000 steps"). It renders in the transcript
    /// as a settled, grayed-out confirm card (kept in history instead of vanishing), with the
    /// option she picked highlighted. Optional/defaulted so existing rows migrate cleanly, and
    /// excluded from what we send to the API (it carries no real conversational turn).
    var decisionSummary: String?
    /// For a decision row: true if she tapped "Yes", false if "Not now". nil for normal rows.
    var decisionAccepted: Bool?

    var isUser: Bool { roleRaw == "user" }
    /// A settled confirm-card record (see `decisionSummary`), not a normal message bubble.
    var isDecision: Bool { decisionSummary != nil }

    init(role: String, content: String, imageData: Data? = nil,
         createdAt: Date = .now, isSystemSeed: Bool = false,
         decisionSummary: String? = nil, decisionAccepted: Bool? = nil) {
        self.id = UUID()
        self.roleRaw = role
        self.content = content
        self.imageData = imageData
        self.createdAt = createdAt
        self.isSystemSeed = isSystemSeed
        self.decisionSummary = decisionSummary
        self.decisionAccepted = decisionAccepted
    }
}
