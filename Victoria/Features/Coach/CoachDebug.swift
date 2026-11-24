#if DEBUG
import Foundation
import SwiftData
import Darwin
import SwiftUI
import UIKit

/// DEBUG-only launch arguments for the coach chat: a long seeded conversation and a
/// load-time probe. Nothing here is compiled into a Release build.
///
///     --demo-long-chat <n>     replace the conversation with n seeded messages
///     --chat-probe             log how long the chat took to become usable
///     --no-notification-prompt do not ask for notification permission at launch (a
///                              screenshot run cannot tap the alert away)
///     --chat-debug-script <s>  answer the coach's model calls from a canned script instead
///                              of a provider: ok | tool | confirm | cutoff | flaky | offline | timeout
///                              | 401 | 429 | 500 | 529
///     --chat-debug-do <a,b,…>  after the chat opens, one step a second: top (scroll to the
///                              oldest loaded message) | send:<text> | quote (quote the newest
///                              reply into the composer) | hold (do not auto-load earlier pages)
///
/// The numbers these produce are recorded in `docs/chat-standards.md`.
enum ChatDebug {

    static func value(after flag: String, in arguments: [String] = CommandLine.arguments) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func has(_ flag: String, in arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(flag)
    }

    /// `--demo-long-chat <n>`: how many messages the seeded conversation holds.
    static var longChatCount: Int? {
        value(after: "--demo-long-chat").flatMap(Int.init).map { max(0, $0) }
    }

    // MARK: - Long conversation seed

    /// One seeded message, before it becomes a row.
    struct SeedMessage: Equatable {
        var role: String
        var content: String
        var createdAt: Date
        var isSystemSeed: Bool
    }

    /// `count` messages ending two minutes before `now`: the canned welcome first, then
    /// alternating user and assistant turns. Deterministic (no randomness), every
    /// `createdAt` distinct and increasing, grouped into sittings a day or so apart so the
    /// timestamp headers appear as they would in a real conversation. Each message carries
    /// its index, so a screenshot shows which part of the history is on screen.
    static func longChat(count: Int, coachName: String, userName: String, now: Date) -> [SeedMessage] {
        guard count > 0 else { return [] }
        // Gaps between consecutive messages, in seconds, oldest first.
        var gaps: [TimeInterval] = []
        for index in 1..<max(count, 1) {
            let inSitting = index % 9 != 0
            gaps.append(inSitting ? TimeInterval(40 + (index * 37) % 75)
                                  : TimeInterval(9 * 3600 + (index * 613) % (20 * 3600)))
        }
        let end = now.addingTimeInterval(-120)
        var date = end.addingTimeInterval(-gaps.reduce(0, +))

        var out: [SeedMessage] = []
        out.reserveCapacity(count)
        for index in 0..<count {
            if index > 0 { date = date.addingTimeInterval(gaps[index - 1]) }
            if index == 0 {
                out.append(SeedMessage(
                    role: "assistant",
                    content: "Hi \(userName)! I'm \(coachName), your coach 💚 I'm here whenever you want to check in, ask a question, or just need a little encouragement.",
                    createdAt: date, isSystemSeed: true))
            } else if (count - 1 - index) % 2 == 1 {
                // Alternating, counted from the end, so the conversation always ends on a reply.
                out.append(SeedMessage(role: "user", content: userLine(index), createdAt: date, isSystemSeed: false))
            } else {
                out.append(SeedMessage(role: "assistant", content: coachLine(index), createdAt: date, isSystemSeed: false))
            }
        }
        return out
    }

    private static let userLines = [
        "How am I doing this week?",
        "I had the chicken bowl again for lunch. Was that a good call?",
        "Slept badly last night and I really don't feel like training today. Should I push through it or take the day?",
        "What should I eat before the gym?",
        "Can you explain why my weight jumped two pounds overnight? I ate the same as always and I'm a bit thrown by it.",
        "ok",
        "Give me three high-protein snacks I can keep at my desk.",
        "I'm travelling Thursday to Sunday. How do I keep this on track without logging every single thing?",
    ]

