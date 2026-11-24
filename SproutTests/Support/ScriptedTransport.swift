import Foundation
@testable import Sprout

/// A transport that answers from a queue of scripted provider responses and records
/// every request it was handed. Lets the full client path (request build, headers,
/// retry, parse, usage accounting) run with no network and no key.
final class ScriptedTransport: AITransport, @unchecked Sendable {

    struct Reply {
        var status: Int
        var body: Data

        static func json(_ status: Int = 200, _ object: [String: Any]) -> Reply {
            // swiftlint:disable:next force_try
            Reply(status: status, body: try! JSONSerialization.data(withJSONObject: object))
        }
    }

    enum Failure: Error { case scriptExhausted }

    private let lock = NSLock()
    private var queue: [Reply]
    private var recorded: [URLRequest] = []

    init(_ replies: [Reply]) { queue = replies }

    var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    /// The JSON body of the n-th request the client sent.
    func body(_ index: Int = 0) -> [String: Any] {
        let all = requests
        guard index < all.count, let data = all[index].httpBody,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return obj
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let reply: Reply = try {
            lock.lock(); defer { lock.unlock() }
            recorded.append(request)
            guard !queue.isEmpty else { throw Failure.scriptExhausted }
            return queue.removeFirst()
        }()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        return (reply.body, response)
    }
}

/// Collects the usage reports of the calls made inside one scoped runtime.
final class UsageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AIUsage] = []

    func record(_ usage: AIUsage) {
        lock.lock(); defer { lock.unlock() }
        items.append(usage)
    }

    var all: [AIUsage] {
        lock.lock(); defer { lock.unlock() }
        return items
    }
}
