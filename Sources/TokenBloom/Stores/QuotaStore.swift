import Foundation
import Observation
import OSLog

@MainActor @Observable
final class QuotaStore {
    private(set) var providers: [ProviderUsage] = []
    private(set) var lastUpdated: Date?
    private(set) var errorMessageKey: String?
    private(set) var isRefreshing = false
    private(set) var activeProviderIds: Set<String> = []
    private(set) var codexResetCredits: [String: CodexResetCredits] = [:]
    private(set) var codexHomes: [URL]

    private let logger = Logger(subsystem: "com.cmsjcm.TokenBloom", category: "quota")
    private var activityTask: Task<Void, Never>?
    private var codexTask: Task<Void, Never>?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaults = UserDefaults.standard.stringArray(forKey: "codexHomes") ?? []
        codexHomes = (0..<2).map { index in
            if let stored = defaults[safe: index], !stored.isEmpty {
                return URL(fileURLWithPath: stored, isDirectory: true)
            }
            return home.appendingPathComponent(index == 0 ? ".codex" : ".codex-2", isDirectory: true)
        }
    }

    var codexAccounts: [CodexAccountConfiguration] {
        codexHomes.enumerated().map { CodexAccountConfiguration(index: $0.offset + 1, home: $0.element) }
    }

    func resetCredits(for provider: ProviderUsage) -> CodexResetCredits? {
        codexResetCredits[provider.id]
    }

    var lowestRemaining: Double? {
        providers.flatMap { [$0.session?.remainingPercent, $0.weekly?.remainingPercent] }.compactMap { $0 }.min()
    }

    var health: QuotaHealth { QuotaHealth(remaining: lowestRemaining) }

    func setCodexHome(_ home: URL, for index: Int) {
        guard codexHomes.indices.contains(index) else { return }
        codexHomes[index] = home
        UserDefaults.standard.set(codexHomes.map(\.path), forKey: "codexHomes")
        providers.removeAll { $0.id == "codex-\(index + 1)" }
        codexResetCredits["codex-\(index + 1)"] = nil
        errorMessageKey = nil
        Task { await refresh() }
    }

    func start() async {
        activityTask = Task { await monitorLocalActivity() }
        defer {
            activityTask?.cancel()
            codexTask?.cancel()
        }
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            await refresh()
        }
    }

    func refresh() async {
        guard !isRefreshing, codexTask == nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let accounts = codexAccounts
        let task = Task { [weak self] in
            await withTaskGroup(of: (CodexAccountConfiguration, CodexDirectSnapshot?).self) { group in
                for account in accounts {
                    group.addTask {
                        (account, try? await CodexDirectClient().fetch(account: account))
                    }
                }
                var results: [(CodexAccountConfiguration, CodexDirectSnapshot?)] = []
                for await result in group { results.append(result) }
                guard let self, !Task.isCancelled else { return }
                self.applyCodex(results)
                self.codexTask = nil
            }
        }
        codexTask = task
        await task.value
    }

    private func applyCodex(_ results: [(CodexAccountConfiguration, CodexDirectSnapshot?)]) {
        var fresh = providers.filter { provider in
            !results.contains { $0.0.id == provider.id }
        }
        var succeeded = 0
        for (account, result) in results {
            guard let result else { continue }
            succeeded += 1
            fresh.append(result.provider)
            if let credits = result.resetCredits { codexResetCredits[account.id] = credits }
        }
        providers = fresh.sorted { $0.id < $1.id }
        lastUpdated = .now
        errorMessageKey = succeeded == 0 && providers.isEmpty ? "error.quotaUnavailable" : nil
        logger.info("Codex refresh completed: \(succeeded, privacy: .public)/\(results.count, privacy: .public) accounts")
    }

    private func monitorLocalActivity() async {
        while !Task.isCancelled {
            let accounts = codexAccounts
            let detected = await Task.detached(priority: .utility) {
                LocalActivityDetector.activeProviderIDs(in: accounts)
            }.value
            guard !Task.isCancelled else { return }
            activeProviderIds = detected
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

private enum LocalActivityDetector {
    static func activeProviderIDs(
        in accounts: [CodexAccountConfiguration],
        now: Date = .now
    ) -> Set<String> {
        Set(accounts.compactMap { account in
            hasRecentSessionActivity(in: account.home, now: now) ? account.id : nil
        })
    }

    private static func hasRecentSessionActivity(in home: URL, now: Date) -> Bool {
        let roots = [
            home.appendingPathComponent("sessions", isDirectory: true),
            home.appendingPathComponent("thread-writer-locks", isDirectory: true)
        ]
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: []
            ) else { continue }

            for case let fileURL as URL in enumerator {
                let isSession = fileURL.pathExtension == "jsonl"
                let isWriterLock = root.lastPathComponent == "thread-writer-locks"
                guard isSession || isWriterLock,
                      let values = try? fileURL.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate else { continue }
                if ActivityDetectionPolicy.isActive(modifiedAt: modified, now: now) { return true }
            }
        }
        return hasRecentDatabaseActivity(in: home)
    }

    private static func hasRecentDatabaseActivity(in home: URL) -> Bool {
        let database = home.appendingPathComponent("logs_2.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else { return false }
        let writeAheadLog = URL(fileURLWithPath: database.path + "-wal")
        let recentWrite = [database, writeAheadLog].contains { url in
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                return false
            }
            let age = Date.now.timeIntervalSince(modified)
            return age >= -1 && age <= 20
        }
        guard recentWrite else { return false }

        let query = """
        SELECT target || '|' || COALESCE(feedback_log_body, '')
        FROM logs
        WHERE ts >= strftime('%s', 'now') - 15
        ORDER BY ts DESC, ts_nanos DESC
        LIMIT 80;
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-batch", database.path, query]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        guard process.terminationStatus == 0,
              let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return false
        }
        let activityMarkers = [
            "submission_dispatch",
            "session_task.turn",
            "run_sampling_request",
            "item/started"
        ]
        return activityMarkers.contains { text.localizedCaseInsensitiveContains($0) }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum ActivityDetectionPolicy {
    static let recentWriteWindow: TimeInterval = 8

    static func isActive(modifiedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(modifiedAt)
        return age >= -1 && age <= recentWriteWindow
    }
}
