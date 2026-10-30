import Foundation

/// Ce que l'on risque à supprimer les éléments d'une règle.
enum RiskLevel: String, Codable, Sendable, CaseIterable {
    /// Données recréées automatiquement.
    case safe
    /// Peut contenir des éléments à garder : à regarder avant de nettoyer.
    case review
    /// Supprimé définitivement, sans passer par la Corbeille.
    case irreversible

    var title: String {
        switch self {
        case .safe: return localized("Sans danger")
        case .review: return localized("À vérifier")
        case .irreversible: return localized("Irréversible")
        }
    }

    var explanation: String {
        switch self {
        case .safe: return localized("Recréé automatiquement : le supprimer ne fait rien perdre.")
        case .review: return localized("Peut contenir des éléments à garder : regardez la liste avant de nettoyer.")
        case .irreversible: return localized("Supprimé définitivement, sans passer par la Corbeille.")
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield"
        case .review: return "eye"
        case .irreversible: return "exclamationmark.triangle"
        }
    }
}

/// Texte d'une règle : une seule chaîne, ou une traduction par langue (`{"fr": "…", "en": "…"}`).
struct RuleText: Codable, Sendable {
    private let translations: [String: String]

    init(_ text: String) {
        translations = ["": text]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            translations = ["": text]
        } else {
            translations = try container.decode([String: String].self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let text = translations[""], translations.count == 1 {
            try container.encode(text)
        } else {
            try container.encode(translations)
        }
    }

    /// Dans la langue de l'interface, sinon en anglais, sinon en français.
    var text: String {
        translations[AppLocalization.languageCode] ?? translations["en"] ?? translations["fr"]
            ?? translations.values.first ?? ""
    }
}

/// Une règle de nettoyage : où chercher, quoi épargner, et ce que l'on risque à supprimer.
///
/// Les règles intégrées et les profils sont décrits en JSON dans `Resources/Rules` (voir docs/RULES.md) ;
/// celles de l'utilisateur sont créées dans l'écran « Règles et profils ».
struct CleanupRule: Identifiable, Codable, Sendable {
    enum Target: String, Codable, Sendable, CaseIterable {
        /// Le contenu de chaque emplacement, élément par élément.
        case contents
        /// L'emplacement lui-même.
        case location
        /// Les dossiers et fichiers portant l'un des noms cherchés, à n'importe quel niveau sous les emplacements.
        case search
    }

    let id: String
    let icon: String
    let risk: RiskLevel
    let selectedByDefault: Bool
    /// Supprimé sans passer par la Corbeille, quel que soit le réglage (la Corbeille elle-même).
    private(set) var permanent: Bool
    let locations: [String]
    let target: Target
    /// Noms cherchés par `search`, avec les jokers `*` et `?`.
    let names: [String]
    /// Profondeur maximale de `search` sous chaque emplacement.
    let maxDepth: Int
    let includeHidden: Bool
    let extensions: [String]
    /// Noms à épargner, avec les jokers `*` et `?`.
    let exclude: [String]
    let olderThanDays: Int?
    private let titleText: RuleText
    private let detailText: RuleText
    private let afterRemovalText: RuleText?
    /// Profil auquel appartient une règle intégrée (`nil` : règles générales).
    private(set) var profileID: String?
    /// Règle créée par l'utilisateur.
    private(set) var isCustom = false

    var title: String { titleText.text }
    var detail: String { detailText.text }
    var afterRemoval: String? { afterRemovalText?.text }
    var locationURLs: [URL] { locations.map(Self.url(for:)) }

    /// Suppression définitive : imposée par la règle ou choisie dans les Réglages.
    var deletesPermanently: Bool { permanent || Remover.deletePermanently }

    /// Sans la Corbeille, ce qui n'est pas recréé automatiquement devient irrécupérable.
    var effectiveRisk: RiskLevel {
        deletesPermanently && risk == .review ? .irreversible : risk
    }

