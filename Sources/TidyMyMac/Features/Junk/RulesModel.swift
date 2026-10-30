import Foundation

/// État de l'écran « Règles et profils » : profils activés, règles désactivées, règles personnelles.
@MainActor
final class RulesModel: ObservableObject {
    @Published private(set) var contents = RuleBook.Contents()
    @Published var saveError: String?
    /// Données fictives des captures d'écran : rien n'est enregistré.
    private var isDemo = false

    init() {
        reload()
    }

    func reload() {
        guard !isDemo else { return }
        contents = RuleBook.load()
    }

    func isEnabled(_ rule: CleanupRule) -> Bool {
        contents.isEnabled(rule)
    }

    func isEnabled(_ profile: RuleProfile) -> Bool {
        contents.enabledProfiles.contains(profile.id)
    }

    func setEnabled(_ enabled: Bool, profile: RuleProfile) {
        if enabled {
            contents.enabledProfiles.insert(profile.id)
        } else {
            contents.enabledProfiles.remove(profile.id)
        }
        savePreferences()
    }

    func setEnabled(_ enabled: Bool, rule: CleanupRule) {
        if enabled {
            contents.disabledRules.remove(rule.id)
        } else {
            contents.disabledRules.insert(rule.id)
        }
        savePreferences()
    }

    /// Ajoute la règle, ou remplace celle qui a le même identifiant.
    func save(_ rule: CleanupRule) {
        var custom = contents.custom
        if let index = custom.firstIndex(where: { $0.id == rule.id }) {
            custom[index] = rule
        } else {
            custom.append(rule)
        }
        saveCustom(custom)
    }

    func delete(_ rule: CleanupRule) {
        saveCustom(contents.custom.filter { $0.id != rule.id })
        contents.disabledRules.remove(rule.id)
        savePreferences()
    }

    private func saveCustom(_ rules: [CleanupRule]) {
        guard !isDemo else {
            contents.custom = rules
            return
        }
        do {
            try RuleBook.saveCustomRules(rules)
            saveError = nil
            reload()
        } catch {
            saveError = localized("Impossible d'enregistrer les règles : \(error.localizedDescription)")
        }
    }

    private func savePreferences() {
        guard !isDemo else { return }
        RuleBook.savePreferences(enabledProfiles: contents.enabledProfiles, disabledRules: contents.disabledRules)
    }

    /// Captures d'écran : profil Développeur activé et une règle personnelle d'exemple.
    func showDemo() {
        isDemo = false
        reload()
        isDemo = true
        contents.enabledProfiles = ["developer"]
        contents.disabledRules = []
        contents.problems = []
        contents.custom = [CleanupRule(
            id: "custom-demo", icon: "arrow.down.circle", risk: .review, selectedByDefault: false,
            locations: ["~/Downloads"], target: .contents, names: [], maxDepth: 4, includeHidden: false,
            extensions: [], exclude: [], olderThanDays: 60, title: localized("Vieux téléchargements"),
            detail: localized("Fichiers du dossier Téléchargements inchangés depuis 60 jours."), afterRemoval: nil
        )]
    }
}
