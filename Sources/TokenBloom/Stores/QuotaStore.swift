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
    private(set) var weather: WeatherSnapshot?
    private(set) var locationStatusKey: String?
    private(set) var codexResetCredits: [String: CodexResetCredits] = [:]
    private(set) var codexHomes: [URL]

    private let weatherClient = WeatherClient()
    private let locationClient = LocationClient()
    private let logger = Logger(subsystem: "com.cmsjcm.TokenBloom", category: "quota")
    private var activityTask: Task<Void, Never>?
    private var weatherTask: Task<Void, Never>?
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

    var isConsuming: Bool { !activeProviderIds.isEmpty }

    func isConsuming(_ provider: ProviderUsage) -> Bool {
        activeProviderIds.contains(provider.id)
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
        weatherTask = Task { await monitorWeather() }
        defer {
            activityTask?.cancel()
            weatherTask?.cancel()
            codexTask?.cancel()
        }
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            await refresh()
        }
    }

    private func monitorWeather() async {
        while !Task.isCancelled {
            do {
                let location = try await locationClient.currentLocation()
                let locationName = await locationClient.displayName(for: location, language: .simplifiedChinese)
                let englishLocationName = await locationClient.displayName(for: location, language: .english)
                weather = try await weatherClient.fetch(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    locationName: locationName,
                    englishLocationName: englishLocationName
                )
                locationStatusKey = nil
            } catch LocationClient.LocationError.permissionDenied {
                weather = nil
                locationStatusKey = "location.permissionDenied"
            } catch LocationClient.LocationError.servicesDisabled {
                weather = nil
                locationStatusKey = "location.servicesDisabled"
            } catch {
                locationStatusKey = "location.weatherFailed"
            }
            try? await Task.sleep(for: .seconds(600))
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        guard codexTask == nil else { return }

        let accounts = codexAccounts
        codexTask = Task { [weak self] in
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
            let detected = detectLocalActivity()
            activeProviderIds = detected
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func detectLocalActivity(now: Date = .now) -> Set<String> {
        return Set(codexAccounts.compactMap { account in
            return hasRecentSessionActivity(in: account.home, now: now) ? account.id : nil
        })
    }

    private func hasRecentSessionActivity(in home: URL, now: Date) -> Bool {
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

    private func hasRecentDatabaseActivity(in home: URL) -> Bool {
        let database = home.appendingPathComponent("logs_2.sqlite")
        guard FileManager.default.fileExists(atPath: database.path) else { return false }

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
