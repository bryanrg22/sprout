#if DEBUG
import Foundation
import SwiftData
import Darwin

/// DEBUG-only launch arguments for the coach chat: a long seeded conversation and a
/// load-time probe. Nothing here is compiled into a Release build.
///
///     --demo-long-chat <n>     replace the conversation with n seeded messages
///     --chat-probe             log how long the chat took to become usable
///     --no-notification-prompt do not ask for notification permission at launch (a
///                              screenshot run cannot tap the alert away)
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
            } else if index % 2 == 1 {
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
        guard let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else { return }
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
#endif
