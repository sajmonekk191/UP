import Foundation

struct LCUEvent: Sendable {
    let uri: String
    let eventType: String
    let data: Data

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? jsonDecoder.decode(T.self, from: data)
    }
}

/// Subscribes to every JSON API event the League client publishes over its WAMP websocket.
final class LCUWebSocket: @unchecked Sendable {
    private let credentials: LCUCredentials
    private var task: URLSessionWebSocketTask?

    init(credentials: LCUCredentials) {
        self.credentials = credentials
    }

    /// Streams events until the socket closes.
    func events() -> AsyncThrowingStream<LCUEvent, Error> {
        var request = URLRequest(url: URL(string: "wss://127.0.0.1:\(credentials.port)/")!)
        request.setValue(credentials.authHeader, forHTTPHeaderField: "Authorization")
        let task = localhostSession.webSocketTask(with: request)
        self.task = task
        task.resume()

        return AsyncThrowingStream { continuation in
            let receiver = Task {
                do {
                    try await task.send(.string(#"[5, "OnJsonApiEvent"]"#))
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        if let event = Self.parse(message) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                receiver.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    func close() {
        task?.cancel(with: .goingAway, reason: nil)
    }

    private static func parse(_ message: URLSessionWebSocketTask.Message) -> LCUEvent? {
        let raw: Data
        switch message {
        case let .string(text): raw = Data(text.utf8)
        case let .data(data): raw = data
        @unknown default: return nil
        }
        guard let array = try? JSONSerialization.jsonObject(with: raw) as? [Any],
              array.count >= 3, (array[0] as? Int) == 8,
              let payload = array[2] as? [String: Any],
              let uri = payload["uri"] as? String else { return nil }
        let body = payload["data"] ?? NSNull()
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])) ?? Data()
        return LCUEvent(uri: uri, eventType: payload["eventType"] as? String ?? "", data: data)
    }
}
