import Foundation
import SwiftData

/// The AI coach's durable, long-term memory — the layer that makes Vita feel like ONE
/// continuous conversation instead of forgetting once the chat scrolls past the recent
/// window (the OpenClaw / Hermes-style "core memory + rolling summary" pattern).
///
/// There is exactly ONE of these in the store (a singleton-ish record; use
/// `fetchOrCreate(in:profile:)` to get it). It holds two qualitative text blocks plus a
/// high-water mark, and is maintained off the user's turn by `CoachMemoryService`:
///
/// - `profileNotes` — durable markdown facts about *who she is*: preferences, life
///   context, foods she likes/dislikes, motivations, obstacles, wins. This is the slowly
///   evolving "about her" document.
/// - `conversationSummary` — a rolling, concise prose summary of older conversation so
///   continuity survives after those messages leave the verbatim window.
/// - `summarizedThroughDate` — the `createdAt` of the newest chat message already folded
///   into the two blocks above (the consolidation "high-water mark"). Anything strictly
///   newer than this is un-folded and will be consolidated on the next overflow.
///
/// IMPORTANT — numbers stay code-owned. This memory holds ONLY qualitative facts. It must
/// NEVER store weights, calories, macros, or targets: those are computed live and
/// authoritatively by `CoachContext` from real data. The consolidation prompt forbids
/// numbers explicitly, and this doc is injected into the system prompt *after* the live
/// numbers with a clear note that the live numbers above win.
@Model
final class CoachMemory {
    /// Stable id. There is only one row, but a UUID keeps it uniform with the other models.
    var id: UUID = UUID()

    /// Durable markdown facts about the user (qualitative only — NO numbers/targets/weights).
    /// Seeded from `profile.onboardingNote` on first creation when that's non-empty, then
    /// grown/curated by the background consolidation pass. Kept bounded (~1500 chars).
    var profileNotes: String = ""

    /// A concise rolling summary of older conversation, for continuity once those messages
    /// drop out of the verbatim recent window. Kept bounded (~1000 chars).
    var conversationSummary: String = ""

    /// `createdAt` of the newest chat message already folded into `profileNotes` /
    /// `conversationSummary`. `nil` means nothing has been consolidated yet. Messages with
    /// `createdAt > summarizedThroughDate` are "un-folded" and pending consolidation.
    var summarizedThroughDate: Date?

    /// When this record was last written (seeded or consolidated). For debugging / future UI.
    var updatedAt: Date = Date.now

    init(profileNotes: String = "",
         conversationSummary: String = "",
         summarizedThroughDate: Date? = nil,
         updatedAt: Date = .now) {
        self.id = UUID()
        self.profileNotes = profileNotes
        self.conversationSummary = conversationSummary
        self.summarizedThroughDate = summarizedThroughDate
        self.updatedAt = updatedAt
    }

    // MARK: - Singleton access

    /// Fetch the single `CoachMemory`, creating (and inserting) it if it doesn't exist yet.
    ///
    /// On first creation, `profileNotes` is seeded from `profile.onboardingNote` (her own
    /// "about me" words) when that's non-empty, so Vita starts with the context the user
    /// already shared rather than a blank slate. The seed is treated as durable qualitative
    /// context; the onboarding note never contains targets, so this is numbers-safe.
    ///
    /// - Parameters:
    ///   - context: the model context to read/insert into.
    ///   - profile: used only to seed `profileNotes` on first creation. Pass `nil` to skip
    ///     seeding (e.g. when no profile is available yet).
    /// - Returns: the one-and-only `CoachMemory` instance.
    @discardableResult
    static func fetchOrCreate(in context: ModelContext,
                              profile: UserProfile? = nil) -> CoachMemory {
        var descriptor = FetchDescriptor<CoachMemory>(
            sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        // First run: create, seeding durable notes from the user's onboarding note if any.
        let seed = profile?.onboardingNote.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let notes: String
        if seed.isEmpty {
            notes = ""
        } else {
            // Label the seed so later consolidation passes know its provenance and the model
            // reads it as durable "about her" context (qualitative, never numeric).
            notes = "From her onboarding note (her own words): \(seed)"
        }
        let memory = CoachMemory(profileNotes: notes)
        context.insert(memory)
        return memory
    }
}