    private static let coachLines = [
        "Really well. Your trend is moving the way you want, and you've logged most days this week. That consistency is what makes it stick.",
        "Good call. A bowl like that covers a big part of your protein for the day.\n\n- **Protein:** about 45 g\n- **Carbs:** rice, so you'll have fuel for training\n- **Watch:** the sauce is where the extra calories hide\n\nIf you want it a little lighter, ask for half the rice and double the greens.",
        "One rough night doesn't undo anything. Here's how I'd think about it:\n\n1. If you feel flat but fine, do a shorter session and keep the weights moderate.\n2. If you feel run down, walk for twenty minutes and call it a win.\n3. Either way, eat normally and get to bed a little earlier tonight.\n\nRest is part of the plan, not a break from it.",
        "Something easy to digest with carbs and a bit of protein, about an hour before: a banana with yogurt, toast with peanut butter, or a small bowl of oats.",
        "## What a jump like that usually is\n\nAlmost always water, not fat. A salty dinner, a hard workout, a late meal or a poor night of sleep can each hold a pound or two for a day.\n\n---\n\nThat is exactly why the app shows your **trend** and not the single reading: the trend barely moved. Give it two or three days and it will settle.",
        "Sounds good 💚",
        "Three that keep well:\n\n- Jerky or a meat stick (about 10 g each)\n- Roasted edamame or chickpeas (about 12 g a handful)\n- A protein bar you actually like (about 20 g)\n\nKeep one in your bag too, so a long afternoon doesn't end at the vending machine.",
        "You don't need to log everything on a trip. Pick *one* anchor and let the rest go:\n\n- Protein at every meal, **or**\n- A walk each day, **or**\n- Just the weigh-in when you're back\n\nA few relaxed days won't move your trend much. Coming back to your routine on Monday is what counts.",
    ]

    private static func userLine(_ index: Int) -> String {
        "\(userLines[(index / 2) % userLines.count]) (#\(index))"
    }

    private static func coachLine(_ index: Int) -> String {
        "\(coachLines[((index - 1) / 2) % coachLines.count])\n\n(#\(index))"
    }

    /// Replaces the stored conversation with the seeded one when `--demo-long-chat <n>` asks
    /// for a different length than the store holds. A second launch with the same argument
    /// changes nothing, so it measures a cold open of an existing conversation.
    @MainActor
    static func seedLongChatIfRequested(_ context: ModelContext, now: Date = .now) {
        guard let count = longChatCount else { return }
        guard let profile = UserProfile.primary(of: (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []) else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<ChatMessage>())) ?? 0
        guard existing != count else { return }

        try? context.delete(model: ChatMessage.self)
        let coach = profile.coachName.isEmpty ? "Vita" : profile.coachName
        for seed in longChat(count: count, coachName: coach,
                             userName: profile.name.isEmpty ? "there" : profile.name, now: now) {
            context.insert(ChatMessage(role: seed.role, content: seed.content,
                                       createdAt: seed.createdAt, isSystemSeed: seed.isSystemSeed))
        }
        try? context.save()
        print("CHATDEBUG seeded \(count) messages")
    }
}

// MARK: - Load-time probe

/// Records how long the chat took to become usable after launch, and how much memory the
/// process holds once it is. Enabled by `--chat-probe`; appends one JSON line per event to
/// `tmp/chat-probe.log` in the app's data container and prints the same line.
///
/// "Usable" is the moment the newest message's row has appeared on screen AND the main
/// queue has run again afterwards, so it includes the fetch, the layout and the scroll.
enum ChatLoadProbe {
    static let isEnabled = ChatDebug.has("--chat-probe")

