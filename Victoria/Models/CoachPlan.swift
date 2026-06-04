import Foundation
import SwiftData

/// One insight "ticket" on the plan — a short, specific read the coach surfaces on Progress.
struct PlanInsight: Codable, Identifiable, Hashable {
    enum Tone: String, Codable, Hashable { case win, watch, nudge }
    var id: UUID = UUID()
    var title: String
    var body: String
    var tone: Tone
}

/// One line in the plan's changelog — so every adaptation is visible, not silent.
struct PlanChange: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var summary: String
}

/// The user's adaptive **Plan** — the AI-authored, evolving "understanding of you" that lives on
/// Progress and that Vita reads + edits. Direction-agnostic (loss or gain; same fields, different
/// targets). Authored as structured output, with markdown prose in `assessment`/`strategy` for the
/// "doc" feel. One row per user, CloudKit-synced (scalar fields defaulted; arrays stored as JSON
/// strings, which is the SwiftData/CloudKit-safe way to carry a list).
@Model
final class CoachPlan {
    var id: UUID = UUID()

    /// One-line read, e.g. "On track for 135 by September".
    var headline: String = ""
    /// The current "are we on target?" read (markdown prose).
    var assessment: String = ""
    /// The approach + the *why* behind the numbers (markdown prose).
    var strategy: String = ""

    /// The daily calorie **range** — a floor (no under-eating) and a soft ceiling. `0`s mean "not set".
    var calorieMin: Double = 0
    var calorieMax: Double = 0
    /// Daily protein target (g).
    var proteinTarget: Double = 0

    /// Captured intent, in the plan's own words.
    var goalSummary: String = ""
    var timeframe: String = ""

    /// The live-web research brief that grounded this build (a short cited summary). Surfaced as an
    /// expandable "what this is based on" on the plan card. Empty when the build wasn't research-
    /// grounded (no key / web search off). Set on generate; preserved across review. Defaulted +
    /// kept out of `init` so it's CloudKit-migration-safe and existing call sites are unchanged.
    var researchNotes: String = ""

    /// How many logged days informed this build — drives the "early read" confidence note.
    var dataPointsAtBuild: Int = 0

    /// JSON-encoded `[PlanInsight]` / `[PlanChange]`. Arrays are persisted as strings so the model
    /// stays CloudKit-friendly; decoded through the computed properties below.
    var insightsJSON: String = "[]"
    var changelogJSON: String = "[]"

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(headline: String = "",
         assessment: String = "",
         strategy: String = "",
         calorieMin: Double = 0,
         calorieMax: Double = 0,
         proteinTarget: Double = 0,
         goalSummary: String = "",
         timeframe: String = "",
         dataPointsAtBuild: Int = 0,
         insights: [PlanInsight] = [],
         changelog: [PlanChange] = [],
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = UUID()
        self.headline = headline
        self.assessment = assessment
        self.strategy = strategy
        self.calorieMin = calorieMin
        self.calorieMax = calorieMax
        self.proteinTarget = proteinTarget
        self.goalSummary = goalSummary
        self.timeframe = timeframe
        self.dataPointsAtBuild = dataPointsAtBuild
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.insights = insights
        self.changelog = changelog
    }

    // MARK: - Decoded array access

    var insights: [PlanInsight] {
        get { Self.decode(insightsJSON) }
        set { insightsJSON = Self.encode(newValue) }
    }

    var changelog: [PlanChange] {
        get { Self.decode(changelogJSON) }
        set { changelogJSON = Self.encode(newValue) }
    }

    // MARK: - Derived

    /// True until there's a week of data — the plan should hedge ("early read, sharpening as we go").
    var isEarlyRead: Bool { dataPointsAtBuild < 7 }

    /// A valid calorie range was set.
    var hasRange: Bool { calorieMin > 0 && calorieMax >= calorieMin }

    /// Range rendered for the UI, e.g. "1,600–1,750". Empty when unset.
    var calorieRangeText: String {
        guard hasRange else { return "" }
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        let lo = f.string(from: calorieMin as NSNumber) ?? "\(Int(calorieMin))"
        let hi = f.string(from: calorieMax as NSNumber) ?? "\(Int(calorieMax))"
        return calorieMin == calorieMax ? lo : "\(lo)–\(hi)"
    }

    // MARK: - Singleton-ish access

    /// The most recently updated plan, if one exists.
    static func current(in context: ModelContext) -> CoachPlan? {
        var d = FetchDescriptor<CoachPlan>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    // MARK: - JSON helpers

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value), let s = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return s
    }

    static func decode<T: Decodable>(_ json: String) -> [T] {
        guard let data = json.data(using: .utf8), let v = try? decoder.decode([T].self, from: data) else {
            return []
        }
        return v
    }
}
