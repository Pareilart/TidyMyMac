import AppKit
import Foundation

struct InstalledApp: Identifiable, Sendable {
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let size: Int64
    var id: URL { url }
}

enum AppScanner {
    /// Dossiers de ~/Library où les applications laissent des données.
    private static let leftoverDirectories = [
        "Application Support", "Application Scripts", "Caches", "Containers", "Group Containers",
        "Preferences", "Preferences/ByHost", "Saved Application State", "Logs",
        "HTTPStorages", "WebKit", "Cookies", "LaunchAgents",
    ]

    static func installedApps() -> [InstalledApp] {
        let roots = [URL(fileURLWithPath: "/Applications"), FS.home.appendingPathComponent("Applications")]
        var bundles: [URL] = []
        for root in roots {
            for url in FS.children(of: root) {
                if url.pathExtension == "app" {
                    bundles.append(url)
                } else if FS.isDirectory(url) {
                    bundles += FS.children(of: url).filter { $0.pathExtension == "app" }
                }
            }
        }
        return bundles.compactMap { url -> InstalledApp? in
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier,
                  !bundleID.hasPrefix("com.apple.") else { return nil }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            return InstalledApp(url: url, name: name, bundleID: bundleID, version: version, size: FS.size(of: url))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Fichiers de ~/Library associés à l'application par son identifiant ou son nom exact.
    static func leftovers(for app: InstalledApp) -> [URL] {
        let bundleID = app.bundleID.lowercased()
        let names: Set<String> = [app.name.lowercased(), app.url.deletingPathExtension().lastPathComponent.lowercased()]
        var found: [URL] = []
        for directory in leftoverDirectories {
            for child in FS.children(of: FS.library.appendingPathComponent(directory)) {
                let name = child.lastPathComponent.lowercased()
                let base = (name as NSString).deletingPathExtension
                if name == bundleID || base == bundleID
                    || name.hasPrefix(bundleID + ".")
                    || name.hasSuffix("." + bundleID)
                    || names.contains(name) || names.contains(base) {
                    found.append(child)
                }
            }
        }
        return found
    }
}

@MainActor
final class AppsModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var loading = false
    @Published var sortBySize = false
    @Published var leftovers: [ScanItem] = []
    @Published var message: String?
    @Published var selection: URL? {
        didSet { loadLeftovers() }
    }

    private var leftoverTask: Task<Void, Never>?

    var selectedApp: InstalledApp? { apps.first { $0.id == selection } }
    var sortedApps: [InstalledApp] { sortBySize ? apps.sorted { $0.size > $1.size } : apps }

    func load() async {
        loading = true
        apps = await Task.detached(priority: .userInitiated) { AppScanner.installedApps() }.value
        loading = false
    }

    private func loadLeftovers() {
        leftoverTask?.cancel()
        leftovers = []
        message = nil
        guard let app = selectedApp else { return }
        leftoverTask = Task {
            let found = await Task.detached(priority: .userInitiated) {
                AppScanner.leftovers(for: app).map { ScanItem(url: $0, size: FS.size(of: $0), selected: true) }
            }.value
            if !Task.isCancelled && selection == app.id {
                leftovers = found
            }
        }
    }

    func uninstall(_ app: InstalledApp) async {
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
            running.terminate()
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let targets = [app.url] + leftovers.filter(\.selected).map(\.url)
        let freed = app.size + leftovers.selectedSize
        let failed = Remover.remove(targets, permanently: false)
        var succeeded = true
        if !failed.isEmpty {
            succeeded = await Remover.recycleWithFinder(failed)
        }
        if succeeded {
            apps.removeAll { $0.id == app.id }
            selection = nil
            Stats.record(freed: freed)
            message = localized("\(app.name) a été placée dans la Corbeille avec ses données : \(freed.formattedBytes) libérés.")
        } else {
            message = localized("Certains fichiers de \(app.name) n'ont pas pu être supprimés.")
        }
    }

    /// Supprime les données de l'application sans toucher à l'application elle-même.
    func reset(_ app: InstalledApp) async {
        let selected = leftovers.filter(\.selected)
        let failed = Remover.remove(selected.map(\.url), permanently: false)
        let failedSet = Set(failed)
        let freed = selected.filter { !failedSet.contains($0.url) }.totalSize
        Stats.record(freed: freed)
        loadLeftovers()
        message = failed.isEmpty
            ? localized("Les données de \(app.name) ont été placées dans la Corbeille : \(freed.formattedBytes) libérés.")
            : localized("\(failed.count) fichier(s) n'ont pas pu être supprimés.")
    }
}
