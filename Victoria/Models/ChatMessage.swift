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

    var isUser: Bool { roleRaw == "user" }

    init(role: String, content: String, imageData: Data? = nil,
         createdAt: Date = .now, isSystemSeed: Bool = false) {
        self.id = UUID()
        self.roleRaw = role
        self.content = content
        self.imageData = imageData
        self.createdAt = createdAt
        self.isSystemSeed = isSystemSeed
    }
}
