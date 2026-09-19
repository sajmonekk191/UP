import Foundation

/// Connection credentials of the running League client (LCU).
struct LCUCredentials: Equatable, Sendable {
    let port: Int
    let password: String

    var authHeader: String {
        "Basic " + Data("riot:\(password)".utf8).base64EncodedString()
    }
}

enum LockfileLocator {
    static let candidatePaths = [
        "/Applications/League of Legends.app/Contents/LoL/lockfile",
        NSHomeDirectory() + "/Applications/League of Legends.app/Contents/LoL/lockfile",
    ]

    /// Finds credentials from the client process arguments, falling back to the lockfile.
    static func find() -> LCUCredentials? {
        fromProcessList() ?? candidatePaths.lazy.compactMap(fromLockfile).first
    }

    static func fromLockfile(_ path: String) -> LCUCredentials? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count >= 5, let port = Int(parts[2]) else { return nil }
        return LCUCredentials(port: port, password: String(parts[3]))
    }

    static func fromProcessList() -> LCUCredentials? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-ww", "-o", "args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        for line in output.split(separator: "\n") where line.contains("LeagueClientUx") && line.contains("--app-port=") {
            guard let port = argument("--app-port=", in: line).flatMap(Int.init),
                  let token = argument("--remoting-auth-token=", in: line) else { continue }
            return LCUCredentials(port: port, password: token)
        }
        return nil
    }

    private static func argument(_ key: String, in line: Substring) -> String? {
        guard let range = line.range(of: key) else { return nil }
        let rest = line[range.upperBound...]
        let value = rest.prefix { $0 != " " && $0 != "\"" }
        return value.isEmpty ? nil : String(value)
    }
}