    /// When the process started, from the kernel, so the fetch that runs before a view's
    /// first `body` is inside the measurement.
    static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return Date() }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }()

    private static var viewInit: Date?
    private static var firstBody: Date?
    private static var reportedUsable = false

    static func markViewInit() {
        guard isEnabled, viewInit == nil else { return }
        _ = processStart
        viewInit = Date()
    }

    static func markFirstBody() {
        guard isEnabled, firstBody == nil else { return }
        firstBody = Date()
    }

    /// Call from the newest row's `onAppear`. `rowsInStore` is every stored message;
    /// `rowsLoaded` is how many the view fetched.
    static func markNewestRowAppeared(rowsInStore: Int, rowsLoaded: Int) {
        guard isEnabled, !reportedUsable else { return }
        reportedUsable = true
        let appeared = Date()
        DispatchQueue.main.async {
            let usable = Date()
            write([
                "event": "usable",
                "rows_in_store": rowsInStore,
                "rows_loaded": rowsLoaded,
                "launch_to_usable_ms": ms(processStart, usable),
                "view_init_to_usable_ms": viewInit.map { ms($0, usable) } ?? -1,
                "first_body_to_usable_ms": firstBody.map { ms($0, usable) } ?? -1,
                "newest_row_to_idle_ms": ms(appeared, usable),
                "footprint_mb": footprintMB(),
            ])
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                write(["event": "settled", "rows_in_store": rowsInStore, "rows_loaded": rowsLoaded,
                       "footprint_mb": footprintMB()])
            }
        }
    }

    /// A free-form measurement line (scroll anchoring checks, paging).
    static func note(_ event: String, _ fields: [String: Any] = [:]) {
        guard isEnabled else { return }
        var line = fields
        line["event"] = event
        line["footprint_mb"] = footprintMB()
        write(line)
    }

    private static func ms(_ from: Date, _ to: Date) -> Int { Int((to.timeIntervalSince(from) * 1000).rounded()) }

    /// The process's physical footprint, the number Xcode's memory gauge shows.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return (Double(info.phys_footprint) / 1_048_576 * 10).rounded() / 10
    }

    private static func write(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        print("CHATPROBE \(line)")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("chat-probe.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? Data((line + "\n").utf8).write(to: url)
        }
    }
}

// MARK: - Scripted replies and scripted steps

/// Answers the coach's model calls from a canned script, in Anthropic's wire format, so a
/// state that needs a provider (a reply, a tool proposal, a 429) can be put on screen with
/// no key and no network. The engine and the client run exactly as they do in the app; only
/// the transport is replaced.
final class DebugChatTransport: AITransport, @unchecked Sendable {
    let script: String
    private let lock = NSLock()
    private var calls = 0

    init(script: String) { self.script = script }

    private func nextCall() -> Int {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return calls
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let call = nextCall()
        try? await Task.sleep(for: .milliseconds(900))   // long enough to see the typing indicator
        func respond(_ status: Int, _ json: [String: Any], headers: [String: String] = [:]) throws -> (Data, URLResponse) {
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: headers)!
            return (try JSONSerialization.data(withJSONObject: json), response)
        }
        func text(_ value: String, stop: String = "end_turn") -> [String: Any] {
            ["model": "debug", "content": [["type": "text", "text": value]], "stop_reason": stop]
        }
        func tool(_ name: String, _ input: [String: Any]) -> [String: Any] {
            ["model": "debug", "stop_reason": "tool_use",
             "content": [["type": "tool_use", "id": "debug_call_\(call)", "name": name, "input": input]]]
        }
        func error(_ type: String, _ message: String) -> [String: Any] {
            ["type": "error", "error": ["type": type, "message": message]]
        }
        switch script {
        case "offline": throw URLError(.notConnectedToInternet)
        case "timeout": throw URLError(.timedOut)
        case "401": return try respond(401, error("authentication_error", "invalid x-api-key"))
        case "429": return try respond(429, error("rate_limit_error", "Rate limit reached."),
                                       headers: ["retry-after": "45"])
        case "500": return try respond(500, error("api_error", "Internal server error"))
        case "529": return try respond(529, error("overloaded_error", "Overloaded"), headers: ["retry-after": "30"])
        case "flaky":
            // Fails once, then answers: what a Retry looks like when it works.
            if call == 1 { throw URLError(.notConnectedToInternet) }
            return try respond(200, text("I'm back. Thanks for trying again 💚 Where were we?"))
        case "cutoff": return try respond(200, text("Here is the start of a plan for your week. On Monday,", stop: "max_tokens"))
        case "tool":
            return try respond(200, call == 1 ? tool("log_water", ["oz": 16])
                                              : text("Logged **16 oz** of water. Nice and steady 💧"))
        case "confirm":
            return try respond(200, call == 1 ? tool("set_step_goal", ["steps": 10000])
                                              : text("Done. Your new step goal is **10,000** a day."))
        default:
            return try respond(200, text("That's a good question. Short answer: **yes**, and here is why.\n\n- Your trend is what counts, not one reading.\n- Protein at each meal keeps you full.\n\nWant me to look at this week with you?"))
        }
    }
}

