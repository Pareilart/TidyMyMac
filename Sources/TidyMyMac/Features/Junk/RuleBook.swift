import Foundation

/// Un profil de métier : un ensemble de règles intégrées, activé dans « Règles et profils ».
struct RuleProfile: Identifiable, Decodable, Sendable {
    let id: String
    let icon: String
    /// Nom d'une couleur du thème (`mint`, `sky`, `peach`…).
    let tint: String
    /// Chemins dont la présence suggère le profil (outils installés, dossiers de travail).
    let detect: [String]
    private let titleText: RuleText
    private let detailText: RuleText

    var title: String { titleText.text }
    var detail: String { detailText.text }
    var isDetected: Bool { detect.contains { FS.exists(CleanupRule.url(for: $0)) } }

    private enum CodingKeys: String, CodingKey {
        case id, icon, tint, detect
        case titleText = "title"
        case detailText = "detail"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "person.crop.circle"
        tint = try container.decodeIfPresent(String.self, forKey: .tint) ?? "mint"
        detect = try container.decodeIfPresent([String].self, forKey: .detect) ?? []
        titleText = try container.decode(RuleText.self, forKey: .titleText)
        detailText = try container.decode(RuleText.self, forKey: .detailText)
    }
}

/// Charge les règles intégrées (générales et profils) et celles créées par l'utilisateur.
enum RuleBook {
    struct Contents: Sendable {
        /// Règles intégrées, générales puis par profil.
        var builtIn: [CleanupRule] = []
        var profiles: [RuleProfile] = []
        var custom: [CleanupRule] = []
        /// Règles ignorées, avec la raison.
        var problems: [String] = []
        var enabledProfiles: Set<String> = []
        var disabledRules: Set<String> = []

        func isEnabled(_ rule: CleanupRule) -> Bool {
            !disabledRules.contains(rule.id) && (rule.profileID.map(enabledProfiles.contains) ?? true)
        }

        /// Règles utilisées par l'analyse des fichiers inutiles.
        var activeRules: [CleanupRule] { (builtIn + custom).filter(isEnabled) }

        func rules(of profile: String?) -> [CleanupRule] {
            builtIn.filter { $0.profileID == profile }
        }
    }

    private struct RuleFile: Codable {
        var profile: RuleProfile?
        var rules: [CleanupRule]

        private enum CodingKeys: String, CodingKey { case profile, rules }

