import Foundation
import Darwin
import OSLog

protocol UsageProvider: Sendable {
    func fetchUsage() async throws -> UsageSnapshot
    func shutdown() async
}

extension UsageProvider {
    func shutdown() async {}
}

/// Follow along with: log stream --predicate 'subsystem == "local.usagebar"' --level debug
enum AppLog {
    static let subsystem = "local.usagebar"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let provider = Logger(subsystem: subsystem, category: "provider")
    static let store = Logger(subsystem: subsystem, category: "store")

    /// os_log output is invisible in a terminal, so mirror a line to stderr when there is one.
    /// Launched from Finder or launchd there is no tty and nothing is written.
    static func terminal(_ message: @autoclosure () -> String) {
        guard isatty(STDERR_FILENO) == 1 else { return }
        FileHandle.standardError.write(Data((message() + "\n").utf8))
    }
}

extension Error {
    /// Server text may carry account metadata, so only ever log our own mapped case.
    var logLabel: String {
        (self as? UsageProviderError).map(String.init(describing:)) ?? String(describing: type(of: self))
    }
}

extension Duration {
    /// Whole milliseconds; a Duration's own description logs nine noisy fractional digits.
    var milliseconds: Int64 {
        components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
    }
}