    init(
        id: String, icon: String, risk: RiskLevel, selectedByDefault: Bool, locations: [String], target: Target,
        names: [String], maxDepth: Int, includeHidden: Bool, extensions: [String], exclude: [String],
        olderThanDays: Int?, title: String, detail: String, afterRemoval: String?
    ) {
        self.id = id
        self.icon = icon
        self.risk = risk
        self.selectedByDefault = selectedByDefault
        self.permanent = false
        self.locations = locations
        self.target = target
        self.names = names
        self.maxDepth = maxDepth
        self.includeHidden = includeHidden
        self.extensions = extensions
        self.exclude = exclude
        self.olderThanDays = olderThanDays
        self.titleText = RuleText(title)
        self.detailText = RuleText(detail)
        self.afterRemovalText = afterRemoval.map(RuleText.init)
        self.isCustom = true
    }

    private enum CodingKeys: String, CodingKey {
        case id, icon, risk, selectedByDefault, permanent, locations, target, names, maxDepth, includeHidden
        case extensions, exclude, olderThanDays
        case titleText = "title"
        case detailText = "detail"
        case afterRemovalText = "afterRemoval"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "folder"
        risk = try container.decodeIfPresent(RiskLevel.self, forKey: .risk) ?? .review
        selectedByDefault = try container.decodeIfPresent(Bool.self, forKey: .selectedByDefault) ?? false
        permanent = try container.decodeIfPresent(Bool.self, forKey: .permanent) ?? false
        locations = try container.decode([String].self, forKey: .locations)
        target = try container.decodeIfPresent(Target.self, forKey: .target) ?? .contents
        names = try container.decodeIfPresent([String].self, forKey: .names) ?? []
        maxDepth = try container.decodeIfPresent(Int.self, forKey: .maxDepth) ?? 4
        includeHidden = try container.decodeIfPresent(Bool.self, forKey: .includeHidden) ?? false
        extensions = try container.decodeIfPresent([String].self, forKey: .extensions) ?? []
        exclude = try container.decodeIfPresent([String].self, forKey: .exclude) ?? []
        olderThanDays = try container.decodeIfPresent(Int.self, forKey: .olderThanDays)
        titleText = try container.decode(RuleText.self, forKey: .titleText)
        detailText = try container.decode(RuleText.self, forKey: .detailText)
        afterRemovalText = try container.decodeIfPresent(RuleText.self, forKey: .afterRemovalText)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(icon, forKey: .icon)
        try container.encode(risk, forKey: .risk)
        try container.encode(selectedByDefault, forKey: .selectedByDefault)
        try container.encode(locations, forKey: .locations)
        try container.encode(target, forKey: .target)
        if target == .search {
            try container.encode(names, forKey: .names)
            try container.encode(maxDepth, forKey: .maxDepth)
        }
        if includeHidden { try container.encode(includeHidden, forKey: .includeHidden) }
        if !extensions.isEmpty { try container.encode(extensions, forKey: .extensions) }
        if !exclude.isEmpty { try container.encode(exclude, forKey: .exclude) }
        try container.encodeIfPresent(olderThanDays, forKey: .olderThanDays)
        try container.encode(titleText, forKey: .titleText)
        try container.encode(detailText, forKey: .detailText)
        try container.encodeIfPresent(afterRemovalText, forKey: .afterRemovalText)
    }

    /// Les règles de l'utilisateur passent toujours par la Corbeille.
    mutating func markAsCustom() {
        isCustom = true
        permanent = false
    }

    mutating func attach(to profile: String?) {
        profileID = profile
    }