extension ChatDebug {

    /// `--chat-debug-script <name>`: route this engine's model calls to the canned script.
    @MainActor
    static func configure(_ engine: CoachTurnEngine) {
        ChatScrollBox.autoLoadDisabled = steps.contains("hold")
        guard let script = value(after: "--chat-debug-script") else { return }
        engine.env.runtime = AIRuntime(provider: .anthropic, apiKey: "debug-key-not-real",
                                       transport: DebugChatTransport(script: script))
    }

    static var steps: [String] {
        (value(after: "--chat-debug-do") ?? "").split(separator: ",").map(String.init)
    }

    /// `--chat-debug-do`: run the steps one a second, starting once the chat has settled.
    @MainActor
    static func runScript(engine: CoachTurnEngine, transcript: ChatTranscript,
                          center: AskVitaCenter?, scrollToTop: @escaping () -> Void) {
        let steps = self.steps.filter { $0 != "hold" }
        guard !steps.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            for step in steps {
                if step == "top" {
                    scrollToTop()
                } else if step.hasPrefix("send:") {
                    engine.send(text: String(step.dropFirst(5)))
                } else if step == "quote", let reply = transcript.rows.last(where: { !$0.isUser && !$0.isDecision }) {
                    let sentence = reply.content.components(separatedBy: "\n").first ?? reply.content
                    center?.quote(sentence)
                }
                try? await Task.sleep(for: .milliseconds(1000))
            }
        }
    }

    // MARK: Is a prepended page held in place?

    /// Where each realized row is on screen (global minY), written by `chatProbeFrame`.
    @MainActor static var rowFrames: [UUID: CGFloat] = [:]

    /// Logs where the anchor row is before a page is prepended and again after, so "the
    /// scroll position is stable" is a measured number (`moved_pt`) and not an impression.
    @MainActor
    static func notePrepend(anchor: UUID?, phase: String, loaded: Int = 0) {
        guard ChatLoadProbe.isEnabled, let anchor else { return }
        struct Before { static var minY: CGFloat? }
        let minY = rowFrames[anchor]
        if phase == "before" {
            Before.minY = minY
        } else {
            ChatLoadProbe.note("prepend", [
                "anchor_before_y": Before.minY.map { Double($0) } ?? -1,
                "anchor_after_y": minY.map { Double($0) } ?? -1,
                "moved_pt": (Before.minY != nil && minY != nil) ? Double(abs(minY! - Before.minY!)) : -1,
                "rows_loaded": loaded,
            ])
        }
    }
}

extension View {
    /// Records the row's position on screen while `--chat-probe` is on; nothing otherwise.
    @ViewBuilder
    func chatProbeFrame(_ id: UUID) -> some View {
        if ChatLoadProbe.isEnabled {
            onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { minY in
                ChatDebug.rowFrames[id] = minY
            }
        } else {
            self
        }
    }
}
#endif
