import Foundation

/// Lets a log line through once, then counts its repeats instead of writing them.
///
/// The pairing screen polls every four seconds. With no connection each pass used to write
/// the same few lines, about 900 an hour into a 600-line ring, so the one line that said
/// why pairing failed was gone within the hour. A line is written the first time it is
/// seen and then at most once per `window`, with how many times it repeated in between.
///
/// Pure: the caller passes the time.
struct RepeatedLineFilter {
    let window: TimeInterval
    private var seen: [String: (lastWritten: Date, repeats: Int)] = [:]

    init(window: TimeInterval = 300) {
        self.window = window
    }

    /// The text to write for `line` at `now`, or nil when it is a repeat inside the window.
    mutating func admit(_ line: String, at now: Date) -> String? {
        guard let entry = seen[line] else {
            prune(before: now)
            seen[line] = (now, 0)
            return line
        }
        let age = now.timeIntervalSince(entry.lastWritten)
        if age >= 0, age < window {
            seen[line] = (entry.lastWritten, entry.repeats + 1)
            return nil
        }
        seen[line] = (now, 0)
        guard entry.repeats > 0 else { return line }
        let minutes = max(1, Int((age / 60).rounded()))
        return "\(line) (repeated \(entry.repeats) more times in the last \(minutes) min)"
    }

    /// Forget lines not seen for two windows, so the table cannot grow without bound.
    private mutating func prune(before now: Date) {
        guard seen.count >= 64 else { return }
        seen = seen.filter { now.timeIntervalSince($0.value.lastWritten) < window * 2 }
    }
}

/// The sync services' way into the field Diagnostics log: the same lines as before, minus
/// the repeats. (`BuddyViewModel` filters its own lines with its own clock.)
enum BuddyLog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var filter = RepeatedLineFilter()

    static func sync(_ line: String, at now: Date = Date()) {
        lock.lock()
        let out = filter.admit(line, at: now)
        lock.unlock()
        if let out { Diagnostics.shared.log(out, .sync) }
    }
}