    /// Éléments concernés, sans jamais renvoyer un dossier protégé ni l'un de ses parents.
    func locate() -> [URL] {
        let candidates: [URL]
        switch target {
        case .location:
            candidates = locationURLs.filter(FS.exists)
        case .contents:
            candidates = locationURLs.flatMap { FS.children(of: $0, includeHidden: includeHidden) }
        case .search:
            candidates = locationURLs.flatMap(search(in:))
        }
        let wanted = Set(extensions.map { $0.lowercased() })
        let cutoff = olderThanDays.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        return candidates.filter { url in
            guard !Self.matches(url.lastPathComponent, any: exclude), !RuleSafety.isProtected(url) else { return false }
            if !wanted.isEmpty && !wanted.contains(url.pathExtension.lowercased()) { return false }
            if let cutoff {
                guard let modified = FS.modificationDate(url), modified < cutoff else { return false }
            }
            return true
        }
    }

    /// Parcourt l'emplacement jusqu'à `maxDepth` niveaux, sans entrer dans ce qui a déjà été trouvé.
    private func search(in root: URL) -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        guard !names.isEmpty, let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: options, errorHandler: { _, _ in true }
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in enumerator {
            if Self.matches(url.lastPathComponent, any: names) {
                found.append(url)
                enumerator.skipDescendants()
            } else if enumerator.level >= maxDepth || Self.unexplored.contains(url.lastPathComponent)
                        || Self.unexplored.contains("*." + url.pathExtension) {
                enumerator.skipDescendants()
            }
        }
        return found
    }

    /// Dossiers où la recherche n'entre pas : volumineux et sans rapport avec le nettoyage.
    private static let unexplored: Set<String> = ["node_modules", "*.photoslibrary", "*.musiclibrary", "*.tvlibrary"]

    static func matches(_ name: String, any patterns: [String]) -> Bool {
        patterns.contains { fnmatch($0, name, 0) == 0 }
    }

    /// `~/…` part du dossier personnel ; les autres chemins doivent être absolus.
    static func url(for path: String) -> URL {
        if path == "~" { return FS.home }
        if path.hasPrefix("~/") { return FS.home.appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}

/// Garde-fous appliqués à toutes les règles, y compris celles créées par l'utilisateur.
enum RuleSafety {
    /// Dossiers qu'aucune règle ne peut supprimer, ni eux ni un de leurs parents.
    private static let protectedPaths: Set<String> = Set(
        ["/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin", "/private", "/Volumes", "/opt"]
            + ["", "Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Applications",
               "Library/Mobile Documents"].map { FS.home.appendingPathComponent($0).standardizedFileURL.path }
    )

    /// Dossiers trop larges pour être vidés ou fouillés en entier par une règle.
    private static let broadPaths: Set<String> = Set(
        ["/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin", "/private", "/Volumes", "/opt"]
            + [FS.home.standardizedFileURL.path, FS.library.standardizedFileURL.path]
    )

    static func isProtected(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let prefix = path == "/" ? "/" : path + "/"
        return protectedPaths.contains { $0 == path || $0.hasPrefix(prefix) }
    }

    /// Raison pour laquelle une règle est refusée, ou `nil` si elle peut s'appliquer.
    static func problem(with rule: CleanupRule) -> String? {
        for location in rule.locations {
            guard location.hasPrefix("/") || location == "~" || location.hasPrefix("~/") else {
                return localized("Le chemin « \(location) » doit commencer par / ou ~.")
            }
            let url = CleanupRule.url(for: location)
            if rule.target == .location && isProtected(url) {
                return localized("« \(location) » est un dossier protégé : aucune règle ne peut le supprimer.")
            }
            if rule.target != .location && broadPaths.contains(url.path) {
                return localized("« \(location) » est trop large : choisissez un dossier plus précis.")
            }
        }
        if rule.target == .search {
            guard !rule.names.isEmpty else { return localized("Indiquez au moins un nom à chercher.") }
            // Un nom fait uniquement de jokers (« * », « *.* ») viserait tout le contenu.
            if let name = rule.names.first(where: { $0.allSatisfy { "*?.".contains($0) } }) {
                return localized("Le nom « \(name) » est trop large.")
            }
        }
        return nil
    }
}
