import Foundation

/// Type d'action enregistrée dans le journal.
enum JournalKind: String, Codable, Sendable {
    case junk, largeFiles, duplicates, spaceExplorer, uninstall, appReset, maintenance, memory, launchItems, loginItems
}

/// Un élément touché par une action, et ce qu'il est devenu.
struct JournalItem: Codable, Sendable, Hashable, Identifiable {
    enum Outcome: String, Codable, Sendable {
        /// Placé dans la Corbeille : on peut encore le récupérer.
        case trashed
        /// Supprimé sans passer par la Corbeille.
        case deleted
        /// Laissé en place (droits insuffisants, fichier verrouillé…).
        case failed
        /// Remis à son emplacement d'origine depuis la Corbeille.
        case restored
    }

    /// Où en est l'élément aujourd'hui, d'après le disque.
    enum Availability {
        /// Dans la Corbeille, et son emplacement d'origine est libre : on peut le remettre en place.
        case restorable
        /// Dans la Corbeille, mais un élément du même nom occupe déjà son emplacement d'origine.
        case occupied
        /// Dans la Corbeille à un endroit que macOS n'a pas indiqué.
        case inTrash
        /// De retour à sa place (depuis TidyMyMac ou avec « Remettre » dans le Finder).
        case restored
        /// Plus dans la Corbeille : elle a été vidée.
        case trashEmptied
        case deleted
        case failed
    }

    /// Chemin d'origine.
    let path: String
    let size: Int64
    var outcome: Outcome
    /// Emplacement dans la Corbeille, quand macOS l'indique.
    var trashPath: String?
    /// Règle ou catégorie qui a proposé l'élément.
    let source: String?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var trashURL: URL? { trashPath.map { URL(fileURLWithPath: $0) } }

    /// Captures d'écran : les éléments fictifs, absents du disque, s'affichent comme restaurables.
    nonisolated(unsafe) static var demoAvailability = false

    var availability: Availability {
        if Self.demoAvailability && outcome == .trashed { return .restorable }
        switch outcome {
        case .restored: return .restored
        case .deleted: return .deleted
        case .failed: return .failed
        case .trashed:
            guard let trash = trashURL else { return FS.exists(url) ? .restored : .inTrash }
            if FS.exists(trash) { return FS.exists(url) ? .occupied : .restorable }
            return FS.exists(url) ? .restored : .trashEmptied
        }
    }
}

/// Une étape d'une action sans fichier (tâche d'entretien, app retirée de l'ouverture de session…).
struct JournalStep: Codable, Sendable, Hashable {
    let title: String
    let detail: String?
    let succeeded: Bool
}

/// Une action menée par TidyMyMac : nettoyage, désinstallation, entretien…
struct JournalEntry: Codable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let kind: JournalKind
    /// Nom de l'app, pour une désinstallation ou une réinitialisation.
    let subject: String?
    var items: [JournalItem]
    var steps: [JournalStep]
    /// Espace disque libéré : éléments supprimés, ou gain mesuré pour l'entretien. Diminue quand on restaure.
    var freed: Int64
    let memoryFreed: Int64

    init(
        kind: JournalKind, subject: String? = nil, items: [JournalItem] = [], steps: [JournalStep] = [],
        freed: Int64 = 0, memoryFreed: Int64 = 0, date: Date = Date()
    ) {
        id = UUID()
        self.date = date
        self.kind = kind
        self.subject = subject
        self.items = items
        self.steps = steps
        self.freed = freed
        self.memoryFreed = memoryFreed
    }

    var title: String {
        let name = subject ?? ""
        switch kind {
        case .junk: return localized("Nettoyage des fichiers inutiles")
        case .largeFiles: return localized("Gros fichiers mis à la Corbeille")
        case .duplicates: return localized("Doublons mis à la Corbeille")
        case .spaceExplorer: return localized("Éléments retirés depuis l'Explorateur d'espace")
        case .uninstall: return localized("Désinstallation de \(name)")
        case .appReset: return localized("Réinitialisation de \(name)")
        case .maintenance: return localized("Entretien")
        case .memory: return localized("Mémoire libérée")
        case .launchItems: return localized("Éléments de démarrage supprimés")
        case .loginItems: return localized("Apps retirées de l'ouverture de session")
        }
    }

    var failureCount: Int {
        items.filter { $0.outcome == .failed }.count + steps.filter { !$0.succeeded }.count
    }

    /// Éléments encore dans la Corbeille que l'on peut remettre en place.
    var restorableItems: [JournalItem] { items.filter { $0.availability == .restorable } }
}

/// Bilan d'une restauration, à afficher tel quel.
struct RestoreResult: Sendable {
    var restoredCount = 0
    var restoredBytes: Int64 = 0
    var conflictCount = 0
    var unavailableCount = 0
    var failedCount = 0

