import Foundation
import AppKit
import Darwin
import OSLog

enum UsageProviderError: LocalizedError {
    case executableMissing, launchFailed, initializationTimeout, malformedResponse
    case windowsMissing, authenticationUnavailable, serverExited, requestTimeout, invalidUsage, serverRejected

    var errorDescription: String? {
        switch self {
        case .executableMissing: return "Codex was not found. Install or open ChatGPT/Codex, then refresh."
        case .launchFailed: return "Could not start Codex App Server."
        case .initializationTimeout: return "Codex App Server took too long to start."
        case .malformedResponse: return "Codex returned an unreadable response."
        case .windowsMissing: return "The 5-hour and weekly limits are unavailable."
        case .authenticationUnavailable: return "Sign in through ChatGPT/Codex, then refresh."
        case .serverExited: return "Codex App Server stopped. Refresh to reconnect."
        case .requestTimeout: return "The usage request timed out. Try refreshing."
        case .invalidUsage: return "Codex returned invalid usage values."
        case .serverRejected: return "Codex could not retrieve usage. Try refreshing."
        }
    }
}

enum CodexExecutableResolver {
    static func resolve() throws -> URL {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path]
        for directory in paths where directory.hasPrefix("/") {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("codex")
            if valid(url) { return url }
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            let url = app.appendingPathComponent("Contents/Resources/codex")
            if valid(url) { return url }
        }
        let fallback = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        if valid(fallback) { return fallback }
        AppLog.provider.error("No codex executable found in PATH, com.openai.codex, or /Applications/ChatGPT.app")
        throw UsageProviderError.executableMissing
    }

    private static func valid(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && !directory.boolValue && FileManager.default.isExecutableFile(atPath: url.path)
    }
}

struct CodexRateLimits: Decodable {
    struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Double?
    }
    struct Limit: Decodable {
        let limitId: String?
        let primary: Window?
        let secondary: Window?
        var windows: [Window] { [primary, secondary].compactMap { $0 } }
        var hasRequiredWindows: Bool {
            windows.filter { $0.windowDurationMins == 300 }.count == 1
                && windows.filter { $0.windowDurationMins == 10080 }.count == 1
        }
    }
    let rateLimits: Limit?
    let rateLimitsByLimitId: [String: Limit]?

    func snapshot() throws -> UsageSnapshot {
        let selected: Limit
        if let main = rateLimits, main.hasRequiredWindows { selected = main }
        else if let codex = rateLimitsByLimitId?["codex"], codex.hasRequiredWindows { selected = codex }
        else {
            let candidates = (rateLimitsByLimitId ?? [:]).values.filter(\.hasRequiredWindows)
            guard candidates.count == 1, let only = candidates.first else { throw UsageProviderError.windowsMissing }
            selected = only
        }
        func metric(_ minutes: Int) throws -> UsageMetric {
            guard let window = selected.windows.first(where: { $0.windowDurationMins == minutes }) else {
                throw UsageProviderError.windowsMissing
            }
            guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent) else { throw UsageProviderError.invalidUsage }
            if let reset = window.resetsAt, !reset.isFinite || reset <= 0 || reset > 253402300799 {
                throw UsageProviderError.invalidUsage
            }
            return UsageMetric(usedPercent: window.usedPercent, resetAt: window.resetsAt.map(Date.init(timeIntervalSince1970:)))
        }
        return try UsageSnapshot(fiveHour: metric(300), weekly: metric(10080), updatedAt: Date())
    }
}

