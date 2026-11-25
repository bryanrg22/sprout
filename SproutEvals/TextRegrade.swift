import Foundation
import XCTest
@testable import Sprout

/// Grades again the text a past run recorded, with the graders as they are now. No model is
/// called and nothing is spent: each record's saved output is graded against its case,
/// rebuilt from the dataset the run used. This is how a grader fix is checked against every
/// past answer before anyone pays for a new run (`Evals/regrade-text.sh`, EVAL_REPORT 34).
///
/// Covered: the five short-writing tasks whose output is the whole answer (the daily brief,
/// the insight line, the weekly reflection, the onboarding note, the progress recap), and the
/// memory fold, whose recorded output is the model's whole reply, graded as the app's
/// `CoachMemoryService.parse` stores it now. A record
/// whose reply the app discarded or whose call failed is not regradable (there is no shown
/// text to grade); it keeps its old result and says why.
enum TextRegrade {

    static let tasks: Set<String> = ["dailyBrief", "insightLine", "weeklyReflection", "onboardingNote", "progressSummary",
                                     "memoryFold"]

    struct Record: Decodable {
        let task: String
        let dataset: String
        let caseID: String
        let candidate: String
        let repeatIndex: Int
        let ok: Bool
        let pass: Bool
        let output: String
        let scores: [String: Double]
    }

    struct Row: Encodable {
        let caseID: String
        let candidate: String
        let repeatIndex: Int
        let oldPass: Bool
        let newPass: Bool
        /// Nil when the record was not regradable.
        let newScores: [String: Double]?
        /// Why it was not regraded, when it was not.
        let note: String?
    }

    struct Tally: Encodable {
        var attempts = 0
        var oldPassed = 0
        var newPassed = 0
        var notRegradable = 0
    }

    struct Result: Encodable {
        let task: String
        let dataset: String
        let rows: [Row]
        let byCandidate: [String: Tally]
    }

    /// Regrades every records file of a text task in `run`, writes `<run>/regrade-text.json`
    /// and returns what it wrote; nil when the run holds no text task this covers.
    @discardableResult
    static func regrade(run: URL, datasets: URL) throws -> Result? {
        let files = (try? FileManager.default.contentsOfDirectory(at: run, includingPropertiesForKeys: nil)) ?? []
        guard let file = files.first(where: { $0.lastPathComponent.hasPrefix("records-") && $0.pathExtension == "jsonl" })
        else { return nil }
        let records = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
            .map { try JSONDecoder().decode(Record.self, from: Data($0.utf8)) }
        guard let first = records.first, tasks.contains(first.task) else { return nil }
        let grade = try grader(task: first.task, datasetURL: datasets.appendingPathComponent("\(first.dataset).jsonl"))

        var rows: [Row] = []
        var tally: [String: Tally] = [:]
        for record in records {
            var row: Row
            if !record.ok || record.scores["used"] == 0 {
                row = Row(caseID: record.caseID, candidate: record.candidate, repeatIndex: record.repeatIndex,
                          oldPass: record.pass, newPass: record.pass, newScores: nil,
                          note: "not regradable: the reply was not shown (failed call, or discarded by the app)")
            } else if let graded = grade(record.caseID, record.output) {
                row = Row(caseID: record.caseID, candidate: record.candidate, repeatIndex: record.repeatIndex,
                          oldPass: record.pass, newPass: graded.pass, newScores: graded.scores, note: nil)
            } else {
                row = Row(caseID: record.caseID, candidate: record.candidate, repeatIndex: record.repeatIndex,
                          oldPass: record.pass, newPass: record.pass, newScores: nil,
                          note: "not regradable: case \(record.caseID) is not in the dataset or does not map")
            }
            rows.append(row)
            var t = tally[record.candidate, default: Tally()]
            t.attempts += 1
            t.oldPassed += row.oldPass ? 1 : 0
            t.newPassed += row.newPass ? 1 : 0
            t.notRegradable += row.newScores == nil ? 1 : 0
            tally[record.candidate] = t
        }
        let result = Result(task: first.task, dataset: first.dataset, rows: rows, byCandidate: tally)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(result).write(to: run.appendingPathComponent("regrade-text.json"))
        return result
    }