    var message: String {
        var parts: [String] = []
        if restoredCount > 0 {
            parts.append(localized("\(restoredCount) élément(s) remis en place."))
        }
        if conflictCount > 0 {
            parts.append(localized("\(conflictCount) élément(s) laissés dans la Corbeille : un élément du même nom est déjà à leur place."))
        }
        if unavailableCount > 0 {
            parts.append(localized("\(unavailableCount) élément(s) ne sont plus dans la Corbeille."))
        }
        if failedCount > 0 {
            parts.append(localized("\(failedCount) élément(s) n'ont pas pu être remis en place : utilisez « Remettre » dans la Corbeille du Finder."))
        }
        return parts.isEmpty ? localized("Rien à remettre en place.") : parts.joined(separator: " ")
    }
}

/// Élément proposé à la suppression, avec sa taille et la règle qui l'a trouvé.
struct RemovalCandidate: Sendable {
    let url: URL
    let size: Int64
    var source: String?
}

/// Historique local de tout ce que TidyMyMac a fait sur ce Mac.
///
/// Chaque action est un fichier JSON de `~/Library/Application Support/TidyMyMac/Journal` :
/// rien n'est envoyé ailleurs, et l'utilisateur peut tout effacer.
@MainActor
final class ActivityJournal: ObservableObject {
    static let shared = ActivityJournal()

    /// Actions, de la plus récente à la plus ancienne.
    @Published private(set) var entries: [JournalEntry] = []
    /// Données fictives des captures d'écran : rien n'est enregistré.
    private var isDemo = false

    /// `-journalFolder <dossier>` au lancement le remplace, pour les essais.
    nonisolated static var folder: URL {
        if let folder = UserDefaults.standard.string(forKey: "journalFolder") {
            return URL(fileURLWithPath: folder)
        }
        return FS.library.appendingPathComponent("Application Support/TidyMyMac/Journal")
    }

    private init() {
        entries = Self.readAll(in: Self.folder)
    }

    @discardableResult
    func record(_ entry: JournalEntry) -> JournalEntry {
        entries.insert(entry, at: 0)
        if !isDemo {
            let file = Self.file(for: entry)
            Task.detached(priority: .utility) { try? Self.write(entry, to: file) }
        }
        return entry
    }

    /// Enregistre une suppression : chaque élément proposé, avec ce qu'il est devenu.
    @discardableResult
    func recordRemoval(
        _ kind: JournalKind, subject: String? = nil, removal: Removal, candidates: [RemovalCandidate]
    ) -> JournalEntry? {
        let trashed = Set(removal.trashed)
        let deleted = Set(removal.deleted)
        let failed = Set(removal.failed)
        let items = candidates.compactMap { candidate -> JournalItem? in
            let outcome: JournalItem.Outcome
            if trashed.contains(candidate.url) {
                outcome = .trashed
            } else if deleted.contains(candidate.url) {
                outcome = .deleted
            } else if failed.contains(candidate.url) {
                outcome = .failed
            } else {
                return nil
            }
            return JournalItem(
                path: candidate.url.path, size: candidate.size, outcome: outcome,
                trashPath: removal.trashLocations[candidate.url]?.path, source: candidate.source
            )
        }
        guard !items.isEmpty else { return nil }
        let freed = items.filter { $0.outcome != .failed }.reduce(Int64(0)) { $0 + $1.size }
        return record(JournalEntry(kind: kind, subject: subject, items: items, freed: freed))
    }

    func entry(withID id: UUID) -> JournalEntry? {
        entries.first { $0.id == id }
    }

    /// Remet à leur place les éléments d'une action encore dans la Corbeille (tous, ou seulement `paths`).
    ///
    /// Un élément n'est jamais remis par-dessus un fichier qui occupe déjà son emplacement d'origine.
    @discardableResult
    func restore(_ entryID: UUID, paths: Set<String>? = nil) -> RestoreResult {
        var result = RestoreResult()
        guard !isDemo, let index = entries.firstIndex(where: { $0.id == entryID }) else { return result }
        var entry = entries[index]
        for position in entry.items.indices where entry.items[position].outcome == .trashed {
            let item = entry.items[position]
            if let paths, !paths.contains(item.path) { continue }
            switch item.availability {
            case .restorable:
                guard let trash = item.trashURL else { continue }
                do {
                    try FileManager.default.createDirectory(
                        at: item.url.deletingLastPathComponent(), withIntermediateDirectories: true
                    )
                    try FileManager.default.moveItem(at: trash, to: item.url)
                    entry.items[position].outcome = .restored
                    result.restoredCount += 1
                    result.restoredBytes += item.size
                } catch {
                    result.failedCount += 1
                }
            case .restored:
                // Déjà remis en place depuis le Finder : on met le journal à jour.
                entry.items[position].outcome = .restored
                result.restoredBytes += item.size
            case .occupied:
                result.conflictCount += 1
            case .inTrash, .trashEmptied:
                result.unavailableCount += 1
            case .deleted, .failed:
                break
            }
        }
        entry.freed = max(entry.freed - result.restoredBytes, 0)
        entries[index] = entry
        Stats.subtract(freed: result.restoredBytes)
        let file = Self.file(for: entry)
        Task.detached(priority: .utility) { try? Self.write(entry, to: file) }
        return result
    }

