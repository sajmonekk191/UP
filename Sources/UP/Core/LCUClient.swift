import Foundation

enum LCUError: LocalizedError {
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case let .http(code, message): "LCU \(code): \(message)"
        }
    }
}

/// Trusts the self-signed certificates the League client and game serve on localhost only.
final class LocalhostTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           space.host == "127.0.0.1" || space.host == "localhost",
           let trust = space.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

let localhostSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 10
    return URLSession(configuration: config, delegate: LocalhostTrustDelegate(), delegateQueue: nil)
}()

let jsonDecoder = JSONDecoder()

/// REST client for the League client's local API.
final class LCUClient: @unchecked Sendable {
    let credentials: LCUCredentials

    init(credentials: LCUCredentials) {
        self.credentials = credentials
    }

    var baseURL: URL { URL(string: "https://127.0.0.1:\(credentials.port)")! }

    @discardableResult
    func request(_ method: String, _ path: String, json: Any? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = method
        request.setValue(credentials.authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed])
        }
        let (data, response) = try await localhostSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw LCUError.http(status, message ?? String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        try jsonDecoder.decode(T.self, from: try await request("GET", path))
    }

    func post(_ path: String, _ json: Any? = nil) async throws { try await request("POST", path, json: json) }
    func put(_ path: String, _ json: Any? = nil) async throws { try await request("PUT", path, json: json) }
    func patch(_ path: String, _ json: Any? = nil) async throws { try await request("PATCH", path, json: json) }
    func delete(_ path: String) async throws { try await request("DELETE", path) }
}