    typealias Grade = (_ caseID: String, _ output: String) -> (scores: [String: Double], pass: Bool)?

    /// The current grader for `task`, closed over its dataset's cases.
    static func grader(task: String, datasetURL: URL) throws -> Grade {
        switch task {
        case "dailyBrief":
            let cases = try index(datasetURL, as: LiveEvals.BriefCase.self, id: \.id)
            return { id, output in
                guard let item = cases[id] else { return nil }
                let picked = DailyBriefService.pick(item.signals)
                let parts = output.split(separator: "\n", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return LiveEvals.gradeBrief(template: (picked.headline, picked.body), reply: (parts[0], parts[1]),
                                            readerIsNotAWoman: item.readerIsNotAWoman)
            }
        case "insightLine":
            let cases = try index(datasetURL, as: LiveEvals.InsightCase.self, id: \.id)
            return { id, output in
                guard let item = cases[id], let chosen = item.chosen else { return nil }
                return Graders.insightLine(template: chosen.insight.template, hint: chosen.hint, line: output,
                                           reader: item.reader)
            }
        case "weeklyReflection":
            let cases = try index(datasetURL, as: LiveEvals.WeeklyCase.self, id: \.id)
            return { id, output in
                guard let item = cases[id], let inputs = item.inputs else { return nil }
                return Graders.weeklyReflection(given: WeeklyReflection.userPrompt(inputs), counts: item.counts,
                                                name: inputs.name, text: output, reader: item.reader)
            }
        case "onboardingNote":
            let cases = try index(datasetURL, as: LiveEvals.OnboardingCase.self, id: \.id)
            return { id, output in
                guard let item = cases[id], let inputs = item.inputs else { return nil }
                return Graders.onboardingNote(given: OnboardingCoachMessage.userPrompt(inputs), name: inputs.name,
                                              mustNotSay: item.mustNotSay, text: output, reader: item.reader)
            }
        case "progressSummary":
            let cases = try index(datasetURL, as: LiveEvals.ProgressCase.self, id: \.id)
            return { id, output in
                guard let item = cases[id], let summary = progressSummary(fromRecorded: output) else { return nil }
                return Graders.progressSummary(snapshot: item.snapshot, summary: summary, reader: item.reader)
            }
        case "memoryFold":
            let cases = try index(datasetURL, as: LiveEvals.MemoryCase.self, id: \.id)
            return { id, output in
                guard let item = cases[id] else { return nil }
                return Graders.memoryFold(raw: output, expect: item.expectation)
            }
        default:
            throw XCTSkip("no text regrade for \(task)")
        }
    }

    /// The recap as the harness recorded it: headline, body, then "- " highlights.
    static func progressSummary(fromRecorded output: String) -> ProgressSummary? {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else { return nil }
        let highlights = lines.dropFirst(2).compactMap { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : nil }
        return ProgressSummary(headline: lines[0], body: lines[1], highlights: highlights)
    }

    private static func index<T: Decodable>(_ url: URL, as type: T.Type, id: KeyPath<T, String>) throws -> [String: T] {
        let rows = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("//") }
            .map { try JSONDecoder().decode(T.self, from: Data($0.utf8)) }
        return Dictionary(rows.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// `Evals/regrade-text.sh Evals/runs/<run> [<run> …]`: no model is called and nothing is
/// spent, so it runs whenever its environment names runs, live keys or not.
final class TextRegradeRun: XCTestCase {
    func testTextRegrade() throws {
        let runs = EvalEnv.regradeTextRuns
        guard !runs.isEmpty else { throw XCTSkip("no runs to regrade (use Evals/regrade-text.sh)") }
        for run in runs {
            let datasets = run.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("datasets")
            try TextRegrade.regrade(run: run, datasets: datasets)
        }
    }
}
