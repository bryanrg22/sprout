import Foundation
import SwiftData

/// Launch-argument hooks for the UI smoke flows (`VictoriaUITests`).
///
/// `--ui-testing` puts a launch into a known state that never touches the simulator's
/// real data: an in-memory store on the production schema with CloudKit off, no system
/// permission prompt, no Apple Health or Google Health import, no write to the widget's
/// shared snapshot, and no model call that can reach a provider. Combined with the
/// existing `--seed-demo --demo-gain`, the demo profile is seeded into that in-memory
/// store. `--ui-test-scripted-ai=<name>` then answers every model call from a built-in
/// script (`UITestAIScript`) instead of the network.
///
/// DEBUG only. The decision is the pure `plan(arguments:isDebugBuild:)`, which returns
/// `.inert` for any build that is not a DEBUG build, and the only code that acts on a
/// plan (`makeContainer`, `installAIRuntime`) is compiled out of Release.
enum UITestHooks {
    static let uiTestingArgument = "--ui-testing"
    static let scriptedAIPrefix = "--ui-test-scripted-ai="

    /// What one launch's arguments ask for.
    struct Plan: Equatable, Sendable {
        /// `--ui-testing` was passed to a DEBUG build.
        var isActive = false
        /// The script named by `--ui-test-scripted-ai=`; nil when none was named.
        var scriptedAI: String?

        static let inert = Plan()
    }

    /// The plan for a set of launch arguments. Inert unless this is a DEBUG build AND
    /// `--ui-testing` is present; a script name without `--ui-testing` does nothing.
    static func plan(arguments: [String], isDebugBuild: Bool) -> Plan {
        guard isDebugBuild, arguments.contains(uiTestingArgument) else { return .inert }
        let name = arguments.first { $0.hasPrefix(scriptedAIPrefix) }
            .map { String($0.dropFirst(scriptedAIPrefix.count)) }
        return Plan(isActive: true, scriptedAI: name)
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// This process's plan, decided once from its launch arguments.
    static let current = plan(arguments: CommandLine.arguments, isDebugBuild: isDebugBuild)

    /// True for a `--ui-testing` launch of a DEBUG build; always false in Release.
    static var isActive: Bool { current.isActive }

    #if DEBUG
    /// The in-memory store a `--ui-testing` launch runs on: the production schema, nothing
    /// on disk, CloudKit off. Same shape as the unit tests' `TestStore`.
    static func makeContainer() throws -> ModelContainer {
        let schema = AppSchema.schema
        let configuration = ModelConfiguration(schema: schema,
                                               isStoredInMemoryOnly: true,
                                               cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// The process-wide AI runtime for a plan: the named script's transport with a
    /// placeholder key, or, when no script is named, a runtime with an EMPTY key so every
    /// AI feature takes its no-key path. Either way a `--ui-testing` launch cannot read
    /// the Keychain key or reach a provider. Nil for an inert plan.
    static func aiRuntime(for plan: Plan) -> AIRuntime? {
        guard plan.isActive else { return nil }
        guard let name = plan.scriptedAI else {
            return AIRuntime(provider: .anthropic, apiKey: "", transport: UITestOfflineTransport())
        }
        guard let script = UITestAIScript(rawValue: name) else {
            // Loud on purpose: a misspelt script name must not fall through to anything else.
            fatalError("Unknown \(scriptedAIPrefix)\(name). Known scripts: "
                       + UITestAIScript.allCases.map(\.rawValue).joined(separator: ", "))
        }
        return AIRuntime(provider: .anthropic, apiKey: UITestAIScript.placeholderKey,
                         transport: UITestScriptedTransport(script: script))
    }

    /// Install this launch's AI runtime. A no-op for an inert plan.
    static func installAIRuntime(for plan: Plan = current) {
        guard let runtime = aiRuntime(for: plan) else { return }
        AIRuntime.setProcessDefault(runtime)
    }
    #endif
}
