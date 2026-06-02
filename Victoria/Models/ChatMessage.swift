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
    var createdAt: Date = Date.now
    /// True for the canned welcome message so we can avoid sending it to the API.
    var isSystemSeed: Bool = false

    var isUser: Bool { roleRaw == "user" }

    init(role: String, content: String, createdAt: Date = .now, isSystemSeed: Bool = false) {
        self.id = UUID()
        self.roleRaw = role
        self.content = content
        self.createdAt = createdAt
        self.isSystemSeed = isSystemSeed
    }
}
