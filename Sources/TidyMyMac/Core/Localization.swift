import Foundation
import ObjectiveC
import SemanticSearch

/// Texte traduit dans la langue choisie dans les Réglages, même si elle a changé depuis le lancement.
func localized(_ value: String.LocalizationValue) -> String {
    String(localized: value, bundle: AppLocalization.bundle ?? .main)
}

/// Langue de l'interface choisie dans les Réglages.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, fr, en, es, de

    var id: String { rawValue }

    /// Chaque langue est écrite dans sa propre langue, comme dans les réglages de macOS.
    var title: String {
        switch self {
        case .system: return localized("Langue du système")
        case .fr: return "Français"
        case .en: return "English"
        case .es: return "Español"
        case .de: return "Deutsch"
        }
    }

    /// Le choix enregistré pour l'app seule (clé `AppleLanguages` de son domaine), hors langue générale de macOS.
    static var saved: AppLanguage {
        guard let identifier = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: identifier)?["AppleLanguages"] as? [String],
              let first = languages.first else { return .system }
        return AppLanguage(rawValue: String(first.prefix(2))) ?? .system
    }

    /// Enregistré dans `AppleLanguages` : macOS l'applique aussi aux lancements suivants.
    func save() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// Change la langue de l'interface sans relancer l'app.
///
/// macOS fixe la langue au lancement. Pour en changer en cours de route, les recherches de traduction de
/// `Bundle.main` sont redirigées vers le dossier `.lproj` choisi ; les vues observent ce modèle et se redessinent.
@MainActor
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()

    @Published private(set) var language: AppLanguage

    /// Langue des formats (tailles, dates relatives, durées), alignée sur celle de l'interface.
    nonisolated(unsafe) private(set) static var locale = Locale.current
    nonisolated(unsafe) fileprivate static var bundle: Bundle?
    private static var mainBundleRedirected = false

    private init() {
        language = AppLanguage.saved
    }

    func select(_ language: AppLanguage) {
        apply(language, persist: true)
    }

    /// `persist: false` change la langue pour cette session seulement (captures d'écran).
    func apply(_ language: AppLanguage, persist: Bool) {
        if persist { language.save() }
        if !Self.mainBundleRedirected {
            object_setClass(Bundle.main, RedirectedMainBundle.self)
            Self.mainBundleRedirected = true
        }
        let code = language == .system ? Self.systemLanguageCode(ignoringSaved: persist) : language.rawValue
        Self.bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
        SemanticSearchLocalization.bundle = Self.bundle ?? .main
        let region = Locale.current.region?.identifier
        Self.locale = Locale(identifier: region.map { "\(code)_\($0)" } ?? code)
        self.language = language
    }

    /// Langue que macOS choisirait d'après ses propres réglages.
    private static func systemLanguageCode(ignoringSaved: Bool) -> String {
        let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: preferred).first ?? "fr"
    }
}

/// Remplace la classe de `Bundle.main` pour servir les traductions de la langue choisie.
private final class RedirectedMainBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = AppLocalization.bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
