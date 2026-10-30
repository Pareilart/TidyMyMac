import AppKit
import Foundation
@preconcurrency import UserNotifications

/// Version sémantique (« 1.4.2 », « v1.4.2 », « 1.5.0-beta.1 »).
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let numbers: [Int]
    let prerelease: String?
    let raw: String

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: "-", maxSplits: 1)
        guard let core = parts.first else { return nil }
        let numbers = core.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, !numbers.contains(nil) else { return nil }
        self.numbers = numbers.compactMap { $0 }
        self.prerelease = parts.count > 1 ? String(parts[1]) : nil
        self.raw = text
    }

    static let current = AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        ?? AppVersion("0.0.0")!

    var description: String { raw }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let right = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if left != right { return left < right }
        }
        // Une préversion passe avant la version finale : 1.0.0-beta < 1.0.0.
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, _): return false
        case (_, nil): return true
        case let (left?, right?): return left.compare(right, options: .numeric) == .orderedAscending
        }
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

struct Release: Equatable, Sendable {
    let version: AppVersion
    let title: String
    let notes: String
    let pageURL: URL
    let downloadURL: URL?
    let publishedAt: Date?
}

/// Vérifie la dernière release publiée sur GitHub (`TMMReleasesRepository` dans Info.plist, au format « owner/repo »).
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case notConfigured
        case checking
        case upToDate
        case available(Release)
        case failed(String)
    }

    static let automaticChecksKey = "checkForUpdates"
    private static let skippedVersionKey = "skippedVersion"
    private static let notifiedVersionKey = "lastNotifiedVersion"
    private static let interval: UInt64 = 24 * 3600 * 1_000_000_000

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheck: Date?
    @Published var showDetails = false

    let current = AppVersion.current
    private let repository = (Bundle.main.object(forInfoDictionaryKey: "TMMReleasesRepository") as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    private var pollTask: Task<Void, Never>?

    var isConfigured: Bool { repository.split(separator: "/").count == 2 }

    var availableRelease: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    private var automaticChecks: Bool {
        UserDefaults.standard.object(forKey: Self.automaticChecksKey) as? Bool ?? true
    }

    /// Vérifie au lancement, puis toutes les 24 heures tant que l'app tourne.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                if automaticChecks {
                    await check(userInitiated: false)
                }
                try? await Task.sleep(nanoseconds: Self.interval)
            }
        }
    }

    func check(userInitiated: Bool) async {
        guard isConfigured else {
            state = .notConfigured
            return
        }
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            lastCheck = Date()
            let skipped = UserDefaults.standard.string(forKey: Self.skippedVersionKey)
            if release.version > current && (userInitiated || release.version.raw != skipped) {
                state = .available(release)
                if userInitiated {
                    showDetails = true
                } else {
                    notify(release)
                }
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(localized("Impossible de joindre GitHub"))
        }
    }

    func download(_ release: Release) {
        NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
        showDetails = false
    }

    func skip(_ release: Release) {
        UserDefaults.standard.set(release.version.raw, forKey: Self.skippedVersionKey)
        state = .upToDate
        showDetails = false
    }

    private func fetchLatestRelease() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TidyMyMac/\(current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(GitHubRelease.self, from: data)
        guard let version = AppVersion(payload.tagName) else { throw URLError(.cannotParseResponse) }
        return Release(
            version: version,
            title: payload.name ?? payload.tagName,
            notes: payload.body ?? "",
            pageURL: payload.htmlUrl,
            downloadURL: payload.assets.first { $0.name.hasSuffix(".zip") }?.browserDownloadUrl,
            publishedAt: payload.publishedAt
        )
    }

    /// Une seule notification système par version.
    private func notify(_ release: Release) {
        guard Bundle.main.bundleIdentifier != nil,
              UserDefaults.standard.string(forKey: Self.notifiedVersionKey) != release.version.raw else { return }
        UserDefaults.standard.set(release.version.raw, forKey: Self.notifiedVersionKey)

        let content = UNMutableNotificationContent()
        content.title = localized("TidyMyMac \(release.version.raw) est disponible")
        content.body = localized("Vous utilisez la version \(current.raw). Ouvrez TidyMyMac pour voir les nouveautés.")
        let request = UNNotificationRequest(identifier: "update-\(release.version)", content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { center.add(request) }
        }
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: URL
    let publishedAt: Date?
    let assets: [Asset]
}