        init(rules: [CleanupRule]) {
            self.rules = rules
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profile = try container.decodeIfPresent(RuleProfile.self, forKey: .profile)
            rules = try container.decode([CleanupRule].self, forKey: .rules)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rules, forKey: .rules)
        }
    }

    private static let enabledProfilesKey = "enabledRuleProfiles"
    private static let disabledRulesKey = "disabledCleanupRules"

    /// Règles de l'utilisateur. `-customRulesFile <fichier>` au lancement le remplace, pour les essais.
    static var customRulesFile: URL {
        if let file = UserDefaults.standard.string(forKey: "customRulesFile") {
            return URL(fileURLWithPath: file)
        }
        return FS.library.appendingPathComponent("Application Support/TidyMyMac/custom-rules.json")
    }

    /// Page qui explique comment proposer une règle intégrée, sur le dépôt GitHub de l'app.
    static var documentationURL: URL? {
        let repository = Bundle.main.object(forInfoDictionaryKey: "TMMReleasesRepository") as? String ?? ""
        guard repository.split(separator: "/").count == 2 else { return nil }
        return URL(string: "https://github.com/\(repository)/blob/main/docs/RULES.md")
    }

    static func load() -> Contents {
        var contents = Contents()
        let defaults = UserDefaults.standard
        contents.enabledProfiles = Set(defaults.stringArray(forKey: enabledProfilesKey) ?? [])
        contents.disabledRules = Set(defaults.stringArray(forKey: disabledRulesKey) ?? [])
        // general.json d'abord, puis les profils dans l'ordre alphabétique.
        func order(_ file: URL) -> (Int, String) {
            (file.lastPathComponent == "general.json" ? 0 : 1, file.lastPathComponent)
        }
        let files = (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Rules") ?? [])
            .sorted { order($0) < order($1) }
        for file in files {
            guard let decoded = decode(file, into: &contents) else { continue }
            if let profile = decoded.profile { contents.profiles.append(profile) }
            for var rule in decoded.rules where accept(rule, from: file, into: &contents) {
                rule.attach(to: decoded.profile?.id)
                contents.builtIn.append(rule)
            }
        }
        if FS.exists(customRulesFile), let decoded = decode(customRulesFile, into: &contents) {
            for var rule in decoded.rules where accept(rule, from: customRulesFile, into: &contents) {
                rule.markAsCustom()
                contents.custom.append(rule)
            }
        }
        return contents
    }

    static func saveCustomRules(_ rules: [CleanupRule]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let folder = customRulesFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(RuleFile(rules: rules)).write(to: customRulesFile, options: .atomic)
    }

    static func savePreferences(enabledProfiles: Set<String>, disabledRules: Set<String>) {
        UserDefaults.standard.set(enabledProfiles.sorted(), forKey: enabledProfilesKey)
        UserDefaults.standard.set(disabledRules.sorted(), forKey: disabledRulesKey)
    }

    private static func decode(_ file: URL, into contents: inout Contents) -> RuleFile? {
        do {
            return try JSONDecoder().decode(RuleFile.self, from: Data(contentsOf: file))
        } catch {
            contents.problems.append(localized("\(file.lastPathComponent) : \(describe(error))"))
            return nil
        }
    }

    private static func accept(_ rule: CleanupRule, from file: URL, into contents: inout Contents) -> Bool {
        let name = file.lastPathComponent
        if (contents.builtIn + contents.custom).contains(where: { $0.id == rule.id }) {
            contents.problems.append(localized("\(name) : identifiant « \(rule.id) » déjà utilisé"))
            return false
        }
        if let problem = RuleSafety.problem(with: rule) {
            contents.problems.append(localized("\(name) : \(localized("\(rule.id) : \(problem)"))"))
            return false
        }
        return true
    }

    /// Message court et lisible pour quelqu'un qui écrit le JSON à la main.
    private static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return localized("fichier illisible") }
        func path(_ codingPath: [CodingKey], _ last: CodingKey? = nil) -> String {
            (codingPath + (last.map { [$0] } ?? [])).reduce("") { result, key in
                if let index = key.intValue { return result + "[\(index)]" }
                return result.isEmpty ? key.stringValue : result + "." + key.stringValue
            }
        }
        switch error {
        case .keyNotFound(let key, let context):
            return localized("champ « \(path(context.codingPath, key)) » manquant")
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return localized("valeur invalide pour « \(path(context.codingPath)) »")
        case .dataCorrupted(let context) where !context.codingPath.isEmpty:
            return localized("valeur invalide pour « \(path(context.codingPath)) »")
        default:
            return localized("JSON invalide")
        }
    }

    /// `TidyMyMac --list-rules` : ce que chaque règle active trouverait, sans rien supprimer.
    static func printReport() {
        let contents = load()
        for rule in contents.activeRules {
            let items = rule.locate()
            let size = items.reduce(Int64(0)) { $0 + FS.size(of: $1) }
            // Rapport en ligne de commande, pas un texte de l'interface.
            var origin = "général"
            if let profile = rule.profileID { origin = profile }
            if rule.isCustom { origin = "personnelle" }
            print("\(rule.id) [\(rule.effectiveRisk.rawValue), \(origin)] : \(items.count) élément(s), \(size.formattedBytes)")
            for item in items.prefix(20) {
                print("  \(item.path.abbreviatingHome)")
            }
            if items.count > 20 {
                print("  … et \(items.count - 20) autres")
            }
        }
        let inactive = (contents.builtIn + contents.custom).filter { !contents.isEnabled($0) }.map(\.id)
        if !inactive.isEmpty {
            print("Inactives : \(inactive.joined(separator: ", "))")
        }
        for problem in contents.problems {
            print("Ignorée : \(problem)")
        }
    }
}
