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

    /// Reads the port and token from the running client's arguments, as the kernel reports them.
    static func fromProcessList() -> LCUCredentials? {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        for pid in pids.prefix(Int(max(count, 0))) where pid > 0 && processName(pid) == "LeagueClientUx" {
            let args = arguments(of: pid)
            guard let port = args.lazy.compactMap({ value("--app-port=", in: $0) }).first.flatMap(Int.init),
                  let token = args.lazy.compactMap({ value("--remoting-auth-token=", in: $0) }).first else { continue }
            return LCUCredentials(port: port, password: token)
        }
        return nil
    }

    private static func processName(_ pid: pid_t) -> String? {
        var name = [CChar](repeating: 0, count: 64)
        guard proc_name(pid, &name, UInt32(name.count)) > 0 else { return nil }
        return String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Arguments of one of the user's processes, parsed from the kernel's argc, path and NUL-separated list.
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = buffer.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        return buffer[MemoryLayout<Int32>.size..<size].split(separator: 0).dropFirst().prefix(argc).map { String(decoding: $0, as: UTF8.self) }
    }

    private static func value(_ key: String, in argument: String) -> String? {
        guard argument.hasPrefix(key), argument.count > key.count else { return nil }
        return String(argument.dropFirst(key.count))
    }
}
