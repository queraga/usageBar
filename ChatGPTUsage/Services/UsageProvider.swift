protocol UsageProvider: Sendable {
    func fetchUsage() async throws -> UsageSnapshot
    func shutdown() async
}

extension UsageProvider {
    func shutdown() async {}
}