actor CodexUsageProvider: UsageProvider {
    private var process: Process?
    private var retiringProcesses: [Process] = []
    private var input: Pipe?
    private var output: Pipe?
    private var readerTask: Task<Void, Never>?
    private var buffer = Data()
    private var generation = UUID()
    private var ready = false
    private var stopped = false
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var fetchTask: Task<UsageSnapshot, Error>?
    private let executableOverride: URL?
    private let initializationSeconds: Double
    private let requestSeconds: Double

    init(executable: URL? = nil, initializationTimeout: Double = 10, requestTimeout: Double = 15) {
        executableOverride = executable
        initializationSeconds = initializationTimeout
        requestSeconds = requestTimeout
    }

    func fetchUsage() async throws -> UsageSnapshot {
        guard !stopped else { throw UsageProviderError.serverExited }
        if let task = fetchTask { return try await task.value }
        let task = Task { try await self.performFetch() }
        fetchTask = task
        defer { fetchTask = nil }
        return try await task.value
    }

    private func performFetch() async throws -> UsageSnapshot {
        let started = ContinuousClock.now
        do {
            if !ready {
                try start()
                _ = try await request("initialize", params: ["clientInfo": ["name": "chatgpt_usage_menu", "title": "ChatGPT Usage", "version": "1.0"]], timeout: initializationSeconds)
                try send(["method": "initialized"])
                ready = true
                AppLog.provider.log("App Server initialized in \(started.duration(to: .now).milliseconds, privacy: .public)ms")
            }
            let data = try await request("account/rateLimits/read", timeout: requestSeconds)
            do {
                let snapshot = try JSONDecoder().decode(CodexRateLimits.self, from: data).snapshot()
                AppLog.provider.log("""
                    Usage read in \(started.duration(to: .now).milliseconds, privacy: .public)ms: \
                    5h used \(snapshot.fiveHour.usedPercent, format: .fixed(precision: 0), privacy: .public)%, \
                    week used \(snapshot.weekly.usedPercent, format: .fixed(precision: 0), privacy: .public)%
                    """)
                return snapshot
            }
            catch let error as UsageProviderError { throw error }
            catch { throw UsageProviderError.malformedResponse }
        } catch {
            AppLog.provider.error("Fetch failed after \(started.duration(to: .now).milliseconds, privacy: .public)ms: \(error.logLabel, privacy: .public)")
            disconnect(error)
            throw error
        }
    }

    private func start() throws {
        guard !stopped else { throw UsageProviderError.serverExited }
        retiringProcesses.removeAll { !$0.isRunning }
        let executable = try executableOverride ?? CodexExecutableResolver.resolve()
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = executable
        child.arguments = ["app-server", "--listen", "stdio://"]
        child.standardInput = stdin
        child.standardOutput = stdout
        // Never forward server diagnostic output, which may contain account metadata.
        child.standardError = FileHandle.nullDevice
        let token = UUID()
        generation = token
        // Preserve byte ordering across partial stdout reads.
        let chunks = AsyncStream<Data> { continuation in
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                continuation.yield(data)
                if data.isEmpty { continuation.finish() }
            }
        }
        readerTask = Task { [weak self] in
            for await data in chunks {
                guard !Task.isCancelled else { break }
                await self?.receive(data, generation: token)
            }
        }
        // A dead child must produce an error, never terminate the parent with SIGPIPE.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        child.terminationHandler = { [weak self] finished in
            AppLog.provider.debug("""
                pid \(finished.processIdentifier, privacy: .public) exited, \
                status \(finished.terminationStatus, privacy: .public)
                """)
            Task { await self?.exited(generation: token) }
        }
        process = child; input = stdin; output = stdout
        do { try child.run() }
        catch {
            AppLog.provider.error("Could not launch \(executable.path, privacy: .public)")
            disconnect(UsageProviderError.launchFailed)
            throw UsageProviderError.launchFailed
        }
        AppLog.provider.log("Launched \(executable.path, privacy: .public) as pid \(child.processIdentifier, privacy: .public)")
    }

    private func send(_ message: [String: Any]) throws {
        guard let process, process.isRunning, let input else { throw UsageProviderError.serverExited }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { throw UsageProviderError.serverExited }
    }

    private func request(_ method: String, params: [String: Any]? = nil, timeout: Double) async throws -> Data {
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            deadlines[id] = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) }
                catch { return }
                await self?.timedOut(id, initializing: method == "initialize")
            }
            do {
                var message: [String: Any] = ["id": id, "method": method]
                if let params { message["params"] = params }
                try send(message)
            } catch { disconnect(error) }
        }
    }

    private func receive(_ data: Data, generation token: UUID) {
        guard generation == token else { return }
        guard !data.isEmpty else { disconnect(UsageProviderError.serverExited); return }
        buffer.append(data)
        guard buffer.count <= 4 * 1024 * 1024 else { disconnect(UsageProviderError.malformedResponse); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.isEmpty { continue }
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                disconnect(UsageProviderError.malformedResponse); return
            }
            guard let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) else { continue }
            deadlines.removeValue(forKey: id)?.cancel()
            if let error = object["error"] as? [String: Any] {
                let message = (error["message"] as? String ?? "").lowercased()
                let auth = ["auth", "login", "log in", "sign in", "unauthorized", "401"].contains { message.contains($0) }
                continuation.resume(throwing: auth ? UsageProviderError.authenticationUnavailable : UsageProviderError.serverRejected)
            } else if let result = object["result"], JSONSerialization.isValidJSONObject(result),
                      let data = try? JSONSerialization.data(withJSONObject: result) {
                continuation.resume(returning: data)
            } else { continuation.resume(throwing: UsageProviderError.malformedResponse) }
        }
    }

    private func timedOut(_ id: Int, initializing: Bool) {
        guard pending[id] != nil else { return }
        let limit = initializing ? initializationSeconds : requestSeconds
        AppLog.provider.error("Request \(id, privacy: .public) timed out after \(limit, format: .fixed(precision: 1), privacy: .public)s")
        disconnect(initializing ? UsageProviderError.initializationTimeout : UsageProviderError.requestTimeout)
    }
    private func exited(generation token: UUID) {
        if generation == token { disconnect(UsageProviderError.serverExited) }
    }

    private func disconnect(_ error: Error) {
        if process != nil {
            AppLog.provider.debug("""
                Disconnecting on \(error.logLabel, privacy: .public), \
                \(self.pending.count, privacy: .public) request(s) pending
                """)
        }
        generation = UUID(); ready = false; buffer.removeAll()
        deadlines.values.forEach { $0.cancel() }; deadlines.removeAll()
        let requests = pending.values; pending.removeAll()
        requests.forEach { $0.resume(throwing: error) }
        readerTask?.cancel(); readerTask = nil
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        try? output?.fileHandleForReading.close()
        if let child = process, child.isRunning {
            retiringProcesses.append(child)
            child.terminate()
            // Bound cleanup even if the child ignores EOF/SIGTERM.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        process = nil; input = nil; output = nil
    }

    func shutdown() async {
        stopped = true
        disconnect(UsageProviderError.serverExited)
        fetchTask?.cancel()
        // Keep the parent alive until child cleanup has completed.
        let children = retiringProcesses
        for _ in 0..<40 {
            if !children.contains(where: \.isRunning) { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        for child in children where child.isRunning { kill(child.processIdentifier, SIGKILL) }
        retiringProcesses.removeAll()
    }
}
