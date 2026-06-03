import SwiftUI
import UIKit

/// A lightweight, on-device diagnostic log — **hidden from the user**, reachable from
/// Settings by tapping the version line 7×. It captures key events (coach sends/replies,
/// AI + network errors, app lifecycle) so if something breaks in the field, we can read
/// exactly where it stopped without a debugger attached — just open Diagnostics, Share
/// the log, and paste it back. Capped and persisted to the app-group container so it
/// survives relaunches.
///
/// Deliberately tiny and dependency-free. `log(...)` is safe to call from any thread.
final class Diagnostics: @unchecked Sendable {
    static let shared = Diagnostics()

    enum Category: String { case app, coach, ai, food, sync, error }

    private let queue = DispatchQueue(label: "com.bryanram.victoria.diagnostics")
    private var buffer: [String] = []
    private let maxLines = 600
    private let fileURL: URL?
    private let fmt: DateFormatter

    private init() {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        fmt = f

        let group = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.bryanram.victoria")
        let dir = group ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        fileURL = dir?.appendingPathComponent("diagnostics.log")

        // Restore the tail from disk so the log spans launches.
        if let url = fileURL, let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
            buffer = Array(text.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init).suffix(maxLines))
        }
    }

    /// Append one timestamped line. Truncates long messages so a stray huge string
    /// can't bloat the log. Thread-safe.
    func log(_ message: String, _ category: Category = .app) {
        let when = Date()
        let trimmed = message.count > 500 ? String(message.prefix(500)) + "…" : message
        queue.async {
            let line = "\(self.fmt.string(from: when)) [\(category.rawValue)] \(trimmed)"
            self.buffer.append(line)
            if self.buffer.count > self.maxLines {
                self.buffer.removeFirst(self.buffer.count - self.maxLines)
            }
            if let url = self.fileURL {
                try? self.buffer.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            }
            #if DEBUG
            print("🩺 \(line)")
            #endif
        }
    }

    /// Full current log, oldest first.
    func dump() -> String { queue.sync { buffer.joined(separator: "\n") } }

    func clear() {
        queue.async {
            self.buffer.removeAll()
            if let url = self.fileURL { try? "".write(to: url, atomically: true, encoding: .utf8) }
        }
    }
}

/// The hidden diagnostics viewer (Settings → tap version 7×). Read-only log with
/// Share / Copy / Clear so Bryan can pull it off a field device and hand it back.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = Diagnostics.shared.dump()

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text.isEmpty ? "No diagnostics captured yet." : text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        Diagnostics.shared.clear()
                        text = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }
}