    /// Efface tout l'historique (les fichiers déjà dans la Corbeille n'y sont pas touchés).
    func clear() {
        entries = []
        guard !isDemo else { return }
        for file in FS.children(of: Self.folder) where file.pathExtension == "json" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Stockage

    private nonisolated static func readAll(in folder: URL) -> [JournalEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return FS.children(of: folder)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(JournalEntry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    private nonisolated static func file(for entry: JournalEntry) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let name = "\(formatter.string(from: entry.date))-\(entry.id.uuidString.prefix(8).lowercased()).json"
        return folder.appendingPathComponent(name)
    }

    private nonisolated static func write(_ entry: JournalEntry, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(entry).write(to: file, options: .atomic)
    }

    private nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    // MARK: Export

    /// Une ligne par élément ou par étape, pour un tableur.
    nonisolated static func csv(for entries: [JournalEntry]) -> String {
        func field(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let dates = ISO8601DateFormatter()
        var lines = ["date,action,path,size_bytes,outcome,trash_location,source"]
        for entry in entries {
            let prefix = [field(dates.string(from: entry.date)), field(entry.title)]
            for item in entry.items {
                lines.append((prefix + [
                    field(item.path), String(item.size), item.outcome.rawValue, field(item.trashPath ?? ""),
                    field(item.source ?? ""),
                ]).joined(separator: ","))
            }
            for step in entry.steps {
                lines.append((prefix + [
                    field(""), "0", step.succeeded ? "done" : "failed", field(""),
                    field([step.title, step.detail].compactMap { $0 }.joined(separator: " — ")),
                ]).joined(separator: ","))
            }
            if entry.items.isEmpty && entry.steps.isEmpty {
                lines.append((prefix + [field(""), String(entry.freed), "done", field(""), field("")]).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    nonisolated static func json(for entries: [JournalEntry]) throws -> Data {
        try encoder.encode(entries)
    }

    // MARK: Captures d'écran

    /// Historique fictif des captures d'écran (aucun fichier réel).
    func showDemo() {
        isDemo = true
        JournalItem.demoAvailability = true
        let day: TimeInterval = 86_400
        let now = Date()
        func items(_ entries: [(String, Double, String?)]) -> [JournalItem] {
            entries.map {
                JournalItem(
                    path: FS.home.appendingPathComponent($0.0).path, size: Int64($0.1 * 1_000_000_000),
                    outcome: .trashed, trashPath: nil, source: $0.2
                )
            }
        }
        let junk = items([
            ("Library/Developer/Xcode/DerivedData/MyApp-dkqf", 6.8, "Xcode – DerivedData"),
            ("Library/Caches/com.example.browser", 2.4, "App caches"),
            ("Library/Developer/Xcode/iOS DeviceSupport/17.5 (21F79)", 3.9, nil),
        ])
        entries = [
            JournalEntry(kind: .junk, items: junk, freed: 13_100_000_000, date: now.addingTimeInterval(-2 * 3600)),
            JournalEntry(
                kind: .maintenance,
                steps: [
                    JournalStep(title: localized("Libérer la mémoire vive"), detail: nil, succeeded: true),
                    JournalStep(title: localized("Vider le cache DNS"), detail: nil, succeeded: true),
                ],
                memoryFreed: 1_400_000_000, date: now.addingTimeInterval(-day - 3600)
            ),
            JournalEntry(
                kind: .uninstall, subject: "Example Editor",
                items: items([("Applications/Example Editor.app", 0.84, nil)]), freed: 840_000_000,
                date: now.addingTimeInterval(-3 * day)
            ),
            JournalEntry(
                kind: .largeFiles, items: items([("Movies/Final edit.mov", 6.1, nil)]), freed: 6_100_000_000,
                date: now.addingTimeInterval(-6 * day)
            ),
            JournalEntry(
                kind: .duplicates, items: items([("Downloads/Archive 2023 copy.zip", 2.3, nil)]), freed: 2_300_000_000,
                date: now.addingTimeInterval(-12 * day)
            ),
            JournalEntry(kind: .junk, items: junk, freed: 4_100_000_000, date: now.addingTimeInterval(-20 * day)),
        ]
    }
}
