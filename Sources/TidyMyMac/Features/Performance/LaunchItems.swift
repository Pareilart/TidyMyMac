import AppKit
import Foundation

/// Agent ou daemon launchd (élément d'arrière-plan).
struct LaunchItem: Identifiable, Sendable {
    enum Scope: String, CaseIterable, Sendable {
        case userAgent, systemAgent, systemDaemon

        var title: String {
            switch self {
            case .userAgent: return localized("Utilisateur")
            case .systemAgent: return localized("Global")
            case .systemDaemon: return localized("Système")
            }
        }

        var order: Int {
            switch self {
            case .userAgent: return 0
            case .systemAgent: return 1
            case .systemDaemon: return 2
            }
        }

        var directory: URL {
            switch self {
            case .userAgent: return FS.library.appendingPathComponent("LaunchAgents")
            case .systemAgent: return URL(fileURLWithPath: "/Library/LaunchAgents")
            case .systemDaemon: return URL(fileURLWithPath: "/Library/LaunchDaemons")
            }
        }
    }

    let url: URL
    let label: String
    let program: String?
    let scope: Scope
    /// Le programme référencé n'existe plus (application désinstallée).
    let isBroken: Bool
    var id: URL { url }

    /// Application qui contient le programme, pour afficher son nom et son icône.
    var appURL: URL? {
        guard let program, let range = program.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(program[..<range.lowerBound]) + ".app")
    }

    var displayName: String {
        appURL?.deletingPathExtension().lastPathComponent ?? label
    }

    static func loadAll() -> [LaunchItem] {
        Scope.allCases.flatMap { scope -> [LaunchItem] in
            FS.children(of: scope.directory)
                .filter { $0.pathExtension == "plist" }
                .map { url -> LaunchItem in
                    let plist = NSDictionary(contentsOf: url) as? [String: Any] ?? [:]
                    let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                    let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                    let isBroken = program.map { $0.hasPrefix("/") && !FileManager.default.fileExists(atPath: $0) } ?? false
                    return LaunchItem(url: url, label: label, program: program, scope: scope, isBroken: isBroken)
                }
        }
    }

    /// Arrête puis supprime les éléments. Les éléments globaux et système partagent une seule demande de mot de passe.
    static func remove(_ items: [LaunchItem]) -> Removal {
        let userDomain = "gui/\(getuid())"
        for item in items where item.scope != .systemDaemon {
            Shell.run("/bin/launchctl", ["bootout", userDomain, item.url.path])
        }
        var removal = Remover.perform(items.filter { $0.scope == .userAgent }.map(\.url), permanently: false)
        let privileged = items.filter { $0.scope != .userAgent }
        if !privileged.isEmpty {
            let script = privileged.map { item -> String in
                let path = item.url.path.shellQuoted
                let stop = item.scope == .systemDaemon ? "/bin/launchctl bootout system \(path) 2>/dev/null; " : ""
                return "\(stop)/bin/rm -f \(path)"
            }.joined(separator: "; ")
            Shell.admin(script)
            for item in privileged {
                if FileManager.default.fileExists(atPath: item.url.path) {
                    removal.failed.append(item.url)
                } else {
                    removal.deleted.append(item.url)
                }
            }
        }
        return removal
    }
}

/// Application ouverte automatiquement à l'ouverture de session, lue via « Événements système ».
struct LoginItem: Identifiable, Hashable, Sendable {
    let name: String
    let path: String?
    var id: String { name }

    /// `nil` si macOS refuse l'accès à « Événements système » (Automatisation).
    static func loadAll() -> [LoginItem]? {
        let script = """
        set output to ""
        tell application "System Events"
            repeat with anItem in login items
                set itemPath to ""
                try
                    set itemPath to path of anItem
                end try
                set output to output & (name of anItem) & tab & itemPath & linefeed
            end repeat
        end tell
        return output
        """
        let result = Shell.run("/usr/bin/osascript", ["-e", script])
        guard result.status == 0 else { return nil }
        return result.output.split(whereSeparator: \.isNewline).compactMap { line -> LoginItem? in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first, !name.isEmpty else { return nil }
            let path = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
            return LoginItem(name: String(name), path: path)
        }
    }

    static func remove(_ items: [LoginItem]) -> Set<String> {
        var removed = Set<String>()
        for item in items {
            let name = item.name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            if Shell.run("/usr/bin/osascript", ["-e", "tell application \"System Events\" to delete login item \"\(name)\""]).status == 0 {
                removed.insert(item.name)
            }
        }
        return removed
    }
}

@MainActor
final class LaunchItemsModel: ObservableObject {
    @Published var items: [LaunchItem] = []
    @Published var loaded = false
    @Published var loginItems: [LoginItem] = []
    @Published var loginItemsLoaded = false
    @Published var loginItemsReadable = true
    @Published var lastActionMessage: String?

    var brokenCount: Int { items.filter(\.isBroken).count }

    func load() async {
        items = await Task.detached { LaunchItem.loadAll() }.value
        loaded = true
    }

    func loadLoginItems() async {
        let found = await Task.detached { LoginItem.loadAll() }.value
        loginItemsReadable = found != nil
        loginItems = found ?? []
        loginItemsLoaded = true
    }

    func remove(_ targets: [LaunchItem]) async {
        let sizes = Dictionary(uniqueKeysWithValues: targets.map { ($0.url, FS.fileSize($0.url)) })
        let removal = await Task.detached { LaunchItem.remove(targets) }.value
        let removed = removal.removed
        ActivityJournal.shared.recordRemoval(
            .launchItems, removal: removal,
            candidates: targets.map { RemovalCandidate(url: $0.url, size: sizes[$0.url] ?? 0, source: $0.label) }
        )
        items.removeAll { removed.contains($0.url) }
        lastActionMessage = removed.count == targets.count
            ? localized("\(removed.count) élément(s) supprimé(s).")
            : localized("\(removed.count) sur \(targets.count) élément(s) supprimé(s).")
    }

    func removeLoginItems(_ targets: [LoginItem]) async {
        let removed = await Task.detached { LoginItem.remove(targets) }.value
        ActivityJournal.shared.record(JournalEntry(
            kind: .loginItems,
            steps: targets.map { JournalStep(title: $0.name, detail: $0.path, succeeded: removed.contains($0.name)) }
        ))
        loginItems.removeAll { removed.contains($0.name) }
        lastActionMessage = localized("\(removed.count) app(s) ne s'ouvriront plus au démarrage.")
    }
}
