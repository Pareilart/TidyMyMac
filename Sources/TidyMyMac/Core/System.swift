import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Système de fichiers

enum FS {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let library = home.appendingPathComponent("Library")

    /// Points de montage à ne jamais parcourir (évite de compter deux fois le volume de données).
    private static let excludedRoots: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/private/var/vm"]
    private static let sizeKeys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    static func children(of url: URL, includeHidden: Bool = false) -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: options)) ?? []
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Vrai pour un dossier réel (les liens symboliques ne sont pas suivis).
    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: sizeKeys), values.isRegularFile == true else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    /// Taille occupée sur le disque par un fichier ou un dossier (récursif).
    static func size(of url: URL) -> Int64 {
        guard isDirectory(url) else { return fileSize(url) }
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(sizeKeys), options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            if excludedRoots.contains(file.path) {
                enumerator.skipDescendants()
                continue
            }
            total += fileSize(file)
        }
        return total
    }

    static func reveal(_ url: URL) {
        reveal([url])
    }

    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Icône du fichier, ou celle de son type s'il n'existe plus (entrée d'index périmée, données fictives).
    static func icon(for url: URL) -> NSImage {
        if exists(url) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .item)
    }
}

// MARK: - Suppression

/// Ce qu'est devenu chaque élément d'une suppression.
struct Removal: Sendable {
    var trashed: [URL] = []
    /// Emplacement de chaque élément dans la Corbeille, quand macOS l'indique.
    var trashLocations: [URL: URL] = [:]
    var deleted: [URL] = []
    var failed: [URL] = []

    var removed: Set<URL> { Set(trashed).union(deleted) }

    mutating func merge(_ other: Removal) {
        trashed += other.trashed
        trashLocations.merge(other.trashLocations) { _, new in new }
        deleted += other.deleted
        failed += other.failed
    }
}

enum Remover {
    static var deletePermanently: Bool { UserDefaults.standard.bool(forKey: "deletePermanently") }

    /// Supprime ou place dans la Corbeille, en notant l'emplacement de chaque élément dans la Corbeille.
    static func perform(_ urls: [URL], permanently: Bool) -> Removal {
        var removal = Removal()
        for url in urls {
            do {
                if permanently {
                    try FileManager.default.removeItem(at: url)
                    removal.deleted.append(url)
                } else {
                    var location: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &location)
                    removal.trashed.append(url)
                    removal.trashLocations[url] = location as URL?
                }
            } catch {
                removal.failed.append(url)
            }
        }
        return removal
    }

    /// Passe par le Finder, qui demande le mot de passe administrateur si nécessaire.
    @MainActor
    static func recycleWithFinder(_ urls: [URL]) async -> Removal {
        guard !urls.isEmpty else { return Removal() }
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { newURLs, error in
                var removal = Removal()
                for url in urls {
                    if let location = newURLs[url] {
                        removal.trashed.append(url)
                        removal.trashLocations[url] = location
                    } else if error == nil {
                        removal.trashed.append(url)
                    } else {
                        removal.failed.append(url)
                    }
                }
                continuation.resume(returning: removal)
            }
        }
    }
}

// MARK: - Commandes shell

enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    static func sh(_ command: String) -> (status: Int32, output: String) {
        run("/bin/sh", ["-c", command])
    }

    /// Exécute une commande avec les droits administrateur (boîte de dialogue système).
    @discardableResult
    static func admin(_ command: String) -> (status: Int32, output: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    }
}

extension String {
    var shellQuoted: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
    var abbreviatingHome: String { (self as NSString).abbreviatingWithTildeInPath }
}

// MARK: - Disque et permissions

struct DiskInfo {
    let total: Int64
    let free: Int64
    var used: Int64 { total - free }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskInfo? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskInfo(total: Int64(total), free: free)
    }

    /// Espace réellement libre, sans compter l'espace purgeable (instantanés, caches iCloud).
    static func physicallyFree() -> Int64? {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let free = values.volumeAvailableCapacity else { return nil }
        return Int64(free)
    }
}

/// Cumul de l'espace libéré par TidyMyMac depuis son installation.
enum Stats {
    static let totalFreedKey = "totalFreedBytes"

    static func record(freed bytes: Int64) {
        guard bytes > 0 else { return }
        let total = UserDefaults.standard.integer(forKey: totalFreedKey)
        UserDefaults.standard.set(total + Int(bytes), forKey: totalFreedKey)
    }
}

enum Permissions {
    /// Dossiers protégés par l'accès complet au disque, dont on teste la lecture.
    /// Pas de conteneur d'app : leur lecture déclenche une autre demande d'autorisation.
    private static let protectedFolders = ["Library/Safari", "Library/Mail", "Library/Messages", "Library/Cookies"]

    /// Vrai si l'un des dossiers protégés présents peut être listé.
    /// Sans aucun dossier protégé sur ce Mac, on ne signale rien plutôt qu'une fausse alerte.
    static var hasFullDiskAccess: Bool {
        let existing = protectedFolders
            .map { FS.home.appendingPathComponent($0).path }
            .filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return true }
        return existing.contains { (try? FileManager.default.contentsOfDirectory(atPath: $0)) != nil }
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// macOS n'applique l'accès complet au disque qu'au prochain lancement de l'app.
    static func relaunchApp() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}

@MainActor
func chooseFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    return panel.runModal() == .OK ? panel.url : nil
}

// MARK: - Formatage

extension Int64 {
    var formattedBytes: String { formatted(.byteCount(style: .file).locale(AppLocalization.locale)) }
    /// Comme `formattedBytes`, mais un tiret quand il n'y a rien eu à gagner.
    var formattedGain: String { self > 0 ? formattedBytes : "—" }
}

extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLocalization.locale
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
