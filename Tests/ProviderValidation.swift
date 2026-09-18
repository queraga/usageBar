import Foundation
import Darwin

@main
struct ProviderValidation {
    /// Timeouts and waits are deliberately tight so the timeout cases stay fast. Slower machines
    /// (CI runners paying a cold interpreter start) stretch them via USAGE_TEST_TIME_SCALE.
    static let timeScale = ProcessInfo.processInfo.environment["USAGE_TEST_TIME_SCALE"]
        .flatMap(Double.init) ?? 1
    static func seconds(_ value: Double) -> Double { value * timeScale }
    static func nanoseconds(_ value: Double) -> UInt64 { UInt64(seconds(value) * 1_000_000_000) }

    static func main() async throws {
        if CommandLine.arguments.contains("--live") {
            let provider = CodexUsageProvider()
            print("Executable: \(try CodexExecutableResolver.resolve().path)")
            do {
                for _ in 0..<2 {
                    let s = try await provider.fetchUsage()
                    print("Real: 5h left=\(s.fiveHour.remainingPercent), week left=\(s.weekly.remainingPercent), resets=\(s.fiveHour.resetAt!), \(s.weekly.resetAt!)")
                }
            } catch { await provider.shutdown(); throw error }
            await provider.shutdown()
            print("Live provider PASS")
            return
        }
        let base = URL(fileURLWithPath: CommandLine.arguments[1])
        let state = URL(fileURLWithPath: ProcessInfo.processInfo.environment["USAGE_TEST_STATE"]!)
        func make(_ mode: String) -> CodexUsageProvider {
            CodexUsageProvider(executable: base.appendingPathComponent(mode), initializationTimeout: seconds(0.4), requestTimeout: seconds(0.4))
        }
        func lines() throws -> [String] { try String(contentsOf: state, encoding: .utf8).split(separator: "\n").map(String.init) }
        let provider = make("good")
        async let a = provider.fetchUsage()
        async let b = provider.fetchUsage()
        let snapshots = try await [a,b]
        precondition(snapshots.allSatisfy { $0.fiveHour.remainingPercent == 75 && $0.weekly.remainingPercent == 58 })
        _ = try await provider.fetchUsage()
        let log = try lines()
        precondition(log.filter { $0.hasPrefix("start") }.count == 1)
        precondition(log.filter { $0.hasPrefix("read") }.count == 2)
        let pid = Int32(log[0].split(separator: " ")[1])!
        await provider.shutdown()
        precondition(kill(pid,0) == -1)
        print("PASS: split JSON, notifications, response IDs, reversed windows, concurrent fetch coalescing, process reuse and shutdown")
        for (mode,expected) in [("init-timeout","initializationTimeout"),("request-timeout","requestTimeout"),("malformed","malformedResponse"),("auth","authenticationUnavailable"),("exit","serverExited")] {
            let p = make(mode)
            do { _ = try await p.fetchUsage(); fatalError("Expected failure") }
            catch { precondition(String(describing:error) == expected, "Unexpected \(error)") }
            await p.shutdown()
            print("PASS: \(mode)")
        }
        // Restart the same provider after an unexpected child exit.
        let restartPath = base.appendingPathComponent("restart")
        try? FileManager.default.removeItem(at: restartPath)
        try FileManager.default.createSymbolicLink(at: restartPath, withDestinationURL: base.appendingPathComponent("exit"))
        // The fake selects by argv[0], so use a terminating executable for the first attempt.
        try FileManager.default.removeItem(at: restartPath)
        try "#!/bin/sh\nexit 1\n".write(to: restartPath, atomically:true, encoding:.utf8)
        try FileManager.default.setAttributes([.posixPermissions:0o755], ofItemAtPath:restartPath.path)
        let reconnect = make("restart")
        do { _ = try await reconnect.fetchUsage(); fatalError() } catch {}
        try FileManager.default.removeItem(at:restartPath)
        try FileManager.default.createSymbolicLink(at:restartPath, withDestinationURL:base.appendingPathComponent("good"))
        _ = try await reconnect.fetchUsage()
        await reconnect.shutdown()
        print("PASS: recovery on next refresh")
        let fallback = #"{"rateLimits":{"primary":null,"secondary":null},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":57,"windowDurationMins":10080,"resetsAt":1789910299},"secondary":{"usedPercent":47,"windowDurationMins":300,"resetsAt":1789585715}}}}"#
        let decoded = try JSONDecoder().decode(CodexRateLimits.self,from:Data(fallback.utf8)).snapshot()
        precondition(decoded.fiveHour.remainingPercent == 53)
        for raw in [fallback.replacingOccurrences(of:"57",with:"157"), fallback.replacingOccurrences(of:"10080",with:"60")] {
            do { _ = try JSONDecoder().decode(CodexRateLimits.self,from:Data(raw.utf8)).snapshot(); fatalError() } catch {}
        }
        print("PASS: fallback selection and malformed metric rejection")
        await testStore(base:base,state:state)
    }
    @MainActor static func testStore(base:URL,state:URL) async {
        let provider = CodexUsageProvider(executable:base.appendingPathComponent("good"))
        let before = (try! String(contentsOf:state, encoding:.utf8)).split(separator:"\n").filter{$0.hasPrefix("start")}.count
        let store = UsageStore(provider:provider)
        store.startAutomaticRefresh(interval:100_000_000)
        store.startAutomaticRefresh(interval:100_000_000)
        try? await Task.sleep(nanoseconds:nanoseconds(0.45))
        precondition(store.snapshot != nil)
        let after = (try! String(contentsOf:state, encoding:.utf8)).split(separator:"\n").filter{$0.hasPrefix("start")}.count
        precondition(after == before+1)
        await store.shutdown()
        let count = try! String(contentsOf:state, encoding:.utf8)
        try? await Task.sleep(nanoseconds:nanoseconds(0.15))
        precondition(count == (try! String(contentsOf:state, encoding:.utf8)))
        let faulty = FailsAfterSuccess()
        let stale = UsageStore(provider:faulty)
        await stale.refresh()
        let previous = stale.snapshot!.updatedAt
        await stale.refresh()
        precondition(stale.snapshot!.updatedAt == previous && stale.errorMessage!.contains("stale"))
        print("PASS: automatic refresh, single loop/process, stopped timer, preserved successful timestamp on error")
    }
}
actor FailsAfterSuccess: UsageProvider {
    var count=0
    func fetchUsage() async throws -> UsageSnapshot {
        count += 1
        if count>1 {throw UsageProviderError.requestTimeout}
        return UsageSnapshot(fiveHour:UsageMetric(usedPercent:25,resetAt:nil),weekly:UsageMetric(usedPercent:42,resetAt:nil),updatedAt:Date())
    }
}
